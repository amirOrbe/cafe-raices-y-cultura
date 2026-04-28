defmodule CRC.Production do
  @moduledoc """
  Context for internal production (producción interna).

  Manages recipes (recetas de producción) and logs (bitácora de lotes).
  Logging a batch atomically deducts raw ingredients from stock and
  adds the resulting product to its own stock.
  """

  import Ecto.Query

  alias CRC.Repo
  alias CRC.Inventory.Product
  alias CRC.Production.{Recipe, RecipeIngredient, ProductionLog}

  @pubsub CRC.PubSub

  # ---------------------------------------------------------------------------
  # Queries
  # ---------------------------------------------------------------------------

  @doc "Returns all active recipes with ingredients (+ product) and output product preloaded."
  def list_active_recipes do
    Recipe
    |> where([r], r.active == true)
    |> order_by([r], r.name)
    |> preload([:output_product, recipe_ingredients: :product])
    |> Repo.all()
  end

  @doc "Returns all recipes (active and inactive) for admin management."
  def list_all_recipes do
    Recipe
    |> order_by([r], r.name)
    |> preload([:output_product, recipe_ingredients: :product])
    |> Repo.all()
  end

  @doc "Gets a recipe by id with full preloads. Raises if not found."
  def get_recipe!(id) do
    Recipe
    |> Repo.get!(id)
    |> Repo.preload([:output_product, recipe_ingredients: :product])
  end

  @doc "Returns the most recent N production logs with recipe and user preloaded."
  def list_recent_logs(limit \\ 50) do
    ProductionLog
    |> order_by([l], desc: l.produced_at)
    |> limit(^limit)
    |> preload([:recipe, :produced_by])
    |> Repo.all()
  end

  @doc "Returns production logs for today (UTC) with recipe and user preloaded."
  def list_today_logs do
    today_start =
      DateTime.utc_now()
      |> DateTime.to_date()
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    ProductionLog
    |> where([l], l.produced_at >= ^today_start)
    |> order_by([l], desc: l.produced_at)
    |> preload([:recipe, :produced_by])
    |> Repo.all()
  end

  @doc "Returns all active products for use in recipe selects."
  def list_products_for_select do
    Product
    |> where([p], p.active == true)
    |> order_by([p], p.name)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Recipe management (admin)
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new production recipe with its ingredient rows.
  `ingredient_list` is a list of maps: [%{product_id: id, quantity: qty}]
  """
  def create_recipe(attrs, ingredient_list) do
    Repo.transaction(fn ->
      recipe =
        %Recipe{}
        |> Recipe.changeset(attrs)
        |> Repo.insert!()

      Enum.each(ingredient_list, fn ing ->
        %RecipeIngredient{}
        |> RecipeIngredient.changeset(Map.put(ing, :recipe_id, recipe.id))
        |> Repo.insert!()
      end)

      Repo.preload(recipe, [:output_product, recipe_ingredients: :product])
    end)
  end

  @doc """
  Updates a recipe and replaces its ingredient list entirely.
  """
  def update_recipe(%Recipe{} = recipe, attrs, ingredient_list) do
    Repo.transaction(fn ->
      updated =
        recipe
        |> Recipe.changeset(attrs)
        |> Repo.update!()

      # Replace all ingredients
      from(ri in RecipeIngredient, where: ri.recipe_id == ^recipe.id)
      |> Repo.delete_all()

      Enum.each(ingredient_list, fn ing ->
        %RecipeIngredient{}
        |> RecipeIngredient.changeset(Map.put(ing, :recipe_id, recipe.id))
        |> Repo.insert!()
      end)

      Repo.preload(updated, [:output_product, recipe_ingredients: :product],
        force: true
      )
    end)
  end

  @doc "Toggles a recipe between active and inactive."
  def toggle_recipe_active(%Recipe{} = recipe) do
    recipe
    |> Recipe.changeset(%{active: !recipe.active})
    |> Repo.update()
  end

  def change_recipe(%Recipe{} = recipe, attrs \\ %{}) do
    Recipe.changeset(recipe, attrs)
  end

  # ---------------------------------------------------------------------------
  # Production logging (all staff)
  # ---------------------------------------------------------------------------

  @doc """
  Registers a production batch.

  Atomically:
    1. Deducts each ingredient × batches from products.stock_quantity
    2. Adds yield_quantity × batches to output_product.stock_quantity
    3. Inserts a production_log record

  Returns {:ok, log} or {:error, reason}.
  """
  def log_production(recipe_id, batches, user_id, notes \\ nil) do
    recipe = get_recipe!(recipe_id)
    batches_d = parse_decimal(batches)

    if Decimal.compare(batches_d, Decimal.new(0)) != :gt do
      {:error, :invalid_batches}
    else
      Repo.transaction(fn ->
        # 1. Deduct raw ingredients
        Enum.each(recipe.recipe_ingredients, fn ri ->
          deduct = Decimal.mult(ri.quantity, batches_d)

          from(p in Product, where: p.id == ^ri.product_id)
          |> Repo.update_all(inc: [stock_quantity: Decimal.negate(deduct)])
        end)

        # 2. Add produced quantity to output product
        add = Decimal.mult(recipe.yield_quantity, batches_d)

        from(p in Product, where: p.id == ^recipe.output_product_id)
        |> Repo.update_all(inc: [stock_quantity: add])

        # 3. Log the batch
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        %ProductionLog{}
        |> ProductionLog.changeset(%{
          recipe_id: recipe_id,
          batches: batches_d,
          notes: notes,
          produced_by_id: user_id,
          produced_at: now
        })
        |> Repo.insert!()
      end)
      |> case do
        {:ok, log} ->
          broadcast_stock_update()
          {:ok, log}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  @doc """
  Computes the cost per output unit for a recipe.
  Returns nil if any ingredient is missing net_cost.
  """
  def recipe_unit_cost(%Recipe{recipe_ingredients: [], yield_quantity: _}), do: nil

  def recipe_unit_cost(%Recipe{recipe_ingredients: ingredients, yield_quantity: yield}) do
    costs =
      Enum.map(ingredients, fn ri ->
        if ri.product && ri.product.net_cost do
          Decimal.mult(ri.quantity, ri.product.net_cost)
        end
      end)

    if Enum.all?(costs, &(&1 != nil)) do
      total = Enum.reduce(costs, Decimal.new(0), &Decimal.add/2)
      Decimal.div(total, yield) |> Decimal.round(4)
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp parse_decimal(v) when is_binary(v) do
    case Decimal.parse(v) do
      {d, _} -> d
      :error -> Decimal.new(0)
    end
  end

  defp parse_decimal(%Decimal{} = d), do: d
  defp parse_decimal(v), do: Decimal.new("#{v}")

  defp broadcast_stock_update do
    Phoenix.PubSub.broadcast(@pubsub, "menu_stock", :stock_updated)
    Phoenix.PubSub.broadcast(@pubsub, "admin:products", {:product_changed, :stock})
  end
end
