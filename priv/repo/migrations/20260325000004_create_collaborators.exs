defmodule CRC.Repo.Migrations.CreateCollaborators do
  use Ecto.Migration

  def change do
    create table(:collaborators) do
      add :name, :string, null: false
      add :bio, :text
      add :instagram_handle, :string
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:collaborators, [:active])
  end
end
