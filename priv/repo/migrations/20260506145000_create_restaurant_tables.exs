defmodule CRC.Repo.Migrations.CreateRestaurantTables do
  use Ecto.Migration

  def change do
    create table(:restaurant_tables) do
      add :number, :integer, null: false
      add :label, :string
      add :capacity, :integer
      add :x_pct, :float, null: false, default: 50.0
      add :y_pct, :float, null: false, default: 50.0
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:restaurant_tables, [:number])
  end
end
