defmodule CRC.Catalog do
  @moduledoc """
  The Catalog context manages the menu: categories and menu items.
  """

  import Ecto.Query, warn: false
  alias CRC.Repo
  alias CRC.Catalog.{Category, MenuItem}

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

  @doc "Deletes a menu item."
  def delete_menu_item(%MenuItem{} = item), do: Repo.delete(item)

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp available_items_query do
    from m in MenuItem, where: m.available == true, order_by: m.position
  end
end
