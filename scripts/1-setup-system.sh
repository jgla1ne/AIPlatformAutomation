#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform - System Setup Script
# Version: 10.2 FINAL
# Description: Installs all system dependencies and prepares environment
# ============================================================================

# Logging setup
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOGS_DIR"
LOGFILE="${LOGS_DIR}/setup-${TIMESTAMP}.log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1" | tee -a "$LOGFILE"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOGFILE"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOGFILE"
}

log_error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOGFILE"
}

log_step() {
    echo -e "\n${BLUE}▶${NC} $1" | tee -a "$LOGFILE"
}

# Error handler
error_handler() {
    log_error "Script failed at line $1"
    log_error "Check log file: $LOGFILE"
    exit 1
}

trap 'error_handler $LINENO' ERR

# ============================================================================
# STEP 1: CREATE DIRECTORY STRUCTURE
# ============================================================================
create_directories() {
    log_step "Creating directory structure..."
    
    local dirs=(
        "${PROJECT_ROOT}/scripts"
        "${PROJECT_ROOT}/stacks"
        "${PROJECT_ROOT}/stacks/ollama"
        "${PROJECT_ROOT}/stacks/litellm"
        "${PROJECT_ROOT}/stacks/anythingllm"
        "${PROJECT_ROOT}/stacks/dify"
        "${PROJECT_ROOT}/stacks/n8n"
        "${PROJECT_ROOT}/stacks/signal"
        "${PROJECT_ROOT}/stacks/clawdbot"
        "${PROJECT_ROOT}/stacks/nginx"
        "${PROJECT_ROOT}/data"
        "${PROJECT_ROOT}/logs"
        "/mnt/data/ollama"
        "/mnt/data/anythingllm"
        "/mnt/data/gdrive"
        "/mnt/data/postgres"
        "/mnt/data/redis"
        "/mnt/data/dify"
        "/mnt/data/dify/api/storage"
        "/mnt/data/dify/qdrant"
        "/mnt/data/n8n"
        "/mnt/data/signal"
        "/mnt/data/clawdbot"
        "/mnt/data/backups"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            sudo mkdir -p "$dir"
            sudo chown -R $(whoami):$(whoami) "$dir"
            log_success "Created: $dir"
        else
            log_info "Already exists: $dir"
        fi
    done
    
    log_success "All directories created"
}

# ============================================================================
# STEP 2: SYSTEM UPDATES
# ============================================================================
update_system() {
    log_step "Updating system packages..."
    
    sudo apt-get update >> "$LOGFILE" 2>&1
    log_success "Package lists updated"
    
    sudo apt-get upgrade -y >> "$LOGFILE" 2>&1
    log_success "System packages upgraded"
}

# ============================================================================
# STEP 3: INSTALL DOCKER
# ============================================================================
install_docker() {
    log_step "Installing Docker..."
    
    if command -v docker &> /dev/null; then
        local version=$(docker --version | cut -d' ' -f3 | tr -d ',')
        log_info "Docker already installed (version: $version)"
        return 0
    fi
    
    # Install prerequisites
    log_info "Installing prerequisites..."
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release >> "$LOGFILE" 2>&1
    
    # Add Docker's official GPG key
    log_info "Adding Docker GPG key..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up repository
    log_info "Setting up Docker repository..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    log_info "Installing Docker Engine..."
    sudo apt-get update >> "$LOGFILE" 2>&1
    sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin >> "$LOGFILE" 2>&1
    
    # Add user to docker group
    sudo usermod -aG docker $(whoami)
    
    log_success "Docker installed successfully"
    log_warning "You may need to log out and back in for docker group to take effect"
}

# ============================================================================
# STEP 4: INSTALL TAILSCALE
# ============================================================================
install_tailscale() {
    log_step "Installing Tailscale..."
    
    if command -v tailscale &> /dev/null; then
        local version=$(tailscale version | head -n1)
        log_info "Tailscale already installed ($version)"
        return 0
    fi
    
    log_info "Adding Tailscale repository..."
    curl -fsSL https://tailscale.com/install.sh | sh >> "$LOGFILE" 2>&1
    
    log_success "Tailscale installed successfully"
    log_warning "Run 'sudo tailscale up' to connect to your network"
}

# ============================================================================
# STEP 5: INSTALL RCLONE
# ============================================================================
install_rclone() {
    log_step "Installing rclone..."
    
    if command -v rclone &> /dev/null; then
        local version=$(rclone version | head -n1 | cut -d' ' -f2)
        log_info "rclone already installed (version: $version)"
        return 0
    fi
    
    log_info "Downloading and installing rclone..."
    curl https://rclone.org/install.sh | sudo bash >> "$LOGFILE" 2>&1
    
    log_success "rclone installed successfully"
    log_warning "Run 'rclone config' to set up Google Drive sync"
}

# ============================================================================
# STEP 6: INSTALL ADDITIONAL TOOLS
# ============================================================================
install_tools() {
    log_step "Installing additional tools..."
    
    local tools=(
        "jq"
        "htop"
        "ncdu"
        "net-tools"
        "git"
        "vim"
        "curl"
        "wget"
        "unzip"
        "tree"
    )
    
    log_info "Installing: ${tools[*]}"
    sudo apt-get install -y "${tools[@]}" >> "$LOGFILE" 2>&1
    
    log_success "Additional tools installed"
}

# ============================================================================
# STEP 7: CREATE ENVIRONMENT FILE
# ============================================================================
create_env_file() {
    log_step "Creating environment configuration..."
    
    local env_file="${PROJECT_ROOT}/.env"
    
    if [[ -f "$env_file" ]]; then
        log_warning ".env file already exists"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Keeping existing .env file"
            return 0
        fi
        mv "$env_file" "${env_file}.backup.${TIMESTAMP}"
        log_info "Backed up existing .env to .env.backup.${TIMESTAMP}"
    fi
    
    log_info "Generating secure secrets..."
    
    # Generate strong random passwords
    local litellm_key="sk-lit-$(openssl rand -hex 16)"
    local postgres_pass="pg_$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-20)"
    local redis_pass="redis_$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-20)"
    local dify_secret="$(openssl rand -hex 32)"
    local n8n_enc_key="$(openssl rand -hex 32)"
    local n8n_jwt_secret="$(openssl rand -hex 32)"
    
    cat > "$env_file" << EOF
#!/bin/bash
# ============================================================================
# AI Platform Environment Configuration
# Generated: $(date +"%Y-%m-%d %H:%M:%S")
# Version: 10.2 FINAL
# ============================================================================

# ----------------------------------------------------------------------------
# CORE PATHS
# ----------------------------------------------------------------------------
PROJECT_ROOT="${PROJECT_ROOT}"
SCRIPTS_DIR="\${PROJECT_ROOT}/scripts"
STACKS_DIR="\${PROJECT_ROOT}/stacks"
DATA_DIR="/mnt/data"
CONFIG_DIR="\${PROJECT_ROOT}/data"
LOGS_DIR="\${PROJECT_ROOT}/logs"

# ----------------------------------------------------------------------------
# DOCKER CONFIGURATION
# ----------------------------------------------------------------------------
DOCKER_NETWORK="ai-platform"
DOCKER_SUBNET="172.20.0.0/16"

# ----------------------------------------------------------------------------
# OLLAMA (Local AI Models)
# ----------------------------------------------------------------------------
OLLAMA_HOST="0.0.0.0"
OLLAMA_PORT="11434"
OLLAMA_MODELS="llama3.2:3b qwen2.5:7b deepseek-r1:7b"

# ----------------------------------------------------------------------------
# LITELLM (AI Gateway)
# ----------------------------------------------------------------------------
LITELLM_PORT="4000"
LITELLM_MASTER_KEY="${litellm_key}"

# ----------------------------------------------------------------------------
# ANYTHINGLLM (Vector Database & RAG)
# ----------------------------------------------------------------------------
ANYTHINGLLM_PORT="3001"
ANYTHINGLLM_STORAGE="\${DATA_DIR}/anythingllm"

# ----------------------------------------------------------------------------
# CLAWDBOT (AI Agent)
# ----------------------------------------------------------------------------
CLAWDBOT_PORT="3000"

# ----------------------------------------------------------------------------
# DIFY (Workflow Automation)
# ----------------------------------------------------------------------------
POSTGRES_DB="dify"
POSTGRES_USER="dify"
POSTGRES_PASSWORD="${postgres_pass}"
POSTGRES_PORT="5432"

REDIS_PASSWORD="${redis_pass}"
REDIS_PORT="6379"

DIFY_SECRET_KEY="${dify_secret}"
DIFY_API_BASE_URL="http://dify-nginx:80/api"
DIFY_WEB_URL="http://dify-nginx:80"

# ----------------------------------------------------------------------------
# N8N (Workflow Automation)
# ----------------------------------------------------------------------------
N8N_PORT="5678"
N8N_ENCRYPTION_KEY="${n8n_enc_key}"
N8N_USER_MANAGEMENT_JWT_SECRET="${n8n_jwt_secret}"

# ----------------------------------------------------------------------------
# SIGNAL API (Messaging)
# ----------------------------------------------------------------------------
SIGNAL_PRIMARY_NUMBER="+1234567890"
SIGNAL_SECONDARY_NUMBER="+0987654321"

# ----------------------------------------------------------------------------
# GOOGLE DRIVE (Cloud Storage)
# ----------------------------------------------------------------------------
GDRIVE_REMOTE="gdrive"
GDRIVE_SYNC_DIR="\${DATA_DIR}/gdrive"

# ----------------------------------------------------------------------------
# EXTERNAL AI APIS (Optional - Add your keys)
# ----------------------------------------------------------------------------
ANTHROPIC_API_KEY=""
OPENAI_API_KEY=""
GROQ_API_KEY=""

# ----------------------------------------------------------------------------
# NGINX (Reverse Proxy)
# ----------------------------------------------------------------------------
NGINX_PORT="8443"

# ----------------------------------------------------------------------------
# DO NOT EDIT BELOW THIS LINE
# ----------------------------------------------------------------------------
EOF

    chmod 600 "$env_file"
    log_success "Environment file created: $env_file"
    log_warning "Secrets generated - keep .env file secure!"
    log_info "File permissions set to 600 (owner read/write only)"
}

# ============================================================================
# STEP 8: VERIFY INSTALLATION
# ============================================================================
verify_installation() {
    log_step "Verifying installation..."
    
    local checks=(
        "docker:Docker"
        "docker:Docker Compose"
        "tailscale:Tailscale"
        "rclone:rclone"
        "jq:jq"
    )
    
    local failed=0
    
    for check in "${checks[@]}"; do
        IFS=':' read -r cmd name <<< "$check"
        if command -v "$cmd" &> /dev/null; then
            log_success "$name installed"
        else
            log_error "$name NOT installed"
            ((failed++))
        fi
    done
    
    # Verify directories
    log_info "Verifying directories..."
    if [[ -d "${PROJECT_ROOT}/stacks" ]]; then
        local stack_count=$(find "${PROJECT_ROOT}/stacks" -mindepth 1 -maxdepth 1 -type d | wc -l)
        log_success "Stack directories created ($stack_count subdirs)"
    else
        log_error "Stack directory not created"
        ((failed++))
    fi
    
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        log_success "Environment file created"
    else
        log_error "Environment file missing"
        ((failed++))
    fi
    
    if [[ $failed -gt 0 ]]; then
        log_error "$failed component(s) failed to install"
        return 1
    fi
    
    log_success "All components verified"
}

# ============================================================================
# STEP 9: DISPLAY NEXT STEPS
# ============================================================================
show_next_steps() {
    cat << "EOF"

╔════════════════════════════════════════════════════════════╗
║                  ✓ SYSTEM SETUP COMPLETE                 ║
╚════════════════════════════════════════════════════════════╝

📋 NEXT STEPS:

1. Configure Tailscale (if not already done):
   sudo tailscale up

2. Configure Google Drive (optional):
   rclone config
   # Follow prompts to set up 'gdrive' remote

3. Review environment configuration:
   nano ~/AIPlatformAutomation/.env
   # Add your API keys for Anthropic, OpenAI, etc.

4. Deploy services:
   cd ~/AIPlatformAutomation/scripts
   ./2-deploy-services.sh

5. Configure services:
   ./3-configure-services.sh

6. Set up systemd (autostart):
   ./4-systemd-setup.sh

⚠️  IMPORTANT NOTES:

• Docker group membership requires logout/login to take effect
  If 'docker ps' fails, run: newgrp docker

• Keep your .env file secure (contains secrets)
  Already set to 600 permissions

• Backup your .env file before making changes:
  cp .env .env.backup

📊 RESOURCE USAGE:
• Disk space used: $(du -sh ${PROJECT_ROOT} 2>/dev/null | cut -f1)
• Data directory: $(du -sh /mnt/data 2>/dev/null | cut -f1)

📝 LOG FILE: ${LOGFILE}

EOF
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    echo "ℹ Log file: $LOGFILE"
    echo ""
    
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║      AI Platform - System Setup v10.2 FINAL             ║
╚════════════════════════════════════════════════════════════╝
EOF
    
    echo ""
    
    # Execute all steps
    create_directories
    update_system
    install_docker
    install_tailscale
    install_rclone
    install_tools
    create_env_file
    verify_installation
    show_next_steps
    
    log_success "System setup completed successfully!"
}

# Run main function and log everything
main "$@" 2>&1 | tee -a "$LOGFILE"
