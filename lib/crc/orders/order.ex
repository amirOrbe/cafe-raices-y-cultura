defmodule CRC.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Orders.OrderItem
  alias CRC.Accounts.User

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

    # Waiter who opened this order (user_id FK)
    belongs_to :user, User
    # Staff member who closed/charged this order
    belongs_to :closed_by, User, foreign_key: :closed_by_id
    has_many :order_items, OrderItem

    timestamps(type: :utc_datetime)
  end

  @valid_statuses ~w(open sent ready closed)
  @valid_payment_methods ~w(efectivo tarjeta transferencia)

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:customer_name, :status, :notes, :user_id])
    |> validate_required([:customer_name, :status])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc """
  Changeset used exclusively when closing an order.
  Requires payment_method and total. amount_paid is required for cash.
  """
  def close_changeset(order, attrs) do
    order
    |> cast(attrs, [:status, :payment_method, :amount_paid, :total, :closed_at, :closed_by_id])
    |> validate_required([:status, :payment_method, :total])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:payment_method, @valid_payment_methods,
        message: "debe ser efectivo, tarjeta o transferencia")
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
