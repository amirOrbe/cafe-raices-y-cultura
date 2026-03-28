defmodule CRC.Repo.Migrations.AddProductExtrasToOrderItems do
  use Ecto.Migration

  def up do
    # Make menu_item_id nullable to allow product-only extras
    execute "ALTER TABLE order_items ALTER COLUMN menu_item_id DROP NOT NULL"

    alter table(:order_items) do
      add :product_id, references(:products, on_delete: :nilify_all)
    end

    create index(:order_items, [:product_id])
  end

  def down do
    drop index(:order_items, [:product_id])

    alter table(:order_items) do
      remove :product_id
    end

    execute "ALTER TABLE order_items ALTER COLUMN menu_item_id SET NOT NULL"
  end
end
