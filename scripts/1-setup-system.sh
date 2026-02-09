#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="1-setup-system-config"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/config"
LOG_DIR="/mnt/data/logs"
SCRIPT_LOG="$LOG_DIR/${SCRIPT_NAME}.log"
ENV_FILE="$CONFIG_DIR/.env"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.txt"
OPENCLAW_CONF_FILE="$CONFIG_DIR/openclaw_config.json"

mkdir -p "$LOG_DIR" "$CONFIG_DIR"
touch "$SCRIPT_LOG"

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SCRIPT_LOG"; }
fail() { log "ERROR: $*"; exit 1; }
prompt_yn() { local prompt="$1"; local default="${2:-y}"; local choice; while true; do read -rp "$prompt [y/n] (default: $default): " choice; choice="${choice:-$default}"; case "$choice" in y|Y) return 0 ;; n|N) return 1 ;; *) echo "Please answer y or n." ;; esac; done; }
pause() { read -rp "Press ENTER to continue..."; }
require_root() { [[ $EUID -eq 0 ]] || fail "Run as root"; }
require_root

# -----------------------------
# STEP 0 — Declare associative arrays and initialize variables
# -----------------------------
declare -A SERVICE_PORTS
declare -A SERVICES_SELECTED
declare -A INTERNAL_LLM_KEYS
declare -A PROVIDER_KEYS

# Initialize variables
GOOGLE_PROJECT_ID=""
GOOGLE_SECRET=""
GOOGLE_OAUTH_URL=""
GOOGLE_RSYNC_URL=""
GDRIVE_MODE=""

PROXY_EMAIL=""
TAILSCALE_AUTH_KEY=""
TAILSCALE_API_KEY=""
SIGNAL_USER_NUMBER=""
LITELLM_ROUTING=""

