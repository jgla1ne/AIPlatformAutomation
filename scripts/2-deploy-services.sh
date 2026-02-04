#!/bin/bash

#############################################################################
# Script 2: Deploy AI Platform Services
# Version: 73.0.0
# Description: Deploys all 26 services with dynamic configuration
# Last Updated: 2026-02-04
# FIX: Safe variable handling, no unbound variable errors
#############################################################################

# SAFER: Don't fail on unbound variables during .env sourcing
set -euo pipefail

#############################################################################
# GLOBAL VARIABLES
#############################################################################

readonly SCRIPT_VERSION="73.0.0"
readonly SCRIPT_NAME="2-deploy-services.sh"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ... (keep all color codes and symbols)

# Paths
readonly INSTALL_DIR="/opt/ai-platform"
readonly ENV_FILE="${INSTALL_DIR}/.env"
readonly COMPOSE_DIR="${INSTALL_DIR}/compose"
readonly LOG_DIR="/var/log/ai-platform"
readonly DATA_DIR="/var/lib/ai-platform"
readonly CONFIG_DIR="${INSTALL_DIR}/config"
readonly BACKUP_DIR="/var/backups/ai-platform"

# ... (keep logging functions)

#############################################################################
# SAFE ENVIRONMENT LOADING
#############################################################################

load_environment() {
    if [ ! -f "${ENV_FILE}" ]; then
        log_error "Environment file not found: ${ENV_FILE}"
        log_info "Please run: sudo ./1-setup-system.sh"
        return 1
    fi
    
    # Temporarily disable unbound variable check
    set +u
    
    # Source with error handling
    # shellcheck disable=SC1090
    if ! source "${ENV_FILE}"; then
        log_error "Failed to source environment file"
        set -u
        return 1
    fi
    
    # Re-enable unbound variable check
    set -u
    
    # Validate critical variables
    local missing_vars=()
    
    [[ -z "${HOST_IP:-}" ]] && missing_vars+=("HOST_IP")
    [[ -z "${POSTGRES_PASSWORD:-}" ]] && missing_vars+=("POSTGRES_PASSWORD")
    [[ -z "${REDIS_PASSWORD:-}" ]] && missing_vars+=("REDIS_PASSWORD")
    [[ -z "${LITELLM_MASTER_KEY:-}" ]] && missing_vars+=("LITELLM_MASTER_KEY")
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - ${var}"
        done
        log_info "Please re-run: sudo ./1-setup-system.sh"
        return 1
    fi
    
    log_success "Environment loaded successfully"
    return 0
}

#############################################################################
# MAIN EXECUTION (FIXED)
#############################################################################

main() {
    clear
    cat << 'BANNER_EOF'
╔════════════════════════════════════════════════════════════════════╗
║                                                                    ║
║              AI Platform Service Deployment                        ║
║                      Version 73.0.0                                ║
║                                                                    ║
║    Enhanced: Dynamic Ports | Tailscale | Ollama | LiteLLM | APIs  ║
║                                                                    ║
╚════════════════════════════════════════════════════════════════════╝
BANNER_EOF
    echo ""
    
    # Check root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Setup logging
    mkdir -p "${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/deploy-$(date +%Y%m%d_%H%M%S).log"
    
    log_info "Starting deployment process..."
    echo ""
    
    # FIXED: Safe environment loading
    if ! load_environment; then
        exit 1
    fi
    
    # Continue with deployment...
    # (rest of your deployment code)
}

main "$@"
exit $?
