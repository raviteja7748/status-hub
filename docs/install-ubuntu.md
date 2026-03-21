# Ubuntu Setup Guide

This is the supported deployment model for Status Hub.

## Final Setup Shape

- Ubuntu runs:
  - the **hub**
  - the **SQLite database**
  - the **collector**
- Your Mac runs only the menu bar app.
- Tailscale connects the Mac app to the Ubuntu hub privately.

If you want status even when you are far away, Ubuntu must keep running the hub and collector in the background.

## What you need before starting

Install these on Ubuntu:

```bash
sudo apt update
sudo apt install -y git curl build-essential
```

Then install Go:

```bash
cd /tmp
curl -LO https://go.dev/dl/go1.26.1.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.26.1.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc
go version
```

Optional, but useful:

- `docker` if you want Docker widget data
- `tailscale` if you want safe private access from your Mac

## If you already have SQLite

That is fine. You do not need a separate SQLite server.

This project uses a normal SQLite database file like:

```text
~/status-hub/status.db
```

The Go app reads and writes that file directly.

## Step-by-step install on Ubuntu

### 1. Get the code

```bash
git clone https://github.com/YOUR-USERNAME/status-hub.git
cd status-hub
```

### 2. Start the hub on Ubuntu

The easiest one-time install path is now:

```bash
sudo STATUS_ADMIN_PASSWORD=replace-me STATUS_DEVICE_TOKEN=replace-me ./scripts/install-ubuntu.sh
```

This script:

- builds `status-hub` and `status-collector`
- installs them into `/usr/local/bin`
- copies the repo into `/opt/status-hub`
- writes environment files under `/etc/status-hub`
- installs and starts both systemd services

If you want the manual source-run path instead, use:

```bash
go run ./cmd/hub -listen :8080 -db status.db -admin-password statusadmin -device-token my-device-token
```

What this does:

- starts the API server on port `8080`
- creates `status.db` if it does not exist
- uses `statusadmin` as the first login password
- requires the same `my-device-token` value your collector uses

### 3. Start the collector on the same Ubuntu machine

If you skipped the install script and want the manual source-run path, use:

```bash
go run ./cmd/collector -hub http://127.0.0.1:8080 -token my-device-token -name ubuntu-server
```

What this does:

- collects real system info from Ubuntu
- sends it to the hub
- auto-registers the device in the menu bar app

### 4. Make Ubuntu stay online all the time

For a real deployment, do not keep these in a terminal forever. Run them as services so they start again after reboot.

This repo already includes a collector service example:

[status-collector.service](/Users/elite/project/status%20/docs/deploy/status-collector.service)

And a hub service example:

[status-hub.service](/Users/elite/project/status%20/docs/deploy/status-hub.service)

The intended setup is:

- one service for `status-hub`
- one service for `status-collector`

### 5. Install the Mac app

The intended user-facing install path is:

- download the latest macOS app zip from GitHub Releases
- unzip it
- move the app into `Applications`
- open it and point it to your Ubuntu hub URL

Until the packaged release flow is published, you can run the app from source on your Mac:

```bash
cd /Users/elite/project/status\ /mac/StatusMenu
swift run
```

Then in the app settings:

- set Hub URL to `http://YOUR-UBUNTU-IP:8080`
- log in with password `statusadmin`

If you use Tailscale, use the Ubuntu Tailscale IP instead.

## Better production setup

For a cleaner Ubuntu setup, build binaries on Ubuntu:

```bash
go build -o status-hub ./cmd/hub
go build -o status-collector ./cmd/collector
```

Then run:

```bash
./status-hub -listen :8080 -db status.db -admin-password statusadmin -device-token my-device-token
./status-collector -hub http://127.0.0.1:8080 -token my-device-token -name ubuntu-server
```

## Update to a newer version later

After your first install, the intended update path is:

```bash
sudo /opt/status-hub/scripts/update-ubuntu.sh main
```

This pulls the latest code for the branch, rebuilds both binaries, and restarts the Ubuntu services.

## Make the services start automatically

Copy both files on Ubuntu:

```bash
sudo cp docs/deploy/status-hub.service /etc/systemd/system/status-hub.service
sudo cp docs/deploy/status-collector.service /etc/systemd/system/status-collector.service
sudo systemctl daemon-reload
sudo systemctl enable --now status-hub
sudo systemctl enable --now status-collector
```

Edit the service files first so the paths, password, token, and hub address match your machine.

## Optional things to install

- `docker`: needed only if you want Docker container status
- `tailscale`: needed only if you want private remote access from Mac

## Simple answer to your question

Yes. The correct always-on setup is:

- Ubuntu runs the hub
- Ubuntu runs the collector
- Mac runs only the menu bar app

You do not need a special Mac-side SSH helper to keep stats flowing 24/7.
