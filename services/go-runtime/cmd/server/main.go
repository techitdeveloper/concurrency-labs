package main

import (
	"log/slog"
	"net/http"
	"os"

	"github.com/techitdeveloper/concurrency-labs/services/go-runtime/internal/metrics"
	"github.com/techitdeveloper/concurrency-labs/services/go-runtime/internal/simulation"
	"github.com/techitdeveloper/concurrency-labs/services/go-runtime/internal/transport"
)

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	port := os.Getenv("PORT")
	if port == "" {
		port = "4001"
	}

	// The Hub is now stateless — it creates a fresh Engine + Collector
	// per WebSocket connection. We pass nil here; the Hub no longer uses
	// a shared engine or collector.
	hub := transport.NewHub((*simulation.Engine)(nil), (*metrics.Collector)(nil))
	hub.Run()

	mux := http.NewServeMux()

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	mux.HandleFunc("/ws", hub.ServeWS)

	addr := ":" + port
	slog.Info("go-runtime starting", "addr", addr)

	if err := http.ListenAndServe(addr, mux); err != nil {
		slog.Error("server error", "err", err)
		os.Exit(1)
	}
}
