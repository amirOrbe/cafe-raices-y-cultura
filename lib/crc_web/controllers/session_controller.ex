defmodule CRCWeb.SessionController do
  @moduledoc "Handles login and logout for staff members."
  use CRCWeb, :controller

  alias CRC.Accounts
  alias CRCWeb.UserAuth

  def new(conn, _params), do: render(conn, :new, error: nil)

  def create(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Bienvenido, #{user.name}.")
        |> UserAuth.log_in_user(user)

      {:error, :inactive_user} ->
        render(conn, :new,
          error: "Tu cuenta está desactivada. Contacta al administrador."
        )

      {:error, :invalid_credentials} ->
        render(conn, :new, error: "Email o contraseña incorrectos.")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Sesión cerrada.")
    |> UserAuth.log_out_user()
  end
end
