defmodule CRC.Repo.Migrations.CreateSuppliers do
  use Ecto.Migration

  def change do
    create table(:suppliers) do
      add :name, :string, null: false
      add :contact_name, :string
      add :phone, :string
      add :email, :string
      add :address, :string
      add :notes, :text
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:suppliers, [:active])
    create index(:suppliers, [:name])
  end
end
