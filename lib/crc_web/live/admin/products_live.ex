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
    {:noreply, assign(socket, :filter_category, cat)}
  end

  def handle_event("set_status_filter", %{"status" => status}, socket) do
    {:noreply, assign(socket, :status_filter, String.to_existing_atom(status))}
  end

  def handle_event("new_product", _params, socket) do
    changeset = Inventory.change_product(%Product{})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:form, to_form(changeset))
     |> assign(:variant_form, nil)
     |> assign(:editing_variant_id, nil)}
  end

  def handle_event("edit_product", %{"id" => id}, socket) do
    product = Inventory.get_product!(String.to_integer(id))
    changeset = Inventory.change_product(product)

    {:noreply,
     socket
     |> assign(:modal, {:edit, product})
     |> assign(:form, to_form(changeset))
     |> assign(:variant_form, nil)
     |> assign(:editing_variant_id, nil)}
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
      {:ok, _product} ->
        label = if socket.assigns.modal == :new, do: "creado", else: "actualizado"
        products = Inventory.list_products()
        low_stock = Enum.count(products, &low_stock?/1)

        {:noreply,
         socket
         |> put_flash(:info, "Insumo #{label} correctamente.")
         |> assign(:products, products)
         |> assign(:low_stock_count, low_stock)
         |> assign(:categories, Inventory.list_product_categories())
         |> assign(:modal, nil)
         |> assign(:form, nil)
         |> assign(:variant_form, nil)
         |> assign(:editing_variant_id, nil)}

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
    <% visible = filtered_products(by_status, @filter_category) %>
    <% active_count = Enum.count(@products, & &1.active) %>
    <% inactive_count = Enum.count(@products, &(!&1.active)) %>
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Insumos</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            {length(visible)} insumos
            {if @status_filter == :active, do: "activos", else: "inactivos"}
            <%= if @status_filter == :active && @low_stock_count > 0 do %>
              · <span class="text-warning font-medium">{@low_stock_count} con stock bajo</span>
            <% end %>
          </p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="new_product">
          <.icon name="hero-plus" class="size-4" />
          Nuevo insumo
        </button>
      </div>

      <%!-- Status tabs --%>
      <div class="flex gap-2">
        <button
          class={["btn btn-sm gap-1.5", if(@status_filter == :active, do: "btn-primary", else: "btn-ghost")]}
          phx-click="set_status_filter"
          phx-value-status="active"
        >
          <.icon name="hero-check-circle" class="size-3.5" />
          Activos
          <span class={["badge badge-xs", if(@status_filter == :active, do: "badge-primary-content/30", else: "badge-ghost")]}>
            {active_count}
          </span>
        </button>
        <button
          class={["btn btn-sm gap-1.5", if(@status_filter == :inactive, do: "btn-error", else: "btn-ghost")]}
          phx-click="set_status_filter"
          phx-value-status="inactive"
        >
          <.icon name="hero-x-circle" class="size-3.5" />
          Inactivos
          <span class={["badge badge-xs", if(@status_filter == :inactive, do: "badge-error-content/30", else: "badge-ghost")]}>
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
          <div class={["bg-base-100 rounded-2xl border shadow-sm p-3 flex items-center gap-3", if(is_low, do: "border-warning/40 bg-warning/5", else: "border-base-300")]}>
            <div class={["flex items-center justify-center w-10 h-10 rounded-xl shrink-0", if(is_low, do: "bg-warning/15", else: "bg-primary/10")]}>
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
                <span class={["text-xs font-medium", if(low_stock?(product), do: "text-warning", else: "text-base-content/70")]}>
                  Stock: {format_quantity(product.stock_quantity)} {unit_abbr(product.unit)}
                </span>
                <span class="text-xs text-base-content/40">
                  Mín: {format_quantity(product.min_stock)} {unit_abbr(product.unit)}
                </span>
              </div>
              <div class="flex items-center gap-3 mt-1">
                <span class="text-xs text-base-content/70">${format_price(product.net_cost)} costo</span>
                <%= if product.sale_price do %>
                  <span class="text-xs text-base-content/50">${format_price(product.sale_price)} venta</span>
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
                class={["btn btn-ghost btn-xs btn-circle", if(product.active, do: "text-error", else: "text-success")]}
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
                <tr class={["hover:bg-base-200/50 transition-colors", if(low_stock?(product) or variant_low_stock, do: "bg-warning/5")]}>
                  <td class="max-w-0">
                    <div class="flex items-center gap-2">
                      <%= if low_stock?(product) or variant_low_stock do %>
                        <.icon name="hero-exclamation-triangle" class="size-4 text-warning shrink-0" />
                      <% end %>
                      <div class="min-w-0">
                        <span class="font-medium text-sm text-base-content truncate block">{product.name}</span>
                        <%= if has_variants do %>
                          <p class="text-xs text-base-content/40 mt-0.5 truncate">
                            {length(product.variants)} tipo{if length(product.variants) != 1, do: "s", else: ""}
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
                    <span class={if low_stock?(product), do: "text-warning", else: "text-base-content"}>
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
                        class="btn btn-ghost btn-sm"
                        phx-click="edit_product"
                        phx-value-id={product.id}
                        title="Editar"
                      >
                        <.icon name="hero-pencil" class="size-4" />
                      </button>
                      <button
                        class={["btn btn-ghost btn-sm", if(product.active, do: "text-error", else: "text-success")]}
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
                      @status_filter == :inactive && @filter_category == "all" -> "No hay insumos inactivos."
                      @status_filter == :inactive -> "No hay insumos inactivos en esta categoría."
                      @filter_category != "all" -> "No hay insumos en esta categoría."
                      true -> "No hay insumos registrados. Crea el primero."
                    end}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <%!-- Modal: new / edit product --%>
    <%= if @modal != nil do %>
      <.product_modal
        form={@form}
        modal={@modal}
        suppliers={@suppliers}
        categories={@categories}
        variant_form={@variant_form}
        editing_variant_id={@editing_variant_id}
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

        <div class="px-6 py-5 space-y-6">
          <%!-- Product form --%>
          <.form id="product-form" for={@form} phx-submit="save_product" class="space-y-1">
            <%!-- Name --%>
            <.input
              field={@form[:name]}
              type="text"
              label="Nombre del insumo"
              placeholder="Ej. Leche, Café de especialidad, Vaso 12oz"
            />

            <%!-- Category + Unit (2 cols) --%>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <.input
                field={@form[:product_category_id]}
                type="select"
                label="Categoría"
                options={[{"— Sin categoría —", ""} | Enum.map(@categories, &{&1.name, &1.id})]}
              />
              <.input
                field={@form[:unit]}
                type="select"
                label="Unidad de medida"
                options={unit_options()}
              />
            </div>

            <%!-- Net cost + Sale price (2 cols) --%>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <.input
                field={@form[:net_cost]}
                type="number"
                label="Costo neto ($)"
                placeholder="0.00"
                step="0.01"
                min="0"
              />
              <.input
                field={@form[:sale_price]}
                type="number"
                label="Precio venta ($) (opcional)"
                placeholder="0.00"
                step="0.01"
                min="0"
              />
            </div>

            <%!-- Stock + Min stock (2 cols) --%>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <.input
                field={@form[:stock_quantity]}
                type="number"
                label="Cantidad en stock"
                placeholder="0"
                step="0.001"
                min="0"
              />
              <.input
                field={@form[:min_stock]}
                type="number"
                label="Stock mínimo (alerta)"
                placeholder="0"
                step="0.001"
                min="0"
              />
            </div>

            <%!-- Supplier --%>
            <.input
              field={@form[:supplier_id]}
              type="select"
              label="Proveedor (opcional)"
              options={[{"— Sin proveedor —", ""} | Enum.map(@suppliers, &{&1.name, &1.id})]}
            />

            <%!-- Notes --%>
            <.input
              field={@form[:notes]}
              type="textarea"
              label="Notas (opcional)"
              placeholder="Observaciones, presentación, marca preferida..."
            />

            <div class="flex justify-end gap-3 pt-2">
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
                    <.icon name="hero-plus" class="size-3.5" />
                    Agregar tipo
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
                      if(is_editing, do: "border-primary/30 bg-primary/5", else: "border-base-200 bg-base-50"),
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
                              <span class="font-medium text-sm text-base-content">{variant.name}</span>
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
                              Stock: {format_quantity(variant.stock_quantity)} {unit_abbr(@product.unit)}
                              · Mín: {format_quantity(variant.min_stock)} {unit_abbr(@product.unit)}
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
                              class={["btn btn-ghost btn-xs", if(variant.active, do: "text-error", else: "text-success")]}
                              phx-click="toggle_variant_active"
                              phx-value-id={variant.id}
                              title={if variant.active, do: "Desactivar", else: "Activar"}
                            >
                              <.icon
                                name={if variant.active, do: "hero-no-symbol", else: "hero-check-circle"}
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
                  <p class="text-xs font-semibold text-primary mb-3 uppercase tracking-wide">Nuevo tipo</p>
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
    [{"— Selecciona unidad —", ""} | Enum.map(Product.units(), &{unit_label(&1), &1})]
  end

  defp unit_label("piezas"), do: "Piezas (pza)"
  defp unit_label("gramos"), do: "Gramos (gr)"
  defp unit_label("kilogramos"), do: "Kilogramos (kg)"
  defp unit_label("mililitros"), do: "Mililitros (ml)"
  defp unit_label("litros"), do: "Litros (lt)"
  defp unit_label("onzas"), do: "Onzas (oz)"
  defp unit_label("paquetes"), do: "Paquetes (paq)"
  defp unit_label(other), do: other

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
end
