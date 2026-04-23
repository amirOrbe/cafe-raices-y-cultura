defmodule CRC.Repo.Migrations.CreateCafeHours do
  use Ecto.Migration

  def change do
    create table(:cafe_hours) do
      add :day_of_week, :integer, null: false
      add :opening_time, :time, null: false
      add :closing_time, :time, null: false
      add :is_closed, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cafe_hours, [:day_of_week])
  end
end
