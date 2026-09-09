defmodule CRC.Repo.Migrations.DefaultQrTokenOnUsers do
  @moduledoc """
  `users.qr_token` fue agregado como NOT NULL sin default por una migración de
  la rama `feature/portal-clientes` que se deployó a producción y luego se
  revirtió a nivel de código. El código actual (master) no conoce esa columna,
  así que crear un usuario nuevo fallaba con un not-null violation.

  Le ponemos un default para que los INSERT que no mencionan la columna sigan
  funcionando. Solo aplica si la columna existe (en test / bases nuevas no
  existe, porque esa migración huérfana no está en el repo).
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
        ALTER TABLE users ALTER COLUMN qr_token SET DEFAULT gen_random_uuid()::text;
        UPDATE users SET qr_token = gen_random_uuid()::text WHERE qr_token IS NULL;
      END IF;
    END $$;
    """)
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'qr_token'
      ) THEN
        ALTER TABLE users ALTER COLUMN qr_token DROP DEFAULT;
      END IF;
    END $$;
    """)
  end
end
