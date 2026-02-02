#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform - Service Configuration Script
# Version: 14.0 - COMPLETE CONFIGURATION WIZARD
# ============================================================================

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOGS_DIR"
LOGFILE="${LOGS_DIR}/configure-${TIMESTAMP}.log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}ℹ${NC} $1" | tee -a "$LOGFILE"; }
log_success() { echo -e "${GREEN}✓${NC} $1" | tee -a "$LOGFILE"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOGFILE"; }
log_error() { echo -e "${RED}✗${NC} $1" | tee -a "$LOGFILE"; }
log_step() { echo -e "\n${CYAN}[$1]${NC} $2" | tee -a "$LOGFILE"; }

# Error handler
error_handler() {
    log_error "Configuration failed at line $1"
    log_error "Check log: $LOGFILE"
    exit 1
}
trap 'error_handler $LINENO' ERR

# ============================================================================
# BANNER
# ============================================================================
show_banner() {
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║       AI PLATFORM - SERVICE CONFIGURATION v14.0            ║
║         COMPLETE SYSTEM CONFIGURATION WIZARD               ║
║                                                            ║
║  Configure:                                                ║
║  • Google Drive sync (rclone + OAuth2)                     ║
║  • ClawdBot integration (Signal + Vector DB)               ║
║  • Port mappings and routing                               ║
║  • System diagnostics and health checks                    ║
║  • Backup automation                                       ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
    echo ""
}

# ============================================================================
# LOAD ENVIRONMENT
# ============================================================================
load_environment() {
    if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
        log_error "Environment file not found: ${PROJECT_ROOT}/.env"
        log_error "Please run ./1-setup-system.sh first"
        exit 1
    fi
    
    set -a
    source "${PROJECT_ROOT}/.env"
    set +a
}

# ============================================================================
# MAIN MENU
# ============================================================================
show_main_menu() {
    clear
    show_banner
    
    cat << EOF
${CYAN}════════════════════════════════════════════════════════════${NC}
  📋 CONFIGURATION MENU
${CYAN}════════════════════════════════════════════════════════════${NC}

  ${GREEN}CLOUD SYNC & BACKUP${NC}
  1) Configure Google Drive Sync (rclone + OAuth2)
  2) Setup Automatic Backups
  3) Test Sync & Backup

  ${GREEN}SERVICE INTEGRATION${NC}
  4) Configure ClawdBot Integration
  5) Configure Signal API Connection
  6) Configure Vector Database (AnythingLLM)

  ${GREEN}NETWORK & ROUTING${NC}
  7) Summarize Network Connections
  8) Diagnose Port Connectivity
  9) Configure Port Mappings
  
  ${GREEN}SYSTEM MANAGEMENT${NC}
  10) Run System Diagnostics
  11) View Service Status
  12) Update Configuration Files
  
  ${GREEN}MAINTENANCE${NC}
  13) Complete System Purge (run 0-cleanup)
  14) Reset Configuration
  
  0) Exit

${CYAN}════════════════════════════════════════════════════════════${NC}
EOF
    
    echo -n "Select option [0-14]: "
    read -r choice
    echo ""
    
    case $choice in
        1) configure_google_drive_wizard ;;
        2) configure_backup_wizard ;;
        3) test_sync_backup ;;
        4) configure_clawdbot_wizard ;;
        5) configure_signal_api_wizard ;;
        6) configure_vectordb_wizard ;;
        7) summarize_connections ;;
        8) diagnose_connectivity ;;
        9) configure_ports_wizard ;;
        10) run_system_diagnostics ;;
        11) view_service_status ;;
        12) update_configuration_files ;;
        13) complete_system_purge ;;
        14) reset_configuration ;;
        0) exit 0 ;;
        *) 
            log_error "Invalid option"
            sleep 2
            show_main_menu
            ;;
    esac
}

# ============================================================================
# 1. CONFIGURE GOOGLE DRIVE SYNC WIZARD
# ============================================================================
configure_google_drive_wizard() {
    clear
    log_step "1" "Google Drive Sync Configuration"
    echo ""
    
    cat << EOF
${CYAN}════════════════════════════════════════════════════════════${NC}
  ☁️  GOOGLE DRIVE SYNC SETUP
${CYAN}════════════════════════════════════════════════════════════${NC}

This wizard will configure:
• rclone with OAuth2 authentication
• Automatic sync to Google Drive
• Backup synchronization
• Scheduled sync tasks

EOF
    
    # Check rclone installation
    if ! command -v rclone &> /dev/null; then
        log_error "rclone is not installed"
        echo ""
        echo "Install rclone:"
        echo "  Ubuntu/Debian: sudo apt install rclone"
        echo "  macOS:         brew install rclone"
        echo ""
        read -p "Press Enter to return to menu..."
        show_main_menu
        return
    fi
    
    log_success "✓ rclone found: $(rclone version | head -n 1)"
    echo ""
    
    # Check existing configuration
    if rclone listremotes 2>/dev/null | grep -q "^gdrive:$"; then
        log_warning "Google Drive remote 'gdrive' already configured"
        echo ""
        read -p "Reconfigure? (y/n) [n]: " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            verify_gdrive_connection
            read -p "Press Enter to return to menu..."
            show_main_menu
            return
        fi
        rclone config delete gdrive 2>/dev/null || true
    fi
    
    # Start OAuth2 configuration
    cat << "EOF"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🔐 OAuth2 Authentication
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Your browser will open for Google authentication:
1. Sign in to your Google account
2. Grant rclone access to Google Drive
3. Wait for confirmation

Press Enter to start OAuth2 flow...
EOF
    read -r
    
    log_info "Starting rclone OAuth2 configuration..."
    echo ""
    
    # Create rclone config interactively
    rclone config create gdrive drive \
        scope=drive \
        config_is_local=false \
        --auto-confirm 2>&1 | tee -a "$LOGFILE"
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log_success "✓ Google Drive configured successfully"
        verify_gdrive_connection
        
        # Update .env
        if ! grep -q "GDRIVE_SYNC_ENABLED" "${PROJECT_ROOT}/.env"; then
            echo "" >> "${PROJECT_ROOT}/.env"
            echo "# Google Drive Sync" >> "${PROJECT_ROOT}/.env"
            echo "GDRIVE_SYNC_ENABLED=true" >> "${PROJECT_ROOT}/.env"
        else
            sed -i 's/GDRIVE_SYNC_ENABLED=.*/GDRIVE_SYNC_ENABLED=true/' "${PROJECT_ROOT}/.env"
        fi
        
        log_success "✓ Updated .env with GDRIVE_SYNC_ENABLED=true"
        
        # Setup sync directories
        setup_sync_directories
        
        # Create sync scripts
        create_sync_scripts
        
        echo ""
        read -p "Setup automatic daily sync? (y/n) [y]: " -r
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            setup_cron_sync
        fi
        
    else
        log_error "✗ Google Drive configuration failed"
        log_error "Please configure manually: rclone config"
    fi
    
    echo ""
    read -p "Press Enter to return to menu..."
    show_main_menu
}

