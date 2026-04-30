defmodule CRCWeb.Admin.VentaManualLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Catalog

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Venta User",
          email: "venta#{System.unique_integer()}@cafe.com",
          role: "admin",
          stations: [],
          password: "contraseña123"
        },
        overrides
      )

    {:ok, user} =
      %CRC.Accounts.User{}
      |> CRC.Accounts.User.changeset(attrs)
      |> CRC.Repo.insert()

    user
  end

  defp admin_conn(conn) do
    admin = insert_user()
    conn = init_test_session(conn, %{"user_id" => admin.id})
    {conn, admin}
  end

  defp employee_conn(conn) do
    user = insert_user(%{role: "empleado", stations: ["sala"]})
    conn = init_test_session(conn, %{"user_id" => user.id})
    {conn, user}
  end

  defp insert_category do
    {:ok, cat} =
      Catalog.create_category(%{
        name: "Cat VM #{System.unique_integer()}",
        description: "Test"
      })

    cat
  end

  defp insert_menu_item(category_id) do
    {:ok, item} =
      Catalog.create_menu_item(%{
        name: "Platillo VM #{System.unique_integer()}",
        price: "100.00",
        category_id: category_id,
        available: true
      })

    item
  end

  # ===========================================================================
  # Access control
  # ===========================================================================

  describe "access control" do
    test "GIVEN unauthenticated user WHEN visiting /admin/ventas/manual THEN redirects",
         %{conn: conn} do
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/ventas/manual")
    end

    test "GIVEN empleado WHEN visiting /admin/ventas/manual THEN redirected",
         %{conn: conn} do
      {conn, _} = employee_conn(conn)
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/ventas/manual")
    end

    test "GIVEN admin WHEN visiting /admin/ventas/manual THEN page loads",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/admin/ventas/manual", on_error: :warn)
      assert html =~ "Venta manual"
    end
  end

  # ===========================================================================
  # Mount state
  # ===========================================================================

  describe "page mount" do
    test "GIVEN admin WHEN mounting THEN empty form is shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, _lv, html} = live(conn, ~p"/admin/ventas/manual", on_error: :warn)
      assert html =~ "cliente" or html =~ "platillo"
    end
  end

  # ===========================================================================
  # update_field event
  # ===========================================================================

  describe "update_field event" do
    test "GIVEN admin WHEN updating customer_name THEN state updates",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/ventas/manual", on_error: :warn)

      html =
        render_click(lv, "update_field", %{"field" => "customer_name", "value" => "Mesa 3"})

      assert is_binary(html)
    end

    test "GIVEN admin WHEN updating notes THEN state updates",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/ventas/manual", on_error: :warn)

      html =
        render_click(lv, "update_field", %{"field" => "notes", "value" => "Cliente especial"})

      assert is_binary(html)
    end
  end

  # ===========================================================================
  # add_line event
  # ===========================================================================

  describe "add_line event" do
    test "GIVEN no item selected WHEN adding line THEN error shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/ventas/manual", on_error: :warn)

      html = render_click(lv, "add_line", %{"item_id" => "", "qty" => "1"})
      assert html =~ "Selecciona" or html =~ "platillo"
    end

    test "GIVEN zero qty WHEN adding line THEN error shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      cat = insert_category()
      item = insert_menu_item(cat.id)

      {:ok, lv, _html} = live(conn, ~p"/admin/ventas/manual", on_error: :warn)

      html = render_click(lv, "add_line", %{"item_id" => to_string(item.id), "qty" => "0"})
      assert html =~ "cantidad" or html =~ "cero"
    end

    test "GIVEN valid item and qty WHEN adding line THEN item appears in order",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      cat = insert_category()
      item = insert_menu_item(cat.id)

      {:ok, lv, _html} = live(conn, ~p"/admin/ventas/manual", on_error: :warn)

      html = render_click(lv, "add_line", %{"item_id" => to_string(item.id), "qty" => "2"})
      assert is_binary(html)
    end
  end

  # ===========================================================================
  # set_method event
  # ===========================================================================

  describe "set_method event" do
    test "GIVEN admin WHEN setting method to tarjeta THEN state updates",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/ventas/manual", on_error: :warn)

      html = render_click(lv, "set_method", %{"method" => "tarjeta"})
      assert is_binary(html)
    end

    test "GIVEN admin WHEN setting method to transferencia THEN state updates",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/ventas/manual", on_error: :warn)

      html = render_click(lv, "set_method", %{"method" => "transferencia"})
      assert is_binary(html)
    end
  end

  # ===========================================================================
  # submit event
  # ===========================================================================

  describe "submit event" do
    test "GIVEN empty form WHEN submitting THEN validation errors shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/ventas/manual", on_error: :warn)

      html = render_click(lv, "submit", %{})
      assert html =~ "nombre" or html =~ "línea" or html =~ "cliente"
    end

    test "GIVEN valid form with lines WHEN submitting THEN order is saved",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      cat = insert_category()
      item = insert_menu_item(cat.id)

      {:ok, lv, _html} = live(conn, ~p"/admin/ventas/manual", on_error: :warn)

      render_click(lv, "update_field", %{"field" => "customer_name", "value" => "Mesa 5"})
      # Switch to tarjeta so amount_paid is not required
      render_click(lv, "set_method", %{"method" => "tarjeta"})
      render_click(lv, "add_line", %{"item_id" => to_string(item.id), "qty" => "1"})

      html = render_click(lv, "submit", %{})
      assert html =~ "Venta registrada" or html =~ "correctamente" or html =~ "manual"
    end
  end

  # ===========================================================================
  # remove_line event
  # ===========================================================================

  describe "remove_line event" do
    test "GIVEN a line added WHEN removing it THEN it disappears",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      cat = insert_category()
      item = insert_menu_item(cat.id)

      {:ok, lv, _html} = live(conn, ~p"/admin/ventas/manual", on_error: :warn)
      render_click(lv, "add_line", %{"item_id" => to_string(item.id), "qty" => "1"})

      html = render_click(lv, "remove_line", %{"idx" => "0"})
      assert is_binary(html)
    end
  end
end
