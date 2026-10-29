defmodule CRC.Repo.Migrations.OneActiveOrderPerTable do
  use Ecto.Migration

  # Two waiters tapping "Abrir mesa" on the same free table at the same time
  # used to create two active comandas for it, and the floor map (one order
  # per table) silently hid one of them. Parked orders drop their table_id,
  # so they never count here.
  def change do
    create unique_index(:orders, [:table_id],
             name: :orders_one_active_per_table_index,
             where:
               "table_id IS NOT NULL AND parked_at IS NULL AND status IN ('open', 'sent', 'ready')"
           )
  end
end