# ============================================================================
# 2. CONFIGURE BACKUP WIZARD
# ============================================================================
configure_backup_wizard() {
    clear
    log_step "2" "Backup System Configuration"
    echo ""
    
    cat << EOF
${CYAN}════════════════════════════════════════════════════════════${NC}
  💾 BACKUP SYSTEM SETUP
${CYAN}════════════════════════════════════════════════════════════${NC}

This wizard will configure:
• Automatic database backups
• Application data backups
• Backup retention policy
• Scheduled backup tasks

EOF
    
    # Backup retention
    echo "Current retention: ${BACKUP_RETENTION_DAYS:-30} days"
    read -p "Backup retention days [30]: " retention
    retention=${retention:-30}
    
    # Update .env
    if ! grep -q "BACKUP_RETENTION_DAYS" "${PROJECT_ROOT}/.env"; then
        echo "BACKUP_RETENTION_DAYS=${retention}" >> "${PROJECT_ROOT}/.env"
    else
        sed -i "s/BACKUP_RETENTION_DAYS=.*/BACKUP_RETENTION_DAYS=${retention}/" "${PROJECT_ROOT}/.env"
    fi
    
    if ! grep -q "BACKUP_ENABLED" "${PROJECT_ROOT}/.env"; then
        echo "BACKUP_ENABLED=true" >> "${PROJECT_ROOT}/.env"
    else
        sed -i 's/BACKUP_ENABLED=.*/BACKUP_ENABLED=true/' "${PROJECT_ROOT}/.env"
    fi
    
    log_success "✓ Backup retention set to ${retention} days"
    
    # Create backup scripts
    create_backup_scripts
    
    echo ""
    read -p "Setup automatic daily backup? (y/n) [y]: " -r
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        setup_cron_backup
    fi
    
    echo ""
    read -p "Run initial backup now? (y/n) [n]: " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "${PROJECT_ROOT}/scripts/backup-services.sh"
    fi
    
    echo ""
    read -p "Press Enter to return to menu..."
    show_main_menu
}

# ============================================================================
# 3. TEST SYNC & BACKUP
# ============================================================================
test_sync_backup() {
    clear
    log_step "3" "Testing Sync & Backup"
    echo ""
    
    # Test Google Drive
    if [[ "${GDRIVE_SYNC_ENABLED:-false}" == "true" ]]; then
        log_info "Testing Google Drive connection..."
        if rclone lsf gdrive: --max-depth 1 >/dev/null 2>&1; then
            log_success "✓ Google Drive accessible"
            echo ""
            echo "Remote contents:"
            rclone lsf gdrive:ai-platform --max-depth 2 2>/dev/null | head -n 20
        else
            log_error "✗ Google Drive connection failed"
        fi
    else
        log_warning "Google Drive sync is disabled"
    fi
    
    echo ""
    
    # Test backup scripts
    log_info "Checking backup scripts..."
    if [[ -x "${PROJECT_ROOT}/scripts/backup-services.sh" ]]; then
        log_success "✓ Backup script exists and is executable"
    else
        log_warning "✗ Backup script not found or not executable"
    fi
    
    if [[ -x "${PROJECT_ROOT}/scripts/sync-to-gdrive.sh" ]]; then
        log_success "✓ Sync script exists and is executable"
    else
        log_warning "✗ Sync script not found or not executable"
    fi
    
    # Show recent backups
    echo ""
    log_info "Recent backups:"
    if [[ -d "${PROJECT_ROOT}/backups" ]]; then
        ls -lht "${PROJECT_ROOT}/backups" | head -n 6
    else
        echo "No backups found"
    fi
    
    echo ""
    read -p "Press Enter to return to menu..."
    show_main_menu
}

# ============================================================================
# 4. CONFIGURE CLAWDBOT WIZARD
# ============================================================================
configure_clawdbot_wizard() {
    clear
    log_step "4" "ClawdBot Integration Configuration"
    echo ""
    
    cat << EOF
${CYAN}════════════════════════════════════════════════════════════${NC}
  🤖 CLAWDBOT CONFIGURATION
${CYAN}════════════════════════════════════════════════════════════${NC}

Configure ClawdBot integration with:
• Claude API (Anthropic)
• Signal API for messaging
• AnythingLLM vector database
• WhatsApp/Telegram channels (optional)

EOF
    
    # Claude API Key
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🔑 Claude API Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Current Claude API Key: ${CLAUDE_API_KEY:0:20}..."
    read -p "Update Claude API Key? (y/n) [n]: " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -sp "Enter Claude API Key: " new_claude_key
        echo ""
        if [[ -n "$new_claude_key" ]]; then
            sed -i "s|CLAUDE_API_KEY=.*|CLAUDE_API_KEY=${new_claude_key}|" "${PROJECT_ROOT}/.env"
            log_success "✓ Claude API Key updated"
            CLAUDE_API_KEY="$new_claude_key"
        fi
    fi
    
    # Signal API Integration
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📱 Signal API Integration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Signal API URL: http://localhost:${SIGNAL_PORT:-8084}"
    read -p "Configure Signal integration for ClawdBot? (y/n) [y]: " -r
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        if ! grep -q "CLAWDBOT_SIGNAL_ENABLED" "${PROJECT_ROOT}/.env"; then
            echo "CLAWDBOT_SIGNAL_ENABLED=true" >> "${PROJECT_ROOT}/.env"
            echo "CLAWDBOT_SIGNAL_URL=http://ai-signal:8080" >> "${PROJECT_ROOT}/.env"
        else
            sed -i 's/CLAWDBOT_SIGNAL_ENABLED=.*/CLAWDBOT_SIGNAL_ENABLED=true/' "${PROJECT_ROOT}/.env"
        fi
        log_success "✓ Signal integration enabled"
    fi
    
    # Vector Database Integration
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🗄️  Vector Database (AnythingLLM) Integration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "AnythingLLM API: http://localhost:${ANYTHINGLLM_PORT:-3001}"
    read -p "Configure AnythingLLM integration for ClawdBot? (y/n) [y]: " -r
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        read -p "Enter AnythingLLM API Key (from AnythingLLM settings): " anythingllm_key
        if [[ -n "$anythingllm_key" ]]; then
            if ! grep -q "CLAWDBOT_ANYTHINGLLM_KEY" "${PROJECT_ROOT}/.env"; then
                echo "CLAWDBOT_ANYTHINGLLM_ENABLED=true" >> "${PROJECT_ROOT}/.env"
                echo "CLAWDBOT_ANYTHINGLLM_URL=http://ai-anythingllm:3001" >> "${PROJECT_ROOT}/.env"
                echo "CLAWDBOT_ANYTHINGLLM_KEY=${anythingllm_key}" >> "${PROJECT_ROOT}/.env"
            else
                sed -i "s/CLAWDBOT_ANYTHINGLLM_KEY=.*/CLAWDBOT_ANYTHINGLLM_KEY=${anythingllm_key}/" "${PROJECT_ROOT}/.env"
                sed -i 's/CLAWDBOT_ANYTHINGLLM_ENABLED=.*/CLAWDBOT_ANYTHINGLLM_ENABLED=true/' "${PROJECT_ROOT}/.env"
            fi
            log_success "✓ AnythingLLM integration configured"
        fi
    fi
    
    # Update ClawdBot configuration file
    create_clawdbot_config
    
    echo ""
    log_success "✓ ClawdBot configuration updated"
    log_info "Restart ClawdBot to apply changes: docker restart ai-clawdbot"
    
    echo ""
    read -p "Restart ClawdBot now? (y/n) [n]: " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker restart ai-clawdbot 2>/dev/null || log_warning "ClawdBot container not running"
    fi
    
    echo ""
    read -p "Press Enter to return to menu..."
    show_main_menu
}

