package transport

// Server → client message kinds
const (
	KindSimulationState = "simulation_state"
	KindMetrics         = "metrics"
	KindError           = "error"
)

// Client → server message kinds
const (
	KindSpawnDot = "spawn_dot"
	KindReset    = "reset"
)

type ServerMessage struct {
	Kind    string      `json:"kind"`
	Payload interface{} `json:"payload"`
}

type ClientMessage struct {
	Kind string `json:"kind"`
}

// SimulationPayload — Dots is []DotState, not interface{} or []*Dot,
// so json.Marshal always produces the correct coordinate fields.
type SimulationPayload struct {
	Dots  interface{} `json:"dots"`
	Count int         `json:"count"`
}

type MetricsPayload struct {
	TimestampMs  int64  `json:"timestamp_ms"`
	HeapAllocKB  uint64 `json:"heap_alloc_kb"`
	HeapSysKB    uint64 `json:"heap_sys_kb"`
	StackInuseKB uint64 `json:"stack_inuse_kb"`
	NumGoroutine int    `json:"num_goroutine"`
	NumGCCycles  uint32 `json:"num_gc_cycles"`
}
