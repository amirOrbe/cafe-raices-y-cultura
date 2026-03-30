defmodule CRC.OrdersTest do
  use CRC.DataCase, async: true

  alias CRC.Orders
  alias CRC.Orders.{Order, OrderItem}
  alias CRC.Catalog
  alias CRC.Accounts.User

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{name: "Test User", email: "user#{System.unique_integer()}@test.com",
          role: "empleado", station: "sala", password: "pass123456"},
        overrides
      )

    {:ok, user} = %User{} |> User.changeset(attrs) |> CRC.Repo.insert()
    user
  end

  defp insert_category(overrides \\ %{}) do
    attrs = Map.merge(%{name: "Cafés", kind: "drink"}, overrides)
    {:ok, cat} = Catalog.create_category(attrs)
    cat
  end

  defp insert_menu_item(category_id, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{name: "Espresso", price: "40.00", category_id: category_id},
        overrides
      )

    {:ok, item} = Catalog.create_menu_item(attrs)
    item
  end

  defp insert_order(overrides \\ %{}) do
    attrs = Map.merge(%{customer_name: "Juan García"}, overrides)
    {:ok, order} = Orders.create_order(attrs)
    order
  end

  defp insert_order_item(order_id, menu_item_id, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{order_id: order_id, menu_item_id: menu_item_id, quantity: 1},
        overrides
      )

    {:ok, item} = Orders.add_item(attrs)
    item
  end

  # ---------------------------------------------------------------------------
  # create_order/1
  # ---------------------------------------------------------------------------

  describe "create_order/1" do
    test "creates an order with valid attrs" do
      assert {:ok, %Order{customer_name: "Mesa 3", status: "open"}} =
               Orders.create_order(%{customer_name: "Mesa 3"})
    end

    test "default status is 'open'" do
      {:ok, order} = Orders.create_order(%{customer_name: "Test"})
      assert order.status == "open"
    end

    test "fails without customer_name" do
      assert {:error, changeset} = Orders.create_order(%{})
      assert "can't be blank" in errors_on(changeset).customer_name
    end

    test "fails with invalid status" do
      assert {:error, changeset} = Orders.create_order(%{customer_name: "X", status: "invalid"})
      assert "is invalid" in errors_on(changeset).status
    end

    test "accepts optional user_id" do
      user = insert_user()
      {:ok, order} = Orders.create_order(%{customer_name: "Sofía", user_id: user.id})
      assert order.user_id == user.id
    end
  end

  # ---------------------------------------------------------------------------
  # list_active_orders/0
  # ---------------------------------------------------------------------------

  describe "list_active_orders/0" do
    test "returns open orders" do
      order = insert_order(%{status: "open"})
      ids = Orders.list_active_orders() |> Enum.map(& &1.id)
      assert order.id in ids
    end

    test "returns sent orders" do
      order = insert_order(%{status: "sent"})
      ids = Orders.list_active_orders() |> Enum.map(& &1.id)
      assert order.id in ids
    end

    test "returns ready orders" do
      order = insert_order(%{status: "ready"})
      ids = Orders.list_active_orders() |> Enum.map(& &1.id)
      assert order.id in ids
    end

    test "excludes closed orders" do
      order = insert_order(%{status: "closed"})
      ids = Orders.list_active_orders() |> Enum.map(& &1.id)
      refute order.id in ids
    end

    test "preloads order_items with menu_item and category" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      insert_order_item(order.id, mi.id)

      [loaded] = Orders.list_active_orders() |> Enum.filter(&(&1.id == order.id))
      [item] = loaded.order_items
      assert item.menu_item.name == "Espresso"
      assert item.menu_item.category.kind == "drink"
    end
  end

  # ---------------------------------------------------------------------------
  # list_open_orders/0
  # ---------------------------------------------------------------------------

  describe "list_open_orders/0" do
    test "returns open, sent, and ready orders" do
      o1 = insert_order(%{status: "open"})
      o2 = insert_order(%{status: "sent"})
      o3 = insert_order(%{status: "ready"})
      closed = insert_order(%{status: "closed"})

      ids = Orders.list_open_orders() |> Enum.map(& &1.id)
      assert o1.id in ids
      assert o2.id in ids
      assert o3.id in ids
      refute closed.id in ids
    end
  end

  # ---------------------------------------------------------------------------
  # get_order!/1
  # ---------------------------------------------------------------------------

  describe "get_order!/1" do
    test "returns order with preloads" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      insert_order_item(order.id, mi.id)

      loaded = Orders.get_order!(order.id)
      assert loaded.id == order.id
      assert [item] = loaded.order_items
      assert item.menu_item.category.kind == "drink"
    end

    test "raises Ecto.NoResultsError for unknown id" do
      assert_raise Ecto.NoResultsError, fn ->
        Orders.get_order!(0)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # add_item/1
  # ---------------------------------------------------------------------------

  describe "add_item/1" do
    test "creates an order item with pending status" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()

      assert {:ok, %OrderItem{status: "pending", quantity: 1}} =
               Orders.add_item(%{order_id: order.id, menu_item_id: mi.id, quantity: 1})
    end

    test "fails without order_id" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      assert {:error, _} = Orders.add_item(%{menu_item_id: mi.id, quantity: 1})
    end

    test "fails with quantity 0" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      assert {:error, changeset} = Orders.add_item(%{order_id: order.id, menu_item_id: mi.id, quantity: 0})
      assert "must be greater than 0" in errors_on(changeset).quantity
    end
  end

  # ---------------------------------------------------------------------------
  # update_item/2
  # ---------------------------------------------------------------------------

  describe "update_item/2" do
    test "updates the quantity" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      item = insert_order_item(order.id, mi.id)

      assert {:ok, updated} = Orders.update_item(item, %{quantity: 3})
      assert updated.quantity == 3
    end

    test "fails with quantity 0" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      item = insert_order_item(order.id, mi.id)

      assert {:error, changeset} = Orders.update_item(item, %{quantity: 0})
      assert "must be greater than 0" in errors_on(changeset).quantity
    end
  end

  # ---------------------------------------------------------------------------
  # remove_item/1
  # ---------------------------------------------------------------------------

  describe "remove_item/1" do
    test "deletes the item" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      item = insert_order_item(order.id, mi.id)

      assert {:ok, _} = Orders.remove_item(item.id)
      assert Orders.get_order!(order.id).order_items == []
    end

    test "returns error for non-existent id" do
      assert {:error, :not_found} = Orders.remove_item(0)
    end
  end

  # ---------------------------------------------------------------------------
  # send_to_kitchen/1
  # ---------------------------------------------------------------------------

  describe "send_to_kitchen/1" do
    test "sets order status to 'sent'" do
      order = insert_order()
      {:ok, updated} = Orders.send_to_kitchen(order)
      assert updated.status == "sent"
    end

    test "marks all pending items as 'sent'" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      insert_order_item(order.id, mi.id, %{status: "pending"})
      insert_order_item(order.id, mi.id |> then(fn _ -> mi.id end), %{status: "pending"})

      {:ok, _} = Orders.send_to_kitchen(order)

      reloaded = Orders.get_order!(order.id)
      assert Enum.all?(reloaded.order_items, &(&1.status == "sent"))
    end

    test "does not change items that are already 'ready'" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      ready_item = insert_order_item(order.id, mi.id, %{status: "ready"})

      # Add a new pending item (additional order)
      pending_item = insert_order_item(order.id, mi.id, %{status: "pending"})

      {:ok, _} = Orders.send_to_kitchen(order)

      reloaded = Orders.get_order!(order.id)
      statuses = Map.new(reloaded.order_items, &{&1.id, &1.status})
      assert statuses[ready_item.id] == "ready"
      assert statuses[pending_item.id] == "sent"
    end

    test "broadcasts order_updated" do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
      order = insert_order()
      {:ok, updated} = Orders.send_to_kitchen(order)
      id = updated.id
      assert_receive {:order_updated, ^id}
    end
  end

  # ---------------------------------------------------------------------------
  # mark_item_ready/1
  # ---------------------------------------------------------------------------

  describe "mark_item_ready/1" do
    test "sets item status to 'ready'" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})

      assert {:ok, updated} = Orders.mark_item_ready(item.id)
      assert updated.status == "ready"
    end

    test "returns error for non-existent id" do
      assert {:error, :not_found} = Orders.mark_item_ready(0)
    end

    test "broadcasts order_updated" do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})

      {:ok, _} = Orders.mark_item_ready(item.id)
      order_id = order.id
      assert_receive {:order_updated, ^order_id}
    end
  end

  # ---------------------------------------------------------------------------
  # mark_order_ready/1
  # ---------------------------------------------------------------------------

  describe "mark_order_ready/1" do
    test "sets order status to 'ready'" do
      order = insert_order(%{status: "sent"})
      {:ok, updated} = Orders.mark_order_ready(order)
      assert updated.status == "ready"
    end

    test "broadcasts order_updated" do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
      order = insert_order(%{status: "sent"})
      {:ok, updated} = Orders.mark_order_ready(order)
      id = updated.id
      assert_receive {:order_updated, ^id}
    end
  end

  # ---------------------------------------------------------------------------
  # close_order/2
  # ---------------------------------------------------------------------------

  describe "close_order/2" do
    test "sets order status to 'closed' with tarjeta" do
      order = Orders.get_order!(insert_order(%{status: "ready"}).id)
      {:ok, updated} = Orders.close_order(order, %{payment_method: "tarjeta"})
      assert updated.status == "closed"
      assert updated.payment_method == "tarjeta"
    end

    test "stores total and efectivo amount_paid" do
      cat = insert_category()
      mi = CRC.Repo.insert!(%CRC.Catalog.MenuItem{name: "X", price: Decimal.new(100), category_id: cat.id, position: 1, available: true, featured: false})
      order = insert_order()
      CRC.Repo.insert!(%CRC.Orders.OrderItem{order_id: order.id, menu_item_id: mi.id, quantity: 2, status: "pending"})
      order = Orders.get_order!(order.id)
      {:ok, updated} = Orders.close_order(order, %{payment_method: "efectivo", amount_paid: Decimal.new(250)})
      assert Decimal.equal?(updated.total, Decimal.new(200))
      assert updated.payment_method == "efectivo"
    end

    test "excludes closed order from list_active_orders" do
      order = Orders.get_order!(insert_order().id)
      {:ok, _} = Orders.close_order(order, %{payment_method: "transferencia"})
      ids = Orders.list_active_orders() |> Enum.map(& &1.id)
      refute order.id in ids
    end

    test "broadcasts order_updated" do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
      order = Orders.get_order!(insert_order().id)
      {:ok, updated} = Orders.close_order(order, %{payment_method: "tarjeta"})
      id = updated.id
      assert_receive {:order_updated, ^id}
    end
  end

  # ---------------------------------------------------------------------------
  # update_order/2
  # ---------------------------------------------------------------------------

  describe "update_order/2" do
    test "updates customer_name" do
      order = insert_order(%{customer_name: "Ana"})
      {:ok, updated} = Orders.update_order(order, %{customer_name: "Ana López"})
      assert updated.customer_name == "Ana López"
    end

    test "fails with invalid status" do
      order = insert_order()
      assert {:error, changeset} = Orders.update_order(order, %{status: "nope"})
      assert "is invalid" in errors_on(changeset).status
    end
  end

  # ---------------------------------------------------------------------------
  # Default argument coverage
  # ---------------------------------------------------------------------------

  describe "create_order/0 default arg" do
    test "returns error with no attrs (required fields missing)" do
      assert {:error, changeset} = Orders.create_order()
      assert "can't be blank" in errors_on(changeset).customer_name
    end
  end

  # ---------------------------------------------------------------------------
  # Timing timestamps
  # ---------------------------------------------------------------------------

  describe "send_to_kitchen/1 sets sent_at" do
    test "sets sent_at on newly sent items" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      insert_order_item(order.id, mi.id, %{status: "pending"})

      {:ok, _} = Orders.send_to_kitchen(order)

      reloaded = Orders.get_order!(order.id)
      assert Enum.all?(reloaded.order_items, &(not is_nil(&1.sent_at)))
    end

    test "does not overwrite sent_at on already-sent items" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      old_time = ~U[2026-01-01 10:00:00Z]
      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id,
        quantity: 1, status: "sent", sent_at: old_time
      })

      {:ok, _} = Orders.send_to_kitchen(order)

      reloaded = Orders.get_order!(order.id)
      # Only pending items are touched; the already-sent item keeps its old sent_at
      [item] = reloaded.order_items
      assert item.sent_at == old_time
    end
  end

  describe "mark_item_ready/1 sets ready_at" do
    test "sets ready_at when marking item ready" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})

      {:ok, updated} = Orders.mark_item_ready(item.id)
      assert not is_nil(updated.ready_at)
    end
  end

  describe "close_order/2 sets closed_at" do
    test "sets closed_at on the order" do
      order = Orders.get_order!(insert_order().id)
      {:ok, updated} = Orders.close_order(order, %{payment_method: "tarjeta"})
      assert not is_nil(updated.closed_at)
    end
  end

  # ---------------------------------------------------------------------------
  # timing_stats/1
  # ---------------------------------------------------------------------------

  describe "timing_stats/1" do
    test "returns empty map when no closed orders" do
      assert Orders.timing_stats() == %{}
    end

    test "returns stats grouped by station kind" do
      cat_drink = insert_category(%{name: "Bebidas Timing", kind: "drink"})
      cat_food  = insert_category(%{name: "Comidas Timing", kind: "food"})
      mi_drink  = insert_menu_item(cat_drink.id)
      mi_food   = insert_menu_item(cat_food.id)

      order = insert_order()

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      sent   = DateTime.add(now, -600, :second)  # 10 min ago
      ready  = DateTime.add(now, -300, :second)  # 5 min ago
      closed_at = now

      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi_drink.id,
        quantity: 1, status: "ready", sent_at: sent, ready_at: ready,
        inserted_at: DateTime.add(now, -900, :second),
        updated_at: now
      })
      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi_food.id,
        quantity: 1, status: "ready", sent_at: sent, ready_at: ready,
        inserted_at: DateTime.add(now, -900, :second),
        updated_at: now
      })

      # Close the order with a closed_at
      order
      |> CRC.Orders.Order.close_changeset(%{
        status: "closed", payment_method: "tarjeta",
        total: Decimal.new(0), closed_at: closed_at
      })
      |> CRC.Repo.update!()

      stats = Orders.timing_stats()
      assert Map.has_key?(stats, "drink")
      assert Map.has_key?(stats, "food")
      assert stats["drink"].prep.avg == 300
      assert stats["drink"].service.avg == 300
    end

    test "returns empty map when closed orders have no timestamps" do
      order = Orders.get_order!(insert_order().id)
      Orders.close_order(order, %{payment_method: "tarjeta"})
      # No items with sent_at/ready_at — timing_stats should return %{}
      assert Orders.timing_stats() == %{}
    end
  end

  describe "add_item/0 default arg" do
    test "returns error with no attrs (required fields missing)" do
      assert {:error, _changeset} = Orders.add_item()
    end
  end

  # ---------------------------------------------------------------------------
  # cancel_item/2 — :not_prepared
  # ---------------------------------------------------------------------------

  describe "cancel_item/2 :not_prepared" do
    test "sets item status to 'cancelled'" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})

      assert {:ok, updated} = Orders.cancel_item(item, :not_prepared)
      assert updated.status == "cancelled"
    end

    test "restores ingredient stock when cancelled as not_prepared" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)

      product =
        CRC.Repo.insert!(%CRC.Inventory.Product{
          name: "Café Test #{System.unique_integer()}",
          category: "granos",
          unit: "g",
          net_cost: Decimal.new("1.00"),
          stock_quantity: Decimal.new("100"),
          active: true
        })

      CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
        menu_item_id: mi.id,
        product_id: product.id,
        quantity: Decimal.new("20")
      })

      order = insert_order(%{status: "sent"})
      # Simulate stock was deducted (qty 2 × 20g = 40g deducted, now at 60)
      CRC.Repo.update_all(
        CRC.Inventory.Product |> where([p], p.id == ^product.id),
        set: [stock_quantity: Decimal.new("60")]
      )

      item = insert_order_item(order.id, mi.id, %{status: "sent", quantity: 2})
      {:ok, _} = Orders.cancel_item(item, :not_prepared)

      reloaded = CRC.Repo.get!(CRC.Inventory.Product, product.id)
      # 60 + (20 × 2) = 100
      assert Decimal.equal?(reloaded.stock_quantity, Decimal.new("100"))
    end

    test "broadcasts order_updated" do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})

      {:ok, _} = Orders.cancel_item(item, :not_prepared)
      order_id = order.id
      assert_receive {:order_updated, ^order_id}
    end

    test "broadcasts stock_updated" do
      Phoenix.PubSub.subscribe(CRC.PubSub, "menu_stock")
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})

      {:ok, _} = Orders.cancel_item(item, :not_prepared)
      assert_receive :stock_updated
    end
  end

  # ---------------------------------------------------------------------------
  # cancel_item/2 — :waste
  # ---------------------------------------------------------------------------

  describe "cancel_item/2 :waste" do
    test "sets item status to 'cancelled_waste'" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})

      assert {:ok, updated} = Orders.cancel_item(item, :waste)
      assert updated.status == "cancelled_waste"
    end

    test "does NOT restore stock when cancelled as waste" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)

      product =
        CRC.Repo.insert!(%CRC.Inventory.Product{
          name: "Leche Test #{System.unique_integer()}",
          category: "lacteos",
          unit: "ml",
          net_cost: Decimal.new("1.00"),
          stock_quantity: Decimal.new("60"),
          active: true
        })

      CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
        menu_item_id: mi.id,
        product_id: product.id,
        quantity: Decimal.new("20")
      })

      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent", quantity: 2})

      {:ok, _} = Orders.cancel_item(item, :waste)

      reloaded = CRC.Repo.get!(CRC.Inventory.Product, product.id)
      # Stock unchanged — still 60
      assert Decimal.equal?(reloaded.stock_quantity, Decimal.new("60"))
    end

    test "broadcasts order_updated" do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "sent"})

      {:ok, _} = Orders.cancel_item(item, :waste)
      order_id = order.id
      assert_receive {:order_updated, ^order_id}
    end
  end

  # ---------------------------------------------------------------------------
  # calculate_order_total — cancelled items excluded
  # ---------------------------------------------------------------------------

  describe "calculate_order_total/1 with cancelled items" do
    test "excludes cancelled items from total" do
      cat = insert_category()
      mi = CRC.Repo.insert!(%CRC.Catalog.MenuItem{
        name: "Item $100", price: Decimal.new(100),
        category_id: cat.id, position: 1, available: true, featured: false
      })
      order = insert_order()
      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 1, status: "sent"
      })
      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 1, status: "cancelled"
      })
      loaded = Orders.get_order!(order.id)
      assert Decimal.equal?(Orders.calculate_order_total(loaded), Decimal.new(100))
    end

    test "excludes cancelled_waste items from total" do
      cat = insert_category()
      mi = CRC.Repo.insert!(%CRC.Catalog.MenuItem{
        name: "Item $50", price: Decimal.new(50),
        category_id: cat.id, position: 1, available: true, featured: false
      })
      order = insert_order()
      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 1, status: "sent"
      })
      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 1, status: "cancelled_waste"
      })
      loaded = Orders.get_order!(order.id)
      assert Decimal.equal?(Orders.calculate_order_total(loaded), Decimal.new(50))
    end
  end

  # ---------------------------------------------------------------------------
  # employee_stats/1
  # ---------------------------------------------------------------------------

  describe "employee_stats/1" do
    setup do
      cat = insert_category(%{kind: "food"})
      mi = insert_menu_item(cat.id, %{name: "Tacos", price: "60.00"})

      kitchen_staff = insert_user(%{name: "Carlos Cocina", station: "cocina"})
      waiter = insert_user(%{name: "Ana Mesera", station: "sala"})

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      sent_at = DateTime.add(now, -600, :second)   # 10 min ago
      ready_at = DateTime.add(now, -300, :second)  # 5 min ago (prep = 5 min = 300s)
      inserted_at = DateTime.add(now, -1200, :second) # 20 min ago

      order =
        CRC.Repo.insert!(%Order{
          customer_name: "Mesa 1",
          status: "closed",
          payment_method: "efectivo",
          total: Decimal.new("60.00"),
          amount_paid: Decimal.new("60.00"),
          closed_at: now,
          user_id: waiter.id,
          closed_by_id: waiter.id,
          inserted_at: inserted_at,
          updated_at: now
        })

      _item =
        CRC.Repo.insert!(%OrderItem{
          order_id: order.id,
          menu_item_id: mi.id,
          quantity: 1,
          status: "ready",
          sent_at: sent_at,
          ready_at: ready_at,
          marked_ready_by_id: kitchen_staff.id
        })

      %{order: order, kitchen_staff: kitchen_staff, waiter: waiter, now: now,
        sent_at: sent_at, ready_at: ready_at, inserted_at: inserted_at}
    end

    test "returns station stats for kitchen staff who marked items ready", %{kitchen_staff: staff, sent_at: sent_at, ready_at: ready_at} do
      %{station_stats: station_stats} = Orders.employee_stats(:all)

      assert [stat] = station_stats
      assert stat.user_id == staff.id
      assert stat.name == "Carlos Cocina"
      assert stat.station == "cocina"
      assert stat.count == 1
      assert stat.avg == DateTime.diff(ready_at, sent_at, :second)
    end

    test "returns waiter stats for waiters who created and closed orders", %{waiter: waiter, now: now, inserted_at: inserted_at} do
      %{waiter_stats: waiter_stats} = Orders.employee_stats(:all)

      assert [stat] = waiter_stats
      assert stat.user_id == waiter.id
      assert stat.name == "Ana Mesera"
      assert stat.count == 1
      assert stat.avg == DateTime.diff(now, inserted_at, :second)
    end

    test "returns empty lists when no closed orders exist" do
      # Use a range that is far in the future to get no results
      future = Date.utc_today() |> Date.add(365)
      future2 = Date.utc_today() |> Date.add(366)
      %{station_stats: ss, waiter_stats: ws} = Orders.employee_stats({:range, future, future2})

      assert ss == []
      assert ws == []
    end

    test "employee appears once even with multiple items", %{order: order, kitchen_staff: staff} do
      cat2 = insert_category(%{name: "Antojitos", kind: "food"})
      mi2 = insert_menu_item(cat2.id, %{name: "Sopa", price: "50.00"})
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      sent = DateTime.add(now, -120, :second)
      ready = DateTime.add(now, -60, :second)

      CRC.Repo.insert!(%OrderItem{
        order_id: order.id,
        menu_item_id: mi2.id,
        quantity: 1,
        status: "ready",
        sent_at: sent,
        ready_at: ready,
        marked_ready_by_id: staff.id
      })

      %{station_stats: station_stats} = Orders.employee_stats(:all)
      assert length(station_stats) == 1
      assert hd(station_stats).count == 2
    end
  end

  # ---------------------------------------------------------------------------
  # list_closed_orders/1 — period filtering
  # ---------------------------------------------------------------------------

  describe "list_closed_orders/1" do
    defp insert_closed_order_at(inserted_at) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      CRC.Repo.insert!(%Order{
        customer_name: "Historial #{System.unique_integer()}",
        status: "closed",
        payment_method: "tarjeta",
        total: Decimal.new("80.00"),
        closed_at: now,
        inserted_at: inserted_at,
        updated_at: now
      })
    end

    test "returns all closed orders with :all" do
      order = insert_closed_order_at(DateTime.utc_now() |> DateTime.truncate(:second))
      ids = Orders.list_closed_orders(:all) |> Enum.map(& &1.id)
      assert order.id in ids
    end

    test "does not return open orders" do
      open = insert_order(%{status: "open"})
      ids = Orders.list_closed_orders(:all) |> Enum.map(& &1.id)
      refute open.id in ids
    end

    test "returns orders from this week with :week" do
      recent = DateTime.utc_now() |> DateTime.add(-2, :day) |> DateTime.truncate(:second)
      order = insert_closed_order_at(recent)
      ids = Orders.list_closed_orders(:week) |> Enum.map(& &1.id)
      assert order.id in ids
    end

    test "excludes orders older than 7 days with :week" do
      old = DateTime.utc_now() |> DateTime.add(-10, :day) |> DateTime.truncate(:second)
      order = insert_closed_order_at(old)
      ids = Orders.list_closed_orders(:week) |> Enum.map(& &1.id)
      refute order.id in ids
    end

    test "returns orders from this month with :month" do
      recent = DateTime.utc_now() |> DateTime.add(-15, :day) |> DateTime.truncate(:second)
      order = insert_closed_order_at(recent)
      ids = Orders.list_closed_orders(:month) |> Enum.map(& &1.id)
      assert order.id in ids
    end

    test "excludes orders older than 30 days with :month" do
      old = DateTime.utc_now() |> DateTime.add(-35, :day) |> DateTime.truncate(:second)
      order = insert_closed_order_at(old)
      ids = Orders.list_closed_orders(:month) |> Enum.map(& &1.id)
      refute order.id in ids
    end

    test "filters by date range {:range, date_from, date_to}" do
      target_dt = ~U[2026-03-10 12:00:00Z]
      order = insert_closed_order_at(target_dt)

      ids =
        Orders.list_closed_orders({:range, ~D[2026-03-10], ~D[2026-03-10]})
        |> Enum.map(& &1.id)

      assert order.id in ids
    end

    test "excludes orders outside date range" do
      outside_dt = ~U[2026-03-05 12:00:00Z]
      order = insert_closed_order_at(outside_dt)

      ids =
        Orders.list_closed_orders({:range, ~D[2026-03-10], ~D[2026-03-15]})
        |> Enum.map(& &1.id)

      refute order.id in ids
    end

    # REGRESSION: Timezone bug — "Hoy" showing $0 when server is UTC, café is UTC-6
    test ":today returns orders created within current local day (UTC-6 offset)" do
      # An order created right now (UTC) must appear in :today regardless of local offset
      # because 'now' is always within 'today' in any negative offset
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      order = insert_closed_order_at(now)
      ids = Orders.list_closed_orders(:today) |> Enum.map(& &1.id)
      assert order.id in ids
    end

    test ":today excludes orders from 48 hours ago" do
      old = DateTime.utc_now() |> DateTime.add(-48, :hour) |> DateTime.truncate(:second)
      order = insert_closed_order_at(old)
      ids = Orders.list_closed_orders(:today) |> Enum.map(& &1.id)
      refute order.id in ids
    end

    test "returns newest first" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      older = insert_closed_order_at(DateTime.add(now, -3600, :second))
      newer = insert_closed_order_at(now)
      [first | _] = Orders.list_closed_orders(:all) |> Enum.filter(&(&1.id in [older.id, newer.id]))
      assert first.id == newer.id
    end
  end

  # ---------------------------------------------------------------------------
  # list_orders_history/2
  # ---------------------------------------------------------------------------

  describe "list_orders_history/2" do
    test "returns closed orders with user preloaded" do
      user = insert_user(%{name: "Mesero Historial"})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      CRC.Repo.insert!(%Order{
        customer_name: "Test Hist",
        status: "closed",
        payment_method: "efectivo",
        amount_paid: Decimal.new("50.00"),
        total: Decimal.new("50.00"),
        closed_at: now,
        user_id: user.id,
        inserted_at: now,
        updated_at: now
      })

      results = Orders.list_orders_history(:all)
      [loaded | _] = Enum.filter(results, &(&1.user_id == user.id))
      assert loaded.user.name == "Mesero Historial"
    end

    test "filters by user_id when provided" do
      u1 = insert_user(%{name: "User A"})
      u2 = insert_user(%{name: "User B"})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      o1 = CRC.Repo.insert!(%Order{
        customer_name: "Para U1", status: "closed", payment_method: "tarjeta",
        total: Decimal.new("40.00"), closed_at: now, user_id: u1.id,
        inserted_at: now, updated_at: now
      })
      CRC.Repo.insert!(%Order{
        customer_name: "Para U2", status: "closed", payment_method: "tarjeta",
        total: Decimal.new("40.00"), closed_at: now, user_id: u2.id,
        inserted_at: now, updated_at: now
      })

      results = Orders.list_orders_history(:all, user_id: u1.id)
      ids = Enum.map(results, & &1.id)
      assert o1.id in ids
      refute Enum.any?(results, &(&1.user_id == u2.id))
    end

    test "returns all orders when user_id is nil (admin view)" do
      u1 = insert_user(%{name: "Uno"})
      u2 = insert_user(%{name: "Dos"})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      o1 = CRC.Repo.insert!(%Order{
        customer_name: "Comanda A", status: "closed", payment_method: "tarjeta",
        total: Decimal.new("30.00"), closed_at: now, user_id: u1.id,
        inserted_at: now, updated_at: now
      })
      o2 = CRC.Repo.insert!(%Order{
        customer_name: "Comanda B", status: "closed", payment_method: "tarjeta",
        total: Decimal.new("30.00"), closed_at: now, user_id: u2.id,
        inserted_at: now, updated_at: now
      })

      ids = Orders.list_orders_history(:all) |> Enum.map(& &1.id)
      assert o1.id in ids
      assert o2.id in ids
    end

    test "excludes open orders" do
      open = insert_order(%{status: "open"})
      ids = Orders.list_orders_history(:all) |> Enum.map(& &1.id)
      refute open.id in ids
    end
  end

  # ---------------------------------------------------------------------------
  # list_waiters_with_history/0
  # ---------------------------------------------------------------------------

  describe "list_waiters_with_history/0" do
    test "returns users who created at least one closed order" do
      user = insert_user(%{name: "Mesero Con Historial"})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      CRC.Repo.insert!(%Order{
        customer_name: "Comanda", status: "closed", payment_method: "tarjeta",
        total: Decimal.new("50.00"), closed_at: now, user_id: user.id,
        inserted_at: now, updated_at: now
      })

      results = Orders.list_waiters_with_history()
      assert Enum.any?(results, &(&1.id == user.id))
    end

    test "does not return users without closed orders" do
      user = insert_user(%{name: "Sin Historial"})
      # No closed orders for this user
      results = Orders.list_waiters_with_history()
      refute Enum.any?(results, &(&1.id == user.id))
    end

    test "returns each user only once even with multiple closed orders" do
      user = insert_user(%{name: "Mesero Duplicado"})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for _ <- 1..3 do
        CRC.Repo.insert!(%Order{
          customer_name: "Comanda #{System.unique_integer()}",
          status: "closed", payment_method: "tarjeta",
          total: Decimal.new("50.00"), closed_at: now, user_id: user.id,
          inserted_at: now, updated_at: now
        })
      end

      results = Orders.list_waiters_with_history()
      count = Enum.count(results, &(&1.id == user.id))
      assert count == 1
    end
  end

  # ---------------------------------------------------------------------------
  # sales_summary/1
  # ---------------------------------------------------------------------------

  describe "sales_summary/1" do
    defp insert_closed_order_with_total(total, payment_method \\ "tarjeta") do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      CRC.Repo.insert!(%Order{
        customer_name: "Ventas #{System.unique_integer()}",
        status: "closed",
        payment_method: payment_method,
        total: Decimal.new(total),
        closed_at: now,
        inserted_at: now,
        updated_at: now
      })
    end

    test "returns zeros when no closed orders" do
      future = Date.utc_today() |> Date.add(365)
      future2 = Date.add(future, 1)
      summary = Orders.sales_summary({:range, future, future2})

      assert Decimal.equal?(summary.total_revenue, Decimal.new(0))
      assert summary.order_count == 0
      assert Decimal.equal?(summary.avg_ticket, Decimal.new(0))
    end

    test "calculates total revenue" do
      o1 = insert_closed_order_with_total("100.00")
      o2 = insert_closed_order_with_total("200.00")

      summary = Orders.sales_summary(:all)
      ids_total = Enum.filter(
        Orders.list_closed_orders(:all),
        &(&1.id in [o1.id, o2.id])
      ) |> Enum.reduce(Decimal.new(0), &Decimal.add(&2, &1.total))

      assert Decimal.compare(summary.total_revenue, ids_total) != :lt
    end

    test "calculates order_count" do
      before_count = Orders.sales_summary(:all).order_count
      insert_closed_order_with_total("50.00")
      insert_closed_order_with_total("50.00")
      after_count = Orders.sales_summary(:all).order_count
      assert after_count == before_count + 2
    end

    test "calculates avg_ticket" do
      future = Date.utc_today() |> Date.add(100)
      future2 = Date.add(future, 30)

      # Insert directly with a future date to isolate
      d1 = ~U[2027-06-01 10:00:00Z]
      CRC.Repo.insert!(%Order{
        customer_name: "Avg A", status: "closed", payment_method: "tarjeta",
        total: Decimal.new("100.00"), closed_at: d1,
        inserted_at: d1, updated_at: d1
      })
      CRC.Repo.insert!(%Order{
        customer_name: "Avg B", status: "closed", payment_method: "tarjeta",
        total: Decimal.new("200.00"), closed_at: d1,
        inserted_at: d1, updated_at: d1
      })

      summary = Orders.sales_summary({:range, ~D[2027-06-01], ~D[2027-06-01]})
      assert Decimal.equal?(summary.avg_ticket, Decimal.new("150.00"))
    end

    test "groups revenue by payment method" do
      d = ~U[2027-07-01 10:00:00Z]
      CRC.Repo.insert!(%Order{
        customer_name: "Efectivo 1", status: "closed", payment_method: "efectivo",
        total: Decimal.new("300.00"), amount_paid: Decimal.new("300.00"),
        closed_at: d, inserted_at: d, updated_at: d
      })
      CRC.Repo.insert!(%Order{
        customer_name: "Tarjeta 1", status: "closed", payment_method: "tarjeta",
        total: Decimal.new("150.00"),
        closed_at: d, inserted_at: d, updated_at: d
      })

      summary = Orders.sales_summary({:range, ~D[2027-07-01], ~D[2027-07-01]})
      assert Decimal.equal?(summary.by_method["efectivo"], Decimal.new("300.00"))
      assert Decimal.equal?(summary.by_method["tarjeta"], Decimal.new("150.00"))
    end
  end

  # ---------------------------------------------------------------------------
  # financial_summary/1
  # ---------------------------------------------------------------------------

  describe "financial_summary/1" do
    # Isolated date so no other tests interfere
    @fin_date ~U[2027-08-15 12:00:00Z]
    @fin_date_range {:range, ~D[2027-08-15], ~D[2027-08-15]}

    defp insert_product_with_cost(net_cost) do
      CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "Ingrediente #{System.unique_integer()}",
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

    test "returns zeros when no closed orders in period" do
      future = {:range, ~D[2030-01-01], ~D[2030-01-02]}
      summary = Orders.financial_summary(future)

      assert Decimal.equal?(summary.revenue, Decimal.new(0))
      assert Decimal.equal?(summary.cogs, Decimal.new(0))
      assert Decimal.equal?(summary.gross_profit, Decimal.new(0))
      assert Decimal.equal?(summary.waste_cost, Decimal.new(0))
      assert Decimal.equal?(summary.net_profit, Decimal.new(0))
    end

    test "calculates revenue from closed orders" do
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{price: "100.00"})

      order = CRC.Repo.insert!(%Order{
        customer_name: "Rev Test",
        status: "closed", payment_method: "tarjeta",
        total: Decimal.new("100.00"),
        closed_at: @fin_date, inserted_at: @fin_date, updated_at: @fin_date
      })
      CRC.Repo.insert!(%OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 1,
        status: "served", inserted_at: @fin_date, updated_at: @fin_date
      })

      summary = Orders.financial_summary(@fin_date_range)
      assert Decimal.equal?(summary.revenue, Decimal.new("100.00"))
    end

    test "calculates COGS as ingredient_qty × net_cost × order_qty" do
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{price: "80.00"})
      product = insert_product_with_cost("5.00")
      # 10 units of ingredient per portion, net_cost 5.00 → cost per portion = 50.00
      link_ingredient(mi.id, product.id, "10")

      order = CRC.Repo.insert!(%Order{
        customer_name: "COGS Test",
        status: "closed", payment_method: "tarjeta",
        total: Decimal.new("80.00"),
        closed_at: @fin_date, inserted_at: @fin_date, updated_at: @fin_date
      })
      # qty 2 → COGS = 2 × 10 × 5.00 = 100.00
      CRC.Repo.insert!(%OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 2,
        status: "served", inserted_at: @fin_date, updated_at: @fin_date
      })

      summary = Orders.financial_summary(@fin_date_range)
      assert Decimal.equal?(summary.cogs, Decimal.new("100.00"))
    end

    test "calculates gross_profit = revenue - cogs" do
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{price: "50.00"})
      product = insert_product_with_cost("2.00")
      link_ingredient(mi.id, product.id, "5")
      # COGS per unit = 5 × 2.00 = 10.00; revenue = 50.00; gross = 40.00

      d = ~U[2027-08-16 12:00:00Z]
      order = CRC.Repo.insert!(%Order{
        customer_name: "Profit Test",
        status: "closed", payment_method: "tarjeta",
        total: Decimal.new("50.00"),
        closed_at: d, inserted_at: d, updated_at: d
      })
      CRC.Repo.insert!(%OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 1,
        status: "served", inserted_at: d, updated_at: d
      })

      summary = Orders.financial_summary({:range, ~D[2027-08-16], ~D[2027-08-16]})
      assert Decimal.equal?(summary.gross_profit, Decimal.new("40.00"))
    end

    test "calculates margin_pct as percentage of revenue" do
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{price: "100.00"})
      product = insert_product_with_cost("2.00")
      link_ingredient(mi.id, product.id, "10")
      # COGS = 10 × 2.00 = 20.00; revenue = 100.00; gross = 80.00; margin = 80%

      d = ~U[2027-08-17 12:00:00Z]
      order = CRC.Repo.insert!(%Order{
        customer_name: "Margin Test",
        status: "closed", payment_method: "tarjeta",
        total: Decimal.new("100.00"),
        closed_at: d, inserted_at: d, updated_at: d
      })
      CRC.Repo.insert!(%OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 1,
        status: "served", inserted_at: d, updated_at: d
      })

      summary = Orders.financial_summary({:range, ~D[2027-08-17], ~D[2027-08-17]})
      assert Decimal.equal?(summary.margin_pct, Decimal.new("80.0"))
    end

    test "calculates waste_cost from cancelled_waste items" do
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{price: "60.00"})
      product = insert_product_with_cost("3.00")
      link_ingredient(mi.id, product.id, "4")
      # waste cost = 1 × 4 × 3.00 = 12.00

      d = ~U[2027-08-18 12:00:00Z]
      order = CRC.Repo.insert!(%Order{
        customer_name: "Waste Test",
        status: "sent", payment_method: nil,
        total: nil,
        inserted_at: d, updated_at: d
      })
      CRC.Repo.insert!(%OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 1,
        status: "cancelled_waste", inserted_at: d, updated_at: d
      })

      summary = Orders.financial_summary({:range, ~D[2027-08-18], ~D[2027-08-18]})
      assert Decimal.equal?(summary.waste_cost, Decimal.new("12.00"))
    end

    test "net_profit = gross_profit - waste_cost" do
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{price: "100.00"})
      product = insert_product_with_cost("1.00")
      link_ingredient(mi.id, product.id, "10")
      # COGS = 10.00; revenue = 100.00; gross = 90.00

      d = ~U[2027-08-19 12:00:00Z]
      order = CRC.Repo.insert!(%Order{
        customer_name: "Net Test",
        status: "closed", payment_method: "tarjeta",
        total: Decimal.new("100.00"),
        closed_at: d, inserted_at: d, updated_at: d
      })
      CRC.Repo.insert!(%OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 1,
        status: "served", inserted_at: d, updated_at: d
      })
      # Waste: 1 item × 10 × 1.00 = 10.00
      waste_order = CRC.Repo.insert!(%Order{
        customer_name: "Waste Order",
        status: "sent", payment_method: nil, total: nil,
        inserted_at: d, updated_at: d
      })
      CRC.Repo.insert!(%OrderItem{
        order_id: waste_order.id, menu_item_id: mi.id, quantity: 1,
        status: "cancelled_waste", inserted_at: d, updated_at: d
      })

      summary = Orders.financial_summary({:range, ~D[2027-08-19], ~D[2027-08-19]})
      # gross = 90.00, waste = 10.00, net = 80.00
      assert Decimal.equal?(summary.net_profit, Decimal.new("80.00"))
    end

    test "excludes cancelled (non-waste) items from COGS" do
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{price: "50.00"})
      product = insert_product_with_cost("5.00")
      link_ingredient(mi.id, product.id, "2")

      d = ~U[2027-08-20 12:00:00Z]
      order = CRC.Repo.insert!(%Order{
        customer_name: "Cancel Test",
        status: "closed", payment_method: "tarjeta",
        total: Decimal.new("0.00"),
        closed_at: d, inserted_at: d, updated_at: d
      })
      # Only cancelled item — should not contribute to COGS
      CRC.Repo.insert!(%OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 1,
        status: "cancelled", inserted_at: d, updated_at: d
      })

      summary = Orders.financial_summary({:range, ~D[2027-08-20], ~D[2027-08-20]})
      assert Decimal.equal?(summary.cogs, Decimal.new("0"))
    end
  end

  # ---------------------------------------------------------------------------
  # top_wasted_items/2
  # ---------------------------------------------------------------------------

  describe "top_wasted_items/2" do
    test "returns items sorted by wasted quantity descending" do
      cat = insert_category()
      mi_a = insert_menu_item(cat.id, %{name: "Platillo A Top Waste"})
      mi_b = insert_menu_item(cat.id, %{name: "Platillo B Low Waste"})

      product = CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "Ing Waste #{System.unique_integer()}",
        category: "otros", unit: "g",
        net_cost: Decimal.new("1.00"),
        stock_quantity: Decimal.new("500"), active: true
      })

      CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
        menu_item_id: mi_a.id, product_id: product.id, quantity: Decimal.new("1")
      })
      CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
        menu_item_id: mi_b.id, product_id: product.id, quantity: Decimal.new("1")
      })

      d = ~U[2027-09-01 10:00:00Z]
      order = CRC.Repo.insert!(%Order{
        customer_name: "Waste Order", status: "sent",
        payment_method: nil, total: nil, inserted_at: d, updated_at: d
      })

      # mi_a wasted 3, mi_b wasted 1
      CRC.Repo.insert!(%OrderItem{
        order_id: order.id, menu_item_id: mi_a.id, quantity: 3,
        status: "cancelled_waste", inserted_at: d, updated_at: d
      })
      CRC.Repo.insert!(%OrderItem{
        order_id: order.id, menu_item_id: mi_b.id, quantity: 1,
        status: "cancelled_waste", inserted_at: d, updated_at: d
      })

      results = Orders.top_wasted_items({:range, ~D[2027-09-01], ~D[2027-09-01]})
      names = Enum.map(results, & &1.name)

      assert "Platillo A Top Waste" in names
      assert "Platillo B Low Waste" in names
      # A should come before B (sorted by qty desc)
      a_pos = Enum.find_index(names, &(&1 == "Platillo A Top Waste"))
      b_pos = Enum.find_index(names, &(&1 == "Platillo B Low Waste"))
      assert a_pos < b_pos
    end

    test "calculates cost for each wasted item" do
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Platillo Costo Waste"})
      product = CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "Ing Cost #{System.unique_integer()}",
        category: "otros", unit: "ml",
        net_cost: Decimal.new("4.00"),
        stock_quantity: Decimal.new("500"), active: true
      })
      CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
        menu_item_id: mi.id, product_id: product.id, quantity: Decimal.new("5")
      })

      d = ~U[2027-09-02 10:00:00Z]
      order = CRC.Repo.insert!(%Order{
        customer_name: "Cost Waste", status: "sent",
        payment_method: nil, total: nil, inserted_at: d, updated_at: d
      })
      # qty=2 → cost = 2 × 5 × 4.00 = 40.00
      CRC.Repo.insert!(%OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 2,
        status: "cancelled_waste", inserted_at: d, updated_at: d
      })

      results = Orders.top_wasted_items({:range, ~D[2027-09-02], ~D[2027-09-02]})
      item = Enum.find(results, &(&1.name == "Platillo Costo Waste"))
      refute is_nil(item)
      assert Decimal.equal?(item.cost, Decimal.new("40.00"))
    end

    test "returns empty list when no waste in period" do
      future = {:range, ~D[2035-01-01], ~D[2035-01-01]}
      assert Orders.top_wasted_items(future) == []
    end

    test "respects the limit parameter" do
      cat = insert_category()
      d = ~U[2027-09-03 10:00:00Z]
      order = CRC.Repo.insert!(%Order{
        customer_name: "Limit Test", status: "sent",
        payment_method: nil, total: nil, inserted_at: d, updated_at: d
      })
      product = CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "Ing Limit #{System.unique_integer()}",
        category: "otros", unit: "g",
        net_cost: Decimal.new("1.00"),
        stock_quantity: Decimal.new("999"), active: true
      })

      for _ <- 1..5 do
        mi = insert_menu_item(cat.id, %{name: "Item Limit #{System.unique_integer()}"})
        CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
          menu_item_id: mi.id, product_id: product.id, quantity: Decimal.new("1")
        })
        CRC.Repo.insert!(%OrderItem{
          order_id: order.id, menu_item_id: mi.id, quantity: 1,
          status: "cancelled_waste", inserted_at: d, updated_at: d
        })
      end

      results = Orders.top_wasted_items({:range, ~D[2027-09-03], ~D[2027-09-03]}, 3)
      assert length(results) == 3
    end
  end

  # ---------------------------------------------------------------------------
  # top_selling_items/2
  # ---------------------------------------------------------------------------

  describe "top_selling_items/2" do
    test "returns items with highest total quantity sold" do
      cat = insert_category()
      mi_top = insert_menu_item(cat.id, %{name: "Best Seller Test"})
      mi_low = insert_menu_item(cat.id, %{name: "Slow Seller Test"})

      d = ~U[2027-10-01 10:00:00Z]
      order = CRC.Repo.insert!(%Order{
        customer_name: "Top Seller", status: "closed",
        payment_method: "tarjeta", total: Decimal.new("100.00"),
        closed_at: d, inserted_at: d, updated_at: d
      })
      CRC.Repo.insert!(%OrderItem{
        order_id: order.id, menu_item_id: mi_top.id, quantity: 5,
        status: "served", inserted_at: d, updated_at: d
      })
      CRC.Repo.insert!(%OrderItem{
        order_id: order.id, menu_item_id: mi_low.id, quantity: 1,
        status: "served", inserted_at: d, updated_at: d
      })

      results = Orders.top_selling_items({:range, ~D[2027-10-01], ~D[2027-10-01]})
      names = Enum.map(results, fn {name, _} -> name end)
      assert "Best Seller Test" in names
      top_pos = Enum.find_index(names, &(&1 == "Best Seller Test"))
      low_pos = Enum.find_index(names, &(&1 == "Slow Seller Test"))
      assert top_pos < low_pos
    end

    test "returns empty list when no closed orders" do
      future = {:range, ~D[2035-06-01], ~D[2035-06-01]}
      assert Orders.top_selling_items(future) == []
    end
  end

  # ---------------------------------------------------------------------------
  # mark_item_served/2
  # ---------------------------------------------------------------------------

  describe "mark_item_served/2" do
    test "sets item status to 'served'" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "ready"})

      assert {:ok, updated} = Orders.mark_item_served(item.id)
      assert updated.status == "served"
    end

    test "sets served_at timestamp" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent"})
      item = insert_order_item(order.id, mi.id, %{status: "ready"})

      {:ok, updated} = Orders.mark_item_served(item.id)
      refute is_nil(updated.served_at)
    end

    test "records served_by_id when provided" do
      user = insert_user()
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order(%{status: "sent", user_id: user.id})
      item = insert_order_item(order.id, mi.id, %{status: "ready"})

      {:ok, updated} = Orders.mark_item_served(item.id, user.id)
      assert updated.served_by_id == user.id
    end

    test "served_by_id is nil when not provided" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      item = insert_order_item(order.id, mi.id, %{status: "ready"})

      {:ok, updated} = Orders.mark_item_served(item.id)
      assert is_nil(updated.served_by_id)
    end

    test "returns {:error, :not_found} for unknown item id" do
      assert {:error, :not_found} = Orders.mark_item_served(0)
    end

    test "broadcasts order_updated" do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()
      item = insert_order_item(order.id, mi.id, %{status: "ready"})

      {:ok, _} = Orders.mark_item_served(item.id)
      order_id = order.id
      assert_receive {:order_updated, ^order_id}
    end

    test "can serve item in any active status (pending, sent, ready)" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      order = insert_order()

      for status <- ["pending", "sent", "ready"] do
        item = insert_order_item(order.id, mi.id, %{status: status})
        assert {:ok, updated} = Orders.mark_item_served(item.id)
        assert updated.status == "served"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # toggle_exclusion/2 — ingredient modifier (sin jitomate)
  # ---------------------------------------------------------------------------

  describe "toggle_exclusion/2" do
    defp insert_product(overrides \\ %{}) do
      CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "Prod #{System.unique_integer()}",
        category: "verduras",
        unit: "g",
        net_cost: Decimal.new("1.00"),
        stock_quantity: Decimal.new("500"),
        active: true
      } |> Map.merge(overrides))
    end

    defp link_ingredient_to_item(menu_item_id, product_id, qty \\ "10") do
      CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
        menu_item_id: menu_item_id,
        product_id: product_id,
        quantity: Decimal.new(qty)
      })
    end

    test "adds exclusion record when ingredient is not yet excluded" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      product = insert_product()
      link_ingredient_to_item(mi.id, product.id)
      order = insert_order()
      item = insert_order_item(order.id, mi.id)

      assert {:ok, :added} = Orders.toggle_exclusion(item.id, product.id)

      excl = CRC.Repo.get_by!(CRC.Orders.OrderItemExclusion,
        order_item_id: item.id, product_id: product.id)
      assert excl.order_item_id == item.id
      assert excl.product_id == product.id
    end

    test "removes exclusion record when ingredient is already excluded" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      product = insert_product()
      link_ingredient_to_item(mi.id, product.id)
      order = insert_order()
      item = insert_order_item(order.id, mi.id)

      # Add exclusion first
      {:ok, :added} = Orders.toggle_exclusion(item.id, product.id)
      # Toggle again → removes it
      assert {:ok, :removed} = Orders.toggle_exclusion(item.id, product.id)

      assert is_nil(CRC.Repo.get_by(CRC.Orders.OrderItemExclusion,
        order_item_id: item.id, product_id: product.id))
    end

    test "toggle is idempotent: add → remove → add works correctly" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      product = insert_product()
      link_ingredient_to_item(mi.id, product.id)
      order = insert_order()
      item = insert_order_item(order.id, mi.id)

      assert {:ok, :added}   = Orders.toggle_exclusion(item.id, product.id)
      assert {:ok, :removed} = Orders.toggle_exclusion(item.id, product.id)
      assert {:ok, :added}   = Orders.toggle_exclusion(item.id, product.id)

      # After 3 toggles, should be excluded again
      assert CRC.Repo.get_by(CRC.Orders.OrderItemExclusion,
        order_item_id: item.id, product_id: product.id)
    end

    test "multiple different ingredients can each be toggled independently" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      prod_a = insert_product(%{name: "Jitomate #{System.unique_integer()}"})
      prod_b = insert_product(%{name: "Lechuga #{System.unique_integer()}"})
      link_ingredient_to_item(mi.id, prod_a.id)
      link_ingredient_to_item(mi.id, prod_b.id)
      order = insert_order()
      item = insert_order_item(order.id, mi.id)

      {:ok, :added} = Orders.toggle_exclusion(item.id, prod_a.id)
      # prod_b NOT excluded

      excls = CRC.Repo.all(from e in CRC.Orders.OrderItemExclusion,
        where: e.order_item_id == ^item.id)
      excluded_ids = Enum.map(excls, & &1.product_id)

      assert prod_a.id in excluded_ids
      refute prod_b.id in excluded_ids
    end
  end

  # ---------------------------------------------------------------------------
  # Inventory deduction respects exclusions (send_to_kitchen)
  # ---------------------------------------------------------------------------

  describe "send_to_kitchen — exclusion-aware inventory deduction" do
    defp insert_stocked_product(name, stock \\ "1000") do
      CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "#{name}_#{System.unique_integer()}",
        category: "insumos",
        unit: "g",
        net_cost: Decimal.new("1.00"),
        stock_quantity: Decimal.new(stock),
        active: true
      })
    end

    defp link_ing(menu_item_id, product_id, qty) do
      CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
        menu_item_id: menu_item_id,
        product_id: product_id,
        quantity: Decimal.new(qty)
      })
    end

    defp current_stock(product_id) do
      CRC.Repo.one!(from p in CRC.Inventory.Product,
        where: p.id == ^product_id, select: p.stock_quantity)
    end

    test "excluded ingredient is NOT deducted from stock when sent to kitchen" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      jitomate = insert_stocked_product("jitomate")
      lechuga  = insert_stocked_product("lechuga")
      link_ing(mi.id, jitomate.id, "50")   # 50g per unit
      link_ing(mi.id, lechuga.id, "30")    # 30g per unit

      order = insert_order()
      item = insert_order_item(order.id, mi.id)

      # Customer: sin jitomate
      {:ok, :added} = Orders.toggle_exclusion(item.id, jitomate.id)

      order = Orders.get_order!(order.id)
      {:ok, _} = Orders.send_to_kitchen(order)

      # Lechuga deducted normally: 1000 - 30 = 970
      assert Decimal.equal?(current_stock(lechuga.id), Decimal.new("970"))
      # Jitomate NOT deducted (excluded): still 1000
      assert Decimal.equal?(current_stock(jitomate.id), Decimal.new("1000"))
    end

    test "non-excluded ingredients are still deducted normally" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      pan    = insert_stocked_product("pan")
      queso  = insert_stocked_product("queso")
      jito   = insert_stocked_product("jito_2")
      link_ing(mi.id, pan.id, "100")
      link_ing(mi.id, queso.id, "40")
      link_ing(mi.id, jito.id, "20")

      order = insert_order()
      item = insert_order_item(order.id, mi.id)

      # Only jito excluded; pan and queso should be deducted
      {:ok, :added} = Orders.toggle_exclusion(item.id, jito.id)

      order = Orders.get_order!(order.id)
      {:ok, _} = Orders.send_to_kitchen(order)

      assert Decimal.equal?(current_stock(pan.id), Decimal.new("900"))   # 1000 - 100
      assert Decimal.equal?(current_stock(queso.id), Decimal.new("960"))  # 1000 - 40
      assert Decimal.equal?(current_stock(jito.id), Decimal.new("1000"))  # not deducted
    end

    test "item with NO exclusions deducts all ingredients (normal behavior unchanged)" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      ingr_a = insert_stocked_product("ingr_a")
      ingr_b = insert_stocked_product("ingr_b")
      link_ing(mi.id, ingr_a.id, "25")
      link_ing(mi.id, ingr_b.id, "10")

      order = insert_order()
      insert_order_item(order.id, mi.id)

      order = Orders.get_order!(order.id)
      {:ok, _} = Orders.send_to_kitchen(order)

      assert Decimal.equal?(current_stock(ingr_a.id), Decimal.new("975"))
      assert Decimal.equal?(current_stock(ingr_b.id), Decimal.new("990"))
    end

    test "exclusion on one order_item does not affect another order_item for same dish" do
      # Two different orders: one has "sin jitomate", the other does not
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      jitomate = insert_stocked_product("jito_cross")
      link_ing(mi.id, jitomate.id, "50")

      # Order A: sin jitomate
      order_a = insert_order(%{customer_name: "Mesa A #{System.unique_integer()}"})
      item_a = insert_order_item(order_a.id, mi.id)
      {:ok, :added} = Orders.toggle_exclusion(item_a.id, jitomate.id)

      # Order B: con jitomate (normal)
      order_b = insert_order(%{customer_name: "Mesa B #{System.unique_integer()}"})
      insert_order_item(order_b.id, mi.id)

      # Send both orders to kitchen
      Orders.send_to_kitchen(Orders.get_order!(order_a.id))
      Orders.send_to_kitchen(Orders.get_order!(order_b.id))

      # Order B deducted 50g, order A did not → net: 1000 - 50 = 950
      assert Decimal.equal?(current_stock(jitomate.id), Decimal.new("950"))
    end
  end

  # ---------------------------------------------------------------------------
  # restore_stock respects exclusions
  # ---------------------------------------------------------------------------

  describe "cancel_item — restore_stock respects exclusions" do
    defp insert_stocked_prod(stock \\ "1000") do
      CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "Prod restore #{System.unique_integer()}",
        category: "insumos",
        unit: "g",
        net_cost: Decimal.new("1.00"),
        stock_quantity: Decimal.new(stock),
        active: true
      })
    end

    defp link_ing2(menu_item_id, product_id, qty) do
      CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
        menu_item_id: menu_item_id,
        product_id: product_id,
        quantity: Decimal.new(qty)
      })
    end

    defp current_stock2(product_id) do
      CRC.Repo.one!(from p in CRC.Inventory.Product,
        where: p.id == ^product_id, select: p.stock_quantity)
    end

    test "excluded ingredient is NOT restored on cancel (it was never deducted)" do
      cat = insert_category()
      mi = insert_menu_item(cat.id)
      jito = insert_stocked_prod("500")
      lech = insert_stocked_prod("500")
      link_ing2(mi.id, jito.id, "20")
      link_ing2(mi.id, lech.id, "15")

      order = insert_order()
      item = insert_order_item(order.id, mi.id)

      # Exclude jitomate before sending
      {:ok, :added} = Orders.toggle_exclusion(item.id, jito.id)
      {:ok, _sent_order} = Orders.send_to_kitchen(Orders.get_order!(order.id))

      # After send: jitomate still 500, lechuga = 485
      assert Decimal.equal?(current_stock2(jito.id), Decimal.new("500"))
      assert Decimal.equal?(current_stock2(lech.id), Decimal.new("485"))

      # Load the sent item struct (cancel_item requires an OrderItem struct)
      sent_item = CRC.Repo.get!(CRC.Orders.OrderItem, item.id)
      {:ok, _} = Orders.cancel_item(sent_item, :not_prepared)

      # Lechuga restored: 485 + 15 = 500
      assert Decimal.equal?(current_stock2(lech.id), Decimal.new("500"))
      # Jitomate unchanged (was excluded, never deducted, nothing to restore)
      assert Decimal.equal?(current_stock2(jito.id), Decimal.new("500"))
    end
  end

  # ---------------------------------------------------------------------------
  # financial_summary COGS respects exclusions
  # ---------------------------------------------------------------------------

  describe "financial_summary COGS — exclusion-aware" do
    @excl_cogs_date ~U[2027-09-20 10:00:00Z]
    @excl_cogs_range {:range, ~D[2027-09-20], ~D[2027-09-20]}

    defp insert_excl_product(net_cost) do
      CRC.Repo.insert!(%CRC.Inventory.Product{
        name: "COGS Excl #{System.unique_integer()}",
        category: "insumos",
        unit: "g",
        net_cost: Decimal.new(net_cost),
        stock_quantity: Decimal.new("9999"),
        active: true
      })
    end

    defp link_excl_ing(menu_item_id, product_id, qty) do
      CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
        menu_item_id: menu_item_id,
        product_id: product_id,
        quantity: Decimal.new(qty)
      })
    end

    test "excluded ingredient is not counted in COGS" do
      # Dish with two ingredients: mozzarella (cost=10, qty=5g) and jitomate (cost=2, qty=8g)
      # Normal COGS = (1×5×10) + (1×8×2) = 50 + 16 = 66
      # With jitomate excluded: COGS = 50 only
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{price: "120.00"})
      mozz = insert_excl_product("10.00")
      jito = insert_excl_product("2.00")
      link_excl_ing(mi.id, mozz.id, "5")
      link_excl_ing(mi.id, jito.id, "8")

      # Insert closed order + order item directly (avoids send/close flow complexity)
      order = CRC.Repo.insert!(%CRC.Orders.Order{
        customer_name: "COGS Excl Test #{System.unique_integer()}",
        status: "closed", payment_method: "tarjeta",
        total: Decimal.new("120.00"),
        closed_at: @excl_cogs_date,
        inserted_at: @excl_cogs_date, updated_at: @excl_cogs_date
      })
      item = CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 1,
        status: "served",
        inserted_at: @excl_cogs_date, updated_at: @excl_cogs_date
      })

      # Customer requested "sin jitomate"
      CRC.Repo.insert!(%CRC.Orders.OrderItemExclusion{
        order_item_id: item.id, product_id: jito.id
      })

      summary = Orders.financial_summary(@excl_cogs_range)

      # mozz: 1 × 5 × 10.00 = 50.00 (jitomate is excluded → not counted)
      assert Decimal.equal?(summary.cogs, Decimal.new("50.00"))
    end

    test "without exclusions COGS counts all ingredients (regression — exclusion filter doesn't break normal case)" do
      # Same setup as above but no exclusion — COGS should be full 66
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{price: "120.00"})
      mozz = insert_excl_product("10.00")
      jito = insert_excl_product("2.00")
      link_excl_ing(mi.id, mozz.id, "5")
      link_excl_ing(mi.id, jito.id, "8")

      d = ~U[2027-09-21 10:00:00Z]
      order = CRC.Repo.insert!(%CRC.Orders.Order{
        customer_name: "COGS Full #{System.unique_integer()}",
        status: "closed", payment_method: "tarjeta",
        total: Decimal.new("120.00"),
        closed_at: d, inserted_at: d, updated_at: d
      })
      CRC.Repo.insert!(%CRC.Orders.OrderItem{
        order_id: order.id, menu_item_id: mi.id, quantity: 1,
        status: "served", inserted_at: d, updated_at: d
      })

      summary = Orders.financial_summary({:range, ~D[2027-09-21], ~D[2027-09-21]})

      # (1 × 5 × 10) + (1 × 8 × 2) = 50 + 16 = 66
      assert Decimal.equal?(summary.cogs, Decimal.new("66.00"))
    end
  end
end
