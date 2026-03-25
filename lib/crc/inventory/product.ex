defmodule CRC.Inventory.Product do
  @moduledoc """
  Schema representing a product or supply item (insumo).

  Categories cover all current and planned offerings:
  food, drinks, dairy, coffee beans, bakery/sandwiches,
  cocktail ingredients, disposables, cleaning, utensils.

  Units support both weight-based (gr, kg, oz) and
  volume-based (ml, lt) as well as discrete (pza, paquete).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @categories ~w(alimentos bebidas lacteos granos panaderia cocteleria desechables limpieza utensilios otro)
  @units ~w(piezas gramos kilogramos mililitros litros onzas paquetes)

  def categories, do: @categories
  def units, do: @units

  schema "products" do
    field :name, :string
    field :category, :string
    field :net_cost, :decimal
    field :sale_price, :decimal
    field :stock_quantity, :decimal, default: Decimal.new(0)
    field :min_stock, :decimal, default: Decimal.new(0)
    field :unit, :string
    field :notes, :string
    field :active, :boolean, default: true

    belongs_to :supplier, CRC.Inventory.Supplier

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :name,
      :category,
      :net_cost,
      :sale_price,
      :stock_quantity,
      :min_stock,
      :unit,
      :notes,
      :active,
      :supplier_id
    ])
    |> validate_required([:name, :category, :net_cost, :stock_quantity, :unit],
      message: "no puede estar en blanco"
    )
    |> validate_inclusion(:category, @categories, message: "no es una opción válida")
    |> validate_inclusion(:unit, @units, message: "no es una opción válida")
    |> validate_number(:net_cost, greater_than_or_equal_to: 0, message: "debe ser mayor o igual a 0")
    |> validate_number(:sale_price, greater_than_or_equal_to: 0, message: "debe ser mayor o igual a 0")
    |> validate_number(:stock_quantity, greater_than_or_equal_to: 0, message: "debe ser mayor o igual a 0")
    |> validate_number(:min_stock, greater_than_or_equal_to: 0, message: "debe ser mayor o igual a 0")
  end
end
