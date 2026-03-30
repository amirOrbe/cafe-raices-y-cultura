defmodule CRCWeb.Waiter.OrderLive do
  @moduledoc "Order-taking LiveView per customer account. Allows adding, editing, and sending a comanda to cocina/barra."

  use CRCWeb, :live_view

  alias CRC.Orders
  alias CRC.Catalog
  alias CRCWeb.Components.SiteComponents

  @tick_interval 30_000
  # Items with this many or fewer portions remaining show a low-stock warning badge
  @low_stock_threshold 5
  @overdue_secs 15 * 60

  @impl true
  def mount(%{"id" => order_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
      Phoenix.PubSub.subscribe(CRC.PubSub, "menu_stock")
      Process.send_after(self(), :tick, @tick_interval)
    end

    order = Orders.get_order!(order_id)
    categories = Catalog.list_categories()
    first_category = List.first(categories)

    menu_items =
      if first_category do
        Catalog.list_menu_items_for_category_with_stock(first_category.id)
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
      |> assign(:selected_menu_item, nil)
      |> assign(:extras, [])
      |> assign(:flash_msg, nil)
      |> assign(:nav_open, false)
      |> assign(:payment_step, false)
      |> assign(:payment_method, nil)
      |> assign(:amount_paid_input, "")
      |> assign(:change_due, nil)
      |> assign(:cancelling_item, nil)
      |> assign(:now, DateTime.utc_now())
      |> assign(:low_stock_threshold, @low_stock_threshold)

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

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_interval)
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  def handle_info(:stock_updated, socket) do
    # A comanda was sent somewhere — reload menu with updated availability
    socket =
      if socket.assigns.selected_category_id do
        items = Catalog.list_menu_items_for_category_with_stock(socket.assigns.selected_category_id)
        assign(socket, :menu_items, items)
      else
        socket
      end

    # Also refresh extras if a menu item is currently selected
    socket =
      if socket.assigns.selected_menu_item do
        mi = socket.assigns.selected_menu_item
        extras = Catalog.list_extras_for_menu_item(mi.id, mi.category_id)
        assign(socket, :extras, extras)
      else
        socket
      end

    {:noreply, socket}
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
    menu_items = Catalog.list_menu_items_for_category_with_stock(category_id)

    {:noreply,
     socket
     |> assign(:selected_category_id, category_id)
     |> assign(:menu_items, menu_items)
     |> assign(:selected_menu_item, nil)
     |> assign(:extras, [])}
  end

  def handle_event("clear_extras", _params, socket) do
    {:noreply, socket |> assign(:selected_menu_item, nil) |> assign(:extras, [])}
  end

  def handle_event("select_menu_item_extras", %{"id" => id}, socket) do
    menu_item_id = String.to_integer(id)
    # Find the menu item struct from the already-loaded list
    menu_item =
      socket.assigns.menu_items
      |> Enum.find_value(fn {mi, _in_stock?} -> if mi.id == menu_item_id, do: mi end)

    if menu_item do
      extras = Catalog.list_extras_for_menu_item(menu_item.id, menu_item.category_id)

      {:noreply,
       socket
       |> assign(:selected_menu_item, menu_item)
       |> assign(:extras, extras)}
    else
      {:noreply, socket}
    end
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

  def handle_event("add_extra", %{"product_id" => product_id_str, "portion_qty" => portion_qty_str}, socket) do
    product_id = String.to_integer(product_id_str)
    portion_qty = Decimal.new(portion_qty_str)
    order = socket.assigns.order
    # Capture which dish this extra belongs to so cocina/barra knows where it goes
    for_menu_item_id = socket.assigns[:selected_menu_item] && socket.assigns.selected_menu_item.id

    # Merge only if same product, same parent dish, and still pending
    existing_pending =
      Enum.find(order.order_items, fn oi ->
        oi.product_id == product_id and
          oi.status == "pending" and
          oi.for_menu_item_id == for_menu_item_id
      end)

    result =
      if existing_pending do
        Orders.update_item(existing_pending, %{quantity: existing_pending.quantity + 1})
      else
        Orders.add_item(%{
          order_id: order.id,
          product_id: product_id,
          portion_quantity: portion_qty,
          quantity: 1,
          for_menu_item_id: for_menu_item_id
        })
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:order, Orders.get_order!(order.id))
         |> assign(:flash_msg, {:success, "Extra agregado"})}

      {:error, _} ->
        {:noreply, assign(socket, :flash_msg, {:error, "No se pudo agregar el extra"})}
    end
  end

  @doc """
  Toggles an ingredient exclusion on a pending order item.
  Only allowed while the item is still pending (before send_to_kitchen).
  """
  def handle_event(
        "toggle_exclusion",
        %{"order_item_id" => oi_id_str, "product_id" => prod_id_str},
        socket
      ) do
    order_item_id = String.to_integer(oi_id_str)
    product_id = String.to_integer(prod_id_str)
    order = socket.assigns.order

    # Guard: only pending items may be modified
    item = Enum.find(order.order_items, &(&1.id == order_item_id))

    if item && item.status == "pending" do
      case Orders.toggle_exclusion(order_item_id, product_id) do
        {:ok, _} ->
          {:noreply, assign(socket, :order, Orders.get_order!(order.id))}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
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

  def handle_event("request_cancel_item", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.order.order_items, &(to_string(&1.id) == id))
    {:noreply, assign(socket, :cancelling_item, item)}
  end

  def handle_event("dismiss_cancel", _params, socket) do
    {:noreply, assign(socket, :cancelling_item, nil)}
  end

  def handle_event("cancel_with_restore", _params, socket) do
    item = socket.assigns.cancelling_item

    case Orders.cancel_item(item, :not_prepared) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:cancelling_item, nil)
         |> assign(:order, Orders.get_order!(socket.assigns.order.id))
         |> assign(:flash_msg, {:success, "Artículo cancelado — stock restaurado"})}

      {:error, _} ->
        {:noreply, assign(socket, :flash_msg, {:error, "No se pudo cancelar el artículo"})}
    end
  end

  def handle_event("cancel_as_waste", _params, socket) do
    item = socket.assigns.cancelling_item

    case Orders.cancel_item(item, :waste) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:cancelling_item, nil)
         |> assign(:order, Orders.get_order!(socket.assigns.order.id))
         |> assign(:flash_msg, {:success, "Artículo marcado como desperdicio"})}

      {:error, _} ->
        {:noreply, assign(socket, :flash_msg, {:error, "No se pudo cancelar el artículo"})}
    end
  end

  def handle_event("mark_item_served", %{"id" => id}, socket) do
    item_id = String.to_integer(id)
    order = socket.assigns.order
    user_id = socket.assigns.current_user.id

    case Orders.mark_item_served(item_id, user_id) do
      {:ok, served_item} ->
        # If this is a menu item, auto-serve all linked extras regardless of status
        if served_item.menu_item_id do
          order.order_items
          |> Enum.filter(fn oi ->
            oi.for_menu_item_id == served_item.menu_item_id and
              oi.status not in ["served", "cancelled", "cancelled_waste"] and
              oi.id != served_item.id
          end)
          |> Enum.each(fn oi -> Orders.mark_item_served(oi.id, user_id) end)
        end

        {:noreply, assign(socket, :order, Orders.get_order!(order.id))}

      {:error, _} ->
        {:noreply, assign(socket, :flash_msg, {:error, "No se pudo marcar como servido"})}
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

  def handle_event("show_payment_step", _params, socket) do
    {:noreply, assign(socket, :payment_step, true)}
  end

  def handle_event("cancel_payment", _params, socket) do
    {:noreply,
     socket
     |> assign(:payment_step, false)
     |> assign(:payment_method, nil)
     |> assign(:amount_paid_input, "")
     |> assign(:change_due, nil)}
  end

  def handle_event("set_payment_method", %{"method" => method}, socket) do
    {:noreply,
     socket
     |> assign(:payment_method, method)
     |> assign(:amount_paid_input, "")
     |> assign(:change_due, nil)}
  end

  def handle_event("update_amount_paid", %{"value" => value}, socket) do
    total = Orders.calculate_order_total(socket.assigns.order)

    change =
      case Decimal.parse(value) do
        {amount, ""} ->
          diff = Decimal.sub(amount, total)
          diff

        _ ->
          nil
      end

    {:noreply,
     socket
     |> assign(:amount_paid_input, value)
     |> assign(:change_due, change)}
  end

  def handle_event("confirm_close_order", _params, socket) do
    order = socket.assigns.order
    method = socket.assigns.payment_method

    amount_paid =
      if method == "efectivo" do
        case Decimal.parse(socket.assigns.amount_paid_input) do
          {d, ""} -> d
          _ -> nil
        end
      else
        nil
      end

    case Orders.close_order(order, %{payment_method: method, amount_paid: amount_paid}, socket.assigns.current_user.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Cuenta cerrada.")
         |> redirect(to: "/mesa")}

      {:error, changeset} ->
        msg =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
          |> Enum.join(", ")

        {:noreply, assign(socket, :flash_msg, {:error, "Error al cerrar: #{msg}"})}
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

        <%!-- Drinks-ready banner --%>
        <%= if drinks_ready_food_pending?(@order) do %>
          <div class="alert alert-info py-2 flex items-center gap-2">
            <.icon name="hero-beaker" class="size-4 shrink-0" />
            <span class="text-sm font-medium">
              {count_ready_drinks(@order)} bebida(s) lista(s) en barra — puedes recogerlas ahora
            </span>
          </div>
        <% end %>

        <%!-- All ready banner --%>
        <%= if all_active_items_ready?(@order) and @order.status != "closed" do %>
          <div class="alert alert-success py-2 flex items-center gap-2">
            <.icon name="hero-check-circle" class="size-4 shrink-0" />
            <span class="text-sm font-medium">¡Todo listo! Sirve la comanda.</span>
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

            <%!-- Cancel dialog — shown when mesero taps trash on a sent/ready item --%>
            <%= if @cancelling_item do %>
              <% ci = @cancelling_item %>
              <div class="mx-4 mt-3 mb-1 rounded-xl border border-error/40 bg-error/5 p-4 space-y-3">
                <p class="text-sm font-semibold text-base-content">
                  Cancelar: <%= if ci.product_id, do: "Extra — #{ci.product.name}", else: ci.menu_item.name %>
                </p>
                <p class="text-xs text-base-content/60">
                  ¿Este artículo ya fue preparado en cocina o barra?
                </p>
                <div class="flex flex-col gap-2">
                  <button
                    class="btn btn-sm btn-error w-full"
                    phx-click="cancel_as_waste"
                  >
                    <.icon name="hero-fire" class="size-4" />
                    Sí — ya fue preparado (desperdicio)
                  </button>
                  <button
                    class="btn btn-sm btn-outline w-full"
                    phx-click="cancel_with_restore"
                  >
                    <.icon name="hero-arrow-uturn-left" class="size-4" />
                    No — no fue preparado (restaurar stock)
                  </button>
                  <button
                    class="btn btn-sm btn-ghost w-full text-base-content/50"
                    phx-click="dismiss_cancel"
                  >
                    Mantener artículo
                  </button>
                </div>
              </div>
            <% end %>

            <div class="divide-y divide-base-200">
              <%= if @order.order_items == [] do %>
                <div class="py-12 text-center text-base-content/40 text-sm">
                  La comanda está vacía. Agrega artículos del menú.
                </div>
              <% else %>
                <%= for item <- sort_items_for_display(@order.order_items) do %>
                  <% cancelled? = item.status in ["cancelled", "cancelled_waste"] %>
                  <% served? = item.status == "served" %>
                  <% overdue? = item_overdue?(item, @now) %>
                  <div class={["flex items-center gap-3 px-4 py-3",
                    cond do
                      cancelled? -> "opacity-40"
                      served? -> "opacity-40 bg-base-200/40"
                      overdue? -> "bg-error/5"
                      item.status == "ready" -> "bg-success/5"
                      true -> ""
                    end
                  ]}>
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-1.5 flex-wrap">
                        <p class={["text-sm font-medium text-base-content", if(cancelled?, do: "line-through")]}>
                          <%= if item.product_id do %>
                            <span class="text-accent font-semibold">Extra:</span> {item.product.name}
                          <% else %>
                            {item.menu_item.name}
                          <% end %>
                        </p>
                        <%= if overdue? do %>
                          <span class="badge badge-xs badge-error gap-0.5 animate-pulse shrink-0">
                            <.icon name="hero-clock" class="size-2.5" /> +15 min
                          </span>
                        <% end %>
                        <%= if item.status == "ready" and not cancelled? do %>
                          <span class="badge badge-xs badge-success animate-pulse shrink-0">¡Listo!</span>
                        <% end %>
                        <%= if served? do %>
                          <span class="badge badge-xs badge-ghost shrink-0">Servido</span>
                        <% end %>
                      </div>
                      <p class="text-xs text-base-content/50">
                        <%= if cancelled? do %>
                          <span class="text-error font-medium">
                            {if item.status == "cancelled_waste", do: "Cancelado — desperdicio", else: "Cancelado — stock restaurado"}
                          </span>
                        <% else %>
                          <%= if item.product_id do %>
                            <%= if item.portion_quantity do %>
                              <span class="font-medium">{format_qty(item.portion_quantity)} {item.product.unit}</span>
                              ·
                            <% end %>
                            <span class="text-warning font-medium">Cocina</span>
                          <% else %>
                            ${format_price(item.menu_item.price)} c/u
                            · <span class={station_text_class(item.menu_item.category.kind)}>
                              {station_label(item.menu_item.category.kind)}
                            </span>
                          <% end %>
                        <% end %>
                      </p>

                      <%!-- Ingredient modifier toggles (pending menu items with a recipe) --%>
                      <%= if item.status == "pending" and not is_nil(item.menu_item_id) and item.menu_item.menu_item_ingredients != [] do %>
                        <div class="flex flex-wrap items-center gap-1 mt-1.5 pt-1.5 border-t border-base-200">
                          <span class="text-xs text-base-content/40 shrink-0">Quitar:</span>
                          <%= for mii <- item.menu_item.menu_item_ingredients do %>
                            <% excl? = Enum.any?(item.exclusions, &(&1.product_id == mii.product_id)) %>
                            <button
                              phx-click="toggle_exclusion"
                              phx-value-order_item_id={item.id}
                              phx-value-product_id={mii.product_id}
                              class={[
                                "badge badge-sm cursor-pointer transition-all select-none",
                                if(excl?, do: "badge-error line-through", else: "badge-ghost hover:badge-warning")
                              ]}
                            >
                              {mii.product.name}
                            </button>
                          <% end %>
                        </div>
                      <% end %>

                      <%!-- Read-only exclusion badges for sent/ready/served items --%>
                      <%= if item.status in ["sent", "ready"] and item.exclusions != [] do %>
                        <div class="flex flex-wrap items-center gap-1 mt-1.5">
                          <span class="text-xs text-warning font-semibold shrink-0">Sin:</span>
                          <%= for excl <- item.exclusions do %>
                            <span class="badge badge-xs badge-warning">{excl.product.name}</span>
                          <% end %>
                        </div>
                      <% end %>
                    </div>

                    <%!-- "Servir" button — only for ready items --%>
                    <%= if item.status == "ready" and @order.status != "closed" do %>
                      <button
                        class="btn btn-xs btn-success gap-1 shrink-0"
                        phx-click="mark_item_served"
                        phx-value-id={item.id}
                      >
                        <.icon name="hero-check" class="size-3" />
                        Servir
                      </button>
                    <% end %>

                    <%!-- Quantity controls — only for non-served, non-cancelled items --%>
                    <%= if !cancelled? and !served? do %>
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
                    <% end %>

                    <%!-- Cancel button — pending and sent/ready only --%>
                    <%= if !cancelled? and !served? and @order.status != "closed" do %>
                      <%= if item.status == "pending" do %>
                        <button
                          class="btn btn-xs btn-ghost btn-circle text-error"
                          phx-click="remove_item"
                          phx-value-id={item.id}
                        >
                          <.icon name="hero-trash" class="size-3.5" />
                        </button>
                      <% else %>
                        <button
                          class="btn btn-xs btn-ghost btn-circle text-error"
                          phx-click="request_cancel_item"
                          phx-value-id={item.id}
                        >
                          <.icon name="hero-x-circle" class="size-3.5" />
                        </button>
                      <% end %>
                    <% end %>
                  </div>
                <% end %>
              <% end %>
            </div>

            <%!-- Action buttons --%>
            <div class="px-4 py-4 border-t border-base-300 flex flex-col gap-2">

              <%!-- Running total --%>
              <%= if @order.order_items != [] do %>
                <% total = Orders.calculate_order_total(@order) %>
                <div class="flex items-center justify-between px-1">
                  <span class="text-sm text-base-content/60">Total:</span>
                  <span class="text-xl font-bold text-primary">${format_price(total)}</span>
                </div>
              <% end %>

              <%!-- Send button --%>
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

              <%!-- Close / payment flow --%>
              <%= if @order.status not in ["closed"] and @order.order_items != [] do %>
                <%= if !@payment_step do %>
                  <button
                    class="btn btn-outline btn-error w-full"
                    phx-click="show_payment_step"
                  >
                    <.icon name="hero-credit-card" class="size-4" />
                    Cobrar y cerrar cuenta
                  </button>
                <% else %>
                  <%!-- Inline payment panel --%>
                  <% total = Orders.calculate_order_total(@order) %>
                  <div class="bg-base-200 rounded-xl p-4 space-y-3 border border-base-300">
                    <div class="flex items-center justify-between">
                      <h3 class="font-semibold text-sm text-base-content">Cobro</h3>
                      <button class="btn btn-xs btn-ghost" phx-click="cancel_payment">
                        <.icon name="hero-x-mark" class="size-3.5" />
                      </button>
                    </div>

                    <%!-- Total reminder --%>
                    <div class="text-center py-1">
                      <p class="text-xs text-base-content/50">Total a cobrar</p>
                      <p class="text-3xl font-bold text-primary">${format_price(total)}</p>
                    </div>

                    <%!-- Method selector --%>
                    <div class="grid grid-cols-3 gap-1.5">
                      <%= for {label, value, icon} <- [
                        {"Efectivo", "efectivo", "hero-banknotes"},
                        {"Tarjeta", "tarjeta", "hero-credit-card"},
                        {"Transfer.", "transferencia", "hero-device-phone-mobile"}
                      ] do %>
                        <button
                          class={["btn btn-sm flex-col h-auto py-2 gap-1",
                            if(@payment_method == value, do: "btn-primary", else: "btn-outline btn-ghost")]}
                          phx-click="set_payment_method"
                          phx-value-method={value}
                        >
                          <.icon name={icon} class="size-4" />
                          <span class="text-xs">{label}</span>
                        </button>
                      <% end %>
                    </div>

                    <%!-- Cash amount input + change --%>
                    <%= if @payment_method == "efectivo" do %>
                      <div class="space-y-2">
                        <label class="text-xs text-base-content/60 font-medium">
                          ¿Con cuánto paga el cliente?
                        </label>
                        <input
                          type="number"
                          inputmode="decimal"
                          step="10"
                          min="0"
                          class="input input-bordered input-sm w-full text-lg font-semibold"
                          placeholder={"Mín. $#{format_price(total)}"}
                          value={@amount_paid_input}
                          phx-keyup="update_amount_paid"
                          phx-value-value={@amount_paid_input}
                          phx-debounce="150"
                        />
                        <%= if @change_due do %>
                          <div class={["flex items-center justify-between rounded-lg px-3 py-2",
                            if(Decimal.lt?(@change_due, Decimal.new(0)),
                              do: "bg-error/10 border border-error/30",
                              else: "bg-success/10 border border-success/30")]}>
                            <span class="text-sm font-medium">
                              {if Decimal.lt?(@change_due, Decimal.new(0)), do: "Falta:", else: "Cambio:"}
                            </span>
                            <span class={["text-xl font-bold",
                              if(Decimal.lt?(@change_due, Decimal.new(0)), do: "text-error", else: "text-success")]}>
                              ${ @change_due |> Decimal.abs() |> format_price() }
                            </span>
                          </div>
                        <% end %>
                      </div>
                    <% end %>

                    <%!-- Confirm button --%>
                    <% can_confirm? =
                      @payment_method != nil and
                      (@payment_method != "efectivo" or
                        (@change_due != nil and not Decimal.lt?(@change_due, Decimal.new(0)))) %>
                    <button
                      class={["btn w-full", if(can_confirm?, do: "btn-success", else: "btn-disabled")]}
                      phx-click="confirm_close_order"
                      disabled={!can_confirm?}
                    >
                      <.icon name="hero-check-circle" class="size-5" />
                      Confirmar cobro
                    </button>
                  </div>
                <% end %>
              <% end %>

            </div>
          </div>

          <%!-- Right panel: menu browser + extras --%>
          <div class="space-y-4">

            <%!-- Menu browser --%>
            <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm flex flex-col">
              <div class="px-4 py-3 border-b border-base-300 flex items-center justify-between gap-2">
                <h2 class="font-semibold text-base-content">Menú</h2>
                <%!-- Stock legend --%>
                <span class="text-xs text-base-content/40 hidden sm:block">
                  <span class="inline-flex items-center gap-1">
                    <span class="size-2 rounded-full bg-error/60 inline-block"></span>Sin inventario
                  </span>
                </span>
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
                    <%!-- portions: nil=sin receta (ilimitado), 0=agotado, n=porciones restantes --%>
                    <%= for {menu_item, portions} <- @menu_items do %>
                      <% selected?   = @selected_menu_item && @selected_menu_item.id == menu_item.id %>
                      <% available?  = is_nil(portions) or portions > 0 %>
                      <% low_stock?  = not is_nil(portions) and portions > 0 and portions <= @low_stock_threshold %>
                      <div class={[
                        "rounded-xl p-3 flex flex-col gap-2 border transition-all",
                        cond do
                          selected?   -> "bg-accent/10 border-accent"
                          not available? -> "bg-base-100 border-error/20 opacity-60"
                          low_stock?  -> "bg-warning/5 border-warning/40"
                          true        -> "bg-base-200/60 border-transparent"
                        end
                      ]}>
                        <div class="flex items-start justify-between gap-2">
                          <div class="flex-1 min-w-0">
                            <p class="text-sm font-medium text-base-content leading-snug">
                              {menu_item.name}
                            </p>
                            <%!-- Agotado --%>
                            <%= if not available? do %>
                              <p class="text-xs text-error mt-0.5 flex items-center gap-0.5">
                                <.icon name="hero-x-circle" class="size-3 shrink-0" />
                                Agotado
                              </p>
                            <%!-- Bajo stock: warning con porciones exactas --%>
                            <% else %>
                              <%= if low_stock? do %>
                                <p class="text-xs text-warning font-semibold mt-0.5 flex items-center gap-0.5">
                                  <.icon name="hero-exclamation-triangle" class="size-3 shrink-0" />
                                  {if portions == 1, do: "¡Es el último!", else: "¡Solo quedan #{portions}!"}
                                </p>
                              <% end %>
                            <% end %>
                          </div>
                          <span class="text-sm font-bold text-primary whitespace-nowrap shrink-0">
                            ${format_price(menu_item.price)}
                          </span>
                        </div>
                        <div class="flex gap-1.5">
                          <button
                            class={[
                              "btn btn-xs flex-1",
                              cond do
                                not available? -> "btn-disabled"
                                low_stock?     -> "btn-warning"
                                true           -> "btn-outline btn-primary"
                              end
                            ]}
                            phx-click="add_item"
                            phx-value-menu_item_id={menu_item.id}
                            disabled={not available?}
                          >
                            {cond do
                              not available? -> "Agotado"
                              low_stock? and portions == 1 -> "¡Agregar — último!"
                              low_stock? -> "Agregar"
                              true -> "Agregar"
                            end}
                          </button>
                          <button
                            class={[
                              "btn btn-xs",
                              if(selected?, do: "btn-accent", else: "btn-ghost btn-outline")
                            ]}
                            phx-click="select_menu_item_extras"
                            phx-value-id={menu_item.id}
                            title="Ver extras de este platillo"
                          >
                            <.icon name="hero-plus-circle" class="size-3.5" />
                          </button>
                        </div>
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

            <%!-- Extras del platillo seleccionado --%>
            <%= if @selected_menu_item && @order.status != "closed" do %>
              <div class="bg-base-100 rounded-2xl border border-accent/30 shadow-sm">
                <div class="px-4 py-3 border-b border-accent/20 flex items-start justify-between gap-2">
                  <div>
                    <h2 class="font-semibold text-base-content flex items-center gap-2">
                      <.icon name="hero-plus-circle" class="size-4 text-accent" />
                      Extras — {@selected_menu_item.name}
                    </h2>
                    <p class="text-xs text-base-content/50 mt-0.5">
                      Toca un ingrediente para agregarlo como extra a la comanda
                    </p>
                  </div>
                  <button
                    class="btn btn-xs btn-ghost"
                    phx-click="clear_extras"
                  >
                    <.icon name="hero-x-mark" class="size-3.5" />
                  </button>
                </div>
                <div class="p-4">
                  <div class="flex flex-wrap gap-2">
                    <%= for {product, portion_qty} <- @extras do %>
                      <button
                        class="btn btn-sm btn-outline btn-accent gap-1.5"
                        phx-click="add_extra"
                        phx-value-product_id={product.id}
                        phx-value-portion_qty={Decimal.to_string(portion_qty)}
                      >
                        <.icon name="hero-plus" class="size-3" />
                        {product.name}
                        <span class="text-xs opacity-70">
                          {format_qty(portion_qty)} {product.unit}
                        </span>
                      </button>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>

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

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp format_price(%Decimal{} = price) do
    price |> Decimal.round(0) |> Decimal.to_string()
  end

  defp format_price(price), do: "#{price}"

  # Formats a quantity removing trailing zeros without scientific notation.
  # e.g. 120.000 → "120", 0.500 → "0.5", 40.000 → "40"
  defp format_qty(%Decimal{} = qty) do
    str = qty |> Decimal.round(3) |> Decimal.to_string()

    if String.contains?(str, ".") do
      str |> String.trim_trailing("0") |> String.trim_trailing(".")
    else
      str
    end
  end

  defp format_qty(qty), do: "#{qty}"

  defp pending_items(order), do: Enum.filter(order.order_items, &(&1.status == "pending"))

  # Active = not yet terminal; served and cancelled items are excluded from business logic.
  defp active_items(order),
    do: Enum.filter(order.order_items, &(&1.status not in ["cancelled", "cancelled_waste", "served"]))

  # Sort for display: ready items first (need immediate action), then in-progress,
  # then served (greyed out at bottom), then cancelled (terminal, very bottom).
  defp sort_items_for_display(items) do
    rank = fn
      "ready" -> 0
      "pending" -> 1
      "sent" -> 2
      "served" -> 3
      _ -> 4
    end

    Enum.sort_by(items, fn item -> rank.(item.status) end)
  end

  defp drinks_ready_food_pending?(order) do
    active = active_items(order)
    drinks = Enum.filter(active, &item_is_drink?/1)
    food = Enum.filter(active, &(not item_is_drink?(&1)))

    drinks != [] and
      Enum.all?(drinks, &(&1.status == "ready")) and
      Enum.any?(food, &(&1.status in ["pending", "sent"]))
  end

  defp all_active_items_ready?(order) do
    active = active_items(order)
    active != [] and Enum.all?(active, &(&1.status == "ready"))
  end

  defp count_ready_drinks(order) do
    order.order_items
    |> Enum.filter(&(&1.status == "ready" and item_is_drink?(&1)))
    |> length()
  end

  defp item_is_drink?(%{menu_item: %{category: %{kind: "drink"}}}), do: true
  defp item_is_drink?(_), do: false

  defp item_overdue?(%{status: "sent", sent_at: sent_at}, now) when not is_nil(sent_at) do
    DateTime.diff(now, sent_at, :second) > @overdue_secs
  end

  defp item_overdue?(_, _), do: false

  defp station_label("drink"), do: "Barra"
  defp station_label("food"), do: "Cocina"
  defp station_label(_), do: "Cocina"

  defp station_text_class("drink"), do: "text-info font-medium"
  defp station_text_class(_), do: "text-warning font-medium"
end
