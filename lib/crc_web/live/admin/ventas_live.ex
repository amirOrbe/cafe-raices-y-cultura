defmodule CRCWeb.Admin.VentasLive do
  @moduledoc "Sales dashboard for the administration panel."

  use CRCWeb, :live_view

  alias CRC.Orders

  @periods [
    {"Hoy", :today},
    {"Esta semana", :week},
    {"Este mes", :month},
    {"Total", :all}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
    end

    socket =
      socket
      |> assign(:page_title, "Ventas · Admin")
      |> assign(:period, :all)
      |> assign(:periods, @periods)
      |> assign(:date_from, "")
      |> assign(:date_to, "")
      |> load_sales_data(:all)

    {:ok, socket}
  end

  @impl true
  def handle_info({:order_updated, _id}, socket) do
    period = socket.assigns[:period_filter] || socket.assigns.period
    {:noreply, load_sales_data(socket, period)}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("set_period", %{"period" => period_str}, socket) do
    period = String.to_existing_atom(period_str)

    {:noreply,
     socket
     |> assign(:period, period)
     |> assign(:date_from, "")
     |> assign(:date_to, "")
     |> load_sales_data(period)}
  end

  def handle_event("set_date_range", %{"date_from" => from, "date_to" => to}, socket) do
    filter =
      with {:ok, d_from} <- Date.from_iso8601(from),
           {:ok, d_to} <- Date.from_iso8601(to),
           true <- Date.compare(d_from, d_to) != :gt do
        {:range, d_from, d_to}
      else
        _ -> nil
      end

    if filter do
      {:noreply,
       socket
       |> assign(:period, nil)
       |> assign(:date_from, from)
       |> assign(:date_to, to)
       |> load_sales_data(filter)}
    else
      {:noreply, socket |> assign(:date_from, from) |> assign(:date_to, to)}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">

      <%!-- Header + filters --%>
      <div class="flex flex-col gap-4">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Ventas</h1>
            <p class="text-base-content/60 mt-1 text-sm">Resumen de comandas cerradas</p>
          </div>

          <%!-- Period tabs --%>
          <div class="flex gap-1 bg-base-200 rounded-xl p-1 self-start sm:self-auto">
            <%= for {label, value} <- @periods do %>
              <button
                class={[
                  "px-3 py-1.5 rounded-lg text-sm font-medium transition-colors",
                  if(@period == value,
                    do: "bg-base-100 text-base-content shadow-sm",
                    else: "text-base-content/60 hover:text-base-content")
                ]}
                phx-click="set_period"
                phx-value-period={value}
              >
                {label}
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Custom date range --%>
        <div class="flex flex-col gap-2">
          <div class="flex items-center gap-1.5 text-xs text-base-content/50 font-medium uppercase tracking-wide">
            <.icon name="hero-calendar" class="size-4" />
            Rango personalizado
          </div>
          <form phx-change="set_date_range" class="flex flex-wrap items-end gap-3">
            <div class="flex flex-col gap-1">
              <label class="text-xs text-base-content/50">Desde</label>
              <input
                type="date"
                name="date_from"
                value={@date_from}
                max={Date.utc_today() |> Date.to_iso8601()}
                class={["input input-bordered input-sm w-40",
                  if(@date_from != "", do: "input-primary border-primary", else: "")]}
              />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-xs text-base-content/50">Hasta</label>
              <input
                type="date"
                name="date_to"
                value={@date_to}
                max={Date.utc_today() |> Date.to_iso8601()}
                class={["input input-bordered input-sm w-40",
                  if(@date_to != "", do: "input-primary border-primary", else: "")]}
              />
            </div>
            <%= if @date_from != "" or @date_to != "" do %>
              <button
                class="btn btn-xs btn-ghost text-base-content/50 self-end"
                phx-click="set_period"
                phx-value-period="today"
                title="Limpiar rango"
              >
                <.icon name="hero-x-mark" class="size-3.5" />
                Limpiar
              </button>
            <% end %>
          </form>
          <%= if @period == nil and @date_from != "" and @date_to != "" do %>
            <span class="badge badge-primary badge-sm self-start">
              Rango personalizado activo
            </span>
          <% end %>
        </div>
      </div>

      <%!-- Summary cards --%>
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <.stat_card
          label="Total ingresos"
          value={"$#{format_price(@summary.total_revenue)}"}
          icon="hero-banknotes"
          color="text-success"
          bg="bg-success/10"
        />
        <.stat_card
          label="Comandas cerradas"
          value={"#{@summary.order_count}"}
          icon="hero-clipboard-document-check"
          color="text-primary"
          bg="bg-primary/10"
        />
        <.stat_card
          label="Ticket promedio"
          value={"$#{format_price(@summary.avg_ticket)}"}
          icon="hero-calculator"
          color="text-accent"
          bg="bg-accent/10"
        />
      </div>

      <%!-- Payment breakdown + top items --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">

        <%!-- Payment method breakdown --%>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-6 space-y-4">
          <h2 class="font-semibold text-base-content">Por método de pago</h2>
          <%= if map_size(@summary.by_method) == 0 do %>
            <p class="text-base-content/40 text-sm py-6 text-center">
              Sin datos para este período.
            </p>
          <% else %>
            <% total_rev = @summary.total_revenue %>
            <%= for {method, amount} <- Enum.sort(@summary.by_method) do %>
              <% pct =
                if Decimal.gt?(total_rev, Decimal.new(0)) do
                  Decimal.mult(Decimal.div(amount, total_rev), Decimal.new(100))
                  |> Decimal.round(1)
                  |> Decimal.to_string()
                else
                  "0"
                end %>
              <div class="space-y-1.5">
                <div class="flex justify-between items-center text-sm">
                  <div class="flex items-center gap-2">
                    <.payment_icon method={method} />
                    <span class="capitalize font-medium text-base-content">{method}</span>
                  </div>
                  <div class="text-right">
                    <span class="font-semibold text-base-content">${format_price(amount)}</span>
                    <span class="text-base-content/40 text-xs ml-1">({pct}%)</span>
                  </div>
                </div>
                <div class="h-2 bg-base-200 rounded-full overflow-hidden">
                  <div
                    class="h-full bg-primary rounded-full transition-all duration-500"
                    style={"width: #{pct}%"}
                  />
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

        <%!-- Top 10 platillos --%>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
          <div class="px-6 py-4 border-b border-base-300">
            <h2 class="font-semibold text-base-content">Top platillos más vendidos</h2>
          </div>
          <%= if @top_items == [] do %>
            <p class="text-base-content/40 text-sm py-8 text-center">
              Sin datos para este período.
            </p>
          <% else %>
            <div class="divide-y divide-base-200">
              <%= for {{name, qty}, idx} <- Enum.with_index(@top_items, 1) do %>
                <div class="flex items-center gap-4 px-6 py-3">
                  <span class={[
                    "text-sm font-bold w-5 text-center shrink-0",
                    cond do
                      idx == 1 -> "text-accent"
                      idx <= 3 -> "text-secondary"
                      true -> "text-base-content/25"
                    end
                  ]}>
                    {idx}
                  </span>
                  <span class="flex-1 text-sm text-base-content truncate">{name}</span>
                  <span class="text-sm font-bold text-base-content">{qty}</span>
                  <span class="text-xs text-base-content/40">uds.</span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

      </div>

      <%!-- Timing stats diagram --%>
      <%= if map_size(@timing_stats) > 0 do %>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-6 space-y-5">
          <div class="flex items-center gap-2">
            <.icon name="hero-clock" class="size-5 text-primary" />
            <h2 class="font-semibold text-base-content">Tiempos de preparación (promedio del período)</h2>
          </div>

          <%= for {kind, stats} <- Enum.sort(@timing_stats) do %>
            <div class="space-y-3">
              <%!-- Station header --%>
              <div class="flex items-center gap-2 text-sm font-semibold text-base-content/70 uppercase tracking-wide">
                <%= if kind == "drink" do %>
                  <.icon name="hero-beaker" class="size-4 text-info" />
                  <span>Barra</span>
                <% else %>
                  <.icon name="hero-fire" class="size-4 text-warning" />
                  <span>Cocina</span>
                <% end %>
              </div>

              <div class="space-y-2 pl-6">
                <.timing_row label="Espera en comanda" stat={stats.wait} />
                <.timing_row label="Preparación" stat={stats.prep} />
                <.timing_row label="Tiempo en mesa" stat={stats.service} />
              </div>
            </div>
          <% end %>

          <p class="text-xs text-base-content/40">
            Basado en comandas cerradas. La barra roja indica promedio mayor a 15 min.
          </p>
        </div>
      <% end %>

      <%!-- Closed orders table --%>
      <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between">
          <h2 class="font-semibold text-base-content">Comandas cerradas</h2>
          <span class="badge badge-ghost badge-sm">{length(@orders)}</span>
        </div>
        <%= if @orders == [] do %>
          <p class="text-base-content/40 text-sm py-10 text-center">
            No hay comandas cerradas en este período.
          </p>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-sm w-full">
              <thead>
                <tr class="text-base-content/50 text-xs uppercase tracking-wide">
                  <th>Cliente</th>
                  <th class="text-right">Total</th>
                  <th>Método</th>
                  <th>Fecha</th>
                </tr>
              </thead>
              <tbody>
                <%= for order <- @orders do %>
                  <tr class="hover:bg-base-50 border-b border-base-200">
                    <td class="text-sm font-medium text-base-content py-3">
                      {order.customer_name}
                    </td>
                    <td class="text-sm font-bold text-primary text-right">
                      ${ format_price(order.total || Decimal.new(0)) }
                    </td>
                    <td>
                      <.payment_badge method={order.payment_method} />
                    </td>
                    <td class="text-xs text-base-content/50 whitespace-nowrap">
                      { format_datetime(order.inserted_at) }
                    </td>
                  </tr>
                <% end %>
              </tbody>
              <%!-- Totals footer --%>
              <tfoot>
                <tr class="border-t-2 border-base-300 bg-base-200/50">
                  <td class="text-sm font-semibold text-base-content py-3 px-4">
                    {length(@orders)} comandas
                  </td>
                  <td class="text-sm font-bold text-primary text-right px-4">
                    ${ format_price(@summary.total_revenue) }
                  </td>
                  <td colspan="2" class="text-xs text-base-content/40 px-4">
                    Ticket prom. ${ format_price(@summary.avg_ticket) }
                  </td>
                </tr>
              </tfoot>
            </table>
          </div>
        <% end %>
      </div>

    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private components
  # ---------------------------------------------------------------------------

  attr :label, :string, required: true
  attr :stat, :any, required: true  # nil | %{avg:, min:, max:}

  defp timing_row(%{stat: nil} = assigns) do
    ~H"""
    <div class="flex items-center gap-3 text-sm">
      <span class="w-36 text-base-content/50 shrink-0">{@label}</span>
      <span class="text-base-content/30 text-xs">Sin datos</span>
    </div>
    """
  end

  defp timing_row(assigns) do
    # Cap bar at 30 min; >15 min shows as error color
    avg_min = assigns.stat.avg / 60
    bar_pct = min(100, round(avg_min / 30 * 100))
    overdue = avg_min >= 15
    assigns = assign(assigns, bar_pct: bar_pct, avg_min: avg_min, overdue: overdue)

    ~H"""
    <div class="flex items-center gap-3 text-sm">
      <span class="w-36 text-base-content/60 shrink-0 text-xs">{@label}</span>
      <div class="flex-1 h-2 bg-base-200 rounded-full overflow-hidden">
        <div
          class={["h-full rounded-full transition-all duration-500",
            if(@overdue, do: "bg-error", else: "bg-primary")]}
          style={"width: #{@bar_pct}%"}
        />
      </div>
      <div class="text-right shrink-0 w-28">
        <span class={["font-semibold text-xs", if(@overdue, do: "text-error", else: "text-base-content")]}>
          {format_duration(@stat.avg)}
          <%= if @overdue do %>
            <.icon name="hero-exclamation-triangle" class="size-3 inline" />
          <% end %>
        </span>
        <span class="text-base-content/40 text-xs ml-1">
          ({format_duration(@stat.min)} – {format_duration(@stat.max)})
        </span>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :icon, :string, required: true
  attr :color, :string, required: true
  attr :bg, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5 flex items-center gap-4">
      <div class={["size-12 rounded-xl flex items-center justify-center shrink-0", @bg]}>
        <.icon name={@icon} class={"size-6 #{@color}"} />
      </div>
      <div>
        <p class="text-2xl font-bold text-base-content">{@value}</p>
        <p class="text-xs text-base-content/50 mt-0.5">{@label}</p>
      </div>
    </div>
    """
  end

  attr :method, :string, default: nil

  defp payment_icon(%{method: "efectivo"} = assigns) do
    ~H"<.icon name='hero-banknotes' class='size-4 text-success' />"
  end

  defp payment_icon(%{method: "tarjeta"} = assigns) do
    ~H"<.icon name='hero-credit-card' class='size-4 text-info' />"
  end

  defp payment_icon(%{method: "transferencia"} = assigns) do
    ~H"<.icon name='hero-device-phone-mobile' class='size-4 text-warning' />"
  end

  defp payment_icon(assigns) do
    ~H"<.icon name='hero-question-mark-circle' class='size-4 text-base-content/30' />"
  end

  attr :method, :string, default: nil

  defp payment_badge(%{method: "efectivo"} = assigns) do
    ~H"<span class='badge badge-sm badge-success'>Efectivo</span>"
  end

  defp payment_badge(%{method: "tarjeta"} = assigns) do
    ~H"<span class='badge badge-sm badge-info'>Tarjeta</span>"
  end

  defp payment_badge(%{method: "transferencia"} = assigns) do
    ~H"<span class='badge badge-sm badge-warning'>Transferencia</span>"
  end

  defp payment_badge(assigns) do
    ~H"<span class='badge badge-sm badge-ghost'>—</span>"
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_sales_data(socket, period) do
    socket
    |> assign(:period_filter, period)
    |> assign(:summary, Orders.sales_summary(period))
    |> assign(:top_items, Orders.top_selling_items(period, 10))
    |> assign(:orders, Orders.list_closed_orders(period))
    |> assign(:timing_stats, Orders.timing_stats(period))
  end

  defp format_price(%Decimal{} = price) do
    price |> Decimal.round(0) |> Decimal.to_string()
  end

  defp format_price(nil), do: "0"
  defp format_price(other), do: "#{other}"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%d/%m/%Y %H:%M")
  end

  defp format_datetime(_), do: "—"

  defp format_duration(seconds) when is_integer(seconds) and seconds < 60, do: "< 1 min"

  defp format_duration(seconds) when is_integer(seconds) do
    mins = div(seconds, 60)
    secs = rem(seconds, 60)
    if secs == 0, do: "#{mins} min", else: "#{mins} min #{secs} s"
  end

  defp format_duration(_), do: "—"
end
