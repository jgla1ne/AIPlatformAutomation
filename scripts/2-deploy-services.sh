#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="2-deploy-services"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/config"
ENV_FILE="$CONFIG_DIR/.env"

# -----------------------------
# STEP 0 — Setup logging
# -----------------------------
# Load DATA_DIR from .env if exists, else default
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "Error: configuration file $ENV_FILE not found. Run Script 1 first."
    exit 1
fi

LOG_DIR="${DATA_DIR}/logs"
mkdir -p "$LOG_DIR"
SCRIPT_LOG="$LOG_DIR/${SCRIPT_NAME}.log"
touch "$SCRIPT_LOG"

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SCRIPT_LOG"; }
fail() { log "ERROR: $*"; exit 1; }

log "STEP 0 — Loaded configuration from Script 1"

# -----------------------------
# STEP 1 — Docker check
# -----------------------------
if ! command -v docker &> /dev/null; then
    fail "Docker is not installed. Install Docker first."
fi
if ! docker info >/dev/null 2>&1; then
    fail "Docker daemon not running. Start Docker first."
fi
log "Docker is installed and running"

# -----------------------------
# STEP 2 — Deploy Core Components
# -----------------------------
log "STEP 2 — Deploying Core Components"
for svc in Ollama AnythingLLM LiteLLM; do
    safe_svc=$(echo "$svc" | tr '[:lower:] ' '[:upper:]_')
    if [[ "${SERVICE_$safe_svc:-false}" == true ]]; then
        port="${PORT_$safe_svc}"
        log "Deploying $svc on port $port"

        case "$svc" in
        Ollama)
            # Pull container or setup environment
            log "Initializing Ollama container (internal LLM)"
            docker run -d --name ollama -p "$port:$port" -v "$DATA_DIR/volumes/ollama:/data" ollama/ollama:latest
            ;;
        AnythingLLM)
            log "Initializing AnythingLLM container"
            docker run -d --name anythingllm -p "$port:$port" -v "$DATA_DIR/volumes/anything:/data" anythingllm:latest
            ;;
        LiteLLM)
            log "Initializing LiteLLM routing service (${LITELLM_ROUTING})"
            docker run -d --name litellm -p "$port:$port" -v "$DATA_DIR/volumes/litellm:/data" litellm:latest \
                --routing "$LITELLM_ROUTING"
            ;;
        esac
    fi
done
pause

# -----------------------------
# STEP 3 — Deploy AI Stack / Applications
# -----------------------------
log "STEP 3 — Deploying AI Stack / Apps"
for svc in Dify ComfyUI OpenWebUI OpenClaw_UI Flowise n8n SuperTokens; do
    safe_svc=$(echo "$svc" | tr '[:lower:] ' '[:upper:]_')
    if [[ "${SERVICE_$safe_svc:-false}" == true ]]; then
        port="${PORT_$safe_svc}"
        log "Deploying $svc on port $port"
        case "$svc" in
        OpenClaw_UI)
            # Mount volumes and connect to Vector DB
            docker run -d --name openclaw_ui -p "$port:$port" \
                -v "$DATA_DIR/volumes/openclaw:/data" \
                -e OPENCLAW_CONFIG="$OPENCLAW_CONF_FILE" openclaw:latest
            ;;
        *)
            docker run -d --name "$svc" -p "$port:$port" -v "$DATA_DIR/volumes/$svc:/data" "$svc:latest"
            ;;
        esac
    fi
done
pause

# -----------------------------
# STEP 4 — Deploy Optional / Monitoring Services
# -----------------------------
log "STEP 4 — Deploying Optional Services"
for svc in Grafana Prometheus ELK Portainer; do
    safe_svc=$(echo "$svc" | tr '[:lower:] ' '[:upper:]_')
    if [[ "${SERVICE_$safe_svc:-false}" == true ]]; then
        port="${PORT_$safe_svc}"
        log "Deploying $svc on port $port"
        docker run -d --name "$svc" -p "$port:$port" -v "$DATA_DIR/volumes/$svc:/data" "$svc:latest"
    fi
done
pause

# -----------------------------
# STEP 5 — Configure External Services
# -----------------------------
log "STEP 5 — Configure Google Drive / Tailscale / Signal"
# Google Drive
case "$GDRIVE_MODE" in
1)
    log "Configuring Google Drive: Project ID + Secret"
    ;;
2)
    log "Configuring Google Drive: OAuth URL"
    ;;
3)
    log "Configuring Google Drive: Rsync only"
    ;;
esac
# Tailscale
if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
    log "Starting Tailscale with Auth Key"
fi
# Signal
if [[ -n "$SIGNAL_USER_NUMBER" ]]; then
    log "Registering Signal user $SIGNAL_USER_NUMBER"
fi
pause

# -----------------------------
# STEP 6 — Deployment Summary
# -----------------------------
log "STEP 6 — Deployment Summary (services will be ready after Step 3 configuration)"
echo "==================== DEPLOYMENT SUMMARY ===================="
printf "%-20s %-10s %-30s\n" "Service" "Port" "URL"
for svc in "${!SERVICES_SELECTED[@]}"; do
    if [[ "${SERVICES_SELECTED[$svc]}" == true ]]; then
        if [[ "$svc" == "PROXY" ]]; then
            echo " PROXY_HTTP  80  http://$DOMAIN_NAME:80/"
            echo " PROXY_HTTPS 443 https://$DOMAIN_NAME:443/"
        else
            port="${SERVICE_PORTS[$svc]}"
            printf "%-20s %-10s http://%s:%s/\n" "$svc" "$port" "$DOMAIN_NAME" "$port"
        fi
    fi
done
echo "============================================================"
pause

log "Script 2 deployment complete. Step 3 will configure and start services."

