defmodule ConcurrencyLabsWeb.ElixirLabLive do
  use ConcurrencyLabsWeb, :live_view

  alias Phoenix.PubSub
  alias ConcurrencyLabs.ElixirSim.{
    DotProcess,
    Session,
    SessionRegistry,
    SessionSimSupervisor,
    SessionSimManager
  }

  @pubsub ConcurrencyLabs.PubSub

  @impl true
  def mount(_params, _session, socket) do
    session_id = socket.id

    if connected?(socket) do
      # Start this tab's private simulation subtree
      SessionRegistry.start_session(session_id)

      # Subscribe to this session's scoped PubSub topic
      PubSub.subscribe(@pubsub, Session.pubsub_topic(session_id))
    end

    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:process_count, 0)
      |> assign(:total_sim_memory_kb, 0)
      |> assign(:avg_memory_bytes, 0)
      |> assign(:beam_total_kb, 0)
      |> assign(:system_process_count, 0)
      |> assign(:total_restarts, 0)
      |> assign(:storm_mode, false)
      |> assign(:last_event, nil)

    {:ok, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    # Stop and GC the entire session subtree when the tab closes
    SessionRegistry.stop_session(socket.assigns.session_id)
    :ok
  end

  # --- PubSub handlers ------------------------------------------------------

  @impl true
  def handle_info({:positions_batch, positions}, socket) do
    {:noreply, push_event(socket, "positions_batch", %{positions: positions})}
  end

  def handle_info({:process_dying, id}, socket) do
    {:noreply,
     socket
     |> push_event("particle_dying", %{id: id})
     |> assign(:last_event, {:kill, "Process ##{id} killed — supervisor restarting…"})}
  end

  def handle_info({:process_restarted, id}, socket) do
    {:noreply,
     socket
     |> push_event("particle_restarted", %{id: id})
     |> assign(:last_event, {:restart, "Process ##{id} restarted by supervisor ✓"})
     |> assign(:total_restarts, socket.assigns.total_restarts + 1)}
  end

  def handle_info({:metrics, sample}, socket) do
    {:noreply,
     socket
     |> assign(:process_count, sample.process_count)
     |> assign(:total_sim_memory_kb, sample.total_sim_memory_kb)
     |> assign(:avg_memory_bytes, sample.avg_memory_bytes)
     |> assign(:beam_total_kb, sample.beam_total_kb)
     |> assign(:system_process_count, sample.system_process_count)
     |> push_event("metrics_update", sample)}
  end

  def handle_info(:reset_complete, socket) do
    {:noreply,
    socket
    |> assign(:storm_mode, false)
    |> assign(:total_restarts, 0)
    |> assign(:last_event, {:info, "Reset to 10 processes"})
    |> push_event("reset_particles", %{})}
  end

  def handle_info(:delayed_reset, socket) do
    SessionSimManager.reset(socket.assigns.session_id)
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- User events ----------------------------------------------------------

  @impl true
  def handle_event("spawn_process", _params, socket) do
    sid = socket.assigns.session_id
    case SessionSimSupervisor.spawn_one(sid) do
      :max_reached ->
        {:noreply, assign(socket, :last_event, {:warn, "Max 500 processes reached"})}
      id ->
        {:noreply, assign(socket, :last_event, {:spawn, "Spawned process ##{id}"})}
    end
  end

  def handle_event("kill_random", _params, socket) do
    sid = socket.assigns.session_id
    ids = SessionSimSupervisor.process_ids(sid)
    case ids do
      [] ->
        {:noreply, assign(socket, :last_event, {:warn, "No processes to kill"})}
      _ ->
        id = Enum.random(ids)
        DotProcess.kill(sid, id)
        SessionSimManager.schedule_respawn(sid, id, 1_200)
        {:noreply, assign(socket, :last_event, {:kill, "Killed ##{id} — supervisor restarting"})}
    end
  end

  def handle_event("mass_kill", _params, socket) do
    sid = socket.assigns.session_id
    count = SessionSimSupervisor.mass_kill(sid)
    {:noreply, assign(socket, :last_event, {:kill, "Killed #{count} processes — watching supervisor rebuild…"})}
  end

  def handle_event("toggle_storm", _params, socket) do
    sid = socket.assigns.session_id
    new_state = !socket.assigns.storm_mode
    SessionSimManager.set_storm(sid, new_state)

    for id <- SessionSimSupervisor.process_ids(sid) do
      case GenServer.whereis(DotProcess.via(sid, id)) do
        nil -> :ok
        pid -> GenServer.cast(pid, {:set_storm, new_state})
      end
    end

    msg = if new_state,
      do: {:storm, "Kill storm ON — processes dying randomly, supervisor healing…"},
      else: {:info, "Kill storm OFF"}

    {:noreply, socket |> assign(:storm_mode, new_state) |> assign(:last_event, msg)}
  end

  def handle_event("stress_test", _params, socket) do
    sid = socket.assigns.session_id
    count = SessionSimSupervisor.stress_test(sid)
    {:noreply, assign(socket, :last_event, {:spawn, "Spawning #{count} processes — watch Avg/process stay flat"})}
  end

  def handle_event("reset", _params, socket) do
    sid = socket.assigns.session_id
    SessionSimManager.reset(sid)
    Process.send_after(self(), :delayed_reset, 300)
    {:noreply, assign(socket, :last_event, {:info, "Resetting…"})}
  end

  # --- Render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="elixir-lab">
      <header class="lab-header">
        <div class="lab-header__left">
          <span class="lab-badge lab-badge--elixir">BEAM / OTP</span>
          <h1 class="lab-title">GenServer Simulation</h1>
          <p class="lab-subtitle">
            Each particle is a supervised GenServer. Kill them in bulk —
            the supervisor heals the system automatically. Your session is private.
          </p>
        </div>
        <div class="lab-header__right">
          <div class="status-pill status-pill--live">
            <span class="status-pip"></span>
            LIVE · private session
          </div>
        </div>
      </header>

      <div class="lab-body">
        <section class="sim-panel" aria-label="BEAM process simulation">
          <div class="panel-header">
            <span class="panel-label panel-label--elixir">PROCESSES</span>
            <span class="dot-counter"><%= @process_count %> GenServers</span>
          </div>

          <div id="elixir-sim-hook" phx-hook="ElixirSimulation">
            <div id="elixir-canvas-area" phx-update="ignore" class="canvas-wrapper canvas-wrapper--elixir">
              <canvas id="elixir-canvas"></canvas>
            </div>
          </div>

          <div class="sim-controls sim-controls--wrap">
            <button phx-click="spawn_process" class="btn btn--elixir">+ Spawn</button>
            <button phx-click="kill_random" class="btn btn--danger-outline">☠ Kill One</button>
            <button phx-click="mass_kill" class="btn btn--danger">☠☠ Mass Kill 50%</button>
            <button
              phx-click="toggle_storm"
              class={"btn #{if @storm_mode, do: "btn--storm-active", else: "btn--storm"}"}
            >
              <%= if @storm_mode, do: "⚡ Stop Storm", else: "⚡ Kill Storm" %>
            </button>
            <button phx-click="stress_test" class="btn btn--ghost">🚀 Stress Test (500)</button>
            <button phx-click="reset" class="btn btn--ghost">↺ Reset</button>
          </div>

          <div class="event-log">
            <span class={"event-log__pip event-log__pip--#{event_type(@last_event)}"}></span>
            <span class="event-log__text"><%= event_text(@last_event) %></span>
          </div>
        </section>

        <section class="metrics-panel" aria-label="BEAM memory metrics">
          <div class="panel-header">
            <span class="panel-label panel-label--elixir">MEMORY</span>
            <span class="panel-label panel-label--dim">:erlang.process_info</span>
          </div>

          <div class="stat-grid">
            <div class="stat-card">
              <span class="stat-label">Avg / Process</span>
              <span class="stat-value stat-value--elixir"><%= format_bytes(@avg_memory_bytes) %></span>
            </div>
            <div class="stat-card">
              <span class="stat-label">Total (sim)</span>
              <span class="stat-value stat-value--elixir"><%= format_kb(@total_sim_memory_kb) %></span>
            </div>
            <div class="stat-card">
              <span class="stat-label">BEAM Total</span>
              <span class="stat-value stat-value--elixir"><%= format_kb(@beam_total_kb) %></span>
            </div>
            <div class="stat-card">
              <span class="stat-label">Restarts</span>
              <span class="stat-value stat-value--elixir"><%= @total_restarts %></span>
            </div>
          </div>

          <div class="chart-container">
            <div class="chart-header">
              <span class="chart-title">Memory Over Time</span>
              <span class="chart-unit">KB</span>
            </div>
            <canvas
              id="elixir-memory-chart"
              phx-hook="ElixirMemoryChart"
              phx-update="ignore"
            ></canvas>
          </div>

          <div class="metrics-footer">
            <div class="footer-row">
              <span class="footer-label">Active GenServers</span>
              <span class="footer-value"><%= @process_count %></span>
            </div>
            <div class="footer-row">
              <span class="footer-label">All BEAM PIDs</span>
              <span class="footer-value"><%= @system_process_count %></span>
            </div>
            <div class="footer-row">
              <span class="footer-label">Supervisor Restarts</span>
              <span class="footer-value"><%= @total_restarts %></span>
            </div>
          </div>

          <p class="metrics-disclaimer">
            <strong>Avg / Process</strong> via <code>:erlang.process_info(pid, :memory)</code>.
            Run the stress test — watch avg stay flat at ~2–3 KB while count hits 500.
            Your session is private: other visitors have their own independent simulation.
          </p>
        </section>
      </div>

      <.explanation />
    </div>
    """
  end

  defp explanation(assigns) do
    ~H"""
    <section class="explainer" aria-label="How the Elixir simulation works">
      <div class="explainer__inner">
        <header class="explainer__header">
          <span class="explainer__eyebrow">// technical notes</span>
          <h2 class="explainer__title">How this works</h2>
          <p class="explainer__lead">
            Each particle is a real OTP GenServer supervised under a DynamicSupervisor.
            Your session is private — opening this page in another tab gives a completely
            independent simulation. Close the tab and every process is stopped and GC'd.
          </p>
        </header>

        <div class="explainer__grid">
          <article class="explainer__card">
            <div class="card__index">01</div>
            <h3 class="card__title">Actor Model</h3>
            <p class="card__body">
              Each particle is an independent <code>GenServer</code> that moves itself —
              no shared state, no central tick loop. Every process has its own heap,
              stack, and mailbox. A crash in one cannot corrupt another's memory.
            </p>
          </article>
          <article class="explainer__card">
            <div class="card__index">02</div>
            <h3 class="card__title">Mass Kill</h3>
            <p class="card__body">
              Killing 50% shows <code>:one_for_one</code> supervision in action:
              only dead processes restart — others keep running untouched.
              Each restart is explicit and delayed so you can watch the system
              rebuild particle by particle.
            </p>
          </article>
          <article class="explainer__card">
            <div class="card__index">03</div>
            <h3 class="card__title">Kill Storm</h3>
            <p class="card__body">
              Each process randomly self-terminates with a tiny probability per tick.
              The supervisor constantly respawns them. The system never goes down —
              it heals continuously, mirroring production OTP systems that run for years.
            </p>
          </article>
          <article class="explainer__card">
            <div class="card__index">04</div>
            <h3 class="card__title">Stress Test</h3>
            <p class="card__body">
              500 processes, ~2–3 KB each. Watch <strong>Avg / Process</strong> on
              the chart stay flat as count climbs. Total memory grows linearly;
              per-process cost stays constant. That's the BEAM story.
            </p>
          </article>
          <article class="explainer__card">
            <div class="card__index">05</div>
            <h3 class="card__title">Per-Session Isolation</h3>
            <p class="card__body">
              Each browser tab gets its own supervised subtree — a private
              <code>Registry</code>, <code>DynamicSupervisor</code>,
              <code>SimManager</code>, and <code>MetricsCollector</code>.
              Closing the tab stops the entire subtree. Two visitors never
              interfere with each other.
            </p>
          </article>
          <article class="explainer__card">
            <div class="card__index">06</div>
            <h3 class="card__title">Batched Broadcasting</h3>
            <p class="card__body">
              500 processes at 30fps would be 15,000 PubSub messages/sec.
              Instead, all positions go to <code>SimManager</code> which flushes
              one batched message every 50ms — 20 msgs/sec regardless of count.
              This keeps LiveView memory flat even during stress tests.
            </p>
          </article>
          <article class="explainer__card">
            <div class="card__index">07</div>
            <h3 class="card__title">Per-Process Memory</h3>
            <p class="card__body">
              Each BEAM process has its own heap and GC. One busy process never
              pauses the world. <code>:erlang.process_info(pid, :memory)</code>
              returns exact bytes per process — something Go's shared heap
              model cannot provide.
            </p>
          </article>
          <article class="explainer__card">
            <div class="card__index">08</div>
            <h3 class="card__title">Go vs BEAM</h3>
            <p class="card__body">
              Go goroutines are faster for raw CPU throughput. BEAM processes
              include supervision, per-process GC, and fault isolation by default.
              BEAM optimises for fault-tolerant long-running systems.
              Go optimises for throughput. Different tools, different problems.
            </p>
          </article>
        </div>

        <footer class="explainer__footer">
          <div class="explainer__stack">
            <span class="stack-item">Elixir 1.16</span>
            <span class="stack-sep">·</span>
            <span class="stack-item">OTP 26</span>
            <span class="stack-sep">·</span>
            <span class="stack-item">DynamicSupervisor</span>
            <span class="stack-sep">·</span>
            <span class="stack-item">Phoenix.PubSub</span>
            <span class="stack-sep">·</span>
            <span class="stack-item">LiveView</span>
          </div>
        </footer>
      </div>
    </section>
    """
  end

  defp event_type(nil), do: "idle"
  defp event_type({type, _}), do: to_string(type)
  defp event_text(nil), do: "Waiting for events…"
  defp event_text({_, text}), do: text

  defp format_kb(kb) when kb >= 1024, do: "#{Float.round(kb / 1024, 1)} MB"
  defp format_kb(kb), do: "#{kb} KB"
  defp format_bytes(b) when b >= 1024, do: "#{Float.round(b / 1024, 1)} KB"
  defp format_bytes(b), do: "#{b} B"
end
