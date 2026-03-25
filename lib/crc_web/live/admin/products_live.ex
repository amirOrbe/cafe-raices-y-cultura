defmodule CRCWeb.Admin.ProductsLive do
  @moduledoc "Inventory (insumos) management from the administration panel."

  use CRCWeb, :live_view

  alias CRC.Inventory
  alias CRC.Inventory.Product

  @impl true
  def mount(_params, _session, socket) do
    products = Inventory.list_products()
    low_stock = Enum.count(products, &low_stock?/1)

    socket =
      socket
      |> assign(:page_title, "Insumos · Admin")
      |> assign(:products, products)
      |> assign(:low_stock_count, low_stock)
      |> assign(:suppliers, Inventory.list_active_suppliers())
      |> assign(:filter_category, "all")
      |> assign(:modal, nil)
      |> assign(:form, nil)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("filter_category", %{"category" => cat}, socket) do
    {:noreply, assign(socket, :filter_category, cat)}
  end

  def handle_event("new_product", _params, socket) do
    changeset = Inventory.change_product(%Product{})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("edit_product", %{"id" => id}, socket) do
    product = Inventory.get_product!(String.to_integer(id))
    changeset = Inventory.change_product(product)

    {:noreply,
     socket
     |> assign(:modal, {:edit, product})
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil)}
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
         |> assign(:modal, nil)
         |> assign(:form, nil)}

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
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Insumos</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            {length(@products)} insumos registrados
            <%= if @low_stock_count > 0 do %>
              · <span class="text-warning font-medium">{@low_stock_count} con stock bajo</span>
            <% end %>
          </p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="new_product">
          <.icon name="hero-plus" class="size-4" />
          Nuevo insumo
        </button>
      </div>

      <%!-- Category filter tabs --%>
      <div class="flex flex-wrap gap-2">
        <.filter_tab value="all" current={@filter_category} label="Todos" />
        <%= for cat <- Product.categories() do %>
          <.filter_tab value={cat} current={@filter_category} label={category_label(cat)} />
        <% end %>
      </div>

      <%!-- Table --%>
      <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
          <table class="table table-zebra w-full">
            <thead>
              <tr class="bg-base-200 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                <th>Nombre</th>
                <th>Categoría</th>
                <th>Stock</th>
                <th>Mín.</th>
                <th>Costo neto</th>
                <th>Precio venta</th>
                <th>Proveedor</th>
                <th>Estado</th>
                <th class="text-right">Acciones</th>
              </tr>
            </thead>
            <tbody>
              <%= for product <- filtered_products(@products, @filter_category) do %>
                <tr class={["hover:bg-base-200/50 transition-colors", if(low_stock?(product), do: "bg-warning/5")]}>
                  <td>
                    <div class="flex items-center gap-2">
                      <%= if low_stock?(product) do %>
                        <.icon name="hero-exclamation-triangle" class="size-4 text-warning shrink-0" />
                      <% end %>
                      <span class="font-medium text-sm text-base-content">{product.name}</span>
                    </div>
                  </td>
                  <td>
                    <span class="badge badge-sm badge-ghost">{category_label(product.category)}</span>
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
                  <td class="text-sm text-base-content/60">
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
              <%= if filtered_products(@products, @filter_category) == [] do %>
                <tr>
                  <td colspan="9" class="text-center py-12 text-base-content/40 text-sm">
                    {if @filter_category == "all",
                      do: "No hay insumos registrados. Crea el primero.",
                      else: "No hay insumos en esta categoría."}
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
      <.product_modal form={@form} modal={@modal} suppliers={@suppliers} />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Product modal
  # ---------------------------------------------------------------------------

  attr :form, :map, required: true
  attr :modal, :any, required: true
  attr :suppliers, :list, required: true

  defp product_modal(assigns) do
    title = if assigns.modal == :new, do: "Nuevo insumo", else: "Editar insumo"
    assigns = assign(assigns, :title, title)

    ~H"""
    <div
      id="product-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_modal"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_modal"></div>

      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-2xl overflow-y-auto max-h-[90vh]">
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between sticky top-0 bg-base-100">
          <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="px-6 py-5">
          <.form id="product-form" for={@form} phx-submit="save_product" class="space-y-1">
            <%!-- Name --%>
            <.input
              field={@form[:name]}
              type="text"
              label="Nombre del insumo"
              placeholder="Ej. Leche entera, Café de especialidad, Vaso 12oz"
            />

            <%!-- Category + Unit (2 cols) --%>
            <div class="grid grid-cols-2 gap-3">
              <.input
                field={@form[:category]}
                type="select"
                label="Categoría"
                options={category_options()}
              />
              <.input
                field={@form[:unit]}
                type="select"
                label="Unidad de medida"
                options={unit_options()}
              />
            </div>

            <%!-- Net cost + Sale price (2 cols) --%>
            <div class="grid grid-cols-2 gap-3">
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
                label="Precio de venta ($) (opcional)"
                placeholder="0.00"
                step="0.01"
                min="0"
              />
            </div>

            <%!-- Stock + Min stock (2 cols) --%>
            <div class="grid grid-cols-2 gap-3">
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

            <div class="flex justify-end gap-3 pt-4">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
              <button type="submit" class="btn btn-primary">
                {if @modal == :new, do: "Crear insumo", else: "Guardar cambios"}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
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

  defp filtered_products(products, "all"), do: products
  defp filtered_products(products, cat), do: Enum.filter(products, &(&1.category == cat))

  defp low_stock?(%Product{min_stock: nil}), do: false
  defp low_stock?(%Product{stock_quantity: stock, min_stock: min}), do: Decimal.compare(stock, min) != :gt

  defp category_options do
    [{"— Selecciona categoría —", ""} | Enum.map(Product.categories(), &{category_label(&1), &1})]
  end

  defp unit_options do
    [{"— Selecciona unidad —", ""} | Enum.map(Product.units(), &{unit_label(&1), &1})]
  end

  defp category_label("alimentos"), do: "Alimentos"
  defp category_label("bebidas"), do: "Bebidas"
  defp category_label("lacteos"), do: "Lácteos"
  defp category_label("granos"), do: "Granos de café"
  defp category_label("panaderia"), do: "Panadería"
  defp category_label("cocteleria"), do: "Coctelería"
  defp category_label("desechables"), do: "Desechables"
  defp category_label("limpieza"), do: "Limpieza"
  defp category_label("utensilios"), do: "Utensilios"
  defp category_label("otro"), do: "Otro"
  defp category_label(other), do: other

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
