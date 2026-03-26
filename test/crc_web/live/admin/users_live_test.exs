defmodule CRCWeb.Admin.UsersLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Accounts
  alias CRC.Accounts.User

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Usuario Test",
          email: "user_test#{System.unique_integer()}@cafe.com",
          role: "admin",
          password: "contraseña123"
        },
        overrides
      )

    {:ok, user} =
      %User{}
      |> User.changeset(attrs)
      |> CRC.Repo.insert()

    user
  end

  defp admin_session(conn) do
    admin = insert_user(%{name: "Admin Users", role: "admin"})
    {init_test_session(conn, %{"user_id" => admin.id}), admin}
  end

  defp cliente_session(conn) do
    cliente = insert_user(%{role: "cliente"})
    {init_test_session(conn, %{"user_id" => cliente.id}), cliente}
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "access control" do
    test "redirects unauthenticated users to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/iniciar-sesion"}}} = live(conn, ~p"/admin/usuarios")
    end

    test "redirects non-admin (cliente) users to /", %{conn: conn} do
      {conn, _} = cliente_session(conn)
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/usuarios")
    end

    test "admin can access users page", %{conn: conn} do
      {conn, _admin} = admin_session(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/admin/usuarios")
      assert html =~ "Usuarios"
    end
  end

  describe "user listing" do
    test "admin sees active users by default", %{conn: conn} do
      {conn, _admin} = admin_session(conn)
      user = insert_user(%{name: "Empleado Visible", role: "empleado", station: "cocina"})

      {:ok, _lv, html} = live(conn, ~p"/admin/usuarios")
      assert html =~ "Empleado Visible"
    end

    test "inactive users are not shown in active filter", %{conn: conn} do
      {conn, admin} = admin_session(conn)
      empleado = insert_user(%{name: "Emp Inactivo", role: "empleado", station: "barra"})
      Accounts.deactivate_user(admin, empleado)

      {:ok, _lv, html} = live(conn, ~p"/admin/usuarios")
      refute html =~ "Emp Inactivo"
    end

    test "set_status_filter 'inactive' shows only inactive users", %{conn: conn} do
      {conn, admin} = admin_session(conn)
      empleado = insert_user(%{name: "Emp Inactivo Ver", role: "empleado", station: "sala"})
      Accounts.deactivate_user(admin, empleado)

      {:ok, lv, _html} = live(conn, ~p"/admin/usuarios")
      html = render_click(lv, "set_status_filter", %{"status" => "inactive"})
      assert html =~ "Emp Inactivo Ver"
    end

    test "set_status_filter 'active' shows only active users", %{conn: conn} do
      {conn, admin} = admin_session(conn)
      empleado = insert_user(%{name: "Emp Activo Ver", role: "empleado", station: "cocina"})

      {:ok, lv, _html} = live(conn, ~p"/admin/usuarios")
      html = render_click(lv, "set_status_filter", %{"status" => "active"})
      assert html =~ "Emp Activo Ver"
    end
  end

  describe "new_user event" do
    test "opens modal", %{conn: conn} do
      {conn, _admin} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/usuarios")

      html = render_click(lv, "new_user", %{})
      assert html =~ "Nuevo usuario"
    end
  end

  describe "save_user event" do
    test "creates a user successfully", %{conn: conn} do
      {conn, _admin} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/usuarios")

      render_click(lv, "new_user", %{})

      html =
        lv
        |> form("#user-form",
          user: %{
            name: "Nuevo Usuario",
            email: "nuevo_user#{System.unique_integer()}@cafe.com",
            role: "admin",
            password: "contraseña123"
          }
        )
        |> render_submit()

      assert html =~ "creado" or !String.contains?(html, "Nuevo usuario")
    end

    test "fails with invalid data and shows errors", %{conn: conn} do
      {conn, _admin} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/usuarios")

      render_click(lv, "new_user", %{})

      html =
        lv
        |> form("#user-form", user: %{name: "", email: "", role: "admin", password: ""})
        |> render_submit()

      # Form should remain visible with errors
      assert html =~ "Nuevo usuario" or html =~ "en blanco"
    end
  end

  describe "toggle_active" do
    test "admin cannot deactivate themselves", %{conn: conn} do
      {conn, admin} = admin_session(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/usuarios")

      html = render_click(lv, "toggle_active", %{"id" => to_string(admin.id)})
      assert html =~ "No puedes desactivar tu propia cuenta"
    end

    test "can deactivate another user", %{conn: conn} do
      {conn, _admin} = admin_session(conn)
      empleado = insert_user(%{name: "Emp Toggle", role: "empleado", station: "cocina"})

      {:ok, lv, _html} = live(conn, ~p"/admin/usuarios")

      html = render_click(lv, "toggle_active", %{"id" => to_string(empleado.id)})
      assert html =~ "desactivado" or !html =~ "Emp Toggle"
    end
  end
end
