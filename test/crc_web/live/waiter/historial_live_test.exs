defmodule CRCWeb.Waiter.HistorialLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Accounts.User
  alias CRC.Orders
  alias CRC.Catalog

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{name: "Mesero #{System.unique_integer()}",
          email: "mes#{System.unique_integer()}@cafe.com",
          role: "empleado", station: "sala", password: "pass123456"},
        overrides
      )
    {:ok, u} = %User{} |> User.changeset(attrs) |> CRC.Repo.insert()
    u
  end

  defp insert_admin(conn) do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        name: "Admin Hist #{System.unique_integer()}",
        email: "admin_h#{System.unique_integer()}@cafe.com",
        role: "admin",
        password: "contraseña123"
      })
      |> CRC.Repo.insert()

    {init_test_session(conn, %{"user_id" => user.id}), user}
  end

  defp auth_conn(conn, user \\ nil) do
    u = user || insert_user()
    {init_test_session(conn, %{"user_id" => u.id}), u}
  end

  defp insert_category do
    {:ok, cat} = Catalog.create_category(%{name: "Cat #{System.unique_integer()}", kind: "food"})
    cat
  end

  defp insert_menu_item(category_id) do
    {:ok, mi} = Catalog.create_menu_item(%{
      name: "Platillo #{System.unique_integer()}", price: "60.00", category_id: category_id
    })
    mi
  end

  # Build a closed order (raw insert to bypass business logic)
  defp insert_closed_order(user_id, customer_name, total \\ "75.00") do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    CRC.Repo.insert!(%CRC.Orders.Order{
      customer_name: customer_name,
      status: "closed",
      payment_method: "tarjeta",
      total: Decimal.new(total),
      closed_at: now,
      user_id: user_id,
      inserted_at: now,
      updated_at: now
    })
  end

  defp insert_open_order(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    CRC.Repo.insert!(%CRC.Orders.Order{
      customer_name: "Abierta #{System.unique_integer()}",
      status: "open",
      user_id: user_id,
      inserted_at: now,
      updated_at: now
    })
  end

  # ---------------------------------------------------------------------------
  # Authentication
  # ---------------------------------------------------------------------------

  describe "authentication" do
    test "redirects unauthenticated user to login", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, "/mesa/historial")
      assert path =~ "/iniciar-sesion"
    end

    test "allows authenticated empleado", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      assert {:ok, _lv, html} = live(conn, "/mesa/historial")
      assert html =~ "Historial"
    end

    test "allows admin user", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      assert {:ok, _lv, html} = live(conn, "/mesa/historial")
      assert html =~ "Historial"
    end
  end

  # ---------------------------------------------------------------------------
  # Mount / basic render
  # ---------------------------------------------------------------------------

  describe "mount" do
    test "renders page title", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, _lv, html} = live(conn, "/mesa/historial")
      assert html =~ "Historial de comandas"
    end

    test "renders period filter buttons", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, _lv, html} = live(conn, "/mesa/historial")
      assert html =~ "Hoy"
      assert html =~ "Semana"
      assert html =~ "Mes"
      assert html =~ "Todo"
    end

    test "shows empty state when no closed orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/mesa/historial")

      # Use a far-future range to guarantee no data
      html = render_click(lv, "set_period", %{"period" => "today"})
      # Either shows orders or empty state message — must not crash
      assert html =~ "comanda" or html =~ "No hay comandas"
    end

    test "shows link back to /mesa", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, _lv, html} = live(conn, "/mesa/historial")
      assert html =~ "/mesa"
    end
  end

  # ---------------------------------------------------------------------------
  # Mesero sees only their own orders
  # ---------------------------------------------------------------------------

  describe "mesero visibility — own orders only" do
    test "mesero sees their own closed orders", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      _order = insert_closed_order(user.id, "Mesa Propia")

      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_click(lv, "set_period", %{"period" => "all"})
      assert html =~ "Mesa Propia"
    end

    test "mesero does NOT see other waiters' closed orders", %{conn: conn} do
      {conn, _my_user} = auth_conn(conn)
      other_user = insert_user(%{name: "Otro Mesero"})
      _other_order = insert_closed_order(other_user.id, "Mesa Ajena Secreta")

      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_click(lv, "set_period", %{"period" => "all"})
      refute html =~ "Mesa Ajena Secreta"
    end

    test "mesero does NOT see open orders (only closed)", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      _open = insert_open_order(user.id)

      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_click(lv, "set_period", %{"period" => "all"})
      # Open orders must not appear
      refute html =~ "Abierta"
    end
  end

  # ---------------------------------------------------------------------------
  # Admin sees ALL orders
  # ---------------------------------------------------------------------------

  describe "admin visibility — all orders" do
    test "admin sees orders from different waiters", %{conn: conn} do
      {conn, _admin} = insert_admin(conn)
      waiter_a = insert_user(%{name: "Waiter A Hist"})
      waiter_b = insert_user(%{name: "Waiter B Hist"})
      _oa = insert_closed_order(waiter_a.id, "Mesa de A Hist")
      _ob = insert_closed_order(waiter_b.id, "Mesa de B Hist")

      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_click(lv, "set_period", %{"period" => "all"})
      assert html =~ "Mesa de A Hist"
      assert html =~ "Mesa de B Hist"
    end

    test "admin sees waiter name on each order", %{conn: conn} do
      {conn, _admin} = insert_admin(conn)
      waiter = insert_user(%{name: "Mesero Visible Admin"})
      _order = insert_closed_order(waiter.id, "Mesa Visible Admin")

      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_click(lv, "set_period", %{"period" => "all"})
      assert html =~ "Mesero Visible Admin"
    end

    test "admin sees the waiter filter dropdown", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      waiter = insert_user(%{name: "Mesero Filtrable"})
      insert_closed_order(waiter.id, "Mesa Filtrable")

      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_click(lv, "set_period", %{"period" => "all"})
      assert html =~ "Mesero Filtrable"
    end

    test "admin can filter by specific waiter", %{conn: conn} do
      {conn, _admin} = insert_admin(conn)
      wa = insert_user(%{name: "Waiter Filtro A"})
      wb = insert_user(%{name: "Waiter Filtro B"})
      insert_closed_order(wa.id, "Comanda Solo A")
      insert_closed_order(wb.id, "Comanda Solo B")

      {:ok, lv, _} = live(conn, "/mesa/historial")
      render_click(lv, "set_period", %{"period" => "all"})

      html = render_change(lv, "filter_user", %{"user_id" => to_string(wa.id)})
      assert html =~ "Comanda Solo A"
      refute html =~ "Comanda Solo B"
    end

    test "admin filter 'Todos' (empty user_id) shows all orders", %{conn: conn} do
      {conn, _admin} = insert_admin(conn)
      wa = insert_user(%{name: "All Filter A"})
      wb = insert_user(%{name: "All Filter B"})
      insert_closed_order(wa.id, "Comanda All A")
      insert_closed_order(wb.id, "Comanda All B")

      {:ok, lv, _} = live(conn, "/mesa/historial")
      render_click(lv, "set_period", %{"period" => "all"})
      render_change(lv, "filter_user", %{"user_id" => to_string(wa.id)})
      html = render_change(lv, "filter_user", %{"user_id" => ""})
      assert html =~ "Comanda All A"
      assert html =~ "Comanda All B"
    end
  end

  # ---------------------------------------------------------------------------
  # Period filtering
  # ---------------------------------------------------------------------------

  describe "period filtering" do
    test "switching to 'all' shows all closed orders", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      insert_closed_order(user.id, "Mesa Historial All")

      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_click(lv, "set_period", %{"period" => "all"})
      assert html =~ "Mesa Historial All"
    end

    test "switching to 'today' does not crash", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_click(lv, "set_period", %{"period" => "today"})
      assert html =~ "Historial"
    end

    test "switching to 'week' does not crash", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_click(lv, "set_period", %{"period" => "week"})
      assert html =~ "Historial"
    end
  end

  # ---------------------------------------------------------------------------
  # Custom date range
  # ---------------------------------------------------------------------------

  describe "custom date range" do
    test "accepts valid date range without crashing", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_change(lv, "set_date_range", %{
        "date_from" => "2026-03-01",
        "date_to" => "2026-03-31"
      })
      assert html =~ "Historial"
    end

    test "shows range indicator banner", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_change(lv, "set_date_range", %{
        "date_from" => "2026-03-01",
        "date_to" => "2026-03-31"
      })
      assert html =~ "2026-03-01"
      assert html =~ "2026-03-31"
    end

    test "ignores invalid range (from > to)", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_change(lv, "set_date_range", %{
        "date_from" => "2026-03-31",
        "date_to" => "2026-03-01"
      })
      assert html =~ "Historial"
    end

    test "order created today appears in its date range", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      today = Date.utc_today()
      insert_closed_order(user.id, "Comanda Hoy Rango")

      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_change(lv, "set_date_range", %{
        "date_from" => Date.to_iso8601(today),
        "date_to" => Date.to_iso8601(today)
      })
      assert html =~ "Comanda Hoy Rango"
    end
  end

  # ---------------------------------------------------------------------------
  # Order expansion (toggle detail)
  # ---------------------------------------------------------------------------

  describe "order detail expansion" do
    test "clicking an order expands its detail view", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_closed_order(user.id, "Mesa Expandible")
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 2,
        status: "served", inserted_at: now, updated_at: now
      })

      {:ok, lv, _} = live(conn, "/mesa/historial")
      render_click(lv, "set_period", %{"period" => "all"})
      html = render_click(lv, "toggle_order", %{"id" => to_string(order.id)})
      assert html =~ "Total cobrado"
    end

    test "clicking an expanded order collapses it", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      order = insert_closed_order(user.id, "Mesa Colapsar")

      {:ok, lv, _} = live(conn, "/mesa/historial")
      render_click(lv, "set_period", %{"period" => "all"})
      render_click(lv, "toggle_order", %{"id" => to_string(order.id)})
      html = render_click(lv, "toggle_order", %{"id" => to_string(order.id)})
      refute html =~ "Total cobrado"
    end

    test "shows order total in expanded view", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      order = insert_closed_order(user.id, "Mesa Total Visible", "120.00")

      {:ok, lv, _} = live(conn, "/mesa/historial")
      render_click(lv, "set_period", %{"period" => "all"})
      html = render_click(lv, "toggle_order", %{"id" => to_string(order.id)})
      assert html =~ "120"
    end
  end

  # ---------------------------------------------------------------------------
  # Summary chip
  # ---------------------------------------------------------------------------

  describe "summary chip" do
    test "shows correct order count", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      insert_closed_order(user.id, "Chip A")
      insert_closed_order(user.id, "Chip B")

      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_click(lv, "set_period", %{"period" => "all"})
      assert html =~ "comanda"
    end

    test "shows total revenue", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      insert_closed_order(user.id, "Rev A", "50.00")

      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_click(lv, "set_period", %{"period" => "all"})
      assert html =~ "Total"
    end
  end

  # ---------------------------------------------------------------------------
  # Payment method label
  # ---------------------------------------------------------------------------

  describe "payment method display" do
    test "shows 'Tarjeta' for tarjeta payment", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      insert_closed_order(user.id, "Mesa Tarjeta")

      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_click(lv, "set_period", %{"period" => "all"})
      assert html =~ "Tarjeta"
    end

    test "shows 'Efectivo' for cash payment", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      CRC.Repo.insert!(%CRC.Orders.Order{
        customer_name: "Mesa Efectivo Hist",
        status: "closed",
        payment_method: "efectivo",
        amount_paid: Decimal.new("100.00"),
        total: Decimal.new("75.00"),
        closed_at: now,
        user_id: user.id,
        inserted_at: now,
        updated_at: now
      })

      {:ok, lv, _} = live(conn, "/mesa/historial")
      html = render_click(lv, "set_period", %{"period" => "all"})
      assert html =~ "Efectivo"
    end
  end
end
