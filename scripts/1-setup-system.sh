#!/usr/bin/env bash
set -euo pipefail

# =====================================================
# Script 1 — Full System Setup & Configuration Collection
# Expanded Internal LLMs + Vector DB integration
# Detailed verbose prompts for user-friendly experience
# =====================================================

SCRIPT_NAME="1-setup-system"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="/mnt/data/logs"
CLEANUP_LOG="$LOG_DIR/cleanup"
DEPLOY_LOG="$LOG_DIR/deploy"
SCRIPT_LOG="$LOG_DIR/${SCRIPT_NAME}.log"
CONFIG_DIR="$ROOT_DIR/config"
ENV_FILE="$CONFIG_DIR/.env"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.txt"
SECRETS_FILE="$CONFIG_DIR/secrets.txt"

mkdir -p "$LOG_DIR" "$CLEANUP_LOG" "$DEPLOY_LOG" "$CONFIG_DIR"
touch "$SCRIPT_LOG"

# -----------------------------
# Logging helpers
# -----------------------------
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SCRIPT_LOG"; }
fail() { log "ERROR: $*"; exit 1; }
prompt_yn() { local prompt="$1"; local default="${2:-y}"; local choice; while true; do read -rp "$prompt [y/n] (default: $default): " choice; choice="${choice:-$default}"; case "$choice" in y|Y) return 0;; n|N) return 1;; *) echo "Please answer y or n.";; esac; done; }
pause() { read -rp "Press ENTER to continue..."; }
require_root() { [[ $EUID -eq 0 ]] || fail "Run as root"; }
require_root

