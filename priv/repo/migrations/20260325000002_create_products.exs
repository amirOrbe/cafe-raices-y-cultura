defmodule CRC.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :name, :string, null: false
      add :category, :string, null: false
      add :net_cost, :decimal, precision: 10, scale: 2, null: false
      add :sale_price, :decimal, precision: 10, scale: 2
      add :stock_quantity, :decimal, precision: 10, scale: 3, null: false, default: 0
      add :min_stock, :decimal, precision: 10, scale: 3, default: 0
      add :unit, :string, null: false
      add :notes, :text
      add :active, :boolean, default: true, null: false
      add :supplier_id, references(:suppliers, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:products, [:category])
    create index(:products, [:active])
    create index(:products, [:supplier_id])
  end
end
