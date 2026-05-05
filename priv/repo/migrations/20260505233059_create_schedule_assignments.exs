defmodule CRC.Repo.Migrations.CreateScheduleAssignments59 do
  use Ecto.Migration

  def change do
    create table(:schedule_assignments) do
      # day_of_week: 0 = Monday … 6 = Sunday
      add :day_of_week, :integer, null: false
      # The Monday of the week this assignment belongs to
      add :week_start_date, :date, null: false
      add :task_id, references(:schedule_tasks, on_delete: :delete_all), null: false
      # Nullable: unassigned slot
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create index(:schedule_assignments, [:task_id])
    create index(:schedule_assignments, [:week_start_date])
    create index(:schedule_assignments, [:user_id])
    # Only one assignment per task per day per week
    create unique_index(:schedule_assignments, [:task_id, :day_of_week, :week_start_date])
  end
end
