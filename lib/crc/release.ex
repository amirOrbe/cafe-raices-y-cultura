defmodule CRC.Release do
  @moduledoc "Tasks for running in production releases (e.g. migrations)."

  @app :crc

  def migrate do
    load_app()

    for repo <- repos() do
      migrate_with_retry(repo)
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  # On a cold-booted VM (e.g. a fresh Fly Machine, especially a brand-new
  # app whose private network is still propagating across the fleet), the
  # private-network DNS resolver can take a while to come up, so the very
  # first DB connection attempts at boot can fail even though the database
  # is fine. Retry with backoff instead of crashing the whole app on that.
  defp migrate_with_retry(repo, attempts_left \\ 12) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
  rescue
    e in DBConnection.ConnectionError ->
      if attempts_left > 1 do
        Process.sleep(5_000)
        migrate_with_retry(repo, attempts_left - 1)
      else
        reraise e, __STACKTRACE__
      end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
