defmodule CRCWeb.Waiter.TableLive do
  @moduledoc "Overview of active customer tabs (cuentas) with option to create new ones."

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

    socket =
      socket
      |> assign(:page_title, "Comandas")
      |> assign(:orders, Orders.list_active_orders())
      |> assign(:now, DateTime.utc_now())
      |> assign(:show_new_modal, false)
      |> assign(:new_name, "")
      |> assign(:name_error, nil)
      |> assign(:nav_open, false)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub + tick
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:order_updated, _order_id}, socket) do
    {:noreply,
     socket
     |> assign(:orders, Orders.list_active_orders())
     |> assign(:now, DateTime.utc_now())}
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

  def handle_event("open_new_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_new_modal, true)
     |> assign(:new_name, "")
     |> assign(:name_error, nil)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :show_new_modal, false)}
  end

  def handle_event("update_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_name, value)}
  end

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
    <SiteComponents.site_navbar nav_open={@nav_open} current_page={:waiter} current_user={@current_user} />
    <div class="min-h-screen bg-base-200 pt-20 pb-10 px-4">
      <div class="max-w-5xl mx-auto space-y-6">

        <%!-- Header --%>
        <div class="flex items-center justify-between flex-wrap gap-3">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Comandas</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              Comandas activas del turno
            </p>
          </div>
          <div class="flex items-center gap-2">
            <a href="/mesa/historial" class="btn btn-ghost btn-sm gap-1">
              <.icon name="hero-clock" class="size-4" />
              Historial
            </a>
            <button class="btn btn-primary btn-sm gap-1" phx-click="open_new_modal">
              <.icon name="hero-plus" class="size-4" />
              Nueva cuenta
            </button>
          </div>
        </div>

        <%!-- Empty state --%>
        <%= if @orders == [] do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-20 text-center">
            <.icon name="hero-clipboard-document-list" class="size-12 text-base-content/20 mx-auto mb-3" />
            <p class="text-base-content/50 text-sm">No hay comandas abiertas.</p>
            <button class="btn btn-primary btn-sm mt-4" phx-click="open_new_modal">
              Abrir primera cuenta
            </button>
          </div>
        <% end %>

        <%!-- Comandas grid --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
          <%= for order <- @orders do %>
            <.cuenta_card order={order} now={@now} />
          <% end %>
        </div>

      </div>
    </div>

    <%!-- Nueva cuenta modal --%>
    <%= if @show_new_modal do %>
      <div class="fixed inset-0 z-50">
        <div class="absolute inset-0 bg-black/50" phx-click="close_modal"></div>
        <div class="relative z-10 flex items-center justify-center min-h-full px-4 pointer-events-none">
          <div class="bg-base-100 rounded-2xl shadow-xl w-full max-w-sm p-6 space-y-4 pointer-events-auto">
            <h2 class="text-lg font-bold text-base-content">Nueva cuenta</h2>
            <p class="text-sm text-base-content/50 mt-1">
              Ingresa el nombre del cliente o una referencia (ej. "Mesa 3", "Juan G.")
            </p>

            <form phx-submit="create_cuenta" class="mt-4 space-y-3">
              <div>
                <input
                  type="text"
                  name="customer_name"
                  value={@new_name}
                  placeholder="Nombre del cliente"
                  class={["input input-bordered w-full", @name_error && "input-error"]}
                  autofocus
                  autocomplete="off"
                />
                <%= if @name_error do %>
                  <p class="text-error text-xs mt-1">{@name_error}</p>
                <% end %>
              </div>
              <div class="flex gap-2 pt-1">
                <button type="button" class="btn btn-ghost flex-1" phx-click="close_modal">
                  Cancelar
                </button>
                <button type="submit" class="btn btn-primary flex-1">
                  Abrir cuenta
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Cuenta card component
  # ---------------------------------------------------------------------------

  attr :order, :map, required: true
  attr :now, :any, required: true

  defp cuenta_card(assigns) do
    assigns =
      assigns
      |> assign(:overdue?, has_overdue_items?(assigns.order, assigns.now))
      |> assign(:drinks_ready?, drinks_ready_food_pending?(assigns.order))
      |> assign(:all_ready?, all_active_items_ready?(assigns.order))
      |> assign(:any_ready?, has_ready_items?(assigns.order))

    ~H"""
    <a href={"/mesa/#{@order.id}"} class="block">
      <div class={[
        "card bg-base-100 shadow-sm border-2 hover:shadow-md transition-all cursor-pointer",
        card_border_class(@overdue?, @all_ready?, @drinks_ready?, @order.status)
      ]}>
        <div class="card-body p-4 gap-2">
          <%!-- Name + status --%>
          <div class="flex items-center justify-between gap-2">
            <span class="text-base font-bold text-base-content truncate">{@order.customer_name}</span>
            <.status_badge status={@order.status} />
          </div>

          <%!-- Item count + waiter --%>
          <div class="flex items-center justify-between gap-2 text-sm text-base-content/60">
            <span>
              <%= if length(@order.order_items) == 0 do %>
                Sin artículos
              <% else %>
                {length(@order.order_items)} {if length(@order.order_items) == 1, do: "artículo", else: "artículos"}
              <% end %>
            </span>
            <%= if @order.user do %>
              <span class="text-xs text-base-content/40 truncate max-w-[100px]">
                <.icon name="hero-user" class="size-3 inline" /> {@order.user.name}
              </span>
            <% end %>
          </div>

          <%!-- Indicator badges --%>
          <div class="flex flex-wrap gap-1.5 min-h-[1.25rem]">
            <%= if @overdue? do %>
              <span class="badge badge-xs badge-error gap-1 animate-pulse">
                <.icon name="hero-clock" class="size-3" /> +15 min
              </span>
            <% end %>
            <%= if @drinks_ready? do %>
              <span class="badge badge-xs badge-info gap-1">
                <.icon name="hero-beaker" class="size-3" /> Bebidas listas
              </span>
            <% end %>
            <%= if @any_ready? and not @all_ready? and not @drinks_ready? do %>
              <span class="badge badge-xs badge-success gap-1">
                <.icon name="hero-check" class="size-3" /> Hay listos
              </span>
            <% end %>
          </div>

          <%!-- CTA button --%>
          <div class="mt-1">
            <span class={["btn btn-xs w-full", cta_btn_class(@overdue?, @all_ready?, @order.status)]}>
              <%= cond do %>
                <% @overdue? -> %>
                  <.icon name="hero-exclamation-triangle" class="size-3" /> Revisar — tardando mucho
                <% @all_ready? -> %>
                  <.icon name="hero-check-circle" class="size-3" /> Lista para servir
                <% @drinks_ready? -> %>
                  <.icon name="hero-beaker" class="size-3" /> Bebidas listas · Revisar
                <% true -> %>
                  Ver comanda
              <% end %>
            </span>
          </div>
        </div>
      </div>
    </a>
    """
  end

  # ---------------------------------------------------------------------------
  # Badge components
  # ---------------------------------------------------------------------------

  defp status_badge(%{status: "open"} = assigns) do
    ~H"<span class='badge badge-sm badge-info'>Abierta</span>"
  end

  defp status_badge(%{status: "sent"} = assigns) do
    ~H"<span class='badge badge-sm badge-warning'>En cocina</span>"
  end

  defp status_badge(%{status: "ready"} = assigns) do
    ~H"<span class='badge badge-sm badge-success'>Lista</span>"
  end

  defp status_badge(assigns) do
    ~H"<span class='badge badge-sm badge-ghost'>{@status}</span>"
  end

  # ---------------------------------------------------------------------------
  # Style helpers
  # ---------------------------------------------------------------------------

  defp card_border_class(true, _all_ready, _drinks_ready, _status),
    do: "border-error animate-pulse"

  defp card_border_class(_overdue, true, _drinks_ready, _status), do: "border-success"
  defp card_border_class(_overdue, _all_ready, true, _status), do: "border-info"
  defp card_border_class(_overdue, _all_ready, _drinks_ready, "sent"), do: "border-warning"
  defp card_border_class(_overdue, _all_ready, _drinks_ready, _status), do: "border-base-300"

  defp cta_btn_class(true, _all_ready, _status), do: "btn-error btn-outline"
  defp cta_btn_class(_overdue, true, _status), do: "btn-success btn-outline"
  defp cta_btn_class(_overdue, _all_ready, _status), do: "btn-outline btn-primary"

  # ---------------------------------------------------------------------------
  # Order state helpers
  # ---------------------------------------------------------------------------

  # Any sent item (not cancelled) has been waiting more than 15 min
  defp has_overdue_items?(order, now) do
    Enum.any?(order.order_items, fn item ->
      item.status == "sent" and not is_nil(item.sent_at) and
        DateTime.diff(now, item.sent_at, :second) > @overdue_seconds
    end)
  end

  # All drink items are ready but at least one food item is still pending/sent
  defp drinks_ready_food_pending?(order) do
    active = Enum.filter(order.order_items, &(&1.status not in ["cancelled", "cancelled_waste"]))
    drinks = Enum.filter(active, &item_is_drink?/1)
    food = Enum.filter(active, &(not item_is_drink?(&1)))

    drinks != [] and
      Enum.all?(drinks, &(&1.status == "ready")) and
      Enum.any?(food, &(&1.status in ["pending", "sent"]))
  end

  # All active items are ready
  defp all_active_items_ready?(order) do
    active = Enum.filter(order.order_items, &(&1.status not in ["cancelled", "cancelled_waste"]))
    active != [] and Enum.all?(active, &(&1.status == "ready"))
  end

  # At least one active item is ready
  defp has_ready_items?(order) do
    Enum.any?(order.order_items, &(&1.status == "ready"))
  end

  defp item_is_drink?(%{menu_item: %{category: %{kind: "drink"}}}), do: true
  defp item_is_drink?(_), do: false
end
