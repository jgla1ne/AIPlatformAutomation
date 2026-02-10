#!/bin/bash
# Script 1: Setup System and Configuration for AI Platform
# Fully completed and aligned with Script 2 requirements
# Preserves UI, menus, steps, arrays, colors, and paths
# Smoke-test ready

set -euo pipefail
IFS=$'\n\t'

# ===== Color helpers =====
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

info() { echo -e "${BLUE}[INFO]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

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

info "Architecture: $ARCH, CPU cores: $CPU_CORES, Memory: ${TOTAL_MEM}MB, Disk: $TOTAL_DISK"

# Detect GPU if NVIDIA present
if command -v nvidia-smi &>/dev/null; then
    HARDWARE_TYPE="GPU"
    info "NVIDIA GPU detected."
else
    HARDWARE_TYPE="CPU"
    info "No GPU detected. Using CPU mode."
fi

# ===== Network Info =====
PRIMARY_IP=$(hostname -I | awk '{print $1}')
if [ -z "$PRIMARY_IP" ]; then
    read -rp "Enter the primary IP for this host: " PRIMARY_IP
fi
info "Using primary IP: $PRIMARY_IP"

# ===== User Inputs =====
echo -e "\n${BLUE}Step 1: Base domain and admin information${RESET}"
read -rp "Enter the base domain/subdomain (e.g., ai.example.com): " BASE_DOMAIN
read -rp "Enter admin email: " ADMIN_EMAIL

# ===== Service Selection =====
echo -e "\n${BLUE}Step 2: Select services to deploy${RESET}"
declare -A ENABLE_SERVICES
SERVICES=("OLLAMA" "LITELLM" "OPENWEBUI" "DIFY" "N8N" "POSTGRES" "REDIS" "HUGGINGFACE" "GRADIO" "FASTAPI" "CUSTOM_APP")
for svc in "${SERVICES[@]}"; do
    read -rp "Enable $svc? (y/N): " resp
    ENABLE_SERVICES[$svc]=${resp,,}  # convert to lowercase
done

# ===== LLM Providers =====
echo -e "\n${BLUE}Step 3: Configure LLM providers${RESET}"
declare -A LLM_PROVIDERS
LLM_LIST=("OPENAI" "ANTHROPIC" "COHERE")
for provider in "${LLM_LIST[@]}"; do
    read -rp "Enable $provider? (y/N): " resp
    if [[ "${resp,,}" == "y" ]]; then
        read -rp "Enter API key for $provider: " key
        LLM_PROVIDERS[$provider]=$key
    fi
done

# ===== Generate credentials for services =====
echo -e "\n${BLUE}Step 4: Generating service credentials${RESET}"
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

if [[ "${ENABLE_SERVICES[N8N],,}" == "y" ]]; then
    N8N_BASIC_AUTH_USER="admin"
    N8N_BASIC_AUTH_PASSWORD=$(openssl rand -base64 16)
    CREDENTIALS["N8N_BASIC_AUTH_USER"]=$N8N_BASIC_AUTH_USER
    CREDENTIALS["N8N_BASIC_AUTH_PASSWORD"]=$N8N_BASIC_AUTH_PASSWORD
fi

# Add any other service-specific credentials here
# Example placeholder:
# CREDENTIALS["SERVICE_KEY"]="value"

# ===== Proxy / TLS Configuration =====
echo -e "\n${BLUE}Step 5: Proxy selection${RESET}"
read -rp "Use Caddy proxy with Let's Encrypt? (y/N): " USE_CADDY
USE_LETSENCRYPT="false"
if [[ "${USE_CADDY,,}" == "y" ]]; then
    USE_LETSENCRYPT="true"
fi

# ===== Save configuration =====
CONFIG_FILE="$CONFIG_DIR/platform_config.env"
info "Saving configuration to $CONFIG_FILE"
{
    echo "BASE_DOMAIN=$BASE_DOMAIN"
    echo "ADMIN_EMAIL=$ADMIN_EMAIL"
    echo "PRIMARY_IP=$PRIMARY_IP"
    echo "HARDWARE_TYPE=$HARDWARE_TYPE"
    echo "USE_LETSENCRYPT=$USE_LETSENCRYPT"
    for svc in "${SERVICES[@]}"; do
        flag=${ENABLE_SERVICES[$svc]:-n}
        echo "ENABLE_${svc}=${flag,,}"
    done
    for provider in "${!LLM_PROVIDERS[@]}"; do
        echo "LLM_${provider}=${LLM_PROVIDERS[$provider]}"
    done
    for key in "${!CREDENTIALS[@]}"; do
        echo "$key=${CREDENTIALS[$key]}"
    done
} > "$CONFIG_FILE"

info "Configuration saved successfully."

# ===== Final Summary =====
echo -e "\n${GREEN}Configuration Summary:${RESET}"
echo "Base domain: $BASE_DOMAIN"
echo "Admin email: $ADMIN_EMAIL"
echo "Primary IP: $PRIMARY_IP"
echo "Hardware type: $HARDWARE_TYPE"
echo "Use Caddy / Let's Encrypt: $USE_LETSENCRYPT"
echo "Enabled services:"
for svc in "${SERVICES[@]}"; do
    [[ "${ENABLE_SERVICES[$svc],,}" == "y" ]] && echo "  - $svc"
done
echo "Configured LLM providers:"
for provider in "${!LLM_PROVIDERS[@]}"; do
    echo "  - $provider"
done

info "Script 1 completed. You can now proceed to run Script 2 to deploy services."

exit 0
