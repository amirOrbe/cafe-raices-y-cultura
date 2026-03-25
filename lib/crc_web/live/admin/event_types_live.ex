defmodule CRCWeb.Admin.EventTypesLive do
  @moduledoc "Event type management from the administration panel."

  use CRCWeb, :live_view

  alias CRC.Events
  alias CRC.Events.EventType

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(CRC.PubSub, "admin:event_types")

    socket =
      socket
      |> assign(:page_title, "Tipos de Evento · Admin")
      |> assign(:event_types, Events.list_event_types())
      |> assign(:status_filter, :active)
      |> assign(:modal, nil)
      |> assign(:form, nil)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:event_type_changed, _event_type}, socket) do
    {:noreply, assign(socket, :event_types, Events.list_event_types())}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("set_status_filter", %{"status" => status}, socket) do
    {:noreply, assign(socket, :status_filter, String.to_existing_atom(status))}
  end

  def handle_event("new_event_type", _params, socket) do
    changeset = Events.change_event_type(%EventType{})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("edit_event_type", %{"id" => id}, socket) do
    event_type = Events.get_event_type!(String.to_integer(id))
    changeset = Events.change_event_type(event_type)

    {:noreply,
     socket
     |> assign(:modal, {:edit, event_type})
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil)}
  end

  def handle_event("save_event_type", %{"event_type" => params}, socket) do
    result =
      case socket.assigns.modal do
        :new -> Events.create_event_type(params)
        {:edit, event_type} -> Events.update_event_type(event_type, params)
      end

    case result do
      {:ok, _event_type} ->
        label = if socket.assigns.modal == :new, do: "creado", else: "actualizado"

        {:noreply,
         socket
         |> put_flash(:info, "Tipo de evento #{label} correctamente.")
         |> assign(:event_types, Events.list_event_types())
         |> assign(:modal, nil)
         |> assign(:form, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    event_type = Events.get_event_type!(String.to_integer(id))

    case Events.toggle_event_type_active(event_type) do
      {:ok, _} ->
        action = if event_type.active, do: "desactivado", else: "activado"

        {:noreply,
         socket
         |> put_flash(:info, "Tipo de evento #{action} correctamente.")
         |> assign(:event_types, Events.list_event_types())}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "No se pudo cambiar el estado del tipo de evento.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <% visible = filter_by_status(@event_types, @status_filter) %>
    <% active_count = Enum.count(@event_types, & &1.active) %>
    <% inactive_count = Enum.count(@event_types, &(!&1.active)) %>
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Tipos de Evento</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            {length(visible)}
            {if length(visible) == 1, do: "tipo", else: "tipos"}
            {if @status_filter == :active, do: "activos", else: "inactivos"}
          </p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="new_event_type">
          <.icon name="hero-plus" class="size-4" />
          Nuevo tipo
        </button>
      </div>

      <%!-- Status tabs --%>
      <div class="flex gap-2">
        <button
          class={["btn btn-sm gap-1.5", if(@status_filter == :active, do: "btn-primary", else: "btn-ghost")]}
          phx-click="set_status_filter"
          phx-value-status="active"
        >
          <.icon name="hero-check-circle" class="size-3.5" />
          Activos
          <span class={["badge badge-xs", if(@status_filter == :active, do: "badge-primary-content/30", else: "badge-ghost")]}>
            {active_count}
          </span>
        </button>
        <button
          class={["btn btn-sm gap-1.5", if(@status_filter == :inactive, do: "btn-error", else: "btn-ghost")]}
          phx-click="set_status_filter"
          phx-value-status="inactive"
        >
          <.icon name="hero-x-circle" class="size-3.5" />
          Inactivos
          <span class={["badge badge-xs", if(@status_filter == :inactive, do: "badge-error-content/30", else: "badge-ghost")]}>
            {inactive_count}
          </span>
        </button>
      </div>

      <%!-- Table --%>
      <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
          <table class="table table-zebra w-full">
            <thead>
              <tr class="bg-base-200 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                <th>Nombre</th>
                <th>Estado</th>
                <th class="text-right">Acciones</th>
              </tr>
            </thead>
            <tbody>
              <%= for event_type <- visible do %>
                <tr class="hover:bg-base-200/50 transition-colors">
                  <td class="font-medium text-sm text-base-content">{event_type.name}</td>
                  <td>
                    <%= if event_type.active do %>
                      <span class="badge badge-sm badge-success">Activo</span>
                    <% else %>
                      <span class="badge badge-sm badge-error">Inactivo</span>
                    <% end %>
                  </td>
                  <td>
                    <div class="flex items-center justify-end gap-1">
                      <button
                        class="btn btn-ghost btn-sm"
                        phx-click="edit_event_type"
                        phx-value-id={event_type.id}
                        title="Editar"
                      >
                        <.icon name="hero-pencil" class="size-4" />
                      </button>
                      <button
                        class={["btn btn-ghost btn-sm", if(event_type.active, do: "text-error", else: "text-success")]}
                        phx-click="toggle_active"
                        phx-value-id={event_type.id}
                        title={if event_type.active, do: "Desactivar", else: "Activar"}
                      >
                        <.icon
                          name={if event_type.active, do: "hero-no-symbol", else: "hero-check-circle"}
                          class="size-4"
                        />
                      </button>
                    </div>
                  </td>
                </tr>
              <% end %>
              <%= if visible == [] do %>
                <tr>
                  <td colspan="3" class="text-center py-12 text-base-content/40 text-sm">
                    {if @status_filter == :active,
                      do: "No hay tipos de evento activos.",
                      else: "No hay tipos de evento inactivos."}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <%!-- Modal: new / edit event type --%>
    <%= if @modal != nil do %>
      <.event_type_modal form={@form} modal={@modal} />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Event type modal
  # ---------------------------------------------------------------------------

  attr :form, :map, required: true
  attr :modal, :any, required: true

  defp event_type_modal(assigns) do
    title = if assigns.modal == :new, do: "Nuevo tipo de evento", else: "Editar tipo de evento"
    assigns = assign(assigns, :title, title)

    ~H"""
    <div
      id="event-type-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_modal"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_modal"></div>

      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-md overflow-hidden">
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="px-6 py-5">
          <.form id="event-type-form" for={@form} phx-submit="save_event_type" class="space-y-1">
            <.input
              field={@form[:name]}
              type="text"
              label="Nombre del tipo"
              placeholder="Ej. Concierto, Taller, Lectura, Feria"
            />

            <div class="flex justify-end gap-3 pt-4">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
              <button type="submit" class="btn btn-primary">
                {if @modal == :new, do: "Crear tipo", else: "Guardar cambios"}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  defp filter_by_status(event_types, :active), do: Enum.filter(event_types, & &1.active)
  defp filter_by_status(event_types, :inactive), do: Enum.filter(event_types, &(!&1.active))
end
