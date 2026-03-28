defmodule CRC.Repo.Migrations.AddPaymentFieldsToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :payment_method, :string, null: true
      add :amount_paid, :decimal, precision: 10, scale: 2, null: true
      add :total, :decimal, precision: 10, scale: 2, null: true
    end

    create index(:orders, [:status, :inserted_at])
    create index(:orders, [:payment_method])
  end
end
