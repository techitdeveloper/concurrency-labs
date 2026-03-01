package metrics

import (
	"runtime"
	"sync"
	"time"
)

// Sample holds a point-in-time snapshot of Go runtime memory.
// All values are in bytes unless noted.
type Sample struct {
	Timestamp    int64  `json:"timestamp_ms"` // Unix milliseconds
	HeapAlloc    uint64 `json:"heap_alloc"`   // bytes currently allocated on the heap
	HeapSys      uint64 `json:"heap_sys"`     // bytes obtained from the OS for the heap
	StackInuse   uint64 `json:"stack_inuse"`  // bytes used by goroutine stacks
	NumGoroutine int    `json:"num_goroutine"`
	NumGCCycles  uint32 `json:"num_gc_cycles"`
}

// Collector periodically samples runtime.MemStats and broadcasts them.
type Collector struct {
	mu       sync.RWMutex
	latest   Sample
	interval time.Duration
	stop     chan struct{}
	Updates  chan Sample
}

// NewCollector creates a collector with the given sampling interval.
func NewCollector(interval time.Duration) *Collector {
	return &Collector{
		interval: interval,
		stop:     make(chan struct{}),
		Updates:  make(chan Sample, 1),
	}
}

// Start launches the sampling loop. Call once.
func (c *Collector) Start() {
	go c.loop()
}

// Stop shuts the collector down cleanly.
func (c *Collector) Stop() {
	close(c.stop)
}

// Latest returns the most recent sample (safe for concurrent reads).
func (c *Collector) Latest() Sample {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.latest
}

// --- internal ---

func (c *Collector) loop() {
	ticker := time.NewTicker(c.interval)
	defer ticker.Stop()

	for {
		select {
		case <-c.stop:
			return
		case <-ticker.C:
			s := c.collect()

			c.mu.Lock()
			c.latest = s
			c.mu.Unlock()

			// Non-blocking send — drop if consumer is behind
			select {
			case c.Updates <- s:
			default:
			}
		}
	}
}

func (c *Collector) collect() Sample {
	var ms runtime.MemStats
	runtime.ReadMemStats(&ms)

	return Sample{
		Timestamp:    time.Now().UnixMilli(),
		HeapAlloc:    ms.HeapAlloc,
		HeapSys:      ms.HeapSys,
		StackInuse:   ms.StackInuse,
		NumGoroutine: runtime.NumGoroutine(),
		NumGCCycles:  ms.NumGC,
	}
}