# ============================================================================
# 5. CONFIGURE SIGNAL API WIZARD
# ============================================================================
configure_signal_api_wizard() {
    clear
    log_step "5" "Signal API Configuration"
    echo ""
    
    cat << EOF
${CYAN}════════════════════════════════════════════════════════════${NC}
  📱 SIGNAL API SETUP
${CYAN}════════════════════════════════════════════════════════════${NC}

Signal API Configuration:
• Link device via QR code
• Configure phone number
• Test message sending

Current Status:
  Port:    ${SIGNAL_PORT:-8084}
  URL:     http://localhost:${SIGNAL_PORT:-8084}

EOF
    
    # Check if Signal container is running
    if docker ps --format '{{.Names}}' | grep -q "^ai-signal$"; then
        log_success "✓ Signal API container is running"
        
        echo ""
        echo "To link your Signal device:"
        echo "1. Open: http://localhost:${SIGNAL_PORT:-8084}/v1/qrcodelink?device_name=ai-platform"
        echo "2. Scan QR code with Signal app"
        echo "3. Complete pairing process"
        echo ""
        
        read -p "Open QR code link in browser? (y/n) [y]: " -r
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            if command -v xdg-open &> /dev/null; then
                xdg-open "http://localhost:${SIGNAL_PORT:-8084}/v1/qrcodelink?device_name=ai-platform" 2>/dev/null &
            elif command -v open &> /dev/null; then
                open "http://localhost:${SIGNAL_PORT:-8084}/v1/qrcodelink?device_name=ai-platform" 2>/dev/null &
            else
                log_info "Please open manually: http://localhost:${SIGNAL_PORT:-8084}/v1/qrcodelink?device_name=ai-platform"
            fi
        fi
        
        echo ""
        read -p "Enter your Signal phone number (with country code, e.g., +1234567890): " signal_number
        if [[ -n "$signal_number" ]]; then
            if ! grep -q "SIGNAL_PHONE_NUMBER" "${PROJECT_ROOT}/.env"; then
                echo "SIGNAL_PHONE_NUMBER=${signal_number}" >> "${PROJECT_ROOT}/.env"
            else
                sed -i "s/SIGNAL_PHONE_NUMBER=.*/SIGNAL_PHONE_NUMBER=${signal_number}/" "${PROJECT_ROOT}/.env"
            fi
            log_success "✓ Signal phone number saved"
        fi
        
    else
        log_error "✗ Signal API container is not running"
        log_info "Start Signal API: cd ${PROJECT_ROOT}/stacks/signal-api && docker-compose up -d"
    fi
    
    echo ""
    read -p "Press Enter to return to menu..."
    show_main_menu
}

# ============================================================================
# 6. CONFIGURE VECTOR DATABASE WIZARD
# ============================================================================
configure_vectordb_wizard() {
    clear
    log_step "6" "Vector Database Configuration"
    echo ""
    
    cat << EOF
${CYAN}════════════════════════════════════════════════════════════${NC}
  🗄️  VECTOR DATABASE SETUP
${CYAN}════════════════════════════════════════════════════════════${NC}

Configure vector database connections:
• Weaviate (primary vector store)
• AnythingLLM integration
• Connection testing

EOF
    
    # Weaviate Status
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Weaviate Vector Database"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if docker ps --format '{{.Names}}' | grep -q "^ai-weaviate$"; then
        log_success "✓ Weaviate is running"
        echo "  URL:    http://localhost:${WEAVIATE_PORT:-8383}"
        echo "  gRPC:   localhost:${WEAVIATE_GRPC_PORT:-50051}"
        
        # Test Weaviate connection
        if curl -s "http://localhost:${WEAVIATE_PORT:-8383}/v1/.well-known/ready" | grep -q "true"; then
            log_success "✓ Weaviate is ready"
        else
            log_warning "⚠ Weaviate is starting..."
        fi
    else
        log_error "✗ Weaviate is not running"
    fi
    
    # AnythingLLM Status
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  AnythingLLM (Vector DB + RAG)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if docker ps --format '{{.Names}}' | grep -q "^ai-anythingllm$"; then
        log_success "✓ AnythingLLM is running"
        echo "  URL:    http://localhost:${ANYTHINGLLM_PORT:-3001}"
        
        echo ""
        log_info "To get AnythingLLM API key:"
        echo "1. Open: http://localhost:${ANYTHINGLLM_PORT:-3001}"
        echo "2. Go to Settings → API Keys"
        echo "3. Create new API key"
        echo "4. Use key for ClawdBot integration"
    else
        log_error "✗ AnythingLLM is not running"
    fi
    
    echo ""
    read -p "Press Enter to return to menu..."
    show_main_menu
}

