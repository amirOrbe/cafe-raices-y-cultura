defmodule CRC.Inventory.Supplier do
  @moduledoc """
  Schema representing a product supplier.

  Suppliers are linked to products. A supplier can be deactivated
  without deleting their associated products (FK nilify_all).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "suppliers" do
    field :name, :string
    field :contact_name, :string
    field :phone, :string
    field :email, :string
    field :address, :string
    field :notes, :string
    field :active, :boolean, default: true

    has_many :products, CRC.Inventory.Product

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(supplier, attrs) do
    supplier
    |> cast(attrs, [:name, :contact_name, :phone, :email, :address, :notes, :active])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 120, message: "debe tener entre 2 y 120 caracteres")
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "tiene formato inválido"
    )
  end
end
