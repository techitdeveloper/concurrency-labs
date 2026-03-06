defmodule ConcurrencyLabs.ElixirSim.SessionRegistry do
  use GenServer

  @dyn_sup ConcurrencyLabs.ElixirSim.SessionDynSup

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_session(session_id) do
    GenServer.call(__MODULE__, {:start, session_id})
  end

  def stop_session(session_id) do
    GenServer.cast(__MODULE__, {:stop, session_id})
  end

  @impl true
  def init(_opts) do
    # Trap exits so we know when session children die unexpectedly
    Process.flag(:trap_exit, true)
    {:ok, %{sessions: %{}}}
  end

  @impl true
  def handle_call({:start, session_id}, _from, %{sessions: sessions} = state) do
    case DynamicSupervisor.start_child(@dyn_sup,
           {ConcurrencyLabs.ElixirSim.Session, session_id}) do
      {:ok, pid} ->
        ConcurrencyLabs.ElixirSim.SessionSimSupervisor.seed(session_id)
        new_state = %{state | sessions: Map.put(sessions, session_id, pid)}
        {:reply, :ok, new_state}

      {:error, {:already_started, _pid}} ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:stop, session_id}, %{sessions: sessions} = state) do
    case Map.get(sessions, session_id) do
      nil ->
        {:noreply, state}

      pid ->
        DynamicSupervisor.terminate_child(@dyn_sup, pid)
        {:noreply, %{state | sessions: Map.delete(sessions, session_id)}}
    end
  end

  # Handle EXIT messages from monitored session children gracefully
  # so the registry itself never crashes due to a child dying
  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
