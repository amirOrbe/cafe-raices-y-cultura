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
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Finanzas</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              Ingresos, costos, ganancias y desperdicio
            </p>
          </div>
          <a
            href={report_href("finanzas", @period)}
            class="btn btn-sm btn-outline gap-2 w-full sm:w-auto"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Descargar reporte
          </a>
        </div>

        <%!-- Contextual help --%>
        <details class="group rounded-xl border border-info/30 bg-info/5 text-sm">
          <summary class="flex cursor-pointer items-center gap-2 px-4 py-3 font-medium text-info list-none select-none">
            <.icon name="hero-information-circle" class="size-4 shrink-0" />
            <span class="flex-1">¿Cómo se calculan estas métricas?</span>
            <.icon
              name="hero-chevron-down"
              class="size-4 shrink-0 transition-transform group-open:rotate-180"
            />
          </summary>
          <div class="px-4 pb-4 text-base-content/70 space-y-1.5 text-xs leading-relaxed">
            <p>
              <strong>Ingresos</strong>
              — suma del total de todas las órdenes cerradas (cobradas) en el período.
            </p>
            <p>
              <strong>Costo de ventas (COGS)</strong>
              — suma del costo de ingredientes de cada platillo vendido, calculado con el costo neto de los insumos × cantidad de la receta. Solo incluye platillos que tienen receta registrada; los que no tienen receta no suman al costo.
            </p>
            <p>
              <strong>Utilidad bruta</strong>
              — Ingresos − Costo de ventas. Lo que queda antes de descontar la merma.
            </p>
            <p>
              <strong>Margen bruto</strong>
              — Utilidad bruta / Ingresos × 100. En cafeterías un margen saludable está entre 55% y 75%.
            </p>
            <p>
              <strong>Merma</strong>
              — costo de los platillos cancelados <em>después</em>
              de haber sido preparados (cancelados como desperdicio). El food ya se hizo pero no se cobró.
            </p>
            <p>
              <strong>Utilidad neta estimada</strong>
              — Utilidad bruta − Merma. No incluye gastos fijos (renta, nómina, servicios).
            </p>
          </div>
        </details>

        <%!-- Period filter --%>
        <.period_filter period={@period} date_from={@date_from} date_to={@date_to} />

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
          <.stat_card
            label="Ingresos"
            sublabel="Ventas cobradas"
            value={"$#{fmt(@summary.revenue)}"}
            icon="hero-banknotes"
            variant={:primary}
          />

          <.stat_card
            label="Costo de ventas"
            sublabel="Ingredientes de lo vendido"
            value={"$#{fmt(@summary.cogs)}"}
            icon="hero-cube"
            variant={:warning}
          />

          <.stat_card
            label="Ganancia bruta"
            sublabel={"Margen #{fmt_pct(@summary.margin_pct)}%"}
            value={"$#{fmt(@summary.gross_profit)}"}
            icon="hero-arrow-trending-up"
            variant={if Decimal.compare(@summary.gross_profit, 0) == :lt, do: :error, else: :success}
          />
        </div>

        <%!-- Waste & Net profit --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.stat_card
            label="Desperdicio"
            sublabel={
              if @waste_items != [] do
                "#{length(@waste_items)} #{if length(@waste_items) == 1, do: "platillo desperdiciado", else: "platillos desperdiciados"}"
              else
                "Costo de ítems cancelados"
              end
            }
            value={"$#{fmt(@summary.waste_cost)}"}
            icon="hero-trash"
            variant={:error}
          />

          <.stat_card
            label="Ganancia neta"
            sublabel="Ganancia bruta − desperdicio"
            value={"$#{fmt(@summary.net_profit)}"}
            icon="hero-scale"
            variant={if Decimal.compare(@summary.net_profit, 0) == :lt, do: :error, else: :success}
          />
        </div>

        <%!-- Note about COGS coverage --%>
        <div class="alert bg-base-100 border-base-300 py-2.5">
          <.icon name="hero-information-circle" class="size-4 text-base-content/40 shrink-0" />
          <p class="text-xs text-base-content/50">
            El costo de ventas solo incluye platillos con receta registrada en el sistema.
            Platillos sin ingredientes asignados no suman al costo.
          </p>
        </div>

        <%!-- Wasted items --%>
        <%= if @waste_items != [] do %>
          <div class="space-y-4">
            <h2 class="text-base font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-trash" class="size-4 text-error" /> Ítems desperdiciados
            </h2>

            <%!-- Mobile: cards --%>
            <div class="md:hidden space-y-2">
              <.panel :for={item <- @waste_items} class="p-4 flex items-center justify-between gap-3">
                <div class="min-w-0">
                  <p class="text-sm font-medium text-base-content truncate">{item.name}</p>
                  <p class="text-xs text-base-content/50">Cantidad: {item.qty}</p>
                </div>
                <p class="text-sm font-semibold text-error shrink-0">${fmt(item.cost)}</p>
              </.panel>
              <.panel class="p-4 flex items-center justify-between">
                <p class="text-sm font-bold text-base-content">Total desperdicio</p>
                <p class="text-sm font-bold text-error">${fmt(@summary.waste_cost)}</p>
              </.panel>
            </div>

            <%!-- Desktop: table --%>
            <.panel class="hidden md:block overflow-hidden">
              <div class="overflow-x-auto">
                <table class="table table-sm w-full table-fixed">
                  <.admin_table_head>
                    <:col class="py-3 px-4 text-left w-[50%]">Platillo</:col>
                    <:col class="py-3 px-4 text-center w-[25%]">Cantidad</:col>
                    <:col class="py-3 px-4 text-right w-[25%]">Costo perdido</:col>
                  </.admin_table_head>
                  <tbody>
                    <%= for {item, i} <- Enum.with_index(@waste_items) do %>
                      <tr class={[
                        "border-b border-base-200 last:border-0",
                        if(rem(i, 2) == 0, do: "", else: "bg-base-50")
                      ]}>
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
                      <td class="py-3 px-4 text-sm font-bold text-base-content" colspan="2">
                        Total desperdicio
                      </td>
                      <td class="py-3 px-4 text-sm font-bold text-right text-error">
                        ${fmt(@summary.waste_cost)}
                      </td>
                    </tr>
                  </tfoot>
                </table>
              </div>
            </.panel>
          </div>
        <% else %>
          <.panel class="py-10 text-center">
            <.icon name="hero-check-circle" class="size-10 text-success/40 mx-auto mb-2" />
            <p class="text-sm text-base-content/50">Sin desperdicios registrados en este período.</p>
          </.panel>
        <% end %>
      </div>
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

  defp fmt(v), do: CRC.Utils.format_money(v)

  defp fmt_pct(%Decimal{} = d), do: Decimal.to_string(d)
  defp fmt_pct(_), do: "0"

  # Builds the query string for /admin/reportes/finanzas.csv so the download
  # always matches whatever period is currently on screen.
  defp report_href(name, {:range, d_from, d_to}) do
    "/admin/reportes/#{name}.csv?" <>
      URI.encode_query(%{
        "period" => "range",
        "date_from" => Date.to_iso8601(d_from),
        "date_to" => Date.to_iso8601(d_to)
      })
  end

  defp report_href(name, period) when is_atom(period) do
    "/admin/reportes/#{name}.csv?" <> URI.encode_query(%{"period" => Atom.to_string(period)})
  end
end
