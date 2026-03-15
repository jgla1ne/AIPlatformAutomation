#!/usr/bin/env bash
# =============================================================================
# Script 1: Tenant Setup - Complete System Configuration Wizard
# =============================================================================
# PURPOSE: Interactive setup wizard for AI Platform
# USAGE:   sudo bash scripts/1-setup-system.sh
# =============================================================================

set -euo pipefail

# Source mission control library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/3-configure-services.sh"   # ← SOURCES LIBRARY

# ─── Colours ─────────────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─── Utility Functions ────────────────────────────────────────────────────────
fail() {
    log "ERROR" "$1"
    exit 1
}

ok() {
    log "SUCCESS" "$1"
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}"
}

print_step() {
    local step="${1}" total="${2}" title="${3}"
    echo ""
    echo -e "${CYAN}  ┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │ Step ${step}/${total}: ${title}                              │${NC}"
    echo -e "${CYAN}  └─────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

print_divider() {
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
}

# ─── Phase 0: System Resource Validation ────────────────────────────────────────
validate_system_resources() {
    print_step "0" "14" "System Resource Validation"
    
    log "INFO" "Validating system resources for AI platform deployment..."
    
    # Check available RAM
    local available_ram_gb
    available_ram_gb=$(awk '/MemAvailable/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
    log "INFO" "Available RAM: ${available_ram_gb}GB"
    
    # Check available disk space
    local available_disk_gb
    available_disk_gb=$(df -BG "/mnt" 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo "0")
    log "INFO" "Available disk space: ${available_disk_gb}GB"
    
    # Validate minimum requirements
    local min_ram_gb=4
    local min_disk_gb=20
    
    if [[ $available_ram_gb -lt $min_ram_gb ]]; then
        log "WARN" "Low RAM detected: ${available_ram_gb}GB < ${min_ram_gb}GB minimum"
        log "WARN" "AI services may be unstable. Consider adding more RAM."
    fi
    
    if [[ $available_disk_gb -lt $min_disk_gb ]]; then
        log "ERROR" "Insufficient disk space: ${available_disk_gb}GB < ${min_disk_gb}GB minimum"
        fail "Deployment requires at least ${min_disk_gb}GB of available disk space"
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        fail "Docker daemon is not running. Start Docker service first."
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        fail "Docker Compose is not available. Install Docker Compose first."
    fi
    
    # Check network connectivity
    if ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        log "WARN" "Network connectivity issues detected"
        log "WARN" "DNS resolution may fail during deployment"
    fi
    
    ok "System resources validated successfully"
}

# ─── Runtime vars (set after volume selection) ────────────────────────────────
DATA_ROOT=""
ENV_FILE=""
COMPOSE_DIR=""
CADDY_DIR=""
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Dynamic service URLs (will be set after tenant selection)
VECTOR_DB_URL=""
OLLAMA_INTERNAL_URL=""
LITELLM_INTERNAL_URL=""

# ─── DNS resolution check (used inside collect_identity) ─────────────────────
check_dns() {
    local domain="${1}"
    PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "unknown")
    
    log "INFO" "Checking DNS resolution for ${domain}..."
    
    # Check if domain resolves to this server's public IP
    local resolved_ip
    resolved_ip=$(nslookup "${domain}" 8.8.8.8 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}' || echo "")
    
    if [[ "${resolved_ip}" == "${PUBLIC_IP}" ]]; then
        log "SUCCESS" "DNS resolves correctly: ${domain} → ${resolved_ip}"
        return 0
    elif [[ -n "${resolved_ip}" && "${resolved_ip}" != "unknown" ]]; then
        log "WARN" "DNS resolves to different IP: ${domain} → ${resolved_ip} (this server: ${PUBLIC_IP})"
        log "WARN" "TLS certificates will fail. Update DNS to point to ${PUBLIC_IP}"
        return 1
    else
        log "WARN" "DNS resolution failed for ${domain}"
        log "WARN" "Using self-signed certificates"
        return 1
    fi
}

# ─── Collect Identity (Domain, Tenant, Email) ───────────────────────────────────
collect_identity() {
    print_step "2" "11" "Domain & Identity"

    echo -e "  ${BOLD}🌐  Domain Setup${NC}"
    echo -e "  ${DIM}DNS must already point to this server for automatic TLS to work${NC}"
    echo ""

    while true; do
        read -p "  ➤ Domain name (e.g. ai.example.com): " DOMAIN
        DOMAIN="${DOMAIN,,}"
        if [[ "${DOMAIN}" =~ ^[a-z0-9][a-z0-9.\-]{2,253}[a-z0-9]$ ]]; then
            break
        fi
        echo "  ❌ Invalid domain format — try again"
    done

    check_dns "${DOMAIN}"

    print_divider

    echo -e "  ${BOLD}🏷️   Tenant Identifier${NC}"
    echo -e "  ${DIM}Short ID used for naming, namespacing and branding${NC}"
    echo ""

    while true; do
        read -p "  ➤ Tenant ID (e.g. mycompany): " TENANT_ID
        TENANT_ID="${TENANT_ID,,}"
        if [[ "${TENANT_ID}" =~ ^[a-z][a-z0-9\-]{2,29}$ ]]; then
            # Define TENANT_DIR right after TENANT_ID is set
            TENANT_DIR="/mnt/data/${TENANT_ID}"
            # Define TENANT_DIR right after TENANT_ID is set
            TENANT_DIR="/mnt/data/${TENANT_ID}"
            break
        fi
        echo "  ❌ Must start with a letter, 3–30 chars, lowercase/numbers/hyphens only"
    done

    print_divider

    echo -e "  ${BOLD}🔧  Project Prefix${NC}"
    echo -e "  ${DIM}Prefix for Docker resources (compose project, containers, volumes)${NC}"
    echo ""

    while true; do
        read -p "  ➤ Project prefix [aip-]: " PROJECT_PREFIX
        PROJECT_PREFIX="${PROJECT_PREFIX:-aip-}"
        PROJECT_PREFIX="${PROJECT_PREFIX,,}"
        if [[ "${PROJECT_PREFIX}" =~ ^[a-z][a-z0-9\-]*-$ ]]; then
            break
        fi
        echo "  ❌ Must end with hyphen, lowercase/numbers/hyphens only"
    done

    print_divider

    echo -e "  ${BOLD}🔧 Hardware Acceleration${NC}"
    echo ""
    read -p "  ➤ Enable NVIDIA GPU support? (Requires nvidia-container-toolkit) [y/N]: " answer
    if [[ "${answer,,}" == "y" ]]; then
        declare -g ENABLE_GPU="true"
    else
        declare -g ENABLE_GPU="false"
    fi
    echo ""

    echo -e "  ${BOLD}📧 Admin Email${NC}"
    echo ""

    while true; do
        read -p "  ➤ Admin email address: " ADMIN_EMAIL
        if [[ "${ADMIN_EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
            break
        fi
        echo "  ❌ Invalid email format — try again"
    done

    ok "Identity configuration completed"
}

# ─── Service Stack Selection ────────────────────────────────────────────
select_stack() {
    print_step "6" "11" "Service Stack Selection"

    echo -e "  ${BOLD}📦  Choose a service stack${NC}"
    echo -e "  ${DIM}Stacks are pre-configured bundles — you can customise in the next step${NC}"
    echo ""
    echo -e "  ${CYAN}  1)${NC}  🟢  ${BOLD}Minimal${NC}       — Ollama + Open WebUI only"
    echo -e "             ${DIM}Ideal for local LLM inference, low resource usage${NC}"
    echo ""
    echo -e "  ${CYAN}  2)${NC}  🔵  ${BOLD}Standard${NC}      — Minimal + n8n + Flowise + Qdrant + LiteLLM"
    echo -e "             ${DIM}Full AI automation stack, recommended starting point${NC}"
    echo ""
    echo -e "  ${CYAN}  3)${NC}  🟣  ${BOLD}Full${NC}          — All services including AI, automation, monitoring, and security"
    echo -e "             ${DIM}Production-grade with complete feature set${NC}"
    echo ""
    echo -e "  ${CYAN}  4)${NC}  ⚙️   ${BOLD}Custom${NC}        — Pick services individually"
    echo -e "             ${DIM}Full control over what gets deployed${NC}"
    echo ""

    while true; do
        read -p "  ➤ Select stack [1-4]: " stack_choice
        stack_choice="${stack_choice:-2}"
        case "${stack_choice}" in
            1|2|3|4) break ;;
            *) echo "  ❌ Enter 1, 2, 3 or 4" ;;
        esac
    done

    # ── Apply stack presets ───────────────────────────────────────────────────
    # First, zero everything out
    ENABLE_POSTGRES=false; ENABLE_REDIS=false; ENABLE_OLLAMA=false; ENABLE_OPENWEBUI=false;
    ENABLE_ANYTHINGLLM=false; ENABLE_DIFY=false; ENABLE_N8N=false; ENABLE_FLOWISE=false;
    ENABLE_LITELLM=false; ENABLE_QDRANT=false; ENABLE_GRAFANA=false; ENABLE_PROMETHEUS=false;
    ENABLE_AUTHENTIK=false; ENABLE_SIGNAL=false; ENABLE_OPENCLAW=false; ENABLE_TAILSCALE=false;
    ENABLE_RCLONE=false; ENABLE_CADDY=true # Caddy is always on

    case "${stack_choice}" in
        1) # Lite Stack
            log "INFO" "Applying 'Lite' preset: OpenWebUI, Ollama, Qdrant, LiteLLM"
            ENABLE_POSTGRES=true; ENABLE_REDIS=true; ENABLE_OLLAMA=true;
            ENABLE_OPENWEBUI=true; ENABLE_QDRANT=true; ENABLE_LITELLM=true;
            STACK_NAME="lite"
            ;;
        2) # Local LLM Developer Stack
            log "INFO" "Applying 'Local LLM Developer' preset: All local AI tools"
            ENABLE_POSTGRES=true; ENABLE_REDIS=true; ENABLE_OLLAMA=true;
            ENABLE_OPENWEBUI=true; ENABLE_ANYTHINGLLM=true; ENABLE_DIFY=true;
            ENABLE_N8N=true; ENABLE_FLOWISE=true; ENABLE_LITELLM=true;
            ENABLE_QDRANT=true;
            STACK_NAME="local-llm-dev"
            ;;
        3) # Full Stack (All Services)
            log "WARN" "Applying 'Full Stack' preset. This requires significant system resources."
            ENABLE_POSTGRES=true; ENABLE_REDIS=true; ENABLE_OLLAMA=true;
            ENABLE_OPENWEBUI=true; ENABLE_ANYTHINGLLM=true; ENABLE_DIFY=true;
            ENABLE_N8N=true; ENABLE_FLOWISE=true; ENABLE_LITELLM=true;
            ENABLE_QDRANT=true; ENABLE_GRAFANA=true; ENABLE_PROMETHEUS=true;
            ENABLE_AUTHENTIK=true; ENABLE_SIGNAL=true; ENABLE_OPENCLAW=true;
            ENABLE_TAILSCALE=true; ENABLE_RCLONE=true;
            ENABLE_CADDY=true; # Always include Caddy
            STACK_NAME="full"
            ;;
        4) # Custom — all off, user picks in next step
            STACK_NAME="custom"
            log "INFO" "Stack: Custom — configure individually below"
            ;;
    esac

    print_divider

    # ── Always offer fine-grained override ────────────────────────────────────
    if [[ "${stack_choice}" != "4" ]]; then
        echo -e "  ${DIM}Stack applied. Would you like to customise individual services?${NC}"
        echo ""

        read -p "  ➤ Customise service selection? [y/N]: " customise
        customise="${customise:-n}"
        [[ "${customise,,}" =~ ^y ]] && stack_choice=4
    fi

    if [[ "${stack_choice}" = "4" ]]; then
        echo ""
        echo -e "  ${BOLD}─── 🤖  AI / LLM ────────────────────────────────────────${NC}"
        ask_service "🦙" "Ollama"        "Local LLM engine"           "ENABLE_OLLAMA"        "$( [[ "${ENABLE_OLLAMA}" == "true" ]]        && echo y || echo n )"
        ask_service "🌐" "Open WebUI"    "Chat UI for Ollama"         "ENABLE_OPENWEBUI"     "$( [[ "${ENABLE_OPENWEBUI}" == "true" ]]     && echo y || echo n )"
        ask_service "🤖" "AnythingLLM"   "AI assistant & RAG"         "ENABLE_ANYTHINGLLM"   "$( [[ "${ENABLE_ANYTHINGLLM}" == "true" ]]   && echo y || echo n )"
        ask_service "🏗️" "Dify"          "LLM app builder"            "ENABLE_DIFY"          "$( [[ "${ENABLE_DIFY}" == "true" ]]          && echo y || echo n )"
        ask_service "🔀" "LiteLLM"       "LLM proxy gateway"          "ENABLE_LITELLM"       "$( [[ "${ENABLE_LITELLM}" == "true" ]]       && echo y || echo n )"

        echo ""
        echo -e "  ${BOLD}─── ⚡  Automation ──────────────────────────────────────${NC}"
        ask_service "🔄" "n8n"           "Workflow automation"         "ENABLE_N8N"           "$( [[ "${ENABLE_N8N}" == "true" ]]           && echo y || echo n )"
        ask_service "🌊" "Flowise"       "AI flow builder"             "ENABLE_FLOWISE"       "$( [[ "${ENABLE_FLOWISE}" == "true" ]]       && echo y || echo n )"

        echo ""
        echo -e "  ${BOLD}─── 📊  Observability ───────────────────────────────────${NC}"
        ask_service "📈" "Grafana"       "Metrics dashboard"           "ENABLE_GRAFANA"       "$( [[ "${ENABLE_GRAFANA}" == "true" ]]       && echo y || echo n )"
        ask_service "🔭" "Prometheus"    "Metrics collection"          "ENABLE_PROMETHEUS"    "$( [[ "${ENABLE_PROMETHEUS}" == "true" ]]    && echo y || echo n )"

        echo ""
        echo -e "  ${BOLD}─── 🔐  Security ────────────────────────────────────────${NC}"
        # Continue with security options if needed...
    fi

    ok "Service stack selection completed"
}

