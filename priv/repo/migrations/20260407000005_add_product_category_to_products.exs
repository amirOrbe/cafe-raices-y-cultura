defmodule CRC.Repo.Migrations.AddProductCategoryToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :product_category_id, references(:product_categories, on_delete: :nilify_all)
      remove :category, :string
    end

    create index(:products, [:product_category_id])
  end
end
