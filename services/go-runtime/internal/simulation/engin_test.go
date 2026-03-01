package simulation

import (
	"testing"
	"time"
)

func TestNewDotIsWithinCanvas(t *testing.T) {
	for i := 0; i < 100; i++ {
		d := NewDot(float64(i))
		if d.X < DotRadius || d.X > CanvasWidth-DotRadius {
			t.Errorf("dot X=%f out of bounds", d.X)
		}
		if d.Y < DotRadius || d.Y > CanvasHeight-DotRadius {
			t.Errorf("dot Y=%f out of bounds", d.Y)
		}
	}
}

func TestDotBounces(t *testing.T) {
	d := &Dot{ID: 0, X: 0, Y: 300, VX: -5, VY: 0}
	d.move()
	if d.VX <= 0 {
		t.Error("expected VX to flip positive after hitting left wall")
	}
}

// func TestCollisionDetection(t *testing.T) {
// 	a := &Dot{ID: 0, X: 100, Y: 100}
// 	b := &Dot{ID: 1, X: 100, Y: 100} // same position → definite collision
// 	if !a.Collides(b) {
// 		t.Error("expected collision for overlapping dots")
// 	}

// 	c := &Dot{ID: 2, X: 500, Y: 500}
// 	if a.Collides(c) {
// 		t.Error("expected no collision for distant dots")
// 	}
// }

func TestEngineSpawnAndReset(t *testing.T) {
	e := NewEngine(10)
	e.Start()
	defer e.Stop()

	if e.DotCount() != 10 {
		t.Errorf("expected 10 dots, got %d", e.DotCount())
	}

	e.SpawnDot()
	if e.DotCount() != 11 {
		t.Errorf("expected 11 dots after spawn, got %d", e.DotCount())
	}

	e.Reset(5)
	if e.DotCount() != 5 {
		t.Errorf("expected 5 dots after reset, got %d", e.DotCount())
	}
}

func TestEngineMaxDotsCap(t *testing.T) {
	e := NewEngine(MaxDots)
	e.Start()
	defer e.Stop()

	// Spawning beyond the cap should be a no-op
	e.SpawnDot()
	if e.DotCount() > MaxDots {
		t.Errorf("exceeded MaxDots cap: got %d", e.DotCount())
	}
}

func TestEngineProducesUpdates(t *testing.T) {
	e := NewEngine(5)
	e.Start()
	defer e.Stop()

	select {
	case snap := <-e.Updates:
		if snap.Count != len(snap.Dots) {
			t.Error("snapshot Count does not match Dots length")
		}
	case <-time.After(500 * time.Millisecond):
		t.Error("timed out waiting for first update")
	}
}
