defmodule CRC.Repo.Migrations.AddStartedByToOrderItems do
  use Ecto.Migration

  # "Preparar" on the barra screen: a barista claims sent items so the others
  # don't make the same drink twice. The item stays "sent" until marked ready.
  def change do
    alter table(:order_items) do
      add :started_at, :utc_datetime
      add :started_by_id, references(:users, on_delete: :nilify_all), null: true
    end

    create index(:order_items, [:started_by_id])
  end
end
