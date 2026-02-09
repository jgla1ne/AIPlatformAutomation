#!/usr/bin/env bash
set -euo pipefail

# =====================================================
# Script 1 — Refined Full System Setup & Configuration Collection
# UX improvements, icon-based menus, Google rsync, Tailscale API/auth
# =====================================================

SCRIPT_NAME="1-setup-system-refined"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/config"
LOG_DIR="/mnt/data/logs"
CLEANUP_LOG="$LOG_DIR/cleanup"
DEPLOY_LOG="$LOG_DIR/deploy"
SCRIPT_LOG="$LOG_DIR/${SCRIPT_NAME}.log"
ENV_FILE="$CONFIG_DIR/.env"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.txt"
SECRETS_FILE="$CONFIG_DIR/secrets.txt"

mkdir -p "$LOG_DIR" "$CLEANUP_LOG" "$DEPLOY_LOG" "$CONFIG_DIR"
touch "$SCRIPT_LOG"

# -----------------------------
# Logging helpers
# -----------------------------
log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SCRIPT_LOG"; }
fail() { log "ERROR: $*"; exit 1; }
prompt_yn() {
  local prompt="$1"
  local default="${2:-y}"
  local choice
  while true; do
    read -rp "$prompt [y/n] (default: $default): " choice
    choice="${choice:-$default}"
    case "$choice" in y|Y) return 0 ;; n|N) return 1 ;; *) echo "Please answer y or n." ;; esac
  done
}
pause() { read -rp "Press ENTER to continue..."; }
require_root() { [[ $EUID -eq 0 ]] || fail "Run as root"; }
require_root

