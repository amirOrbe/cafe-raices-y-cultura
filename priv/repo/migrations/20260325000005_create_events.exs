defmodule CRC.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :title, :string, null: false
      add :description, :text
      add :event_type_id, references(:event_types, on_delete: :nilify_all)
      add :event_date, :date, null: false
      add :start_time, :time_usec, null: false
      add :end_time, :time_usec, null: false
      add :tags, {:array, :string}, default: []
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:events, [:event_date])
    create index(:events, [:active])
    create index(:events, [:event_type_id])
  end
end
