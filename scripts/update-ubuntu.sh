#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH="${1:-main}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo/root." >&2
  exit 1
fi

pushd "${ROOT_DIR}" >/dev/null
git fetch origin
git checkout "${BRANCH}"
git pull --ff-only origin "${BRANCH}"
go build -o /usr/local/bin/status-hub ./cmd/hub
go build -o /usr/local/bin/status-collector ./cmd/collector
popd >/dev/null

systemctl restart status-hub
systemctl restart status-collector
systemctl --no-pager --full status status-hub status-collector
