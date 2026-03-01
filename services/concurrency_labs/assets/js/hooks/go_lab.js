// assets/js/hooks/go_lab.js

const CANVAS_W = 1000;
const CANVAS_H = 750;
const DOT_RADIUS = 6;
const GLOW_RADIUS = 12;

const CHART_MAX_POINTS = 60;

// ---------------------------------------------------------------------------
// GoSimulation hook
// Mounted on #go-sim-hook (the outer, LiveView-managed div).
// The canvas and overlay live inside #go-sim-canvas-area (phx-update="ignore"),
// which is a child of this.el — so querySelector still works fine.
// ---------------------------------------------------------------------------
export const GoSimulation = {
  mounted() {
    // this.el = #go-sim-hook
    // querySelector searches all descendants, including the ignored subtree
    this.canvas = this.el.querySelector("#sim-canvas");
    this.overlay = this.el.querySelector("#canvas-overlay");

    if (!this.canvas) {
      console.error("[GoSimulation] #sim-canvas not found");
      return;
    }

    this.canvas.width = CANVAS_W;
    this.canvas.height = CANVAS_H;
    this.ctx = this.canvas.getContext("2d");

    this.dots = [];
    this.animFrame = null;
    this.ws = null;
    this._frameCount = 0;

    // Read the WS URL once from the attribute — LiveView may patch this
    // attribute later but we don't re-read it, so no reconnect storms.
    this._wsUrl = this.el.dataset.wsUrl;

    this.handleEvent("go_command", (cmd) => this._sendToGo(cmd));

    this._connectWS();
    this._startRenderLoop();
  },

  destroyed() {
    if (this.ws) {
      this.ws.onclose = null; // suppress retry loop on intentional teardown
      this.ws.close();
    }
    if (this.animFrame) cancelAnimationFrame(this.animFrame);
    if (this._retryTimer) clearTimeout(this._retryTimer);
  },

  _connectWS() {
    if (!this._wsUrl) {
      console.error("[GoSimulation] data-ws-url missing");
      return;
    }

    this.ws = new WebSocket(this._wsUrl);

    this.ws.onopen = () => {
      console.log("[GoSimulation] connected ->", this._wsUrl);
      this._setOverlay(false);
      this.pushEvent("connection_status", { connected: true });
    };

    this.ws.onclose = (e) => {
      console.warn("[GoSimulation] closed (code:", e.code, ") — retry in 3s");
      this._setOverlay(true, "Disconnected — retrying in 3s…");
      this.pushEvent("connection_status", { connected: false });
      this._retryTimer = setTimeout(() => this._connectWS(), 3000);
    };

    this.ws.onerror = () => {};

    this.ws.onmessage = (event) => {
      try {
        this._handleServerMessage(JSON.parse(event.data));
      } catch (e) {
        console.error("[GoSimulation] parse error:", e);
      }
    };
  },

  _sendToGo(cmd) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(cmd));
    }
  },

  _handleServerMessage(msg) {
    switch (msg.kind) {
      case "simulation_state":
        this.dots = msg.payload.dots;
        if (++this._frameCount % 10 === 0) {
          this.pushEvent("dot_count_update", { count: msg.payload.count });
        }
        break;

      case "metrics":
        this.pushEvent("metrics_update", msg.payload);
        document.dispatchEvent(
          new CustomEvent("memory_sample", { detail: msg.payload })
        );
        break;

      default:
        console.warn("[GoSimulation] unknown kind:", msg.kind);
    }
  },

  _startRenderLoop() {
    const draw = () => {
      this._drawFrame();
      this.animFrame = requestAnimationFrame(draw);
    };
    this.animFrame = requestAnimationFrame(draw);
  },

  _drawFrame() {
    const ctx = this.ctx;
    if (!ctx) return;

    ctx.fillStyle = "#0a0a0f";
    ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);

    ctx.strokeStyle = "rgba(255,255,255,0.025)";
    ctx.lineWidth = 1;
    for (let x = 0; x <= CANVAS_W; x += 100) {
      ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, CANVAS_H); ctx.stroke();
    }
    for (let y = 0; y <= CANVAS_H; y += 75) {
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(CANVAS_W, y); ctx.stroke();
    }

    for (const dot of this.dots) {
      this._drawDot(ctx, dot);
    }
  },

  _drawDot(ctx, dot) {
    const x = dot.x, y = dot.y;

    const glow = ctx.createRadialGradient(x, y, 0, x, y, GLOW_RADIUS);
    glow.addColorStop(0, "rgba(0, 210, 255, 0.18)");
    glow.addColorStop(1, "rgba(0, 210, 255, 0)");
    ctx.beginPath();
    ctx.arc(x, y, GLOW_RADIUS, 0, Math.PI * 2);
    ctx.fillStyle = glow;
    ctx.fill();

    const core = ctx.createRadialGradient(
      x - DOT_RADIUS * 0.3, y - DOT_RADIUS * 0.3, 0,
      x, y, DOT_RADIUS
    );
    core.addColorStop(0, "#a8f0ff");
    core.addColorStop(0.5, "#00d2ff");
    core.addColorStop(1, "#0090b8");
    ctx.beginPath();
    ctx.arc(x, y, DOT_RADIUS, 0, Math.PI * 2);
    ctx.fillStyle = core;
    ctx.fill();
  },

  _setOverlay(visible, msg = "Connecting to Go runtime…") {
    if (!this.overlay) return;
    this.overlay.style.display = visible ? "flex" : "none";
    if (visible) this.overlay.textContent = msg;
  },
};

