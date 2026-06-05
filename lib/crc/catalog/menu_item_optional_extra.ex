defmodule CRC.Catalog.MenuItemOptionalExtra do
  @moduledoc "Optional add-on product for a menu item (e.g. leche on an infusion)."

  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Catalog.MenuItem
  alias CRC.Inventory.Product

  schema "menu_item_optional_extras" do
    belongs_to :menu_item, MenuItem
    belongs_to :product, Product

    # Amount of product used per unit ordered (for stock deduction)
    field :portion_quantity, :decimal
    # nil = free, >0 = charge this amount when added to a comanda
    field :sale_price, :decimal

    timestamps(type: :utc_datetime)
  end

  def changeset(extra, attrs) do
    extra
    |> cast(attrs, [:menu_item_id, :product_id, :portion_quantity, :sale_price])
    |> validate_required([:menu_item_id, :product_id, :portion_quantity])
    |> validate_number(:portion_quantity, greater_than: 0)
    |> validate_number(:sale_price, greater_than_or_equal_to: 0)
    |> unique_constraint([:menu_item_id, :product_id],
      message: "este extra ya está configurado para el platillo"
    )
  end
end
