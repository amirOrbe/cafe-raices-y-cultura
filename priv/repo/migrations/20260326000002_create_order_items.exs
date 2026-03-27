defmodule CRC.Repo.Migrations.CreateOrderItems do
  use Ecto.Migration

  def change do
    create table(:order_items) do
      add :order_id, references(:orders, on_delete: :delete_all), null: false
      add :menu_item_id, references(:menu_items, on_delete: :restrict), null: false
      add :quantity, :integer, null: false, default: 1
      add :notes, :text
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create index(:order_items, [:order_id])
    create index(:order_items, [:menu_item_id])
  end
end
