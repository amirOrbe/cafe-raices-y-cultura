defmodule CRC.Repo.Migrations.CreateEventPhotos do
  use Ecto.Migration

  def change do
    create table(:event_photos) do
      add :image_url, :string, null: false
      add :caption, :string
      add :event_id, references(:events, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:event_photos, [:event_id])
  end
end
