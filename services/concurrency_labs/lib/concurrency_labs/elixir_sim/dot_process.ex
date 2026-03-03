defmodule ConcurrencyLabs.ElixirSim.DotProcess do
  @moduledoc """
  Per-session BEAM process. Scoped by session_id so processes from different
  tabs never collide in the registry or in PubSub.
  """

  use GenServer

  alias ConcurrencyLabs.ElixirSim.{Session, SessionSimManager}
  alias Phoenix.PubSub

  @pubsub ConcurrencyLabs.PubSub
  @canvas_w 1000.0
  @canvas_h 600.0
  @dot_radius 6.0
  @tick_ms 33
  @storm_death_chance 0.003
  @restart_delay_ms 1_200

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id, id))
  end

  def kill(session_id, id) do
    case GenServer.whereis(via(session_id, id)) do
      nil -> :not_found
      pid ->
        topic = Session.pubsub_topic(session_id)
        PubSub.broadcast(@pubsub, topic, {:process_dying, id})
        GenServer.cast(pid, :die)
        :ok
    end
  end

  def via(session_id, id) do
    registry = Session.registry_name(session_id)
    {:via, Registry, {registry, id}}
  end

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    session_id = Keyword.fetch!(opts, :session_id)
    restarted = Keyword.get(opts, :restarted, false)
    storm_mode = Keyword.get(opts, :storm_mode, false)

    speed = 1.5 + :rand.uniform_real() * 2.5
    angle = :rand.uniform_real() * 2 * :math.pi()

    state = %{
      id: id,
      session_id: session_id,
      x: @dot_radius + :rand.uniform_real() * (@canvas_w - 2 * @dot_radius),
      y: @dot_radius + :rand.uniform_real() * (@canvas_h - 2 * @dot_radius),
      vx: :math.cos(angle) * speed,
      vy: :math.sin(angle) * speed,
      memory_bytes: 0,
      storm_mode: storm_mode,
      active: not restarted
    }

    if restarted do
      Process.send_after(self(), :begin, @restart_delay_ms)
    else
      schedule_tick()
    end

    {:ok, state}
  end

  @impl true
  def handle_cast({:set_storm, enabled}, state) do
    {:noreply, %{state | storm_mode: enabled}}
  end

  def handle_cast(:die, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:begin, state) do
    topic = Session.pubsub_topic(state.session_id)
    PubSub.broadcast(@pubsub, topic, {:process_restarted, state.id})
    schedule_tick()
    {:noreply, %{state | active: true}}
  end

  def handle_info(:tick, %{active: false} = state) do
    {:noreply, state}
  end

  def handle_info(:tick, state) do
    state = move(state)
    state = %{state | memory_bytes: current_memory()}

    SessionSimManager.report_position(state.session_id, state.id, state.x, state.y)

    if state.storm_mode and :rand.uniform_real() < @storm_death_chance do
      topic = Session.pubsub_topic(state.session_id)
      PubSub.broadcast(@pubsub, topic, {:process_dying, state.id})
      {:stop, :normal, state}
    else
      schedule_tick()
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(:normal, %{storm_mode: true, id: id, session_id: session_id}) do
    SessionSimManager.process_died(session_id, id, :storm)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp move(state) do
    x = state.x + state.vx
    y = state.y + state.vy
    {x, vx} = bounce_x(x, state.vx)
    {y, vy} = bounce_y(y, state.vy)
    %{state | x: x, y: y, vx: vx, vy: vy}
  end

  defp bounce_x(x, vx) do
    cond do
      x - @dot_radius < 0 -> {@dot_radius, abs(vx)}
      x + @dot_radius > @canvas_w -> {@canvas_w - @dot_radius, -abs(vx)}
      true -> {x, vx}
    end
  end

  defp bounce_y(y, vy) do
    cond do
      y - @dot_radius < 0 -> {@dot_radius, abs(vy)}
      y + @dot_radius > @canvas_h -> {@canvas_h - @dot_radius, -abs(vy)}
      true -> {y, vy}
    end
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_ms)

  defp current_memory do
    case Process.info(self(), :memory) do
      {:memory, bytes} -> bytes
      nil -> 0
    end
  end
end
