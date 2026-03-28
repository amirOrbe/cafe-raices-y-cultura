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
end
