defmodule CRC.Repo.Migrations.CreateMenuItemOptionalExtras do
  use Ecto.Migration

  def change do
    create table(:menu_item_optional_extras) do
      add :menu_item_id, references(:menu_items, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :delete_all), null: false
      add :portion_quantity, :decimal, null: false
      add :sale_price, :decimal

      timestamps(type: :utc_datetime)
    end

    create unique_index(:menu_item_optional_extras, [:menu_item_id, :product_id])
    create index(:menu_item_optional_extras, [:menu_item_id])
  end
end
