defmodule CRC.Catalog.MenuItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Catalog.Category

  schema "menu_items" do
    field :name, :string
    field :description, :string
    field :price, :decimal
    field :image_url, :string
    field :available, :boolean, default: true
    field :featured, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :category, Category

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(menu_item, attrs) do
    menu_item
    |> cast(attrs, [:name, :description, :price, :image_url, :available, :featured, :position, :category_id])
    |> validate_required([:name, :price, :category_id])
    |> validate_number(:price, greater_than: 0)
    |> assoc_constraint(:category)
  end
end
