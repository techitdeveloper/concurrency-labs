defmodule ConcurrencyLabs.ElixirSim.SessionSimManager do
  @moduledoc """
  Per-session GenServer. Handles:
  - Batched position broadcasting (one PubSub msg per flush, not per process)
  - Storm mode state and respawn scheduling
  - All respawn messages stay inside this process — no stray sends to LiveView
  All timing constants come from ElixirSim.Config.
  """

  use GenServer

  alias Phoenix.PubSub
  alias ConcurrencyLabs.ElixirSim.{Config, Session}

  @pubsub ConcurrencyLabs.PubSub

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    name = Keyword.get(opts, :name, via(session_id))
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def via(session_id) do
    {:via, Registry, {ConcurrencyLabs.ElixirSim.SessionRegistry_Procs, {:sim_mgr, session_id}}}
  end

  def report_position(session_id, id, x, y) do
    case GenServer.whereis(via(session_id)) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:position, id, x, y})
    end
  end

  def process_died(session_id, id, :storm) do
    case GenServer.whereis(via(session_id)) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:died, id, :storm})
    end
  end

  def schedule_respawn(session_id, id, delay_ms, opts \\ []) do
    case GenServer.whereis(via(session_id)) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:schedule_respawn, id, delay_ms, opts})
    end
  end

  def set_storm(session_id, enabled) do
    case GenServer.whereis(via(session_id)) do
      nil -> :ok
      pid -> GenServer.call(pid, {:set_storm, enabled})
    end
  end

  def storm_mode?(session_id) do
    case GenServer.whereis(via(session_id)) do
      nil -> false
      pid -> GenServer.call(pid, :storm_mode)
    end
  end

  def reset(session_id) do
    case GenServer.whereis(via(session_id)) do
      nil -> :ok
      pid -> GenServer.cast(pid, :reset)
    end
  end

  # --- Callbacks ------------------------------------------------------------

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    cfg = Config.get()
    schedule_flush(cfg.flush_ms)
    {:ok, %{session_id: session_id, positions: %{}, storm_mode: false, cfg: cfg}}
  end

  @impl true
  def handle_cast({:position, id, x, y}, state) do
    {:noreply, put_in(state, [:positions, id], {x, y})}
  end

  def handle_cast({:died, id, :storm}, state) do
    delay = state.cfg.storm_respawn_ms
    Process.send_after(self(), {:do_respawn, id, [storm_mode: state.storm_mode]}, delay)
    {:noreply, state}
  end

  def handle_cast({:schedule_respawn, id, delay_ms, opts}, state) do
    Process.send_after(self(), {:do_respawn, id, opts}, delay_ms)
    {:noreply, state}
  end

  def handle_cast(:reset, state) do
    Process.send_after(self(), :do_reset, 0)
    {:noreply, %{state | storm_mode: false, positions: %{}}}
  end

  @impl true
  def handle_call({:set_storm, enabled}, _from, state) do
    {:reply, enabled, %{state | storm_mode: enabled}}
  end

  def handle_call(:storm_mode, _from, state) do
    {:reply, state.storm_mode, state}
  end

  @impl true
  def handle_info({:do_respawn, id, _opts}, state) do
    ConcurrencyLabs.ElixirSim.SessionSimSupervisor.start_process(
      state.session_id,
      id,
      restarted: true,
      storm_mode: state.storm_mode
    )

    {:noreply, state}
  end

  def handle_info(:flush, state) do
    if map_size(state.positions) > 0 do
      topic = Session.pubsub_topic(state.session_id)
      serializable = Map.new(state.positions, fn {id, {x, y}} -> {id, [x, y]} end)
      PubSub.broadcast(@pubsub, topic, {:positions_batch, serializable})
    end

    schedule_flush(state.cfg.flush_ms)
    {:noreply, %{state | positions: %{}}}
  end

  def handle_info(:do_reset, state) do
    do_reset(state.session_id, state.cfg)
    {:noreply, %{state | positions: %{}}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_flush(flush_ms), do: Process.send_after(self(), :flush, flush_ms)

  defp do_reset(session_id, cfg) do
    sup_pid = GenServer.whereis(ConcurrencyLabs.ElixirSim.SessionSimSupervisor.via(session_id))

    if sup_pid do
      for {_, pid, _, _} <- DynamicSupervisor.which_children(sup_pid) do
        DynamicSupervisor.terminate_child(sup_pid, pid)
      end
    end

    registry = Session.registry_name(session_id)
    wait_for_empty_registry(registry, 50, 40)

    ConcurrencyLabs.ElixirSim.SessionSimSupervisor.seed(session_id)

    Process.sleep(cfg.tick_ms * 2)

    topic = Session.pubsub_topic(session_id)
    Phoenix.PubSub.broadcast(ConcurrencyLabs.PubSub, topic, :reset_complete)
  end

  defp wait_for_empty_registry(registry, sleep_ms, retries) when retries > 0 do
    if Registry.select(registry, [{{:"$1", :_, :_}, [], [:"$1"]}]) == [] do
      :ok
    else
      Process.sleep(sleep_ms)
      wait_for_empty_registry(registry, sleep_ms, retries - 1)
    end
  end

  defp wait_for_empty_registry(_registry, _sleep_ms, 0), do: :ok
end
