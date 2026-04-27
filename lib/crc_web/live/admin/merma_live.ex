defmodule CRCWeb.Admin.MermaLive do
  @moduledoc "Stock adjustment (merma / waste) management for ingredient products."

  use CRCWeb, :live_view

  import CRCWeb.Layouts, only: [flash_group: 1]

  alias CRC.Inventory

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Merma de Insumos · Admin")
      |> assign(:products, Inventory.list_products())
      |> assign(:adjustments, Inventory.list_recent_adjustments(100))
      |> assign(:modal_open, false)
      |> assign(:form, nil)
      |> assign(:qty_sign, "-")

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("open_modal", _params, socket) do
    form = Inventory.change_stock_adjustment() |> to_form()

    socket =
      socket
      |> assign(:modal_open, true)
      |> assign(:form, form)
      |> assign(:qty_sign, "-")

    {:noreply, socket}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :modal_open, false)}
  end

  def handle_event("set_sign", %{"sign" => sign}, socket) do
    {:noreply, assign(socket, :qty_sign, sign)}
  end

  def handle_event("save_adjustment", %{"stock_adjustment" => params}, socket) do
    raw_qty = Map.get(params, "quantity", "0")

    # Apply sign: loss is negative, addition (correction) is positive.
    qty =
      case Decimal.parse(raw_qty) do
        {d, _} ->
          if socket.assigns.qty_sign == "-",
            do: Decimal.negate(d),
            else: d

        :error ->
          Decimal.new(0)
      end

    attrs = Map.put(params, "quantity", qty)

    case Inventory.create_stock_adjustment(attrs, socket.assigns.current_user.id) do
      {:ok, _adj} ->
        socket =
          socket
          |> assign(:adjustments, Inventory.list_recent_adjustments(100))
          |> assign(:products, Inventory.list_products())
          |> assign(:modal_open, false)
          |> put_flash(:info, "Ajuste registrado correctamente.")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 pb-10">
      <div class="max-w-4xl mx-auto px-4 py-8 space-y-6">

        <%!-- Header --%>
        <div class="flex items-center justify-between flex-wrap gap-3">
          <div>
            <h1 class="text-2xl font-bold text-base-content">🗑️ Merma de Insumos</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              Registra pérdidas de stock por caducidad, derrames, robos u otros motivos.
            </p>
          </div>
          <button class="btn btn-primary btn-sm" phx-click="open_modal">
            <.icon name="hero-plus" class="size-4" />
            Registrar ajuste
          </button>
        </div>

        <%!-- Info banner --%>
        <div class="alert alert-info text-sm">
          <.icon name="hero-information-circle" class="size-5 shrink-0" />
          <div>
            <p class="font-semibold">¿Cómo funciona?</p>
            <p class="text-xs mt-0.5">
              Cada ajuste descuenta (o corrige) el stock del insumo de forma inmediata y queda registrado con razón y usuario.
              Usa <strong>pérdida</strong> para caducidad, derrames o robos.
              Usa <strong>corrección</strong> cuando un conteo físico revela que tienes más stock del que el sistema refleja.
            </p>
          </div>
        </div>

        <%!-- History table --%>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
          <div class="px-5 py-4 border-b border-base-300">
            <h2 class="font-semibold text-base-content">Historial de ajustes</h2>
          </div>

          <%= if @adjustments == [] do %>
            <div class="py-16 text-center text-base-content/40 text-sm">
              No hay ajustes registrados todavía.
            </div>
          <% else %>
            <%!-- Mobile cards --%>
            <div class="md:hidden divide-y divide-base-200">
              <%= for adj <- @adjustments do %>
                <div class="px-4 py-3 flex items-start gap-3">
                  <span class={"badge badge-sm mt-0.5 shrink-0 #{if Decimal.negative?(adj.quantity), do: "badge-error", else: "badge-success"}"}>
                    {if Decimal.negative?(adj.quantity), do: "▼", else: "▲"}
                    {Decimal.abs(adj.quantity) |> format_qty()}
                  </span>
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-base-content truncate">
                      {adj.product && adj.product.name}
                    </p>
                    <p class="text-xs text-base-content/50">
                      {Inventory.adjustment_reason_label(adj.reason)}
                      {if adj.notes && adj.notes != "", do: " · #{adj.notes}"}
                    </p>
                    <p class="text-xs text-base-content/40 mt-0.5">
                      {adj.adjusted_by && adj.adjusted_by.name} · {format_dt(adj.inserted_at)}
                    </p>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Desktop table --%>
            <div class="hidden md:block overflow-x-auto">
              <table class="table table-zebra table-fixed w-full">
                <thead>
                  <tr class="bg-base-200 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                    <th class="w-[22%]">Insumo</th>
                    <th class="w-[12%]">Cantidad</th>
                    <th class="w-[20%]">Razón</th>
                    <th class="w-[26%]">Notas</th>
                    <th class="w-[12%]">Usuario</th>
                    <th class="w-[8%]">Fecha</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for adj <- @adjustments do %>
                    <tr class="hover:bg-base-200/50 transition-colors">
                      <td class="text-sm font-medium text-base-content">
                        {adj.product && adj.product.name}
                      </td>
                      <td>
                        <span class={"badge badge-sm #{if Decimal.negative?(adj.quantity), do: "badge-error", else: "badge-success"}"}>
                          {if Decimal.negative?(adj.quantity), do: "−", else: "+"}{Decimal.abs(adj.quantity) |> format_qty()}
                          {adj.product && adj.product.unit}
                        </span>
                      </td>
                      <td class="text-sm text-base-content/70">
                        {Inventory.adjustment_reason_label(adj.reason)}
                      </td>
                      <td class="text-sm text-base-content/60 truncate max-w-0">
                        {adj.notes || "—"}
                      </td>
                      <td class="text-xs text-base-content/50">
                        {adj.adjusted_by && adj.adjusted_by.name || "—"}
                      </td>
                      <td class="text-xs text-base-content/40">
                        {format_dt(adj.inserted_at)}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>

      </div>
    </div>

    <%!-- Modal --%>
    <%= if @modal_open do %>
      <div class="modal modal-open modal-bottom sm:modal-middle" role="dialog">
        <div class="modal-box max-w-lg">

          <h3 class="text-lg font-bold mb-1">Registrar ajuste de stock</h3>
          <p class="text-xs text-base-content/50 mb-4">
            Selecciona el insumo, indica la cantidad y la razón. El stock se actualiza de inmediato.
          </p>

          <.form for={@form} phx-submit="save_adjustment" class="space-y-4">

            <%!-- Product --%>
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Insumo</span></label>
              <select name="stock_adjustment[product_id]" class="select select-bordered w-full" required>
                <option value="">— Selecciona un insumo —</option>
                <%= for p <- @products do %>
                  <option value={p.id}>{p.name} (stock actual: {format_qty(p.stock_quantity)} {p.unit})</option>
                <% end %>
              </select>
                          </div>

            <%!-- Type: loss vs correction --%>
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Tipo de ajuste</span></label>
              <div class="flex gap-2">
                <button
                  type="button"
                  class={"btn btn-sm flex-1 #{if @qty_sign == "-", do: "btn-error", else: "btn-ghost"}"}
                  phx-click="set_sign"
                  phx-value-sign="-"
                >
                  📉 Pérdida (descuenta stock)
                </button>
                <button
                  type="button"
                  class={"btn btn-sm flex-1 #{if @qty_sign == "+", do: "btn-success", else: "btn-ghost"}"}
                  phx-click="set_sign"
                  phx-value-sign="+"
                >
                  📈 Corrección (agrega stock)
                </button>
              </div>
            </div>

            <%!-- Quantity --%>
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Cantidad</span>
                <span class="label-text-alt text-base-content/40">En la unidad del insumo (litros, gramos, etc.)</span>
              </label>
              <input
                type="number"
                name="stock_adjustment[quantity]"
                min="0.001"
                step="0.001"
                placeholder="Ej: 0.5"
                class="input input-bordered w-full"
                required
              />
                          </div>

            <%!-- Reason --%>
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Razón</span></label>
              <select name="stock_adjustment[reason]" class="select select-bordered w-full" required>
                <option value="">— Selecciona la razón —</option>
                <%= for {label, value} <- Inventory.adjustment_reasons() do %>
                  <option value={value}>{label}</option>
                <% end %>
              </select>
                          </div>

            <%!-- Notes --%>
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Notas</span>
                <span class="label-text-alt text-base-content/40">Opcional</span>
              </label>
              <textarea
                name="stock_adjustment[notes]"
                class="textarea textarea-bordered w-full"
                rows="2"
                placeholder="Ej: Se cayó el bote de leche del refrigerador"
              ></textarea>
            </div>

            <div class="modal-action pt-2">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
              <button type="submit" class="btn btn-primary">Registrar ajuste</button>
            </div>

          </.form>
        </div>
        <div class="modal-backdrop" phx-click="close_modal"></div>
      </div>
    <% end %>

    <.flash_group flash={@flash} />
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp format_qty(nil), do: "0"
  defp format_qty(%Decimal{} = d) do
    d = Decimal.abs(d)
    if Decimal.integer?(d),
      do: d |> Decimal.to_integer() |> to_string(),
      else: d |> Decimal.round(3) |> Decimal.to_string() |> String.trim_trailing("0") |> String.trim_trailing(".")
  end
  defp format_qty(v), do: to_string(v)

  defp format_dt(%DateTime{} = dt) do
    # Display in UTC (tzdata not installed; no named-zone conversion available).
    Calendar.strftime(dt, "%d/%m/%y %H:%M UTC")
  end
  defp format_dt(_), do: "—"

  # CoreComponents already imports translate_error/1 — used via the .error component directly.
end
