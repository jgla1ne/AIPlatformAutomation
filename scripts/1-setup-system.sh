#!/usr/bin/env bash

################################################################################
# SCRIPT 1 v98.1.0 - AI PLATFORM SYSTEM INITIALIZATION
# FIXED: Tailscale AppArmor snap profile handling
################################################################################

set -uo pipefail

# ============================================================================
# CONSTANTS & CONFIGURATION
# ============================================================================

readonly SCRIPT_VERSION="98.1.0"
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

# Configuration variables (will be populated)
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
# LOGGING FUNCTIONS
# ============================================================================

log_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local message="$1"
    echo "" | tee -a "$LOG_FILE"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}  [${CURRENT_STEP}/${TOTAL_STEPS}] ${message}${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}   ✓ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}   ✗ ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}   ⚠ WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}   ℹ $1${NC}" | tee -a "$LOG_FILE"
}

log_section() {
    local title="$1"
    echo "" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}${BOLD}║  ${title}${NC}" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_ubuntu_version() {
    log_step "CHECKING UBUNTU VERSION"
    
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot determine OS version"
        exit 1
    fi
    
    source /etc/os-release
    
    if [ "$ID" != "ubuntu" ]; then
        log_error "This script requires Ubuntu (detected: ${ID})"
        exit 1
    fi
    
    local version_major="${VERSION_ID%%.*}"
    
    if [ "$version_major" -lt 22 ]; then
        log_error "Ubuntu 22.04 LTS or newer required (detected: ${VERSION_ID})"
        exit 1
    fi
    
    log_success "Ubuntu ${VERSION_ID} detected"
}

check_internet_connectivity() {
    log_step "CHECKING INTERNET CONNECTIVITY"
    
    local test_hosts=("8.8.8.8" "1.1.1.1" "github.com")
    local connected=false
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
            connected=true
            break
        fi
    done
    
    if [ "$connected" = false ]; then
        log_error "No internet connectivity detected"
        exit 1
    fi
    
    log_success "Internet connectivity verified"
}

# ============================================================================
# APPARMOR MANAGEMENT (CRITICAL FOR TAILSCALE)
# ============================================================================

check_apparmor_kernel() {
    log_info "Checking AppArmor kernel support..."
    
    # Check if AppArmor is enabled in kernel
    if [ ! -d /sys/kernel/security/apparmor ]; then
        log_warning "AppArmor not enabled in kernel"
        return 1
    fi
    
    # Check if AppArmor module is loaded
    if ! lsmod | grep -q apparmor; then
        log_warning "AppArmor kernel module not loaded"
        return 1
    fi
    
    log_success "AppArmor kernel support detected"
    return 0
}

setup_apparmor_for_snap() {
    log_info "Setting up AppArmor for snap packages..."
    
    # Ensure AppArmor is installed
    if ! dpkg -l | grep -q apparmor; then
        log_info "Installing AppArmor..."
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            apparmor apparmor-utils apparmor-profiles \
            >/dev/null 2>&1
    fi
    
    # Check kernel support
    if ! check_apparmor_kernel; then
        log_warning "AppArmor kernel support missing - using permissive mode"
        
        # Put snap profiles in complain mode (permissive)
        if [ -d /var/lib/snapd/apparmor/profiles ]; then
            log_info "Setting snap AppArmor profiles to complain mode..."
            
            # Reload snap profiles in complain mode
            for profile in /var/lib/snapd/apparmor/profiles/snap.*; do
                if [ -f "$profile" ]; then
                    apparmor_parser -R "$profile" 2>/dev/null || true
                    apparmor_parser -C "$profile" 2>/dev/null || true
                fi
            done
        fi
        
        # Disable AppArmor enforcement for snaps
        if [ -f /etc/apparmor.d/usr.lib.snapd.snap-confine.real ]; then
            ln -sf /etc/apparmor.d/usr.lib.snapd.snap-confine.real \
                   /etc/apparmor.d/disable/ 2>/dev/null || true
            apparmor_parser -R /etc/apparmor.d/usr.lib.snapd.snap-confine.real 2>/dev/null || true
        fi
        
        log_warning "AppArmor set to permissive mode for snaps"
        return 0
    fi
    
    # AppArmor kernel support exists - enable properly
    log_info "Enabling AppArmor service..."
    
    systemctl unmask apparmor.service 2>/dev/null || true
    systemctl enable apparmor.service 2>/dev/null || true
    systemctl start apparmor.service 2>/dev/null || true
    
    # Wait for service to be ready
    sleep 2
    
    if systemctl is-active --quiet apparmor.service; then
        log_success "AppArmor service active"
        
        # Reload snap profiles
        if [ -d /var/lib/snapd/apparmor/profiles ]; then
            log_info "Loading snap AppArmor profiles..."
            
            for profile in /var/lib/snapd/apparmor/profiles/snap.*; do
                if [ -f "$profile" ]; then
                    apparmor_parser -r "$profile" 2>/dev/null || true
                fi
            done
            
            log_success "Snap profiles loaded"
        fi
    else
        log_warning "AppArmor service failed to start - using permissive mode"
    fi
    
    return 0
}

