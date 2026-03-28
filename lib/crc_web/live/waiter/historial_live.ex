defmodule CRCWeb.Waiter.HistorialLive do
  @moduledoc "Historical closed orders view. Waiters see their own; admins see all."

  use CRCWeb, :live_view

  alias CRC.Orders

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    is_admin = user.role == "admin"

    waiters = if is_admin, do: Orders.list_waiters_with_history(), else: []

    socket =
      socket
      |> assign(:page_title, "Historial de comandas")
      |> assign(:is_admin, is_admin)
      |> assign(:waiters, waiters)
      |> assign(:period, :today)
      |> assign(:date_from, "")
      |> assign(:date_to, "")
      |> assign(:filter_user_id, nil)
      |> assign(:expanded_id, nil)
      |> load_orders()

    {:ok, socket}
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
      |> load_orders()

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
        |> load_orders()

      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("filter_user", %{"user_id" => user_id_str}, socket) do
    user_id = if user_id_str == "", do: nil, else: String.to_integer(user_id_str)

    socket =
      socket
      |> assign(:filter_user_id, user_id)
      |> load_orders()

    {:noreply, socket}
  end

  def handle_event("toggle_order", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    expanded = if socket.assigns.expanded_id == id, do: nil, else: id
    {:noreply, assign(socket, :expanded_id, expanded)}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 pb-16">
      <div class="max-w-4xl mx-auto px-4 py-8 space-y-6">

        <%!-- Header --%>
        <div class="flex items-center justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Historial de comandas</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              <%= if @is_admin do %>
                Todas las comandas cerradas
              <% else %>
                Tus comandas cerradas
              <% end %>
            </p>
          </div>
          <a href="/mesa" class="btn btn-sm btn-ghost">
            <.icon name="hero-arrow-left" class="size-4" /> Volver
          </a>
        </div>

        <%!-- Filters --%>
        <div class="flex flex-wrap items-end gap-4">
          <%!-- Period tabs --%>
          <div class="flex gap-2 flex-wrap">
            <%= for {label, value} <- [{"Hoy", "today"}, {"Semana", "week"}, {"Mes", "month"}, {"Todo", "all"}] do %>
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
                class="input input-sm input-bordered w-36"
              />
              <span class="text-base-content/40 text-xs">—</span>
              <input
                type="date" name="date_to" value={@date_to}
                class="input input-sm input-bordered w-36"
              />
            </div>
          </form>

          <%!-- Admin: filter by waiter --%>
          <%= if @is_admin and @waiters != [] do %>
            <div class="flex flex-col gap-1">
              <span class="text-xs text-base-content/50">Mesero</span>
              <form phx-change="filter_user">
                <select name="user_id" class="select select-sm select-bordered">
                  <option value="">Todos</option>
                  <%= for w <- @waiters do %>
                    <option value={w.id} selected={@filter_user_id == w.id}>{w.name}</option>
                  <% end %>
                </select>
              </form>
            </div>
          <% end %>
        </div>

        <%!-- Active range indicator --%>
        <%= if is_tuple(@period) do %>
          <div class="alert alert-info py-2">
            <.icon name="hero-calendar" class="size-4" />
            <span class="text-sm">
              Rango activo: {elem(@period, 1) |> Date.to_iso8601()} — {elem(@period, 2) |> Date.to_iso8601()}
            </span>
          </div>
        <% end %>

        <%!-- Summary chip --%>
        <div class="flex items-center gap-3">
          <span class="badge badge-lg badge-ghost">
            {length(@orders)} {if length(@orders) == 1, do: "comanda", else: "comandas"}
          </span>
          <%= if @orders != [] do %>
            <span class="text-sm font-semibold text-base-content">
              Total: <span class="text-primary">${format_total(total_revenue(@orders))}</span>
            </span>
          <% end %>
        </div>

        <%!-- Empty state --%>
        <%= if @orders == [] do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-20 text-center">
            <.icon name="hero-document-text" class="size-12 text-base-content/20 mx-auto mb-3" />
            <p class="text-base-content/50 text-sm">No hay comandas cerradas en este período.</p>
          </div>
        <% end %>

        <%!-- Orders list --%>
        <div class="space-y-3">
          <%= for order <- @orders do %>
            <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
              <%!-- Order row (clickable header) --%>
              <button
                class="w-full text-left px-5 py-4 flex items-center gap-4 hover:bg-base-200/50 transition-colors"
                phx-click="toggle_order"
                phx-value-id={order.id}
              >
                <%!-- Date/time --%>
                <div class="shrink-0 text-center w-12">
                  <p class="text-xs font-bold text-base-content">{format_day(order.closed_at)}</p>
                  <p class="text-xs text-base-content/50">{format_month(order.closed_at)}</p>
                </div>

                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2 flex-wrap">
                    <span class="font-semibold text-base-content truncate">{order.customer_name}</span>
                    <span class="badge badge-xs badge-ghost">{order_item_count(order)} artículos</span>
                    <%= if @is_admin and order.user do %>
                      <span class="badge badge-xs badge-ghost text-base-content/50">{order.user.name}</span>
                    <% end %>
                  </div>
                  <p class="text-xs text-base-content/40 mt-0.5">
                    {format_time(order.closed_at)} · {payment_label(order.payment_method)}
                  </p>
                </div>

                <div class="shrink-0 text-right">
                  <p class="font-bold text-primary">${format_total(order.total)}</p>
                  <%= if order.payment_method == "efectivo" and order.amount_paid do %>
                    <% change = Decimal.sub(order.amount_paid, order.total) %>
                    <p class="text-xs text-base-content/40">
                      Cambio: ${format_total(change)}
                    </p>
                  <% end %>
                </div>

                <.icon
                  name={if @expanded_id == order.id, do: "hero-chevron-up", else: "hero-chevron-down"}
                  class="size-4 text-base-content/30 shrink-0"
                />
              </button>

              <%!-- Expanded detail --%>
              <%= if @expanded_id == order.id do %>
                <div class="border-t border-base-300 px-5 py-4 space-y-1 bg-base-50">
                  <%= for item <- visible_items(order.order_items) do %>
                    <div class="flex items-center justify-between py-1.5 text-sm">
                      <div class="flex items-center gap-2 min-w-0">
                        <%= if item.for_menu_item_id do %>
                          <span class="text-base-content/30 text-xs pl-4">↳</span>
                          <span class="text-base-content/60 truncate">
                            {item_name(item)} <span class="text-xs text-base-content/40">× {item.quantity}</span>
                          </span>
                        <% else %>
                          <span class="text-base-content truncate">
                            {item_name(item)} <span class="text-xs text-base-content/40">× {item.quantity}</span>
                          </span>
                        <% end %>
                        <%= if item.status == "cancelled" or item.status == "cancelled_waste" do %>
                          <span class="badge badge-xs badge-error">Cancelado</span>
                        <% end %>
                      </div>
                      <%= if item.menu_item && item.status not in ["cancelled", "cancelled_waste"] do %>
                        <span class="text-base-content/70 shrink-0 ml-4">
                          ${format_total(Decimal.mult(item.menu_item.price, Decimal.new(item.quantity)))}
                        </span>
                      <% end %>
                    </div>
                  <% end %>

                  <div class="pt-3 mt-2 border-t border-base-200 flex justify-between items-center">
                    <span class="text-sm text-base-content/50">Total cobrado</span>
                    <span class="font-bold text-base-content">${format_total(order.total)}</span>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp load_orders(socket) do
    user = socket.assigns.current_user
    period = socket.assigns.period

    opts =
      if socket.assigns.is_admin do
        case socket.assigns.filter_user_id do
          nil -> []
          uid -> [user_id: uid]
        end
      else
        [user_id: user.id]
      end

    orders = Orders.list_orders_history(period, opts)
    assign(socket, :orders, orders)
  end

  defp total_revenue(orders) do
    Enum.reduce(orders, Decimal.new(0), fn o, acc ->
      Decimal.add(acc, o.total || Decimal.new(0))
    end)
  end

  defp order_item_count(order) do
    order.order_items
    |> Enum.count(&(&1.status not in ["cancelled", "cancelled_waste"] and is_nil(&1.for_menu_item_id) and not is_nil(&1.menu_item_id)))
  end

  defp visible_items(items) do
    items
    |> Enum.sort_by(fn i ->
      {if(i.for_menu_item_id, do: 1, else: 0), i.id}
    end)
  end

  defp item_name(%{menu_item: %{name: name}}), do: name
  defp item_name(%{product: %{name: name}}), do: name
  defp item_name(_), do: "—"

  defp format_total(%Decimal{} = d), do: d |> Decimal.round(0) |> Decimal.to_string()
  defp format_total(nil), do: "0"
  defp format_total(v), do: "#{v}"

  defp format_day(nil), do: "—"
  defp format_day(dt) do
    dt
    |> DateTime.add(-6 * 3600, :second)
    |> Map.get(:day)
    |> Integer.to_string()
    |> String.pad_leading(2, "0")
  end

  defp format_month(nil), do: ""
  defp format_month(dt) do
    months = ~w(ene feb mar abr may jun jul ago sep oct nov dic)
    month_idx = (dt |> DateTime.add(-6 * 3600, :second)).month - 1
    Enum.at(months, month_idx)
  end

  defp format_time(nil), do: ""
  defp format_time(dt) do
    local = DateTime.add(dt, -6 * 3600, :second)
    h = local.hour |> Integer.to_string() |> String.pad_leading(2, "0")
    m = local.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{h}:#{m}"
  end

  defp payment_label("efectivo"), do: "Efectivo"
  defp payment_label("tarjeta"), do: "Tarjeta"
  defp payment_label("transferencia"), do: "Transferencia"
  defp payment_label(_), do: "—"
end
