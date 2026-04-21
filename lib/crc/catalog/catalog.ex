defmodule CRC.Catalog do
  @moduledoc """
  The Catalog context manages the menu: categories and menu items.
  """

  import Ecto.Query, warn: false
  alias CRC.Repo
  alias CRC.Catalog.{Category, MenuItem, MenuItemIngredient, Package, PackageItem}
  alias CRC.Inventory.Product

  # ---------------------------------------------------------------------------
  # Categories
  # ---------------------------------------------------------------------------

  @doc "Returns all active categories ordered by name, preloading their items with ingredient quantities."
  def list_categories do
    Category
    |> where(active: true)
    |> order_by(:name)
    |> preload(menu_items: ^available_items_query())
    |> Repo.all()
    |> Repo.preload(menu_items: [menu_item_ingredients: [product: :variants]])
  end

  @doc "Returns all categories (including inactive) for admin use."
  def list_all_categories do
    Category
    |> order_by(:name)
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

  @doc "Returns a changeset for a category."
  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  # ---------------------------------------------------------------------------
  # Menu Items
  # ---------------------------------------------------------------------------

  @doc "Returns all available menu items."
  def list_menu_items do
    MenuItem
    |> where(available: true)
    |> order_by([:category_id, :name])
    |> preload(:category)
    |> Repo.all()
  end

  @doc "Returns all menu items (including unavailable) for admin use."
  def list_all_menu_items do
    MenuItem
    |> order_by([:category_id, :name])
    |> preload(:category)
    |> Repo.all()
  end

  @doc "Returns featured menu items."
  def list_featured_items do
    MenuItem
    |> where(available: true, featured: true)
    |> order_by(:name)
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
    |> order_by(:name)
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
    from m in MenuItem, where: m.available == true, order_by: m.name
  end

  # ---------------------------------------------------------------------------
  # Packages
  # ---------------------------------------------------------------------------

  @doc "Returns all active packages, preloading items and menu_items."
  def list_packages do
    Package
    |> where(active: true)
    |> order_by(:name)
    |> preload(package_items: :menu_item)
    |> Repo.all()
  end

  @doc "Returns all packages (including inactive) for admin, preloading items."
  def list_all_packages do
    Package
    |> order_by(:name)
    |> preload(package_items: :menu_item)
    |> Repo.all()
  end

  @doc "Gets a single package by id with items preloaded. Raises if not found."
  def get_package!(id) do
    Package
    |> Repo.get!(id)
    |> Repo.preload(package_items: :menu_item)
  end

  def create_package(attrs \\ %{}) do
    %Package{}
    |> Package.changeset(attrs)
    |> Repo.insert()
  end

  def update_package(%Package{} = package, attrs) do
    package
    |> Package.changeset(attrs)
    |> Repo.update()
  end

  def delete_package(%Package{} = package) do
    Repo.delete(package)
  end

  def change_package(%Package{} = package, attrs \\ %{}) do
    Package.changeset(package, attrs)
  end

  @doc "Adds or replaces all package_items for a package given a list of %{menu_item_id, quantity} maps."
  def set_package_items(%Package{} = package, items) when is_list(items) do
    Repo.transaction(fn ->
      Repo.delete_all(from pi in PackageItem, where: pi.package_id == ^package.id)

      Enum.each(items, fn item ->
        %PackageItem{}
        |> PackageItem.changeset(Map.put(item, :package_id, package.id))
        |> Repo.insert!()
      end)

      get_package!(package.id)
    end)
  end

  @doc """
  Returns menu items with computed cost and margin for package recommendations.
  Only includes items that have at least one ingredient with a known cost.
  """
  def menu_items_with_margin do
    MenuItem
    |> where(available: true)
    |> order_by(:name)
    |> preload(menu_item_ingredients: :product)
    |> Repo.all()
    |> Enum.map(fn mi ->
      cost = compute_cost(mi)
      margin = if cost && Decimal.compare(mi.price, Decimal.new(0)) == :gt do
        mi.price
        |> Decimal.sub(cost)
        |> Decimal.div(mi.price)
        |> Decimal.mult(100)
        |> Decimal.round(1)
      end

      %{menu_item: mi, cost: cost, margin: margin}
    end)
    |> Enum.filter(& &1.cost != nil)
    |> Enum.sort_by(& &1.margin, :desc)
  end

  @doc "Suggests up to `count` package combos based on ingredient cost data."
  def suggest_packages(count \\ 3) do
    items = menu_items_with_margin()

    case items do
      [] -> []
      [_] -> []
      _ ->
        pairs = for i <- items, j <- items, i.menu_item.id < j.menu_item.id, do: {i, j}

        pairs
        |> Enum.map(fn {a, b} ->
          normal_price = Decimal.add(a.menu_item.price, b.menu_item.price)
          total_cost = Decimal.add(a.cost, b.cost)
          suggested_price = normal_price |> Decimal.mult("0.85") |> Decimal.round(0)
          package_margin =
            suggested_price
            |> Decimal.sub(total_cost)
            |> Decimal.div(suggested_price)
            |> Decimal.mult(100)
            |> Decimal.round(1)

          %{
            item_a: a,
            item_b: b,
            normal_price: normal_price,
            suggested_price: suggested_price,
            total_cost: total_cost,
            package_margin: package_margin,
            savings: Decimal.sub(normal_price, suggested_price)
          }
        end)
        |> Enum.filter(fn s -> Decimal.compare(s.package_margin, Decimal.new(30)) != :lt end)
        |> Enum.sort_by(& &1.package_margin, :desc)
        |> Enum.take(count)
    end
  end

  defp compute_cost(%MenuItem{menu_item_ingredients: []}), do: nil
  defp compute_cost(%MenuItem{menu_item_ingredients: ingredients}) do
    costs = Enum.map(ingredients, fn mii ->
      if mii.product && mii.product.net_cost do
        Decimal.mult(mii.product.net_cost, mii.quantity)
      end
    end)

    if Enum.all?(costs, & &1 != nil) do
      Enum.reduce(costs, Decimal.new(0), &Decimal.add/2)
    end
  end
end