# ============================================================================
# STORAGE TIER INITIALIZATION
# ============================================================================

initialize_storage_tier() {
    log_step "INITIALIZING STORAGE TIER"
    
    log_info "Creating directory structure in ${DATA_PATH}..."
    
    # Core directories
    local directories=(
        # Database tier
        "${DATA_PATH}/postgres"
        "${DATA_PATH}/redis"
        
        # Vector databases
        "${DATA_PATH}/qdrant"
        "${DATA_PATH}/weaviate"
        "${DATA_PATH}/chroma"
        
        # LLM services
        "${DATA_PATH}/litellm/config"
        "${DATA_PATH}/litellm/logs"
        "${DATA_PATH}/openclaw/config"
        "${DATA_PATH}/openclaw/logs"
        
        # Workflow & monitoring
        "${DATA_PATH}/n8n"
        "${DATA_PATH}/prometheus"
        "${DATA_PATH}/grafana"
        "${DATA_PATH}/loki"
        
        # Integration services
        "${DATA_PATH}/signal-cli"
        "${DATA_PATH}/langfuse"
        
        # Storage & sync
        "${DATA_PATH}/gdrive-sync"
        "${DATA_PATH}/backups"
        
        # Logs & metrics
        "${DATA_PATH}/logs/nginx"
        "${DATA_PATH}/logs/caddy"
        "${DATA_PATH}/logs/openclaw"
        "${DATA_PATH}/logs/litellm"
        
        # Configuration
        "${DATA_PATH}/config"
        "${DATA_PATH}/secrets"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir" 2>/dev/null || true
        chmod 755 "$dir" 2>/dev/null || true
    done
    
    log_success "Created ${#directories[@]} directories"
    
    # Create secrets directory at root level
    mkdir -p "$SECRETS_PATH" 2>/dev/null || true
    chmod 700 "$SECRETS_PATH" 2>/dev/null || true
    
    mkdir -p "$CONFIG_PATH" 2>/dev/null || true
    chmod 755 "$CONFIG_PATH" 2>/dev/null || true
    
    log_success "Storage tier initialized"
}

# ============================================================================
# PORT AVAILABILITY CHECK
# ============================================================================

check_port_availability() {
    log_step "CHECKING PORT AVAILABILITY"
    
    log_info "Scanning required ports..."
    
    local required_ports=(
        80      # HTTP (Caddy/Nginx)
        443     # HTTPS (Caddy/Nginx)
        5432    # PostgreSQL
        6379    # Redis
        6333    # Qdrant
        8080    # Weaviate
        8000    # Chroma
        4000    # LiteLLM
        8001    # OpenClaw
        5678    # N8N
        9090    # Prometheus
        3000    # Grafana
        3100    # Loki
        3001    # Langfuse
    )
    
    local ports_in_use=()
    
    for port in "${required_ports[@]}"; do
        if ss -tuln | grep -q ":${port} "; then
            ports_in_use+=("$port")
            log_warning "Port ${port} is already in use"
        else
            log_success "Port ${port} available"
        fi
    done
    
    if [ ${#ports_in_use[@]} -gt 0 ]; then
        log_warning "${#ports_in_use[@]} ports in use: ${ports_in_use[*]}"
        
        read -p "Continue anyway? (yes/no): " CONTINUE_WITH_PORTS
        
        if [ "$CONTINUE_WITH_PORTS" != "yes" ]; then
            log_error "Port conflicts detected - aborting"
            exit 1
        fi
    else
        log_success "All required ports available"
    fi
}

# ============================================================================
# DOMAIN VALIDATION
# ============================================================================

validate_domain() {
    log_step "VALIDATING DOMAIN"
    
    while true; do
        read -p "❯ Enter your domain name (e.g., example.com): " DOMAIN_NAME
        
        # Basic validation
        if [[ ! "$DOMAIN_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$ ]]; then
            log_error "Invalid domain format"
            continue
        fi
        
        log_success "Domain: ${DOMAIN_NAME}"
        
        # DNS check
        log_info "Checking DNS resolution..."
        
        if host "$DOMAIN_NAME" >/dev/null 2>&1; then
            local resolved_ip
            resolved_ip=$(host "$DOMAIN_NAME" | grep "has address" | head -1 | awk '{print $NF}')
            log_success "DNS resolves to: ${resolved_ip}"
        else
            log_warning "DNS does not resolve yet (configure after setup)"
        fi
        
        break
    done
    
    # Get SSL email
    while true; do
        read -p "❯ Enter email for SSL certificates: " SSL_EMAIL
        
        if [[ "$SSL_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log_success "Email: ${SSL_EMAIL}"
            break
        else
            log_error "Invalid email format"
        fi
    done
    
    # Save configuration
    cat > "${CONFIG_PATH}/domain.conf" <<EOF
DOMAIN_NAME="${DOMAIN_NAME}"
SSL_EMAIL="${SSL_EMAIL}"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    log_success "Domain configuration saved"
}

# ============================================================================
# DOCKER INSTALLATION
# ============================================================================

install_docker() {
    log_step "INSTALLING DOCKER"
    
    if command -v docker >/dev/null 2>&1; then
        local docker_version
        docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_success "Docker already installed: ${docker_version}"
        return 0
    fi
    
    log_info "Installing Docker from official repository..."
    
    # Install prerequisites
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        >/dev/null 2>&1
    
    # Add Docker GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    
    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
        >/dev/null 2>&1
    
    # Enable and start Docker
    systemctl enable docker 2>/dev/null || true
    systemctl start docker 2>/dev/null || true
    
    # Verify installation
    if docker --version >/dev/null 2>&1; then
        local docker_version
        docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_success "Docker installed: ${docker_version}"
    else
        log_error "Docker installation failed"
        exit 1
    fi
    
    # Install Docker Compose
    if docker compose version >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker compose version | awk '{print $4}')
        log_success "Docker Compose installed: ${compose_version}"
    else
        log_error "Docker Compose installation failed"
        exit 1
    fi
}

# ============================================================================
# TAILSCALE SETUP (WITH APPARMOR FIX)
# ============================================================================

setup_tailscale() {
    log_step "CONFIGURING TAILSCALE VPN"
    
    log_info "Tailscale provides secure access without UFW"
    log_info "Cloud provider firewall handles perimeter security"
    
    # Setup AppArmor for snap packages (CRITICAL FIX)
    setup_apparmor_for_snap
    
    # Check if Tailscale is already installed
    if command -v tailscale >/dev/null 2>&1; then
        log_info "Tailscale already installed"
        
        # Check if already authenticated
        if tailscale status >/dev/null 2>&1; then
            log_success "Tailscale already authenticated"
            return 0
        fi
    else
        log_info "Installing Tailscale..."
        
        # Install Tailscale via snap (requires AppArmor fix)
        snap install tailscale 2>&1 | tee -a "$LOG_FILE" || {
            log_error "Tailscale snap installation failed"
            log_info "Falling back to apt installation..."
            
            # Fallback to apt installation
            curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | \
                tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
            
            curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | \
                tee /etc/apt/sources.list.d/tailscale.list
            
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y tailscale >/dev/null 2>&1
        }
        
        # Enable and start Tailscale
        systemctl enable tailscaled 2>/dev/null || true
        systemctl start tailscaled 2>/dev/null || true
        
        sleep 3
        
        log_success "Tailscale installed"
    fi
    
    # Authenticate Tailscale
    log_info "Authenticating Tailscale..."
    
    echo ""
    read -p "❯ Enter Tailscale auth key (or press Enter to authenticate manually): " TAILSCALE_AUTH_KEY
    echo ""
    
    if [ -n "$TAILSCALE_AUTH_KEY" ]; then
        log_info "Authenticating with auth key..."
        
        # Authenticate with key
        if tailscale up --authkey="$TAILSCALE_AUTH_KEY" --accept-routes 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Tailscale authenticated successfully"
        else
            log_error "Tailscale authentication failed"
            log_info "Trying manual authentication..."
            
            tailscale up --accept-routes 2>&1 | tee -a "$LOG_FILE" || {
                log_error "Manual authentication also failed"
                log_warning "Continue without Tailscale (not recommended)"
                read -p "Continue? (yes/no): " CONTINUE_WITHOUT_TAILSCALE
                
                if [ "$CONTINUE_WITHOUT_TAILSCALE" != "yes" ]; then
                    exit 1
                fi
            }
        fi
    else
        log_info "Starting manual authentication..."
        log_info "Follow the URL to authenticate in your browser"
        echo ""
        
        tailscale up --accept-routes 2>&1 | tee -a "$LOG_FILE" || {
            log_error "Manual authentication failed"
            log_warning "Continue without Tailscale (not recommended)"
            read -p "Continue? (yes/no): " CONTINUE_WITHOUT_TAILSCALE
            
            if [ "$CONTINUE_WITHOUT_TAILSCALE" != "yes" ]; then
                exit 1
            fi
        }
    fi
    
    # Verify Tailscale status
    sleep 2
    
    if tailscale status >/dev/null 2>&1; then
        local tailscale_ip
        tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "N/A")
        log_success "Tailscale IP: ${tailscale_ip}"
        
        # Save configuration
        cat > "${CONFIG_PATH}/tailscale.conf" <<EOF
TAILSCALE_ENABLED="true"
TAILSCALE_IP="${tailscale_ip}"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    else
        log_warning "Tailscale not fully configured"
        
        cat > "${CONFIG_PATH}/tailscale.conf" <<EOF
TAILSCALE_ENABLED="false"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    fi
}

# ============================================================================
# VECTOR DATABASE SELECTION
# ============================================================================

select_vector_database() {
    log_step "SELECTING VECTOR DATABASE"
    
    echo ""
    echo "Available vector databases:"
    echo "  1) Qdrant (recommended - fastest, Rust-based)"
    echo "  2) Weaviate (feature-rich, GraphQL)"
    echo "  3) Chroma (lightweight, Python-based)"
    echo ""
    
    while true; do
        read -p "❯ Select vector database (1-3): " VDB_CHOICE
        
        case "$VDB_CHOICE" in
            1)
                VECTOR_DB="qdrant"
                log_success "Selected: Qdrant"
                break
                ;;
            2)
                VECTOR_DB="weaviate"
                log_success "Selected: Weaviate"
                break
                ;;
            3)
                VECTOR_DB="chroma"
                log_success "Selected: Chroma"
                break
                ;;
            *)
                log_error "Invalid selection"
                ;;
        esac
    done
    
    # Save configuration
    cat > "${CONFIG_PATH}/vector-db.conf" <<EOF
VECTOR_DB="${VECTOR_DB}"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    log_success "Vector database configuration saved"
}

# ============================================================================
# REVERSE PROXY SELECTION
# ============================================================================

select_reverse_proxy() {
    log_step "SELECTING REVERSE PROXY"
    
    echo ""
    echo "Available reverse proxies:"
    echo "  1) Caddy (recommended - automatic HTTPS)"
    echo "  2) Nginx (traditional, high-performance)"
    echo ""
    
    while true; do
        read -p "❯ Select reverse proxy (1-2): " PROXY_CHOICE
        
        case "$PROXY_CHOICE" in
            1)
                REVERSE_PROXY="caddy"
                log_success "Selected: Caddy"
                break
                ;;
            2)
                REVERSE_PROXY="nginx"
                log_success "Selected: Nginx"
                break
                ;;
            *)
                log_error "Invalid selection"
                ;;
        esac
    done
    
    # Save configuration
    cat > "${CONFIG_PATH}/reverse-proxy.conf" <<EOF
