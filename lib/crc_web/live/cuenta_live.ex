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
    total = Orders.calculate_order_total(order)

    socket =
      socket
      |> assign(:page_title, "Tu cuenta — #{order.customer_name}")
      |> assign(:order, order)
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
      {:noreply,
       socket
       |> assign(:order, order)
       |> assign(:total, Orders.calculate_order_total(order))}
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
    <%!-- Print styles: hide interactive chrome, force white background --%>
    <style>
      @media print {
        .no-print { display: none !important; }
        body { background: white !important; }
        .print-card { box-shadow: none !important; border: 1px solid #ddd !important; }
      }
    </style>

    <div class="min-h-screen bg-base-200 flex flex-col">
      <%!-- Header --%>
      <div class="bg-primary text-primary-content px-4 py-5 text-center shadow-md">
        <p class="text-xs font-semibold uppercase tracking-widest opacity-70">
          Café Raíces y Cultura
        </p>
        <h1 class="text-xl font-bold mt-1">Tu cuenta</h1>
        <p class="text-sm opacity-80 mt-0.5">{@order.customer_name}</p>
      </div>

      <%!-- Status badge --%>
      <div class="flex justify-center pt-4 px-4">
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

      <%!-- Items --%>
      <div class="flex-1 px-4 pt-4 pb-6 max-w-lg mx-auto w-full space-y-2">
        <% bill_lines = bill_items(@order) %>
        <%= if bill_lines == [] do %>
          <div class="text-center py-10 text-base-content/40 text-sm">
            Aún no hay artículos en tu cuenta.
          </div>
        <% else %>
          <div class="bg-base-100 rounded-2xl shadow-sm overflow-hidden border border-base-300">
            <div class="divide-y divide-base-200">
              <%= for line <- bill_lines do %>
                <div class="flex items-center gap-3 px-4 py-3">
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-base-content leading-snug">
                      {line.name}
                      <%= if line.note do %>
                        <span class="text-xs text-base-content/50 font-normal">
                          · {line.note}
                        </span>
                      <% end %>
                    </p>
                    <%= if line.for_person && line.for_person != "" do %>
                      <p class="text-xs text-base-content/50 mt-0.5">
                        👤 {line.for_person}
                      </p>
                    <% end %>
                  </div>
                  <div class="text-right shrink-0">
                    <p class="text-xs text-base-content/50">{line.quantity}× ${format_price(line.unit_price)}</p>
                    <p class="text-sm font-semibold text-base-content">${format_price(line.subtotal)}</p>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Total --%>
            <div class="px-4 py-4 bg-base-200/60 border-t border-base-300 flex items-center justify-between">
              <span class="font-semibold text-base-content">Total</span>
              <span class="text-2xl font-bold text-primary">${format_price(@total)}</span>
            </div>
          </div>

          <%!-- Payment info if closed --%>
          <%= if @order.status == "closed" && @order.payment_method do %>
            <div class="bg-success/10 border border-success/30 rounded-xl px-4 py-3 text-sm text-success font-medium flex items-center gap-2">
              <.icon name="hero-check-badge" class="size-4 shrink-0" />
              Pagado con {payment_label(@order.payment_method)}
              <%= if @order.amount_paid && @order.payment_method == "efectivo" do %>
                <span class="ml-auto text-base-content/60 font-normal">
                  Entregado ${ format_price(@order.amount_paid)}
                  · Cambio ${format_price(Decimal.sub(@order.amount_paid, @total))}
                </span>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>

      <%!-- Download / print button --%>
      <div class="no-print px-4 pb-4 max-w-lg mx-auto w-full">
        <button
          onclick="window.print()"
          class="btn btn-outline w-full gap-2"
        >
          <.icon name="hero-arrow-down-tray" class="size-4" />
          Descargar / Imprimir cuenta
        </button>
      </div>

      <%!-- Footer --%>
      <div class="text-center pb-8 text-xs text-base-content/30 px-4">
        ¡Gracias por visitarnos! 🌱
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Returns customer-visible line items: menu items and package items with prices.
  # Excludes cancelled items and ingredient extras (products) which have no customer price.
  defp bill_items(%{order_items: items}) do
    items
    |> Enum.filter(fn oi ->
      oi.status not in ["cancelled", "cancelled_waste"] and
        not is_nil(oi.menu_item_id) and not is_nil(oi.menu_item)
    end)
    |> Enum.map(fn oi ->
      unit_price = oi.unit_price || oi.menu_item.price
      %{
        name: oi.menu_item.name,
        note: package_note(oi),
        for_person: oi.for_person,
        quantity: oi.quantity,
        unit_price: unit_price,
        subtotal: Decimal.mult(unit_price, Decimal.new(oi.quantity))
      }
    end)
  end

  defp package_note(%{package_id: nil}), do: nil
  defp package_note(%{package: %{name: name}}) when not is_nil(name), do: "Paquete #{name}"
  defp package_note(_), do: "Paquete"

  defp payment_label("efectivo"), do: "efectivo"
  defp payment_label("tarjeta"), do: "tarjeta"
  defp payment_label("transferencia"), do: "transferencia"
  defp payment_label(other), do: other

  defp format_price(%Decimal{} = d) do
    :erlang.float_to_binary(Decimal.to_float(d), decimals: 2)
  end

  defp format_price(nil), do: "0.00"
end
