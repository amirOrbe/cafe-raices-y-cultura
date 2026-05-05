defmodule CRCWeb.Admin.DashboardLive do
  @moduledoc "Main administration dashboard — operational real-time view."

  use CRCWeb, :live_view

  alias CRC.Accounts
  alias CRC.Inventory
  alias CRC.Orders

  @tick_interval 60_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
      Phoenix.PubSub.subscribe(CRC.PubSub, "admin:users")
      Phoenix.PubSub.subscribe(CRC.PubSub, "admin:products")
      schedule_tick()
    end

    socket =
      socket
      |> assign(:page_title, "Dashboard · Admin")
      |> assign(:now, DateTime.utc_now())
      |> load_all()

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub + tick
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:order_updated, _order_id}, socket) do
    {:noreply, load_all(socket)}
  end

  def handle_info({event, _payload}, socket)
      when event in [:user_changed, :product_changed] do
    {:noreply, load_all(socket)}
  end

  def handle_info(:tick, socket) do
    schedule_tick()
    {:noreply, socket |> assign(:now, DateTime.utc_now()) |> load_all()}
  end

  # ---------------------------------------------------------------------------
  # Data loading
  # ---------------------------------------------------------------------------

  defp load_all(socket) do
    users = Accounts.list_users()
    low_stock = Inventory.list_low_stock_products()
    sales = Orders.sales_summary(:today)
    open_orders = Orders.list_open_orders()
    top_items = Orders.top_selling_items(:today, 5)

    pending_cocina = count_sent_by_dest(open_orders, "cocina")
    pending_barra = count_sent_by_dest(open_orders, "barra")

    socket
    |> assign(:sales, sales)
    |> assign(:open_orders, open_orders)
    |> assign(:pending_cocina, pending_cocina)
    |> assign(:pending_barra, pending_barra)
    |> assign(:top_items, top_items)
    |> assign(:low_stock, low_stock)
    |> assign(:user_stats, build_user_stats(users))
  end

  defp count_sent_by_dest(orders, dest) do
    orders
    |> Enum.flat_map(& &1.order_items)
    |> Enum.count(fn oi ->
      oi.status == "sent" and
        not is_nil(oi.menu_item) and
        oi.menu_item.destination == dest
    end)
  end

  defp build_user_stats(users) do
    %{
      total: length(users),
      active: Enum.count(users, & &1.is_active),
      employees: Enum.count(users, &(&1.role == "empleado")),
      admins: Enum.count(users, &(&1.role == "admin"))
    }
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- ── Header ─────────────────────────────────────────────────────────── --%>
      <div class="flex items-center justify-between flex-wrap gap-2">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Dashboard</h1>
          <p class="text-base-content/50 text-sm mt-0.5">
            Bienvenido, {@current_user.name} · {format_date(@now)}
          </p>
        </div>
        <div class="text-xs text-base-content/30 font-mono">
          Actualizado {format_time(@now)}
        </div>
      </div>

      <%!-- ── Métricas de hoy ────────────────────────────────────────────────── --%>
      <div>
        <h2 class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-3">
          Hoy
        </h2>
        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
          <.stat_card
            label="Ventas del día"
            value={"$#{format_price(@sales.total_revenue)}"}
            icon="hero-banknotes"
            variant={:success}
          />
          <.stat_card
            label="Cuentas cerradas"
            value={@sales.order_count}
            icon="hero-check-circle"
            variant={:primary}
          />
          <.stat_card
            label="Ticket promedio"
            value={"$#{format_price(@sales.avg_ticket)}"}
            icon="hero-receipt-percent"
            variant={:accent}
          />
          <.stat_card
            label="Órdenes activas"
            value={length(@open_orders)}
            icon="hero-clock"
            variant={:info}
          />
          <.stat_card
            label="Pendiente cocina"
            value={@pending_cocina}
            icon="hero-fire"
            variant={if @pending_cocina > 0, do: :warning, else: :success}
          />
          <.stat_card
            label="Pendiente barra"
            value={@pending_barra}
            icon="hero-beaker"
            variant={if @pending_barra > 0, do: :warning, else: :success}
          />
        </div>
      </div>

      <%!-- ── Pago por método (hoy) ─────────────────────────────────────────── --%>
      <%= if map_size(@sales.by_method) > 0 do %>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <%= for {method, amount} <- @sales.by_method do %>
            <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm px-4 py-3 flex items-center justify-between">
              <div class="flex items-center gap-2">
                <.icon name={payment_icon(method)} class="size-4 text-base-content/50" />
                <span class="text-sm capitalize text-base-content/70">{method}</span>
              </div>
              <span class="font-bold text-base-content">${format_price(amount)}</span>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- ── Órdenes activas ────────────────────────────────────────────────── --%>
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">

        <%!-- Active orders list (takes 2/3 of the grid) --%>
        <div class="lg:col-span-2 bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
          <div class="px-5 py-4 border-b border-base-300 flex items-center justify-between">
            <h2 class="font-semibold text-base-content">Órdenes activas</h2>
            <%= if @open_orders != [] do %>
              <span class="badge badge-info badge-sm">{length(@open_orders)}</span>
            <% end %>
          </div>

          <%= if @open_orders == [] do %>
            <div class="py-12 text-center text-base-content/40 text-sm">
              <.icon name="hero-check-circle" class="size-10 mx-auto mb-2 text-success" />
              Sin órdenes activas en este momento
            </div>
          <% else %>
            <div class="divide-y divide-base-200">
              <%= for order <- Enum.sort_by(@open_orders, & &1.inserted_at) do %>
                <% mins = elapsed_minutes(order, @now) %>
                <div class="px-5 py-3 flex items-center gap-3 flex-wrap">
                  <%!-- Customer + waiter --%>
                  <div class="flex-1 min-w-0">
                    <p class="font-semibold text-base-content text-sm">{order.customer_name}</p>
                    <p class="text-xs text-base-content/40 mt-0.5">
                      <%= if order.user do %>
                        👤 {order.user.name}
                      <% end %>
                      · {item_summary(order)}
                    </p>
                  </div>

                  <%!-- Elapsed time --%>
                  <%= if mins do %>
                    <span class={[
                      "text-xs font-mono font-semibold tabular-nums",
                      cond do
                        mins >= 30 -> "text-error animate-pulse"
                        mins >= 15 -> "text-warning"
                        true -> "text-base-content/50"
                      end
                    ]}>
                      🕐 {mins}m
                    </span>
                  <% end %>

                  <%!-- Status --%>
                  <.order_status_badge status={order.status} />

                  <%!-- Pending items by station --%>
                  <% sent_cocina = count_sent_items(order, "cocina") %>
                  <% sent_barra = count_sent_items(order, "barra") %>
                  <%= if sent_cocina > 0 do %>
                    <span class="badge badge-warning badge-sm">🍳 {sent_cocina}</span>
                  <% end %>
                  <%= if sent_barra > 0 do %>
                    <span class="badge badge-info badge-sm">🍹 {sent_barra}</span>
                  <% end %>
                  <%= if count_pending_items(order) > 0 do %>
                    <span class="badge badge-ghost badge-sm">⏳ {count_pending_items(order)} pendiente</span>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Top platillos del día --%>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
          <div class="px-5 py-4 border-b border-base-300">
            <h2 class="font-semibold text-base-content">Top platillos hoy</h2>
          </div>
          <%= if @top_items == [] do %>
            <div class="py-8 text-center text-base-content/40 text-sm">
              Sin ventas registradas hoy
            </div>
          <% else %>
            <div class="divide-y divide-base-200">
              <%= for {{name, qty}, idx} <- Enum.with_index(@top_items) do %>
                <div class="flex items-center gap-3 px-5 py-3">
                  <span class={[
                    "size-6 rounded-full flex items-center justify-center text-xs font-bold shrink-0",
                    case idx do
                      0 -> "bg-warning/20 text-warning"
                      1 -> "bg-base-content/10 text-base-content/60"
                      2 -> "bg-accent/20 text-accent"
                      _ -> "bg-base-200 text-base-content/40"
                    end
                  ]}>
                    {idx + 1}
                  </span>
                  <p class="flex-1 text-sm text-base-content truncate">{name}</p>
                  <span class="text-sm font-bold text-primary">{qty}</span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- ── Stock bajo + Usuarios ──────────────────────────────────────────── --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">

        <%!-- Stock bajo --%>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
          <div class="px-5 py-4 border-b border-base-300 flex items-center justify-between">
            <h2 class="font-semibold text-base-content">Stock bajo</h2>
            <%= if @low_stock != [] do %>
              <span class="badge badge-warning badge-sm">{length(@low_stock)}</span>
            <% end %>
          </div>
          <%= if @low_stock == [] do %>
            <div class="py-8 text-center text-base-content/40 text-sm">
              <.icon name="hero-check-circle" class="size-8 mx-auto mb-1 text-success" />
              Todo el stock está bien
            </div>
          <% else %>
            <div class="divide-y divide-base-200">
              <%= for product <- Enum.take(@low_stock, 8) do %>
                <div class="flex items-center justify-between px-5 py-3 gap-3">
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-base-content truncate">{product.name}</p>
                    <p class="text-xs text-base-content/40">
                      Mín: {product.min_stock} {product.unit}
                    </p>
                  </div>
                  <div class="text-right shrink-0">
                    <p class={[
                      "text-sm font-bold",
                      if(Decimal.compare(product.stock_quantity, Decimal.new(0)) == :eq,
                        do: "text-error",
                        else: "text-warning"
                      )
                    ]}>
                      {format_stock(product.stock_quantity)} {product.unit}
                    </p>
                    <%= if Decimal.compare(product.stock_quantity, Decimal.new(0)) == :eq do %>
                      <p class="text-xs text-error font-semibold">Agotado</p>
                    <% end %>
                  </div>
                </div>
              <% end %>
              <%= if length(@low_stock) > 8 do %>
                <div class="px-5 py-3 text-center">
                  <a href="/admin/inventario" class="text-xs text-primary hover:underline">
                    Ver {length(@low_stock) - 8} más →
                  </a>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Usuarios --%>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
          <div class="px-5 py-4 border-b border-base-300 flex items-center justify-between">
            <h2 class="font-semibold text-base-content">Equipo</h2>
            <a href="/admin/usuarios" class="btn btn-xs btn-ghost text-primary">Ver todos</a>
          </div>
          <div class="px-5 py-4 grid grid-cols-2 gap-3">
            <.mini_stat label="Total" value={@user_stats.total} icon="hero-users" color="text-primary" />
            <.mini_stat label="Activos" value={@user_stats.active} icon="hero-check-circle" color="text-success" />
            <.mini_stat label="Empleados" value={@user_stats.employees} icon="hero-briefcase" color="text-secondary" />
            <.mini_stat label="Admins" value={@user_stats.admins} icon="hero-shield-check" color="text-accent" />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private components
  # ---------------------------------------------------------------------------

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :variant, :atom, default: :primary

  defp stat_card(assigns) do
    bg_class =
      case assigns.variant do
        :primary -> "bg-primary/10"
        :secondary -> "bg-secondary/10"
        :accent -> "bg-accent/10"
        :success -> "bg-success/10"
        :error -> "bg-error/10"
        :warning -> "bg-warning/10"
        :info -> "bg-info/10"
      end

    text_class =
      case assigns.variant do
        :primary -> "text-primary"
        :secondary -> "text-secondary"
        :accent -> "text-accent"
        :success -> "text-success"
        :error -> "text-error"
        :warning -> "text-warning"
        :info -> "text-info"
      end

    assigns = assigns |> assign(:bg_class, bg_class) |> assign(:text_class, text_class)

    ~H"""
    <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-3 sm:p-4 flex items-center gap-3">
      <div class={["size-10 rounded-xl flex items-center justify-center shrink-0", @bg_class]}>
        <.icon name={@icon} class={"size-5 #{@text_class}"} />
      </div>
      <div class="min-w-0">
        <p class="text-lg sm:text-xl font-bold text-base-content leading-none truncate">{@value}</p>
        <p class="text-xs text-base-content/50 mt-0.5 leading-tight">{@label}</p>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true
  attr :color, :string, required: true

  defp mini_stat(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <.icon name={@icon} class={"size-4 shrink-0 #{@color}"} />
      <div>
        <p class="text-base font-bold text-base-content leading-none">{@value}</p>
        <p class="text-xs text-base-content/40">{@label}</p>
      </div>
    </div>
    """
  end

  attr :status, :string, required: true

  defp order_status_badge(%{status: "open"} = assigns) do
    ~H'<span class="badge badge-info badge-sm">Abierta</span>'
  end

  defp order_status_badge(%{status: "sent"} = assigns) do
    ~H'<span class="badge badge-warning badge-sm">En preparación</span>'
  end

  defp order_status_badge(%{status: "ready"} = assigns) do
    ~H'<span class="badge badge-success badge-sm">Lista</span>'
  end

  defp order_status_badge(assigns) do
    ~H'<span class="badge badge-ghost badge-sm">{@status}</span>'
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp elapsed_minutes(order, now) do
    DateTime.diff(now, order.inserted_at, :minute)
  end

  defp item_summary(order) do
    total = length(order.order_items)
    "#{total} #{if total == 1, do: "artículo", else: "artículos"}"
  end

  defp count_sent_items(order, dest) do
    Enum.count(order.order_items, fn oi ->
      oi.status == "sent" and not is_nil(oi.menu_item) and
        oi.menu_item.destination == dest
    end)
  end

  defp count_pending_items(order) do
    Enum.count(order.order_items, &(&1.status == "pending"))
  end

  defp format_price(%Decimal{} = d), do: :erlang.float_to_binary(Decimal.to_float(d), decimals: 2)
  defp format_price(nil), do: "0.00"

  defp format_stock(%Decimal{} = d) do
    str = d |> Decimal.round(3) |> Decimal.to_string()
    if String.contains?(str, "."),
      do: str |> String.trim_trailing("0") |> String.trim_trailing("."),
      else: str
  end

  defp format_date(dt), do: Calendar.strftime(dt, "%d/%m/%Y")
  defp format_time(dt), do: Calendar.strftime(dt, "%H:%M")

  defp payment_icon("efectivo"), do: "hero-banknotes"
  defp payment_icon("tarjeta"), do: "hero-credit-card"
  defp payment_icon("transferencia"), do: "hero-device-phone-mobile"
  defp payment_icon(_), do: "hero-question-mark-circle"

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_interval)
end