REVERSE_PROXY="${REVERSE_PROXY}"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    log_success "Reverse proxy configuration saved"
}

# ============================================================================
# CLOUD PROVIDER CONFIGURATION
# ============================================================================

configure_cloud_provider() {
    log_step "CONFIGURING CLOUD PROVIDER"
    
    echo ""
    echo "Cloud providers:"
    echo "  1) OVH Cloud"
    echo "  2) AWS"
    echo "  3) Google Cloud"
    echo "  4) Azure"
    echo "  5) Other/On-premises"
    echo ""
    
    while true; do
        read -p "❯ Select cloud provider (1-5): " CLOUD_CHOICE
        
        case "$CLOUD_CHOICE" in
            1)
                CLOUD_PROVIDER="ovh"
                log_success "Selected: OVH Cloud"
                break
                ;;
            2)
                CLOUD_PROVIDER="aws"
                log_success "Selected: AWS"
                break
                ;;
            3)
                CLOUD_PROVIDER="gcp"
                log_success "Selected: Google Cloud"
                break
                ;;
            4)
                CLOUD_PROVIDER="azure"
                log_success "Selected: Azure"
                break
                ;;
            5)
                CLOUD_PROVIDER="other"
                log_success "Selected: Other/On-premises"
                break
                ;;
            *)
                log_error "Invalid selection"
                ;;
        esac
    done
    
    # Display firewall configuration instructions
    echo ""
    log_info "IMPORTANT: Configure your cloud firewall"
    echo ""
    
    case "$CLOUD_PROVIDER" in
        ovh)
            echo "  OVH Cloud Firewall Rules:"
            echo "  - Allow TCP 80 (HTTP)"
            echo "  - Allow TCP 443 (HTTPS)"
            echo "  - Allow Tailscale UDP 41641"
            echo "  - Block all other inbound traffic"
            ;;
        aws)
            echo "  AWS Security Group Rules:"
            echo "  - Inbound: TCP 80 from 0.0.0.0/0"
            echo "  - Inbound: TCP 443 from 0.0.0.0/0"
            echo "  - Inbound: UDP 41641 from 0.0.0.0/0 (Tailscale)"
            ;;
        gcp)
            echo "  GCP Firewall Rules:"
            echo "  - allow-http: TCP 80 from 0.0.0.0/0"
            echo "  - allow-https: TCP 443 from 0.0.0.0/0"
            echo "  - allow-tailscale: UDP 41641 from 0.0.0.0/0"
            ;;
        azure)
            echo "  Azure NSG Rules:"
            echo "  - AllowHTTP: TCP 80 Inbound"
            echo "  - AllowHTTPS: TCP 443 Inbound"
            echo "  - AllowTailscale: UDP 41641 Inbound"
            ;;
        other)
            echo "  Required open ports:"
            echo "  - TCP 80 (HTTP)"
            echo "  - TCP 443 (HTTPS)"
            echo "  - UDP 41641 (Tailscale)"
            ;;
    esac
    
    echo ""
    read -p "Press Enter when firewall is configured..."
    
    # Save configuration
    cat > "${CONFIG_PATH}/cloud-provider.conf" <<EOF
