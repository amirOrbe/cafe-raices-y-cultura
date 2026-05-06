defmodule CRC.Orders.Table do
  @moduledoc "A physical restaurant table that can be associated with orders."

  use Ecto.Schema
  import Ecto.Changeset

  schema "restaurant_tables" do
    field :number, :integer
    field :label, :string
    field :capacity, :integer
    field :x_pct, :float, default: 50.0
    field :y_pct, :float, default: 50.0
    field :is_active, :boolean, default: true

    has_many :orders, CRC.Orders.Order

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(table, attrs) do
    table
    |> cast(attrs, [:number, :label, :capacity, :x_pct, :y_pct, :is_active])
    |> validate_required([:number])
    |> validate_number(:number, greater_than: 0, message: "debe ser mayor a 0")
    |> validate_number(:capacity, greater_than: 0, message: "debe ser mayor a 0")
    |> unique_constraint(:number, message: "ya existe una mesa con ese número")
  end

  @doc "Changeset for updating only the floor-map position (drag-and-drop)."
  def position_changeset(table, attrs) do
    table
    |> cast(attrs, [:x_pct, :y_pct])
    |> validate_required([:x_pct, :y_pct])
  end
end
