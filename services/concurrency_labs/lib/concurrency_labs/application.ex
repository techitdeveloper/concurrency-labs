defmodule ConcurrencyLabs.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ConcurrencyLabsWeb.Telemetry,
      # ConcurrencyLabs.Repo,
      {DNSCluster, query: Application.get_env(:concurrency_labs, :dns_cluster_query) || :ignore},

      # Global registry for session supervisors and their named children.
      # Uses composite keys like {:session, id}, {:sim_sup, id}, {:sim_mgr, id}
      {Registry, keys: :unique, name: ConcurrencyLabs.ElixirSim.SessionRegistry_Procs},

      # Named DynamicSupervisor for session subtrees
      Supervisor.child_spec(
        {DynamicSupervisor,
         strategy: :one_for_one, name: ConcurrencyLabs.ElixirSim.SessionDynSup},
        id: :session_dyn_sup
      ),

      # Manages session subtree start/stop
      ConcurrencyLabs.ElixirSim.SessionRegistry,
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
