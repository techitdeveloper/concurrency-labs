defmodule ConcurrencyLabsWeb.GoLabLive do
  use ConcurrencyLabsWeb, :live_view

  @go_ws_url Application.compile_env(
               :concurrency_labs,
               :go_ws_url,
               "ws://localhost:4001/ws"
             )

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:dot_count, 10)
      |> assign(:heap_alloc_kb, 0)
      |> assign(:heap_sys_kb, 0)
      |> assign(:stack_inuse_kb, 0)
      |> assign(:num_goroutine, 0)
      |> assign(:num_gc_cycles, 0)
      |> assign(:go_ws_url, @go_ws_url)
      |> assign(:connected, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("metrics_update", params, socket) do
    socket =
      socket
      |> assign(:heap_alloc_kb, params["heap_alloc_kb"] || 0)
      |> assign(:heap_sys_kb, params["heap_sys_kb"] || 0)
      |> assign(:stack_inuse_kb, params["stack_inuse_kb"] || 0)
      |> assign(:num_goroutine, params["num_goroutine"] || 0)
      |> assign(:num_gc_cycles, params["num_gc_cycles"] || 0)

    {:noreply, socket}
  end

  def handle_event("dot_count_update", %{"count" => count}, socket) do
    {:noreply, assign(socket, :dot_count, count)}
  end

  def handle_event("connection_status", %{"connected" => connected}, socket) do
    {:noreply, assign(socket, :connected, connected)}
  end

  def handle_event("spawn_dot", _params, socket) do
    {:noreply, push_event(socket, "go_command", %{kind: "spawn_dot"})}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, push_event(socket, "go_command", %{kind: "reset"})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="go-lab">
      <header class="lab-header">
        <div class="lab-header__left">
          <span class="lab-badge">GO RUNTIME</span>
          <h1 class="lab-title">Goroutine Simulation</h1>
          <p class="lab-subtitle">
            Each dot owns a goroutine. Collisions spawn new ones.
            Watch Go's heap respond in real time.
          </p>
        </div>
        <div class="lab-header__right">
          <div class={"status-pill #{if @connected, do: "status-pill--live", else: "status-pill--offline"}"}>
            <span class="status-pip"></span>
            <%= if @connected, do: "LIVE", else: "CONNECTING…" %>
          </div>
        </div>
      </header>

      <div class="lab-body">
        <section class="sim-panel" aria-label="Goroutine simulation">
          <div class="panel-header">
            <span class="panel-label">SIMULATION</span>
            <span class="dot-counter">
              <span id="dot-count-display"><%= @dot_count %></span> dots
            </span>
          </div>

          <div
            id="go-sim-hook"
            phx-hook="GoSimulation"
            data-ws-url={@go_ws_url}
          >
            <div id="go-sim-canvas-area" phx-update="ignore" class="canvas-wrapper">
              <canvas id="sim-canvas"></canvas>
              <div id="canvas-overlay" class="canvas-overlay">
                Connecting to Go runtime…
              </div>
            </div>
          </div>

          <div class="sim-controls">
            <button phx-click="spawn_dot" class="btn btn--primary">
              + Spawn Goroutine
            </button>
            <button phx-click="reset" class="btn btn--ghost">
              ↺ Reset
            </button>
          </div>
        </section>

        <section class="metrics-panel" aria-label="Go runtime memory metrics">
          <div class="panel-header">
            <span class="panel-label">MEMORY</span>
            <span class="panel-label panel-label--dim">runtime.MemStats</span>
          </div>

          <div class="stat-grid">
            <div class="stat-card">
              <span class="stat-label">Heap Alloc</span>
              <span class="stat-value"><%= format_kb(@heap_alloc_kb) %></span>
            </div>
            <div class="stat-card">
              <span class="stat-label">Heap Sys</span>
              <span class="stat-value"><%= format_kb(@heap_sys_kb) %></span>
            </div>
            <div class="stat-card">
              <span class="stat-label">Stack In-Use</span>
              <span class="stat-value"><%= format_kb(@stack_inuse_kb) %></span>
            </div>
            <div class="stat-card">
              <span class="stat-label">Total Goroutines</span>
              <span class="stat-value"><%= @num_goroutine %></span>
            </div>
          </div>

          <div class="chart-container">
            <div class="chart-header">
              <span class="chart-title">Heap Allocation Over Time</span>
              <span class="chart-unit">KB</span>
            </div>
            <canvas
              id="memory-chart"
              phx-hook="MemoryChart"
              phx-update="ignore"
            ></canvas>
          </div>

          <div class="metrics-footer">
            <div class="footer-row">
              <span class="footer-label">Simulation dots</span>
              <span class="footer-value"><%= @dot_count %></span>
            </div>
            <div class="footer-row">
              <span class="footer-label">GC cycles</span>
              <span class="footer-value"><%= @num_gc_cycles %></span>
            </div>
          </div>

          <p class="metrics-disclaimer">
            <strong>Total Goroutines</strong> is process-wide —
            includes Go internals, the HTTP server, and one goroutine
            per simulation dot. Heap values reflect Go's allocator,
            not OS pages.
          </p>
        </section>
      </div>

      <%!-- Explanation section --%>
      <.explanation />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Explanation section — rendered server-side, fully SEO-visible
  # ---------------------------------------------------------------------------

  defp explanation(assigns) do
    ~H"""
    <section class="explainer" aria-label="How this works">
      <div class="explainer__inner">

        <header class="explainer__header">
          <span class="explainer__eyebrow">// technical notes</span>
          <h2 class="explainer__title">How this works</h2>
          <p class="explainer__lead">
            This is a real Go service running live on the server — not an animation.
            Every dot you see corresponds to an actual goroutine executing concurrently
            inside the Go runtime.
          </p>
        </header>

        <div class="explainer__grid">

          <article class="explainer__card">
            <div class="card__index">01</div>
            <h3 class="card__title">The Simulation</h3>
            <p class="card__body">
              The Go service spawns <code>N</code> goroutines on startup (default: 50).
              Each goroutine owns a dot and waits for a tick signal every 33ms (~30fps).
              On each tick, the dot updates its own position independently — no shared
              state, no central position manager. When two dots collide, a new goroutine
              is spawned at the collision midpoint, growing the simulation organically.
            </p>
          </article>

          <article class="explainer__card">
            <div class="card__index">02</div>
            <h3 class="card__title">Fan-out / Fan-in</h3>
            <p class="card__body">
              The engine uses a classic Go concurrency pattern. Each tick it fans out
              a signal to all dot goroutines via buffered channels, then fans in their
              updated positions. At 1000 dots this means 1000 goroutines executing
              concurrently every 33ms — scheduled across available CPU cores by Go's
              M:N runtime scheduler. You're watching the scheduler work.
            </p>
          </article>

          <article class="explainer__card">
            <div class="card__index">03</div>
            <h3 class="card__title">Memory Graph</h3>
            <p class="card__body">
              The graph plots <code>HeapAlloc</code> from <code>runtime.MemStats</code>,
              sampled every second. As dot count grows, heap allocation rises because
              each goroutine stack starts at 2–8 KB and each dot struct allocates
              channel buffers. The GC cycle counter increments whenever Go's garbage
              collector runs — watch it tick up as allocation pressure increases.
            </p>
          </article>

          <article class="explainer__card">
            <div class="card__index">04</div>
            <h3 class="card__title">Per-Session Isolation</h3>
            <p class="card__body">
              Each browser tab gets a completely independent simulation. When you open
              this page, the Go server creates a fresh engine with its own goroutines.
              When you close the tab, the WebSocket disconnects and every goroutine in
              that session is stopped and garbage collected. Two concurrent visitors
              have zero shared state between them.
            </p>
          </article>

          <article class="explainer__card">
            <div class="card__index">05</div>
            <h3 class="card__title">Collision Cooldown</h3>
            <p class="card__body">
              After a collision, both parent dots and the newly spawned child are marked
              immune for 500ms. Without this, a newly spawned dot starting near its
              parent would immediately re-collide on the next tick, triggering a
              chain reaction that fills the canvas in seconds. The cooldown ensures
              collisions are observable events, not instant cascades.
            </p>
          </article>

          <article class="explainer__card">
            <div class="card__index">06</div>
            <h3 class="card__title">What's Not Measured</h3>
            <p class="card__body">
              <code>HeapAlloc</code> is process-wide, not per-goroutine — Go provides
              no per-goroutine memory attribution. <code>NumGoroutine</code> includes
              the Go runtime's own internal goroutines (~5), the HTTP server, and the
              metrics collector, not just simulation dots. Stack memory is reported
              separately as <code>StackInuse</code>. These are intentional limitations
              of <code>runtime.MemStats</code>, not bugs.
            </p>
          </article>

          <article class="explainer__card">
            <div class="card__index">07</div>
            <h3 class="card__title">Phoenix + LiveView Bridge</h3>
            <p class="card__body">
              The frontend is a Phoenix LiveView application. A JavaScript hook opens
              a direct WebSocket to the Go service at <code>/ws</code>, receives dot
              positions at 30fps, and renders them onto an HTML5 canvas — bypassing
              LiveView's DOM diffing entirely for the hot render path. Memory metrics
              are pushed back to the LiveView server via <code>pushEvent</code> so the
              stat cards are server-rendered and SEO-visible.
            </p>
          </article>

          <article class="explainer__card">
            <div class="card__index">08</div>
            <h3 class="card__title">Tradeoffs &amp; Limits</h3>
            <p class="card__body">
              Collision detection is O(n²) — comparing every dot pair each tick.
              This is intentional: it's fast enough for 1000 dots at 30fps (~500K
              comparisons in under 1ms on modern hardware) and keeps the code simple.
              A spatial hash grid would be the natural next step for 10K+ dots.
              The hard cap of 1000 dots prevents runaway memory growth in production.
            </p>
          </article>

        </div>

        <footer class="explainer__footer">
          <div class="explainer__stack">
            <span class="stack-item">Go 1.22</span>
            <span class="stack-sep">·</span>
            <span class="stack-item">gorilla/websocket</span>
            <span class="stack-sep">·</span>
            <span class="stack-item">Phoenix 1.7</span>
            <span class="stack-sep">·</span>
            <span class="stack-item">LiveView</span>
            <span class="stack-sep">·</span>
            <span class="stack-item">HTML5 Canvas</span>
            <span class="stack-sep">·</span>
            <span class="stack-item">Chart.js</span>
          </div>
        </footer>

      </div>
    </section>
    """
  end

  defp format_kb(kb) when kb >= 1024, do: "#{Float.round(kb / 1024, 1)} MB"
  defp format_kb(kb), do: "#{kb} KB"
end
