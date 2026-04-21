defmodule CRC.Repo.Migrations.CreateWorkSchedules do
  use Ecto.Migration

  def change do
    create table(:work_schedules) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # ISO 8601: 1 = Monday … 7 = Sunday (matches Date.day_of_week/1)
      add :day_of_week, :integer, null: false
      add :start_time, :time, null: false
      add :end_time, :time, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:work_schedules, [:user_id])
    create unique_index(:work_schedules, [:user_id, :day_of_week])
  end
end
