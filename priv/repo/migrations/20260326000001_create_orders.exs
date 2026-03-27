defmodule CRC.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders) do
      add :table_number, :string, null: false
      add :status, :string, null: false, default: "open"
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:orders, [:status])
    create index(:orders, [:table_number])
  end
end
