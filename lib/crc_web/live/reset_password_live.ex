defmodule CRCWeb.ResetPasswordLive do
  use CRCWeb, :live_view

  alias CRC.Accounts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Phoenix.Token.verify(CRCWeb.Endpoint, "password_reset", token, max_age: 3600) do
      {:ok, _user_id} ->
        {:ok, assign(socket, token: token, form: to_form(%{}), done: false, error: nil)}

      {:error, _} ->
        {:ok, assign(socket, token: nil, form: to_form(%{}), done: false, error: :invalid)}
    end
  end

  @impl true
  def handle_event("submit", %{"password" => password, "password_confirmation" => confirmation}, socket) do
    if password != confirmation do
      {:noreply, assign(socket, error: :mismatch)}
    else
      case Accounts.reset_password_by_token(socket.assigns.token, password) do
        {:ok, _user} ->
          {:noreply, assign(socket, done: true, error: nil)}

        {:error, :invalid_token} ->
          {:noreply, assign(socket, error: :invalid)}

        {:error, changeset} ->
          errors = changeset.errors |> Enum.map(fn {_field, {msg, _}} -> msg end)
          {:noreply, assign(socket, error: {:validation, errors})}
      end
    end
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
          <%= cond do %>
            <% @error == :invalid -> %>
              <div class="text-center space-y-4">
                <div class="w-14 h-14 bg-error/10 rounded-full flex items-center justify-center mx-auto">
                  <.icon name="hero-x-circle" class="size-7 text-error" />
                </div>
                <h1 class="text-xl font-bold text-base-content">Enlace inválido</h1>
                <p class="text-sm text-base-content/60 leading-relaxed">
                  Este enlace ha expirado o ya fue usado. Los enlaces son válidos por 1 hora.
                </p>
                <a href="/recuperar-contrasena" class="btn btn-primary w-full">
                  Solicitar nuevo enlace
                </a>
              </div>

            <% @done -> %>
              <div class="text-center space-y-4">
                <div class="w-14 h-14 bg-success/10 rounded-full flex items-center justify-center mx-auto">
                  <.icon name="hero-check-circle" class="size-7 text-success" />
                </div>
                <h1 class="text-xl font-bold text-base-content">Contraseña actualizada</h1>
                <p class="text-sm text-base-content/60">
                  Tu contraseña ha sido restablecida correctamente.
                </p>
                <a href="/iniciar-sesion" class="btn btn-primary w-full">
                  Iniciar sesión
                </a>
              </div>

            <% true -> %>
              <h1 class="text-xl font-bold text-base-content mb-1">Nueva contraseña</h1>
              <p class="text-sm text-base-content/60 mb-6">Elige una contraseña segura de al menos 8 caracteres.</p>

              <%= if @error == :mismatch do %>
                <div class="alert alert-error mb-5 text-sm py-3">
                  <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                  <span>Las contraseñas no coinciden.</span>
                </div>
              <% end %>

              <%= if match?({:validation, _}, @error) do %>
                <% {:validation, msgs} = @error %>
                <div class="alert alert-error mb-5 text-sm py-3">
                  <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                  <span>{Enum.join(msgs, ", ")}</span>
                </div>
              <% end %>

              <.form for={@form} phx-submit="submit" class="space-y-4">
                <div class="form-control">
                  <label class="label pb-1">
                    <span class="label-text font-medium">Nueva contraseña</span>
                  </label>
                  <input
                    type="password"
                    name="password"
                    placeholder="••••••••"
                    autocomplete="new-password"
                    required
                    minlength="8"
                    class="input input-bordered w-full"
                  />
                </div>

                <div class="form-control">
                  <label class="label pb-1">
                    <span class="label-text font-medium">Confirmar contraseña</span>
                  </label>
                  <input
                    type="password"
                    name="password_confirmation"
                    placeholder="••••••••"
                    autocomplete="new-password"
                    required
                    minlength="8"
                    class="input input-bordered w-full"
                  />
                </div>

                <button type="submit" class="btn btn-primary w-full mt-2">
                  Guardar contraseña
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
