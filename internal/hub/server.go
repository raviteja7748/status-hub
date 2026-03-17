package hub

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/elite/status/internal/model"
	"github.com/gorilla/websocket"
)

type authMode string

const (
	authModeSession authMode = "session"
	authModeClient  authMode = "client"
)

type authIdentity struct {
	Mode authMode
	ID   string
	Name string
}

type contextKey string

const authContextKey contextKey = "authIdentity"

type Config struct {
	AdminPassword string
	PublicURL     string
}

type Server struct {
	store      *Store
	config     Config
	upgrader   websocket.Upgrader
	mu         sync.Mutex
	sessions   map[string]time.Time
	streams    map[*websocket.Conn]struct{}
	httpClient *http.Client
}

func NewServer(store *Store, config Config) *Server {
	return &Server{
		store:  store,
		config: config,
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool { return true },
		},
		sessions:   map[string]time.Time{},
		streams:    map[*websocket.Conn]struct{}{},
		httpClient: &http.Client{Timeout: 10 * time.Second},
	}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("/api/sessions", s.handleSessionLogin)
	mux.HandleFunc("/api/bootstrap", s.withAuth(s.handleBootstrap))
	mux.HandleFunc("/api/devices", s.withAuth(s.handleDevices))
	mux.HandleFunc("/api/layouts", s.withAuth(s.handleLayouts))
	mux.HandleFunc("/api/alerts", s.withAuth(s.handleAlerts))
	mux.HandleFunc("/api/events", s.withAuth(s.handleEvents))
	mux.HandleFunc("/api/events/", s.withAuth(s.handleEventActions))
	mux.HandleFunc("/api/notification-channels", s.withAdminAuth(s.handleChannels))
	mux.HandleFunc("/api/client-tokens", s.withAdminAuth(s.handleClientTokens))
	mux.HandleFunc("/api/client-tokens/", s.withAdminAuth(s.handleClientTokenActions))
	mux.HandleFunc("/ws/device", s.handleDeviceSocket)
	mux.HandleFunc("/ws/stream", s.handleClientStream)
	return loggingMiddleware(mux)
}

func (s *Server) handleSessionLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	var req model.AuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid json"})
		return
	}
	if req.Password == "" || req.Password != s.config.AdminPassword {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid password"})
		return
	}
	token := randomToken()
	s.mu.Lock()
	s.sessions[token] = time.Now().Add(24 * time.Hour)
	s.mu.Unlock()
	writeJSON(w, http.StatusOK, model.AuthResponse{Token: token})
}

func (s *Server) withAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		identity, ok, err := s.authenticate(r)
		if err != nil {
			s.writeServerError(w, r, err)
			return
		}
		if !ok {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), authContextKey, identity)))
	}
}

func (s *Server) withAdminAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		identity, ok, err := s.authenticate(r)
		if err != nil {
			s.writeServerError(w, r, err)
			return
		}
		if !ok || identity.Mode != authModeSession {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "admin session required"})
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), authContextKey, identity)))
	}
}

func (s *Server) authenticate(r *http.Request) (authIdentity, bool, error) {
	token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	if token == "" {
		token = r.URL.Query().Get("token")
	}
	if token == "" {
		return authIdentity{}, false, nil
	}
	if s.validSession(token) {
		return authIdentity{Mode: authModeSession, ID: token, Name: "admin"}, true, nil
	}
	client, err := s.store.ValidateClientToken(r.Context(), token)
	if err != nil {
		return authIdentity{}, false, err
	}
	if client != nil {
		return authIdentity{Mode: authModeClient, ID: client.ID, Name: client.Name}, true, nil
	}
	return authIdentity{}, false, nil
}

func (s *Server) validSession(token string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	expiry, ok := s.sessions[token]
	if !ok {
		return false
	}
	if time.Now().After(expiry) {
		delete(s.sessions, token)
		return false
	}
	return true
}

func identityFromContext(ctx context.Context) authIdentity {
	identity, _ := ctx.Value(authContextKey).(authIdentity)
	return identity
}

func (s *Server) handleBootstrap(w http.ResponseWriter, r *http.Request) {
	target := r.URL.Query().Get("target")
	if target == "" {
		target = "mac_menu_bar"
	}
	deviceID := r.URL.Query().Get("deviceId")
	bootstrap, err := s.store.BuildBootstrap(r.Context(), deviceID, target)
	if err != nil {
		s.writeServerError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, bootstrap)
}

func (s *Server) handleDevices(w http.ResponseWriter, r *http.Request) {
	devices, err := s.store.ListDevices(r.Context())
	if err != nil {
		s.writeServerError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, devices)
}

