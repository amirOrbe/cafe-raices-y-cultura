defmodule CRC.Catalog.MenuItemIngredient do
  @moduledoc "Ingredient (product) that makes up a menu item, with quantity."

  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Catalog.MenuItem
  alias CRC.Inventory.Product

  schema "menu_item_ingredients" do
    belongs_to :menu_item, MenuItem
    belongs_to :product, Product

    field :quantity, :decimal

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(mii, attrs) do
    mii
    |> cast(attrs, [:menu_item_id, :product_id, :quantity])
    |> validate_required([:menu_item_id, :product_id, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> unique_constraint([:menu_item_id, :product_id],
      message: "este ingrediente ya está en el platillo"
    )
  end
end
