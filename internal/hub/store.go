package hub

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"sort"
	"time"

	"github.com/elite/status/internal/model"
	"github.com/google/uuid"
	_ "modernc.org/sqlite"
)

type Store struct {
	db *sql.DB
}

func NewStore(path string) (*Store, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}

	store := &Store{db: db}
	return store, store.init()
}

func (s *Store) init() error {
	statements := []string{
		`create table if not exists devices (
			id text primary key,
			name text not null,
			token text not null unique,
			last_seen text not null,
			capabilities text not null,
			metadata text not null
		);`,
		`create table if not exists snapshots (
			device_id text primary key,
			payload text not null,
			collected_at text not null
		);`,
		`create table if not exists widgets (
			id text primary key,
			device_id text not null,
			kind text not null,
			title text not null,
			visible integer not null,
			display_order integer not null,
			size text not null,
			settings text not null
		);`,
		`create table if not exists alert_rules (
			id text primary key,
			device_id text not null,
			title text not null,
			metric text not null,
			condition text not null,
			threshold real not null,
			duration_seconds integer not null,
			severity text not null,
			channels text not null,
			enabled integer not null,
			resolve_behavior text not null
		);`,
		`create table if not exists events (
			id text primary key,
			device_id text not null,
			alert_rule_id text,
			type text not null,
			severity text not null,
			title text not null,
			body text not null,
			created_at text not null,
			resolved_at text,
			dedupe_key text not null unique
		);`,
		`create table if not exists notification_channels (
			id text primary key,
			kind text not null,
			name text not null,
			enabled integer not null,
			config text not null
		);`,
	}

	for _, stmt := range statements {
		if _, err := s.db.Exec(stmt); err != nil {
			return err
		}
	}

	return nil
}

