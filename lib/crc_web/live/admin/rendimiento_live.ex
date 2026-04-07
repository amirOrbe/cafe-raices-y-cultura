defmodule CRCWeb.Admin.RendimientoLive do
  @moduledoc "Admin view showing per-employee performance metrics, rankings, and recognitions."

  use CRCWeb, :live_view

  alias CRC.{Orders, Accounts}
  alias CRC.Accounts.User

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
      |> assign(:recognition_modal, nil)
      |> assign(:recognition_note, "")
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

  def handle_event("open_recognition_modal", %{"user_id" => user_id_str, "kind" => kind}, socket) do
    user_id = String.to_integer(user_id_str)
    user = Accounts.get_user(user_id)

    socket =
      socket
      |> assign(:recognition_modal, %{user: user, kind: kind})
      |> assign(:recognition_note, "")

    {:noreply, socket}
  end

  def handle_event("close_recognition_modal", _, socket) do
    {:noreply, assign(socket, :recognition_modal, nil)}
  end

  def handle_event("update_recognition_note", %{"note" => note}, socket) do
    {:noreply, assign(socket, :recognition_note, note)}
  end

  def handle_event("confirm_recognition", _, socket) do
    %{recognition_modal: %{user: user, kind: kind}, recognition_note: note} = socket.assigns
    current_user = socket.assigns.current_user

    attrs = %{
      user_id: user.id,
      kind: kind,
      note: if(note == "", do: nil, else: note),
      period_date: Date.utc_today()
    }

    case Accounts.give_recognition(current_user, attrs) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:recognition_modal, nil)
          |> assign(:recognition_note, "")
          |> load_stats()
          |> put_flash(:info, "Reconocimiento enviado a #{user.name}")

        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "No tienes permiso para dar reconocimientos")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error al guardar el reconocimiento")}
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
            Tiempos de preparación, atención y rankings del período
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

        <%!-- Rankings --%>
        <%= if @revenue_ranking != [] or @speed_ranking != [] do %>
          <div class="space-y-4">
            <div class="flex items-center gap-2">
              <h2 class="text-base font-semibold text-base-content">Rankings del período</h2>
              <span class="badge badge-sm badge-warning">🏆</span>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">

              <%!-- Revenue ranking --%>
              <%= if @revenue_ranking != [] do %>
                <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5 space-y-3">
                  <div class="flex items-center gap-2 mb-1">
                    <span class="text-base">💰</span>
                    <h3 class="font-semibold text-sm text-base-content">Mayor venta</h3>
                  </div>
                  <div class="space-y-2">
                    <%= for entry <- @revenue_ranking do %>
                      <% medal = medal_for(entry.rank) %>
                      <div class="flex items-center justify-between gap-2">
                        <div class="flex items-center gap-2 min-w-0">
                          <span class="text-lg shrink-0">{medal}</span>
                          <div class="size-7 rounded-full bg-primary/10 flex items-center justify-center text-xs font-bold text-primary shrink-0">
                            {String.first(entry.name) |> String.upcase()}
                          </div>
                          <span class="text-sm font-medium text-base-content truncate">{entry.name}</span>
                        </div>
                        <div class="flex items-center gap-3 shrink-0">
                          <div class="text-right">
                            <p class="text-sm font-bold text-success">
                              $<%= Decimal.round(entry.revenue, 2) %>
                            </p>
                            <p class="text-xs text-base-content/40">{entry.order_count} comandas</p>
                          </div>
                          <%= if @current_user.role == "admin" do %>
                            <button
                              class="btn btn-xs btn-ghost border border-base-300 gap-1"
                              phx-click="open_recognition_modal"
                              phx-value-user_id={entry.user_id}
                              phx-value-kind="top_sales"
                              title="Dar reconocimiento"
                            >
                              🎖️
                            </button>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- Speed ranking --%>
              <%= if @speed_ranking != [] do %>
                <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5 space-y-3">
                  <div class="flex items-center gap-2 mb-1">
                    <span class="text-base">⚡</span>
                    <h3 class="font-semibold text-sm text-base-content">Mayor velocidad</h3>
                  </div>
                  <div class="space-y-2">
                    <%= for entry <- @speed_ranking do %>
                      <% medal = medal_for(entry.rank) %>
                      <div class="flex items-center justify-between gap-2">
                        <div class="flex items-center gap-2 min-w-0">
                          <span class="text-lg shrink-0">{medal}</span>
                          <div class="size-7 rounded-full bg-secondary/10 flex items-center justify-center text-xs font-bold text-secondary shrink-0">
                            {String.first(entry.name) |> String.upcase()}
                          </div>
                          <span class="text-sm font-medium text-base-content truncate">{entry.name}</span>
                          <%= if entry.station do %>
                            <span class="badge badge-xs badge-ghost">{entry.station}</span>
                          <% end %>
                        </div>
                        <div class="flex items-center gap-3 shrink-0">
                          <div class="text-right">
                            <p class="text-sm font-bold text-info">{format_duration(entry.avg_secs)}</p>
                            <p class="text-xs text-base-content/40">{entry.count} ítems</p>
                          </div>
                          <%= if @current_user.role == "admin" do %>
                            <button
                              class="btn btn-xs btn-ghost border border-base-300 gap-1"
                              phx-click="open_recognition_modal"
                              phx-value-user_id={entry.user_id}
                              phx-value-kind="top_speed"
                              title="Dar reconocimiento"
                            >
                              🎖️
                            </button>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

            </div>
          </div>
        <% end %>

        <%!-- Recent recognitions today --%>
        <%= if @recognitions_today != [] do %>
          <div class="space-y-3">
            <h2 class="text-base font-semibold text-base-content">Reconocimientos de hoy</h2>
            <div class="flex flex-wrap gap-3">
              <%= for r <- @recognitions_today do %>
                <div class="bg-base-100 rounded-xl border border-warning/30 shadow-sm px-4 py-3 flex items-start gap-3 max-w-xs">
                  <span class="text-2xl shrink-0">{recognition_emoji(r.kind)}</span>
                  <div class="min-w-0">
                    <p class="text-sm font-semibold text-base-content truncate">{r.user.name}</p>
                    <p class="text-xs text-base-content/50">{recognition_label(r.kind)}</p>
                    <%= if r.note do %>
                      <p class="text-xs text-base-content/70 mt-1 italic">"{r.note}"</p>
                    <% end %>
                    <%= if r.given_by do %>
                      <p class="text-xs text-base-content/30 mt-1">— {r.given_by.name}</p>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
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
            <.stat_grid stats={@station_stats} threshold_secs={@prep_threshold_secs} unit="ítems" current_user={@current_user} />
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
            <.stat_grid stats={@waiter_stats} threshold_secs={@service_threshold_secs} unit="comandas" current_user={@current_user} />

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

    <%!-- Recognition modal --%>
    <%= if @recognition_modal do %>
      <% modal = @recognition_modal %>
      <div class="modal modal-open">
        <div class="modal-box max-w-sm">
          <div class="flex items-center gap-3 mb-4">
            <span class="text-3xl">{recognition_emoji(modal.kind)}</span>
            <div>
              <h3 class="font-bold text-base">{recognition_label(modal.kind)}</h3>
              <p class="text-sm text-base-content/60">para {modal.user.name}</p>
            </div>
          </div>

          <div class="form-control mb-4">
            <label class="label">
              <span class="label-text text-xs">Nota personal (opcional)</span>
            </label>
            <textarea
              class="textarea textarea-bordered textarea-sm resize-none"
              rows="3"
              placeholder="Ej: Excelente actitud hoy, los clientes quedaron muy contentos…"
              phx-change="update_recognition_note"
              name="note"
            >{@recognition_note}</textarea>
          </div>

          <div class="modal-action">
            <button class="btn btn-ghost btn-sm" phx-click="close_recognition_modal">
              Cancelar
            </button>
            <button class="btn btn-primary btn-sm gap-1" phx-click="confirm_recognition">
              <.icon name="hero-check" class="size-4" />
              Confirmar
            </button>
          </div>
        </div>
        <div class="modal-backdrop" phx-click="close_recognition_modal"></div>
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Stat grid component
  # ---------------------------------------------------------------------------

  attr :stats, :list, required: true
  attr :threshold_secs, :integer, required: true
  attr :unit, :string, default: "ítems"
  attr :current_user, User, required: true

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
              <%= if @current_user.role == "admin" do %>
                <button
                  class="btn btn-xs btn-ghost px-1"
                  phx-click="open_recognition_modal"
                  phx-value-user_id={stat.user_id}
                  phx-value-kind="custom"
                  title="Dar reconocimiento"
                >
                  🎖️
                </button>
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

    %{revenue_ranking: revenue, speed_ranking: speed} =
      Orders.employee_rankings(socket.assigns.period)

    recognitions_today = Accounts.list_recognitions_for_period(Date.utc_today())

    socket
    |> assign(:station_stats, station)
    |> assign(:waiter_stats, waiters)
    |> assign(:revenue_ranking, revenue)
    |> assign(:speed_ranking, speed)
    |> assign(:recognitions_today, recognitions_today)
  end

  defp format_duration(secs) when secs < 60, do: "#{secs}s"
  defp format_duration(secs) do
    mins = div(secs, 60)
    rem = rem(secs, 60)
    if rem == 0, do: "#{mins}min", else: "#{mins}min #{rem}s"
  end

  defp medal_for(1), do: "🥇"
  defp medal_for(2), do: "🥈"
  defp medal_for(3), do: "🥉"
  defp medal_for(_), do: "·"

  defp recognition_emoji("top_sales"), do: "💰"
  defp recognition_emoji("top_speed"), do: "⚡"
  defp recognition_emoji(_), do: "🎖️"

  defp recognition_label("top_sales"), do: "Mayor ventas"
  defp recognition_label("top_speed"), do: "Mayor velocidad"
  defp recognition_label(_), do: "Reconocimiento especial"
end
