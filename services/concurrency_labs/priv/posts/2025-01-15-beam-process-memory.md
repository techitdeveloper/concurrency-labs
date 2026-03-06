%{
  title: "BEAM Process Memory: What the Numbers Actually Mean",
  date: "2025-01-15",
  description: "A hands-on look at how BEAM measures per-process memory, why the numbers surprise most developers, and what they mean for production systems.",
  tags: ["elixir", "beam", "memory"]
}
---

Every BEAM process gets its own heap. That's the sentence that makes Elixir different
from nearly every other concurrent runtime — and it has real consequences for how you
reason about memory in production.

## What `:erlang.process_info/2` actually returns

When you call `:erlang.process_info(pid, :memory)`, you get back a number in **words**,
not bytes. On a 64-bit system, one word is 8 bytes:

```elixir
pid = spawn(fn -> receive do _ -> :ok end end)
{:memory, words} = :erlang.process_info(pid, :memory)
bytes = words * :erlang.system_info(:wordsize)
```

A freshly spawned process with no state uses roughly **2–3 KB**. That sounds small —
and it is. This is the core of the BEAM story.

## Why per-process GC matters

In a shared-heap runtime like the JVM, a GC pause stops every thread. The more threads
you have, the more work the GC does. BEAM is different: each process has its own heap
and its own GC cycle. A busy process doesn't pause a quiet one.

The practical consequence: **you can run hundreds of thousands of processes without
coordinating memory across them**. Each process pays only for its own work.

## What the stress test shows

In the [Elixir Lab](/elixir-concurrency), hitting *Stress Test (500)* spawns 500
GenServers. Watch the **Avg / Process** metric — it stays flat around 2–3 KB while
the total climbs linearly. That's the BEAM story in one number.

| Count | Avg / process | Total |
|-------|--------------|-------|
| 10    | ~2.4 KB      | ~24 KB |
| 100   | ~2.4 KB      | ~240 KB |
| 500   | ~2.4 KB      | ~1.2 MB |

Linear scaling, constant per-unit cost.

## What the number doesn't tell you

The `:memory` figure includes the process stack, heap, and internal bookkeeping.
It does **not** include binaries larger than 64 bytes — those live on a shared binary
heap and are reference-counted separately. If your process handles large binaries,
`process_info(pid, :binary)` gives you a closer picture.

## Takeaway

Per-process memory in BEAM is small, predictable, and isolated. If you're coming from
a thread-based model, the instinct is to worry about spawning too many processes.
The numbers say otherwise.