func (s *Store) SeedDefaults() error {
	ctx := context.Background()
	channels, err := s.ListNotificationChannels(ctx)
	if err != nil {
		return err
	}
	if len(channels) == 0 {
		channel := model.NotificationChannel{
			ID:      uuid.NewString(),
			Kind:    "ntfy",
			Name:    "Phone Alerts",
			Enabled: false,
			Config: map[string]interface{}{
				"serverURL": "https://ntfy.sh",
				"topic":     "replace-me",
			},
		}
		if err := s.SaveNotificationChannels(ctx, []model.NotificationChannel{channel}); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) UpsertDevice(ctx context.Context, token, name string, capabilities map[string]bool, metadata map[string]string) (model.Device, error) {
	var id string
	err := s.db.QueryRowContext(ctx, `select id from devices where token = ?`, token).Scan(&id)
	now := time.Now().UTC().Format(time.RFC3339)
	caps, _ := json.Marshal(capabilities)
	meta, _ := json.Marshal(metadata)
	if errors.Is(err, sql.ErrNoRows) {
		id = uuid.NewString()
		_, err = s.db.ExecContext(ctx, `insert into devices (id, name, token, last_seen, capabilities, metadata) values (?, ?, ?, ?, ?, ?)`,
			id, name, token, now, string(caps), string(meta))
		if err != nil {
			return model.Device{}, err
		}
		if err := s.SaveWidgets(ctx, id, DefaultWidgets(id)); err != nil {
			return model.Device{}, err
		}
		if err := s.SaveAlertRules(ctx, id, DefaultAlertRules(id)); err != nil {
			return model.Device{}, err
		}
	} else if err != nil {
		return model.Device{}, err
	} else {
		_, err = s.db.ExecContext(ctx, `update devices set name = ?, last_seen = ?, capabilities = ?, metadata = ? where id = ?`,
			name, now, string(caps), string(meta), id)
		if err != nil {
			return model.Device{}, err
		}
	}

	return s.GetDeviceByID(ctx, id)
}

func (s *Store) GetDeviceByID(ctx context.Context, id string) (model.Device, error) {
	var (
		device     model.Device
		lastSeen   string
		capsJSON   string
		metaJSON   string
		snapshotJS sql.NullString
	)
	err := s.db.QueryRowContext(ctx, `
		select d.id, d.name, d.last_seen, d.capabilities, d.metadata, coalesce(s.payload, '')
		from devices d
		left join snapshots s on s.device_id = d.id
		where d.id = ?`, id).Scan(&device.ID, &device.Name, &lastSeen, &capsJSON, &metaJSON, &snapshotJS)
	if err != nil {
		return model.Device{}, err
	}
	parseDeviceFields(&device, lastSeen, capsJSON, metaJSON, snapshotJS.String)
	return device, nil
}

func (s *Store) GetDeviceByToken(ctx context.Context, token string) (model.Device, error) {
	var id string
	if err := s.db.QueryRowContext(ctx, `select id from devices where token = ?`, token).Scan(&id); err != nil {
		return model.Device{}, err
	}
	return s.GetDeviceByID(ctx, id)
}

func parseDeviceFields(device *model.Device, lastSeen, capsJSON, metaJSON, snapshotJSON string) {
	device.LastSeen, _ = time.Parse(time.RFC3339, lastSeen)
	_ = json.Unmarshal([]byte(capsJSON), &device.Capabilities)
	_ = json.Unmarshal([]byte(metaJSON), &device.Metadata)
	if snapshotJSON != "" {
		var snapshot model.Snapshot
		if json.Unmarshal([]byte(snapshotJSON), &snapshot) == nil {
			device.Snapshot = &snapshot
		}
	}
	device.Online = time.Since(device.LastSeen) < 90*time.Second
	device.AlertState = "healthy"
}

func (s *Store) ListDevices(ctx context.Context) ([]model.Device, error) {
	rows, err := s.db.QueryContext(ctx, `
		select d.id, d.name, d.last_seen, d.capabilities, d.metadata, coalesce(s.payload, '')
		from devices d
		left join snapshots s on s.device_id = d.id
		order by d.name asc`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var devices []model.Device
	for rows.Next() {
		var (
			device       model.Device
			lastSeen     string
			capsJSON     string
			metaJSON     string
			snapshotJSON string
		)
		if err := rows.Scan(&device.ID, &device.Name, &lastSeen, &capsJSON, &metaJSON, &snapshotJSON); err != nil {
			return nil, err
		}
		parseDeviceFields(&device, lastSeen, capsJSON, metaJSON, snapshotJSON)
		devices = append(devices, device)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	active, err := s.ListActiveEvents(ctx)
	if err == nil {
		stateByDevice := map[string]string{}
		for _, event := range active {
			current := stateByDevice[event.DeviceID]
			if current == "" || severityRank(event.Severity) > severityRank(current) {
				stateByDevice[event.DeviceID] = event.Severity
			}
		}
		for i := range devices {
			if state := stateByDevice[devices[i].ID]; state != "" {
				devices[i].AlertState = state
			}
		}
	}

	return devices, nil
}

func severityRank(severity string) int {
	switch severity {
	case "critical":
		return 3
	case "warning":
		return 2
	case "info":
		return 1
	default:
		return 0
	}
}

func (s *Store) SaveSnapshot(ctx context.Context, deviceID string, snapshot model.Snapshot) error {
	payload, _ := json.Marshal(snapshot)
	_, err := s.db.ExecContext(ctx, `
		insert into snapshots (device_id, payload, collected_at) values (?, ?, ?)
		on conflict(device_id) do update set payload = excluded.payload, collected_at = excluded.collected_at`,
		deviceID, string(payload), snapshot.CollectedAt.Format(time.RFC3339))
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `update devices set last_seen = ? where id = ?`, time.Now().UTC().Format(time.RFC3339), deviceID)
	return err
}

func (s *Store) ListWidgets(ctx context.Context, deviceID string) ([]model.Widget, error) {
	rows, err := s.db.QueryContext(ctx, `
		select id, kind, device_id, title, visible, display_order, size, settings
		from widgets where device_id = ?
		order by display_order asc`, deviceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var widgets []model.Widget
	for rows.Next() {
		var widget model.Widget
		var visible int
		var settings string
		if err := rows.Scan(&widget.ID, &widget.Kind, &widget.DeviceID, &widget.Title, &visible, &widget.Order, &widget.Size, &settings); err != nil {
			return nil, err
		}
		widget.Visible = visible == 1
		_ = json.Unmarshal([]byte(settings), &widget.Settings)
		if widget.Settings == nil {
			widget.Settings = map[string]interface{}{}
		}
		widgets = append(widgets, widget)
	}
	return widgets, rows.Err()
}

func (s *Store) SaveWidgets(ctx context.Context, deviceID string, widgets []model.Widget) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `delete from widgets where device_id = ?`, deviceID); err != nil {
		return err
	}
	sort.Slice(widgets, func(i, j int) bool { return widgets[i].Order < widgets[j].Order })
	for i := range widgets {
		widgets[i].DeviceID = deviceID
		if widgets[i].ID == "" {
			widgets[i].ID = uuid.NewString()
		}
		settings, _ := json.Marshal(widgets[i].Settings)
		if _, err := tx.ExecContext(ctx, `insert into widgets (id, device_id, kind, title, visible, display_order, size, settings) values (?, ?, ?, ?, ?, ?, ?, ?)`,
			widgets[i].ID, deviceID, widgets[i].Kind, widgets[i].Title, boolToInt(widgets[i].Visible), widgets[i].Order, widgets[i].Size, string(settings)); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) ListAlertRules(ctx context.Context, deviceID string) ([]model.AlertRule, error) {
	rows, err := s.db.QueryContext(ctx, `
		select id, device_id, title, metric, condition, threshold, duration_seconds, severity, channels, enabled, resolve_behavior
		from alert_rules where device_id = ?
		order by title asc`, deviceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var rules []model.AlertRule
	for rows.Next() {
		var rule model.AlertRule
		var enabled int
		var channels string
		if err := rows.Scan(&rule.ID, &rule.DeviceID, &rule.Title, &rule.Metric, &rule.Condition, &rule.Threshold, &rule.DurationSeconds, &rule.Severity, &channels, &enabled, &rule.ResolveBehavior); err != nil {
			return nil, err
		}
		rule.Enabled = enabled == 1
		_ = json.Unmarshal([]byte(channels), &rule.Channels)
		rules = append(rules, rule)
	}
	return rules, rows.Err()
}

func (s *Store) SaveAlertRules(ctx context.Context, deviceID string, rules []model.AlertRule) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `delete from alert_rules where device_id = ?`, deviceID); err != nil {
		return err
	}
	for _, rule := range rules {
		if rule.ID == "" {
			rule.ID = uuid.NewString()
		}
		rule.DeviceID = deviceID
		channels, _ := json.Marshal(rule.Channels)
		if _, err := tx.ExecContext(ctx, `
			insert into alert_rules (id, device_id, title, metric, condition, threshold, duration_seconds, severity, channels, enabled, resolve_behavior)
			values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			rule.ID, rule.DeviceID, rule.Title, rule.Metric, rule.Condition, rule.Threshold, rule.DurationSeconds, rule.Severity, string(channels), boolToInt(rule.Enabled), rule.ResolveBehavior); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) SaveEvent(ctx context.Context, event model.Event) error {
	var resolved *string
	if event.ResolvedAt != nil {
		value := event.ResolvedAt.Format(time.RFC3339)
		resolved = &value
	}
	_, err := s.db.ExecContext(ctx, `
		insert into events (id, device_id, alert_rule_id, type, severity, title, body, created_at, resolved_at, dedupe_key)
		values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		event.ID, event.DeviceID, event.AlertRuleID, event.Type, event.Severity, event.Title, event.Body, event.CreatedAt.Format(time.RFC3339), resolved, event.DedupeKey)
	return err
}

func (s *Store) FindActiveEventByDedupeKey(ctx context.Context, dedupeKey string) (*model.Event, error) {
	row := s.db.QueryRowContext(ctx, `
		select id, device_id, alert_rule_id, type, severity, title, body, created_at, resolved_at, dedupe_key
		from events where dedupe_key = ? and resolved_at is null`, dedupeKey)
	var (
		event      model.Event
		createdAt  string
		resolvedAt sql.NullString
	)
	err := row.Scan(&event.ID, &event.DeviceID, &event.AlertRuleID, &event.Type, &event.Severity, &event.Title, &event.Body, &createdAt, &resolvedAt, &event.DedupeKey)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	event.CreatedAt, _ = time.Parse(time.RFC3339, createdAt)
	if resolvedAt.Valid {
		when, _ := time.Parse(time.RFC3339, resolvedAt.String)
		event.ResolvedAt = &when
	}
	return &event, nil
}

func (s *Store) ResolveEvent(ctx context.Context, eventID string) error {
	_, err := s.db.ExecContext(ctx, `update events set resolved_at = ? where id = ?`, time.Now().UTC().Format(time.RFC3339), eventID)
	return err
}

func (s *Store) ListEvents(ctx context.Context, deviceID string) ([]model.Event, error) {
	query := `
		select id, device_id, alert_rule_id, type, severity, title, body, created_at, resolved_at, dedupe_key
		from events`
	var args []interface{}
	if deviceID != "" {
		query += ` where device_id = ?`
		args = append(args, deviceID)
	}
	query += ` order by created_at desc limit 100`
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []model.Event
	for rows.Next() {
		var (
			event      model.Event
			createdAt  string
			resolvedAt sql.NullString
		)
		if err := rows.Scan(&event.ID, &event.DeviceID, &event.AlertRuleID, &event.Type, &event.Severity, &event.Title, &event.Body, &createdAt, &resolvedAt, &event.DedupeKey); err != nil {
			return nil, err
		}
		event.CreatedAt, _ = time.Parse(time.RFC3339, createdAt)
		if resolvedAt.Valid {
			when, _ := time.Parse(time.RFC3339, resolvedAt.String)
			event.ResolvedAt = &when
		}
		events = append(events, event)
	}
	return events, rows.Err()
}

func (s *Store) ListActiveEvents(ctx context.Context) ([]model.Event, error) {
	rows, err := s.db.QueryContext(ctx, `
		select id, device_id, alert_rule_id, type, severity, title, body, created_at, resolved_at, dedupe_key
		from events where resolved_at is null order by created_at desc`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []model.Event
	for rows.Next() {
		var (
			event     model.Event
			createdAt string
			resolved  sql.NullString
		)
		if err := rows.Scan(&event.ID, &event.DeviceID, &event.AlertRuleID, &event.Type, &event.Severity, &event.Title, &event.Body, &createdAt, &resolved, &event.DedupeKey); err != nil {
			return nil, err
		}
		event.CreatedAt, _ = time.Parse(time.RFC3339, createdAt)
		events = append(events, event)
	}
	return events, rows.Err()
}

func (s *Store) ListNotificationChannels(ctx context.Context) ([]model.NotificationChannel, error) {
	rows, err := s.db.QueryContext(ctx, `select id, kind, name, enabled, config from notification_channels order by name asc`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var channels []model.NotificationChannel
	for rows.Next() {
		var channel model.NotificationChannel
		var enabled int
		var config string
		if err := rows.Scan(&channel.ID, &channel.Kind, &channel.Name, &enabled, &config); err != nil {
			return nil, err
		}
		channel.Enabled = enabled == 1
		_ = json.Unmarshal([]byte(config), &channel.Config)
		channels = append(channels, channel)
	}
	return channels, rows.Err()
}

func (s *Store) SaveNotificationChannels(ctx context.Context, channels []model.NotificationChannel) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `delete from notification_channels`); err != nil {
		return err
	}
	for _, channel := range channels {
		if channel.ID == "" {
			channel.ID = uuid.NewString()
		}
		config, _ := json.Marshal(channel.Config)
		if _, err := tx.ExecContext(ctx, `insert into notification_channels (id, kind, name, enabled, config) values (?, ?, ?, ?, ?)`,
			channel.ID, channel.Kind, channel.Name, boolToInt(channel.Enabled), string(config)); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func boolToInt(value bool) int {
	if value {
		return 1
	}
	return 0
}
