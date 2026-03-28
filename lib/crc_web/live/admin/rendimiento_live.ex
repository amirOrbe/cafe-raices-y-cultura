defmodule CRCWeb.Admin.RendimientoLive do
  @moduledoc "Admin view showing per-employee performance metrics and response times."

  use CRCWeb, :live_view

  alias CRC.Orders

  # Thresholds in seconds: >15 min prep is slow for station staff; >60 min total is slow for waiters
  @prep_threshold_secs 15 * 60
  @service_threshold_secs 60 * 60

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
    end

    socket =
      socket
      |> assign(:page_title, "Rendimiento")
      |> assign(:period, :today)
      |> assign(:date_from, "")
      |> assign(:date_to, "")
      |> assign(:prep_threshold_secs, @prep_threshold_secs)
      |> assign(:service_threshold_secs, @service_threshold_secs)
      |> load_stats()

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:order_updated, _}, socket) do
    {:noreply, load_stats(socket)}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("set_period", %{"period" => period}, socket) do
    period_atom = String.to_existing_atom(period)

    socket =
      socket
      |> assign(:period, period_atom)
      |> assign(:date_from, "")
      |> assign(:date_to, "")
      |> load_stats()

    {:noreply, socket}
  end

  def handle_event("set_date_range", %{"date_from" => from, "date_to" => to}, socket) do
    with {:ok, date_from} <- Date.from_iso8601(from),
         {:ok, date_to} <- Date.from_iso8601(to),
         true <- Date.compare(date_from, date_to) != :gt do
      socket =
        socket
        |> assign(:period, {:range, date_from, date_to})
        |> assign(:date_from, from)
        |> assign(:date_to, to)
        |> load_stats()

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
      <div class="max-w-6xl mx-auto px-4 py-8 space-y-8">

        <%!-- Header --%>
        <div>
          <h1 class="text-2xl font-bold text-base-content">Rendimiento del personal</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            Tiempos de preparación y atención por empleado
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

          <%!-- Custom date range --%>
          <form phx-change="set_date_range" class="flex flex-col gap-1">
            <span class="text-xs text-base-content/50">Rango personalizado</span>
            <div class="flex gap-2 items-center">
              <input
                type="date" name="date_from" value={@date_from}
                class="input input-sm input-bordered w-40"
              />
              <span class="text-base-content/40 text-xs">—</span>
              <input
                type="date" name="date_to" value={@date_to}
                class="input input-sm input-bordered w-40"
              />
            </div>
          </form>
        </div>

        <%!-- Active range indicator --%>
        <%= if is_tuple(@period) do %>
          <div class="alert alert-info alert-sm py-2">
            <.icon name="hero-calendar" class="size-4" />
            <span class="text-sm">
              Rango personalizado activo:
              {elem(@period, 1) |> Date.to_iso8601()} — {elem(@period, 2) |> Date.to_iso8601()}
            </span>
          </div>
        <% end %>

        <%!-- No data --%>
        <%= if @station_stats == [] and @waiter_stats == [] do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-20 text-center">
            <.icon name="hero-chart-bar" class="size-12 text-base-content/20 mx-auto mb-3" />
            <p class="text-base-content/50 text-sm">
              No hay datos de rendimiento para este período.
            </p>
            <p class="text-base-content/30 text-xs mt-1">
              Los datos aparecen una vez que se cierran comandas con empleados identificados.
            </p>
          </div>
        <% end %>

        <%!-- Station staff: cocina & barra --%>
        <%= if @station_stats != [] do %>
          <div class="space-y-4">
            <div class="flex items-center gap-2">
              <h2 class="text-base font-semibold text-base-content">Cocina y Barra — Preparación</h2>
              <span class="badge badge-sm badge-ghost">{length(@station_stats)} empleados</span>
            </div>
            <p class="text-xs text-base-content/40 -mt-2">
              Tiempo desde que el pedido llega a la estación hasta que se marca listo.
            </p>
            <.stat_grid stats={@station_stats} threshold_secs={@prep_threshold_secs} unit="ítems" />
          </div>
        <% end %>

        <%!-- Waiters --%>
        <%= if @waiter_stats != [] do %>
          <div class="space-y-4">
            <div class="flex items-center gap-2">
              <h2 class="text-base font-semibold text-base-content">Meseros — Tiempo de servicio</h2>
              <span class="badge badge-sm badge-ghost">{length(@waiter_stats)} meseros</span>
            </div>
            <p class="text-xs text-base-content/40 -mt-2">
              Tiempo total de la cuenta (apertura → cobro) y tiempo de recogida (platillo listo → servido).
            </p>
            <.stat_grid stats={@waiter_stats} threshold_secs={@service_threshold_secs} unit="comandas" />

            <%!-- Pickup time sub-grid (only when there is served data) --%>
            <% has_pickup = Enum.any?(@waiter_stats, fn s -> s.pickup_count > 0 end) %>
            <%= if has_pickup do %>
              <div>
                <p class="text-xs font-semibold text-base-content/60 uppercase tracking-wider mb-3">
                  Tiempo de recogida (platillo listo → servido en mesa)
                </p>
                <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                  <%= for stat <- @waiter_stats, stat.pickup_count > 0 do %>
                    <% pickup_overdue? = stat.pickup_avg >= @prep_threshold_secs %>
                    <div class={["bg-base-100 rounded-2xl border shadow-sm p-4 space-y-2",
                      if(pickup_overdue?, do: "border-error/40", else: "border-base-300")]}>
                      <div class="flex items-center gap-2">
                        <div class="size-7 rounded-full bg-primary/10 flex items-center justify-center text-xs font-bold text-primary shrink-0">
                          {String.first(stat.name) |> String.upcase()}
                        </div>
                        <span class="text-sm font-semibold text-base-content truncate">{stat.name}</span>
                      </div>
                      <div class="grid grid-cols-3 gap-1 text-center">
                        <div>
                          <p class="text-xs text-base-content/40">Ítems</p>
                          <p class="text-sm font-semibold">{stat.pickup_count}</p>
                        </div>
                        <div>
                          <p class="text-xs text-base-content/40">Promedio</p>
                          <p class={["text-sm font-bold", if(pickup_overdue?, do: "text-error", else: "text-success")]}>
                            {format_duration(stat.pickup_avg)}
                          </p>
                        </div>
                        <div>
                          <p class="text-xs text-base-content/40">Rango</p>
                          <p class="text-xs text-base-content/60">
                            {format_duration(stat.pickup_min)} – {format_duration(stat.pickup_max)}
                          </p>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>

      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Stat grid component
  # ---------------------------------------------------------------------------

  attr :stats, :list, required: true
  attr :threshold_secs, :integer, required: true
  attr :unit, :string, default: "ítems"

  defp stat_grid(assigns) do
    max_avg = assigns.stats |> Enum.map(& &1.avg) |> Enum.max(fn -> 1 end)
    assigns = assign(assigns, :max_avg, max(max_avg, 1))

    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <%= for stat <- @stats do %>
        <% overdue? = stat.avg >= @threshold_secs %>
        <div class={[
          "bg-base-100 rounded-2xl border shadow-sm p-4 space-y-3",
          if(overdue?, do: "border-error/40", else: "border-base-300")
        ]}>
          <%!-- Employee header --%>
          <div class="flex items-center justify-between gap-2">
            <div class="flex items-center gap-2 min-w-0">
              <div class={[
                "size-8 rounded-full flex items-center justify-center text-sm font-bold shrink-0",
                if(overdue?, do: "bg-error text-error-content", else: "bg-primary/10 text-primary")
              ]}>
                {String.first(stat.name) |> String.upcase()}
              </div>
              <span class="text-sm font-semibold text-base-content truncate">{stat.name}</span>
            </div>
            <div class="flex items-center gap-1 shrink-0">
              <%= if stat.station && stat.station != "—" do %>
                <span class="badge badge-xs badge-ghost">{stat.station}</span>
              <% end %>
              <%= if overdue? do %>
                <span class="badge badge-xs badge-error gap-1">
                  <.icon name="hero-exclamation-triangle" class="size-3" /> Lento
                </span>
              <% end %>
            </div>
          </div>

          <%!-- Metrics --%>
          <div class="grid grid-cols-3 gap-1 text-center">
            <div>
              <p class="text-xs text-base-content/40">Total</p>
              <p class="text-sm font-semibold text-base-content">{stat.count}</p>
              <p class="text-xs text-base-content/40">{@unit}</p>
            </div>
            <div>
              <p class="text-xs text-base-content/40">Promedio</p>
              <p class={["text-sm font-bold", if(overdue?, do: "text-error", else: "text-success")]}>
                {format_duration(stat.avg)}
              </p>
            </div>
            <div>
              <p class="text-xs text-base-content/40">Rango</p>
              <p class="text-xs text-base-content/60">
                {format_duration(stat.min)}–{format_duration(stat.max)}
              </p>
            </div>
          </div>

          <%!-- Bar --%>
          <div class="w-full bg-base-200 rounded-full h-2">
            <div
              class={["h-2 rounded-full transition-all", if(overdue?, do: "bg-error", else: "bg-success")]}
              style={"width: #{min(round(stat.avg / @max_avg * 100), 100)}%"}
            >
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_stats(socket) do
    %{station_stats: station, waiter_stats: waiters} =
      Orders.employee_stats(socket.assigns.period)

    socket
    |> assign(:station_stats, station)
    |> assign(:waiter_stats, waiters)
  end

  defp format_duration(secs) when secs < 60, do: "#{secs}s"
  defp format_duration(secs) do
    mins = div(secs, 60)
    rem = rem(secs, 60)
    if rem == 0, do: "#{mins}min", else: "#{mins}min #{rem}s"
  end
end
