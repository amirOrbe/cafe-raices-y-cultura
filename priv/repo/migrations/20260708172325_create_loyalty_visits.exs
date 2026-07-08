defmodule CRC.Repo.Migrations.CreateLoyaltyVisits do
  use Ecto.Migration

  def change do
    create table(:loyalty_visits) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :recorded_by_id, references(:users, on_delete: :nilify_all)
      add :order_id, references(:orders, on_delete: :nilify_all)
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:loyalty_visits, [:user_id])
    create index(:loyalty_visits, [:recorded_by_id])
  end
end
