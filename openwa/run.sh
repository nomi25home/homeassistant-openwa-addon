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

print(str(value).strip())
PY
}

# Resolve a secret: use the configured value unless it is empty or the shipped placeholder;
# otherwise reuse a persisted random key (generated once on first boot). This keeps the engine's
# seeded key and the helper's key stable across restarts without ever shipping a real default secret.
resolve_secret() {
  local value="$1" file="$2" generated
  if [ -n "$value" ] && [ "$value" != "CHANGE_ME_TO_A_LONG_RANDOM_SECRET" ]; then
    printf '%s' "$value"
    return 0
  fi
  if [ -s "$file" ]; then
    cat "$file"
    return 0
  fi
  generated="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
  generated="${generated:0:32}"
  ( umask 077; printf '%s' "$generated" >"$file" )
  printf '%s' "$generated"
}

# Resolve the native engine key. The engine seeds its key only ONCE (on an empty DB), so to keep the
# helper matching it across restarts AND upgrades, prefer in order: explicit option > our persisted
# file > the raw key the engine already seeded on a prior boot (/data/openwa/.api-key) > a fresh key.
resolve_engine_key() {
  local opt="$1" generated
  if [ -n "$opt" ] && [ "$opt" != "CHANGE_ME_TO_A_LONG_RANDOM_SECRET" ]; then
    printf '%s' "$opt"
    return 0
  fi
  if [ -s "/data/openwa_api_key.txt" ]; then
    cat "/data/openwa_api_key.txt"
    return 0
  fi
  if [ -s "${OPENWA_DATA_DIR}/.api-key" ]; then
    cat "${OPENWA_DATA_DIR}/.api-key"
    return 0
  fi
  generated="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
  printf '%s' "${generated:0:32}"
}

LOG_LEVEL="$(read_option log_level "info")"
SESSION_ID="$(read_option session_id "")"

# Native engine key (port 2785): used by the helper AND the companion HACS integration.
OPENWA_API_KEY="$(resolve_engine_key "$(read_option openwa_api_key "")")"
# Keep the file the helper reads in sync with the resolved key (single source of truth).
( umask 077; printf '%s' "$OPENWA_API_KEY" >/data/openwa_api_key.txt )
# Helper inbound key (port 2786, X-API-Key). The helper reads the same file.
HELPER_MASTER_KEY="$(resolve_secret "$(read_option api_master_key "")" "/data/master_key.txt")"

export NODE_ENV=production

# Persist OpenWA data across add-on restarts. Runs as root (the add-on overrides the upstream
# entrypoint with ENTRYPOINT ["/run.sh"]), so it can rewrite /app/data freely.
if [ ! -L "/app/data" ]; then
  mkdir -p /app
  rm -rf /app/data
  ln -s "${OPENWA_DATA_DIR}" /app/data
fi

# Chromium writes its config/cache under these XDG dirs (set as ENV in the base image). The upstream
# entrypoint normally creates them; we replace it, so create them here or Chromium can crash at launch.
mkdir -p "${XDG_CONFIG_HOME:-/tmp/.config}" "${XDG_CACHE_HOME:-/tmp/.cache}"

# Clear stale Chromium singleton locks left by an unclean shutdown; otherwise a relinked session fails
# to relaunch ("profile appears to be in use"). Safe: no Chromium is running this early.
rm -f "${OPENWA_DATA_DIR}/sessions/"*/Singleton* 2>/dev/null || true

export PORT=2785
export LOG_LEVEL="${LOG_LEVEL}"

export DATABASE_TYPE=sqlite
export DATABASE_NAME="${OPENWA_DATA_DIR}/openwa.sqlite"
export DATABASE_SYNCHRONIZE=false
# Auth/audit DB (holds the seeded API key). Pin it onto the persistent volume explicitly.
export MAIN_DATABASE_NAME="${OPENWA_DATA_DIR}/main.sqlite"

export ENGINE_TYPE=whatsapp-web.js
export SESSION_DATA_PATH="${OPENWA_DATA_DIR}/sessions"
export PUPPETEER_HEADLESS=true
export PUPPETEER_ARGS="--no-sandbox,--disable-setuid-sandbox,--disable-dev-shm-usage,--disable-gpu"

export STORAGE_TYPE=local
export STORAGE_LOCAL_PATH="${OPENWA_DATA_DIR}/media"

export WEBHOOK_TIMEOUT=10000
export WEBHOOK_MAX_RETRIES=3
export WEBHOOK_RETRY_DELAY=5000

export PLUGINS_DIR="${OPENWA_DATA_DIR}/plugins"

# Resume an already-linked session automatically after an add-on restart.
export AUTO_START_SESSIONS=true

# The engine seeds its native admin key from API_MASTER_KEY on first boot — seed it with the
# native key the helper and companion integration use.
export API_MASTER_KEY="${OPENWA_API_KEY}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🟢 OpenWA Home Assistant Add-on"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🔑 OpenWA native API key (port 2785, also for the companion integration):"
echo "     ${OPENWA_API_KEY}"
echo "  🔑 Helper API key (port 2786, send it as the X-API-Key header):"
echo "     ${HELPER_MASTER_KEY}"
echo "  🔗 Session ID: ${SESSION_ID:-auto (created on first QR scan)}"
echo "  First time? Open the add-on Web UI (sidebar panel) and scan the QR code with"
echo "  WhatsApp → Linked Devices → Link a Device."
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
