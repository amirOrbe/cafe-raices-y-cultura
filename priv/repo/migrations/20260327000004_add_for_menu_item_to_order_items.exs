defmodule CRC.Repo.Migrations.AddForMenuItemToOrderItems do
  use Ecto.Migration

  def change do
    alter table(:order_items) do
      # Links an ingredient extra to the specific dish it was added for.
      # Example: "Queso gouda extra" → references "Sandwich Clásico".
      add :for_menu_item_id, references(:menu_items, on_delete: :nilify_all), null: true
    end

    create index(:order_items, [:for_menu_item_id])
  end
end