func (s *Server) handleLayouts(w http.ResponseWriter, r *http.Request) {
	deviceID := r.URL.Query().Get("deviceId")
	target := r.URL.Query().Get("target")
	if deviceID == "" || target == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "deviceId and target are required"})
		return
	}
	switch r.Method {
	case http.MethodGet:
		layout, err := s.store.GetLayout(r.Context(), deviceID, target)
		if err != nil {
			s.writeServerError(w, r, err)
			return
		}
		writeJSON(w, http.StatusOK, layout)
	case http.MethodPut:
		var widgets []model.Widget
		if err := json.NewDecoder(r.Body).Decode(&widgets); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid layout payload"})
			return
		}
		if err := s.store.SaveLayout(r.Context(), deviceID, target, widgets); err != nil {
			s.writeServerError(w, r, err)
			return
		}
		layout, err := s.store.GetLayout(r.Context(), deviceID, target)
		if err != nil {
			s.writeServerError(w, r, err)
			return
		}
		writeJSON(w, http.StatusOK, layout)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (s *Server) handleAlerts(w http.ResponseWriter, r *http.Request) {
	deviceID := r.URL.Query().Get("deviceId")
	if deviceID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "deviceId is required"})
		return
	}
	switch r.Method {
	case http.MethodGet:
		rules, err := s.store.ListAlertRules(r.Context(), deviceID)
		if err != nil {
			s.writeServerError(w, r, err)
			return
		}
		writeJSON(w, http.StatusOK, rules)
	case http.MethodPut:
		var rules []model.AlertRule
		if err := json.NewDecoder(r.Body).Decode(&rules); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid rules payload"})
			return
		}
		if err := s.store.SaveAlertRules(r.Context(), deviceID, rules); err != nil {
			s.writeServerError(w, r, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (s *Server) handleEvents(w http.ResponseWriter, r *http.Request) {
	deviceID := r.URL.Query().Get("deviceId")
	events, err := s.store.ListEvents(r.Context(), deviceID)
	if err != nil {
		s.writeServerError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, events)
}

func (s *Server) handleEventActions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	path := strings.TrimPrefix(r.URL.Path, "/api/events/")
	if !strings.HasSuffix(path, "/ack") {
		http.NotFound(w, r)
		return
	}
	eventID := strings.TrimSuffix(path, "/ack")
	eventID = strings.TrimSuffix(eventID, "/")
	if eventID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "event id is required"})
		return
	}
	identity := identityFromContext(r.Context())
	if err := s.store.AcknowledgeEvent(r.Context(), eventID, identity.Name); err != nil {
		s.writeServerError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) handleChannels(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		channels, err := s.store.ListNotificationChannels(r.Context())
		if err != nil {
			s.writeServerError(w, r, err)
			return
		}
		writeJSON(w, http.StatusOK, channels)
	case http.MethodPut:
		var channels []model.NotificationChannel
		if err := json.NewDecoder(r.Body).Decode(&channels); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid channel payload"})
			return
		}
		if err := s.store.SaveNotificationChannels(r.Context(), channels); err != nil {
			s.writeServerError(w, r, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (s *Server) handleClientTokens(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		tokens, err := s.store.ListClientTokens(r.Context())
		if err != nil {
			s.writeServerError(w, r, err)
			return
		}
		writeJSON(w, http.StatusOK, tokens)
	case http.MethodPost:
		var req model.ClientTokenCreateRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid token payload"})
			return
		}
		if req.Name == "" {
			req.Name = "client"
		}
		if req.Kind == "" {
			req.Kind = "mac_menu_bar"
		}
		token, err := s.store.IssueClientToken(r.Context(), req.Name, req.Kind)
		if err != nil {
			s.writeServerError(w, r, err)
			return
		}
		writeJSON(w, http.StatusOK, token)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func (s *Server) handleClientTokenActions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	id := strings.TrimPrefix(r.URL.Path, "/api/client-tokens/")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "token id is required"})
		return
	}
	if err := s.store.RevokeClientToken(r.Context(), id); err != nil {
		s.writeServerError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) handleDeviceSocket(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	if token == "" {
		http.Error(w, "missing token", http.StatusUnauthorized)
		return
	}
	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	var device model.Device
	for {
		var envelope model.CollectorEnvelope
		if err := conn.ReadJSON(&envelope); err != nil {
			return
		}

		switch envelope.Type {
		case "hello":
			hello := envelope.Hello
			if hello == nil {
				continue
			}
			name := hello.DeviceName
			if name == "" {
				name = hello.Hostname
			}
			device, err = s.store.UpsertDevice(r.Context(), token, name, hello.Capabilities, hello.Metadata)
			if err != nil {
				log.Printf("upsert device failed: %v", err)
				return
			}
			s.broadcast(model.StreamMessage{Type: "device", Device: &device})
		case "snapshot":
			if envelope.Snapshot == nil {
				continue
			}
			if device.ID == "" {
				device, err = s.store.UpsertDevice(r.Context(), token, envelope.Snapshot.Hostname, map[string]bool{}, nil)
				if err != nil {
					return
				}
			}
			if err := s.store.SaveSnapshot(r.Context(), device.ID, *envelope.Snapshot); err != nil {
				log.Printf("save snapshot failed: %v", err)
				continue
			}
			device, _ = s.store.GetDeviceByID(r.Context(), device.ID)
			s.broadcast(model.StreamMessage{Type: "device", Device: &device})
			s.evaluateAlerts(r.Context(), device, *envelope.Snapshot)
		}
	}
}

