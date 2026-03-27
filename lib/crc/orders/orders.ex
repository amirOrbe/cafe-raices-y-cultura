defmodule CRC.Orders do
  @moduledoc """
  The Orders context manages comandas: open orders per customer account,
  order items, and real-time notifications to cocina and barra via PubSub.
  """

  import Ecto.Query, warn: false
  alias CRC.Repo
  alias CRC.Orders.{Order, OrderItem}

  # Both cocina and barra subscribe to this topic
  @pubsub_topic "orders"

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

  @doc "Marks all pending items as 'sent', sets order status to 'sent', broadcasts to stations."
  def send_to_kitchen(%Order{} = order) do
    # Transition pending items so cocina/barra can see them
    from(oi in OrderItem,
      where: oi.order_id == ^order.id and oi.status == "pending"
    )
    |> Repo.update_all(set: [status: "sent"])

    result =
      order
      |> Order.changeset(%{status: "sent"})
      |> Repo.update()

    case result do
      {:ok, updated} ->
        broadcast({:order_updated, updated.id})
        {:ok, updated}

      error ->
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
end