# ============================================================================
# HELPER FUNCTIONS FOR SYNC & BACKUP
# ============================================================================

verify_gdrive_connection() {
    log_info "Verifying Google Drive connection..."
    if rclone lsf gdrive: --max-depth 1 >/dev/null 2>&1; then
        log_success "✓ Connected to Google Drive"
        echo ""
        echo "Root directory:"
        rclone lsf gdrive: --max-depth 1 | head -n 10
    else
        log_error "✗ Failed to connect to Google Drive"
    fi
}

setup_sync_directories() {
    log_info "Setting up sync directories..."
    
    local sync_dirs=(
        "ai-platform/backups"
        "ai-platform/exports"
        "ai-platform/configs"
        "ai-platform/logs"
    )
    
    for dir in "${sync_dirs[@]}"; do
        rclone mkdir "gdrive:${dir}" 2>/dev/null || true
    done
    
    sudo mkdir -p /mnt/data/gdrive/ai-platform 2>/dev/null || mkdir -p "${PROJECT_ROOT}/gdrive"
    log_success "✓ Sync directories created"
}

create_clawdbot_config() {
    local config_file="${PROJECT_ROOT}/stacks/clawdbot/config/clawdbot.json"
    mkdir -p "$(dirname "$config_file")"
    
    cat > "$config_file" << EOF
{
  "model": "claude-3-5-sonnet-20241022",
  "api_key": "${CLAUDE_API_KEY}",
  "integrations": {
    "signal": {
      "enabled": ${CLAWDBOT_SIGNAL_ENABLED:-false},
      "url": "${CLAWDBOT_SIGNAL_URL:-http://ai-signal:8080}"
    },
    "anythingllm": {
      "enabled": ${CLAWDBOT_ANYTHINGLLM_ENABLED:-false},
      "url": "${CLAWDBOT_ANYTHINGLLM_URL:-http://ai-anythingllm:3001}",
      "api_key": "${CLAWDBOT_ANYTHINGLLM_KEY:-}"
    }
  },
  "features": {
    "memory": true,
    "web_search": true,
    "code_execution": false
  }
}
EOF
    
    log_success "✓ ClawdBot configuration file created"
}
# ============================================================================
# 7. SUMMARIZE NETWORK CONNECTIONS
# ============================================================================
summarize_connections() {
    clear
    log_step "7" "Network Connection Summary"
    echo ""

    cat << EOF
${CYAN}════════════════════════════════════════════════════════════${NC}
  🌐 NETWORK TOPOLOGY SUMMARY
${CYAN}════════════════════════════════════════════════════════════${NC}

EOF

    # Load environment
    set -a
    source "${PROJECT_ROOT}/.env" 2>/dev/null
    set +a

    # Docker Network
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Docker Network"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if docker network inspect ai-platform &>/dev/null; then
        log_success "✓ Network 'ai-platform' exists"
        echo ""
        docker network inspect ai-platform --format '{{range .Containers}}  • {{.Name}}: {{.IPv4Address}}{{println}}{{end}}'
    else
        log_error "✗ Network 'ai-platform' not found"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Service Port Mappings"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Service table
    printf "%-20s %-15s %-15s %-30s\n" "SERVICE" "INTERNAL PORT" "EXTERNAL PORT" "ACCESS URL"
    printf "%-20s %-15s %-15s %-30s\n" "────────────────────" "─────────────" "─────────────" "──────────────────────────────"

    # Define services
    declare -A services=(
        ["Dify"]="80:${DIFY_PORT:-8200}:http://localhost:${DIFY_PORT:-8200}"
        ["n8n"]="5678:${N8N_PORT:-5678}:http://localhost:${N8N_PORT:-5678}"
        ["AnythingLLM"]="3001:${ANYTHINGLLM_PORT:-3001}:http://localhost:${ANYTHINGLLM_PORT:-3001}"
        ["Flowise"]="3000:${FLOWISE_PORT:-3000}:http://localhost:${FLOWISE_PORT:-3000}"
        ["PostgreSQL"]="5432:${POSTGRES_PORT:-5432}:postgresql://localhost:${POSTGRES_PORT:-5432}"
        ["Redis"]="6379:${REDIS_PORT:-6379}:redis://localhost:${REDIS_PORT:-6379}"
        ["Weaviate"]="8383:${WEAVIATE_PORT:-8383}:http://localhost:${WEAVIATE_PORT:-8383}"
        ["Qdrant"]="6333:${QDRANT_PORT:-6333}:http://localhost:${QDRANT_PORT:-6333}"
        ["Milvus"]="19530:${MILVUS_PORT:-19530}:http://localhost:${MILVUS_PORT:-19530}"
        ["Signal API"]="8080:${SIGNAL_PORT:-8084}:http://localhost:${SIGNAL_PORT:-8084}"
        ["ClawdBot"]="8888:${CLAWDBOT_PORT:-8888}:http://localhost:${CLAWDBOT_PORT:-8888}"
    )

    for service in "${!services[@]}"; do
        IFS=':' read -r internal external url <<< "${services[$service]}"
        printf "%-20s %-15s %-15s %-30s\n" "$service" "$internal" "$external" "$url"
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Internal Service Discovery (Docker DNS)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    printf "%-25s %-40s\n" "CONTAINER NAME" "INTERNAL HOSTNAME"
    printf "%-25s %-40s\n" "─────────────────────────" "────────────────────────────────────────"
    printf "%-25s %-40s\n" "ai-dify-web" "ai-dify-web:80"
    printf "%-25s %-40s\n" "ai-n8n" "ai-n8n:5678"
    printf "%-25s %-40s\n" "ai-anythingllm" "ai-anythingllm:3001"
    printf "%-25s %-40s\n" "ai-postgres" "ai-postgres:5432"
    printf "%-25s %-40s\n" "ai-redis" "ai-redis:6379"
    printf "%-25s %-40s\n" "ai-weaviate" "ai-weaviate:8080"
    printf "%-25s %-40s\n" "ai-signal" "ai-signal:8080"
    printf "%-25s %-40s\n" "ai-clawdbot" "ai-clawdbot:8888"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  External Access (Public Ports)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "These ports are exposed to your host machine:"
    docker ps --format "table {{.Names}}\t{{.Ports}}" | grep "ai-"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Routing Rules"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "External Request → Host:PORT → Docker Container:INTERNAL_PORT"
    echo ""
    echo "Example:"
    echo "  Browser → localhost:${DIFY_PORT:-8200} → ai-dify-web:80"
    echo "  ClawdBot → ai-signal:8080 → Signal API"
    echo "  n8n → ai-postgres:5432 → PostgreSQL"

    echo ""
    read -p "Press Enter to return to menu..."
    show_main_menu
}

