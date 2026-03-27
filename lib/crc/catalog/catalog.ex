defmodule CRC.Catalog do
  @moduledoc """
  The Catalog context manages the menu: categories and menu items.
  """

  import Ecto.Query, warn: false
  alias CRC.Repo
  alias CRC.Catalog.{Category, MenuItem, MenuItemIngredient}

  # ---------------------------------------------------------------------------
  # Categories
  # ---------------------------------------------------------------------------

  @doc "Returns all active categories ordered by position, preloading their items."
  def list_categories do
    Category
    |> where(active: true)
    |> order_by(:position)
    |> preload(menu_items: ^available_items_query())
    |> Repo.all()
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
    from(p in CRC.Inventory.Product,
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

  defp available_items_query do
    from m in MenuItem, where: m.available == true, order_by: m.position
  end
end
