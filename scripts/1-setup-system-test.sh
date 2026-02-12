#!/bin/bash

set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Paths
readonly DATA_ROOT="/mnt/data"
readonly METADATA_DIR="$DATA_ROOT/metadata"

print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║            AI PLATFORM AUTOMATION - SETUP                      ║"
    echo "║                      Version 4.0.0                               ║"
    echo "║                Configuration Collection Only                ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

setup_logging() {
    mkdir -p "$DATA_ROOT/logs"
    local log_file="$DATA_ROOT/logs/setup.log"
    exec 1> >(tee -a "$log_file")
    exec 2> >(tee -a "$log_file" >&2)
}

create_directory_structure() {
    print_info "Creating directory structure..."
    
    mkdir -p "$DATA_ROOT"/{compose,env,config,metadata,data,logs,secrets}
    
    print_success "Directory structure created"
    print_info "Base: $DATA_ROOT"
}

generate_basic_env() {
    print_info "Generating basic environment file..."
    
    local env_file="$DATA_ROOT/.env"
    
    cat > "$env_file" <<EOF
# AI Platform Environment
# Generated: $(date -Iseconds)

# Paths
DATA_ROOT=$DATA_ROOT
METADATA_DIR=$METADATA_DIR

# Basic Configuration
TIMEZONE=UTC
LOG_LEVEL=info

# Generated Secrets
ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
JWT_SECRET=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)
EOF
    
    print_success "Environment file generated: $env_file"
}

main() {
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
    
    # Setup
    setup_logging
    
    # Display banner
    print_banner
    
    print_info "Starting AI Platform Setup..."
    echo ""
    
    # Create structure
    create_directory_structure
    
    # Generate basic config
    generate_basic_env
    
    echo ""
    print_success "🎉 SETUP SCRIPT COMPLETED SUCCESSFULLY!"
    echo ""
    print_info "Next: Run the compose generator script:"
    echo ""
    echo -e "${CYAN}sudo bash 2-deploy-services.sh${NC}"
    echo ""
    
    exit 0
}

main "$@"
