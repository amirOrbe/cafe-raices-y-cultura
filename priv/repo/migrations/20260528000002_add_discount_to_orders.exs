defmodule CRC.Repo.Migrations.AddDiscountToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :discount_id, references(:discounts, on_delete: :nilify_all)
      add :discount_percentage, :integer, default: 0, null: false
    end
  end
end
