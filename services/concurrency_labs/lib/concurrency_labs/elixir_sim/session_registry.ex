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
    # No need to start a DynamicSupervisor here — it's already named and running
    {:ok, %{sessions: %{}}}
  end

  @impl true
  def handle_call({:start, session_id}, _from, state) do
    case DynamicSupervisor.start_child(@dyn_sup,
           {ConcurrencyLabs.ElixirSim.Session, session_id}) do
      {:ok, pid} ->
        ConcurrencyLabs.ElixirSim.SessionSimSupervisor.seed(session_id)
        {:reply, :ok, put_in(state, [:sessions, session_id], pid)}

      {:error, {:already_started, _pid}} ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:stop, session_id}, state) do
    case Map.get(state.sessions, session_id) do
      nil -> {:noreply, state}
      pid ->
        DynamicSupervisor.terminate_child(@dyn_sup, pid)
        {:noreply, Map.delete(state.sessions, session_id)}
    end
  end
end
