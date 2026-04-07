defmodule CRC.Repo.Migrations.CreateProductCategories do
  use Ecto.Migration

  def change do
    create table(:product_categories) do
      add :name, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:product_categories, [:name])
  end
end
