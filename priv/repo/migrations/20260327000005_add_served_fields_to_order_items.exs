defmodule CRC.Repo.Migrations.AddServedFieldsToOrderItems do
  use Ecto.Migration

  def change do
    alter table(:order_items) do
      add :served_at, :utc_datetime
      add :served_by_id, references(:users, on_delete: :nilify_all)
    end

    create index(:order_items, [:served_by_id])
  end
end
