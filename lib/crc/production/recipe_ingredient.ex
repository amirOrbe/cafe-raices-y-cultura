defmodule CRC.Production.RecipeIngredient do
  @moduledoc "An ingredient (product) consumed per batch of a production recipe."

  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Inventory.Product
  alias CRC.Production.Recipe

  schema "production_recipe_ingredients" do
    field :quantity, :decimal

    belongs_to :recipe, Recipe
    belongs_to :product, Product

    timestamps(type: :utc_datetime)
  end

  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [:recipe_id, :product_id, :quantity])
    |> validate_required([:recipe_id, :product_id, :quantity],
      message: "no puede estar en blanco"
    )
    |> validate_number(:quantity, greater_than: 0, message: "debe ser mayor a 0")
    |> unique_constraint([:recipe_id, :product_id],
      message: "este insumo ya está en la receta"
    )
  end
end
