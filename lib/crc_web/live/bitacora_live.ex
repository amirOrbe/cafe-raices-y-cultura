defmodule CRCWeb.BitacoraLive do
  @moduledoc """
  Bitácora de turno — digital shift handoff board.

  Any authenticated user can read, create and resolve notes.
  Admin users can additionally delete notes.
  Notes broadcast in real time via PubSub so every connected device
  sees new entries and resolutions immediately.
  """

  use CRCWeb, :live_view

  import CRCWeb.Layouts, only: [flash_group: 1]

  alias CRC.ShiftNotes
  alias CRCWeb.Components.SiteComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: ShiftNotes.subscribe()

    socket =
      socket
      |> assign(:page_title, "Bitácora de Turno")
      |> assign(:active_notes, ShiftNotes.list_active_notes())
      |> assign(:resolved_notes, ShiftNotes.list_recent_resolved_notes(3))
      |> assign(:show_resolved, false)
      |> assign(:new_category, "general")
      |> assign(:nav_open, false)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:note_created, note}, socket) do
    {:noreply, update(socket, :active_notes, fn notes -> [note | notes] end)}
  end

  def handle_info({:note_resolved, note}, socket) do
    socket =
      socket
      |> update(:active_notes, fn notes -> Enum.reject(notes, &(&1.id == note.id)) end)
      |> update(:resolved_notes, fn notes -> [note | notes] end)

    {:noreply, socket}
  end

  def handle_info({:note_deleted, note_id}, socket) do
    socket =
      socket
      |> update(:active_notes, fn notes -> Enum.reject(notes, &(&1.id == note_id)) end)
      |> update(:resolved_notes, fn notes -> Enum.reject(notes, &(&1.id == note_id)) end)

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_nav", _params, socket) do
    {:noreply, update(socket, :nav_open, &(!&1))}
  end

  def handle_event("close_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, false)}
  end

  def handle_event("set_category", %{"category" => cat}, socket) do
    {:noreply, assign(socket, :new_category, cat)}
  end

  def handle_event("create_note", %{"note" => %{"content" => content}}, socket) do
    content = String.trim(content)

    if content == "" do
      {:noreply, put_flash(socket, :error, "Escribe algo antes de publicar.")}
    else
      case ShiftNotes.create_note(
             %{"content" => content, "category" => socket.assigns.new_category},
             socket.assigns.current_user.id
           ) do
        {:ok, _} ->
          {:noreply, assign(socket, :new_category, "general")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "No se pudo guardar la nota.")}
      end
    end
  end

  def handle_event("resolve_note", %{"id" => id_str}, socket) do
    ShiftNotes.resolve_note(String.to_integer(id_str), socket.assigns.current_user.id)
    {:noreply, socket}
  end

  def handle_event("delete_note", %{"id" => id_str}, socket) do
    if socket.assigns.current_user.role == "admin" do
      ShiftNotes.delete_note(String.to_integer(id_str))
    end

    {:noreply, socket}
  end

  def handle_event("toggle_resolved", _params, socket) do
    {:noreply, update(socket, :show_resolved, &(!&1))}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <SiteComponents.site_navbar
      nav_open={@nav_open}
      current_page={:bitacora}
      current_user={@current_user}
    />

    <div class="min-h-screen bg-base-200 pt-20 pb-12">
      <div class="max-w-2xl mx-auto px-4 space-y-6">
        <%!-- Header --%>
        <div>
          <div class="flex items-center gap-2 mb-1">
            <.icon name="hero-clipboard-document-check" class="size-6 text-primary" />
            <h1 class="text-2xl font-bold text-base-content">Bitácora de Turno</h1>
          </div>
          <p class="text-sm text-base-content/50">
            Deja notas para el siguiente turno: alertas de stock, preparaciones pendientes, avisos de equipo.
            Las notas permanecen visibles hasta que alguien las resuelva.
          </p>
        </div>

        <%!-- New note form --%>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5 space-y-4">
          <p class="text-sm font-semibold text-base-content">Nueva nota</p>

          <%!-- Category selector --%>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
            <%= for {label, value} <- ShiftNotes.categories() do %>
              <button
                type="button"
                class={[
                  "btn btn-sm text-xs",
                  if(@new_category == value,
                    do: "btn-primary",
                    else: "btn-ghost border border-base-300"
                  )
                ]}
                phx-click="set_category"
                phx-value-category={value}
              >
                {label}
              </button>
            <% end %>
          </div>

          <%!-- Content + submit --%>
          <form phx-submit="create_note" class="space-y-3">
            <textarea
              name="note[content]"
              class="textarea textarea-bordered w-full text-sm"
              rows="3"
              placeholder={category_placeholder(@new_category)}
              required
            ></textarea>
            <button type="submit" class="btn btn-primary w-full sm:w-auto">
              <.icon name="hero-paper-airplane" class="size-4" /> Publicar nota
            </button>
          </form>
        </div>

        <%!-- Active notes --%>
        <div class="space-y-3">
          <h2 class="text-xs font-semibold text-base-content/50 uppercase tracking-wider flex items-center gap-2">
            Notas activas
            <%= if @active_notes != [] do %>
              <span class="badge badge-primary badge-sm">{length(@active_notes)}</span>
            <% end %>
          </h2>

          <%= if @active_notes == [] do %>
            <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-14 text-center">
              <.icon
                name="hero-clipboard-document-check"
                class="size-10 text-base-content/20 mx-auto mb-3"
              />
              <p class="text-sm text-base-content/40 font-medium">Todo en orden</p>
              <p class="text-xs text-base-content/30 mt-1">No hay notas activas para este turno.</p>
            </div>
          <% else %>
            <div class="space-y-3">
              <%= for note <- @active_notes do %>
                <div class={["rounded-2xl border shadow-sm p-4", note_card_class(note.category)]}>
                  <%!-- Category badge --%>
                  <span class={["badge badge-sm", note_badge_class(note.category)]}>
                    {ShiftNotes.category_label(note.category)}
                  </span>

                  <%!-- Content --%>
                  <p class="mt-2 text-sm text-base-content leading-relaxed">{note.content}</p>

                  <%!-- Meta + actions --%>
                  <div class="flex items-center justify-between flex-wrap gap-2 mt-3 pt-3 border-t border-base-300/50">
                    <span class="text-xs text-base-content/50">
                      <span class="font-medium text-base-content/70">
                        {note.author && note.author.name}
                      </span>
                      · {format_dt(note.inserted_at)}
                    </span>
                    <div class="flex items-center gap-2">
                      <button
                        class="btn btn-xs btn-success gap-1"
                        phx-click="resolve_note"
                        phx-value-id={note.id}
                      >
                        <.icon name="hero-check" class="size-3" /> Resolver
                      </button>
                      <%= if @current_user.role == "admin" do %>
                        <button
                          class="btn btn-xs btn-ghost text-error"
                          phx-click="delete_note"
                          phx-value-id={note.id}
                          data-confirm="¿Eliminar esta nota permanentemente?"
                        >
                          <.icon name="hero-trash" class="size-3" />
                        </button>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Resolved notes (collapsible) --%>
        <%= if @resolved_notes != [] do %>
          <div>
            <button
              class="flex items-center gap-2 text-xs font-semibold text-base-content/50 hover:text-base-content transition-colors uppercase tracking-wider"
              phx-click="toggle_resolved"
            >
              <.icon
                name={if @show_resolved, do: "hero-chevron-down", else: "hero-chevron-right"}
                class="size-3.5"
              /> Resueltas (últimos 3 días)
              <span class="badge badge-ghost badge-sm">{length(@resolved_notes)}</span>
            </button>

            <%= if @show_resolved do %>
              <div class="mt-3 space-y-2">
                <%= for note <- @resolved_notes do %>
                  <div class="bg-base-100 rounded-xl border border-base-300 p-3 opacity-60">
                    <div class="flex items-start gap-2 flex-wrap">
                      <span class="badge badge-sm badge-ghost shrink-0">
                        {ShiftNotes.category_label(note.category)}
                      </span>
                      <p class="text-sm text-base-content/60 flex-1 line-through decoration-base-content/30">
                        {note.content}
                      </p>
                    </div>
                    <div class="flex items-center justify-between flex-wrap gap-2 mt-2">
                      <p class="text-xs text-base-content/40">
                        {note.author && note.author.name} · Resuelto por {(note.resolved_by &&
                                                                             note.resolved_by.name) ||
                          "—"}
                        {if note.resolved_at, do: " · #{format_dt(note.resolved_at)}"}
                      </p>
                      <%= if @current_user.role == "admin" do %>
                        <button
                          class="btn btn-xs btn-ghost text-error"
                          phx-click="delete_note"
                          phx-value-id={note.id}
                          data-confirm="¿Eliminar esta nota?"
                        >
                          <.icon name="hero-trash" class="size-3" />
                        </button>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp note_card_class("stock"), do: "border-error/30 bg-error/5"
  defp note_card_class("preparacion"), do: "border-info/30 bg-info/5"
  defp note_card_class("equipo"), do: "border-warning/30 bg-warning/5"
  defp note_card_class(_), do: "border-base-300 bg-base-100"

  defp note_badge_class("stock"), do: "badge-error"
  defp note_badge_class("preparacion"), do: "badge-info"
  defp note_badge_class("equipo"), do: "badge-warning"
  defp note_badge_class(_), do: "badge-ghost"

  defp category_placeholder("stock"), do: "Ej: Se acabó la crema de cacahuate — pedir hoy"
  defp category_placeholder("preparacion"), do: "Ej: El pan de ayer está en el congelador"
  defp category_placeholder("equipo"), do: "Ej: La licuadora 2 hace ruido raro"
  defp category_placeholder(_), do: "Ej: Llega el proveedor de leche a las 10am mañana"

  defp format_dt(%DateTime{} = dt),
    do: Calendar.strftime(dt, "%d/%m %H:%M")

  defp format_dt(_), do: "—"
end
