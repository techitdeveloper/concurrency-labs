// assets/js/hooks/elixir_lab.js

const CANVAS_W = 1000;
const CANVAS_H = 600;
const DOT_RADIUS = 6;
const GLOW_RADIUS = 14;
const CHART_MAX_POINTS = 60;
const DEATH_FADE_MS = 800;
const RESTART_FADE_MS = 600;

const C = {
  bg:          "#09080f",
  alive_core1: "#c4b5fd",
  alive_core2: "#7c3aed",
  alive_glow:  "rgba(167, 139, 250, 0.18)",
  dead_core:   "#ef4444",
  dead_glow:   "rgba(239, 68, 68, 0.15)",
  grid:        "rgba(255,255,255,0.02)",
};

// ---------------------------------------------------------------------------
// ElixirSimulation hook
// ---------------------------------------------------------------------------
export const ElixirSimulation = {
  mounted() {
    this.canvas = this.el.querySelector("#elixir-canvas");
    if (!this.canvas) { console.error("[ElixirSimulation] canvas not found"); return; }

    this.canvas.width = CANVAS_W;
    this.canvas.height = CANVAS_H;
    this.ctx = this.canvas.getContext("2d");
    this.particles = new Map(); // id → particle state
    this.animFrame = null;

    // Batched positions: {positions: {"id": [x, y], ...}}
    this.handleEvent("positions_batch", ({ positions }) => {
      for (const [idStr, pos] of Object.entries(positions)) {
        const id = parseInt(idStr);
        const [x, y] = pos;
        const existing = this.particles.get(id);

        // Don't overwrite a dying particle with stale position
        if (existing?.state === "dying") continue;

        if (existing) {
          existing.x = x;
          existing.y = y;
          if (existing.state === "restarting" || existing.state === "alive") {
            // keep state as-is, just update coords
          }
        } else {
          this.particles.set(id, {
            id, x, y,
            state: "alive",
            alpha: 1.0,
            fadeStart: null,
          });
        }
      }
    });

    this.handleEvent("particle_dying", ({ id }) => {
      const p = this.particles.get(id);
      if (!p) {
        // Create a dying ghost even if we haven't seen this particle before
        this.particles.set(id, { id, x: 0, y: 0, state: "dying", alpha: 1.0, fadeStart: performance.now() });
        return;
      }
      p.state = "dying";
      p.fadeStart = performance.now();
      p.alpha = 1.0;
    });

    this.handleEvent("particle_restarted", ({ id }) => {
      const existing = this.particles.get(id);
      this.particles.set(id, {
        id,
        x: existing?.x ?? Math.random() * CANVAS_W,
        y: existing?.y ?? Math.random() * CANVAS_H,
        state: "restarting",
        alpha: 0.0,
        fadeStart: performance.now(),
      });
    });

    this.handleEvent("reset_particles", () => this.particles.clear());

    this._startRenderLoop();
  },

  destroyed() {
    if (this.animFrame) cancelAnimationFrame(this.animFrame);
  },

  _startRenderLoop() {
    const draw = (now) => {
      this._drawFrame(now);
      this.animFrame = requestAnimationFrame(draw);
    };
    this.animFrame = requestAnimationFrame(draw);
  },

  _drawFrame(now) {
    const ctx = this.ctx;
    ctx.fillStyle = C.bg;
    ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);

    // Grid
    ctx.strokeStyle = C.grid;
    ctx.lineWidth = 1;
    for (let x = 0; x <= CANVAS_W; x += 100) {
      ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, CANVAS_H); ctx.stroke();
    }
    for (let y = 0; y <= CANVAS_H; y += 75) {
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(CANVAS_W, y); ctx.stroke();
    }

    const toDelete = [];
    for (const [id, p] of this.particles) {
      const alpha = this._updateAlpha(p, now);
      if (alpha <= 0 && p.state === "dying") { toDelete.push(id); continue; }
      this._drawParticle(ctx, p, alpha);
    }
    for (const id of toDelete) this.particles.delete(id);
  },

  _updateAlpha(p, now) {
    if (p.state === "alive") return 1.0;
    if (!p.fadeStart) return p.alpha ?? 1.0;

    const elapsed = now - p.fadeStart;
    const duration = p.state === "dying" ? DEATH_FADE_MS : RESTART_FADE_MS;
    const t = Math.min(elapsed / duration, 1.0);

    if (p.state === "dying") {
      p.alpha = 1.0 - t;
    } else {
      p.alpha = t;
      if (t >= 1.0) { p.state = "alive"; p.fadeStart = null; }
    }
    return p.alpha;
  },

  _drawParticle(ctx, p, alpha) {
    if (alpha <= 0 || !p.x) return;
    const isDead = p.state === "dying";
    const x = p.x, y = p.y;

    ctx.globalAlpha = alpha;

    const glow = ctx.createRadialGradient(x, y, 0, x, y, GLOW_RADIUS);
    glow.addColorStop(0, isDead ? C.dead_glow : C.alive_glow);
    glow.addColorStop(1, "rgba(0,0,0,0)");
    ctx.beginPath();
    ctx.arc(x, y, GLOW_RADIUS, 0, Math.PI * 2);
    ctx.fillStyle = glow;
    ctx.fill();

    const core = ctx.createRadialGradient(
      x - DOT_RADIUS * 0.3, y - DOT_RADIUS * 0.3, 0,
      x, y, DOT_RADIUS
    );
    if (isDead) {
      core.addColorStop(0, "#fca5a5");
      core.addColorStop(1, C.dead_core);
    } else {
      core.addColorStop(0, C.alive_core1);
      core.addColorStop(1, C.alive_core2);
    }
    ctx.beginPath();
    ctx.arc(x, y, DOT_RADIUS, 0, Math.PI * 2);
    ctx.fillStyle = core;
    ctx.fill();

    ctx.globalAlpha = 1.0;
  },
};

