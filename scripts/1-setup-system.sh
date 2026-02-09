#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="1-setup-system-config"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_PATH="$ROOT_DIR"
DEFAULT_DATA_DIR="/mnt/data"
CONFIG_DIR="$HOME_PATH/config"
ENV_FILE="$CONFIG_DIR/.env"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.txt"
OPENCLAW_CONF_FILE="$CONFIG_DIR/openclaw_config.json"

# -----------------------------
# Utilities
# -----------------------------
log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SCRIPT_LOG"; }
fail() { log "ERROR: $*"; exit 1; }
prompt_yn() { local prompt="$1"; local default="${2:-y}"; local choice; while true; do read -rp "$prompt [y/n] (default: $default): " choice; choice="${choice:-$default}"; choice="${choice:-$default}"; case "$choice" in y|Y) return 0 ;; n|N) return 1 ;; *) echo "Please answer y or n." ;; esac; done; }
pause() { read -rp "Press ENTER to continue..."; }
require_root() { [[ $EUID -eq 0 ]] || fail "Run as root"; }
require_root

# -----------------------------
# STEP 0 — Detect existing configuration
# -----------------------------
if [ -f "$ENV_FILE" ]; then
  log "Existing configuration detected at $ENV_FILE"
  if prompt_yn "Do you want to run the nuclear cleanup first?"; then
    log "Please run ./0-complete-cleanup.sh and restart Script 1."
    exit 0
  else
    log "Continuing with existing configuration..."
  fi
elif [ -d "$CONFIG_DIR" ] && [ -z "$(ls -A "$CONFIG_DIR")" ]; then
  log "Config folder exists but empty. Proceeding with fresh setup..."
else
  log "No existing configuration detected. Proceeding with fresh setup..."
fi

# -----------------------------
# STEP 1 — Select /mnt/data volume or mount device
# -----------------------------
log "STEP 1 — Data volume selection and mount"

# Check if already mounted
if mountpoint -q "$DEFAULT_DATA_DIR"; then
    log "$DEFAULT_DATA_DIR is already mounted, skipping mount."
    DATA_DIR="$DEFAULT_DATA_DIR"
