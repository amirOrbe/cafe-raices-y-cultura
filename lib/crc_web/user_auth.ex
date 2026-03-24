defmodule CRCWeb.UserAuth do
  @moduledoc """
  Plug y helpers de autenticación para controllers y LiveViews.

  ## Uso en controllers (router)

      pipeline :browser do
        plug :fetch_current_user
      end

      pipeline :require_auth do
        plug :require_authenticated_user
      end

  ## Uso en LiveViews

      on_mount {CRCWeb.UserAuth, :fetch_current_user}
      on_mount {CRCWeb.UserAuth, :require_authenticated_user}
      on_mount {CRCWeb.UserAuth, :require_admin}
  """

  import Plug.Conn
  import Phoenix.Controller

  alias CRC.Accounts

  @session_key "user_id"

  # ---------------------------------------------------------------------------
  # Plugs para el pipeline del router
  # ---------------------------------------------------------------------------

  @doc "Carga el usuario actual desde la sesión y lo asigna como :current_user."
  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, @session_key)
    assign(conn, :current_user, user_id && Accounts.get_user(user_id))
  end

  @doc "Redirige a /iniciar-sesion si no hay sesión activa."
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Debes iniciar sesión para continuar.")
      |> redirect(to: "/iniciar-sesion")
      |> halt()
    end
  end

  @doc "Redirige al inicio si el usuario no tiene rol admin."
  def require_admin(conn, _opts) do
    case conn.assigns[:current_user] do
      %{role: "admin"} ->
        conn

      _ ->
        conn
        |> put_flash(:error, "No tienes permiso para acceder a esta sección.")
        |> redirect(to: "/")
        |> halt()
    end
  end

  @doc "Redirige según rol si ya hay una sesión activa (para la página de login)."
  def redirect_if_authenticated(conn, _opts) do
    case conn.assigns[:current_user] do
      %{role: "admin"} ->
        conn |> redirect(to: "/admin") |> halt()

      %{} ->
        conn |> redirect(to: "/") |> halt()

      _ ->
        conn
    end
  end

  # ---------------------------------------------------------------------------
  # Manejo de sesión
  # ---------------------------------------------------------------------------

  @doc "Inicia sesión: guarda el user_id en sesión y redirige al panel."
  def log_in_user(conn, user) do
    conn
    |> renew_session()
    |> put_session(@session_key, user.id)
    |> redirect(to: "/admin")
  end

  @doc "Cierra sesión: limpia la sesión y redirige al inicio."
  def log_out_user(conn) do
    conn
    |> renew_session()
    |> redirect(to: "/")
  end

  # ---------------------------------------------------------------------------
  # on_mount para LiveViews
  # ---------------------------------------------------------------------------

  @doc false
  def on_mount(:fetch_current_user, _params, session, socket) do
    {:cont, assign_current_user(socket, session)}
  end

  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket = assign_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "Debes iniciar sesión para continuar.")
        |> Phoenix.LiveView.redirect(to: "/iniciar-sesion")

      {:halt, socket}
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    socket = assign_current_user(socket, session)

    case socket.assigns.current_user do
      %{role: "admin"} ->
        {:cont, socket}

      _ ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "No tienes permiso para acceder a esta sección.")
          |> Phoenix.LiveView.redirect(to: "/")

        {:halt, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers privados
  # ---------------------------------------------------------------------------

  defp assign_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      user_id = session[@session_key]
      user_id && Accounts.get_user(user_id)
    end)
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
