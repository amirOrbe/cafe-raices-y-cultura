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
  # close_order/1
  # ---------------------------------------------------------------------------

  describe "close_order/1" do
    test "sets order status to 'closed'" do
      order = insert_order(%{status: "ready"})
      {:ok, updated} = Orders.close_order(order)
      assert updated.status == "closed"
    end

    test "excludes closed order from list_active_orders" do
      order = insert_order()
      {:ok, _} = Orders.close_order(order)
      ids = Orders.list_active_orders() |> Enum.map(& &1.id)
      refute order.id in ids
    end

    test "broadcasts order_updated" do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
      order = insert_order()
      {:ok, updated} = Orders.close_order(order)
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

  describe "add_item/0 default arg" do
    test "returns error with no attrs (required fields missing)" do
      assert {:error, _changeset} = Orders.add_item()
    end
  end
end
