# Status Hub

Status Hub is a remote monitoring project for a Linux machine you want to watch from:

- a native macOS menu bar app
- self-hosted alerts through ntfy

The product has three moving parts:

- `cmd/hub`: Go hub API, SQLite persistence, websocket ingest, alert engine
- `cmd/collector`: Go Linux collector for system metrics, battery state, and Docker status
- `mac/StatusMenu`: SwiftUI menu bar client

## Supported Architecture

- Ubuntu runs the **hub** and **collector** all the time.
- Tailscale keeps Ubuntu and your Mac on the same private network.
- The macOS menu bar app is the only supported UI.
- The Mac app connects to the hub and shows live status from Ubuntu.

This means you do not need an SSH helper from the Mac. The always-on part lives on Ubuntu.

## What You Install Where

- On Ubuntu:
  - `status-hub`
  - `status-collector`
- On Mac:
  - the `StatusMenu` app

Detailed Ubuntu setup is in [docs/install-ubuntu.md](/Users/elite/project/status%20/docs/install-ubuntu.md).

## Distribution

The Mac app is packaged as:

- package a proper macOS `.app`
- publish a zip artifact through GitHub Releases
- let users download the latest release instead of building from source

The repo now includes:

- a packaging script at `scripts/package-macos-app.sh`
- a GitHub Actions workflow at `.github/workflows/release-macos.yml`

You can still run the Mac app from source locally with:

```bash
cd mac/StatusMenu
swift run
```

## Quick Start

### 1. Start the hub on Ubuntu

```bash
sudo STATUS_ADMIN_PASSWORD=replace-me STATUS_DEVICE_TOKEN=replace-me ./scripts/install-ubuntu.sh
```

This installs the binaries, writes systemd env files, and starts both services.

### 2. Open the Mac app

Use the packaged app from GitHub Releases when available.

For local source runs:

```bash
cd mac/StatusMenu
swift run
```

### 3. Update Ubuntu later

```bash
sudo /opt/status-hub/scripts/update-ubuntu.sh main
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

- v1 is single-user and optimized for self-hosting over Tailscale.
- GitHub widgets are intentionally out of scope for the first implementation.
- The macOS menu bar app is the supported operator UI.
- Alert delivery currently targets ntfy-compatible endpoints.
