defmodule CRC.Orders do
  @moduledoc """
  The Orders context manages comandas: open orders per customer account,
  order items, and real-time notifications to cocina and barra via PubSub.
  """

  import Ecto.Query, warn: false
  alias CRC.Repo
  alias CRC.Orders.{Order, OrderItem, OrderItemExclusion, Table}
  alias CRC.Catalog.{MenuItemIngredient, Package}
  alias CRC.Inventory.{Product, ProductVariant}
  alias CRC.Accounts.User

  # Both cocina and barra subscribe to this topic
  @pubsub_topic "orders"
  # Waiter menu browsers subscribe to this for real-time stock availability
  @stock_topic "menu_stock"
  # Waiter floor map subscribes to this for real-time table layout updates
  @tables_topic "restaurant_tables"

  # ---------------------------------------------------------------------------
  # Orders
  # ---------------------------------------------------------------------------

  @doc "Returns all orders with status 'open', 'sent', or 'ready'. Preloads items with menu_item + category + product + exclusions, and the user who created the order."
  def list_open_orders do
    Order
    |> where([o], o.status in ["open", "sent", "ready"])
    |> order_by([o], o.inserted_at)
    |> preload([
      :user,
      order_items: [
        :product,
        :variant,
        :for_menu_item,
        exclusions: [:product],
        menu_item: :category,
        package: []
      ]
    ])
    |> Repo.all()
  end

  @doc "Returns active orders (open/sent/ready) for the waiter overview, sorted oldest first."
  def list_active_orders do
    Order
    |> where([o], o.status in ["open", "sent", "ready"])
    |> order_by([o], o.inserted_at)
    |> preload([
      :user,
      order_items: [
        :product,
        :variant,
        :for_menu_item,
        exclusions: [:product],
        menu_item: :category,
        package: []
      ]
    ])
    |> Repo.all()
  end

  @doc "Returns active group orders (is_group: true), sorted oldest first."
  def list_active_groups do
    Order
    |> where([o], o.status in ["open", "sent", "ready"] and o.is_group == true)
    |> order_by([o], o.inserted_at)
    |> preload([
      :user,
      order_items: [
        :product,
        :variant,
        :for_menu_item,
        exclusions: [:product],
        menu_item: :category,
        package: []
      ]
    ])
    |> Repo.all()
  end

  @doc "Returns active takeout orders (order_type: takeout, not a group, no table), sorted oldest first."
  def list_active_takeout do
    Order
    |> where([o],
      o.status in ["open", "sent", "ready"] and
      o.order_type == "takeout" and
      o.is_group == false and
      is_nil(o.table_id)
    )
    |> order_by([o], o.inserted_at)
    |> preload([
      :user,
      order_items: [
        :product,
        :variant,
        :for_menu_item,
        exclusions: [:product],
        menu_item: :category,
        package: []
      ]
    ])
    |> Repo.all()
  end

  @doc "Gets an order by id. Raises if not found. Preloads items with full ingredient recipe + exclusions for the modifier UI."
  def get_order!(id) do
    Order
    |> Repo.get!(id)
    |> Repo.preload([
      :user,
      order_items: [
        :product,
        :variant,
        :for_menu_item,
        :package,
        exclusions: [:product],
        menu_item: [:category, menu_item_ingredients: [product: :variants]]
      ]
    ])
  end

  @doc """
  Generates (or returns an existing) unique bill token for an order.
  The token is used to build the public /cuenta/:token URL for customers.
  """
  def generate_bill_token(%Order{bill_token: token} = order) when not is_nil(token) do
    {:ok, order}
  end

  def generate_bill_token(%Order{} = order) do
    token = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)

    order
    |> Order.changeset(%{bill_token: token})
    |> Repo.update()
  end

  @doc "Fetches an order by its public bill token. Raises Ecto.NoResultsError if not found."
  def get_order_by_token!(token) do
    Order
    |> Repo.get_by!(bill_token: token)
    |> Repo.preload([
      :user,
      :discount,
      order_items: [
        :product,
        :variant,
        :for_menu_item,
        :package,
        exclusions: [:product],
        menu_item: [:category]
      ]
    ])
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

  @doc """
  Calculates the running total for an order from its preloaded items.
  Menu item lines, variant selections with an extra_charge, and product
  extras with a sale_price (unit_price > 0) all contribute to the total.
  """
  def calculate_order_total(%Order{order_items: items}) do
    Enum.reduce(items, Decimal.new(0), fn item, acc ->
      if item.status in ["cancelled", "cancelled_waste"] do
        acc
      else
        cond do
          # Menu item (or package item with unit_price override)
          item.menu_item_id && item.menu_item ->
            price = item.unit_price || item.menu_item.price
            Decimal.add(acc, Decimal.mult(price, Decimal.new(item.quantity)))

          # Variant selection with an extra charge
          item.variant_id && item.unit_price &&
              Decimal.compare(item.unit_price, Decimal.new(0)) == :gt ->
            Decimal.add(acc, Decimal.mult(item.unit_price, Decimal.new(item.quantity)))

          # Product extra with a customer-facing sale price
          item.product_id && item.unit_price &&
              Decimal.compare(item.unit_price, Decimal.new(0)) == :gt ->
            Decimal.add(acc, Decimal.mult(item.unit_price, Decimal.new(item.quantity)))

          true ->
            acc
        end
      end
    end)
  end

  @doc """
  Closes an order, recording payment method, amount paid (cash only),
  and the total calculated at close time.

  attrs must include %{payment_method: "efectivo"|"tarjeta"|"transferencia"}
  and, when efectivo, %{amount_paid: Decimal}.
  """
  def close_order(%Order{} = order, attrs, closed_by_id \\ nil) do
    subtotal = calculate_order_total(order)
    discount_pct = Map.get(attrs, :discount_percentage, 0) || 0

    total =
      if discount_pct > 0 do
        Decimal.mult(subtotal, Decimal.new(100 - discount_pct))
        |> Decimal.div(Decimal.new(100))
      else
        subtotal
      end

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    result =
      order
      |> Order.close_changeset(
        Map.merge(attrs, %{
          status: "closed",
          total: total,
          closed_at: now,
          closed_by_id: closed_by_id
        })
      )
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
  # Manual (retroactive) orders
  # ---------------------------------------------------------------------------

  @doc """
  Creates a fully-closed order from a paper ticket or other offline source.

  The order is inserted directly in "closed" status with all items in "served"
  state. It is flagged `manual_entry: true` so it is included in financial
  totals but excluded from rendimiento/timing metrics.

  `items` is a list of maps: [%{menu_item_id: id, quantity: n}]
  `attrs` must include: customer_name, payment_method, total, closed_at.
  """
  def create_manual_order(attrs, items, closed_by_id \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      # Normalise attrs to string-keyed map before merging to avoid
      # mixed atom/string key errors in Ecto.Changeset.cast/4.
      str_attrs =
        attrs
        |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
        |> Map.merge(%{"closed_by_id" => closed_by_id, "manual_entry" => true})

      order =
        %Order{}
        |> Order.manual_changeset(str_attrs)
        |> Repo.insert!()

      Enum.each(items, fn %{menu_item_id: menu_item_id, quantity: qty} ->
        %OrderItem{}
        |> OrderItem.changeset(%{
          order_id: order.id,
          menu_item_id: menu_item_id,
          quantity: qty,
          status: "served",
          served_at: now
        })
        |> Repo.insert!()
      end)

      broadcast({:order_updated, order.id})
      order
    end)
  end

  # ---------------------------------------------------------------------------
  # Sales reporting
  # ---------------------------------------------------------------------------

  @doc """
  Returns all closed orders for the given period, newest first.
  period: :today | :week | :month | :all
  """
  def list_closed_orders(period \\ :all) do
    Order
    |> where([o], o.status == "closed")
    |> filter_by_period(period)
    |> order_by([o], desc: o.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns closed orders for the history view, with user and item preloads.
  Options:
    - user_id: only return orders created by this user (nil = all)
  """
  def list_orders_history(period \\ :all, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)

    Order
    |> where([o], o.status == "closed")
    |> filter_by_period(period)
    |> maybe_filter_user(user_id)
    |> order_by([o], desc: o.closed_at)
    |> preload([
      :user,
      :closed_by,
      order_items: [
        :product,
        :for_menu_item,
        exclusions: [:product],
        menu_item: :category,
        package: []
      ]
    ])
    |> Repo.all()
  end

  @doc "Returns all users who have created at least one closed order, for admin filter dropdown."
  def list_waiters_with_history do
    User
    |> join(:inner, [u], o in Order, on: o.user_id == u.id and o.status == "closed")
    |> distinct([u], u.id)
    |> order_by([u], u.name)
    |> Repo.all()
  end

  defp maybe_filter_user(query, nil), do: query
  defp maybe_filter_user(query, user_id), do: where(query, [o], o.user_id == ^user_id)

  @doc """
  Returns a summary map for the given period:
    %{total_revenue, order_count, avg_ticket, by_method}
  where by_method is %{"efectivo" => Decimal, ...}
  """
  def sales_summary(period \\ :all) do
    orders = list_closed_orders(period)

    total_revenue =
      Enum.reduce(orders, Decimal.new(0), fn o, acc ->
        Decimal.add(acc, o.total || Decimal.new(0))
      end)

    order_count = length(orders)

    avg_ticket =
      if order_count > 0 do
        total_revenue |> Decimal.div(Decimal.new(order_count)) |> Decimal.round(2)
      else
        Decimal.new(0)
      end

    by_method =
      orders
      |> Enum.group_by(& &1.payment_method)
      |> Map.new(fn {method, group} ->
        sum =
          Enum.reduce(group, Decimal.new(0), fn o, acc ->
            Decimal.add(acc, o.total || Decimal.new(0))
          end)

        {method || "desconocido", sum}
      end)

    %{
      total_revenue: total_revenue,
      order_count: order_count,
      avg_ticket: avg_ticket,
      by_method: by_method
    }
  end

  @doc """
  Returns a financial summary for the given period:
    %{revenue, cogs, gross_profit, margin_pct, waste_cost, net_profit}

  - revenue:       total from closed orders
  - cogs:          ingredient cost (net_cost × qty) for all sold menu items
  - gross_profit:  revenue - cogs
  - margin_pct:    gross_profit / revenue × 100  (0 if no revenue)
  - waste_cost:    ingredient cost for cancelled_waste items in period
  - net_profit:    gross_profit - waste_cost

  Note: items without a recipe (no menu_item_ingredients rows) are not counted
  in cogs — their cost is treated as 0.
  """
  def financial_summary(period \\ :all) do
    # Revenue from closed orders in period
    revenue =
      Order
      |> where([o], o.status == "closed")
      |> filter_by_period(period)
      |> select([o], sum(o.total))
      |> Repo.one()
      |> decimal_or_zero()

    # IDs of closed orders in period (for COGS join)
    closed_ids_query =
      Order
      |> where([o], o.status == "closed")
      |> filter_by_period(period)
      |> select([o], o.id)

    # COGS: quantity_ordered × ingredient_quantity_per_unit × ingredient_net_cost
    # Left-join exclusions and exclude rows where the ingredient was removed by the customer
    # (excluded ingredients were never deducted from stock, so they are not a real cost).
    cogs =
      from(oi in OrderItem,
        join: mii in MenuItemIngredient,
        on: mii.menu_item_id == oi.menu_item_id,
        join: p in Product,
        on: p.id == mii.product_id,
        left_join: excl in OrderItemExclusion,
        on: excl.order_item_id == oi.id and excl.product_id == mii.product_id,
        where: oi.order_id in subquery(closed_ids_query),
        where: oi.status not in ["cancelled", "cancelled_waste"],
        where: not is_nil(oi.menu_item_id),
        where: is_nil(excl.id),
        select: sum(fragment("?::numeric * ? * ?", oi.quantity, mii.quantity, p.net_cost))
      )
      |> Repo.one()
      |> decimal_or_zero()

    # Waste cost: ingredient cost of cancelled_waste items in any order in the period
    all_order_ids_in_period =
      Order
      |> filter_by_period(period)
      |> select([o], o.id)

    waste_cost =
      from(oi in OrderItem,
        join: mii in MenuItemIngredient,
        on: mii.menu_item_id == oi.menu_item_id,
        join: p in Product,
        on: p.id == mii.product_id,
        left_join: excl in OrderItemExclusion,
        on: excl.order_item_id == oi.id and excl.product_id == mii.product_id,
        where: oi.order_id in subquery(all_order_ids_in_period),
        where: oi.status == "cancelled_waste",
        where: not is_nil(oi.menu_item_id),
        where: is_nil(excl.id),
        select: sum(fragment("?::numeric * ? * ?", oi.quantity, mii.quantity, p.net_cost))
      )
      |> Repo.one()
      |> decimal_or_zero()

    gross_profit = Decimal.sub(revenue, cogs)

    margin_pct =
      if Decimal.compare(revenue, Decimal.new(0)) == :gt do
        Decimal.div(gross_profit, revenue)
        |> Decimal.mult(Decimal.new(100))
        |> Decimal.round(1)
      else
        Decimal.new(0)
      end

    %{
      revenue: revenue,
      cogs: cogs,
      gross_profit: gross_profit,
      margin_pct: margin_pct,
      waste_cost: waste_cost,
      net_profit: Decimal.sub(gross_profit, waste_cost)
    }
  end

  @doc """
  Returns the top N most wasted menu items for the period (cancelled_waste),
  with their total quantity wasted and total ingredient cost.
  Returns a list of maps: %{name: str, qty: int, cost: Decimal}
  """
  def top_wasted_items(period \\ :all, limit \\ 10) do
    all_order_ids_in_period =
      Order
      |> filter_by_period(period)
      |> select([o], o.id)

    from(oi in OrderItem,
      join: mi in assoc(oi, :menu_item),
      join: mii in MenuItemIngredient,
      on: mii.menu_item_id == oi.menu_item_id,
      join: p in Product,
      on: p.id == mii.product_id,
      where: oi.order_id in subquery(all_order_ids_in_period),
      where: oi.status == "cancelled_waste",
      where: not is_nil(oi.menu_item_id),
      group_by: [mi.id, mi.name],
      select: %{
        name: mi.name,
        qty: sum(oi.quantity),
        cost: sum(fragment("?::numeric * ? * ?", oi.quantity, mii.quantity, p.net_cost))
      },
      order_by: [desc: sum(oi.quantity)],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp decimal_or_zero(nil), do: Decimal.new(0)
  defp decimal_or_zero(%Decimal{} = d), do: d
  defp decimal_or_zero(v), do: Decimal.new("#{v}")

  @doc """
  Returns the top N menu items by total quantity sold in closed orders.
  Returns [{name, total_qty}] sorted descending.
  """
  def top_selling_items(period \\ :all, limit \\ 10) do
    closed_ids =
      Order
      |> where([o], o.status == "closed")
      |> filter_by_period(period)
      |> select([o], o.id)

    from(oi in OrderItem,
      join: mi in assoc(oi, :menu_item),
      where: oi.order_id in subquery(closed_ids) and not is_nil(oi.menu_item_id),
      group_by: [oi.menu_item_id, mi.name],
      order_by: [desc: sum(oi.quantity)],
      limit: ^limit,
      select: {mi.name, sum(oi.quantity)}
    )
    |> Repo.all()
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

  @doc """
  Adds all items from a package to an order.

  Creates one OrderItem per package_item, distributing the package price
  proportionally across items (based on individual menu_item prices).
  All items are tagged with the package_id for display purposes.

  Returns {:ok, [order_items]} or {:error, reason}.
  """
  def add_package(%{order_id: order_id} = attrs) do
    package_id = attrs[:package_id] || attrs["package_id"]

    with %Package{} = package <-
           CRC.Repo.get(Package, package_id) |> CRC.Repo.preload(package_items: :menu_item),
         true <- package.active,
         false <- Enum.empty?(package.package_items) do
      # Calculate proportional unit prices
      items_with_price =
        Enum.map(package.package_items, fn pi ->
          {pi, pi.menu_item.price}
        end)

      total_individual =
        Enum.reduce(items_with_price, Decimal.new(0), fn {_pi, p}, acc ->
          Decimal.add(acc, Decimal.mult(p, Decimal.new(1)))
        end)

      result =
        CRC.Repo.transaction(fn ->
          items_with_price
          |> Enum.map(fn {pi, item_price} ->
            unit_price =
              if Decimal.compare(total_individual, Decimal.new(0)) == :gt do
                package.price
                |> Decimal.mult(item_price)
                |> Decimal.div(total_individual)
                |> Decimal.round(2)
              else
                Decimal.div(package.price, length(items_with_price))
                |> Decimal.round(2)
              end

            %OrderItem{}
            |> OrderItem.changeset(%{
              order_id: order_id,
              menu_item_id: pi.menu_item_id,
              package_id: package.id,
              unit_price: unit_price,
              quantity: pi.quantity,
              status: "pending"
            })
            |> CRC.Repo.insert!()
          end)
        end)

      case result do
        {:ok, items} ->
          broadcast({:order_updated, order_id})
          {:ok, items}

        {:error, reason} ->
          {:error, reason}
      end
    else
      nil -> {:error, :package_not_found}
      false -> {:error, :package_inactive}
      true -> {:error, :package_empty}
    end
  end

  @doc """
  Toggles an ingredient exclusion on a pending order item.

  If the product is not yet excluded → inserts the exclusion record.
  If it is already excluded → removes it (customer changed their mind).

  Only meaningful for pending items (before send_to_kitchen). Calling it on
  a sent item is harmless but has no effect on inventory since deduction
  already happened.

  Returns `{:ok, :added}` | `{:ok, :removed}` | `{:error, changeset}`.
  """
  def toggle_exclusion(order_item_id, product_id) do
    case Repo.get_by(OrderItemExclusion,
           order_item_id: order_item_id,
           product_id: product_id
         ) do
      nil ->
        result =
          %OrderItemExclusion{}
          |> OrderItemExclusion.changeset(%{
            order_item_id: order_item_id,
            product_id: product_id
          })
          |> Repo.insert()

        case result do
          {:ok, _} -> {:ok, :added}
          error -> error
        end

      existing ->
        Repo.delete(existing)
        {:ok, :removed}
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

  @doc "Sets the notes text on a pending order item. Broadcasts so kitchen/barra refreshes."
  def set_item_notes(order_item_id, notes) do
    case Repo.get(OrderItem, order_item_id) do
      nil ->
        {:error, :not_found}

      item ->
        update_item(item, %{notes: notes})
    end
  end

  @doc "Sets the for_person identifier on a pending order item (e.g. 'gorra roja')."
  def set_item_for_person(order_item_id, for_person) do
    case Repo.get(OrderItem, order_item_id) do
      nil ->
        {:error, :not_found}

      item ->
        update_item(item, %{for_person: for_person})
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

  @doc """
  Cancels a sent/ready order item.

  - `:not_prepared` — the kitchen did not make it; restores ingredient stock
    and marks status as "cancelled". Broadcasts stock_updated so waiter menus refresh.
  - `:waste` — the item was already prepared but not served; does NOT restore
    stock and marks status as "cancelled_waste".
  """
  def cancel_item(%OrderItem{} = item, :not_prepared) do
    result =
      Repo.transaction(fn ->
        restore_stock_for_item(item)
        item |> OrderItem.changeset(%{status: "cancelled"}) |> Repo.update!()
      end)

    case result do
      {:ok, updated} ->
        broadcast({:order_updated, item.order_id})
        Phoenix.PubSub.broadcast(CRC.PubSub, @stock_topic, :stock_updated)
        Phoenix.PubSub.broadcast(CRC.PubSub, "admin:products", {:product_changed, :stock})
        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def cancel_item(%OrderItem{} = item, :waste) do
    result = item |> OrderItem.changeset(%{status: "cancelled_waste"}) |> Repo.update()

    case result do
      {:ok, updated} ->
        broadcast({:order_updated, item.order_id})
        {:ok, updated}

      error ->
        error
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
        # 1. Mark pending items → sent (record timestamp)
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        from(oi in OrderItem,
          where: oi.order_id == ^order.id and oi.status == "pending"
        )
        |> Repo.update_all(set: [status: "sent", sent_at: now])

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

      {:error, {:insufficient_stock, name}} ->
        {:error, {:insufficient_stock, name}}

      {:error, _} = error ->
        error
    end
  end

  @doc "Sets an OrderItem status to 'ready', optionally recording who marked it."
  def mark_item_ready(id, marked_by_id \\ nil) do
    case Repo.get(OrderItem, id) do
      nil ->
        {:error, :not_found}

      item ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        result =
          item
          |> OrderItem.changeset(%{
            status: "ready",
            ready_at: now,
            marked_ready_by_id: marked_by_id
          })
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

  @doc "Sets an OrderItem status to 'served', recording who delivered it and when."
  def mark_item_served(id, served_by_id \\ nil) do
    case Repo.get(OrderItem, id) do
      nil ->
        {:error, :not_found}

      item ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        result =
          item
          |> OrderItem.changeset(%{status: "served", served_at: now, served_by_id: served_by_id})
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

  defp broadcast_tables_changed do
    Phoenix.PubSub.broadcast(CRC.PubSub, @tables_topic, :tables_changed)
  end

  # Reverses the stock deduction for a single order item.
  # Called inside a transaction from cancel_item/2 when :not_prepared.
  # Excluded ingredients were never deducted, so they are NOT restored.
  defp restore_stock_for_item(%OrderItem{menu_item_id: menu_item_id, quantity: qty} = item)
       when not is_nil(menu_item_id) do
    # Load exclusions so we only restore what was actually deducted
    excluded_product_ids =
      from(e in OrderItemExclusion,
        where: e.order_item_id == ^item.id,
        select: e.product_id
      )
      |> Repo.all()
      |> MapSet.new()

    ingredients =
      from(mii in MenuItemIngredient, where: mii.menu_item_id == ^menu_item_id)
      |> Repo.all()

    Enum.each(ingredients, fn mii ->
      unless MapSet.member?(excluded_product_ids, mii.product_id) do
        restore = Decimal.mult(mii.quantity, Decimal.new(qty))

        from(p in Product, where: p.id == ^mii.product_id)
        |> Repo.update_all(inc: [stock_quantity: restore])
      end
    end)
  end

  defp restore_stock_for_item(%OrderItem{
         product_id: product_id,
         quantity: qty,
         portion_quantity: portion
       })
       when not is_nil(product_id) do
    restore = Decimal.mult(portion || Decimal.new(1), Decimal.new(qty))

    from(p in Product, where: p.id == ^product_id)
    |> Repo.update_all(inc: [stock_quantity: restore])
  end

  # Variant selection item: restore from product_variants.stock_quantity using recipe quantity.
  defp restore_stock_for_item(%OrderItem{
         variant_id: variant_id,
         for_menu_item_id: for_menu_item_id,
         quantity: qty
       })
       when not is_nil(variant_id) and not is_nil(for_menu_item_id) do
    variant = Repo.get!(ProductVariant, variant_id)

    qty_per_unit =
      from(mii in MenuItemIngredient,
        where: mii.menu_item_id == ^for_menu_item_id and mii.product_id == ^variant.product_id,
        select: mii.quantity
      )
      |> Repo.one()

    if qty_per_unit do
      restore = Decimal.mult(qty_per_unit, Decimal.new(qty))

      from(v in ProductVariant, where: v.id == ^variant_id)
      |> Repo.update_all(inc: [stock_quantity: restore])
    end
  end

  defp restore_stock_for_item(_), do: :ok

  defp filter_by_period(query, :all), do: query

  defp filter_by_period(query, :today) do
    # Compute the café's local date from UTC using the configured offset.
    # NaiveDateTime.local_now() is unreliable when the server OS is set to UTC
    # (e.g. Mac with UTC timezone), so we use an explicit offset from config.
    offset_hours = Application.get_env(:crc, :utc_offset_hours, -6)
    offset_secs = offset_hours * 3_600

    # Shift UTC now into local time to get today's local date
    local_date =
      DateTime.utc_now()
      |> DateTime.add(offset_secs, :second)
      |> DateTime.to_date()

    # Convert local midnight back to UTC for the DB query
    start =
      DateTime.new!(local_date, ~T[00:00:00], "Etc/UTC")
      |> DateTime.add(-offset_secs, :second)

    where(query, [o], o.inserted_at >= ^start)
  end

  defp filter_by_period(query, :week) do
    offset_hours = Application.get_env(:crc, :utc_offset_hours, -6)
    offset_secs = offset_hours * 3_600

    local_date =
      DateTime.utc_now()
      |> DateTime.add(offset_secs, :second)
      |> DateTime.to_date()

    # Day of week: Monday = 1 … Sunday = 7
    days_since_monday = Date.day_of_week(local_date) - 1
    monday = Date.add(local_date, -days_since_monday)

    start =
      DateTime.new!(monday, ~T[00:00:00], "Etc/UTC")
      |> DateTime.add(-offset_secs, :second)

    where(query, [o], o.inserted_at >= ^start)
  end

  defp filter_by_period(query, :month) do
    offset_hours = Application.get_env(:crc, :utc_offset_hours, -6)
    offset_secs = offset_hours * 3_600

    local_date =
      DateTime.utc_now()
      |> DateTime.add(offset_secs, :second)
      |> DateTime.to_date()

    first_of_month = Date.beginning_of_month(local_date)

    start =
      DateTime.new!(first_of_month, ~T[00:00:00], "Etc/UTC")
      |> DateTime.add(-offset_secs, :second)

    where(query, [o], o.inserted_at >= ^start)
  end

  defp filter_by_period(query, {:range, date_from, date_to}) do
    start_dt = DateTime.new!(date_from, ~T[00:00:00])
    end_dt = DateTime.new!(date_to, ~T[23:59:59])
    where(query, [o], o.inserted_at >= ^start_dt and o.inserted_at <= ^end_dt)
  end

  # ---------------------------------------------------------------------------
  # Timing statistics
  # ---------------------------------------------------------------------------

  @doc """
  Returns average/min/max preparation times (in seconds) for closed orders
  in the given period, grouped by station kind ("food" / "drink").

  Each key maps to %{wait: stat, prep: stat, service: stat} where
  stat is %{avg: integer, min: integer, max: integer} or nil if no data.

  - wait    = sent_at − inserted_at  (time from adding to sending to station)
  - prep    = ready_at − sent_at     (time station took to prepare)
  - service = closed_at − ready_at   (time item sat ready before order closed)
  """
  def timing_stats(period \\ :all) do
    closed_orders =
      Order
      |> where([o], o.status == "closed" and not is_nil(o.closed_at) and o.manual_entry == false)
      |> filter_by_period(period)
      |> select([o], %{id: o.id, closed_at: o.closed_at})
      |> Repo.all()

    if closed_orders == [] do
      %{}
    else
      order_map = Map.new(closed_orders, &{&1.id, &1.closed_at})
      order_ids = Map.keys(order_map)

      items =
        from(oi in OrderItem,
          join: mi in assoc(oi, :menu_item),
          where:
            oi.order_id in ^order_ids and
              not is_nil(oi.sent_at) and
              not is_nil(oi.ready_at) and
              not is_nil(oi.menu_item_id),
          select: %{
            order_id: oi.order_id,
            kind: mi.destination,
            inserted_at: oi.inserted_at,
            sent_at: oi.sent_at,
            ready_at: oi.ready_at
          }
        )
        |> Repo.all()

      items
      |> Enum.map(fn item ->
        closed_at = Map.get(order_map, item.order_id)
        wait = DateTime.diff(item.sent_at, item.inserted_at, :second)
        prep = DateTime.diff(item.ready_at, item.sent_at, :second)
        service = if closed_at, do: DateTime.diff(closed_at, item.ready_at, :second)
        Map.merge(item, %{wait: wait, prep: prep, service: service})
      end)
      |> Enum.group_by(& &1.kind)
      |> Map.new(fn {kind, group} ->
        {kind,
         %{
           wait: time_stat(group, :wait),
           prep: time_stat(group, :prep),
           service: time_stat(Enum.filter(group, &(&1.service != nil)), :service)
         }}
      end)
    end
  end

  defp time_stat([], _field), do: nil

  defp time_stat(items, field) do
    vals = items |> Enum.map(&Map.get(&1, field)) |> Enum.filter(&(&1 != nil and &1 >= 0))

    case vals do
      [] ->
        nil

      _ ->
        avg = round(Enum.sum(vals) / length(vals))
        %{avg: avg, min: Enum.min(vals), max: Enum.max(vals)}
    end
  end

  # ---------------------------------------------------------------------------
  # Employee performance statistics
  # ---------------------------------------------------------------------------

  @doc """
  Returns per-employee timing statistics for the given period.

  Returns:
    %{
      station_stats: [%{user_id, name, station, count, avg, min, max}],
      waiter_stats:  [%{user_id, name, station, count, avg, min, max}]
    }

  station_stats: kitchen/barra staff — avg seconds from sent_at to ready_at per item.
  waiter_stats:  waiters — avg seconds from order inserted_at to closed_at per order.
  Both lists are sorted by avg descending (slowest first).
  """
  def employee_stats(period \\ :all) do
    closed_order_ids =
      Order
      |> where([o], o.status == "closed" and o.manual_entry == false)
      |> filter_by_period(period)
      |> select([o], o.id)
      |> Repo.all()

    if closed_order_ids == [] do
      %{station_stats: [], waiter_stats: []}
    else
      station_stats = build_station_stats(closed_order_ids)
      waiter_stats = build_waiter_stats(closed_order_ids)
      %{station_stats: station_stats, waiter_stats: waiter_stats}
    end
  end

  @doc """
  Returns revenue and speed rankings for the given period.

  Returns a map with two keys:
  - `:revenue_ranking` — waiters sorted by descending total revenue (closed orders).
    Each entry: `%{user_id, name, revenue, order_count, rank}`.
  - `:speed_ranking` — station/waiter staff sorted by ascending avg prep/service time.
    Each entry: `%{user_id, name, station, avg_secs, count, rank}`.

  Only employees with at least 1 data point in the period are included.
  """
  def employee_rankings(period \\ :all) do
    closed_order_ids =
      Order
      |> where([o], o.status == "closed" and o.manual_entry == false)
      |> filter_by_period(period)
      |> select([o], o.id)
      |> Repo.all()

    if closed_order_ids == [] do
      %{revenue_ranking: [], speed_ranking: []}
    else
      revenue_ranking = build_revenue_ranking(closed_order_ids)
      speed_ranking = build_speed_ranking(closed_order_ids)
      %{revenue_ranking: revenue_ranking, speed_ranking: speed_ranking}
    end
  end

  defp build_revenue_ranking(closed_order_ids) do
    from(o in Order,
      join: u in User,
      on: o.user_id == u.id,
      where: o.id in ^closed_order_ids and not is_nil(o.user_id),
      group_by: [u.id, u.name],
      select: %{
        user_id: u.id,
        name: u.name,
        revenue: sum(o.total),
        order_count: count(o.id)
      },
      order_by: [desc: sum(o.total)]
    )
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, rank} -> Map.put(entry, :rank, rank) end)
  end

  defp build_speed_ranking(closed_order_ids) do
    # Station staff (cocina/barra): lower prep time = better
    station_rows =
      from(oi in OrderItem,
        join: u in User,
        on: oi.marked_ready_by_id == u.id,
        where:
          oi.order_id in ^closed_order_ids and
            not is_nil(oi.sent_at) and
            not is_nil(oi.ready_at),
        select: %{
          user_id: u.id,
          name: u.name,
          stations: u.stations,
          sent_at: oi.sent_at,
          ready_at: oi.ready_at
        }
      )
      |> Repo.all()

    station_entries =
      station_rows
      |> Enum.group_by(fn r -> {r.user_id, r.name, r.stations} end)
      |> Enum.map(fn {{uid, name, stations}, rows} ->
        times = Enum.map(rows, fn r -> DateTime.diff(r.ready_at, r.sent_at, :second) end)
        avg = round(Enum.sum(times) / length(times))

        %{
          user_id: uid,
          name: name,
          station: stations_label(stations),
          avg_secs: avg,
          count: length(times)
        }
      end)

    # Waiters pickup time: lower = better
    pickup_rows =
      from(oi in OrderItem,
        join: u in User,
        on: oi.served_by_id == u.id,
        where:
          oi.order_id in ^closed_order_ids and
            not is_nil(oi.ready_at) and
            not is_nil(oi.served_at),
        select: %{
          user_id: u.id,
          name: u.name,
          stations: u.stations,
          ready_at: oi.ready_at,
          served_at: oi.served_at
        }
      )
      |> Repo.all()

    pickup_entries =
      pickup_rows
      |> Enum.group_by(fn r -> {r.user_id, r.name, r.stations} end)
      |> Enum.map(fn {{uid, name, stations}, rows} ->
        times =
          rows
          |> Enum.map(fn r -> DateTime.diff(r.served_at, r.ready_at, :second) end)
          |> Enum.filter(&(&1 >= 0))

        if times == [] do
          nil
        else
          avg = round(Enum.sum(times) / length(times))

          %{
            user_id: uid,
            name: name,
            station: stations_label(stations),
            avg_secs: avg,
            count: length(times)
          }
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Merge both, deduplicate by user_id keeping lowest avg if same user appears twice
    (station_entries ++ pickup_entries)
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {_uid, entries} -> Enum.min_by(entries, & &1.avg_secs) end)
    |> Enum.sort_by(& &1.avg_secs, :asc)
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, rank} -> Map.put(entry, :rank, rank) end)
  end

  defp build_station_stats(closed_order_ids) do
    from(oi in OrderItem,
      join: u in User,
      on: oi.marked_ready_by_id == u.id,
      join: mi in assoc(oi, :menu_item),
      join: cat in assoc(mi, :category),
      where:
        oi.order_id in ^closed_order_ids and
          not is_nil(oi.sent_at) and
          not is_nil(oi.ready_at) and
          not is_nil(oi.marked_ready_by_id),
      select: %{
        user_id: u.id,
        name: u.name,
        stations: u.stations,
        sent_at: oi.sent_at,
        ready_at: oi.ready_at
      }
    )
    |> Repo.all()
    |> Enum.group_by(fn r -> {r.user_id, r.name, r.stations} end)
    |> Enum.map(fn {{uid, name, stations}, rows} ->
      times = Enum.map(rows, fn r -> DateTime.diff(r.ready_at, r.sent_at, :second) end)
      build_stat_entry(uid, name, stations_label(stations), length(times), times)
    end)
    |> Enum.sort_by(& &1.avg, :desc)
  end

  defp build_waiter_stats(closed_order_ids) do
    service_rows =
      from(o in Order,
        join: u in User,
        on: o.user_id == u.id,
        where: o.id in ^closed_order_ids and not is_nil(o.closed_at),
        select: %{
          user_id: u.id,
          name: u.name,
          stations: u.stations,
          inserted_at: o.inserted_at,
          closed_at: o.closed_at
        }
      )
      |> Repo.all()

    # Pickup time: seconds from item ready_at to waiter's served_at
    pickup_by_user =
      from(oi in OrderItem,
        join: u in User,
        on: oi.served_by_id == u.id,
        where:
          oi.order_id in ^closed_order_ids and
            not is_nil(oi.ready_at) and
            not is_nil(oi.served_at),
        select: %{user_id: u.id, ready_at: oi.ready_at, served_at: oi.served_at}
      )
      |> Repo.all()
      |> Enum.group_by(& &1.user_id)
      |> Enum.into(%{}, fn {uid, rows} ->
        times =
          rows
          |> Enum.map(fn r -> DateTime.diff(r.served_at, r.ready_at, :second) end)
          |> Enum.filter(&(&1 >= 0))

        {uid,
         %{
           count: length(times),
           avg: if(times == [], do: 0, else: round(Enum.sum(times) / length(times))),
           min: Enum.min(times, fn -> 0 end),
           max: Enum.max(times, fn -> 0 end)
         }}
      end)

    service_rows
    |> Enum.group_by(fn r -> {r.user_id, r.name, r.stations} end)
    |> Enum.map(fn {{uid, name, stations}, rows} ->
      times =
        rows
        |> Enum.map(fn r -> DateTime.diff(r.closed_at, r.inserted_at, :second) end)
        |> Enum.filter(&(&1 >= 0))

      pickup = Map.get(pickup_by_user, uid, %{count: 0, avg: 0, min: 0, max: 0})

      base = build_stat_entry(uid, name, stations_label(stations), length(rows), times)

      Map.merge(base, %{
        pickup_count: pickup.count,
        pickup_avg: pickup.avg,
        pickup_min: pickup.min,
        pickup_max: pickup.max
      })
    end)
    |> Enum.sort_by(& &1.avg, :desc)
  end

  defp build_stat_entry(user_id, name, station, count, times) when times == [] do
    %{user_id: user_id, name: name, station: station || "—", count: count, avg: 0, min: 0, max: 0}
  end

  defp build_stat_entry(user_id, name, station, count, times) do
    %{
      user_id: user_id,
      name: name,
      station: station || "—",
      count: count,
      avg: round(Enum.sum(times) / length(times)),
      min: Enum.min(times),
      max: Enum.max(times)
    }
  end

  # Converts a stations list (e.g. ["barra", "sala"]) to a display string ("barra · sala").
  defp stations_label([]), do: "—"
  defp stations_label(nil), do: "—"
  defp stations_label(list), do: Enum.join(list, " · ")

  # ---------------------------------------------------------------------------
  # Stock deduction (runs inside send_to_kitchen transaction)
  # ---------------------------------------------------------------------------

  defp deduct_ingredients_for_items([]), do: :ok

  defp deduct_ingredients_for_items(pending_items) do
    # Split by type: variant selections vs everything else
    {variant_items, rest} = Enum.split_with(pending_items, fn oi -> not is_nil(oi.variant_id) end)

    # Variant items → deduct from product_variants.stock_quantity using the
    # quantity defined in the parent menu item's recipe.
    deduct_variant_stock(variant_items)

    # Split the rest: regular menu items (deduct via recipe) vs direct product extras
    {menu_items, extras} = Enum.split_with(rest, &(&1.menu_item_id != nil))

    # Build deduction map from menu item recipes
    deductions = build_recipe_deductions(menu_items)

    # Merge in extra deductions: portion_quantity × order quantity
    # portion_quantity stores the recipe-based serving size (e.g. 120g arrachera)
    all_deductions =
      Enum.reduce(extras, deductions, fn oi, acc ->
        portion = oi.portion_quantity || Decimal.new(1)
        total = Decimal.mult(portion, Decimal.new(oi.quantity))
        Map.update(acc, oi.product_id, total, &Decimal.add(&1, total))
      end)

    # Lock all affected products and verify stock BEFORE decrementing.
    # Runs inside the send_to_kitchen transaction so the lock is held until commit.
    lock_and_check_products!(all_deductions)

    # Apply one atomic decrement per product
    Enum.each(all_deductions, fn {product_id, deduction} ->
      from(p in Product, where: p.id == ^product_id)
      |> Repo.update_all(inc: [stock_quantity: Decimal.negate(deduction)])
    end)
  end

  # Deducts from product_variants.stock_quantity for variant-selection order items.
  # Each variant item knows:
  #   - variant_id        → which specific type (e.g. "Leche de Avena", id=5, product_id=3)
  #   - for_menu_item_id  → which dish recipe to look up (e.g. "Matcha Latte")
  #   - quantity          → how many units ordered (e.g. 2)
  #
  # The per-unit deduction amount comes from menu_item_ingredients.quantity for
  # (for_menu_item_id, variant.product_id).  If the parent product is not in the
  # recipe we skip — it means stock tracking wasn't set up for that ingredient.
  defp deduct_variant_stock([]), do: :ok

  defp deduct_variant_stock(variant_items) do
    variant_ids = variant_items |> Enum.map(& &1.variant_id) |> Enum.uniq()

    # Load variants to get parent product_id
    variants =
      from(v in ProductVariant, where: v.id in ^variant_ids)
      |> Repo.all()
      |> Map.new(fn v -> {v.id, v} end)

    # Load relevant recipe rows: (menu_item_id, product_id) → quantity
    for_menu_item_ids =
      variant_items
      |> Enum.map(& &1.for_menu_item_id)
      |> Enum.uniq()
      |> Enum.reject(&is_nil/1)

    recipe_quantities =
      from(mii in MenuItemIngredient,
        where: mii.menu_item_id in ^for_menu_item_ids
      )
      |> Repo.all()
      |> Map.new(fn mii -> {{mii.menu_item_id, mii.product_id}, mii.quantity} end)

    # Accumulate deduction per variant_id
    deductions =
      Enum.reduce(variant_items, %{}, fn oi, acc ->
        with %ProductVariant{} = variant <- Map.get(variants, oi.variant_id),
             false <- is_nil(oi.for_menu_item_id),
             qty_per_unit when not is_nil(qty_per_unit) <-
               Map.get(recipe_quantities, {oi.for_menu_item_id, variant.product_id}) do
          total = Decimal.mult(qty_per_unit, Decimal.new(oi.quantity))
          Map.update(acc, oi.variant_id, total, &Decimal.add(&1, total))
        else
          _ -> acc
        end
      end)

    # Lock all affected variants and verify stock BEFORE decrementing.
    lock_and_check_variants!(deductions)

    # One atomic decrement per variant
    Enum.each(deductions, fn {variant_id, deduction} ->
      from(v in ProductVariant, where: v.id == ^variant_id)
      |> Repo.update_all(inc: [stock_quantity: Decimal.negate(deduction)])
    end)
  end

  # ---------------------------------------------------------------------------
  # Stock locking helpers (run inside send_to_kitchen transaction)
  # ---------------------------------------------------------------------------

  # Locks product rows with SELECT FOR UPDATE and rolls back the transaction
  # if any product lacks sufficient stock for the planned deduction.
  # This prevents concurrent sends from driving stock negative.
  defp lock_and_check_products!(deductions) when map_size(deductions) == 0, do: :ok

  defp lock_and_check_products!(deductions) do
    product_ids = Map.keys(deductions)

    locked =
      from(p in Product, where: p.id in ^product_ids, lock: "FOR UPDATE")
      |> Repo.all()
      |> Map.new(fn p -> {p.id, p} end)

    Enum.each(deductions, fn {product_id, needed} ->
      case Map.get(locked, product_id) do
        nil ->
          :ok

        product ->
          if Decimal.compare(product.stock_quantity, needed) == :lt do
            Repo.rollback({:insufficient_stock, product.name})
          end
      end
    end)
  end

  # Same as above but for product_variants rows.
  defp lock_and_check_variants!(deductions) when map_size(deductions) == 0, do: :ok

  defp lock_and_check_variants!(deductions) do
    variant_ids = Map.keys(deductions)

    locked =
      from(v in ProductVariant, where: v.id in ^variant_ids, lock: "FOR UPDATE")
      |> Repo.all()
      |> Map.new(fn v -> {v.id, v} end)

    Enum.each(deductions, fn {variant_id, needed} ->
      case Map.get(locked, variant_id) do
        nil ->
          :ok

        variant ->
          if Decimal.compare(variant.stock_quantity, needed) == :lt do
            Repo.rollback({:insufficient_stock, "tipo de ingrediente"})
          end
      end
    end)
  end

  defp build_recipe_deductions([]), do: %{}

  defp build_recipe_deductions(menu_items) do
    menu_item_ids =
      menu_items
      |> Enum.map(& &1.menu_item_id)
      |> Enum.uniq()

    order_item_ids = Enum.map(menu_items, & &1.id)

    # Load all ingredients for the relevant menu items in one query
    ingredients =
      from(mii in MenuItemIngredient, where: mii.menu_item_id in ^menu_item_ids)
      |> Repo.all()

    # Load exclusions for these order items: {order_item_id, product_id} pairs
    exclusions =
      from(e in OrderItemExclusion, where: e.order_item_id in ^order_item_ids)
      |> Repo.all()

    # Build a MapSet of {order_item_id, product_id} for O(1) exclusion lookups
    excluded_pairs =
      MapSet.new(exclusions, fn e -> {e.order_item_id, e.product_id} end)

    # Group by menu_item_id for quick lookup
    by_menu_item = Enum.group_by(ingredients, & &1.menu_item_id)

    # Accumulate total deduction per product, skipping excluded ingredients
    Enum.reduce(menu_items, %{}, fn order_item, acc ->
      item_ingredients = Map.get(by_menu_item, order_item.menu_item_id, [])

      Enum.reduce(item_ingredients, acc, fn mii, inner ->
        if MapSet.member?(excluded_pairs, {order_item.id, mii.product_id}) do
          # Customer requested "sin X" — do not deduct this ingredient
          inner
        else
          total = Decimal.mult(mii.quantity, Decimal.new(order_item.quantity))
          Map.update(inner, mii.product_id, total, &Decimal.add(&1, total))
        end
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Restaurant tables
  # ---------------------------------------------------------------------------

  @doc "Returns all restaurant tables sorted by number."
  def list_tables do
    Table
    |> order_by(:number)
    |> Repo.all()
  end

  @doc "Returns only active restaurant tables sorted by number."
  def list_active_tables do
    Table
    |> where(is_active: true)
    |> order_by(:number)
    |> Repo.all()
  end

  @doc "Gets a table by id. Raises if not found."
  def get_table!(id), do: Repo.get!(Table, id)

  @doc "Creates a restaurant table and broadcasts the change to all connected floor maps."
  def create_table(attrs \\ %{}) do
    result =
      %Table{}
      |> Table.changeset(attrs)
      |> Repo.insert()

    if match?({:ok, _}, result), do: broadcast_tables_changed()
    result
  end

  @doc "Updates a restaurant table and broadcasts the change to all connected floor maps."
  def update_table(%Table{} = table, attrs) do
    result =
      table
      |> Table.changeset(attrs)
      |> Repo.update()

    if match?({:ok, _}, result), do: broadcast_tables_changed()
    result
  end

  @doc "Updates only the floor-map position of a table (x_pct, y_pct) and broadcasts."
  def move_table(%Table{} = table, x_pct, y_pct) do
    result =
      table
      |> Table.position_changeset(%{x_pct: x_pct, y_pct: y_pct})
      |> Repo.update()

    if match?({:ok, _}, result), do: broadcast_tables_changed()
    result
  end

  @doc "Deletes a restaurant table and broadcasts the change to all connected floor maps."
  def delete_table(%Table{} = table) do
    result = Repo.delete(table)
    if match?({:ok, _}, result), do: broadcast_tables_changed()
    result
  end

  @doc "Returns a changeset for a table (for form building)."
  def change_table(%Table{} = table, attrs \\ %{}) do
    Table.changeset(table, attrs)
  end

  @doc """
  Returns a map of table_id => order for all currently active orders
  that are associated with a table. Tables with no active order are absent.
  """
  def active_orders_by_table do
    Order
    |> where([o], o.status in ["open", "sent", "ready"] and not is_nil(o.table_id))
    |> preload([
      :user,
      order_items: [
        :product,
        :variant,
        :for_menu_item,
        exclusions: [:product],
        menu_item: :category,
        package: []
      ]
    ])
    |> Repo.all()
    |> Map.new(fn order -> {order.table_id, order} end)
  end
end
