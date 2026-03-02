defmodule ConcurrencyLabs.ElixirSim.SimManager do
  @moduledoc """
  Central GenServer that owns:
  - All respawn scheduling (storm deaths + manual kills)
  - Batched position broadcasting (one PubSub msg/tick, not one per process)
  - Storm mode state

  Why this exists:
  - DynamicSupervisor cannot receive custom messages (no handle_info in OTP)
  - mass_kill/0 used self() which resolved to the LiveView caller PID
  - 490 processes × 30fps = 14,700 PubSub msgs/sec flooding LiveView heap
    → this coordinator collects all positions and sends ONE message per tick

  Architecture:
    DotProcess → SimManager.report_position (cast)
    SimManager → accumulates positions, flushes every @flush_ms via PubSub
    DotProcess.terminate → SimManager.process_died (cast)
    SimManager → schedules respawn after delay, calls ElixirSimSupervisor
  """

  use GenServer

  alias Phoenix.PubSub
  alias ConcurrencyLabs.ElixirSim.ElixirSimSupervisor

  @pubsub ConcurrencyLabs.PubSub
  @topic "elixir_sim"

  # Flush accumulated positions to PubSub at this rate regardless of process count
  # 50ms = 20fps — smooth enough, low enough to not flood LiveView
  @flush_ms 50

  @storm_respawn_delay_ms 1_500
  @manual_respawn_delay_ms 1_200

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Called by DotProcess every tick with its current position
  def report_position(id, x, y) do
    GenServer.cast(__MODULE__, {:position, id, x, y})
  end

  # Called by DotProcess.terminate/2 when a storm death occurs
  def process_died(id, :storm) do
    GenServer.cast(__MODULE__, {:died, id, :storm})
  end

  # Called by SimManager itself (and mass_kill) to schedule a respawn
  def schedule_respawn(id, delay_ms, opts \\ []) do
    GenServer.cast(__MODULE__, {:schedule_respawn, id, delay_ms, opts})
  end

  def set_storm(enabled) do
    GenServer.call(__MODULE__, {:set_storm, enabled})
  end

  def storm_mode? do
    GenServer.call(__MODULE__, :storm_mode)
  end

  # --- GenServer callbacks --------------------------------------------------

  @impl true
  def init(_opts) do
    schedule_flush()
    {:ok, %{
      positions: %{},   # id → {x, y}
      storm_mode: false
    }}
  end

  @impl true
  def handle_cast({:position, id, x, y}, state) do
    {:noreply, put_in(state, [:positions, id], {x, y})}
  end

  def handle_cast({:died, id, :storm}, state) do
    if state.storm_mode do
      schedule_respawn(id, @storm_respawn_delay_ms, storm_mode: true)
    end
    {:noreply, state}
  end

  def handle_cast({:schedule_respawn, id, delay_ms, opts}, state) do
    Process.send_after(self(), {:do_respawn, id, opts}, delay_ms)
    {:noreply, state}
  end

  @impl true
  def handle_call({:set_storm, enabled}, _from, state) do
    {:reply, enabled, %{state | storm_mode: enabled}}
  end

  def handle_call(:storm_mode, _from, state) do
    {:reply, state.storm_mode, state}
  end

  @impl true
  def handle_info({:do_respawn, id, opts}, state) do
    ElixirSimSupervisor.start_process(id, [{:restarted, true} | opts])
    {:noreply, state}
  end

  def handle_info(:flush, state) do
    if map_size(state.positions) > 0 do
      serializable =
        Map.new(state.positions, fn {id, {x, y}} -> {id, [x, y]} end)

      PubSub.broadcast(@pubsub, @topic, {:positions_batch, serializable})
    end

    schedule_flush()
    {:noreply, %{state | positions: %{}}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_ms)
  end
end
