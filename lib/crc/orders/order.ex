defmodule CRC.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Orders.{OrderItem, Table}
  alias CRC.Accounts.User
  alias CRC.Settings.Discount

  schema "orders" do
    field :customer_name, :string
    field :status, :string, default: "open"
    field :notes, :string
    # Payment fields — populated only when the order is closed
    field :payment_method, :string
    field :amount_paid, :decimal
    field :total, :decimal
    # Timing — set when the order is closed
    field :closed_at, :utc_datetime
    # True for orders entered retroactively (e.g., paper tickets during power outage).
    # These count toward financial totals but are excluded from rendimiento metrics.
    field :manual_entry, :boolean, default: false
    # Unique token used to generate a public customer-facing bill URL (/cuenta/:token).
    field :bill_token, :string
    # Order type: "dine_in" (para comer aquí, default) or "takeout" (para llevar)
    field :order_type, :string, default: "dine_in"
    # True for grupo de comensales — an order not tied to a physical table, explicitly created as a group
    field :is_group, :boolean, default: false
    # Discount applied at close time (denormalized for historical accuracy)
    field :discount_percentage, :integer, default: 0

    # Waiter who opened this order (user_id FK)
    belongs_to :user, User
    # Staff member who closed/charged this order
    belongs_to :closed_by, User, foreign_key: :closed_by_id
    # Physical table this order belongs to (nullable for backward-compat)
    belongs_to :table, Table
    # Discount applied at close time (nullable — nil means no discount)
    belongs_to :discount, Discount
    has_many :order_items, OrderItem

    timestamps(type: :utc_datetime)
  end

  @valid_statuses ~w(open sent ready closed)
  @valid_payment_methods ~w(efectivo tarjeta transferencia)
  @valid_order_types ~w(dine_in takeout)

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:customer_name, :status, :notes, :user_id, :table_id, :bill_token, :order_type, :is_group])
    |> validate_required([:customer_name, :status])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:order_type, @valid_order_types)
  end

  @doc """
  Changeset for creating a manual (retroactive) order.
  Creates the order already closed, skipping the normal workflow.
  """
  def manual_changeset(order, attrs) do
    order
    |> cast(attrs, [
      :customer_name,
      :notes,
      :payment_method,
      :amount_paid,
      :total,
      :closed_at,
      :closed_by_id,
      :manual_entry,
      :discount_percentage,
      :discount_id
    ])
    |> validate_required([:customer_name, :payment_method, :total, :closed_at])
    |> put_change(:status, "closed")
    |> put_change(:manual_entry, true)
    |> validate_inclusion(:payment_method, @valid_payment_methods,
      message: "debe ser efectivo, tarjeta o transferencia"
    )
    |> validate_cash_amount()
  end

  @doc """
  Changeset used exclusively when closing an order.
  Requires payment_method and total. amount_paid is required for cash.
  """
  def close_changeset(order, attrs) do
    order
    |> cast(attrs, [
      :status,
      :payment_method,
      :amount_paid,
      :total,
      :closed_at,
      :closed_by_id,
      :discount_id,
      :discount_percentage
    ])
    |> validate_required([:status, :payment_method, :total])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:payment_method, @valid_payment_methods,
      message: "debe ser efectivo, tarjeta o transferencia"
    )
    |> validate_cash_amount()
  end

  defp validate_cash_amount(changeset) do
    if get_field(changeset, :payment_method) == "efectivo" and
         is_nil(get_field(changeset, :amount_paid)) do
      add_error(changeset, :amount_paid, "es requerido para pagos en efectivo")
    else
      changeset
    end
  end
end
