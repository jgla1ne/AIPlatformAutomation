#!/usr/bin/env bash
set -euo pipefail

###############################################
# Script 1 — System Setup & Configuration
# Fully compliant with README.md
###############################################

# --------------------------------------------------
# Logging / Local vars
# --------------------------------------------------
SCRIPT_NAME="1-setup-system"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_DATA_DIR="/mnt/data"
CONFIG_DIR="$ROOT_DIR/config"
ENV_FILE="$CONFIG_DIR/.env"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.txt"
OPENCLAW_CONF_FILE="$CONFIG_DIR/openclaw_config.json"

# Temporary log to ensure unbound vars don't break early
SCRIPT_LOG="/tmp/${SCRIPT_NAME}.log"
touch "$SCRIPT_LOG"
log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SCRIPT_LOG"; }
fail() { log "ERROR: $*"; exit 1; }
prompt_yn() { local p="$1"; local d="${2:-y}"; local c; while true; do \
    read -rp "$p [y/n] (default: $d): " c; c="${c:-$d}"; \
    case "$c" in y|Y) return 0 ;; n|N) return 1 ;; *) echo "Please answer y or n." ;; esac; done; }
pause() { read -rp "Press ENTER to continue..."; }
require_root() { [[ $EUID -eq 0 ]] || fail "Run as root"; }
require_root

# --------------------------------------------------
# STEP 0 — Existing config detection
# --------------------------------------------------
if [[ -f "$ENV_FILE" ]]; then
  log "Existing configuration detected at $ENV_FILE"
  if prompt_yn "Run cleanup first?"; then
    log "Please run ./0-complete-cleanup.sh first"; exit 0
  fi
fi
mkdir -p "$CONFIG_DIR"

# --------------------------------------------------
# STEP 1 — Data volume selection & mount
# --------------------------------------------------
DATA_DIR="$DEFAULT_DATA_DIR"
log "STEP 1 — Data volume selection and mount"
if ! mountpoint -q "$DEFAULT_DATA_DIR"; then
  echo "Select device to mount for AIPlatform data (ENTER to skip):"
  mapfile -t devices < <(lsblk -dpno NAME,SIZE,TYPE | awk '$3=="disk"{print $1":"$2}')
  for i in "${!devices[@]}"; do echo "$((i+1))) ${devices[$i]}"; done
  read -rp "Device number: " dev_choice
  if [[ "$dev_choice" =~ ^[0-9]+$ ]]; then
    selected_device="${devices[$((dev_choice-1))]%:*}"
    mkdir -p "$DEFAULT_DATA_DIR"
    log "Mounting $selected_device → $DEFAULT_DATA_DIR"
    mount "$selected_device" "$DEFAULT_DATA_DIR"
  fi
fi

# --------------------------------------------------
# STEP 2 — Create dataset folders, reset log
# --------------------------------------------------
log "STEP 2 — Create folders"
for sub in logs volumes backups tmp; do mkdir -p "$DATA_DIR/$sub"; done
SCRIPT_LOG_DIR="$DATA_DIR/logs"
SCRIPT_LOG="$SCRIPT_LOG_DIR/${SCRIPT_NAME}.log"
touch "$SCRIPT_LOG"
log "Folders ready in $DATA_DIR"

# Fix perms
chown -R "${SUDO_USER:-$USER}":"${SUDO_USER:-$USER}" "$DATA_DIR" "$CONFIG_DIR"
chmod -R 755 "$DATA_DIR" "$CONFIG_DIR"
pause

