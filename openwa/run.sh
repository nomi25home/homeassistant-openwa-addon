#!/usr/bin/env bash
set -euo pipefail

OPTIONS_FILE="/data/options.json"
OPENWA_DATA_DIR="/data/openwa"

mkdir -p "${OPENWA_DATA_DIR}/sessions"
mkdir -p "${OPENWA_DATA_DIR}/media"
mkdir -p "${OPENWA_DATA_DIR}/plugins"

read_option() {
  local key="$1"
  local default_value="$2"

  python3 - "$OPTIONS_FILE" "$key" "$default_value" <<'PY'
import json
import sys

path = sys.argv[1]
key = sys.argv[2]
default_value = sys.argv[3]

try:
    with open(path, "r", encoding="utf-8") as file:
        data = json.load(file)
except Exception:
    print(default_value)
    raise SystemExit(0)

value = data.get(key, default_value)
if value is None:
    value = default_value

print(value)
PY
}

API_MASTER_KEY="$(read_option api_master_key "")"
LOG_LEVEL="$(read_option log_level "info")"
OPENWA_API_KEY="$(read_option openwa_api_key "")"
SESSION_ID="$(read_option session_id "")"

export NODE_ENV=production

mkdir -p "${OPENWA_DATA_DIR}"

# Ensure the native API uses the configured key.
if [ -n "$OPENWA_API_KEY" ]; then
  echo "API_KEY=${OPENWA_API_KEY}" > "${OPENWA_DATA_DIR}/.env.generated"
fi

export PORT=2785
export LOG_LEVEL="${LOG_LEVEL}"

export DATABASE_TYPE=sqlite
export DATABASE_NAME="${OPENWA_DATA_DIR}/openwa.sqlite"
export DATABASE_SYNCHRONIZE=false

export ENGINE_TYPE=whatsapp-web.js
export SESSION_DATA_PATH="${OPENWA_DATA_DIR}/sessions"
export PUPPETEER_HEADLESS=true
export PUPPETEER_ARGS="--no-sandbox,--disable-setuid-sandbox,--disable-dev-shm-usage,--disable-gpu"

export STORAGE_TYPE=local
export STORAGE_LOCAL_PATH="${OPENWA_DATA_DIR}/media"

export REDIS_ENABLED=false

export WEBHOOK_TIMEOUT=10000
export WEBHOOK_MAX_RETRIES=3
export WEBHOOK_RETRY_DELAY=5000

export RATE_LIMIT_TTL=60
export RATE_LIMIT_MAX=100

export PLUGINS_ENABLED=true
export PLUGINS_DIR="${OPENWA_DATA_DIR}/plugins"

export API_MASTER_KEY="${API_MASTER_KEY}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🟢 OpenWA Home Assistant Add-on"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$OPENWA_API_KEY" ]; then
  echo "  💡 Automated Setup:"
  echo "  The add-on will automatically manage your session."
  echo "  🔑 Session ID: ${SESSION_ID:-None (will be generated)}"
  echo "  If this is your first time, please scan the QR code at:"
  echo "  http://homeassistant.local:2786/qr"
else
  echo "  ⚠️  openwa_api_key is not configured."
  echo "  Set openwa_api_key in the add-on options before using QR/session features."
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cleanup() {
  echo "[OpenWA Add-on] Stopping services..."

  if [ -n "${HELPER_PID:-}" ]; then
    kill "${HELPER_PID}" 2>/dev/null || true
  fi

  if [ -n "${OPENWA_PID:-}" ]; then
    kill "${OPENWA_PID}" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

start_openwa() {
  cd /app 2>/dev/null || true

  if [ -f "/app/dist/main.js" ]; then
    node /app/dist/main.js &
    OPENWA_PID="$!"
    return 0
  fi

  if [ -f "/app/dist/src/main.js" ]; then
    node /app/dist/src/main.js &
    OPENWA_PID="$!"
    return 0
  fi

  if [ -f "dist/main.js" ]; then
    node dist/main.js &
    OPENWA_PID="$!"
    return 0
  fi

  if [ -f "dist/src/main.js" ]; then
    node dist/src/main.js &
    OPENWA_PID="$!"
    return 0
  fi

  if command -v npm >/dev/null 2>&1; then
    npm run start:prod &
    OPENWA_PID="$!"
    return 0
  fi

  echo "[OpenWA Add-on] Could not find OpenWA start command."
  return 1
}

wait_for_openwa() {
  local timeout="${1:-90}"
  local elapsed=0

  echo "[OpenWA Add-on] Waiting for OpenWA API on port 2785..."

  while [ "$elapsed" -lt "$timeout" ]; do
    if curl -fsS "http://127.0.0.1:2785/api/health" >/dev/null 2>&1; then
      echo "[OpenWA Add-on] OpenWA API is healthy."
      return 0
    fi

    if ! kill -0 "${OPENWA_PID}" 2>/dev/null; then
      echo "[OpenWA Add-on] OpenWA process exited before becoming healthy."
      return 1
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo "[OpenWA Add-on] Timed out waiting for OpenWA API."
  return 1
}

echo "[OpenWA Add-on] Starting OpenWA API on port 2785..."
echo "[OpenWA Add-on] Data directory: ${OPENWA_DATA_DIR}"

start_openwa

wait_for_openwa 90 || {
  echo "[OpenWA Add-on] OpenWA did not become healthy. Check logs above."
  wait "${OPENWA_PID}" || true
  exit 1
}

echo "[OpenWA Add-on] Starting helper server on port 2786..."
python3 /usr/local/bin/helper_server.py &
HELPER_PID="$!"

wait -n "${OPENWA_PID}" "${HELPER_PID}"
