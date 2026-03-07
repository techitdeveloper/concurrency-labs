package transport

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"

	"github.com/techitdeveloper/concurrency-labs/services/go-runtime/internal/config"
	"github.com/techitdeveloper/concurrency-labs/services/go-runtime/internal/metrics"
	"github.com/techitdeveloper/concurrency-labs/services/go-runtime/internal/simulation"
)

const (
	writeWait  = 10 * time.Second
	pongWait   = 60 * time.Second
	pingPeriod = (pongWait * 9) / 10
)

// Hub is stateless — each WebSocket connection is a fully self-contained session.
type Hub struct {
	cfg      config.Config
	upgrader websocket.Upgrader
}

func NewHub(cfg config.Config) *Hub {
	h := &Hub{cfg: cfg}

	h.upgrader = websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 4096,
		CheckOrigin:     h.checkOrigin,
	}

	return h
}

// checkOrigin allows all origins when AllowedOrigins is empty,
// otherwise restricts to the configured list.
func (h *Hub) checkOrigin(r *http.Request) bool {
	if len(h.cfg.AllowedOrigins) == 0 {
		return true
	}
	origin := r.Header.Get("Origin")
	for _, allowed := range h.cfg.AllowedOrigins {
		if origin == allowed {
			return true
		}
	}
	slog.Warn("ws origin rejected", "origin", origin)
	return false
}

func (h *Hub) ServeWS(w http.ResponseWriter, r *http.Request) {
	conn, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Error("ws upgrade failed", "err", err)
		return
	}

	s := newSession(conn, h.cfg)
	slog.Info("session started", "remote", conn.RemoteAddr(), "id", s.id)

	s.run()

	slog.Info("session ended", "remote", conn.RemoteAddr(), "id", s.id)
}

// ---------------------------------------------------------------------------
// session
// ---------------------------------------------------------------------------

var sessionID atomic.Uint64

type session struct {
	id           uint64
	conn         *websocket.Conn
	engine       *simulation.Engine
	collector    *metrics.Collector
	send         chan []byte
	done         chan struct{}
	initialCount int
}

func newSession(conn *websocket.Conn, cfg config.Config) *session {
	engineCfg := simulation.EngineConfig{
		MaxDots:      cfg.MaxDots,
		TickInterval: cfg.TickInterval,
		Dot: simulation.DotConfig{
			Radius:            cfg.DotRadius,
			CanvasWidth:       cfg.CanvasWidth,
			CanvasHeight:      cfg.CanvasHeight,
			MinSpeed:          cfg.DotMinSpeed,
			MaxSpeed:          cfg.DotMaxSpeed,
			CollisionCooldown: cfg.CollisionCooldown,
			SpawnOffsetMult:   cfg.SpawnOffsetMult,
		},
	}

	return &session{
		id:           sessionID.Add(1),
		conn:         conn,
		engine:       simulation.NewEngine(cfg.InitialCount, engineCfg),
		collector:    metrics.NewCollector(cfg.MetricsInterval),
		send:         make(chan []byte, 64),
		done:         make(chan struct{}),
		initialCount: cfg.InitialCount,
	}
}

func (s *session) run() {
	s.engine.Start()
	s.collector.Start()

	go s.fanOutSimulation()
	go s.fanOutMetrics()
	go s.writePump()

	s.readPump() // blocks until connection closes

	close(s.done)

	// Give fan-out goroutines a moment to exit before stopping the engine.
	time.Sleep(10 * time.Millisecond)

	s.engine.Stop()
	s.collector.Stop()
}

// ---------------------------------------------------------------------------
// Fan-out goroutines
// ---------------------------------------------------------------------------

func (s *session) fanOutSimulation() {
	for {
		select {
		case <-s.done:
			return
		case snap, ok := <-s.engine.Updates:
			if !ok {
				return
			}
			s.broadcast(ServerMessage{
				Kind: KindSimulationState,
				Payload: SimulationPayload{
					Dots:  snap.Dots,
					Count: snap.Count,
				},
			})
		}
	}
}

func (s *session) fanOutMetrics() {
	for {
		select {
		case <-s.done:
			return
		case sample, ok := <-s.collector.Updates:
			if !ok {
				return
			}
			s.broadcast(ServerMessage{
				Kind: KindMetrics,
				Payload: MetricsPayload{
					TimestampMs:  sample.Timestamp,
					HeapAllocKB:  sample.HeapAlloc / 1024,
					HeapSysKB:    sample.HeapSys / 1024,
					StackInuseKB: sample.StackInuse / 1024,
					NumGoroutine: sample.NumGoroutine,
					NumGCCycles:  sample.NumGCCycles,
				},
			})
		}
	}
}

func (s *session) broadcast(msg ServerMessage) {
	data, err := json.Marshal(msg)
	if err != nil {
		slog.Error("marshal error", "err", err)
		return
	}
	select {
	case <-s.done:
		return
	default:
	}
	select {
	case s.send <- data:
	case <-s.done:
	default:
		// Client too slow — drop frame
	}
}

// ---------------------------------------------------------------------------
// Read / write pumps
// ---------------------------------------------------------------------------

func (s *session) readPump() {
	defer s.conn.Close()

	s.conn.SetReadLimit(512)
	s.conn.SetReadDeadline(time.Now().Add(pongWait))
	s.conn.SetPongHandler(func(string) error {
		s.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, raw, err := s.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err,
				websocket.CloseGoingAway,
				websocket.CloseAbnormalClosure,
			) {
				slog.Warn("ws read error", "err", err, "session", s.id)
			}
			return
		}

		var msg ClientMessage
		if err := json.Unmarshal(raw, &msg); err != nil {
			slog.Warn("invalid client message", "err", err)
			continue
		}
		s.handleClientMessage(msg)
	}
}

func (s *session) handleClientMessage(msg ClientMessage) {
	switch msg.Kind {
	case KindSpawnDot:
		s.engine.SpawnDot()
	case KindReset:
		s.engine.Reset(s.initialCount)
	default:
		slog.Warn("unknown client message kind", "kind", msg.Kind, "session", s.id)
	}
}

func (s *session) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer ticker.Stop()

	for {
		select {
		case <-s.done:
			return
		case msg, ok := <-s.send:
			s.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				s.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := s.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			s.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := s.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
