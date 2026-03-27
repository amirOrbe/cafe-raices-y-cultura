defmodule CRC.Orders.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Orders.Order
  alias CRC.Catalog.MenuItem

  schema "order_items" do
    field :quantity, :integer, default: 1
    field :notes, :string
    field :status, :string, default: "pending"

    belongs_to :order, Order
    belongs_to :menu_item, MenuItem

    timestamps(type: :utc_datetime)
  end

  # pending = added but not yet sent to station
  # sent    = dispatched to cocina/barra, being prepared
  # ready   = prepared and ready to serve
  @valid_statuses ~w(pending sent ready)

  @doc false
  def changeset(order_item, attrs) do
    order_item
    |> cast(attrs, [:quantity, :notes, :status, :order_id, :menu_item_id])
    |> validate_required([:quantity, :status, :order_id, :menu_item_id])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_inclusion(:status, @valid_statuses)
    |> assoc_constraint(:order)
    |> assoc_constraint(:menu_item)
  end
end