# -----------------------------
# Multi-select helper
# -----------------------------
prompt_select_numbers() {
  local prompt="$1"; local -n options=$2; local -n output=$3
  echo; echo "=== $prompt ==="
  for i in "${!options[@]}"; do echo "$((i+1))) ${options[$i]}"; done
  echo "0) ALL"
  read -rp "Enter numbers separated by commas (e.g., 1,3,0): " input
  IFS=',' read -ra indices <<< "$input"
  output=()
  for idx in "${indices[@]}"; do
    idx=$(echo "$idx" | xargs)
    if [[ "$idx" == "0" ]]; then output=("${options[@]}"); break
    elif [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >=1 && idx <= ${#options[@]} )); then output+=("${options[$((idx-1))]}"); fi
  done
}

# -----------------------------
# STEP 1 — Hardware Detection
# -----------------------------
log "STEP 1 — Hardware Detection"
CPU_CORES=$(nproc)
RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
DISK_GB=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
GPU_PRESENT=false; GPU_MODEL="none"
if command -v nvidia-smi >/dev/null 2>&1; then GPU_PRESENT=true; GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1); fi
log "Detected hardware: CPU=${CPU_CORES} cores, RAM=${RAM_GB}GB, Disk=${DISK_GB}GB, GPU=$GPU_PRESENT ($GPU_MODEL)"
pause

# -----------------------------
# STEP 2 — Service Selection
# -----------------------------
log "STEP 2 — Service Selection"
CORE_COMPONENTS=("Ollama" "AnythingLLM" "LiteLLM")
SELECTED_CORE=(); prompt_select_numbers "Select Core Components" CORE_COMPONENTS SELECTED_CORE

AI_STACK=("Dify" "ComfyUI" "OpenWebUI" "OpenClaw UI" "Flowise" "n8n" "SuperTokens")
SELECTED_AI=(); prompt_select_numbers "Select AI Stack / App Layer services" AI_STACK SELECTED_AI

OPTIONAL_SERVICES=("Grafana" "Prometheus" "ELK" "Portainer")
SELECTED_OPTIONAL=(); prompt_select_numbers "Select Optional / Monitoring services" OPTIONAL_SERVICES SELECTED_OPTIONAL

for svc in "${CORE_COMPONENTS[@]}" "${AI_STACK[@]}" "${OPTIONAL_SERVICES[@]}"; do SERVICES_SELECTED["$svc"]=false; done
for svc in "${SELECTED_CORE[@]}" "${SELECTED_AI[@]}" "${SELECTED_OPTIONAL[@]}"; do SERVICES_SELECTED["$svc"]=true; done
pause

# -----------------------------
# STEP 3 — Domain + Proxy + SSL
# -----------------------------
log "STEP 3 — Domain and Proxy setup"
read -rp "Enter main domain/subdomain: " DOMAIN_NAME
DOMAIN_IP=$(dig +short "$DOMAIN_NAME" | head -n1 || true)
while [[ -z "$DOMAIN_IP" ]]; do echo "Domain cannot resolve"; read -rp "Enter valid domain: " DOMAIN_NAME; DOMAIN_IP=$(dig +short "$DOMAIN_NAME" | head -n1 || true); done
log "Domain $DOMAIN_NAME resolves to $DOMAIN_IP"

if prompt_yn "Do you want to configure a proxy?"; then
  SERVICES_SELECTED["Proxy"]=true
  while [[ -z "$PROXY_EMAIL" ]]; do read -rp "Enter email for SSL certificates: " PROXY_EMAIL; done
  SERVICE_PORTS["ProxyHTTP"]=80
  SERVICE_PORTS["ProxyHTTPS"]=443
fi
pause

# -----------------------------
# STEP 4 — Internal LLMs
# -----------------------------
log "STEP 4 — Internal LLM Selection"
INTERNAL_LLMS=("Llama2" "Llama3" "MPT-7B" "Falcon" "Google Gemini" "Mistral")
SELECTED_INTERNAL_LLMS=(); prompt_select_numbers "Select Internal LLMs to include" INTERNAL_LLMS SELECTED_INTERNAL_LLMS
for llm in "${SELECTED_INTERNAL_LLMS[@]}"; do INTERNAL_LLM_KEYS["$llm"]="$(openssl rand -hex 16)"; log "Generated auth key for $llm"; done
pause

# -----------------------------
# STEP 5 — External LLM Providers
# -----------------------------
log "STEP 5 — External LLM Providers"
EXTERNAL_PROVIDERS=("OpenAI" "Cohere" "Anthropic" "GoogleVertex" "OpenRouter" "GROQ" "Google Gemini")
for provider in "${EXTERNAL_PROVIDERS[@]}"; do
  if prompt_yn "Use provider $provider?"; then read -rp "Enter API key for $provider: " key; PROVIDER_KEYS[$provider]=$key; fi
done
pause

# -----------------------------
# STEP 6 — Vector DB & OpenClaw
# -----------------------------
log "STEP 6 — Vector DB selection & OpenClaw config"
VECTOR_DBS=("Postgres" "Redis" "Milvus" "Weaviate" "Qdrant" "Chroma" "None")
SELECTED_VECTOR_DB=(); prompt_select_numbers "Select Vector DB for embeddings / OpenClaw" VECTOR_DBS SELECTED_VECTOR_DB
VECTOR_DB="${SELECTED_VECTOR_DB[0]:-None}"; read -rp "Vector DB username (default: vectoruser): " VECTOR_DB_USER; VECTOR_DB_USER="${VECTOR_DB_USER:-vectoruser}"
VECTOR_DB_PASS=$(openssl rand -hex 12)
cat > "$OPENCLAW_CONF_FILE" <<EOF
{
  "vector_db": "$VECTOR_DB",
  "db_user": "$VECTOR_DB_USER",
  "db_pass": "$VECTOR_DB_PASS",
  "api_key": "$(openssl rand -hex 16)"
}
EOF
log "OpenClaw configuration created at $OPENCLAW_CONF_FILE"
pause

# -----------------------------
# STEP 7 — LiteLLM Routing
# -----------------------------
log "STEP 7 — LiteLLM routing"
ROUTING_OPTIONS=("Round-robin" "Priority" "Weighted")
for i in "${!ROUTING_OPTIONS[@]}"; do echo "$((i+1))) ${ROUTING_OPTIONS[$i]}"; done
while true; do read -rp "Select LiteLLM routing strategy by number: " choice
  if [[ "$choice" =~ ^[1-3]$ ]]; then LITELLM_ROUTING="${ROUTING_OPTIONS[$((choice-1))]}"; break; else echo "Enter 1,2,3"; fi
done
pause

# -----------------------------
# STEP 8 — Google Drive setup (3 options)
# -----------------------------
log "STEP 8 — Google Drive / rsync setup"
echo "Select Google Drive mode:"
echo "1) Project ID + Secret"
echo "2) OAuth URL"
echo "3) Rsync only"
read -rp "Mode [1-3]: " GDRIVE_MODE
case "$GDRIVE_MODE" in
1) read -rp "Project ID: " GOOGLE_PROJECT_ID; read -rp "Secret: " GOOGLE_SECRET;; 
2) read -rp "OAuth URL: " GOOGLE_OAUTH_URL;; 
3) read -rp "Rsync URL: " GOOGLE_RSYNC_URL;; 
*) echo "Invalid, skipping";;
esac
pause

# -----------------------------
# STEP 9 — Tailscale
# -----------------------------
log "STEP 9 — Tailscale"
read -rp "Auth Key (optional): " TAILSCALE_AUTH_KEY
read -rp "API Key (optional): " TAILSCALE_API_KEY
pause

# -----------------------------
# STEP 10 — Signal User
# -----------------------------
log "STEP 10 — Signal user number"
read -rp "Enter Signal user phone number (for pairing later in Step 3): " SIGNAL_USER_NUMBER
pause

