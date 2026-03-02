defmodule ConcurrencyLabs.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ConcurrencyLabsWeb.Telemetry,
      ConcurrencyLabs.Repo,
      {DNSCluster, query: Application.get_env(:concurrency_labs, :dns_cluster_query) || :ignore},

      # Elixir simulation registry — must start before the supervisor
      {Registry, keys: :unique, name: ConcurrencyLabs.ElixirSim.Registry},

      # Simulation supervisor — manages all DotProcess GenServers
      ConcurrencyLabs.ElixirSim.ElixirSimSupervisor,

      ConcurrencyLabs.ElixirSim.SimManager,

      # Metrics collector — samples :erlang.process_info every 1s
      ConcurrencyLabs.ElixirSim.MetricsCollector,

      {Phoenix.PubSub, name: ConcurrencyLabs.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: ConcurrencyLabs.Finch},
      # Start a worker by calling: ConcurrencyLabs.Worker.start_link(arg)
      # {ConcurrencyLabs.Worker, arg},
      # Start to serve requests, typically the last entry
      ConcurrencyLabsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ConcurrencyLabs.Supervisor]
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Seed initial processes after the supervisor tree is running
        ConcurrencyLabs.ElixirSim.ElixirSimSupervisor.seed()
        {:ok, pid}

      error ->
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ConcurrencyLabsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
