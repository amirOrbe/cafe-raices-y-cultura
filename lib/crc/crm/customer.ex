defmodule CRC.CRM.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  alias CRC.Accounts.User
  alias CRC.CRM.{CustomerVisit, LoyaltyRedemption}
  alias CRC.Orders.Order

  schema "customers" do
    field :name, :string
    field :phone, :string
    field :email, :string
    field :birthday, :date
    field :notes, :string
    field :active, :boolean, default: true

    belongs_to :created_by, User, foreign_key: :created_by_id
    has_many :visits, CustomerVisit
    has_many :redemptions, LoyaltyRedemption
    has_many :orders, Order

    timestamps(type: :utc_datetime)
  end

  @email_format ~r/^[^\s]+@[^\s]+\.[^\s]+$/

  @doc false
  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [:name, :phone, :email, :birthday, :notes, :active, :created_by_id])
    |> validate_required([:name, :phone], message: "no puede estar en blanco")
    |> update_change(:name, &CRC.Utils.title_case/1)
    |> update_change(:email, &normalize_email/1)
    |> validate_format(:email, @email_format, message: "tiene formato inválido")
  end

  defp normalize_email(nil), do: nil
  defp normalize_email(""), do: nil

  defp normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()
end
