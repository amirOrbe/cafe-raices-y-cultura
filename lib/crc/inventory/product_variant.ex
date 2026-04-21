defmodule CRC.Inventory.ProductVariant do
  @moduledoc """
  A specific type or variant of a product/supply.

  Examples: "Entera", "Avena", "Deslactosada" are variants of the "Leche" product.

  Each variant tracks its own stock level and can carry an extra charge
  over the parent product's base price. Variants are optional — not every
  product needs them.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Inventory.Product

  @type t :: %__MODULE__{}

  schema "product_variants" do
    field :name, :string
    field :extra_charge, :decimal, default: Decimal.new(0)
    field :stock_quantity, :decimal, default: Decimal.new(0)
    field :min_stock, :decimal, default: Decimal.new(0)
    field :active, :boolean, default: true

    belongs_to :product, Product

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(variant, attrs) do
    variant
    |> cast(attrs, [:product_id, :name, :extra_charge, :stock_quantity, :min_stock, :active])
    |> update_change(:name, &CRC.Utils.title_case/1)
    |> validate_required([:product_id, :name], message: "no puede estar en blanco")
    |> validate_length(:name, min: 1, max: 80)
    |> validate_number(:extra_charge,
      greater_than_or_equal_to: 0,
      message: "debe ser mayor o igual a 0"
    )
    |> validate_number(:stock_quantity,
      greater_than_or_equal_to: 0,
      message: "debe ser mayor o igual a 0"
    )
    |> validate_number(:min_stock,
      greater_than_or_equal_to: 0,
      message: "debe ser mayor o igual a 0"
    )
    |> unique_constraint([:product_id, :name],
      message: "ya existe un tipo con ese nombre para este insumo"
    )
  end
end
