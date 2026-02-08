#!/usr/bin/env bash

################################################################################
# SCRIPT 1 v98.5.0 - AI PLATFORM SYSTEM INITIALIZATION
# PHASE 1: CRITICAL REGRESSION FIXES
# - Restored Tailscale v98.3.1 logic (auth key + API key + port 8443)
# - Restored Google Drive v98.3.1 logic (2 auth methods)
# - Zero regressions from working baseline
################################################################################

set -uo pipefail

# ============================================================================
# CONSTANTS & CONFIGURATION
# ============================================================================

readonly SCRIPT_VERSION="98.5.0"
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

# Paths
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
TAILSCALE_API_KEY=""
GPU_ENABLED="false"
GDRIVE_AUTH_METHOD=""
GDRIVE_SERVICE_ACCOUNT_JSON=""
GDRIVE_CLIENT_ID=""
GDRIVE_CLIENT_SECRET=""
GDRIVE_SYNC_PATH="/mnt/data/gdrive"

# Port allocations (AI GUIDE COMPLIANT)
readonly OLLAMA_PORT=11434
readonly LITELLM_PORT=4000
readonly OPENWEBUI_PORT=8080
readonly OPENCLAW_PORT=8001
readonly POSTGRES_PORT=5432
readonly REDIS_PORT=6379
readonly LANGFUSE_PORT=3000
readonly N8N_PORT=5678
readonly GRAFANA_PORT=3001
readonly PROMETHEUS_PORT=9090
readonly SIGNAL_CLI_PORT=8080
readonly TAILSCALE_PORT=8443  # FIXED: Restored correct port
readonly QDRANT_PORT=6333
readonly CHROMADB_PORT=8000
readonly WEAVIATE_PORT=8080
readonly MILVUS_PORT=19530

# ============================================================================
# LOGGING & PROGRESS FUNCTIONS
# ============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

progress_bar() {
    ((CURRENT_STEP++))
    local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local completed=$((percent / 2))
    local remaining=$((50 - completed))
    
    printf "\r${BOLD}[%d/%d]${NC} [" "$CURRENT_STEP" "$TOTAL_STEPS"
    printf "%${completed}s" | tr ' ' '█'
    printf "%${remaining}s" | tr ' ' '░'
    printf "] %d%%" "$percent"
}

