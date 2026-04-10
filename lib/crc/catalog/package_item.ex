defmodule CRC.Catalog.PackageItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "package_items" do
    field :quantity, :integer, default: 1

    belongs_to :package, CRC.Catalog.Package
    belongs_to :menu_item, CRC.Catalog.MenuItem

    timestamps(type: :utc_datetime)
  end

  def changeset(package_item, attrs) do
    package_item
    |> cast(attrs, [:package_id, :menu_item_id, :quantity])
    |> validate_required([:menu_item_id, :quantity])
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:package_id)
    |> foreign_key_constraint(:menu_item_id)
    |> unique_constraint([:package_id, :menu_item_id])
  end
end
