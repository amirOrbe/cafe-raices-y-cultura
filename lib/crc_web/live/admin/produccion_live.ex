defmodule CRCWeb.Admin.ProduccionLive do
  @moduledoc """
  Admin view for Producción Interna.

  Recipe name = output product name (auto-resolved on save via Inventory lookup).
  Lets admins create/edit recipes with dynamic ingredient rows and browse history.
  """

  use CRCWeb, :live_view

  alias CRC.Inventory
  alias CRC.Production
  alias CRC.Production.Recipe

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "admin:products")
    end

    socket =
      socket
      |> assign(:page_title, "Producción · Admin")
      |> assign(:recipes, Production.list_all_recipes())
      |> assign(:recent_logs, Production.list_recent_logs(100))
      |> assign(:products, Production.list_products_for_select())
      |> assign(:modal, nil)
      |> assign(:recipe_form, nil)
      |> assign(:ingredient_rows, [])
      |> assign(:tab, :recipes)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:product_changed, _}, socket) do
    {:noreply,
     socket
     |> assign(:recent_logs, Production.list_recent_logs(100))
     |> assign(:recipes, Production.list_all_recipes())}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Tab
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, String.to_existing_atom(tab))}
  end

  # ---------------------------------------------------------------------------
  # Recipe modal — new / edit
  # ---------------------------------------------------------------------------

  def handle_event("new_recipe", _params, socket) do
    changeset = Production.change_recipe(%Recipe{})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:recipe_form, to_form(changeset, as: "recipe"))
     |> assign(:ingredient_rows, [fresh_row()])}
  end

  def handle_event("edit_recipe", %{"id" => id}, socket) do
    recipe = Production.get_recipe!(String.to_integer(id))
    changeset = Production.change_recipe(recipe)

    rows =
      recipe.recipe_ingredients
      |> Enum.map(fn ri ->
        %{
          id: ri.id,
          product_id: to_string(ri.product_id),
          quantity: Decimal.to_string(ri.quantity)
        }
      end)

    rows = if rows == [], do: [fresh_row()], else: rows

    {:noreply,
     socket
     |> assign(:modal, {:edit, recipe})
     |> assign(:recipe_form, to_form(changeset, as: "recipe"))
     |> assign(:ingredient_rows, rows)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal, nil)
     |> assign(:recipe_form, nil)
     |> assign(:ingredient_rows, [])}
  end

  # ---------------------------------------------------------------------------
  # Dynamic ingredient rows
  # ---------------------------------------------------------------------------

  def handle_event("add_ingredient_row", _params, socket) do
    rows = socket.assigns.ingredient_rows ++ [fresh_row()]
    {:noreply, assign(socket, :ingredient_rows, rows)}
  end

  def handle_event("remove_ingredient_row", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    rows = List.delete_at(socket.assigns.ingredient_rows, idx)
    rows = if rows == [], do: [fresh_row()], else: rows
    {:noreply, assign(socket, :ingredient_rows, rows)}
  end

  # phx-change inside a <form> does NOT send phx-value-* attributes.
  # LiveView sends _target with the changed field path + form values nested by name.
  def handle_event("update_ingredient_row", %{"_target" => [_, idx_str, field]} = params, socket) do
    idx = String.to_integer(idx_str)
    value = get_in(params, ["ingredient_rows", idx_str, field]) || ""

    rows =
      List.update_at(socket.assigns.ingredient_rows, idx, fn row ->
        Map.put(row, String.to_existing_atom(field), value)
      end)

    {:noreply, assign(socket, :ingredient_rows, rows)}
  end

  # Fallback: ignore any update_ingredient_row that doesn't match expected shape
  def handle_event("update_ingredient_row", _params, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Save recipe — output product auto-resolved from recipe name
  # ---------------------------------------------------------------------------

  def handle_event("save_recipe", %{"recipe" => params} = full_params, socket) do
    # Read ingredient rows from form params (most up-to-date values)
    ingredient_rows = parse_ingredient_rows_from_params(full_params)
    ingredient_list = build_ingredient_list(ingredient_rows)

    # Auto-resolve (or create) the output product from the recipe name + unit
    recipe_name = params["name"] || ""
    yield_unit = params["yield_unit"] || ""

    case Inventory.find_or_create_production_output(recipe_name, yield_unit) do
      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "No se pudo crear el insumo de salida. Inténtalo de nuevo.")}

      {:ok, product} ->
        params_with_product = Map.put(params, "output_product_id", product.id)

        result =
          case socket.assigns.modal do
            :new ->
              Production.create_recipe(params_with_product, ingredient_list)

            {:edit, recipe} ->
              Production.update_recipe(recipe, params_with_product, ingredient_list)
          end

        case result do
          {:ok, _recipe} ->
            {:noreply,
             socket
             |> assign(:modal, nil)
             |> assign(:recipe_form, nil)
             |> assign(:ingredient_rows, [])
             |> assign(:recipes, Production.list_all_recipes())
             |> put_flash(:info, "Receta guardada.")}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, assign(socket, :recipe_form, to_form(cs, as: "recipe"))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "No se pudo guardar la receta.")}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Toggle active
  # ---------------------------------------------------------------------------

  def handle_event("toggle_active", %{"id" => id}, socket) do
    recipe = Enum.find(socket.assigns.recipes, &(to_string(&1.id) == id))

    case recipe && Production.toggle_recipe_active(recipe) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:recipes, Production.list_all_recipes())
         |> put_flash(:info, "Receta actualizada.")}

      _ ->
        {:noreply, put_flash(socket, :error, "No se pudo actualizar.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 pb-12">
      <div class="max-w-5xl mx-auto px-4 sm:px-6 py-8 space-y-6">
        <%!-- Header --%>
        <div class="flex items-center justify-between flex-wrap gap-3">
          <div class="flex items-center gap-3">
            <.icon name="hero-beaker" class="size-7 text-primary" />
            <div>
              <h1 class="text-2xl font-bold text-base-content">Producción Interna</h1>
              <p class="text-sm text-base-content/50">
                Gestiona recetas de producción y revisa el historial.
              </p>
            </div>
          </div>
          <%= if @tab == :recipes do %>
            <button class="btn btn-primary btn-sm gap-2" phx-click="new_recipe">
              <.icon name="hero-plus" class="size-4" /> Nueva receta
            </button>
          <% end %>
        </div>

        <%!-- Tabs --%>
        <div class="tabs tabs-bordered">
          <button
            class={"tab #{if @tab == :recipes, do: "tab-active"}"}
            phx-click="set_tab"
            phx-value-tab="recipes"
          >
            Recetas <span class="ml-2 badge badge-ghost badge-sm">{length(@recipes)}</span>
          </button>
          <button
            class={"tab #{if @tab == :history, do: "tab-active"}"}
            phx-click="set_tab"
            phx-value-tab="history"
          >
            Historial <span class="ml-2 badge badge-ghost badge-sm">{length(@recent_logs)}</span>
          </button>
        </div>

        <%!-- Recipes tab --%>
        <%= if @tab == :recipes do %>
          <%= if @recipes == [] do %>
            <div class="bg-base-100 rounded-2xl border border-base-300 py-16 text-center text-base-content/40 text-sm">
              No hay recetas todavía. Crea la primera.
            </div>
          <% else %>
            <%!-- Mobile cards --%>
            <div class="md:hidden space-y-3">
              <%= for recipe <- @recipes do %>
                <div class={"bg-base-100 rounded-2xl border shadow-sm p-4 space-y-3 #{if recipe.active, do: "border-base-300", else: "border-base-300 opacity-60"}"}>
                  <div class="flex items-start justify-between gap-2">
                    <div>
                      <p class="font-semibold text-base-content">{recipe.name}</p>
                      <p class="text-xs text-base-content/50 mt-0.5">
                        Produce {format_qty(recipe.yield_quantity)} {recipe.yield_unit}
                      </p>
                    </div>
                    <input
                      type="checkbox"
                      class="toggle toggle-primary toggle-sm shrink-0 mt-0.5"
                      checked={recipe.active}
                      phx-click="toggle_active"
                      phx-value-id={recipe.id}
                    />
                  </div>
                  <div class="flex flex-wrap gap-1">
                    <%= for ri <- recipe.recipe_ingredients do %>
                      <span class="badge badge-xs badge-ghost">
                        {ri.product && ri.product.name} · {format_qty(ri.quantity)}
                      </span>
                    <% end %>
                  </div>
                  <% cost = Production.recipe_unit_cost(recipe) %>
                  <%= if cost do %>
                    <p class="text-xs text-base-content/40">Costo/u: ${format_qty(cost)}</p>
                  <% end %>
                  <button
                    class="btn btn-ghost btn-xs w-full"
                    phx-click="edit_recipe"
                    phx-value-id={recipe.id}
                  >
                    <.icon name="hero-pencil" class="size-3.5" /> Editar
                  </button>
                </div>
              <% end %>
            </div>

            <%!-- Desktop table --%>
            <div class="hidden md:block bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
              <table class="table table-fixed w-full">
                <thead class="bg-base-200 text-xs uppercase tracking-wider text-base-content/50">
                  <tr>
                    <th class="w-48">Nombre</th>
                    <th class="w-32">Produce</th>
                    <th>Ingredientes</th>
                    <th class="w-28 text-right">Costo/u</th>
                    <th class="w-20 text-center">Activa</th>
                    <th class="w-20"></th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-200">
                  <%= for recipe <- @recipes do %>
                    <tr class={"#{unless recipe.active, do: "opacity-50"}"}>
                      <td class="font-semibold text-sm">{recipe.name}</td>
                      <td class="text-sm text-base-content/70">
                        {format_qty(recipe.yield_quantity)} {recipe.yield_unit}
                      </td>
                      <td>
                        <div class="flex flex-wrap gap-1">
                          <%= for ri <- recipe.recipe_ingredients do %>
                            <span class="badge badge-xs badge-ghost">
                              {ri.product && ri.product.name} · {format_qty(ri.quantity)}
                            </span>
                          <% end %>
                        </div>
                      </td>
                      <td class="text-right text-sm text-base-content/60">
                        <% cost = Production.recipe_unit_cost(recipe) %>
                        {if cost, do: "$#{format_qty(cost)}", else: "—"}
                      </td>
                      <td class="text-center">
                        <input
                          type="checkbox"
                          class="toggle toggle-primary toggle-sm"
                          checked={recipe.active}
                          phx-click="toggle_active"
                          phx-value-id={recipe.id}
                        />
                      </td>
                      <td class="text-right">
                        <button
                          class="btn btn-ghost btn-xs"
                          phx-click="edit_recipe"
                          phx-value-id={recipe.id}
                        >
                          <.icon name="hero-pencil" class="size-3.5" />
                        </button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        <% end %>

        <%!-- History tab --%>
        <%= if @tab == :history do %>
          <%= if @recent_logs == [] do %>
            <div class="bg-base-100 rounded-2xl border border-base-300 py-16 text-center text-base-content/40 text-sm">
              Sin producción registrada todavía.
            </div>
          <% else %>
            <%!-- Mobile cards --%>
            <div class="md:hidden space-y-3">
              <%= for log <- @recent_logs do %>
                <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-4">
                  <div class="flex items-center justify-between gap-2">
                    <p class="font-semibold text-sm">{log.recipe && log.recipe.name}</p>
                    <span class="badge badge-success badge-sm shrink-0">
                      {format_qty(log.batches)} {if Decimal.compare(log.batches, Decimal.new(1)) ==
                                                      :eq,
                                                    do: "lote",
                                                    else: "lotes"}
                    </span>
                  </div>
                  <p class="text-xs text-base-content/50 mt-1">
                    {log.produced_by && log.produced_by.name} · {format_dt(log.produced_at)}
                  </p>
                  <%= if log.notes && log.notes != "" do %>
                    <p class="text-xs text-base-content/40 mt-1 italic">{log.notes}</p>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%!-- Desktop table --%>
            <div class="hidden md:block bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
              <table class="table table-fixed w-full">
                <thead class="bg-base-200 text-xs uppercase tracking-wider text-base-content/50">
                  <tr>
                    <th class="w-40">Fecha / Hora</th>
                    <th class="w-48">Receta</th>
                    <th class="w-24 text-center">Lotes</th>
                    <th class="w-36">Registró</th>
                    <th>Notas</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-200">
                  <%= for log <- @recent_logs do %>
                    <tr>
                      <td class="text-sm text-base-content/60">{format_dt(log.produced_at)}</td>
                      <td class="font-medium text-sm">{log.recipe && log.recipe.name}</td>
                      <td class="text-center">
                        <span class="badge badge-success badge-sm">
                          {format_qty(log.batches)}
                        </span>
                      </td>
                      <td class="text-sm text-base-content/60">
                        {log.produced_by && log.produced_by.name}
                      </td>
                      <td class="text-sm text-base-content/40 truncate">{log.notes}</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>

    <%!-- Recipe modal --%>
    <%= if @modal != nil do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center p-2 sm:p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" phx-click="close_modal" />

        <div class="relative bg-base-100 rounded-2xl shadow-xl w-full max-w-2xl max-h-[95vh] sm:max-h-[90vh] overflow-y-auto">
          <div class="p-4 sm:p-6 space-y-4 sm:space-y-5">
            <%!-- Modal header --%>
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-bold text-base-content">
                {if @modal == :new, do: "Nueva receta", else: "Editar receta"}
              </h2>
              <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <%!-- Info callout --%>
            <div class="rounded-xl bg-info/10 border border-info/20 px-4 py-3 space-y-1.5 text-xs text-base-content/70 leading-relaxed">
              <p class="font-semibold text-base-content flex items-center gap-1.5">
                <.icon name="hero-beaker" class="size-3.5 text-info" /> ¿Qué es una receta?
              </p>
              <p>
                Una receta describe cómo producir un insumo interno a partir de otros ingredientes.
                Ejemplo: con <strong>500 gr de naranjas</strong>
                y <strong>50 ml de aceite</strong>
                produces <strong>200 ml de Oleo de Naranja</strong>.
              </p>
              <p>
                Un <strong>lote</strong>
                = ejecutar la receta una vez completa. Si registras 3 lotes, el sistema multiplica
                todos los ingredientes y el resultado por 3 automáticamente.
              </p>
            </div>

            <%!-- Recipe form --%>
            <.form for={@recipe_form} phx-submit="save_recipe" class="space-y-5">
              <%!-- phx-update="ignore" prevents LiveView from overwriting these
                   inputs when ingredient_rows state changes (which would clear
                   whatever the user has typed). The form submit still reads the
                   current DOM values correctly. --%>
              <div id="recipe-static-fields" phx-update="ignore" class="space-y-4">
                <%!-- Name (= output product) --%>
                <div class="form-control">
                  <label class="label pb-1">
                    <span class="label-text font-medium">Nombre del insumo que produces</span>
                  </label>
                  <input
                    type="text"
                    name="recipe[name]"
                    value={@recipe_form[:name].value}
                    class="input input-bordered w-full"
                    placeholder="Ej: Oleo de Naranja, Jarabe de Vainilla, Caldo Base…"
                  />
                  <p class="text-xs text-base-content/40 mt-1">
                    Este nombre aparecerá como insumo en Inventario. Si no existe, se crea automáticamente.
                  </p>
                </div>

                <%!-- Yield quantity + unit --%>
                <div>
                  <label class="label pb-1">
                    <span class="label-text font-medium">¿Cuánto produce <em>un lote</em>?</span>
                  </label>
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div class="form-control">
                      <input
                        type="number"
                        name="recipe[yield_quantity]"
                        value={@recipe_form[:yield_quantity].value}
                        min="0.001"
                        step="0.001"
                        class="input input-bordered w-full"
                        placeholder="Ej: 200"
                      />
                      <p class="text-xs text-base-content/40 mt-1">
                        Cantidad de insumo que obtienes por lote.
                      </p>
                    </div>
                    <div class="form-control">
                      <select name="recipe[yield_unit]" class="select select-bordered w-full">
                        <option value="">Unidad…</option>
                        <%= for unit <- units() do %>
                          <option
                            value={unit}
                            selected={@recipe_form[:yield_unit].value == unit}
                          >
                            {unit}
                          </option>
                        <% end %>
                      </select>
                      <p class="text-xs text-base-content/40 mt-1">
                        Ej: mililitros, gramos, porciones…
                      </p>
                    </div>
                  </div>
                </div>

                <%!-- Notes --%>
                <div class="form-control">
                  <label class="label pb-1">
                    <span class="label-text font-medium">Notas internas</span>
                    <span class="label-text-alt text-base-content/40">Opcional</span>
                  </label>
                  <textarea
                    name="recipe[notes]"
                    class="textarea textarea-bordered w-full text-sm"
                    rows="2"
                    placeholder="Instrucciones, temperatura, observaciones…"
                  >{@recipe_form[:notes].value}</textarea>
                </div>
              </div>

              <%!-- Ingredients --%>
              <div class="space-y-3">
                <div class="flex items-center justify-between">
                  <div>
                    <p class="text-sm font-semibold text-base-content">Ingredientes por lote</p>
                    <p class="text-xs text-base-content/40 mt-0.5">
                      Insumos que se consumen cada vez que produces un lote completo.
                    </p>
                  </div>
                  <button
                    type="button"
                    class="btn btn-ghost btn-xs gap-1 shrink-0"
                    phx-click="add_ingredient_row"
                  >
                    <.icon name="hero-plus" class="size-3.5" /> Agregar fila
                  </button>
                </div>

                <div class="space-y-2">
                  <%= for {row, idx} <- Enum.with_index(@ingredient_rows) do %>
                    <% row_product = Enum.find(@products, &(to_string(&1.id) == to_string(row.product_id))) %>
                    <%!-- Stack on mobile: select full-width, then qty + unit + delete in a row below --%>
                    <div class="rounded-lg border border-base-300 bg-base-100 p-2 space-y-1.5 sm:space-y-0 sm:bg-transparent sm:border-0 sm:p-0 sm:flex sm:items-center sm:gap-2">
                      <select
                        class="select select-bordered select-sm w-full sm:flex-1"
                        phx-change="update_ingredient_row"
                        phx-value-index={idx}
                        phx-value-field="product_id"
                        name={"ingredient_rows[#{idx}][product_id]"}
                      >
                        <option value="">— Selecciona insumo —</option>
                        <%= for product <- @products do %>
                          <option
                            value={product.id}
                            selected={to_string(row.product_id) == to_string(product.id)}
                          >
                            {product.name} ({product.unit})
                          </option>
                        <% end %>
                      </select>
                      <div class="flex items-center gap-1.5">
                        <input
                          type="number"
                          min="0.001"
                          step="0.001"
                          class="input input-bordered input-sm flex-1 sm:w-24 sm:flex-none"
                          placeholder="Cant."
                          value={row.quantity}
                          phx-change="update_ingredient_row"
                          name={"ingredient_rows[#{idx}][quantity]"}
                        />
                        <span class="text-xs text-base-content/40 w-8 shrink-0">
                          {if row_product, do: unit_abbr(row_product.unit), else: ""}
                        </span>
                        <button
                          type="button"
                          class="btn btn-ghost btn-sm btn-circle text-error shrink-0"
                          phx-click="remove_ingredient_row"
                          phx-value-index={idx}
                        >
                          <.icon name="hero-trash" class="size-4" />
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>

              <%!-- Submit --%>
              <div class="flex justify-end gap-3 pt-2">
                <button type="button" class="btn btn-ghost" phx-click="close_modal">
                  Cancelar
                </button>
                <button type="submit" class="btn btn-primary">
                  <.icon name="hero-check" class="size-4" /> Guardar receta
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp units do
    [
      "mililitros",
      "litros",
      "gramos",
      "kilogramos",
      "piezas",
      "porciones",
      "cucharadas",
      "cucharaditas",
      "tazas"
    ]
  end

  defp fresh_row, do: %{id: nil, product_id: "", quantity: ""}

  defp unit_abbr("piezas"), do: "pza"
  defp unit_abbr("gramos"), do: "gr"
  defp unit_abbr("kilogramos"), do: "kg"
  defp unit_abbr("mililitros"), do: "ml"
  defp unit_abbr("litros"), do: "lt"
  defp unit_abbr("onzas"), do: "oz"
  defp unit_abbr("paquetes"), do: "paq"
  defp unit_abbr("porciones"), do: "por"
  defp unit_abbr("cucharadas"), do: "cda"
  defp unit_abbr("cucharaditas"), do: "cdta"
  defp unit_abbr("tazas"), do: "tz"
  defp unit_abbr(other), do: other

  # Reads ingredient rows from the submitted form params (most reliable source)
  defp parse_ingredient_rows_from_params(params) do
    rows_map = params["ingredient_rows"] || %{}

    rows_map
    |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
    |> Enum.map(fn {_, row} ->
      %{product_id: row["product_id"] || "", quantity: row["quantity"] || ""}
    end)
  end

  defp build_ingredient_list(rows) do
    rows
    |> Enum.reject(fn row ->
      row.product_id == "" or is_nil(row.product_id) or
        (row.quantity == "" or is_nil(row.quantity))
    end)
    |> Enum.map(fn row ->
      %{
        product_id: parse_id(row.product_id),
        quantity: row.quantity
      }
    end)
  end

  defp parse_id(v) when is_binary(v) and v != "", do: String.to_integer(v)
  defp parse_id(v), do: v

  defp format_qty(nil), do: "0"

  defp format_qty(%Decimal{} = d) do
    abs = Decimal.abs(d)

    if Decimal.integer?(abs),
      do: abs |> Decimal.to_integer() |> to_string(),
      else:
        abs
        |> Decimal.round(3)
        |> Decimal.to_string()
        |> String.trim_trailing("0")
        |> String.trim_trailing(".")
  end

  defp format_qty(v), do: to_string(v)

  defp format_dt(%DateTime{} = dt),
    do: Calendar.strftime(dt, "%d %b %H:%M")

  defp format_dt(_), do: "—"
end
