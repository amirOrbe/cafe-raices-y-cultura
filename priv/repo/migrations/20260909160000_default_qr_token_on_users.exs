defmodule CRC.Repo.Migrations.DefaultQrTokenOnUsers do
  @moduledoc """
  `users.qr_token` fue agregado como NOT NULL sin default por una migración de
  la rama `feature/portal-clientes` que se deployó a producción y luego se
  revirtió a nivel de código. El código actual (master) no conoce esa columna,
  así que crear un usuario nuevo fallaba con un not-null violation.

  Quitamos el NOT NULL: los INSERT del código actual, que no mencionan la
  columna, dejan qr_token en NULL (permitido, y el índice único acepta varios
  NULL en Postgres). No se elimina la columna para no perder los tokens ya
  generados.

  Condicional: en test / bases nuevas la columna no existe (esa migración
  huérfana no está en el repo), así que no se hace nada.
  """
  use Ecto.Migration

  def up do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'qr_token'
      ) THEN
        ALTER TABLE users ALTER COLUMN qr_token DROP NOT NULL;
        ALTER TABLE users ALTER COLUMN qr_token DROP DEFAULT;
      END IF;
    END $$;
    """)
  end

  def down do
    :ok
  end
end
