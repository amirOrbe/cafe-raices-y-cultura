defmodule CRC.Repo.Migrations.AddBillTokenToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :bill_token, :string, null: true
    end

    create unique_index(:orders, [:bill_token])
  end
end
