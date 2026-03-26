defmodule CRCWeb.Admin.ProductsLiveTest do
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
          name: "Admin Products",
          email: "admin_prod#{System.unique_integer()}@cafe.com",
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
    attrs = Map.merge(%{name: "Proveedor Prod #{System.unique_integer()}"}, overrides)
    {:ok, s} = Inventory.create_supplier(attrs)
    s
  end

  defp insert_product(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Insumo Test #{System.unique_integer()}",
          category: "lacteos",
          unit: "litros",
          net_cost: "25.00",
          stock_quantity: "10.0",
          min_stock: "2.0"
        },
        overrides
      )

    {:ok, p} = Inventory.create_product(attrs)
    p
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "access control" do
    test "redirects unauthenticated to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/iniciar-sesion"}}} = live(conn, ~p"/admin/insumos")
    end

    test "admin can access products page", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/admin/insumos")
      assert html =~ "Insumos"
    end
  end

  describe "product listing" do
    test "admin sees all active products", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      insert_product(%{name: "Leche Entera Test"})

      {:ok, _lv, html} = live(conn, ~p"/admin/insumos")
      assert html =~ "Leche Entera Test"
    end

    test "inactive products are not shown in active filter", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      product = insert_product(%{name: "Insumo Inactivo Test"})
      Inventory.toggle_product_active(product)

      {:ok, _lv, html} = live(conn, ~p"/admin/insumos")
      refute html =~ "Insumo Inactivo Test"
    end

    test "status filter shows inactive products", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      product = insert_product(%{name: "Insumo Inactivo Ver"})
      Inventory.toggle_product_active(product)

      {:ok, lv, _html} = live(conn, ~p"/admin/insumos")
      html = render_click(lv, "set_status_filter", %{"status" => "inactive"})
      assert html =~ "Insumo Inactivo Ver"
    end
  end

  describe "category filter" do
    test "filter_category filters by category", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      insert_product(%{name: "Café Especial", category: "granos"})
      insert_product(%{name: "Leche Especial", category: "lacteos"})

      {:ok, lv, _html} = live(conn, ~p"/admin/insumos")

      html = render_click(lv, "filter_category", %{"category" => "granos"})
      assert html =~ "Café Especial"
      refute html =~ "Leche Especial"
    end

    test "filter_category 'all' shows all products", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      insert_product(%{name: "Café Granos", category: "granos"})
      insert_product(%{name: "Leche Lácteos", category: "lacteos"})

      {:ok, lv, _html} = live(conn, ~p"/admin/insumos")

      html = render_click(lv, "filter_category", %{"category" => "all"})
      assert html =~ "Café Granos"
      assert html =~ "Leche Lácteos"
    end
  end

  describe "new_product event" do
    test "opens modal", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/insumos")

      html = render_click(lv, "new_product", %{})
      assert html =~ "Nuevo insumo"
    end
  end

  describe "save_product event" do
    test "creates product successfully", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      supplier = insert_supplier()
      {:ok, lv, _html} = live(conn, ~p"/admin/insumos")

      render_click(lv, "new_product", %{})

      html =
        lv
        |> form("#product-form",
          product: %{
            name: "Nuevo Insumo Especial",
            category: "alimentos",
            unit: "kilogramos",
            net_cost: "50.00",
            stock_quantity: "5.0",
            min_stock: "1.0",
            supplier_id: supplier.id
          }
        )
        |> render_submit()

      assert html =~ "creado" or html =~ "Nuevo Insumo Especial"
    end

    test "fails with invalid data", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/insumos")

      render_click(lv, "new_product", %{})

      html =
        lv
        |> form("#product-form", product: %{name: ""})
        |> render_submit()

      # Modal should remain or show errors
      assert html =~ "Nuevo insumo" or html =~ "en blanco"
    end
  end

  describe "toggle_active event" do
    test "toggles product active status", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      product = insert_product(%{name: "Insumo Toggle"})

      {:ok, lv, _html} = live(conn, ~p"/admin/insumos")

      html = render_click(lv, "toggle_active", %{"id" => to_string(product.id)})
      assert html =~ "desactivado" or !String.contains?(html, "Insumo Toggle")
    end
  end
end
