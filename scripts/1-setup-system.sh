#!/usr/bin/env bash

################################################################################
# SCRIPT 1 v98.3.1 - AI PLATFORM SYSTEM INITIALIZATION
# FIXED: All syntax errors + full validation
################################################################################

set -uo pipefail

# ============================================================================
# CONSTANTS & CONFIGURATION
# ============================================================================

readonly SCRIPT_VERSION="98.3.1"
readonly SCRIPT_NAME="1-setup-system.sh"
readonly LOG_FILE="/var/log/ai-platform-setup-$(date +%Y%m%d_%H%M%S).log"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Paths - FIXED: No spaces in command substitution
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_PATH="$(dirname "$SCRIPT_DIR")"
readonly DATA_PATH="/mnt/data/ai-platform"
readonly SECRETS_PATH="${ROOT_PATH}/.secrets"
readonly CONFIG_PATH="${ROOT_PATH}/config"

# Progress tracking
TOTAL_STEPS=25
CURRENT_STEP=0

# Configuration variables
DOMAIN_NAME=""
SSL_EMAIL=""
VECTOR_DB=""
REVERSE_PROXY=""
CLOUD_PROVIDER=""
ENABLE_GDRIVE_SYNC="false"
ENABLE_SIGNAL="false"
ENABLE_MONITORING="false"
ENABLE_N8N="false"
TAILSCALE_AUTH_KEY=""

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}   ℹ${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}   ✓${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}   ⚠${NC} ${YELLOW}WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}   ✗${NC} ${RED}ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

log_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo "" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}[${CURRENT_STEP}/${TOTAL_STEPS}] $1${NC}" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

