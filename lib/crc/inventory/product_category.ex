defmodule CRC.Inventory.ProductCategory do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "product_categories" do
    field :name, :string
    has_many :products, CRC.Inventory.Product, foreign_key: :product_category_id
    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name])
    |> validate_required([:name], message: "no puede estar en blanco")
    |> validate_length(:name, min: 2, max: 60, message: "debe tener entre 2 y 60 caracteres")
    |> unique_constraint(:name, message: "ya existe una categoría con ese nombre")
  end
end
