#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_ROOT="/opt/status-hub"
CONFIG_ROOT="/etc/status-hub"
DATA_ROOT="/var/lib/status-hub"
BIN_DIR="/usr/local/bin"

ADMIN_PASSWORD="${STATUS_ADMIN_PASSWORD:-}"
DEVICE_TOKEN="${STATUS_DEVICE_TOKEN:-}"
DEVICE_NAME="${STATUS_DEVICE_NAME:-ubuntu-server}"
HUB_URL="${STATUS_HUB_URL:-http://127.0.0.1:8080}"
LISTEN_ADDR="${STATUS_LISTEN_ADDR:-:8080}"
DB_PATH="${STATUS_DB_PATH:-${DATA_ROOT}/status.db}"

usage() {
  cat <<'EOF'
Usage:
  sudo STATUS_ADMIN_PASSWORD=... STATUS_DEVICE_TOKEN=... [STATUS_DEVICE_NAME=ubuntu-server] [STATUS_HUB_URL=http://127.0.0.1:8080] ./scripts/install-ubuntu.sh

This script:
  - builds status-hub and status-collector
  - installs binaries into /usr/local/bin
  - installs systemd unit files
  - writes config env files under /etc/status-hub
  - enables and starts both services
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo/root." >&2
  exit 1
fi

if [[ -z "${ADMIN_PASSWORD}" || -z "${DEVICE_TOKEN}" ]]; then
  echo "STATUS_ADMIN_PASSWORD and STATUS_DEVICE_TOKEN are required." >&2
  usage
  exit 1
fi

mkdir -p "${INSTALL_ROOT}" "${CONFIG_ROOT}" "${DATA_ROOT}" "${BIN_DIR}"

if [[ "${ROOT_DIR}" != "${INSTALL_ROOT}" ]]; then
  cp -a "${ROOT_DIR}/." "${INSTALL_ROOT}/"
fi

pushd "${INSTALL_ROOT}" >/dev/null
go build -o "${BIN_DIR}/status-hub" ./cmd/hub
go build -o "${BIN_DIR}/status-collector" ./cmd/collector
popd >/dev/null

cat > "${CONFIG_ROOT}/status-hub.env" <<EOF
STATUS_LISTEN_ADDR=${LISTEN_ADDR}
STATUS_DB_PATH=${DB_PATH}
STATUS_ADMIN_PASSWORD=${ADMIN_PASSWORD}
EOF

cat > "${CONFIG_ROOT}/status-collector.env" <<EOF
STATUS_HUB_URL=${HUB_URL}
STATUS_DEVICE_TOKEN=${DEVICE_TOKEN}
STATUS_DEVICE_NAME=${DEVICE_NAME}
EOF

install -m 0644 "${INSTALL_ROOT}/docs/deploy/status-hub.service" /etc/systemd/system/status-hub.service
install -m 0644 "${INSTALL_ROOT}/docs/deploy/status-collector.service" /etc/systemd/system/status-collector.service

systemctl daemon-reload
systemctl enable --now status-hub
systemctl enable --now status-collector

echo "Installed and started:"
echo "  - status-hub"
echo "  - status-collector"
echo
echo "Config files:"
echo "  - ${CONFIG_ROOT}/status-hub.env"
echo "  - ${CONFIG_ROOT}/status-collector.env"
echo "Installed repo copy:"
echo "  - ${INSTALL_ROOT}"
