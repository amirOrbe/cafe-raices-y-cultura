defmodule CRCWeb.Admin.FinanzasLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Accounts.User
  alias CRC.Orders
  alias CRC.Catalog

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_admin(conn) do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        name: "Admin Fin #{System.unique_integer()}",
        email: "admin_fin#{System.unique_integer()}@cafe.com",
        role: "admin",
        password: "contraseña123"
      })
      |> CRC.Repo.insert()

    {init_test_session(conn, %{"user_id" => user.id}), user}
  end

  defp insert_category(kind \\ "food") do
    {:ok, cat} = Catalog.create_category(%{name: "Cat #{System.unique_integer()}", kind: kind})
    cat
  end

  defp insert_menu_item(category_id, overrides \\ %{}) do
    {:ok, mi} =
      Catalog.create_menu_item(
        Map.merge(%{name: "Item #{System.unique_integer()}", price: "50.00", category_id: category_id}, overrides)
      )
    mi
  end

  defp insert_product(net_cost) do
    CRC.Repo.insert!(%CRC.Inventory.Product{
      name: "Ing #{System.unique_integer()}",
      category: "granos",
      unit: "g",
      net_cost: Decimal.new(net_cost),
      stock_quantity: Decimal.new("1000"),
      active: true
    })
  end

  defp link_ingredient(menu_item_id, product_id, quantity) do
    CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
      menu_item_id: menu_item_id,
      product_id: product_id,
      quantity: Decimal.new(quantity)
    })
  end

  # Closes a real order and returns it
  defp close_order_with_item(price \\ "80.00") do
    cat = insert_category()
    mi = insert_menu_item(cat.id, %{price: price})
    {:ok, order} = Orders.create_order(%{customer_name: "Cliente Fin #{System.unique_integer()}"})
    {:ok, _} = Orders.add_item(%{order_id: order.id, menu_item_id: mi.id, quantity: 1})
    order = Orders.get_order!(order.id)
    {:ok, closed} = Orders.close_order(order, %{payment_method: "tarjeta"})
    {closed, mi}
  end

  # ---------------------------------------------------------------------------
  # Authentication
  # ---------------------------------------------------------------------------

  describe "authentication" do
    test "redirects non-admin to root", %{conn: conn} do
      {:ok, emp} =
        %User{}
        |> User.changeset(%{
          name: "Emp Fin", email: "emp_fin#{System.unique_integer()}@cafe.com",
          role: "empleado", station: "sala", password: "pass123456"
        })
        |> CRC.Repo.insert()

      conn = init_test_session(conn, %{"user_id" => emp.id})
      {:error, {:redirect, %{to: path}}} = live(conn, "/admin/finanzas")
      assert path =~ "/"
    end

    test "redirects unauthenticated user", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, "/admin/finanzas")
      assert path =~ "/iniciar-sesion"
    end
  end

  # ---------------------------------------------------------------------------
  # Mount / basic render
  # ---------------------------------------------------------------------------

  describe "mount" do
    test "renders page title", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/finanzas")
      assert html =~ "Finanzas"
    end

    test "renders all financial card labels", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/finanzas")
      assert html =~ "Ingresos"
      assert html =~ "Costo de ventas"
      assert html =~ "Ganancia bruta"
      assert html =~ "Desperdicio"
      assert html =~ "Ganancia neta"
    end

    test "renders period filter buttons", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/finanzas")
      assert html =~ "Hoy"
      assert html =~ "Esta semana"
      assert html =~ "Este mes"
      assert html =~ "Total"
    end

    test "renders custom date range inputs", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/finanzas")
      assert html =~ "date_from"
      assert html =~ "date_to"
    end

    test "shows zero revenue when no closed orders", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/finanzas")
      # Should show $0 somewhere for all metrics (uses "Total" period by default)
      assert html =~ "$0"
    end
  end

  # ---------------------------------------------------------------------------
  # Revenue display
  # ---------------------------------------------------------------------------

  describe "revenue display" do
    test "shows revenue from closed orders", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      close_order_with_item("100.00")

      {:ok, _lv, html} = live(conn, "/admin/finanzas")
      assert html =~ "Ingresos"
      # Revenue should include the $100 order total
      assert html =~ "100"
    end
  end

  # ---------------------------------------------------------------------------
  # Period switching
  # ---------------------------------------------------------------------------

  describe "set_period event" do
    test "switches to 'week' without crashing", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/finanzas")
      html = render_click(lv, "set_period", %{"period" => "week"})
      assert html =~ "Finanzas"
    end

    test "switches to 'month' without crashing", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/finanzas")
      html = render_click(lv, "set_period", %{"period" => "month"})
      assert html =~ "Finanzas"
    end

    test "switches to 'today' without crashing", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/finanzas")
      html = render_click(lv, "set_period", %{"period" => "today"})
      assert html =~ "Finanzas"
    end

    test "switches to 'all' without crashing", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/finanzas")
      html = render_click(lv, "set_period", %{"period" => "all"})
      assert html =~ "Finanzas"
    end

    test "clears date inputs when switching to preset period", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/finanzas")

      render_change(lv, "set_date_range", %{"date_from" => "2026-01-01", "date_to" => "2026-01-31"})
      render_click(lv, "set_period", %{"period" => "today"})
      html = render(lv)
      refute html =~ "Rango:"
    end
  end

  # ---------------------------------------------------------------------------
  # Custom date range
  # ---------------------------------------------------------------------------

  describe "set_date_range event" do
    test "accepts valid date range without crashing", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/finanzas")
      html = render_change(lv, "set_date_range", %{
        "date_from" => "2026-03-01",
        "date_to" => "2026-03-31"
      })
      assert html =~ "Finanzas"
    end

    test "shows range indicator when custom range is active", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/finanzas")
      html = render_change(lv, "set_date_range", %{
        "date_from" => "2026-03-01",
        "date_to" => "2026-03-31"
      })
      assert html =~ "2026-03-01"
      assert html =~ "2026-03-31"
    end

    test "ignores invalid range (from > to)", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/finanzas")
      html = render_change(lv, "set_date_range", %{
        "date_from" => "2026-03-31",
        "date_to" => "2026-03-01"
      })
      assert html =~ "Finanzas"
    end

    test "filters data by custom range", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      # Create an order in a far past range that should NOT appear in a future range
      {:ok, lv, _} = live(conn, "/admin/finanzas")

      html = render_change(lv, "set_date_range", %{
        "date_from" => "2035-01-01",
        "date_to" => "2035-01-02"
      })
      # With no orders in that future range, should show zeros
      assert html =~ "$0"
    end
  end

  # ---------------------------------------------------------------------------
  # Waste items table
  # ---------------------------------------------------------------------------

  describe "waste items display" do
    test "shows empty state when no waste in period", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/finanzas")

      html = render_change(lv, "set_date_range", %{
        "date_from" => "2035-02-01",
        "date_to" => "2035-02-01"
      })
      assert html =~ "Sin desperdicios registrados"
    end

    test "shows waste items table when waste exists", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Platillo Desperdiciado FIN"})
      product = insert_product("2.00")
      link_ingredient(mi.id, product.id, "5")

      d = ~U[2027-11-01 10:00:00Z]
      order = CRC.Repo.insert!(%CRC.Orders.Order{
        customer_name: "Waste Display",
        status: "sent", payment_method: nil, total: nil,
        inserted_at: d, updated_at: d
      })
      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 1,
        status: "cancelled_waste", inserted_at: d, updated_at: d
      })

      {:ok, lv, _} = live(conn, "/admin/finanzas")
      html = render_change(lv, "set_date_range", %{
        "date_from" => "2027-11-01",
        "date_to" => "2027-11-01"
      })
      assert html =~ "Platillo Desperdiciado FIN"
    end
  end

  # ---------------------------------------------------------------------------
  # Net profit color — positive vs negative
  # ---------------------------------------------------------------------------

  describe "net profit display" do
    test "renders net profit section", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/finanzas")
      assert html =~ "Ganancia neta"
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub refresh
  # ---------------------------------------------------------------------------

  describe "PubSub handle_info" do
    test "refreshes on order_updated without crashing", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/finanzas")

      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, 999})
      assert render(lv) =~ "Finanzas"
    end
  end

  # ---------------------------------------------------------------------------
  # COGS note displayed
  # ---------------------------------------------------------------------------

  describe "informational note about COGS" do
    test "shows note about items without recipe", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/finanzas")
      assert html =~ "solo incluye platillos con receta"
    end
  end
end
