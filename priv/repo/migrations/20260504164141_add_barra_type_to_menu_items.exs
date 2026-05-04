defmodule CRC.Repo.Migrations.AddBarraTypeToMenuItems do
  use Ecto.Migration

  def change do
    alter table(:menu_items) do
      add :barra_type, :string, null: true
    end
  end
end