CLOUD_PROVIDER="${CLOUD_PROVIDER}"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    log_success "Cloud provider configuration saved"
}

# ============================================================================
# GOOGLE DRIVE SYNC SETUP
# ============================================================================

setup_google_drive_sync() {
    log_step "CONFIGURING GOOGLE DRIVE SYNC (OPTIONAL)"
    
    echo ""
    read -p "❯ Enable Google Drive sync? (yes/no): " ENABLE_GDRIVE
    
    if [ "$ENABLE_GDRIVE" != "yes" ]; then
        log_info "Google Drive sync disabled"
        ENABLE_GDRIVE_SYNC="false"
        return 0
    fi
    
    ENABLE_GDRIVE_SYNC="true"
    
    log_info "Installing rclone..."
    
    if ! command -v rclone >/dev/null 2>&1; then
        curl https://rclone.org/install.sh | bash 2>&1 | tee -a "$LOG_FILE"
    fi
    
    log_info "Configuring Google Drive..."
    
    echo ""
    echo "Choose configuration method:"
    echo "  1) Manual OAuth (enter credentials)"
    echo "  2) Remote configuration (use URL)"
    echo ""
    
    read -p "❯ Select method (1-2): " RCLONE_METHOD
    
    case "$RCLONE_METHOD" in
        1)
            log_info "Starting manual OAuth configuration..."
            log_info "Follow the prompts to authenticate"
            echo ""
            
            rclone config create gdrive drive \
                scope=drive \
                2>&1 | tee -a "$LOG_FILE"
            ;;
        2)
            log_info "Use this URL to generate configuration:"
            echo ""
            echo "  https://rclone.org/remote_setup/"
            echo ""
            read -p "Press Enter after completing remote configuration..."
            ;;
    esac
    
    # Verify configuration
    if rclone listremotes | grep -q "gdrive:"; then
        log_success "Google Drive configured successfully"
        
        # Save configuration
        cat > "${CONFIG_PATH}/gdrive.conf" <<EOF