# ============================================================================
# 8. DIAGNOSE PORT CONNECTIVITY
# ============================================================================
diagnose_connectivity() {
    clear
    log_step "8" "Port Connectivity Diagnostics"
    echo ""

    cat << EOF
${CYAN}════════════════════════════════════════════════════════════${NC}
  🔍 CONNECTIVITY DIAGNOSTICS
${CYAN}════════════════════════════════════════════════════════════${NC}

Testing:
• Internal port availability
• Docker container connectivity
• External port accessibility
• Network routing

EOF

    # Load environment
    set -a
    source "${PROJECT_ROOT}/.env" 2>/dev/null
    set +a

    # Test internal ports
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Internal Port Checks (localhost)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    declare -A test_ports=(
        ["Dify"]="${DIFY_PORT:-8200}"
        ["n8n"]="${N8N_PORT:-5678}"
        ["AnythingLLM"]="${ANYTHINGLLM_PORT:-3001}"
        ["Flowise"]="${FLOWISE_PORT:-3000}"
        ["PostgreSQL"]="${POSTGRES_PORT:-5432}"
        ["Redis"]="${REDIS_PORT:-6379}"
        ["Weaviate"]="${WEAVIATE_PORT:-8383}"
        ["Signal API"]="${SIGNAL_PORT:-8084}"
        ["ClawdBot"]="${CLAWDBOT_PORT:-8888}"
    )

    for service in "${!test_ports[@]}"; do
        port="${test_ports[$service]}"
        printf "%-20s Port %-6s ... " "$service" "$port"

        if timeout 2 bash -c "echo >/dev/tcp/localhost/$port" 2>/dev/null; then
            echo -e "${GREEN}✓ OPEN${NC}"
        else
            echo -e "${RED}✗ CLOSED${NC}"
        fi
    done

    # Test Docker network
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Docker Network Connectivity"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if docker network inspect ai-platform &>/dev/null; then
        log_success "✓ Network 'ai-platform' exists"

        # Test container to container connectivity
        if docker ps --format '{{.Names}}' | grep -q "^ai-postgres$"; then
            echo ""
            echo "Testing inter-container connectivity..."

            # Try to ping PostgreSQL from n8n container
            if docker ps --format '{{.Names}}' | grep -q "^ai-n8n$"; then
                if docker exec ai-n8n sh -c "nc -zv ai-postgres 5432" &>/dev/null; then
                    log_success "✓ n8n can reach PostgreSQL (ai-postgres:5432)"
                else
                    log_error "✗ n8n cannot reach PostgreSQL"
                fi
            fi

            # Try to ping Weaviate from ClawdBot
            if docker ps --format '{{.Names}}' | grep -q "^ai-clawdbot$"; then
                if docker exec ai-clawdbot sh -c "nc -zv ai-weaviate 8080" &>/dev/null 2>&1; then
                    log_success "✓ ClawdBot can reach Weaviate (ai-weaviate:8080)"
                else
                    log_warning "⚠ ClawdBot cannot reach Weaviate (may not be running)"
                fi
            fi
        fi
    else
        log_error "✗ Network 'ai-platform' not found"
    fi

    # External connectivity test
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  External Connectivity Test"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    read -p "Test external connectivity via api64.ipify.org? (y/n) [y]: " -r
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo ""
        log_info "Detecting external IP address..."

        external_ip=$(curl -s https://api64.ipify.org?format=text 2>/dev/null || echo "Unable to detect")
        if [[ "$external_ip" != "Unable to detect" ]]; then
            log_success "✓ External IP: $external_ip"

            echo ""
            log_info "Testing if ports are accessible externally..."
            log_warning "Note: This requires port forwarding to be configured on your router"

            # Try to test via external service
            for service in "Dify" "n8n"; do
                port="${test_ports[$service]}"
                printf "  %-20s (Port %-6s) ... " "$service" "$port"

                # Use timeout and external port checker
                result=$(timeout 5 curl -s "https://portchecker.co/check?port=$port" 2>/dev/null | grep -o "open\|closed" | head -n1 || echo "timeout")

                if [[ "$result" == "open" ]]; then
                    echo -e "${GREEN}✓ ACCESSIBLE${NC}"
                elif [[ "$result" == "closed" ]]; then
                    echo -e "${YELLOW}⚠ NOT ACCESSIBLE (normal if no port forwarding)${NC}"
                else
                    echo -e "${BLUE}? UNABLE TO TEST${NC}"
                fi
            done
        else
            log_error "✗ Unable to detect external IP"
        fi
    fi

    # Firewall check
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Firewall Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if command -v ufw &>/dev/null; then
        sudo ufw status | head -n 20
    elif command -v firewall-cmd &>/dev/null; then
        sudo firewall-cmd --list-all | head -n 20
    else
        log_info "No firewall detected (ufw/firewalld)"
    fi

    echo ""
    read -p "Press Enter to return to menu..."
    show_main_menu
}

# ============================================================================
# 9. CONFIGURE PORTS WIZARD
# ============================================================================
configure_ports_wizard() {
    clear
    log_step "9" "Port Configuration Wizard"
    echo ""

    cat << EOF
${CYAN}════════════════════════════════════════════════════════════${NC}
  ⚙️  PORT CONFIGURATION
${CYAN}════════════════════════════════════════════════════════════${NC}

Modify port mappings for services.
Changes will update:
• .env file
• docker-compose configurations
• Requires service restart

EOF

    echo "Select service to configure:"
    echo ""
    echo "  1) Dify (currently: ${DIFY_PORT:-8200})"
    echo "  2) n8n (currently: ${N8N_PORT:-5678})"
    echo "  3) AnythingLLM (currently: ${ANYTHINGLLM_PORT:-3001})"
    echo "  4) Flowise (currently: ${FLOWISE_PORT:-3000})"
    echo "  5) PostgreSQL (currently: ${POSTGRES_PORT:-5432})"
    echo "  6) Redis (currently: ${REDIS_PORT:-6379})"
    echo "  7) Weaviate (currently: ${WEAVIATE_PORT:-8383})"
    echo "  8) Qdrant (currently: ${QDRANT_PORT:-6333})"
    echo "  9) Signal API (currently: ${SIGNAL_PORT:-8084})"
    echo " 10) ClawdBot (currently: ${CLAWDBOT_PORT:-8888})"
    echo "  0) Back to main menu"
    echo ""

    read -p "Select service [0-10]: " service_choice

    case $service_choice in
        1) configure_service_port "DIFY_PORT" "Dify" "${DIFY_PORT:-8200}" "80" ;;
        2) configure_service_port "N8N_PORT" "n8n" "${N8N_PORT:-5678}" "5678" ;;
        3) configure_service_port "ANYTHINGLLM_PORT" "AnythingLLM" "${ANYTHINGLLM_PORT:-3001}" "3001" ;;
        4) configure_service_port "FLOWISE_PORT" "Flowise" "${FLOWISE_PORT:-3000}" "3000" ;;
        5) configure_service_port "POSTGRES_PORT" "PostgreSQL" "${POSTGRES_PORT:-5432}" "5432" ;;
        6) configure_service_port "REDIS_PORT" "Redis" "${REDIS_PORT:-6379}" "6379" ;;
        7) configure_service_port "WEAVIATE_PORT" "Weaviate" "${WEAVIATE_PORT:-8383}" "8080" ;;
        8) configure_service_port "QDRANT_PORT" "Qdrant" "${QDRANT_PORT:-6333}" "6333" ;;
        9) configure_service_port "SIGNAL_PORT" "Signal API" "${SIGNAL_PORT:-8084}" "8080" ;;
        10) configure_service_port "CLAWDBOT_PORT" "ClawdBot" "${CLAWDBOT_PORT:-8888}" "8888" ;;
        0) show_main_menu; return ;;
        *)
            log_error "Invalid option"
            sleep 2
            configure_ports_wizard
            ;;
    esac
}

