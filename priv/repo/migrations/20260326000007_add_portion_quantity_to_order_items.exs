defmodule CRC.Repo.Migrations.AddPortionQuantityToOrderItems do
  use Ecto.Migration

  def change do
    alter table(:order_items) do
      # Stores the recipe portion size for ingredient extras (e.g. 120.0 grams).
      # Nil for regular menu-item-based order items (stock is deducted via recipe).
      add :portion_quantity, :decimal, precision: 10, scale: 3
    end
  end
end
