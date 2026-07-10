defmodule CRCWeb.FaltantesLive do
  use CRCWeb, :live_view

  alias CRC.Inventory
  alias CRCWeb.Components.SiteComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "admin:products")
    end

    all_products = Inventory.list_all_active_products()

    {:ok,
     socket
     |> assign(
       page_title: "Faltantes",
       faltantes: Inventory.list_low_stock_products(),
       compras_hoy: Inventory.list_todays_purchases(),
       all_products: all_products,
       registrando: nil,
       qty_input: "",
       search: "",
       search_results: [],
       nav_open: false
     )}
  end

  @impl true
  def handle_info({:product_changed, _}, socket) do
    {:noreply,
     assign(socket,
       faltantes: Inventory.list_low_stock_products(),
       compras_hoy: Inventory.list_todays_purchases(),
       all_products: Inventory.list_all_active_products()
     )}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_nav", _params, socket) do
    {:noreply, update(socket, :nav_open, &(!&1))}
  end

  def handle_event("close_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, false)}
  end

  def handle_event("registrar", %{"id" => id}, socket) do
    {:noreply, assign(socket, registrando: String.to_integer(id), qty_input: "", search: "", search_results: [])}
  end

  def handle_event("registrar_otro", _params, socket) do
    {:noreply, assign(socket, registrando: :buscar, qty_input: "", search: "", search_results: [])}
  end

  def handle_event("cancelar", _params, socket) do
    {:noreply, assign(socket, registrando: nil, qty_input: "", search: "", search_results: [])}
  end

  def handle_event("search", %{"value" => q}, socket) do
    results =
      if String.length(String.trim(q)) >= 1 do
        q_down = String.downcase(q)
        Enum.filter(socket.assigns.all_products, fn p ->
          String.contains?(String.downcase(p.name), q_down)
        end)
        |> Enum.take(6)
      else
        []
      end

    {:noreply, assign(socket, search: q, search_results: results)}
  end

  def handle_event("select_product", %{"id" => id}, socket) do
    product_id = String.to_integer(id)
    {:noreply, assign(socket, registrando: product_id, search: "", search_results: [])}
  end

  def handle_event("confirmar_compra", %{"product_id" => id, "qty" => qty_str}, socket) do
    product_id = String.to_integer(id)
    user_id = socket.assigns.current_user && socket.assigns.current_user.id

    case parse_positive(qty_str) do
      {:ok, qty} ->
        case Inventory.create_stock_adjustment(
               %{product_id: product_id, quantity: qty, reason: "compra"},
               user_id
             ) do
          {:ok, _} ->
            faltantes = Inventory.list_low_stock_products()
            compras_hoy = Inventory.list_todays_purchases()

            Phoenix.PubSub.broadcast(CRC.PubSub, "admin:products", {:product_changed, %{id: product_id}})

            {:noreply,
             socket
             |> assign(faltantes: faltantes, compras_hoy: compras_hoy, registrando: nil, qty_input: "")
             |> put_flash(:info, "Compra registrada.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "No se pudo registrar. Intenta de nuevo.")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Ingresa una cantidad válida mayor a 0.")}
    end
  end

  @impl true
  def render(assigns) do
    selected =
      case assigns.registrando do
        nil -> nil
        :buscar -> nil
        id -> Enum.find(assigns.faltantes ++ assigns.all_products, &(&1.id == id))
      end

    assigns = assign(assigns, :selected_product, selected)

    ~H"""
    <SiteComponents.site_navbar
      nav_open={@nav_open}
      current_page={:faltantes}
      current_user={@current_user}
    />

    <div class="min-h-screen bg-base-200 pt-20">
      <div class="max-w-lg mx-auto px-4 py-6 pb-24">

        <%!-- Header --%>
        <h1 class="text-2xl font-bold text-base-content mb-1">Faltantes</h1>
        <p class="text-sm text-base-content/50 mb-6">Toca un insumo para registrar cuánto compraste</p>

        <%!-- All good state --%>
        <div :if={@faltantes == []} class="bg-base-100 rounded-2xl p-12 text-center shadow-sm">
          <div class="text-5xl mb-3">✅</div>
          <p class="font-semibold text-base-content">¡Todo en orden!</p>
          <p class="text-sm text-base-content/50 mt-1">No hay insumos por debajo del mínimo.</p>
        </div>

        <%!-- Faltantes: lista limpia --%>
        <div :if={@faltantes != []} class="bg-base-100 rounded-2xl shadow-sm overflow-hidden mb-4">
          <div class="px-4 py-3 border-b border-base-200 flex items-center justify-between">
            <span class="text-xs font-semibold text-base-content/50 uppercase tracking-widest">Hay que comprar</span>
            <span class="text-xs font-bold text-error">{length(@faltantes)} insumos</span>
          </div>
          <button
            :for={product <- @faltantes}
            type="button"
            phx-click="registrar"
            phx-value-id={product.id}
            class="w-full flex items-center gap-3 px-4 py-4 border-b border-base-200 last:border-0 hover:bg-base-50 active:bg-base-200 transition-colors text-left"
          >
            <%!-- Indicador --%>
            <div class={[
              "size-2.5 rounded-full shrink-0",
              if(Decimal.compare(product.stock_quantity, 0) == :eq, do: "bg-error", else: "bg-warning")
            ]}></div>

            <%!-- Nombre --%>
            <div class="flex-1 min-w-0">
              <p class="font-medium text-base-content">{product.name}</p>
              <p class="text-xs text-base-content/40 mt-0.5">
                Quedan <span class="font-semibold text-base-content/60">{format_qty(product.stock_quantity)} {product.unit}</span>
                · necesitas mín. <span class="font-semibold text-base-content/60">{format_qty(product.min_stock)} {product.unit}</span>
              </p>
            </div>

            <%!-- CTA --%>
            <span class="text-xs font-semibold text-primary shrink-0">Registrar →</span>
          </button>
        </div>

        <%!-- Otro insumo --%>
        <button
          type="button"
          phx-click="registrar_otro"
          class="w-full flex items-center gap-3 px-4 py-4 bg-base-100 rounded-2xl shadow-sm border-2 border-dashed border-base-300 hover:border-primary/40 hover:bg-base-50 transition-colors text-left mb-8"
        >
          <div class="size-8 rounded-full bg-base-200 flex items-center justify-center text-base-content/40 font-bold text-lg shrink-0">+</div>
          <div>
            <p class="font-medium text-base-content/70">Registrar otro insumo</p>
            <p class="text-xs text-base-content/40">Para algo que no está en la lista de arriba</p>
          </div>
        </button>

        <%!-- Registrado hoy --%>
        <div :if={@compras_hoy != []}>
          <p class="text-xs font-semibold text-base-content/40 uppercase tracking-widest mb-3">Registrado hoy</p>
          <div class="bg-base-100 rounded-2xl shadow-sm overflow-hidden">
            <div :for={adj <- @compras_hoy} class="flex items-center gap-3 px-4 py-3 border-b border-base-200 last:border-0">
              <div class="size-7 rounded-full bg-success/10 flex items-center justify-center shrink-0">
                <span class="text-success text-sm font-bold">✓</span>
              </div>
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-base-content truncate">{adj.product.name}</p>
                <p class="text-xs text-base-content/40">
                  {adj.adjusted_by && adj.adjusted_by.name} · {format_time(adj.inserted_at)}
                </p>
              </div>
              <span class="text-sm font-semibold text-success shrink-0">
                +{format_qty(adj.quantity)} {adj.product.unit}
              </span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Modal --%>
      <div :if={@registrando != nil} class="fixed inset-0 z-50 flex items-end sm:items-center justify-center">
        <div class="absolute inset-0 bg-black/50" phx-click="cancelar"></div>
        <div class="relative w-full sm:max-w-sm bg-base-100 rounded-t-3xl sm:rounded-2xl shadow-2xl p-6 pb-10 sm:pb-6">
          <div class="w-10 h-1 bg-base-300 rounded-full mx-auto mb-6 sm:hidden"></div>

          <%!-- Buscador --%>
          <div :if={@registrando == :buscar || @selected_product == nil}>
            <p class="text-lg font-bold text-base-content mb-4">¿Qué compraste?</p>
            <input
              type="text"
              placeholder="Escribe el nombre del insumo…"
              value={@search}
              phx-keyup="search"
              phx-debounce="150"
              name="q"
              class="input input-bordered w-full mb-2"
              autofocus
            />
            <div :if={@search_results != []} class="mt-1 rounded-xl overflow-hidden border border-base-200">
              <button
                :for={p <- @search_results}
                type="button"
                phx-click="select_product"
                phx-value-id={p.id}
                class="w-full flex items-center justify-between px-4 py-3 hover:bg-base-200 border-b border-base-200 last:border-0 transition-colors"
              >
                <span class="font-medium text-base-content">{p.name}</span>
                <span class="text-xs text-base-content/40">{format_qty(p.stock_quantity)} {p.unit}</span>
              </button>
            </div>
            <p :if={String.length(String.trim(@search)) >= 1 && @search_results == []}
               class="text-sm text-base-content/40 text-center py-6">
              No encontré ese insumo.
            </p>
          </div>

          <%!-- Formulario de cantidad --%>
          <div :if={@selected_product != nil && @registrando != :buscar}>
            <p class="text-xs text-base-content/40 uppercase tracking-wide font-semibold mb-1">Registrar compra</p>
            <p class="text-xl font-bold text-base-content mb-1">{@selected_product.name}</p>
            <p class="text-sm text-base-content/50 mb-6">
              Tienes <strong>{format_qty(@selected_product.stock_quantity)} {@selected_product.unit}</strong>
              y necesitas al menos <strong>{format_qty(@selected_product.min_stock)} {@selected_product.unit}</strong>
            </p>

            <form phx-submit="confirmar_compra">
              <input type="hidden" name="product_id" value={@selected_product.id} />
              <label class="text-sm font-semibold text-base-content mb-2 block">
                ¿Cuánto compraste? (en {@selected_product.unit})
              </label>
              <input
                type="number"
                inputmode="decimal"
                min="0.01"
                step="any"
                placeholder="0"
                name="qty"
                class="input input-bordered w-full text-2xl font-bold text-center h-16"
                autofocus
              />
              <button type="submit" phx-disable-with="Guardando..." class="btn btn-success w-full mt-4 text-base font-bold">
                ✓ Listo, lo registré
              </button>
            </form>
          </div>

          <button type="button" phx-click="cancelar" class="btn btn-ghost w-full mt-2 text-sm">
            Cancelar
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp parse_positive(str) do
    case Decimal.parse(String.trim(str)) do
      {d, ""} ->
        if Decimal.gt?(d, 0), do: {:ok, d}, else: :error
      _ ->
        :error
    end
  end

  defp format_qty(d) do
    d
    |> Decimal.round(2)
    |> Decimal.to_string()
    |> then(fn s ->
      if String.contains?(s, ".") do
        s |> String.trim_trailing("0") |> String.trim_trailing(".")
      else
        s
      end
    end)
  end

  defp utc_offset, do: Application.get_env(:crc, :utc_offset_hours, -6)

  defp format_time(%DateTime{} = dt) do
    local = DateTime.add(dt, utc_offset() * 3600, :second)
    pad2 = fn n -> String.pad_leading(to_string(n), 2, "0") end
    "#{pad2.(local.hour)}:#{pad2.(local.minute)}"
  end

  defp format_time(_), do: ""
end
