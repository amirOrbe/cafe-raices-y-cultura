defmodule CRC.Repo.Migrations.CreateScheduleAreas do
  use Ecto.Migration

  def change do
    create table(:schedule_areas) do
      add :name, :string, null: false
      add :color, :string, default: "purple"
      add :position, :integer, default: 0, null: false

      timestamps()
    end

    create index(:schedule_areas, [:position])
  end
end
