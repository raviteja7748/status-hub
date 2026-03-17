# Ubuntu Setup Guide

This project can run fully on your Ubuntu server.

## What stays on Ubuntu

Yes, for the first version you can keep the main backend on Ubuntu only:

- the **hub** runs on Ubuntu
- the **SQLite database** stays on Ubuntu
- the **collector** can also run on the same Ubuntu machine

Your Mac menu bar app connects to the Ubuntu hub.

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

## Step-by-step install

### 1. Get the code

If this becomes your public GitHub repo:

```bash
git clone https://github.com/YOUR-USERNAME/status-hub.git
cd status-hub
```

For now, if you copy the folder manually, just enter the project folder.

### 2. Start the hub on Ubuntu

```bash
go run ./cmd/hub -listen :8080 -db status.db -admin-password statusadmin
```

What this does:

- starts the API server on port `8080`
- creates `status.db` if it does not exist
- uses `statusadmin` as the first login password

### 3. Start the collector on the same Ubuntu machine

```bash
go run ./cmd/collector -hub http://127.0.0.1:8080 -token my-device-token -name ubuntu-server
```

What this does:

- collects real system info from Ubuntu
- sends it to the hub
- auto-registers the device in the menu bar app

### 4. Open the menu bar app from your Mac

Run the native menu bar app on your Mac:

```bash
cd /Users/elite/project/status\ /mac/StatusMenu
swift run
```

Then in the app settings:

- set Hub URL to `http://YOUR-UBUNTU-IP:8080`
- log in with password `statusadmin`

If you use Tailscale, use the Ubuntu Tailscale IP instead.

## Better production setup

For a cleaner Ubuntu setup, build binaries:

```bash
go build -o status-hub ./cmd/hub
go build -o status-collector ./cmd/collector
```

Then run:

```bash
./status-hub -listen :8080 -db status.db -admin-password statusadmin
./status-collector -hub http://127.0.0.1:8080 -token my-device-token -name ubuntu-server
```

## Make collector start automatically

Use the example service file:

[status-collector.service](/Users/elite/project/status%20/docs/deploy/status-collector.service)

Copy it on Ubuntu:

```bash
sudo cp docs/deploy/status-collector.service /etc/systemd/system/status-collector.service
sudo systemctl daemon-reload
sudo systemctl enable --now status-collector
```

## Optional things to install

- `docker`: needed only if you want Docker container status
- `tailscale`: needed only if you want private remote access from Mac

## Simple answer to your question

Yes, you can keep this on Ubuntu only for now.

The Ubuntu server can run:

- hub
- SQLite database
- collector

Then your Mac menu bar app connects to it.
