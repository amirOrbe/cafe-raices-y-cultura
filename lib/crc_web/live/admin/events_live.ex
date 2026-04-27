defmodule CRCWeb.Admin.EventsLive do
  @moduledoc "Events management from the administration panel."

  use CRCWeb, :live_view

  alias CRC.Cloudinary
  alias CRC.Events
  alias CRC.Events.Event
  alias CRC.Settings

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "admin:events")
      Phoenix.PubSub.subscribe(CRC.PubSub, "admin:event_types")
      Phoenix.PubSub.subscribe(CRC.PubSub, "admin:collaborators")
    end

    socket =
      socket
      |> assign(:page_title, "Eventos · Admin")
      |> assign(:events, Events.list_events())
      |> assign(:event_types, Events.list_active_event_types())
      |> assign(:all_collaborators, Events.list_active_collaborators())
      |> assign(:modal, nil)
      |> assign(:form, nil)
      |> assign(:collaborators_draft, [])
      |> assign(:available_collaborators, [])
      |> assign(:selected_collaborator_id, "")
      |> assign(:collaborator_role_input, "")
      |> assign(:timeline, nil)
      |> assign(:event_photos, [])
      |> allow_upload(:event_photo,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 5,
        max_file_size: 5_000_000,
        auto_upload: true
      )

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:event_changed, _event}, socket) do
    {:noreply, assign(socket, :events, Events.list_events())}
  end

  def handle_info({:event_type_changed, _event_type}, socket) do
    {:noreply, assign(socket, :event_types, Events.list_active_event_types())}
  end

  def handle_info({:collaborator_changed, _collaborator}, socket) do
    all_collaborators = Events.list_active_collaborators()

    socket =
      socket
      |> assign(:all_collaborators, all_collaborators)
      |> update_available_collaborators()

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("new_event", _params, socket) do
    changeset = Events.change_event(%Event{})

    socket =
      socket
      |> assign(:modal, :new)
      |> assign(:form, to_form(changeset))
      |> assign(:collaborators_draft, [])
      |> assign(:selected_collaborator_id, "")
      |> assign(:collaborator_role_input, "")
      |> assign(:timeline, nil)
      |> update_available_collaborators()

    {:noreply, socket}
  end

  def handle_event("edit_event", %{"id" => id}, socket) do
    event = Events.get_event!(String.to_integer(id))
    changeset = Events.change_event(event)

    draft =
      Enum.map(event.event_collaborators, fn ec ->
        %{
          collaborator_id: ec.collaborator_id,
          name: ec.collaborator.name,
          role: ec.role_in_event || ""
        }
      end)

    timeline =
      compute_timeline(
        Date.to_iso8601(event.event_date),
        format_time(event.start_time),
        format_time(event.end_time),
        event.id
      )

    socket =
      socket
      |> assign(:modal, {:edit, event})
      |> assign(:form, to_form(changeset))
      |> assign(:collaborators_draft, draft)
      |> assign(:selected_collaborator_id, "")
      |> assign(:collaborator_role_input, "")
      |> assign(:timeline, timeline)
      |> assign(:event_photos, Events.list_event_photos(event.id))
      |> update_available_collaborators()

    {:noreply, socket}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal, nil)
     |> assign(:form, nil)
     |> assign(:collaborators_draft, [])
     |> assign(:selected_collaborator_id, "")
     |> assign(:collaborator_role_input, "")
     |> assign(:timeline, nil)
     |> assign(:event_photos, [])}
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :event_photo, ref)}
  end

  def handle_event("delete_event_photo", %{"id" => id}, socket) do
    Events.delete_event_photo(String.to_integer(id))

    event_id =
      case socket.assigns.modal do
        {:edit, event} -> event.id
        _ -> nil
      end

    photos = if event_id, do: Events.list_event_photos(event_id), else: []
    {:noreply, assign(socket, :event_photos, photos)}
  end

  def handle_event("form_changed", %{"event" => params}, socket) do
    date_str = params["event_date"] || ""
    start_str = params["start_time"] || ""
    end_str = params["end_time"] || ""

    editing_event_id =
      case socket.assigns.modal do
        {:edit, ev} -> ev.id
        _ -> nil
      end

    timeline =
      with {:ok, new_date} <- Date.from_iso8601(date_str) do
        current_date = socket.assigns.timeline && socket.assigns.timeline.date

        if new_date == current_date do
          # Date unchanged — just update time positions, no DB call
          %{socket.assigns.timeline |
            new_start: parse_time_opt(start_str),
            new_end: parse_time_opt(end_str)
          }
        else
          compute_timeline(date_str, start_str, end_str, editing_event_id)
        end
      else
        _ -> nil
      end

    {:noreply, assign(socket, :timeline, timeline)}
  end

  # Ignore form_changed if it doesn't include the event key (e.g. collaborator selects)
  def handle_event("form_changed", _params, socket), do: {:noreply, socket}

  def handle_event("save_event", %{"event" => params}, socket) do
    collaborators_with_roles =
      Enum.map(socket.assigns.collaborators_draft, fn entry ->
        {entry.collaborator_id, entry.role}
      end)

    params = parse_tags(params)

    result =
      case socket.assigns.modal do
        :new -> Events.create_event(params, collaborators_with_roles)
        {:edit, event} -> Events.update_event(event, params, collaborators_with_roles)
      end

    case result do
      {:ok, _event} ->
        label = if socket.assigns.modal == :new, do: "creado", else: "actualizado"

        {:noreply,
         socket
         |> put_flash(:info, "Evento #{label} correctamente.")
         |> assign(:events, Events.list_events())
         |> assign(:modal, nil)
         |> assign(:form, nil)
         |> assign(:collaborators_draft, [])
         |> assign(:selected_collaborator_id, "")
         |> assign(:collaborator_role_input, "")
         |> assign(:timeline, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    event = Events.get_event!(String.to_integer(id))

    case Events.toggle_event_active(event) do
      {:ok, _} ->
        action = if event.active, do: "desactivado", else: "activado"

        {:noreply,
         socket
         |> put_flash(:info, "Evento #{action} correctamente.")
         |> assign(:events, Events.list_events())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo cambiar el estado del evento.")}
    end
  end

  def handle_event("add_collaborator_to_draft", _params, socket) do
    selected_id = socket.assigns.selected_collaborator_id
    role = socket.assigns.collaborator_role_input

    if selected_id == "" do
      {:noreply, socket}
    else
      collaborator_id = String.to_integer(selected_id)
      collaborator = Enum.find(socket.assigns.all_collaborators, &(&1.id == collaborator_id))

      already_in_draft =
        Enum.any?(socket.assigns.collaborators_draft, &(&1.collaborator_id == collaborator_id))

      if collaborator && !already_in_draft do
        new_entry = %{collaborator_id: collaborator_id, name: collaborator.name, role: role}
        new_draft = socket.assigns.collaborators_draft ++ [new_entry]

        socket =
          socket
          |> assign(:collaborators_draft, new_draft)
          |> assign(:selected_collaborator_id, "")
          |> assign(:collaborator_role_input, "")
          |> update_available_collaborators()

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    end
  end

  def handle_event("remove_collaborator_from_draft", %{"id" => id}, socket) do
    collaborator_id = String.to_integer(id)

    new_draft =
      Enum.reject(socket.assigns.collaborators_draft, &(&1.collaborator_id == collaborator_id))

    socket =
      socket
      |> assign(:collaborators_draft, new_draft)
      |> update_available_collaborators()

    {:noreply, socket}
  end

  def handle_event("update_collaborator_selection", %{"collab_select" => value}, socket) do
    {:noreply, assign(socket, :selected_collaborator_id, value)}
  end

  def handle_event("update_collaborator_role", %{"collab_role" => value}, socket) do
    {:noreply, assign(socket, :collaborator_role_input, value)}
  end

  # Manual fallback: fires when the admin clicks "Subir fotos".
  # Handles entries that weren't auto-consumed by handle_progress.
  def handle_event("upload_event_photos", _params, socket) do
    require Logger
    entries = socket.assigns.uploads.event_photo.entries
    Logger.info("[EventPhoto] upload_event_photos triggered, entries: #{length(entries)}")

    event_id =
      case socket.assigns.modal do
        {:edit, event} -> event.id
        _ -> nil
      end

    if event_id && entries != [] do
      consume_uploaded_entries(socket, :event_photo, fn %{path: path}, e ->
        Logger.info("[EventPhoto] Manual upload: #{e.client_name}")

        case Cloudinary.upload(path, folder: "events", content_type: e.client_type) do
          {:ok, url} ->
            Events.add_event_photo(event_id, url)
            {:ok, url}

          {:error, reason} ->
            Logger.error("[EventPhoto] #{e.client_name} falló: #{inspect(reason)}")
            {:ok, nil}
        end
      end)

      {:noreply, assign(socket, :event_photos, Events.list_event_photos(event_id))}
    else
      {:noreply, socket}
    end
  end

  # Automatically fires when each file finishes transferring to the server (auto_upload: true).
  def handle_progress(:event_photo, entry, socket) do
    require Logger
    Logger.info("[EventPhoto] handle_progress: #{entry.client_name}, done=#{entry.done?}, progress=#{entry.progress}")

    if entry.done? do
      event_id =
        case socket.assigns.modal do
          {:edit, event} -> event.id
          _ -> nil
        end

      if event_id do
        consume_uploaded_entries(socket, :event_photo, fn %{path: path}, e ->
          Logger.info("[EventPhoto] Enviando a Cloudinary: #{e.client_name}")

          case Cloudinary.upload(path, folder: "events", content_type: e.client_type) do
            {:ok, url} ->
              Events.add_event_photo(event_id, url)
              {:ok, url}

            {:error, reason} ->
              Logger.error("[EventPhoto] #{e.client_name} falló: #{inspect(reason)}")
              {:ok, nil}
          end
        end)

        {:noreply, assign(socket, :event_photos, Events.list_event_photos(event_id))}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Eventos</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            {length(@events)} {if length(@events) == 1, do: "evento", else: "eventos"} registrados
          </p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="new_event">
          <.icon name="hero-plus" class="size-4" />
          Nuevo evento
        </button>
      </div>

      <%!-- ── Mobile card list (< md) ──────────────────────────────────────── --%>
      <div class="md:hidden flex flex-col gap-2">
        <%= if @events == [] do %>
          <div class="text-center py-12 text-base-content/40 text-sm bg-base-100 rounded-2xl border border-base-300">
            No hay eventos registrados. Crea el primero.
          </div>
        <% end %>
        <%= for event <- @events do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-3 flex items-start gap-3">
            <%!-- Date block --%>
            <div class="shrink-0 w-11 flex flex-col items-center justify-center bg-primary/10 rounded-xl py-1.5 px-1 text-center">
              <span class="text-xs font-bold text-primary leading-none">
                {Calendar.strftime(event.event_date, "%d")}
              </span>
              <span class="text-[10px] text-primary/70 uppercase font-medium leading-none mt-0.5">
                {Calendar.strftime(event.event_date, "%b")}
              </span>
            </div>
            <%!-- Info --%>
            <div class="flex-1 min-w-0">
              <div class="flex items-start justify-between gap-2">
                <p class="font-semibold text-sm text-base-content line-clamp-2 leading-snug">{event.title}</p>
                <.event_status_badge event={event} />
              </div>
              <div class="flex items-center gap-1.5 mt-1 flex-wrap">
                <%= if event.event_type do %>
                  <span class="badge badge-xs badge-ghost">{event.event_type.name}</span>
                <% end %>
                <span class="text-xs text-base-content/50">
                  {format_time(event.start_time)} – {format_time(event.end_time)}
                </span>
              </div>
              <%= if event.event_collaborators != [] do %>
                <div class="flex flex-wrap gap-1 mt-1.5">
                  <%= for ec <- event.event_collaborators do %>
                    <span class="badge badge-xs badge-ghost">{ec.collaborator.name}</span>
                  <% end %>
                </div>
              <% end %>
            </div>
            <%!-- Actions --%>
            <div class="flex flex-col items-center gap-1 shrink-0">
              <button
                class="btn btn-ghost btn-xs btn-circle"
                phx-click="edit_event"
                phx-value-id={event.id}
                title="Editar"
              >
                <.icon name="hero-pencil" class="size-4" />
              </button>
              <button
                class={["btn btn-ghost btn-xs btn-circle", if(event.active, do: "text-error", else: "text-success")]}
                phx-click="toggle_active"
                phx-value-id={event.id}
                title={if event.active, do: "Desactivar", else: "Activar"}
              >
                <.icon
                  name={if event.active, do: "hero-no-symbol", else: "hero-check-circle"}
                  class="size-4"
                />
              </button>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- ── Desktop table (md+) ────────────────────────────────────────────── --%>
      <div class="hidden md:block bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
          <table class="table table-zebra table-fixed w-full">
            <thead>
              <tr class="bg-base-200 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                <th class="w-[28%]">Título</th>
                <th class="w-[13%]">Tipo</th>
                <th class="w-[11%]">Fecha</th>
                <th class="w-[13%]">Horario</th>
                <th class="w-[10%]">Estado</th>
                <th class="w-[18%]">Colaboradores</th>
                <th class="w-[7%] text-right">Acciones</th>
              </tr>
            </thead>
            <tbody>
              <%= for event <- @events do %>
                <tr class="hover:bg-base-200/50 transition-colors">
                  <td class="max-w-0 font-medium text-sm text-base-content">
                    <span class="truncate block">{event.title}</span>
                  </td>
                  <td class="text-sm text-base-content/70 truncate">
                    {if event.event_type, do: event.event_type.name, else: "—"}
                  </td>
                  <td class="text-sm text-base-content/70 whitespace-nowrap">
                    {Calendar.strftime(event.event_date, "%d/%m/%Y")}
                  </td>
                  <td class="text-sm text-base-content/70 whitespace-nowrap">
                    {format_time(event.start_time)} – {format_time(event.end_time)}
                  </td>
                  <td>
                    <.event_status_badge event={event} />
                  </td>
                  <td>
                    <div class="flex flex-wrap gap-1">
                      <%= if event.event_collaborators == [] do %>
                        <span class="text-xs text-base-content/40">—</span>
                      <% else %>
                        <%= for ec <- event.event_collaborators do %>
                          <span class="badge badge-xs badge-ghost">{ec.collaborator.name}</span>
                        <% end %>
                      <% end %>
                    </div>
                  </td>
                  <td>
                    <div class="flex items-center justify-end gap-1">
                      <button
                        class="btn btn-ghost btn-xs btn-circle"
                        phx-click="edit_event"
                        phx-value-id={event.id}
                        title="Editar"
                      >
                        <.icon name="hero-pencil" class="size-4" />
                      </button>
                      <button
                        class={["btn btn-ghost btn-xs btn-circle", if(event.active, do: "text-error", else: "text-success")]}
                        phx-click="toggle_active"
                        phx-value-id={event.id}
                        title={if event.active, do: "Desactivar", else: "Activar"}
                      >
                        <.icon
                          name={if event.active, do: "hero-no-symbol", else: "hero-check-circle"}
                          class="size-4"
                        />
                      </button>
                    </div>
                  </td>
                </tr>
              <% end %>
              <%= if @events == [] do %>
                <tr>
                  <td colspan="7" class="text-center py-12 text-base-content/40 text-sm">
                    No hay eventos registrados. Crea el primero.
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <%!-- Modal: new / edit event --%>
    <%= if @modal != nil do %>
      <.event_modal
        form={@form}
        modal={@modal}
        event_types={@event_types}
        collaborators_draft={@collaborators_draft}
        available_collaborators={@available_collaborators}
        selected_collaborator_id={@selected_collaborator_id}
        collaborator_role_input={@collaborator_role_input}
        timeline={@timeline}
        event_photos={@event_photos}
        uploads={@uploads}
      />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Event status badge component
  # ---------------------------------------------------------------------------

  attr :event, :map, required: true

  defp event_status_badge(assigns) do
    ~H"""
    <%= if !@event.active do %>
      <span class="badge badge-sm badge-error">Inactivo</span>
    <% else %>
      <% status = compute_event_status(@event) %>
      <%= case status do %>
        <% :live -> %>
          <span class="badge badge-sm badge-success">En curso</span>
        <% :upcoming -> %>
          <span class="badge badge-sm badge-accent">Próximo</span>
        <% :future -> %>
          <span class="badge badge-sm badge-ghost">Futuro</span>
        <% :past -> %>
          <span class="badge badge-sm">Pasado</span>
      <% end %>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Event modal
  # ---------------------------------------------------------------------------

  attr :form, :map, required: true
  attr :modal, :any, required: true
  attr :event_types, :list, required: true
  attr :collaborators_draft, :list, required: true
  attr :available_collaborators, :list, required: true
  attr :selected_collaborator_id, :string, required: true
  attr :collaborator_role_input, :string, required: true
  attr :timeline, :any, default: nil
  attr :event_photos, :list, default: []
  attr :uploads, :map, required: true

  defp event_modal(assigns) do
    title = if assigns.modal == :new, do: "Nuevo evento", else: "Editar evento"
    assigns = assign(assigns, :title, title)

    ~H"""
    <div
      id="event-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_modal"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_modal"></div>

      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-2xl overflow-y-auto max-h-[90vh]">
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between sticky top-0 bg-base-100 z-10">
          <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="px-6 py-5">
          <.form
            id="event-form"
            for={@form}
            phx-submit="save_event"
            phx-change="form_changed"
            class="space-y-3"
          >
            <%!-- Title (full width) --%>
            <.input
              field={@form[:title]}
              type="text"
              label="Título del evento"
              placeholder="Ej. Noche de Jazz, Taller de Barismo, Feria del Libro"
            />

            <%!-- Event type + Date (2 cols) --%>
            <div class="grid grid-cols-2 gap-3">
              <.input
                field={@form[:event_type_id]}
                type="select"
                label="Tipo de evento"
                options={[{"— Sin tipo —", ""} | Enum.map(@event_types, &{&1.name, &1.id})]}
              />
              <.input
                field={@form[:event_date]}
                type="date"
                label="Fecha"
              />
            </div>

            <%!-- Start time + End time (2 cols) --%>
            <div class="grid grid-cols-2 gap-3">
              <.input
                field={@form[:start_time]}
                type="time"
                label="Hora de inicio"
              />
              <.input
                field={@form[:end_time]}
                type="time"
                label="Hora de fin"
              />
            </div>

            <%!-- Day timeline --%>
            <.day_timeline timeline={@timeline} />

            <%!-- Tags --%>
            <.input
              field={@form[:tags]}
              type="text"
              label="Etiquetas (opcional)"
              placeholder="separadas por coma, ej: Música, Noche"
              value={tags_to_string(@form[:tags].value)}
            />

            <%!-- Description --%>
            <.input
              field={@form[:description]}
              type="textarea"
              label="Descripción (opcional)"
              placeholder="Describe el evento, qué pasará, quién es bienvenido..."
            />

            <%!-- Collaborators section --%>
            <div class="pt-2">
              <div class="divider text-sm font-semibold text-base-content/60">Colaboradores</div>

              <%!-- Draft list --%>
              <%= if @collaborators_draft != [] do %>
                <div class="space-y-2 mb-4">
                  <%= for entry <- @collaborators_draft do %>
                    <div class="flex items-center gap-2 bg-base-200 rounded-lg px-3 py-2">
                      <span class="flex-1 text-sm font-medium text-base-content">{entry.name}</span>
                      <%= if entry.role != "" do %>
                        <span class="text-xs text-base-content/60">{entry.role}</span>
                      <% end %>
                      <button
                        type="button"
                        class="btn btn-ghost btn-xs btn-circle text-error"
                        phx-click="remove_collaborator_from_draft"
                        phx-value-id={entry.collaborator_id}
                      >
                        <.icon name="hero-x-mark" class="size-3.5" />
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%!-- Add collaborator row --%>
              <div class="flex gap-2 items-end">
                <div class="flex-1">
                  <label class="label text-xs font-medium text-base-content/70 pb-1">
                    Colaborador
                  </label>
                  <select
                    class="select select-bordered select-sm w-full"
                    phx-change="update_collaborator_selection"
                    name="collab_select"
                    value={@selected_collaborator_id}
                  >
                    <option value="">— Selecciona —</option>
                    <%= for c <- @available_collaborators do %>
                      <option value={c.id} selected={@selected_collaborator_id == to_string(c.id)}>
                        {c.name}
                      </option>
                    <% end %>
                  </select>
                </div>
                <div class="flex-1">
                  <label class="label text-xs font-medium text-base-content/70 pb-1">
                    Rol (opcional)
                  </label>
                  <input
                    type="text"
                    class="input input-bordered input-sm w-full"
                    placeholder="Ej. Guitarrista, DJ, Ponente"
                    phx-change="update_collaborator_role"
                    name="collab_role"
                    value={@collaborator_role_input}
                  />
                </div>
                <button
                  type="button"
                  class="btn btn-sm btn-outline"
                  phx-click="add_collaborator_to_draft"
                  disabled={@selected_collaborator_id == ""}
                >
                  Agregar
                </button>
              </div>
            </div>

            <div class="flex justify-end gap-3 pt-4">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
              <button type="submit" class="btn btn-primary">
                {if @modal == :new, do: "Crear evento", else: "Guardar cambios"}
              </button>
            </div>
          </.form>

          <%!-- ── Galería de fotos (solo en modo edición) ──────────────────────── --%>
          <%= if @modal != :new do %>
            <div class="mt-5 pt-4 border-t border-base-300">
              <div class="flex items-center gap-2 mb-3">
                <.icon name="hero-photo" class="size-4 text-base-content/60" />
                <h3 class="text-sm font-semibold text-base-content">Fotos del evento</h3>
                <span class="badge badge-xs badge-ghost">{length(@event_photos)}</span>
              </div>

              <%!-- Grid de fotos existentes --%>
              <%= if @event_photos != [] do %>
                <div class="grid grid-cols-3 gap-2 mb-4">
                  <%= for photo <- @event_photos do %>
                    <div class="relative group aspect-square overflow-hidden rounded-xl border border-base-300">
                      <img
                        src={photo.image_url}
                        alt={photo.caption || "Foto del evento"}
                        class="w-full h-full object-cover"
                        loading="lazy"
                      />
                      <div class="absolute inset-0 bg-black/0 group-hover:bg-black/50 transition-colors flex items-center justify-center">
                        <button
                          type="button"
                          class="opacity-0 group-hover:opacity-100 transition-opacity btn btn-circle btn-sm btn-error"
                          phx-click="delete_event_photo"
                          phx-value-id={photo.id}
                          data-confirm="¿Eliminar esta foto del evento?"
                        >
                          <.icon name="hero-trash" class="size-4" />
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%!-- Subir nuevas fotos --%>
              <form phx-submit="upload_event_photos" phx-change="validate_upload" class="space-y-3">
                <%!-- Drop zone — click abre el selector de archivos --%>
                <label
                  for={@uploads.event_photo.ref}
                  class="flex flex-col items-center justify-center gap-2 w-full py-6 px-4 rounded-2xl border-2 border-dashed border-base-300 hover:border-primary/40 hover:bg-primary/5 cursor-pointer transition-all duration-200"
                >
                  <div class="flex items-center justify-center w-10 h-10 rounded-full bg-primary/10">
                    <.icon name="hero-arrow-up-tray" class="size-5 text-primary" />
                  </div>
                  <div class="text-center">
                    <p class="text-sm font-medium text-base-content">
                      Selecciona o arrastra fotos aquí
                    </p>
                    <p class="text-xs text-base-content/40 mt-0.5">
                      JPG, PNG o WebP · Máx. 5 MB · Hasta 5 a la vez
                    </p>
                  </div>
                  <.live_file_input upload={@uploads.event_photo} class="sr-only" />
                </label>

                <%!-- Previews + progreso — solo cuando hay archivos seleccionados --%>
                <%= if @uploads.event_photo.entries != [] do %>
                  <div class="space-y-2">
                    <%= for entry <- @uploads.event_photo.entries do %>
                      <div class="flex items-center gap-3 p-2.5 bg-base-200 rounded-xl">
                        <.live_img_preview entry={entry} class="w-10 h-10 object-cover rounded-lg shrink-0" />
                        <div class="flex-1 min-w-0">
                          <p class="text-xs font-medium text-base-content truncate">{entry.client_name}</p>
                          <div class="w-full bg-base-300 rounded-full h-1.5 mt-1.5">
                            <div
                              class="bg-primary h-1.5 rounded-full transition-all duration-300"
                              style={"width: #{entry.progress}%"}
                            />
                          </div>
                        </div>
                        <button
                          type="button"
                          class="btn btn-ghost btn-xs btn-circle text-error shrink-0"
                          phx-click="cancel_upload"
                          phx-value-ref={entry.ref}
                        >
                          <.icon name="hero-x-mark" class="size-3.5" />
                        </button>
                      </div>
                    <% end %>
                  </div>

                  <button type="submit" class="btn btn-primary btn-sm w-full gap-2">
                    <.icon name="hero-arrow-up-tray" class="size-4" />
                    Subir {length(@uploads.event_photo.entries)}
                    {if length(@uploads.event_photo.entries) == 1, do: "foto", else: "fotos"}
                  </button>
                <% end %>
              </form>
            </div>
          <% end %>
          <%!-- ── Fin galería ─────────────────────────────────────────────────── --%>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Day timeline component
  # ---------------------------------------------------------------------------

  attr :timeline, :any, default: nil

  # No date selected yet → render nothing
  defp day_timeline(%{timeline: nil} = assigns), do: ~H""

  # Date selected but no café hours configured for that day
  defp day_timeline(%{timeline: %{cafe_hours: nil, date: date}} = assigns) do
    day_name =
      case Date.day_of_week(date) do
        1 -> "lunes"
        2 -> "martes"
        3 -> "miércoles"
        4 -> "jueves"
        5 -> "viernes"
        6 -> "sábado"
        7 -> "domingo"
      end

    assigns = assign(assigns, :day_name, day_name)

    ~H"""
    <div class="flex items-center gap-2 px-3 py-2.5 rounded-lg bg-base-200 border border-base-300 text-sm text-base-content/60">
      <.icon name="hero-clock" class="size-4 shrink-0 text-base-content/40" />
      <span>El café no tiene horario configurado para los <strong>{@day_name}</strong>.</span>
      <a
        href="/admin/configuracion"
        target="_blank"
        class="link link-primary text-xs ml-auto shrink-0 whitespace-nowrap"
      >
        Configurar →
      </a>
    </div>
    """
  end

  # Full timeline rendering
  defp day_timeline(assigns) do
    tl = assigns.timeline
    {opening, closing} = tl.cafe_hours

    event_blocks =
      Enum.map(tl.other_events, fn e ->
        %{
          left: time_to_pct(e.start_time, opening, closing),
          width: time_to_pct_range(e.start_time, e.end_time, opening, closing),
          title: e.title
        }
      end)

    {new_block, has_conflict, outside_hours} =
      case {tl.new_start, tl.new_end} do
        {nil, _} ->
          {nil, false, false}

        {_, nil} ->
          {nil, false, false}

        {s, e} ->
          if Time.compare(e, s) != :gt do
            {nil, false, false}
          else
            conflict = has_conflict?(s, e, tl.other_events)
            outside = outside_hours?(s, e, opening, closing)

            block = %{
              left: time_to_pct(s, opening, closing),
              width: time_to_pct_range(s, e, opening, closing)
            }

            {block, conflict, outside}
          end
      end

    ticks = hour_ticks(opening, closing)

    assigns =
      assigns
      |> assign(:opening, opening)
      |> assign(:closing, closing)
      |> assign(:event_blocks, event_blocks)
      |> assign(:new_block, new_block)
      |> assign(:ticks, ticks)
      |> assign(:has_conflict, has_conflict)
      |> assign(:outside_hours, outside_hours)

    ~H"""
    <div class="space-y-1 pb-1">
      <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wide">
        Disponibilidad del día
      </p>

      <%!-- Timeline bar --%>
      <div class="relative h-9 bg-base-200 rounded-lg overflow-hidden border border-base-300">

        <%!-- Existing event blocks --%>
        <%= for block <- @event_blocks do %>
          <div
            class="absolute inset-y-0 bg-error/25 border-x border-error/50 flex items-center overflow-hidden"
            style={"left: #{block.left}%; width: #{block.width}%;"}
            title={block.title}
          >
            <span class="text-xs text-error/80 px-1.5 truncate leading-none font-medium">
              {block.title}
            </span>
          </div>
        <% end %>

        <%!-- New event block --%>
        <%= if @new_block do %>
          <div
            class={"absolute inset-y-0 flex items-center overflow-hidden border-x
              #{if @has_conflict, do: "bg-warning/30 border-warning", else: "bg-primary/25 border-primary/60"}"}
            style={"left: #{@new_block.left}%; width: #{@new_block.width}%;"}
          >
            <span class={"text-xs px-1.5 truncate leading-none font-semibold
              #{if @has_conflict, do: "text-warning-content", else: "text-primary"}"}>
              Este evento
            </span>
          </div>
        <% end %>

      </div>

      <%!-- Hour tick labels --%>
      <div class="relative h-4">
        <%= for {label, pct} <- @ticks do %>
          <span
            class="absolute text-xs text-base-content/35 -translate-x-1/2 leading-none"
            style={"left: #{pct}%;"}
          >
            {label}
          </span>
        <% end %>
      </div>

      <%!-- Warnings --%>
      <%= if @has_conflict do %>
        <div class="flex items-center gap-1.5 text-xs text-warning font-medium">
          <.icon name="hero-exclamation-triangle" class="size-3.5 shrink-0" />
          Este horario se superpone con otro evento del mismo día.
        </div>
      <% end %>

      <%= if @outside_hours do %>
        <div class="flex items-center gap-1.5 text-xs text-base-content/50">
          <.icon name="hero-information-circle" class="size-3.5 shrink-0" />
          El evento se extiende fuera del horario de apertura
          ({format_time(@opening)} – {format_time(@closing)}).
        </div>
      <% end %>

      <%!-- Legend + time range --%>
      <div class="flex items-center gap-3 text-xs text-base-content/40 pt-0.5 flex-wrap">
        <%= if @event_blocks != [] do %>
          <div class="flex items-center gap-1">
            <div class="w-3 h-3 rounded-sm bg-error/25 border border-error/50 shrink-0"></div>
            Otros eventos
          </div>
        <% end %>
        <div class="flex items-center gap-1">
          <div class="w-3 h-3 rounded-sm bg-primary/25 border border-primary/60 shrink-0"></div>
          Este evento
        </div>
        <span class="ml-auto whitespace-nowrap">
          Apertura {format_time(@opening)} – Cierre {format_time(@closing)}
        </span>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp update_available_collaborators(socket) do
    draft_ids = Enum.map(socket.assigns.collaborators_draft, & &1.collaborator_id)
    available = Enum.reject(socket.assigns.all_collaborators, fn c -> c.id in draft_ids end)
    assign(socket, :available_collaborators, available)
  end

  defp compute_event_status(event) do
    now = cdmx_now()
    today = NaiveDateTime.to_date(now)
    cdmx_time = NaiveDateTime.to_time(now)

    cond do
      event.event_date == today and
          Time.compare(event.start_time, cdmx_time) != :gt and
          Time.compare(event.end_time, cdmx_time) == :gt ->
        :live

      event.event_date == today and Time.compare(event.start_time, cdmx_time) == :gt ->
        :upcoming

      Date.compare(event.event_date, today) == :gt ->
        :future

      true ->
        :past
    end
  end

  # Builds the timeline map for a given date/start/end string combination.
  # Returns nil when the date string is absent or invalid.
  defp compute_timeline(date_str, start_str, end_str, editing_event_id) do
    case Date.from_iso8601(date_str || "") do
      {:ok, date} ->
        cafe_hours = Settings.hours_for_date(date)
        all_events = Events.list_events_for_date(date)

        other_events =
          case editing_event_id do
            nil -> all_events
            id -> Enum.reject(all_events, &(&1.id == id))
          end

        %{
          date: date,
          cafe_hours: cafe_hours,
          other_events: other_events,
          new_start: parse_time_opt(start_str),
          new_end: parse_time_opt(end_str)
        }

      _ ->
        nil
    end
  end

  # Parses "HH:MM" or "HH:MM:SS" into a Time struct; returns nil on failure.
  defp parse_time_opt(nil), do: nil
  defp parse_time_opt(""), do: nil

  defp parse_time_opt(str) do
    case Time.from_iso8601(str) do
      {:ok, t} -> t
      _ ->
        case Time.from_iso8601(str <> ":00") do
          {:ok, t} -> t
          _ -> nil
        end
    end
  end

  # Returns the seconds-since-midnight value of a Time struct.
  defp time_secs(%Time{hour: h, minute: m, second: s}), do: h * 3600 + m * 60 + s

  # Returns the percentage offset of `t` within [opening, closing], clamped to [0, 100].
  defp time_to_pct(t, opening, closing) do
    total = time_secs(closing) - time_secs(opening)
    if total <= 0 do
      0.0
    else
      raw = (time_secs(t) - time_secs(opening)) / total * 100
      max(0.0, min(100.0, raw))
    end
  end

  # Returns the width percentage of the [start_t, end_t] block clipped to [opening, closing].
  # Minimum 1% so very short events are still visible.
  defp time_to_pct_range(start_t, end_t, opening, closing) do
    total = time_secs(closing) - time_secs(opening)

    if total <= 0 do
      0.0
    else
      s = max(time_secs(opening), time_secs(start_t))
      e = min(time_secs(closing), time_secs(end_t))
      max(1.0, (e - s) / total * 100)
    end
  end

  # Returns true if the [new_start, new_end] window overlaps any event in `events`.
  defp has_conflict?(new_start, new_end, events) do
    Enum.any?(events, fn e ->
      Time.compare(new_start, e.end_time) == :lt and
        Time.compare(new_end, e.start_time) == :gt
    end)
  end

  # Returns true if the new event extends beyond the café's opening window.
  defp outside_hours?(new_start, new_end, opening, closing) do
    Time.compare(new_start, opening) == :lt or Time.compare(new_end, closing) == :gt
  end

  # Returns [{label, pct}] for every even hour within [opening, closing].
  defp hour_ticks(opening, closing) do
    total = time_secs(closing) - time_secs(opening)

    if total <= 0 do
      []
    else
      open_h = opening.hour
      # Include the closing hour only if it falls on the hour exactly
      close_h = closing.hour + if(closing.minute > 0 or closing.second > 0, do: 1, else: 0)

      open_h..close_h
      |> Enum.filter(fn h -> rem(h, 2) == 0 end)
      |> Enum.map(fn h ->
        t = Time.new!(h, 0, 0)
        pct = (time_secs(t) - time_secs(opening)) / total * 100
        {format_time(t), pct}
      end)
      |> Enum.filter(fn {_, pct} -> pct >= 0.0 and pct <= 100.0 end)
    end
  end

  defp cdmx_now do
    DateTime.utc_now()
    |> DateTime.add(-6 * 3600, :second)
    |> DateTime.to_naive()
  end

  defp format_time(nil), do: "—"
  defp format_time(%Time{} = t), do: Calendar.strftime(t, "%H:%M")

  defp tags_to_string(nil), do: ""
  defp tags_to_string([]), do: ""
  defp tags_to_string(tags) when is_list(tags), do: Enum.join(tags, ", ")
  defp tags_to_string(val), do: to_string(val)

  defp parse_tags(%{"tags" => tags_str} = params) when is_binary(tags_str) do
    tags =
      tags_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Map.put(params, "tags", tags)
  end

  defp parse_tags(params), do: params
end