log_section() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}${BOLD}║  $1${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_ubuntu_version() {
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot detect OS version"
        exit 1
    fi
    
    source /etc/os-release
    
    if [ "$ID" != "ubuntu" ]; then
        log_error "This script requires Ubuntu (detected: $ID)"
        exit 1
    fi
    
    local version_number="${VERSION_ID//./}"
    if [ "$version_number" -lt 2004 ]; then
        log_error "Ubuntu 20.04 or higher required (detected: $VERSION_ID)"
        exit 1
    fi
    
    log_success "Ubuntu $VERSION_ID detected"
}

check_internet_connectivity() {
    log_info "Checking internet connectivity..."
    
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_error "No internet connectivity"
        exit 1
    fi
    
    if ! ping -c 1 -W 3 github.com >/dev/null 2>&1; then
        log_warning "Cannot reach github.com - DNS may have issues"
    fi
    
    log_success "Internet connectivity verified"
}

# ============================================================================
# APPARMOR SETUP (SYSTEMD APPROACH FROM SCRIPT 0)
# ============================================================================

setup_apparmor_properly() {
    log_step "CONFIGURING APPARMOR (SYSTEMD METHOD)"
    
    log_info "Installing AppArmor utilities..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        apparmor \
        apparmor-utils \
        apparmor-profiles \
        apparmor-profiles-extra >/dev/null 2>&1
    
    log_success "AppArmor packages installed"
    
    # Enable AppArmor service
    log_info "Enabling AppArmor service..."
    systemctl enable apparmor.service >/dev/null 2>&1
    systemctl start apparmor.service >/dev/null 2>&1
    
    if systemctl is-active --quiet apparmor.service; then
        log_success "AppArmor service is active"
    else
        log_warning "AppArmor service not active - will use permissive mode"
    fi
    
    # Check kernel support
    if [ -d /sys/module/apparmor ]; then
        log_success "AppArmor kernel module loaded"
    else
        log_warning "AppArmor kernel module not found - permissive mode only"
    fi
    
    # Set profiles to complain mode (non-blocking)
    if command -v aa-complain >/dev/null 2>&1; then
        log_info "Setting AppArmor to complain mode (non-blocking)..."
        aa-complain /etc/apparmor.d/* 2>/dev/null || true
        log_success "AppArmor configured in permissive mode"
    fi
}

# ============================================================================
# STORAGE TIER INITIALIZATION
# ============================================================================

initialize_storage_tier() {
    log_step "INITIALIZING STORAGE TIER"
    
    log_info "Creating directory structure..."
    
    # Main data directory
    mkdir -p "$DATA_PATH"
    
    # Core services
    mkdir -p "${DATA_PATH}/postgres/data"
    mkdir -p "${DATA_PATH}/redis/data"
    mkdir -p "${DATA_PATH}/litellm/config"
    mkdir -p "${DATA_PATH}/openclaw/config"
    mkdir -p "${DATA_PATH}/openclaw/data"
    mkdir -p "${DATA_PATH}/openwebui/data"
    mkdir -p "${DATA_PATH}/openwebui/config"
    
    # Vector databases
    mkdir -p "${DATA_PATH}/qdrant/data"
    mkdir -p "${DATA_PATH}/chroma/data"
    mkdir -p "${DATA_PATH}/weaviate/data"
    
    # Monitoring
    mkdir -p "${DATA_PATH}/prometheus/data"
    mkdir -p "${DATA_PATH}/prometheus/config"
    mkdir -p "${DATA_PATH}/grafana/data"
    mkdir -p "${DATA_PATH}/loki/data"
    mkdir -p "${DATA_PATH}/loki/config"
    
    # N8N
    mkdir -p "${DATA_PATH}/n8n"
    
    # Langfuse
    mkdir -p "${DATA_PATH}/langfuse"
    
    # Integrations
    mkdir -p "${DATA_PATH}/signal-cli/config"
    mkdir -p "${DATA_PATH}/signal-cli/data"
    mkdir -p "${DATA_PATH}/gdrive-sync/rclone"
    mkdir -p "${DATA_PATH}/gdrive-sync/data"
    
    # Logs and backups
    mkdir -p "${DATA_PATH}/logs"
    mkdir -p "${DATA_PATH}/backups"
    
    # Config directories
    mkdir -p "$CONFIG_PATH"
    mkdir -p "$SECRETS_PATH"
    
    # Set permissions
    chmod 755 "$DATA_PATH"
    chmod 700 "$SECRETS_PATH"
    
    log_success "Storage tier initialized at $DATA_PATH"
}

# ============================================================================
# PORT AVAILABILITY CHECK
# ============================================================================

check_port_availability() {
    log_step "CHECKING PORT AVAILABILITY"
    
    local ports=(
        "80:HTTP"
        "443:HTTPS"
        "5432:PostgreSQL"
        "6379:Redis"
        "6333:Qdrant"
        "8000:Chroma"
        "8080:Weaviate"
        "4000:LiteLLM"
        "8001:OpenClaw"
        "3002:OpenWebUI"
        "3001:Langfuse"
        "5678:N8N"
        "9090:Prometheus"
        "3000:Grafana"
        "3100:Loki"
    )
    
    local all_clear=true
    
    for port_info in "${ports[@]}"; do
        local port="${port_info%%:*}"
        local service="${port_info##*:}"
        
        if ss -tuln | grep -q ":${port} "; then
            log_warning "Port $port ($service) is already in use"
            all_clear=false
        else
            log_success "Port $port ($service) available"
        fi
    done
    
    if [ "$all_clear" = false ]; then
        echo ""
        read -p "Some ports are in use. Continue anyway? (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_error "Port conflict - aborting"
            exit 1
        fi
    fi
}

# ============================================================================
# DOMAIN VALIDATION (SUPPORTS SUBDOMAINS)
# ============================================================================

validate_domain() {
    log_step "VALIDATING DOMAIN"
    
    while true; do
        read -p "❯ Enter your domain name (e.g., ai.example.com): " DOMAIN_NAME
        
        # Validate domain format (allows subdomains)
        if [[ "$DOMAIN_NAME" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
            log_success "Domain: $DOMAIN_NAME"
            break
        else
            log_error "Invalid domain format"
            echo "   Examples: example.com, ai.example.com, platform.company.org"
        fi
    done
    
    # Check DNS resolution
    log_info "Checking DNS resolution..."
    local resolved_ip=$(dig +short "$DOMAIN_NAME" 2>/dev/null | head -n1)
    
    if [ -n "$resolved_ip" ]; then
        log_success "DNS resolves to: $resolved_ip"
    else
        log_warning "DNS does not resolve yet (configure after setup)"
    fi
    
    # Get SSL email
    while true; do
        read -p "❯ Enter email for SSL certificates: " SSL_EMAIL
        
        if [[ "$SSL_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log_success "SSL email: $SSL_EMAIL"
            break
        else
            log_error "Invalid email format"
        fi
    done
    
    # Save configuration
    cat > "${CONFIG_PATH}/domain.conf" <<EOF
DOMAIN_NAME="$DOMAIN_NAME"
SSL_EMAIL="$SSL_EMAIL"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    log_success "Domain configuration saved"
}

# ============================================================================
# DOCKER INSTALLATION (NON-ROOT SETUP)
# ============================================================================

install_docker() {
    log_step "INSTALLING DOCKER"
    
    if command -v docker >/dev/null 2>&1; then
        local docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
        log_success "Docker already installed (version $docker_version)"
    else
        log_info "Installing Docker..."
        
        # Install prerequisites
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            ca-certificates \
            curl \
            gnupg \
            lsb-release >/dev/null 2>&1
        
        # Add Docker GPG key
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
            gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
        
        # Add Docker repository
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin >/dev/null 2>&1
        
        log_success "Docker installed successfully"
    fi
    
    # Configure Docker for non-root use
    log_info "Configuring Docker for non-root access..."
    
    # Create docker group if it doesn't exist
    if ! getent group docker >/dev/null; then
        groupadd docker
        log_success "Docker group created"
    fi
    
    # Add current user (who invoked sudo) to docker group
    local actual_user="${SUDO_USER:-$USER}"
    if [ "$actual_user" != "root" ]; then
        usermod -aG docker "$actual_user"
        log_success "User $actual_user added to docker group"
        log_info "Note: Log out and back in for group changes to take effect"
    fi
    
    # Enable and start Docker
    systemctl enable docker.service >/dev/null 2>&1
    systemctl enable containerd.service >/dev/null 2>&1
    systemctl start docker.service
    
    if systemctl is-active --quiet docker.service; then
        log_success "Docker service is running"
    else
        log_error "Docker service failed to start"
        exit 1
    fi
    
    # Test Docker
    if docker ps >/dev/null 2>&1; then
        log_success "Docker is working correctly"
    else
        log_error "Docker is not functioning properly"
        exit 1
    fi
}

# ============================================================================
# TAILSCALE INSTALLATION (APT + SYSTEMD METHOD)
# ============================================================================

install_tailscale_properly() {
    log_step "CONFIGURING TAILSCALE VPN"
    
    log_info "Tailscale provides secure access without UFW"
    log_info "Cloud provider firewall handles perimeter security"
    
    # Remove any existing snap installation
    if snap list tailscale >/dev/null 2>&1; then
        log_info "Removing snap-based Tailscale..."
        snap remove tailscale >/dev/null 2>&1 || true
    fi
    
    # Install via apt (no AppArmor issues)
    if command -v tailscale >/dev/null 2>&1; then
        log_success "Tailscale already installed"
    else
        log_info "Installing Tailscale via apt..."
        
        # Add Tailscale repository
        curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).noarmor.gpg | \
            tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
        
        curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).tailscale-keyring.list | \
            tee /etc/apt/sources.list.d/tailscale.list
        
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tailscale >/dev/null 2>&1
        
        log_success "Tailscale installed via apt"
    fi
    
    # Enable and start tailscaled service
    systemctl enable tailscaled.service >/dev/null 2>&1
    systemctl start tailscaled.service
    
    if systemctl is-active --quiet tailscaled.service; then
        log_success "Tailscaled service is running"
    else
        log_error "Tailscaled service failed to start"
        exit 1
    fi
    
    # Authentication
    log_info "Authenticating Tailscale..."
    echo ""
    read -p "❯ Enter Tailscale auth key (or press Enter to authenticate manually): " TAILSCALE_AUTH_KEY
    echo ""
    
    local tailscale_connected=false
    
    if [ -n "$TAILSCALE_AUTH_KEY" ]; then
        log_info "Authenticating with auth key..."
        
        if tailscale up --authkey="$TAILSCALE_AUTH_KEY" --accept-routes 2>&1 | tee -a "$LOG_FILE"; then
            tailscale_connected=true
            log_success "Tailscale authenticated successfully"
        else
            log_warning "Auth key authentication failed"
        fi
    fi
    
    if [ "$tailscale_connected" = false ]; then
        log_info "Manual authentication required..."
        log_info "Run: tailscale up"
        echo ""
        
        if tailscale up --accept-routes 2>&1 | tee -a "$LOG_FILE"; then
            tailscale_connected=true
            log_success "Tailscale authenticated successfully"
        else
            log_error "Manual authentication also failed"
            log_info "You can authenticate later with: sudo tailscale up"
        fi
    fi
    
    # Get Tailscale IP
    if [ "$tailscale_connected" = true ]; then
        sleep 2
        local tailscale_ip=$(tailscale ip -4 2>/dev/null)
        
        if [ -n "$tailscale_ip" ]; then
            log_success "Tailscale IP: $tailscale_ip"
            
            # Save configuration
            cat > "${CONFIG_PATH}/tailscale.conf" <<EOF
TAILSCALE_ENABLED="true"
TAILSCALE_IP="$tailscale_ip"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
        fi
    fi
}

# ============================================================================
# VECTOR DATABASE SELECTION
# ============================================================================

select_vector_database() {
    log_step "SELECTING VECTOR DATABASE"
    
    echo "Available vector databases:"
    echo "  1) Qdrant (recommended - best performance)"
    echo "  2) Chroma (simple, Python-native)"
    echo "  3) Weaviate (enterprise features)"
    echo ""
    
    while true; do
        read -p "❯ Select vector database (1-3): " choice
        
        case $choice in
            1)
                VECTOR_DB="qdrant"
                log_success "Selected: Qdrant (port 6333)"
                break
                ;;
            2)
                VECTOR_DB="chroma"
                log_success "Selected: Chroma (port 8000)"
                break
                ;;
            3)
                VECTOR_DB="weaviate"
                log_success "Selected: Weaviate (port 8080)"
                break
                ;;
            *)
                log_error "Invalid choice, please select 1-3"
                ;;
        esac
    done
    
    # Save configuration
    cat > "${CONFIG_PATH}/vector-db.conf" <<EOF
VECTOR_DB="$VECTOR_DB"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
}

# ============================================================================
# REVERSE PROXY SELECTION
# ============================================================================

select_reverse_proxy() {
    log_step "SELECTING REVERSE PROXY"
    
    echo "Available reverse proxies:"
    echo "  1) Traefik (recommended - automatic SSL, dashboard)"
    echo "  2) Nginx Proxy Manager (web UI)"
    echo "  3) Caddy (simple, automatic HTTPS)"
    echo ""
    
    while true; do
        read -p "❯ Select reverse proxy (1-3): " choice
        
        case $choice in
            1)
                REVERSE_PROXY="traefik"
                log_success "Selected: Traefik"
                break
                ;;
            2)
                REVERSE_PROXY="nginx-proxy-manager"
                log_success "Selected: Nginx Proxy Manager"
                break
                ;;
            3)
                REVERSE_PROXY="caddy"
                log_success "Selected: Caddy"
                break
                ;;
            *)
                log_error "Invalid choice, please select 1-3"
                ;;
        esac
    done
    
    # Save configuration
    cat > "${CONFIG_PATH}/reverse-proxy.conf" <<EOF
REVERSE_PROXY="$REVERSE_PROXY"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
}

# ============================================================================
# CLOUD PROVIDER SELECTION
# ============================================================================

select_cloud_provider() {
    log_step "SELECTING CLOUD PROVIDER"
    
    echo "Cloud provider (for firewall documentation):"
    echo "  1) AWS (Security Groups)"
    echo "  2) GCP (Firewall Rules)"
    echo "  3) Azure (Network Security Groups)"
    echo "  4) Other/On-Premise"
    echo ""
    
    while true; do
        read -p "❯ Select cloud provider (1-4): " choice
        
        case $choice in
            1)
                CLOUD_PROVIDER="aws"
                log_success "Selected: AWS"
                break
                ;;
            2)
                CLOUD_PROVIDER="gcp"
                log_success "Selected: GCP"
                break
                ;;
            3)
                CLOUD_PROVIDER="azure"
                log_success "Selected: Azure"
                break
                ;;
            4)
                CLOUD_PROVIDER="other"
                log_success "Selected: Other/On-Premise"
                break
                ;;
            *)
                log_error "Invalid choice, please select 1-4"
                ;;
        esac
    done
    
    # Save configuration
    cat > "${CONFIG_PATH}/cloud-provider.conf" <<EOF
CLOUD_PROVIDER="$CLOUD_PROVIDER"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
}

# ============================================================================
# ADDITIONAL SERVICES CONFIGURATION
# ============================================================================

configure_additional_services() {
    log_step "CONFIGURING ADDITIONAL SERVICES"
    
    echo "Optional services:"
    echo ""
    
    # N8N
    read -p "❯ Enable N8N workflow automation? (y/N): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        ENABLE_N8N="true"
        log_success "N8N enabled"
    else
        log_info "N8N disabled"
    fi
    
    # Monitoring
    read -p "❯ Enable monitoring stack (Prometheus/Grafana/Loki)? (y/N): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        ENABLE_MONITORING="true"
        log_success "Monitoring stack enabled"
    else
        log_info "Monitoring stack disabled"
    fi
    
    # Signal-CLI
    read -p "❯ Enable Signal messaging integration? (y/N): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        ENABLE_SIGNAL="true"
        log_success "Signal integration enabled"
    else
        log_info "Signal integration disabled"
    fi
    
    # Google Drive
    read -p "❯ Enable Google Drive sync? (y/N): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        ENABLE_GDRIVE_SYNC="true"
        log_success "Google Drive sync enabled"
    else
        log_info "Google Drive sync disabled"
    fi
    
    # Save configuration
    cat > "${CONFIG_PATH}/additional-services.conf" <<EOF
ENABLE_N8N="$ENABLE_N8N"
ENABLE_MONITORING="$ENABLE_MONITORING"
ENABLE_SIGNAL="$ENABLE_SIGNAL"
ENABLE_GDRIVE_SYNC="$ENABLE_GDRIVE_SYNC"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    log_success "Additional services configured"
}

# ============================================================================
# SIGNAL-CLI CONFIGURATION
# ============================================================================

configure_signal_cli() {
    log_step "CONFIGURING SIGNAL-CLI"
    
    echo "Signal-CLI setup options:"
    echo "  1) Link via QR code (recommended - no phone number needed)"
    echo "  2) Register with phone number (requires SMS verification)"
    echo ""
    
    while true; do
        read -p "❯ Select method (1-2): " choice
        
        case $choice in
            1)
                log_success "QR code linking selected"
                log_info "After deployment, scan QR code from Signal app:"
                log_info "  docker logs signal-api"
                
                cat > "${CONFIG_PATH}/signal-method.conf" <<EOF
SIGNAL_METHOD="qr"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
                break
                ;;
            2)
                read -p "❯ Enter phone number (E.164 format, e.g., +1234567890): " SIGNAL_PHONE
                
                if [[ "$SIGNAL_PHONE" =~ ^\+[0-9]{10,15}$ ]]; then
                    log_success "Phone number: $SIGNAL_PHONE"
                    
                    cat > "${CONFIG_PATH}/signal-phone.conf" <<EOF
SIGNAL_METHOD="phone"
SIGNAL_PHONE="$SIGNAL_PHONE"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
                    
                    log_info "After deployment, register with:"
                    log_info "  docker exec -it signal-api signal-cli -a $SIGNAL_PHONE register"
                    log_info "  docker exec -it signal-api signal-cli -a $SIGNAL_PHONE verify CODE"
                    break
                else
                    log_error "Invalid phone number format"
                fi
                ;;
            *)
                log_error "Invalid choice, please select 1 or 2"
                ;;
        esac
    done
}

# ============================================================================
# LLM PROVIDERS CONFIGURATION
# ============================================================================

configure_llm_providers() {
    log_step "CONFIGURING LLM PROVIDERS"
    
    log_info "Configure API keys for external LLM providers"
    log_info "Press Enter to skip any provider"
    echo ""
    
    local providers_config=""
    
    # OpenAI
    read -p "❯ OpenAI API Key: " OPENAI_API_KEY
    if [ -n "$OPENAI_API_KEY" ]; then
        providers_config+="OPENAI_API_KEY=\"${OPENAI_API_KEY}\"\n"
        log_success "OpenAI configured"
    fi
    
    # Anthropic
    read -p "❯ Anthropic API Key: " ANTHROPIC_API_KEY
    if [ -n "$ANTHROPIC_API_KEY" ]; then
        providers_config+="ANTHROPIC_API_KEY=\"${ANTHROPIC_API_KEY}\"\n"
        log_success "Anthropic configured"
    fi
    
    # Google AI
    read -p "❯ Google AI API Key: " GOOGLE_API_KEY
    if [ -n "$GOOGLE_API_KEY" ]; then
        providers_config+="GOOGLE_API_KEY=\"${GOOGLE_API_KEY}\"\n"
        log_success "Google AI configured"
    fi
    
    # Cohere
    read -p "❯ Cohere API Key: " COHERE_API_KEY
    if [ -n "$COHERE_API_KEY" ]; then
        providers_config+="COHERE_API_KEY=\"${COHERE_API_KEY}\"\n"
        log_success "Cohere configured"
    fi
    
    # Mistral
    read -p "❯ Mistral API Key: " MISTRAL_API_KEY
    if [ -n "$MISTRAL_API_KEY" ]; then
        providers_config+="MISTRAL_API_KEY=\"${MISTRAL_API_KEY}\"\n"
        log_success "Mistral configured"
    fi
    
    # Save providers configuration
    if [ -n "$providers_config" ]; then
        echo -e "$providers_config" > "${SECRETS_PATH}/llm-providers.env"
        chmod 600 "${SECRETS_PATH}/llm-providers.env"
        log_success "LLM provider credentials saved"
    else
        log_warning "No LLM providers configured (can be added later)"
    fi
}

# ============================================================================
# LITELLM CONFIGURATION GENERATION
# ============================================================================

generate_litellm_config() {
    log_step "GENERATING LITELLM CONFIGURATION"
    
    log_info "Creating LiteLLM routing configuration..."
    
    # Base configuration
    cat > "${DATA_PATH}/litellm/config/litellm_config.yaml" <<'EOF'
# LiteLLM Configuration
model_list:
  # OpenAI Models
  - model_name: gpt-4
    litellm_params:
      model: openai/gpt-4
      api_key: os.environ/OPENAI_API_KEY
      
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: openai/gpt-3.5-turbo
      api_key: os.environ/OPENAI_API_KEY

  # Anthropic Models
  - model_name: claude-3-opus
    litellm_params:
      model: anthropic/claude-3-opus-20240229
      api_key: os.environ/ANTHROPIC_API_KEY
      
  - model_name: claude-3-sonnet
    litellm_params:
      model: anthropic/claude-3-sonnet-20240229
      api_key: os.environ/ANTHROPIC_API_KEY

  # Google AI Models
  - model_name: gemini-pro
    litellm_params:
      model: google/gemini-pro
      api_key: os.environ/GOOGLE_API_KEY

  # Cohere Models
  - model_name: command-r-plus
    litellm_params:
      model: cohere/command-r-plus
      api_key: os.environ/COHERE_API_KEY

  # Mistral Models
  - model_name: mistral-large
    litellm_params:
      model: mistral/mistral-large-latest
      api_key: os.environ/MISTRAL_API_KEY

# Routing Configuration
router_settings:
  routing_strategy: simple-shuffle
  model_group_alias:
    gpt-4: ["gpt-4"]
    gpt-3.5: ["gpt-3.5-turbo"]
    claude: ["claude-3-opus", "claude-3-sonnet"]
    gemini: ["gemini-pro"]

# General Settings
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: postgresql://ai_platform:os.environ/POSTGRES_PASSWORD@postgres:5432/ai_platform
  
  # Caching
  redis_host: redis
  redis_port: 6379
  redis_password: os.environ/REDIS_PASSWORD
  
  # Observability
  success_callback: ["langfuse"]
  langfuse_public_key: os.environ/LANGFUSE_PUBLIC_KEY
  langfuse_secret_key: os.environ/LANGFUSE_SECRET_KEY
  langfuse_host: http://langfuse:3001

# Logging
litellm_settings:
  drop_params: true
  set_verbose: false
  json_logs: true
EOF
    
    chmod 644 "${DATA_PATH}/litellm/config/litellm_config.yaml"
    log_success "LiteLLM configuration generated"
}

# ============================================================================
# SECRETS GENERATION
# ============================================================================

generate_secrets() {
    log_step "GENERATING SECRETS"
    
    log_info "Generating secure passwords and keys..."
    
    # Generate strong random strings
    generate_password() {
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
    }
    
    generate_key() {
        openssl rand -hex 32
    }
    
    # Core database passwords
    POSTGRES_PASSWORD=$(generate_password)
    REDIS_PASSWORD=$(generate_password)
    
    # Service API keys
    LITELLM_MASTER_KEY=$(generate_key)
    OPENCLAW_API_KEY=$(generate_key)
    OPENWEBUI_SECRET=$(generate_key)
    
    # N8N encryption key
    N8N_ENCRYPTION_KEY=$(generate_key)
    
    # Langfuse keys
    LANGFUSE_PUBLIC_KEY=$(generate_key)
    LANGFUSE_SECRET_KEY=$(generate_key)
    LANGFUSE_SALT=$(generate_password)
    
    # JWT secret
    JWT_SECRET=$(generate_key)
    
    # Save all secrets
    cat > "${SECRETS_PATH}/generated.env" <<EOF
# Generated Secrets - $(date -u +%Y-%m-%dT%H:%M:%SZ)
# DO NOT COMMIT TO VERSION CONTROL

# Database Passwords
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
REDIS_PASSWORD="${REDIS_PASSWORD}"

# Service API Keys
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY}"
OPENCLAW_API_KEY="${OPENCLAW_API_KEY}"
OPENWEBUI_SECRET="${OPENWEBUI_SECRET}"

# Workflow Automation
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY}"

# Observability
LANGFUSE_PUBLIC_KEY="${LANGFUSE_PUBLIC_KEY}"
LANGFUSE_SECRET_KEY="${LANGFUSE_SECRET_KEY}"
LANGFUSE_SALT="${LANGFUSE_SALT}"

# Security
JWT_SECRET="${JWT_SECRET}"
EOF
    
    chmod 600 "${SECRETS_PATH}/generated.env"
    
    log_success "Secrets generated and saved securely"
    log_warning "Backup ${SECRETS_PATH}/generated.env immediately!"
}

# ============================================================================
# ENVIRONMENT FILE CREATION
# ============================================================================

create_environment_files() {
    log_step "CREATING ENVIRONMENT FILES"
    
    # Load all configurations
    source "${CONFIG_PATH}/domain.conf"
    source "${CONFIG_PATH}/vector-db.conf"
    source "${CONFIG_PATH}/reverse-proxy.conf"
    source "${CONFIG_PATH}/cloud-provider.conf"
    source "${CONFIG_PATH}/additional-services.conf"
    source "${SECRETS_PATH}/generated.env"
    
    # Load optional configs
    [ -f "${CONFIG_PATH}/tailscale.conf" ] && source "${CONFIG_PATH}/tailscale.conf"
    [ -f "${SECRETS_PATH}/llm-providers.env" ] && source "${SECRETS_PATH}/llm-providers.env"
    
    log_info "Creating master .env file..."
    
    # Create master environment file
    cat > "${ROOT_PATH}/.env" <<EOF
# AI Platform Environment Configuration
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

# =============================================================================
# DOMAIN & SSL
# =============================================================================
DOMAIN_NAME="${DOMAIN_NAME}"
SSL_EMAIL="${SSL_EMAIL}"

# =============================================================================
# INFRASTRUCTURE
# =============================================================================
CLOUD_PROVIDER="${CLOUD_PROVIDER}"
REVERSE_PROXY="${REVERSE_PROXY}"
VECTOR_DB="${VECTOR_DB}"

# =============================================================================
# DATABASE SERVICES
# =============================================================================
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=ai_platform
POSTGRES_USER=ai_platform
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD="${REDIS_PASSWORD}"

# =============================================================================
# CORE AI SERVICES
# =============================================================================
LITELLM_HOST=litellm
LITELLM_PORT=4000
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY}"

OPENCLAW_HOST=openclaw
OPENCLAW_PORT=8001
OPENCLAW_API_KEY="${OPENCLAW_API_KEY}"

OPENWEBUI_HOST=openwebui
OPENWEBUI_PORT=3002
OPENWEBUI_SECRET="${OPENWEBUI_SECRET}"

# =============================================================================
# WORKFLOW AUTOMATION
# =============================================================================
N8N_ENABLED="${ENABLE_N8N}"
N8N_HOST=n8n
N8N_PORT=5678
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY}"

# =============================================================================
# MONITORING & OBSERVABILITY
# =============================================================================
PROMETHEUS_ENABLED="${ENABLE_MONITORING}"
GRAFANA_ENABLED="${ENABLE_MONITORING}"
LOKI_ENABLED="${ENABLE_MONITORING}"

LANGFUSE_HOST=langfuse
LANGFUSE_PORT=3001
LANGFUSE_PUBLIC_KEY="${LANGFUSE_PUBLIC_KEY}"
LANGFUSE_SECRET_KEY="${LANGFUSE_SECRET_KEY}"
LANGFUSE_SALT="${LANGFUSE_SALT}"

# =============================================================================
# INTEGRATION SERVICES
# =============================================================================
SIGNAL_ENABLED="${ENABLE_SIGNAL}"
SIGNAL_HOST=signal-api
SIGNAL_PORT=8080

GDRIVE_SYNC_ENABLED="${ENABLE_GDRIVE_SYNC}"

TAILSCALE_ENABLED="${TAILSCALE_ENABLED:-true}"
TAILSCALE_IP="${TAILSCALE_IP:-N/A}"

# =============================================================================
# SECURITY
# =============================================================================
JWT_SECRET="${JWT_SECRET}"

# =============================================================================
# PATHS
# =============================================================================
DATA_PATH=/mnt/data/ai-platform
LOG_PATH=/mnt/data/ai-platform/logs
BACKUP_PATH=/mnt/data/ai-platform/backups
EOF
    
    chmod 600 "${ROOT_PATH}/.env"
    
    log_success "Master .env file created"
    
    # Create service-specific env files
    log_info "Creating service-specific environment files..."
    
    # LiteLLM environment
    if [ -f "${SECRETS_PATH}/llm-providers.env" ]; then
        cat "${SECRETS_PATH}/llm-providers.env" > "${DATA_PATH}/litellm/config/.env"
        echo "LITELLM_MASTER_KEY=\"${LITELLM_MASTER_KEY}\"" >> "${DATA_PATH}/litellm/config/.env"
        echo "POSTGRES_PASSWORD=\"${POSTGRES_PASSWORD}\"" >> "${DATA_PATH}/litellm/config/.env"
        echo "REDIS_PASSWORD=\"${REDIS_PASSWORD}\"" >> "${DATA_PATH}/litellm/config/.env"
        echo "LANGFUSE_PUBLIC_KEY=\"${LANGFUSE_PUBLIC_KEY}\"" >> "${DATA_PATH}/litellm/config/.env"
        echo "LANGFUSE_SECRET_KEY=\"${LANGFUSE_SECRET_KEY}\"" >> "${DATA_PATH}/litellm/config/.env"
        chmod 600 "${DATA_PATH}/litellm/config/.env"
    fi
    
    # OpenClaw environment
    cat > "${DATA_PATH}/openclaw/config/.env" <<EOF
OPENCLAW_API_KEY="${OPENCLAW_API_KEY}"
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=ai_platform
POSTGRES_USER=ai_platform
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD="${REDIS_PASSWORD}"
LITELLM_URL=http://litellm:4000
LITELLM_API_KEY="${LITELLM_MASTER_KEY}"
EOF
    chmod 600 "${DATA_PATH}/openclaw/config/.env"
    
    # OpenWebUI environment
    cat > "${DATA_PATH}/openwebui/config/.env" <<EOF
OPENWEBUI_SECRET_KEY="${OPENWEBUI_SECRET}"
OLLAMA_BASE_URL=http://ollama:11434
LITELLM_BASE_URL=http://litellm:4000
LITELLM_API_KEY="${LITELLM_MASTER_KEY}"
WEBUI_AUTH=true
WEBUI_JWT_SECRET_KEY="${JWT_SECRET}"
EOF
    chmod 600 "${DATA_PATH}/openwebui/config/.env"
    
    # N8N environment (if enabled)
    if [ "$ENABLE_N8N" = "true" ]; then
        cat > "${DATA_PATH}/n8n/.env" <<EOF
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY}"
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=https
N8N_EDITOR_BASE_URL=https://n8n.${DOMAIN_NAME}
WEBHOOK_URL=https://n8n.${DOMAIN_NAME}
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=ai_platform
POSTGRES_USER=ai_platform
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
POSTGRES_SCHEMA=n8n
EOF
        chmod 600 "${DATA_PATH}/n8n/.env"
    fi
    
    # Langfuse environment
    cat > "${DATA_PATH}/langfuse/.env" <<EOF
DATABASE_URL=postgresql://ai_platform:${POSTGRES_PASSWORD}@postgres:5432/ai_platform
NEXTAUTH_URL=https://langfuse.${DOMAIN_NAME}
NEXTAUTH_SECRET="${LANGFUSE_SECRET_KEY}"
SALT="${LANGFUSE_SALT}"
LANGFUSE_PUBLIC_KEY="${LANGFUSE_PUBLIC_KEY}"
LANGFUSE_SECRET_KEY="${LANGFUSE_SECRET_KEY}"
EOF
    chmod 600 "${DATA_PATH}/langfuse/.env"
    
    log_success "Service-specific environment files created"
}

# ============================================================================
# GOOGLE DRIVE SYNC CONFIGURATION (2 AUTH METHODS)
# ============================================================================

configure_google_drive_sync() {
    if [ "$ENABLE_GDRIVE_SYNC" != "true" ]; then
        return 0
    fi
    
    log_step "CONFIGURING GOOGLE DRIVE SYNC"
    
    log_info "Google Drive sync requires OAuth authentication"
    echo ""
    echo "Two authentication methods available:"
    echo "  1) Browser OAuth (automatic - recommended)"
    echo "  2) Manual token paste (headless servers)"
    echo ""
    
    while true; do
        read -p "❯ Select method (1-2): " GDRIVE_METHOD
        
        case "$GDRIVE_METHOD" in
            1)
                log_info "Browser OAuth selected"
                log_info "After deployment, run:"
                echo ""
                echo "  docker exec -it gdrive-sync rclone config create gdrive drive"
                echo ""
                log_info "This will:"
                echo "  1. Generate an OAuth URL"
                echo "  2. Open your browser for authorization"
                echo "  3. Automatically save the token"
                
                # Create placeholder config
                mkdir -p "${DATA_PATH}/gdrive-sync/rclone"
                cat > "${DATA_PATH}/gdrive-sync/rclone/README.txt" <<EOF
Google Drive OAuth Configuration

After deployment, authenticate with:

  docker exec -it gdrive-sync rclone config create gdrive drive

Follow the browser prompts to authorize access.

Configuration will be saved to: /config/rclone/rclone.conf
EOF
                
                GDRIVE_AUTH_METHOD="browser"
                break
                ;;
            2)
                log_info "Manual token method selected"
                echo ""
                log_info "To generate token manually:"
                echo "  1. Visit: https://rclone.org/drive/#making-your-own-client-id"
                echo "  2. Create OAuth credentials"
                echo "  3. Run locally: rclone authorize \"drive\""
                echo "  4. Paste resulting token below"
                echo ""
                
                read -p "❯ Paste OAuth token (or press Enter to configure later): " GDRIVE_TOKEN
                
                if [ -n "$GDRIVE_TOKEN" ]; then
                    # Create rclone config with token
                    mkdir -p "${DATA_PATH}/gdrive-sync/rclone"
                    cat > "${DATA_PATH}/gdrive-sync/rclone/rclone.conf" <<EOF
[gdrive]
type = drive
scope = drive
token = ${GDRIVE_TOKEN}
team_drive = 
EOF
                    chmod 600 "${DATA_PATH}/gdrive-sync/rclone/rclone.conf"
                    log_success "OAuth token saved"
                    GDRIVE_AUTH_METHOD="manual-token"
                else
                    log_info "Token configuration deferred"
                    GDRIVE_AUTH_METHOD="manual-later"
                fi
                break
                ;;
            *)
                log_error "Invalid choice, please select 1 or 2"
                ;;
        esac
    done
    
    # Configure sync settings
    echo ""
    read -p "❯ Google Drive folder to sync (default: /AIPlatform): " GDRIVE_FOLDER
    GDRIVE_FOLDER="${GDRIVE_FOLDER:-/AIPlatform}"
    
    read -p "❯ Sync interval in hours (default: 6): " SYNC_INTERVAL
    SYNC_INTERVAL="${SYNC_INTERVAL:-6}"
    
    # Save configuration
    cat > "${CONFIG_PATH}/gdrive.conf" <<EOF
ENABLE_GDRIVE_SYNC="true"
GDRIVE_AUTH_METHOD="${GDRIVE_AUTH_METHOD}"
GDRIVE_FOLDER="${GDRIVE_FOLDER}"
SYNC_INTERVAL="${SYNC_INTERVAL}"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    # Create sync script
    cat > "${DATA_PATH}/gdrive-sync/sync.sh" <<'EOFSCRIPT'
#!/bin/bash
# Google Drive Sync Script

REMOTE_PATH="${GDRIVE_FOLDER}"
LOCAL_PATH="/data"
LOG_FILE="/data/logs/gdrive-sync.log"

echo "[$(date)] Starting sync: ${LOCAL_PATH} <-> gdrive:${REMOTE_PATH}" | tee -a "$LOG_FILE"

rclone sync "${LOCAL_PATH}" "gdrive:${REMOTE_PATH}" \
    --exclude ".git/**" \
    --exclude "*.tmp" \
    --exclude "*.log" \
    --log-file="$LOG_FILE" \
    --log-level INFO \
    --stats 1m

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "[$(date)] Sync completed successfully" | tee -a "$LOG_FILE"
else
    echo "[$(date)] Sync failed with code ${EXIT_CODE}" | tee -a "$LOG_FILE"
fi
EOFSCRIPT
    
    chmod +x "${DATA_PATH}/gdrive-sync/sync.sh"
    
    log_success "Google Drive sync configured"
    log_info "Sync folder: ${GDRIVE_FOLDER}"
    log_info "Sync interval: ${SYNC_INTERVAL} hours"
}

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

show_deployment_summary() {
    log_step "DEPLOYMENT SUMMARY"
    
    # Load all configurations
    source "${CONFIG_PATH}/domain.conf"
    source "${CONFIG_PATH}/vector-db.conf"
    source "${CONFIG_PATH}/reverse-proxy.conf"
    source "${CONFIG_PATH}/cloud-provider.conf"
    source "${CONFIG_PATH}/additional-services.conf"
    
    local tailscale_ip="N/A"
    [ -f "${CONFIG_PATH}/tailscale.conf" ] && source "${CONFIG_PATH}/tailscale.conf" && tailscale_ip="${TAILSCALE_IP}"
    
    echo ""
    log_section "✅ SYSTEM INITIALIZATION COMPLETE"
    
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  DEPLOYMENT CONFIGURATION${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${CYAN}📋 INFRASTRUCTURE${NC}"
    echo -e "   • Domain:            ${GREEN}${DOMAIN_NAME}${NC}"
    echo -e "   • SSL Email:         ${GREEN}${SSL_EMAIL}${NC}"
    echo -e "   • Cloud Provider:    ${GREEN}${CLOUD_PROVIDER}${NC}"
    echo -e "   • Reverse Proxy:     ${GREEN}${REVERSE_PROXY}${NC}"
    echo -e "   • Vector Database:   ${GREEN}${VECTOR_DB}${NC}"
    echo -e "   • Tailscale IP:      ${GREEN}${tailscale_ip}${NC}"
    echo ""
    
    echo -e "${CYAN}🔧 CORE SERVICES${NC}"
    echo -e "   • PostgreSQL:        ${GREEN}✓ Configured${NC} (port 5432)"
    echo -e "   • Redis:             ${GREEN}✓ Configured${NC} (port 6379)"
    echo -e "   • ${VECTOR_DB}:           ${GREEN}✓ Configured${NC}"
    echo -e "   • LiteLLM:           ${GREEN}✓ Configured${NC} (port 4000)"
    echo -e "   • OpenClaw:          ${GREEN}✓ Configured${NC} (port 8001)"
    echo -e "   • OpenWebUI:         ${GREEN}✓ Configured${NC} (port 3002)"
    echo ""
    
    echo -e "${CYAN}🚀 ADDITIONAL SERVICES${NC}"
    
    if [ "$ENABLE_N8N" = "true" ]; then
        echo -e "   • N8N:               ${GREEN}✓ Enabled${NC} (https://n8n.${DOMAIN_NAME})"
    else
        echo -e "   • N8N:               ${YELLOW}○ Disabled${NC}"
    fi
    
    if [ "$ENABLE_MONITORING" = "true" ]; then
        echo -e "   • Prometheus:        ${GREEN}✓ Enabled${NC} (port 9090)"
        echo -e "   • Grafana:           ${GREEN}✓ Enabled${NC} (https://grafana.${DOMAIN_NAME})"
        echo -e "   • Loki:              ${GREEN}✓ Enabled${NC} (port 3100)"
    else
        echo -e "   • Monitoring Stack:  ${YELLOW}○ Disabled${NC}"
    fi
    
    echo -e "   • Langfuse:          ${GREEN}✓ Enabled${NC} (https://langfuse.${DOMAIN_NAME})"
    echo ""
    
    echo -e "${CYAN}🔗 INTEGRATIONS${NC}"
    
    if [ "$ENABLE_SIGNAL" = "true" ]; then
        echo -e "   • Signal-CLI:        ${GREEN}✓ Enabled${NC}"
    else
        echo -e "   • Signal-CLI:        ${YELLOW}○ Disabled${NC}"
    fi
    
    if [ "$ENABLE_GDRIVE_SYNC" = "true" ]; then
        echo -e "   • Google Drive:      ${GREEN}✓ Enabled${NC}"
    else
        echo -e "   • Google Drive:      ${YELLOW}○ Disabled${NC}"
    fi
    
    echo ""
    
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  ACCESS URLS${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "   🌐 Primary Services:"
    echo -e "      • Main Platform:     ${GREEN}https://${DOMAIN_NAME}${NC}"
    echo -e "      • LiteLLM API:       ${GREEN}https://litellm.${DOMAIN_NAME}${NC}"
    echo -e "      • OpenWebUI:         ${GREEN}https://openwebui.${DOMAIN_NAME}${NC}"
    echo -e "      • OpenClaw:          ${GREEN}https://openclaw.${DOMAIN_NAME}${NC}"
    echo ""
    
    if [ "$ENABLE_N8N" = "true" ] || [ "$ENABLE_MONITORING" = "true" ]; then
        echo -e "   🔧 Management Tools:"
        [ "$ENABLE_N8N" = "true" ] && echo -e "      • N8N Workflows:     ${GREEN}https://n8n.${DOMAIN_NAME}${NC}"
        [ "$ENABLE_MONITORING" = "true" ] && echo -e "      • Grafana:           ${GREEN}https://grafana.${DOMAIN_NAME}${NC}"
        echo -e "      • Langfuse:          ${GREEN}https://langfuse.${DOMAIN_NAME}${NC}"
        echo ""
    fi
    
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  SECURITY & CREDENTIALS${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "   🔒 Secrets Location:"
    echo -e "      ${YELLOW}${SECRETS_PATH}/generated.env${NC}"
    echo -e "      ${YELLOW}${SECRETS_PATH}/llm-providers.env${NC}"
    echo ""
    echo -e "   ${RED}⚠️  IMPORTANT: Backup these files immediately!${NC}"
    echo ""
    
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  NEXT STEPS${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "   ${GREEN}1.${NC} Update DNS A record:"
    echo -e "      ${DOMAIN_NAME} → $(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')"
    echo ""
    echo -e "   ${GREEN}2.${NC} Run deployment script:"
    echo -e "      ${CYAN}cd ${ROOT_PATH}${NC}"
    echo -e "      ${CYAN}sudo ./scripts/2-deploy-services.sh${NC}"
    echo ""
    echo -e "   ${GREEN}3.${NC} Monitor deployment:"
    echo -e "      ${CYAN}docker compose logs -f${NC}"
    echo ""
    
    if [ "$ENABLE_SIGNAL" = "true" ]; then
        echo -e "   ${GREEN}4.${NC} Configure Signal-CLI:"
        if [ -f "${CONFIG_PATH}/signal-phone.conf" ]; then
            source "${CONFIG_PATH}/signal-phone.conf"
            echo -e "      ${CYAN}docker exec -it signal-api signal-cli -a ${SIGNAL_PHONE} register${NC}"
            echo -e "      ${CYAN}docker exec -it signal-api signal-cli -a ${SIGNAL_PHONE} verify CODE${NC}"
        else
            echo -e "      ${CYAN}docker logs signal-api${NC} (scan QR code)"
        fi
        echo ""
    fi
    
    if [ "$ENABLE_GDRIVE_SYNC" = "true" ]; then
        local step_num=5
        [ "$ENABLE_SIGNAL" = "true" ] && step_num=5 || step_num=4
        echo -e "   ${GREEN}${step_num}.${NC} Configure Google Drive:"
        echo -e "      ${CYAN}docker exec -it gdrive-sync rclone config create gdrive drive${NC}"
        echo ""
    fi
    
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    log_success "System initialization complete! Ready for deployment."
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    clear
    
    log_section "AI PLATFORM SYSTEM INITIALIZATION v${SCRIPT_VERSION}"
    
    echo -e "${BLUE}This script will:${NC}"
    echo -e "  ${GREEN}✓${NC} Install Docker & Docker Compose"
    echo -e "  ${GREEN}✓${NC} Configure Tailscale VPN (apt method)"
    echo -e "  ${GREEN}✓${NC} Setup AppArmor (systemd approach)"
    echo -e "  ${GREEN}✓${NC} Initialize storage tier"
    echo -e "  ${GREEN}✓${NC} Generate secrets"
    echo -e "  ${GREEN}✓${NC} Configure LLM providers"
    echo -e "  ${GREEN}✓${NC} Setup optional services"
    echo ""
    
    read -p "Press Enter to continue or Ctrl+C to abort..."
    
    # Pre-flight checks
    check_root
    check_ubuntu_version
    check_internet_connectivity
    
    # Core system setup
    setup_apparmor_properly
    initialize_storage_tier
    check_port_availability
    
    # Domain & SSL
    validate_domain
    
    # Docker installation
    install_docker
    
    # Tailscale (apt + systemd)
    install_tailscale_properly
    
    # Vector database selection
    select_vector_database
    
    # Reverse proxy selection
    select_reverse_proxy
    
    # Cloud provider
    select_cloud_provider
    
    # Additional services
    configure_additional_services
    
    # Optional: Signal-CLI
    [ "$ENABLE_SIGNAL" = "true" ] && configure_signal_cli
    
    # External LLM providers
    configure_llm_providers
    
    # Generate LiteLLM config
    generate_litellm_config
    
    # Optional: Google Drive
    [ "$ENABLE_GDRIVE_SYNC" = "true" ] && configure_google_drive_sync
    
    # Generate secrets
    generate_secrets
    
    # Create environment files
    create_environment_files
    
    # Show summary
    show_deployment_summary
    
    log_success "Script completed successfully!"
    
    exit 0
}

# Execute main function
main "$@"