configure_service_port() {
    local env_var="$1"
    local service_name="$2"
    local current_port="$3"
    local internal_port="$4"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Configure ${service_name}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Current external port: ${current_port}"
    echo "Internal container port: ${internal_port} (fixed)"
    echo ""

    read -p "Enter new external port [${current_port}]: " new_port
    new_port=${new_port:-$current_port}

    # Validate port
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        log_error "Invalid port number"
        sleep 2
        configure_ports_wizard
        return
    fi

    # Check if port is in use
    if timeout 1 bash -c "echo >/dev/tcp/localhost/$new_port" 2>/dev/null; then
        log_warning "Port ${new_port} appears to be in use"
        read -p "Continue anyway? (y/n) [n]: " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            configure_ports_wizard
            return
        fi
    fi

    # Update .env
    if grep -q "^${env_var}=" "${PROJECT_ROOT}/.env"; then
        sed -i "s/^${env_var}=.*/${env_var}=${new_port}/" "${PROJECT_ROOT}/.env"
    else
        echo "${env_var}=${new_port}" >> "${PROJECT_ROOT}/.env"
    fi

    log_success "✓ Updated ${env_var}=${new_port} in .env"

    # Offer to regenerate stack configs
    echo ""
    read -p "Regenerate docker-compose files? (y/n) [y]: " -r
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        log_info "Regenerating stack configurations..."

        # Call generate_stack_configs from script 1
        if [[ -f "${SCRIPT_DIR}/1-setup-system.sh" ]]; then
            bash -c "source '${SCRIPT_DIR}/1-setup-system.sh' && generate_stack_configs" 2>&1 | tee -a "$LOGFILE"
        else
            log_warning "Cannot find 1-setup-system.sh to regenerate configs"
            log_info "Run manually: ./1-setup-system.sh"
        fi
    fi

    # Offer to restart service
    echo ""
    read -p "Restart ${service_name} service? (y/n) [n]: " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        local stack_name=$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        local stack_dir="${PROJECT_ROOT}/stacks/${stack_name}"

        if [[ -d "$stack_dir" ]]; then
            cd "$stack_dir"
            docker-compose down 2>&1 | tee -a "$LOGFILE"
            docker-compose up -d 2>&1 | tee -a "$LOGFILE"
            cd "$PROJECT_ROOT"
            log_success "✓ ${service_name} restarted with new port"
        else
            log_warning "Stack directory not found: $stack_dir"
        fi
    fi

    echo ""
    read -p "Press Enter to return to port configuration..."
    configure_ports_wizard
}

# ============================================================================
# 10. RUN SYSTEM DIAGNOSTICS
# ============================================================================
run_system_diagnostics() {
    clear
    log_step "10" "System Diagnostics"
    echo ""

    cat << EOF
${CYAN}════════════════════════════════════════════════════════════${NC}
  🔧 SYSTEM DIAGNOSTICS
${CYAN}════════════════════════════════════════════════════════════${NC}

Running comprehensive system checks...

EOF

    # Docker status
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Docker Environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if command -v docker &>/dev/null; then
        log_success "✓ Docker: $(docker --version)"
        log_success "✓ Docker Compose: $(docker-compose --version)"
    else
        log_error "✗ Docker not found"
    fi

    # Disk space
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Disk Usage"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    df -h / | tail -n 1

    # Docker disk usage
    echo ""
    echo "Docker volumes:"
    docker system df -v 2>/dev/null | head -n 20 || echo "Unable to check"

    # Running containers
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Running Containers"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "ai-|NAMES"

    # Memory usage
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Container Memory Usage"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep -E "ai-|NAME"

    # Check critical services
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Critical Services Health"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # PostgreSQL
    if docker ps --format '{{.Names}}' | grep -q "^ai-postgres$"; then
        if docker exec ai-postgres pg_isready -U ${POSTGRES_USER:-postgres} &>/dev/null; then
            log_success "✓ PostgreSQL: healthy"
        else
            log_error "✗ PostgreSQL: unhealthy"
        fi
    else
        log_warning "⚠ PostgreSQL: not running"
    fi

    # Redis
    if docker ps --format '{{.Names}}' | grep -q "^ai-redis$"; then
        if docker exec ai-redis redis-cli ping &>/dev/null; then
            log_success "✓ Redis: healthy"
        else
            log_error "✗ Redis: unhealthy"
        fi
    else
        log_warning "⚠ Redis: not running"
    fi

    # Weaviate
    if docker ps --format '{{.Names}}' | grep -q "^ai-weaviate$"; then
        if curl -sf "http://localhost:${WEAVIATE_PORT:-8383}/v1/.well-known/ready" | grep -q "true"; then
            log_success "✓ Weaviate: healthy"
        else
            log_warning "⚠ Weaviate: starting or unhealthy"
        fi
    else
        log_warning "⚠ Weaviate: not running"
    fi

    # Log files
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Recent Logs"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Log directory: ${LOGS_DIR}"
    ls -lht "${LOGS_DIR}" 2>/dev/null | head -n 10 || echo "No logs found"

    echo ""
    read -p "Press Enter to return to menu..."
    show_main_menu
}

