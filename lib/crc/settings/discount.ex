defmodule CRC.Settings.Discount do
  use Ecto.Schema
  import Ecto.Changeset

  schema "discounts" do
    field :name, :string
    field :percentage, :integer
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(discount, attrs) do
    discount
    |> cast(attrs, [:name, :percentage, :active])
    |> validate_required([:name, :percentage])
    |> validate_number(:percentage, greater_than: 0, less_than_or_equal_to: 100,
        message: "debe ser entre 1 y 100"
      )
  end
end
