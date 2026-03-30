defmodule CRC.Repo.Migrations.CreateOrderItemExclusions do
  use Ecto.Migration

  @moduledoc """
  Stores ingredient exclusions per order item — e.g. "sin jitomate" for a sandwich.
  When an ingredient is excluded:
    - It is NOT deducted from inventory at send_to_kitchen time.
    - The kitchen/barra display shows it as a "sin X" badge.
    - The financial COGS calculation also excludes its cost.
  """

  def change do
    create table(:order_item_exclusions) do
      add :order_item_id, references(:order_items, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    # Prevent duplicates; fast lookup by order_item
    create unique_index(:order_item_exclusions, [:order_item_id, :product_id])
    create index(:order_item_exclusions, [:order_item_id])
  end
end
