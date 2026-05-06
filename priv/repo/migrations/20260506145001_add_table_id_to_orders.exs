defmodule CRC.Repo.Migrations.AddTableIdToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :table_id, references(:restaurant_tables, on_delete: :nilify_all)
    end

    create index(:orders, [:table_id])
  end
end