ENABLE_GDRIVE_SYNC="true"
GDRIVE_REMOTE="gdrive"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    else
        log_warning "Google Drive configuration incomplete"
        ENABLE_GDRIVE_SYNC="false"
    fi
}

# ============================================================================
# SIGNAL-CLI SETUP
# ============================================================================

setup_signal_cli() {
    log_step "CONFIGURING SIGNAL-CLI (OPTIONAL)"
    
    echo ""
    read -p "❯ Enable Signal notifications? (yes/no): " ENABLE_SIGNAL_INPUT
    
    if [ "$ENABLE_SIGNAL_INPUT" != "yes" ]; then
        log_info "Signal notifications disabled"
        ENABLE_SIGNAL="false"
        return 0
    fi
    
    ENABLE_SIGNAL="true"
    
    log_info "Signal-CLI will be configured via Docker container"
    log_info "Configuration options:"
    echo ""
    echo "  1) Link via QR code (scan with existing Signal app)"
    echo "  2) Register new phone number (requires SMS verification)"
    echo "  3) Configure later (manual setup)"
    echo ""
    
    read -p "❯ Select method (1-3): " SIGNAL_METHOD
    
    case "$SIGNAL_METHOD" in
        1)
            log_info "QR code linking will be available after container starts"
            log_info "Run: docker logs signal-api (to get QR code)"
            SIGNAL_SETUP_METHOD="qr"
            ;;
        2)
            log_info "Phone registration will be available after container starts"
            log_info "Run: docker exec -it signal-api signal-cli -a +YOUR_PHONE register"
            SIGNAL_SETUP_METHOD="phone"
            ;;
        3)
            log_info "Manual configuration deferred"
            SIGNAL_SETUP_METHOD="manual"
            ;;
    esac
    
    # Save configuration
    cat > "${CONFIG_PATH}/signal.conf" <<EOF
ENABLE_SIGNAL="true"
SIGNAL_SETUP_METHOD="${SIGNAL_SETUP_METHOD}"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    log_success "Signal-CLI configuration saved"
}

# ============================================================================
# EXTERNAL LLM PROVIDERS
# ============================================================================

