defmodule CRCWeb.Employee.ProfileLive do
  @moduledoc """
  Self-service profile page accessible to any authenticated user.

  Allows changing:
    - Display name
    - Profile photo (Cloudinary upload)
    - Password (requires current password for verification)

  Does NOT allow changing: email, role, stations, or active status.
  Those fields remain admin-only.
  """

  use CRCWeb, :live_view

  import CRCWeb.Layouts, only: [flash_group: 1]

  alias CRC.Accounts
  alias CRC.Accounts.User
  alias CRC.Cloudinary
  alias CRCWeb.Components.SiteComponents

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, "Mi Perfil")
      |> assign(:profile_form, User.profile_changeset(user, %{}) |> to_form())
      |> assign(:remove_avatar, false)
      |> assign(:pw_errors, [])
      |> assign(:nav_open, false)
      |> allow_upload(:avatar,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 5_000_000,
        auto_upload: true
      )

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events — navbar
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_nav", _params, socket) do
    {:noreply, update(socket, :nav_open, &(!&1))}
  end

  def handle_event("close_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, false)}
  end

  # ---------------------------------------------------------------------------
  # Events — avatar
  # ---------------------------------------------------------------------------

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  def handle_event("remove_avatar", _params, socket) do
    {:noreply, assign(socket, :remove_avatar, true)}
  end

  def handle_event("keep_avatar", _params, socket) do
    {:noreply, assign(socket, :remove_avatar, false)}
  end

  # ---------------------------------------------------------------------------
  # Events — save profile (name + avatar)
  # ---------------------------------------------------------------------------

  def handle_event("save_profile", %{"user" => params}, socket) do
    user = socket.assigns.current_user

    # Upload avatar to Cloudinary if a new file was selected
    uploaded_url =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
        case Cloudinary.upload(path, folder: "avatars", content_type: entry.client_type) do
          {:ok, url} -> {:ok, url}
          {:error, _} -> {:ok, nil}
        end
      end)
      |> List.first()

    params =
      cond do
        uploaded_url -> Map.put(params, "avatar_url", uploaded_url)
        socket.assigns.remove_avatar -> Map.put(params, "avatar_url", nil)
        true -> params
      end

    case Accounts.update_own_profile(user, params) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:current_user, updated_user)
         |> assign(:profile_form, User.profile_changeset(updated_user, %{}) |> to_form())
         |> assign(:remove_avatar, false)
         |> put_flash(:info, "Perfil actualizado correctamente.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset))}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — change password
  # ---------------------------------------------------------------------------

  def handle_event(
        "change_password",
        %{"current_password" => current, "new_password" => new, "confirm_password" => confirm},
        socket
      ) do
    user = socket.assigns.current_user

    errors = validate_password_form(current, new, confirm)

    if errors != [] do
      {:noreply, assign(socket, :pw_errors, errors)}
    else
      case Accounts.authenticate_user(user.email, current) do
        {:ok, _} ->
          case Accounts.update_own_password(user, new) do
            {:ok, updated_user} ->
              {:noreply,
               socket
               |> assign(:current_user, updated_user)
               |> assign(:pw_errors, [])
               |> put_flash(:info, "Contraseña actualizada correctamente.")}

            {:error, changeset} ->
              msgs =
                Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
                  Enum.reduce(opts, msg, fn {k, v}, acc ->
                    String.replace(acc, "%{#{k}}", to_string(v))
                  end)
                end)
                |> Map.values()
                |> List.flatten()

              {:noreply, assign(socket, :pw_errors, msgs)}
          end

        {:error, _} ->
          {:noreply, assign(socket, :pw_errors, ["La contraseña actual es incorrecta."])}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <SiteComponents.site_navbar
      nav_open={@nav_open}
      current_page={:perfil}
      current_user={@current_user}
    />

    <div class="min-h-screen bg-base-200 pt-20 pb-12">
      <div class="max-w-lg mx-auto px-4 space-y-6">

        <%!-- Header --%>
        <div class="flex items-center gap-3">
          <div class="size-14 rounded-full bg-primary/10 border border-base-300 overflow-hidden shrink-0 flex items-center justify-center">
            <%= if @current_user.avatar_url do %>
              <img src={@current_user.avatar_url} alt={@current_user.name} class="size-14 object-cover" />
            <% else %>
              <span class="text-primary font-bold text-xl">
                {String.first(@current_user.name) |> String.upcase()}
              </span>
            <% end %>
          </div>
          <div>
            <h1 class="text-xl font-bold text-base-content">{@current_user.name}</h1>
            <p class="text-sm text-base-content/50">{@current_user.email}</p>
            <span class="badge badge-sm badge-ghost mt-1">
              {if @current_user.role == "admin", do: "Administrador", else: "Empleado"}
            </span>
          </div>
        </div>

        <%!-- Card 1: Nombre y foto --%>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-6">
          <h2 class="text-base font-semibold text-base-content mb-4">Nombre y foto de perfil</h2>

          <.form
            for={@profile_form}
            phx-submit="save_profile"
            phx-change="validate_upload"
            class="space-y-5"
          >
            <%!-- Avatar section --%>
            <div>
              <p class="text-sm font-medium text-base-content mb-2">
                Foto de perfil
                <span class="text-base-content/40 font-normal">(opcional)</span>
              </p>

              <%!-- Current avatar --%>
              <%= if @current_user.avatar_url && !@remove_avatar do %>
                <div class="flex items-center gap-3 p-3 bg-base-200 rounded-xl mb-3">
                  <img
                    src={@current_user.avatar_url}
                    class="size-16 rounded-full object-cover border border-base-300 shrink-0"
                  />
                  <div>
                    <p class="text-sm font-medium text-base-content">Foto actual</p>
                    <div class="flex gap-2 mt-1.5">
                      <button
                        type="button"
                        class="btn btn-xs btn-error btn-outline gap-1"
                        phx-click="remove_avatar"
                      >
                        <.icon name="hero-trash" class="size-3" /> Eliminar
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>

              <%!-- Drop zone — shown when no avatar or when removing --%>
              <%= if !@current_user.avatar_url || @remove_avatar do %>
                <%= if @remove_avatar do %>
                  <div class="flex items-center justify-between p-3 bg-error/5 border border-error/20 rounded-xl mb-3">
                    <p class="text-sm text-error">La foto se eliminará al guardar.</p>
                    <button
                      type="button"
                      class="btn btn-xs btn-ghost"
                      phx-click="keep_avatar"
                    >
                      Cancelar
                    </button>
                  </div>
                <% end %>
                <label
                  for={@uploads.avatar.ref}
                  class="flex flex-col items-center justify-center gap-2 w-full py-6 px-4 rounded-2xl border-2 border-dashed border-base-300 hover:border-primary/40 hover:bg-primary/5 cursor-pointer transition-all"
                >
                  <.icon name="hero-user-circle" class="size-8 text-primary/40" />
                  <div class="text-center">
                    <p class="text-sm font-medium text-base-content">
                      {if @remove_avatar, do: "Subir foto nueva (opcional)", else: "Selecciona una foto de perfil"}
                    </p>
                    <p class="text-xs text-base-content/40 mt-0.5">JPG, PNG o WebP · Máx. 5 MB</p>
                  </div>
                  <.live_file_input upload={@uploads.avatar} class="sr-only" />
                </label>
              <% end %>

              <%!-- Upload preview --%>
              <%= for entry <- @uploads.avatar.entries do %>
                <div class="flex items-center gap-3 mt-3 p-3 bg-base-200 rounded-xl">
                  <.live_img_preview entry={entry} class="size-12 object-cover rounded-full shrink-0" />
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium truncate">{entry.client_name}</p>
                    <div class="w-full bg-base-300 rounded-full h-1.5 mt-1.5">
                      <div
                        class="bg-primary h-1.5 rounded-full transition-all"
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

            <%!-- Name field --%>
            <.input
              field={@profile_form[:name]}
              type="text"
              label="Nombre completo"
              placeholder="Tu nombre"
            />

            <div class="flex justify-end pt-1">
              <button type="submit" class="btn btn-primary">
                <.icon name="hero-check" class="size-4" />
                Guardar cambios
              </button>
            </div>
          </.form>
        </div>

        <%!-- Card 2: Cambiar contraseña --%>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-6">
          <h2 class="text-base font-semibold text-base-content mb-1">Cambiar contraseña</h2>
          <p class="text-xs text-base-content/50 mb-4">Mínimo 8 caracteres.</p>

          <%!-- Password errors --%>
          <%= if @pw_errors != [] do %>
            <div class="alert alert-error text-sm mb-4">
              <.icon name="hero-x-circle" class="size-5 shrink-0" />
              <ul class="list-disc list-inside space-y-0.5">
                <%= for e <- @pw_errors do %>
                  <li>{e}</li>
                <% end %>
              </ul>
            </div>
          <% end %>

          <form phx-submit="change_password" class="space-y-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Contraseña actual</span>
              </label>
              <input
                type="password"
                name="current_password"
                class="input input-bordered w-full"
                placeholder="Tu contraseña actual"
                required
                autocomplete="current-password"
              />
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Nueva contraseña</span>
              </label>
              <input
                type="password"
                name="new_password"
                class="input input-bordered w-full"
                placeholder="Mínimo 8 caracteres"
                required
                autocomplete="new-password"
              />
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Confirmar nueva contraseña</span>
              </label>
              <input
                type="password"
                name="confirm_password"
                class="input input-bordered w-full"
                placeholder="Repite la nueva contraseña"
                required
                autocomplete="new-password"
              />
            </div>

            <div class="flex justify-end pt-1">
              <button type="submit" class="btn btn-primary">
                <.icon name="hero-lock-closed" class="size-4" />
                Actualizar contraseña
              </button>
            </div>
          </form>
        </div>

      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp validate_password_form(current, new, confirm) do
    []
    |> then(fn e ->
      if String.trim(current) == "",
        do: ["Escribe tu contraseña actual." | e],
        else: e
    end)
    |> then(fn e ->
      if String.length(new) < 8,
        do: ["La nueva contraseña debe tener al menos 8 caracteres." | e],
        else: e
    end)
    |> then(fn e ->
      if new != confirm,
        do: ["Las contraseñas nuevas no coinciden." | e],
        else: e
    end)
  end
end
