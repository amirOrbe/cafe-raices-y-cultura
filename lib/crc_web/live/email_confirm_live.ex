defmodule CRCWeb.EmailConfirmLive do
  @moduledoc """
  Handles email address confirmation via a signed token.

  Users arrive here by clicking the link in their welcome email.
  The token is signed with Phoenix.Token and expires after 7 days.
  Confirming the email sets `confirmed_at` on the user record but
  does NOT affect login access — it is purely informational.
  """

  use CRCWeb, :live_view

  alias CRC.Accounts

  # Token max age: 7 days in seconds
  @token_max_age 7 * 24 * 3600

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    result =
      case Phoenix.Token.verify(CRCWeb.Endpoint, "email_confirm", token,
             max_age: @token_max_age
           ) do
        {:ok, user_id} -> confirm_user(user_id)
        {:error, :expired} -> {:error, :expired}
        {:error, _} -> {:error, :invalid}
      end

    socket =
      socket
      |> assign(:page_title, "Confirmar correo")
      |> assign(:result, result)

    {:ok, socket}
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Confirmar correo")
     |> assign(:result, {:error, :invalid})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 flex items-center justify-center px-4">
      <div class="bg-base-100 rounded-2xl shadow-sm border border-base-300 p-10 max-w-md w-full text-center">

        <%= case @result do %>
          <% {:ok, user} -> %>
            <div class="w-16 h-16 rounded-full bg-success/15 flex items-center justify-center mx-auto mb-6">
              <.icon name="hero-check-circle" class="size-10 text-success" />
            </div>
            <h1 class="text-xl font-bold text-base-content mb-2">
              ¡Correo confirmado!
            </h1>
            <p class="text-base-content/60 text-sm mb-6">
              Hola, <strong class="text-base-content">{user.name}</strong>.
              Tu dirección de correo ha sido verificada correctamente.
            </p>
            <a href="/iniciar-sesion" class="btn btn-primary btn-sm">
              Iniciar sesión
            </a>

          <% {:error, :already_confirmed} -> %>
            <div class="w-16 h-16 rounded-full bg-info/15 flex items-center justify-center mx-auto mb-6">
              <.icon name="hero-information-circle" class="size-10 text-info" />
            </div>
            <h1 class="text-xl font-bold text-base-content mb-2">
              Ya confirmado
            </h1>
            <p class="text-base-content/60 text-sm mb-6">
              Este correo ya había sido confirmado anteriormente. No necesitas hacer nada más.
            </p>
            <a href="/" class="btn btn-ghost btn-sm">Ir al inicio</a>

          <% {:error, :expired} -> %>
            <div class="w-16 h-16 rounded-full bg-warning/15 flex items-center justify-center mx-auto mb-6">
              <.icon name="hero-clock" class="size-10 text-warning" />
            </div>
            <h1 class="text-xl font-bold text-base-content mb-2">
              Enlace expirado
            </h1>
            <p class="text-base-content/60 text-sm">
              El enlace de confirmación venció (tiene validez de 7 días).
              Pide a un administrador que reenvíe el correo de bienvenida.
            </p>

          <% {:error, _} -> %>
            <div class="w-16 h-16 rounded-full bg-error/15 flex items-center justify-center mx-auto mb-6">
              <.icon name="hero-x-circle" class="size-10 text-error" />
            </div>
            <h1 class="text-xl font-bold text-base-content mb-2">
              Enlace inválido
            </h1>
            <p class="text-base-content/60 text-sm">
              El enlace de confirmación no es válido o ya fue utilizado.
              Pide a un administrador que reenvíe el correo de bienvenida.
            </p>
        <% end %>

      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp confirm_user(user_id) do
    case Accounts.get_user(user_id) do
      nil ->
        {:error, :invalid}

      %{confirmed_at: confirmed_at} when not is_nil(confirmed_at) ->
        {:error, :already_confirmed}

      user ->
        Accounts.confirm_user_email(user)
    end
  end
end
