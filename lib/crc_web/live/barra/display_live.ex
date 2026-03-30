defmodule CRCWeb.Barra.DisplayLive do
  @moduledoc "Barra display screen. Shows sent orders filtered to drink items only."

  use CRCWeb, :live_view

  import CRCWeb.Layouts, only: [flash_group: 1]

  alias CRC.Orders
  alias CRCWeb.Components.SiteComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
    end

    socket =
      socket
      |> assign(:page_title, "Barra")
      |> assign(:orders, Orders.list_open_orders())
      |> assign(:nav_open, false)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:order_updated, _order_id}, socket) do
    {:noreply, assign(socket, :orders, Orders.list_open_orders())}
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

  def handle_event("mark_item_ready", %{"id" => id}, socket) do
    case Orders.mark_item_ready(String.to_integer(id), socket.assigns.current_user.id) do
      {:ok, _} ->
        {:noreply, assign(socket, :orders, Orders.list_open_orders())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo marcar el artículo como listo.")}
    end
  end

  def handle_event("mark_all_drinks_ready", %{"id" => id}, socket) do
    order = Enum.find(socket.assigns.orders, &(to_string(&1.id) == id))

    if order do
      order.order_items
      |> Enum.filter(fn oi -> oi.status == "sent" and drink_item?(oi) end)
      |> Enum.each(fn oi -> Orders.mark_item_ready(oi.id, socket.assigns.current_user.id) end)

      {:noreply,
       socket
       |> put_flash(:info, "#{order.customer_name} lista en barra.")
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
    <SiteComponents.site_navbar nav_open={@nav_open} current_page={:barra} current_user={@current_user} />
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

        <%!-- No pending orders --%>
        <%= if pending_orders(@orders) == [] do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-20 text-center">
            <.icon name="hero-check-circle" class="size-12 text-success mx-auto mb-3" />
            <p class="text-base-content/50 text-sm">No hay bebidas pendientes.</p>
          </div>
        <% end %>

        <%!-- Orders grid (drink items only) --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <%= for order <- pending_orders(@orders) do %>
            <% drink_items = drink_items(order) %>
            <%= if drink_items != [] do %>
              <div class="bg-base-100 rounded-2xl border border-info shadow-sm flex flex-col">

                <%!-- Order header --%>
                <div class="px-4 py-3 bg-info/10 rounded-t-2xl border-b border-info/30 flex items-center justify-between">
                  <div>
                    <h2 class="font-bold text-base-content">{order.customer_name}</h2>
                    <p class="text-xs text-base-content/50">
                      {length(drink_items)} {if length(drink_items) == 1, do: "bebida", else: "bebidas"}
                    </p>
                  </div>
                  <span class="badge badge-info badge-sm">Enviado</span>
                </div>

                <%!-- Drink items list --%>
                <div class="flex-1 divide-y divide-base-200">
                  <%= for item <- drink_items do %>
                    <div class="flex items-center gap-3 px-4 py-3">
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-medium text-base-content">
                          <span class="font-bold text-primary">{item.quantity}×</span>
                          {item.menu_item && item.menu_item.name}
                        </p>
                        <%!-- Ingredient exclusions requested by customer --%>
                        <%= if item.exclusions != [] do %>
                          <div class="flex flex-wrap items-center gap-1 mt-1">
                            <span class="text-xs font-bold text-error shrink-0">⚠ Sin:</span>
                            <%= for excl <- item.exclusions do %>
                              <span class="badge badge-xs badge-error">{excl.product.name}</span>
                            <% end %>
                          </div>
                        <% end %>
                        <%= if item.notes do %>
                          <p class="text-xs text-base-content/50 mt-0.5">{item.notes}</p>
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

                <%!-- Mark all drinks ready --%>
                <div class="px-4 py-3 border-t border-base-300">
                  <button
                    class="btn btn-success w-full btn-sm"
                    phx-click="mark_all_drinks_ready"
                    phx-value-id={order.id}
                  >
                    <.icon name="hero-check" class="size-4" />
                    Todo listo — {order.customer_name}
                  </button>
                </div>

              </div>
            <% end %>
          <% end %>
        </div>

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
  # Private helpers
  # ---------------------------------------------------------------------------

  # Only show drink items actively waiting to be prepared (not yet marked ready).
  # Excludes "ready" items so that second-batch sends don't resurface
  # already-served drinks in the bar queue.
  defp drink_items(order) do
    Enum.filter(order.order_items, fn oi ->
      oi.status == "sent" and drink_item?(oi)
    end)
  end

  defp drink_item?(oi) do
    not is_nil(oi.menu_item) and oi.menu_item.category.kind == "drink"
  end

  # An order is pending in barra if ANY drink item still has status "sent",
  # regardless of the order-level status (which may have advanced to "ready"
  # if cocina marked everything ready first while a drink was still pending).
  defp pending_orders(orders) do
    Enum.filter(orders, fn o ->
      Enum.any?(o.order_items, fn oi -> oi.status == "sent" and drink_item?(oi) end)
    end)
  end

  # Orders where all drink items are ready (none "sent") — waiting to be served.
  defp ready_drink_orders(orders) do
    Enum.filter(orders, fn o ->
      drinks = Enum.filter(o.order_items, &drink_item?/1)
      drinks != [] and Enum.all?(drinks, fn oi -> oi.status == "ready" end)
    end)
  end
end