# --------------------------------------------------
# STEP 3 — Hardware detection
# --------------------------------------------------
log "STEP 3 — Hardware detection"
CPU_CORES=$(nproc)
RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
DISK_GB=$(df -BG "$DATA_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
GPU_PRESENT=false; GPU_MODEL="none"
if command -v nvidia-smi >/dev/null 2>&1; then
  GPU_PRESENT=true
  GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
fi
log "Hardware: CPU=$CPU_CORES cores, RAM=${RAM_GB}GB, Disk=${DISK_GB}GB, GPU=$GPU_PRESENT ($GPU_MODEL)"
pause

# --------------------------------------------------
# Utility: numbered service selector with 0=all
# --------------------------------------------------
select_services(){
  local title="$1"; shift
  local -n arr="$1"; local -n out="$2"
  echo "Select $title (0=all):"
  for i in "${!arr[@]}"; do echo "$((i+1))) ${arr[$i]}"; done
  read -rp "Numbers: " nums
  if [[ "$nums" =~ (^| )0($| ) ]]; then
    out=("${arr[@]}"); return
  fi
  out=()
  for n in $nums; do
    if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#arr[@]} )); then
      out+=("${arr[$((n-1))]}")
    fi
  done
}

# --------------------------------------------------
# STEP 4 — Choose Services
# --------------------------------------------------
CORE=("Ollama" "AnythingLLM" "LiteLLM")
AISTACK=("Dify" "ComfyUI" "OpenWebUI" "OpenClaw_UI" "Flowise" "n8n" "SuperTokens")
OPTIONAL=("Grafana" "Prometheus" "ELK" "Portainer")

declare -A SERVICES_SELECTED
declare -A SERVICE_PORTS
declare -A INTERNAL_LLM_KEYS
declare -A EXTERNAL_PROVIDER_KEYS

# init
for svc in "${CORE[@]}" "${AISTACK[@]}" "${OPTIONAL[@]}"; do
  SERVICES_SELECTED["$svc"]=false
  SERVICE_PORTS["$svc"]=10000
done

select_services "Core components" CORE SELECTED_CORE
select_services "AI Stack services" AISTACK SELECTED_AI
select_services "Optional services" OPTIONAL SELECTED_OPT

for s in "${SELECTED_CORE[@]}" "${SELECTED_AI[@]}" "${SELECTED_OPT[@]}"; do
  SERVICES_SELECTED["$s"]=true
done

log "Services selected"
pause

# --------------------------------------------------
# STEP 5 — Domain + Proxy + SSL
# --------------------------------------------------
log "STEP 5 — Domain + Proxy setup"
read -rp "Main domain: " DOMAIN_NAME
while ! dig +short "$DOMAIN_NAME" >/dev/null 2>&1; do
  echo "Domain not resolving"; read -rp "Enter valid domain: " DOMAIN_NAME
done
if prompt_yn "Configure proxy?"; then
  read -rp "Email for SSL: " PROXY_EMAIL
  SERVICES_SELECTED["Proxy"]=true
  SERVICE_PORTS["ProxyHTTP"]=80
  SERVICE_PORTS["ProxyHTTPS"]=443
fi
pause

# --------------------------------------------------
# STEP 6 — Internal LLMs
# --------------------------------------------------
IL=()
INTERNALS=("Llama2" "Llama3" "MPT-7B" "Falcon" "Google_Gemini" "Mistral")
select_services "Internal LLMs" INTERNALS IL
for llm in "${IL[@]}"; do
  INTERNAL_LLM_KEYS["$llm"]="$(openssl rand -hex 16)"
done
pause

# --------------------------------------------------
# STEP 7 — External LLM Providers
# --------------------------------------------------
PROVIDERS=("OpenAI" "Cohere" "Anthropic" "GoogleVertex" "OpenRouter" "GROQ" "Google_Gemini")
for p in "${PROVIDERS[@]}"; do
  if prompt_yn "Use provider $p?"; then
    read -rp "API key: " ext_key
    EXTERNAL_PROVIDER_KEYS["$p"]="$ext_key"
  fi
done
pause

# --------------------------------------------------
# STEP 8 — Vector DB & OpenClaw config
# --------------------------------------------------
VDB=("Postgres" "Redis" "Milvus" "Weaviate" "Qdrant" "Chroma" "None")
VDSELECTION=()
select_services "Vector DB (OpenClaw)" VDB VDSELECTION
VECTOR_DB="${VDSELECTION[0]:-None}"
read -rp "Vector DB username (default vectoruser): " DBUSER
DBUSER="${DBUSER:-vectoruser}"
DBPASS="$(openssl rand -hex 12)"

cat >"$OPENCLAW_CONF_FILE"<<EOF
{
  "vector_db":"$VECTOR_DB",
  "db_user":"$DBUSER",
  "db_pass":"$DBPASS",
  "api_key":"$(openssl rand -hex 16)"
}
EOF
pause

# --------------------------------------------------
# STEP 9 — LiteLLM routing
# --------------------------------------------------
ROUTES=("Round-robin" "Priority" "Weighted")
echo "LiteLLM Routing:"
for i in "${!ROUTES[@]}"; do echo "$((i+1))) ${ROUTES[$i]}"; done
while true; do read -rp "Pick number: " rchoice
  if [[ "$rchoice" =~ ^[1-3]$ ]]; then
    LITELLM_ROUTING="${ROUTES[$((rchoice-1))]}"; break
  fi
done
pause

# --------------------------------------------------
# STEP 10 — Google Drive
# --------------------------------------------------
echo "Google Drive config modes:"
echo "1) Project ID + Secret"
echo "2) OAuth URL"
echo "3) Rsync only"
read -rp "Mode [1-3]: " GDRIVE_MODE
case "$GDRIVE_MODE" in
  1) read -rp "Project ID: " GOOGLE_PROJECT_ID; read -rp "Secret: " GOOGLE_SECRET ;;
  2) read -rp "OAuth URL: " GOOGLE_OAUTH_URL ;;
  3) read -rp "Rsync URL: " GOOGLE_RSYNC_URL ;;