# ============================================================================
# 11. VIEW SERVICE STATUS
# ============================================================================
view_service_status() {
    clear
    log_step "11" "Service Status Dashboard"
    echo ""

    cat << EOF
${CYAN}════════════════════════════════════════════════════════════${NC}
  📊 SERVICE STATUS DASHBOARD
${CYAN}════════════════════════════════════════════════════════════${NC}

EOF

    # All containers
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  All Services"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "ai-|NAMES"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Quick Actions"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  1) View container logs"
    echo "  2) Restart a service"
    echo "  3) Stop a service"
    echo "  4) Start a service"
    echo "  0) Back to main menu"
    echo ""

    read -p "Select action [0-4]: " action_choice

    case $action_choice in
        1) view_container_logs ;;
        2) restart_service_interactive ;;
        3) stop_service_interactive ;;
        4) start_service_interactive ;;
        0) show_main_menu ;;
        *) view_service_status ;;
    esac
}

view_container_logs() {
    echo ""
    echo "Available containers:"
    docker ps --format '{{.Names}}' | grep "^ai-" | nl
    echo ""
    read -p "Enter container number: " container_num

    container_name=$(docker ps --format '{{.Names}}' | grep "^ai-" | sed -n "${container_num}p")
    if [[ -n "$container_name" ]]; then
        echo ""
        log_info "Showing last 50 lines for $container_name (Ctrl+C to exit)"
        echo ""
        docker logs --tail 50 -f "$container_name"
    else
        log_error "Invalid selection"
    fi

    view_service_status
}

restart_service_interactive() {
    echo ""
    echo "Available containers:"
    docker ps --format '{{.Names}}' | grep "^ai-" | nl
    echo ""
    read -p "Enter container number to restart: " container_num

    container_name=$(docker ps --format '{{.Names}}' | grep "^ai-" | sed -n "${container_num}p")
    if [[ -n "$container_name" ]]; then
        docker restart "$container_name"
        log_success "✓ Restarted $container_name"
    else
        log_error "Invalid selection"
    fi

    sleep 2
    view_service_status
}

stop_service_interactive() {
    echo ""
    echo "Running containers:"
    docker ps --format '{{.Names}}' | grep "^ai-" | nl
    echo ""
    read -p "Enter container number to stop: " container_num

    container_name=$(docker ps --format '{{.Names}}' | grep "^ai-" | sed -n "${container_num}p")
    if [[ -n "$container_name" ]]; then
        docker stop "$container_name"
        log_success "✓ Stopped $container_name"
    else
        log_error "Invalid selection"
    fi

    sleep 2
    view_service_status
}

start_service_interactive() {
    echo ""
    echo "Stopped containers:"
    docker ps -a --filter "status=exited" --format '{{.Names}}' | grep "^ai-" | nl
    echo ""
    read -p "Enter container number to start: " container_num

    container_name=$(docker ps -a --filter "status=exited" --format '{{.Names}}' | grep "^ai-" | sed -n "${container_num}p")
    if [[ -n "$container_name" ]]; then
        docker start "$container_name"
        log_success "✓ Started $container_name"
    else
        log_error "Invalid selection"
    fi

    sleep 2
    view_service_status
}

# ============================================================================
# 12. UPDATE CONFIGURATION FILES
# ============================================================================
update_configuration_files() {
    clear
    log_step "12" "Update Configuration Files"
    echo ""

    cat << EOF
${CYAN}════════════════════════════════════════════════════════════${NC}
  📝 CONFIGURATION UPDATE
${CYAN}════════════════════════════════════════════════════════════${NC}

This will regenerate all stack configurations based on .env

EOF

    log_warning "This will overwrite existing docker-compose files!"
    echo ""
    read -p "Continue? (y/n) [n]: " -r

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        show_main_menu
        return
    fi

    # Backup existing configs
    log_info "Backing up existing configurations..."
    mkdir -p "${PROJECT_ROOT}/backups/config-backup-${TIMESTAMP}"
    cp -r "${PROJECT_ROOT}/stacks" "${PROJECT_ROOT}/backups/config-backup-${TIMESTAMP}/" 2>/dev/null || true
    log_success "✓ Backup created"

    # Regenerate configs
    log_info "Regenerating stack configurations..."

    if [[ -f "${SCRIPT_DIR}/1-setup-system.sh" ]]; then
        # Source and call the function
        (
            set -a
            source "${PROJECT_ROOT}/.env"
            set +a
            source "${SCRIPT_DIR}/1-setup-system.sh"
            generate_stack_configs
        ) 2>&1 | tee -a "$LOGFILE"

        log_success "✓ Configurations regenerated"

        echo ""
        read -p "Restart all services to apply changes? (y/n) [n]: " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Restarting services..."
            "${SCRIPT_DIR}/2-deploy-services.sh" restart 2>&1 | tee -a "$LOGFILE"
        fi
    else
        log_error "Cannot find 1-setup-system.sh"
    fi

    echo ""
    read -p "Press Enter to return to menu..."
    show_main_menu
}

