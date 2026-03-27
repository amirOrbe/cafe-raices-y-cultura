defmodule CRC.Repo.Migrations.AddCustomerNameToOrders do
  use Ecto.Migration

  def change do
    # Rename table_number -> customer_name (mesero names the tab by client)
    rename table(:orders), :table_number, to: :customer_name

    drop_if_exists index(:orders, [:table_number])
    create index(:orders, [:customer_name])

    alter table(:orders) do
      # Optional link to a registered user (future: self-service ordering)
      add :user_id, references(:users, on_delete: :nilify_all), null: true
    end
  end
end
