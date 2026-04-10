defmodule CRC.Catalog.Package do
  use Ecto.Schema
  import Ecto.Changeset

  schema "packages" do
    field :name, :string
    field :description, :string
    field :price, :decimal
    field :active, :boolean, default: true
    field :featured, :boolean, default: false

    has_many :package_items, CRC.Catalog.PackageItem, on_delete: :delete_all
    has_many :menu_items, through: [:package_items, :menu_item]

    timestamps(type: :utc_datetime)
  end

  def changeset(package, attrs) do
    package
    |> cast(attrs, [:name, :description, :price, :active, :featured])
    |> validate_required([:name, :price])
    |> validate_number(:price, greater_than: 0)
    |> unique_constraint(:name)
  end
end
