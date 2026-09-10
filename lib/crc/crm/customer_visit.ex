defmodule CRC.CRM.CustomerVisit do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Accounts.User
  alias CRC.CRM.Customer
  alias CRC.Orders.Order

  schema "customer_visits" do
    field :recorded_at, :utc_datetime

    belongs_to :customer, Customer
    belongs_to :order, Order
    belongs_to :recorded_by, User, foreign_key: :recorded_by_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(visit, attrs) do
    visit
    |> cast(attrs, [:customer_id, :order_id, :recorded_at, :recorded_by_id])
    |> validate_required([:customer_id, :order_id, :recorded_at])
    |> assoc_constraint(:customer)
    |> assoc_constraint(:order)
    |> unique_constraint(:order_id, message: "esta comanda ya cuenta como visita")
  end
end
