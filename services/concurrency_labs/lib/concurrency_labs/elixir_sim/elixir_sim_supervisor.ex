defmodule ConcurrencyLabs.ElixirSim.ElixirSimSupervisor do
  @moduledoc """
  Pure DynamicSupervisor — only starts and stops child processes.
  No custom handle_info. All respawn logic lives in SimManager.

  restart: :temporary on every child so OTP never auto-restarts anyone.
  All restarts are explicit and go through SimManager.
  """

  use DynamicSupervisor

  alias ConcurrencyLabs.ElixirSim.DotProcess

  @initial_count 10
  @max_count 500
  @stress_batch 20
  @stress_batch_delay 80

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def seed do
    for id <- 0..(@initial_count - 1) do
      start_process(id, restarted: false)
    end
  end

  def spawn_one do
    id = next_id()

    if id >= @max_count do
      :max_reached
    else
      start_process(id, restarted: false)
      id
    end
  end

  def process_ids do
    Registry.select(
      ConcurrencyLabs.ElixirSim.Registry,
      [{{:"$1", :_, :_}, [], [:"$1"]}]
    )
  end

  def process_count do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  def mass_kill do
    ids = process_ids()
    count = max(1, div(length(ids), 2))

    ids
    |> Enum.shuffle()
    |> Enum.take(count)
    |> Enum.each(fn id ->
      DotProcess.kill(id)
      # Schedule respawn through SimManager — NOT self()
      ConcurrencyLabs.ElixirSim.SimManager.schedule_respawn(
        id,
        1_200,
        storm_mode: ConcurrencyLabs.ElixirSim.SimManager.storm_mode?()
      )
    end)

    count
  end

  def stress_test do
    current = length(process_ids())
    to_spawn = min(490, @max_count - current)
    start_id = next_id()

    Task.start(fn ->
      0..(to_spawn - 1)
      |> Enum.chunk_every(@stress_batch)
      |> Enum.each(fn batch ->
        for i <- batch, do: start_process(start_id + i, restarted: false)
        Process.sleep(@stress_batch_delay)
      end)
    end)

    to_spawn
  end

  def reset do
    ConcurrencyLabs.ElixirSim.SimManager.set_storm(false)

    for {_, pid, _, _} <- DynamicSupervisor.which_children(__MODULE__) do
      DynamicSupervisor.terminate_child(__MODULE__, pid)
    end

    Process.sleep(100)
    seed()
  end

  def start_process(id, opts) do
    all_opts = [id: id] ++ opts

    spec = %{
      id: {DotProcess, id},
      start: {DotProcess, :start_link, [all_opts]},
      restart: :temporary,
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, _} ->
        :ok

      {:error, {:already_started, _}} ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.warning("Could not start process #{id}: #{inspect(reason)}")
        :error
    end
  end

  defp next_id do
    ids = process_ids()
    if Enum.empty?(ids), do: 0, else: Enum.max(ids) + 1
  end
end
