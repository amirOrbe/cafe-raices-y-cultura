defmodule CRC.Repo.Migrations.CreateDiscounts do
  use Ecto.Migration

  def change do
    create table(:discounts) do
      add :name, :string, null: false
      add :percentage, :integer, null: false
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:discounts, [:active])
  end
end
