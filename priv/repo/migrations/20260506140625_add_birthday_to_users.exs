defmodule CRC.Repo.Migrations.AddBirthdayToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :birthday, :date
    end

    create index(:users, [:birthday])
  end
end