# -----------------------------
# STEP 11 — Assign service ports (default placeholders)
# -----------------------------
log "STEP 11 — Assign service ports (for future deployment)"
for svc in "${!SERVICES_SELECTED[@]}"; do
  if [[ "${SERVICES_SELECTED[$svc]}" == true ]]; then
    default_port=10000
    case "$svc" in
      Ollama) default_port=11400 ;;
      LiteLLM) default_port=8000 ;;
      Dify) default_port=3000 ;;
      OpenWebUI) default_port=8080 ;;
      OpenClaw\ UI) default_port=8081 ;;
      Flowise) default_port=5000 ;;
      n8n) default_port=5678 ;;
      SuperTokens) default_port=3567 ;;
      Grafana) default_port=3001 ;;
      Prometheus) default_port=9090 ;;
      ELK) default_port=5601 ;;
      Portainer) default_port=9000 ;;
    esac
    read -rp "Assign port for $svc (default $default_port): " input_port
    SERVICE_PORTS[$svc]="${input_port:-$default_port}"
  fi
done
pause

# -----------------------------
# STEP 12 — Write .env & credentials
# -----------------------------
{
  echo "DOMAIN_NAME=\"$DOMAIN_NAME\""
  echo "VECTOR_DB=\"$VECTOR_DB\""
  echo "VECTOR_DB_USER=\"$VECTOR_DB_USER\""
  echo "VECTOR_DB_PASS=\"$VECTOR_DB_PASS\""
  echo "LITELLM_ROUTING=\"$LITELLM_ROUTING\""
  echo "TAILSCALE_AUTH_KEY=\"$TAILSCALE_AUTH_KEY\""
  echo "TAILSCALE_API_KEY=\"$TAILSCALE_API_KEY\""
  echo "PROXY_EMAIL=\"$PROXY_EMAIL\""
  echo "SIGNAL_USER_NUMBER=\"$SIGNAL_USER_NUMBER\""
  echo "GDRIVE_MODE=\"$GDRIVE_MODE\""
  echo "GOOGLE_PROJECT_ID=\"$GOOGLE_PROJECT_ID\""
  echo "GOOGLE_SECRET=\"$GOOGLE_SECRET\""
  echo "GOOGLE_OAUTH_URL=\"$GOOGLE_OAUTH_URL\""
  echo "GOOGLE_RSYNC_URL=\"$GOOGLE_RSYNC_URL\""
  for svc in "${!SERVICES_SELECTED[@]}"; do
    safe_name="${svc^^// /_}"
    echo "SERVICE_${safe_name}=${SERVICES_SELECTED[$svc]}"
    echo "PORT_${safe_name}=${SERVICE_PORTS[$svc]}"
  done
  for llm in "${!INTERNAL_LLM_KEYS[@]}"; do safe_llm="${llm^^// /_}"; echo "INTERNAL_LLM_${safe_llm}=${INTERNAL_LLM_KEYS[$llm]}"; done
  for provider in "${!PROVIDER_KEYS[@]}"; do safe_provider="${provider^^// /_}"; echo "EXTERNAL_PROVIDER_${safe_provider}=${PROVIDER_KEYS[$provider]}"; done
} > "$ENV_FILE"

{
  echo "VECTOR_DB_USER=$VECTOR_DB_USER"
  echo "VECTOR_DB_PASS=$VECTOR_DB_PASS"
  echo "SIGNAL_USER_NUMBER=$SIGNAL_USER_NUMBER"
  for llm in "${!INTERNAL_LLM_KEYS[@]}"; do safe_llm="${llm^^// /_}"; echo "INTERNAL_LLM_${safe_llm}=${INTERNAL_LLM_KEYS[$llm]}"; done
} > "$CREDENTIALS_FILE"

log "Configuration files written: $ENV_FILE, $CREDENTIALS_FILE, $OPENCLAW_CONF_FILE"
pause

# -----------------------------
# STEP 13 — Post-setup summary (no real health check)
# -----------------------------
log "STEP 13 — Configuration Summary"
echo "==================== SERVICE CONFIGURATION SUMMARY ===================="
printf "%-20s %-10s %-20s\n" "Service" "Port" "URL (after deployment)"
for svc in "${!SERVICES_SELECTED[@]}"; do
  if [[ "${SERVICES_SELECTED[$svc]}" == true ]]; then
    port="${SERVICE_PORTS[$svc]}"
    echo " $(printf '%-18s %-10s http://%s:%s/' "$svc" "$port" "$DOMAIN_NAME" "$port")"
  fi
done
echo "======================================================================"
echo "Proxy SSL Email: ${PROXY_EMAIL:-N/A}"
echo "Tailscale Auth Key: ${TAILSCALE_AUTH_KEY:-N/A}"
echo "Tailscale API Key: ${TAILSCALE_API_KEY:-N/A}"
echo "Signal User Number: ${SIGNAL_USER_NUMBER:-N/A}"
echo "Google Drive Mode: ${GDRIVE_MODE:-N/A}"
pause
log "Script 1 configuration complete. Step 2 will deploy services."