func (s *Server) evaluateAlerts(ctx context.Context, device model.Device, snapshot model.Snapshot) {
	rules, err := s.store.ListAlertRules(ctx, device.ID)
	if err != nil {
		return
	}
	for _, rule := range rules {
		if !rule.Enabled {
			continue
		}
		fired, body := EvaluateRule(rule, snapshot)
		dedupeKey := device.ID + ":" + rule.ID
		active, err := s.store.FindActiveEventByDedupeKey(ctx, dedupeKey)
		if err != nil {
			continue
		}
		if fired && active == nil {
			event := NewEvent(device.ID, rule, body)
			if err := s.store.SaveEvent(ctx, event); err == nil {
				s.broadcast(model.StreamMessage{Type: "event", Event: &event})
				go s.dispatchNotifications(context.Background(), event, rule)
			}
		}
		if !fired && active != nil && rule.ResolveBehavior == "auto" {
			if err := s.store.ResolveEvent(ctx, active.ID); err == nil {
				now := time.Now().UTC()
				active.ResolvedAt = &now
				active.Type = "resolved"
				s.broadcast(model.StreamMessage{Type: "event", Event: active})
			}
		}
	}
}

func (s *Server) dispatchNotifications(ctx context.Context, event model.Event, rule model.AlertRule) {
	channels, err := s.store.ListNotificationChannels(ctx)
	if err != nil {
		return
	}
	for _, channel := range channels {
		if !channel.Enabled {
			continue
		}
		if len(rule.Channels) > 0 && !contains(rule.Channels, channel.ID) {
			continue
		}
		if channel.Kind != "ntfy" {
			continue
		}
		serverURL, _ := channel.Config["serverURL"].(string)
		topic, _ := channel.Config["topic"].(string)
		if serverURL == "" || topic == "" {
			continue
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(serverURL, "/")+"/"+topic, strings.NewReader(event.Title+"\n"+event.Body))
		if err != nil {
			continue
		}
		req.Header.Set("Title", event.Title)
		req.Header.Set("Priority", mapPriority(event.Severity))
		resp, err := s.httpClient.Do(req)
		if err == nil && resp.Body != nil {
			resp.Body.Close()
		}
	}
}

func mapPriority(severity string) string {
	switch severity {
	case "critical":
		return "5"
	case "warning":
		return "4"
	default:
		return "3"
	}
}

func contains(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

func (s *Server) handleClientStream(w http.ResponseWriter, r *http.Request) {
	_, ok, err := s.authenticate(r)
	if err != nil {
		s.writeServerError(w, r, err)
		return
	}
	if !ok {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	s.mu.Lock()
	s.streams[conn] = struct{}{}
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		delete(s.streams, conn)
		s.mu.Unlock()
		conn.Close()
	}()

	for {
		if _, _, err := conn.NextReader(); err != nil {
			return
		}
	}
}

func (s *Server) broadcast(message model.StreamMessage) {
	payload, err := json.Marshal(message)
	if err != nil {
		return
	}

	s.mu.Lock()
	conns := make([]*websocket.Conn, 0, len(s.streams))
	for conn := range s.streams {
		conns = append(conns, conn)
	}
	s.mu.Unlock()

	var failed []*websocket.Conn
	for _, conn := range conns {
		if err := conn.WriteMessage(websocket.TextMessage, payload); err != nil {
			conn.Close()
			failed = append(failed, conn)
		}
	}

	if len(failed) == 0 {
		return
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	for _, conn := range failed {
		delete(s.streams, conn)
	}
}

func (s *Server) writeServerError(w http.ResponseWriter, r *http.Request, err error) {
	log.Printf("500 %s %s: %v", r.Method, r.URL.Path, err)
	writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
}

func writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func randomToken() string {
	buf := make([]byte, 24)
	_, _ = rand.Read(buf)
	return hex.EncodeToString(buf)
}


func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start))
	})
}

