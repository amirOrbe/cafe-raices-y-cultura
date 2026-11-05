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
      empleado =
        crear_usuario(%{
          role: "empleado",
          stations: ["sala"],
          email: "emp_redirect#{System.unique_integer()}@test.com"
        })

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
      empleado = crear_usuario(%{role: "empleado", stations: ["sala"], email: "emp@test.com"})
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

  describe "límite de intentos de login" do
    @throttle_message "Demasiados intentos"

    defp intento(ip, email, password) do
      build_conn()
      |> put_req_header("fly-client-ip", ip)
      |> post(~p"/iniciar-sesion", %{"email" => email, "password" => password})
    end

    defp ip_unica, do: "198.51.100.#{System.unique_integer([:positive])}"
    defp correo_unico, do: "limite#{System.unique_integer([:positive])}@example.com"

    test "bloquea un correo tras 10 fallos, aun desde otra IP y con la contraseña correcta" do
      email = crear_usuario(%{email: correo_unico()}).email

      for _ <- 1..10, do: intento(ip_unica(), email, "contraseña-mala-123")

      conn = intento(ip_unica(), email, "contraseña123")

      refute get_session(conn, "user_id")
      assert html_response(conn, 200) =~ @throttle_message
    end

    test "bloquea una IP tras 20 fallos, aunque cambie de correo" do
      ip = ip_unica()

      for _ <- 1..20, do: intento(ip, correo_unico(), "contraseña-mala-123")

      conn = intento(ip, correo_unico(), "contraseña-mala-123")

      assert html_response(conn, 200) =~ @throttle_message
    end

    test "un login correcto no consume intentos" do
      email = crear_usuario(%{email: correo_unico()}).email
      ip = ip_unica()

      for _ <- 1..12 do
        conn = intento(ip, email, "contraseña123")
        assert get_session(conn, "user_id")
      end
    end
  end
end
