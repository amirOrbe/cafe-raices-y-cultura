defmodule CRC.Repo.Migrations.AddForPersonToOrderItems do
  use Ecto.Migration

  def change do
    alter table(:order_items) do
      add :for_person, :string, null: true, size: 50
    end
  end
end
