defmodule CRCWeb.Admin.VentaManualLive do
  @moduledoc """
  Admin form to register a manual (offline/paper) sale.

  Used when orders were taken on paper (e.g., power outage) and need to be
  entered retroactively. The resulting order is immediately closed and counts
  toward financial totals, but is excluded from rendimiento metrics.
  """

  use CRCWeb, :live_view

  import CRCWeb.Layouts, only: [flash_group: 1]

  alias CRC.Catalog
  alias CRC.Orders

  @impl true
  def mount(_params, _session, socket) do
    # Format current UTC time for the datetime-local input.
    # tzdata is not installed, so we work in UTC throughout.
    now_utc    = DateTime.utc_now()
    default_dt = Calendar.strftime(now_utc, "%Y-%m-%dT%H:%M")

    socket =
      socket
      |> assign(:page_title, "Venta Manual · Admin")
      |> assign(:menu_items, Catalog.list_menu_items())
      |> assign(:lines, [])
      |> assign(:customer_name, "")
      |> assign(:payment_method, "efectivo")
      |> assign(:datetime_input, default_dt)
      |> assign(:notes, "")
      |> assign(:errors, [])

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("update_field", %{"field" => field, "value" => value}, socket) do
    {:noreply, assign(socket, String.to_existing_atom(field), value)}
  end

  # Receives form submit from the item-picker mini-form (select + qty + button).
  def handle_event("add_line", %{"item_id" => item_id, "qty" => qty_str}, socket) do
    qty = parse_qty(qty_str)

    cond do
      item_id == "" ->
        {:noreply, put_error(socket, "Selecciona un platillo.")}

      qty <= 0 ->
        {:noreply, put_error(socket, "La cantidad debe ser mayor a cero.")}

      true ->
        item = Enum.find(socket.assigns.menu_items, &(to_string(&1.id) == item_id))

        new_lines =
          case Enum.find_index(socket.assigns.lines, &(&1.item.id == item.id)) do
            nil -> socket.assigns.lines ++ [%{item: item, qty: qty}]
            idx -> List.update_at(socket.assigns.lines, idx, &%{&1 | qty: &1.qty + qty})
          end

        {:noreply,
         socket
         |> assign(:lines, new_lines)
         |> assign(:errors, [])}
    end
  end

  def handle_event("remove_line", %{"idx" => idx_str}, socket) do
    idx   = String.to_integer(idx_str)
    lines = List.delete_at(socket.assigns.lines, idx)
    {:noreply, assign(socket, :lines, lines)}
  end

  def handle_event("set_method", %{"method" => method}, socket) do
    {:noreply, assign(socket, :payment_method, method)}
  end

  def handle_event("submit", _params, socket) do
    errors = validate(socket.assigns)

    if errors != [] do
      {:noreply, assign(socket, :errors, errors)}
    else
      total    = compute_total(socket.assigns.lines)
      closed_at = parse_datetime(socket.assigns.datetime_input)

      attrs = %{
        customer_name:  socket.assigns.customer_name,
        payment_method: socket.assigns.payment_method,
        total:          total,
        closed_at:      closed_at,
        notes:          socket.assigns.notes
      }

      items =
        Enum.map(socket.assigns.lines, fn %{item: item, qty: qty} ->
          %{menu_item_id: item.id, quantity: qty}
        end)

      case Orders.create_manual_order(attrs, items, socket.assigns.current_user.id) do
        {:ok, _order} ->
          {:noreply,
           socket
           |> assign(:lines, [])
           |> assign(:customer_name, "")
           |> assign(:notes, "")
           |> assign(:errors, [])
           |> put_flash(:info, "Venta registrada correctamente.")}

        {:error, _} ->
          {:noreply, put_error(socket, "No se pudo guardar. Verifica los datos e intenta de nuevo.")}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 pb-10">
      <div class="max-w-2xl mx-auto px-4 py-8 space-y-6">

        <%!-- Header --%>
        <div>
          <div class="flex items-center gap-2 mb-1">
            <.icon name="hero-pencil-square" class="size-6 text-primary" />
            <h1 class="text-2xl font-bold text-base-content">Venta manual</h1>
          </div>
          <p class="text-sm text-base-content/50">
            Registra comandas tomadas en papel. Cuentan en Finanzas y Ventas, pero no afectan Rendimiento ni tiempos de cocina.
          </p>
        </div>

        <%!-- Help banner --%>
        <div class="alert alert-warning text-sm">
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
          <div>
            <p class="font-semibold">¿Cuándo usar esto?</p>
            <p class="text-xs mt-0.5">
              Solo para ventas que ya ocurrieron pero no quedaron registradas en el sistema
              (corte de luz, internet caído, etc.). El total se toma del menú; ajústalo si cobraste diferente.
            </p>
          </div>
        </div>

        <%!-- Errors --%>
        <%= if @errors != [] do %>
          <div class="alert alert-error text-sm">
            <.icon name="hero-x-circle" class="size-5 shrink-0" />
            <ul class="list-disc list-inside space-y-0.5">
              <%= for e <- @errors do %>
                <li>{e}</li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <%!-- Form card --%>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-6 space-y-5">

          <%!-- Customer name --%>
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Nombre del cliente</span></label>
            <input
              type="text"
              class="input input-bordered w-full"
              placeholder="Ej. Mesa 4 / Juan Pérez"
              value={@customer_name}
              phx-keyup="update_field"
              phx-value-field="customer_name"
              phx-debounce="200"
            />
          </div>

          <%!-- Date and time --%>
          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Fecha y hora de la venta</span>
              <span class="label-text-alt text-base-content/40">¿Cuándo ocurrió?</span>
            </label>
            <input
              type="datetime-local"
              class="input input-bordered w-full"
              value={@datetime_input}
              phx-change="update_field"
              phx-value-field="datetime_input"
            />
          </div>

          <%!-- Add items --%>
          <div class="space-y-3">
            <p class="text-sm font-medium text-base-content">Artículos</p>

            <%!-- Mini-form: submit sends item_id + qty together, no phx-change needed --%>
            <form phx-submit="add_line" class="flex gap-2 flex-wrap items-end">
              <select name="item_id" class="select select-bordered flex-1 min-w-0">
                <option value="">— Selecciona un platillo —</option>
                <%= for item <- @menu_items do %>
                  <option value={item.id}>
                    {if item.category, do: "#{item.category.name} · "}{item.name} — ${format_price(item.price)}
                  </option>
                <% end %>
              </select>
              <input
                type="number"
                name="qty"
                min="1"
                max="99"
                value="1"
                class="input input-bordered w-20 text-center"
                placeholder="Cant."
              />
              <button type="submit" class="btn btn-primary btn-sm">
                <.icon name="hero-plus" class="size-4" />
                Agregar
              </button>
            </form>

            <%!-- Lines --%>
            <%= if @lines != [] do %>
              <div class="bg-base-200 rounded-xl divide-y divide-base-300">
                <%= for {line, idx} <- Enum.with_index(@lines) do %>
                  <div class="flex items-center gap-3 px-4 py-2.5">
                    <span class="text-sm font-bold text-primary shrink-0">{line.qty}×</span>
                    <span class="flex-1 text-sm text-base-content truncate">{line.item.name}</span>
                    <span class="text-sm text-base-content/60 shrink-0">${format_price(Decimal.mult(line.item.price, Decimal.new(line.qty)))}</span>
                    <button
                      class="btn btn-ghost btn-xs btn-circle text-error shrink-0"
                      phx-click="remove_line"
                      phx-value-idx={idx}
                    >
                      <.icon name="hero-x-mark" class="size-3.5" />
                    </button>
                  </div>
                <% end %>
                <%!-- Total row --%>
                <div class="flex items-center justify-between px-4 py-2.5 bg-base-300/40 rounded-b-xl">
                  <span class="text-sm font-semibold text-base-content">Total</span>
                  <span class="text-lg font-bold text-primary">${format_price(compute_total(@lines))}</span>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Payment method --%>
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Método de pago</span></label>
            <div class="grid grid-cols-3 gap-2">
              <%= for {label, value, icon} <- [
                {"Efectivo", "efectivo", "hero-banknotes"},
                {"Tarjeta", "tarjeta", "hero-credit-card"},
                {"Transfer.", "transferencia", "hero-device-phone-mobile"}
              ] do %>
                <button
                  type="button"
                  class={["btn btn-sm flex-col h-auto py-2 gap-1",
                    if(@payment_method == value, do: "btn-primary", else: "btn-outline btn-ghost")]}
                  phx-click="set_method"
                  phx-value-method={value}
                >
                  <.icon name={icon} class="size-4" />
                  <span class="text-xs">{label}</span>
                </button>
              <% end %>
            </div>
          </div>

          <%!-- Notes --%>
          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Notas</span>
              <span class="label-text-alt text-base-content/40">Opcional</span>
            </label>
            <textarea
              class="textarea textarea-bordered w-full"
              rows="2"
              placeholder="Ej. Comandas en papel durante corte de luz 14:00–16:00"
              phx-keyup="update_field"
              phx-value-field="notes"
              phx-debounce="300"
            >{@notes}</textarea>
          </div>

          <%!-- Submit --%>
          <button
            class="btn btn-primary w-full"
            phx-click="submit"
            disabled={@lines == []}
          >
            <.icon name="hero-check" class="size-5" />
            Registrar venta
          </button>

        </div>

      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp parse_qty(str) do
    case Integer.parse(str || "0") do
      {n, _} when n > 0 -> n
      _ -> 0
    end
  end

  defp parse_datetime(str) do
    case NaiveDateTime.from_iso8601(str <> ":00") do
      {:ok, ndt} ->
        # Treat the value from the datetime-local input as UTC (tzdata not installed).
        DateTime.from_naive!(ndt, "Etc/UTC") |> DateTime.truncate(:second)

      _ ->
        DateTime.utc_now() |> DateTime.truncate(:second)
    end
  end

  defp compute_total(lines) do
    Enum.reduce(lines, Decimal.new(0), fn %{item: item, qty: qty}, acc ->
      Decimal.add(acc, Decimal.mult(item.price, Decimal.new(qty)))
    end)
  end

  defp validate(assigns) do
    []
    |> then(fn e ->
      if String.trim(assigns.customer_name) == "",
        do: ["El nombre del cliente es requerido." | e], else: e
    end)
    |> then(fn e ->
      if assigns.lines == [],
        do: ["Agrega al menos un artículo." | e], else: e
    end)
  end

  defp put_error(socket, msg) do
    assign(socket, :errors, [msg | socket.assigns.errors])
  end

  defp format_price(nil), do: "0.00"
  defp format_price(%Decimal{} = d), do: Decimal.round(d, 2) |> Decimal.to_string()
  defp format_price(n) when is_number(n), do: :erlang.float_to_binary(n / 1, decimals: 2)
  defp format_price(other), do: to_string(other)
end
