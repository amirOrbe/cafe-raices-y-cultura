defmodule CRC.Catalog.MenuItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Catalog.{Category, MenuItemIngredient}

  @destinations ~w(cocina barra)

  def destinations, do: @destinations

  schema "menu_items" do
    field :name, :string
    field :description, :string
    field :price, :decimal
    field :destination, :string, default: "cocina"
    field :available, :boolean, default: true
    field :featured, :boolean, default: false
    field :image_url, :string

    belongs_to :category, Category
    has_many :menu_item_ingredients, MenuItemIngredient

    timestamps(type: :utc_datetime)
  end

  def changeset(menu_item, attrs) do
    menu_item
    |> cast(attrs, [:name, :description, :price, :destination, :available, :featured, :category_id, :image_url])
    |> update_change(:name, &CRC.Utils.title_case/1)
    |> validate_required([:name, :price, :destination, :category_id])
    |> validate_inclusion(:destination, @destinations, message: "debe ser cocina o barra")
    |> validate_number(:price, greater_than: 0)
    |> assoc_constraint(:category)
  end
end
