defmodule CRC.Catalog do
  @moduledoc """
  The Catalog context manages the menu: categories and menu items.
  """

  import Ecto.Query, warn: false
  alias CRC.Repo
  alias CRC.Catalog.{Category, MenuItem, MenuItemIngredient}
  alias CRC.Inventory.Product

  # ---------------------------------------------------------------------------
  # Categories
  # ---------------------------------------------------------------------------

  @doc "Returns all active categories ordered by position, preloading their items with ingredient quantities."
  def list_categories do
    Category
    |> where(active: true)
    |> order_by(:position)
    |> preload(menu_items: ^available_items_query())
    |> Repo.all()
    |> Repo.preload(menu_items: [menu_item_ingredients: :product])
  end

  @doc "Returns all categories (including inactive) for admin use."
  def list_all_categories do
    Category
    |> order_by(:position)
    |> Repo.all()
  end

  @doc "Gets a single category by id. Raises if not found."
  def get_category!(id), do: Repo.get!(Category, id)

  @doc "Creates a category."
  def create_category(attrs \\ %{}) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a category."
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a category."
  def delete_category(%Category{} = category), do: Repo.delete(category)

  # ---------------------------------------------------------------------------
  # Menu Items
  # ---------------------------------------------------------------------------

  @doc "Returns all available menu items."
  def list_menu_items do
    MenuItem
    |> where(available: true)
    |> order_by([:category_id, :position])
    |> preload(:category)
    |> Repo.all()
  end

  @doc "Returns all menu items (including unavailable) for admin use."
  def list_all_menu_items do
    MenuItem
    |> order_by([:category_id, :position])
    |> preload(:category)
    |> Repo.all()
  end

  @doc "Returns featured menu items."
  def list_featured_items do
    MenuItem
    |> where(available: true, featured: true)
    |> order_by(:position)
    |> preload(:category)
    |> Repo.all()
  end

  @doc "Gets a single menu item by id. Raises if not found."
  def get_menu_item!(id), do: Repo.get!(MenuItem, id) |> Repo.preload(:category)

  @doc "Gets a menu item with its ingredients preloaded. Raises if not found."
  def get_menu_item_with_ingredients!(id) do
    MenuItem
    |> Repo.get!(id)
    |> Repo.preload(:category)
    |> Repo.preload(menu_item_ingredients: :product)
  end

  @doc "Returns a changeset for a menu item."
  def change_menu_item(%MenuItem{} = item, attrs \\ %{}) do
    MenuItem.changeset(item, attrs)
  end

  @doc "Creates a menu item."
  def create_menu_item(attrs \\ %{}) do
    %MenuItem{}
    |> MenuItem.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a menu item."
  def update_menu_item(%MenuItem{} = item, attrs) do
    item
    |> MenuItem.changeset(attrs)
    |> Repo.update()
  end

  @doc "Toggles the available status of a menu item."
  def toggle_menu_item_available(%MenuItem{} = item) do
    update_menu_item(item, %{available: !item.available})
  end

  @doc "Deletes a menu item."
  def delete_menu_item(%MenuItem{} = item), do: Repo.delete(item)

  # ---------------------------------------------------------------------------
  # Ingredients
  # ---------------------------------------------------------------------------

  @doc """
  Lists products without a supplier — these are the ingredients used in menu items.
  """
  def list_ingredient_products do
    from(p in Product,
      where: is_nil(p.supplier_id) and p.active == true,
      order_by: p.name
    )
    |> Repo.all()
  end

  @doc """
  Replaces all ingredients for a menu item with the given list.
  Each entry is a map with :product_id and :quantity keys.
  Runs inside a transaction.
  """
  def set_menu_item_ingredients(menu_item_id, ingredients) when is_list(ingredients) do
    Repo.transaction(fn ->
      Repo.delete_all(
        from mii in MenuItemIngredient, where: mii.menu_item_id == ^menu_item_id
      )

      Enum.each(ingredients, fn %{product_id: pid, quantity: qty} ->
        %MenuItemIngredient{}
        |> MenuItemIngredient.changeset(%{
          menu_item_id: menu_item_id,
          product_id: pid,
          quantity: qty
        })
        |> Repo.insert!()
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @doc """
  Returns available menu items for a given category, preloading ingredient stock.
  Each entry is a `{%MenuItem{}, available_portions}` tuple where:
  - `nil`     — no recipe defined; item is always available (unlimited)
  - `0`       — at least one ingredient is fully depleted; item is unavailable
  - integer   — the number of portions that can still be prepared before running out
  """
  def list_menu_items_for_category_with_stock(category_id) do
    MenuItem
    |> where(available: true, category_id: ^category_id)
    |> order_by(:position)
    |> preload([:category, menu_item_ingredients: :product])
    |> Repo.all()
    |> Enum.map(&{&1, available_portions(&1)})
  end

  @doc """
  Returns all unique ingredient products used by available menu items in a given category.
  Used to populate the "extras disponibles" panel in the waiter comanda view.
  """
  def list_extras_for_category(category_id) do
    from(p in Product,
      join: mii in MenuItemIngredient,
      on: mii.product_id == p.id,
      join: mi in MenuItem,
      on: mi.id == mii.menu_item_id,
      where: mi.category_id == ^category_id and mi.available == true and p.active == true,
      distinct: p.id,
      order_by: p.name
    )
    |> Repo.all()
  end

  @doc """
  Returns extras for a specific menu item as `{%Product{}, portion_quantity}` tuples.

  - If the product is an ingredient of the given menu item → uses that item's exact recipe quantity.
  - If the product belongs to the category but not this item → uses (min + max) / 2 across the category.

  Results are sorted by product name.
  """
  def list_extras_for_menu_item(menu_item_id, category_id) do
    all_products =
      from(p in Product,
        join: mii in MenuItemIngredient, on: mii.product_id == p.id,
        join: mi in MenuItem, on: mi.id == mii.menu_item_id,
        where: mi.category_id == ^category_id and mi.available == true and p.active == true,
        distinct: p.id,
        order_by: p.name
      )
      |> Repo.all()

    # Exact quantities from this menu item's recipe: %{product_id => quantity}
    item_quantities =
      from(mii in MenuItemIngredient, where: mii.menu_item_id == ^menu_item_id)
      |> Repo.all()
      |> Map.new(&{&1.product_id, &1.quantity})

    # Category-level avg (min + max) / 2 fallback: %{product_id => avg_quantity}
    product_ids = Enum.map(all_products, & &1.id)

    category_avgs =
      from(mii in MenuItemIngredient,
        join: mi in MenuItem, on: mi.id == mii.menu_item_id,
        where: mi.category_id == ^category_id and mii.product_id in ^product_ids,
        group_by: mii.product_id,
        select: {mii.product_id, fragment("(MIN(?) + MAX(?)) / 2.0", mii.quantity, mii.quantity)}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(all_products, fn product ->
      qty =
        Map.get(item_quantities, product.id) ||
          Map.get(category_avgs, product.id, Decimal.new(1))

      {product, qty}
    end)
  end

  @doc """
  Returns the number of complete portions that can still be prepared for a menu item.

  - `nil`     — no recipe; availability is unlimited (always orderable)
  - `0`       — at least one ingredient is depleted; item cannot be prepared
  - integer n — the item can be prepared exactly n more times before an ingredient runs out

  The bottleneck ingredient (lowest floor(stock / quantity_per_portion)) determines the result.
  Inactive or missing products are treated as 0 stock.
  """
  def available_portions(%MenuItem{menu_item_ingredients: []}), do: nil

  def available_portions(%MenuItem{menu_item_ingredients: ingredients}) do
    ingredients
    |> Enum.map(fn mii ->
      if is_nil(mii.product) or not mii.product.active do
        0
      else
        mii.product.stock_quantity
        |> Decimal.div(mii.quantity)
        |> Decimal.round(0, :floor)
        |> Decimal.to_integer()
      end
    end)
    |> Enum.min()
  end

  @doc """
  Returns true when every ingredient has enough stock for at least one serving.
  Kept for backward compatibility; prefer `available_portions/1` for richer info.
  """
  def item_in_stock?(menu_item) do
    case available_portions(menu_item) do
      nil -> true
      n -> n > 0
    end
  end

  defp available_items_query do
    from m in MenuItem, where: m.available == true, order_by: m.position
  end
end
