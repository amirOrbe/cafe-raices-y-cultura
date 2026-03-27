defmodule CRCWeb.Admin.PlatillosLive do
  @moduledoc "Menu item (platillos) management from the administration panel."

  use CRCWeb, :live_view

  alias CRC.Catalog
  alias CRC.Catalog.MenuItem

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Platillos · Admin")
      |> assign(:items, Catalog.list_all_menu_items())
      |> assign(:categories, Catalog.list_all_categories())
      |> assign(:available_products, Catalog.list_ingredient_products())
      |> assign(:filter_category, "all")
      |> assign(:status_filter, :available)
      |> assign(:modal, nil)
      |> assign(:form, nil)
      |> assign(:ingredients_draft, [])
      |> assign(:selected_product_id, "")
      |> assign(:ingredient_quantity_input, "")

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events — filters
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("set_status_filter", %{"status" => status}, socket) do
    {:noreply, assign(socket, :status_filter, String.to_existing_atom(status))}
  end

  def handle_event("set_category_filter", %{"category" => cat}, socket) do
    {:noreply, assign(socket, :filter_category, cat)}
  end

  # ---------------------------------------------------------------------------
  # Events — modal / CRUD
  # ---------------------------------------------------------------------------

  def handle_event("new_item", _params, socket) do
    changeset = Catalog.change_menu_item(%MenuItem{})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:form, to_form(changeset))
     |> assign(:ingredients_draft, [])
     |> assign(:selected_product_id, "")
     |> assign(:ingredient_quantity_input, "")}
  end

  def handle_event("edit_item", %{"id" => id}, socket) do
    item = Catalog.get_menu_item_with_ingredients!(String.to_integer(id))
    changeset = Catalog.change_menu_item(item)

    draft =
      Enum.map(item.menu_item_ingredients, fn mii ->
        %{
          product_id: mii.product_id,
          product_name: mii.product.name,
          quantity: mii.quantity,
          unit: mii.product.unit
        }
      end)

    {:noreply,
     socket
     |> assign(:modal, {:edit, item})
     |> assign(:form, to_form(changeset))
     |> assign(:ingredients_draft, draft)
     |> assign(:selected_product_id, "")
     |> assign(:ingredient_quantity_input, "")}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil, ingredients_draft: [])}
  end

  def handle_event("save_item", %{"menu_item" => params}, socket) do
    result =
      case socket.assigns.modal do
        :new -> Catalog.create_menu_item(params)
        {:edit, item} -> Catalog.update_menu_item(item, params)
      end

    case result do
      {:ok, item} ->
        Catalog.set_menu_item_ingredients(
          item.id,
          socket.assigns.ingredients_draft
        )

        label = if socket.assigns.modal == :new, do: "creado", else: "actualizado"

        {:noreply,
         socket
         |> put_flash(:info, "Platillo #{label} correctamente.")
         |> assign(:items, Catalog.list_all_menu_items())
         |> assign(:modal, nil)
         |> assign(:form, nil)
         |> assign(:ingredients_draft, [])}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete_item", %{"id" => id}, socket) do
    item = Catalog.get_menu_item!(String.to_integer(id))

    case Catalog.delete_menu_item(item) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Platillo eliminado correctamente.")
         |> assign(:items, Catalog.list_all_menu_items())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo eliminar el platillo.")}
    end
  end

  def handle_event("toggle_available", %{"id" => id}, socket) do
    item = Catalog.get_menu_item!(String.to_integer(id))

    case Catalog.toggle_menu_item_available(item) do
      {:ok, _} ->
        action = if item.available, do: "ocultado del menú", else: "publicado en el menú"

        {:noreply,
         socket
         |> put_flash(:info, "Platillo #{action}.")
         |> assign(:items, Catalog.list_all_menu_items())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo cambiar la disponibilidad.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — ingredient draft management
  # ---------------------------------------------------------------------------

  def handle_event("select_ingredient", %{"ingredient_product_id" => pid}, socket) do
    {:noreply, assign(socket, :selected_product_id, pid)}
  end

  def handle_event("set_ingredient_qty", %{"ingredient_quantity" => qty}, socket) do
    {:noreply, assign(socket, :ingredient_quantity_input, qty)}
  end

  def handle_event("add_ingredient", _params, socket) do
    %{
      available_products: products,
      selected_product_id: pid_str,
      ingredient_quantity_input: qty_str,
      ingredients_draft: draft
    } = socket.assigns

    with true <- pid_str != "" and pid_str != nil,
         {pid, _} <- Integer.parse(pid_str),
         product <- Enum.find(products, &(&1.id == pid)),
         true <- product != nil,
         false <- Enum.any?(draft, &(&1.product_id == pid)),
         {qty_float, _} <- Float.parse(qty_str <> ""),
         true <- qty_float > 0 do
      qty = Decimal.from_float(qty_float)

      entry = %{
        product_id: product.id,
        product_name: product.name,
        quantity: qty,
        unit: product.unit
      }

      {:noreply,
       socket
       |> assign(:ingredients_draft, draft ++ [entry])
       |> assign(:selected_product_id, "")
       |> assign(:ingredient_quantity_input, "")}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove_ingredient", %{"product_id" => pid_str}, socket) do
    pid = String.to_integer(pid_str)
    draft = Enum.reject(socket.assigns.ingredients_draft, &(&1.product_id == pid))
    {:noreply, assign(socket, :ingredients_draft, draft)}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <% by_status = filter_by_status(@items, @status_filter) %>
    <% visible = filter_by_category(by_status, @filter_category) %>
    <% available_count = Enum.count(@items, & &1.available) %>
    <% unavailable_count = Enum.count(@items, &(!&1.available)) %>

    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Platillos</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            {length(visible)} platillos
            {if @status_filter == :available, do: "disponibles", else: "no disponibles"}
          </p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="new_item">
          <.icon name="hero-plus" class="size-4" />
          Nuevo platillo
        </button>
      </div>

      <%!-- Status filter tabs --%>
      <div class="flex gap-2">
        <button
          class={["btn btn-sm gap-1.5", if(@status_filter == :available, do: "btn-primary", else: "btn-ghost")]}
          phx-click="set_status_filter"
          phx-value-status="available"
        >
          <.icon name="hero-check-circle" class="size-3.5" />
          Disponibles
          <span class="badge badge-xs">{available_count}</span>
        </button>
        <button
          class={["btn btn-sm gap-1.5", if(@status_filter == :unavailable, do: "btn-error", else: "btn-ghost")]}
          phx-click="set_status_filter"
          phx-value-status="unavailable"
        >
          <.icon name="hero-eye-slash" class="size-3.5" />
          Ocultos
          <span class="badge badge-xs">{unavailable_count}</span>
        </button>
      </div>

      <%!-- Category filter tabs --%>
      <div class="flex flex-wrap gap-2">
        <.cat_tab value="all" current={@filter_category} label="Todos" />
        <%= for cat <- @categories do %>
          <.cat_tab value={to_string(cat.id)} current={@filter_category} label={cat.name} />
        <% end %>
      </div>

      <%!-- Table --%>
      <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
          <table class="table table-zebra w-full">
            <thead>
              <tr class="bg-base-200 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                <th>Platillo</th>
                <th>Categoría</th>
                <th>Precio</th>
                <th>Destacado</th>
                <th>Estado</th>
                <th class="text-right">Acciones</th>
              </tr>
            </thead>
            <tbody>
              <%= for item <- visible do %>
                <tr class="hover:bg-base-200/50 transition-colors">
                  <td>
                    <div>
                      <p class="font-medium text-sm text-base-content">{item.name}</p>
                      <%= if item.description do %>
                        <p class="text-xs text-base-content/50 line-clamp-1">{item.description}</p>
                      <% end %>
                    </div>
                  </td>
                  <td>
                    <span class="badge badge-sm badge-ghost">
                      {if item.category, do: item.category.name, else: "—"}
                    </span>
                  </td>
                  <td class="text-sm font-medium text-base-content">
                    ${format_price(item.price)}
                  </td>
                  <td>
                    <%= if item.featured do %>
                      <span class="badge badge-sm badge-warning">⭐ Destacado</span>
                    <% end %>
                  </td>
                  <td>
                    <%= if item.available do %>
                      <span class="badge badge-sm badge-success">Visible</span>
                    <% else %>
                      <span class="badge badge-sm badge-ghost">Oculto</span>
                    <% end %>
                  </td>
                  <td>
                    <div class="flex items-center justify-end gap-1">
                      <button
                        class="btn btn-ghost btn-sm"
                        phx-click="edit_item"
                        phx-value-id={item.id}
                        title="Editar"
                      >
                        <.icon name="hero-pencil" class="size-4" />
                      </button>
                      <button
                        class={["btn btn-ghost btn-sm", if(item.available, do: "text-warning", else: "text-success")]}
                        phx-click="toggle_available"
                        phx-value-id={item.id}
                        title={if item.available, do: "Ocultar del menú", else: "Publicar en menú"}
                      >
                        <.icon
                          name={if item.available, do: "hero-eye-slash", else: "hero-eye"}
                          class="size-4"
                        />
                      </button>
                      <button
                        class="btn btn-ghost btn-sm text-error"
                        phx-click="delete_item"
                        phx-value-id={item.id}
                        title="Eliminar"
                        data-confirm={"¿Eliminar «#{item.name}»? Esta acción no se puede deshacer."}
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              <% end %>
              <%= if visible == [] do %>
                <tr>
                  <td colspan="6" class="text-center py-12 text-base-content/40 text-sm">
                    {cond do
                      @status_filter == :unavailable && @filter_category == "all" ->
                        "No hay platillos ocultos."

                      @filter_category != "all" ->
                        "No hay platillos en esta categoría."

                      true ->
                        "No hay platillos registrados. Crea el primero."
                    end}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <%!-- Modal --%>
    <%= if @modal != nil do %>
      <.item_modal
        form={@form}
        modal={@modal}
        categories={@categories}
        ingredients_draft={@ingredients_draft}
        available_products={@available_products}
        selected_product_id={@selected_product_id}
        ingredient_quantity_input={@ingredient_quantity_input}
      />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Item modal
  # ---------------------------------------------------------------------------

  attr :form, :map, required: true
  attr :modal, :any, required: true
  attr :categories, :list, required: true
  attr :ingredients_draft, :list, required: true
  attr :available_products, :list, required: true
  attr :selected_product_id, :string, required: true
  attr :ingredient_quantity_input, :string, required: true

  defp item_modal(assigns) do
    title = if assigns.modal == :new, do: "Nuevo platillo", else: "Editar platillo"
    assigns = assign(assigns, :title, title)

    ~H"""
    <div
      id="item-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_modal"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_modal"></div>

      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-2xl overflow-y-auto max-h-[92vh]">
        <%!-- Modal header --%>
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between sticky top-0 bg-base-100 z-10">
          <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="px-6 py-5">
          <.form id="item-form" for={@form} phx-submit="save_item" class="space-y-1">
            <%!-- Name --%>
            <.input
              field={@form[:name]}
              type="text"
              label="Nombre del platillo"
              placeholder="Ej. Cappuccino, El Favorito, Toast Francés"
            />

            <%!-- Description --%>
            <.input
              field={@form[:description]}
              type="textarea"
              label="Descripción (opcional)"
              placeholder="Descripción breve que aparece en el menú público..."
            />

            <%!-- Category + Price (2 cols) --%>
            <div class="grid grid-cols-2 gap-3">
              <.input
                field={@form[:category_id]}
                type="select"
                label="Categoría"
                options={[{"— Selecciona categoría —", ""} | Enum.map(@categories, &{&1.name, &1.id})]}
              />
              <.input
                field={@form[:price]}
                type="number"
                label="Precio ($)"
                placeholder="0.00"
                step="0.01"
                min="0.01"
              />
            </div>

            <%!-- Image URL --%>
            <.input
              field={@form[:image_url]}
              type="text"
              label="URL de imagen (opcional)"
              placeholder="https://..."
            />

            <%!-- Position + switches (3 cols) --%>
            <div class="grid grid-cols-3 gap-3">
              <.input
                field={@form[:position]}
                type="number"
                label="Posición"
                placeholder="0"
                min="0"
              />
              <.input
                field={@form[:featured]}
                type="checkbox"
                label="Destacado ⭐"
              />
              <.input
                field={@form[:available]}
                type="checkbox"
                label="Visible en menú"
              />
            </div>

            <%!-- ── Ingredients section ──────────────────────────────────────── --%>
            <div class="mt-5 pt-4 border-t border-base-300">
              <div class="flex items-center gap-2 mb-3">
                <.icon name="hero-beaker" class="size-4 text-base-content/60" />
                <h3 class="text-sm font-semibold text-base-content">Ingredientes</h3>
                <span class="badge badge-xs badge-ghost">{length(@ingredients_draft)}</span>
              </div>

              <%!-- Current ingredient list --%>
              <%= if @ingredients_draft != [] do %>
                <div class="mb-3 space-y-1.5">
                  <%= for ing <- @ingredients_draft do %>
                    <div class="flex items-center justify-between py-1.5 px-3 bg-base-200 rounded-lg">
                      <span class="text-sm font-medium text-base-content">{ing.product_name}</span>
                      <div class="flex items-center gap-3">
                        <span class="text-xs text-base-content/60">
                          {format_qty(ing.quantity)} {unit_abbr(ing.unit)}
                        </span>
                        <button
                          type="button"
                          class="btn btn-ghost btn-xs text-error p-0"
                          phx-click="remove_ingredient"
                          phx-value-product_id={ing.product_id}
                          title="Quitar ingrediente"
                        >
                          <.icon name="hero-x-mark" class="size-3.5" />
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%!-- Add ingredient picker --%>
              <div class="flex gap-2 items-end flex-wrap sm:flex-nowrap">
                <div class="flex-1 min-w-0">
                  <label class="label text-xs pb-0.5">Insumo</label>
                  <select
                    class="select select-sm w-full"
                    phx-change="select_ingredient"
                    name="ingredient_product_id"
                  >
                    <option value="">— Selecciona insumo —</option>
                    <%= for p <- @available_products do %>
                      <option
                        value={p.id}
                        selected={to_string(p.id) == @selected_product_id}
                      >
                        {p.name} ({unit_abbr(p.unit)})
                      </option>
                    <% end %>
                  </select>
                </div>
                <div class="w-28 shrink-0">
                  <label class="label text-xs pb-0.5">Cantidad</label>
                  <input
                    type="number"
                    class="input input-sm w-full"
                    placeholder="0"
                    step="0.001"
                    min="0"
                    value={@ingredient_quantity_input}
                    phx-change="set_ingredient_qty"
                    name="ingredient_quantity"
                  />
                </div>
                <button
                  type="button"
                  class="btn btn-sm btn-outline btn-primary shrink-0"
                  phx-click="add_ingredient"
                >
                  <.icon name="hero-plus" class="size-3.5" />
                  Agregar
                </button>
              </div>

              <%= if @available_products == [] do %>
                <p class="text-xs text-base-content/50 mt-2">
                  No hay insumos sin proveedor disponibles. Crea insumos sin asignar proveedor en
                  <a href="/admin/insumos" class="link link-primary">Inventario → Insumos</a>.
                </p>
              <% end %>
            </div>
            <%!-- ── End Ingredients ──────────────────────────────────────────── --%>

            <div class="flex justify-end gap-3 pt-4">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">
                Cancelar
              </button>
              <button type="submit" class="btn btn-primary">
                {if @modal == :new, do: "Crear platillo", else: "Guardar cambios"}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Category filter tab
  # ---------------------------------------------------------------------------

  attr :value, :string, required: true
  attr :current, :string, required: true
  attr :label, :string, required: true

  defp cat_tab(assigns) do
    ~H"""
    <button
      class={["btn btn-sm", if(@value == @current, do: "btn-primary", else: "btn-ghost")]}
      phx-click="set_category_filter"
      phx-value-category={@value}
    >
      {@label}
    </button>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp filter_by_status(items, :available), do: Enum.filter(items, & &1.available)
  defp filter_by_status(items, :unavailable), do: Enum.filter(items, &(!&1.available))

  defp filter_by_category(items, "all"), do: items

  defp filter_by_category(items, cat_id) do
    {id, _} = Integer.parse(cat_id)
    Enum.filter(items, &(&1.category_id == id))
  end

  defp format_price(%Decimal{} = d), do: Decimal.to_string(d)
  defp format_price(val), do: to_string(val)

  defp format_qty(nil), do: "0"

  defp format_qty(%Decimal{} = d) do
    if Decimal.integer?(d),
      do: d |> Decimal.to_integer() |> to_string(),
      else: Decimal.to_string(d)
  end

  defp format_qty(val), do: to_string(val)

  defp unit_abbr("piezas"), do: "pza"
  defp unit_abbr("gramos"), do: "gr"
  defp unit_abbr("kilogramos"), do: "kg"
  defp unit_abbr("mililitros"), do: "ml"
  defp unit_abbr("litros"), do: "lt"
  defp unit_abbr("onzas"), do: "oz"
  defp unit_abbr("paquetes"), do: "paq"
  defp unit_abbr(other), do: other
end
