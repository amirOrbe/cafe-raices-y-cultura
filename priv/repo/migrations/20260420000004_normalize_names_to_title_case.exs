defmodule CRC.Repo.Migrations.NormalizeNamesToTitleCase do
  use Ecto.Migration

  @moduledoc """
  Backfill: convert all existing name/title text fields to Title Case
  using PostgreSQL's built-in initcap() function.

  initcap('leche evaporada')    => 'Leche Evaporada'
  initcap('CAFÉ DE OLLA')       => 'Café De Olla'
  initcap('Leche Entera')       => 'Leche Entera'  (no change)
  """

  def up do
    execute "UPDATE products         SET name = initcap(name) WHERE name IS NOT NULL"
    execute "UPDATE product_variants SET name = initcap(name) WHERE name IS NOT NULL"
    execute "UPDATE product_categories SET name = initcap(name) WHERE name IS NOT NULL"
    execute "UPDATE suppliers        SET name = initcap(name) WHERE name IS NOT NULL"
    execute "UPDATE suppliers        SET contact_name = initcap(contact_name) WHERE contact_name IS NOT NULL"
    execute "UPDATE categories       SET name = initcap(name) WHERE name IS NOT NULL"
    execute "UPDATE menu_items       SET name = initcap(name) WHERE name IS NOT NULL"
    execute "UPDATE packages         SET name = initcap(name) WHERE name IS NOT NULL"
    execute "UPDATE collaborators    SET name = initcap(name) WHERE name IS NOT NULL"
    execute "UPDATE event_types      SET name = initcap(name) WHERE name IS NOT NULL"
    execute "UPDATE events           SET title = initcap(title) WHERE title IS NOT NULL"
    execute "UPDATE users            SET name = initcap(name) WHERE name IS NOT NULL"
    execute "UPDATE reservations     SET name = initcap(name) WHERE name IS NOT NULL"
  end

  def down do
    # Title Case cannot be reliably reversed — this migration is intentionally irreversible.
    :ok
  end
end
