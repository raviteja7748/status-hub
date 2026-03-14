# Status Hub

Status Hub is a no-AI, open-source remote monitoring platform for a Linux device you want to watch from:

- a native macOS menu bar app
- a mobile-friendly web dashboard
- self-hosted alerts through ntfy

It is built as a starter monorepo with:

- `cmd/hub`: Go hub API, SQLite persistence, websocket ingest, alert engine
- `cmd/collector`: Go Linux collector for system metrics, battery state, and Docker status
- `web`: React + TypeScript PWA dashboard
- `mac/StatusMenu`: SwiftUI menu bar client

## Current MVP

- collector websocket connection to the hub
- persistent device, widget, alert, event, and notification channel storage
- default widget presets and alert presets
- editable widget visibility/order from the dashboard
- editable thresholds and ntfy notification settings
- live device/event updates for the web dashboard
- a starter macOS menu bar client that logs in and shows device summaries

## Quick Start

Detailed Ubuntu instructions are in [docs/install-ubuntu.md](/Users/elite/project/status%20/docs/install-ubuntu.md).

### 1. Run the hub

```bash
go run ./cmd/hub -listen :8080 -admin-password statusadmin
```

### 2. Run the collector

```bash
go run ./cmd/collector -hub http://localhost:8080 -token my-device-token -name old-linux-laptop
```

The first collector connection auto-registers the device and seeds default widgets and alerts.

### 3. Run the web dashboard

```bash
cd web
npm install
npm run dev
```

Open the shown Vite URL, point it to your hub, and sign in with the hub admin password.

### 4. Run the Mac menu bar app

```bash
cd mac/StatusMenu
swift run
```

## Environment Variables

- `STATUS_LISTEN_ADDR`
- `STATUS_DB_PATH`
- `STATUS_ADMIN_PASSWORD`
- `STATUS_PUBLIC_URL`
- `STATUS_HUB_URL`
- `STATUS_DEVICE_TOKEN`
- `STATUS_DEVICE_NAME`

## Notes

- v1 is single-user and optimized for self-hosting over Tailscale or another VPN.
- GitHub widgets are intentionally out of scope for the first implementation.
- Browser push is not wired yet; alert delivery currently targets ntfy-compatible endpoints.
