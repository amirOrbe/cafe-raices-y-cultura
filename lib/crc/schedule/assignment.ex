defmodule CRC.Schedule.Assignment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "schedule_assignments" do
    # 0 = Monday … 6 = Sunday
    field :day_of_week, :integer
    field :week_start_date, :date

    belongs_to :task, CRC.Schedule.Task
    belongs_to :user, CRC.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [:day_of_week, :week_start_date, :task_id, :user_id])
    |> validate_required([:day_of_week, :week_start_date, :task_id])
    |> validate_inclusion(:day_of_week, 0..6)
    |> assoc_constraint(:task)
    |> assoc_constraint(:user)
    |> unique_constraint([:task_id, :day_of_week, :week_start_date])
  end
end
