defmodule CRC.Repo.Migrations.DropPortalClientesOrphans do
  @moduledoc """
  La rama abandonada `feature/portal-clientes` se deployó a producción y se
  revirtió a nivel de código pocas horas después. Dejó objetos físicos en la
  base de datos de producción que `master` nunca conoció:

    * tabla  `loyalty_visits`
    * columnas `orders.client_id` y `orders.scheduled_for`
    * columna `users.qr_token` (ya se le quitó el NOT NULL en
      20260909160000_default_qr_token_on_users.exs; aquí se elimina)
    * filas huérfanas en `schema_migrations`

  El nuevo módulo de CRM (migración siguiente) reconstruye todo esto limpio con
  nombres nuevos, así que estos restos solo estorban. Esta migración los retira.

  Todo va guarded con `IF EXISTS` / `information_schema`, de modo que en `test`
  y en bases nuevas —donde nada de esto existe— la migración es un no-op.
  Irreversible por diseño: `down` no recrea basura.
  """
  use Ecto.Migration

  def up do
    execute("DROP TABLE IF EXISTS loyalty_visits")

    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'orders' AND column_name = 'client_id'
      ) THEN
        ALTER TABLE orders DROP COLUMN client_id;
      END IF;

      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'orders' AND column_name = 'scheduled_for'
      ) THEN
        ALTER TABLE orders DROP COLUMN scheduled_for;
      END IF;

      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'qr_token'
      ) THEN
        ALTER TABLE users DROP COLUMN qr_token;
      END IF;
    END $$;
    """)

    execute("""
    DELETE FROM schema_migrations
    WHERE version IN (20260708172324, 20260708172325, 20260708183959)
    """)
  end

  def down do
    :ok
  end
end
