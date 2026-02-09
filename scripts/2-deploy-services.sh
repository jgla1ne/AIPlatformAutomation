#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="2-deploy-services"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/config"
LOG_DIR="/mnt/data/logs"
SCRIPT_LOG="$LOG_DIR/${SCRIPT_NAME}.log"
ENV_FILE="$CONFIG_DIR/.env"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.txt"

mkdir -p "$LOG_DIR"
touch "$SCRIPT_LOG"

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SCRIPT_LOG"; }
fail() { log "ERROR: $*"; exit 1; }
pause() { read -rp "Press ENTER to continue..."; }

require_root() { [[ $EUID -eq 0 ]] || fail "Run as root"; }
require_root

# -----------------------------
# STEP 0 — Load configuration
# -----------------------------
log "STEP 0 — Loading configuration from Script 1"
if [[ ! -f "$ENV_FILE" ]]; then fail "$ENV_FILE not found. Run Script 1 first."; fi
source "$ENV_FILE"
if [[ ! -f "$CREDENTIALS_FILE" ]]; then fail "$CREDENTIALS_FILE not found."; fi
source "$CREDENTIALS_FILE"
log "Configuration loaded successfully."
pause

# -----------------------------
# STEP 1 — Utility functions
# -----------------------------
check_port() {
  local port=$1
  if ss -tulpn | grep -q ":$port\b"; then return 0; else return 1; fi
}

deploy_docker_service() {
  local svc_name=$1
  local image=$2
  local port=$3
  log "Deploying $svc_name on port $port"
  docker pull "$image"
  docker run -d --name "$svc_name" -p "$port:$port" "$image"
}

# -----------------------------
# STEP 2 — Core Components Deployment
# -----------------------------
log "STEP 2 — Deploying Core Components"

# Ollama
if [[ "${SERVICE_OLLAMA:-false}" == true ]]; then
  log "Deploying Ollama LLM server..."
  docker pull ollama/ollama:latest
  docker run -d --name ollama -p "${PORT_OLLAMA:-11400}:11400" ollama/ollama:latest
  pause
fi

# AnythingLLM
if [[ "${SERVICE_ANYTHINGLLM:-false}" == true ]]; then
  log "Deploying AnythingLLM..."
  docker pull anythingai/anythingllm:latest
  docker run -d --name anythingllm -p "${PORT_ANYTHINGLLM:-8001}:8001" anythingai/anythingllm:latest
  pause
fi

# LiteLLM
if [[ "${SERVICE_LITELLM:-false}" == true ]]; then
  log "Deploying LiteLLM with routing strategy $LITELLM_ROUTING..."
  docker pull liteai/litellm:latest
  docker run -d --name litellm -p "${PORT_LITELLM:-8000}:8000" -e ROUTING_STRATEGY="$LITELLM_ROUTING" liteai/litellm:latest
  pause
fi

# -----------------------------
# STEP 3 — AI Stack Deployment
# -----------------------------
log "STEP 3 — Deploying AI Stack / App Layer"
declare -A AI_SERVICES_IMAGES=(
  ["Dify"]="difyai/dify:latest"
  ["ComfyUI"]="comfyui/comfyui:latest"
  ["OpenWebUI"]="openwebui/openwebui:latest"
  ["OpenClaw UI"]="openclaw/openclaw-ui:latest"
  ["Flowise"]="flowise/flowise:latest"
  ["n8n"]="n8nio/n8n:latest"
  ["SuperTokens"]="supertokens/supertokens-postgresql:latest"
)

for svc in "${!AI_SERVICES_IMAGES[@]}"; do
  if [[ "${SERVICES_SELECTED[$svc]:-false}" == true ]]; then
    port_var="PORT_${svc^^// /_}"
    port="${!port_var:-10000}"
    deploy_docker_service "$svc" "${AI_SERVICES_IMAGES[$svc]}" "$port"
  fi
done
pause

# -----------------------------
# STEP 4 — Optional Services Deployment
# -----------------------------
log "STEP 4 — Deploying Optional Services"
declare -A OPTIONAL_IMAGES=(
  ["Grafana"]="grafana/grafana:latest"
  ["Prometheus"]="prom/prometheus:latest"
  ["ELK"]="docker.elastic.co/kibana/kibana:8.9.0"
  ["Portainer"]="portainer/portainer-ce:latest"
)

