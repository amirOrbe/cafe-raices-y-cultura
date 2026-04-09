defmodule CRC.Repo.Migrations.AddDestinationToMenuItems do
  use Ecto.Migration

  def change do
    alter table(:menu_items) do
      add :destination, :string, null: false, default: "cocina"
    end
  end
end
