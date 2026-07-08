defmodule CRC.Loyalty.LoyaltyVisit do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Accounts.User

  @type t :: %__MODULE__{}

  schema "loyalty_visits" do
    belongs_to :user, User
    belongs_to :recorded_by, User
    belongs_to :order, CRC.Orders.Order

    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(visit, attrs) do
    visit
    |> cast(attrs, [:user_id, :recorded_by_id, :order_id, :notes])
    |> validate_required([:user_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:recorded_by_id)
    |> foreign_key_constraint(:order_id)
  end
end