for svc in "${!OPTIONAL_IMAGES[@]}"; do
  if [[ "${SERVICES_SELECTED[$svc]:-false}" == true ]]; then
    port_var="PORT_${svc^^// /_}"
    port="${!port_var:-10000}"
    deploy_docker_service "$svc" "${OPTIONAL_IMAGES[$svc]}" "$port"
  fi
done
pause

# -----------------------------
# STEP 5 — OpenClaw + Vector DB
# -----------------------------
log "STEP 5 — Deploying OpenClaw and Vector DB"
if [[ "${SERVICE_OPENCLAW_UI:-false}" == true ]]; then
  docker pull openclaw/openclaw:latest
  docker run -d --name openclaw -p "${PORT_OPENCLAW_UI:-8081}:8081" \
    -v "$OPENCLAW_CONF_FILE:/app/config/openclaw_config.json" openclaw/openclaw:latest
fi

# Deploy Vector DB if selected
if [[ "$VECTOR_DB" != "None" ]]; then
  log "Deploying Vector DB: $VECTOR_DB"
  case "$VECTOR_DB" in
    Qdrant)
      docker pull qdrant/qdrant:latest
      docker run -d --name qdrant -p 6333:6333 qdrant/qdrant:latest
      ;;
    Chroma)
      docker pull chroma/chroma:latest
      docker run -d --name chroma -p 8000:8000 chroma/chroma:latest
      ;;
    *)
      log "Deployment for $VECTOR_DB not automated; ensure manually or add docker image"
      ;;
  esac
fi
pause

# -----------------------------
# STEP 6 — Proxy Deployment
# -----------------------------
if [[ "${SERVICE_PROXY:-false}" == true ]]; then
  log "Deploying Proxy with SSL for $DOMAIN_NAME..."
  docker pull nginx:latest
  docker run -d --name proxy -p 80:80 -p 443:443 -e DOMAIN="$DOMAIN_NAME" -e EMAIL="$PROXY_EMAIL" nginx:latest
  pause
fi

# -----------------------------
# STEP 7 — Tailscale Deployment
# -----------------------------
if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
  log "Deploying Tailscale..."
  docker pull tailscale/tailscale:latest
  docker run -d --name tailscale --cap-add=NET_ADMIN -e TS_AUTHKEY="$TAILSCALE_AUTH_KEY" -e TS_API_KEY="$TAILSCALE_API_KEY" tailscale/tailscale:latest
  pause
fi

# -----------------------------
# STEP 8 — Signal pairing
# -----------------------------
if [[ -n "$SIGNAL_USER_NUMBER" ]]; then
  log "Deploying Signal API pairing (user $SIGNAL_USER_NUMBER)..."
  docker pull signalsrv/signal-api:latest
  docker run -d --name signal-api -p 8085:8085 -e SIGNAL_USER_NUMBER="$SIGNAL_USER_NUMBER" signalsrv/signal-api:latest
  pause
fi

# -----------------------------
# STEP 9 — Google Drive / Rsync
# -----------------------------
case "$GDRIVE_MODE" in
1)
  log "Configuring Google Drive with Project ID + Secret..."
  ;;
2)
  log "Configuring Google Drive with OAuth URL..."
  ;;
3)
  log "Configuring Rsync only..."
  ;;
esac
pause

# -----------------------------
# STEP 10 — Post-deployment summary
# -----------------------------
log "STEP 10 — Deployment Summary"
echo "==================== DEPLOYMENT SUMMARY ===================="
printf "%-20s %-10s %-20s %-8s\n" "Service" "Port" "URL" "Status"
for svc in "${!SERVICES_SELECTED[@]}"; do
  if [[ "${SERVICES_SELECTED[$svc]}" == true ]]; then
    port_var="PORT_${svc^^// /_}"
    port="${!port_var:-N/A}"
    status="❌"
    # Quick port check
    if check_port "$port"; then status="✅"; fi
    printf "%-20s %-10s %-20s %-8s\n" "$svc" "$port" "http://$DOMAIN_NAME:$port" "$status"
  fi
done
echo "================================================================"
pause
log "Script 2 deployment complete."

