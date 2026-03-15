# Codebase Bug Review - Status Hub

A comprehensive review of the codebase in `/home/elite/status-hub` has identified several bugs, potential issues, and areas for improvement.

## 1. Backend (Go)

### 1.1 Concurrency & Performance
- **Blocking Broadcasts (`internal/hub/server.go`):** The `broadcast` method holds `s.mu` (a `sync.Mutex`) while iterating and calling `conn.WriteMessage`. If a single WebSocket client is slow, it will block the entire server, including other WebSocket updates, session logins, and session validations, because they all share the same mutex.
- **Blocking Snapshot (`internal/collector/collector.go`):** `cpu.Percent(time.Second, false)` blocks for exactly 1 second to calculate the CPU percentage. This occurs during every collection cycle, which might delay other collection tasks or cause jitter in high-frequency monitoring.
- **SQLite Concurrency (`internal/hub/store.go`):** `db.SetMaxOpenConns(1)` is set. While this avoids "database is locked" errors with SQLite, it prevents concurrent reads even when WAL mode is enabled.

### 1.2 Collector Issues
- **Error Silencing:** Many calls in `collectSnapshot` and `readBattery` ignore errors (`_`). For example, if `host.Info()` or `mem.VirtualMemory()` fails, the collector might send partial or stale snapshots without logging the failure.
- **Battery Detection:** In `readBattery`, the loop might overwrite `acOnline` if multiple AC/ADP adapters are present. It also assumes `/sys/class/power_supply` entries for battery start with "BAT", which is common but not universal.
- **Docker Parsing:** `readDockerContainers` uses `exec.Command` for `docker ps`. If the output is extremely large, `cmd.Output()` might consume significant memory. It also assumes `docker` is in the PATH but doesn't handle permission issues gracefully (e.g., if the user is not in the `docker` group).

### 1.3 Logic & Stability
- **ID Churn (`internal/hub/store.go`):** `SaveWidgets` and `SaveAlertRules` delete all existing records and re-insert them. This causes the primary keys (UUIDs) to change every time settings are saved, which will break any external references or frontend state tracking that relies on stable IDs.
- **Dedupe Key collisions:** The `dedupeKey` for events is `deviceID + ":" + rule.ID`. If a rule is deleted and recreated with a new ID (due to the churn mentioned above), the dedupe logic will fail to recognize the old event, potentially causing duplicate alerts.
- **Websocket URL Scheme (`internal/collector/collector.go`):** `collectorWSURL` only switches `https` to `wss`. If the URL is `http`, it switches to `ws`. This is correct, but it doesn't handle other schemes or missing schemes gracefully.

## 2. Frontend (React / TypeScript)

### 2.1 React Hooks & State
- **Experimental Hook Usage (`web/src/App.tsx`):** `useEffectEvent` is used. This is an experimental React feature and is not available in standard stable React 19. It will likely cause a runtime error or build failure in a standard environment.
- **Infinite Update Loop / Excessive Rerenders:** The `useEffect` that manages the WebSocket calls `loadBootstrap` on every message. If `loadBootstrap` triggers a state change that somehow causes the server to broadcast a message (though unlikely in this specific app), it could loop. More importantly, it re-fetches the *entire* bootstrap state on every message, which is inefficient.
- **Transition Jitter:** `startTransition` is used for `setBootstrap`, but `setSelectedDeviceId` is called inside it. If `next.device?.id` is missing, it might reset the user's selected device unexpectedly during a background update.

### 2.2 API & Connectivity
- **WebSocket URL Construction:** `baseUrl.replace(/^http/, 'ws')` only replaces the first occurrence. If the URL is `https://...`, it becomes `wss://...`, but if the URL is `http://...`, it becomes `ws://...`. This is fine, but it doesn't handle `localhost:8080` without a protocol (which `resolveDefaultBaseUrl` might return).
- **Hardcoded Target:** `api.bootstrap` hardcodes `target=mobile_web`. While appropriate for a mobile companion, it limits the reuse of the API for other layouts (like the Mac menu bar mentioned in the UI).
- **LocalStorage Sync:** `resolveDefaultBaseUrl` has complex logic that might return `window.location.origin` even if a valid `localhost` URL is saved in `localStorage`, depending on the current origin.

### 2.3 UI / UX
- **Data Index Assumption:** `widgetValue` for `temperature` only checks `snapshot?.temperatures[0]`. If a device has multiple sensors, only the first one is ever shown, regardless of widget settings.
- **Error Handling:** When a WebSocket connection fails, there is no automatic reconnection logic beyond the component unmounting/remounting (which only happens if dependencies change).

## 3. General / Misc
- **Duplicate Code:** `envOrDefault` is implemented identically in both `cmd/collector/main.go` and `cmd/hub/main.go`.
- **Hardcoded Default Token:** `cmd/collector/main.go` hardcodes `device-demo-token` as a default. This is a security risk if users don't realize they should change it.
- **Admin Password:** The default admin password `statusadmin` is hardcoded in `cmd/hub/main.go`.
