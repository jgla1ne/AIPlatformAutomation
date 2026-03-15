#!/usr/bin/env bash
# =============================================================================
# Script 1: Run-once system setup and configuration collector
# After this runs, use script 2 to deploy and script 3 to manage.
# =============================================================================
set -euo pipefail

# Source mission control library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/3-configure-services.sh"   # ← SOURCES LIBRARY

# ── Colors and Logging ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log_info()    { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error()   { echo -e "${RED}✗${NC} $1"; }

# ── System Installation Functions (run once) ────────────────────────────────
install_system_packages() {
    log_info "Installing system packages..."
    apt-get update
    apt-get install -y curl wget git htop docker.io docker-compose
    systemctl enable docker
    systemctl start docker
    log_success "System packages installed"
}

configure_security() {
    log_info "Configuring security settings..."
    # Add user to docker group if not already
    if ! groups "$SUDO_USER" | grep -q docker; then
        usermod -aG docker "$SUDO_USER"
        log_info "Added $SUDO_USER to docker group"
    fi
    log_success "Security configured"
}

# ── Interactive Collection Functions ─────────────────────────────────────────
collect_domain_config() {
    echo ""
    echo -e "${BOLD}🌐 Domain Configuration${NC}"
    echo "===================="
    
    # Tenant name
    local default_tenant="datasquiz"
    read -p "Tenant name [$default_tenant]: " TENANT_NAME
    TENANT_NAME="${TENANT_NAME:-$default_tenant}"
    
    # Domain
    local default_domain="ai.${TENANT_NAME}.local"
    read -p "Base domain [$default_domain]: " BASE_DOMAIN
    BASE_DOMAIN="${BASE_DOMAIN:-$default_domain}"
    
    # Admin email
    local default_email="admin@${BASE_DOMAIN}"
    read -p "Admin email [$default_email]: " ADMIN_EMAIL
    ADMIN_EMAIL="${ADMIN_EMAIL:-$default_email}"
    
    # SSL configuration
    echo ""
    echo "SSL Configuration:"
    echo "  1) Let's Encrypt (requires public domain)"
    echo "  2) Self-signed (for local development)"
    read -p "Choose [2]: " ssl_choice
    case "${ssl_choice:-2}" in
        1) USE_LETSENCRYPT=true ;;
        *) USE_LETSENCRYPT=false ;;
    esac
    
    log_success "Domain configuration collected"
}

select_services() {
    echo ""
    echo -e "${BOLD}🚀 Service Selection${NC}"
    echo "==================="
    
    # Core AI services
    echo "Core AI Services:"
    read -p "Enable LiteLLM (AI model router) [Y/n]: " choice
    ENABLE_LITELLM="${choice,,}" || ENABLE_LITELLM=true
    [[ "$ENABLE_LITELLM" == "n" ]] && ENABLE_LITELLM=false
    
    read -p "Enable Ollama (local LLM runtime) [Y/n]: " choice
    ENABLE_OLLAMA="${choice,,}" || ENABLE_OLLAMA=true
    [[ "$ENABLE_OLLAMA" == "n" ]] && ENABLE_OLLAMA=false
    
    # Web applications
    echo ""
    echo "Web Applications (all use LiteLLM):"
    read -p "Enable OpenWebUI (chat interface) [Y/n]: " choice
    ENABLE_OPENWEBUI="${choice,,}" || ENABLE_OPENWEBUI=true
    [[ "$ENABLE_OPENWEBUI" == "n" ]] && ENABLE_OPENWEBUI=false
    
    read -p "Enable n8n (workflow automation) [y/N]: " choice
    ENABLE_N8N="${choice,,}" || ENABLE_N8N=false
    [[ "$ENABLE_N8N" == "y" ]] && ENABLE_N8N=true
    
    read -p "Enable Flowise (AI workflow builder) [y/N]: " choice
    ENABLE_FLOWISE="${choice,,}" || ENABLE_FLOWISE=false
    [[ "$ENABLE_FLOWISE" == "y" ]] && ENABLE_FLOWISE=true
    
    read -p "Enable AnythingLLM (document chat) [y/N]: " choice
    ENABLE_ANYTHINGLLM="${choice,,}" || ENABLE_ANYTHINGLLM=false
    [[ "$ENABLE_ANYTHINGLLM" == "y" ]] && ENABLE_ANYTHINGLLM=true
    
    # Infrastructure
    echo ""
    echo "Infrastructure:"
    read -p "Enable Qdrant (vector database) [Y/n]: " choice
    ENABLE_QDRANT="${choice,,}" || ENABLE_QDRANT=true
    [[ "$ENABLE_QDRANT" == "n" ]] && ENABLE_QDRANT=false
    
    read -p "Enable Monitoring (Prometheus + Grafana) [Y/n]: " choice
    ENABLE_MONITORING="${choice,,}" || ENABLE_MONITORING=true
    [[ "$ENABLE_MONITORING" == "n" ]] && ENABLE_MONITORING=false
    
    read -p "Enable Tailscale VPN [y/N]: " choice
    ENABLE_TAILSCALE="${choice,,}" || ENABLE_TAILSCALE=false
    [[ "$ENABLE_TAILSCALE" == "y" ]] && ENABLE_TAILSCALE=true
    
    log_success "Service selection completed"
}