# -----------------------------
# Numbered multi-select helper
# -----------------------------
prompt_select_numbers() {
  local prompt="$1"
  local -n options=$2
  local -n output=$3
  echo
  echo "=== $prompt ==="
  for i in "${!options[@]}"; do
    echo "$((i+1))) ${options[$i]}"
  done
  echo "0) ALL"
  read -rp "Enter numbers separated by commas (e.g., 1,3,0): " input
  IFS=',' read -ra indices <<< "$input"
  output=()
  for idx in "${indices[@]}"; do
    idx=$(echo "$idx" | xargs)
    if [[ "$idx" == "0" ]]; then
      output=("${options[@]}")
      break
    elif [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >=1 && idx <= ${#options[@]} )); then
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
pause

# =====================================================
# STEP 2 — Core, AI, Optional Services Selection
# =====================================================
log "STEP 2 — Service Selection"

CORE_COMPONENTS=("Ollama" "AnythingLLM" "LiteLLM")
SELECTED_CORE=()
prompt_select_numbers "Select Core Components (required for AI runtime)" CORE_COMPONENTS SELECTED_CORE

AI_STACK=("Dify" "ComfyUI" "OpenWebUI" "OpenClaw UI" "Flowise" "n8n" "SuperTokens")
SELECTED_AI=()
prompt_select_numbers "Select AI Stack / Application Layer services" AI_STACK SELECTED_AI

OPTIONAL_SERVICES=("Grafana" "Prometheus" "ELK" "Portainer")
SELECTED_OPTIONAL=()
prompt_select_numbers "Select Optional / Monitoring services" OPTIONAL_SERVICES SELECTED_OPTIONAL

declare -A SERVICES_SELECTED
for svc in "${CORE_COMPONENTS[@]}" "${AI_STACK[@]}" "${OPTIONAL_SERVICES[@]}"; do SERVICES_SELECTED[$svc]=false; done
for svc in "${SELECTED_CORE[@]}" "${SELECTED_AI[@]}" "${SELECTED_OPTIONAL[@]}"; do SERVICES_SELECTED[$svc]=true; done
pause

# =====================================================
# STEP 3 — Proxy & Domain Configuration
# =====================================================
log "STEP 3 — Proxy & Domain Configuration"
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
# STEP 7 — Google rsync / OAuth
# =====================================================
log "STEP 7 — Google rsync authentication"
RSYNC_METHODS=("Project ID + Secret" "OAuth URL")
SELECTED_RSYNC=()
prompt_select_numbers "Select Google rsync authentication method" RSYNC_METHODS SELECTED_RSYNC
RSYNC_METHOD="${SELECTED_RSYNC[0]}"
if [[ "$RSYNC_METHOD" == "Project ID + Secret" ]]; then
  read -rp "Enter Google Project ID: " GOOGLE_PROJECT_ID
  read -rp "Enter Google Secret: " GOOGLE_SECRET
else
  read -rp "Enter OAuth URL: " GOOGLE_OAUTH_URL
fi
pause

# =====================================================
# STEP 8 — Tailscale Auth / API key
# =====================================================
log "STEP 8 — Tailscale configuration"
TAILSCALE_PORT=8443
read -rp "Enter Tailscale HTTPS port (default 8443): " input_port
TAILSCALE_PORT="${input_port:-$TAILSCALE_PORT}"
TAILSCALE_AUTH_KEY=$(openssl rand -hex 16)
TAILSCALE_API_KEY=$(openssl rand -hex 16)
log "Generated Tailscale auth key and API key"
pause

# =====================================================
# STEP 9 — LiteLLM Routing
# =====================================================
log "STEP 9 — LiteLLM routing strategy"
read -rp "Enter LiteLLM routing strategy (round-robin / priority / weighted): " LITELLM_ROUTING
pause

# =====================================================
# STEP 10 — OpenClaw Configuration
# =====================================================
log "STEP 10 — OpenClaw Configuration"
read -rp "Enter OpenClaw additional settings (optional): " OPENCLAW_CONFIG
DB_USER="dbuser"
DB_PASS=$(openssl rand -hex 12)
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
# STEP 11 — Write .env, credentials, secrets
# =====================================================
log "STEP 11 — Writing configuration files"
{
  echo "# Auto-generated config by $SCRIPT_NAME"
  echo "DOMAIN_NAME=\"$DOMAIN_NAME\""
  echo "PROXY=\"$PROXY\""
  echo "VECTOR_DB=\"$VECTOR_DB\""
  echo "VECTOR_DB_USER=\"$VECTOR_DB_USER\""
  echo "VECTOR_DB_PASS=\"$VECTOR_DB_PASS\""
  echo "TAILSCALE_PORT=\"$TAILSCALE_PORT\""
  echo "TAILSCALE_AUTH_KEY=\"$TAILSCALE_AUTH_KEY\""
  echo "TAILSCALE_API_KEY=\"$TAILSCALE_API_KEY\""
  echo "LITELLM_ROUTING=\"$LITELLM_ROUTING\""
  echo "OPENCLAW_CONFIG=\"$OPENCLAW_CONFIG\""
  [[ -n "${GOOGLE_PROJECT_ID:-}" ]] && echo "GOOGLE_PROJECT_ID=\"$GOOGLE_PROJECT_ID\""
  [[ -n "${GOOGLE_SECRET:-}" ]] && echo "GOOGLE_SECRET=\"$GOOGLE_SECRET\""
  [[ -n "${GOOGLE_OAUTH_URL:-}" ]] && echo "GOOGLE_OAUTH_URL=\"$GOOGLE_OAUTH_URL\""
  for svc in "${!SERVICES_SELECTED[@]}"; do echo "SERVICE_${svc^^}=${SERVICES_SELECTED[$svc]}"; done
  for llm in "${!INTERNAL_LLM_KEYS[@]}"; do echo "INTERNAL_LLM_${llm^^}=${INTERNAL_LLM_KEYS[$llm]}"; done
  for provider in "${!PROVIDER_KEYS[@]}"; do echo "EXTERNAL_PROVIDER_${provider^^}=${PROVIDER_KEYS[$provider]}"; done
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
pause

# =====================================================
# STEP 12 — Post-Script Summary with Icons
# =====================================================
log "STEP 12 — Configuration Summary"
echo
echo "==================== SUMMARY ===================="
echo "Core Stack:"
for svc in "${CORE_COMPONENTS[@]}"; do
  [[ "${SERVICES_SELECTED[$svc]}" == true ]] && icon="✅" || icon="❌"
  echo "$icon $svc"
done
echo "AI Stack:"
for svc in "${AI_STACK[@]}"; do
  [[ "${SERVICES_SELECTED[$svc]}" == true ]] && icon="⚙️" || icon="❌"
  echo "$icon $svc"
done
echo "Optional Services:"
for svc in "${OPTIONAL_SERVICES[@]}"; do
  [[ "${SERVICES_SELECTED[$svc]}" == true ]] && icon="⚙️" || icon="❌"
  echo "$icon $svc"
done
echo "Internal LLMs:"
for llm in "${SELECTED_INTERNAL_LLMS[@]}"; do echo "✅ $llm"; done
echo "External LLM Providers:"
for provider in "${!PROVIDER_KEYS[@]}"; do echo "✅ $provider"; done
echo "Vector DB: $VECTOR_DB"
echo "Tailscale HTTPS Port: $TAILSCALE_PORT"
echo "Signal phone: ${SIGNAL_PHONE:-Not set}"
echo "LiteLLM routing: $LITELLM_ROUTING"
echo "Configuration written to .env, credentials.txt, openclaw_config.json"
echo "================================================"

