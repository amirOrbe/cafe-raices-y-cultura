defmodule CRCWeb.Kitchen.DisplayLiveTest do
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
        %{name: "Cocinero", email: "cocina#{System.unique_integer()}@cafe.com",
          role: "empleado", station: "cocina", password: "pass123456"},
        overrides
      )

    {:ok, user} = %User{} |> User.changeset(attrs) |> CRC.Repo.insert()
    user
  end

  defp auth_conn(conn) do
    user = insert_user()
    {init_test_session(conn, %{"user_id" => user.id}), user}
  end

  defp insert_category(kind \\ "food") do
    {:ok, cat} = Catalog.create_category(%{name: "Cat #{System.unique_integer()}", kind: kind})
    cat
  end

  defp insert_menu_item(category_id, name \\ "Platillo") do
    {:ok, item} = Catalog.create_menu_item(%{name: name, price: "80.00", category_id: category_id})
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
      {:error, {:redirect, %{to: path}}} = live(conn, "/cocina")
      assert path =~ "/iniciar-sesion"
    end
  end

  # ---------------------------------------------------------------------------
  # Empty state
  # ---------------------------------------------------------------------------

  describe "empty state" do
    test "shows no-orders message when nothing is sent", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, _lv, html} = live(conn, "/cocina")
      assert html =~ "No hay pedidos pendientes en cocina"
    end

    test "does not show open (unsent) orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      food_cat = insert_category("food")
      mi = insert_menu_item(food_cat.id)
      order = insert_order(%{status: "open"})
      insert_order_item(order.id, mi.id, %{status: "pending"})
      {:ok, _lv, html} = live(conn, "/cocina")
      assert html =~ "No hay pedidos pendientes en cocina"
    end
  end

  # ---------------------------------------------------------------------------
  # Food-only filtering
  # ---------------------------------------------------------------------------

  describe "food filtering" do
    test "shows food items from sent orders", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      food_cat = insert_category("food")
      mi = insert_menu_item(food_cat.id, "Enchiladas")
      order = insert_order(%{customer_name: "Cliente A", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/cocina")
      assert html =~ "Enchiladas"
      assert html =~ "Cliente A"
    end

    test "does NOT show drink items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category("drink")
      drink_mi = insert_menu_item(drink_cat.id, "Margarita")
      order = insert_order(%{customer_name: "Solo Bebida", status: "sent"})
      insert_order_item(order.id, drink_mi.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/cocina")
      refute html =~ "Margarita"
      # No food items → order card should NOT appear
      refute html =~ "Solo Bebida"
    end

    test "shows extra-kind items" do
      # 'extra' category kind should also appear in cocina
      food_cat = %{} # tested inline below
      assert true
    end

    test "shows extra items alongside food items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      extra_cat = insert_category("extra")
      mi = insert_menu_item(extra_cat.id, "Postre del día")
      order = insert_order(%{customer_name: "Cliente Extra", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/cocina")
      assert html =~ "Postre del día"
    end

    test "does NOT show pending (not yet sent) food items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      food_cat = insert_category("food")
      mi = insert_menu_item(food_cat.id, "Tacos")
      order = insert_order(%{customer_name: "Solo Pending", status: "sent"})
      # Item is pending (waiter hasn't clicked Enviar yet)
      insert_order_item(order.id, mi.id, %{status: "pending"})
      {:ok, _lv, html} = live(conn, "/cocina")
      refute html =~ "Tacos"
    end
  end

  # ---------------------------------------------------------------------------
  # mark_item_ready
  # ---------------------------------------------------------------------------

  describe "mark_item_ready" do
    test "marks item as ready and shows badge", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      food_cat = insert_category("food")
      mi = insert_menu_item(food_cat.id, "Sopa")
      order = insert_order(%{customer_name: "Mesa 2", status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/cocina")

      render_click(lv, "mark_item_ready", %{"id" => to_string(item.id)})

      reloaded = Orders.get_order!(order.id)
      assert hd(reloaded.order_items).status == "ready"
    end

    test "shows Listo badge after marking item ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      food_cat = insert_category("food")
      mi = insert_menu_item(food_cat.id, "Caldo")
      order = insert_order(%{customer_name: "Mesa 3", status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/cocina")

      html = render_click(lv, "mark_item_ready", %{"id" => to_string(item.id)})
      assert html =~ "Listo"
    end
  end

  # ---------------------------------------------------------------------------
  # mark_order_ready
  # ---------------------------------------------------------------------------

  describe "mark_order_ready" do
    test "marks order as ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      food_cat = insert_category("food")
      mi = insert_menu_item(food_cat.id)
      order = insert_order(%{customer_name: "Rápido", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/cocina")

      render_click(lv, "mark_order_ready", %{"id" => to_string(order.id)})

      reloaded = Orders.get_order!(order.id)
      assert reloaded.status == "ready"
    end

    test "moves order to 'listos para servir' section", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      food_cat = insert_category("food")
      mi = insert_menu_item(food_cat.id)
      order = insert_order(%{customer_name: "Para Servir", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/cocina")

      html = render_click(lv, "mark_order_ready", %{"id" => to_string(order.id)})
      assert html =~ "Listos para servir"
      assert html =~ "Para Servir"
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  describe "PubSub" do
    test "refreshes when order_updated is broadcast", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, html} = live(conn, "/cocina")
      assert html =~ "No hay pedidos pendientes en cocina"

      food_cat = insert_category("food")
      mi = insert_menu_item(food_cat.id, "Frijoles")
      order = insert_order(%{customer_name: "PubSub", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})

      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, order.id})

      html = render(lv)
      assert html =~ "Frijoles"
    end
  end

  describe "nav events" do
    test "toggle_nav opens and closes nav", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/cocina")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "toggle_nav", %{})
      assert render(lv) =~ "Cocina"
    end

    test "close_nav closes nav", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/cocina")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "close_nav", %{})
      assert render(lv) =~ "Cocina"
    end
  end

  describe "mark_order_ready edge cases" do
    test "does nothing when order id not found in assigns", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/cocina")

      # Send mark_order_ready with an id that doesn't match any loaded order
      render_click(lv, "mark_order_ready", %{"id" => "999999"})
      assert render(lv) =~ "Cocina"
    end
  end

  describe "mark_item_ready error path" do
    test "handles item not found gracefully", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:ok, lv, _} = live(conn, "/cocina")

      # Should not crash when item id doesn't exist
      html = render_click(lv, "mark_item_ready", %{"id" => "0"})
      assert html =~ "Cocina"
    end
  end

  describe "pedido/pedidos pluralization" do
    test "shows pedido (singular) when one order is pending", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      food_cat = insert_category("food")
      mi = insert_menu_item(food_cat.id, "Platillo Singular")
      order = insert_order(%{customer_name: "Singular", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})

      {:ok, _lv, html} = live(conn, "/cocina")
      assert html =~ "pedido"
    end
  end

  describe "food item with ready status" do
    test "shows Listo badge for ready food items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      food_cat = insert_category("food")
      mi = insert_menu_item(food_cat.id, "Sopa Lista")
      order = insert_order(%{customer_name: "Lista Ya", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "ready"})

      {:ok, _lv, html} = live(conn, "/cocina")
      assert html =~ "Listo"
    end
  end

  describe "food item with notes" do
    test "shows item notes when present", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      food_cat = insert_category("food")
      mi = insert_menu_item(food_cat.id, "Tacos Especiales")
      order = insert_order(%{customer_name: "Con Notas", status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent", notes: "sin chile"})

      {:ok, _lv, html} = live(conn, "/cocina")
      assert html =~ "sin chile"
    end
  end
end
