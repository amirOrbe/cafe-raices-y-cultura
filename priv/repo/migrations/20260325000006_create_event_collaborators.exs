defmodule CRC.Repo.Migrations.CreateEventCollaborators do
  use Ecto.Migration

  def change do
    create table(:event_collaborators) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :collaborator_id, references(:collaborators, on_delete: :delete_all), null: false
      add :role_in_event, :string

      timestamps(type: :utc_datetime)
    end

    create index(:event_collaborators, [:event_id])
    create index(:event_collaborators, [:collaborator_id])
    create unique_index(:event_collaborators, [:event_id, :collaborator_id])
  end
end