configure_llm_providers() {
    log_step "CONFIGURING EXTERNAL LLM PROVIDERS"
    
    log_info "Select LLM providers to enable (space-separated):"
    echo ""
    echo "Available providers:"
    echo "  1) OpenAI"
    echo "  2) Anthropic (Claude)"
    echo "  3) Google (Gemini)"
    echo "  4) DeepSeek"
    echo "  5) Groq"
    echo "  6) OpenRouter (aggregator)"
    echo ""
    
    declare -A PROVIDER_KEYS
    
    read -p "❯ Select providers (e.g., '1 2 3'): " PROVIDER_CHOICES
    
    for choice in $PROVIDER_CHOICES; do
        case "$choice" in
            1)
                log_info "Configuring OpenAI..."
                read -p "❯ Enter OpenAI API key: " OPENAI_KEY
                PROVIDER_KEYS["OPENAI_API_KEY"]="$OPENAI_KEY"
                log_success "OpenAI configured"
                ;;
            2)
                log_info "Configuring Anthropic..."
                read -p "❯ Enter Anthropic API key: " ANTHROPIC_KEY
                PROVIDER_KEYS["ANTHROPIC_API_KEY"]="$ANTHROPIC_KEY"
                log_success "Anthropic configured"
                ;;
            3)
                log_info "Configuring Google Gemini..."
                read -p "❯ Enter Google API key: " GOOGLE_KEY
                PROVIDER_KEYS["GOOGLE_API_KEY"]="$GOOGLE_KEY"
                log_success "Google configured"
                ;;
            4)
                log_info "Configuring DeepSeek..."
                read -p "❯ Enter DeepSeek API key: " DEEPSEEK_KEY
                PROVIDER_KEYS["DEEPSEEK_API_KEY"]="$DEEPSEEK_KEY"
                log_success "DeepSeek configured"
                ;;
            5)
                log_info "Configuring Groq..."
                read -p "❯ Enter Groq API key: " GROQ_KEY
                PROVIDER_KEYS["GROQ_API_KEY"]="$GROQ_KEY"
                log_success "Groq configured"
                ;;
            6)
                log_info "Configuring OpenRouter..."
                read -p "❯ Enter OpenRouter API key: " OPENROUTER_KEY
                PROVIDER_KEYS["OPENROUTER_API_KEY"]="$OPENROUTER_KEY"
                log_success "OpenRouter configured"
                ;;
        esac
    done
    
    # Save to secrets file
    for key in "${!PROVIDER_KEYS[@]}"; do
        echo "${key}=\"${PROVIDER_KEYS[$key]}\"" >> "${SECRETS_PATH}/llm-providers.env"
    done
    
    chmod 600 "${SECRETS_PATH}/llm-providers.env"
    
    log_success "LLM providers configured"
}

# ============================================================================
# SECRET GENERATION
# ============================================================================

generate_secret() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

generate_secrets() {
    log_step "GENERATING SECRETS"
    
    log_info "Generating secure passwords and API keys..."
    
    # Generate all secrets
    local POSTGRES_PASSWORD=$(generate_secret)
    local REDIS_PASSWORD=$(generate_secret)
    local LITELLM_MASTER_KEY=$(generate_secret)
    local OPENCLAW_API_KEY=$(generate_secret)
    local N8N_ENCRYPTION_KEY=$(generate_secret)
    local LANGFUSE_SALT=$(generate_secret)
    local JWT_SECRET=$(generate_secret)
    
    # Save to secrets file
    cat > "${SECRETS_PATH}/generated.env" <<EOF
# Auto-generated secrets - $(date -u +%Y-%m-%dT%H:%M:%SZ)
# DO NOT COMMIT TO VERSION CONTROL

# Database passwords
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
REDIS_PASSWORD="${REDIS_PASSWORD}"

# LLM service keys
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY}"
OPENCLAW_API_KEY="${OPENCLAW_API_KEY}"

# Workflow automation
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY}"

# Monitoring & observability
LANGFUSE_SALT="${LANGFUSE_SALT}"

# General
JWT_SECRET="${JWT_SECRET}"
EOF
    
    chmod 600 "${SECRETS_PATH}/generated.env"
    
    log_success "Generated 7 secure secrets"
    log_warning "BACKUP THIS FILE: ${SECRETS_PATH}/generated.env"
}

# ============================================================================
# ENVIRONMENT FILE CREATION
# ============================================================================

create_environment_files() {
    log_step "CREATING ENVIRONMENT FILES"
    
    log_info "Generating master .env file..."
    
    # Source all configuration files
    source "${CONFIG_PATH}/domain.conf"
    source "${CONFIG_PATH}/vector-db.conf"
    source "${CONFIG_PATH}/reverse-proxy.conf"
    source "${CONFIG_PATH}/cloud-provider.conf"
    source "${SECRETS_PATH}/generated.env"
    
    # Create master .env
    cat > "${ROOT_PATH}/.env" <<EOF
# AI Platform Configuration
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

# ============================================================================
# DOMAIN & SSL
# ============================================================================
DOMAIN_NAME="${DOMAIN_NAME}"
SSL_EMAIL="${SSL_EMAIL}"

# ============================================================================
# INFRASTRUCTURE
# ============================================================================
CLOUD_PROVIDER="${CLOUD_PROVIDER}"
REVERSE_PROXY="${REVERSE_PROXY}"
VECTOR_DB="${VECTOR_DB}"

# ============================================================================
# DATABASE CONFIGURATION
# ============================================================================
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=ai_platform
POSTGRES_USER=ai_platform
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD="${REDIS_PASSWORD}"

# ============================================================================
# VECTOR DATABASE
# ============================================================================
QDRANT_HOST=qdrant
QDRANT_PORT=6333

WEAVIATE_HOST=weaviate
WEAVIATE_PORT=8080

CHROMA_HOST=chroma
CHROMA_PORT=8000

# ============================================================================
# LLM SERVICES
# ============================================================================
LITELLM_HOST=litellm
LITELLM_PORT=4000
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY}"

