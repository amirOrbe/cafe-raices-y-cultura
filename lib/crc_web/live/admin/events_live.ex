defmodule CRCWeb.Admin.EventsLive do
  @moduledoc "Events management from the administration panel."

  use CRCWeb, :live_view

  alias CRC.Events
  alias CRC.Events.Event

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

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:event_changed, _event}, socket) do
    {:noreply,
     socket
     |> assign(:events, Events.list_events())}
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

    socket =
      socket
      |> assign(:modal, {:edit, event})
      |> assign(:form, to_form(changeset))
      |> assign(:collaborators_draft, draft)
      |> assign(:selected_collaborator_id, "")
      |> assign(:collaborator_role_input, "")
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
     |> assign(:collaborator_role_input, "")}
  end

  def handle_event("save_event", %{"event" => params}, socket) do
    collaborators_with_roles =
      Enum.map(socket.assigns.collaborators_draft, fn entry ->
        {entry.collaborator_id, entry.role}
      end)

    # Parse tags from comma-separated string to list
    params = parse_tags(params)

    result =
      case socket.assigns.modal do
        :new ->
          Events.create_event(params, collaborators_with_roles)

        {:edit, event} ->
          Events.update_event(event, params, collaborators_with_roles)
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
         |> assign(:collaborator_role_input, "")}

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

  def handle_event("update_collaborator_selection", %{"value" => value}, socket) do
    {:noreply, assign(socket, :selected_collaborator_id, value)}
  end

  def handle_event("update_collaborator_role", %{"value" => value}, socket) do
    {:noreply, assign(socket, :collaborator_role_input, value)}
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

      <%!-- Table --%>
      <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
          <table class="table table-zebra w-full">
            <thead>
              <tr class="bg-base-200 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                <th>Título</th>
                <th>Tipo</th>
                <th>Fecha</th>
                <th>Horario</th>
                <th>Estado</th>
                <th>Colaboradores</th>
                <th class="text-right">Acciones</th>
              </tr>
            </thead>
            <tbody>
              <%= for event <- @events do %>
                <tr class="hover:bg-base-200/50 transition-colors">
                  <td class="font-medium text-sm text-base-content max-w-xs">
                    <span class="line-clamp-2">{event.title}</span>
                  </td>
                  <td class="text-sm text-base-content/70">
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
                        class="btn btn-ghost btn-sm"
                        phx-click="edit_event"
                        phx-value-id={event.id}
                        title="Editar"
                      >
                        <.icon name="hero-pencil" class="size-4" />
                      </button>
                      <button
                        class={["btn btn-ghost btn-sm", if(event.active, do: "text-error", else: "text-success")]}
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
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between sticky top-0 bg-base-100">
          <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="px-6 py-5">
          <.form id="event-form" for={@form} phx-submit="save_event" class="space-y-3">
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
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp update_available_collaborators(socket) do
    draft_ids = Enum.map(socket.assigns.collaborators_draft, & &1.collaborator_id)

    available =
      Enum.reject(socket.assigns.all_collaborators, fn c -> c.id in draft_ids end)

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
