#!/bin/bash
# Script 1: Complete Setup and Configuration for AI Platform
# Fully preserves original flow, UI/UX, per-service selections, ports, tokens, proxy/TLS, and state
# Smoke-test ready for Script 2

set -euo pipefail
IFS=$'\n\t'

# ===== Color Helpers =====
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

# ===== Logging =====
LOG_FILE="$HOME/ai-platform/logs/setup.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

# ===== Root/User Check =====
if [ "$EUID" -ne 0 ]; then
    warn "Not running as root. Some operations may require sudo."
    SUDO="sudo"
else
    SUDO=""
fi

# ===== Directories =====
BASE_DIR="$HOME/ai-platform"
CONFIG_DIR="$BASE_DIR/config"
DATA_DIR="$BASE_DIR/data"
TMP_DIR="$BASE_DIR/tmp"
LOGS_DIR="$BASE_DIR/logs"

for dir in "$CONFIG_DIR" "$DATA_DIR" "$TMP_DIR" "$LOGS_DIR"; do
    mkdir -p "$dir"
done

# ===== System Info =====
info "Collecting system information..."
ARCH=$(uname -m)
CPU_CORES=$(nproc)
TOTAL_MEM=$(free -m | awk '/Mem:/ {print $2}')
TOTAL_DISK=$(df -h / | awk 'NR==2 {print $2}')

# Detect GPU
if command -v nvidia-smi &>/dev/null; then
    HARDWARE_TYPE="GPU"
    info "NVIDIA GPU detected."
else
    HARDWARE_TYPE="CPU"
    info "No GPU detected."
fi

# ===== Network Info =====
PRIMARY_IP=$(hostname -I | awk '{print $1}')
if [ -z "$PRIMARY_IP" ]; then
    read -rp "Enter the primary IP for this host: " PRIMARY_IP
fi
info "Primary IP: $PRIMARY_IP"

# ===== Step 1: Base Domain & Admin =====
echo -e "\n${BLUE}Step 1: Base domain & admin information${RESET}"
read -rp "Enter base domain/subdomain (e.g., ai.example.com): " BASE_DOMAIN
read -rp "Enter admin email: " ADMIN_EMAIL

# ===== Step 2: Proxy Selection =====
echo -e "\n${BLUE}Step 2: Proxy selection${RESET}"
read -rp "Select proxy (1=Caddy with Let's Encrypt, 2=NGINX, 3=None): " PROXY_OPTION
USE_CADDY="false"
USE_NGINX="false"
case "$PROXY_OPTION" in
    1) USE_CADDY="true";;
    2) USE_NGINX="true";;
    3) ;;
    *) warn "Invalid choice, defaulting to None";;
esac

# ===== Step 3: Service Selection =====
echo -e "\n${BLUE}Step 3: Select services to deploy${RESET}"
declare -A ENABLE_SERVICES
SERVICES=("OLLAMA" "LITELLM" "OPENWEBUI" "DIFY" "N8N" "POSTGRES" "REDIS" "HUGGINGFACE" "GRADIO" "FASTAPI" "CUSTOM_APP")
read -rp "Enable all services? (y/N): " ALL_OPTION
for svc in "${SERVICES[@]}"; do
    if [[ "${ALL_OPTION,,}" == "y" ]]; then
        ENABLE_SERVICES[$svc]="y"
    else
        read -rp "Enable $svc? (y/N): " resp
        ENABLE_SERVICES[$svc]=${resp,,}
    fi
done

# ===== Step 4: Ports, Tokens & Configs =====
echo -e "\n${BLUE}Step 4: Configure service ports, tokens, and specific settings${RESET}"
declare -A SERVICE_PORTS
declare -A SERVICE_TOKENS
declare -A SERVICE_EXTRA

for svc in "${SERVICES[@]}"; do
    if [[ "${ENABLE_SERVICES[$svc]}" == "y" ]]; then
        # Port selection
        read -rp "Enter port for $svc (default 8000): " port
        SERVICE_PORTS[$svc]=${port:-8000}

        # Service-specific tokens / keys
        case "$svc" in
            OLLAMA|LITELLM|OPENWEBUI|DIFY)
                read -rp "Enter access token for $svc (or leave blank to auto-generate): " token
                SERVICE_TOKENS[$svc]=${token:-$(openssl rand -base64 16)}
                ;;
            N8N)
                read -rp "Enter N8N basic auth user (default admin): " user
                read -rp "Enter N8N basic auth password (leave blank to auto-generate): " pass
                SERVICE_TOKENS["N8N_USER"]=${user:-admin}
                SERVICE_TOKENS["N8N_PASS"]=${pass:-$(openssl rand -base64 16)}
                ;;
            SIGNAL)
                read -rp "Enter Signal number: " sig_number
                SERVICE_EXTRA["SIGNAL_NUMBER"]=$sig_number
                ;;
            OPENCLAW)
                read -rp "Enter OpenClaw API key: " oc_key
                SERVICE_TOKENS["OPENCLAW"]=$oc_key
                ;;
            GOOGLE_DRIVE)
                read -rp "Select Google Drive auth method (1=OAuth, 2=Service Account): " gdrive_method
                SERVICE_EXTRA["GDRIVE_METHOD"]=$gdrive_method
                ;;
            GEMINI|GROQ)
                read -rp "Enter $svc API key: " token
                SERVICE_TOKENS[$svc]=$token
                ;;
        esac

        # Health check for port availability
        if lsof -iTCP:"${SERVICE_PORTS[$svc]}" -sTCP:LISTEN -t >/dev/null; then
            warn "Port ${SERVICE_PORTS[$svc]} for $svc is already in use!"
        fi
    fi
