#!/usr/bin/env bash
# =============================================================================
# Script 3: Mission Control - Utility Library - STABLE v4.0
# =============================================================================
# PURPOSE: Central utility library for logging and common functions.
# =============================================================================

set -euo pipefail

# --- Color and Logging Definitions (Exportable) ---
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $*"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }

# =============================================================================
# --- UTILITY FUNCTIONS (Available to all scripts that source this file) ---
# =============================================================================

# --- Environment Utilities ---
load_tenant_env() {
    local tenant_id="$1"
    local env_file="/mnt/data/${tenant_id}/.env"
    if [[ ! -f "$env_file" ]]; then
        fail "Environment file not found for tenant '${tenant_id}' at ${env_file}"
    fi
    log "Loading environment from: ${env_file}"
    set -a
    source "$env_file"
    set +a
}

# --- Service Management Utilities ---
start_service() {
    local service="$1"
    log "Starting service: $service..."
    docker compose up -d "$service"
    ok "Service '$service' is starting. Check '--status'."
}

# --- Export all utility functions for other scripts to use ---
export -f log ok warn fail load_tenant_env start_service

# =============================================================================
# --- MAIN EXECUTION BLOCK (Only runs when script is executed directly) ---
# =============================================================================

# Correct Source Safety Guard
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then

    main() {
        if [[ -z "${1:-}" ]]; then
            fail "TENANT_ID is required. Usage: sudo bash $0 <tenant_id> [action]"
        fi
        local TENANT_ID="$1"
        shift

        load_tenant_env "${TENANT_ID}"
        cd "${DATA_ROOT}"

        local ACTION=${1:---status}
        local SERVICE=${2:-}
        
        case "$ACTION" in
            --start) [ -z "$SERVICE" ] && fail "Usage: $0 $TENANT_ID --start <service_name>" || start_service "$SERVICE" ;; 
            --status) echo "Showing status..." ;; # Placeholder
            *) echo "Invalid action" ;;
        esac
    }

    # Execute the main function with all script arguments
    main "$@"
fi
