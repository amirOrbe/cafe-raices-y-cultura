defmodule CRC.Repo.Migrations.AddParkedFieldsToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      # Set when a waiter "parks" a still-open comanda so the customer can pay
      # later (another day). The order stays open, frees its table, and drops
      # out of the active board — it shows up in "Cuentas por cobrar" instead.
      add :parked_at, :utc_datetime
      add :parked_by_id, references(:users, on_delete: :nilify_all)
    end

    create index(:orders, [:parked_at])
  end
end
