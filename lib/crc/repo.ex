defmodule CRC.Repo do
  use Ecto.Repo,
    otp_app: :crc,
    adapter: Ecto.Adapters.Postgres
end
