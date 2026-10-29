defmodule CRCWeb.Kitchen.DisplayLive do
  @moduledoc "Kitchen (cocina) display screen. Shows sent orders filtered to food items only."

  use CRCWeb, :live_view

  import CRCWeb.Layouts, only: [flash_group: 1]

  alias CRC.Orders
  alias CRCWeb.Components.{SiteComponents, StationComponents}

  @tick_interval 60_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
      schedule_tick()
    end

    orders = Orders.list_open_orders()

    socket =
      socket
      |> assign(:page_title, "Cocina")
      |> assign(:orders, orders)
      |> assign(:nav_open, false)
      |> assign(:now, DateTime.utc_now())
      |> assign(:seen_sent_ids, sent_kitchen_ids(orders))
      |> assign(:cancel_alerts, [])
      |> assign(:view_mode, :by_order)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub + tick
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:order_updated, _order_id}, socket) do
    # Coalesce a burst of broadcasts into a single reload
    Orders.drain_order_updates()
    new_orders = Orders.list_open_orders()
    new_ids = sent_kitchen_ids(new_orders)
    disappeared_ids = MapSet.difference(socket.assigns.seen_sent_ids, new_ids)
    new_items? = not MapSet.subset?(new_ids, socket.assigns.seen_sent_ids)

    # Detect items that left "sent" due to cancellation (not just marked ready)
    new_alerts =
      if MapSet.size(disappeared_ids) > 0 do
        new_orders
        |> Enum.flat_map(& &1.order_items)
        |> Enum.filter(fn oi ->
          MapSet.member?(disappeared_ids, oi.id) and
            oi.status in ["cancelled", "cancelled_waste"]
        end)
        |> Enum.map(fn oi ->
          order = Enum.find(new_orders, &(&1.id == oi.order_id))

          %{
            id: oi.id,
            customer: order && order.customer_name,
            item_name: item_label(oi),
            quantity: oi.quantity
          }
        end)
      else
        []
      end

    socket =
      socket
      |> assign(:orders, new_orders)
      |> assign(:seen_sent_ids, new_ids)
      |> update(:cancel_alerts, &(new_alerts ++ &1))

    socket =
      if new_items?, do: push_event(socket, "play_sound", %{type: "new_order"}), else: socket

    {:noreply, socket}
  end

  def handle_info(:tick, socket) do
    schedule_tick()
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, !socket.assigns.nav_open)}
  end

  def handle_event("close_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, false)}
  end

  def handle_event("dismiss_cancel_alert", %{"id" => id}, socket) do
    id = String.to_integer(id)
    {:noreply, update(socket, :cancel_alerts, &Enum.reject(&1, fn a -> a.id == id end))}
  end

  def handle_event("mark_item_ready", %{"id" => id}, socket) do
    case Orders.mark_item_ready(String.to_integer(id), socket.assigns.current_user.id) do
      {:ok, _} ->
        {:noreply, assign(socket, :orders, Orders.list_open_orders())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo marcar el artículo como listo.")}
    end
  end

  def handle_event("mark_order_ready", %{"id" => id}, socket) do
    order = Enum.find(socket.assigns.orders, &(to_string(&1.id) == id))

    if order do
      # Mark all pending kitchen items as ready first, then mark the order itself.
      order.order_items
      |> Enum.filter(fn oi -> oi.status == "sent" and kitchen_item?(oi) end)
      |> Enum.each(fn oi -> Orders.mark_item_ready(oi.id, socket.assigns.current_user.id) end)

      case Orders.mark_order_ready(order) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "#{order.customer_name} marcada como lista.")
           |> assign(:orders, Orders.list_open_orders())}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "No se pudo marcar el pedido como listo.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :view_mode, String.to_existing_atom(mode))}
  end

  def handle_event("mark_group_ready", %{"ids" => ids_str}, socket) do
    ids = ids_str |> String.split(",") |> Enum.map(&String.to_integer/1)
    Enum.each(ids, fn id -> Orders.mark_item_ready(id, socket.assigns.current_user.id) end)
    {:noreply, assign(socket, :orders, Orders.list_open_orders())}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <SiteComponents.site_navbar
      nav_open={@nav_open}
      current_page={:cocina}
      current_user={@current_user}
    />
    <div id="sound-notifier" phx-hook="SoundNotifier" class="hidden"></div>
    <div class="min-h-screen bg-base-200 pt-20 pb-10 px-4">
      <div class="max-w-6xl mx-auto space-y-4">
        <%!-- Header --%>
        <% pending = pending_orders(@orders) %>
        <div class="flex items-center justify-between flex-wrap gap-3">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Cocina</h1>
            <p class="text-sm text-base-content/70">
              {length(pending)} {if length(pending) == 1, do: "pedido", else: "pedidos"} en espera
            </p>
          </div>
          <StationComponents.sound_hint />
        </div>

        <%!-- How it works — names the exact buttons below; always visible for temporary staff --%>
        <div class="bg-base-100 border border-base-300 rounded-2xl px-4 py-3">
          <StationComponents.how_to steps={[
            {"Empieza por la", "1", "— es la que lleva más tiempo"},
            {"Marca", "Listo", "cada platillo al terminarlo"},
            {"Toca", "Todo listo", "cuando salga la comanda completa"}
          ]} />
        </div>

        <%!-- Cancellation alerts --%>
        <%= for alert <- @cancel_alerts do %>
          <div class="alert alert-error py-2 flex items-center gap-3 shadow-sm" role="alert">
            <.icon name="hero-x-circle" class="size-5 shrink-0" />
            <span class="text-sm font-semibold flex-1">
              Cancelado: <span class="font-bold">{alert.customer}</span>
              — {alert.quantity}× {alert.item_name}
            </span>
            <button
              phx-click="dismiss_cancel_alert"
              phx-value-id={alert.id}
              class="btn btn-sm btn-ghost min-h-11 text-error-content"
            >
              Entendido
            </button>
          </div>
        <% end %>

        <%!-- View toggle --%>
        <%= if pending != [] do %>
          <div class="flex">
            <StationComponents.view_toggle view_mode={@view_mode} grouped_label="Por platillo" />
          </div>
        <% end %>

        <%!-- No pending orders --%>
        <%= if pending == [] do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 py-16 px-6 text-center space-y-2">
            <.icon name="hero-check-circle" class="size-12 text-success mx-auto" />
            <p class="text-base font-semibold text-base-content">
              No hay pedidos pendientes en cocina.
            </p>
            <p class="text-sm text-base-content/70">
              Cuando un mesero envíe una comanda aparecerá aquí y sonará un aviso.
            </p>
          </div>
        <% end %>

        <%= if @view_mode == :grouped do %>
          <%!-- Per-dish view — one card per dish across all comandas, to batch them --%>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 items-start">
            <%= for {group, position} <- Enum.with_index(group_kitchen_items(pending), 1) do %>
              <% gmins = group_elapsed_minutes(group.oldest_sent_at, @now) %>
              <%!-- Stable id: LiveView patches this card in place instead of reusing another's nodes --%>
              <.kitchen_card id={"kitchen-group-#{group.menu_item.id}"} mins={gmins}>
                <header class="px-4 py-3 flex items-center gap-3">
                  <SiteComponents.queue_number n={position} />
                  <div class="flex-1 min-w-0">
                    <h2 class="text-lg font-bold text-base-content leading-tight">
                      <span class="text-primary tabular-nums">{group.total_qty}×</span>
                      {group.menu_item.name}
                    </h2>
                    <p class="text-sm text-base-content/70">
                      {group.entry_count} {if group.entry_count == 1,
                        do: "comanda",
                        else: "comandas"}
                    </p>
                  </div>
                  <StationComponents.wait_time mins={gmins} />
                </header>
                <ul class="divide-y divide-base-200 border-t border-base-200">
                  <li :for={entry <- group.entries} class="flex items-center gap-3 px-4 py-2.5">
                    <div class="flex-1 min-w-0">
                      <%!-- Always the comanda: with many orders open, a bare "Ana" is ambiguous --%>
                      <p class="text-base font-semibold text-base-content">
                        {entry.order.customer_name}
                        <span :if={entry.item.quantity > 1} class="text-primary tabular-nums">
                          ×{entry.item.quantity}
                        </span>
                      </p>
                      <StationComponents.item_details item={entry.item} order={entry.order} />
                    </div>
                    <StationComponents.ready_button id={entry.item.id} />
                  </li>
                </ul>
                <div class="px-3 py-3 border-t border-base-200 mt-auto">
                  <button
                    class="btn btn-success min-h-12 w-full gap-1.5"
                    phx-click="mark_group_ready"
                    phx-value-ids={Enum.join(group.item_ids, ",")}
                  >
                    <.icon name="hero-check" class="size-5" /> Todo listo
                  </button>
                </div>
              </.kitchen_card>
            <% end %>
          </div>
        <% else %>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 items-start">
            <%= for {order, position} <-
                  pending
                  |> Enum.filter(&(food_items(&1) != []))
                  |> Enum.with_index(1) do %>
              <% food_items = food_items(order) %>
              <% mins = elapsed_minutes(order, @now, &kitchen_item?/1) %>
              <.kitchen_card id={"kitchen-order-#{order.id}"} mins={mins}>
                <header class="px-4 py-3 flex items-center gap-3">
                  <SiteComponents.queue_number n={position} />
                  <div class="flex-1 min-w-0">
                    <h2 class="text-lg font-bold text-base-content leading-tight truncate">
                      {order.customer_name}
                    </h2>
                    <p class="text-sm text-base-content/70 flex items-center gap-x-2 flex-wrap">
                      <span>
                        {length(food_items)} {if length(food_items) == 1,
                          do: "platillo",
                          else: "platillos"}
                      </span>
                      <span :if={order.order_type == "takeout"} class="inline-flex items-center gap-1">
                        <.icon name="hero-shopping-bag" class="size-3.5" /> Para llevar
                      </span>
                      <span :if={order.is_group} class="inline-flex items-center gap-1">
                        <.icon name="hero-user-group" class="size-3.5" /> Grupo
                      </span>
                    </p>
                  </div>
                  <StationComponents.wait_time mins={mins} />
                </header>
                <ul class="divide-y divide-base-200 border-t border-base-200">
                  <li :for={item <- food_items} class="flex items-center gap-3 px-4 py-2.5">
                    <div class="flex-1 min-w-0">
                      <p class="text-base font-semibold text-base-content">
                        <span class="text-primary tabular-nums">{item.quantity}×</span>
                        <%= if item.product_id do %>
                          <span class="text-base-content/70">Extra:</span> {item.product.name}
                          <span
                            :if={item.portion_quantity}
                            class="text-sm text-base-content/70 font-normal"
                          >
                            ({format_qty(item.portion_quantity)} {item.product.unit})
                          </span>
                        <% else %>
                          {item.menu_item.name}
                        <% end %>
                        <span :if={item.package_id} class="badge badge-sm badge-ghost ml-1">
                          Paquete
                        </span>
                      </p>
                      <%!-- Which dish this extra belongs to --%>
                      <p
                        :if={item.product_id && item.for_menu_item}
                        class="text-sm text-base-content/70 mt-0.5 flex items-center gap-1"
                      >
                        <.icon name="hero-arrow-turn-down-right" class="size-3.5 shrink-0" /> para
                        <span class="font-semibold">{item.for_menu_item.name}</span>
                      </p>
                      <StationComponents.item_details item={item} order={order} />
                    </div>
                    <StationComponents.ready_button id={item.id} />
                  </li>
                </ul>
                <div class="px-3 py-3 border-t border-base-200 mt-auto">
                  <button
                    class="btn btn-success min-h-12 w-full gap-1.5"
                    phx-click="mark_order_ready"
                    phx-value-id={order.id}
                  >
                    <.icon name="hero-check" class="size-5" /> Todo listo
                  </button>
                </div>
              </.kitchen_card>
            <% end %>
          </div>
        <% end %>

        <%!-- Ready orders, waiting for the waiter --%>
        <% ready = ready_orders(@orders) %>
        <%= if ready != [] do %>
          <section class="space-y-2 pt-4">
            <h2 class="text-base font-semibold text-base-content">Listos para servir</h2>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
              <%= for order <- ready do %>
                <div class="bg-base-100 rounded-xl border border-success/40 px-4 py-3 flex items-center gap-3">
                  <.icon name="hero-check-circle" class="size-5 text-success shrink-0" />
                  <p class="font-semibold text-base-content truncate flex-1">{order.customer_name}</p>
                  <p class="text-sm text-base-content/70 shrink-0">
                    {kitchen_item_count(order)} platillos
                  </p>
                </div>
              <% end %>
            </div>
          </section>
        <% end %>
      </div>
    </div>
    <.flash_group flash={@flash} />
    """
  end

  # Card shell: neutral, with a red border only when the comanda is late (≥12 min)
  attr :id, :string, required: true
  attr :mins, :any, default: nil
  slot :inner_block, required: true

  defp kitchen_card(assigns) do
    ~H"""
    <article
      id={@id}
      class={[
        "bg-base-100 rounded-2xl border shadow-sm flex flex-col overflow-hidden",
        if(@mins && @mins >= 12, do: "border-error", else: "border-base-300")
      ]}
    >
      {render_slot(@inner_block)}
    </article>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Only show items actively waiting to be prepared (not yet marked ready).
  # Excludes "ready" items so that second-batch sends don't resurface
  # already-prepared items in the cooking queue.
  defp food_items(order) do
    Enum.filter(order.order_items, fn oi ->
      oi.status == "sent" and kitchen_item?(oi)
    end)
  end

  # Total kitchen item count for an order (sent + ready) — used in display labels.
  defp kitchen_item_count(order) do
    Enum.count(order.order_items, &kitchen_item?/1)
  end

  # Ingredient extras (product_id set, no menu_item) always go to cocina
  defp kitchen_item?(%{product_id: pid}) when not is_nil(pid), do: true
  defp kitchen_item?(%{menu_item: mi}) when not is_nil(mi), do: mi.destination == "cocina"
  defp kitchen_item?(_), do: false

  defp format_qty(%Decimal{} = qty) do
    str = qty |> Decimal.round(3) |> Decimal.to_string()

    if String.contains?(str, ".") do
      str |> String.trim_trailing("0") |> String.trim_trailing(".")
    else
      str
    end
  end

  # An order is pending in cocina if ANY kitchen item still has status "sent".
  # Sorted by oldest sent_at first (FIFO) so the team always works in arrival order.
  defp pending_orders(orders) do
    orders
    |> Enum.filter(fn o ->
      Enum.any?(o.order_items, fn oi -> oi.status == "sent" and kitchen_item?(oi) end)
    end)
    |> Enum.sort_by(
      fn o ->
        o.order_items
        |> Enum.filter(&(&1.status == "sent" and kitchen_item?(&1) and not is_nil(&1.sent_at)))
        |> Enum.map(& &1.sent_at)
        |> Enum.min(DateTime, fn -> DateTime.utc_now() end)
      end,
      DateTime
    )
  end

  defp ready_orders(orders), do: Enum.filter(orders, &(&1.status == "ready"))

  # Minutes elapsed since the oldest sent item of the given type in this order.
  # Returns nil if no sent items with a sent_at timestamp exist.
  defp elapsed_minutes(order, now, item_filter) do
    sent_ats =
      order.order_items
      |> Enum.filter(&(&1.status == "sent" and not is_nil(&1.sent_at) and item_filter.(&1)))
      |> Enum.map(& &1.sent_at)

    case sent_ats do
      [] -> nil
      ats -> DateTime.diff(now, Enum.min(ats, DateTime), :minute)
    end
  end

  # Returns the set of IDs of kitchen items currently in "sent" state.
  # Used to detect newly-arrived items and trigger the notification sound.
  defp sent_kitchen_ids(orders) do
    orders
    |> Enum.flat_map(& &1.order_items)
    |> Enum.filter(&(&1.status == "sent" and kitchen_item?(&1)))
    |> MapSet.new(& &1.id)
  end

  # Human-readable label for a cancelled item (menu item name or product name).
  defp item_label(%{menu_item: %{name: name}}) when not is_nil(name), do: name
  defp item_label(%{product: %{name: name}}) when not is_nil(name), do: "Extra: #{name}"
  defp item_label(_), do: "Artículo"

  # Groups all pending kitchen items by menu_item_id across all orders.
  # Returns a list of maps, the longest-waiting dish first.
  defp group_kitchen_items(orders) do
    orders
    |> Enum.flat_map(fn order ->
      order.order_items
      |> Enum.filter(fn oi ->
        oi.status == "sent" and kitchen_item?(oi) and not is_nil(oi.menu_item_id)
      end)
      |> Enum.map(fn oi -> {order, oi} end)
    end)
    |> Enum.group_by(fn {_order, oi} -> oi.menu_item_id end)
    |> Enum.map(fn {_id, entries} ->
      {_order, first} = hd(entries)
      total_qty = Enum.sum(Enum.map(entries, fn {_, oi} -> oi.quantity end))
      item_ids = Enum.map(entries, fn {_, oi} -> oi.id end)

      oldest_sent_at =
        entries
        |> Enum.map(fn {_, oi} -> oi.sent_at end)
        |> Enum.reject(&is_nil/1)
        |> case do
          [] -> nil
          ats -> Enum.min(ats, DateTime)
        end

      %{
        menu_item: first.menu_item,
        total_qty: total_qty,
        entry_count: length(entries),
        item_ids: item_ids,
        oldest_sent_at: oldest_sent_at,
        entries: Enum.map(entries, fn {order, oi} -> %{order: order, item: oi} end)
      }
    end)
    # Oldest waiting dish first (FIFO), same as the per-order view
    |> Enum.sort_by(&queue_key(&1.oldest_sent_at))
  end

  # Sort key for FIFO: earliest sent_at first, groups without one last
  defp queue_key(nil), do: {1, 0}
  defp queue_key(sent_at), do: {0, DateTime.to_unix(sent_at)}

  defp group_elapsed_minutes(nil, _now), do: nil
  defp group_elapsed_minutes(sent_at, now), do: DateTime.diff(now, sent_at, :minute)

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_interval)
end
