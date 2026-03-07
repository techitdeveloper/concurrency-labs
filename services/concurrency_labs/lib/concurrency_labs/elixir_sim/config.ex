defmodule ConcurrencyLabs.ElixirSim.Config do
  @moduledoc """
  Runtime configuration for the Elixir simulation.

  All tunables read from application environment, which is populated by
  config/runtime.exs (production) or config/dev.exs (development).

  Environment variables (all optional — defaults are production-safe):

    ELIXIR_SIM_INITIAL_COUNT      starting process count          (default: 10)
    ELIXIR_SIM_MAX_COUNT          hard cap on concurrent procs    (default: 500)
    ELIXIR_SIM_TICK_MS            movement tick in ms             (default: 33)
    ELIXIR_SIM_FLUSH_MS           position-batch flush interval   (default: 50)
    ELIXIR_SIM_CANVAS_W           canvas width in px              (default: 1000)
    ELIXIR_SIM_CANVAS_H           canvas height in px             (default: 600)
    ELIXIR_SIM_DOT_RADIUS         dot radius in px                (default: 6)
    ELIXIR_SIM_MIN_SPEED          min dot speed (px/tick)         (default: 1.5)
    ELIXIR_SIM_MAX_SPEED          max dot speed (px/tick)         (default: 4.0)
    ELIXIR_SIM_STORM_DEATH_CHANCE probability of self-kill/tick   (default: 0.003)
    ELIXIR_SIM_RESTART_DELAY_MS   delay before a killed dot respawns (default: 1200)
    ELIXIR_SIM_STORM_RESPAWN_MS   storm respawn delay             (default: 1500)
    ELIXIR_SIM_METRICS_INTERVAL_MS metrics sampling interval      (default: 1000)
    ELIXIR_SIM_STRESS_BATCH       processes per stress batch      (default: 20)
    ELIXIR_SIM_STRESS_BATCH_DELAY ms between stress batches       (default: 80)
  """

  @app :concurrency_labs
  @key :elixir_sim

  @defaults %{
    initial_count: 10,
    max_count: 500,
    tick_ms: 33,
    flush_ms: 50,
    canvas_w: 1000.0,
    canvas_h: 600.0,
    dot_radius: 6.0,
    min_speed: 1.5,
    max_speed: 4.0,
    storm_death_chance: 0.003,
    restart_delay_ms: 1_200,
    storm_respawn_ms: 1_500,
    metrics_interval_ms: 1_000,
    stress_batch: 20,
    stress_batch_delay_ms: 80
  }

  @doc "Returns the merged config map (app env overrides defaults)."
  def get do
    overrides = Application.get_env(@app, @key, %{})
    Map.merge(@defaults, overrides)
  end

  @doc "Convenience — fetch a single key with its default."
  def get(key) when is_atom(key) do
    Map.fetch!(get(), key)
  end
end
