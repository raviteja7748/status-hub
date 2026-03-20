package main

import (
	"context"
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/elite/status/internal/collector"
)

func main() {
	hubURL := flag.String("hub", envOrDefault("STATUS_HUB_URL", "http://localhost:8080"), "hub base URL")
	token := flag.String("token", envOrDefault("STATUS_DEVICE_TOKEN", ""), "device token")
	name := flag.String("name", envOrDefault("STATUS_DEVICE_NAME", ""), "friendly device name")
	interval := flag.Duration("interval", 15*time.Second, "snapshot interval")
	flag.Parse()
	if *token == "" {
		log.Fatal("device token is required (set --token or STATUS_DEVICE_TOKEN)")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	instance := collector.New(collector.Config{
		HubURL:   *hubURL,
		Token:    *token,
		Name:     *name,
		Interval: *interval,
	})

	if err := instance.Run(ctx); err != nil && err != context.Canceled {
		log.Fatal(err)
	}
}

func envOrDefault(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}
