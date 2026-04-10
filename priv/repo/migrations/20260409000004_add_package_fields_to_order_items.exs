defmodule CRC.Repo.Migrations.AddPackageFieldsToOrderItems do
  use Ecto.Migration

  def change do
    alter table(:order_items) do
      add :package_id, references(:packages, on_delete: :nilify_all)
      add :unit_price, :decimal, precision: 10, scale: 2
    end

    create index(:order_items, [:package_id])
  end
end
