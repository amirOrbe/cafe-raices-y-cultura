defmodule CRC.Repo.Migrations.RemoveKindFromCategories do
  use Ecto.Migration

  def up do
    alter table(:categories) do
      remove :kind, :string
    end
  end

  def down do
    alter table(:categories) do
      add :kind, :string, default: "food"
    end
  end
end
