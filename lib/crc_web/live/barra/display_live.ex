defmodule CRCWeb.Barra.DisplayLive do
  @moduledoc "Barra display screen. Shows sent orders filtered to drink items only."

  use CRCWeb, :live_view

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
    case Orders.mark_item_ready(String.to_integer(id)) do
      {:ok, _} ->
        {:noreply, assign(socket, :orders, Orders.list_open_orders())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo marcar el artículo como listo.")}
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
                          {item.menu_item.name}
                        </p>
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

              </div>
            <% end %>
          <% end %>
        </div>

      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Only show items that have been explicitly sent (status "sent" or "ready")
  # Items with status "pending" haven't been dispatched to the station yet
  defp drink_items(order) do
    Enum.filter(order.order_items, fn oi ->
      oi.menu_item.category.kind == "drink" and oi.status in ["sent", "ready"]
    end)
  end

  defp pending_orders(orders) do
    orders
    |> Enum.filter(&(&1.status == "sent"))
    |> Enum.filter(fn o -> drink_items(o) != [] end)
  end
end
