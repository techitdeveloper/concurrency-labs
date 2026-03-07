package simulation

import (
	"math"
	"math/rand"
	"sync"
	"time"
)

// DotConfig holds the physics parameters for dots.
// The Engine populates this from config.Config so no magic numbers live here.
type DotConfig struct {
	Radius            float64
	CanvasWidth       float64
	CanvasHeight      float64
	MinSpeed          float64
	MaxSpeed          float64
	CollisionCooldown time.Duration
	SpawnOffsetMult   float64
}

// DotState is the serializable snapshot of a dot's position.
// This — not *Dot — is what gets JSON-encoded and sent to the browser.
// Keeping it separate from Dot means sync.Mutex never touches the wire.
type DotState struct {
	ID             float64   `json:"id"`
	X              float64   `json:"x"`
	Y              float64   `json:"y"`
	VX             float64   `json:"vx"`
	VY             float64   `json:"vy"`
	CollisionUntil time.Time `json:"-"`
}

// Dot is the live simulation object. Never JSON-encoded directly.
type Dot struct {
	mu  sync.Mutex
	cfg DotConfig

	ID             float64
	X              float64
	Y              float64
	VX             float64
	VY             float64
	CollisionUntil time.Time

	tickCh chan struct{}
	posCh  chan DotState
	stopCh chan struct{}
}

func NewDot(id float64, cfg DotConfig) *Dot {
	x := cfg.Radius + rand.Float64()*(cfg.CanvasWidth-2*cfg.Radius)
	y := cfg.Radius + rand.Float64()*(cfg.CanvasHeight-2*cfg.Radius)
	return newDot(id, x, y, cfg)
}

func NewDotAt(id float64, x, y float64, cfg DotConfig) *Dot {
	angle := rand.Float64() * 2 * math.Pi
	minOffset := cfg.Radius * cfg.SpawnOffsetMult
	offset := minOffset + rand.Float64()*minOffset
	spawnX := clamp(x+math.Cos(angle)*offset, cfg.Radius, cfg.CanvasWidth-cfg.Radius)
	spawnY := clamp(y+math.Sin(angle)*offset, cfg.Radius, cfg.CanvasHeight-cfg.Radius)
	d := newDot(id, spawnX, spawnY, cfg)
	d.CollisionUntil = time.Now().Add(cfg.CollisionCooldown)
	return d
}

func newDot(id, x, y float64, cfg DotConfig) *Dot {
	speedRange := cfg.MaxSpeed - cfg.MinSpeed
	speed := cfg.MinSpeed + rand.Float64()*speedRange
	angle := rand.Float64() * 2 * math.Pi
	return &Dot{
		cfg:    cfg,
		ID:     id,
		X:      x,
		Y:      y,
		VX:     math.Cos(angle) * speed,
		VY:     math.Sin(angle) * speed,
		tickCh: make(chan struct{}, 1),
		posCh:  make(chan DotState, 1),
		stopCh: make(chan struct{}),
	}
}

func (d *Dot) Start() {
	go func() {
		for {
			select {
			case <-d.stopCh:
				return
			case <-d.tickCh:
				d.move()
				d.mu.Lock()
				state := DotState{
					ID:             d.ID,
					X:              d.X,
					Y:              d.Y,
					VX:             d.VX,
					VY:             d.VY,
					CollisionUntil: d.CollisionUntil,
				}
				d.mu.Unlock()
				d.posCh <- state
			}
		}
	}()
}

func (d *Dot) Stop() {
	close(d.stopCh)
}

func (d *Dot) move() {
	d.mu.Lock()
	defer d.mu.Unlock()

	d.X += d.VX
	d.Y += d.VY

	r := d.cfg.Radius
	w := d.cfg.CanvasWidth
	h := d.cfg.CanvasHeight

	if d.X-r < 0 {
		d.X = r
		d.VX = math.Abs(d.VX)
	} else if d.X+r > w {
		d.X = w - r
		d.VX = -math.Abs(d.VX)
	}
	if d.Y-r < 0 {
		d.Y = r
		d.VY = math.Abs(d.VY)
	} else if d.Y+r > h {
		d.Y = h - r
		d.VY = -math.Abs(d.VY)
	}
}

func clamp(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
