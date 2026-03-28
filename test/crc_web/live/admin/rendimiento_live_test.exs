defmodule CRCWeb.Admin.RendimientoLiveTest do
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
        name: "Admin Rend #{System.unique_integer()}",
        email: "admin_r#{System.unique_integer()}@cafe.com",
        role: "admin",
        password: "contraseña123"
      })
      |> CRC.Repo.insert()

    {init_test_session(conn, %{"user_id" => user.id}), user}
  end

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{name: "Staff #{System.unique_integer()}",
          email: "staff#{System.unique_integer()}@cafe.com",
          role: "empleado", station: "cocina", password: "pass123456"},
        overrides
      )
    {:ok, u} = %User{} |> User.changeset(attrs) |> CRC.Repo.insert()
    u
  end

  defp insert_category(kind \\ "food") do
    {:ok, cat} = Catalog.create_category(%{name: "Cat #{System.unique_integer()}", kind: kind})
    cat
  end

  defp insert_menu_item(category_id) do
    {:ok, mi} = Catalog.create_menu_item(%{
      name: "Item #{System.unique_integer()}", price: "60.00", category_id: category_id
    })
    mi
  end

  # Insert a closed order with a timed item to generate stats
  defp insert_stat_order(waiter, kitchen_staff) do
    cat = insert_category()
    mi = insert_menu_item(cat.id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    sent_at  = DateTime.add(now, -600, :second)
    ready_at = DateTime.add(now, -300, :second)
    inserted_at = DateTime.add(now, -900, :second)

    order = CRC.Repo.insert!(%CRC.Orders.Order{
      customer_name: "Stat Order #{System.unique_integer()}",
      status: "closed",
      payment_method: "tarjeta",
      total: Decimal.new("60.00"),
      closed_at: now,
      user_id: waiter.id,
      closed_by_id: waiter.id,
      inserted_at: inserted_at,
      updated_at: now
    })

    CRC.Repo.insert!(%CRC.Orders.OrderItem{
      order_id: order.id,
      menu_item_id: mi.id,
      quantity: 1,
      status: "ready",
      sent_at: sent_at,
      ready_at: ready_at,
      marked_ready_by_id: kitchen_staff.id,
      inserted_at: inserted_at,
      updated_at: now
    })

    order
  end

  # ---------------------------------------------------------------------------
  # Authentication
  # ---------------------------------------------------------------------------

  describe "authentication" do
    test "redirects non-admin to root", %{conn: conn} do
      {:ok, user} =
        %User{}
        |> User.changeset(%{
          name: "Emp", email: "emp_rend#{System.unique_integer()}@cafe.com",
          role: "empleado", station: "sala", password: "pass123456"
        })
        |> CRC.Repo.insert()

      conn = init_test_session(conn, %{"user_id" => user.id})
      {:error, {:redirect, %{to: path}}} = live(conn, "/admin/rendimiento")
      assert path =~ "/"
    end

    test "redirects unauthenticated user", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, "/admin/rendimiento")
      assert path =~ "/iniciar-sesion"
    end
  end

  # ---------------------------------------------------------------------------
  # Mount / basic render
  # ---------------------------------------------------------------------------

  describe "mount" do
    test "renders page title", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/rendimiento")
      assert html =~ "Rendimiento"
    end

    test "renders period filter buttons", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/rendimiento")
      assert html =~ "Hoy"
      assert html =~ "Esta semana"
      assert html =~ "Este mes"
      assert html =~ "Total"
    end

    test "renders custom date range inputs", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/rendimiento")
      assert html =~ "date_from"
      assert html =~ "date_to"
    end

    test "shows empty state message when no data", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/rendimiento")
      assert html =~ "No hay datos de rendimiento"
    end
  end

  # ---------------------------------------------------------------------------
  # Period switching
  # ---------------------------------------------------------------------------

  describe "set_period event" do
    test "switches period to 'week'", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/rendimiento")

      html = render_click(lv, "set_period", %{"period" => "week"})
      # Week button should now be active (btn-primary)
      assert html =~ "Esta semana"
    end

    test "switches period to 'month'", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/rendimiento")

      render_click(lv, "set_period", %{"period" => "month"})
      html = render(lv)
      assert html =~ "Este mes"
    end

    test "switches period to 'all'", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/rendimiento")

      render_click(lv, "set_period", %{"period" => "all"})
      html = render(lv)
      assert html =~ "Total"
    end

    test "clears date_from and date_to when switching to preset period", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/rendimiento")

      # First set a custom range
      render_change(lv, "set_date_range", %{"date_from" => "2026-01-01", "date_to" => "2026-01-31"})
      # Then switch to preset
      render_click(lv, "set_period", %{"period" => "today"})

      html = render(lv)
      # Range indicator should disappear
      refute html =~ "Rango personalizado activo"
    end
  end

  # ---------------------------------------------------------------------------
  # REGRESSION Bug #1: to_string crash on {:range, date, date} tuple
  # ---------------------------------------------------------------------------

  describe "period button rendering with tuple period (Bug #1 regression)" do
    test "custom date range does NOT crash the page", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/rendimiento")

      # Setting a date range stores period = {:range, date, date} in socket
      # This must NOT crash when rendering the period buttons
      assert render_change(lv, "set_date_range", %{
               "date_from" => "2026-03-01",
               "date_to" => "2026-03-31"
             }) =~ "Rendimiento"
    end

    test "custom date range shows range indicator banner", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/rendimiento")

      html = render_change(lv, "set_date_range", %{
        "date_from" => "2026-03-01",
        "date_to" => "2026-03-31"
      })

      assert html =~ "2026-03-01"
      assert html =~ "2026-03-31"
    end

    test "preset period buttons render without crash after custom range was set", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/rendimiento")

      # Set custom range first
      render_change(lv, "set_date_range", %{
        "date_from" => "2026-03-01",
        "date_to" => "2026-03-31"
      })

      # Then switch back to atom period — must not crash
      html = render_click(lv, "set_period", %{"period" => "week"})
      assert html =~ "Rendimiento"
      assert html =~ "Esta semana"
    end

    test "invalid date range is silently ignored (no crash)", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/rendimiento")

      # date_from after date_to → should be ignored
      html = render_change(lv, "set_date_range", %{
        "date_from" => "2026-03-31",
        "date_to" => "2026-03-01"
      })

      assert html =~ "Rendimiento"
    end
  end

  # ---------------------------------------------------------------------------
  # Stats rendering with data
  # ---------------------------------------------------------------------------

  describe "stats display" do
    test "shows station stats when kitchen staff has marked items ready", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      waiter  = insert_user(%{station: "sala"})
      kitchen = insert_user(%{name: "Carlos Cocina #{System.unique_integer()}", station: "cocina"})
      insert_stat_order(waiter, kitchen)

      {:ok, _lv, html} = live(conn, "/admin/rendimiento")
      assert html =~ kitchen.name
    end

    test "shows waiter stats when waiter has closed orders", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      waiter  = insert_user(%{name: "Ana Mesera #{System.unique_integer()}", station: "sala"})
      kitchen = insert_user(%{station: "cocina"})
      insert_stat_order(waiter, kitchen)

      {:ok, _lv, html} = live(conn, "/admin/rendimiento")
      assert html =~ waiter.name
    end

    test "employee does not appear when no orders in selected period", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      waiter  = insert_user(%{name: "Invisible Mesero #{System.unique_integer()}", station: "sala"})
      kitchen = insert_user(%{station: "cocina"})
      insert_stat_order(waiter, kitchen)

      {:ok, lv, _} = live(conn, "/admin/rendimiento")

      # Far-future range → no data
      html = render_change(lv, "set_date_range", %{
        "date_from" => "2035-01-01",
        "date_to" => "2035-01-02"
      })
      assert html =~ "No hay datos de rendimiento"
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub refresh
  # ---------------------------------------------------------------------------

  describe "PubSub handle_info" do
    test "refreshes stats on order_updated broadcast", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/rendimiento")

      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, 999})
      # Should not crash after receiving PubSub message
      assert render(lv) =~ "Rendimiento"
    end
  end
end
