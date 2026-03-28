defmodule CRC.Repo.Migrations.AddTimingFields do
  use Ecto.Migration

  def change do
    alter table(:order_items) do
      add :sent_at, :utc_datetime, null: true
      add :ready_at, :utc_datetime, null: true
    end

    alter table(:orders) do
      add :closed_at, :utc_datetime, null: true
    end
  end
end
