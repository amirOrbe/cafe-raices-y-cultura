defmodule CRC.Repo.Migrations.CreateScheduleTasks do
  use Ecto.Migration

  def change do
    create table(:schedule_tasks) do
      add :name, :string, null: false
      add :position, :integer, default: 0, null: false
      add :area_id, references(:schedule_areas, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:schedule_tasks, [:area_id])
    create index(:schedule_tasks, [:position])
  end
end
