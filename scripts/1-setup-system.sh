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

    # Get tenant name
    local default_tenant="datasquiz"
    echo -ne "  📝 Tenant name [${default_tenant}]: "
    read -r TENANT_NAME
    TENANT_NAME="${TENANT_NAME:-$default_tenant}"
    log "INFO" "Tenant name: ${TENANT_NAME}"

    # Get domain
    local default_domain="ai.${TENANT_NAME}.local"
    echo -ne "  🌐 Base domain [${default_domain}]: "
    read -r BASE_DOMAIN
    BASE_DOMAIN="${BASE_DOMAIN:-$default_domain}"
    log "INFO" "Base domain: ${BASE_DOMAIN}"

    # Get admin email
    local default_email="admin@${BASE_DOMAIN}"
    echo -ne "  📧 Admin email [${default_email}]: "
    read -r ADMIN_EMAIL
    ADMIN_EMAIL="${ADMIN_EMAIL:-$default_email}"
    log "INFO" "Admin email: ${ADMIN_EMAIL}"

    # SSL configuration
    echo ""
    echo -e "  🔒 SSL Configuration:"
    echo -e "     1) Let's Encrypt (requires public domain & DNS)"
    echo -e "     2) Self-signed (for local development)"
    echo -ne "  Choose [2]: "
    read -r ssl_choice
    case "${ssl_choice:-2}" in
        1) 
            USE_LETSENCRYPT=true
            # Check DNS resolution
            if ! check_dns "${BASE_DOMAIN}"; then
                echo ""
                echo -e "  ${YELLOW}⚠️  DNS WARNING${NC}"
                echo -e "  ${DIM}Let's Encrypt will fail without proper DNS.${NC}"
                echo -e "  ${DIM}Consider using self-signed for testing.${NC}"
                echo -ne "  Continue with Let's Encrypt anyway? [y/N]: "
                read -r continue_choice
                if [[ "${continue_choice,,}" != "y" ]]; then
                    USE_LETSENCRYPT=false
                    log "INFO" "Switched to self-signed certificates"
                fi
            fi
            ;;
        *) 
            USE_LETSENCRYPT=false 
            log "INFO" "Using self-signed certificates"
            ;;
    esac

    ok "Identity configuration completed"
}

