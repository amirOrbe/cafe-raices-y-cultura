defmodule CRC.Repo.Migrations.CreatePhotos do
  use Ecto.Migration

  def change do
    create table(:photos) do
      add :url, :string, null: false
      add :caption, :string
      add :position, :integer, default: 0, null: false
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:photos, [:position])
    create index(:photos, [:active])
  end
end
