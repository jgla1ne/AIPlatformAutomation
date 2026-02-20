#!/bin/bash

set -euo pipefail

# Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DATA_ROOT="/mnt/data"
readonly METADATA_DIR="$DATA_ROOT/metadata"
readonly LOG_FILE="$DATA_ROOT/logs/setup.log"
readonly ENV_FILE="$DATA_ROOT/.env"
readonly SERVICES_FILE="$METADATA_DIR/selected_services.json"

# Basic logging
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE" 2>/dev/null || echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# UI Functions
print_banner() {
    clear
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            AI PLATFORM AUTOMATION - SETUP                    ║${NC}"
    echo -e "${CYAN}║              Version 4.5.0 - Simple Working Version      ║${NC}"
    echo -e "${CYAN}║           Volume Detection + Domain Configuration          ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}\n"
}

print_header() {
    echo -e "\n${CYAN}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Directory structure creation
create_directory_structure() {
    log "INFO" "Creating directory structure..."
    mkdir -p "$DATA_ROOT" "$METADATA_DIR" "$DATA_ROOT/logs" "$DATA_ROOT/config" "$DATA_ROOT/data" "$DATA_ROOT/ssl" "$DATA_ROOT/backups" "$DATA_ROOT/scripts" "$DATA_ROOT/scripts/lib"
    log "SUCCESS" "Directory structure created"
}

# Service Selection
select_services() {
    print_header "🎯 Service Selection"
    
    echo ""
    print_info "Select services to deploy:"
    echo ""
    echo "🏗️  Infrastructure:"
    echo "  [1] PostgreSQL - Relational database"
    echo "  [2] Redis - Cache and message queue"
    echo ""
    echo "🤖 AI Applications:"
    echo "  [3] Open WebUI - Modern ChatGPT-like interface"
    echo "  [4] n8n - Workflow automation platform"
    echo "  [5] Ollama - Local LLM runtime"
    echo ""
    echo "📊 Monitoring:"
    echo "  [6] Grafana - Metrics and visualization"
    echo ""
    echo "📦 Storage:"
    echo "  [7] MinIO - S3-compatible storage"
    echo ""
    
    echo "Enter selection (space-separated, e.g., '1 3 6'):"
    echo -n "Selection: "
    read -r selection
    
    # Simple service mapping
    SELECTED_SERVICES=()
    for num in $selection; do
        case $num in
            1) SELECTED_SERVICES+=("postgres") ;;
            2) SELECTED_SERVICES+=("redis") ;;
            3) SELECTED_SERVICES+=("openwebui") ;;
            4) SELECTED_SERVICES+=("n8n") ;;
            5) SELECTED_SERVICES+=("ollama") ;;
            6) SELECTED_SERVICES+=("grafana") ;;
            7) SELECTED_SERVICES+=("minio") ;;
        esac
    done
    
    # Save selected services
    mkdir -p "$(dirname "$SERVICES_FILE")"
    cat > "$SERVICES_FILE" <<EOF
{
  "total_services": ${#SELECTED_SERVICES[@]},
  "selected_services": [
EOF
    
    local first=true
    for service in "${SELECTED_SERVICES[@]}"; do
        if [[ "$first" == false ]]; then
            echo "," >> "$SERVICES_FILE"
        fi
        first=false
        echo "    \"$service\"" >> "$SERVICES_FILE"
    done
    
    cat >> "$SERVICES_FILE" <<EOF
  ]
}
EOF
    
    print_success "Services selected: ${SELECTED_SERVICES[*]}"
}

# Configuration collection
collect_configurations() {
    print_header "⚙️ Configuration Collection"
    
    # Get running user information
    RUNNING_USER="${SUDO_USER:-$USER}"
    RUNNING_UID=$(id -u "$RUNNING_USER")
    RUNNING_GID=$(id -g "$RUNNING_USER")
    
    # Initialize environment file
    cat > "$ENV_FILE" <<EOF
# AI Platform Environment
# Generated: $(date -Iseconds)

# System Configuration
DATA_ROOT=$DATA_ROOT
METADATA_DIR=$METADATA_DIR
TIMEZONE=UTC
LOG_LEVEL=info

# Network Configuration
DOMAIN=localhost
DOMAIN_NAME=localhost
PROXY_CONFIG_METHOD=alias
PROXY_TYPE=caddy
SSL_TYPE=letsencrypt
SSL_EMAIL=hosting@datasquiz.net

# User Configuration
RUNNING_USER=$RUNNING_USER
RUNNING_UID=$RUNNING_UID
RUNNING_GID=$RUNNING_GID
BIND_IP=0.0.0.0
EOF
    
    # Add sub-path environment variables for selected services
    local proxy_domain="${DOMAIN_NAME:-localhost}"
    
    if [[ " ${SELECTED_SERVICES[*]} " =~ " n8n " ]]; then
        echo "N8N_PATH=/n8n/" >> "$ENV_FILE"
        echo "N8N_EDITOR_BASE_URL=https://$proxy_domain/n8n/" >> "$ENV_FILE"
        echo "N8N_WEBHOOK_URL=https://$proxy_domain/n8n/" >> "$ENV_FILE"
        print_success "n8n sub-path variables configured"
    fi
    
    if [[ " ${SELECTED_SERVICES[*]} " =~ " grafana " ]]; then
        echo "GF_SERVER_ROOT_URL=https://$proxy_domain/grafana/" >> "$ENV_FILE"
        echo "GF_SERVER_SERVE_FROM_SUB_PATH=true" >> "$ENV_FILE"
        print_success "grafana sub-path variables configured"
    fi
    
    if [[ " ${SELECTED_SERVICES[*]} " =~ " openwebui " ]]; then
        echo "WEBUI_URL=https://$proxy_domain/openwebui" >> "$ENV_FILE"
        print_success "openwebui sub-path variables configured"
    fi
    
    if [[ " ${SELECTED_SERVICES[*]} " =~ " minio " ]]; then
        echo "MINIO_BROWSER_REDIRECT_URL=https://$proxy_domain/minio" >> "$ENV_FILE"
        echo "MINIO_SERVER_URL=https://$proxy_domain/minio" >> "$ENV_FILE"
        print_success "minio sub-path variables configured"
    fi
    
    print_success "Configuration collection completed"
}

# Main Execution
main() {
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
    
    # Create directory structure FIRST
    create_directory_structure
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    log "INFO" "Logging initialized"
    
    # Initialize service manifest
    mkdir -p "$(dirname "/mnt/data/config/installed_services.json")"
    echo '{"services": {}}' > "/mnt/data/config/installed_services.json"
    
    # Display banner
    print_banner
    
    # Execute phases
    select_services
    collect_configurations
    
    echo ""
    print_success "Script 1 setup completed successfully!"
    echo ""
    print_info "Directory structure created at: $DATA_ROOT"
    print_info "Environment file created at: $ENV_FILE"
    print_info "Service manifest created at: /mnt/data/config/installed_services.json"
    print_info "Selected services: ${SELECTED_SERVICES[*]}"
    echo ""
    print_info "You can now run: ./2-deploy-services.sh"
}

# Execute main function
main "$@"