# ─── Data Volume Selection ───────────────────────────────────────────────────
select_data_volume() {
    print_step "4" "11" "Data Volume Selection"

    echo -e "  ${BOLD}💾  Available Mount Points${NC}"
    echo -e "  ${DIM}Select where to store AI platform data${NC}"
    echo ""

    # Use /mnt/data as the standard location
    DATA_ROOT="/mnt/data"
    ENV_FILE="${DATA_ROOT}/${TENANT_NAME}/.env"
    
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

# ─── Service Stack Selection ────────────────────────────────────────────────────
select_stack() {
    print_step "6" "11" "Service Stack Selection"

    echo -e "  ${BOLD}📦  Choose a service stack${NC}"
    echo -e "  ${DIM}Stacks are pre-configured bundles — you can customise in the next step${NC}"
    echo ""

    # Core AI services
    echo -e "  ${BOLD}🤖  Core AI Services${NC}"
    echo -ne "  Enable LiteLLM (AI model router) [Y/n]: "
    read -r choice
    ENABLE_LITELLM=true
    [[ "${choice,,}" == "n" ]] && ENABLE_LITELLM=false

    echo -ne "  Enable Ollama (local LLM runtime) [Y/n]: "
    read -r choice
    ENABLE_OLLAMA=true
    [[ "${choice,,}" == "n" ]] && ENABLE_OLLAMA=false

    echo -ne "  Enable Qdrant (vector database) [Y/n]: "
    read -r choice
    ENABLE_QDRANT=true
    [[ "${choice,,}" == "n" ]] && ENABLE_QDRANT=false

    # Web applications
    echo ""
    echo -e "  ${BOLD}🌐  Web Applications${NC}"
    echo -ne "  Enable OpenWebUI (chat interface) [Y/n]: "
    read -r choice
    ENABLE_OPENWEBUI=true
    [[ "${choice,,}" == "n" ]] && ENABLE_OPENWEBUI=false

    echo -ne "  Enable n8n (workflow automation) [y/N]: "
    read -r choice
    ENABLE_N8N=false
    [[ "${choice,,}" == "y" ]] && ENABLE_N8N=true

    echo -ne "  Enable Flowise (AI workflow builder) [y/N]: "
    read -r choice
    ENABLE_FLOWISE=false
    [[ "${choice,,}" == "y" ]] && ENABLE_FLOWISE=true

    echo -ne "  Enable AnythingLLM (document chat) [y/N]: "
    read -r choice
    ENABLE_ANYTHINGLLM=false
    [[ "${choice,,}" == "y" ]] && ENABLE_ANYTHINGLLM=true

    # Infrastructure
    echo ""
    echo -e "  ${BOLD}🔧  Infrastructure${NC}"
    echo -ne "  Enable Monitoring (Prometheus + Grafana) [Y/n]: "
    read -r choice
    ENABLE_MONITORING=true
    [[ "${choice,,}" == "n" ]] && ENABLE_MONITORING=false

    echo -ne "  Enable Tailscale VPN [y/N]: "
    read -r choice
    ENABLE_TAILSCALE=false
    [[ "${choice,,}" == "y" ]] && ENABLE_TAILSCALE=true

    # Log selections
    log "INFO" "LiteLLM: ${ENABLE_LITELLM}"
    log "INFO" "Ollama: ${ENABLE_OLLAMA}"
    log "INFO" "Qdrant: ${ENABLE_QDRANT}"
    log "INFO" "OpenWebUI: ${ENABLE_OPENWEBUI}"
    log "INFO" "n8n: ${ENABLE_N8N}"
    log "INFO" "Flowise: ${ENABLE_FLOWISE}"
    log "INFO" "AnythingLLM: ${ENABLE_ANYTHINGLLM}"
    log "INFO" "Monitoring: ${ENABLE_MONITORING}"
    log "INFO" "Tailscale: ${ENABLE_TAILSCALE}"
    
    ok "Service stack selection completed"
}

# ─── LLM Configuration ───────────────────────────────────────────────────────
collect_llm_config() {
    print_step "8" "11" "LLM Provider Configuration"

    echo -e "  ${BOLD}🔑  LLM Provider API Keys${NC}"
    echo -e "  ${DIM}Enter API keys for providers you want to use (leave blank to skip)${NC}"
    echo ""

    # OpenAI
    echo -ne "  🤖 OpenAI API Key: "
    read -s OPENAI_API_KEY
    echo ""

    # Anthropic
    echo -ne "  🧠 Anthropic API Key: "
    read -s ANTHROPIC_API_KEY
    echo ""

    # Gemini
    echo -ne "  🌟 Gemini API Key: "
    read -s GEMINI_API_KEY
    echo ""

    # Groq
    echo -ne "  ⚡ Groq API Key: "
    read -s GROQ_API_KEY
    echo ""

    # OpenRouter
    echo -ne "  🔗 OpenRouter API Key: "
    read -s OPENROUTER_API_KEY
    echo ""

    # Ollama models (if enabled)
    if [[ "$ENABLE_OLLAMA" == "true" ]]; then
        echo ""
        echo -ne "  🦙 Ollama models (comma-separated) [llama3.1]: "
        read -r OLLAMA_MODELS
        OLLAMA_MODELS="${OLLAMA_MODELS:-llama3.1}"
        log "INFO" "Ollama models: ${OLLAMA_MODELS}"
    fi

    # Tailscale (if enabled)
    if [[ "$ENABLE_TAILSCALE" == "true" ]]; then
        echo ""
        echo -ne "  🔐 Tailscale Auth Key: "
        read -s TAILSCALE_AUTH_KEY
        echo ""
    fi

    # Google Drive (optional)
    echo ""
    echo -e "  ${BOLD}☁️  Google Drive Integration (Optional)${NC}"
    echo -ne "  GDrive Client ID: "
    read -r GDRIVE_CLIENT_ID
    echo -ne "  GDrive Client Secret: "
    read -s GDRIVE_CLIENT_SECRET
    echo ""
    echo -ne "  GDrive Refresh Token: "
    read -s GDRIVE_REFRESH_TOKEN
    echo ""

    ok "LLM configuration completed"
}

# ─── LiteLLM Routing Strategy Configuration ───────────────────────────────
collect_litellm_routing() {
    print_step "8.5" "11" "LiteLLM Routing Strategy"
    
    echo -e "  ${BOLD}🧠  LiteLLM Routing Strategy${NC}"
    echo -e "  ${DIM}Configure intelligent model routing for cost/latency optimization${NC}"
    echo ""

    echo -e "  🚦 Available routing strategies:"
    echo -e "     1) least-busy     (default — spread load across models)"
    echo -e "     2) latency-based (fastest model wins)"
    echo -e "     3) cost-based     (cheapest model wins)"
    echo -ne "  Choose [1]: "
    read -r route_choice
    
    case "${route_choice:-1}" in
        2) 
            LITELLM_ROUTING_STRATEGY="latency-based-routing"
            log "INFO" "Routing strategy: latency-based"
            ;;
        3) 
            LITELLM_ROUTING_STRATEGY="cost-based-routing"
            log "INFO" "Routing strategy: cost-based"
            ;;
        *) 
            LITELLM_ROUTING_STRATEGY="least-busy"
            log "INFO" "Routing strategy: least-busy"
            ;;
    esac

    echo ""
    echo -e "  🎯 Model fallbacks will be configured automatically"
    echo -e "  ${DIM}Example: gpt-4o → gpt-4o-mini → claude-3-5-sonnet${NC}"

    ok "LiteLLM routing strategy configured"
}

