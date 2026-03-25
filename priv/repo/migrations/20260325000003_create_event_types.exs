defmodule CRC.Repo.Migrations.CreateEventTypes do
  use Ecto.Migration

  def change do
    create table(:event_types) do
      add :name, :string, null: false
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:event_types, [:active])
  end
end
