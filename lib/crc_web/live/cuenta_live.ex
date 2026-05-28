defmodule CRCWeb.CuentaLive do
  @moduledoc """
  Public customer-facing bill page.
  Accessible at /cuenta/:token — no login required.
  Renders the itemized bill in real time; customers scan a QR code from the waiter's screen.
  """

  use CRCWeb, :live_view

  alias CRC.Orders

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
    end

    order = Orders.get_order_by_token!(token)
    subtotal = Orders.calculate_order_total(order)
    total = if order.status == "closed" && order.total, do: order.total, else: subtotal

    socket =
      socket
      |> assign(:page_title, "Tu cuenta — #{order.customer_name}")
      |> assign(:order, order)
      |> assign(:subtotal, subtotal)
      |> assign(:total, total)

    {:ok, socket}
  rescue
    Ecto.NoResultsError ->
      {:ok,
       socket
       |> put_flash(:error, "Cuenta no encontrada.")
       |> redirect(to: "/")}
  end

  # ---------------------------------------------------------------------------
  # PubSub — refresh bill whenever the order changes
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:order_updated, order_id}, socket) do
    if socket.assigns.order.id == order_id do
      order = Orders.get_order_by_token!(socket.assigns.order.bill_token)
      subtotal = Orders.calculate_order_total(order)
      total = if order.status == "closed" && order.total, do: order.total, else: subtotal

      {:noreply,
       socket
       |> assign(:order, order)
       |> assign(:subtotal, subtotal)
       |> assign(:total, total)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Print CSS: clean receipt layout, hide interactive elements --%>
    <style>
      @media print {
        .no-print  { display: none !important; }
        .print-card { box-shadow: none !important; border: 1px solid #ccc !important; border-radius: 4px !important; }
        body { background: white !important; font-size: 13px !important; }
        @page { margin: 16mm; size: A4; }
      }
    </style>

    <div class="min-h-screen bg-base-200 flex flex-col">

      <%!-- ── Header ──────────────────────────────────────────────────────────── --%>
      <div id="bill-header" class="bg-primary text-primary-content px-4 py-5 text-center shadow-md">
        <p class="text-xs font-semibold uppercase tracking-widest opacity-70">
          Café Raíces y Cultura
        </p>
        <h1 class="text-xl font-bold mt-1">Tu cuenta</h1>
        <p class="text-base opacity-90 mt-0.5 font-semibold">{@order.customer_name}</p>
      </div>

      <%!-- ── Meta info (mesero · fecha) ────────────────────────────────────── --%>
      <div class="max-w-lg mx-auto w-full px-4 pt-4 pb-1">
        <div class="bg-base-100 rounded-xl border border-base-300 px-4 py-3 print-card
                    grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-base-content/60">
          <div>
            <span class="font-semibold text-base-content/80">Mesero</span><br />
            {if @order.user, do: @order.user.name, else: "—"}
          </div>
          <div>
            <span class="font-semibold text-base-content/80">Fecha</span><br />
            {format_datetime(@order.inserted_at)}
          </div>
          <%= if @order.closed_at do %>
            <div>
              <span class="font-semibold text-base-content/80">Hora de cierre</span><br />
              {format_datetime(@order.closed_at)}
            </div>
          <% end %>
          <%= if @order.status == "closed" && @order.payment_method do %>
            <div>
              <span class="font-semibold text-base-content/80">Pago</span><br />
              {payment_label(@order.payment_method)}
            </div>
          <% end %>
        </div>
      </div>

      <%!-- ── Status badge ──────────────────────────────────────────────────── --%>
      <div class="flex justify-center pt-3 px-4">
        <%= case @order.status do %>
          <% "closed" -> %>
            <div class="badge badge-success badge-lg gap-1.5 py-3 px-4">
              <.icon name="hero-check-circle" class="size-4" /> Cuenta cerrada · Pagado
            </div>
          <% "ready" -> %>
            <div class="badge badge-success badge-outline badge-lg gap-1.5 py-3 px-4">
              <.icon name="hero-check" class="size-4" /> ¡Listo para servir!
            </div>
          <% _ -> %>
            <div class="badge badge-warning badge-lg gap-1.5 py-3 px-4">
              <.icon name="hero-clock" class="size-4" /> En preparación
            </div>
        <% end %>
      </div>

      <%!-- ── Item list ──────────────────────────────────────────────────────── --%>
      <div class="flex-1 px-4 pt-3 pb-4 max-w-lg mx-auto w-full space-y-2">
        <% bill_lines = bill_items(@order) %>
        <%= if bill_lines == [] do %>
          <div class="text-center py-10 text-base-content/40 text-sm">
            Aún no hay artículos en tu cuenta.
          </div>
        <% else %>
          <div class="bg-base-100 rounded-2xl shadow-sm overflow-hidden border border-base-300 print-card">
            <%!-- Header row --%>
            <div class="px-4 py-2 bg-base-200/70 border-b border-base-300
                        grid grid-cols-[1fr_auto] text-xs font-semibold text-base-content/50 uppercase tracking-wide">
              <span>Artículo</span>
              <span class="text-right">Importe</span>
            </div>

            <div class="divide-y divide-base-200">
              <%= for line <- bill_lines do %>
                <div class="flex items-start gap-3 px-4 py-3">
                  <%!-- Left: name + breakdown details --%>
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-semibold text-base-content leading-snug">
                      <span class="text-primary font-bold">{line.quantity}×</span>
                      {line.name}
                      <%= if line.note do %>
                        <span class="text-xs text-base-content/40 font-normal">· {line.note}</span>
                      <% end %>
                    </p>

                    <%!-- Variant selections (e.g. leche de avena +$10) --%>
                    <%= for v <- line.variants do %>
                      <p class="text-xs text-primary/70 mt-0.5 flex items-baseline gap-1">
                        <span>◦ {v.name}</span>
                        <%= if v.extra_price do %>
                          <span class="text-base-content/40">+${format_price(v.extra_price)}</span>
                        <% end %>
                      </p>
                    <% end %>

                    <%!-- Ingredient exclusions --%>
                    <%= if line.exclusions != [] do %>
                      <p class="text-xs text-error mt-0.5">
                        Sin: {Enum.join(line.exclusions, ", ")}
                      </p>
                    <% end %>

                    <%!-- Who this item is for --%>
                    <%= if line.for_person && line.for_person != "" do %>
                      <p class="text-xs text-base-content/50 mt-0.5">
                        👤 {line.for_person}
                      </p>
                    <% end %>

                    <%!-- Free-text notes --%>
                    <%= if line.notes && line.notes != "" do %>
                      <p class="text-xs text-warning mt-0.5">
                        📝 {line.notes}
                      </p>
                    <% end %>
                  </div>

                  <%!-- Right: price --%>
                  <div class="text-right shrink-0">
                    <p class="text-xs text-base-content/40">${format_price(line.unit_price)} c/u</p>
                    <p class="text-sm font-bold text-base-content">${format_price(line.subtotal)}</p>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Discount breakdown + Total --%>
            <%= if @order.discount_percentage && @order.discount_percentage > 0 do %>
              <div class="px-4 py-2 border-t border-base-300 flex items-center justify-between text-sm text-base-content/60">
                <span>Subtotal</span>
                <span>${format_price(@subtotal)}</span>
              </div>
              <div class="px-4 py-2 flex items-center justify-between text-sm text-success font-medium">
                <span>Descuento {if @order.discount, do: @order.discount.name, else: "#{@order.discount_percentage}%"} (-{@order.discount_percentage}%)</span>
                <span>-${format_price(Decimal.sub(@subtotal, @total))}</span>
              </div>
            <% end %>
            <div class="px-4 py-4 bg-base-200/60 border-t border-base-300
                        flex items-center justify-between">
              <span class="font-semibold text-base-content">Total</span>
              <span class="text-2xl font-bold text-primary">${format_price(@total)}</span>
            </div>
          </div>

          <%!-- Payment + change breakdown (efectivo) --%>
          <%= if @order.status == "closed" && @order.payment_method do %>
            <div class="bg-success/10 border border-success/30 rounded-xl px-4 py-3 text-sm text-success font-medium print-card">
              <div class="flex items-center gap-2">
                <.icon name="hero-check-badge" class="size-4 shrink-0" />
                <span>Pagado con {payment_label(@order.payment_method)}</span>
              </div>
              <%= if @order.amount_paid && @order.payment_method == "efectivo" do %>
                <div class="mt-2 text-xs text-base-content/60 space-y-0.5 pl-6">
                  <p>Entregado: <span class="font-semibold">${format_price(@order.amount_paid)}</span></p>
                  <p>Cambio: <span class="font-semibold">${format_price(Decimal.sub(@order.amount_paid, @total))}</span></p>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>

        <%!-- Download / print button --%>
        <div class="no-print pt-1">
          <button
            onclick="window.print()"
            class="btn btn-outline w-full gap-2"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" />
            Descargar PDF
          </button>
        </div>
      </div>

      <%!-- Footer --%>
      <div class="text-center pb-8 text-xs text-base-content/30 px-4 no-print">
        ¡Gracias por visitarnos! 🌱
      </div>
      <div class="hidden text-center pb-4 text-xs text-base-content/40 px-4" style="display:none">
        <p>Café Raíces y Cultura · cafe@raicesycultura.mx</p>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Returns customer-visible line items with full breakdown per item.
  # Excludes cancelled items, ingredient extras, and variant-only rows.
  defp bill_items(%{order_items: items}) do
    # Build a lookup: menu_item_id → list of %{name, extra_price} for each selected variant.
    # Variant items with unit_price > 0 have an extra charge that contributes to the total.
    variant_map =
      items
      |> Enum.filter(fn oi ->
        not is_nil(oi.variant_id) and not is_nil(oi.for_menu_item_id) and
          not is_nil(oi.variant)
      end)
      |> Enum.group_by(& &1.for_menu_item_id, fn oi ->
        extra =
          if oi.unit_price && Decimal.gt?(oi.unit_price, Decimal.new(0)),
            do: oi.unit_price,
            else: nil

        %{name: oi.variant.name, extra_price: extra}
      end)

    items
    |> Enum.filter(fn oi ->
      oi.status not in ["cancelled", "cancelled_waste"] and
        not is_nil(oi.menu_item_id) and not is_nil(oi.menu_item)
    end)
    |> Enum.map(fn oi ->
      unit_price = oi.unit_price || oi.menu_item.price
      exclusion_names = Enum.map(oi.exclusions, fn e -> e.product && e.product.name end) |> Enum.reject(&is_nil/1)
      variants = Map.get(variant_map, oi.menu_item_id, [])

      %{
        name: oi.menu_item.name,
        note: package_note(oi),
        for_person: oi.for_person,
        notes: oi.notes,
        quantity: oi.quantity,
        unit_price: unit_price,
        subtotal: Decimal.mult(unit_price, Decimal.new(oi.quantity)),
        variants: variants,
        exclusions: exclusion_names
      }
    end)
  end

  defp package_note(%{package_id: nil}), do: nil
  defp package_note(%{package: %{name: name}}) when not is_nil(name), do: "Paquete #{name}"
  defp package_note(_), do: "Paquete"

  defp payment_label("efectivo"), do: "Efectivo"
  defp payment_label("tarjeta"), do: "Tarjeta"
  defp payment_label("transferencia"), do: "Transferencia"
  defp payment_label(other), do: other

  defp format_price(%Decimal{} = d) do
    :erlang.float_to_binary(Decimal.to_float(d), decimals: 2)
  end

  defp format_price(nil), do: "0.00"

  # Formats a UTC datetime as "DD/MM/YYYY HH:MM" in local display.
  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%d/%m/%Y %H:%M")
  end

  defp format_datetime(nil), do: "—"
end
