#!/usr/bin/env bash
#############################################################################
# Script 2 — Deploy Services (Modular Docker Compose)
# Collects individual service YML fragments, builds a full stack, deploys
# Stepwise deployment with health checks, logs, summary
#############################################################################

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/config"
COMPOSE_DIR="$ROOT_DIR/compose"
DEPLOY_LOG_DIR="/mnt/data/logs"
DEPLOY_LOG="$DEPLOY_LOG_DIR/deploy.log"
SUMMARY_FILE="$CONFIG_DIR/service_deploy_summary.txt"

mkdir -p "$DEPLOY_LOG_DIR"
touch "$DEPLOY_LOG"
touch "$SUMMARY_FILE"

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$DEPLOY_LOG"; }
fail() { log "ERROR: $*"; exit 1; }
pause() { read -rp "Press ENTER to continue..."; }

# --------------------------------------------------
# STEP 0 — Load environment
# --------------------------------------------------
[[ -f "$CONFIG_DIR/.env" ]] || fail ".env file missing! Run Script 1 first."
set -o allexport
source "$CONFIG_DIR/.env"
set +o allexport
log "Loaded configuration from $CONFIG_DIR/.env"

# --------------------------------------------------
# STEP 1 — Define service categories
# --------------------------------------------------
CORE_SERVICES=("Ollama" "AnythingLLM" "LiteLLM")
AI_STACK=("Dify" "ComfyUI" "OpenWebUI" "OpenClaw_UI" "Flowise" "n8n" "SuperTokens")
OPTIONAL_SERVICES=("Grafana" "Prometheus" "ELK" "Portainer")

ALL_SERVICES=("${CORE_SERVICES[@]}" "${AI_STACK[@]}" "${OPTIONAL_SERVICES[@]}")

# Compose output
FINAL_COMPOSE="$COMPOSE_DIR/docker-compose.yml"
echo "version: '3.9'" > "$FINAL_COMPOSE"
echo "services:" >> "$FINAL_COMPOSE"

# --------------------------------------------------
# STEP 2 — Merge individual service YML fragments
# --------------------------------------------------
log "Collecting individual service compose files..."
for svc in "${ALL_SERVICES[@]}"; do
    if [[ "${!SERVICE_$svc:-false}" != true ]]; then
        log "Skipping $svc (not selected)"
        continue
    fi

    FRAGMENT_FILE="$COMPOSE_DIR/services/${svc}.yml"
    if [[ ! -f "$FRAGMENT_FILE" ]]; then
        log "WARNING: Compose fragment missing for $svc → $FRAGMENT_FILE"
        continue
    fi

    log "Merging $svc compose fragment..."
    # Indent fragment and append to final compose
    sed 's/^/  /' "$FRAGMENT_FILE" >> "$FINAL_COMPOSE"
done

log "Merged compose file written to $FINAL_COMPOSE"

# --------------------------------------------------
# STEP 3 — Deploy services one by one with health check
# --------------------------------------------------
log "Deploying services stepwise..."
for svc in "${ALL_SERVICES[@]}"; do
    if [[ "${!SERVICE_$svc:-false}" != true ]]; then
        continue
    fi

    PORT="${!PORT_$svc:-10000}"
    log "Deploying $svc on port $PORT..."
    docker compose -f "$FINAL_COMPOSE" up -d "$svc"

    # Health check (5 retries)
    SUCCESS=false
    for ((i=1;i<=5;i++)); do
        if docker ps | grep -q "$svc"; then
            log "$svc is running (attempt $i)"
            SUCCESS=true
            break
        else
            log "$svc not running yet, retry $i/5..."
            sleep 5
        fi
    done

    if ! $SUCCESS; then
        log "WARNING: $svc failed to start after 5 attempts"
    fi

    # Update summary
    echo "$svc -> http://$(hostname -I | awk '{print $1}'):$PORT/" >> "$SUMMARY_FILE"
done

# --------------------------------------------------
# STEP 4 — Deployment summary
# --------------------------------------------------
log "=== Deployment Summary ==="
cat "$SUMMARY_FILE"
log "STEP 2 complete — All selected services attempted."
pause
