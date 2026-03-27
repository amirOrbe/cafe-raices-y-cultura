defmodule CRC.Orders do
  @moduledoc """
  The Orders context manages comandas: open orders per customer account,
  order items, and real-time notifications to cocina and barra via PubSub.
  """

  import Ecto.Query, warn: false
  alias CRC.Repo
  alias CRC.Orders.{Order, OrderItem}
  alias CRC.Catalog.MenuItemIngredient
  alias CRC.Inventory.Product

  # Both cocina and barra subscribe to this topic
  @pubsub_topic "orders"
  # Waiter menu browsers subscribe to this for real-time stock availability
  @stock_topic "menu_stock"

  # ---------------------------------------------------------------------------
  # Orders
  # ---------------------------------------------------------------------------

  @doc "Returns all orders with status 'open', 'sent', or 'ready'. Preloads items with menu_item + category."
  def list_open_orders do
    Order
    |> where([o], o.status in ["open", "sent", "ready"])
    |> order_by([o], o.inserted_at)
    |> preload(order_items: [menu_item: :category])
    |> Repo.all()
  end

  @doc "Returns active orders (open/sent/ready) for the waiter overview, sorted oldest first."
  def list_active_orders do
    Order
    |> where([o], o.status in ["open", "sent", "ready"])
    |> order_by([o], o.inserted_at)
    |> preload(order_items: [menu_item: :category])
    |> Repo.all()
  end

  @doc "Gets an order by id. Raises if not found. Preloads items with menu_item + category."
  def get_order!(id) do
    Order
    |> Repo.get!(id)
    |> Repo.preload(order_items: [menu_item: :category])
  end

  @doc "Creates an order (a new customer tab)."
  def create_order(attrs \\ %{}) do
    %Order{}
    |> Order.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates an order."
  def update_order(%Order{} = order, attrs) do
    order
    |> Order.changeset(attrs)
    |> Repo.update()
  end

  @doc "Closes an order by setting its status to 'closed'."
  def close_order(%Order{} = order) do
    result =
      order
      |> Order.changeset(%{status: "closed"})
      |> Repo.update()

    case result do
      {:ok, updated} ->
        broadcast({:order_updated, updated.id})
        {:ok, updated}

      error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Order Items
  # ---------------------------------------------------------------------------

  @doc "Adds an OrderItem to an order. Broadcasts if the order is already sent/ready."
  def add_item(attrs \\ %{}) do
    result =
      %OrderItem{}
      |> OrderItem.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, item} ->
        broadcast({:order_updated, item.order_id})
        {:ok, item}

      error ->
        error
    end
  end

  @doc "Updates an order item. Broadcasts so kitchen/barra refreshes."
  def update_item(%OrderItem{} = item, attrs) do
    result =
      item
      |> OrderItem.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated} ->
        broadcast({:order_updated, updated.order_id})
        {:ok, updated}

      error ->
        error
    end
  end

  @doc "Removes an OrderItem by id. Broadcasts so kitchen/barra refreshes."
  def remove_item(id) do
    case Repo.get(OrderItem, id) do
      nil ->
        {:error, :not_found}

      item ->
        case Repo.delete(item) do
          {:ok, deleted} ->
            broadcast({:order_updated, deleted.order_id})
            {:ok, deleted}

          error ->
            error
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Kitchen / Barra actions
  # ---------------------------------------------------------------------------

  @doc """
  Marks all pending items as 'sent', updates order status, deducts ingredient
  stock from inventory, and broadcasts to stations and waiter menu browsers.
  All DB writes run in a single transaction.
  """
  def send_to_kitchen(%Order{} = order) do
    # Load pending items directly from DB (safe regardless of preload state)
    pending =
      from(oi in OrderItem,
        where: oi.order_id == ^order.id and oi.status == "pending"
      )
      |> Repo.all()

    result =
      Repo.transaction(fn ->
        # 1. Mark pending items → sent
        from(oi in OrderItem,
          where: oi.order_id == ^order.id and oi.status == "pending"
        )
        |> Repo.update_all(set: [status: "sent"])

        # 2. Update order status
        updated =
          order
          |> Order.changeset(%{status: "sent"})
          |> Repo.update!()

        # 3. Deduct ingredient stock for the sent items
        deduct_ingredients_for_items(pending)

        updated
      end)

    case result do
      {:ok, updated} ->
        broadcast({:order_updated, updated.id})
        # Notify all waiter browsers to refresh menu availability
        Phoenix.PubSub.broadcast(CRC.PubSub, @stock_topic, :stock_updated)
        # Notify admin inventory view
        Phoenix.PubSub.broadcast(CRC.PubSub, "admin:products", {:product_changed, :stock})
        {:ok, updated}

      {:error, _} = error ->
        error
    end
  end

  @doc "Sets an OrderItem status to 'ready'."
  def mark_item_ready(id) do
    case Repo.get(OrderItem, id) do
      nil ->
        {:error, :not_found}

      item ->
        result =
          item
          |> OrderItem.changeset(%{status: "ready"})
          |> Repo.update()

        case result do
          {:ok, updated} ->
            broadcast({:order_updated, updated.order_id})
            {:ok, updated}

          error ->
            error
        end
    end
  end

  @doc "Sets an order status to 'ready' and broadcasts."
  def mark_order_ready(%Order{} = order) do
    result =
      order
      |> Order.changeset(%{status: "ready"})
      |> Repo.update()

    case result do
      {:ok, updated} ->
        broadcast({:order_updated, updated.id})
        {:ok, updated}

      error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(CRC.PubSub, @pubsub_topic, message)
  end

  # ---------------------------------------------------------------------------
  # Stock deduction (runs inside send_to_kitchen transaction)
  # ---------------------------------------------------------------------------

  defp deduct_ingredients_for_items([]), do: :ok

  defp deduct_ingredients_for_items(pending_items) do
    menu_item_ids =
      pending_items
      |> Enum.map(& &1.menu_item_id)
      |> Enum.uniq()

    # Load all ingredients for the relevant menu items in one query
    ingredients =
      from(mii in MenuItemIngredient, where: mii.menu_item_id in ^menu_item_ids)
      |> Repo.all()

    # Group by menu_item_id for quick lookup
    by_menu_item = Enum.group_by(ingredients, & &1.menu_item_id)

    # Accumulate total deduction per product across all pending items
    deductions =
      Enum.reduce(pending_items, %{}, fn order_item, acc ->
        item_ingredients = Map.get(by_menu_item, order_item.menu_item_id, [])

        Enum.reduce(item_ingredients, acc, fn mii, inner ->
          total = Decimal.mult(mii.quantity, Decimal.new(order_item.quantity))
          Map.update(inner, mii.product_id, total, &Decimal.add(&1, total))
        end)
      end)

    # Apply one atomic decrement per product
    Enum.each(deductions, fn {product_id, deduction} ->
      from(p in Product, where: p.id == ^product_id)
      |> Repo.update_all(inc: [stock_quantity: Decimal.negate(deduction)])
    end)
  end
end
