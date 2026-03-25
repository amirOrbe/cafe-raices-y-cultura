defmodule CRCWeb.Admin.CollaboratorsLive do
  @moduledoc "Collaborator management from the administration panel."

  use CRCWeb, :live_view

  alias CRC.Events
  alias CRC.Events.Collaborator

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(CRC.PubSub, "admin:collaborators")

    socket =
      socket
      |> assign(:page_title, "Colaboradores · Admin")
      |> assign(:collaborators, Events.list_collaborators())
      |> assign(:status_filter, :active)
      |> assign(:modal, nil)
      |> assign(:form, nil)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:collaborator_changed, _collaborator}, socket) do
    {:noreply, assign(socket, :collaborators, Events.list_collaborators())}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("set_status_filter", %{"status" => status}, socket) do
    {:noreply, assign(socket, :status_filter, String.to_existing_atom(status))}
  end

  def handle_event("new_collaborator", _params, socket) do
    changeset = Events.change_collaborator(%Collaborator{})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("edit_collaborator", %{"id" => id}, socket) do
    collaborator = Events.get_collaborator!(String.to_integer(id))
    changeset = Events.change_collaborator(collaborator)

    {:noreply,
     socket
     |> assign(:modal, {:edit, collaborator})
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil)}
  end

  def handle_event("save_collaborator", %{"collaborator" => params}, socket) do
    result =
      case socket.assigns.modal do
        :new -> Events.create_collaborator(params)
        {:edit, collaborator} -> Events.update_collaborator(collaborator, params)
      end

    case result do
      {:ok, _collaborator} ->
        label = if socket.assigns.modal == :new, do: "creado", else: "actualizado"

        {:noreply,
         socket
         |> put_flash(:info, "Colaborador #{label} correctamente.")
         |> assign(:collaborators, Events.list_collaborators())
         |> assign(:modal, nil)
         |> assign(:form, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    collaborator = Events.get_collaborator!(String.to_integer(id))

    case Events.toggle_collaborator_active(collaborator) do
      {:ok, _} ->
        action = if collaborator.active, do: "desactivado", else: "activado"

        {:noreply,
         socket
         |> put_flash(:info, "Colaborador #{action} correctamente.")
         |> assign(:collaborators, Events.list_collaborators())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo cambiar el estado del colaborador.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <% visible = filter_by_status(@collaborators, @status_filter) %>
    <% active_count = Enum.count(@collaborators, & &1.active) %>
    <% inactive_count = Enum.count(@collaborators, &(!&1.active)) %>
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Colaboradores</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            {length(visible)}
            {if length(visible) == 1, do: "colaborador", else: "colaboradores"}
            {if @status_filter == :active, do: "activos", else: "inactivos"}
          </p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="new_collaborator">
          <.icon name="hero-plus" class="size-4" />
          Nuevo colaborador
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
                <th>Instagram</th>
                <th>Bio</th>
                <th>Estado</th>
                <th class="text-right">Acciones</th>
              </tr>
            </thead>
            <tbody>
              <%= for collaborator <- visible do %>
                <tr class="hover:bg-base-200/50 transition-colors">
                  <td class="font-medium text-sm text-base-content">{collaborator.name}</td>
                  <td class="text-sm text-base-content/70">
                    {if collaborator.instagram_handle,
                      do: "@#{collaborator.instagram_handle}",
                      else: "—"}
                  </td>
                  <td class="text-sm text-base-content/60 max-w-xs">
                    <%= if collaborator.bio do %>
                      <span class="line-clamp-1">{collaborator.bio}</span>
                    <% else %>
                      —
                    <% end %>
                  </td>
                  <td>
                    <%= if collaborator.active do %>
                      <span class="badge badge-sm badge-success">Activo</span>
                    <% else %>
                      <span class="badge badge-sm badge-error">Inactivo</span>
                    <% end %>
                  </td>
                  <td>
                    <div class="flex items-center justify-end gap-1">
                      <button
                        class="btn btn-ghost btn-sm"
                        phx-click="edit_collaborator"
                        phx-value-id={collaborator.id}
                        title="Editar"
                      >
                        <.icon name="hero-pencil" class="size-4" />
                      </button>
                      <button
                        class={["btn btn-ghost btn-sm", if(collaborator.active, do: "text-error", else: "text-success")]}
                        phx-click="toggle_active"
                        phx-value-id={collaborator.id}
                        title={if collaborator.active, do: "Desactivar", else: "Activar"}
                      >
                        <.icon
                          name={if collaborator.active, do: "hero-no-symbol", else: "hero-check-circle"}
                          class="size-4"
                        />
                      </button>
                    </div>
                  </td>
                </tr>
              <% end %>
              <%= if visible == [] do %>
                <tr>
                  <td colspan="5" class="text-center py-12 text-base-content/40 text-sm">
                    {if @status_filter == :active,
                      do: "No hay colaboradores activos.",
                      else: "No hay colaboradores inactivos."}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <%!-- Modal: new / edit collaborator --%>
    <%= if @modal != nil do %>
      <.collaborator_modal form={@form} modal={@modal} />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Collaborator modal
  # ---------------------------------------------------------------------------

  attr :form, :map, required: true
  attr :modal, :any, required: true

  defp collaborator_modal(assigns) do
    title = if assigns.modal == :new, do: "Nuevo colaborador", else: "Editar colaborador"
    assigns = assign(assigns, :title, title)

    ~H"""
    <div
      id="collaborator-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_modal"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_modal"></div>

      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-lg overflow-y-auto max-h-[90vh]">
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between sticky top-0 bg-base-100">
          <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="px-6 py-5">
          <.form id="collaborator-form" for={@form} phx-submit="save_collaborator" class="space-y-1">
            <.input
              field={@form[:name]}
              type="text"
              label="Nombre"
              placeholder="Ej. Ana García, Trío Raíces"
            />
            <.input
              field={@form[:instagram_handle]}
              type="text"
              label="Instagram (opcional)"
              placeholder="sin @, ej: anagarcia.music"
            />
            <.input
              field={@form[:bio]}
              type="textarea"
              label="Biografía (opcional)"
              placeholder="Breve descripción del colaborador o agrupación..."
            />

            <div class="flex justify-end gap-3 pt-4">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
              <button type="submit" class="btn btn-primary">
                {if @modal == :new, do: "Crear colaborador", else: "Guardar cambios"}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  defp filter_by_status(collaborators, :active), do: Enum.filter(collaborators, & &1.active)
  defp filter_by_status(collaborators, :inactive), do: Enum.filter(collaborators, &(!&1.active))
end
