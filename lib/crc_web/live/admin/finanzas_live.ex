defmodule CRCWeb.Admin.FinanzasLive do
  @moduledoc "Financial P&L dashboard: revenue, COGS, gross profit, waste cost, net profit."

  use CRCWeb, :live_view

  alias CRC.Orders

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
    end

    socket =
      socket
      |> assign(:page_title, "Finanzas")
      |> assign(:period, :all)
      |> assign(:date_from, "")
      |> assign(:date_to, "")
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_info({:order_updated, _}, socket) do
    {:noreply, load_data(socket)}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("set_period", %{"period" => period}, socket) do
    socket =
      socket
      |> assign(:period, String.to_existing_atom(period))
      |> assign(:date_from, "")
      |> assign(:date_to, "")
      |> load_data()

    {:noreply, socket}
  end

  def handle_event("set_date_range", %{"date_from" => from, "date_to" => to}, socket) do
    with {:ok, d_from} <- Date.from_iso8601(from),
         {:ok, d_to} <- Date.from_iso8601(to),
         true <- Date.compare(d_from, d_to) != :gt do
      socket =
        socket
        |> assign(:period, {:range, d_from, d_to})
        |> assign(:date_from, from)
        |> assign(:date_to, to)
        |> load_data()

      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 pb-10">
      <div class="max-w-5xl mx-auto px-4 py-8 space-y-8">

        <%!-- Header --%>
        <div>
          <h1 class="text-2xl font-bold text-base-content">Finanzas</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            Ingresos, costos, ganancias y desperdicio
          </p>
        </div>

        <%!-- Period filter --%>
        <div class="flex flex-wrap items-end gap-4">
          <div class="flex gap-2 flex-wrap">
            <%= for {label, value} <- [{"Hoy", "today"}, {"Esta semana", "week"}, {"Este mes", "month"}, {"Total", "all"}] do %>
              <button
                class={["btn btn-sm", if(is_atom(@period) and Atom.to_string(@period) == value, do: "btn-primary", else: "btn-ghost border border-base-300")]}
                phx-click="set_period"
                phx-value-period={value}
              >
                {label}
              </button>
            <% end %>
          </div>

          <form phx-change="set_date_range" class="flex flex-col gap-1">
            <span class="text-xs text-base-content/50">Rango personalizado</span>
            <div class="flex gap-2 items-center">
              <input type="date" name="date_from" value={@date_from} class="input input-sm input-bordered w-40" />
              <span class="text-base-content/40 text-xs">—</span>
              <input type="date" name="date_to" value={@date_to} class="input input-sm input-bordered w-40" />
            </div>
          </form>
        </div>

        <%= if is_tuple(@period) do %>
          <div class="alert alert-info py-2">
            <.icon name="hero-calendar" class="size-4" />
            <span class="text-sm">
              Rango: {elem(@period, 1) |> Date.to_iso8601()} — {elem(@period, 2) |> Date.to_iso8601()}
            </span>
          </div>
        <% end %>

        <%!-- Main P&L cards --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">

          <%!-- Revenue --%>
          <.fin_card
            label="Ingresos"
            sublabel="Ventas cobradas"
            value={"$#{fmt(@summary.revenue)}"}
            icon="hero-banknotes"
            color="text-base-content"
            bg="bg-base-100"
          />

          <%!-- COGS --%>
          <.fin_card
            label="Costo de ventas"
            sublabel="Ingredientes de lo vendido"
            value={"$#{fmt(@summary.cogs)}"}
            icon="hero-cube"
            color="text-warning"
            bg="bg-base-100"
          />

          <%!-- Gross profit --%>
          <.fin_card
            label="Ganancia bruta"
            sublabel={"Margen #{fmt_pct(@summary.margin_pct)}%"}
            value={"$#{fmt(@summary.gross_profit)}"}
            icon="hero-arrow-trending-up"
            color={if Decimal.compare(@summary.gross_profit, 0) == :lt, do: "text-error", else: "text-success"}
            bg="bg-base-100"
          />

        </div>

        <%!-- Waste & Net profit --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">

          <%!-- Waste cost --%>
          <div class="bg-base-100 rounded-2xl border border-error/30 shadow-sm p-5 space-y-2">
            <div class="flex items-center gap-2">
              <div class="size-9 rounded-xl bg-error/10 flex items-center justify-center">
                <.icon name="hero-trash" class="size-5 text-error" />
              </div>
              <div>
                <p class="text-xs text-base-content/50 uppercase tracking-wide font-medium">Desperdicio</p>
                <p class="text-xs text-base-content/40">Costo de ítems cancelados</p>
              </div>
            </div>
            <p class="text-3xl font-bold text-error">${fmt(@summary.waste_cost)}</p>
            <%= if @waste_items != [] do %>
              <p class="text-xs text-base-content/40 pt-1">
                {length(@waste_items)} {if length(@waste_items) == 1, do: "platillo desperdiciado", else: "platillos desperdiciados"}
              </p>
            <% end %>
          </div>

          <%!-- Net profit --%>
          <div class={["bg-base-100 rounded-2xl border shadow-sm p-5 space-y-2",
            if(Decimal.compare(@summary.net_profit, 0) == :lt, do: "border-error/40", else: "border-success/30")]}>
            <div class="flex items-center gap-2">
              <div class={["size-9 rounded-xl flex items-center justify-center",
                if(Decimal.compare(@summary.net_profit, 0) == :lt, do: "bg-error/10", else: "bg-success/10")]}>
                <.icon name="hero-scale" class={if(Decimal.compare(@summary.net_profit, 0) == :lt, do: "size-5 text-error", else: "size-5 text-success")} />
              </div>
              <div>
                <p class="text-xs text-base-content/50 uppercase tracking-wide font-medium">Ganancia neta</p>
                <p class="text-xs text-base-content/40">Ganancia bruta − desperdicio</p>
              </div>
            </div>
            <p class={["text-3xl font-bold",
              if(Decimal.compare(@summary.net_profit, 0) == :lt, do: "text-error", else: "text-success")]}>
              ${fmt(@summary.net_profit)}
            </p>
          </div>

        </div>

        <%!-- Note about COGS coverage --%>
        <div class="alert bg-base-100 border-base-300 py-2.5">
          <.icon name="hero-information-circle" class="size-4 text-base-content/40 shrink-0" />
          <p class="text-xs text-base-content/50">
            El costo de ventas solo incluye platillos con receta registrada en el sistema.
            Platillos sin ingredientes asignados no suman al costo.
          </p>
        </div>

        <%!-- Wasted items table --%>
        <%= if @waste_items != [] do %>
          <div class="space-y-4">
            <h2 class="text-base font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-trash" class="size-4 text-error" />
              Ítems desperdiciados
            </h2>

            <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
              <table class="table table-sm w-full">
                <thead>
                  <tr class="border-b border-base-300 text-xs text-base-content/50 uppercase tracking-wide">
                    <th class="py-3 px-4 text-left font-medium">Platillo</th>
                    <th class="py-3 px-4 text-center font-medium">Cantidad</th>
                    <th class="py-3 px-4 text-right font-medium">Costo perdido</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for {item, i} <- Enum.with_index(@waste_items) do %>
                    <tr class={["border-b border-base-200 last:border-0", if(rem(i, 2) == 0, do: "", else: "bg-base-50")]}>
                      <td class="py-3 px-4 text-sm font-medium text-base-content">{item.name}</td>
                      <td class="py-3 px-4 text-sm text-center text-base-content/70">{item.qty}</td>
                      <td class="py-3 px-4 text-sm text-right font-semibold text-error">
                        ${fmt(item.cost)}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
                <tfoot>
                  <tr class="border-t border-base-300">
                    <td class="py-3 px-4 text-sm font-bold text-base-content" colspan="2">Total desperdicio</td>
                    <td class="py-3 px-4 text-sm font-bold text-right text-error">
                      ${fmt(@summary.waste_cost)}
                    </td>
                  </tr>
                </tfoot>
              </table>
            </div>
          </div>
        <% else %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-10 text-center">
            <.icon name="hero-check-circle" class="size-10 text-success/40 mx-auto mb-2" />
            <p class="text-sm text-base-content/50">Sin desperdicios registrados en este período.</p>
          </div>
        <% end %>

      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Sub-components
  # ---------------------------------------------------------------------------

  attr :label, :string, required: true
  attr :sublabel, :string, default: nil
  attr :value, :string, required: true
  attr :icon, :string, required: true
  attr :color, :string, default: "text-base-content"
  attr :bg, :string, default: "bg-base-100"

  defp fin_card(assigns) do
    ~H"""
    <div class={[@bg, "rounded-2xl border border-base-300 shadow-sm p-5 space-y-3"]}>
      <div class="flex items-center gap-2">
        <div class="size-9 rounded-xl bg-base-200 flex items-center justify-center">
          <.icon name={@icon} class={"size-5 #{@color}"} />
        </div>
        <div>
          <p class="text-xs text-base-content/50 uppercase tracking-wide font-medium">{@label}</p>
          <p :if={@sublabel} class="text-xs text-base-content/40">{@sublabel}</p>
        </div>
      </div>
      <p class={["text-3xl font-bold", @color]}>{@value}</p>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp load_data(socket) do
    period = socket.assigns.period

    socket
    |> assign(:summary, Orders.financial_summary(period))
    |> assign(:waste_items, Orders.top_wasted_items(period))
  end

  defp fmt(%Decimal{} = d), do: d |> Decimal.round(0) |> Decimal.to_string()
  defp fmt(nil), do: "0"
  defp fmt(v), do: "#{v}"

  defp fmt_pct(%Decimal{} = d), do: Decimal.to_string(d)
  defp fmt_pct(_), do: "0"
end