# ─── Helper function for asking about services ───────────────────────────────────
ask_service() {
    local icon="$1" name="$2" description="$3" var_name="$4" current_value="$5"
    
    echo -ne "  ${icon}  ${BOLD}${name}${NC} ${DIM}(${description})${NC} "
    read -p "[${current_value}]: " choice
    choice="${choice:-${current_value}}"
    
    if [[ "${choice,,}" =~ ^y ]]; then
        declare -g "${var_name}=true"
    else
        declare -g "${var_name}=false"
    fi
}

# ─── Data Volume Selection ───────────────────────────────────────────────────
select_data_volume() {
    print_step "4" "11" "Data Volume Selection"

    echo -e "  ${BOLD}💾  Available Mount Points${NC}"
    echo -e "  ${DIM}Select where to store AI platform data${NC}"
    echo ""

    # Use /mnt/data as the standard location
    DATA_ROOT="/mnt/data"
    ENV_FILE="${DATA_ROOT}/${TENANT_ID}/.env"
    
    if [[ ! -d "/mnt" ]]; then
        log "ERROR" "/mnt directory not found. This is required for data storage."
        fail "Create /mnt directory and ensure it's properly mounted."
    fi

    # Check if we can write to /mnt
    if ! touch "/mnt/.test_write" 2>/dev/null; then
        log "ERROR" "Cannot write to /mnt directory. Check permissions and mount."
        fail "Fix /mnt permissions before continuing."
    else
        rm -f "/mnt/.test_write"
    fi

    log "INFO" "Data volume selected: ${DATA_ROOT}"
    log "INFO" "Environment file will be: ${ENV_FILE}"
    
    ok "Data volume configured"
}

