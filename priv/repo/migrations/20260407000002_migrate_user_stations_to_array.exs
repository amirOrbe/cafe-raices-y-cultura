defmodule CRC.Repo.Migrations.MigrateUserStationsToArray do
  use Ecto.Migration

  def up do
    # 1. Add the new array column with a safe default
    alter table(:users) do
      add :stations, {:array, :string}, null: false, default: []
    end

    # 2. Migrate existing single-station data into the array
    execute("""
    UPDATE users
    SET stations = ARRAY[station]
    WHERE station IS NOT NULL AND station <> ''
    """)

    # 3. Drop the old single-station column (index drops automatically)
    alter table(:users) do
      remove :station
    end
  end

  def down do
    alter table(:users) do
      add :station, :string
    end

    execute("""
    UPDATE users
    SET station = stations[1]
    WHERE array_length(stations, 1) > 0
    """)

    alter table(:users) do
      remove :stations
    end
  end
end
