defmodule CRCWeb.Admin.UsersLive do
  @moduledoc "User management from the administration panel."

  use CRCWeb, :live_view

  alias CRC.Accounts
  alias CRC.Accounts.User
  alias CRC.Cloudinary

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
      |> assign(:form_role, "admin")
      |> assign(:remove_avatar, false)
      |> allow_upload(:avatar,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 5_000_000,
        auto_upload: true
      )

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
     |> assign(:form, to_form(changeset))
     |> assign(:form_role, "admin")
     |> assign(:remove_avatar, false)}
  end

  def handle_event("edit_user", %{"id" => id}, socket) do
    user = Accounts.get_user!(String.to_integer(id))
    changeset = User.changeset(user, %{})

    {:noreply,
     socket
     |> assign(:modal, {:edit, user})
     |> assign(:form, to_form(changeset))
     |> assign(:form_role, user.role)
     |> assign(:remove_avatar, false)}
  end

  def handle_event("role_changed", %{"user" => %{"role" => role}}, socket) do
    {:noreply, assign(socket, :form_role, role)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil, form_role: "admin", remove_avatar: false)}
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  def handle_event("remove_avatar", _params, socket) do
    {:noreply, assign(socket, :remove_avatar, true)}
  end

  def handle_event("save_user", %{"user" => params}, socket) do
    admin = socket.assigns.current_user

    # Upload avatar to Cloudinary if one was selected
    uploaded_avatar_url =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
        case Cloudinary.upload(path, folder: "avatars", content_type: entry.client_type) do
          {:ok, url} ->
            {:ok, url}

          {:error, reason} ->
            require Logger
            Logger.error("Avatar upload failed: #{inspect(reason)}")
            {:ok, nil}
        end
      end)
      |> List.first()

    params =
      cond do
        uploaded_avatar_url -> Map.put(params, "avatar_url", uploaded_avatar_url)
        socket.assigns.remove_avatar -> Map.put(params, "avatar_url", nil)
        true -> params
      end

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
         |> assign(:form, nil)
         |> assign(:remove_avatar, false)}

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

      <%!-- ── Mobile card list (< md) ──────────────────────────────────────── --%>
      <div class="md:hidden flex flex-col gap-2">
        <%= if visible == [] do %>
          <div class="text-center py-12 text-base-content/40 text-sm bg-base-100 rounded-2xl border border-base-300">
            {if @status_filter == :active,
              do: "No hay usuarios activos.",
              else: "No hay usuarios inactivos."}
          </div>
        <% end %>
        <%= for user <- visible do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-3 flex items-center gap-3">
            <%!-- Avatar --%>
            <div class="size-11 rounded-full bg-primary/10 flex items-center justify-center shrink-0 overflow-hidden border border-base-300">
              <%= if user.avatar_url do %>
                <img src={user.avatar_url} alt={user.name} class="size-11 object-cover" />
              <% else %>
                <span class="text-primary font-bold text-sm">
                  {String.first(user.name) |> String.upcase()}
                </span>
              <% end %>
            </div>
            <%!-- Info --%>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 flex-wrap">
                <p class="font-semibold text-sm text-base-content truncate">{user.name}</p>
                <.role_badge role={user.role} />
              </div>
              <p class="text-xs text-base-content/50 truncate mt-0.5">{user.email}</p>
              <div class="flex items-center gap-1.5 mt-1.5 flex-wrap">
                <.status_badge is_active={user.is_active} />
                <%= for s <- user.stations do %>
                  <span class="badge badge-xs badge-ghost">{station_label(s)}</span>
                <% end %>
              </div>
            </div>
            <%!-- Actions --%>
            <div class="flex flex-col items-center gap-1 shrink-0">
              <button
                id={"btn-edit-mobile-#{user.id}"}
                class="btn btn-ghost btn-xs btn-circle"
                phx-click="edit_user"
                phx-value-id={user.id}
                title="Editar"
              >
                <.icon name="hero-pencil" class="size-4" />
              </button>
              <button
                id={"btn-toggle-mobile-#{user.id}"}
                class={["btn btn-ghost btn-xs btn-circle", if(user.is_active, do: "text-error", else: "text-success")]}
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
          </div>
        <% end %>
      </div>

      <%!-- ── Desktop table (md+) ────────────────────────────────────────────── --%>
      <div class="hidden md:block bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
          <table class="table table-zebra table-fixed w-full">
            <thead>
              <tr class="bg-base-200 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                <th class="w-[25%]">Nombre</th>
                <th class="w-[28%]">Correo</th>
                <th class="w-[12%]">Rol</th>
                <th class="w-[18%]">Estación</th>
                <th class="w-[10%]">Estado</th>
                <th class="w-[7%] text-right">Acciones</th>
              </tr>
            </thead>
            <tbody>
              <%= for user <- visible do %>
                <tr class="hover:bg-base-200/50 transition-colors">
                  <td class="max-w-0">
                    <div class="flex items-center gap-3">
                      <div class="size-8 rounded-full bg-primary/10 flex items-center justify-center shrink-0 overflow-hidden border border-base-300">
                        <%= if user.avatar_url do %>
                          <img src={user.avatar_url} alt={user.name} class="size-8 object-cover" />
                        <% else %>
                          <span class="text-primary font-semibold text-xs">
                            {String.first(user.name) |> String.upcase()}
                          </span>
                        <% end %>
                      </div>
                      <span class="font-medium text-sm text-base-content truncate">{user.name}</span>
                    </div>
                  </td>
                  <td class="max-w-0 text-sm text-base-content/70 truncate">{user.email}</td>
                  <td>
                    <.role_badge role={user.role} />
                  </td>
                  <td>
                    <div class="flex flex-wrap gap-1">
                      <%= if user.stations == [] do %>
                        <span class="text-sm text-base-content/40">—</span>
                      <% else %>
                        <%= for s <- user.stations do %>
                          <span class="badge badge-xs badge-ghost">{station_label(s)}</span>
                        <% end %>
                      <% end %>
                    </div>
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
      <.user_modal
        form={@form}
        modal={@modal}
        form_role={@form_role}
        uploads={@uploads}
        remove_avatar={@remove_avatar}
      />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # User modal
  # ---------------------------------------------------------------------------

  attr :form, :map, required: true
  attr :modal, :any, required: true
  attr :form_role, :string, required: true
  attr :uploads, :map, required: true
  attr :remove_avatar, :boolean, default: false

  defp user_modal(assigns) do
    title =
      case assigns.modal do
        :new -> "Nuevo usuario"
        {:edit, _} -> "Editar usuario"
      end

    current_avatar =
      case assigns.modal do
        {:edit, user} -> user.avatar_url
        _ -> nil
      end

    assigns = assigns |> assign(:title, title) |> assign(:current_avatar, current_avatar)

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
      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-lg overflow-y-auto max-h-[90vh]">
        <%!-- Header --%>
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
          <button id="btn-close-modal" class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <%!-- Form --%>
        <div class="px-6 py-5">
          <.form id="user-form" for={@form} phx-submit="save_user" phx-change="validate_upload" class="space-y-1">

            <%!-- ── Avatar ──────────────────────────────────────────────────────── --%>
            <div class="pb-2">
              <p class="text-sm font-medium text-base-content mb-2">
                Foto de perfil <span class="text-base-content/40 font-normal">(opcional)</span>
              </p>

              <%= if @current_avatar && !@remove_avatar do %>
                <div class="flex items-center gap-3 p-3 bg-base-200 rounded-xl mb-2">
                  <img src={@current_avatar} class="size-14 rounded-full object-cover border border-base-300 shrink-0" />
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-base-content">Foto actual</p>
                    <button type="button" class="btn btn-xs btn-error btn-outline gap-1 mt-1" phx-click="remove_avatar">
                      <.icon name="hero-trash" class="size-3" /> Eliminar foto
                    </button>
                  </div>
                </div>
              <% end %>

              <%= if !@current_avatar || @remove_avatar do %>
                <label
                  for={@uploads.avatar.ref}
                  class="flex flex-col items-center justify-center gap-2 w-full py-5 px-4 rounded-2xl border-2 border-dashed border-base-300 hover:border-primary/40 hover:bg-primary/5 cursor-pointer transition-all duration-200"
                >
                  <div class="flex items-center justify-center w-10 h-10 rounded-full bg-primary/10">
                    <.icon name="hero-user-circle" class="size-5 text-primary" />
                  </div>
                  <div class="text-center">
                    <p class="text-sm font-medium text-base-content">Selecciona una foto de perfil</p>
                    <p class="text-xs text-base-content/40 mt-0.5">JPG, PNG o WebP · Máx. 5 MB</p>
                  </div>
                  <.live_file_input upload={@uploads.avatar} class="sr-only" />
                </label>
              <% end %>

              <%= for entry <- @uploads.avatar.entries do %>
                <div class="flex items-center gap-3 mt-2 p-2.5 bg-base-200 rounded-xl">
                  <.live_img_preview entry={entry} class="size-10 object-cover rounded-full shrink-0" />
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium truncate">{entry.client_name}</p>
                    <div class="w-full bg-base-300 rounded-full h-1.5 mt-1.5">
                      <div class="bg-primary h-1.5 rounded-full transition-all duration-300" style={"width: #{entry.progress}%"} />
                    </div>
                  </div>
                  <button type="button" class="btn btn-ghost btn-xs btn-circle text-error shrink-0" phx-click="cancel_upload" phx-value-ref={entry.ref}>
                    <.icon name="hero-x-mark" class="size-3.5" />
                  </button>
                </div>
              <% end %>
            </div>
            <%!-- ── End Avatar ───────────────────────────────────────────────────── --%>

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
              phx-change="role_changed"
            />
            <%!-- Station checkboxes — only shown when role is "empleado" --%>
            <%= if @form_role == "empleado" do %>
              <div class="form-control">
                <label class="label pb-1">
                  <span class="label-text text-sm font-medium">Estaciones</span>
                </label>
                <%!-- Hidden sentinel so the key is always present even if nothing is checked --%>
                <input type="hidden" name="user[stations][]" value="" />
                <div class="flex flex-wrap gap-x-5 gap-y-2 px-1">
                  <%= for {label, value} <- [{"Cocina", "cocina"}, {"Barra", "barra"}, {"Sala (mesero/a)", "sala"}] do %>
                    <label class="flex items-center gap-2 cursor-pointer">
                      <input
                        type="checkbox"
                        name="user[stations][]"
                        value={value}
                        checked={value in (Phoenix.HTML.Form.input_value(@form, :stations) || [])}
                        class="checkbox checkbox-sm checkbox-primary"
                      />
                      <span class="text-sm label-text">{label}</span>
                    </label>
                  <% end %>
                </div>
                <%= if msg = @form[:stations].errors |> List.first() do %>
                  <p class="text-error text-xs mt-1">{elem(msg, 0)}</p>
                <% end %>
              </div>
            <% end %>
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

  defp station_label("cocina"), do: "Cocina"
  defp station_label("barra"), do: "Barra"
  defp station_label("sala"), do: "Sala"
  defp station_label(other), do: other
end
