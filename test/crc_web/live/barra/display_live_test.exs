defmodule CRCWeb.Barra.DisplayLiveTest do
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
        %{name: "Barman", email: "barra#{System.unique_integer()}@cafe.com",
          role: "empleado", station: "barra", password: "pass123456"},
        overrides
      )

    {:ok, user} = %User{} |> User.changeset(attrs) |> CRC.Repo.insert()
    user
  end

  defp auth_conn(conn) do
    user = insert_user()
    {init_test_session(conn, %{"user_id" => user.id}), user}
  end

  defp insert_category(kind \\ "drink") do
    {:ok, cat} = Catalog.create_category(%{name: "Cat #{System.unique_integer()}", kind: kind})
    cat
  end

  defp insert_menu_item(category_id, name \\ "Bebida") do
    {:ok, item} = Catalog.create_menu_item(%{name: name, price: "60.00", category_id: category_id})
    item
  end

  defp insert_order(overrides \\ %{}) do
    {:ok, order} = Orders.create_order(Map.merge(%{customer_name: "Test"}, overrides))
    order
  end

  defp insert_order_item(order_id, menu_item_id, overrides \\ %{}) do
    {:ok, item} =
      Orders.add_item(Map.merge(%{order_id: order_id, menu_item_id: menu_item_id, quantity: 1}, overrides))

    item
  end

  # ---------------------------------------------------------------------------
  # Authentication
  # ---------------------------------------------------------------------------

  describe "authentication" do
    test "redirects to login when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, "/barra")
      assert path =~ "/iniciar-sesion"
    end
  end

  # ---------------------------------------------------------------------------
  # Empty state
  # ---------------------------------------------------------------------------

  describe "empty state" do
    test "shows no-orders message when nothing is sent", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "No hay bebidas pendientes"
    end

    test "does not show open (unsent) orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id)
      order = insert_order(%{status: "open"})
      insert_order_item(order.id, mi.id, %{status: "pending"})
      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "No hay bebidas pendientes"
    end
  end

  # ---------------------------------------------------------------------------
  # Drink-only filtering
  # ---------------------------------------------------------------------------

  describe "drink filtering" do
    test "shows drink items from sent orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Café de olla")
      order = insert_order(%{customer_name: "Mesa 5", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "Café de olla"
      assert html =~ "Mesa 5"
    end

    test "does NOT show food items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      food_cat = insert_category("food")
      food_mi = insert_menu_item(food_cat.id, "Chilaquiles")
      order = insert_order(%{customer_name: "Solo Comida", status: "sent"})
      insert_order_item(order.id, food_mi.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/barra")
      refute html =~ "Chilaquiles"
      refute html =~ "Solo Comida"
    end

    test "does NOT show pending (not yet sent) drink items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Agua fresca")
      order = insert_order(%{customer_name: "Sin Enviar", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "pending"})
      {:ok, _lv, html} = live(conn, "/barra")
      refute html =~ "Agua fresca"
    end

    test "shows multiple drink items from the same order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi1 = insert_menu_item(drink_cat.id, "Limonada")
      mi2 = insert_menu_item(drink_cat.id, "Jamaica")
      order = insert_order(%{customer_name: "Dos Bebidas", status: "sent"})
      insert_order_item(order.id, mi1.id, %{status: "sent"})
      insert_order_item(order.id, mi2.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "Limonada"
      assert html =~ "Jamaica"
    end
  end

  # ---------------------------------------------------------------------------
  # mark_item_ready
  # ---------------------------------------------------------------------------

  describe "mark_item_ready" do
    test "marks drink item as ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Horchata")
      order = insert_order(%{customer_name: "Lista", status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/barra")

      render_click(lv, "mark_item_ready", %{"id" => to_string(item.id)})

      reloaded = Orders.get_order!(order.id)
      assert hd(reloaded.order_items).status == "ready"
    end

    test "removes drink from queue after marking it ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Tepache")
      order = insert_order(%{customer_name: "Listo Ya", status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/barra")

      html = render_click(lv, "mark_item_ready", %{"id" => to_string(item.id)})
      # Item moves to "ready" — disappears from the bar queue
      refute html =~ "Tepache"
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  describe "PubSub" do
    test "refreshes when order_updated is broadcast", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, html} = live(conn, "/barra")
      assert html =~ "No hay bebidas pendientes"

      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Michelada")
      order = insert_order(%{customer_name: "PubSub Barra", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})

      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, order.id})

      html = render(lv)
      assert html =~ "Michelada"
    end
  end

  # ---------------------------------------------------------------------------
  # Mixed order (food + drinks) — barra only sees drinks
  # ---------------------------------------------------------------------------

  describe "mixed order" do
    test "barra only shows drink items from a mixed order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      food_cat = insert_category("food")
      drink_cat = insert_category("drink")
      food_mi = insert_menu_item(food_cat.id, "Pozole")
      drink_mi = insert_menu_item(drink_cat.id, "Agua de tamarindo")
      order = insert_order(%{customer_name: "Mixto", status: "sent"})
      insert_order_item(order.id, food_mi.id, %{status: "sent"})
      insert_order_item(order.id, drink_mi.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/barra")
      refute html =~ "Pozole"
      assert html =~ "Agua de tamarindo"
    end
  end

  describe "nav events" do
    test "toggle_nav opens and closes nav", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/barra")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "toggle_nav", %{})
      assert render(lv) =~ "Barra"
    end

    test "close_nav closes nav", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/barra")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "close_nav", %{})
      assert render(lv) =~ "Barra"
    end
  end

  describe "mark_item_ready error path" do
    test "handles item not found gracefully", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/barra")

      # Should not crash when item id doesn't exist
      html = render_click(lv, "mark_item_ready", %{"id" => "0"})
      assert html =~ "Barra"
    end
  end

  describe "drink item with ready status" do
    test "does NOT show already-ready drinks in the pending queue", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Agua Lista")
      order = insert_order(%{customer_name: "Bebida Lista", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "ready"})

      {:ok, _lv, html} = live(conn, "/barra")
      # Already-ready drinks must not resurface in the bar queue
      refute html =~ "Agua Lista"
    end
  end

  # ---------------------------------------------------------------------------
  # Bug regression: second-batch sends must not resurface already-ready drinks
  # ---------------------------------------------------------------------------

  describe "second batch does not resurface ready drinks (Bug 1)" do
    test "only shows newly-sent drinks when a second batch arrives", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi1 = insert_menu_item(drink_cat.id, "Limonada Servida")
      mi2 = insert_menu_item(drink_cat.id, "Horchata Nueva")
      order = insert_order(%{customer_name: "Mesa Segundas Barra", status: "sent"})

      # First batch: mi1 already served (ready)
      insert_order_item(order.id, mi1.id, %{status: "ready"})
      # Second batch: mi2 newly sent
      insert_order_item(order.id, mi2.id, %{status: "sent"})

      {:ok, _lv, html} = live(conn, "/barra")

      assert html =~ "Horchata Nueva"
      refute html =~ "Limonada Servida"
    end

    test "order disappears from barra when all drinks are marked ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Café Final")
      order = insert_order(%{customer_name: "Solo Barra", status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/barra")

      html = render_click(lv, "mark_item_ready", %{"id" => to_string(item.id)})
      refute html =~ "Solo Barra"
    end
  end

  # ---------------------------------------------------------------------------
  # Bug regression: barra must show orders whose status advanced to "ready"
  # while a drink item is still "sent" (Bug 2)
  # ---------------------------------------------------------------------------

  describe "pending drinks visible when order status is ready (Bug 2)" do
    test "shows order in barra if a drink is still sent, even when order.status == ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Refresco Pendiente")
      # Simulate: kitchen used mark_order_ready while 1 drink was still "sent"
      order = insert_order(%{customer_name: "Orden Casi Lista", status: "ready"})
      insert_order_item(order.id, mi.id, %{status: "sent"})

      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "Refresco Pendiente"
    end

    test "partial mark: 3 of 4 drinks ready — remaining sent drink still shows", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi_a = insert_menu_item(drink_cat.id, "Bebida A")
      mi_b = insert_menu_item(drink_cat.id, "Bebida B")
      mi_c = insert_menu_item(drink_cat.id, "Bebida C")
      mi_d = insert_menu_item(drink_cat.id, "Bebida D Pendiente")
      order = insert_order(%{customer_name: "Cuatro Bebidas", status: "sent"})
      insert_order_item(order.id, mi_a.id, %{status: "ready"})
      insert_order_item(order.id, mi_b.id, %{status: "ready"})
      insert_order_item(order.id, mi_c.id, %{status: "ready"})
      insert_order_item(order.id, mi_d.id, %{status: "sent"})

      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "Bebida D Pendiente"
      refute html =~ "Bebida A"
      refute html =~ "Bebida B"
      refute html =~ "Bebida C"
    end

    test "order disappears from barra once all drinks (including last one) are ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Última Bebida")
      order = insert_order(%{customer_name: "Última Mesa", status: "ready"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/barra")

      html = render_click(lv, "mark_item_ready", %{"id" => to_string(item.id)})
      refute html =~ "Última Bebida"
      refute html =~ "Última Mesa"
    end
  end

  describe "pedido/pedidos pluralization" do
    test "shows pedido (singular) for one pending drink order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Bebida Singular")
      order = insert_order(%{customer_name: "Solo Uno", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})

      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "pedido"
    end
  end

  describe "drink item with notes" do
    test "shows item notes when present", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      mi = insert_menu_item(drink_cat.id, "Café con instrucciones")
      order = insert_order(%{customer_name: "Con Notas Barra", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent", notes: "sin azúcar"})

      {:ok, _lv, html} = live(conn, "/barra")
      assert html =~ "sin azúcar"
    end
  end
end
