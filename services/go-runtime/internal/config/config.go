package config

import (
	"log/slog"
	"os"
	"strconv"
	"strings"
	"time"
)

// Config holds every runtime-tunable value for the Go service.
// All fields have production-safe defaults; every field can be
// overridden by the corresponding environment variable.
//
// Environment variables (all optional):
//
//	PORT                 HTTP listen port                        (default: 4001)
//	LOG_LEVEL            debug | info | warn | error             (default: info)
//	ALLOWED_ORIGINS      comma-separated WebSocket origins        (default: *)
//
//	SIM_INITIAL_COUNT    starting dot count                      (default: 50)
//	SIM_MAX_DOTS         hard cap on concurrent dots             (default: 1000)
//	SIM_TICK_MS          simulation tick in milliseconds         (default: 33)
//
//	DOT_RADIUS           dot radius in canvas units              (default: 6)
//	CANVAS_WIDTH         canvas width in canvas units            (default: 1000)
//	CANVAS_HEIGHT        canvas height in canvas units           (default: 750)
//	DOT_MIN_SPEED        minimum dot speed (units/tick)          (default: 1.5)
//	DOT_MAX_SPEED        maximum dot speed (units/tick)          (default: 4.0)
//	COLLISION_COOLDOWN_MS cooldown after a collision in ms       (default: 1000)
//	SPAWN_OFFSET_MULT    spawn-offset multiplier × DotRadius     (default: 8)
//
//	METRICS_INTERVAL_MS  MemStats sampling interval in ms        (default: 1000)
type Config struct {
	// Server
	Port           string
	LogLevel       slog.Level
	AllowedOrigins []string // empty slice means "allow all"

	// Simulation
	InitialCount int
	MaxDots      int
	TickInterval time.Duration

	// Dot physics
	DotRadius         float64
	CanvasWidth       float64
	CanvasHeight      float64
	DotMinSpeed       float64
	DotMaxSpeed       float64
	CollisionCooldown time.Duration
	SpawnOffsetMult   float64

	// Metrics
	MetricsInterval time.Duration
}

// Load reads environment variables and returns a fully-populated Config.
// Any missing or unparseable variable falls back to its default.
func Load() Config {
	c := Config{
		Port:              envString("PORT", "4001"),
		LogLevel:          parseLogLevel(envString("LOG_LEVEL", "info")),
		AllowedOrigins:    parseOrigins(envString("ALLOWED_ORIGINS", "")),
		InitialCount:      envInt("SIM_INITIAL_COUNT", 50),
		MaxDots:           envInt("SIM_MAX_DOTS", 1000),
		TickInterval:      envDuration("SIM_TICK_MS", 33),
		DotRadius:         envFloat("DOT_RADIUS", 6.0),
		CanvasWidth:       envFloat("CANVAS_WIDTH", 1000.0),
		CanvasHeight:      envFloat("CANVAS_HEIGHT", 750.0),
		DotMinSpeed:       envFloat("DOT_MIN_SPEED", 1.5),
		DotMaxSpeed:       envFloat("DOT_MAX_SPEED", 4.0),
		CollisionCooldown: envDuration("COLLISION_COOLDOWN_MS", 1000),
		SpawnOffsetMult:   envFloat("SPAWN_OFFSET_MULT", 8.0),
		MetricsInterval:   envDuration("METRICS_INTERVAL_MS", 1000),
	}
	return c
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

func envString(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		slog.Warn("config: invalid int, using default", "key", key, "value", v, "default", def)
		return def
	}
	return n
}

func envFloat(key string, def float64) float64 {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil {
		slog.Warn("config: invalid float, using default", "key", key, "value", v, "default", def)
		return def
	}
	return f
}

// envDuration reads a millisecond integer and converts to time.Duration.
func envDuration(key string, defMs int) time.Duration {
	ms := envInt(key, defMs)
	return time.Duration(ms) * time.Millisecond
}

func parseLogLevel(s string) slog.Level {
	switch strings.ToLower(s) {
	case "debug":
		return slog.LevelDebug
	case "warn", "warning":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

// parseOrigins splits a comma-separated origin list.
// An empty or "*" value means "allow all" (returned as nil/empty slice).
func parseOrigins(s string) []string {
	if s == "" || s == "*" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}