// ---------------------------------------------------------------------------
// MemoryChart hook
// ---------------------------------------------------------------------------
export const MemoryChart = {
  mounted() {
    this._labels = [];
    this._heapData = [];
    this._chart = null;

    this._waitForChartJs(() => { this._chart = this._buildChart(); });

    this._listener = (e) => this._onSample(e.detail);
    document.addEventListener("memory_sample", this._listener);
  },

  destroyed() {
    document.removeEventListener("memory_sample", this._listener);
    if (this._chart) this._chart.destroy();
  },

  _waitForChartJs(cb, attempts = 0) {
    if (typeof Chart !== "undefined") {
      cb();
    } else if (attempts < 30) {
      setTimeout(() => this._waitForChartJs(cb, attempts + 1), 100);
    } else {
      console.error("[MemoryChart] Chart.js not loaded after 3s");
    }
  },

  _onSample(payload) {
    this._labels.push(new Date(payload.timestamp_ms).toLocaleTimeString());
    this._heapData.push(payload.heap_alloc_kb);

    if (this._labels.length > CHART_MAX_POINTS) {
      this._labels.shift();
      this._heapData.shift();
    }

    if (this._chart) {
      this._chart.data.labels = this._labels;
      this._chart.data.datasets[0].data = this._heapData;
      this._chart.update("none");
    }
  },

  _buildChart() {
    return new Chart(this.el, {
      type: "line",
      data: {
        labels: [],
        datasets: [{
          label: "Heap Alloc (KB)",
          data: [],
          borderColor: "#00d2ff",
          backgroundColor: "rgba(0, 210, 255, 0.07)",
          borderWidth: 2,
          pointRadius: 0,
          tension: 0.4,
          fill: true,
        }],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            mode: "index",
            intersect: false,
            backgroundColor: "#1a1a2e",
            titleColor: "#7df9ff",
            bodyColor: "#e0e0e0",
            borderColor: "#00d2ff",
            borderWidth: 1,
          },
        },
        scales: {
          x: {
            ticks: { color: "#555", maxTicksLimit: 6, font: { family: "JetBrains Mono, monospace", size: 10 } },
            grid: { color: "rgba(255,255,255,0.04)" },
          },
          y: {
            beginAtZero: false,
            ticks: { color: "#555", font: { family: "JetBrains Mono, monospace", size: 10 }, callback: (v) => `${v} KB` },
            grid: { color: "rgba(255,255,255,0.04)" },
          },
        },
      },
    });
  },
};