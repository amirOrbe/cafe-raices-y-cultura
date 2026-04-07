defmodule CRC.Catalog.MenuItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Catalog.{Category, MenuItemIngredient}

  schema "menu_items" do
    field :name, :string
    field :description, :string
    field :price, :decimal
    field :available, :boolean, default: true
    field :featured, :boolean, default: false

    belongs_to :category, Category
    has_many :menu_item_ingredients, MenuItemIngredient

    timestamps(type: :utc_datetime)
  end

  def changeset(menu_item, attrs) do
    menu_item
    |> cast(attrs, [:name, :description, :price, :available, :featured, :category_id])
    |> validate_required([:name, :price, :category_id])
    |> validate_number(:price, greater_than: 0)
    |> assoc_constraint(:category)
  end
end