# ─── Vector DB Selection ───────────────────────────────────────────────────────
select_vector_db() {
    print_step "7" "11" "Vector Database Selection"

    echo -e "  ${BOLD}🗄️  Choose Vector Database${NC}"
    echo ""

    echo -e "  🎯 Available vector databases:"
    echo -e "     1) Qdrant     (default — lightweight, fast)"
    echo -e "     2) Weaviate   (GraphQL API, hybrid search)"
    echo -ne "  Choose [1]: "
    read -r vdb_choice
    
    case "${vdb_choice:-1}" in
        2) 
            VECTOR_DB_TYPE="weaviate"
            ENABLE_WEAVIATE=true
            ENABLE_QDRANT=false
            log "INFO" "Vector database: Weaviate"
            ;;
        *) 
            VECTOR_DB_TYPE="qdrant"
            ENABLE_QDRANT=true
            log "INFO" "Vector database: Qdrant"
            ;;
    esac

    echo ""
    echo -e "  📊 Vector database: ${VECTOR_DB_TYPE}"
    echo -e "  ${DIM}This will be used by all AI services for embeddings${NC}"

    ok "Vector database selection completed"
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
    echo "All data will be stored in ${DATA_ROOT:-/mnt/data}/${TENANT_NAME:-datasquiz}"
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
    select_vector_db
    collect_llm_config
    collect_litellm_routing
    generate_secrets

    # Export all variables for script 3 functions
    export TENANT_NAME BASE_DOMAIN ADMIN_EMAIL USE_LETSENCRYPT
    export ENABLE_LITELLM ENABLE_OLLAMA ENABLE_OPENWEBUI ENABLE_N8N ENABLE_FLOWISE ENABLE_ANYTHINGLLM
    export ENABLE_QDRANT ENABLE_MONITORING ENABLE_TAILSCALE
    export OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY GROQ_API_KEY OPENROUTER_API_KEY
    export OLLAMA_MODELS TAILSCALE_AUTH_KEY GDRIVE_CLIENT_ID GDRIVE_CLIENT_SECRET GDRIVE_REFRESH_TOKEN
    export LITELLM_ROUTING_STRATEGY VECTOR_DB_TYPE
    export DB_PASSWORD ADMIN_PASSWORD JWT_SECRET ENCRYPTION_KEY REDIS_PASSWORD
    export REAL_UID REAL_GID

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
    echo "📁 Configuration files created in: ${DATA_ROOT}/${TENANT_NAME}/configs"
    echo "🔧 Environment file: ${ENV_FILE}"
    echo ""
    echo -e "${YELLOW}⚠️  Do not re-run script 1 unless rebuilding from scratch.${NC}"
}

# Only run main if executed directly (not when sourced)
(return 0 2>/dev/null) || main "$@"
