defmodule CRC.Repo.Migrations.CreateShiftNotes do
  use Ecto.Migration

  def change do
    create table(:shift_notes) do
      add :content, :text, null: false
      add :category, :string, null: false, default: "general"
      add :status, :string, null: false, default: "active"
      add :author_id, references(:users, on_delete: :nilify_all)
      add :resolved_by_id, references(:users, on_delete: :nilify_all)
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:shift_notes, [:status])
    create index(:shift_notes, [:author_id])
    create index(:shift_notes, [:inserted_at])
  end
end
