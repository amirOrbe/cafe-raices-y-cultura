defmodule CRC.Repo.Migrations.CreateReservations do
  use Ecto.Migration

  def change do
    create table(:reservations) do
      add :name, :string, null: false
      add :email, :string
      add :phone, :string, null: false
      add :date, :date, null: false
      add :time, :time, null: false
      add :party_size, :integer, null: false
      add :notes, :text
      add :status, :string, default: "pending", null: false

      timestamps(type: :utc_datetime)
    end

    create index(:reservations, [:date])
    create index(:reservations, [:status])
  end
end
