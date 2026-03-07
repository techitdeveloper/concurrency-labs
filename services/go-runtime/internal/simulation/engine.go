package simulation

import (
	"sync"
	"time"
)

// EngineConfig holds simulation-level knobs.
// Populated from config.Config by the caller (transport layer).
type EngineConfig struct {
	MaxDots      int
	TickInterval time.Duration
	Dot          DotConfig
}

// StateSnapshot is what gets broadcast to the WebSocket client every tick.
// It uses DotState (plain value, no mutex, proper json tags) — never *Dot.
type StateSnapshot struct {
	Dots  []DotState `json:"dots"`
	Count int        `json:"count"`
}

// Engine runs the simulation for a single session.
type Engine struct {
	cfg    EngineConfig
	mu     sync.Mutex
	dots   []*Dot
	nextID float64

	ticker   *time.Ticker
	stopLoop chan struct{}
	Updates  chan StateSnapshot
}

func NewEngine(initialCount int, cfg EngineConfig) *Engine {
	e := &Engine{
		cfg:      cfg,
		stopLoop: make(chan struct{}),
		Updates:  make(chan StateSnapshot, 1),
	}
	for i := 0; i < initialCount; i++ {
		e.addDot()
	}
	return e
}

func (e *Engine) Start() {
	e.ticker = time.NewTicker(e.cfg.TickInterval)
	e.mu.Lock()
	for _, d := range e.dots {
		d.Start()
	}
	e.mu.Unlock()
	go e.loop()
}

func (e *Engine) Stop() {
	close(e.stopLoop)
	if e.ticker != nil {
		e.ticker.Stop()
	}
	e.mu.Lock()
	for _, d := range e.dots {
		d.Stop()
	}
	e.mu.Unlock()
}

func (e *Engine) SpawnDot() {
	e.mu.Lock()
	defer e.mu.Unlock()
	if len(e.dots) >= e.cfg.MaxDots {
		return
	}
	d := e.addDot()
	d.Start()
}

func (e *Engine) Reset(initialCount int) {
	e.mu.Lock()
	for _, d := range e.dots {
		d.Stop()
	}
	e.dots = nil
	e.nextID = 0
	for i := 0; i < initialCount; i++ {
		e.addDot()
	}
	newDots := make([]*Dot, len(e.dots))
	copy(newDots, e.dots)
	e.mu.Unlock()

	for _, d := range newDots {
		d.Start()
	}
}

func (e *Engine) DotCount() int {
	e.mu.Lock()
	defer e.mu.Unlock()
	return len(e.dots)
}

func (e *Engine) addDot() *Dot {
	d := NewDot(e.nextID, e.cfg.Dot)
	e.nextID++
	e.dots = append(e.dots, d)
	return d
}

func (e *Engine) loop() {
	for {
		select {
		case <-e.stopLoop:
			return
		case <-e.ticker.C:
			e.tick()
		}
	}
}

func (e *Engine) tick() {
	e.mu.Lock()
	dots := make([]*Dot, len(e.dots))
	copy(dots, e.dots)
	e.mu.Unlock()

	// Fan-out
	for _, d := range dots {
		select {
		case d.tickCh <- struct{}{}:
		default:
		}
	}

	// Fan-in
	now := time.Now()
	updated := make([]DotState, 0, len(dots))
	for _, d := range dots {
		select {
		case pos := <-d.posCh:
			updated = append(updated, pos)
		default:
			d.mu.Lock()
			updated = append(updated, DotState{
				ID:             d.ID,
				X:              d.X,
				Y:              d.Y,
				VX:             d.VX,
				VY:             d.VY,
				CollisionUntil: d.CollisionUntil,
			})
			d.mu.Unlock()
		}
	}

	// Collision detection
	type spawnPoint struct{ x, y float64 }
	var toSpawn []spawnPoint
	collided := make(map[float64]bool, len(updated))
	r := e.cfg.Dot.Radius
	collisionDistSq := (r * 2) * (r * 2)

	for i := 0; i < len(updated); i++ {
		for j := i + 1; j < len(updated); j++ {
			a, b := &updated[i], &updated[j]
			if collided[a.ID] || collided[b.ID] {
				continue
			}
			if now.Before(a.CollisionUntil) || now.Before(b.CollisionUntil) {
				continue
			}
			dx := a.X - b.X
			dy := a.Y - b.Y
			if dx*dx+dy*dy < collisionDistSq {
				collided[a.ID] = true
				collided[b.ID] = true
				toSpawn = append(toSpawn, spawnPoint{
					x: (a.X + b.X) / 2,
					y: (a.Y + b.Y) / 2,
				})
			}
		}
	}

	// Write back + spawn
	e.mu.Lock()

	posMap := make(map[float64]*DotState, len(updated))
	for i := range updated {
		posMap[updated[i].ID] = &updated[i]
	}
	for _, d := range e.dots {
		if u, ok := posMap[d.ID]; ok {
			d.X, d.Y, d.VX, d.VY = u.X, u.Y, u.VX, u.VY
			if collided[d.ID] {
				d.CollisionUntil = now.Add(e.cfg.Dot.CollisionCooldown)
			}
		}
	}

	countBefore := len(e.dots)
	var newDots []*Dot
	for i, sp := range toSpawn {
		if countBefore+i >= e.cfg.MaxDots {
			break
		}
		d := NewDotAt(e.nextID, sp.x, sp.y, e.cfg.Dot)
		e.nextID++
		e.dots = append(e.dots, d)
		newDots = append(newDots, d)
	}

	snapshot := e.buildSnapshot()
	e.mu.Unlock()

	for _, d := range newDots {
		d.Start()
	}

	select {
	case e.Updates <- snapshot:
	default:
	}
}

// buildSnapshot converts dots to DotState slices for JSON serialization.
// DotState has no sync.Mutex — safe to marshal. *Dot is never sent over the wire.
func (e *Engine) buildSnapshot() StateSnapshot {
	states := make([]DotState, len(e.dots))
	for i, d := range e.dots {
		states[i] = DotState{
			ID: d.ID,
			X:  d.X,
			Y:  d.Y,
			VX: d.VX,
			VY: d.VY,
		}
	}
	return StateSnapshot{Dots: states, Count: len(states)}
}