# ─── Generate secrets (preserve on re-run) ───────────────────────────────────
generate_secrets() {
    print_step "11" "11" "Generating Secrets"

    load_existing_secret() {
        local key="${1}" default="${2}"
        if [[ -f "$ENV_FILE" ]]; then
            local existing_value
            existing_value=$(grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"')
            if [[ -n "$existing_value" ]]; then
                echo "$existing_value"
                return 0
            fi
        fi
        echo "$default"
    }

    log "INFO" "Generating secure secrets..."

    # Generate or load existing secrets
    DB_PASSWORD=$(load_existing_secret "DB_PASSWORD" "$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)")
    ADMIN_PASSWORD=$(load_existing_secret "ADMIN_PASSWORD" "$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)")
    JWT_SECRET=$(load_existing_secret "JWT_SECRET" "$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)")
    ENCRYPTION_KEY=$(load_existing_secret "ENCRYPTION_KEY" "$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)")
    REDIS_PASSWORD=$(load_existing_secret "REDIS_PASSWORD" "$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)")

    # Get user info for ownership
    REAL_UID=$(id -u "$SUDO_USER")
    REAL_GID=$(id -g "$SUDO_USER")

    ok "Secrets generated successfully"
}

# ─── Main orchestration ────────────────────────────────────────────────────────
main() {
    echo -e "${BOLD}🚀 AI Platform Setup Wizard${NC}"
    echo "=========================="
    echo ""
    echo "This wizard will guide you through configuring your AI platform deployment."
    echo "All data will be stored in ${DATA_ROOT:-/mnt/data}/${TENANT_ID:-datasquiz}"
    echo ""
    
    # Check if running as root
    [[ $EUID -eq 0 ]] || { 
        echo -e "${RED}ERROR: This script must be run as root (use sudo)${NC}"
        exit 1
    }

    # Execute all setup phases
    validate_system_resources
    collect_identity
    select_data_volume
    select_stack
    generate_secrets

    # Export variables for script 3 functions - map old names to new
    export TENANT_NAME="${TENANT_ID}"
    export BASE_DOMAIN="${DOMAIN}"
    export ADMIN_EMAIL="${ADMIN_EMAIL}"
    export USE_LETSENCRYPT="${USE_LETSENCRYPT:-false}"
    export ENABLE_LITELLM="${ENABLE_LITELLM:-false}"
    export ENABLE_OLLAMA="${ENABLE_OLLAMA:-false}"
    export ENABLE_OPENWEBUI="${ENABLE_OPENWEBUI:-false}"
    export ENABLE_N8N="${ENABLE_N8N:-false}"
    export ENABLE_FLOWISE="${ENABLE_FLOWISE:-false}"
    export ENABLE_ANYTHINGLLM="${ENABLE_ANYTHINGLLM:-false}"
    export ENABLE_QDRANT="${ENABLE_QDRANT:-false}"
    export ENABLE_MONITORING="${ENABLE_GRAFANA:-false}"
    export ENABLE_TAILSCALE="${ENABLE_TAILSCALE:-false}"
    export LITELLM_ROUTING_STRATEGY="${LITELLM_ROUTING_STRATEGY:-least-busy}"
    export VECTOR_DB_TYPE="${VECTOR_DB_TYPE:-qdrant}"
    export OLLAMA_MODELS="${OLLAMA_MODELS:-llama3.1}"
    export LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-12345}"
    export DB_PASSWORD="${DB_PASSWORD}"
    export ADMIN_PASSWORD="${ADMIN_PASSWORD}"
    export JWT_SECRET="${JWT_SECRET}"
    export ENCRYPTION_KEY="${ENCRYPTION_KEY}"
    export REDIS_PASSWORD="${REDIS_PASSWORD}"
    export REAL_UID="${REAL_UID}"
    export REAL_GID="${REAL_GID}"

    # All generation delegated to script 3 functions
    generate_env              # writes .env via script 3
    prepare_directories       # UID-aware directory creation
    generate_configs          # all config files via script 3

    echo ""
    echo -e "${GREEN}✅ Setup Complete!${NC}"
    echo ""
    echo "📋 Next steps:"
    echo "   1. Deploy services: sudo bash scripts/2-deploy-services.sh"
    echo "   2. Monitor health: sudo bash scripts/3-configure-services.sh health"
    echo ""
    echo "📁 Configuration files created in: ${DATA_ROOT}/${TENANT_ID}/configs"
    echo "🔧 Environment file: ${ENV_FILE}"
    echo ""
    echo -e "${YELLOW}⚠️  Do not re-run script 1 unless rebuilding from scratch.${NC}"
}

# Only run main if executed directly (not when sourced)
(return 0 2>/dev/null) || main "$@"
