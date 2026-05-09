defmodule CRCWeb.Kitchen.DisplayLive do
  @moduledoc "Kitchen (cocina) display screen. Shows sent orders filtered to food items only."

  use CRCWeb, :live_view

  import CRCWeb.Layouts, only: [flash_group: 1]

  alias CRC.Orders
  alias CRCWeb.Components.SiteComponents

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
      <div class="max-w-6xl mx-auto space-y-6">
        <%!-- Header --%>
        <div class="flex items-center justify-between flex-wrap gap-3">
          <div>
            <h1 class="text-2xl font-bold text-base-content">🍳 Cocina</h1>
            <p class="text-sm text-base-content/50 mt-0.5">Platillos y comida</p>
          </div>
          <div class="flex items-center gap-2">
            <% pending = pending_orders(@orders) %>
            <span class="badge badge-lg badge-warning">
              {length(pending)} {if length(pending) == 1, do: "pedido", else: "pedidos"}
            </span>
          </div>
        </div>

        <%!-- Onboarding tip (dismissed per-browser via localStorage) --%>
        <div
          id="tip-cocina"
          phx-hook="DismissableTip"
          data-tip-id="cocina"
          class="bg-base-100 border border-primary/30 rounded-2xl shadow-sm px-5 py-4 space-y-3"
        >
          <div class="flex items-center justify-between gap-3">
            <div class="flex items-center gap-2">
              <span>💡</span>
              <p class="font-semibold text-base-content text-sm">¿Primera vez en Cocina?</p>
            </div>
            <button data-dismiss-tip class="btn btn-xs btn-ghost text-base-content/40 shrink-0">✕ Entendido</button>
          </div>
          <ul class="space-y-2 text-sm text-base-content/70">
            <li class="flex items-start gap-2">
              <span class="shrink-0 mt-0.5 w-5 h-5 rounded-full bg-primary/15 text-primary text-xs flex items-center justify-center font-bold">1</span>
              <span>Los platillos llegan solos cuando el mesero envía una comanda.</span>
            </li>
            <li class="flex items-start gap-2">
              <span class="shrink-0 mt-0.5 w-5 h-5 rounded-full bg-primary/15 text-primary text-xs flex items-center justify-center font-bold">2</span>
              <span>El reloj 🕐 muestra el tiempo de espera: 🟢 &lt;7 min · 🟡 7-12 min · 🔴 +12 min.</span>
            </li>
            <li class="flex items-start gap-2">
              <span class="shrink-0 mt-0.5 w-5 h-5 rounded-full bg-primary/15 text-primary text-xs flex items-center justify-center font-bold">3</span>
              <span><strong>Agrupado</strong>: junta el mismo platillo de varias mesas para prepararlo todo de un golpe.</span>
            </li>
            <li class="flex items-start gap-2">
              <span class="shrink-0 mt-0.5 w-5 h-5 rounded-full bg-primary/15 text-primary text-xs flex items-center justify-center font-bold">4</span>
              <span>Toca <strong>Listo</strong> en cada platillo, o <strong>Todo listo</strong> para cerrar toda la mesa de una vez.</span>
            </li>
          </ul>
        </div>

        <%!-- Cancellation alerts --%>
        <%= for alert <- @cancel_alerts do %>
          <div class="alert alert-error py-2 flex items-center gap-3 shadow-sm">
            <.icon name="hero-x-circle" class="size-5 shrink-0" />
            <span class="text-sm font-semibold flex-1">
              ⚠ Cancelado:
              <span class="font-bold">{alert.customer}</span>
              — {alert.quantity}× {alert.item_name}
            </span>
            <button
              phx-click="dismiss_cancel_alert"
              phx-value-id={alert.id}
              class="btn btn-xs btn-ghost text-error-content"
            >
              Entendido
            </button>
          </div>
        <% end %>

        <%!-- View mode toggle --%>
        <%= if pending_orders(@orders) != [] do %>
          <div class="flex gap-1 bg-base-200 rounded-xl p-1 w-fit">
            <button
              class={["btn btn-xs gap-1.5", if(@view_mode == :by_order, do: "btn-primary", else: "btn-ghost")]}
              phx-click="set_view_mode"
              phx-value-mode="by_order"
            >
              <.icon name="hero-squares-2x2" class="size-3" /> Por mesa
            </button>
            <button
              class={["btn btn-xs gap-1.5", if(@view_mode == :grouped, do: "btn-primary", else: "btn-ghost")]}
              phx-click="set_view_mode"
              phx-value-mode="grouped"
            >
              <.icon name="hero-queue-list" class="size-3" /> Agrupado
            </button>
          </div>
        <% end %>

        <%!-- No pending orders --%>
        <%= if pending_orders(@orders) == [] do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-20 text-center">
            <.icon name="hero-check-circle" class="size-12 text-success mx-auto mb-3" />
            <p class="text-base-content/50 text-sm">No hay pedidos pendientes en cocina.</p>
          </div>
        <% end %>

        <%!-- Orders grid (food items only) --%>
        <%= if @view_mode == :grouped do %>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <%= for group <- group_kitchen_items(pending_orders(@orders)) do %>
              <% gmins = group_elapsed_minutes(group.oldest_sent_at, @now) %>
              <div class="bg-base-100 rounded-2xl border border-warning shadow-sm flex flex-col">
                <div class="px-4 py-3 bg-warning/10 rounded-t-2xl border-b border-warning/30 flex items-center gap-2">
                  <div class="flex-1 min-w-0">
                    <h2 class="font-bold text-base-content truncate">
                      <span class="text-primary text-lg">{group.total_qty}×</span>
                      {group.menu_item.name}
                    </h2>
                    <p class="text-xs text-base-content/50">
                      {group.entry_count} {if group.entry_count == 1, do: "mesa", else: "mesas"}
                    </p>
                  </div>
                  <div class="flex items-center gap-2 shrink-0">
                    <%= if gmins do %>
                      <span class={[
                        "text-xs font-mono font-semibold tabular-nums",
                        cond do
                          gmins >= 12 -> "text-error animate-pulse"
                          gmins >= 7 -> "text-warning"
                          true -> "text-success"
                        end
                      ]}>
                        🕐 {gmins}m
                      </span>
                    <% end %>
                    <span class="badge badge-warning badge-sm">Pendiente</span>
                  </div>
                </div>
                <div class="flex-1 divide-y divide-base-200">
                  <%= for entry <- group.entries do %>
                    <% item = entry.item %>
                    <% display_name = if item.for_person && item.for_person != "", do: item.for_person, else: entry.order.customer_name %>
                    <% item_variants = Enum.filter(entry.order.order_items, fn oi -> not is_nil(oi.variant_id) and oi.for_menu_item_id == item.menu_item_id end) %>
                    <div class="flex items-start gap-3 px-4 py-3">
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-medium text-base-content">
                          {display_name}
                          <%= if item.quantity > 1 do %>
                            <span class="text-xs text-base-content/50 font-normal ml-1">×{item.quantity}</span>
                          <% end %>
                        </p>
                        <%= if item_variants != [] do %>
                          <div class="flex flex-wrap items-center gap-1 mt-1">
                            <%= for vi <- item_variants do %>
                              <span class="badge badge-xs badge-primary">{vi.variant.name}</span>
                            <% end %>
                          </div>
                        <% end %>
                        <%= if item.exclusions != [] do %>
                          <div class="flex flex-wrap items-center gap-1 mt-1">
                            <span class="text-xs font-bold text-error shrink-0">⚠ Sin:</span>
                            <%= for excl <- item.exclusions do %>
                              <span class="badge badge-xs badge-error">{excl.product.name}</span>
                            <% end %>
                          </div>
                        <% end %>
                        <%= if item.notes && item.notes != "" do %>
                          <div class="flex items-center gap-1 mt-1 bg-warning/15 rounded px-1.5 py-0.5">
                            <span class="text-xs shrink-0">📝</span>
                            <p class="text-xs font-semibold text-warning">{item.notes}</p>
                          </div>
                        <% end %>
                      </div>
                      <%= if item.status == "ready" do %>
                        <span class="badge badge-xs badge-success shrink-0">Listo</span>
                      <% else %>
                        <button
                          class="btn btn-xs btn-outline btn-success shrink-0"
                          phx-click="mark_item_ready"
                          phx-value-id={item.id}
                        >
                          Listo
                        </button>
                      <% end %>
                    </div>
                  <% end %>
                </div>
                <div class="px-4 py-3 border-t border-base-300">
                  <button
                    class="btn btn-success w-full btn-sm overflow-hidden"
                    phx-click="mark_group_ready"
                    phx-value-ids={Enum.join(group.item_ids, ",")}
                  >
                    <.icon name="hero-check" class="size-4 shrink-0" />
                    <span class="truncate">Todo listo — {group.menu_item.name}</span>
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <%= for order <- pending_orders(@orders) do %>
            <% food_items = food_items(order) %>
            <% mins = elapsed_minutes(order, @now, &kitchen_item?/1) %>
            <%= if food_items != [] do %>
              <div class="bg-base-100 rounded-2xl border border-warning shadow-sm flex flex-col">
                <%!-- Order header --%>
                <div class="px-4 py-3 bg-warning/10 rounded-t-2xl border-b border-warning/30 flex items-center gap-2">
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2 flex-wrap">
                      <h2 class="font-bold text-base-content truncate">{order.customer_name}</h2>
                      <%= if order.order_type == "takeout" do %>
                        <span class="badge badge-xs badge-accent shrink-0">🛍 Para llevar</span>
                      <% end %>
                      <%= if order.is_group do %>
                        <span class="badge badge-xs badge-ghost shrink-0">👥 Grupo</span>
                      <% end %>
                    </div>
                    <p class="text-xs text-base-content/50">
                      {length(food_items)} {if length(food_items) == 1,
                        do: "platillo",
                        else: "platillos"}
                    </p>
                  </div>
                  <div class="flex items-center gap-2 shrink-0">
                    <%= if mins do %>
                      <span class={[
                        "text-xs font-mono font-semibold tabular-nums",
                        cond do
                          mins >= 12 -> "text-error animate-pulse"
                          mins >= 7 -> "text-warning"
                          true -> "text-success"
                        end
                      ]}>
                        🕐 {mins}m
                      </span>
                    <% end %>
                    <span class="badge badge-warning badge-sm">Enviado</span>
                  </div>
                </div>

                <%!-- Food items list --%>
                <div class="flex-1 divide-y divide-base-200">
                  <%= for item <- food_items do %>
                    <div class="flex items-center gap-3 px-4 py-3">
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-medium text-base-content">
                          <span class="font-bold text-primary">{item.quantity}×</span>
                          <%= if item.product_id do %>
                            <span class="text-accent">Extra:</span> {item.product.name}
                            <%= if item.portion_quantity do %>
                              <span class="text-xs text-base-content/50 font-normal">
                                ({format_qty(item.portion_quantity)} {item.product.unit})
                              </span>
                            <% end %>
                          <% else %>
                            {item.menu_item.name}
                          <% end %>
                          <%= if item.package_id do %>
                            <span class="badge badge-xs badge-primary ml-1">Paquete</span>
                          <% end %>
                        </p>
                        <%!-- Show which dish this extra belongs to --%>
                        <%= if item.product_id && item.for_menu_item do %>
                          <p class="text-xs text-accent/70 mt-0.5 flex items-center gap-1">
                            <span>↳ para</span>
                            <span class="font-semibold">{item.for_menu_item.name}</span>
                          </p>
                        <% end %>
                        <%!-- Variant selections (e.g. leche de avena) --%>
                        <% item_variants =
                          Enum.filter(order.order_items, fn oi ->
                            not is_nil(oi.variant_id) and oi.for_menu_item_id == item.menu_item_id
                          end) %>
                        <%= if item_variants != [] do %>
                          <div class="flex flex-wrap items-center gap-1 mt-1">
                            <%= for vi <- item_variants do %>
                              <span class="badge badge-xs badge-primary">{vi.variant.name}</span>
                            <% end %>
                          </div>
                        <% end %>
                        <%!-- Ingredient exclusions requested by customer --%>
                        <%= if item.exclusions != [] do %>
                          <div class="flex flex-wrap items-center gap-1 mt-1">
                            <span class="text-xs font-bold text-error shrink-0">⚠ Sin:</span>
                            <%= for excl <- item.exclusions do %>
                              <span class="badge badge-xs badge-error">{excl.product.name}</span>
                            <% end %>
                          </div>
                        <% end %>
                        <%!-- Who at the table ordered this item --%>
                        <%= if item.for_person && item.for_person != "" do %>
                          <div class="flex items-center gap-1 mt-1">
                            <span class="text-xs shrink-0 select-none">👤</span>
                            <p class="text-xs font-semibold text-base-content/70">{item.for_person}</p>
                          </div>
                        <% end %>
                        <%= if item.notes && item.notes != "" do %>
                          <div class="flex items-center gap-1 mt-1 bg-warning/15 rounded px-1.5 py-0.5">
                            <span class="text-xs shrink-0 select-none">📝</span>
                            <p class="text-xs font-semibold text-warning">{item.notes}</p>
                          </div>
                        <% end %>
                      </div>

                      <%= if item.status == "ready" do %>
                        <span class="badge badge-xs badge-success">Listo</span>
                      <% else %>
                        <button
                          class="btn btn-xs btn-outline btn-success"
                          phx-click="mark_item_ready"
                          phx-value-id={item.id}
                        >
                          Listo
                        </button>
                      <% end %>
                    </div>
                  <% end %>
                </div>

                <%!-- Mark all food ready --%>
                <div class="px-4 py-3 border-t border-base-300">
                  <button
                    class="btn btn-success w-full btn-sm overflow-hidden"
                    phx-click="mark_order_ready"
                    phx-value-id={order.id}
                  >
                    <.icon name="hero-check" class="size-4 shrink-0" />
                    <span class="truncate">Todo listo — {order.customer_name}</span>
                  </button>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
        <% end %>

        <%!-- Ready orders --%>
        <% ready = ready_orders(@orders) %>
        <%= if ready != [] do %>
          <div class="space-y-3">
            <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider">
              Listos para servir
            </h2>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for order <- ready do %>
                <div class="bg-base-100 rounded-2xl border border-success/50 shadow-sm px-4 py-4 flex items-center gap-3">
                  <div class="flex-1 min-w-0">
                    <p class="font-bold text-base-content truncate">{order.customer_name}</p>
                    <p class="text-xs text-base-content/50">
                      {kitchen_item_count(order)} platillos
                    </p>
                  </div>
                  <span class="badge badge-success shrink-0">Lista</span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    <.flash_group flash={@flash} />
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
  # Returns a list of maps sorted by total quantity descending.
  defp group_kitchen_items(orders) do
    orders
    |> Enum.flat_map(fn order ->
      order.order_items
      |> Enum.filter(fn oi -> oi.status == "sent" and kitchen_item?(oi) and not is_nil(oi.menu_item_id) end)
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
    |> Enum.sort_by(& &1.total_qty, :desc)
  end

  defp group_elapsed_minutes(nil, _now), do: nil
  defp group_elapsed_minutes(sent_at, now), do: DateTime.diff(now, sent_at, :minute)

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_interval)
end
