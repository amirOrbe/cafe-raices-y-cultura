defmodule CRC.Inventory.Product do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @units ~w(piezas gramos kilogramos mililitros litros onzas paquetes)

  def units, do: @units

  schema "products" do
    field :name, :string
    field :net_cost, :decimal
    field :sale_price, :decimal
    field :stock_quantity, :decimal, default: Decimal.new(0)
    field :min_stock, :decimal, default: Decimal.new(0)
    field :unit, :string
    field :notes, :string
    field :active, :boolean, default: true

    belongs_to :supplier, CRC.Inventory.Supplier
    belongs_to :product_category, CRC.Inventory.ProductCategory
    has_many :variants, CRC.Inventory.ProductVariant, preload_order: [asc: :name]

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :name,
      :product_category_id,
      :net_cost,
      :sale_price,
      :stock_quantity,
      :min_stock,
      :unit,
      :notes,
      :active,
      :supplier_id
    ])
    |> update_change(:name, &CRC.Utils.title_case/1)
    |> validate_required([:name, :net_cost, :stock_quantity, :unit],
      message: "no puede estar en blanco"
    )
    |> validate_inclusion(:unit, @units, message: "no es una opción válida")
    |> validate_number(:net_cost, greater_than_or_equal_to: 0, message: "debe ser mayor o igual a 0")
    |> validate_number(:sale_price, greater_than_or_equal_to: 0, message: "debe ser mayor o igual a 0")
    |> validate_number(:stock_quantity, greater_than_or_equal_to: 0, message: "debe ser mayor o igual a 0")
    |> validate_number(:min_stock, greater_than_or_equal_to: 0, message: "debe ser mayor o igual a 0")
  end
end
