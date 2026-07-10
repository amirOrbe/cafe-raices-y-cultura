defmodule CRC.Inventory.StockAdjustment do
  @moduledoc """
  Records a manual change to a product's stock quantity.

  Reasons:
    caducidad     — product expired before use
    derrame       — liquid spilled / container broken
    robo          — theft or unexplained shrinkage
    ajuste_manual — periodic physical-count correction
    otro          — any other reason (explained in notes)

  quantity is negative for losses, positive for additions (e.g. a correction
  that adds stock back). The Inventory context applies the quantity delta to
  the product's stock_quantity in the same transaction.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Inventory.Product
  alias CRC.Accounts.User

  @valid_reasons ~w(compra caducidad derrame robo ajuste_manual otro)

  schema "stock_adjustments" do
    field :quantity, :decimal
    field :reason, :string
    field :notes, :string

    belongs_to :product, Product
    belongs_to :adjusted_by, User, foreign_key: :adjusted_by_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(adj, attrs) do
    adj
    |> cast(attrs, [:product_id, :quantity, :reason, :notes, :adjusted_by_id])
    |> validate_required([:product_id, :quantity, :reason])
    |> validate_inclusion(:reason, @valid_reasons, message: "no es una razón válida")
    |> validate_number(:quantity, not_equal_to: 0, message: "debe ser distinto de cero")
    |> assoc_constraint(:product)
  end
end
