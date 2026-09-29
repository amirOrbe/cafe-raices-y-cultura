defmodule CRC.Repo.Migrations.ReclassifyRetailCategories do
  use Ecto.Migration

  @retail_categories ["Cafe A Granel", "Merch", "Película Fotográfica", "Rev & Scan"]

  # These categories are simple retail products (café en grano, merch,
  # rollos de película, servicio de revelado…) — no se preparan, así que
  # no deben mandarse a cocina ni a barra. Reclasifica sus menu_items
  # existentes al nuevo destino "retail" y limpia barra_type (ya no aplica).
  def up do
    execute("""
    UPDATE menu_items
    SET destination = 'retail', barra_type = NULL
    FROM categories
    WHERE menu_items.category_id = categories.id
      AND categories.name = ANY(#{sql_array(@retail_categories)})
    """)
  end

  # Not a true inverse (original destinations were a mix of cocina/barra,
  # not recorded) — reverts to the schema default so nothing is left
  # inconsistent if this migration needs to be rolled back.
  def down do
    execute("""
    UPDATE menu_items
    SET destination = 'cocina'
    FROM categories
    WHERE menu_items.category_id = categories.id
      AND categories.name = ANY(#{sql_array(@retail_categories)})
      AND menu_items.destination = 'retail'
    """)
  end

  defp sql_array(list) do
    quoted = Enum.map_join(list, ",", &"'#{String.replace(&1, "'", "''")}'")
    "ARRAY[#{quoted}]"
  end
end
