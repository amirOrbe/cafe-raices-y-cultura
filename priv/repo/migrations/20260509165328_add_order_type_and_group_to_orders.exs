defmodule CRC.Repo.Migrations.AddOrderTypeAndGroupToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      # "dine_in" = para comer aquí (default), "takeout" = para llevar
      add :order_type, :string, default: "dine_in", null: false
      # true for grupo de comensales (no assigned table, explicitly created as a group)
      add :is_group, :boolean, default: false, null: false
    end
  end
end
