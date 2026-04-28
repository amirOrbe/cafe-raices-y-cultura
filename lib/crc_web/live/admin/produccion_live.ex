defmodule CRCWeb.Admin.ProduccionLive do
  @moduledoc """
  Admin view for Producción Interna.

  Recipe name = output product name (auto-resolved on save via Inventory lookup).
  Lets admins create/edit recipes with dynamic ingredient rows and browse history.
  """

  use CRCWeb, :live_view

  import CRCWeb.Layouts, only: [flash_group: 1]

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

    # Auto-resolve output product from recipe name
    recipe_name = params["name"] || ""

    case Inventory.find_product_by_name(recipe_name) do
      nil ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "No existe ningún insumo llamado \"#{recipe_name}\". Créalo primero en Insumos."
         )}

      product ->
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
              <p class="text-sm text-base-content/50">Gestiona recetas de producción y revisa el historial.</p>
            </div>
          </div>
          <%= if @tab == :recipes do %>
            <button class="btn btn-primary btn-sm gap-2" phx-click="new_recipe">
              <.icon name="hero-plus" class="size-4" />
              Nueva receta
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
            Recetas
            <span class="ml-2 badge badge-ghost badge-sm">{length(@recipes)}</span>
          </button>
          <button
            class={"tab #{if @tab == :history, do: "tab-active"}"}
            phx-click="set_tab"
            phx-value-tab="history"
          >
            Historial
            <span class="ml-2 badge badge-ghost badge-sm">{length(@recent_logs)}</span>
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
                      {format_qty(log.batches)} {if Decimal.compare(log.batches, Decimal.new(1)) == :eq, do: "lote", else: "lotes"}
                    </span>
                  </div>
                  <p class="text-xs text-base-content/50 mt-1">
                    {log.produced_by && log.produced_by.name}
                    · {format_dt(log.produced_at)}
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
                      <td class="text-sm text-base-content/60">{log.produced_by && log.produced_by.name}</td>
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
      <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" phx-click="close_modal" />

        <div class="relative bg-base-100 rounded-2xl shadow-xl w-full max-w-2xl max-h-[90vh] overflow-y-auto">
          <div class="p-6 space-y-5">

            <%!-- Modal header --%>
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-bold text-base-content">
                {if @modal == :new, do: "Nueva receta", else: "Editar receta"}
              </h2>
              <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <%!-- Recipe form --%>
            <.form for={@recipe_form} phx-submit="save_recipe" class="space-y-5">

              <%!-- Name (= output product) --%>
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-medium">Nombre del producto que se produce</span>
                </label>
                <input
                  type="text"
                  name="recipe[name]"
                  value={@recipe_form[:name].value}
                  class={"input input-bordered w-full #{if @recipe_form[:name].errors != [], do: "input-error"}"}
                  placeholder="Ej: Oleo de Naranja"
                />
                <p class="text-xs text-base-content/40 mt-1">
                  Debe coincidir exactamente con el nombre del insumo registrado en Inventario.
                </p>
                <%= for {msg, _} <- @recipe_form[:name].errors do %>
                  <p class="text-xs text-error mt-1">{msg}</p>
                <% end %>
              </div>

              <%!-- Yield quantity + unit --%>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Cantidad que produce</span>
                  </label>
                  <input
                    type="number"
                    name="recipe[yield_quantity]"
                    value={@recipe_form[:yield_quantity].value}
                    min="0.001"
                    step="0.001"
                    class={"input input-bordered w-full #{if @recipe_form[:yield_quantity].errors != [], do: "input-error"}"}
                    placeholder="Ej: 500"
                  />
                  <%= for {msg, _} <- @recipe_form[:yield_quantity].errors do %>
                    <p class="text-xs text-error mt-1">{msg}</p>
                  <% end %>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Unidad</span>
                  </label>
                  <select
                    name="recipe[yield_unit]"
                    class={"select select-bordered w-full #{if @recipe_form[:yield_unit].errors != [], do: "select-error"}"}
                  >
                    <option value="">Seleccionar…</option>
                    <%= for unit <- units() do %>
                      <option
                        value={unit}
                        selected={@recipe_form[:yield_unit].value == unit}
                      >
                        {unit}
                      </option>
                    <% end %>
                  </select>
                  <%= for {msg, _} <- @recipe_form[:yield_unit].errors do %>
                    <p class="text-xs text-error mt-1">{msg}</p>
                  <% end %>
                </div>
              </div>

              <%!-- Ingredients --%>
              <div class="space-y-3">
                <div class="flex items-center justify-between">
                  <p class="text-sm font-semibold text-base-content">Ingredientes por lote</p>
                  <button
                    type="button"
                    class="btn btn-ghost btn-xs gap-1"
                    phx-click="add_ingredient_row"
                  >
                    <.icon name="hero-plus" class="size-3.5" />
                    Agregar
                  </button>
                </div>

                <div class="space-y-2">
                  <%= for {row, idx} <- Enum.with_index(@ingredient_rows) do %>
                    <div class="flex items-center gap-2">
                      <select
                        class="select select-bordered select-sm flex-1"
                        phx-change="update_ingredient_row"
                        phx-value-index={idx}
                        phx-value-field="product_id"
                        name={"ingredient_rows[#{idx}][product_id]"}
                      >
                        <option value="">Insumo…</option>
                        <%= for product <- @products do %>
                          <option value={product.id} selected={to_string(row.product_id) == to_string(product.id)}>
                            {product.name}
                          </option>
                        <% end %>
                      </select>
                      <input
                        type="number"
                        min="0.001"
                        step="0.001"
                        class="input input-bordered input-sm w-24"
                        placeholder="Cant."
                        value={row.quantity}
                        phx-change="update_ingredient_row"
                        name={"ingredient_rows[#{idx}][quantity]"}
                      />
                      <button
                        type="button"
                        class="btn btn-ghost btn-sm btn-circle text-error"
                        phx-click="remove_ingredient_row"
                        phx-value-index={idx}
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>

              <%!-- Notes --%>
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-medium">Notas internas</span>
                  <span class="label-text-alt text-base-content/40">Opcional</span>
                </label>
                <textarea
                  name="recipe[notes]"
                  class="textarea textarea-bordered w-full text-sm"
                  rows="2"
                  placeholder="Instrucciones, observaciones…"
                >{@recipe_form[:notes].value}</textarea>
              </div>

              <%!-- Submit --%>
              <div class="flex justify-end gap-3 pt-2">
                <button type="button" class="btn btn-ghost" phx-click="close_modal">
                  Cancelar
                </button>
                <button type="submit" class="btn btn-primary">
                  <.icon name="hero-check" class="size-4" />
                  Guardar receta
                </button>
              </div>
            </.form>

          </div>
        </div>
      </div>
    <% end %>

    <.flash_group flash={@flash} />
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp units do
    [
      "mililitros", "litros",
      "gramos", "kilogramos",
      "piezas", "porciones",
      "cucharadas", "cucharaditas", "tazas"
    ]
  end

  defp fresh_row, do: %{id: nil, product_id: "", quantity: ""}

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
      (row.product_id == "" or is_nil(row.product_id)) or
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
      else: abs |> Decimal.round(3) |> Decimal.to_string() |> String.trim_trailing("0") |> String.trim_trailing(".")
  end
  defp format_qty(v), do: to_string(v)

  defp format_dt(%DateTime{} = dt),
    do: Calendar.strftime(dt, "%d %b %H:%M")
  defp format_dt(_), do: "—"
end
