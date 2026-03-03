defmodule ConcurrencyLabs.ElixirSim.MetricsCollector do
  @moduledoc """
  Per-session metrics sampler. Started as part of the Session subtree.
  Subscribes to the session-scoped PubSub topic to count restarts.
  Broadcasts metrics back on the same scoped topic so only this
  session's LiveView receives them.
  """

  use GenServer

  alias Phoenix.PubSub
  alias ConcurrencyLabs.ElixirSim.{Session, SessionSimSupervisor}

  @pubsub ConcurrencyLabs.PubSub
  @interval_ms 1_000

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  def via(session_id) do
    {:via, Registry,
     {ConcurrencyLabs.ElixirSim.SessionRegistry_Procs,
      {:metrics, session_id}}}
  end

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    topic = Session.pubsub_topic(session_id)
    PubSub.subscribe(@pubsub, topic)
    schedule()
    {:ok, %{session_id: session_id, total_restarts: 0}}
  end

  @impl true
  def handle_info({:process_restarted, _id}, state) do
    {:noreply, %{state | total_restarts: state.total_restarts + 1}}
  end

  def handle_info(:collect, state) do
    sample = collect(state.session_id, state.total_restarts)
    topic = Session.pubsub_topic(state.session_id)
    PubSub.broadcast(@pubsub, topic, {:metrics, sample})
    schedule()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule, do: Process.send_after(self(), :collect, @interval_ms)

  defp collect(session_id, total_restarts) do
    ids = SessionSimSupervisor.process_ids(session_id)
    process_count = length(ids)
    registry = Session.registry_name(session_id)

    memories =
      Enum.map(ids, fn id ->
        case Registry.lookup(registry, id) do
          [{pid, _}] ->
            case Process.info(pid, :memory) do
              {:memory, bytes} -> bytes
              nil -> 0
            end
          [] -> 0
        end
      end)

    total_sim_memory = Enum.sum(memories)
    avg_memory = if process_count > 0, do: div(total_sim_memory, process_count), else: 0

    %{
      timestamp_ms: System.system_time(:millisecond),
      process_count: process_count,
      total_sim_memory_kb: div(total_sim_memory, 1024),
      avg_memory_bytes: avg_memory,
      beam_total_kb: div(:erlang.memory(:total), 1024),
      beam_processes_kb: div(:erlang.memory(:processes), 1024),
      system_process_count: :erlang.system_info(:process_count),
      total_restarts: total_restarts
    }
  end
end
