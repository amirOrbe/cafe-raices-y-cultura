defmodule CRCWeb.Barra.DisplayLive do
  @moduledoc "Barra display screen. Shows sent orders filtered to drink items only, split by temperature."

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
      |> assign(:page_title, "Barra")
      |> assign(:orders, orders)
      |> assign(:nav_open, false)
      |> assign(:now, DateTime.utc_now())
      |> assign(:seen_sent_ids, sent_drink_ids(orders))
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
    new_ids = sent_drink_ids(new_orders)
    disappeared_ids = MapSet.difference(socket.assigns.seen_sent_ids, new_ids)
    new_items? = not MapSet.subset?(new_ids, socket.assigns.seen_sent_ids)

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

  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :view_mode, String.to_existing_atom(mode))}
  end

  def handle_event("mark_group_ready", %{"ids" => ids_str}, socket) do
    ids = ids_str |> String.split(",") |> Enum.map(&String.to_integer/1)
    Enum.each(ids, fn id -> Orders.mark_item_ready(id, socket.assigns.current_user.id) end)
    {:noreply, assign(socket, :orders, Orders.list_open_orders())}
  end

  # Marks all sent drink items of a specific barra_type (or all if type == "all") as ready.
  def handle_event("mark_drinks_ready", %{"id" => id, "type" => type}, socket) do
    order = Enum.find(socket.assigns.orders, &(to_string(&1.id) == id))

    if order do
      order.order_items
      |> Enum.filter(fn oi ->
        oi.status == "sent" and drink_item?(oi) and
          (type == "all" or barra_type(oi) == type)
      end)
      |> Enum.each(fn oi -> Orders.mark_item_ready(oi.id, socket.assigns.current_user.id) end)

      label =
        case type do
          "caliente" -> "#{order.customer_name} — calientes listos."
          "fria" -> "#{order.customer_name} — frías listas."
          _ -> "#{order.customer_name} lista en barra."
        end

      {:noreply,
       socket
       |> put_flash(:info, label)
       |> assign(:orders, Orders.list_open_orders())}
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <SiteComponents.site_navbar
      nav_open={@nav_open}
      current_page={:barra}
      current_user={@current_user}
    />
    <div id="sound-notifier" phx-hook="SoundNotifier" class="hidden"></div>
    <div class="min-h-screen bg-base-200 pt-20 pb-10 px-4">
      <div class="max-w-6xl mx-auto space-y-6">
        <%!-- Header --%>
        <div class="flex items-center justify-between flex-wrap gap-3">
          <div>
            <h1 class="text-2xl font-bold text-base-content">🍹 Barra</h1>
            <p class="text-sm text-base-content/50 mt-0.5">Bebidas</p>
          </div>
          <div class="flex items-center gap-2">
            <% pending = pending_orders(@orders) %>
            <span class="badge badge-lg badge-info">
              {length(pending)} {if length(pending) == 1, do: "pedido", else: "pedidos"}
            </span>
          </div>
        </div>

        <%!-- Onboarding tip (dismissed per-browser via localStorage) --%>
        <div
          id="tip-barra"
          phx-hook="DismissableTip"
          data-tip-id="barra"
          class="bg-base-100 border border-info/30 rounded-2xl shadow-sm px-5 py-4 space-y-3"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="flex items-center gap-2">
              <span class="text-lg">💡</span>
              <p class="font-semibold text-base-content text-sm">¿Primera vez en Barra?</p>
            </div>
            <button data-dismiss-tip class="btn btn-xs btn-ghost text-base-content/40">✕ Entendido</button>
          </div>
          <ol class="space-y-1.5 text-sm text-base-content/70 list-none pl-0">
            <li class="flex items-start gap-2">
              <span class="shrink-0 w-5 h-5 rounded-full bg-info/15 text-info text-xs flex items-center justify-center font-bold">1</span>
              Las bebidas llegan automáticamente cuando el mesero envía una comanda.
            </li>
            <li class="flex items-start gap-2">
              <span class="shrink-0 w-5 h-5 rounded-full bg-info/15 text-info text-xs flex items-center justify-center font-bold">2</span>
              Las bebidas se dividen en ☕ <strong>Calientes</strong> y ❄️ <strong>Frías</strong> para facilitar la preparación.
            </li>
            <li class="flex items-start gap-2">
              <span class="shrink-0 w-5 h-5 rounded-full bg-info/15 text-info text-xs flex items-center justify-center font-bold">3</span>
              Vista <strong>Agrupado</strong>: junta la misma bebida de varias mesas — ideal para preparar varios cafés seguidos.
            </li>
            <li class="flex items-start gap-2">
              <span class="shrink-0 w-5 h-5 rounded-full bg-info/15 text-info text-xs flex items-center justify-center font-bold">4</span>
              Toca <strong>Listo</strong> en cada bebida o <strong>Todo listo</strong> para avisar al mesero que puede servir.
            </li>
          </ol>
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

        <%!-- No pending orders --%>
        <%= if pending_orders(@orders) == [] do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-20 text-center">
            <.icon name="hero-check-circle" class="size-12 text-success mx-auto mb-3" />
            <p class="text-base-content/50 text-sm">No hay bebidas pendientes.</p>
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

        <%!-- Grouped view — one card per drink, across all mesas --%>
        <%= if @view_mode == :grouped do %>
          <% grouped_caliente = group_drink_items(pending_orders(@orders), "caliente") %>
          <%= if grouped_caliente != [] do %>
            <div class="space-y-3">
              <h2 class="flex items-center gap-2 text-sm font-semibold text-base-content/70 uppercase tracking-wider">
                <span>☕</span> Calientes
                <span class="badge badge-sm badge-error">{length(grouped_caliente)}</span>
              </h2>
              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <%= for group <- grouped_caliente do %>
                  <% gmins = group_elapsed_minutes(group.oldest_sent_at, @now) %>
                  <.grouped_drink_card group={group} gmins={gmins} border_class="border-error" header_class="bg-error/10 border-error/30" />
                <% end %>
              </div>
            </div>
          <% end %>

          <% grouped_fria = group_drink_items(pending_orders(@orders), "fria") %>
          <%= if grouped_fria != [] do %>
            <div class="space-y-3">
              <h2 class="flex items-center gap-2 text-sm font-semibold text-base-content/70 uppercase tracking-wider">
                <span>❄️</span> Frías
                <span class="badge badge-sm badge-info">{length(grouped_fria)}</span>
              </h2>
              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <%= for group <- grouped_fria do %>
                  <% gmins = group_elapsed_minutes(group.oldest_sent_at, @now) %>
                  <.grouped_drink_card group={group} gmins={gmins} border_class="border-info" header_class="bg-info/10 border-info/30" />
                <% end %>
              </div>
            </div>
          <% end %>

          <% grouped_other = group_drink_items(pending_orders(@orders), nil) %>
          <%= if grouped_other != [] do %>
            <div class="space-y-3">
              <h2 class="flex items-center gap-2 text-sm font-semibold text-base-content/60 uppercase tracking-wider">
                <span>🍹</span> Bebidas
                <span class="badge badge-sm badge-ghost">{length(grouped_other)}</span>
              </h2>
              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <%= for group <- grouped_other do %>
                  <% gmins = group_elapsed_minutes(group.oldest_sent_at, @now) %>
                  <.grouped_drink_card group={group} gmins={gmins} border_class="border-info" header_class="bg-info/10 border-info/30" />
                <% end %>
              </div>
            </div>
          <% end %>
        <% else %>
          <%!-- ── By-order view ─────────────────────────────────────────────────── --%>

          <%!-- ── Calientes section ──────────────────────────────────────────────── --%>
          <% caliente_orders = orders_by_type(@orders, "caliente") %>
          <%= if caliente_orders != [] do %>
            <div class="space-y-3">
              <h2 class="flex items-center gap-2 text-sm font-semibold text-base-content/70 uppercase tracking-wider">
                <span>☕</span> Calientes
                <span class="badge badge-sm badge-error">{length(caliente_orders)}</span>
              </h2>
              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <%= for order <- caliente_orders do %>
                  <.drink_order_card
                    order={order}
                    items={typed_drink_items(order, "caliente")}
                    badge_class="badge-error"
                    border_class="border-error"
                    header_class="bg-error/10 border-error/30"
                    type="caliente"
                    mins={elapsed_minutes(order, @now, &drink_item?/1)}
                  />
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- ── Frías section ──────────────────────────────────────────────────── --%>
          <% fria_orders = orders_by_type(@orders, "fria") %>
          <%= if fria_orders != [] do %>
            <div class="space-y-3">
              <h2 class="flex items-center gap-2 text-sm font-semibold text-base-content/70 uppercase tracking-wider">
                <span>❄️</span> Frías
                <span class="badge badge-sm badge-info">{length(fria_orders)}</span>
              </h2>
              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <%= for order <- fria_orders do %>
                  <.drink_order_card
                    order={order}
                    items={typed_drink_items(order, "fria")}
                    badge_class="badge-info"
                    border_class="border-info"
                    header_class="bg-info/10 border-info/30"
                    type="fria"
                    mins={elapsed_minutes(order, @now, &drink_item?/1)}
                  />
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- ── Sin clasificar (items without barra_type set) ─────────────────── --%>
          <% other_orders = orders_by_type(@orders, nil) %>
          <%= if other_orders != [] do %>
            <div class="space-y-3">
              <h2 class="flex items-center gap-2 text-sm font-semibold text-base-content/60 uppercase tracking-wider">
                <span>🍹</span> Bebidas
                <span class="badge badge-sm badge-ghost">{length(other_orders)}</span>
              </h2>
              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <%= for order <- other_orders do %>
                  <.drink_order_card
                    order={order}
                    items={typed_drink_items(order, nil)}
                    badge_class="badge-info"
                    border_class="border-info"
                    header_class="bg-info/10 border-info/30"
                    type="all"
                    mins={elapsed_minutes(order, @now, &drink_item?/1)}
                  />
                <% end %>
              </div>
            </div>
          <% end %>
        <% end %>

        <%!-- Ready orders --%>
        <% ready = ready_drink_orders(@orders) %>
        <%= if ready != [] do %>
          <div class="space-y-3">
            <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider">
              Listos para servir
            </h2>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for order <- ready do %>
                <div class="bg-base-100 rounded-2xl border border-success/50 shadow-sm px-4 py-4 flex items-center justify-between">
                  <div>
                    <p class="font-bold text-base-content">{order.customer_name}</p>
                    <p class="text-xs text-base-content/50">
                      {Enum.count(order.order_items, &drink_item?/1)} bebidas
                    </p>
                  </div>
                  <span class="badge badge-success">Lista</span>
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
  # Private components
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Grouped drink card component
  # ---------------------------------------------------------------------------

  attr :group, :map, required: true
  attr :gmins, :any, default: nil
  attr :border_class, :string, required: true
  attr :header_class, :string, required: true

  defp grouped_drink_card(assigns) do
    ~H"""
    <div class={"bg-base-100 rounded-2xl border shadow-sm flex flex-col #{@border_class}"}>
      <div class={"px-4 py-3 rounded-t-2xl border-b flex items-center justify-between #{@header_class}"}>
        <div>
          <h2 class="font-bold text-base-content">
            <span class="text-primary text-lg">{@group.total_qty}×</span>
            {@group.menu_item.name}
          </h2>
          <p class="text-xs text-base-content/50">
            {@group.entry_count} {if @group.entry_count == 1, do: "mesa", else: "mesas"}
          </p>
        </div>
        <div class="flex items-center gap-2">
          <%= if @gmins do %>
            <span class={[
              "text-xs font-mono font-semibold tabular-nums",
              cond do
                @gmins >= 12 -> "text-error animate-pulse"
                @gmins >= 7 -> "text-warning"
                true -> "text-success"
              end
            ]}>
              🕐 {@gmins}m
            </span>
          <% end %>
          <span class="badge badge-sm badge-info">Pendiente</span>
        </div>
      </div>
      <div class="flex-1 divide-y divide-base-200">
        <%= for entry <- @group.entries do %>
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
          class="btn btn-success w-full btn-sm"
          phx-click="mark_group_ready"
          phx-value-ids={Enum.join(@group.item_ids, ",")}
        >
          <.icon name="hero-check" class="size-4" /> Todo listo — {@group.menu_item.name}
        </button>
      </div>
    </div>
    """
  end

  attr :order, :map, required: true
  attr :items, :list, required: true
  attr :badge_class, :string, required: true
  attr :border_class, :string, required: true
  attr :header_class, :string, required: true
  attr :type, :string, required: true
  attr :mins, :any, default: nil

  defp drink_order_card(assigns) do
    ~H"""
    <div class={"bg-base-100 rounded-2xl border shadow-sm flex flex-col #{@border_class}"}>
      <%!-- Order header --%>
      <div class={"px-4 py-3 rounded-t-2xl border-b flex items-center justify-between #{@header_class}"}>
        <div>
          <h2 class="font-bold text-base-content">{@order.customer_name}</h2>
          <p class="text-xs text-base-content/50">
            {length(@items)} {if length(@items) == 1, do: "bebida", else: "bebidas"}
          </p>
        </div>
        <div class="flex items-center gap-2">
          <%= if @mins do %>
            <span class={[
              "text-xs font-mono font-semibold tabular-nums",
              cond do
                @mins >= 12 -> "text-error animate-pulse"
                @mins >= 7 -> "text-warning"
                true -> "text-success"
              end
            ]}>
              🕐 {@mins}m
            </span>
          <% end %>
          <span class={"badge badge-sm #{@badge_class}"}>Enviado</span>
        </div>
      </div>

      <%!-- Drink items list --%>
      <div class="flex-1 divide-y divide-base-200">
        <%= for item <- @items do %>
          <div class="flex items-center gap-3 px-4 py-3">
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-base-content">
                <span class="font-bold text-primary">{item.quantity}×</span>
                {item.menu_item && item.menu_item.name}
                <%= if item.package_id do %>
                  <span class="badge badge-xs badge-primary ml-1">Paquete</span>
                <% end %>
              </p>
              <%!-- Variant selections --%>
              <% item_variants =
                Enum.filter(@order.order_items, fn oi ->
                  not is_nil(oi.variant_id) and oi.for_menu_item_id == item.menu_item_id
                end) %>
              <%= if item_variants != [] do %>
                <div class="flex flex-wrap items-center gap-1 mt-1">
                  <%= for vi <- item_variants do %>
                    <span class="badge badge-xs badge-primary">{vi.variant.name}</span>
                  <% end %>
                </div>
              <% end %>
              <%!-- Ingredient exclusions --%>
              <%= if item.exclusions != [] do %>
                <div class="flex flex-wrap items-center gap-1 mt-1">
                  <span class="text-xs font-bold text-error shrink-0">⚠ Sin:</span>
                  <%= for excl <- item.exclusions do %>
                    <span class="badge badge-xs badge-error">{excl.product.name}</span>
                  <% end %>
                </div>
              <% end %>
              <%!-- Who at the table ordered this --%>
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

      <%!-- Mark all ready for this type --%>
      <div class="px-4 py-3 border-t border-base-300">
        <button
          class="btn btn-success w-full btn-sm"
          phx-click="mark_drinks_ready"
          phx-value-id={@order.id}
          phx-value-type={@type}
        >
          <.icon name="hero-check" class="size-4" /> Todo listo — {@order.customer_name}
        </button>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp drink_item?(oi) do
    not is_nil(oi.menu_item) and oi.menu_item.destination == "barra"
  end

  # Returns the barra_type of an item ("fria" | "caliente" | nil).
  defp barra_type(oi), do: oi.menu_item && oi.menu_item.barra_type

  # Sent drink items of a specific type for an order.
  # type == nil means items with no barra_type set.
  defp typed_drink_items(order, type) do
    Enum.filter(order.order_items, fn oi ->
      oi.status == "sent" and drink_item?(oi) and barra_type(oi) == type
    end)
  end

  # Orders that have at least one sent drink item of the given type.
  # Sorted by oldest sent_at first (FIFO) so the barista works in arrival order.
  defp orders_by_type(orders, type) do
    orders
    |> Enum.filter(fn o ->
      Enum.any?(o.order_items, fn oi ->
        oi.status == "sent" and drink_item?(oi) and barra_type(oi) == type
      end)
    end)
    |> Enum.sort_by(
      fn o ->
        o.order_items
        |> Enum.filter(&(&1.status == "sent" and drink_item?(&1) and not is_nil(&1.sent_at)))
        |> Enum.map(& &1.sent_at)
        |> Enum.min(DateTime, fn -> DateTime.utc_now() end)
      end,
      DateTime
    )
  end

  # An order is pending in barra if ANY drink item still has status "sent".
  defp pending_orders(orders) do
    Enum.filter(orders, fn o ->
      Enum.any?(o.order_items, fn oi -> oi.status == "sent" and drink_item?(oi) end)
    end)
  end

  # Orders where all drink items are ready — waiting to be served.
  defp ready_drink_orders(orders) do
    Enum.filter(orders, fn o ->
      drinks = Enum.filter(o.order_items, &drink_item?/1)
      drinks != [] and Enum.all?(drinks, fn oi -> oi.status == "ready" end)
    end)
  end

  # Minutes elapsed since the oldest sent drink item in this order.
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

  # Returns the set of IDs of drink items currently in "sent" state.
  defp sent_drink_ids(orders) do
    orders
    |> Enum.flat_map(& &1.order_items)
    |> Enum.filter(&(&1.status == "sent" and drink_item?(&1)))
    |> MapSet.new(& &1.id)
  end

  defp item_label(%{menu_item: %{name: name}}) when not is_nil(name), do: name
  defp item_label(%{product: %{name: name}}) when not is_nil(name), do: "Extra: #{name}"
  defp item_label(_), do: "Artículo"

  # Groups pending drink items by menu_item_id for the given barra_type.
  # Returns a list of group maps sorted by total quantity descending.
  defp group_drink_items(orders, type) do
    orders
    |> Enum.flat_map(fn order ->
      order.order_items
      |> Enum.filter(fn oi ->
        oi.status == "sent" and drink_item?(oi) and
          barra_type(oi) == type and not is_nil(oi.menu_item_id)
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
    |> Enum.sort_by(& &1.total_qty, :desc)
  end

  defp group_elapsed_minutes(nil, _now), do: nil
  defp group_elapsed_minutes(sent_at, now), do: DateTime.diff(now, sent_at, :minute)

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_interval)
end
