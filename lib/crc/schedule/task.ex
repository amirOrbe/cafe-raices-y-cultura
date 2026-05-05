defmodule CRC.Schedule.Task do
  use Ecto.Schema
  import Ecto.Changeset

  schema "schedule_tasks" do
    field :name, :string
    field :position, :integer, default: 0

    belongs_to :area, CRC.Schedule.Area
    has_many :assignments, CRC.Schedule.Assignment

    timestamps()
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:name, :position, :area_id])
    |> validate_required([:name, :area_id])
    |> assoc_constraint(:area)
  end
end
