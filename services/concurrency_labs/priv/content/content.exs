# priv/content/content.exs
#
# Single source of truth for all page copy.
# Edit this file. Recompile + redeploy. Never touch templates for copy changes.

%{
  hero: %{
    kicker: "live concurrency experiments",
    headline: ["Processes.", "Goroutines.", "Real behavior."],
    headline_accent: "Real behavior.",
    subheadline: """
    Interactive labs that show how BEAM and Go handle concurrency
    at runtime — supervision, memory, scheduling. Not slides. Not diagrams.
    Running code you can interact with.
    """
  },

  hero_stats: [
    %{value: "500",   label: "max GenServers"},
    %{value: "500", label: "max goroutines"},
    %{value: "30fps", label: "live metrics"}
  ],

  what_this_is: %{
    title: "Engineering proof, not a résumé",
    paragraphs: [
      """
      Most portfolio sites list technologies. This one runs them.
      Each lab spawns real supervised processes or goroutines on the server —
      you're watching the BEAM scheduler and Go runtime work, not a
      pre-recorded animation.
      """,
      """
      The Elixir lab demonstrates OTP supervision: kill half the processes,
      watch the supervisor rebuild the system. The Go lab shows goroutine
      fan-out and heap growth under real concurrency load. Both expose
      runtime memory metrics live.
      """,
      """
      The goal is not to teach syntax. It's to show runtime behavior —
      the part that matters in production and the part most engineers
      never see until something breaks.
      """
    ]
  },

  labs: %{
    elixir: %{
      badge: "BEAM / OTP",
      title: "Supervised GenServers",
      link_text: "Elixir Concurrency Lab →",
      points: [
        "How BEAM isolates each process on its own heap",
        "Why a crash in one process cannot corrupt another's memory",
        "How :one_for_one supervision rebuilds the system without touching live processes",
        "Why per-process memory stays flat at ~2–3 KB regardless of count",
        "What 500 concurrent GenServers actually costs in memory"
      ]
    },
    go: %{
      badge: "GO RUNTIME",
      title: "Goroutine Scheduling",
      link_text: "Go Concurrency Lab →",
      points: [
        "How Go's M:N scheduler distributes goroutines across CPU cores",
        "Why goroutine stacks start at 2–8 KB and grow on demand",
        "How heap allocation responds to concurrent load in real time",
        "What runtime.MemStats actually measures and what it misses",
        "Where BEAM's fault isolation model differs fundamentally from Go's"
      ]
    }
  },

  work: [
    %{
      index: "01",
      title: "High-value transaction processing",
      constraint: "Millions of dollars processed daily",
      description: """
      Built the core transaction pipeline in Elixir/OTP handling financial
      operations where consistency and auditability were non-negotiable.
      Designed the supervision tree to guarantee no transaction was silently
      dropped on process crash. Implemented idempotency at the message level
      to survive network retries without double-processing.
      """,
      what_i_owned: "Architecture, supervision design, failure recovery",
      stack: ["Elixir", "OTP", "PostgreSQL", "GenStage"]
    },
    %{
      index: "02",
      title: "Real-time multiplayer backend",
      constraint: "Thousands of concurrent users, sub-100ms state sync",
      description: """
      Designed and built the game state synchronization backend in Go,
      handling thousands of simultaneous WebSocket connections with shared
      mutable state. Used a sharded actor model to eliminate lock contention
      at scale. Built the fan-out layer that pushed state deltas to connected
      clients without broadcasting full state on every tick.
      """,
      what_i_owned: "Concurrency model, state sync protocol, load testing",
      stack: ["Go", "WebSockets", "Redis", "Protocol Buffers"]
    },
    %{
      index: "03",
      title: "Event-driven data pipeline",
      constraint: "High-throughput, ordered processing with back-pressure",
      description: """
      Built a multi-stage data pipeline using GenStage and Broadway that
      consumed from Kafka, applied transformations, and wrote to multiple
      downstream systems. Designed the back-pressure model so slow consumers
      slowed producers instead of accumulating unbounded queues.
      """,
      what_i_owned: "Pipeline architecture, back-pressure tuning, observability",
      stack: ["Elixir", "Broadway", "Kafka", "GenStage"]
    }
  ],

  about: %{
    contact_email: "indreeshpandey@gmail.com",
    summary: [
      """
      Backend engineer with 5+ years building concurrent, fault-tolerant
      systems in Elixir and Go. Work spans financial transaction pipelines,
      real-time multiplayer backends, and distributed data systems — all at
      production scale with real consequences for failure.
      """,
      """
      Open to senior backend, systems, or infrastructure roles. Particularly
      interested in teams working with Elixir/OTP, Go, or anyone who cares
      about how their runtime actually behaves under load.
      """
    ],
    links: [
      %{label: "GitHub",  href: "https://github.com/techitdeveloper/concurrency-labs", external: true},
      # %{label: "Email",   href: "mailto:indreeshpandey@gmail.com",                      external: true},
      %{label: "Hire Me", href: "/hire",                                                external: false, primary: true}
    ]
  },

  # ---------------------------------------------------------------------------
  # /hire page content
  # ---------------------------------------------------------------------------
  hire: %{
    headline: "Available for backend roles",
    positioning: "I build concurrent, fault-tolerant backend systems in Elixir and Go — the kind where correctness under load is not optional.",

    can_help_with: [
      %{
        area: "Concurrent system design",
        detail: "Designing systems where thousands of operations run simultaneously without corrupting shared state — using OTP supervision trees, Go channel patterns, or hybrid architectures."
      },
      %{
        area: "Fault-tolerant backends",
        detail: "Building services that recover from partial failure automatically. Process supervision, circuit breakers, retry semantics, and graceful degradation baked in from the start."
      },
      %{
        area: "High-throughput data pipelines",
        detail: "Event-driven pipelines with back-pressure, ordered processing guarantees, and observability — built on GenStage, Broadway, or Go worker pools."
      },
      %{
        area: "Real-time systems",
        detail: "WebSocket backends, pub/sub architectures, and state synchronization for systems where latency is a product requirement, not an afterthought."
      },
      %{
        area: "Performance & runtime analysis",
        detail: "Diagnosing memory growth, scheduler contention, GC pressure, and throughput bottlenecks at the runtime level — not just profiling the application layer."
      },
      %{
        area: "Architecture & technical ownership",
        detail: "Owning architecture decisions end-to-end: modeling failure modes, choosing tradeoffs explicitly, and documenting decisions clearly for the team."
      }
    ],

    experience: %{
      years: "5+",
      summary: "Production backend work across financial systems, real-time platforms, and distributed data infrastructure. Have owned architecture decisions, led technical migrations, and shipped systems under real production constraints.",
      highlights: [
        "Designed transaction pipelines processing millions of dollars daily in Elixir/OTP",
        "Built real-time multiplayer backends handling thousands of concurrent WebSocket connections in Go",
        "Implemented high-throughput event pipelines with back-pressure using GenStage and Broadway",
        "Worked across the full backend: protocol design, runtime tuning, deployment, observability",
        "Comfortable in codebases I didn't start — reading, understanding, and improving existing systems"
      ]
    },

    skills: [
      %{category: "Languages",              items: ["Elixir", "Go", "SQL"]},
      %{category: "Runtimes & Frameworks",  items: ["OTP / BEAM", "Phoenix", "LiveView", "GenStage", "Broadway"]},
      %{category: "Concurrency",            items: ["GenServer", "DynamicSupervisor", "goroutines", "channels", "worker pools"]},
      %{category: "Infrastructure",         items: ["PostgreSQL", "Redis", "Kafka", "Docker", "Fly.io"]},
      %{category: "Practices",              items: ["Event-driven architecture", "back-pressure design", "failure modeling", "runtime observability"]}
    ],

    availability: %{
      status: "open", #"open" to "limited" or "unavailable"
      label: "Available now",
      detail: "Open to full-time remote/on-site roles. Can discuss contract engagements for well-scoped projects.",
      preference: "Strong preference for teams using Elixir/OTP or Go in production."
    },

    contact: %{
      email: "indreeshpandey@gmail.com",
      github: "https://github.com/techitdeveloper",
      resume: "https://docs.google.com/document/d/17WIUmFZvqxzzVw6xhK5B5-i-SJPrw1MR6OiCXmUENTY/edit?usp=drive_link"
    }
  }
}