OPENCLAW_HOST=openclaw
OPENCLAW_PORT=8001
OPENCLAW_API_KEY="${OPENCLAW_API_KEY}"

# ============================================================================
# OPTIONAL SERVICES
# ============================================================================
N8N_ENABLED="${ENABLE_N8N}"
N8N_HOST=n8n
N8N_PORT=5678
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY}"

SIGNAL_ENABLED="${ENABLE_SIGNAL}"
SIGNAL_HOST=signal-api
SIGNAL_PORT=8080

GDRIVE_SYNC_ENABLED="${ENABLE_GDRIVE_SYNC}"

# ============================================================================
# MONITORING
# ============================================================================
PROMETHEUS_ENABLED="${ENABLE_MONITORING}"
GRAFANA_ENABLED="${ENABLE_MONITORING}"
LOKI_ENABLED="${ENABLE_MONITORING}"

LANGFUSE_HOST=langfuse
LANGFUSE_PORT=3001
LANGFUSE_SALT="${LANGFUSE_SALT}"

# ============================================================================
# SECURITY
# ============================================================================
JWT_SECRET="${JWT_SECRET}"

# ============================================================================
# PATHS
# ============================================================================
DATA_PATH=/mnt/data/ai-platform
LOG_PATH=/mnt/data/ai-platform/logs
BACKUP_PATH=/mnt/data/ai-platform/backups
EOF
    
    chmod 600 "${ROOT_PATH}/.env"
    
    log_success "Master .env file created"
    
    # Create service-specific env files
    log_info "Creating service-specific environment files..."
    
    # LiteLLM config
    if [ -f "${SECRETS_PATH}/llm-providers.env" ]; then
        cat "${SECRETS_PATH}/llm-providers.env" > "${DATA_PATH}/litellm/config/.env"
        chmod 600 "${DATA_PATH}/litellm/config/.env"
        log_success "LiteLLM environment configured"
    fi
    
    log_success "All environment files created"
}

# ============================================================================
# OPTIONAL FEATURES
# ============================================================================

configure_optional_features() {
    log_step "CONFIGURING OPTIONAL FEATURES"
    
    echo ""
    read -p "❯ Enable N8N workflow automation? (yes/no): " ENABLE_N8N_INPUT
    ENABLE_N8N="${ENABLE_N8N_INPUT}"
    
    read -p "❯ Enable monitoring (Prometheus/Grafana/Loki)? (yes/no): " ENABLE_MON_INPUT
    ENABLE_MONITORING="${ENABLE_MON_INPUT}"
    
    # Save configuration
    cat > "${CONFIG_PATH}/optional-features.conf" <<EOF
ENABLE_N8N="${ENABLE_N8N}"
ENABLE_MONITORING="${ENABLE_MONITORING}"
CONFIGURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    log_success "Optional features configured"
}

# ============================================================================
# VERIFICATION
# ============================================================================

verify_setup() {
    log_step "VERIFYING SETUP"
    
    local verification_passed=true
    
    # Check Docker
    if docker --version >/dev/null 2>&1; then
        log_success "Docker installed"
    else
        log_error "Docker not found"
        verification_passed=false
    fi
    
    # Check Tailscale
    if command -v tailscale >/dev/null 2>&1; then
        log_success "Tailscale installed"
    else
        log_warning "Tailscale not found"
    fi
    
    # Check storage structure
    if [ -d "$DATA_PATH" ]; then
        log_success "Storage tier created"
    else
        log_error "Storage tier missing"
        verification_passed=false
    fi
    
    # Check configuration files
    local required_configs=(
        "${CONFIG_PATH}/domain.conf"
        "${CONFIG_PATH}/vector-db.conf"
        "${CONFIG_PATH}/reverse-proxy.conf"
        "${CONFIG_PATH}/cloud-provider.conf"
        "${SECRETS_PATH}/generated.env"
        "${ROOT_PATH}/.env"
    )
    
    for config in "${required_configs[@]}"; do
        if [ -f "$config" ]; then
            log_success "$(basename "$config") exists"
        else
            log_error "$(basename "$config") missing"
            verification_passed=false
        fi
    done
    
    if [ "$verification_passed" = true ]; then
        log_success "All verification checks passed"
    else
        log_error "Some verification checks failed"
        exit 1
    fi
}

# ============================================================================
# SETUP SUMMARY
# ============================================================================

