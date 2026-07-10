defmodule CRCWeb.Admin.ProductsLive do
  @moduledoc "Inventory (insumos) management from the administration panel."

  use CRCWeb, :live_view

  alias CRC.Inventory
  alias CRC.Inventory.Product
  alias CRC.Inventory.ProductVariant

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(CRC.PubSub, "admin:products")

    products = Inventory.list_products()
    low_stock = Enum.count(products, &low_stock?/1)

    socket =
      socket
      |> assign(:page_title, "Insumos · Admin")
      |> assign(:products, products)
      |> assign(:low_stock_count, low_stock)
      |> assign(:suppliers, Inventory.list_active_suppliers())
      |> assign(:categories, Inventory.list_product_categories())
      |> assign(:filter_category, "all")
      |> assign(:status_filter, :active)
      |> assign(:modal, nil)
      |> assign(:form, nil)
      |> assign(:variant_form, nil)
      |> assign(:editing_variant_id, nil)
      |> assign(:purchase_total, "")
      |> assign(:purchase_qty, "")
      |> assign(:search, "")
      |> assign(:page, 1)
      |> assign(:per_page, 25)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:product_changed, _product}, socket) do
    products = Inventory.list_products()
    low_stock = Enum.count(products, &low_stock?/1)

    # If a product is open in the edit modal, refresh its variants
    updated_modal =
      case socket.assigns.modal do
        {:edit, product} ->
          {:edit, Inventory.get_product!(product.id)}

        other ->
          other
      end

    {:noreply,
     socket
     |> assign(:products, products)
     |> assign(:low_stock_count, low_stock)
     |> assign(:suppliers, Inventory.list_active_suppliers())
     |> assign(:categories, Inventory.list_product_categories())
     |> assign(:modal, updated_modal)}
  end

  # ---------------------------------------------------------------------------
  # Product events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("filter_category", %{"category" => cat}, socket) do
    {:noreply, socket |> assign(:filter_category, cat) |> assign(:page, 1)}
  end

  def handle_event("set_status_filter", %{"status" => status}, socket) do
    {:noreply,
     socket |> assign(:status_filter, String.to_existing_atom(status)) |> assign(:page, 1)}
  end

  def handle_event("search_products", %{"value" => query}, socket) do
    {:noreply, socket |> assign(:search, query) |> assign(:page, 1)}
  end

  def handle_event("go_page", %{"page" => page}, socket) do
    {:noreply, assign(socket, :page, String.to_integer(page))}
  end

  def handle_event("new_product", _params, socket) do
    changeset = Inventory.change_product(%Product{})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:form, to_form(changeset))
     |> assign(:variant_form, nil)
     |> assign(:editing_variant_id, nil)
     |> assign(:purchase_total, "")
     |> assign(:purchase_qty, "")}
  end

  def handle_event("edit_product", %{"id" => id}, socket) do
    product = Inventory.get_product!(String.to_integer(id))
    changeset = Inventory.change_product(product)

    {:noreply,
     socket
     |> assign(:modal, {:edit, product})
     |> assign(:form, to_form(changeset))
     |> assign(:variant_form, nil)
     |> assign(:editing_variant_id, nil)
     |> assign(:purchase_total, "")
     |> assign(:purchase_qty, "")}
  end

  # Live-validates the form and auto-calculates net_cost when purchase helpers are filled.
  def handle_event("validate_product", params, socket) do
    product_params = Map.get(params, "product", %{})
    purchase_total = Map.get(params, "purchase_total", "")
    purchase_qty = Map.get(params, "purchase_qty", "")

    product_params = maybe_calc_unit_cost(product_params, purchase_total, purchase_qty)

    product =
      case socket.assigns.modal do
        {:edit, p} -> p
        _ -> %Product{}
      end

    changeset =
      product
      |> Inventory.change_product(product_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:purchase_total, purchase_total)
     |> assign(:purchase_qty, purchase_qty)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(modal: nil, form: nil, variant_form: nil, editing_variant_id: nil)}
  end

  def handle_event("save_product", %{"product" => params}, socket) do
    result =
      case socket.assigns.modal do
        :new -> Inventory.create_product(params)
        {:edit, product} -> Inventory.update_product(product, params)
      end

    case result do
      {:ok, product} ->
        products = Inventory.list_products()
        low_stock = Enum.count(products, &low_stock?/1)

        base =
          socket
          |> assign(:products, products)
          |> assign(:low_stock_count, low_stock)
          |> assign(:categories, Inventory.list_product_categories())
          |> assign(:variant_form, nil)
          |> assign(:editing_variant_id, nil)

        if socket.assigns.modal == :new do
          # After creating, open the edit modal so the user can add tipos right away
          fresh = Inventory.get_product!(product.id)
          changeset = Inventory.change_product(fresh)

          {:noreply,
           base
           |> put_flash(:info, "Insumo creado. Ahora puedes agregar los tipos.")
           |> assign(:modal, {:edit, fresh})
           |> assign(:form, to_form(changeset))}
        else
          {:noreply,
           base
           |> put_flash(:info, "Insumo actualizado correctamente.")
           |> assign(:modal, nil)
           |> assign(:form, nil)}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    product = Inventory.get_product!(String.to_integer(id))

    case Inventory.toggle_product_active(product) do
      {:ok, _} ->
        action = if product.active, do: "desactivado", else: "activado"
        products = Inventory.list_products()
        low_stock = Enum.count(products, &low_stock?/1)

        {:noreply,
         socket
         |> put_flash(:info, "Insumo #{action} correctamente.")
         |> assign(:products, products)
         |> assign(:low_stock_count, low_stock)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo cambiar el estado del insumo.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Variant events
  # ---------------------------------------------------------------------------

  def handle_event("new_variant_form", _params, socket) do
    changeset = Inventory.change_variant(%ProductVariant{})

    {:noreply,
     socket
     |> assign(:variant_form, to_form(changeset, as: :variant))
     |> assign(:editing_variant_id, nil)}
  end

  def handle_event("edit_variant_form", %{"id" => id}, socket) do
    variant = Inventory.get_variant!(String.to_integer(id))
    changeset = Inventory.change_variant(variant)

    {:noreply,
     socket
     |> assign(:variant_form, to_form(changeset, as: :variant))
     |> assign(:editing_variant_id, variant.id)}
  end

  def handle_event("cancel_variant_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:variant_form, nil)
     |> assign(:editing_variant_id, nil)}
  end

  def handle_event("save_variant", %{"variant" => params}, socket) do
    {:edit, product} = socket.assigns.modal

    result =
      case socket.assigns.editing_variant_id do
        nil ->
          Inventory.create_variant(product.id, params)

        variant_id ->
          variant = Inventory.get_variant!(variant_id)
          Inventory.update_variant(variant, params)
      end

    case result do
      {:ok, _variant} ->
        label = if socket.assigns.editing_variant_id, do: "actualizado", else: "agregado"
        fresh_product = Inventory.get_product!(product.id)

        {:noreply,
         socket
         |> put_flash(:info, "Tipo #{label} correctamente.")
         |> assign(:modal, {:edit, fresh_product})
         |> assign(:variant_form, nil)
         |> assign(:editing_variant_id, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :variant_form, to_form(changeset, as: :variant))}
    end
  end

  def handle_event("delete_variant", %{"id" => id}, socket) do
    variant = Inventory.get_variant!(String.to_integer(id))
    {:edit, product} = socket.assigns.modal

    case Inventory.delete_variant(variant) do
      {:ok, _} ->
        fresh_product = Inventory.get_product!(product.id)

        {:noreply,
         socket
         |> put_flash(:info, "Tipo eliminado.")
         |> assign(:modal, {:edit, fresh_product})
         |> assign(:variant_form, nil)
         |> assign(:editing_variant_id, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo eliminar el tipo.")}
    end
  end

  def handle_event("toggle_variant_active", %{"id" => id}, socket) do
    variant = Inventory.get_variant!(String.to_integer(id))
    {:edit, product} = socket.assigns.modal

    case Inventory.toggle_variant_active(variant) do
      {:ok, _} ->
        fresh_product = Inventory.get_product!(product.id)
        {:noreply, assign(socket, :modal, {:edit, fresh_product})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo cambiar el estado del tipo.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <% by_status = filter_by_status(@products, @status_filter) %>
    <% by_category = filtered_products(by_status, @filter_category) %>
    <% filtered = search_filter(by_category, @search) %>
    <% total_pages = max(1, ceil(length(filtered) / @per_page)) %>
    <% visible = paginate(filtered, @page, @per_page) %>
    <% active_count = Enum.count(@products, & &1.active) %>
    <% inactive_count = Enum.count(@products, &(!&1.active)) %>
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Insumos</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            {length(filtered)} insumos {if @status_filter == :active, do: "activos", else: "inactivos"}
            <%= if @status_filter == :active && @low_stock_count > 0 do %>
              · <span class="text-warning font-medium">{@low_stock_count} con stock bajo</span>
            <% end %>
          </p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="new_product">
          <.icon name="hero-plus" class="size-4" /> Nuevo insumo
        </button>
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
          phx-keyup="search_products"
          phx-debounce="200"
        />
      </div>

      <%!-- Status tabs --%>
      <div class="flex gap-2">
        <button
          class={[
            "btn btn-sm gap-1.5",
            if(@status_filter == :active, do: "btn-primary", else: "btn-ghost")
          ]}
          phx-click="set_status_filter"
          phx-value-status="active"
        >
          <.icon name="hero-check-circle" class="size-3.5" /> Activos
          <span class={[
            "badge badge-xs",
            if(@status_filter == :active, do: "badge-primary-content/30", else: "badge-ghost")
          ]}>
            {active_count}
          </span>
        </button>
        <button
          class={[
            "btn btn-sm gap-1.5",
            if(@status_filter == :inactive, do: "btn-error", else: "btn-ghost")
          ]}
          phx-click="set_status_filter"
          phx-value-status="inactive"
        >
          <.icon name="hero-x-circle" class="size-3.5" /> Inactivos
          <span class={[
            "badge badge-xs",
            if(@status_filter == :inactive, do: "badge-error-content/30", else: "badge-ghost")
          ]}>
            {inactive_count}
          </span>
        </button>
      </div>

      <%!-- Category filter tabs --%>
      <div class="flex gap-2 overflow-x-auto pb-1 scrollbar-hide">
        <.filter_tab value="all" current={@filter_category} label="Todos" />
        <%= for cat <- @categories do %>
          <.filter_tab value={to_string(cat.id)} current={@filter_category} label={cat.name} />
        <% end %>
      </div>

      <%!-- ── Mobile card list (< md) ──────────────────────────────────────── --%>
      <div class="md:hidden flex flex-col gap-2">
        <%= if visible == [] do %>
          <div class="text-center py-12 text-base-content/40 text-sm bg-base-100 rounded-2xl border border-base-300">
            {cond do
              @status_filter == :inactive && @filter_category == "all" -> "No hay insumos inactivos."
              @status_filter == :inactive -> "No hay insumos inactivos en esta categoría."
              @filter_category != "all" -> "No hay insumos en esta categoría."
              true -> "No hay insumos registrados. Crea el primero."
            end}
          </div>
        <% end %>
        <%= for product <- visible do %>
          <% has_variants = product.variants != [] %>
          <% variant_low_stock = Enum.any?(product.variants, &variant_low_stock?/1) %>
          <% is_low = low_stock?(product) or variant_low_stock %>
          <div class={[
            "bg-base-100 rounded-2xl border shadow-sm p-3 flex items-center gap-3",
            if(is_low, do: "border-warning/40 bg-warning/5", else: "border-base-300")
          ]}>
            <div class={[
              "flex items-center justify-center w-10 h-10 rounded-xl shrink-0",
              if(is_low, do: "bg-warning/15", else: "bg-primary/10")
            ]}>
              <%= if is_low do %>
                <.icon name="hero-exclamation-triangle" class="size-5 text-warning" />
              <% else %>
                <.icon name="hero-beaker" class="size-5 text-primary" />
              <% end %>
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 flex-wrap">
                <p class="font-semibold text-sm text-base-content truncate">{product.name}</p>
                <%= if product.active do %>
                  <span class="badge badge-xs badge-success shrink-0">Activo</span>
                <% else %>
                  <span class="badge badge-xs badge-error shrink-0">Inactivo</span>
                <% end %>
              </div>
              <div class="flex items-center gap-2 mt-1 flex-wrap">
                <%= if product.product_category do %>
                  <span class="badge badge-xs badge-ghost">{product.product_category.name}</span>
                <% end %>
                <span class={[
                  "text-xs font-medium",
                  if(low_stock?(product), do: "text-warning", else: "text-base-content/70")
                ]}>
                  Stock: {format_quantity(product.stock_quantity)} {unit_abbr(product.unit)}
                </span>
                <span class="text-xs text-base-content/40">
                  Mín: {format_quantity(product.min_stock)} {unit_abbr(product.unit)}
                </span>
              </div>
              <div class="flex items-center gap-3 mt-1">
                <span class="text-xs text-base-content/70">
                  ${format_price(product.net_cost)} costo
                </span>
                <%= if product.sale_price do %>
                  <span class="text-xs text-base-content/50">
                    ${format_price(product.sale_price)} venta
                  </span>
                <% end %>
                <%= if product.supplier do %>
                  <span class="text-xs text-base-content/40 truncate">{product.supplier.name}</span>
                <% end %>
              </div>
              <%= if has_variants and variant_low_stock do %>
                <p class="text-xs text-warning mt-0.5">Stock bajo en algún tipo</p>
              <% end %>
            </div>
            <div class="flex flex-col items-center gap-1 shrink-0">
              <button
                class="btn btn-ghost btn-xs btn-circle"
                phx-click="edit_product"
                phx-value-id={product.id}
                title="Editar"
              >
                <.icon name="hero-pencil" class="size-4" />
              </button>
              <button
                class={[
                  "btn btn-ghost btn-xs btn-circle",
                  if(product.active, do: "text-error", else: "text-success")
                ]}
                phx-click="toggle_active"
                phx-value-id={product.id}
                title={if product.active, do: "Desactivar", else: "Activar"}
              >
                <.icon
                  name={if product.active, do: "hero-no-symbol", else: "hero-check-circle"}
                  class="size-4"
                />
              </button>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- ── Desktop table (md+) ────────────────────────────────────────────── --%>
      <div class="hidden md:block bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
          <table class="table table-zebra table-fixed w-full">
            <thead>
              <tr class="bg-base-200 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                <th class="w-[22%]">Nombre</th>
                <th class="w-[12%]">Categoría</th>
                <th class="w-[10%]">Stock</th>
                <th class="w-[8%]">Mín.</th>
                <th class="w-[10%]">Costo neto</th>
                <th class="w-[10%]">Precio venta</th>
                <th class="w-[14%]">Proveedor</th>
                <th class="w-[8%]">Estado</th>
                <th class="w-[6%] text-right">Acciones</th>
              </tr>
            </thead>
            <tbody>
              <%= for product <- visible do %>
                <% has_variants = product.variants != [] %>
                <% variant_low_stock = Enum.any?(product.variants, &variant_low_stock?/1) %>
                <tr class={[
                  "hover:bg-base-200/50 transition-colors",
                  if(low_stock?(product) or variant_low_stock, do: "bg-warning/5")
                ]}>
                  <td class="max-w-0">
                    <div class="flex items-center gap-2">
                      <%= if low_stock?(product) or variant_low_stock do %>
                        <.icon name="hero-exclamation-triangle" class="size-4 text-warning shrink-0" />
                      <% end %>
                      <div class="min-w-0">
                        <span class="font-medium text-sm text-base-content truncate block">
                          {product.name}
                        </span>
                        <%= if has_variants do %>
                          <p class="text-xs text-base-content/40 mt-0.5 truncate">
                            {length(product.variants)} tipo{if length(product.variants) != 1,
                              do: "s",
                              else: ""}
                            <%= if variant_low_stock do %>
                              · <span class="text-warning">stock bajo</span>
                            <% end %>
                          </p>
                        <% end %>
                      </div>
                    </div>
                  </td>
                  <td>
                    <span class="badge badge-sm badge-ghost">
                      {if product.product_category, do: product.product_category.name, else: "—"}
                    </span>
                  </td>
                  <td class="text-sm font-medium">
                    <span class={
                      if low_stock?(product), do: "text-warning", else: "text-base-content"
                    }>
                      {format_quantity(product.stock_quantity)} {unit_abbr(product.unit)}
                    </span>
                  </td>
                  <td class="text-sm text-base-content/60">
                    {format_quantity(product.min_stock)} {unit_abbr(product.unit)}
                  </td>
                  <td class="text-sm text-base-content">${format_price(product.net_cost)}</td>
                  <td class="text-sm text-base-content/70">
                    {if product.sale_price, do: "$#{format_price(product.sale_price)}", else: "—"}
                  </td>
                  <td class="max-w-0 text-sm text-base-content/60 truncate">
                    {if product.supplier, do: product.supplier.name, else: "—"}
                  </td>
                  <td>
                    <%= if product.active do %>
                      <span class="badge badge-sm badge-success">Activo</span>
                    <% else %>
                      <span class="badge badge-sm badge-error">Inactivo</span>
                    <% end %>
                  </td>
                  <td>
                    <div class="flex items-center justify-end gap-1">
                      <button
                        class="btn btn-ghost btn-xs btn-circle"
                        phx-click="edit_product"
                        phx-value-id={product.id}
                        title="Editar"
                      >
                        <.icon name="hero-pencil" class="size-4" />
                      </button>
                      <button
                        class={[
                          "btn btn-ghost btn-xs btn-circle",
                          if(product.active, do: "text-error", else: "text-success")
                        ]}
                        phx-click="toggle_active"
                        phx-value-id={product.id}
                        title={if product.active, do: "Desactivar", else: "Activar"}
                      >
                        <.icon
                          name={if product.active, do: "hero-no-symbol", else: "hero-check-circle"}
                          class="size-4"
                        />
                      </button>
                    </div>
                  </td>
                </tr>
              <% end %>
              <%= if visible == [] do %>
                <tr>
                  <td colspan="9" class="text-center py-12 text-base-content/40 text-sm">
                    {cond do
                      @status_filter == :inactive && @filter_category == "all" ->
                        "No hay insumos inactivos."

                      @status_filter == :inactive ->
                        "No hay insumos inactivos en esta categoría."

                      @filter_category != "all" ->
                        "No hay insumos en esta categoría."

                      true ->
                        "No hay insumos registrados. Crea el primero."
                    end}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <%!-- Pagination --%>
    <%= if total_pages > 1 do %>
      <div class="flex items-center justify-center gap-2 flex-wrap">
        <button
          class="btn btn-sm btn-ghost gap-1"
          phx-click="go_page"
          phx-value-page={@page - 1}
          disabled={@page <= 1}
        >
          <.icon name="hero-chevron-left" class="size-3.5" /> Anterior
        </button>
        <%= for p <- 1..total_pages do %>
          <button
            class={["btn btn-sm", if(p == @page, do: "btn-primary", else: "btn-ghost")]}
            phx-click="go_page"
            phx-value-page={p}
          >
            {p}
          </button>
        <% end %>
        <button
          class="btn btn-sm btn-ghost gap-1"
          phx-click="go_page"
          phx-value-page={@page + 1}
          disabled={@page >= total_pages}
        >
          Siguiente <.icon name="hero-chevron-right" class="size-3.5" />
        </button>
      </div>
    <% end %>

    <%!-- Modal: new / edit product --%>
    <%= if @modal != nil do %>
      <.product_modal
        form={@form}
        modal={@modal}
        suppliers={@suppliers}
        categories={@categories}
        variant_form={@variant_form}
        editing_variant_id={@editing_variant_id}
        purchase_total={@purchase_total}
        purchase_qty={@purchase_qty}
      />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Product modal
  # ---------------------------------------------------------------------------

  attr :form, :map, required: true
  attr :modal, :any, required: true
  attr :suppliers, :list, required: true
  attr :categories, :list, required: true
  attr :variant_form, :any, required: true
  attr :editing_variant_id, :any, required: true
  attr :purchase_total, :string, required: true
  attr :purchase_qty, :string, required: true

  defp product_modal(assigns) do
    is_edit = match?({:edit, _}, assigns.modal)
    title = if is_edit, do: "Editar insumo", else: "Nuevo insumo"

    product =
      case assigns.modal do
        {:edit, p} -> p
        _ -> nil
      end

    assigns =
      assigns
      |> assign(:title, title)
      |> assign(:is_edit, is_edit)
      |> assign(:product, product)

    ~H"""
    <div
      id="product-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_modal"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_modal"></div>

      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-2xl overflow-y-auto max-h-[90vh]">
        <%!-- Modal header --%>
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between sticky top-0 bg-base-100 z-10">
          <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="px-6 py-5 space-y-5">
          <%!-- Step flow indicator --%>
          <div class="flex items-center gap-2 text-xs text-base-content/50 flex-wrap">
            <span class="flex items-center gap-1 font-semibold text-primary">
              <span class="size-5 rounded-full bg-primary text-primary-content flex items-center justify-center font-bold text-[10px]">1</span>
              Elige la unidad
            </span>
            <span class="text-base-content/30">→</span>
            <span class="flex items-center gap-1">
              <span class="size-5 rounded-full bg-base-300 text-base-content flex items-center justify-center font-bold text-[10px]">2</span>
              Calcula el costo
            </span>
            <span class="text-base-content/30">→</span>
            <span class="flex items-center gap-1">
              <span class="size-5 rounded-full bg-base-300 text-base-content flex items-center justify-center font-bold text-[10px]">3</span>
              Registra el stock
            </span>
          </div>

          <%!-- Product form --%>
          <.form
            id="product-form"
            for={@form}
            phx-submit="save_product"
            phx-change="validate_product"
            class="space-y-4"
          >
            <%!-- Name + Category (2 cols) --%>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <.input
                field={@form[:name]}
                type="text"
                label="Nombre del insumo"
                placeholder="Ej. Leche, Café molido, Vaso 12oz"
              />
              <.input
                field={@form[:product_category_id]}
                type="select"
                label="Categoría (opcional)"
                options={[{"— Sin categoría —", ""} | Enum.map(@categories, &{&1.name, &1.id})]}
              />
            </div>

            <%!-- STEP 1 — Unit (prominent, with warning) --%>
            <div class="rounded-xl border-2 border-primary/25 bg-primary/4 p-4 space-y-2">
              <p class="text-xs font-bold text-primary flex items-center gap-1.5">
                <span class="size-5 rounded-full bg-primary text-primary-content flex items-center justify-center font-bold text-[10px]">1</span>
                Unidad de medida — elige primero
              </p>
              <.input
                field={@form[:unit]}
                type="select"
                label=""
                options={unit_options()}
              />
              <% unit_val = @form[:unit].value || "" %>
              <%= if unit_val != "" do %>
                <p class="text-xs text-base-content/60 leading-relaxed">
                  <strong>Todo lo demás usa {unit_label(unit_val)}.</strong>
                  El stock, el stock mínimo, la calculadora y las recetas de tus platillos
                  deben expresarse siempre en {unit_label(unit_val)}.
                  {unit_example(unit_val)}
                </p>
              <% else %>
                <p class="text-xs text-warning flex items-center gap-1">
                  <.icon name="hero-exclamation-triangle" class="size-3.5 shrink-0" />
                  Selecciona la unidad antes de continuar — todo lo demás depende de ella.
                </p>
              <% end %>
            </div>

            <%!-- STEP 2 — Cost calculator --%>
            <% unit_val = @form[:unit].value || "" %>
            <div class="rounded-xl border border-base-300 bg-base-200/40 p-4 space-y-3">
              <p class="text-xs font-bold text-base-content/70 flex items-center gap-1.5">
                <span class="size-5 rounded-full bg-base-300 text-base-content flex items-center justify-center font-bold text-[10px]">2</span>
                Costo del insumo
              </p>

              <%!-- Calculator sub-section --%>
              <div class="rounded-lg border border-dashed border-base-content/20 bg-base-100 p-3 space-y-2">
                <p class="text-xs text-base-content/50 font-medium">
                  🧮 Calculadora — si no sabes el costo por unidad, llena estos dos campos
                </p>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div class="form-control">
                    <label class="label py-0.5">
                      <span class="label-text text-xs font-medium">¿Cuánto pagaste en total? ($)</span>
                    </label>
                    <input
                      type="number"
                      name="purchase_total"
                      value={@purchase_total}
                      min="0"
                      step="0.01"
                      placeholder="Ej: 100.00"
                      class="input input-bordered input-sm w-full"
                    />
                    <p class="text-xs text-base-content/40 mt-0.5">El precio que pagaste por toda la compra</p>
                  </div>
                  <div class="form-control">
                    <label class="label py-0.5">
                      <span class="label-text text-xs font-medium">
                        ¿Cuánto{if unit_val != "", do: " (en #{unit_label(unit_val)})", else: ""} compraste?
                      </span>
                    </label>
                    <input
                      type="number"
                      name="purchase_qty"
                      value={@purchase_qty}
                      min="0"
                      step="0.001"
                      placeholder={unit_qty_placeholder(unit_val)}
                      class="input input-bordered input-sm w-full"
                      onblur="if(this.value){this.value=parseFloat(this.value).toFixed(3)}"
                    />
                    <p class="text-xs text-base-content/40 mt-0.5">
                      {unit_qty_hint(unit_val)}
                    </p>
                  </div>
                </div>
                <%= if @purchase_total != "" and @purchase_qty != "" do %>
                  <% total = Decimal.parse(@purchase_total) %>
                  <% qty = Decimal.parse(@purchase_qty) %>
                  <%= case {total, qty} do %>
                    <% {{t, _}, {q, _}} when true -> %>
                      <%= if Decimal.compare(q, 0) == :gt and Decimal.compare(t, 0) == :gt do %>
                        <% unit_cost = t |> Decimal.div(q) |> Decimal.round(4) %>
                        <div class="flex items-center gap-2 rounded-lg bg-success/10 border border-success/30 px-3 py-2">
                          <.icon name="hero-check-circle" class="size-4 text-success shrink-0" />
                          <p class="text-xs text-success font-semibold">
                            Costo por {if unit_val != "", do: unit_label(unit_val), else: "unidad"}:
                            <span class="text-base">${Decimal.to_string(unit_cost)}</span>
                            → se aplicó en "Costo neto" abajo
                          </p>
                        </div>
                      <% else %>
                        <p class="text-xs text-error flex items-center gap-1">
                          <.icon name="hero-x-circle" class="size-3.5" />
                          Los valores deben ser mayores a 0.
                        </p>
                      <% end %>
                    <% _ -> %>
                      <p class="text-xs text-error flex items-center gap-1">
                        <.icon name="hero-x-circle" class="size-3.5" />
                        Escribe números válidos en ambos campos.
                      </p>
                  <% end %>
                <% end %>
              </div>

              <%!-- Net cost (auto-filled or manual) --%>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <.input
                    field={@form[:net_cost]}
                    type="number"
                    label={"Costo neto por #{if unit_val != "", do: unit_label(unit_val), else: "unidad"} ($)"}
                    placeholder="0.0000"
                    step="0.0001"
                    min="0"
                  />
                  <p class="text-xs text-base-content/40 mt-1 leading-relaxed">
                    Lo que te cuesta <strong>una sola {if unit_val != "", do: unit_label(unit_val), else: "unidad"}</strong>.
                    Si usaste la calculadora ya está listo; si no, escríbelo directo.
                  </p>
                </div>
                <div>
                  <.input
                    field={@form[:sale_price]}
                    type="number"
                    label="Precio de venta ($) (opcional)"
                    placeholder="0.00"
                    step="0.01"
                    min="0"
                  />
                  <p class="text-xs text-base-content/40 mt-1">
                    Solo si vendes este insumo directamente a un cliente (ej. bebidas embotelladas). La mayoría de insumos lo dejan vacío.
                  </p>
                </div>
              </div>
            </div>

            <%!-- STEP 3 — Stock --%>
            <div class="rounded-xl border border-base-300 bg-base-200/40 p-4 space-y-3">
              <p class="text-xs font-bold text-base-content/70 flex items-center gap-1.5">
                <span class="size-5 rounded-full bg-base-300 text-base-content flex items-center justify-center font-bold text-[10px]">3</span>
                Stock
              </p>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <.input
                    field={@form[:stock_quantity]}
                    type="number"
                    label={"¿Cuánto#{if unit_val != "", do: " (#{unit_label(unit_val)})", else: ""} tienes hoy?"}
                    placeholder="0.000"
                    step="0.001"
                    min="0"
                    onblur="if(this.value){this.value=parseFloat(this.value).toFixed(3)}"
                  />
                  <p class="text-xs text-base-content/40 mt-1">
                    El sistema lo descuenta automáticamente cada vez que se envía un pedido a cocina.
                  </p>
                </div>
                <div>
                  <.input
                    field={@form[:min_stock]}
                    type="number"
                    label={"Avisar cuando baje de#{if unit_val != "", do: " (#{unit_label(unit_val)})", else: ""}"}
                    placeholder="0.000"
                    step="0.001"
                    min="0"
                    onblur="if(this.value){this.value=parseFloat(this.value).toFixed(3)}"
                  />
                  <p class="text-xs text-base-content/40 mt-1">
                    {unit_min_stock_hint(unit_val)}
                  </p>
                </div>
              </div>
            </div>

            <%!-- Supplier + Notes --%>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <.input
                field={@form[:supplier_id]}
                type="select"
                label="Proveedor (opcional)"
                options={[{"— Sin proveedor —", ""} | Enum.map(@suppliers, &{&1.name, &1.id})]}
              />
              <.input
                field={@form[:notes]}
                type="textarea"
                label="Notas (opcional)"
                placeholder="Marca, presentación, observaciones..."
              />
            </div>

            <div class="flex justify-end gap-3 pt-1">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
              <button type="submit" class="btn btn-primary">
                {if !@is_edit, do: "Crear insumo", else: "Guardar cambios"}
              </button>
            </div>
          </.form>

          <%!-- Variants section — only visible when editing --%>
          <%= if @is_edit do %>
            <div class="border-t border-base-200 pt-5">
              <div class="flex items-center justify-between mb-3">
                <div>
                  <h3 class="font-semibold text-base-content text-sm">Tipos de este insumo</h3>
                  <p class="text-xs text-base-content/50 mt-0.5">
                    Opcional · por ejemplo: Entera, Avena, Deslactosada para Leche
                  </p>
                </div>
                <%= if is_nil(@variant_form) do %>
                  <button
                    type="button"
                    class="btn btn-sm btn-outline gap-1.5"
                    phx-click="new_variant_form"
                  >
                    <.icon name="hero-plus" class="size-3.5" /> Agregar tipo
                  </button>
                <% end %>
              </div>

              <%!-- Existing variants list --%>
              <%= if @product.variants != [] do %>
                <div class="space-y-2 mb-4">
                  <%= for variant <- @product.variants do %>
                    <% is_editing = @editing_variant_id == variant.id %>
                    <% v_low = variant_low_stock?(variant) %>
                    <div class={[
                      "rounded-xl border p-3",
                      if(is_editing,
                        do: "border-primary/30 bg-primary/5",
                        else: "border-base-200 bg-base-50"
                      ),
                      if(v_low and not is_editing, do: "border-warning/30 bg-warning/5", else: "")
                    ]}>
                      <%= if is_editing do %>
                        <%!-- Inline edit form --%>
                        <.variant_form_fields
                          form={@variant_form}
                          unit={@product.unit}
                          on_cancel="cancel_variant_form"
                          submit_label="Guardar tipo"
                        />
                      <% else %>
                        <%!-- Variant row display --%>
                        <div class="flex items-start justify-between gap-3">
                          <div class="flex-1 min-w-0">
                            <div class="flex items-center gap-2 flex-wrap">
                              <span class="font-medium text-sm text-base-content">
                                {variant.name}
                              </span>
                              <%= if not variant.active do %>
                                <span class="badge badge-xs badge-error">Inactivo</span>
                              <% end %>
                              <%= if v_low do %>
                                <span class="badge badge-xs badge-warning gap-1">
                                  <.icon name="hero-exclamation-triangle" class="size-2.5" />
                                  Stock bajo
                                </span>
                              <% end %>
                              <%= if Decimal.compare(variant.extra_charge, 0) == :gt do %>
                                <span class="badge badge-xs badge-info">
                                  +${format_price(variant.extra_charge)}
                                </span>
                              <% end %>
                            </div>
                            <p class="text-xs text-base-content/50 mt-1">
                              Stock: {format_quantity(variant.stock_quantity)} {unit_abbr(
                                @product.unit
                              )} · Mín: {format_quantity(variant.min_stock)} {unit_abbr(@product.unit)}
                            </p>
                          </div>
                          <div class="flex items-center gap-1 shrink-0">
                            <button
                              type="button"
                              class="btn btn-ghost btn-xs"
                              phx-click="edit_variant_form"
                              phx-value-id={variant.id}
                              title="Editar tipo"
                            >
                              <.icon name="hero-pencil" class="size-3.5" />
                            </button>
                            <button
                              type="button"
                              class={[
                                "btn btn-ghost btn-xs",
                                if(variant.active, do: "text-error", else: "text-success")
                              ]}
                              phx-click="toggle_variant_active"
                              phx-value-id={variant.id}
                              title={if variant.active, do: "Desactivar", else: "Activar"}
                            >
                              <.icon
                                name={
                                  if variant.active, do: "hero-no-symbol", else: "hero-check-circle"
                                }
                                class="size-3.5"
                              />
                            </button>
                            <button
                              type="button"
                              class="btn btn-ghost btn-xs text-error"
                              phx-click="delete_variant"
                              phx-value-id={variant.id}
                              title="Eliminar tipo"
                              data-confirm={"¿Eliminar el tipo \"#{variant.name}\"? Esta acción no se puede deshacer."}
                            >
                              <.icon name="hero-trash" class="size-3.5" />
                            </button>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <%= if is_nil(@variant_form) do %>
                  <p class="text-sm text-base-content/40 italic mb-4">
                    Sin tipos definidos. Este insumo se registra como una sola variedad.
                  </p>
                <% end %>
              <% end %>

              <%!-- New variant form (shown when adding) --%>
              <%= if not is_nil(@variant_form) and is_nil(@editing_variant_id) do %>
                <div class="rounded-xl border border-primary/30 bg-primary/5 p-4">
                  <p class="text-xs font-semibold text-primary mb-3 uppercase tracking-wide">
                    Nuevo tipo
                  </p>
                  <.variant_form_fields
                    form={@variant_form}
                    unit={@product.unit}
                    on_cancel="cancel_variant_form"
                    submit_label="Agregar tipo"
                  />
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Variant form fields component
  # ---------------------------------------------------------------------------

  attr :form, :map, required: true
  attr :unit, :string, required: true
  attr :on_cancel, :string, required: true
  attr :submit_label, :string, required: true

  defp variant_form_fields(assigns) do
    ~H"""
    <.form for={@form} phx-submit="save_variant" class="space-y-3">
      <.input
        field={@form[:name]}
        type="text"
        label="Nombre del tipo"
        placeholder="Ej. Entera, Avena, Deslactosada"
      />
      <div class="grid grid-cols-3 gap-3">
        <.input
          field={@form[:stock_quantity]}
          type="number"
          label={"Stock (#{unit_abbr(@unit)})"}
          placeholder="0"
          step="0.001"
          min="0"
        />
        <.input
          field={@form[:min_stock]}
          type="number"
          label={"Mín. (#{unit_abbr(@unit)})"}
          placeholder="0"
          step="0.001"
          min="0"
        />
        <.input
          field={@form[:extra_charge]}
          type="number"
          label="Cargo extra ($)"
          placeholder="0.00"
          step="0.01"
          min="0"
        />
      </div>
      <div class="flex justify-end gap-2 pt-1">
        <button
          type="button"
          class="btn btn-ghost btn-sm"
          phx-click={@on_cancel}
        >
          Cancelar
        </button>
        <button type="submit" class="btn btn-primary btn-sm">
          {@submit_label}
        </button>
      </div>
    </.form>
    """
  end

  # ---------------------------------------------------------------------------
  # Filter tab component
  # ---------------------------------------------------------------------------

  attr :value, :string, required: true
  attr :current, :string, required: true
  attr :label, :string, required: true

  defp filter_tab(assigns) do
    ~H"""
    <button
      class={[
        "btn btn-sm",
        if(@value == @current, do: "btn-primary", else: "btn-ghost")
      ]}
      phx-click="filter_category"
      phx-value-category={@value}
    >
      {@label}
    </button>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp filter_by_status(products, :active), do: Enum.filter(products, & &1.active)
  defp filter_by_status(products, :inactive), do: Enum.filter(products, &(!&1.active))

  defp search_filter(products, ""), do: products

  defp search_filter(products, query) do
    q = query |> String.trim() |> String.downcase()
    Enum.filter(products, fn p -> String.contains?(String.downcase(p.name), q) end)
  end

  defp paginate(items, page, per_page) do
    items |> Enum.drop((page - 1) * per_page) |> Enum.take(per_page)
  end

  defp filtered_products(products, "all"), do: products

  defp filtered_products(products, cat_id) do
    Enum.filter(products, &(to_string(&1.product_category_id) == cat_id))
  end

  defp low_stock?(%Product{min_stock: nil}), do: false

  defp low_stock?(%Product{stock_quantity: stock, min_stock: min}),
    do: Decimal.compare(stock, min) != :gt

  defp variant_low_stock?(%ProductVariant{active: false}), do: false

  defp variant_low_stock?(%ProductVariant{stock_quantity: stock, min_stock: min}),
    do: Decimal.compare(stock, min) != :gt

  defp unit_options do
    labels = %{
      "piezas" => "Piezas (pza) — tortillas, vasos, huevos…",
      "gramos" => "Gramos (gr) — café, azúcar, harina…",
      "kilogramos" => "Kilogramos (kg) — carne, verduras a granel…",
      "mililitros" => "Mililitros (ml) — leche, jugos, salsas…",
      "litros" => "Litros (lt) — aceite, agua, crema…",
      "onzas" => "Onzas (oz) — especias, queso…",
      "paquetes" => "Paquetes (paq) — servilletas, sorbetes…"
    }

    [{"— Selecciona unidad —", ""} | Enum.map(Product.units(), &{Map.get(labels, &1, &1), &1})]
  end

  defp unit_label("piezas"), do: "piezas"
  defp unit_label("gramos"), do: "gramos"
  defp unit_label("kilogramos"), do: "kilogramos"
  defp unit_label("mililitros"), do: "mililitros"
  defp unit_label("litros"), do: "litros"
  defp unit_label("onzas"), do: "onzas"
  defp unit_label("paquetes"), do: "paquetes"
  defp unit_label(other), do: other

  # Contextual example shown after choosing a unit
  defp unit_example("gramos"),
    do:
      "Ejemplo: si usas 18 gramos de café por espresso, en la receta del platillo pondrás 18."

  defp unit_example("kilogramos"),
    do:
      "Ejemplo: si usas 0.5 kg de harina por receta, en el platillo pondrás 0.500."

  defp unit_example("mililitros"),
    do:
      "Ejemplo: si una porción lleva 200 ml de leche, en el platillo pondrás 200."

  defp unit_example("litros"),
    do:
      "Ejemplo: si usas 0.2 litros de crema por platillo, en la receta pondrás 0.200."

  defp unit_example("piezas"),
    do:
      "Ejemplo: si cada sope usa 3 tortillas, en la receta del platillo pondrás 3."

  defp unit_example("onzas"),
    do: "Ejemplo: una porción de 2 oz → pondrás 2 en la receta del platillo."

  defp unit_example("paquetes"),
    do: "Ejemplo: si cada plato usa medio paquete, pondrás 0.500 en la receta."

  defp unit_example(_), do: ""

  # Placeholder for the purchase qty input, unit-aware
  defp unit_qty_placeholder("gramos"), do: "Ej: 250.000 (gramos comprados)"
  defp unit_qty_placeholder("kilogramos"), do: "Ej: 1.000 (kg comprados)"
  defp unit_qty_placeholder("mililitros"), do: "Ej: 1000.000 (ml comprados)"
  defp unit_qty_placeholder("litros"), do: "Ej: 4.000 (litros comprados)"
  defp unit_qty_placeholder("piezas"), do: "Ej: 30.000 (piezas compradas)"
  defp unit_qty_placeholder("onzas"), do: "Ej: 16.000 (onzas compradas)"
  defp unit_qty_placeholder("paquetes"), do: "Ej: 12.000 (paquetes comprados)"
  defp unit_qty_placeholder(_), do: "Ej: 250"

  # Hint below the purchase qty input, unit-aware
  defp unit_qty_hint("gramos"),
    do: "Cuántos gramos compraste en total (ej. un bote de 250 g → escribe 250)"

  defp unit_qty_hint("kilogramos"),
    do: "Cuántos kilogramos compraste (ej. 1 kilo → escribe 1)"

  defp unit_qty_hint("mililitros"),
    do: "Cuántos mililitros compraste (ej. una botella de 1 litro = 1000 ml → escribe 1000)"

  defp unit_qty_hint("litros"),
    do: "Cuántos litros compraste (ej. un galón de 4 litros → escribe 4)"

  defp unit_qty_hint("piezas"),
    do: "Cuántas piezas compraste (ej. una caja de 30 → escribe 30)"

  defp unit_qty_hint("onzas"),
    do: "Cuántas onzas compraste (ej. 16 oz → escribe 16)"

  defp unit_qty_hint("paquetes"),
    do: "Cuántos paquetes compraste (ej. una docena → escribe 12)"

  defp unit_qty_hint(_), do: "La cantidad total que recibiste, en la unidad que elegiste arriba"

  # Hint for min_stock, unit-aware
  defp unit_min_stock_hint("gramos"),
    do: "Recomendado: lo que necesitas para 2–3 días de operación. Ej: si usas 200 g/día → ponle 400–600."

  defp unit_min_stock_hint("kilogramos"),
    do: "Ej: si consumes 0.5 kg al día → ponle 1.000 para que te avise cuando quede solo 1 kg."

  defp unit_min_stock_hint("mililitros"),
    do: "Ej: si usas 500 ml al día → ponle 1000 para tener margen de 2 días."

  defp unit_min_stock_hint("litros"),
    do: "Ej: si usas 2 litros al día → ponle 4.000 como mínimo de seguridad."

  defp unit_min_stock_hint("piezas"),
    do: "Ej: si vendes 20 piezas al día → ponle 40 para que te avise con 2 días de anticipación."

  defp unit_min_stock_hint(_),
    do: "Cuando el stock baje de este número te avisamos en el panel. Ponlo en lo que necesitas para 2–3 días."

  defp unit_abbr("piezas"), do: "pza"
  defp unit_abbr("gramos"), do: "gr"
  defp unit_abbr("kilogramos"), do: "kg"
  defp unit_abbr("mililitros"), do: "ml"
  defp unit_abbr("litros"), do: "lt"
  defp unit_abbr("onzas"), do: "oz"
  defp unit_abbr("paquetes"), do: "paq"
  defp unit_abbr(other), do: other

  defp format_price(nil), do: "—"
  defp format_price(%Decimal{} = d), do: Decimal.to_string(d)
  defp format_price(val), do: to_string(val)

  defp format_quantity(nil), do: "0"

  defp format_quantity(%Decimal{} = d) do
    if Decimal.integer?(d) do
      d |> Decimal.to_integer() |> to_string()
    else
      Decimal.to_string(d)
    end
  end

  defp format_quantity(val), do: to_string(val)

  # If both purchase_total and purchase_qty are valid positive numbers,
  # overwrites the net_cost param with total / qty (rounded to 4 decimals).
  # Otherwise leaves params untouched so the user can type net_cost directly.
  defp maybe_calc_unit_cost(params, total_str, qty_str) do
    with {total, _} <- Decimal.parse(total_str || ""),
         true <- Decimal.compare(total, Decimal.new(0)) == :gt,
         {qty, _} <- Decimal.parse(qty_str || ""),
         true <- Decimal.compare(qty, Decimal.new(0)) == :gt do
      unit_cost = total |> Decimal.div(qty) |> Decimal.round(4)
      Map.put(params, "net_cost", Decimal.to_string(unit_cost))
    else
      _ -> params
    end
  end
end