# -------------------------
# Helper for numbered multi-select
# -------------------------
prompt_select_numbers() {
  local prompt="$1"
  local -n options=$2
  local -n output=$3
  echo
  echo "=== $prompt ==="
  for i in "${!options[@]}"; do
    echo "$((i+1))) ${options[$i]}"
  done
  read -rp "Enter numbers separated by commas (e.g., 1,3,4) or leave empty to skip: " input
  IFS=',' read -ra indices <<< "$input"
  output=()
  for idx in "${indices[@]}"; do
    idx=$(echo "$idx" | xargs)
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >=1 && idx <= ${#options[@]} )); then
      output+=("${options[$((idx-1))]}")
    fi
  done
}

# =====================================================
# STEP 1 — Hardware Detection
# =====================================================
log "STEP 1 — Hardware Detection"
CPU_CORES=$(nproc)
RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
DISK_GB=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
GPU_PRESENT=false
GPU_MODEL="none"
if command -v nvidia-smi >/dev/null 2>&1; then
  GPU_PRESENT=true
  GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
fi
log "Detected hardware: CPU=${CPU_CORES} cores, RAM=${RAM_GB}GB, Disk=${DISK_GB}GB, GPU=$GPU_PRESENT ($GPU_MODEL)"
cat > "$CONFIG_DIR/hardware-profile.env" <<EOF
CPU_CORES=$CPU_CORES
RAM_GB=$RAM_GB
DISK_GB=$DISK_GB
GPU_PRESENT=$GPU_PRESENT
GPU_MODEL="$GPU_MODEL"
EOF
pause

# =====================================================
# STEP 2 — Stack Services Selection
# =====================================================
log "STEP 2 — Stack Services Selection"

# Core Components
CORE_COMPONENTS=("Ollama" "AnythingLLM" "LiteLLM")
SELECTED_CORE=()
prompt_select_numbers "Select Core Components (required for AI runtime)" CORE_COMPONENTS SELECTED_CORE

# AI Stack / Application Layer
AI_STACK=("Dify" "ComfyUI" "OpenWebUI" "OpenClaw UI" "Flowise" "n8n" "SuperTokens")
SELECTED_AI=()
prompt_select_numbers "Select AI Stack / Application Layer services" AI_STACK SELECTED_AI

# Optional / Monitoring
OPTIONAL_SERVICES=("Grafana" "Prometheus" "ELK" "Portainer")
SELECTED_OPTIONAL=()
prompt_select_numbers "Select Optional / Monitoring services" OPTIONAL_SERVICES SELECTED_OPTIONAL

# Consolidate all selections
declare -A SERVICES_SELECTED
for svc in "${CORE_COMPONENTS[@]}" "${AI_STACK[@]}" "${OPTIONAL_SERVICES[@]}"; do SERVICES_SELECTED[$svc]=false; done
for svc in "${SELECTED_CORE[@]}" "${SELECTED_AI[@]}" "${SELECTED_OPTIONAL[@]}"; do SERVICES_SELECTED[$svc]=true; done
pause

# =====================================================
# STEP 3 — Proxy & Domain Configuration
# =====================================================
log "STEP 3 — Proxy Selection & Domain Configuration"
PROXIES=("Nginx" "Traefik" "Caddy" "None")
SELECTED_PROXY=()
prompt_select_numbers "Select reverse proxy" PROXIES SELECTED_PROXY
PROXY="${SELECTED_PROXY[0]:-None}"
read -rp "Enter main domain for public IP / certificates (example: example.com): " DOMAIN_NAME
pause

# =====================================================
# STEP 4 — Internal LLM Selection
# =====================================================
log "STEP 4 — Internal LLM Selection"
INTERNAL_LLMS=("Llama2" "Llama3" "MPT-7B" "Falcon" "Google Gemini" "Mistral")
SELECTED_INTERNAL_LLMS=()
prompt_select_numbers "Select Internal LLMs to include" INTERNAL_LLMS SELECTED_INTERNAL_LLMS
declare -A INTERNAL_LLM_KEYS
if [[ ${#SELECTED_INTERNAL_LLMS[@]} -gt 0 ]]; then
  for llm in "${SELECTED_INTERNAL_LLMS[@]}"; do
    INTERNAL_LLM_KEYS[$llm]=$(openssl rand -hex 16)
    log "Generated auth key for $llm"
  done
fi
pause

# =====================================================
# STEP 5 — External LLM Providers
# =====================================================
log "STEP 5 — External LLM Providers"
EXTERNAL_PROVIDERS=("OpenAI" "Cohere" "Anthropic" "GoogleVertex" "OpenRouter" "GROQ" "Google Gemini")
declare -A PROVIDER_KEYS
for provider in "${EXTERNAL_PROVIDERS[@]}"; do
  if prompt_yn "Use provider $provider?"; then
    read -rp "Enter API key for $provider: " key
    PROVIDER_KEYS[$provider]=$key
  fi
done
pause

# =====================================================
# STEP 6 — Vector DB Selection
# =====================================================
log "STEP 6 — Vector DB Selection"
VECTOR_DBS=("Postgres" "Redis" "Milvus" "Weaviate" "Qdrant" "Chroma" "None")
SELECTED_VECTOR_DB=()
prompt_select_numbers "Select Vector DB for embeddings / OpenClaw integration" VECTOR_DBS SELECTED_VECTOR_DB
VECTOR_DB="${SELECTED_VECTOR_DB[0]:-None}"
read -rp "Enter Vector DB username (default: vectoruser): " VECTOR_DB_USER
VECTOR_DB_USER="${VECTOR_DB_USER:-vectoruser}"
VECTOR_DB_PASS=$(openssl rand -hex 12)
log "Generated Vector DB credentials"
pause

# =====================================================
# STEP 7 — Tailscale / Signal / LiteLLM Routing
# =====================================================
log "STEP 7 — Tailscale, Signal, LiteLLM Routing"
read -rp "Enter Tailscale HTTPS port (default 8443): " TAILSCALE_PORT
TAILSCALE_PORT="${TAILSCALE_PORT:-8443}"
read -rp "Enter Signal phone number (defer QR pairing to Script 2): " SIGNAL_PHONE
read -rp "Enter LiteLLM routing strategy (round-robin / priority / weighted): " LITELLM_ROUTING
pause

# =====================================================
# STEP 8 — OpenClaw Configuration
# =====================================================
log "STEP 8 — OpenClaw Configuration"
read -rp "Enter OpenClaw additional settings (if any): " OPENCLAW_CONFIG
DB_USER="dbuser"
DB_PASS=$(openssl rand -hex 12)
log "Generated DB credentials for OpenClaw"
# Create OpenClaw config file pointing to chosen Vector DB
OPENCLAW_CONF_FILE="$CONFIG_DIR/openclaw_config.json"
cat > "$OPENCLAW_CONF_FILE" <<EOF
{
  "vector_db": "$VECTOR_DB",
  "db_user": "$VECTOR_DB_USER",
  "db_pass": "$VECTOR_DB_PASS",
  "api_key": "$(openssl rand -hex 16)",
  "settings": "$OPENCLAW_CONFIG"
}
EOF
log "OpenClaw configuration file written: $OPENCLAW_CONF_FILE"
pause

# =====================================================
# STEP 9 — Monitoring Stack
# =====================================================
log "STEP 9 — Monitoring Stack"
MONITORING=("Prometheus" "Grafana" "ELK")
declare -A MONITOR_SELECTED
for mon in "${MONITORING[@]}"; do
  if prompt_yn "Include $mon in monitoring?"; then MONITOR_SELECTED[$mon]=true; fi
done
pause

# =====================================================
# STEP 10 — Write .env, credentials, secrets
# =====================================================
log "STEP 10 — Writing configuration files"
{
  echo "# Auto-generated config by $SCRIPT_NAME"
  echo "CPU_CORES=$CPU_CORES"
  echo "RAM_GB=$RAM_GB"
  echo "DISK_GB=$DISK_GB"
  echo "GPU_PRESENT=$GPU_PRESENT"
  echo "GPU_MODEL=\"$GPU_MODEL\""
  echo "DOMAIN_NAME=\"$DOMAIN_NAME\""
  echo "PROXY=\"$PROXY\""
  echo "VECTOR_DB=\"$VECTOR_DB\""
  echo "VECTOR_DB_USER=\"$VECTOR_DB_USER\""
  echo "VECTOR_DB_PASS=\"$VECTOR_DB_PASS\""
  echo "TAILSCALE_PORT=\"$TAILSCALE_PORT\""
  echo "SIGNAL_PHONE=\"$SIGNAL_PHONE\""
  echo "LITELLM_ROUTING=\"$LITELLM_ROUTING\""
  echo "OPENCLAW_CONFIG=\"$OPENCLAW_CONFIG\""
  echo "DB_USER=\"$DB_USER\""
  echo "DB_PASS=\"$DB_PASS\""
  for svc in "${!SERVICES_SELECTED[@]}"; do echo "SERVICE_${svc^^}=${SERVICES_SELECTED[$svc]}"; done
  for llm in "${!INTERNAL_LLM_KEYS[@]}"; do echo "INTERNAL_LLM_${llm^^}=${INTERNAL_LLM_KEYS[$llm]}"; done
  for provider in "${!PROVIDER_KEYS[@]}"; do echo "EXTERNAL_PROVIDER_${provider^^}=${PROVIDER_KEYS[$provider]}"; done
  for mon in "${MONITORING[@]}"; do [[ "${MONITOR_SELECTED[$mon]}" == true ]] && echo "MONITOR_${mon^^}=true"; done
} > "$ENV_FILE"

# Write credentials
{
  echo "DB_USER=$DB_USER"
  echo "DB_PASS=$DB_PASS"
  echo "VECTOR_DB_USER=$VECTOR_DB_USER"
  echo "VECTOR_DB_PASS=$VECTOR_DB_PASS"
  for llm in "${!INTERNAL_LLM_KEYS[@]}"; do echo "INTERNAL_LLM_${llm^^}=${INTERNAL_LLM_KEYS[$llm]}"; done
} > "$CREDENTIALS_FILE"

log "Configuration files written:"
log "  ENV: $ENV_FILE"
log "  Credentials: $CREDENTIALS_FILE"
log "  OpenClaw: $OPENCLAW_CONF_FILE"
log "  Secrets file: $SECRETS_FILE (if generated later)"

# =====================================================
# STEP 11 — Health Check & Summary
# =====================================================
log "STEP 11 — Configuration Summary"
echo
echo "Selected Core Components: ${SELECTED_CORE[*]}"
echo "Selected AI Stack: ${SELECTED_AI[*]}"
echo "Selected Optional/Monitoring: ${SELECTED_OPTIONAL[*]}"
echo "Selected Internal LLMs: ${SELECTED_INTERNAL_LLMS[*]}"
echo "Selected External LLM Providers: ${!PROVIDER_KEYS[*]}"
echo "Vector DB: $VECTOR_DB"
echo "Proxy: $PROXY"
echo "Domain: $DOMAIN_NAME"
echo "Tailscale HTTPS port: $TAILSCALE_PORT"
echo "Signal phone (deferred pairing): $SIGNAL_PHONE"
echo "LiteLLM routing strategy: $LITELLM_ROUTING"
echo "Monitoring stack enabled:"
for mon in "${MONITORING[@]}"; do [[ "${MONITOR_SELECTED[$mon]}" == true ]] && echo "  - $mon"; done
echo
log "Script 1 completed successfully. Next step: scripts/2-deploy-services.sh"

