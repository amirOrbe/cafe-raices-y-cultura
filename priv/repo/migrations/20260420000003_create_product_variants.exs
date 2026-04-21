defmodule CRC.Repo.Migrations.CreateProductVariants do
  use Ecto.Migration

  def change do
    create table(:product_variants) do
      add :product_id, references(:products, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :extra_charge, :decimal, precision: 10, scale: 2, null: false, default: 0
      add :stock_quantity, :decimal, precision: 10, scale: 3, null: false, default: 0
      add :min_stock, :decimal, precision: 10, scale: 3, null: false, default: 0
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:product_variants, [:product_id])
    create index(:product_variants, [:active])
    create unique_index(:product_variants, [:product_id, :name])
  end
end
