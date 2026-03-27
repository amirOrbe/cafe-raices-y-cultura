defmodule CRC.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Orders.OrderItem
  alias CRC.Accounts.User

  schema "orders" do
    field :customer_name, :string
    field :status, :string, default: "open"
    field :notes, :string

    belongs_to :user, User
    has_many :order_items, OrderItem

    timestamps(type: :utc_datetime)
  end

  @valid_statuses ~w(open sent ready closed)

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:customer_name, :status, :notes, :user_id])
    |> validate_required([:customer_name, :status])
    |> validate_inclusion(:status, @valid_statuses)
  end
end
