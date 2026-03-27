defmodule CRCWeb.Waiter.OrderLive do
  @moduledoc "Order-taking LiveView per customer account. Allows adding, editing, and sending a comanda to cocina/barra."

  use CRCWeb, :live_view

  alias CRC.Orders
  alias CRC.Catalog
  alias CRCWeb.Components.SiteComponents

  @impl true
  def mount(%{"id" => order_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
    end

    order = Orders.get_order!(order_id)
    categories = Catalog.list_categories()
    first_category = List.first(categories)

    menu_items =
      if first_category do
        load_menu_items_for_category(first_category.id)
      else
        []
      end

    socket =
      socket
      |> assign(:page_title, order.customer_name)
      |> assign(:order, order)
      |> assign(:categories, categories)
      |> assign(:selected_category_id, first_category && first_category.id)
      |> assign(:menu_items, menu_items)
      |> assign(:flash_msg, nil)
      |> assign(:nav_open, false)

    {:ok, socket}
  rescue
    Ecto.NoResultsError ->
      {:ok,
       socket
       |> put_flash(:error, "Cuenta no encontrada.")
       |> redirect(to: "/mesa")}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:order_updated, order_id}, socket) do
    if socket.assigns.order.id == order_id do
      {:noreply, assign(socket, :order, Orders.get_order!(order_id))}
    else
      {:noreply, socket}
    end
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

  def handle_event("select_category", %{"id" => id}, socket) do
    category_id = String.to_integer(id)
    menu_items = load_menu_items_for_category(category_id)

    {:noreply,
     socket
     |> assign(:selected_category_id, category_id)
     |> assign(:menu_items, menu_items)}
  end

  def handle_event("add_item", %{"menu_item_id" => menu_item_id_str}, socket) do
    menu_item_id = String.to_integer(menu_item_id_str)
    order = socket.assigns.order

    # Only merge with an existing *pending* item — sent/ready items are already in the kitchen
    existing_pending =
      Enum.find(order.order_items, fn oi ->
        oi.menu_item_id == menu_item_id and oi.status == "pending"
      end)

    result =
      if existing_pending do
        Orders.update_item(existing_pending, %{quantity: existing_pending.quantity + 1})
      else
        Orders.add_item(%{
          order_id: order.id,
          menu_item_id: menu_item_id,
          quantity: 1
        })
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:order, Orders.get_order!(order.id))
         |> assign(:flash_msg, {:success, "Artículo agregado"})}

      {:error, _} ->
        {:noreply, assign(socket, :flash_msg, {:error, "No se pudo agregar el artículo"})}
    end
  end

  def handle_event("increment_item", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.order.order_items, &(to_string(&1.id) == id))

    if item do
      case Orders.update_item(item, %{quantity: item.quantity + 1}) do
        {:ok, _} ->
          {:noreply, assign(socket, :order, Orders.get_order!(socket.assigns.order.id))}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("decrement_item", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.order.order_items, &(to_string(&1.id) == id))

    if item && item.quantity > 1 do
      case Orders.update_item(item, %{quantity: item.quantity - 1}) do
        {:ok, _} ->
          {:noreply, assign(socket, :order, Orders.get_order!(socket.assigns.order.id))}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_item", %{"id" => id}, socket) do
    case Orders.remove_item(String.to_integer(id)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:order, Orders.get_order!(socket.assigns.order.id))
         |> assign(:flash_msg, {:success, "Artículo eliminado"})}

      {:error, _} ->
        {:noreply, assign(socket, :flash_msg, {:error, "No se pudo eliminar el artículo"})}
    end
  end

  def handle_event("send_to_kitchen", _params, socket) do
    case Orders.send_to_kitchen(socket.assigns.order) do
      {:ok, updated_order} ->
        {:noreply,
         socket
         |> assign(:order, Orders.get_order!(updated_order.id))
         |> assign(:flash_msg, {:success, "Comanda enviada a cocina y barra"})}

      {:error, _} ->
        {:noreply, assign(socket, :flash_msg, {:error, "No se pudo enviar la comanda"})}
    end
  end

  def handle_event("close_order", _params, socket) do
    case Orders.close_order(socket.assigns.order) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Cuenta cerrada.")
         |> redirect(to: "/mesa")}

      {:error, _} ->
        {:noreply, assign(socket, :flash_msg, {:error, "No se pudo cerrar la cuenta"})}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <SiteComponents.site_navbar nav_open={@nav_open} current_page={:waiter} current_user={@current_user} />
    <div class="min-h-screen bg-base-200 pt-20 pb-10">
      <div class="max-w-6xl mx-auto px-4 space-y-4">

        <%!-- Header --%>
        <div class="flex items-center gap-3 flex-wrap">
          <a href="/mesa" class="btn btn-ghost btn-sm gap-1">
            <.icon name="hero-arrow-left" class="size-4" />
            Comandas
          </a>
          <div class="flex-1">
            <h1 class="text-xl font-bold text-base-content">
              {@order.customer_name}
            </h1>
          </div>
          <.order_status_badge status={@order.status} />
        </div>

        <%!-- Flash message --%>
        <%= if @flash_msg do %>
          <% {type, msg} = @flash_msg %>
          <div class={["alert alert-sm", if(type == :success, do: "alert-success", else: "alert-error")]}>
            <span class="text-sm">{msg}</span>
          </div>
        <% end %>

        <%!-- Main layout: order panel + menu browser --%>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">

          <%!-- Left panel: current order items --%>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm">
            <div class="px-4 py-3 border-b border-base-300">
              <h2 class="font-semibold text-base-content">Comanda</h2>
              <p class="text-xs text-base-content/50 mt-0.5">
                {length(@order.order_items)} {if length(@order.order_items) == 1, do: "artículo", else: "artículos"}
              </p>
            </div>

            <div class="divide-y divide-base-200">
              <%= if @order.order_items == [] do %>
                <div class="py-12 text-center text-base-content/40 text-sm">
                  La comanda está vacía. Agrega artículos del menú.
                </div>
              <% else %>
                <%= for item <- @order.order_items do %>
                  <div class="flex items-center gap-3 px-4 py-3">
                    <div class="flex-1 min-w-0">
                      <p class="text-sm font-medium text-base-content truncate">
                        {item.menu_item.name}
                      </p>
                      <p class="text-xs text-base-content/50">
                        ${format_price(item.menu_item.price)} c/u
                        · <span class={station_text_class(item.menu_item.category.kind)}>
                          {station_label(item.menu_item.category.kind)}
                        </span>
                      </p>
                    </div>

                    <%!-- Quantity controls — available on any non-closed order --%>
                    <div class="flex items-center gap-1">
                      <button
                        class="btn btn-xs btn-ghost btn-circle"
                        phx-click="decrement_item"
                        phx-value-id={item.id}
                        disabled={item.quantity <= 1 or @order.status == "closed"}
                      >
                        <.icon name="hero-minus" class="size-3" />
                      </button>
                      <span class="w-6 text-center text-sm font-semibold">{item.quantity}</span>
                      <button
                        class="btn btn-xs btn-ghost btn-circle"
                        phx-click="increment_item"
                        phx-value-id={item.id}
                        disabled={@order.status == "closed"}
                      >
                        <.icon name="hero-plus" class="size-3" />
                      </button>
                    </div>

                    <%!-- Item status badge — always visible once order has been sent --%>
                    <%= if @order.status in ["sent", "ready"] do %>
                      <.item_status_badge status={item.status} />
                    <% end %>

                    <%!-- Remove button --%>
                    <button
                      class="btn btn-xs btn-ghost btn-circle text-error"
                      phx-click="remove_item"
                      phx-value-id={item.id}
                      disabled={@order.status == "closed"}
                    >
                      <.icon name="hero-trash" class="size-3.5" />
                    </button>
                  </div>
                <% end %>
              <% end %>
            </div>

            <%!-- Action buttons --%>
            <div class="px-4 py-4 border-t border-base-300 flex flex-col gap-2">
              <%!-- Send button: only active when there are pending (unsent) items --%>
              <button
                class="btn btn-primary w-full"
                phx-click="send_to_kitchen"
                disabled={pending_items(@order) == [] or @order.status == "closed"}
              >
                <.icon name="hero-paper-airplane" class="size-4" />
                <%= if @order.status == "open" do %>
                  Enviar a cocina y barra
                <% else %>
                  Enviar adicionales
                <% end %>
              </button>

              <%= if @order.status not in ["closed"] and @order.order_items != [] do %>
                <button
                  class="btn btn-outline btn-error w-full"
                  phx-click="close_order"
                >
                  Cerrar cuenta
                </button>
              <% end %>
            </div>
          </div>

          <%!-- Right panel: menu browser --%>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm flex flex-col">
            <div class="px-4 py-3 border-b border-base-300">
              <h2 class="font-semibold text-base-content">Menú</h2>
            </div>

            <%!-- Category tabs --%>
            <div class="flex gap-1 overflow-x-auto px-4 py-3 border-b border-base-200">
              <%= for category <- @categories do %>
                <button
                  class={["btn btn-xs", if(@selected_category_id == category.id, do: "btn-primary", else: "btn-ghost")]}
                  phx-click="select_category"
                  phx-value-id={category.id}
                  disabled={@order.status == "closed"}
                >
                  {category.name}
                </button>
              <% end %>
            </div>

            <%!-- Menu items grid --%>
            <div class="flex-1 overflow-y-auto p-4">
              <%= if @order.status == "closed" do %>
                <p class="text-center py-12 text-base-content/40 text-sm">
                  Esta cuenta está cerrada.
                </p>
              <% else %>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <%= for menu_item <- @menu_items do %>
                    <div class="bg-base-200/60 rounded-xl p-3 flex flex-col gap-2">
                      <div class="flex items-start justify-between gap-2">
                        <p class="text-sm font-medium text-base-content leading-snug">{menu_item.name}</p>
                        <span class="text-sm font-bold text-primary whitespace-nowrap">${format_price(menu_item.price)}</span>
                      </div>
                      <button
                        class="btn btn-xs btn-outline btn-primary w-full"
                        phx-click="add_item"
                        phx-value-menu_item_id={menu_item.id}
                      >
                        Agregar
                      </button>
                    </div>
                  <% end %>

                  <%= if @menu_items == [] do %>
                    <p class="col-span-2 text-center py-8 text-base-content/40 text-sm">
                      No hay artículos en esta categoría.
                    </p>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Status badge components
  # ---------------------------------------------------------------------------

  attr :status, :string, required: true

  defp order_status_badge(%{status: "open"} = assigns) do
    ~H"<span class='badge badge-info'>Abierta</span>"
  end

  defp order_status_badge(%{status: "sent"} = assigns) do
    ~H"<span class='badge badge-warning'>En cocina / barra</span>"
  end

  defp order_status_badge(%{status: "ready"} = assigns) do
    ~H"<span class='badge badge-success'>Lista</span>"
  end

  defp order_status_badge(%{status: "closed"} = assigns) do
    ~H"<span class='badge badge-ghost'>Cerrada</span>"
  end

  defp order_status_badge(assigns) do
    ~H"<span class='badge'>{@status}</span>"
  end

  attr :status, :string, required: true

  defp item_status_badge(%{status: "pending"} = assigns) do
    ~H"<span class='badge badge-xs badge-ghost'>Sin enviar</span>"
  end

  defp item_status_badge(%{status: "sent"} = assigns) do
    ~H"<span class='badge badge-xs badge-warning'>En preparación</span>"
  end

  defp item_status_badge(%{status: "ready"} = assigns) do
    ~H"<span class='badge badge-xs badge-success'>Listo</span>"
  end

  defp item_status_badge(assigns) do
    ~H"<span class='badge badge-xs badge-ghost'>{@status}</span>"
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_menu_items_for_category(category_id) do
    Catalog.list_menu_items()
    |> Enum.filter(&(&1.category_id == category_id))
  end

  defp format_price(%Decimal{} = price) do
    price |> Decimal.round(0) |> Decimal.to_string()
  end

  defp format_price(price), do: "#{price}"

  defp pending_items(order), do: Enum.filter(order.order_items, &(&1.status == "pending"))

  defp station_label("drink"), do: "Barra"
  defp station_label("food"), do: "Cocina"
  defp station_label(_), do: "Cocina"

  defp station_text_class("drink"), do: "text-info font-medium"
  defp station_text_class(_), do: "text-warning font-medium"
end
