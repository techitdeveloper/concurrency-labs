defmodule ConcurrencyLabs.ElixirSim.MetricsCollector do
  use GenServer

  alias Phoenix.PubSub
  alias ConcurrencyLabs.ElixirSim.ElixirSimSupervisor

  @pubsub ConcurrencyLabs.PubSub
  @topic "elixir_sim"
  @interval_ms 1_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{total_restarts: 0}}
  end

  @impl true
  def handle_info({:process_restarted, _id}, state) do
    {:noreply, %{state | total_restarts: state.total_restarts + 1}}
  end

  def handle_info(:collect, state) do
    sample = collect(state.total_restarts)
    PubSub.broadcast(@pubsub, @topic, {:metrics, sample})
    schedule()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule do
    Process.send_after(self(), :collect, @interval_ms)
  end

  defp collect(total_restarts) do
    ids = ElixirSimSupervisor.process_ids()
    process_count = length(ids)

    memories =
      ids
      |> Enum.map(fn id ->
        case Registry.lookup(ConcurrencyLabs.ElixirSim.Registry, id) do
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
