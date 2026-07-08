defmodule CRCWeb.Client.RegistrationLive do
  use CRCWeb, :live_view

  alias CRC.Accounts
  alias CRC.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    changeset = User.registration_changeset(%User{}, %{})

    {:ok,
     assign(socket,
       form: to_form(changeset, as: "user"),
       page_title: "Crear cuenta"
     )}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      %User{}
      |> User.registration_changeset(params)
      |> maybe_add_confirmation_error(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
  end

  @impl true
  def handle_event("save", %{"user" => params}, socket) do
    if passwords_match?(params) do
      case Accounts.register_client(params) do
        {:ok, _user} ->
          {:noreply,
           socket
           |> put_flash(:info, "¡Cuenta creada! Revisa tu correo para confirmarla.")
           |> redirect(to: "/iniciar-sesion")}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
      end
    else
      changeset =
        %User{}
        |> User.registration_changeset(params)
        |> maybe_add_confirmation_error(params)
        |> Map.put(:action, :validate)

      {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
    end
  end

  defp passwords_match?(params) do
    Map.get(params, "password") == Map.get(params, "password_confirmation")
  end

  defp maybe_add_confirmation_error(changeset, params) do
    if passwords_match?(params) do
      changeset
    else
      Ecto.Changeset.add_error(
        changeset,
        :password_confirmation,
        "las contraseñas no coinciden"
      )
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 flex items-center justify-center px-4 py-10">
      <div class="w-full max-w-md">
        <div class="mb-4 text-center">
          <a href="/" class="text-sm text-base-content/50 hover:text-base-content/70 transition-colors">
            ← Volver al menú
          </a>
        </div>

        <div class="card bg-base-100 shadow-md border border-base-300">
          <div class="card-body">
            <div class="text-center mb-4">
              <h1 class="text-2xl font-bold text-base-content">Crea tu cuenta</h1>
              <p class="text-sm text-base-content/60 mt-1">
                Únete a Café Raíces y Cultura
              </p>
            </div>

            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-1">
              <.input
                field={@form[:name]}
                type="text"
                label="Nombre completo"
                autocomplete="name"
                required
              />

              <.input
                field={@form[:email]}
                type="email"
                label="Correo electrónico"
                autocomplete="email"
                required
              />

              <.input
                field={@form[:phone]}
                type="text"
                label="Teléfono"
                placeholder="10 dígitos"
                autocomplete="tel"
              />

              <.input
                field={@form[:birthday]}
                type="date"
                label="Fecha de nacimiento"
              />

              <.input
                field={@form[:password]}
                type="password"
                label="Contraseña"
                autocomplete="new-password"
                minlength="8"
                required
              />

              <.input
                field={@form[:password_confirmation]}
                type="password"
                label="Confirmar contraseña"
                autocomplete="new-password"
                minlength="8"
                required
              />

              <button type="submit" class="btn btn-primary w-full mt-4">
                Crear cuenta
              </button>
            </.form>

            <p class="text-center text-sm text-base-content/60 mt-4">
              ¿Ya tienes cuenta?
              <a href="/iniciar-sesion" class="link link-primary font-medium">
                Inicia sesión
              </a>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
