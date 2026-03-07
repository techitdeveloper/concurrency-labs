defmodule ConcurrencyLabs.ElixirSim.DotProcess do
  @moduledoc """
  Per-session BEAM process. Scoped by session_id so processes from different
  tabs never collide in the registry or in PubSub.
  """

  use GenServer

  alias ConcurrencyLabs.ElixirSim.{Config, Session, SessionSimManager}
  alias Phoenix.PubSub

  @pubsub ConcurrencyLabs.PubSub

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id, id))
  end

  def kill(session_id, id) do
    case GenServer.whereis(via(session_id, id)) do
      nil ->
        :not_found

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
    cfg = Config.get()

    id = Keyword.fetch!(opts, :id)
    session_id = Keyword.fetch!(opts, :session_id)
    restarted = Keyword.get(opts, :restarted, false)
    storm_mode = Keyword.get(opts, :storm_mode, false)

    speed_range = cfg.max_speed - cfg.min_speed
    speed = cfg.min_speed + :rand.uniform_real() * speed_range
    angle = :rand.uniform_real() * 2 * :math.pi()

    state = %{
      id: id,
      session_id: session_id,
      x: cfg.dot_radius + :rand.uniform_real() * (cfg.canvas_w - 2 * cfg.dot_radius),
      y: cfg.dot_radius + :rand.uniform_real() * (cfg.canvas_h - 2 * cfg.dot_radius),
      vx: :math.cos(angle) * speed,
      vy: :math.sin(angle) * speed,
      storm_mode: storm_mode,
      active: not restarted,
      # snapshot config into state so moves are consistent for this process's lifetime
      cfg: cfg
    }

    if restarted do
      Process.send_after(self(), :begin, cfg.restart_delay_ms)
    else
      schedule_tick(cfg.tick_ms)
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
    schedule_tick(state.cfg.tick_ms)
    {:noreply, %{state | active: true}}
  end

  def handle_info(:tick, %{active: false} = state) do
    {:noreply, state}
  end

  def handle_info(:tick, state) do
    state = move(state)
    SessionSimManager.report_position(state.session_id, state.id, state.x, state.y)

    if state.storm_mode and :rand.uniform_real() < state.cfg.storm_death_chance do
      topic = Session.pubsub_topic(state.session_id)
      PubSub.broadcast(@pubsub, topic, {:process_dying, state.id})
      {:stop, :normal, state}
    else
      schedule_tick(state.cfg.tick_ms)
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

  defp move(%{cfg: cfg} = state) do
    x = state.x + state.vx
    y = state.y + state.vy
    {x, vx} = bounce_x(x, state.vx, cfg)
    {y, vy} = bounce_y(y, state.vy, cfg)
    %{state | x: x, y: y, vx: vx, vy: vy}
  end

  defp bounce_x(x, vx, cfg) do
    cond do
      x - cfg.dot_radius < 0 -> {cfg.dot_radius, abs(vx)}
      x + cfg.dot_radius > cfg.canvas_w -> {cfg.canvas_w - cfg.dot_radius, -abs(vx)}
      true -> {x, vx}
    end
  end

  defp bounce_y(y, vy, cfg) do
    cond do
      y - cfg.dot_radius < 0 -> {cfg.dot_radius, abs(vy)}
      y + cfg.dot_radius > cfg.canvas_h -> {cfg.canvas_h - cfg.dot_radius, -abs(vy)}
      true -> {y, vy}
    end
  end

  defp schedule_tick(tick_ms), do: Process.send_after(self(), :tick, tick_ms)
end
