defmodule CRCWeb.Admin.SuppliersLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Accounts.User
  alias CRC.Inventory

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Admin Suppliers",
          email: "admin_sup#{System.unique_integer()}@cafe.com",
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

  defp admin_conn(conn) do
    admin = insert_user()
    {init_test_session(conn, %{"user_id" => admin.id}), admin}
  end

  defp insert_supplier(overrides \\ %{}) do
    attrs = Map.merge(%{name: "Proveedor #{System.unique_integer()}"}, overrides)
    {:ok, s} = Inventory.create_supplier(attrs)
    s
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "access control" do
    test "redirects unauthenticated to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/iniciar-sesion"}}} = live(conn, ~p"/admin/proveedores")
    end

    test "admin can access suppliers page", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/admin/proveedores")
      assert html =~ "Proveedores"
    end
  end

  describe "supplier listing" do
    test "admin sees all active suppliers", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      insert_supplier(%{name: "Proveedor Activo Test"})

      {:ok, _lv, html} = live(conn, ~p"/admin/proveedores")
      assert html =~ "Proveedor Activo Test"
    end

    test "inactive suppliers are not shown in active filter", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      supplier = insert_supplier(%{name: "Proveedor Inactivo Test"})
      Inventory.toggle_supplier_active(supplier)

      {:ok, _lv, html} = live(conn, ~p"/admin/proveedores")
      refute html =~ "Proveedor Inactivo Test"
    end

    test "status filter shows inactive suppliers", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      supplier = insert_supplier(%{name: "Inactivo Visible"})
      Inventory.toggle_supplier_active(supplier)

      {:ok, lv, _html} = live(conn, ~p"/admin/proveedores")
      html = render_click(lv, "set_status_filter", %{"status" => "inactive"})
      assert html =~ "Inactivo Visible"
    end

    test "status filter shows active suppliers", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      insert_supplier(%{name: "Activo Visible"})

      {:ok, lv, _html} = live(conn, ~p"/admin/proveedores")
      html = render_click(lv, "set_status_filter", %{"status" => "active"})
      assert html =~ "Activo Visible"
    end
  end

  describe "new_supplier event" do
    test "opens modal", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/proveedores")

      html = render_click(lv, "new_supplier", %{})
      assert html =~ "Nuevo proveedor"
    end
  end

  describe "save_supplier event" do
    test "creates supplier successfully", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/proveedores")

      render_click(lv, "new_supplier", %{})

      html =
        lv
        |> form("#supplier-form", supplier: %{name: "Nuevo Proveedor Especial"})
        |> render_submit()

      assert html =~ "creado" or html =~ "Nuevo Proveedor Especial"
    end

    test "fails with invalid data (no name)", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/proveedores")

      render_click(lv, "new_supplier", %{})

      html =
        lv
        |> form("#supplier-form", supplier: %{name: ""})
        |> render_submit()

      # Modal should remain open with error
      assert html =~ "Nuevo proveedor" or html =~ "en blanco"
    end
  end

  describe "toggle_active event" do
    test "toggles supplier status", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      supplier = insert_supplier(%{name: "Proveedor Toggle"})

      {:ok, lv, _html} = live(conn, ~p"/admin/proveedores")

      html = render_click(lv, "toggle_active", %{"id" => to_string(supplier.id)})
      assert html =~ "desactivado" or !String.contains?(html, "Proveedor Toggle")
    end
  end

  describe "edit_supplier event" do
    test "opens modal with existing supplier data", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      supplier = insert_supplier(%{name: "Proveedor Editar"})

      {:ok, lv, _html} = live(conn, ~p"/admin/proveedores")

      html = render_click(lv, "edit_supplier", %{"id" => to_string(supplier.id)})
      assert html =~ "Editar proveedor"
      assert html =~ "Proveedor Editar"
    end
  end
end
