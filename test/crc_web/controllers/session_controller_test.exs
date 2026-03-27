defmodule CRCWeb.SessionControllerTest do
  use CRCWeb.ConnCase, async: true

  alias CRC.Accounts.User
  alias CRC.Repo

  defp crear_usuario(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Test Admin",
          email: "admin@test.com",
          password: "contraseña123",
          role: "admin"
        },
        overrides
      )

    {:ok, user} =
      %User{}
      |> User.changeset(attrs)
      |> Repo.insert()

    user
  end

  # ---------------------------------------------------------------------------
  # GET /iniciar-sesion
  # ---------------------------------------------------------------------------

  describe "GET /iniciar-sesion" do
    test "muestra el formulario de inicio de sesión", %{conn: conn} do
      conn = get(conn, ~p"/iniciar-sesion")
      assert html_response(conn, 200) =~ "Iniciar sesión"
    end

    test "redirige al panel si ya hay sesión activa (admin)", %{conn: conn} do
      user = crear_usuario()

      conn =
        conn
        |> init_test_session(%{"user_id" => user.id})
        |> get(~p"/iniciar-sesion")

      assert redirected_to(conn) == ~p"/admin"
    end

    test "redirige al inicio si ya hay sesión activa (no-admin)", %{conn: conn} do
      empleado = crear_usuario(%{role: "empleado", station: "sala", email: "emp_redirect#{System.unique_integer()}@test.com"})

      conn =
        conn
        |> init_test_session(%{"user_id" => empleado.id})
        |> get(~p"/iniciar-sesion")

      assert redirected_to(conn) == ~p"/"
    end
  end

  # ---------------------------------------------------------------------------
  # POST /iniciar-sesion
  # ---------------------------------------------------------------------------

  describe "POST /iniciar-sesion" do
    test "inicia sesión con credenciales correctas", %{conn: conn} do
      crear_usuario(%{email: "acceso@test.com"})

      conn =
        post(conn, ~p"/iniciar-sesion", %{
          "email" => "acceso@test.com",
          "password" => "contraseña123"
        })

      assert get_session(conn, "user_id")
      assert redirected_to(conn) == ~p"/admin"
    end

    test "rechaza contraseña incorrecta", %{conn: conn} do
      crear_usuario(%{email: "acceso@test.com"})

      conn =
        post(conn, ~p"/iniciar-sesion", %{
          "email" => "acceso@test.com",
          "password" => "mal_password"
        })

      assert html_response(conn, 200) =~ "Email o contraseña incorrectos"
      refute get_session(conn, "user_id")
    end

    test "rechaza email inexistente", %{conn: conn} do
      conn =
        post(conn, ~p"/iniciar-sesion", %{
          "email" => "noexiste@test.com",
          "password" => "contraseña123"
        })

      assert html_response(conn, 200) =~ "Email o contraseña incorrectos"
      refute get_session(conn, "user_id")
    end

    test "rechaza usuario inactivo", %{conn: conn} do
      admin = crear_usuario()
      empleado = crear_usuario(%{role: "empleado", station: "sala", email: "emp@test.com"})
      CRC.Accounts.deactivate_user(admin, empleado)

      conn =
        post(conn, ~p"/iniciar-sesion", %{
          "email" => "emp@test.com",
          "password" => "contraseña123"
        })

      assert html_response(conn, 200) =~ "desactivada"
      refute get_session(conn, "user_id")
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE /cerrar-sesion
  # ---------------------------------------------------------------------------

  describe "DELETE /cerrar-sesion" do
    test "cierra la sesión y redirige al inicio", %{conn: conn} do
      user = crear_usuario()

      conn =
        conn
        |> init_test_session(%{"user_id" => user.id})
        |> delete(~p"/cerrar-sesion")

      refute get_session(conn, "user_id")
      assert redirected_to(conn) == ~p"/"
    end
  end
end
