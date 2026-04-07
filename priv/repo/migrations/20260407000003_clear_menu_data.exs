defmodule CRC.Repo.Migrations.ClearMenuData do
  use Ecto.Migration

  def up do
    execute "DELETE FROM menu_item_ingredients"
    execute "DELETE FROM order_items WHERE menu_item_id IS NOT NULL"
    execute "DELETE FROM menu_items"
    execute "DELETE FROM categories"
  end

  def down do
    # Irreversible — data cannot be restored from a migration rollback
    :ok
  end
end
