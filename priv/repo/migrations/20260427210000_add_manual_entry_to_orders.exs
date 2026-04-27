defmodule CRC.Repo.Migrations.AddManualEntryToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :manual_entry, :boolean, default: false, null: false
    end

    create index(:orders, [:manual_entry])
  end
end
