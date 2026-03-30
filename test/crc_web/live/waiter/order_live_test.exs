defmodule CRCWeb.Waiter.OrderLiveTest do
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
        %{name: "Mesero", email: "mesero#{System.unique_integer()}@cafe.com",
          role: "empleado", station: "sala", password: "pass123456"},
        overrides
      )

    {:ok, user} = %User{} |> User.changeset(attrs) |> CRC.Repo.insert()
    user
  end

  defp auth_conn(conn) do
    user = insert_user()
    {init_test_session(conn, %{"user_id" => user.id}), user}
  end

  defp insert_category(overrides \\ %{}) do
    attrs = Map.merge(%{name: "Cafés", kind: "drink"}, overrides)
    {:ok, cat} = Catalog.create_category(attrs)
    cat
  end

  defp insert_menu_item(category_id, overrides \\ %{}) do
    attrs = Map.merge(%{name: "Espresso", price: "45.00", category_id: category_id}, overrides)
    {:ok, item} = Catalog.create_menu_item(attrs)
    item
  end

  defp insert_order(overrides \\ %{}) do
    {:ok, order} = Orders.create_order(Map.merge(%{customer_name: "Test"}, overrides))
    order
  end

  defp insert_order_item(order_id, menu_item_id, overrides \\ %{}) do
    {:ok, item} =
      Orders.add_item(
        Map.merge(%{order_id: order_id, menu_item_id: menu_item_id, quantity: 1}, overrides)
      )

    item
  end

  # ---------------------------------------------------------------------------
  # Authentication
  # ---------------------------------------------------------------------------

  describe "authentication" do
    test "redirects to login when not authenticated", %{conn: conn} do
      order = insert_order()
      {:error, {:redirect, %{to: path}}} = live(conn, "/mesa/#{order.id}")
      assert path =~ "/iniciar-sesion"
    end
  end

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  describe "mount" do
    test "shows order with customer name", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      order = insert_order(%{customer_name: "Rocío Mendez"})
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "Rocío Mendez"
    end

    test "redirects to /mesa for unknown order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      {:error, {:redirect, %{to: "/mesa"}}} = live(conn, "/mesa/999999")
    end

    test "shows empty comanda message when no items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      order = insert_order()
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "La comanda está vacía"
    end

    test "shows existing items in the order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Capuchino"})
      order = insert_order()
      insert_order_item(order.id, mi.id)
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "Capuchino"
    end

    test "send button is disabled on empty order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      order = insert_order()
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "Enviar a cocina y barra"
      assert html =~ ~s(phx-click="send_to_kitchen" disabled)
    end
  end

  # ---------------------------------------------------------------------------
  # Adding items
  # ---------------------------------------------------------------------------

  describe "add_item" do
    test "adds a new item to the order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Latte"})
      order = insert_order()
      {:ok, lv, _html} = live(conn, "/mesa/#{order.id}")

      html = render_click(lv, "add_item", %{"menu_item_id" => to_string(mi.id)})
      assert html =~ "Latte"
      assert html =~ "Artículo agregado"
    end

    test "increments quantity when adding an existing item", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Americano"})
      order = insert_order()
      insert_order_item(order.id, mi.id, %{quantity: 1})
      {:ok, lv, _html} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "add_item", %{"menu_item_id" => to_string(mi.id)})

      html = render(lv)
      # Quantity should be 2
      assert html =~ "2"
    end

    test "added item has pending status", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "add_item", %{"menu_item_id" => to_string(mi.id)})

      reloaded = Orders.get_order!(order.id)
      assert hd(reloaded.order_items).status == "pending"
    end
  end

  # ---------------------------------------------------------------------------
  # Quantity controls
  # ---------------------------------------------------------------------------

  describe "increment_item" do
    test "increments item quantity", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      item = insert_order_item(order.id, mi.id, %{quantity: 1})
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "increment_item", %{"id" => to_string(item.id)})

      reloaded = Orders.get_order!(order.id)
      assert hd(reloaded.order_items).quantity == 2
    end
  end

  describe "decrement_item" do
    test "decrements item quantity", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      item = insert_order_item(order.id, mi.id, %{quantity: 3})
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "decrement_item", %{"id" => to_string(item.id)})

      reloaded = Orders.get_order!(order.id)
      assert hd(reloaded.order_items).quantity == 2
    end

    test "does not decrement below 1", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      item = insert_order_item(order.id, mi.id, %{quantity: 1})
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "decrement_item", %{"id" => to_string(item.id)})

      reloaded = Orders.get_order!(order.id)
      assert hd(reloaded.order_items).quantity == 1
    end
  end

  # ---------------------------------------------------------------------------
  # Remove item
  # ---------------------------------------------------------------------------

  describe "remove_item" do
    test "removes the item from the order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Moka"})
      order = insert_order()
      item = insert_order_item(order.id, mi.id)
      {:ok, lv, _html} = live(conn, "/mesa/#{order.id}")

      html = render_click(lv, "remove_item", %{"id" => to_string(item.id)})
      assert html =~ "Artículo eliminado"
      # Comanda should be empty (item removed from order, not from menu browser)
      assert html =~ "La comanda está vacía"
      assert Orders.get_order!(order.id).order_items == []
    end
  end

  # ---------------------------------------------------------------------------
  # Send to kitchen
  # ---------------------------------------------------------------------------

  describe "send_to_kitchen" do
    test "button is enabled when there are pending items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      insert_order_item(order.id, mi.id, %{status: "pending"})
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")

      # Has pending items → button should NOT carry the disabled attribute
      refute html =~ ~s(phx-click="send_to_kitchen" disabled)
    end

    test "button is disabled when all items are sent", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")

      assert html =~ "Enviar adicionales"
      # No pending items → button should carry the disabled attribute
      assert html =~ ~s(phx-click="send_to_kitchen" disabled)
    end

    test "marks pending items as sent and order as sent", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      insert_order_item(order.id, mi.id, %{status: "pending"})
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "send_to_kitchen")

      reloaded = Orders.get_order!(order.id)
      assert reloaded.status == "sent"
      assert Enum.all?(reloaded.order_items, &(&1.status == "sent"))
    end

    test "shows 'Enviar adicionales' label when order is already sent", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "Enviar adicionales"
    end

    test "can add and send additional items after initial send", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      # Add new item — creates a NEW pending item (not increment of existing sent item)
      render_click(lv, "add_item", %{"menu_item_id" => to_string(mi.id)})

      # DB should have one sent item + one pending item
      reloaded = Orders.get_order!(order.id)
      pending = Enum.filter(reloaded.order_items, &(&1.status == "pending"))
      assert length(pending) == 1

      # Button should NOT be disabled (has pending items to send)
      html = render(lv)
      refute html =~ ~s(phx-click="send_to_kitchen" disabled)

      # Send the additional item
      render_click(lv, "send_to_kitchen")

      reloaded2 = Orders.get_order!(order.id)
      assert Enum.all?(reloaded2.order_items, &(&1.status in ["sent", "ready"]))
    end

    test "item remains visible after send (no ¡Listo! badge yet)", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      insert_order_item(order.id, mi.id)
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "send_to_kitchen")
      html = render(lv)
      # Item is still visible in the list but ¡Listo! badge is NOT shown (item is "sent", not ready)
      assert html =~ mi.name
      refute html =~ "¡Listo!"
    end
  end

  # ---------------------------------------------------------------------------
  # Close order
  # ---------------------------------------------------------------------------

  describe "close_order payment flow" do
    test "show_payment_step reveals payment panel", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      insert_order_item(order.id, mi.id)
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      html = render_click(lv, "show_payment_step")
      assert html =~ "Total a cobrar"
      assert html =~ "Efectivo"
    end

    test "redirects to /mesa after confirming tarjeta payment", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      insert_order_item(order.id, mi.id)
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "show_payment_step")
      render_click(lv, "set_payment_method", %{"method" => "tarjeta"})

      assert {:error, {:redirect, %{to: "/mesa"}}} =
               render_click(lv, "confirm_close_order")
    end

    test "closed order no longer appears in active list", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Té"})
      order = insert_order(%{customer_name: "Miguel"})
      insert_order_item(order.id, mi.id)
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "show_payment_step")
      render_click(lv, "set_payment_method", %{"method" => "transferencia"})
      render_click(lv, "confirm_close_order")

      {:ok, _lv2, html} = live(conn, "/mesa")
      refute html =~ "Miguel"
    end
  end

  # ---------------------------------------------------------------------------
  # Item status badges
  # ---------------------------------------------------------------------------

  describe "item status badges" do
    test "shows 'Listo' badge when item is ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "ready"})
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "Listo"
    end

    test "sent items in sent order are visible but do NOT show ¡Listo! badge", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      # Item is visible
      assert html =~ mi.name
      # ¡Listo! badge only appears when status is "ready"
      refute html =~ "¡Listo!"
    end

    test "pending items in sent order are visible but do NOT show ¡Listo! badge", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "pending"})
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      # Item is visible
      assert html =~ mi.name
      # ¡Listo! badge only appears when status is "ready"
      refute html =~ "¡Listo!"
    end
  end

  # ---------------------------------------------------------------------------
  # Navigation
  # ---------------------------------------------------------------------------

  describe "nav events" do
    test "toggle_nav opens and closes nav", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      order = insert_order()
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "toggle_nav", %{})
      assert render(lv) =~ order.customer_name
    end

    test "close_nav closes nav", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      order = insert_order()
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "close_nav", %{})
      assert render(lv) =~ order.customer_name
    end
  end

  # ---------------------------------------------------------------------------
  # Category selection
  # ---------------------------------------------------------------------------

  describe "select_category" do
    test "switching category loads its menu items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat1 = insert_category(%{name: "Cafés", kind: "drink"})
      cat2 = insert_category(%{name: "Comidas", kind: "food"})
      insert_menu_item(cat1.id, %{name: "Espresso Cat"})
      insert_menu_item(cat2.id, %{name: "Tacos Cat"})
      order = insert_order()
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      html = render_click(lv, "select_category", %{"id" => to_string(cat2.id)})
      assert html =~ "Tacos Cat"
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub handle_info
  # ---------------------------------------------------------------------------

  describe "handle_info PubSub" do
    test "updates order when order_updated matches current order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Ristretto PubSub"})
      order = insert_order()
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      # Add item via DB and broadcast
      Orders.add_item(%{order_id: order.id, menu_item_id: mi.id, quantity: 1})
      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, order.id})

      html = render(lv)
      assert html =~ "Ristretto PubSub"
    end

    test "ignores order_updated for a different order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      order = insert_order(%{customer_name: "Orden Principal"})
      other_order = insert_order(%{customer_name: "Otra Orden"})
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, other_order.id})

      html = render(lv)
      # Still shows the original order, not the other one
      assert html =~ "Orden Principal"
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases for item controls
  # ---------------------------------------------------------------------------

  describe "increment_item with missing item" do
    test "does nothing when item id not found in order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      order = insert_order()
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      # Sending increment for non-existent item id — should not crash
      render_click(lv, "increment_item", %{"id" => "999999"})
      assert render(lv) =~ order.customer_name
    end
  end

  describe "food category station labels" do
    test "shows Cocina label for food category items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      food_cat = insert_category(%{name: "Comidas", kind: "food"})
      mi = insert_menu_item(food_cat.id, %{name: "Enchiladas"})
      order = insert_order()
      insert_order_item(order.id, mi.id)
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "Cocina"
    end

    test "shows Cocina label for extra category items", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      extra_cat = insert_category(%{name: "Extras", kind: "extra"})
      mi = insert_menu_item(extra_cat.id, %{name: "Postre"})
      order = insert_order()
      insert_order_item(order.id, mi.id)
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "Cocina"
    end
  end

  describe "closed order state" do
    test "shows Esta cuenta está cerrada when order is closed", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "closed"})
      insert_order_item(order.id, mi.id)
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "cerrada"
    end

    test "send button is disabled when order is closed", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "closed"})
      insert_order_item(order.id, mi.id, %{status: "pending"})
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ ~s(phx-click="send_to_kitchen" disabled)
    end
  end

  # ---------------------------------------------------------------------------
  # Cancel item flow
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Timing banners and overdue warnings
  # ---------------------------------------------------------------------------

  describe "drinks-ready banner" do
    test "shows banner when drinks are ready but food is still pending", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category(%{name: "Barra Banner", kind: "drink"})
      food_cat  = insert_category(%{name: "Cocina Banner", kind: "food"})
      mi_drink  = insert_menu_item(drink_cat.id, %{name: "Limonada"})
      mi_food   = insert_menu_item(food_cat.id,  %{name: "Enchiladas"})
      order = insert_order(%{status: "sent"})
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

      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "bebida(s) lista(s) en barra"
    end

    test "does not show banner when all items are ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      drink_cat = insert_category(%{name: "Barra All", kind: "drink"})
      mi = insert_menu_item(drink_cat.id, %{name: "Café"})
      order = insert_order(%{status: "ready"})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id,
        quantity: 1, status: "ready", sent_at: now, ready_at: now,
        inserted_at: now, updated_at: now
      })

      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      refute html =~ "bebida(s) lista(s) en barra"
    end
  end

  describe "all-ready banner" do
    test "shows banner when all active items are ready", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category(%{name: "Cat Ready", kind: "food"})
      mi = insert_menu_item(cat.id, %{name: "Burrito"})
      order = insert_order(%{status: "sent"})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id,
        quantity: 1, status: "ready", sent_at: now, ready_at: now,
        inserted_at: now, updated_at: now
      })

      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "¡Todo listo!"
    end
  end

  describe "overdue item warning" do
    test "shows +15 min badge on item sent more than 15 min ago", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category(%{name: "Cocina Overdue", kind: "food"})
      mi = insert_menu_item(cat.id, %{name: "Pozole"})
      order = insert_order(%{status: "sent"})
      old = DateTime.utc_now() |> DateTime.add(-20 * 60, :second) |> DateTime.truncate(:second)

      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id,
        quantity: 1, status: "sent", sent_at: old,
        inserted_at: old, updated_at: old
      })

      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "+15 min"
    end

    test "does not show +15 min badge on recently sent item", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category(%{name: "Cocina Fresh", kind: "food"})
      mi = insert_menu_item(cat.id, %{name: "Caldo"})
      order = insert_order(%{status: "sent"})
      recent = DateTime.utc_now() |> DateTime.add(-3 * 60, :second) |> DateTime.truncate(:second)

      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id,
        quantity: 1, status: "sent", sent_at: recent,
        inserted_at: recent, updated_at: recent
      })

      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      refute html =~ "+15 min"
    end
  end

  describe "cancel item flow" do
    test "request_cancel_item shows cancel dialog for sent item", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Enchiladas"})
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      html = render_click(lv, "request_cancel_item", %{"id" => to_string(item.id)})
      assert html =~ "¿Este artículo ya fue preparado"
      assert html =~ "Enchiladas"
    end

    test "dismiss_cancel removes the dialog", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Tacos"})
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "request_cancel_item", %{"id" => to_string(item.id)})
      html = render_click(lv, "dismiss_cancel")
      refute html =~ "¿Este artículo ya fue preparado"
    end

    test "cancel_with_restore marks item as 'cancelled'", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Sopa"})
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "request_cancel_item", %{"id" => to_string(item.id)})
      html = render_click(lv, "cancel_with_restore")
      assert html =~ "stock restaurado"

      reloaded = Orders.get_order!(order.id)
      assert hd(reloaded.order_items).status == "cancelled"
    end

    test "cancel_as_waste marks item as 'cancelled_waste'", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Postre"})
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "request_cancel_item", %{"id" => to_string(item.id)})
      html = render_click(lv, "cancel_as_waste")
      assert html =~ "desperdicio"

      reloaded = Orders.get_order!(order.id)
      assert hd(reloaded.order_items).status == "cancelled_waste"
    end

    test "cancelled item shows strikethrough text in comanda", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Agua Fresca"})
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      render_click(lv, "request_cancel_item", %{"id" => to_string(item.id)})
      html = render_click(lv, "cancel_as_waste")
      assert html =~ "line-through"
      assert html =~ "Agua Fresca"
    end

    test "pending item uses remove_item (trash) not request_cancel_item", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      insert_order_item(order.id, mi.id, %{status: "pending"})
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")

      assert html =~ ~s(phx-click="remove_item")
      refute html =~ ~s(phx-click="request_cancel_item")
    end

    test "sent item uses request_cancel_item not remove_item", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")

      assert html =~ ~s(phx-click="request_cancel_item")
    end
  end

  describe "order status badges" do
    test "shows Abierta badge for open order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      order = insert_order(%{status: "open"})
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "Abierta"
    end

    test "shows En cocina / barra badge for sent order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      order = insert_order(%{status: "sent"})
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "En cocina / barra"
    end

    test "shows Lista badge for ready order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      order = insert_order(%{status: "ready"})
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "Lista"
    end

    test "shows Cerrada badge for closed order", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "closed"})
      insert_order_item(order.id, mi.id)
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ "Cerrada"
    end
  end

  # ---------------------------------------------------------------------------
  # mark_item_served — basic + auto-serve regression
  # ---------------------------------------------------------------------------

  describe "mark_item_served" do
    test "marks a ready item as served", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Tacos Servidos"})
      order = insert_order(%{customer_name: "Mesa Servir", status: "sent", user_id: user.id})
      item = insert_order_item(order.id, mi.id, %{status: "ready"})

      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")
      html = render_click(lv, "mark_item_served", %{"id" => to_string(item.id)})
      assert html =~ "Servido"
    end

    test "served item no longer shows the Servir button", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Latte"})
      order = insert_order(%{customer_name: "Mesa Botón", status: "sent", user_id: user.id})
      item = insert_order_item(order.id, mi.id, %{status: "ready"})

      {:ok, lv, html_before} = live(conn, "/mesa/#{order.id}")
      assert html_before =~ "Servir"

      render_click(lv, "mark_item_served", %{"id" => to_string(item.id)})
      html_after = render(lv)
      refute html_after =~ ~r/phx-value-id="#{item.id}"[^>]*>.*?Servir/s
    end

    # REGRESSION Bug #4: extra stays visible after parent served (any status)
    test "auto-serves a 'pending' extra when parent menu item is served", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Capuchino Auto"})

      extra_product = CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "Leche extra #{System.unique_integer()}",
        category: "lacteos", unit: "ml",
        net_cost: Decimal.new("0.05"),
        stock_quantity: Decimal.new("3000"), active: true
      })

      order = insert_order(%{customer_name: "Mesa Auto Serve", status: "sent", user_id: user.id})
      parent_item = insert_order_item(order.id, mi.id, %{status: "ready"})

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      extra_item = CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, product_id: extra_product.id,
        for_menu_item_id: mi.id, quantity: 1, status: "pending",
        inserted_at: now, updated_at: now
      })

      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")
      render_click(lv, "mark_item_served", %{"id" => to_string(parent_item.id)})

      reloaded = CRC.Repo.get!(CRC.Orders.OrderItem, extra_item.id)
      assert reloaded.status == "served"
    end

    test "auto-serves a 'sent' extra when parent menu item is served", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Mocca Auto"})

      extra_product = CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "Jarabe #{System.unique_integer()}",
        category: "otros", unit: "ml",
        net_cost: Decimal.new("0.10"),
        stock_quantity: Decimal.new("2000"), active: true
      })

      order = insert_order(%{customer_name: "Mesa Auto Sent", status: "sent", user_id: user.id})
      parent_item = insert_order_item(order.id, mi.id, %{status: "ready"})

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      extra_item = CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, product_id: extra_product.id,
        for_menu_item_id: mi.id, quantity: 1, status: "sent",
        inserted_at: now, updated_at: now
      })

      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")
      render_click(lv, "mark_item_served", %{"id" => to_string(parent_item.id)})

      reloaded = CRC.Repo.get!(CRC.Orders.OrderItem, extra_item.id)
      assert reloaded.status == "served"
    end

    test "does NOT auto-serve extras of a DIFFERENT menu item", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      cat = insert_category()
      mi_a = insert_menu_item(cat.id, %{name: "Bebida A"})
      mi_b = insert_menu_item(cat.id, %{name: "Bebida B"})

      extra_product = CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "Extra Otro #{System.unique_integer()}",
        category: "otros", unit: "ml",
        net_cost: Decimal.new("0.05"),
        stock_quantity: Decimal.new("1000"), active: true
      })

      order = insert_order(%{customer_name: "Mesa Dos Bebidas", status: "sent", user_id: user.id})
      item_a = insert_order_item(order.id, mi_a.id, %{status: "ready"})
      _item_b = insert_order_item(order.id, mi_b.id, %{status: "ready"})

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      extra_for_b = CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, product_id: extra_product.id,
        for_menu_item_id: mi_b.id, quantity: 1, status: "pending",
        inserted_at: now, updated_at: now
      })

      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")
      render_click(lv, "mark_item_served", %{"id" => to_string(item_a.id)})

      reloaded = CRC.Repo.get!(CRC.Orders.OrderItem, extra_for_b.id)
      assert reloaded.status == "pending"
    end

    test "does NOT auto-serve cancelled extras", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Café Cancelado Extra"})

      extra_product = CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "Extra Cancelado #{System.unique_integer()}",
        category: "otros", unit: "ml",
        net_cost: Decimal.new("0.05"),
        stock_quantity: Decimal.new("1000"), active: true
      })

      order = insert_order(%{customer_name: "Mesa Cancel Extra", status: "sent", user_id: user.id})
      parent_item = insert_order_item(order.id, mi.id, %{status: "ready"})

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      cancelled_extra = CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, product_id: extra_product.id,
        for_menu_item_id: mi.id, quantity: 1, status: "cancelled",
        inserted_at: now, updated_at: now
      })

      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")
      render_click(lv, "mark_item_served", %{"id" => to_string(parent_item.id)})

      reloaded = CRC.Repo.get!(CRC.Orders.OrderItem, cancelled_extra.id)
      assert reloaded.status == "cancelled"
    end

    test "does NOT auto-serve cancelled_waste extras", %{conn: conn} do
      {conn, user} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Café Waste Extra"})

      extra_product = CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "Extra Waste #{System.unique_integer()}",
        category: "otros", unit: "ml",
        net_cost: Decimal.new("0.05"),
        stock_quantity: Decimal.new("1000"), active: true
      })

      order = insert_order(%{customer_name: "Mesa Waste Extra", status: "sent", user_id: user.id})
      parent_item = insert_order_item(order.id, mi.id, %{status: "ready"})

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      waste_extra = CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, product_id: extra_product.id,
        for_menu_item_id: mi.id, quantity: 1, status: "cancelled_waste",
        inserted_at: now, updated_at: now
      })

      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")
      render_click(lv, "mark_item_served", %{"id" => to_string(parent_item.id)})

      reloaded = CRC.Repo.get!(CRC.Orders.OrderItem, waste_extra.id)
      assert reloaded.status == "cancelled_waste"
    end
  end

  # ---------------------------------------------------------------------------
  # Low-stock & out-of-stock menu item display
  # ---------------------------------------------------------------------------

  describe "low-stock and out-of-stock menu items" do
    defp insert_stocked_product_for_ui(stock) do
      CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "Prod UI #{System.unique_integer()}",
        category: "insumos",
        unit: "g",
        net_cost: Decimal.new("1.00"),
        stock_quantity: Decimal.new(stock),
        active: true
      })
    end

    defp link_recipe_for_ui(menu_item_id, product_id, qty) do
      CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
        menu_item_id: menu_item_id,
        product_id: product_id,
        quantity: Decimal.new(qty)
      })
    end

    test "item with no recipe always shows normal Agregar button", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ mi.name
      assert html =~ "Agregar"
      refute html =~ "Agotado"
    end

    test "item with sufficient stock shows normal Agregar button (no warning)", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      # 10g per portion, 1000g stock = 100 portions → no warning
      prod = insert_stocked_product_for_ui("1000")
      link_recipe_for_ui(mi.id, prod.id, "10")
      order = insert_order()
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ mi.name
      assert html =~ "Agregar"
      refute html =~ "Solo quedan"
      refute html =~ "el último"
      refute html =~ "Agotado"
    end

    test "item with low stock (2 portions) shows low-stock warning", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      # 10g per portion, 20g stock = 2 portions → low-stock warning
      prod = insert_stocked_product_for_ui("20")
      link_recipe_for_ui(mi.id, prod.id, "10")
      order = insert_order()
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ mi.name
      assert html =~ "Solo quedan 2"
    end

    test "item with exactly 1 portion shows '¡Es el último!' warning", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      # 10g per portion, 10g stock = exactly 1 portion
      prod = insert_stocked_product_for_ui("10")
      link_recipe_for_ui(mi.id, prod.id, "10")
      order = insert_order()
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ mi.name
      assert html =~ "el último"
    end

    test "item with 0 stock is disabled and shows Agotado", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      # 0g stock = cannot be prepared
      prod = insert_stocked_product_for_ui("0")
      link_recipe_for_ui(mi.id, prod.id, "10")
      order = insert_order()
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ mi.name
      assert html =~ "Agotado"
      # Button should be disabled
      assert html =~ "disabled"
    end

    test "item above threshold (6 portions) shows no warning", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      # 10g per portion, 60g stock = 6 portions → above threshold of 5 → no warning
      prod = insert_stocked_product_for_ui("60")
      link_recipe_for_ui(mi.id, prod.id, "10")
      order = insert_order()
      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      assert html =~ mi.name
      assert html =~ "Agregar"
      refute html =~ "Solo quedan"
      refute html =~ "el último"
    end

    test "item with low stock can still be added (button is NOT disabled)", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      # 2 portions remaining — still orderable, just with a warning
      prod = insert_stocked_product_for_ui("20")
      link_recipe_for_ui(mi.id, prod.id, "10")
      order = insert_order()
      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")
      # Adding the item should succeed
      html = render_click(lv, "add_item", %{"menu_item_id" => to_string(mi.id)})
      reloaded = CRC.Orders.get_order!(order.id)
      assert Enum.any?(reloaded.order_items, &(&1.menu_item_id == mi.id))
      # After adding, the warning portion count updated (2→1 after send, but here just reload)
      assert html =~ mi.name
    end

    test "stock update via PubSub refreshes the menu display", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      prod = insert_stocked_product_for_ui("20")
      link_recipe_for_ui(mi.id, prod.id, "10")
      order = insert_order()
      {:ok, lv, html} = live(conn, "/mesa/#{order.id}")
      # Initially 2 portions remaining
      assert html =~ "Solo quedan 2"
      # Simulate stock depletion by broadcasting the stock update event
      Phoenix.PubSub.broadcast(CRC.PubSub, "menu_stock", :stock_updated)
      # Allow the LiveView to process the message
      html = render(lv)
      assert html =~ mi.name
    end
  end

  # ---------------------------------------------------------------------------
  # Ingredient exclusion toggles (sin jitomate)
  # ---------------------------------------------------------------------------

  describe "ingredient exclusion toggles" do
    defp insert_recipe_product(name) do
      CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "#{name}_#{System.unique_integer()}",
        category: "verduras",
        unit: "g",
        net_cost: Decimal.new("1.00"),
        stock_quantity: Decimal.new("999"),
        active: true
      })
    end

    defp link_recipe(menu_item_id, product_id) do
      CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
        menu_item_id: menu_item_id,
        product_id: product_id,
        quantity: Decimal.new("10")
      })
    end

    test "shows ingredient toggles for pending menu item with a recipe", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      prod = insert_recipe_product("Jitomate")
      link_recipe(mi.id, prod.id)
      order = insert_order()
      insert_order_item(order.id, mi.id)

      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      # The ingredient name should appear as a toggle badge
      assert html =~ prod.name
      # The "Quitar:" label is shown
      assert html =~ "Quitar:"
    end

    test "does NOT show ingredient toggles for items with no recipe", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      # No ingredients linked to this menu item
      order = insert_order()
      insert_order_item(order.id, mi.id)

      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      refute html =~ "Quitar:"
    end

    test "clicking an ingredient badge excludes it (shows as error/strikethrough)", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      prod = insert_recipe_product("Cebolla")
      link_recipe(mi.id, prod.id)
      order = insert_order()
      item = insert_order_item(order.id, mi.id)

      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      html =
        render_click(lv, "toggle_exclusion", %{
          "order_item_id" => to_string(item.id),
          "product_id" => to_string(prod.id)
        })

      # After exclusion, the badge gets `line-through` class (excluded style)
      assert html =~ "line-through"
      # Exclusion record was created in DB
      assert CRC.Repo.get_by(CRC.Orders.OrderItemExclusion,
               order_item_id: item.id, product_id: prod.id)
    end

    test "clicking again removes the exclusion (toggle off)", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      prod = insert_recipe_product("Lechuga")
      link_recipe(mi.id, prod.id)
      order = insert_order()
      item = insert_order_item(order.id, mi.id)

      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      # First click: exclude
      render_click(lv, "toggle_exclusion", %{
        "order_item_id" => to_string(item.id),
        "product_id" => to_string(prod.id)
      })

      # Second click: un-exclude
      html =
        render_click(lv, "toggle_exclusion", %{
          "order_item_id" => to_string(item.id),
          "product_id" => to_string(prod.id)
        })

      # line-through removed (ingredient is included again)
      refute html =~ "line-through"
      # DB record removed
      assert is_nil(CRC.Repo.get_by(CRC.Orders.OrderItemExclusion,
               order_item_id: item.id, product_id: prod.id))
    end

    test "does NOT show ingredient toggles for sent items (read-only state)", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      prod = insert_recipe_product("Aguacate")
      link_recipe(mi.id, prod.id)
      order = insert_order(%{status: "sent"})
      insert_order_item(order.id, mi.id, %{status: "sent"})

      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      # No modifiable toggles shown for sent items
      refute html =~ "Quitar:"
    end

    test "shows read-only 'Sin:' badge for excluded ingredient on sent item", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      prod = insert_recipe_product("Cilantro")
      link_recipe(mi.id, prod.id)
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})

      # Create exclusion directly in DB (was set before sending)
      CRC.Repo.insert!(%CRC.Orders.OrderItemExclusion{
        order_item_id: item.id,
        product_id: prod.id
      })

      {:ok, _lv, html} = live(conn, "/mesa/#{order.id}")
      # Read-only "Sin:" badge visible
      assert html =~ "Sin:"
      assert html =~ prod.name
    end

    test "toggle_exclusion on non-pending item is ignored (guard)", %{conn: conn} do
      {conn, _} = auth_conn(conn)
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      prod = insert_recipe_product("Chile")
      link_recipe(mi.id, prod.id)
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})

      {:ok, lv, _} = live(conn, "/mesa/#{order.id}")

      # Should not raise, just be ignored
      render_click(lv, "toggle_exclusion", %{
        "order_item_id" => to_string(item.id),
        "product_id" => to_string(prod.id)
      })

      # No exclusion should have been created
      assert is_nil(CRC.Repo.get_by(CRC.Orders.OrderItemExclusion,
               order_item_id: item.id, product_id: prod.id))
    end
  end
end
