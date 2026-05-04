defmodule CRC.Catalog.MenuItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Catalog.{Category, MenuItemIngredient}

  @destinations ~w(cocina barra)
  # Only relevant when destination == "barra". nil means unclassified.
  @barra_types ~w(fria caliente)

  def destinations, do: @destinations
  def barra_types, do: @barra_types

  schema "menu_items" do
    field :name, :string
    field :description, :string
    field :price, :decimal
    field :destination, :string, default: "cocina"
    field :available, :boolean, default: true
    field :featured, :boolean, default: false
    field :image_url, :string
    # Subcategory for bar items: "fria" | "caliente" | nil (unclassified)
    field :barra_type, :string

    belongs_to :category, Category
    has_many :menu_item_ingredients, MenuItemIngredient

    timestamps(type: :utc_datetime)
  end

  def changeset(menu_item, attrs) do
    menu_item
    |> cast(attrs, [
      :name,
      :description,
      :price,
      :destination,
      :available,
      :featured,
      :category_id,
      :image_url,
      :barra_type
    ])
    |> update_change(:name, &CRC.Utils.title_case/1)
    |> validate_required([:name, :price, :destination, :category_id])
    |> validate_inclusion(:destination, @destinations, message: "debe ser cocina o barra")
    |> validate_inclusion(:barra_type, @barra_types ++ [nil],
      message: "debe ser fria o caliente"
    )
    |> clear_barra_type_for_cocina()
    |> validate_number(:price, greater_than: 0)
    |> assoc_constraint(:category)
  end

  # If destination is cocina, barra_type is irrelevant — clear it to keep data clean.
  defp clear_barra_type_for_cocina(changeset) do
    if get_field(changeset, :destination) == "cocina" do
      put_change(changeset, :barra_type, nil)
    else
      changeset
    end
  end
end
