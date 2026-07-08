defmodule CRCWeb.ForgotPasswordLive do
  use CRCWeb, :live_view

  alias CRC.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{"email" => ""}), submitted: false)}
  end

  @impl true
  def handle_event("submit", %{"email" => email}, socket) do
    Accounts.request_password_reset(email)
    {:noreply, assign(socket, submitted: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 flex items-center justify-center px-4">
      <div class="w-full max-w-sm">
        <div class="flex justify-center mb-8">
          <a href="/">
            <img src="/images/brand/logo-color.png" alt="Café Raíces y Cultura" class="h-16 w-auto" />
          </a>
        </div>

        <div class="bg-base-100 rounded-2xl shadow-md border border-base-300 p-8">
          <%= if @submitted do %>
            <div class="text-center space-y-4">
              <div class="w-14 h-14 bg-success/10 rounded-full flex items-center justify-center mx-auto">
                <.icon name="hero-envelope" class="size-7 text-success" />
              </div>
              <h1 class="text-xl font-bold text-base-content">Revisa tu correo</h1>
              <p class="text-sm text-base-content/60 leading-relaxed">
                Si existe una cuenta con ese correo, recibirás un enlace para restablecer tu contraseña.
                El enlace es válido por <strong>1 hora</strong>.
              </p>
              <a href="/iniciar-sesion" class="btn btn-primary w-full mt-2">
                Volver al inicio de sesión
              </a>
            </div>
          <% else %>
            <h1 class="text-xl font-bold text-base-content mb-1">Recuperar contraseña</h1>
            <p class="text-sm text-base-content/60 mb-6">
              Ingresa tu correo y te enviaremos un enlace para crear una nueva contraseña.
            </p>

            <.form for={@form} phx-submit="submit" class="space-y-4">
              <div class="form-control">
                <label class="label pb-1">
                  <span class="label-text font-medium">Correo electrónico</span>
                </label>
                <input
                  type="email"
                  name="email"
                  placeholder="tu@correo.com"
                  autocomplete="email"
                  required
                  class="input input-bordered w-full"
                />
              </div>

              <button type="submit" class="btn btn-primary w-full mt-2">
                Enviar enlace
              </button>
            </.form>
          <% end %>
        </div>

        <p class="text-center text-xs text-base-content/40 mt-6">
          <a href="/iniciar-sesion" class="hover:text-base-content/60 transition-colors">
            ← Volver al inicio de sesión
          </a>
        </p>
      </div>
    </div>
    """
  end
end
