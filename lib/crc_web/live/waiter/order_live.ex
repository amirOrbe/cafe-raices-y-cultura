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
    packages = Catalog.list_packages()

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
      |> assign(:packages, packages)
      |> assign(:selected_category_id, first_category && first_category.id)
      |> assign(:menu_tab, :menu)
      |> assign(:menu_items, menu_items)
      |> assign(:selected_menu_item, nil)
      |> assign(:extras, [])
      |> assign(:flash_msg, nil)
      |> assign(:nav_open, false)
      |> assign(:payment_step, false)
      |> assign(:payment_method, nil)
      |> assign(:amount_paid_input, "")
      |> assign(:change_due, nil)
      |> assign(:split_count, nil)
      |> assign(:split_input, "")
      |> assign(:cancelling_item, nil)
      |> assign(:now, DateTime.utc_now())
      |> assign(:low_stock_threshold, @low_stock_threshold)
      |> assign(:seen_ready_ids, ready_item_ids(order))
      |> assign(:bill_modal, false)
      |> assign(:menu_search, "")
      |> assign(:search_results, nil)

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
      new_order = Orders.get_order!(order_id)
      new_ids = ready_item_ids(new_order)
      new_ready? = not MapSet.subset?(new_ids, socket.assigns.seen_ready_ids)

      socket =
        socket
        |> assign(:order, new_order)
        |> assign(:seen_ready_ids, new_ids)

      socket =
        if new_ready?, do: push_event(socket, "play_sound", %{type: "item_ready"}), else: socket

      {:noreply, socket}
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
        items =
          Catalog.list_menu_items_for_category_with_stock(socket.assigns.selected_category_id)

        assign(socket, :menu_items, items)
      else
        socket
      end

    # Also refresh extras if a menu item is currently selected
    socket =
      if socket.assigns.selected_menu_item do
        mi = socket.assigns.selected_menu_item
        extras = Catalog.list_recipe_ingredients(mi.id)
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

  # Generates a bill token (if not yet set) and opens the bill modal.
  def handle_event("generate_bill", _params, socket) do
    order = socket.assigns.order

    if order.bill_token do
      {:noreply, assign(socket, :bill_modal, true)}
    else
      case Orders.generate_bill_token(order) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:order, Orders.get_order!(order.id))
           |> assign(:bill_modal, true)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "No se pudo generar la cuenta.")}
      end
    end
  end

  def handle_event("close_bill_modal", _params, socket) do
    {:noreply, assign(socket, :bill_modal, false)}
  end

  # Cross-category menu search — triggers on every keystroke (debounced in template).
  def handle_event("search_menu", %{"query" => q}, socket) do
    q = String.trim(q)

    if q == "" do
      {:noreply, socket |> assign(:menu_search, "") |> assign(:search_results, nil)}
    else
      results = Catalog.search_menu_items(q)
      {:noreply, socket |> assign(:menu_search, q) |> assign(:search_results, results)}
    end
  end

  def handle_event("clear_menu_search", _params, socket) do
    {:noreply, socket |> assign(:menu_search, "") |> assign(:search_results, nil)}
  end

  def handle_event("select_menu_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :menu_tab, String.to_existing_atom(tab))}
  end

  def handle_event("select_category", %{"id" => id}, socket) do
    category_id = String.to_integer(id)

    if socket.assigns.selected_category_id == category_id do
      {:noreply,
       socket
       |> assign(:selected_category_id, nil)
       |> assign(:menu_items, [])
       |> assign(:selected_menu_item, nil)
       |> assign(:extras, [])}
    else
      menu_items = Catalog.list_menu_items_for_category_with_stock(category_id)

      {:noreply,
       socket
       |> assign(:selected_category_id, category_id)
       |> assign(:menu_items, menu_items)
       |> assign(:selected_menu_item, nil)
       |> assign(:extras, [])}
    end
  end

  def handle_event("add_package", %{"package_id" => package_id_str}, socket) do
    package_id = String.to_integer(package_id_str)
    order = socket.assigns.order

    case Orders.add_package(%{order_id: order.id, package_id: package_id}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:order, Orders.get_order!(order.id))
         |> assign(:flash_msg, {:success, "Paquete agregado"})}

      {:error, :package_not_found} ->
        {:noreply, assign(socket, :flash_msg, {:error, "Paquete no encontrado"})}

      {:error, :package_inactive} ->
        {:noreply, assign(socket, :flash_msg, {:error, "Paquete no disponible"})}

      {:error, _} ->
        {:noreply, assign(socket, :flash_msg, {:error, "No se pudo agregar el paquete"})}
    end
  end

  def handle_event("clear_extras", _params, socket) do
    {:noreply, socket |> assign(:selected_menu_item, nil) |> assign(:extras, [])}
  end

  def handle_event("select_menu_item_extras", %{"id" => id}, socket) do
    menu_item_id = String.to_integer(id)

    # Try the already-loaded category list first; fall back to a DB fetch so
    # that the extras button on order item rows works regardless of which
    # category is currently visible in the catalog panel.
    menu_item =
      socket.assigns.menu_items
      |> Enum.find_value(fn {mi, _in_stock?} -> if mi.id == menu_item_id, do: mi end)
      |> then(fn
        nil -> CRC.Repo.get(CRC.Catalog.MenuItem, menu_item_id) |> CRC.Repo.preload(:category)
        mi -> mi
      end)

    if menu_item do
      extras = Catalog.list_recipe_ingredients(menu_item.id)

      {:noreply,
       socket
       |> assign(:selected_menu_item, menu_item)
       |> assign(:extras, extras)}
    else
      {:noreply, socket}
    end
  end

  # Repeat an existing order item — adds a new pending unit of the same menu item.
  # Merges with an existing pending item if one exists, otherwise creates a new one.
  def handle_event("repeat_item", %{"menu_item_id" => menu_item_id_str}, socket) do
    menu_item_id = String.to_integer(menu_item_id_str)
    order = socket.assigns.order

    existing_pending =
      Enum.find(order.order_items, fn oi ->
        oi.menu_item_id == menu_item_id and oi.status == "pending"
      end)

    result =
      if existing_pending do
        Orders.update_item(existing_pending, %{quantity: existing_pending.quantity + 1})
      else
        Orders.add_item(%{order_id: order.id, menu_item_id: menu_item_id, quantity: 1})
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:order, Orders.get_order!(order.id))
         |> assign(:flash_msg, {:success, "Artículo repetido"})}

      {:error, _} ->
        {:noreply, assign(socket, :flash_msg, {:error, "No se pudo repetir el artículo"})}
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

  def handle_event(
        "add_extra",
        %{"product_id" => product_id_str, "portion_qty" => portion_qty_str} = params,
        socket
      ) do
    product_id = String.to_integer(product_id_str)
    portion_qty = Decimal.new(portion_qty_str)
    order = socket.assigns.order
    # Capture which dish this extra belongs to so cocina/barra knows where it goes
    for_menu_item_id = socket.assigns[:selected_menu_item] && socket.assigns.selected_menu_item.id

    # Customer-facing price for this extra: sale_price × portion_qty (nil or 0 = no charge)
    unit_price =
      case Map.get(params, "sale_price") do
        nil -> nil
        "0" -> nil
        str ->
          d = Decimal.new(str)
          if Decimal.compare(d, Decimal.new(0)) == :gt,
            do: Decimal.mult(d, portion_qty) |> Decimal.round(2),
            else: nil
      end

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
          unit_price: unit_price,
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

  def handle_event(
        "select_variant",
        %{"menu_item_id" => mi_id, "variant_id" => v_id, "product_id" => p_id},
        socket
      ) do
    menu_item_id = String.to_integer(mi_id)
    variant_id = String.to_integer(v_id)
    product_id = String.to_integer(p_id)
    order = socket.assigns.order

    # Find any existing variant selection for this ingredient + dish combination
    existing = find_selected_variant(order.order_items, menu_item_id, product_id)

    # Remove the old selection (if any)
    if existing, do: Orders.remove_item(existing.id)

    # Toggle: clicking the already-selected variant deselects it
    already_selected? = existing && existing.variant_id == variant_id

    unless already_selected? do
      variant = CRC.Inventory.get_variant!(variant_id)

      Orders.add_item(%{
        order_id: order.id,
        variant_id: variant_id,
        for_menu_item_id: menu_item_id,
        unit_price: variant.extra_charge,
        quantity: 1
      })
    end

    {:noreply, assign(socket, :order, Orders.get_order!(order.id))}
  end

  def handle_event("set_item_note", %{"item_id" => id, "note" => note}, socket) do
    order_item_id = String.to_integer(id)
    order = socket.assigns.order

    item = Enum.find(order.order_items, &(&1.id == order_item_id))

    if item && item.status == "pending" do
      case Orders.set_item_notes(order_item_id, note) do
        {:ok, _} ->
          {:noreply, assign(socket, :order, Orders.get_order!(order.id))}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_item_for_person", %{"item_id" => id, "for_person" => for_person}, socket) do
    order_item_id = String.to_integer(id)
    order = socket.assigns.order
    item = Enum.find(order.order_items, &(&1.id == order_item_id))

    if item && item.status == "pending" do
      case Orders.set_item_for_person(order_item_id, for_person) do
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
      # Check available stock before incrementing so the waiter gets immediate
      # feedback instead of a confusing error at send-to-kitchen time.
      max_qty = item_max_quantity(item)

      if max_qty != nil and item.quantity >= max_qty do
        {:noreply,
         assign(socket, :flash_msg,
           {:error,
            "Sin stock suficiente para agregar más «#{item_display_name(item)}». Solo quedan #{max_qty} porciones."}
         )}
      else
        case Orders.update_item(item, %{quantity: item.quantity + 1}) do
          {:ok, _} ->
            {:noreply, assign(socket, :order, Orders.get_order!(socket.assigns.order.id))}

          {:error, _} ->
            {:noreply, socket}
        end
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

  def handle_event("cancel_order", _params, socket) do
    order = socket.assigns.order

    if order.order_items == [] and order.status == "open" do
      CRC.Repo.delete(order)
      {:noreply, redirect(socket, to: "/mesa")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_order_type", %{"type" => type}, socket)
      when type in ["dine_in", "takeout"] do
    order = socket.assigns.order

    case Orders.update_order(order, %{order_type: type}) do
      {:ok, _updated} ->
        updated = Orders.get_order!(order.id)
        Phoenix.PubSub.broadcast(CRC.PubSub, "orders", {:order_updated, order.id})
        {:noreply, assign(socket, :order, updated)}

      {:error, _} ->
        {:noreply, assign(socket, :flash_msg, {:error, "No se pudo actualizar el tipo de orden."})}
    end
  end

  def handle_event("send_to_kitchen", _params, socket) do
    case Orders.send_to_kitchen(socket.assigns.order) do
      {:ok, updated_order} ->
        {:noreply,
         socket
         |> assign(:order, Orders.get_order!(updated_order.id))
         |> assign(:flash_msg, {:success, "Comanda enviada a cocina y barra"})}

      {:error, {:insufficient_stock, name}} ->
        {:noreply,
         socket
         |> assign(:flash_msg, {:error, "Sin stock suficiente de «#{name}». Otro mesero lo agotó al mismo tiempo."})}

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
     |> assign(:change_due, nil)
     |> assign(:split_count, nil)
     |> assign(:split_input, "")}
  end

  def handle_event("update_split_input", %{"value" => value}, socket) do
    count =
      case Integer.parse(value) do
        {n, ""} when n >= 2 -> n
        _ -> nil
      end

    {:noreply,
     socket
     |> assign(:split_input, value)
     |> assign(:split_count, count)}
  end

  def handle_event("clear_split", _params, socket) do
    {:noreply, socket |> assign(:split_count, nil) |> assign(:split_input, "")}
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

    case Orders.close_order(
           order,
           %{payment_method: method, amount_paid: amount_paid},
           socket.assigns.current_user.id
         ) do
      {:ok, closed_order} ->
        # Pre-generate the bill token so the QR is ready whenever the waiter
        # needs to show it — but don't auto-open the modal; let them tap the button.
        closed_with_token =
          case Orders.generate_bill_token(closed_order) do
            {:ok, o} -> o
            _ -> closed_order
          end

        {:noreply,
         socket
         |> assign(:order, Orders.get_order!(closed_with_token.id))
         |> assign(:payment_step, false)
         |> assign(:flash_msg, {:success, "Cuenta cerrada · usa «Mostrar QR» si el cliente lo pide"})}

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
    <SiteComponents.site_navbar
      nav_open={@nav_open}
      current_page={:waiter}
      current_user={@current_user}
    />
    <div id="sound-notifier" phx-hook="SoundNotifier" class="hidden"></div>
    <div class="min-h-screen bg-base-200 pt-20 pb-10">
      <div class="max-w-6xl mx-auto px-4 space-y-4">
        <%!-- Header --%>
        <div class="flex items-start gap-3 min-w-0">
          <a href="/mesa" class="btn btn-ghost btn-sm gap-1 shrink-0 mt-0.5">
            <.icon name="hero-arrow-left" class="size-4" /> Comandas
          </a>
          <div class="flex-1 min-w-0">
            <%!-- Nombre + badge de estado en la misma línea --%>
            <div class="flex items-center gap-2 min-w-0">
              <h1 class="text-xl font-bold text-base-content truncate min-w-0 flex-1">
                {@order.customer_name}
              </h1>
              <span class="shrink-0"><.order_status_badge status={@order.status} /></span>
            </div>
            <div class="flex items-center gap-1.5 mt-0.5 flex-wrap">
              <%!-- Toggle de tipo de orden (editable si no está cerrada) --%>
              <%= if @order.status != "closed" do %>
                <div class="join" data-order-type={@order.order_type}>
                  <button
                    class={[
                      "btn btn-xs join-item gap-1",
                      if(@order.order_type == "dine_in",
                        do: "btn-primary",
                        else: "btn-ghost border border-base-300"
                      )
                    ]}
                    phx-click="set_order_type"
                    phx-value-type="dine_in"
                  >
                    <.icon name="hero-building-storefront" class="size-3" /> En el lugar
                  </button>
                  <button
                    class={[
                      "btn btn-xs join-item gap-1",
                      if(@order.order_type == "takeout",
                        do: "btn-accent",
                        else: "btn-ghost border border-base-300"
                      )
                    ]}
                    phx-click="set_order_type"
                    phx-value-type="takeout"
                  >
                    <.icon name="hero-shopping-bag" class="size-3" /> Para llevar
                  </button>
                </div>
              <% else %>
                <%!-- Cuenta cerrada: solo badge de lectura --%>
                <%= if @order.order_type == "takeout" do %>
                  <span class="badge badge-xs badge-accent gap-1">
                    <.icon name="hero-shopping-bag" class="size-3" /> Para llevar
                  </span>
                <% end %>
              <% end %>
              <%= if @order.is_group do %>
                <span class="badge badge-xs badge-ghost gap-1">
                  <.icon name="hero-user-group" class="size-3" /> Grupo
                </span>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Flash message --%>
        <%= if @flash_msg do %>
          <% {type, msg} = @flash_msg %>
          <div class={[
            "alert alert-sm",
            if(type == :success, do: "alert-success", else: "alert-error")
          ]}>
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
              <div class="flex items-center justify-between gap-2">
                <h2 class="font-semibold text-base-content">Comanda</h2>
                <%!-- Status summary strip --%>
                <% pending_count = Enum.count(@order.order_items, &(&1.status == "pending")) %>
                <% sent_count = Enum.count(@order.order_items, &(&1.status == "sent")) %>
                <% ready_count = Enum.count(@order.order_items, &(&1.status == "ready")) %>
                <div class="flex items-center gap-1.5 flex-wrap justify-end">
                  <%= if pending_count > 0 do %>
                    <span class="badge badge-xs badge-warning gap-0.5">
                      <span class="size-1.5 rounded-full bg-warning-content/70 inline-block"></span>
                      {pending_count} pend.
                    </span>
                  <% end %>
                  <%= if sent_count > 0 do %>
                    <span class="badge badge-xs badge-info gap-0.5">
                      <span class="size-1.5 rounded-full bg-info-content/70 inline-block"></span>
                      {sent_count} cocina
                    </span>
                  <% end %>
                  <%= if ready_count > 0 do %>
                    <span class="badge badge-xs badge-success gap-0.5 animate-pulse">
                      <span class="size-1.5 rounded-full bg-success-content/70 inline-block"></span>
                      {ready_count} ✓
                    </span>
                  <% end %>
                </div>
              </div>
            </div>

            <%!-- Cancel dialog — shown when mesero taps trash on a sent/ready item --%>
            <%= if @cancelling_item do %>
              <% ci = @cancelling_item %>
              <div class="mx-4 mt-3 mb-1 rounded-xl border border-error/40 bg-error/5 p-4 space-y-3">
                <p class="text-sm font-semibold text-base-content">
                  Cancelar: {if ci.product_id,
                    do: "Extra — #{ci.product.name}",
                    else: ci.menu_item.name}
                </p>
                <p class="text-xs text-base-content/60">
                  ¿Este artículo ya fue preparado en cocina o barra?
                </p>
                <div class="flex flex-col gap-2">
                  <button
                    class="btn btn-sm btn-error w-full"
                    phx-click="cancel_as_waste"
                  >
                    <.icon name="hero-fire" class="size-4" /> Sí — ya fue preparado (desperdicio)
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

            <%!-- Pre-compute distinct person identifiers already used in this order --%>
            <% used_persons =
              @order.order_items
              |> Enum.map(& &1.for_person)
              |> Enum.reject(&(is_nil(&1) or &1 == ""))
              |> Enum.uniq() %>

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
                  <%!-- Color-coded left border by status for at-a-glance scanning --%>
                  <div class={[
                    "flex items-center gap-3 px-4 py-4 border-l-[3px]",
                    cond do
                      cancelled? -> "opacity-40 border-l-base-300"
                      served? -> "opacity-40 bg-base-200/40 border-l-base-300"
                      overdue? -> "bg-error/5 border-l-error"
                      item.status == "ready" -> "bg-success/5 border-l-success"
                      item.status == "sent" -> "bg-info/5 border-l-info"
                      item.status == "pending" -> "border-l-warning"
                      true -> "border-l-transparent"
                    end
                  ]}>
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-1.5 flex-wrap">
                        <p class={[
                          "text-sm font-medium text-base-content",
                          if(cancelled?, do: "line-through")
                        ]}>
                          <%= if item.product_id do %>
                            <span class="text-accent font-semibold">Extra:</span> {item.product.name}
                          <% else %>
                            {item.menu_item.name}
                          <% end %>
                        </p>
                        <%!-- "Para quién" badge — shown when set, for all statuses --%>
                        <%= if item.for_person && item.for_person != "" do %>
                          <span class="badge badge-xs badge-ghost gap-0.5 shrink-0">
                            👤 {item.for_person}
                          </span>
                        <% end %>
                        <%= if item.package_id do %>
                          <span class="badge badge-xs badge-primary gap-0.5 mt-0.5">
                            <.icon name="hero-gift" class="size-2.5" /> Paquete
                          </span>
                        <% end %>
                        <%= if overdue? do %>
                          <span class="badge badge-xs badge-error gap-0.5 animate-pulse shrink-0">
                            <.icon name="hero-clock" class="size-2.5" /> +15 min
                          </span>
                        <% end %>
                        <%= if item.status == "ready" and not cancelled? do %>
                          <span class="badge badge-xs badge-success animate-pulse shrink-0">
                            ¡Listo!
                          </span>
                        <% end %>
                        <%= if served? do %>
                          <span class="badge badge-xs badge-ghost shrink-0">Servido</span>
                        <% end %>
                      </div>
                      <p class="text-xs text-base-content/50">
                        <%= if cancelled? do %>
                          <span class="text-error font-medium">
                            {if item.status == "cancelled_waste",
                              do: "Cancelado — desperdicio",
                              else: "Cancelado — stock restaurado"}
                          </span>
                        <% else %>
                          <%= if item.product_id do %>
                            <%= if item.portion_quantity do %>
                              <span class="font-medium">
                                {format_qty(item.portion_quantity)} {item.product.unit}
                              </span>
                              ·
                            <% end %>
                            <span class="text-warning font-medium">Cocina</span>
                          <% else %>
                            ${format_price(item.unit_price || item.menu_item.price)} c/u
                            ·
                            <span class={station_text_class(item.menu_item.destination)}>
                              {station_label(item.menu_item.destination)}
                            </span>
                          <% end %>
                        <% end %>
                      </p>

                      <%!-- "Para quién" input — editable only while pending --%>
                      <%= if item.status == "pending" do %>
                        <div class="mt-1.5 pt-1.5 border-t border-base-200 space-y-1">
                          <%!-- Quick-pick chips from already-entered persons in this order --%>
                          <%= if used_persons != [] do %>
                            <div class="flex gap-1 flex-wrap">
                              <%= for person <- used_persons do %>
                                <button
                                  type="button"
                                  class={[
                                    "badge badge-xs cursor-pointer transition-all select-none",
                                    if(item.for_person == person,
                                      do: "badge-primary",
                                      else: "badge-ghost hover:badge-primary"
                                    )
                                  ]}
                                  phx-click="set_item_for_person"
                                  phx-value-item_id={item.id}
                                  phx-value-for_person={person}
                                >
                                  👤 {person}
                                </button>
                              <% end %>
                              <%= if item.for_person && item.for_person != "" do %>
                                <button
                                  type="button"
                                  class="badge badge-xs badge-ghost cursor-pointer hover:badge-error select-none"
                                  phx-click="set_item_for_person"
                                  phx-value-item_id={item.id}
                                  phx-value-for_person=""
                                >
                                  ✕
                                </button>
                              <% end %>
                            </div>
                          <% end %>
                          <form phx-change="set_item_for_person">
                            <input type="hidden" name="item_id" value={item.id} />
                            <div class="flex items-center gap-1.5">
                              <span class="text-sm shrink-0 leading-none select-none">👤</span>
                              <input
                                type="text"
                                name="for_person"
                                maxlength="50"
                                class="input input-xs flex-1 border-base-300 text-xs placeholder-base-content/30"
                                placeholder="¿Para quién? ej: señora, gorra roja…"
                                value={item.for_person || ""}
                                phx-debounce="600"
                              />
                            </div>
                          </form>
                        </div>
                      <% end %>

                      <%!-- Ingredient modifier toggles + variant selectors (pending menu items) --%>
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
                                if(excl?,
                                  do: "badge-error line-through",
                                  else: "badge-ghost hover:badge-warning"
                                )
                              ]}
                            >
                              {mii.product.name}
                            </button>
                          <% end %>
                        </div>
                        <%!-- One variant-selector row per ingredient that has active types --%>
                        <%= for mii <- item.menu_item.menu_item_ingredients do %>
                          <% active_variants = Enum.filter(mii.product.variants, & &1.active) %>
                          <%= if active_variants != [] do %>
                            <% sel =
                              find_selected_variant(
                                @order.order_items,
                                item.menu_item_id,
                                mii.product_id
                              ) %>
                            <div class="flex flex-wrap items-center gap-1 mt-1 pt-1 border-t border-base-200/60">
                              <span class="text-xs text-base-content/40 shrink-0">
                                {mii.product.name}:
                              </span>
                              <%= for variant <- active_variants do %>
                                <% selected? = sel != nil and sel.variant_id == variant.id %>
                                <button
                                  phx-click="select_variant"
                                  phx-value-menu_item_id={item.menu_item_id}
                                  phx-value-variant_id={variant.id}
                                  phx-value-product_id={mii.product_id}
                                  class={[
                                    "badge badge-sm cursor-pointer transition-all select-none",
                                    if(selected?,
                                      do: "badge-primary",
                                      else: "badge-ghost hover:badge-primary"
                                    )
                                  ]}
                                >
                                  {variant.name}
                                  <%= if Decimal.compare(variant.extra_charge, Decimal.new(0)) == :gt do %>
                                    <span class="opacity-60 ml-0.5">
                                      +${format_price(variant.extra_charge)}
                                    </span>
                                  <% end %>
                                </button>
                              <% end %>
                            </div>
                          <% end %>
                        <% end %>
                      <% end %>

                      <%!-- Read-only variant badges for sent/ready items --%>
                      <% sent_variants = get_variant_items(@order.order_items, item) %>
                      <%= if item.status in ["sent", "ready"] and sent_variants != [] do %>
                        <div class="flex flex-wrap items-center gap-1 mt-1.5">
                          <%= for vi <- sent_variants do %>
                            <span class="badge badge-xs badge-primary">{vi.variant.name}</span>
                            <%= if vi.unit_price && Decimal.compare(vi.unit_price, Decimal.new(0)) == :gt do %>
                              <span class="text-xs text-primary font-medium">
                                +${format_price(vi.unit_price)}
                              </span>
                            <% end %>
                          <% end %>
                        </div>
                      <% end %>

                      <%!-- Note input — editable for pending menu items --%>
                      <%= if item.status == "pending" and not is_nil(item.menu_item_id) do %>
                        <form
                          phx-change="set_item_note"
                          class="mt-1.5 pt-1.5 border-t border-base-200"
                        >
                          <input type="hidden" name="item_id" value={item.id} />
                          <div class="flex items-center gap-1.5">
                            <span class="text-sm shrink-0 leading-none select-none">📝</span>
                            <input
                              type="text"
                              name="note"
                              class="input input-xs flex-1 border-base-300 text-xs placeholder-base-content/30"
                              placeholder="Nota para cocina (ej: término medio)…"
                              value={item.notes || ""}
                              phx-debounce="600"
                            />
                          </div>
                        </form>
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

                      <%!-- Read-only note display for sent/ready items --%>
                      <%= if item.status in ["sent", "ready"] and not is_nil(item.notes) and item.notes != "" do %>
                        <div class="flex items-center gap-1 mt-1.5">
                          <span class="text-xs shrink-0 select-none">📝</span>
                          <p class="text-xs text-base-content/60 italic">{item.notes}</p>
                        </div>
                      <% end %>
                    </div>

                    <%!-- "Servir" button — only for ready items --%>
                    <%= if item.status == "ready" and @order.status != "closed" do %>
                      <button
                        class="btn btn-sm btn-success gap-1 shrink-0"
                        phx-click="mark_item_served"
                        phx-value-id={item.id}
                      >
                        <.icon name="hero-check" class="size-4" /> Servir
                      </button>
                    <% end %>

                    <%!-- "Extras" button — only on pending menu items (not extras/packages) --%>
                    <%= if not cancelled? and not served? and not is_nil(item.menu_item_id) and
                          is_nil(item.package_id) and item.status == "pending" and
                          @order.status != "closed" do %>
                      <button
                        class={[
                          "btn btn-sm btn-ghost btn-circle",
                          if(@selected_menu_item && @selected_menu_item.id == item.menu_item_id,
                            do: "text-accent",
                            else: "text-base-content/50"
                          )
                        ]}
                        phx-click="select_menu_item_extras"
                        phx-value-id={item.menu_item_id}
                        title="Agregar extras a este platillo"
                      >
                        <.icon name="hero-plus-circle" class="size-4" />
                      </button>
                    <% end %>

                    <%!-- "Repetir" button — for sent/ready menu items (not ingredient extras) --%>
                    <%= if not cancelled? and not served? and not is_nil(item.menu_item_id) and
                          item.status in ["sent", "ready"] and @order.status != "closed" do %>
                      <button
                        class="btn btn-sm btn-ghost btn-circle text-primary"
                        phx-click="repeat_item"
                        phx-value-menu-item-id={item.menu_item_id}
                        title="Repetir este artículo"
                      >
                        <.icon name="hero-arrow-path" class="size-4" />
                      </button>
                    <% end %>

                    <%!-- Quantity controls — only for non-served, non-cancelled items --%>
                    <%= if !cancelled? and !served? do %>
                      <div class="flex items-center gap-1">
                        <button
                          class="btn btn-sm btn-ghost btn-circle"
                          phx-click="decrement_item"
                          phx-value-id={item.id}
                          disabled={item.quantity <= 1 or @order.status == "closed"}
                        >
                          <.icon name="hero-minus" class="size-4" />
                        </button>
                        <span class="w-8 text-center text-base font-bold">{item.quantity}</span>
                        <% max_qty = item_max_quantity(item) %>
                        <button
                          class="btn btn-sm btn-ghost btn-circle"
                          phx-click="increment_item"
                          phx-value-id={item.id}
                          disabled={@order.status == "closed" or (max_qty != nil and item.quantity >= max_qty)}
                          title={if max_qty != nil and item.quantity >= max_qty, do: "Sin stock suficiente", else: nil}
                        >
                          <.icon name="hero-plus" class="size-4" />
                        </button>
                      </div>
                    <% end %>

                    <%!-- Cancel button — pending and sent/ready only --%>
                    <%= if !cancelled? and !served? and @order.status != "closed" do %>
                      <%= if item.status == "pending" do %>
                        <button
                          class="btn btn-sm btn-ghost btn-circle text-error"
                          phx-click="remove_item"
                          phx-value-id={item.id}
                        >
                          <.icon name="hero-trash" class="size-4" />
                        </button>
                      <% else %>
                        <button
                          class="btn btn-sm btn-ghost btn-circle text-error"
                          phx-click="request_cancel_item"
                          phx-value-id={item.id}
                        >
                          <.icon name="hero-x-circle" class="size-4" />
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

              <%!-- Send button — shows count of pending items --%>
              <% pending = pending_items(@order) %>
              <button
                class="btn btn-primary w-full"
                phx-click="send_to_kitchen"
                disabled={pending == [] or @order.status == "closed"}
              >
                <.icon name="hero-paper-airplane" class="size-4" />
                <%= if @order.status == "open" do %>
                  Enviar a cocina y barra
                <% else %>
                  Enviar adicionales
                <% end %>
                <%= if pending != [] do %>
                  <span class="badge badge-sm badge-primary-content/30 ml-1">
                    {length(pending)}
                  </span>
                <% end %>
              </button>

              <%!-- Cancelar comanda vacía — solo si no tiene artículos y está abierta --%>
              <%= if @order.order_items == [] and @order.status == "open" do %>
                <button
                  class="btn btn-outline btn-error w-full"
                  phx-click="cancel_order"
                  data-confirm="¿Cancelar esta comanda? Se eliminará y no podrá recuperarse."
                >
                  <.icon name="hero-x-mark" class="size-4" /> Cancelar comanda
                </button>
              <% end %>

              <%!-- Bill / QR modal trigger — solo cuando la cuenta está cerrada --%>
              <%= if @order.status == "closed" and @order.order_items != [] do %>
                <div class="flex gap-2">
                  <a href="/mesa" class="btn btn-ghost flex-1">
                    <.icon name="hero-arrow-left" class="size-4" /> Volver
                  </a>
                  <button
                    class="btn btn-accent flex-1"
                    phx-click="generate_bill"
                  >
                    <.icon name="hero-qr-code" class="size-4" /> Mostrar QR
                  </button>
                </div>
              <% end %>

              <%!-- Close / payment flow --%>
              <%= if @order.status not in ["closed"] and @order.order_items != [] do %>
                <%= if !@payment_step do %>
                  <button
                    class="btn btn-outline btn-error w-full"
                    phx-click="show_payment_step"
                  >
                    <.icon name="hero-credit-card" class="size-4" /> Cobrar y cerrar cuenta
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

                    <%!-- Total + split --%>
                    <div class="text-center py-1 space-y-2">
                      <p class="text-xs text-base-content/50">Total a cobrar</p>
                      <p class="text-3xl font-bold text-primary">${format_price(total)}</p>

                      <%!-- Split bill row --%>
                      <div class="flex items-center justify-center gap-2 mt-1">
                        <.icon name="hero-users" class="size-3.5 text-base-content/40" />
                        <span class="text-xs text-base-content/50">Dividir entre</span>
                        <input
                          type="number"
                          inputmode="numeric"
                          min="2"
                          max="20"
                          class="input input-xs input-bordered w-14 text-center"
                          placeholder="2"
                          value={@split_input}
                          phx-keyup="update_split_input"
                          phx-value-value={@split_input}
                          phx-debounce="200"
                        />
                        <span class="text-xs text-base-content/50">personas</span>
                        <%= if @split_count do %>
                          <button
                            class="btn btn-xs btn-ghost text-base-content/40"
                            phx-click="clear_split"
                            title="Quitar división"
                          >
                            <.icon name="hero-x-mark" class="size-3" />
                          </button>
                        <% end %>
                      </div>

                      <%= if @split_count do %>
                        <div class="bg-primary/10 rounded-lg px-4 py-2">
                          <p class="text-xs text-base-content/60">Corresponde a cada persona</p>
                          <p class="text-2xl font-bold text-primary">
                            ${format_price(Decimal.div(total, Decimal.new(@split_count)))}
                          </p>
                          <p class="text-xs text-base-content/40">
                            ({@split_count} personas · total ${format_price(total)})
                          </p>
                        </div>
                      <% end %>
                    </div>

                    <%!-- Method selector --%>
                    <div class="grid grid-cols-3 gap-1.5">
                      <%= for {label, value, icon} <- [
                        {"Efectivo", "efectivo", "hero-banknotes"},
                        {"Tarjeta", "tarjeta", "hero-credit-card"},
                        {"Transfer.", "transferencia", "hero-device-phone-mobile"}
                      ] do %>
                        <button
                          class={[
                            "btn btn-sm flex-col h-auto py-2 gap-1",
                            if(@payment_method == value,
                              do: "btn-primary",
                              else: "btn-outline btn-ghost"
                            )
                          ]}
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
                          <div class={[
                            "flex items-center justify-between rounded-lg px-3 py-2",
                            if(Decimal.lt?(@change_due, Decimal.new(0)),
                              do: "bg-error/10 border border-error/30",
                              else: "bg-success/10 border border-success/30"
                            )
                          ]}>
                            <span class="text-sm font-medium">
                              {if Decimal.lt?(@change_due, Decimal.new(0)),
                                do: "Falta:",
                                else: "Cambio:"}
                            </span>
                            <span class={[
                              "text-xl font-bold",
                              if(Decimal.lt?(@change_due, Decimal.new(0)),
                                do: "text-error",
                                else: "text-success"
                              )
                            ]}>
                              ${@change_due |> Decimal.abs() |> format_price()}
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
                      <.icon name="hero-check-circle" class="size-5" /> Confirmar cobro
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
                <%!-- Main tab switcher: Menú / Paquetes --%>
                <div class="flex gap-1">
                  <button
                    class={[
                      "btn btn-sm",
                      if(@menu_tab == :menu, do: "btn-primary", else: "btn-ghost")
                    ]}
                    phx-click="select_menu_tab"
                    phx-value-tab="menu"
                  >
                    Menú
                  </button>
                  <button
                    class={[
                      "btn btn-sm gap-1",
                      if(@menu_tab == :packages, do: "btn-primary", else: "btn-ghost")
                    ]}
                    phx-click="select_menu_tab"
                    phx-value-tab="packages"
                  >
                    <.icon name="hero-gift" class="size-3.5" /> Paquetes
                    <%= if @packages != [] do %>
                      <span class="badge badge-xs">{length(@packages)}</span>
                    <% end %>
                  </button>
                </div>
                <%!-- Stock legend (menu tab only) --%>
                <%= if @menu_tab == :menu do %>
                  <span class="text-xs text-base-content/40 hidden sm:block">
                    <span class="inline-flex items-center gap-1">
                      <span class="size-2 rounded-full bg-error/60 inline-block"></span>Sin inventario
                    </span>
                  </span>
                <% end %>
              </div>

              <%= if @menu_tab == :menu do %>
                <%!-- Search bar — wrapped in form so phx-change fires with name key --%>
                <form phx-change="search_menu" class="px-4 py-2 border-b border-base-200">
                  <div class="relative">
                    <.icon name="hero-magnifying-glass" class="absolute left-2.5 top-1/2 -translate-y-1/2 size-4 text-base-content/30 pointer-events-none" />
                    <input
                      type="text"
                      name="query"
                      value={@menu_search}
                      placeholder="Buscar platillo o bebida…"
                      class="input input-sm input-bordered w-full pl-8 pr-8"
                      phx-debounce="200"
                      autocomplete="off"
                      disabled={@order.status == "closed"}
                    />
                    <%= if @menu_search != "" do %>
                      <button
                        type="button"
                        class="absolute right-2 top-1/2 -translate-y-1/2 text-base-content/30 hover:text-base-content"
                        phx-click="clear_menu_search"
                      >
                        <.icon name="hero-x-mark" class="size-4" />
                      </button>
                    <% end %>
                  </div>
                </form>

                <%= if @order.status == "closed" do %>
                  <div class="flex-1 flex items-center justify-center">
                    <p class="text-center py-12 text-base-content/40 text-sm">
                      Esta cuenta está cerrada.
                    </p>
                  </div>
                <% else %>
                  <%= if @search_results != nil do %>
                    <%!-- Search results --%>
                    <div class="flex-1 overflow-y-auto p-3">
                      <p class="text-xs text-base-content/40 mb-3">
                        <%= if @search_results == [] do %>
                          Sin resultados para "<span class="font-semibold">{@menu_search}</span>"
                        <% else %>
                          {length(@search_results)} resultado(s)
                        <% end %>
                      </p>
                      <div class="grid grid-cols-2 gap-2">
                        <%= for {menu_item, portions} <- @search_results do %>
                          <% count = if is_nil(portions), do: nil, else: portions.count %>
                          <% bottleneck = if is_nil(portions), do: nil, else: portions.bottleneck %>
                          <% available? = is_nil(count) or count > 0 %>
                          <% low_stock? = not is_nil(count) and count > 0 and count <= @low_stock_threshold %>
                          <div class={["rounded-xl p-3 flex flex-col gap-2 border transition-all",
                            cond do
                              not available? -> "bg-base-100 border-error/20 opacity-60"
                              low_stock? -> "bg-warning/5 border-warning/40"
                              true -> "bg-base-200/60 border-transparent"
                            end]}>
                            <div class="flex items-start justify-between gap-2">
                              <div class="flex-1 min-w-0">
                                <p class="text-sm font-medium text-base-content leading-snug">{menu_item.name}</p>
                                <%= if not available? do %>
                                  <p class="text-xs text-error mt-0.5 flex items-center gap-1">
                                    <.icon name="hero-x-circle" class="size-3 shrink-0" />
                                    {if bottleneck, do: "Agotado · sin #{bottleneck}", else: "Agotado"}
                                  </p>
                                <% else %>
                                  <%= if low_stock? do %>
                                    <p class="text-xs text-warning font-semibold mt-0.5 flex items-center gap-1">
                                      <.icon name="hero-exclamation-triangle" class="size-3 shrink-0" />
                                      {cond do
                                        count == 1 and bottleneck -> "¡Solo sale 1! · se acaba #{bottleneck}"
                                        count == 1 -> "¡Es el último!"
                                        bottleneck -> "¡Solo salen #{count}! · se acaba #{bottleneck}"
                                        true -> "¡Solo quedan #{count}!"
                                      end}
                                    </p>
                                  <% end %>
                                <% end %>
                              </div>
                              <span class="text-sm font-bold text-primary whitespace-nowrap shrink-0">
                                ${format_price(menu_item.price)}
                              </span>
                            </div>
                            <button
                              class={["btn btn-xs w-full", cond do
                                not available? -> "btn-disabled"
                                low_stock? -> "btn-warning"
                                true -> "btn-outline btn-primary"
                              end]}
                              phx-click="add_item"
                              phx-value-menu_item_id={menu_item.id}
                              disabled={not available?}
                            >
                              {if not available?, do: "Agotado", else: "Agregar"}
                            </button>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% else %>
                    <%!-- Category button grid --%>
                    <div class="grid grid-cols-2 gap-1.5 p-3 border-b border-base-200 max-h-44 overflow-y-auto shrink-0">
                      <%= for category <- @categories do %>
                        <% has_items? = length(category.menu_items) > 0 %>
                        <button
                          class={[
                            "btn btn-sm justify-between gap-1 w-full",
                            if(@selected_category_id == category.id,
                              do: "btn-primary",
                              else: "btn-ghost border border-base-300"),
                            if(not has_items?, do: "opacity-40", else: "")
                          ]}
                          phx-click="select_category"
                          phx-value-id={category.id}
                          disabled={@order.status == "closed" or not has_items?}
                        >
                          <span class="truncate text-left flex-1">{category.name}</span>
                          <span class={[
                            "badge badge-xs shrink-0",
                            if(@selected_category_id == category.id,
                              do: "badge-primary-content/40",
                              else: "badge-ghost")
                          ]}>
                            {length(category.menu_items)}
                          </span>
                        </button>
                      <% end %>
                    </div>

                    <%!-- Items for selected category --%>
                    <div class="flex-1 overflow-y-auto p-3">
                      <%= if is_nil(@selected_category_id) do %>
                        <p class="text-center py-10 text-base-content/40 text-sm">
                          Selecciona una categoría
                        </p>
                      <% else %>
                        <div class="grid grid-cols-2 gap-2">
                          <%= for {menu_item, portions} <- @menu_items do %>
                            <% count = if is_nil(portions), do: nil, else: portions.count %>
                            <% bottleneck = if is_nil(portions), do: nil, else: portions.bottleneck %>
                            <% available? = is_nil(count) or count > 0 %>
                            <% low_stock? = not is_nil(count) and count > 0 and count <= @low_stock_threshold %>
                            <div class={["rounded-xl p-3 flex flex-col gap-2 border transition-all",
                              cond do
                                not available? -> "bg-base-100 border-error/20 opacity-60"
                                low_stock? -> "bg-warning/5 border-warning/40"
                                true -> "bg-base-200/60 border-transparent"
                              end]}>
                              <div class="flex items-start justify-between gap-2">
                                <div class="flex-1 min-w-0">
                                  <p class="text-sm font-medium text-base-content leading-snug">{menu_item.name}</p>
                                  <%= if not available? do %>
                                    <p class="text-xs text-error mt-0.5 flex items-center gap-1">
                                      <.icon name="hero-x-circle" class="size-3 shrink-0" />
                                      {if bottleneck, do: "Agotado · sin #{bottleneck}", else: "Agotado"}
                                    </p>
                                  <% else %>
                                    <%= if low_stock? do %>
                                      <p class="text-xs text-warning font-semibold mt-0.5 flex items-center gap-1">
                                        <.icon name="hero-exclamation-triangle" class="size-3 shrink-0" />
                                        {cond do
                                          count == 1 and bottleneck -> "¡Solo sale 1! · se acaba #{bottleneck}"
                                          count == 1 -> "¡Es el último!"
                                          bottleneck -> "¡Solo salen #{count}! · se acaba #{bottleneck}"
                                          true -> "¡Solo quedan #{count}!"
                                        end}
                                      </p>
                                    <% end %>
                                  <% end %>
                                </div>
                                <span class="text-sm font-bold text-primary whitespace-nowrap shrink-0">
                                  ${format_price(menu_item.price)}
                                </span>
                              </div>
                              <button
                                class={["btn btn-xs w-full", cond do
                                  not available? -> "btn-disabled"
                                  low_stock? -> "btn-warning"
                                  true -> "btn-outline btn-primary"
                                end]}
                                phx-click="add_item"
                                phx-value-menu_item_id={menu_item.id}
                                disabled={not available?}
                              >
                                {if not available?, do: "Agotado", else: "Agregar"}
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
                  <% end %>
                <% end %>
              <% else %>
                <%!-- Packages grid --%>
                <div class="flex-1 overflow-y-auto p-4">
                  <%= if @order.status == "closed" do %>
                    <p class="text-center py-12 text-base-content/40 text-sm">
                      Esta cuenta está cerrada.
                    </p>
                  <% else %>
                    <%= if @packages == [] do %>
                      <p class="text-center py-12 text-base-content/40 text-sm">
                        No hay paquetes disponibles.
                      </p>
                    <% else %>
                      <div class="space-y-3">
                        <%= for package <- @packages do %>
                          <div class="rounded-xl border border-primary/20 bg-primary/5 p-3 flex items-start gap-3">
                            <div class="flex-1 min-w-0">
                              <p class="text-sm font-semibold text-base-content">{package.name}</p>
                              <%= if package.description do %>
                                <p class="text-xs text-base-content/50 mt-0.5">
                                  {package.description}
                                </p>
                              <% end %>
                              <div class="flex flex-wrap gap-1 mt-2">
                                <%= for pi <- package.package_items do %>
                                  <span class="badge badge-xs badge-ghost">
                                    <%= if pi.quantity > 1 do %>
                                      {pi.quantity}×
                                    <% end %>
                                    {pi.menu_item.name}
                                  </span>
                                <% end %>
                              </div>
                            </div>
                            <div class="flex flex-col items-end gap-2 shrink-0">
                              <span class="text-base font-bold text-primary">
                                ${format_price(package.price)}
                              </span>
                              <button
                                class="btn btn-xs btn-primary"
                                phx-click="add_package"
                                phx-value-package_id={package.id}
                              >
                                <.icon name="hero-plus" class="size-3" /> Agregar
                              </button>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              <% end %>
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
                      <% sale = product.sale_price %>
                      <% extra_price =
                        if sale && Decimal.compare(sale, Decimal.new(0)) == :gt,
                          do: Decimal.mult(sale, portion_qty) |> Decimal.round(2),
                          else: nil %>
                      <button
                        class="btn btn-sm btn-outline btn-accent gap-1.5"
                        phx-click="add_extra"
                        phx-value-product_id={product.id}
                        phx-value-portion_qty={Decimal.to_string(portion_qty)}
                        phx-value-sale_price={if sale, do: Decimal.to_string(sale), else: "0"}
                      >
                        <.icon name="hero-plus" class="size-3" />
                        {product.name}
                        <span class="text-xs opacity-70">
                          {format_qty(portion_qty)} {product.unit}
                          <%= if extra_price do %>
                            · ${ format_price(extra_price)}
                          <% end %>
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

    <%!-- ── Bill / QR modal ──────────────────────────────────────────────────── --%>
    <%= if @bill_modal do %>
      <%!-- Backdrop --%>
      <div
        class="fixed inset-0 z-40 bg-black/60"
        phx-click="close_bill_modal"
      >
      </div>
      <%!-- Modal card (above backdrop, click doesn't bubble) --%>
      <div class="fixed inset-0 z-50 flex items-center justify-center p-4 pointer-events-none">
        <div class="bg-base-100 rounded-2xl shadow-2xl w-full max-w-sm overflow-hidden pointer-events-auto">
          <%!-- Header --%>
          <div class="bg-primary text-primary-content px-5 py-4 flex items-center gap-3">
            <div class="flex-1 min-w-0">
              <h2 class="font-bold text-lg">Cuenta</h2>
              <p class="text-sm opacity-80 truncate">{@order.customer_name}</p>
            </div>
            <button phx-click="close_bill_modal" class="btn btn-sm btn-ghost text-primary-content shrink-0">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <div class="px-5 py-4 space-y-4 overflow-y-auto max-h-[70vh]">
            <%!-- Item list --%>
            <% bill_lines = bill_modal_items(@order) %>
            <%= if bill_lines != [] do %>
              <div class="divide-y divide-base-200 text-sm">
                <%= for line <- bill_lines do %>
                  <div class="flex items-baseline justify-between py-2 gap-2">
                    <div class="flex-1 min-w-0">
                      <span class="font-medium">{line.name}</span>
                      <span class="text-base-content/50 ml-1">{line.quantity}×</span>
                      <%= if line.for_person && line.for_person != "" do %>
                        <span class="text-base-content/40 text-xs block">👤 {line.for_person}</span>
                      <% end %>
                    </div>
                    <span class="font-semibold shrink-0">${format_price(line.subtotal)}</span>
                  </div>
                <% end %>
              </div>

              <%!-- Total --%>
              <div class="flex items-center justify-between border-t border-base-300 pt-3">
                <span class="font-semibold">Total</span>
                <span class="text-2xl font-bold text-primary">
                  ${format_price(Orders.calculate_order_total(@order))}
                </span>
              </div>
            <% end %>

            <%!-- QR code --%>
            <%= if @order.bill_token do %>
              <% cuenta_url = CRCWeb.Endpoint.url() <> ~p"/cuenta/#{@order.bill_token}" %>
              <div class="flex flex-col items-center gap-3 pt-2">
                <p class="text-xs text-base-content/50 text-center">
                  El cliente puede escanear este QR para ver su cuenta en tiempo real
                </p>
                <div class="bg-white p-3 rounded-xl border border-base-300 shadow-sm">
                  <img
                    src={"https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=#{URI.encode_www_form(cuenta_url)}"}
                    alt="QR cuenta"
                    class="w-48 h-48 block"
                  />
                </div>
                <p class="text-xs text-base-content/40 font-mono text-center break-all">
                  {cuenta_url}
                </p>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Status badge components
  # ---------------------------------------------------------------------------

  attr :status, :string, required: true

  defp order_status_badge(%{status: "open"} = assigns) do
    ~H'<span class="badge badge-info">Abierta</span>'
  end

  defp order_status_badge(%{status: "sent"} = assigns) do
    ~H'<span class="badge badge-warning">En cocina / barra</span>'
  end

  defp order_status_badge(%{status: "ready"} = assigns) do
    ~H'<span class="badge badge-success">Lista</span>'
  end

  defp order_status_badge(%{status: "closed"} = assigns) do
    ~H'<span class="badge badge-ghost">Cerrada</span>'
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Customer-visible bill lines: non-cancelled menu items with prices.
  # Excludes ingredient extras (product_id set) which have no customer-facing price.
  defp bill_modal_items(%{order_items: items}) do
    items
    |> Enum.filter(fn oi ->
      oi.status not in ["cancelled", "cancelled_waste"] and
        not is_nil(oi.menu_item_id) and not is_nil(oi.menu_item)
    end)
    |> Enum.map(fn oi ->
      unit_price = oi.unit_price || oi.menu_item.price
      %{
        name: oi.menu_item.name,
        for_person: oi.for_person,
        quantity: oi.quantity,
        unit_price: unit_price,
        subtotal: Decimal.mult(unit_price, Decimal.new(oi.quantity))
      }
    end)
  end

  defp format_price(%Decimal{} = price) do
    price |> Decimal.round(0) |> Decimal.to_string()
  end

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

  defp pending_items(order), do: Enum.filter(order.order_items, &(&1.status == "pending"))

  # Active = not yet terminal; served and cancelled items are excluded from business logic.
  defp active_items(order),
    do:
      Enum.filter(
        order.order_items,
        &(&1.status not in ["cancelled", "cancelled_waste", "served"])
      )

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

    items
    |> Enum.reject(&(not is_nil(&1.variant_id)))
    |> Enum.sort_by(fn item -> rank.(item.status) end)
  end

  # Returns the variant OrderItem currently selected for a given ingredient + dish combo.
  defp find_selected_variant(order_items, menu_item_id, product_id) do
    Enum.find(order_items, fn oi ->
      oi.status == "pending" and
        not is_nil(oi.variant_id) and
        oi.for_menu_item_id == menu_item_id and
        oi.variant != nil and
        oi.variant.product_id == product_id
    end)
  end

  # Returns all variant OrderItems linked to a given menu item OrderItem.
  defp get_variant_items(order_items, item) do
    Enum.filter(order_items, fn oi ->
      not is_nil(oi.variant_id) and
        oi.for_menu_item_id == item.menu_item_id and
        oi.status not in ["cancelled", "cancelled_waste"]
    end)
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

  defp item_is_drink?(%{menu_item: %{destination: "barra"}}), do: true
  defp item_is_drink?(_), do: false

  defp item_overdue?(%{status: "sent", sent_at: sent_at}, now) when not is_nil(sent_at) do
    DateTime.diff(now, sent_at, :second) > @overdue_secs
  end

  defp item_overdue?(_, _), do: false

  defp station_label("barra"), do: "Barra"
  defp station_label(_), do: "Cocina"

  defp station_text_class("barra"), do: "text-info font-medium"
  defp station_text_class(_), do: "text-warning font-medium"

  # Returns the set of IDs of items currently in "ready" state.
  # Used to detect newly-ready items and trigger the notification sound.
  defp ready_item_ids(order) do
    order.order_items
    |> Enum.filter(&(&1.status == "ready"))
    |> MapSet.new(& &1.id)
  end

  # Returns the maximum quantity allowed for an order item based on current
  # ingredient stock. Returns nil when there is no recipe (unlimited).
  # The menu_item must be preloaded with menu_item_ingredients + product.
  defp item_max_quantity(%{menu_item: %{menu_item_ingredients: [_ | _]} = mi}),
    do: Catalog.available_portions(mi)  # still returns plain integer — used for +/- limit only

  defp item_max_quantity(_), do: nil

  defp item_display_name(%{menu_item: %{name: name}}), do: name
  defp item_display_name(%{product: %{name: name}}), do: name
  defp item_display_name(_), do: "artículo"
end