else
    echo "Select device to mount for AIPlatform data:"
    mapfile -t devices < <(lsblk -dpno NAME,SIZE,TYPE | awk '$3=="disk"{print $1":"$2}')
    for i in "${!devices[@]}"; do echo "$((i+1))) ${devices[$i]}"; done
    read -rp "Enter number of device to mount (or ENTER to skip and use default path $DEFAULT_DATA_DIR): " dev_choice
    if [[ -n "$dev_choice" && "$dev_choice" =~ ^[0-9]+$ && "$dev_choice" -ge 1 && "$dev_choice" -le ${#devices[@]} ]]; then
        selected_device="${devices[$((dev_choice-1))]%:*}"
        fs_type="ext4"
        read -rp "Enter filesystem type for device $selected_device (default: ext4): " input_fs
        fs_type="${input_fs:-$fs_type}"
        mkdir -p "$DEFAULT_DATA_DIR"
        log "Mounting $selected_device at $DEFAULT_DATA_DIR with type $fs_type"
        mount -t "$fs_type" "$selected_device" "$DEFAULT_DATA_DIR"
    fi
    DATA_DIR="$DEFAULT_DATA_DIR"
fi

# -----------------------------
# STEP 2 — Create folders & logs
# -----------------------------
log "STEP 2 — Creating folder structure in $DATA_DIR"
FOLDERS=("logs" "volumes" "backups" "tmp")
mkdir -p "$DATA_DIR"
for sub in "${FOLDERS[@]}"; do mkdir -p "$DATA_DIR/$sub"; done
mkdir -p "$CONFIG_DIR"
SCRIPT_LOG_DIR="$DATA_DIR/logs"
SCRIPT_LOG="$SCRIPT_LOG_DIR/${SCRIPT_NAME}.log"
touch "$SCRIPT_LOG"
chown -R "${SUDO_USER:-$USER}":"${SUDO_USER:-$USER}" "$DATA_DIR" "$CONFIG_DIR"
chmod -R 755 "$DATA_DIR" "$CONFIG_DIR"
log "Folder structure created under $DATA_DIR and $CONFIG_DIR"

# -----------------------------
# STEP 3 — Hardware Detection
# -----------------------------
CPU_CORES=$(nproc)
RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
DISK_GB=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
GPU_PRESENT=false; GPU_MODEL="none"
if command -v nvidia-smi >/dev/null 2>&1; then GPU_PRESENT=true; GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1); fi
log "Detected hardware: CPU=${CPU_CORES} cores, RAM=${RAM_GB}GB, Disk=${DISK_GB}GB, GPU=$GPU_PRESENT ($GPU_MODEL)"
pause

# -----------------------------
# STEP 4 — Service Selection
# -----------------------------
log "STEP 4 — Service Selection"
CORE_COMPONENTS=("Ollama" "AnythingLLM" "LiteLLM")
SELECTED_CORE=(); prompt_select_numbers "Select Core Components" CORE_COMPONENTS SELECTED_CORE
AI_STACK=("Dify" "ComfyUI" "OpenWebUI" "OpenClaw_UI" "Flowise" "n8n" "SuperTokens")
SELECTED_AI=(); prompt_select_numbers "Select AI Stack / App Layer services" AI_STACK SELECTED_AI
OPTIONAL_SERVICES=("Grafana" "Prometheus" "ELK" "Portainer")
SELECTED_OPTIONAL=(); prompt_select_numbers "Select Optional / Monitoring services" OPTIONAL_SERVICES SELECTED_OPTIONAL

# -----------------------------
# Initialize service arrays
# -----------------------------
declare -A SERVICE_PORTS
declare -A SERVICES_SELECTED
declare -A INTERNAL_LLM_KEYS
declare -A PROVIDER_KEYS

for svc in "${CORE_COMPONENTS[@]}" "${AI_STACK[@]}" "${OPTIONAL_SERVICES[@]}"; do
  safe_name=$(echo "$svc" | tr '[:lower:] ' '[:upper:]_')
  SERVICES_SELECTED["$safe_name"]=false
done
for svc in "${SELECTED_CORE[@]}" "${SELECTED_AI[@]}" "${SELECTED_OPTIONAL[@]}"; do
  safe_name=$(echo "$svc" | tr '[:lower:] ' '[:upper:]_')
  SERVICES_SELECTED["$safe_name"]=true
done
pause

# -----------------------------
# STEP 5 — Domain + Proxy + SSL
# -----------------------------
log "STEP 5 — Domain and Proxy setup"
read -rp "Enter main domain/subdomain: " DOMAIN_NAME
DOMAIN_IP=$(dig +short "$DOMAIN_NAME" | head -n1 || true)
while [[ -z "$DOMAIN_IP" ]]; do echo "Domain cannot resolve"; read -rp "Enter valid domain: " DOMAIN_NAME; DOMAIN_IP=$(dig +short "$DOMAIN_NAME" | head -n1 || true); done
log "Domain $DOMAIN_NAME resolves to $DOMAIN_IP"

PROXY_EMAIL=""
if prompt_yn "Do you want to configure a proxy?"; then
  SERVICES_SELECTED["PROXY"]=true
  while [[ -z "$PROXY_EMAIL" ]]; do read -rp "Enter email for SSL certificates: " PROXY_EMAIL; done
  SERVICE_PORTS["PROXY_HTTP"]=80
  SERVICE_PORTS["PROXY_HTTPS"]=443
fi
pause

# -----------------------------
# STEP 6 — Internal LLMs
# -----------------------------
INTERNAL_LLMS=("Llama2" "Llama3" "MPT-7B" "Falcon" "Google_Gemini" "Mistral")
SELECTED_INTERNAL_LLMS=(); prompt_select_numbers "Select Internal LLMs to include" INTERNAL_LLMS SELECTED_INTERNAL_LLMS
for llm in "${SELECTED_INTERNAL_LLMS[@]}"; do
  safe_llm=$(echo "$llm" | tr '[:lower:] ' '[:upper:]_')
  INTERNAL_LLM_KEYS["$safe_llm"]="$(openssl rand -hex 16)"
done
pause

# -----------------------------
# STEP 7 — External LLM Providers
# -----------------------------
EXTERNAL_PROVIDERS=("OpenAI" "Cohere" "Anthropic" "GoogleVertex" "OpenRouter" "GROQ" "Google_Gemini")
for provider in "${EXTERNAL_PROVIDERS[@]}"; do
  safe_provider=$(echo "$provider" | tr '[:lower:] ' '[:upper:]_')
  if prompt_yn "Use provider $provider?"; then read -rp "Enter API key for $provider: " key; PROVIDER_KEYS[$safe_provider]=$key; fi
done
pause

# -----------------------------
# STEP 8 — Vector DB & OpenClaw
# -----------------------------
VECTOR_DBS=("Postgres" "Redis" "Milvus" "Weaviate" "Qdrant" "Chroma" "None")
SELECTED_VECTOR_DB=(); prompt_select_numbers "Select Vector DB for embeddings / OpenClaw" VECTOR_DBS SELECTED_VECTOR_DB
VECTOR_DB="${SELECTED_VECTOR_DB[0]:-None}"
read -rp "Vector DB username (default vectoruser): " VECTOR_DB_USER; VECTOR_DB_USER="${VECTOR_DB_USER:-vectoruser}"
VECTOR_DB_PASS=$(openssl rand -hex 12)
cat > "$OPENCLAW_CONF_FILE" <<EOF
{
  "vector_db": "$VECTOR_DB",
  "db_user": "$VECTOR_DB_USER",
  "db_pass": "$VECTOR_DB_PASS",
  "api_key": "$(openssl rand -hex 16)"
}
EOF
pause

# -----------------------------
# STEP 9 — LiteLLM Routing
# -----------------------------
ROUTING_OPTIONS=("Round-robin" "Priority" "Weighted")
for i in "${!ROUTING_OPTIONS[@]}"; do echo "$((i+1))) ${ROUTING_OPTIONS[$i]}"; done
while true; do
  read -rp "Select LiteLLM routing strategy by number: " choice
  if [[ "$choice" =~ ^[1-3]$ ]]; then LITELLM_ROUTING="${ROUTING_OPTIONS[$((choice-1))]}"; break; else echo "Enter 1,2,3"; fi
done
pause

# -----------------------------
# STEP 10 — Google Drive / Rsync
# -----------------------------
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
# STEP 11 — Tailscale
# -----------------------------
read -rp "Auth Key (optional): " TAILSCALE_AUTH_KEY
read -rp "API Key (optional): " TAILSCALE_API_KEY
pause

# -----------------------------
# STEP 12 — Signal
# -----------------------------
read -rp "Enter Signal user phone number: " SIGNAL_USER_NUMBER
pause

# -----------------------------
# STEP 13 — Assign service ports safely
# -----------------------------
for svc in "${!SERVICES_SELECTED[@]}"; do
  if [[ "${SERVICES_SELECTED[$svc]}" == true && "$svc" != "PROXY" ]]; then
    case "$svc" in
      OLLAMA) SERVICE_PORTS[$svc]=11400 ;;
      LITELLM) SERVICE_PORTS[$svc]=8000 ;;
      DIFY) SERVICE_PORTS[$svc]=3000 ;;
      OPENWEBUI) SERVICE_PORTS[$svc]=8080 ;;
      OPENCLAW_UI) SERVICE_PORTS[$svc]=8081 ;;
      FLOWISE) SERVICE_PORTS[$svc]=5000 ;;
      N8N) SERVICE_PORTS[$svc]=5678 ;;
      SUPERTOKENS) SERVICE_PORTS[$svc]=3567 ;;
      GRAFANA) SERVICE_PORTS[$svc]=3001 ;;
      PROMETHEUS) SERVICE_PORTS[$svc]=9090 ;;
      ELK) SERVICE_PORTS[$svc]=5601 ;;
      PORTAINER) SERVICE_PORTS[$svc]=9000 ;;
      *) SERVICE_PORTS[$svc]=10000 ;;
    esac
  fi
