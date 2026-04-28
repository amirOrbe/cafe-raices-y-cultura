defmodule CRC.Production.Recipe do
  @moduledoc "A production recipe: defines what ingredients are consumed and what product is created."

  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Inventory.Product
  alias CRC.Production.{RecipeIngredient, ProductionLog}

  schema "production_recipes" do
    field :name, :string
    field :yield_quantity, :decimal
    field :yield_unit, :string
    field :notes, :string
    field :active, :boolean, default: true

    belongs_to :output_product, Product
    has_many :recipe_ingredients, RecipeIngredient, on_delete: :delete_all
    has_many :production_logs, ProductionLog, on_delete: :nothing

    timestamps(type: :utc_datetime)
  end

  def changeset(recipe, attrs) do
    recipe
    |> cast(attrs, [:name, :yield_quantity, :yield_unit, :notes, :active, :output_product_id])
    |> update_change(:name, &CRC.Utils.title_case/1)
    |> validate_required([:name, :yield_quantity, :yield_unit, :output_product_id],
      message: "no puede estar en blanco"
    )
    |> validate_length(:name, min: 2, max: 120)
    |> validate_number(:yield_quantity,
      greater_than: 0,
      message: "debe ser mayor a 0"
    )
    |> unique_constraint(:name, message: "ya existe una receta con ese nombre")
  end
end
