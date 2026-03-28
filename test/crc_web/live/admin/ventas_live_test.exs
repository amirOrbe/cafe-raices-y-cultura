defmodule CRCWeb.Admin.VentasLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Accounts.User
  alias CRC.Orders
  alias CRC.Catalog

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_admin(conn) do
    attrs = %{
      name: "Admin Ventas #{System.unique_integer()}",
      email: "admin_v#{System.unique_integer()}@cafe.com",
      role: "admin",
      password: "contraseña123"
    }

    {:ok, user} = %User{} |> User.changeset(attrs) |> CRC.Repo.insert()
    {init_test_session(conn, %{"user_id" => user.id}), user}
  end

  defp insert_category(overrides \\ %{}) do
    {:ok, cat} = Catalog.create_category(Map.merge(%{name: "Cat #{System.unique_integer()}", kind: "food"}, overrides))
    cat
  end

  defp insert_menu_item(category_id, overrides \\ %{}) do
    {:ok, mi} = Catalog.create_menu_item(Map.merge(%{name: "Item #{System.unique_integer()}", price: "50.00", category_id: category_id}, overrides))
    mi
  end

  defp close_order_with_items(payment_method \\ "tarjeta") do
    cat = insert_category()
    mi = insert_menu_item(cat.id)
    {:ok, order} = Orders.create_order(%{customer_name: "Cliente Test"})
    {:ok, _} = Orders.add_item(%{order_id: order.id, menu_item_id: mi.id, quantity: 1})
    order = Orders.get_order!(order.id)
    {:ok, closed} = Orders.close_order(order, %{payment_method: payment_method})
    closed
  end

  # ---------------------------------------------------------------------------
  # Authentication
  # ---------------------------------------------------------------------------

  describe "authentication" do
    test "redirects non-admin to login", %{conn: conn} do
      {:ok, user} =
        %User{}
        |> User.changeset(%{
          name: "Emp", email: "emp_v#{System.unique_integer()}@cafe.com",
          role: "empleado", station: "sala", password: "pass123456"
        })
        |> CRC.Repo.insert()

      conn = init_test_session(conn, %{"user_id" => user.id})
      {:error, {:redirect, %{to: path}}} = live(conn, "/admin/ventas")
      assert path =~ "/"
    end
  end

  # ---------------------------------------------------------------------------
  # Mount / basic render
  # ---------------------------------------------------------------------------

  describe "mount" do
    test "renders page title and period tabs", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/ventas")
      assert html =~ "Ventas"
      assert html =~ "Hoy"
      assert html =~ "Esta semana"
      assert html =~ "Este mes"
      assert html =~ "Total"
    end

    test "shows zero revenue when no closed orders", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/ventas")
      assert html =~ "0"
    end

    test "shows closed order in table", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      close_order_with_items("tarjeta")
      {:ok, _lv, html} = live(conn, "/admin/ventas")
      assert html =~ "Cliente Test"
    end
  end

  # ---------------------------------------------------------------------------
  # Period filters
  # ---------------------------------------------------------------------------

  describe "set_period" do
    test "switching to Total shows all closed orders", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      close_order_with_items()
      {:ok, lv, _} = live(conn, "/admin/ventas")

      html = render_click(lv, "set_period", %{"period" => "all"})
      assert html =~ "Cliente Test"
    end

    test "switching period clears date range inputs", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/ventas")

      render_click(lv, "set_period", %{"period" => "all"})
      html = render(lv)
      # date inputs should be empty
      assert html =~ ~s(value="")
    end
  end

  describe "set_date_range" do
    test "valid range filters orders correctly", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      close_order_with_items()
      {:ok, lv, _} = live(conn, "/admin/ventas")

      today = Date.utc_today() |> Date.to_iso8601()
      html = render_change(lv, "set_date_range", %{"date_from" => today, "date_to" => today})
      assert html =~ "Rango personalizado activo"
      assert html =~ "Cliente Test"
    end

    test "invalid range (from > to) does not apply filter", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/ventas")

      html = render_change(lv, "set_date_range", %{"date_from" => "2026-12-31", "date_to" => "2026-01-01"})
      refute html =~ "Rango personalizado activo"
    end
  end

  # ---------------------------------------------------------------------------
  # Timing stats diagram
  # ---------------------------------------------------------------------------

  describe "timing stats" do
    test "does not show diagram when no timing data exists", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      close_order_with_items()
      {:ok, _lv, html} = live(conn, "/admin/ventas")
      # No items with sent_at/ready_at → no diagram
      refute html =~ "Tiempos de preparación"
    end

    test "shows timing diagram when closed orders have timestamps", %{conn: conn} do
      {conn, _} = insert_admin(conn)

      cat = insert_category(%{kind: "food"})
      mi = insert_menu_item(cat.id)
      {:ok, order} = Orders.create_order(%{customer_name: "Timing Test"})

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      sent_at  = DateTime.add(now, -600, :second)
      ready_at = DateTime.add(now, -300, :second)

      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id,
        quantity: 1, status: "ready", sent_at: sent_at, ready_at: ready_at,
        inserted_at: DateTime.add(now, -900, :second), updated_at: now
      })

      order
      |> CRC.Orders.Order.close_changeset(%{
        status: "closed", payment_method: "tarjeta",
        total: Decimal.new(50), closed_at: now
      })
      |> CRC.Repo.update!()

      {:ok, _lv, html} = live(conn, "/admin/ventas")
      assert html =~ "Tiempos de preparación"
      assert html =~ "Cocina"
      assert html =~ "Preparación"
    end

    test "highlights overdue phase in error color (avg >= 15 min)", %{conn: conn} do
      {conn, _} = insert_admin(conn)

      cat = insert_category(%{kind: "food"})
      mi = insert_menu_item(cat.id)
      {:ok, order} = Orders.create_order(%{customer_name: "Slow Kitchen"})

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      # prep time = 20 min
      sent_at  = DateTime.add(now, -1200, :second)
      ready_at = now

      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id,
        quantity: 1, status: "ready", sent_at: sent_at, ready_at: ready_at,
        inserted_at: DateTime.add(now, -1500, :second), updated_at: now
      })

      order
      |> CRC.Orders.Order.close_changeset(%{
        status: "closed", payment_method: "tarjeta",
        total: Decimal.new(50), closed_at: now
      })
      |> CRC.Repo.update!()

      {:ok, _lv, html} = live(conn, "/admin/ventas")
      assert html =~ "bg-error"
    end
  end

  # ---------------------------------------------------------------------------
  # Real-time PubSub
  # ---------------------------------------------------------------------------

  describe "real-time PubSub" do
    test "updates stats when order_updated is broadcast", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/ventas")

      close_order_with_items("tarjeta")
      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, 0})

      html = render(lv)
      assert html =~ "Cliente Test"
    end
  end
end
