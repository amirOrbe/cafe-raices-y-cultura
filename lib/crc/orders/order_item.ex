defmodule CRC.Orders.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Orders.{Order, OrderItemExclusion}
  alias CRC.Catalog.MenuItem
  alias CRC.Inventory.Product

  schema "order_items" do
    field :quantity, :integer, default: 1
    field :notes, :string
    field :status, :string, default: "pending"
    # For ingredient extras: the recipe portion size (e.g. 120.000 grams per unit ordered).
    # Nil for regular menu-item orders — stock is deducted via the menu item's recipe.
    field :portion_quantity, :decimal
    # Timing fields — set automatically on status transitions
    field :sent_at, :utc_datetime
    field :ready_at, :utc_datetime
    field :served_at, :utc_datetime

    belongs_to :order, Order
    belongs_to :menu_item, MenuItem
    # Nullable: used for ingredient extras added directly (no menu item)
    belongs_to :product, Product
    # Kitchen/barra staff who marked this item ready (nullable)
    belongs_to :marked_ready_by, CRC.Accounts.User, foreign_key: :marked_ready_by_id
    # Waiter who delivered this item to the table (nullable)
    belongs_to :served_by, CRC.Accounts.User, foreign_key: :served_by_id
    # For ingredient extras: the dish this extra was added for, e.g. "Queso gouda → Sandwich Clásico"
    belongs_to :for_menu_item, CRC.Catalog.MenuItem, foreign_key: :for_menu_item_id
    # Ingredients explicitly excluded by the customer (e.g. "sin jitomate")
    has_many :exclusions, OrderItemExclusion

    timestamps(type: :utc_datetime)
  end

  # pending          = added but not yet sent to station
  # sent             = dispatched to cocina/barra, being prepared
  # ready            = prepared and waiting to be picked up by waiter
  # served           = picked up and delivered to the table
  # cancelled        = removed before preparation; stock was restored
  # cancelled_waste  = removed after preparation; stock was NOT restored (food was made)
  @valid_statuses ~w(pending sent ready served cancelled cancelled_waste)

  @doc false
  def changeset(order_item, attrs) do
    order_item
    |> cast(attrs, [:quantity, :notes, :status, :order_id, :menu_item_id, :product_id, :portion_quantity, :sent_at, :ready_at, :served_at, :marked_ready_by_id, :served_by_id, :for_menu_item_id])
    |> validate_required([:quantity, :status, :order_id])
    |> validate_item_source()
    |> validate_number(:quantity, greater_than: 0)
    |> validate_inclusion(:status, @valid_statuses)
    |> assoc_constraint(:order)
    |> assoc_constraint(:menu_item)
    |> assoc_constraint(:product)
  end

  # An order item must reference either a menu_item OR a product (ingredient extra), not neither.
  defp validate_item_source(changeset) do
    menu_item_id = get_field(changeset, :menu_item_id)
    product_id = get_field(changeset, :product_id)

    if is_nil(menu_item_id) and is_nil(product_id) do
      add_error(changeset, :base, "debe referenciar un platillo o un extra de ingrediente")
    else
      changeset
    end
  end
end