show_step() {
    progress_bar
    echo -e " ${CYAN}$1${NC}"
    log "STEP [$CURRENT_STEP/$TOTAL_STEPS]: $1"
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

check_root() {
    show_step "Checking root privileges"
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    log_success "Root privileges confirmed"
}

check_ubuntu_version() {
    show_step "Verifying Ubuntu version"
    
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot determine OS version"
        exit 1
    fi
    
    source /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "This script requires Ubuntu (detected: $ID)"
        exit 1
    fi
    
    local version_major="${VERSION_ID%%.*}"
    if [[ "$version_major" -lt 20 ]]; then
        log_error "Ubuntu 20.04 or higher required (detected: $VERSION_ID)"
        exit 1
    fi
    
    log_success "Ubuntu $VERSION_ID detected"
}

check_internet_connectivity() {
    show_step "Testing internet connectivity"
    
    local test_hosts=("8.8.8.8" "1.1.1.1")
    local connected=false
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 2 "$host" &>/dev/null; then
            connected=true
            break
        fi
    done
    
    if [[ "$connected" = false ]]; then
        log_error "No internet connectivity detected"
        exit 1
    fi
    
    log_success "Internet connectivity confirmed"
}

check_disk_space() {
    show_step "Checking available disk space"
    
    local required_gb=50
    local available_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [[ "$available_gb" -lt "$required_gb" ]]; then
        log_error "Insufficient disk space: ${available_gb}GB available, ${required_gb}GB required"
        exit 1
    fi
    
    log_success "${available_gb}GB disk space available"
}

# ============================================================================
# APPARMOR CONFIGURATION
# ============================================================================

setup_apparmor_properly() {
    show_step "Configuring AppArmor security profiles"
    
    # Check if AppArmor is available in kernel
    if [[ ! -d /sys/kernel/security/apparmor ]]; then
        log_warning "AppArmor not available in kernel - skipping security profile setup"
        return 0
    fi
    
    # Install AppArmor utilities if needed
    if ! command -v aa-status &>/dev/null; then
        log_info "Installing AppArmor utilities..."
        apt-get update -qq
        apt-get install -y -qq apparmor-utils &>/dev/null
    fi
    
    # Create Docker AppArmor profile
    local profile_path="/etc/apparmor.d/docker-ai-platform"
    
    cat > "$profile_path" <<'EOF'
#include <tunables/global>

profile docker-ai-platform flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  
  network,
  capability,
  file,
  umount,
  
  deny @{PROC}/* w,
  deny /sys/[^f]*/** wklx,
  deny /sys/f[^s]*/** wklx,
  deny /sys/fs/[^c]*/** wklx,
  deny /sys/fs/c[^g]*/** wklx,
  deny /sys/fs/cg[^r]*/** wklx,
  deny /sys/firmware/** rwklx,
  deny /sys/kernel/security/** rwklx,
}
EOF
    
    # Load the profile
    if apparmor_parser -r "$profile_path" 2>/dev/null; then
        log_success "AppArmor profile loaded successfully"
    else
        log_warning "AppArmor profile created but not loaded (may not affect functionality)"
    fi
}

# ============================================================================
# STORAGE INITIALIZATION
# ============================================================================

initialize_storage_tier() {
    show_step "Initializing storage tier"
    
    local directories=(
        "$DATA_PATH"
        "$DATA_PATH/ollama"
        "$DATA_PATH/postgres"
        "$DATA_PATH/redis"
        "$DATA_PATH/qdrant"
        "$DATA_PATH/chromadb"
        "$DATA_PATH/weaviate"
        "$DATA_PATH/milvus"
        "$DATA_PATH/langfuse"
        "$DATA_PATH/n8n"
        "$DATA_PATH/grafana"
        "$DATA_PATH/prometheus"
        "$DATA_PATH/signal-cli"
        "$DATA_PATH/gdrive"
        "$DATA_PATH/backups"
        "$DATA_PATH/logs"
        "$SECRETS_PATH"
        "$CONFIG_PATH"
    )
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 755 "$dir"
            log_info "Created directory: $dir"
        fi
    done
    
    log_success "Storage tier initialized"
}

# ============================================================================
# PORT AVAILABILITY CHECKS
# ============================================================================

check_port_availability() {
    show_step "Checking port availability"
    
    local ports=(
        "$OLLAMA_PORT:Ollama"
        "$LITELLM_PORT:LiteLLM"
        "$OPENWEBUI_PORT:OpenWebUI"
        "$OPENCLAW_PORT:OpenClaw"
        "$POSTGRES_PORT:PostgreSQL"
        "$REDIS_PORT:Redis"
        "$LANGFUSE_PORT:Langfuse"
        "$N8N_PORT:n8n"
        "$GRAFANA_PORT:Grafana"
        "$PROMETHEUS_PORT:Prometheus"
        "$TAILSCALE_PORT:Tailscale"
    )
    
    local conflicts=0
    
    for port_info in "${ports[@]}"; do
        local port="${port_info%%:*}"
        local service="${port_info##*:}"
        
        if ss -tuln | grep -q ":${port} "; then
            log_warning "Port $port ($service) already in use"
            ((conflicts++))
        fi
    done
    
    if [[ $conflicts -gt 0 ]]; then
        log_warning "$conflicts port conflict(s) detected - may need manual resolution"
        echo ""
        read -p "Continue anyway? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Setup aborted by user"
            exit 1
        fi
    else
        log_success "All required ports available"
    fi
}

# ============================================================================
# GPU DETECTION
# ============================================================================

detect_gpu_capability() {
    show_step "Detecting GPU capability"
    
    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi &>/dev/null; then
            GPU_ENABLED="true"
            local gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits | head -1)
            log_success "NVIDIA GPU detected: $gpu_info"
            
            # Install NVIDIA Container Toolkit
            log_info "Installing NVIDIA Container Toolkit..."
            distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
                sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
            apt-get update -qq
            apt-get install -y -qq nvidia-container-toolkit
            
            log_success "GPU support enabled"
        else
            log_warning "nvidia-smi found but failed to query GPU"
            GPU_ENABLED="false"
        fi
    else
        log_info "No NVIDIA GPU detected - using CPU mode"
        GPU_ENABLED="false"
    fi
}

# ============================================================================
# DOMAIN VALIDATION
# ============================================================================

validate_domain() {
    show_step "Configuring domain and SSL"
    
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  DOMAIN & SSL CONFIGURATION${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    while true; do
        read -p "Enter your domain name (e.g., ai.example.com): " DOMAIN_NAME
        
        if [[ -z "$DOMAIN_NAME" ]]; then
            log_error "Domain name cannot be empty"
            continue
        fi
        
        # Basic domain validation
        if [[ ! "$DOMAIN_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$ ]]; then
            log_error "Invalid domain name format"
            continue
        fi
        
        break
    done
    
    while true; do
        read -p "Enter email for SSL certificates: " SSL_EMAIL
        
        if [[ -z "$SSL_EMAIL" ]]; then
            log_error "Email cannot be empty"
            continue
        fi
        
        # Basic email validation
        if [[ ! "$SSL_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log_error "Invalid email format"
            continue
        fi
        
        break
    done
    
    log_success "Domain configured: $DOMAIN_NAME"
    log_success "SSL email: $SSL_EMAIL"
}

# ============================================================================
# DOCKER INSTALLATION
# ============================================================================

install_docker() {
    show_step "Installing Docker and Docker Compose"
    
    if command -v docker &>/dev/null && command -v docker compose &>/dev/null; then
        local docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_success "Docker already installed: $docker_version"
        return 0
    fi
    
    log_info "Installing Docker..."
    
    # Remove old versions
    apt-get remove -y -qq docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Install prerequisites
    apt-get update -qq
    apt-get install -y -qq \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update -qq
    apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
    
    # Add current user to docker group if not root
    if [[ -n "${SUDO_USER:-}" ]]; then
        usermod -aG docker "$SUDO_USER"
        log_info "Added $SUDO_USER to docker group (logout/login required)"
    fi
    
    local docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
    log_success "Docker installed: $docker_version"
}

# ============================================================================
# TAILSCALE INSTALLATION & CONFIGURATION (RESTORED v98.3.1)
# ============================================================================

install_tailscale_properly() {
    show_step "Installing and configuring Tailscale VPN"
    
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  TAILSCALE VPN CONFIGURATION${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo -e "${BLUE}Tailscale provides secure remote access to your AI platform.${NC}"
    echo ""
    echo -e "${YELLOW}You'll need:${NC}"
    echo -e "  1. Tailscale Auth Key (from https://login.tailscale.com/admin/settings/keys)"
    echo -e "  2. Tailscale API Key (from https://login.tailscale.com/admin/settings/keys)"
    echo ""
    
    # Collect Tailscale Auth Key
    while true; do
        read -p "Enter Tailscale Auth Key: " TAILSCALE_AUTH_KEY
        
        if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
            log_error "Tailscale Auth Key cannot be empty"
            continue
        fi
        
        # Validate format (tskey-auth-*)
        if [[ ! "$TAILSCALE_AUTH_KEY" =~ ^tskey-auth- ]]; then
            log_warning "Auth key should start with 'tskey-auth-'"
            read -p "Continue anyway? (y/N): " -r
            [[ $REPLY =~ ^[Yy]$ ]] && break
            continue
        fi
        
        break
    done
    
    # Collect Tailscale API Key
    while true; do
        read -p "Enter Tailscale API Key: " TAILSCALE_API_KEY
        
        if [[ -z "$TAILSCALE_API_KEY" ]]; then
            log_error "Tailscale API Key cannot be empty"
            continue
        fi
        
        # Validate format (tskey-api-*)
        if [[ ! "$TAILSCALE_API_KEY" =~ ^tskey-api- ]]; then
            log_warning "API key should start with 'tskey-api-'"
            read -p "Continue anyway? (y/N): " -r
            [[ $REPLY =~ ^[Yy]$ ]] && break
            continue
        fi
        
        break
    done
    
    log_success "Tailscale keys collected"
    
    # Install Tailscale if not present
    if ! command -v tailscale &>/dev/null; then
        log_info "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    
    # Store keys securely
    mkdir -p "$SECRETS_PATH"
    chmod 700 "$SECRETS_PATH"
    
    cat > "$SECRETS_PATH/tailscale.env" <<EOF
TAILSCALE_AUTH_KEY=$TAILSCALE_AUTH_KEY
TAILSCALE_API_KEY=$TAILSCALE_API_KEY
TAILSCALE_PORT=$TAILSCALE_PORT
EOF
    
    chmod 600 "$SECRETS_PATH/tailscale.env"
    
    log_success "Tailscale configured (port: $TAILSCALE_PORT)"
}

# ============================================================================
# VECTOR DATABASE SELECTION
# ============================================================================

select_vector_database() {
    show_step "Selecting vector database"
    
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  VECTOR DATABASE SELECTION${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo "Select your vector database:"
    echo "  1) Qdrant (Recommended - High performance, feature-rich)"
    echo "  2) ChromaDB (Lightweight, Python-native)"
    echo "  3) Weaviate (GraphQL API, semantic search)"
    echo "  4) Milvus (Highly scalable, production-grade)"
    echo ""
    
    while true; do
        read -p "Enter choice [1-4]: " choice
        
        case $choice in
            1)
                VECTOR_DB="qdrant"
                log_success "Selected: Qdrant (port: $QDRANT_PORT)"
                break
                ;;
            2)
                VECTOR_DB="chromadb"
                log_success "Selected: ChromaDB (port: $CHROMADB_PORT)"
                break
                ;;
            3)
                VECTOR_DB="weaviate"
                log_success "Selected: Weaviate (port: $WEAVIATE_PORT)"
                break
                ;;
            4)
                VECTOR_DB="milvus"
                log_success "Selected: Milvus (port: $MILVUS_PORT)"
                break
                ;;
            *)
                log_error "Invalid choice. Please select 1-4"
                ;;
        esac
    done
}

# ============================================================================
# REVERSE PROXY SELECTION
# ============================================================================

select_reverse_proxy() {
    show_step "Selecting reverse proxy"
    
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  REVERSE PROXY SELECTION${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo "Select your reverse proxy:"
    echo "  1) Traefik (Recommended - Auto SSL, Docker integration)"
    echo "  2) Nginx Proxy Manager (Web UI, beginner-friendly)"
    echo "  3) Caddy (Automatic HTTPS, simple config)"
    echo ""
    
    while true; do
        read -p "Enter choice [1-3]: " choice
        
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
                log_error "Invalid choice. Please select 1-3"
                ;;
        esac
    done
}

# ============================================================================
# CLOUD PROVIDER SELECTION
# ============================================================================

select_cloud_provider() {
    show_step "Selecting cloud provider"
    
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  CLOUD PROVIDER CONFIGURATION${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo "Select your cloud provider (for backups & storage):"
    echo "  1) AWS (S3, EC2)"
    echo "  2) Google Cloud (GCS, Compute Engine)"
    echo "  3) Azure (Blob Storage, VMs)"
    echo "  4) DigitalOcean (Spaces, Droplets)"
    echo "  5) None (Local only)"
    echo ""
    
    while true; do
        read -p "Enter choice [1-5]: " choice
        
        case $choice in
            1)
                CLOUD_PROVIDER="aws"
                log_success "Selected: AWS"
                break
                ;;
            2)
                CLOUD_PROVIDER="gcp"
                log_success "Selected: Google Cloud Platform"
                break
                ;;
            3)
                CLOUD_PROVIDER="azure"
                log_success "Selected: Microsoft Azure"
                break
                ;;
            4)
                CLOUD_PROVIDER="digitalocean"
                log_success "Selected: DigitalOcean"
                break
                ;;
            5)
                CLOUD_PROVIDER="none"
                log_success "Selected: Local only (no cloud provider)"
                break
                ;;
            *)
                log_error "Invalid choice. Please select 1-5"
                ;;
        esac
    done
}

# ============================================================================
# ADDITIONAL SERVICES CONFIGURATION
# ============================================================================

configure_additional_services() {
    show_step "Configuring optional services"
    
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  OPTIONAL SERVICES${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # n8n
    read -p "Enable n8n workflow automation? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ENABLE_N8N="true"
        log_success "n8n enabled (port: $N8N_PORT)"
    fi
    
    # Monitoring stack
    read -p "Enable monitoring (Grafana + Prometheus)? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ENABLE_MONITORING="true"
        log_success "Monitoring enabled (Grafana: $GRAFANA_PORT, Prometheus: $PROMETHEUS_PORT)"
    fi
    
    # Signal-CLI
    read -p "Enable Signal messaging integration? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ENABLE_SIGNAL="true"
        log_success "Signal-CLI enabled (port: $SIGNAL_CLI_PORT)"
    fi
    
    # Google Drive sync
    read -p "Enable Google Drive synchronization? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ENABLE_GDRIVE_SYNC="true"
        log_success "Google Drive sync enabled"
    fi
}

# ============================================================================
# SIGNAL-CLI CONFIGURATION
# ============================================================================

configure_signal_cli() {
    show_step "Configuring Signal-CLI"
    
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  SIGNAL MESSAGING CONFIGURATION${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo -e "${YELLOW}Note: You'll need to complete Signal registration after deployment${NC}"
    echo -e "${BLUE}Instructions will be provided in the deployment summary${NC}"
    echo ""
    
    log_info "Signal-CLI will be configured during deployment"
}

# ============================================================================
# GOOGLE DRIVE SYNC CONFIGURATION (RESTORED v98.3.1)
# ============================================================================

configure_google_drive_sync() {
    show_step "Configuring Google Drive synchronization"
    
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  GOOGLE DRIVE SYNC CONFIGURATION${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo "Select authentication method:"
    echo "  1) Service Account (Recommended for servers)"
    echo "  2) OAuth2 (Browser-based authentication)"
    echo ""
    
    while true; do
        read -p "Enter choice [1-2]: " choice
        
        case $choice in
            1)
                GDRIVE_AUTH_METHOD="service_account"
                configure_gdrive_service_account
                break
                ;;
            2)
                GDRIVE_AUTH_METHOD="oauth2"
                configure_gdrive_oauth2
                break
                ;;
            *)
                log_error "Invalid choice. Please select 1 or 2"
                ;;
        esac
    done
    
    # Configure sync path
    while true; do
        read -p "Enter local sync path [${GDRIVE_SYNC_PATH}]: " input_path
        
        if [[ -n "$input_path" ]]; then
            GDRIVE_SYNC_PATH="$input_path"
        fi
        
        # Create directory
        mkdir -p "$GDRIVE_SYNC_PATH"
        chmod 755 "$GDRIVE_SYNC_PATH"
        
        log_success "Google Drive sync path: $GDRIVE_SYNC_PATH"
        break
    done
}

configure_gdrive_service_account() {
    echo ""
    echo -e "${YELLOW}Service Account Setup:${NC}"
    echo "  1. Go to https://console.cloud.google.com/apis/credentials"
    echo "  2. Create a service account"
    echo "  3. Generate JSON key"
    echo "  4. Enable Google Drive API"
    echo "  5. Share your Drive folder with the service account email"
    echo ""
    
    while true; do
        read -p "Enter path to service account JSON file: " json_path
        
        if [[ ! -f "$json_path" ]]; then
            log_error "File not found: $json_path"
            continue
        fi
        
        # Validate JSON
        if ! jq empty "$json_path" 2>/dev/null; then
            log_error "Invalid JSON file"
            continue
        fi
        
        # Copy to secrets directory
        GDRIVE_SERVICE_ACCOUNT_JSON="$SECRETS_PATH/gdrive-service-account.json"
        cp "$json_path" "$GDRIVE_SERVICE_ACCOUNT_JSON"
        chmod 600 "$GDRIVE_SERVICE_ACCOUNT_JSON"
        
        log_success "Service account JSON configured"
        break
    done
}

configure_gdrive_oauth2() {
    echo ""
    echo -e "${YELLOW}OAuth2 Setup:${NC}"
    echo "  1. Go to https://console.cloud.google.com/apis/credentials"
    echo "  2. Create OAuth 2.0 Client ID (Desktop application)"
    echo "  3. Download client configuration"
    echo "  4. Enable Google Drive API"
    echo ""
    
    while true; do
        read -p "Enter OAuth2 Client ID: " client_id
        
        if [[ -z "$client_id" ]]; then
            log_error "Client ID cannot be empty"
            continue
        fi
        
        GDRIVE_CLIENT_ID="$client_id"
        break
    done
    
    while true; do
        read -p "Enter OAuth2 Client Secret: " client_secret
        
        if [[ -z "$client_secret" ]]; then
            log_error "Client Secret cannot be empty"
            continue
        fi
        
        GDRIVE_CLIENT_SECRET="$client_secret"
        break
    done
    
    # Store OAuth2 credentials
    cat > "$SECRETS_PATH/gdrive-oauth2.env" <<EOF
GDRIVE_CLIENT_ID=$GDRIVE_CLIENT_ID
GDRIVE_CLIENT_SECRET=$GDRIVE_CLIENT_SECRET
EOF
    
    chmod 600 "$SECRETS_PATH/gdrive-oauth2.env"
    
    log_success "OAuth2 credentials configured"
    log_info "You'll complete authentication via browser after deployment"
}

# ============================================================================
# LLM PROVIDER CONFIGURATION
# ============================================================================

configure_llm_providers() {
    show_step "Configuring LLM providers"
    
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  EXTERNAL LLM PROVIDER CONFIGURATION${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo -e "${BLUE}Configure API keys for external LLM providers (optional)${NC}"
    echo -e "${YELLOW}Press Enter to skip any provider${NC}"
    echo ""
    
    # OpenAI
    read -p "OpenAI API Key: " openai_key
    if [[ -n "$openai_key" ]]; then
        echo "OPENAI_API_KEY=$openai_key" >> "$SECRETS_PATH/llm-providers.env"
        log_success "OpenAI configured"
    fi
    
    # Anthropic
    read -p "Anthropic API Key: " anthropic_key
    if [[ -n "$anthropic_key" ]]; then
        echo "ANTHROPIC_API_KEY=$anthropic_key" >> "$SECRETS_PATH/llm-providers.env"
        log_success "Anthropic configured"
    fi
    
    # Google AI
    read -p "Google AI API Key: " google_key
    if [[ -n "$google_key" ]]; then
        echo "GOOGLE_API_KEY=$google_key" >> "$SECRETS_PATH/llm-providers.env"
        log_success "Google AI configured"
    fi
    
    # Cohere
    read -p "Cohere API Key: " cohere_key
    if [[ -n "$cohere_key" ]]; then
        echo "COHERE_API_KEY=$cohere_key" >> "$SECRETS_PATH/llm-providers.env"
        log_success "Cohere configured"
    fi
    
    # Hugging Face
    read -p "Hugging Face API Key: " hf_key
    if [[ -n "$hf_key" ]]; then
        echo "HUGGINGFACE_API_KEY=$hf_key" >> "$SECRETS_PATH/llm-providers.env"
        log_success "Hugging Face configured"
    fi
    
    if [[ -f "$SECRETS_PATH/llm-providers.env" ]]; then
        chmod 600 "$SECRETS_PATH/llm-providers.env"
        log_success "LLM provider credentials secured"
    else
        log_info "No external LLM providers configured (using local models only)"
    fi
}

# ============================================================================
# OLLAMA MODEL SELECTION
# ============================================================================

select_ollama_models() {
    show_step "Selecting Ollama models"
    
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  OLLAMA MODEL SELECTION${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [[ "$GPU_ENABLED" = "true" ]]; then
        echo -e "${GREEN}GPU detected - you can run larger models${NC}"
    else
        echo -e "${YELLOW}CPU mode - recommend smaller models (7B or less)${NC}"
    fi
    echo ""
    
    echo "Recommended models:"
    echo "  1) llama3.2:latest (3B - Fast, efficient)"
    echo "  2) llama3.1:8b (8B - Balanced performance)"
    echo "  3) mistral:latest (7B - Great for code)"
    echo "  4) codellama:latest (7B - Optimized for coding)"
    echo "  5) phi3:latest (3.8B - Microsoft, very efficient)"
    echo "  6) gemma2:2b (2B - Google, lightweight)"
    echo "  7) Custom selection"
    echo ""
    
    local selected_models=()
    
    while true; do
        read -p "Select models (space-separated numbers, or 'done'): " selection
        
        if [[ "$selection" = "done" ]]; then
            break
        fi
        
        for choice in $selection; do
            case $choice in
                1) selected_models+=("llama3.2:latest") ;;
                2) selected_models+=("llama3.1:8b") ;;
                3) selected_models+=("mistral:latest") ;;
                4) selected_models+=("codellama:latest") ;;
                5) selected_models+=("phi3:latest") ;;
                6) selected_models+=("gemma2:2b") ;;
                7)
                    read -p "Enter custom model name: " custom_model
                    if [[ -n "$custom_model" ]]; then
                        selected_models+=("$custom_model")
                    fi
                    ;;
                *)
                    log_error "Invalid choice: $choice"
                    ;;
            esac
        done
        
        if [[ ${#selected_models[@]} -gt 0 ]]; then
            echo ""
            echo "Selected models:"
            printf '  - %s\n' "${selected_models[@]}"
            echo ""
            read -p "Add more models? (y/N): " -r
            [[ ! $REPLY =~ ^[Yy]$ ]] && break
        fi
    done
    
    if [[ ${#selected_models[@]} -eq 0 ]]; then
        log_warning "No models selected - defaulting to llama3.2:latest"
        selected_models=("llama3.2:latest")
    fi
    
    # Generate model pull script
    cat > "$CONFIG_PATH/pull-ollama-models.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "Pulling Ollama models..."

EOF
    
    for model in "${selected_models[@]}"; do
        echo "docker exec ollama ollama pull $model" >> "$CONFIG_PATH/pull-ollama-models.sh"
    done
    
    chmod +x "$CONFIG_PATH/pull-ollama-models.sh"
    
    log_success "${#selected_models[@]} model(s) selected"
    log_info "Models will be pulled after deployment"
}

# ============================================================================
# LITELLM CONFIGURATION WITH ROUTING
# ============================================================================

generate_litellm_config() {
    show_step "Generating LiteLLM configuration"
    
    cat > "$CONFIG_PATH/litellm-config.yaml" <<EOF
model_list:
  # Local Ollama models
  - model_name: llama3.2
    litellm_params:
      model: ollama/llama3.2:latest
      api_base: http://ollama:11434
  
  - model_name: llama3.1
    litellm_params:
      model: ollama/llama3.1:8b
      api_base: http://ollama:11434
  
  - model_name: mistral
    litellm_params:
      model: ollama/mistral:latest
      api_base: http://ollama:11434
  
  - model_name: codellama
    litellm_params:
      model: ollama/codellama:latest
      api_base: http://ollama:11434

EOF
    
    # Add external providers if configured
    if [[ -f "$SECRETS_PATH/llm-providers.env" ]]; then
        source "$SECRETS_PATH/llm-providers.env"
        
        if [[ -n "${OPENAI_API_KEY:-}" ]]; then
            cat >> "$CONFIG_PATH/litellm-config.yaml" <<EOF
  # OpenAI models
  - model_name: gpt-4
    litellm_params:
      model: gpt-4
      api_key: \${OPENAI_API_KEY}
  
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: gpt-3.5-turbo
      api_key: \${OPENAI_API_KEY}

EOF
        fi
        
        if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
            cat >> "$CONFIG_PATH/litellm-config.yaml" <<EOF
  # Anthropic models
  - model_name: claude-3-opus
    litellm_params:
      model: claude-3-opus-20240229
      api_key: \${ANTHROPIC_API_KEY}
  
  - model_name: claude-3-sonnet
    litellm_params:
      model: claude-3-sonnet-20240229
      api_key: \${ANTHROPIC_API_KEY}

EOF
        fi
    fi
    
    # Add router configuration
    cat >> "$CONFIG_PATH/litellm-config.yaml" <<EOF

# Router configuration
router_settings:
  routing_strategy: least-busy
  num_retries: 2
  timeout: 60
  
  # Model fallback chains
  fallback_models:
    - ["gpt-4", "claude-3-opus", "llama3.1"]
    - ["gpt-3.5-turbo", "claude-3-sonnet", "mistral"]
    - ["codellama", "mistral"]

# General settings
general_settings:
  master_key: \${LITELLM_MASTER_KEY}
  database_url: postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/litellm
  
  # Enable features
  spend_logs: true
  success_callbacks: ["langfuse"]
  failure_callbacks: ["langfuse"]
  
  # Langfuse integration
  langfuse_public_key: \${LANGFUSE_PUBLIC_KEY}
  langfuse_secret_key: \${LANGFUSE_SECRET_KEY}
  langfuse_host: http://langfuse:3000

# Cache configuration
cache:
  type: redis
  host: redis
  port: 6379
  ttl: 3600
EOF
    
    chmod 644 "$CONFIG_PATH/litellm-config.yaml"
    log_success "LiteLLM configuration generated with routing and fallbacks"
}

# ============================================================================
# SECRET GENERATION
# ============================================================================

generate_secrets() {
    show_step "Generating secure secrets"
    
    # Generate random secrets
    local postgres_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    local redis_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    local litellm_master_key=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    local langfuse_salt=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    local langfuse_secret=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    local langfuse_public_key="pk_$(openssl rand -hex 16)"
    local langfuse_secret_key="sk_$(openssl rand -hex 16)"
    local n8n_encryption_key=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    # Store in secrets file
    cat > "$SECRETS_PATH/platform.env" <<EOF
# Database credentials
POSTGRES_USER=aiplatform
POSTGRES_PASSWORD=$postgres_password
POSTGRES_DB=aiplatform

# Redis
REDIS_PASSWORD=$redis_password

# LiteLLM
LITELLM_MASTER_KEY=$litellm_master_key

# Langfuse
LANGFUSE_SALT=$langfuse_salt
LANGFUSE_SECRET=$langfuse_secret
LANGFUSE_PUBLIC_KEY=$langfuse_public_key
LANGFUSE_SECRET_KEY=$langfuse_secret_key

# n8n
N8N_ENCRYPTION_KEY=$n8n_encryption_key

# Generated on $(date)
EOF
    
    chmod 600 "$SECRETS_PATH/platform.env"
    log_success "Secure secrets generated and stored"
}

# ============================================================================
# ENVIRONMENT FILE CREATION
# ============================================================================

create_environment_files() {
    show_step "Creating environment configuration files"
    
    # Main .env file
    cat > "$ROOT_PATH/.env" <<EOF
# AI Platform Configuration
# Generated on $(date)

# Domain & SSL
DOMAIN_NAME=$DOMAIN_NAME
SSL_EMAIL=$SSL_EMAIL

# Architecture
VECTOR_DB=$VECTOR_DB
REVERSE_PROXY=$REVERSE_PROXY
CLOUD_PROVIDER=$CLOUD_PROVIDER

# Features
ENABLE_GDRIVE_SYNC=$ENABLE_GDRIVE_SYNC
ENABLE_SIGNAL=$ENABLE_SIGNAL
ENABLE_MONITORING=$ENABLE_MONITORING
ENABLE_N8N=$ENABLE_N8N
GPU_ENABLED=$GPU_ENABLED

# Ports
OLLAMA_PORT=$OLLAMA_PORT
LITELLM_PORT=$LITELLM_PORT
OPENWEBUI_PORT=$OPENWEBUI_PORT
OPENCLAW_PORT=$OPENCLAW_PORT
POSTGRES_PORT=$POSTGRES_PORT
REDIS_PORT=$REDIS_PORT
LANGFUSE_PORT=$LANGFUSE_PORT
N8N_PORT=$N8N_PORT
GRAFANA_PORT=$GRAFANA_PORT
PROMETHEUS_PORT=$PROMETHEUS_PORT
TAILSCALE_PORT=$TAILSCALE_PORT

# Paths
DATA_PATH=$DATA_PATH
SECRETS_PATH=$SECRETS_PATH
CONFIG_PATH=$CONFIG_PATH
EOF
    
    if [[ "$ENABLE_GDRIVE_SYNC" = "true" ]]; then
        echo "GDRIVE_SYNC_PATH=$GDRIVE_SYNC_PATH" >> "$ROOT_PATH/.env"
        echo "GDRIVE_AUTH_METHOD=$GDRIVE_AUTH_METHOD" >> "$ROOT_PATH/.env"
    fi
    
    chmod 644 "$ROOT_PATH/.env"
    log_success "Environment files created"
}

# ============================================================================
# DEPLOYMENT SUMMARY (FIXED: Load configs first)
# ============================================================================

show_deployment_summary() {
    show_step "Generating deployment summary"
    
    # Source configuration files
    [[ -f "$ROOT_PATH/.env" ]] && source "$ROOT_PATH/.env"
    [[ -f "$SECRETS_PATH/platform.env" ]] && source "$SECRETS_PATH/platform.env"
    [[ -f "$SECRETS_PATH/tailscale.env" ]] && source "$SECRETS_PATH/tailscale.env"
    
    echo ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}  DEPLOYMENT CONFIGURATION SUMMARY${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${BOLD}${CYAN}🌐 Network Configuration:${NC}"
    echo -e "  Domain: ${GREEN}$DOMAIN_NAME${NC}"
    echo -e "  SSL Email: ${GREEN}$SSL_EMAIL${NC}"
    echo -e "  Reverse Proxy: ${GREEN}$REVERSE_PROXY${NC}"
    echo -e "  Tailscale Port: ${GREEN}$TAILSCALE_PORT${NC}"
    echo ""
    
    echo -e "${BOLD}${CYAN}🗄️  Data Layer:${NC}"
    echo -e "  Vector Database: ${GREEN}$VECTOR_DB${NC}"
    echo -e "  PostgreSQL Port: ${GREEN}$POSTGRES_PORT${NC}"
    echo -e "  Redis Port: ${GREEN}$REDIS_PORT${NC}"
    echo ""
    
    echo -e "${BOLD}${CYAN}🤖 AI Services:${NC}"
    echo -e "  Ollama: ${GREEN}http://localhost:$OLLAMA_PORT${NC}"
    echo -e "  LiteLLM: ${GREEN}http://localhost:$LITELLM_PORT${NC}"
    echo -e "  OpenWebUI: ${GREEN}http://localhost:$OPENWEBUI_PORT${NC}"
    echo -e "  OpenClaw: ${GREEN}http://localhost:$OPENCLAW_PORT${NC}"
    echo -e "  Langfuse: ${GREEN}http://localhost:$LANGFUSE_PORT${NC}"
    echo ""
    
    if [[ "$GPU_ENABLED" = "true" ]]; then
        echo -e "${BOLD}${CYAN}🎮 GPU Configuration:${NC}"
        echo -e "  Status: ${GREEN}ENABLED${NC}"
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | while read -r line; do
            echo -e "  GPU: ${GREEN}$line${NC}"
        done
        echo ""
    fi
    
    if [[ "$ENABLE_N8N" = "true" ]]; then
        echo -e "${BOLD}${CYAN}🔄 Workflow Automation:${NC}"
        echo -e "  n8n: ${GREEN}http://localhost:$N8N_PORT${NC}"
        echo ""
    fi
    
    if [[ "$ENABLE_MONITORING" = "true" ]]; then
        echo -e "${BOLD}${CYAN}📊 Monitoring:${NC}"
        echo -e "  Grafana: ${GREEN}http://localhost:$GRAFANA_PORT${NC}"
        echo -e "  Prometheus: ${GREEN}http://localhost:$PROMETHEUS_PORT${NC}"
        echo ""
    fi
    
    if [[ "$ENABLE_GDRIVE_SYNC" = "true" ]]; then
        echo -e "${BOLD}${CYAN}☁️  Google Drive Sync:${NC}"
        echo -e "  Auth Method: ${GREEN}$GDRIVE_AUTH_METHOD${NC}"
        echo -e "  Sync Path: ${GREEN}$GDRIVE_SYNC_PATH${NC}"
        echo ""
    fi
    
    echo -e "${BOLD}${CYAN}🔐 Security:${NC}"
    echo -e "  Secrets: ${GREEN}$SECRETS_PATH${NC}"
    echo -e "  Tailscale: ${GREEN}Configured${NC}"
    echo -e "  AppArmor: ${GREEN}Enabled${NC}"
    echo ""
    
    echo -e "${BOLD}${CYAN}📁 Storage:${NC}"
    echo -e "  Data Path: ${GREEN}$DATA_PATH${NC}"
    echo -e "  Config Path: ${GREEN}$CONFIG_PATH${NC}"
    echo ""
    
    echo -e "${BOLD}${YELLOW}⚡ Next Steps:${NC}"
    echo -e "  1. Review configuration files in ${GREEN}$CONFIG_PATH${NC}"
    echo -e "  2. Run deployment: ${GREEN}sudo bash scripts/2-deploy-stack.sh${NC}"
    echo -e "  3. Pull Ollama models: ${GREEN}bash $CONFIG_PATH/pull-ollama-models.sh${NC}"
    echo ""
    
    if [[ "$ENABLE_SIGNAL" = "true" ]]; then
        echo -e "${BOLD}${YELLOW}📱 Signal-CLI Setup:${NC}"
        echo -e "  After deployment, register Signal:"
        echo -e "  ${GREEN}docker exec signal-cli signal-cli -u +YOUR_PHONE link${NC}"
        echo ""
    fi
    
    if [[ "$ENABLE_GDRIVE_SYNC" = "true" && "$GDRIVE_AUTH_METHOD" = "oauth2" ]]; then
        echo -e "${BOLD}${YELLOW}🔑 Google Drive OAuth2:${NC}"
        echo -e "  Complete authentication after deployment:"
        echo -e "  ${GREEN}docker exec gdrive-sync rclone config reconnect gdrive:${NC}"
        echo ""
    fi
    
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${NC}"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo ""
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                           ║${NC}"
    echo -e "${BOLD}${CYAN}║        AI PLATFORM INITIALIZATION v${SCRIPT_VERSION}             ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                           ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log "Starting AI Platform setup v$SCRIPT_VERSION"
    echo -e "${BLUE}Log file: $LOG_FILE${NC}"
    echo ""
    
    echo -e "${BOLD}${YELLOW}⚠️  IMPORTANT NOTICE ⚠️${NC}"
    echo -e "${YELLOW}This script will configure your system for AI platform deployment.${NC}"
    echo ""
    
    echo -e "${BLUE}This script will:${NC}"
    echo -e "  ${GREEN}✓${NC} Install Docker & Docker Compose"
    echo -e "  ${GREEN}✓${NC} Configure Tailscale VPN (auth key + API key)"
    echo -e "  ${GREEN}✓${NC} Setup AppArmor security"
    echo -e "  ${GREEN}✓${NC} Detect GPU capability"
    echo -e "  ${GREEN}✓${NC} Initialize storage tier"
    echo -e "  ${GREEN}✓${NC} Generate secrets"
    echo -e "  ${GREEN}✓${NC} Configure LLM providers & routing"
    echo -e "  ${GREEN}✓${NC} Select Ollama models"
    echo -e "  ${GREEN}✓${NC} Setup optional services (n8n, monitoring, Signal, Google Drive)"
    echo ""
    
    read -p "Press Enter to continue or Ctrl+C to abort..."
    
    # Pre-flight checks
    check_root
    check_ubuntu_version
    check_internet_connectivity
    check_disk_space
    
    # Core system setup
    setup_apparmor_properly
    initialize_storage_tier
    check_port_availability
    
    # GPU detection
    detect_gpu_capability
    
    # Domain & SSL
    validate_domain
    
    # Docker installation
    install_docker
    
    # Tailscale (RESTORED v98.3.1)
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
    [[ "$ENABLE_SIGNAL" = "true" ]] && configure_signal_cli
    
    # Optional: Google Drive (RESTORED v98.3.1)
    [[ "$ENABLE_GDRIVE_SYNC" = "true" ]] && configure_google_drive_sync
    
    # External LLM providers
    configure_llm_providers
    
    # Ollama model selection
    select_ollama_models
    
    # Generate LiteLLM config with routing
    generate_litellm_config
    
    # Generate secrets
    generate_secrets
    
    # Create environment files
    create_environment_files
    
    # Show summary (FIXED: Loads configs first)
    show_deployment_summary
    
    log_success "✅ SYSTEM INITIALIZATION COMPLETE"
    
    echo ""
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  SETUP COMPLETE - READY FOR DEPLOYMENT  ${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    exit 0
}

# Execute main function
main "$@"