generate_setup_summary() {
    log_step "GENERATING SETUP SUMMARY"
    
    local summary_file="${ROOT_PATH}/SETUP_SUMMARY.txt"
    
    # Source configuration
    source "${CONFIG_PATH}/domain.conf" 2>/dev/null || true
    source "${CONFIG_PATH}/vector-db.conf" 2>/dev/null || true
    source "${CONFIG_PATH}/reverse-proxy.conf" 2>/dev/null || true
    source "${CONFIG_PATH}/cloud-provider.conf" 2>/dev/null || true
    source "${CONFIG_PATH}/tailscale.conf" 2>/dev/null || true
    
    cat > "$summary_file" <<EOF
╔════════════════════════════════════════════════════════════════╗
║          AI PLATFORM - SYSTEM SETUP COMPLETE                  ║
║          Generated: $(date)                    ║
╚════════════════════════════════════════════════════════════════╝

INFRASTRUCTURE CONFIGURATION
────────────────────────────────────────────────────────────────
Domain:           ${DOMAIN_NAME}
SSL Email:        ${SSL_EMAIL}
Cloud Provider:   ${CLOUD_PROVIDER}
Reverse Proxy:    ${REVERSE_PROXY}
Vector Database:  ${VECTOR_DB}
Tailscale:        ${TAILSCALE_ENABLED:-false}
Tailscale IP:     ${TAILSCALE_IP:-N/A}

SERVICE PORTS
────────────────────────────────────────────────────────────────
HTTP:             80 (public)
HTTPS:            443 (public)
PostgreSQL:       5432 (internal)
Redis:            6379 (internal)
Vector DB:        $([ "$VECTOR_DB" = "qdrant" ] && echo "6333" || [ "$VECTOR_DB" = "weaviate" ] && echo "8080" || echo "8000") (internal)
LiteLLM:          4000 (internal)
OpenClaw:         8001 (internal)
N8N:              5678 (Tailscale)
Prometheus:       9090 (Tailscale)
Grafana:          3000 (Tailscale)
Langfuse:         3001 (Tailscale)

SERVICE URLs (after deployment)
────────────────────────────────────────────────────────────────
Main App:         https://${DOMAIN_NAME}
LiteLLM API:      https://${DOMAIN_NAME}/litellm
OpenClaw API:     https://${DOMAIN_NAME}/openclaw
N8N:              https://${DOMAIN_NAME}/n8n
Grafana:          https://${DOMAIN_NAME}/grafana
Langfuse:         https://${DOMAIN_NAME}/langfuse

OPTIONAL FEATURES
────────────────────────────────────────────────────────────────
N8N Automation:   ${ENABLE_N8N}
Monitoring:       ${ENABLE_MONITORING}
Google Drive:     ${ENABLE_GDRIVE_SYNC}
Signal Notify:    ${ENABLE_SIGNAL}

SECURITY NOTES
────────────────────────────────────────────────────────────────
⚠ NO UFW - Cloud firewall provides perimeter security
✓ Tailscale provides zero-trust VPN access
✓ Reverse proxy handles TLS termination
✓ Docker manages container networking
✓ All secrets generated and stored securely

IMPORTANT FILES
────────────────────────────────────────────────────────────────
⚠ BACKUP THESE FILES IMMEDIATELY:
  - ${SECRETS_PATH}/generated.env
  - ${ROOT_PATH}/.env
  - ${CONFIG_PATH}/*.conf

NEXT STEPS
────────────────────────────────────────────────────────────────
1. Configure cloud provider firewall (see above)
2. Setup DNS records:
   - A record: ${DOMAIN_NAME} → YOUR_SERVER_IP
   - CNAME: *.${DOMAIN_NAME} → ${DOMAIN_NAME}

3. Run next script:
   sudo ./scripts/2-setup-databases.sh

4. After all scripts complete:
   docker compose up -d

═══════════════════════════════════════════════════════════════
System initialization completed successfully!
═══════════════════════════════════════════════════════════════
EOF

    cat "$summary_file" | tee -a "$LOG_FILE"
    
    log_success "Summary saved to: ${summary_file}"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_section "AI PLATFORM SYSTEM INITIALIZATION v${SCRIPT_VERSION}"
    
    # Pre-flight checks
    check_root
    check_ubuntu_version
    check_internet_connectivity
    
    # Core setup
    initialize_storage_tier
    check_port_availability
    validate_domain
    install_docker
    setup_tailscale  # NOW WITH APPARMOR FIX
    
    # Configuration
    select_vector_database
    select_reverse_proxy
    configure_cloud_provider
    
    # Optional features
    configure_optional_features
    setup_google_drive_sync
    setup_signal_cli
    
    # LLM providers
    configure_llm_providers
    
    # Secrets & environment
    generate_secrets
    create_environment_files
    
    # Verification
    verify_setup
    generate_setup_summary
    
    # Success
    log_section "SETUP COMPLETE"
    echo ""
    log_success "System initialization completed successfully!"
    echo ""
    log_info "Review: ${ROOT_PATH}/SETUP_SUMMARY.txt"
    log_info "Next: sudo ./scripts/2-setup-databases.sh"
    echo ""
}

main "$@"
