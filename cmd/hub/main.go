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
	adminPassword := flag.String("admin-password", envOrDefault("STATUS_ADMIN_PASSWORD", "statusadmin"), "admin password for dashboard login")
	publicURL := flag.String("public-url", envOrDefault("STATUS_PUBLIC_URL", "http://localhost:8080"), "public hub URL")
	flag.Parse()

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
