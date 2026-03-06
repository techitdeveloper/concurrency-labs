defmodule ConcurrencyLabs.ElixirSim.Session do
  @moduledoc """
  Supervised subtree for one browser tab (LiveView session).

  Children:
  1. Per-session dot Registry  (names like {session_id, dot_id})
  2. SessionSimSupervisor      (DynamicSupervisor for DotProcesses)
  3. SessionSimManager         (batched broadcasts + respawn scheduling)
  4. MetricsCollector          (samples memory every 1s)

  Lifecycle: started by SessionRegistry on LiveView mount,
  stopped by SessionRegistry on LiveView terminate.
  All children are GC'd when the session supervisor stops.
  """

  use Supervisor

  alias ConcurrencyLabs.ElixirSim.{
    SessionSimSupervisor,
    SessionSimManager,
    MetricsCollector
  }

  def start_link(session_id) do
    Supervisor.start_link(__MODULE__, session_id, name: via(session_id))
  end

  def stop(session_id) do
    case GenServer.whereis(via(session_id)) do
      nil -> :ok
      pid -> Supervisor.stop(pid, :normal)
    end
  end

  def via(session_id) do
    {:via, Registry, {ConcurrencyLabs.ElixirSim.SessionRegistry_Procs, {:session, session_id}}}
  end

  @impl true
  def init(session_id) do
    children = [
      # Per-session dot registry — keys are integer dot IDs
      %{
        id: :"dot_registry_#{session_id}",
        start: {Registry, :start_link, [[keys: :unique, name: registry_name(session_id)]]},
        type: :supervisor
      },

      # DynamicSupervisor for DotProcesses
      {SessionSimSupervisor, session_id: session_id},

      # SimManager: batched broadcasts + respawn scheduling
      {SessionSimManager, session_id: session_id},

      # Metrics sampler
      {MetricsCollector, session_id: session_id}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def registry_name(session_id) do
    :"dot_registry_#{session_id}"
  end

  def pubsub_topic(session_id) do
    "elixir_sim:#{session_id}"
  end
end
