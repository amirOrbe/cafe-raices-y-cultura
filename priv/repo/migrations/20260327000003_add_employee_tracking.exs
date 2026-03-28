defmodule CRC.Repo.Migrations.AddEmployeeTracking do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :closed_by_id, references(:users, on_delete: :nilify_all), null: true
    end

    alter table(:order_items) do
      add :marked_ready_by_id, references(:users, on_delete: :nilify_all), null: true
    end

    create index(:orders, [:user_id])
    create index(:orders, [:closed_by_id])
    create index(:order_items, [:marked_ready_by_id])
  end
end
