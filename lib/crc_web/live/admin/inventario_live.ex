defmodule CRCWeb.Admin.InventarioLive do
  @moduledoc """
  Quick stock overview for admin.

  Shows all active products with their current stock. Allows updating any
  product's stock by entering the new absolute quantity plus an optional note.
  The delta is calculated automatically and recorded as a stock adjustment.
  """

  use CRCWeb, :live_view

  import CRCWeb.Layouts, only: [flash_group: 1]

  alias CRC.Inventory

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Inventario · Admin")
      |> assign(:products, load_products())
      |> assign(:editing_id, nil)
      |> assign(:new_qty, "")
      |> assign(:notes, "")
      |> assign(:filter, "all")
      |> assign(:search, "")

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Filter
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("set_filter", %{"filter" => filter}, socket) do
    {:noreply, assign(socket, :filter, filter)}
  end

  def handle_event("search_stock", %{"query" => query}, socket) do
    {:noreply, assign(socket, :search, query)}
  end

  # ---------------------------------------------------------------------------
  # Inline edit
  # ---------------------------------------------------------------------------

  def handle_event("start_edit", %{"id" => id}, socket) do
    product = Enum.find(socket.assigns.products, &(to_string(&1.id) == id))
    current = if product, do: format_qty(product.stock_quantity), else: ""

    socket =
      socket
      |> assign(:editing_id, String.to_integer(id))
      |> assign(:new_qty, current)
      |> assign(:notes, "")

    {:noreply, socket}
  end

  def handle_event("cancel_edit", _params, socket) do
    socket =
      socket
      |> assign(:editing_id, nil)
      |> assign(:new_qty, "")
      |> assign(:notes, "")

    {:noreply, socket}
  end

  def handle_event("form_change", %{"new_qty" => qty, "notes" => notes}, socket) do
    {:noreply, assign(socket, new_qty: qty, notes: notes)}
  end

  def handle_event("save_stock", %{"new_qty" => raw_qty, "notes" => notes}, socket) do
    product_id = socket.assigns.editing_id

    with %{} = product <- Enum.find(socket.assigns.products, &(&1.id == product_id)),
         {new_qty, _} <- Decimal.parse(raw_qty),
         delta <- Decimal.sub(new_qty, product.stock_quantity),
         false <- Decimal.equal?(delta, Decimal.new(0)) do
      reason = if Decimal.negative?(delta), do: "ajuste_manual", else: "ajuste_manual"

      attrs = %{
        "product_id" => product_id,
        "quantity" => delta,
        "reason" => reason,
        "notes" => if(String.trim(notes) == "", do: nil, else: String.trim(notes))
      }

      case Inventory.create_stock_adjustment(attrs, socket.assigns.current_user.id) do
        {:ok, _adj} ->
          socket =
            socket
            |> assign(:products, load_products())
            |> assign(:editing_id, nil)
            |> assign(:new_qty, "")
            |> assign(:notes, "")
            |> put_flash(:info, "Stock de #{product.name} actualizado correctamente.")

          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "No se pudo actualizar el stock. Verifica el valor ingresado.")}
      end
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Insumo no encontrado.")}

      :error ->
        {:noreply, put_flash(socket, :error, "Cantidad inválida.")}

      # delta == 0: no change
      true ->
        socket =
          socket
          |> assign(:editing_id, nil)
          |> assign(:new_qty, "")
          |> assign(:notes, "")

        {:noreply, put_flash(socket, :info, "El stock no cambió (el valor ingresado es igual al actual).")}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 pb-10">
      <div class="max-w-5xl mx-auto px-4 py-8 space-y-6">

        <%!-- Header --%>
        <div class="flex items-start justify-between flex-wrap gap-3">
          <div>
            <h1 class="text-2xl font-bold text-base-content">📦 Inventario</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              Stock actual de todos los insumos. Haz clic en
              <strong>Actualizar</strong>
              para corregir cualquier cantidad.
            </p>
          </div>
          <a href="/admin/insumos/merma" class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-trending-down" class="size-4" /> Ver merma
          </a>
        </div>

        <%!-- Search bar --%>
        <div class="relative">
          <.icon
            name="hero-magnifying-glass"
            class="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-base-content/40 pointer-events-none"
          />
          <input
            type="search"
            name="query"
            value={@search}
            placeholder="Buscar insumo..."
            class="input input-bordered w-full pl-9 pr-4"
            phx-change="search_stock"
            phx-debounce="200"
          />
        </div>

        <%!-- Filter tabs --%>
        <div class="tabs tabs-box w-fit">
          <button
            class={"tab #{if @filter == "all", do: "tab-active"}"}
            phx-click="set_filter"
            phx-value-filter="all"
          >
            Todos
          </button>
          <button
            class={"tab #{if @filter == "low", do: "tab-active"}"}
            phx-click="set_filter"
            phx-value-filter="low"
          >
            ⚠️ Stock bajo
          </button>
          <button
            class={"tab #{if @filter == "ok", do: "tab-active"}"}
            phx-click="set_filter"
            phx-value-filter="ok"
          >
            ✅ En orden
          </button>
        </div>

        <%!-- Legend --%>
        <div class="flex gap-4 text-xs text-base-content/50 flex-wrap">
          <span class="flex items-center gap-1">
            <span class="inline-block w-2.5 h-2.5 rounded-full bg-error"></span> Sin stock o crítico
          </span>
          <span class="flex items-center gap-1">
            <span class="inline-block w-2.5 h-2.5 rounded-full bg-warning"></span>
            En mínimo o por debajo
          </span>
          <span class="flex items-center gap-1">
            <span class="inline-block w-2.5 h-2.5 rounded-full bg-success"></span> En orden
          </span>
        </div>

        <%!-- Product list --%>
        <% visible = @products |> visible_products(@filter) |> search_filter(@search) %>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
          <%= if visible == [] do %>
            <div class="py-20 text-center text-base-content/40 text-sm">
              No hay insumos que mostrar en este filtro.
            </div>
          <% else %>
            <%!-- Mobile cards --%>
            <div class="md:hidden divide-y divide-base-200">
              <%= for p <- visible do %>
                <div class="px-4 py-4 space-y-2">
                  <div class="flex items-center gap-2">
                    <span class={"inline-block w-2.5 h-2.5 rounded-full shrink-0 #{stock_dot_class(p)}"}></span>
                    <span class="font-medium text-base-content text-sm">{p.name}</span>
                  </div>
                  <div class="flex items-center justify-between">
                    <div>
                      <span class={"text-2xl font-bold #{stock_text_class(p)}"}>
                        {format_qty(p.stock_quantity)}
                      </span>
                      <span class="text-xs text-base-content/50 ml-1">{p.unit}</span>
                      <p class="text-xs text-base-content/40 mt-0.5">
                        Mínimo: {format_qty(p.min_stock)} {p.unit}
                      </p>
                    </div>
                    <%= if @editing_id == p.id do %>
                      <button
                        class="btn btn-ghost btn-xs text-base-content/40"
                        phx-click="cancel_edit"
                      >
                        Cancelar
                      </button>
                    <% else %>
                      <button
                        class="btn btn-sm btn-outline"
                        phx-click="start_edit"
                        phx-value-id={p.id}
                      >
                        <.icon name="hero-pencil-square" class="size-3.5" /> Actualizar
                      </button>
                    <% end %>
                  </div>
                  <%= if @editing_id == p.id do %>
                    <.edit_form product={p} new_qty={@new_qty} notes={@notes} />
                  <% end %>
                </div>
              <% end %>
            </div>

            <%!-- Desktop table --%>
            <div class="hidden md:block overflow-x-auto">
              <table class="table table-fixed w-full">
                <thead>
                  <tr class="bg-base-200 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                    <th class="w-[34%]">Insumo</th>
                    <th class="w-[17%]">Stock actual</th>
                    <th class="w-[14%]">Mínimo</th>
                    <th class="w-[13%]">Estado</th>
                    <th class="w-[22%] text-right pr-5">Acción</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for p <- visible do %>
                    <tr class="hover:bg-base-200/40 transition-colors border-b border-base-200 last:border-0">
                      <td>
                        <div class="flex items-center gap-2">
                          <span class={"inline-block w-2.5 h-2.5 rounded-full shrink-0 #{stock_dot_class(p)}"}></span>
                          <span class="text-sm font-medium text-base-content">{p.name}</span>
                          <%= if p.supplier do %>
                            <span class="badge badge-ghost badge-xs">{p.supplier.name}</span>
                          <% end %>
                        </div>
                      </td>
                      <td>
                        <span class={"text-base font-bold #{stock_text_class(p)}"}>
                          {format_qty(p.stock_quantity)}
                        </span>
                        <span class="text-xs text-base-content/50 ml-1">{p.unit}</span>
                      </td>
                      <td class="text-sm text-base-content/50">
                        {format_qty(p.min_stock)} {p.unit}
                      </td>
                      <td>
                        <span class={"badge badge-sm whitespace-nowrap #{stock_badge_class(p)}"}>
                          {stock_label(p)}
                        </span>
                      </td>
                      <td class="text-right pr-4">
                        <%= if @editing_id == p.id do %>
                          <button
                            class="btn btn-ghost btn-xs text-base-content/40"
                            phx-click="cancel_edit"
                          >
                            Cancelar
                          </button>
                        <% else %>
                          <button
                            class="btn btn-sm btn-outline"
                            phx-click="start_edit"
                            phx-value-id={p.id}
                          >
                            <.icon name="hero-pencil-square" class="size-3.5" /> Actualizar
                          </button>
                        <% end %>
                      </td>
                    </tr>
                    <%!-- Inline edit row --%>
                    <%= if @editing_id == p.id do %>
                      <tr class="bg-primary/5 border-b border-primary/20">
                        <td colspan="5" class="px-6 py-4">
                          <.edit_form product={p} new_qty={@new_qty} notes={@notes} />
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # ---------------------------------------------------------------------------
  # Edit form component
  # ---------------------------------------------------------------------------

  attr :product, :map, required: true
  attr :new_qty, :string, required: true
  attr :notes, :string, required: true

  defp edit_form(assigns) do
    ~H"""
    <form phx-submit="save_stock" phx-change="form_change">
      <div class="flex flex-col sm:flex-row sm:items-end gap-3">
        <%!-- Nuevo stock --%>
        <div class="w-full sm:w-44 shrink-0">
          <label class="label py-0.5">
            <span class="label-text text-xs font-semibold text-primary">
              Nuevo stock
              <%= if @product.unit && @product.unit != "" do %>
                <span class="font-normal text-base-content/50">({@product.unit})</span>
              <% end %>
            </span>
          </label>
          <input
            type="number"
            name="new_qty"
            value={@new_qty}
            min="0"
            step="0.001"
            placeholder={"Ej: #{format_qty(@product.stock_quantity)}"}
            class="input input-bordered input-sm w-full focus:input-primary"
            autofocus
            required
            onblur="if(this.value){this.value=parseFloat(this.value).toFixed(3)}"
          />
          <p class="text-xs text-base-content/40 mt-0.5">
            Actual: <strong>{format_qty(@product.stock_quantity)}</strong>
            {if @product.unit && @product.unit != "", do: @product.unit}
            <.delta_preview new_qty={@new_qty} current={@product.stock_quantity} unit={@product.unit} />
          </p>
        </div>

        <%!-- Comentario --%>
        <div class="flex-1 min-w-0">
          <label class="label py-0.5">
            <span class="label-text text-xs font-semibold">Comentario</span>
            <span class="label-text-alt text-base-content/40 text-xs">Opcional</span>
          </label>
          <input
            type="text"
            name="notes"
            value={@notes}
            maxlength="200"
            placeholder="Ej: Conteo físico del turno mañana"
            class="input input-bordered input-sm w-full"
          />
        </div>

        <%!-- Botones --%>
        <div class="flex gap-2 shrink-0">
          <button type="submit" class="btn btn-primary btn-sm">
            <.icon name="hero-check" class="size-4" /> Guardar
          </button>
          <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">
            Cancelar
          </button>
        </div>
      </div>
    </form>
    """
  end

  # Shows +X or −X preview while the user types the new quantity
  defp delta_preview(%{new_qty: raw} = assigns) do
    delta =
      case Decimal.parse(raw) do
        {new, _} ->
          d = Decimal.sub(new, assigns.current)

          cond do
            Decimal.equal?(d, Decimal.new(0)) -> nil
            Decimal.positive?(d) -> "+#{format_qty(d)}"
            true -> "−#{format_qty(Decimal.abs(d))}"
          end

        :error ->
          nil
      end

    assigns = assign(assigns, :delta, delta)

    ~H"""
    <%= if @delta do %>
      <span class={"ml-1 font-bold #{if String.starts_with?(@delta, "+"), do: "text-success", else: "text-error"}"}>
        ({@delta} {@unit})
      </span>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_products do
    Inventory.list_products()
    |> Enum.filter(& &1.active)
    |> Enum.sort_by(fn p ->
      # Sort: critical first, then low stock, then ok; alphabetically within group
      {stock_sort_key(p), p.name}
    end)
  end

  defp visible_products(products, "low"),
    do: Enum.filter(products, &stock_is_low?/1)

  defp visible_products(products, "ok"),
    do: Enum.reject(products, &stock_is_low?/1)

  defp visible_products(products, _all), do: products

  defp search_filter(products, ""), do: products

  defp search_filter(products, query) do
    q = query |> String.trim() |> String.downcase()

    # Build search variants to handle Spanish plurals:
    # "totopos" → also try "totopo"; "chilaquiles" → also try "chilaquil" (strip "es")
    variants =
      [q, strip_plural(q)]
      |> Enum.uniq()
      |> Enum.reject(&(&1 == ""))

    Enum.filter(products, fn p ->
      name = String.downcase(p.name)
      Enum.any?(variants, &String.contains?(name, &1))
    end)
  end

  # Strips common Spanish plural suffixes to improve search recall.
  defp strip_plural(q) do
    cond do
      String.ends_with?(q, "es") and String.length(q) > 4 -> String.slice(q, 0..-3//1)
      String.ends_with?(q, "s") and String.length(q) > 2  -> String.slice(q, 0..-2//1)
      true -> q
    end
  end

  defp stock_is_low?(%{stock_quantity: qty, min_stock: min}) do
    Decimal.compare(qty, min) != :gt
  end

  # 0 = critical (zero or negative), 1 = low, 2 = ok
  defp stock_sort_key(p) do
    cond do
      Decimal.compare(p.stock_quantity, Decimal.new(0)) != :gt -> 0
      stock_is_low?(p) -> 1
      true -> 2
    end
  end

  defp stock_dot_class(p) do
    cond do
      Decimal.compare(p.stock_quantity, Decimal.new(0)) != :gt -> "bg-error"
      stock_is_low?(p) -> "bg-warning"
      true -> "bg-success"
    end
  end

  defp stock_text_class(p) do
    cond do
      Decimal.compare(p.stock_quantity, Decimal.new(0)) != :gt -> "text-error"
      stock_is_low?(p) -> "text-warning"
      true -> "text-success"
    end
  end

  defp stock_badge_class(p) do
    cond do
      Decimal.compare(p.stock_quantity, Decimal.new(0)) != :gt -> "badge-error"
      stock_is_low?(p) -> "badge-warning"
      true -> "badge-success badge-outline"
    end
  end

  defp stock_label(p) do
    cond do
      Decimal.compare(p.stock_quantity, Decimal.new(0)) != :gt -> "Sin stock"
      stock_is_low?(p) -> "Stock bajo"
      true -> "OK"
    end
  end

  defp format_qty(nil), do: "0"

  defp format_qty(%Decimal{} = d) do
    d = Decimal.abs(d)

    if Decimal.integer?(d),
      do: d |> Decimal.to_integer() |> to_string(),
      else:
        d
        |> Decimal.round(3)
        |> Decimal.to_string()
        |> String.trim_trailing("0")
        |> String.trim_trailing(".")
  end

  defp format_qty(v), do: to_string(v)
end
