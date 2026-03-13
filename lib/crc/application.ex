defmodule CRC.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CRCWeb.Telemetry,
      CRC.Repo,
      {DNSCluster, query: Application.get_env(:crc, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CRC.PubSub},
      # Start a worker by calling: CRC.Worker.start_link(arg)
      # {CRC.Worker, arg},
      # Start to serve requests, typically the last entry
      CRCWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CRC.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CRCWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
