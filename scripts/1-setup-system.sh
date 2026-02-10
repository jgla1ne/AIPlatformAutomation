#!/bin/bash
# Script 1: Setup System and Configuration for AI Platform
# Fully completed version preserving original UI/UX, per-service selections, tokens, ports, etc.
# Smoke-test ready for Script 2 deployment

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

# ===== Step 1: Base domain and admin info =====
echo -e "\n${BLUE}Step 1: Base domain and admin information${RESET}"
read -rp "Enter the base domain/subdomain (e.g., ai.example.com): " BASE_DOMAIN
read -rp "Enter admin email: " ADMIN_EMAIL

# ===== Step 2: Proxy selection =====
echo -e "\n${BLUE}Step 2: Proxy selection${RESET}"
read -rp "Select proxy (1=Caddy with Let's Encrypt, 2=None): " PROXY_OPTION
USE_CADDY="false"
case "$PROXY_OPTION" in
    1) USE_CADDY="true";;
    2) USE_CADDY="false";;
    *) warn "Invalid choice, defaulting to None"; USE_CADDY="false";;
esac

# ===== Step 3: Service Selection =====
echo -e "\n${BLUE}Step 3: Select services to deploy${RESET}"
declare -A ENABLE_SERVICES
SERVICES=("OLLAMA" "LITELLM" "OPENWEBUI" "DIFY" "N8N" "POSTGRES" "REDIS" "HUGGINGFACE" "GRADIO" "FASTAPI" "CUSTOM_APP")
ALL_OPTION=""
read -rp "Enable all services? (y/N): " ALL_OPTION
for svc in "${SERVICES[@]}"; do
    if [[ "${ALL_OPTION,,}" == "y" ]]; then
        ENABLE_SERVICES[$svc]="y"
    else
        read -rp "Enable $svc? (y/N): " resp
        ENABLE_SERVICES[$svc]=${resp,,}
    fi
done

# ===== Step 4: Ports & service configuration =====
echo -e "\n${BLUE}Step 4: Configure service ports and tokens${RESET}"
declare -A SERVICE_PORTS
declare -A SERVICE_TOKENS

for svc in "${SERVICES[@]}"; do
    if [[ "${ENABLE_SERVICES[$svc]}" == "y" ]]; then
        read -rp "Enter port for $svc (default 8000): " port
        SERVICE_PORTS[$svc]=${port:-8000}

        # Token / API key prompts
        case "$svc" in
            OPENWEBUI|LITELLM|DIFY|OLLAMA)
                read -rp "Enter access token for $svc (or leave blank to auto-generate): " token
                if [[ -z "$token" ]]; then
                    token=$(openssl rand -base64 16)
                fi
                SERVICE_TOKENS[$svc]=$token
                ;;
            N8N)
                read -rp "Enter N8N basic auth user (default admin): " user
                read -rp "Enter N8N basic auth password (or leave blank to auto-generate): " pass
                SERVICE_TOKENS["N8N_USER"]=${user:-admin}
                SERVICE_TOKENS["N8N_PASS"]=${pass:-$(openssl rand -base64 16)}
                ;;
            SIGNAL)
                read -rp "Enter Signal API key: " token
                SERVICE_TOKENS[$svc]=$token
                ;;
            OPENCLAW)
                read -rp "Enter OpenClaw key: " token
                SERVICE_TOKENS[$svc]=$token
                ;;
            GOOGLE_DRIVE)
                read -rp "Enter Google Drive token: " token
                SERVICE_TOKENS[$svc]=$token
                ;;
            GEMINI|GROQ)
                read -rp "Enter $svc API key: " token
                SERVICE_TOKENS[$svc]=$token
                ;;
        esac
    fi
done

# ===== Step 5: LLM Provider Configuration =====
echo -e "\n${BLUE}Step 5: Configure LLM providers${RESET}"
declare -A LLM_PROVIDERS
LLM_LIST=("OPENAI" "ANTHROPIC" "COHERE" "GEMINI" "GROQ")
for provider in "${LLM_LIST[@]}"; do
    read -rp "Enable $provider? (y/N): " resp
    if [[ "${resp,,}" == "y" ]]; then
        read -rp "Enter API key for $provider: " key
        LLM_PROVIDERS[$provider]=$key
    fi
done

# ===== Step 6: Generate service credentials =====
echo -e "\n${BLUE}Step 6: Generating service credentials${RESET}"
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

# Add other service-specific credentials here as needed

# ===== Step 7: Save configuration =====
CONFIG_FILE="$CONFIG_DIR/platform_config.env"
info "Saving configuration to $CONFIG_FILE"

{
    echo "BASE_DOMAIN=$BASE_DOMAIN"
    echo "ADMIN_EMAIL=$ADMIN_EMAIL"
    echo "PRIMARY_IP=$PRIMARY_IP"
    echo "HARDWARE_TYPE=$HARDWARE_TYPE"
    echo "USE_CADDY=$USE_CADDY"

    for svc in "${SERVICES[@]}"; do
        echo "ENABLE_${svc}=${ENABLE_SERVICES[$svc]}"
        [[ -n "${SERVICE_PORTS[$svc]:-}" ]] && echo "PORT_${svc}=${SERVICE_PORTS[$svc]}"
    done

    for key in "${!SERVICE_TOKENS[@]}"; do
        echo "$key=${SERVICE_TOKENS[$key]}"
    done

    for key in "${!LLM_PROVIDERS[@]}"; do
        echo "LLM_${key}=${LLM_PROVIDERS[$key]}"
    done

    for key in "${!CREDENTIALS[@]}"; do
        echo "$key=${CREDENTIALS[$key]}"
    done
} > "$CONFIG_FILE"

info "Configuration saved successfully."

# ===== Step 8: Summary =====
echo -e "\n${GREEN}Configuration Summary:${RESET}"
echo "Base domain: $BASE_DOMAIN"
echo "Admin email: $ADMIN_EMAIL"
echo "Primary IP: $PRIMARY_IP"
echo "Hardware type: $HARDWARE_TYPE"
echo "Caddy/Let's Encrypt proxy: $USE_CADDY"
echo "Enabled services:"
for svc in "${SERVICES[@]}"; do
    [[ "${ENABLE_SERVICES[$svc],,}" == "y" ]] && echo "  - $svc (port: ${SERVICE_PORTS[$svc]:-N/A})"
done
echo "Configured LLM providers:"
for provider in "${!LLM_PROVIDERS[@]}"; do
    echo "  - $provider"
done

info "Script 1 completed. You can now proceed to Script 2 to deploy services."

exit 0

