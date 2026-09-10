defmodule CRC.CRM.LoyaltyRedemption do
  @moduledoc """
  Evento de lealtad para un cliente: una recompensa que ganó y (opcionalmente)
  redimió. Guarda snapshots del beneficio (`benefit_snapshot`,
  `visits_required_snapshot`) para que editar o desactivar la config
  (`LoyaltyReward`) no altere lo que el cliente ya ganó.

  `kind`:
    * `"visits"`   — `cycle` numera el bloque de la tarjeta perforada (1, 2, 3…)
    * `"birthday"` — `birthday_year` es el año en que se otorgó

  `status`: `"earned"` → `"redeemed"` (al aplicarse en una comanda) o `"void"`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Accounts.User
  alias CRC.CRM.{Customer, LoyaltyReward}
  alias CRC.Orders.Order

  @statuses ~w(earned redeemed void)

  schema "loyalty_redemptions" do
    field :kind, :string
    field :benefit_snapshot, :string
    field :visits_required_snapshot, :integer
    field :cycle, :integer, default: 1
    field :earned_at, :utc_datetime
    field :earned_at_visit_count, :integer
    field :status, :string, default: "earned"
    field :redeemed_at, :utc_datetime
    field :birthday_year, :integer

    belongs_to :customer, Customer
    belongs_to :loyalty_reward, LoyaltyReward
    belongs_to :redeemed_by, User, foreign_key: :redeemed_by_id
    belongs_to :order, Order

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(redemption, attrs) do
    redemption
    |> cast(attrs, [
      :customer_id,
      :loyalty_reward_id,
      :kind,
      :benefit_snapshot,
      :visits_required_snapshot,
      :cycle,
      :earned_at,
      :earned_at_visit_count,
      :status,
      :redeemed_at,
      :redeemed_by_id,
      :order_id,
      :birthday_year
    ])
    |> validate_required([:customer_id, :kind, :benefit_snapshot, :cycle, :earned_at, :status])
    |> validate_inclusion(:kind, ~w(visits birthday))
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:customer)
    |> assoc_constraint(:loyalty_reward)
    |> assoc_constraint(:order)
    |> unique_constraint([:customer_id, :loyalty_reward_id, :cycle],
      name: :loyalty_redemptions_unique_visits_cycle_index,
      message: "esta recompensa ya fue otorgada"
    )
    |> unique_constraint([:customer_id, :birthday_year],
      name: :loyalty_redemptions_unique_birthday_year_index,
      message: "el beneficio de cumpleaños de este año ya fue otorgado"
    )
  end

  @doc "Changeset para marcar la recompensa como redimida en una comanda."
  def redeem_changeset(redemption, attrs) do
    redemption
    |> cast(attrs, [:status, :redeemed_at, :redeemed_by_id, :order_id])
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:order)
  end
end
