defmodule CRC.Repo.Migrations.CreatePackages do
  use Ecto.Migration

  def change do
    create table(:packages) do
      add :name, :string, null: false
      add :description, :string
      add :price, :decimal, precision: 10, scale: 2, null: false
      add :active, :boolean, default: true, null: false
      add :featured, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:packages, [:name])

    create table(:package_items) do
      add :package_id, references(:packages, on_delete: :delete_all), null: false
      add :menu_item_id, references(:menu_items, on_delete: :delete_all), null: false
      add :quantity, :integer, default: 1, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:package_items, [:package_id, :menu_item_id])
    create index(:package_items, [:package_id])
  end
end
