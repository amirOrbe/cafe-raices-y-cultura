defmodule CRCWeb.Admin.UsersLive do
  @moduledoc "User management from the administration panel."

  use CRCWeb, :live_view

  alias CRC.Accounts
  alias CRC.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(CRC.PubSub, "admin:users")

    socket =
      socket
      |> assign(:page_title, "Usuarios · Admin")
      |> assign(:users, Accounts.list_users())
      |> assign(:status_filter, :active)
      |> assign(:modal, nil)
      |> assign(:form, nil)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:user_changed, _user}, socket) do
    {:noreply, assign(socket, :users, Accounts.list_users())}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("set_status_filter", %{"status" => status}, socket) do
    {:noreply, assign(socket, :status_filter, String.to_existing_atom(status))}
  end

  def handle_event("new_user", _params, socket) do
    changeset = User.changeset(%User{}, %{})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("edit_user", %{"id" => id}, socket) do
    user = Accounts.get_user!(String.to_integer(id))
    changeset = User.changeset(user, %{})

    {:noreply,
     socket
     |> assign(:modal, {:edit, user})
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil)}
  end

  def handle_event("save_user", %{"user" => params}, socket) do
    admin = socket.assigns.current_user

    result =
      case socket.assigns.modal do
        :new ->
          Accounts.create_user(admin, params)

        {:edit, user} ->
          # Skip password update if left blank
          clean_params =
            if params["password"] == "" or is_nil(params["password"]) do
              Map.delete(params, "password")
            else
              params
            end

          Accounts.update_user(admin, user, clean_params)
      end

    case result do
      {:ok, _user} ->
        label = if socket.assigns.modal == :new, do: "creado", else: "actualizado"

        {:noreply,
         socket
         |> put_flash(:info, "Usuario #{label} correctamente.")
         |> assign(:users, Accounts.list_users())
         |> assign(:modal, nil)
         |> assign(:form, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "No tienes permiso para realizar esta acción.")}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    admin = socket.assigns.current_user
    user = Accounts.get_user!(String.to_integer(id))

    result =
      if user.is_active do
        Accounts.deactivate_user(admin, user)
      else
        Accounts.activate_user(admin, user)
      end

    case result do
      {:ok, _} ->
        action = if user.is_active, do: "desactivado", else: "activado"

        {:noreply,
         socket
         |> put_flash(:info, "Usuario #{action} correctamente.")
         |> assign(:users, Accounts.list_users())}

      {:error, :cannot_deactivate_self} ->
        {:noreply, put_flash(socket, :error, "No puedes desactivar tu propia cuenta.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo cambiar el estado del usuario.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <% visible = filter_by_status(@users, @status_filter) %>
    <% active_count = Enum.count(@users, & &1.is_active) %>
    <% inactive_count = Enum.count(@users, &(!&1.is_active)) %>
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Usuarios</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            {length(visible)}
            {if length(visible) == 1, do: "usuario", else: "usuarios"}
            {if @status_filter == :active, do: "activos", else: "inactivos"}
          </p>
        </div>
        <button id="btn-new-user" class="btn btn-primary gap-2" phx-click="new_user">
          <.icon name="hero-plus" class="size-4" />
          Nuevo usuario
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
                <th>Correo</th>
                <th>Rol</th>
                <th>Estación</th>
                <th>Estado</th>
                <th class="text-right">Acciones</th>
              </tr>
            </thead>
            <tbody>
              <%= for user <- visible do %>
                <tr class="hover:bg-base-200/50 transition-colors">
                  <td>
                    <div class="flex items-center gap-3">
                      <div class="size-8 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
                        <span class="text-primary font-semibold text-xs">
                          {String.first(user.name) |> String.upcase()}
                        </span>
                      </div>
                      <span class="font-medium text-sm text-base-content">{user.name}</span>
                    </div>
                  </td>
                  <td class="text-sm text-base-content/70">{user.email}</td>
                  <td>
                    <.role_badge role={user.role} />
                  </td>
                  <td class="text-sm text-base-content/60">
                    {station_label(user.station)}
                  </td>
                  <td>
                    <.status_badge is_active={user.is_active} />
                  </td>
                  <td>
                    <div class="flex items-center justify-end gap-1">
                      <button
                        id={"btn-edit-#{user.id}"}
                        class="btn btn-ghost btn-sm"
                        phx-click="edit_user"
                        phx-value-id={user.id}
                        title="Editar"
                      >
                        <.icon name="hero-pencil" class="size-4" />
                      </button>
                      <button
                        id={"btn-toggle-#{user.id}"}
                        class={["btn btn-ghost btn-sm", if(user.is_active, do: "text-error", else: "text-success")]}
                        phx-click="toggle_active"
                        phx-value-id={user.id}
                        title={if user.is_active, do: "Desactivar", else: "Activar"}
                      >
                        <.icon
                          name={if user.is_active, do: "hero-no-symbol", else: "hero-check-circle"}
                          class="size-4"
                        />
                      </button>
                    </div>
                  </td>
                </tr>
              <% end %>
              <%= if visible == [] do %>
                <tr>
                  <td colspan="6" class="text-center py-12 text-base-content/40 text-sm">
                    {if @status_filter == :active,
                      do: "No hay usuarios activos.",
                      else: "No hay usuarios inactivos."}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <%!-- Modal: new / edit user --%>
    <%= if @modal != nil do %>
      <.user_modal form={@form} modal={@modal} />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # User modal
  # ---------------------------------------------------------------------------

  attr :form, :map, required: true
  attr :modal, :any, required: true

  defp user_modal(assigns) do
    title =
      case assigns.modal do
        :new -> "Nuevo usuario"
        {:edit, _} -> "Editar usuario"
      end

    assigns = assign(assigns, :title, title)

    ~H"""
    <div
      id="user-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_modal"
      phx-key="Escape"
    >
      <%!-- Overlay --%>
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_modal"></div>

      <%!-- Panel --%>
      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-lg overflow-hidden">
        <%!-- Header --%>
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
          <button id="btn-close-modal" class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <%!-- Form --%>
        <div class="px-6 py-5">
          <.form id="user-form" for={@form} phx-submit="save_user" class="space-y-1">
            <.input field={@form[:name]} type="text" label="Nombre completo" placeholder="Ej. Ana García López" />
            <.input field={@form[:email]} type="email" label="Correo electrónico" placeholder="correo@ejemplo.com" />
            <.input field={@form[:phone]} type="text" label="Teléfono (opcional)" placeholder="55 1234 5678" />
            <.input
              field={@form[:role]}
              type="select"
              label="Rol"
              options={[
                {"Administrador", "admin"},
                {"Empleado", "empleado"},
                {"Cliente", "cliente"}
              ]}
            />
            <.input
              field={@form[:station]}
              type="select"
              label="Estación (solo empleados)"
              options={[
                {"— Ninguna —", ""},
                {"Cocina", "cocina"},
                {"Barra", "barra"},
                {"Sala (mesero/a)", "sala"}
              ]}
            />
            <.input
              field={@form[:password]}
              type="password"
              label={if @modal == :new, do: "Contraseña", else: "Contraseña (dejar en blanco para no cambiar)"}
              placeholder={if @modal == :new, do: "Mínimo 8 caracteres", else: "Nueva contraseña (opcional)"}
            />

            <div class="flex justify-end gap-3 pt-4">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
              <button type="submit" class="btn btn-primary">
                {if @modal == :new, do: "Crear usuario", else: "Guardar cambios"}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Badge components
  # ---------------------------------------------------------------------------

  defp role_badge(assigns) do
    {text, cls} =
      case assigns.role do
        "admin" -> {"Admin", "badge-primary"}
        "empleado" -> {"Empleado", "badge-secondary"}
        _ -> {"Cliente", "badge-ghost"}
      end

    assigns = assign(assigns, text: text, cls: cls)

    ~H"""
    <span class={["badge badge-sm", @cls]}>{@text}</span>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <%= if @is_active do %>
      <span class="badge badge-sm badge-success">Activo</span>
    <% else %>
      <span class="badge badge-sm badge-error">Inactivo</span>
    <% end %>
    """
  end

  defp filter_by_status(users, :active), do: Enum.filter(users, & &1.is_active)
  defp filter_by_status(users, :inactive), do: Enum.filter(users, &(!&1.is_active))

  defp station_label(nil), do: "—"
  defp station_label(""), do: "—"
  defp station_label("cocina"), do: "Cocina"
  defp station_label("barra"), do: "Barra"
  defp station_label("sala"), do: "Sala"
  defp station_label(other), do: other
end
