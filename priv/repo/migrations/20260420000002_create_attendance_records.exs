defmodule CRC.Repo.Migrations.CreateAttendanceRecords do
  use Ecto.Migration

  def change do
    create table(:attendance_records) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :date, :date, null: false

      # Snapshot of scheduled times at the moment the record is created
      add :scheduled_start, :time
      add :scheduled_end, :time

      # Actual clock-in / clock-out timestamps (UTC)
      add :clocked_in_at, :utc_datetime
      add :clocked_out_at, :utc_datetime

      # Coordinates at clock-in (nil when registered manually)
      add :latitude, :float
      add :longitude, :float

      # true when an admin registers the time on behalf of the employee
      add :manual_entry, :boolean, default: false, null: false

      # on_time | late | absent
      add :status, :string, default: "absent", null: false

      timestamps(type: :utc_datetime)
    end

    create index(:attendance_records, [:user_id])
    create index(:attendance_records, [:date])
    create unique_index(:attendance_records, [:user_id, :date])
  end
end
