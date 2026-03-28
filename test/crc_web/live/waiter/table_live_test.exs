defmodule CRCWeb.Waiter.TableLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Accounts.User
  alias CRC.Orders

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{name: "Waiter", email: "waiter#{System.unique_integer()}@cafe.com",
          role: "empleado", station: "sala", password: "pass123456"},
        overrides
      )

    {:ok, user} = %User{} |> User.changeset(attrs) |> CRC.Repo.insert()
    user
  end

  defp auth_conn(conn, role \\ "empleado") do
    user = insert_user(%{role: role})
    {init_test_session(conn, %{"user_id" => user.id}), user}
  end

  defp insert_order(overrides \\ %{}) do
    {:ok, order} = Orders.create_order(Map.merge(%{customer_name: "Juan"}, overrides))
    order
  end

  # ---------------------------------------------------------------------------
  # Authentication
  # ---------------------------------------------------------------------------

  describe "authentication" do
    test "redirects to login when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, "/mesa")
      assert path =~ "/iniciar-sesion"
    end
  end

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  describe "mount" do
    test "shows empty state when no active orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "No hay comandas abiertas"
    end

    test "shows active open orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      insert_order(%{customer_name: "Sofía", status: "open"})
      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "Sofía"
    end

    test "shows sent orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      insert_order(%{customer_name: "Carlos", status: "sent"})
      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "Carlos"
    end

    test "shows ready orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      insert_order(%{customer_name: "María", status: "ready"})
      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "María"
    end

    test "does not show closed orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      insert_order(%{customer_name: "Cerrado", status: "closed"})
      {:ok, _lv, html} = live(conn, "/mesa")
      refute html =~ "Cerrado"
    end

    test "shows correct status badge for sent order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      insert_order(%{customer_name: "Pedro", status: "sent"})
      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "En cocina"
    end

    test "shows correct status badge for ready order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      insert_order(%{customer_name: "Ana", status: "ready"})
      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "Lista"
    end
  end

  # ---------------------------------------------------------------------------
  # Nueva cuenta modal
  # ---------------------------------------------------------------------------

  describe "nueva cuenta modal" do
    test "opens modal on button click", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _html} = live(conn, "/mesa")

      html = lv |> render_click("open_new_modal")
      assert html =~ "Nueva cuenta"
      assert html =~ "Nombre del cliente"
    end

    test "closes modal on cancel", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _html} = live(conn, "/mesa")

      lv |> render_click("open_new_modal")
      html = lv |> render_click("close_modal")
      refute html =~ "Nombre del cliente"
    end

    test "shows validation error when submitting empty name", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _html} = live(conn, "/mesa")

      lv |> render_click("open_new_modal")
      html = lv |> render_submit("create_cuenta", %{"customer_name" => "   "})
      assert html =~ "El nombre no puede estar vacío"
    end

    test "creates cuenta and redirects to order page", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _html} = live(conn, "/mesa")

      lv |> render_click("open_new_modal")
      assert {:error, {:live_redirect, %{to: path}}} =
               lv |> render_submit("create_cuenta", %{"customer_name" => "Luis"})

      assert path =~ "/mesa/"
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub updates
  # ---------------------------------------------------------------------------

  describe "PubSub" do
    test "refreshes list when order_updated is broadcast", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _html} = live(conn, "/mesa")

      order = insert_order(%{customer_name: "PubSub Test"})
      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, order.id})

      html = render(lv)
      assert html =~ "PubSub Test"
    end
  end

  describe "nav events" do
    test "toggle_nav opens and closes nav", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/mesa")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "toggle_nav", %{})
      assert render(lv) =~ "Comandas"
    end

    test "close_nav closes nav", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/mesa")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "close_nav", %{})
      assert render(lv) =~ "Comandas"
    end
  end

  describe "update_name event" do
    test "update_name tracks the input value", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/mesa")

      lv |> render_click("open_new_modal")
      lv |> render_change("update_name", %{"value" => "Luis Pérez"})
      assert render(lv) =~ "Luis Pérez"
    end
  end

  # ---------------------------------------------------------------------------
  # Visual indicators: overdue, drinks-ready, all-ready
  # ---------------------------------------------------------------------------

  describe "overdue indicator" do
    test "shows +15 min badge when sent item has sent_at > 15 min ago", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      alias CRC.Catalog

      {:ok, cat} = Catalog.create_category(%{name: "Cat Overdue", kind: "food"})
      {:ok, mi} = Catalog.create_menu_item(%{name: "Platillo Lento", price: "80.00", category_id: cat.id})
      order = insert_order(%{customer_name: "Overdue Test", status: "sent"})

      old_sent_at = DateTime.utc_now() |> DateTime.add(-20 * 60, :second) |> DateTime.truncate(:second)
      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id,
        quantity: 1, status: "sent", sent_at: old_sent_at,
        inserted_at: old_sent_at, updated_at: old_sent_at
      })

      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "+15 min"
    end

    test "does not show +15 min badge for recently sent items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      alias CRC.Catalog

      {:ok, cat} = Catalog.create_category(%{name: "Cat Fresh", kind: "food"})
      {:ok, mi} = Catalog.create_menu_item(%{name: "Platillo Rapido", price: "80.00", category_id: cat.id})
      order = insert_order(%{customer_name: "Fresh Test", status: "sent"})

      recent_sent_at = DateTime.utc_now() |> DateTime.add(-5 * 60, :second) |> DateTime.truncate(:second)
      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id,
        quantity: 1, status: "sent", sent_at: recent_sent_at,
        inserted_at: recent_sent_at, updated_at: recent_sent_at
      })

      {:ok, _lv, html} = live(conn, "/mesa")
      refute html =~ "+15 min"
    end
  end

  describe "drinks-ready indicator" do
    test "shows Bebidas listas badge when drinks ready but food pending", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      alias CRC.Catalog

      {:ok, drink_cat} = Catalog.create_category(%{name: "Bebidas Test", kind: "drink"})
      {:ok, food_cat}  = Catalog.create_category(%{name: "Comida Test", kind: "food"})
      {:ok, mi_drink}  = Catalog.create_menu_item(%{name: "Refresco", price: "30.00", category_id: drink_cat.id})
      {:ok, mi_food}   = Catalog.create_menu_item(%{name: "Taco", price: "60.00", category_id: food_cat.id})

      order = insert_order(%{customer_name: "Drinks Ready", status: "sent"})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi_drink.id,
        quantity: 1, status: "ready", sent_at: now, ready_at: now,
        inserted_at: now, updated_at: now
      })
      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi_food.id,
        quantity: 1, status: "sent", sent_at: now,
        inserted_at: now, updated_at: now
      })

      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "Bebidas listas"
    end

    test "does not show Bebidas listas when food is also ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      alias CRC.Catalog

      {:ok, drink_cat} = Catalog.create_category(%{name: "Beb All Ready", kind: "drink"})
      {:ok, food_cat}  = Catalog.create_category(%{name: "Com All Ready", kind: "food"})
      {:ok, mi_drink}  = Catalog.create_menu_item(%{name: "Agua", price: "20.00", category_id: drink_cat.id})
      {:ok, mi_food}   = Catalog.create_menu_item(%{name: "Sopa", price: "50.00", category_id: food_cat.id})

      order = insert_order(%{customer_name: "All Ready", status: "ready"})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi_drink.id,
        quantity: 1, status: "ready", sent_at: now, ready_at: now,
        inserted_at: now, updated_at: now
      })
      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi_food.id,
        quantity: 1, status: "ready", sent_at: now, ready_at: now,
        inserted_at: now, updated_at: now
      })

      {:ok, _lv, html} = live(conn, "/mesa")
      refute html =~ "Bebidas listas"
      assert html =~ "Lista para servir"
    end
  end

  describe "order item count on cards" do
    test "shows Sin artículos when order has no items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      insert_order(%{customer_name: "Sin Items"})
      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "Sin artículos"
    end

    test "shows singular artículo when order has exactly 1 item", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      alias CRC.Catalog

      {:ok, cat} = Catalog.create_category(%{name: "Test Cat", kind: "drink"})
      {:ok, mi} = Catalog.create_menu_item(%{name: "Solo Uno", price: "45.00", category_id: cat.id})
      order = insert_order(%{customer_name: "Un Item"})
      Orders.add_item(%{order_id: order.id, menu_item_id: mi.id, quantity: 1})

      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "artículo"
    end

    test "shows plural artículos when order has 2+ items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      alias CRC.Catalog

      {:ok, cat} = Catalog.create_category(%{name: "Test Cat2", kind: "drink"})
      {:ok, mi1} = Catalog.create_menu_item(%{name: "Bebida A", price: "30.00", category_id: cat.id})
      {:ok, mi2} = Catalog.create_menu_item(%{name: "Bebida B", price: "35.00", category_id: cat.id})
      order = insert_order(%{customer_name: "Dos Items"})
      Orders.add_item(%{order_id: order.id, menu_item_id: mi1.id, quantity: 1})
      Orders.add_item(%{order_id: order.id, menu_item_id: mi2.id, quantity: 1})

      {:ok, _lv, html} = live(conn, "/mesa")
      assert html =~ "artículos"
    end
  end
end
