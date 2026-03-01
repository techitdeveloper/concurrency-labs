package simulation

import (
	"math"
	"math/rand"
	"sync"
	"time"
)

const (
	DotRadius    = 6.0
	CanvasWidth  = 1000.0
	CanvasHeight = 750.0

	CollisionCooldown = 1000 * time.Millisecond
	MinSpawnOffset    = DotRadius * 8
)

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
	mu sync.Mutex

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

func NewDot(id float64) *Dot {
	x := DotRadius + rand.Float64()*(CanvasWidth-2*DotRadius)
	y := DotRadius + rand.Float64()*(CanvasHeight-2*DotRadius)
	return newDot(id, x, y)
}

func NewDotAt(id float64, x, y float64) *Dot {
	angle := rand.Float64() * 2 * math.Pi
	offset := MinSpawnOffset + rand.Float64()*MinSpawnOffset
	spawnX := clamp(x+math.Cos(angle)*offset, DotRadius, CanvasWidth-DotRadius)
	spawnY := clamp(y+math.Sin(angle)*offset, DotRadius, CanvasHeight-DotRadius)
	d := newDot(id, spawnX, spawnY)
	d.CollisionUntil = time.Now().Add(CollisionCooldown)
	return d
}

func newDot(id, x, y float64) *Dot {
	speed := 1.5 + rand.Float64()*2.5
	angle := rand.Float64() * 2 * math.Pi
	return &Dot{
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

	if d.X-DotRadius < 0 {
		d.X = DotRadius
		d.VX = math.Abs(d.VX)
	} else if d.X+DotRadius > CanvasWidth {
		d.X = CanvasWidth - DotRadius
		d.VX = -math.Abs(d.VX)
	}
	if d.Y-DotRadius < 0 {
		d.Y = DotRadius
		d.VY = math.Abs(d.VY)
	} else if d.Y+DotRadius > CanvasHeight {
		d.Y = CanvasHeight - DotRadius
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
