#!/usr/bin/env bash
#############################################################################
# Script 4: Add New Docker Service to Stack
# Fully integrated with AIPlatformAutomation
# Updates docker-compose.yml, .env, and post-deployment summary
#############################################################################

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/compose/docker-compose.yml"
ENV_FILE="$ROOT_DIR/config/.env"
SUMMARY_FILE="$ROOT_DIR/config/service_summary.txt"

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { log "ERROR: $*"; exit 1; }
pause() { read -rp "Press ENTER to continue..."; }
prompt_yn() { local p="$1"; local d="${2:-y}"; local c; while true; do \
    read -rp "$p [y/n] (default: $d): " c; c="${c:-$d}"; \
    case "$c" in y|Y) return 0 ;; n|N) return 1 ;; *) echo "Please answer y or n." ;; esac; done; }

# --------------------------------------------------
# STEP 0 — Environment check
# --------------------------------------------------
[[ -f "$COMPOSE_FILE" ]] || fail "docker-compose.yml not found at $COMPOSE_FILE"
[[ -f "$ENV_FILE" ]] || fail ".env file not found at $ENV_FILE"

# Load existing env variables
set -o allexport
source "$ENV_FILE"
set +o allexport

# --------------------------------------------------
# STEP 1 — Prompt for service info
# --------------------------------------------------
echo "=== ADD NEW SERVICE TO AI PLATFORM STACK ==="
read -rp "Docker image name: " IMAGE_NAME
read -rp "Service name (unique, letters/numbers/underscores): " SERVICE_NAME
[[ "$SERVICE_NAME" =~ ^[a-zA-Z0-9_]+$ ]] || fail "Invalid service name"

# Check port availability
while true; do
  read -rp "Internal container port: " INTERNAL_PORT
  if lsof -iTCP -sTCP:LISTEN -P -n | grep -q ":$INTERNAL_PORT"; then
    echo "Port $INTERNAL_PORT is in use. Pick another."
  else
    break
  fi
done

read -rp "External host port (ENTER = same as internal): " EXTERNAL_PORT
EXTERNAL_PORT="${EXTERNAL_PORT:-$INTERNAL_PORT}"

# --------------------------------------------------
# STEP 2 — Update docker-compose.yml
# --------------------------------------------------
SERVICE_YAML=$(cat <<EOF

$SERVICE_NAME:
  image: $IMAGE_NAME
  container_name: $SERVICE_NAME
  restart: unless-stopped
  networks:
    - ai-platform
  ports:
    - "$EXTERNAL_PORT:$INTERNAL_PORT"
  volumes:
    - ${SERVICE_NAME}_data:/data
EOF
)

echo "$SERVICE_YAML" >> "$COMPOSE_FILE"
log "Service $SERVICE_NAME appended to docker-compose.yml"

# --------------------------------------------------
# STEP 3 — Update .env
# --------------------------------------------------
echo "SERVICE_${SERVICE_NAME}=true" >> "$ENV_FILE"
echo "PORT_${SERVICE_NAME}=$EXTERNAL_PORT" >> "$ENV_FILE"
log ".env updated with $SERVICE_NAME"

# --------------------------------------------------
# STEP 4 — Deploy service
# --------------------------------------------------
cd "$ROOT_DIR/compose"
docker compose up -d "$SERVICE_NAME"
log "$SERVICE_NAME deployed!"

# --------------------------------------------------
# STEP 5 — Update summary
# --------------------------------------------------
echo "$SERVICE_NAME -> http://$(hostname -I | awk '{print $1}'):$EXTERNAL_PORT/" >> "$SUMMARY_FILE"
log "Service summary updated at $SUMMARY_FILE"

log "✅ Service $SERVICE_NAME added successfully!"
pause