done

# Prompt overrides
for svc in "${!SERVICES_SELECTED[@]}"; do
  if [[ "${SERVICES_SELECTED[$svc]}" == true && "$svc" != "PROXY" ]]; then
    default_port="${SERVICE_PORTS[$svc]}"
    read -rp "Assign port for $svc (default $default_port): " input_port
    SERVICE_PORTS[$svc]="${input_port:-$default_port}"
  fi
done
pause

# -----------------------------
# STEP 14 — Write .env & credentials
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
    echo "SERVICE_$svc=${SERVICES_SELECTED[$svc]}"
    echo "PORT_$svc=${SERVICE_PORTS[$svc]}"
  done
  for llm in "${!INTERNAL_LLM_KEYS[@]}"; do echo "INTERNAL_LLM_$llm=${INTERNAL_LLM_KEYS[$llm]}"; done
  for provider in "${!PROVIDER_KEYS[@]}"; do echo "EXTERNAL_PROVIDER_$provider=${PROVIDER_KEYS[$provider]}"; done
} > "$ENV_FILE"

{
  echo "VECTOR_DB_USER=$VECTOR_DB_USER"
  echo "VECTOR_DB_PASS=$VECTOR_DB_PASS"
  echo "SIGNAL_USER_NUMBER=$SIGNAL_USER_NUMBER"
  for llm in "${!INTERNAL_LLM_KEYS[@]}"; do echo "INTERNAL_LLM_$llm=${INTERNAL_LLM_KEYS[$llm]}"; done
} > "$CREDENTIALS_FILE"

# -----------------------------
# STEP 15 — Post-setup summary
# -----------------------------
log "STEP 15 — Configuration Summary"
echo "==================== SERVICE CONFIGURATION SUMMARY ===================="
printf "%-20s %-10s %-30s\n" "Service" "Port" "URL (after deployment)"
for svc in "${!SERVICES_SELECTED[@]}"; do
  if [[ "${SERVICES_SELECTED[$svc]}" == true ]]; then
    if [[ "$svc" == "PROXY" ]]; then
      echo " PROXY_HTTP  80  http://$DOMAIN_NAME:80/"
      echo " PROXY_HTTPS 443 https://$DOMAIN_NAME:443/"
    else
      port="${SERVICE_PORTS[$svc]}"
      echo " $(printf '%-18s %-10s http://%s:%s/' "$svc" "$port" "$DOMAIN_NAME" "$port")"
    fi
  fi
done
echo "======================================================================"
echo "Proxy SSL Email: ${PROXY_EMAIL:-N/A}"
echo "Tailscale Auth Key: ${TAILSCALE_AUTH_KEY:-N/A}"
echo "Tailscale API Key: ${TAILSCALE_API_KEY:-N/A}"
echo "Signal User Number: ${SIGNAL_USER_NUMBER:-N/A}"
echo "Google Drive Mode: ${GDRIVE_MODE:-N/A}"
pause

log "Script 1 configuration complete. Step 2 can now deploy services."