// ---------------------------------------------------------------------------
// ElixirMemoryChart — dual line: total + avg per process
// ---------------------------------------------------------------------------
export const ElixirMemoryChart = {
  mounted() {
    this._labels = [];
    this._totalData = [];
    this._avgData = [];
    this._chart = null;
    this._waitForChartJs(() => { this._chart = this._buildChart(); });
    this.handleEvent("metrics_update", (p) => this._onSample(p));
  },

  destroyed() {
    if (this._chart) this._chart.destroy();
  },

  _waitForChartJs(cb, n = 0) {
    if (typeof Chart !== "undefined") cb();
    else if (n < 30) setTimeout(() => this._waitForChartJs(cb, n + 1), 100);
  },

  _onSample(p) {
    this._labels.push(new Date(p.timestamp_ms).toLocaleTimeString());
    this._totalData.push(p.total_sim_memory_kb);
    this._avgData.push(+(p.avg_memory_bytes / 1024).toFixed(2));

    if (this._labels.length > CHART_MAX_POINTS) {
      this._labels.shift(); this._totalData.shift(); this._avgData.shift();
    }

    if (this._chart) {
      this._chart.data.labels = this._labels;
      this._chart.data.datasets[0].data = this._totalData;
      this._chart.data.datasets[1].data = this._avgData;
      this._chart.update("none");
    }
  },

  _buildChart() {
    return new Chart(this.el, {
      type: "line",
      data: {
        labels: [],
        datasets: [
          {
            label: "Total (KB)",
            data: [],
            borderColor: "#a78bfa",
            backgroundColor: "rgba(167,139,250,0.07)",
            borderWidth: 2,
            pointRadius: 0,
            tension: 0.4,
            fill: true,
            yAxisID: "y",
          },
          {
            label: "Avg/process (KB)",
            data: [],
            borderColor: "#34d399",
            backgroundColor: "rgba(52,211,153,0.05)",
            borderWidth: 1.5,
            pointRadius: 0,
            tension: 0.4,
            fill: false,
            borderDash: [4, 3],
            yAxisID: "y2",
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        interaction: { mode: "index", intersect: false },
        plugins: {
          legend: {
            display: true,
            position: "top",
            labels: { color: "#6b6b8a", font: { family: "JetBrains Mono, monospace", size: 10 }, boxWidth: 12, padding: 12 },
          },
          tooltip: { backgroundColor: "#1a0f2e", titleColor: "#a78bfa", bodyColor: "#e0e0e0", borderColor: "#a78bfa", borderWidth: 1 },
        },
        scales: {
          x: {
            ticks: { color: "#555", maxTicksLimit: 6, font: { family: "JetBrains Mono, monospace", size: 10 } },
            grid: { color: "rgba(255,255,255,0.04)" },
          },
          y: {
            position: "left",
            beginAtZero: true,
            ticks: { color: "#a78bfa", font: { family: "JetBrains Mono, monospace", size: 10 }, callback: v => `${v}KB` },
            grid: { color: "rgba(255,255,255,0.04)" },
            title: { display: true, text: "Total", color: "#a78bfa", font: { size: 9 } },
          },
          y2: {
            position: "right",
            beginAtZero: true,
            ticks: { color: "#34d399", font: { family: "JetBrains Mono, monospace", size: 10 }, callback: v => `${v}KB` },
            grid: { drawOnChartArea: false },
            title: { display: true, text: "Avg/proc", color: "#34d399", font: { size: 9 } },
          },
        },
      },
    });
  },
};