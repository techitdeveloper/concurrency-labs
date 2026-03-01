package transport

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"

	"github.com/techitdeveloper/concurrency-labs/services/go-runtime/internal/metrics"
	"github.com/techitdeveloper/concurrency-labs/services/go-runtime/internal/simulation"
)

const (
	writeWait  = 10 * time.Second
	pongWait   = 60 * time.Second
	pingPeriod = (pongWait * 9) / 10
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 4096,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

// Hub is stateless — each WebSocket connection is a fully self-contained session.
type Hub struct {
	metricsInterval time.Duration
}

func NewHub(_ *simulation.Engine, _ *metrics.Collector) *Hub {
	return &Hub{metricsInterval: 1 * time.Second}
}

func (h *Hub) Run() {}

func (h *Hub) ServeWS(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Error("ws upgrade failed", "err", err)
		return
	}

	s := newSession(conn, h.metricsInterval)
	slog.Info("session started", "remote", conn.RemoteAddr(), "id", s.id)

	s.run()

	slog.Info("session ended", "remote", conn.RemoteAddr(), "id", s.id)
}

// ---------------------------------------------------------------------------
// session
// ---------------------------------------------------------------------------

var sessionID atomic.Uint64

type session struct {
	id        uint64
	conn      *websocket.Conn
	engine    *simulation.Engine
	collector *metrics.Collector
	send      chan []byte
	done      chan struct{} // closed when the session is shutting down
}

func newSession(conn *websocket.Conn, metricsInterval time.Duration) *session {
	return &session{
		id:        sessionID.Add(1),
		conn:      conn,
		engine:    simulation.NewEngine(simulation.InitialCount),
		collector: metrics.NewCollector(metricsInterval),
		send:      make(chan []byte, 64),
		done:      make(chan struct{}),
	}
}

func (s *session) run() {
	s.engine.Start()
	s.collector.Start()

	go s.fanOutSimulation()
	go s.fanOutMetrics()
	go s.writePump()

	s.readPump() // blocks until connection closes

	// Signal fanOut goroutines to stop before we close send
	close(s.done)

	// Give fan-out goroutines a moment to exit their select
	// before we stop the engine (which closes Updates channels)
	time.Sleep(10 * time.Millisecond)

	s.engine.Stop()
	s.collector.Stop()
}

// ---------------------------------------------------------------------------
// Fan-out goroutines
// Each selects on both s.done and the update channel so they exit cleanly
// the moment cleanup begins — no send on closed channel.
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
	// Check done before attempting send — avoids racing with cleanup
	select {
	case <-s.done:
		return
	default:
	}
	select {
	case s.send <- data:
	case <-s.done:
		// Session is shutting down — discard
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
		s.engine.Reset(simulation.InitialCount)
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
