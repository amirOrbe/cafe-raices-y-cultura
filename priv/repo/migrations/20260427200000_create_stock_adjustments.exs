defmodule CRC.Repo.Migrations.CreateStockAdjustments do
  use Ecto.Migration

  def change do
    create table(:stock_adjustments) do
      add :product_id,     references(:products, on_delete: :restrict), null: false
      add :quantity,       :decimal, null: false   # negative = loss, positive = addition
      add :reason,         :string,  null: false   # caducidad|derrame|robo|ajuste_manual|otro
      add :notes,          :string
      add :adjusted_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:stock_adjustments, [:product_id])
    create index(:stock_adjustments, [:adjusted_by_id])
    create index(:stock_adjustments, [:inserted_at])
  end
end
