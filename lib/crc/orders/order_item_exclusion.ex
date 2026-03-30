defmodule CRC.Orders.OrderItemExclusion do
  @moduledoc """
  Records a single ingredient exclusion on an order item.

  When a customer requests "sin jitomate" on a sandwich, a record is created
  linking that order_item → jitomate (product). At send_to_kitchen time the
  deduction logic skips excluded ingredients so stock stays correct.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Orders.OrderItem
  alias CRC.Inventory.Product

  schema "order_item_exclusions" do
    belongs_to :order_item, OrderItem
    belongs_to :product, Product

    timestamps(type: :utc_datetime)
  end

  def changeset(exclusion, attrs) do
    exclusion
    |> cast(attrs, [:order_item_id, :product_id])
    |> validate_required([:order_item_id, :product_id])
    |> unique_constraint([:order_item_id, :product_id],
      message: "este ingrediente ya está excluido"
    )
  end
end
