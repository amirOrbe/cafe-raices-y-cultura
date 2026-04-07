defmodule CRC.Repo.Migrations.RemovePositionAndImageUrlFromMenuItems do
  use Ecto.Migration

  def up do
    alter table(:menu_items) do
      remove :position, :integer
      remove :image_url, :string
    end

    alter table(:categories) do
      remove :position, :integer
    end
  end

  def down do
    alter table(:menu_items) do
      add :position, :integer, default: 0
      add :image_url, :string
    end

    alter table(:categories) do
      add :position, :integer, default: 0
    end
  end
end
