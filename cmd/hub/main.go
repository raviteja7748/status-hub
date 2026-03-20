package main

import (
	"flag"
	"log"
	"net/http"
	"os"

	"github.com/elite/status/internal/hub"
)

func main() {
	listenAddr := flag.String("listen", envOrDefault("STATUS_LISTEN_ADDR", ":8080"), "listen address")
	dbPath := flag.String("db", envOrDefault("STATUS_DB_PATH", "status.db"), "sqlite database path")
	adminPassword := flag.String("admin-password", envOrDefault("STATUS_ADMIN_PASSWORD", ""), "admin password for dashboard login")
	deviceToken := flag.String("device-token", envOrDefault("STATUS_DEVICE_TOKEN", ""), "shared collector token")
	publicURL := flag.String("public-url", envOrDefault("STATUS_PUBLIC_URL", "http://localhost:8080"), "public hub URL")
	flag.Parse()
	if *adminPassword == "" {
		log.Fatal("admin password is required (set --admin-password or STATUS_ADMIN_PASSWORD)")
	}
	if *deviceToken == "" {
		log.Fatal("device token is required (set --device-token or STATUS_DEVICE_TOKEN)")
	}

	store, err := hub.NewStore(*dbPath)
	if err != nil {
		log.Fatalf("open store: %v", err)
	}
	if err := store.SeedDefaults(); err != nil {
		log.Fatalf("seed defaults: %v", err)
	}

	server := hub.NewServer(store, hub.Config{
		AdminPassword: *adminPassword,
		PublicURL:     *publicURL,
		DeviceToken:   *deviceToken,
	})

	log.Printf("hub listening on %s", *listenAddr)
	if err := http.ListenAndServe(*listenAddr, server.Routes()); err != nil {
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