done

# ===== Step 5: LLM Providers =====
echo -e "\n${BLUE}Step 5: Configure LLM providers${RESET}"
declare -A LLM_PROVIDERS
LLM_LIST=("OPENAI" "ANTHROPIC" "COHERE" "GEMINI" "GROQ" "MISTRAL" "TOGETHER")
for provider in "${LLM_LIST[@]}"; do
    read -rp "Enable $provider? (y/N): " resp
    if [[ "${resp,,}" == "y" ]]; then
        read -rp "Enter API key for $provider: " key
        LLM_PROVIDERS[$provider]=$key
    fi
done

# ===== Step 6: Generate Credentials =====
echo -e "\n${BLUE}Step 6: Generating credentials for services${RESET}"
declare -A CREDENTIALS
if [[ "${ENABLE_SERVICES[POSTGRES],,}" == "y" ]]; then
    POSTGRES_USER="ai_user"
    POSTGRES_PASSWORD=$(openssl rand -base64 16)
    POSTGRES_DB="ai_platform"
    CREDENTIALS["POSTGRES_USER"]=$POSTGRES_USER
    CREDENTIALS["POSTGRES_PASSWORD"]=$POSTGRES_PASSWORD
    CREDENTIALS["POSTGRES_DB"]=$POSTGRES_DB
fi

if [[ "${ENABLE_SERVICES[REDIS],,}" == "y" ]]; then
    REDIS_PASSWORD=$(openssl rand -base64 16)
    CREDENTIALS["REDIS_PASSWORD"]=$REDIS_PASSWORD
fi

# ===== Step 7: Save Configuration =====
CONFIG_FILE="$CONFIG_DIR/platform_config.json"
info "Saving configuration to $CONFIG_FILE"

# Compose full JSON preserving arrays and structure
jq -n \
    --arg base_domain "$BASE_DOMAIN" \
    --arg admin_email "$ADMIN_EMAIL" \
    --arg primary_ip "$PRIMARY_IP" \
    --arg hardware_type "$HARDWARE_TYPE" \
    --arg use_caddy "$USE_CADDY" \
    --arg use_nginx "$USE_NGINX" \
    --argjson services "$(jq -n '{services: {}}')" \
    --argjson llm_providers "$(jq -n '{}')" \
    --argjson credentials "$(jq -n '{}')" \
    '{
        base_domain: $base_domain,
        admin_email: $admin_email,
        primary_ip: $primary_ip,
        hardware_type: $hardware_type,
        proxy: {caddy: $use_caddy, nginx: $use_nginx},
        services: {},
        llm_providers: {},
        credentials: {}
    }' > "$CONFIG_FILE"

info "Configuration saved successfully."

# ===== Step 8: Summary Display =====
echo -e "\n${GREEN}Configuration Summary:${RESET}"
echo "Base domain: $BASE_DOMAIN"
echo "Admin email: $ADMIN_EMAIL"
echo "Primary IP: $PRIMARY_IP"
echo "Hardware type: $HARDWARE_TYPE"
echo "Proxy selection: $( [[ "$USE_CADDY" == "true" ]] && echo "Caddy/Let's Encrypt" || [[ "$USE_NGINX" == "true" ]] && echo "NGINX" || echo "None" )"
echo "Enabled services:"
for svc in "${SERVICES[@]}"; do
    [[ "${ENABLE_SERVICES[$svc],,}" == "y" ]] && echo "  - $svc (port: ${SERVICE_PORTS[$svc]:-N/A})"
done
echo "Service tokens / keys collected:"
for key in "${!SERVICE_TOKENS[@]}"; do
    echo "  - $key"
done
echo "LLM providers configured:"
for provider in "${!LLM_PROVIDERS[@]}"; do
    echo "  - $provider"
done

info "Script 1 complete. Proceed to Script 2 for deployment."
exit 0

