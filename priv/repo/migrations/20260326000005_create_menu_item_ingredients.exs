defmodule CRC.Repo.Migrations.CreateMenuItemIngredients do
  use Ecto.Migration

  def change do
    create table(:menu_item_ingredients) do
      add :menu_item_id, references(:menu_items, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :delete_all), null: false
      add :quantity, :decimal, precision: 10, scale: 3, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:menu_item_ingredients, [:menu_item_id])
    create index(:menu_item_ingredients, [:product_id])
    create unique_index(:menu_item_ingredients, [:menu_item_id, :product_id])
  end
end
