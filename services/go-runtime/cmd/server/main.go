package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/techitdeveloper/concurrency-labs/services/go-runtime/internal/config"
	"github.com/techitdeveloper/concurrency-labs/services/go-runtime/internal/transport"
)

func main() {
	cfg := config.Load()

	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: cfg.LogLevel,
	}))
	slog.SetDefault(logger)

	slog.Info("go-runtime config loaded",
		"port", cfg.Port,
		"log_level", cfg.LogLevel,
		"initial_count", cfg.InitialCount,
		"max_dots", cfg.MaxDots,
		"tick_ms", cfg.TickInterval.Milliseconds(),
		"canvas", cfg.CanvasWidth, "x", cfg.CanvasHeight,
		"allowed_origins", cfg.AllowedOrigins,
	)

	hub := transport.NewHub(cfg)

	mux := http.NewServeMux()

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	mux.HandleFunc("/ws", hub.ServeWS)

	srv := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: mux,
	}

	// Start server in background so we can listen for shutdown signals.
	go func() {
		slog.Info("go-runtime listening", "addr", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "err", err)
			os.Exit(1)
		}
	}()

	// Block until we receive SIGTERM (Fly.io) or SIGINT (Ctrl-C in dev).
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
	sig := <-quit
	slog.Info("shutdown signal received", "signal", sig)

	// Give in-flight WebSocket sessions up to 15 seconds to drain.
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		slog.Error("graceful shutdown failed", "err", err)
		os.Exit(1)
	}

	slog.Info("go-runtime stopped cleanly")
}
