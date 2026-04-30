defmodule CRC.Repo.Migrations.CreateProductionTables do
  use Ecto.Migration

  def change do
    # Recipe: defines how to make an internal product (e.g. "Oleo de Naranja")
    create table(:production_recipes) do
      add :name, :string, null: false
      # how much is produced per batch
      add :yield_quantity, :decimal, null: false
      # unit of the output (ml, gramos, porciones…)
      add :yield_unit, :string, null: false
      add :notes, :text
      add :active, :boolean, null: false, default: true
      add :output_product_id, references(:products, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:production_recipes, [:active])
    create index(:production_recipes, [:output_product_id])

    # Ingredients consumed per batch of a recipe
    create table(:production_recipe_ingredients) do
      add :recipe_id, references(:production_recipes, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :delete_all), null: false
      # amount consumed per single batch
      add :quantity, :decimal, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:production_recipe_ingredients, [:recipe_id])
    create unique_index(:production_recipe_ingredients, [:recipe_id, :product_id])

    # Log: when a batch was actually produced
    create table(:production_logs) do
      add :recipe_id, references(:production_recipes, on_delete: :restrict), null: false
      # multiplier (1 = one batch, 2.5 = two and a half)
      add :batches, :decimal, null: false, default: 1
      add :notes, :text
      add :produced_by_id, references(:users, on_delete: :nilify_all)
      add :produced_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:production_logs, [:recipe_id])
    create index(:production_logs, [:produced_by_id])
    create index(:production_logs, [:produced_at])
  end
end
