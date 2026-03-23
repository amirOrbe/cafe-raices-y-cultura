defmodule CRC.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string, null: false
      add :email, :string, null: false
      add :phone, :string
      add :role, :string, null: false, default: "cliente"
      add :station, :string
      add :is_active, :boolean, null: false, default: true
      add :password_hash, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create index(:users, [:role])
    create index(:users, [:is_active])
  end
end
