#!/usr/bin/env bash
#############################################################################
# Script 2 — Deploy Services
# Reads configuration from Script 1 (.env) and deploys the selected stack
# Includes logging, health checks, stepwise installation, summary
#############################################################################

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/config"
ENV_FILE="$CONFIG_DIR/.env"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.txt"
OPENCLAW_CONF_FILE="$CONFIG_DIR/openclaw_config.json"
DATA_DIR="/mnt/data"
LOG_DIR="$DATA_DIR/logs"
DEPLOY_LOG="$LOG_DIR/deploy.log"
SUMMARY_FILE="$CONFIG_DIR/service_deploy_summary.txt"

# Create logs if missing
mkdir -p "$LOG_DIR"
touch "$DEPLOY_LOG"
touch "$SUMMARY_FILE"

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$DEPLOY_LOG"; }
fail() { log "ERROR: $*"; exit 1; }
pause() { read -rp "Press ENTER to continue..."; }

# --------------------------------------------------
# STEP 0 — Load Environment
# --------------------------------------------------
[[ -f "$ENV_FILE" ]] || fail ".env file not found! Run Script 1 first."
set -o allexport
source "$ENV_FILE"
set +o allexport
log "Environment loaded from $ENV_FILE"

# --------------------------------------------------
# STEP 1 — Define service categories
# --------------------------------------------------
CORE=("Ollama" "AnythingLLM" "LiteLLM")
AISTACK=("Dify" "ComfyUI" "OpenWebUI" "OpenClaw_UI" "Flowise" "n8n" "SuperTokens")
OPTIONAL=("Grafana" "Prometheus" "ELK" "Portainer")

ALL_SERVICES=("${CORE[@]}" "${AISTACK[@]}" "${OPTIONAL[@]}")

# --------------------------------------------------
# STEP 2 — Deploy Services Stepwise
# --------------------------------------------------
log "STEP 2 — Deploying services one by one"

for svc in "${ALL_SERVICES[@]}"; do
    if [[ "${!SERVICE_$svc:-false}" != true ]]; then
        log "Skipping $svc (not selected)"
        continue
    fi

    PORT="${!PORT_$svc:-10000}"
    IMAGE_VAR="IMAGE_$svc"
    IMAGE="${!IMAGE_VAR:-$svc:latest}"

    log "Deploying $svc → image: $IMAGE, port: $PORT"

    # Run container
    if [[ "$svc" == "LiteLLM" ]]; then
        docker compose -f "$ROOT_DIR/compose/docker-compose.yml" up -d litellm
    else
        docker compose -f "$ROOT_DIR/compose/docker-compose.yml" up -d "$svc"
    fi

    # Health check loop (5 retries, 5s interval)
    RETRIES=5
    SUCCESS=false
    for ((i=1;i<=RETRIES;i++)); do
        if docker ps | grep -q "$svc"; then
            log "$svc is running (attempt $i)"
            SUCCESS=true
            break
        else
            log "$svc not running yet, retry $i/$RETRIES"
            sleep 5
        fi
    done
    if ! $SUCCESS; then
        log "WARNING: $svc failed to start after $RETRIES attempts"
    fi

    # Update summary
    echo "$svc -> http://$(hostname -I | awk '{print $1}'):$PORT/" >> "$SUMMARY_FILE"
done

# --------------------------------------------------
# STEP 3 — Final Deployment Summary
# --------------------------------------------------
log "Deployment summary:"
cat "$SUMMARY_FILE"
log "STEP 2 complete — All selected services attempted."
pause
