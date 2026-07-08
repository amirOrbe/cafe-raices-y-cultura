defmodule CRC.Repo.Migrations.AddQrTokenToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :qr_token, :string
    end

    create unique_index(:users, [:qr_token])

    # Back-fill existing rows with a unique token
    execute(
      "UPDATE users SET qr_token = gen_random_uuid()::text WHERE qr_token IS NULL",
      "SELECT 1"
    )

    alter table(:users) do
      modify :qr_token, :string, null: false
    end
  end
end
