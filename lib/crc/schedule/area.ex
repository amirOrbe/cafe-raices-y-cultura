defmodule CRC.Schedule.Area do
  use Ecto.Schema
  import Ecto.Changeset

  schema "schedule_areas" do
    field :name, :string
    # color key: "purple" | "blue" | "green" | "orange" | "pink"
    field :color, :string, default: "purple"
    field :position, :integer, default: 0

    has_many :tasks, CRC.Schedule.Task, preload_order: [asc: :position]

    timestamps()
  end

  @doc false
  def changeset(area, attrs) do
    area
    |> cast(attrs, [:name, :color, :position])
    |> validate_required([:name])
    |> validate_inclusion(:color, ~w(purple blue green orange pink))
  end
end