# ============================================================================
# 13. COMPLETE SYSTEM PURGE
# ============================================================================
complete_system_purge() {
    clear

    cat << "EOF"
${RED}╔════════════════════════════════════════════════════════════╗
║                                                            ║
║                  ⚠️  SYSTEM PURGE WARNING ⚠️                 ║
║                                                            ║
║  This will PERMANENTLY DELETE:                             ║
║  • All Docker containers                                   ║
║  • All Docker volumes and data                             ║
║  • All configuration files                                 ║
║  • All logs                                                ║
║  • All backups                                             ║
║                                                            ║
║  THIS CANNOT BE UNDONE!                                    ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝${NC}
EOF

    echo ""
    log_error "You are about to destroy ALL platform data!"
    echo ""

    read -p "Type 'DELETE EVERYTHING' to confirm: " confirmation

    if [[ "$confirmation" != "DELETE EVERYTHING" ]]; then
        log_info "Purge cancelled"
        sleep 2
        show_main_menu
        return
    fi

    echo ""
    read -p "Final confirmation - proceed with purge? (yes/no): " final_confirm

    if [[ "$final_confirm" != "yes" ]]; then
        log_info "Purge cancelled"
        sleep 2
        show_main_menu
        return
    fi

    # Execute cleanup
    log_info "Executing complete system purge..."
    echo ""

    if [[ -f "${SCRIPT_DIR}/0-cleanup.sh" ]]; then
        "${SCRIPT_DIR}/0-cleanup.sh" 2>&1 | tee -a "$LOGFILE"
        log_success "✓ System purge completed"
    else
        log_error "Cleanup script not found: ${SCRIPT_DIR}/0-cleanup.sh"
    fi

    echo ""
    log_info "Platform has been completely removed"
    log_info "To reinstall, run: ./1-setup-system.sh"
    echo ""

    read -p "Press Enter to exit..."
    exit 0
}

# ============================================================================
# 14. RESET CONFIGURATION
# ============================================================================
reset_configuration() {
    clear
    log_step "14" "Reset Configuration"
    echo ""

    cat << EOF
${CYAN}════════════════════════════════════════════════════════════${NC}
  🔄 CONFIGURATION RESET
${CYAN}════════════════════════════════════════════════════════════${NC}

This will reset configuration to defaults (keeps data):
• Regenerate .env with default values
• Reset port mappings
• Clear custom settings

Docker volumes and data will NOT be deleted.

EOF

    log_warning "Current .env will be backed up to .env.backup"
    echo ""
    read -p "Continue? (y/n) [n]: " -r

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        show_main_menu
        return
    fi

    # Backup .env
    cp "${PROJECT_ROOT}/.env" "${PROJECT_ROOT}/.env.backup-${TIMESTAMP}"
    log_success "✓ Backed up .env to .env.backup-${TIMESTAMP}"

    # Regenerate .env
    log_info "Regenerating .env with defaults..."

    if [[ -f "${SCRIPT_DIR}/1-setup-system.sh" ]]; then
        # Run setup interactively
        "${SCRIPT_DIR}/1-setup-system.sh" 2>&1 | tee -a "$LOGFILE"
        log_success "✓ Configuration reset complete"
    else
        log_error "Setup script not found"
    fi

    echo ""
    read -p "Press Enter to return to menu..."
    show_main_menu
}

# ============================================================================
# HELPER FUNCTIONS FOR SYNC/BACKUP
# ============================================================================

create_sync_scripts() {
    # Script already created in Part 1
    log_info "Creating sync scripts..."

    # Upload script
    cat > "${PROJECT_ROOT}/scripts/sync-to-gdrive.sh" << 'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_ROOT}/.env"

echo "Syncing to Google Drive..."
rclone sync "${PROJECT_ROOT}/backups" "gdrive:ai-platform/backups" -v
rclone sync "${PROJECT_ROOT}/exports" "gdrive:ai-platform/exports" -v
rclone copy "${PROJECT_ROOT}/.env" "gdrive:ai-platform/configs/" -v

echo "✓ Sync completed"
EOFSCRIPT

    chmod +x "${PROJECT_ROOT}/scripts/sync-to-gdrive.sh"

    # Download script
    cat > "${PROJECT_ROOT}/scripts/restore-from-gdrive.sh" << 'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_ROOT}/.env"

echo "Restoring from Google Drive..."
rclone sync "gdrive:ai-platform/backups" "${PROJECT_ROOT}/backups" -v
rclone sync "gdrive:ai-platform/exports" "${PROJECT_ROOT}/exports" -v

echo "✓ Restore completed"
EOFSCRIPT

    chmod +x "${PROJECT_ROOT}/scripts/restore-from-gdrive.sh"

    log_success "✓ Sync scripts created"
}

create_backup_scripts() {
    log_info "Creating backup scripts..."

    # Backup script
    cat > "${PROJECT_ROOT}/scripts/backup-services.sh" << 'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_ROOT}/.env"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${PROJECT_ROOT}/backups/${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

echo "Creating backup: ${TIMESTAMP}"

# PostgreSQL
echo "Backing up PostgreSQL..."
docker exec ai-postgres pg_dumpall -U ${POSTGRES_USER:-postgres} | gzip > "${BACKUP_DIR}/postgres.sql.gz"

# Redis (if running)
if docker ps --format '{{.Names}}' | grep -q "^ai-redis$"; then
    echo "Backing up Redis..."
    docker exec ai-redis redis-cli --rdb /data/dump.rdb
    docker cp ai-redis:/data/dump.rdb "${BACKUP_DIR}/redis.rdb"
fi

# Volumes
echo "Backing up volumes..."
mkdir -p "${BACKUP_DIR}/volumes"
docker run --rm -v ai-dify-data:/data -v "${BACKUP_DIR}/volumes":/backup alpine tar czf /backup/dify-data.tar.gz -C /data . 2>/dev/null || true
docker run --rm -v ai-anythingllm-data:/data -v "${BACKUP_DIR}/volumes":/backup alpine tar czf /backup/anythingllm-data.tar.gz -C /data . 2>/dev/null || true

# Config backup
cp "${PROJECT_ROOT}/.env" "${BACKUP_DIR}/.env.backup"

# Cleanup old backups
find "${PROJECT_ROOT}/backups" -type d -mtime +${BACKUP_RETENTION_DAYS:-30} -exec rm -rf {} + 2>/dev/null || true

echo "✓ Backup completed: ${BACKUP_DIR}"
EOFSCRIPT

    chmod +x "${PROJECT_ROOT}/scripts/backup-services.sh"
    log_success "✓ Backup script created"
}

setup_cron_sync() {
    log_info "Setting up automatic sync schedule..."

    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "sync-to-gdrive"; echo "0 2 * * * ${PROJECT_ROOT}/scripts/sync-to-gdrive.sh >> ${LOGS_DIR}/cron-sync.log 2>&1") | crontab -

    log_success "✓ Daily sync scheduled for 2:00 AM"
}

setup_cron_backup() {
    log_info "Setting up automatic backup schedule..."

    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "backup-services"; echo "0 3 * * * ${PROJECT_ROOT}/scripts/backup-services.sh >> ${LOGS_DIR}/cron-backup.log 2>&1") | crontab -

    log_success "✓ Daily backup scheduled for 3:00 AM"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    show_banner
    load_environment
    show_main_menu
}

main "$@"
