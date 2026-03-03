defmodule ConcurrencyLabs.ElixirSim.SessionSimSupervisor do
  @moduledoc """
  Per-session DynamicSupervisor. Manages DotProcesses for one browser tab.
  Scoped by session_id — process names include session_id to avoid clashes.
  """

  use DynamicSupervisor

  alias ConcurrencyLabs.ElixirSim.{Session, DotProcess}

  @initial_count 10
  @max_count 500
  @stress_batch 20
  @stress_batch_delay 80

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    name = Keyword.get(opts, :name, via(session_id))
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  def via(session_id) do
    {:via, Registry,
     {ConcurrencyLabs.ElixirSim.SessionRegistry_Procs,
      {:sim_sup, session_id}}}
  end

  @impl true
  def init(opts) do
    Process.put(:session_id, Keyword.fetch!(opts, :session_id))
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # --- Public API (all take session_id) ------------------------------------

  def seed(session_id) do
    for id <- 0..(@initial_count - 1) do
      start_process(session_id, id, restarted: false)
    end
  end

  def spawn_one(session_id) do
    id = next_id(session_id)
    if id >= @max_count do
      :max_reached
    else
      start_process(session_id, id, restarted: false)
      id
    end
  end

  def process_ids(session_id) do
    registry = Session.registry_name(session_id)
    Registry.select(registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  def process_count(session_id) do
    case GenServer.whereis(via(session_id)) do
      nil -> 0
      pid -> DynamicSupervisor.count_children(pid).active
    end
  end

  def mass_kill(session_id) do
    ids = process_ids(session_id)
    count = max(1, div(length(ids), 2))

    ids
    |> Enum.shuffle()
    |> Enum.take(count)
    |> Enum.each(fn id ->
      DotProcess.kill(session_id, id)
      ConcurrencyLabs.ElixirSim.SessionSimManager.schedule_respawn(
        session_id, id, 1_200)
    end)

    count
  end

  def stress_test(session_id) do
    current = length(process_ids(session_id))
    to_spawn = min(490, @max_count - current)
    start_id = next_id(session_id)

    Task.start(fn ->
      0..(to_spawn - 1)
      |> Enum.chunk_every(@stress_batch)
      |> Enum.each(fn batch ->
        for i <- batch do
          start_process(session_id, start_id + i, restarted: false)
        end
        Process.sleep(@stress_batch_delay)
      end)
    end)

    to_spawn
  end

  def reset(session_id) do
    ConcurrencyLabs.ElixirSim.SessionSimManager.reset(session_id)
  end

  def start_process(session_id, id, opts) do
    sup_pid = GenServer.whereis(via(session_id))
    if is_nil(sup_pid), do: {:error, :no_supervisor}

    all_opts = [id: id, session_id: session_id] ++ opts

    spec = %{
      id: {DotProcess, session_id, id},
      start: {DotProcess, :start_link, [all_opts]},
      restart: :temporary,
      type: :worker
    }

    case DynamicSupervisor.start_child(sup_pid, spec) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} ->
        require Logger
        Logger.warning("Session #{session_id}: failed to start process #{id}: #{inspect(reason)}")
        :error
    end
  end

  defp next_id(session_id) do
    ids = process_ids(session_id)
    if Enum.empty?(ids), do: 0, else: Enum.max(ids) + 1
  end
end