esac
pause

# --------------------------------------------------
# STEP 11 — Tailscale
# --------------------------------------------------
read -rp "Tailscale Auth Key (optional): " TAILSCALE_AUTH_KEY
read -rp "Tailscale API Key (optional): " TAILSCALE_API_KEY
pause

# --------------------------------------------------
# STEP 12 — Signal
# --------------------------------------------------
read -rp "Signal user phone number: " SIGNAL_USER_NUMBER
pause

# --------------------------------------------------
# STEP 13 — Assign service ports
# --------------------------------------------------
for svc in "${!SERVICES_SELECTED[@]}"; do
  if [[ "${SERVICES_SELECTED[$svc]}" == true ]]; then
    def="${SERVICE_PORTS[$svc]:-10000}"
    read -rp "Port for $svc (default $def): " inp
    SERVICE_PORTS["$svc"]="${inp:-$def}"
  fi
done
pause

# --------------------------------------------------
# STEP 14 — Write .env + credentials
# --------------------------------------------------
{
echo "DOMAIN_NAME=\"$DOMAIN_NAME\""
echo "VECTOR_DB=\"$VECTOR_DB\""
echo "VECTOR_DB_USER=\"$DBUSER\""
echo "VECTOR_DB_PASS=\"$DBPASS\""
echo "LITELLM_ROUTING=\"$LITELLM_ROUTING\""
echo "TAILSCALE_AUTH_KEY=\"$TAILSCALE_AUTH_KEY\""
echo "TAILSCALE_API_KEY=\"$TAILSCALE_API_KEY\""
echo "SIGNAL_USER_NUMBER=\"$SIGNAL_USER_NUMBER\""
echo "GDRIVE_MODE=\"$GDRIVE_MODE\""
echo "PROXY_EMAIL=\"${PROXY_EMAIL:-}\""
for llm in "${!INTERNAL_LLM_KEYS[@]}"; do
  echo "INTERNAL_LLM_$llm=${INTERNAL_LLM_KEYS[$llm]}"
done
for p in "${!EXTERNAL_PROVIDER_KEYS[@]}"; do
  echo "EXTERNAL_PROVIDER_$p=${EXTERNAL_PROVIDER_KEYS[$p]}"
done
for svc in "${!SERVICE_PORTS[@]}"; do
  echo "SERVICE_$svc=${SERVICES_SELECTED[$svc]}"
  echo "PORT_$svc=${SERVICE_PORTS[$svc]}"
done
} >"$ENV_FILE"

cat <<EOF >"$CREDENTIALS_FILE"
VECTOR_DB_USER=$DBUSER
VECTOR_DB_PASS=$DBPASS
SIGNAL_USER_NUMBER=$SIGNAL_USER_NUMBER
EOF

# --------------------------------------------------
# STEP 15 — Final Summary
# --------------------------------------------------
log "Configuration summary (deployment after Script 2):"
for svc in "${!SERVICES_SELECTED[@]}"; do
  if [[ "${SERVICES_SELECTED[$svc]}" == true ]]; then
    echo "$svc -> http://$DOMAIN_NAME:${SERVICE_PORTS[$svc]}/"
  fi
done
log "Script 1 complete — Run ./2-deploy-services.sh next."
