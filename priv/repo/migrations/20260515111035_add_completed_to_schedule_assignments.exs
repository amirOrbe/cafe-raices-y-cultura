defmodule CRC.Repo.Migrations.AddCompletedToScheduleAssignments do
  use Ecto.Migration

  def change do
    alter table(:schedule_assignments) do
      add :completed, :boolean, default: false, null: false
      add :completed_at, :utc_datetime
    end
  end
end
