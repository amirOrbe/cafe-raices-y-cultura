defmodule CRC.Repo.Migrations.AddVariantIdToOrderItems do
  use Ecto.Migration

  def change do
    alter table(:order_items) do
      add :variant_id, references(:product_variants, on_delete: :restrict), null: true
    end

    create index(:order_items, [:variant_id])
  end
end