collect_api_keys() {
    echo ""
    echo -e "${BOLD}🔑 API Keys${NC}"
    echo "============"
    echo "Enter API keys (leave empty to skip):"
    
    read -p "OpenAI API Key: " OPENAI_API_KEY
    read -p "Anthropic API Key: " ANTHROPIC_API_KEY
    read -p "Gemini API Key: " GEMINI_API_KEY
    read -p "Groq API Key: " GROQ_API_KEY
    read -p "OpenRouter API Key: " OPENROUTER_API_KEY
    
    # Ollama models
    if [[ "$ENABLE_OLLAMA" == "true" ]]; then
        read -p "Ollama models (comma-separated) [llama3.1]: " OLLAMA_MODELS
        OLLAMA_MODELS="${OLLAMA_MODELS:-llama3.1}"
    fi
    
    # Tailscale auth key
    if [[ "$ENABLE_TAILSCALE" == "true" ]]; then
        read -p "Tailscale Auth Key: " TAILSCALE_AUTH_KEY
    fi
    
    # Google Drive (optional)
    echo ""
    echo "Google Drive Integration (optional):"
    read -p "GDrive Client ID: " GDRIVE_CLIENT_ID
    read -p "GDrive Client Secret: " GDRIVE_CLIENT_SECRET
    read -p "GDrive Refresh Token: " GDRIVE_REFRESH_TOKEN
    
    log_success "API keys collected"
}

collect_routing_config() {
    echo ""
    echo -e "${BOLD}🔀 LiteLLM Routing Strategy${NC}"
    echo "=========================="
    echo "  1) least-busy     (default — spread load)"
    echo "  2) latency-based  (fastest model wins)"
    echo "  3) cost-based     (cheapest model wins)"
    read -p "Choose [1]: " route_choice
    case "${route_choice:-1}" in
        2) LITELLM_ROUTING_STRATEGY="latency-based-routing" ;;
        3) LITELLM_ROUTING_STRATEGY="cost-based-routing" ;;
        *) LITELLM_ROUTING_STRATEGY="least-busy" ;;
    esac
    
    echo ""
    echo -e "${BOLD}🗃️  Vector Database${NC}"
    echo "==================="
    echo "  1) Qdrant     (default — lightweight, fast)"
    echo "  2) Weaviate   (GraphQL API, hybrid search)"
    read -p "Choose [1]: " vdb_choice
    case "${vdb_choice:-1}" in
        2) 
            VECTOR_DB_TYPE="weaviate"
            ENABLE_WEAVIATE=true
            ENABLE_QDRANT=false
            ;;
        *) 
            VECTOR_DB_TYPE="qdrant"
            ENABLE_QDRANT=true
            ;;
    esac
    
    log_success "Routing configuration completed"
}

generate_secrets() {
    log_info "Generating secure secrets..."
    
    # Database password
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    # Admin password
    ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
    
    # JWT secret
    JWT_SECRET=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)
    
    # Encryption key
    ENCRYPTION_KEY=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)
    
    # Redis password
    REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    log_success "Secrets generated"
}

# ── Main Orchestration ───────────────────────────────────────────────────────
main() {
    echo -e "${BOLD}🚀 AI Platform Setup Wizard${NC}"
    echo "=========================="
    echo ""
    echo "This wizard will configure your AI platform deployment."
    echo "All data will be stored in /mnt/data/${TENANT_NAME:-datasquiz}"
    echo ""
    
    # Check if running as root
    [[ $EUID -eq 0 ]] || { log_error "Please run with sudo"; exit 1; }
    
    # System setup
    install_system_packages
    configure_security
    
    # Interactive collection
    collect_domain_config
    select_services
    collect_api_keys
    collect_routing_config
    generate_secrets
    
    # Get user info for ownership
    REAL_UID=$(id -u "$SUDO_USER")
    REAL_GID=$(id -g "$SUDO_USER")
    
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
    echo "Next steps:"
    echo "1. Run: sudo bash scripts/2-deploy-services.sh"
    echo "2. Monitor deployment with: sudo bash scripts/3-configure-services.sh health"
    echo ""
    echo "Configuration files created in: /mnt/data/${TENANT_NAME}/configs"
    echo "Environment file: /mnt/data/${TENANT_NAME}/.env"
    echo ""
    log_warning "Do not re-run script 1 unless rebuilding from scratch."
}

# Only run main if executed directly (not when sourced)
(return 0 2>/dev/null) || main "$@"
