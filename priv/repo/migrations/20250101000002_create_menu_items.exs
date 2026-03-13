defmodule CRC.Repo.Migrations.CreateMenuItems do
  use Ecto.Migration

  def change do
    create table(:menu_items) do
      add :category_id, references(:categories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :price, :decimal, precision: 8, scale: 2, null: false
      add :image_url, :string
      add :available, :boolean, default: true, null: false
      add :featured, :boolean, default: false, null: false
      add :position, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:menu_items, [:category_id])
    create index(:menu_items, [:available])
    create index(:menu_items, [:featured])
  end
end
