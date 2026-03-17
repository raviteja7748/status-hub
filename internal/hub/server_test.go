package hub

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/elite/status/internal/model"
)

func TestBootstrapDefaultsToMacMenuBar(t *testing.T) {
	server, store := newTestServer(t)
	device, err := store.UpsertDevice(context.Background(), "collector-token", "ubuntu-box", map[string]bool{}, nil)
	if err != nil {
		t.Fatalf("seed device: %v", err)
	}

	if _, err := store.GetLayout(context.Background(), device.ID, "mobile_web"); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("expected no mobile_web layout, got %v", err)
	}

	sessionToken := "test-session"
	server.sessions[sessionToken] = time.Now().Add(time.Hour)

	request := httptest.NewRequest(http.MethodGet, "/api/bootstrap", nil)
	request.Header.Set("Authorization", "Bearer "+sessionToken)
	recorder := httptest.NewRecorder()

	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", recorder.Code)
	}

	var response model.BootstrapResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatalf("decode bootstrap response: %v", err)
	}

	if response.Layout == nil {
		t.Fatal("expected bootstrap layout")
	}
	if response.Layout.Target != "mac_menu_bar" {
		t.Fatalf("expected mac_menu_bar target, got %q", response.Layout.Target)
	}
}

func TestRootReturnsNotFound(t *testing.T) {
	server, _ := newTestServer(t)

	request := httptest.NewRequest(http.MethodGet, "/", nil)
	recorder := httptest.NewRecorder()
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", recorder.Code)
	}
}

func newTestServer(t *testing.T) (*Server, *Store) {
	t.Helper()

	store, err := NewStore(filepath.Join(t.TempDir(), "status.db"))
	if err != nil {
		t.Fatalf("new store: %v", err)
	}
	if err := store.SeedDefaults(); err != nil {
		t.Fatalf("seed defaults: %v", err)
	}

	server := NewServer(store, Config{
		AdminPassword: "statusadmin",
		PublicURL:     "http://localhost:8080",
	})
	return server, store
}
