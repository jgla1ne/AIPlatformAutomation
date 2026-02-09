#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="1-setup-system"
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
prompt_yn() { local prompt="$1"; local default="${2:-y}"; local choice; while true; do read -rp "$prompt [y/n] (default: $default): " choice; choice="${choice:-$default}"; case "$choice" in y|Y) return 0 ;; n|N) return 1 ;; *) echo "Please answer y or n." ;; esac; done; }
pause() { read -rp "Press ENTER to continue..."; }
require_root() { [[ $EUID -eq 0 ]] || fail "Run as root"; }
require_root

# -----------------------------
# STEP 0 — Existing configuration
# -----------------------------
SCRIPT_LOG="/tmp/${SCRIPT_NAME}.log"
touch "$SCRIPT_LOG"
if [ -f "$ENV_FILE" ]; then
    log "Existing configuration detected at $ENV_FILE"
    if prompt_yn "Do you want to run nuclear cleanup first?"; then
        log "Please run ./0-complete-cleanup.sh and restart Script 1."
        exit 0
    else
        log "Continuing with existing configuration..."
    fi
fi
mkdir -p "$CONFIG_DIR"

# -----------------------------
# STEP 1 — Data volume
# -----------------------------
DATA_DIR="$DEFAULT_DATA_DIR"
if ! mountpoint -q "$DEFAULT_DATA_DIR"; then
    echo "Select device to mount for AIPlatform data:"
    mapfile -t devices < <(lsblk -dpno NAME,SIZE,TYPE | awk '$3=="disk"{print $1":"$2}')
    for i in "${!devices[@]}"; do echo "$((i+1))) ${devices[$i]}"; done
    read -rp "Enter number of device to mount (ENTER to use default $DEFAULT_DATA_DIR): " dev_choice
    if [[ -n "$dev_choice" && "$dev_choice" =~ ^[0-9]+$ && "$dev_choice" -ge 1 && "$dev_choice" -le ${#devices[@]} ]]; then
        selected_device="${devices[$((dev_choice-1))]%:*}"
        fs_type="ext4"
        read -rp "Enter filesystem type for $selected_device (default ext4): " input_fs
        fs_type="${input_fs:-$fs_type}"
        mkdir -p "$DEFAULT_DATA_DIR"
        log "Mounting $selected_device at $DEFAULT_DATA_DIR with type $fs_type"
        mount -t "$fs_type" "$selected_device" "$DEFAULT_DATA_DIR"
    fi
fi

# -----------------------------
# STEP 2 — Create folders
# -----------------------------
FOLDERS=("logs" "volumes" "backups" "tmp")
mkdir -p "$DATA_DIR"
for sub in "${FOLDERS[@]}"; do mkdir -p "$DATA_DIR/$sub"; done
mkdir -p "$CONFIG_DIR"
SCRIPT_LOG_DIR="$DATA_DIR/logs"
SCRIPT_LOG="$SCRIPT_LOG_DIR/${SCRIPT_NAME}.log"
touch "$SCRIPT_LOG"
chown -R "${SUDO_USER:-$USER}":"${SUDO_USER:-$USER}" "$DATA_DIR" "$CONFIG_DIR"
chmod -R 755 "$DATA_DIR" "$CONFIG_DIR"
log "Folder structure ready at $DATA_DIR and $CONFIG_DIR"
pause

# -----------------------------
# STEP 3 — Hardware detection
# -----------------------------
CPU_CORES=$(nproc)
RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
DISK_GB=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
GPU_PRESENT=false; GPU_MODEL="none"
if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_PRESENT=true
    GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
fi
log "Detected hardware: CPU=${CPU_CORES} cores, RAM=${RAM_GB}GB, Disk=${DISK_GB}GB, GPU=$GPU_PRESENT ($GPU_MODEL)"
pause

# -----------------------------
# STEP 4 — Service selection (0=all)
# -----------------------------
CORE_COMPONENTS=("Ollama" "AnythingLLM" "LiteLLM")
AI_STACK=("Dify" "ComfyUI" "OpenWebUI" "OpenClaw_UI" "Flowise" "n8n" "SuperTokens")
OPTIONAL_SERVICES=("Grafana" "Prometheus" "ELK" "Portainer")

declare -A SERVICES_SELECTED
declare -A SERVICE_PORTS
declare -A INTERNAL_LLM_KEYS
declare -A PROVIDER_KEYS

# Initialize
for svc in "${CORE_COMPONENTS[@]}" "${AI_STACK[@]}" "${OPTIONAL_SERVICES[@]}"; do
    safe_name=$(echo "$svc" | tr '[:lower:] ' '[:upper:]_')
    SERVICES_SELECTED["$safe_name"]=false
    SERVICE_PORTS["$safe_name"]=10000
done

select_services() {
    local section="$1"; shift
    local -n options=$1
    local -n sel_out=$2
    echo "Select $section services (0=All):"
    for i in "${!options[@]}"; do echo "$((i+1))) ${options[$i]}"; done
    read -rp "Enter numbers separated by space: " input
    sel_out=()
    if [[ "$input" =~ (^|[[:space:]])0($|[[:space:]]) ]]; then
        sel_out=("${options[@]}")
    else
        for n in $input; do
            if [[ "$n" =~ ^[0-9]+$ && $n -ge 1 && $n -le ${#options[@]} ]]; then
                sel_out+=("${options[$((n-1))]}")
            fi
        done
    fi
}

SELECTED_CORE=(); select_services "Core" CORE_COMPONENTS SELECTED_CORE
for svc in "${SELECTED_CORE[@]}"; do SERVICES_SELECTED["$(echo "$svc" | tr '[:lower:] ' '[:upper:]_')"]=true; done
SELECTED_AI=(); select_services "AI Stack / App Layer" AI_STACK SELECTED_AI
for svc in "${SELECTED_AI[@]}"; do SERVICES_SELECTED["$(echo "$svc" | tr '[:lower:] ' '[:upper:]_')"]=true; done
SELECTED_OPTIONAL=(); select_services "Optional / Monitoring" OPTIONAL_SERVICES SELECTED_OPTIONAL
for svc in "${SELECTED_OPTIONAL[@]}"; do SERVICES_SELECTED["$(echo "$svc" | tr '[:lower:] ' '[:upper:]_')"]=true; done

log "Services selected:"
for svc in "${!SERVICES_SELECTED[@]}"; do log " $svc : ${SERVICES_SELECTED[$svc]}"; done
pause

# -----------------------------
# STEP 5 — Domain + Proxy + SSL
# -----------------------------
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
SELECTED_INTERNAL_LLMS=()
select_services "Internal LLMs" INTERNAL_LLMS SELECTED_INTERNAL_LLMS
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
    if prompt_yn "Use provider $provider?"; then
        read -rp "Enter API key for $provider: " key
        PROVIDER_KEYS[$safe_provider]=$key
    fi
done
pause

# -----------------------------
# STEP 8 — Vector DB & OpenClaw
# -----------------------------
VECTOR_DBS=("Postgres" "Redis" "Milvus" "Weaviate" "Qdrant" "Chroma" "None")
SELECTED_VECTOR_DB=()
select_services "Vector DB for embeddings/OpenClaw" VECTOR_DBS SELECTED_VECTOR_DB
VECTOR_DB="${SELECTED_VECTOR_DB[0]:-None}"
read -rp "Vector DB username (default vectoruser): " VECTOR_DB_USER
VECTOR_DB_USER="${VECTOR_DB_USER:-vectoruser}"
VECTOR_DB_PASS=$(openssl rand -hex 12)

# Write credentials / OpenClaw config
cat > "$OPENCLAW_CONF_FILE" <<EOF
VECTOR_DB_USER=$VECTOR_DB_USER
VECTOR_DB_PASS=$VECTOR_DB_PASS
EOF

cat > "$CREDENTIALS_FILE" <<EOF
SIGNAL_USER_NUMBER=
EOF

# -----------------------------
# STEP 9 — Post-setup summary
# -----------------------------
log "Configuration complete. Files:"
log " - $ENV_FILE"
log " - $CREDENTIALS_FILE"
log " - $OPENCLAW_CONF_FILE"
log "Services selected (ports may change in Step 2 deployment):"
for svc in "${!SERVICES_SELECTED[@]}"; do
    if [[ "${SERVICES_SELECTED[$svc]}" == true ]]; then
        port="${SERVICE_PORTS[$svc]:-N/A}"
        log " $svc : port $port"
    fi
done

pause
log "Script 1 final setup complete. Ready for Step 2 deployment."
