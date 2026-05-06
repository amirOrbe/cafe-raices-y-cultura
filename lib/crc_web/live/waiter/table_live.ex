defmodule CRCWeb.Waiter.TableLive do
  @moduledoc "Visual floor map of restaurant tables with real-time order status."

  use CRCWeb, :live_view

  alias CRC.Orders
  alias CRCWeb.Components.SiteComponents

  @tick_interval 30_000
  @overdue_seconds 15 * 60

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
      Process.send_after(self(), :tick, @tick_interval)
    end

    tables = Orders.list_active_tables()
    orders_by_table = Orders.active_orders_by_table()
    # Also keep "tableless" orders (created before this feature)
    tableless = Orders.list_active_orders() |> Enum.filter(&is_nil(&1.table_id))

    socket =
      socket
      |> assign(:page_title, "Mesas")
      |> assign(:tables, tables)
      |> assign(:orders_by_table, orders_by_table)
      |> assign(:tableless, tableless)
      |> assign(:now, DateTime.utc_now())
      |> assign(:selected_table, nil)
      |> assign(:show_new_modal, false)
      |> assign(:name_error, nil)
      |> assign(:nav_open, false)
      |> assign(:seen_ready_ids, all_ready_ids_from_map(orders_by_table, tableless))

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub + tick
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:order_updated, _order_id}, socket) do
    orders_by_table = Orders.active_orders_by_table()
    tableless = Orders.list_active_orders() |> Enum.filter(&is_nil(&1.table_id))
    new_ids = all_ready_ids_from_map(orders_by_table, tableless)
    new_ready? = not MapSet.subset?(new_ids, socket.assigns.seen_ready_ids)

    socket =
      socket
      |> assign(:orders_by_table, orders_by_table)
      |> assign(:tableless, tableless)
      |> assign(:now, DateTime.utc_now())
      |> assign(:seen_ready_ids, new_ids)

    socket =
      if new_ready?, do: push_event(socket, "play_sound", %{type: "item_ready"}), else: socket

    {:noreply, socket}
  end

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_interval)
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

  def handle_event("select_table", %{"id" => id}, socket) do
    table = Enum.find(socket.assigns.tables, &(to_string(&1.id) == id))

    case Map.get(socket.assigns.orders_by_table, table.id) do
      nil ->
        # Free table — show confirmation modal to open new order
        {:noreply,
         socket
         |> assign(:selected_table, table)
         |> assign(:show_new_modal, true)
         |> assign(:name_error, nil)}

      order ->
        # Occupied table — navigate directly to the order
        {:noreply, push_navigate(socket, to: "/mesa/#{order.id}")}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_new_modal, false)
     |> assign(:selected_table, nil)}
  end

  def handle_event("create_order_for_table", _params, socket) do
    table = socket.assigns.selected_table

    case Orders.create_order(%{
           customer_name: "Mesa #{table.number}",
           table_id: table.id,
           user_id: socket.assigns.current_user.id
         }) do
      {:ok, order} ->
        {:noreply,
         socket
         |> assign(:show_new_modal, false)
         |> push_navigate(to: "/mesa/#{order.id}")}

      {:error, _changeset} ->
        {:noreply, assign(socket, :name_error, "No se pudo abrir la mesa, intenta de nuevo")}
    end
  end

  # Legacy: open a tableless order with a custom name
  def handle_event("create_cuenta", %{"customer_name" => name}, socket) do
    name = String.trim(name)

    if name == "" do
      {:noreply, assign(socket, :name_error, "El nombre no puede estar vacío")}
    else
      case Orders.create_order(%{customer_name: name, user_id: socket.assigns.current_user.id}) do
        {:ok, order} ->
          {:noreply,
           socket
           |> assign(:show_new_modal, false)
           |> push_navigate(to: "/mesa/#{order.id}")}

        {:error, _changeset} ->
          {:noreply, assign(socket, :name_error, "No se pudo crear la cuenta, intenta de nuevo")}
      end
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
      current_page={:waiter}
      current_user={@current_user}
    />
    <div id="sound-notifier" phx-hook="SoundNotifier" class="hidden"></div>
    <div class="min-h-screen bg-base-200 pt-20 pb-10 px-4">
      <div class="max-w-5xl mx-auto space-y-5">
        <%!-- Header --%>
        <div class="flex items-center justify-between flex-wrap gap-3">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Mesas</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              {map_size(@orders_by_table)} ocupada{if map_size(@orders_by_table) != 1, do: "s"} ·
              {length(@tables) - map_size(@orders_by_table)} libre{if (length(@tables) - map_size(@orders_by_table)) != 1, do: "s"}
            </p>
          </div>
          <a href="/mesa/historial" class="btn btn-ghost btn-sm gap-1">
            <.icon name="hero-clock" class="size-4" /> Historial
          </a>
        </div>

        <%!-- Floor map or empty state --%>
        <%= if @tables == [] do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-16 text-center space-y-3">
            <.icon name="hero-table-cells" class="size-12 text-base-content/20 mx-auto" />
            <p class="text-base-content/50 text-sm font-medium">No hay mesas configuradas</p>
            <p class="text-base-content/40 text-xs">
              Un administrador debe agregar las mesas desde
              <a href="/admin/mesas" class="link">Admin → Mesas</a>.
            </p>
          </div>
        <% else %>
          <%!-- Map canvas --%>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
            <div
              class="relative w-full select-none"
              style="aspect-ratio: 16/9; background-image: radial-gradient(circle, oklch(80% 0.02 78) 1px, transparent 1px); background-size: 32px 32px;"
            >
              <%= for table <- @tables do %>
                <% order = Map.get(@orders_by_table, table.id) %>
                <% {chip_class, label_text} = table_chip_style(order, @now) %>
                <button
                  phx-click="select_table"
                  phx-value-id={table.id}
                  class={"absolute -translate-x-1/2 -translate-y-1/2 #{chip_class} w-14 h-14 rounded-2xl flex flex-col items-center justify-center shadow-md border-2 transition-all hover:scale-110 active:scale-95 focus:outline-none"}
                  style={"left: #{table.x_pct}%; top: #{table.y_pct}%"}
                  title={label_text}
                >
                  <span class="text-xl font-bold leading-none">{table.number}</span>
                  <%= if table.label && table.label != "" do %>
                    <span class="text-[9px] leading-tight truncate w-12 text-center px-0.5 mt-0.5 opacity-75">
                      {table.label}
                    </span>
                  <% end %>
                  <%= if order && overdue?(order, @now) do %>
                    <span class="absolute -top-1.5 -right-1.5 size-3.5 rounded-full bg-error border-2 border-base-100 animate-ping" />
                    <span class="absolute -top-1.5 -right-1.5 size-3.5 rounded-full bg-error border-2 border-base-100" />
                  <% end %>
                </button>
              <% end %>
            </div>

            <%!-- Status legend --%>
            <div class="px-5 py-3 border-t border-base-200 flex flex-wrap items-center gap-x-4 gap-y-1.5 text-xs text-base-content/60">
              <span class="flex items-center gap-1.5">
                <span class="size-3 rounded bg-base-200 border border-base-300 inline-block" /> Libre
              </span>
              <span class="flex items-center gap-1.5">
                <span class="size-3 rounded bg-info inline-block" /> Abierta
              </span>
              <span class="flex items-center gap-1.5">
                <span class="size-3 rounded bg-warning inline-block" /> En cocina
              </span>
              <span class="flex items-center gap-1.5">
                <span class="size-3 rounded bg-success inline-block" /> Lista para servir
              </span>
              <span class="flex items-center gap-1.5">
                <span class="size-3 rounded bg-error inline-block animate-pulse" /> +15 min esperando
              </span>
            </div>
          </div>
        <% end %>

        <%!-- Tableless orders (backward compat) --%>
        <%= if @tableless != [] do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
            <div class="px-5 py-3 border-b border-base-200 flex items-center justify-between gap-2">
              <div class="flex items-center gap-2">
                <.icon name="hero-clipboard-document-list" class="size-4 text-base-content/40" />
                <h3 class="font-semibold text-sm text-base-content">Cuentas sin mesa asignada</h3>
              </div>
              <span class="badge badge-ghost badge-sm">{length(@tableless)}</span>
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3 p-4">
              <%= for order <- @tableless do %>
                <.cuenta_card order={order} now={@now} />
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>

    <%!-- Open table modal --%>
    <%= if @show_new_modal and @selected_table do %>
      <div class="fixed inset-0 z-50">
        <div class="absolute inset-0 bg-black/50" phx-click="close_modal" />
        <div class="relative z-10 flex items-center justify-center min-h-full px-4 pointer-events-none">
          <div class="bg-base-100 rounded-2xl shadow-xl w-full max-w-sm p-6 space-y-4 pointer-events-auto">
            <div class="flex items-center gap-4">
              <div class="size-14 rounded-2xl bg-primary text-primary-content flex items-center justify-center text-2xl font-bold shadow">
                {@selected_table.number}
              </div>
              <div>
                <h2 class="text-lg font-bold text-base-content">
                  Mesa {@selected_table.number}
                  <%= if @selected_table.label && @selected_table.label != "" do %>
                    <span class="text-base-content/50 font-normal text-base"> · {@selected_table.label}</span>
                  <% end %>
                </h2>
                <p class="text-sm text-base-content/50">
                  {if @selected_table.capacity,
                    do: "Hasta #{@selected_table.capacity} personas · ",
                    else: ""}
                  Libre
                </p>
              </div>
            </div>
            <%= if @name_error do %>
              <p class="text-error text-xs">{@name_error}</p>
            <% end %>
            <div class="flex gap-2 pt-1">
              <button type="button" class="btn btn-ghost flex-1" phx-click="close_modal">
                Cancelar
              </button>
              <button
                type="button"
                class="btn btn-primary flex-1 gap-1"
                phx-click="create_order_for_table"
              >
                <.icon name="hero-plus" class="size-4" /> Abrir mesa
              </button>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Table chip style helper
  # ---------------------------------------------------------------------------

  defp table_chip_style(nil, _now) do
    {"bg-base-200 text-base-content/50 border-base-300", "Libre"}
  end

  defp table_chip_style(order, now) do
    cond do
      overdue?(order, now) ->
        {"bg-error text-error-content border-error", "Tardando — #{order.customer_name}"}

      all_active_items_ready?(order) ->
        {"bg-success text-success-content border-success", "Lista — #{order.customer_name}"}

      order.status == "sent" ->
        {"bg-warning text-warning-content border-warning", "En cocina — #{order.customer_name}"}

      true ->
        {"bg-info text-info-content border-info", "Abierta — #{order.customer_name}"}
    end
  end

  # ---------------------------------------------------------------------------
  # Cuenta card (for tableless legacy orders)
  # ---------------------------------------------------------------------------

  attr :order, :map, required: true
  attr :now, :any, required: true

  defp cuenta_card(assigns) do
    assigns =
      assigns
      |> assign(:overdue?, overdue?(assigns.order, assigns.now))
      |> assign(:all_ready?, all_active_items_ready?(assigns.order))

    ~H"""
    <a href={"/mesa/#{@order.id}"} class="block">
      <div class={[
        "card bg-base-100 shadow-sm border-2 hover:shadow-md transition-all cursor-pointer",
        card_border_class(@overdue?, @all_ready?, @order.status)
      ]}>
        <div class="card-body p-4 gap-2">
          <div class="flex items-center justify-between gap-2">
            <span class="text-base font-bold text-base-content truncate">{@order.customer_name}</span>
            <.status_badge status={@order.status} />
          </div>
          <div class="flex items-center justify-between gap-2 text-sm text-base-content/60">
            <span>
              {length(@order.order_items)} art{if length(@order.order_items) != 1, do: "ículos", else: "ículo"}
            </span>
            <%= if @order.user do %>
              <span class="text-xs text-base-content/40 truncate max-w-[100px]">
                <.icon name="hero-user" class="size-3 inline" /> {@order.user.name}
              </span>
            <% end %>
          </div>
          <%= if @overdue? do %>
            <span class="badge badge-xs badge-error gap-1 animate-pulse">
              <.icon name="hero-clock" class="size-3" /> +15 min
            </span>
          <% end %>
        </div>
      </div>
    </a>
    """
  end

  defp status_badge(%{status: "open"} = assigns) do
    ~H'<span class="badge badge-sm badge-info">Abierta</span>'
  end

  defp status_badge(%{status: "sent"} = assigns) do
    ~H'<span class="badge badge-sm badge-warning">En cocina</span>'
  end

  defp status_badge(%{status: "ready"} = assigns) do
    ~H'<span class="badge badge-sm badge-success">Lista</span>'
  end

  defp status_badge(assigns) do
    ~H'<span class="badge badge-sm badge-ghost">{@status}</span>'
  end

  defp card_border_class(true, _all_ready, _status), do: "border-error animate-pulse"
  defp card_border_class(_overdue, true, _status), do: "border-success"
  defp card_border_class(_overdue, _all_ready, "sent"), do: "border-warning"
  defp card_border_class(_overdue, _all_ready, _status), do: "border-base-300"

  # ---------------------------------------------------------------------------
  # Order state helpers
  # ---------------------------------------------------------------------------

  defp overdue?(order, now) do
    Enum.any?(order.order_items, fn item ->
      item.status == "sent" and not is_nil(item.sent_at) and
        DateTime.diff(now, item.sent_at, :second) > @overdue_seconds
    end)
  end

  defp all_active_items_ready?(order) do
    active = Enum.filter(order.order_items, &(&1.status not in ["cancelled", "cancelled_waste"]))
    active != [] and Enum.all?(active, &(&1.status == "ready"))
  end

  defp all_ready_ids_from_map(orders_by_table, tableless) do
    (Map.values(orders_by_table) ++ tableless)
    |> Enum.flat_map(& &1.order_items)
    |> Enum.filter(&(&1.status == "ready"))
    |> MapSet.new(& &1.id)
  end
end
