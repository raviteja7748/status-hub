package hub

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/elite/status/internal/model"
	"github.com/gorilla/websocket"
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

	sessionToken := seedSession(server)

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

func TestDeviceSocketRejectsInvalidToken(t *testing.T) {
	server, _ := newTestServer(t)
	testHTTP := httptest.NewServer(server.Routes())
	defer testHTTP.Close()

	wsURL := "ws" + strings.TrimPrefix(testHTTP.URL, "http") + "/ws/device?token=wrong-token"
	conn, resp, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err == nil {
		conn.Close()
		t.Fatal("expected websocket dial to fail with invalid collector token")
	}
	if resp == nil {
		t.Fatal("expected HTTP response from failed websocket handshake")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d", resp.StatusCode)
	}
}

func TestDeviceSocketAcceptsConfiguredToken(t *testing.T) {
	server, _ := newTestServer(t)
	testHTTP := httptest.NewServer(server.Routes())
	defer testHTTP.Close()

	wsURL := "ws" + strings.TrimPrefix(testHTTP.URL, "http") + "/ws/device?token=collector-token"
	conn, resp, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		if resp != nil {
			resp.Body.Close()
		}
		t.Fatalf("expected websocket dial to succeed, got %v", err)
	}
	conn.Close()
}

func TestAcknowledgeEventReturnsNotFoundForUnknownID(t *testing.T) {
	server, store := newTestServer(t)
	sessionToken := seedSession(server)
	device, err := store.UpsertDevice(context.Background(), "collector-token", "ubuntu-box", map[string]bool{}, nil)
	if err != nil {
		t.Fatalf("seed device: %v", err)
	}

	event := NewEvent(device.ID, model.AlertRule{ID: "rule-1", Title: "rule", Severity: "warning"}, "body")
	if err := store.SaveEvent(context.Background(), event); err != nil {
		t.Fatalf("seed event: %v", err)
	}

	request := httptest.NewRequest(http.MethodPost, "/api/events/"+event.ID+"/ack", nil)
	request.Header.Set("Authorization", "Bearer "+sessionToken)
	recorder := httptest.NewRecorder()
	server.Routes().ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200 for existing event, got %d", recorder.Code)
	}

	request = httptest.NewRequest(http.MethodPost, "/api/events/missing-event-id/ack", nil)
	request.Header.Set("Authorization", "Bearer "+sessionToken)
	recorder = httptest.NewRecorder()
	server.Routes().ServeHTTP(recorder, request)
	if recorder.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for missing event, got %d", recorder.Code)
	}

	var payload map[string]string
	if err := json.NewDecoder(recorder.Body).Decode(&payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload["error"] != "event not found" {
		t.Fatalf("expected not found error, got %q", payload["error"])
	}
}

func TestServerErrorResponseIsSanitized(t *testing.T) {
	server, _ := newTestServer(t)
	sessionToken := seedSession(server)

	request := httptest.NewRequest(http.MethodGet, "/api/bootstrap?deviceId=missing-device-id&target=mobile_web", nil)
	request.Header.Set("Authorization", "Bearer "+sessionToken)
	recorder := httptest.NewRecorder()
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", recorder.Code)
	}
	if strings.Contains(strings.ToLower(recorder.Body.String()), "sql") {
		t.Fatalf("expected sanitized error response, got %s", recorder.Body.String())
	}

	var payload map[string]string
	if err := json.NewDecoder(strings.NewReader(recorder.Body.String())).Decode(&payload); err != nil {
		t.Fatalf("decode error payload: %v", err)
	}
	if payload["error"] != "internal server error" {
		t.Fatalf("expected sanitized payload, got %q", payload["error"])
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
		DeviceToken:   "collector-token",
	})
	return server, store
}

func seedSession(server *Server) string {
	token := "test-session"
	server.mu.Lock()
	server.sessions[token] = time.Now().Add(time.Hour)
	server.mu.Unlock()
	return token
}
