#!/usr/bin/env bash
# =============================================================================
# Script 0: Nuclear Cleanup - README COMPLIANT
# =============================================================================
# PURPOSE: Stop containers, remove data, clear all state
# USAGE:   sudo bash scripts/0-complete-cleanup.sh [tenant_id] [options]
# OPTIONS: --dry-run           Show what would be removed without action
#          --containers-only  Only remove containers, keep data
# =============================================================================

set -euo pipefail

# =============================================================================
# ROOT EXECUTION CHECK (README P7 - exception for script 0)
# =============================================================================
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root for complete cleanup"
    exit 1
fi

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# =============================================================================
# LOGGING (README P11)
# =============================================================================
LOG_FILE=""
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}
ok() { log "OK: $*"; }
warn() { log "WARN: $*"; }
fail() { log "FAIL: $*"; exit 1; }
dry_run() { [[ "${DRY_RUN:-false}" == "true" ]] && echo "[DRY-RUN] $1"; }

# =============================================================================
# CONFIRMATION FUNCTIONS
# =============================================================================
typed_confirmation() {
    local confirmation="$1"
    local expected="$2"
    
    echo ""
    read -r -p "  Type '${expected}' to confirm: " input
    if [[ "$input" != "$expected" ]]; then
        fail "Confirmation failed. Expected '${expected}' but got '${input}'"
    fi
}

# =============================================================================
# CONTAINER CLEANUP
# =============================================================================
cleanup_containers() {
    local tenant_id="$1"
    local prefix="${2:-ai}"
    
    log "Cleaning up containers for tenant '${tenant_id}'..."
    
    # Get list of tenant containers
    local containers
    containers=$(docker ps -a --format "{{.Names}}" | grep "^${prefix}-${tenant_id}-" || true)
    
    if [[ -z "$containers" ]]; then
        log "No containers found for tenant ${tenant_id}"
        return 0
    fi
    
    # Stop and remove containers
    for container in $containers; do
        log "Stopping container: ${container}"
        dry_run "docker stop ${container}"
        [[ "${DRY_RUN:-false}" != "true" ]] && docker stop "${container}" >/dev/null 2>&1 || true
        
        log "Removing container: ${container}"
        dry_run "docker rm ${container}"
        [[ "${DRY_RUN:-false}" != "true" ]] && docker rm "${container}" >/dev/null 2>&1 || true
    done
    
    ok "Containers cleaned up"
}

# =============================================================================
# NETWORK CLEANUP
# =============================================================================
cleanup_networks() {
    local tenant_id="$1"
    local prefix="${2:-ai}"
    
    log "Cleaning up networks for tenant '${tenant_id}'..."
    
    # Get list of tenant networks
    local networks
    networks=$(docker network ls --format "{{.Name}}" | grep "^${prefix}-${tenant_id}" || true)
    
    if [[ -z "$networks" ]]; then
        log "No networks found for tenant ${tenant_id}"
        return 0
    fi
    
    # Remove networks
    for network in $networks; do
        log "Removing network: ${network}"
        dry_run "docker network rm ${network}"
        [[ "${DRY_RUN:-false}" != "true" ]] && docker network rm "${network}" >/dev/null 2>&1 || true
    done
    
    ok "Networks cleaned up"
}

# =============================================================================
# VOLUME CLEANUP (README P10 - bind mounts only)
# =============================================================================
cleanup_volumes() {
    local tenant_id="$1"
    
    if [[ "${CONTAINERS_ONLY:-false}" == "true" ]]; then
        log "Skipping volume cleanup (containers-only mode)"
        return 0
    fi
    
    log "Cleaning up data directories for tenant '${tenant_id}'..."
    
    local base_dir="/mnt/${tenant_id}"
    
    if [[ -d "$base_dir" ]]; then
        log "Removing data directory: ${base_dir}"
        dry_run "rm -rf ${base_dir}"
        [[ "${DRY_RUN:-false}" != "true" ]] && rm -rf "${base_dir}"
    fi
    
    ok "Data directories cleaned up"
}

# =============================================================================
# CONFIGURED MARKERS CLEANUP (README P8)
# =============================================================================
cleanup_markers() {
    local tenant_id="$1"
    local configured_dir="/mnt/${tenant_id}/.configured"
    
    if [[ -d "$configured_dir" ]]; then
        log "Removing configuration markers for tenant '${tenant_id}'..."
        dry_run "rm -rf ${configured_dir}"
        [[ "${DRY_RUN:-false}" != "true" ]] && rm -rf "${configured_dir}"
    fi
    
    ok "Configuration markers cleaned up"
}

# =============================================================================
# SYSTEM CLEANUP
# =============================================================================
cleanup_system() {
    if [[ "${CONTAINERS_ONLY:-false}" == "true" ]]; then
        log "Skipping system cleanup (containers-only mode)"
        return 0
    fi
    
    log "Performing final system cleanup..."
    
    # Clean up any orphaned Docker resources
    dry_run "docker system prune -f"
    [[ "${DRY_RUN:-false}" != "true" ]] && docker system prune -f >/dev/null 2>&1 || true
    
    ok "System cleanup completed"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    local tenant_id="${1:-}"
    local dry_run=false
    local containers_only=false
    
    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --containers-only)
                containers_only=true
                shift
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
    
    # Set global variables
    export DRY_RUN="$dry_run"
    export CONTAINERS_ONLY="$containers_only"
    
    # Set up logging
    LOG_FILE="/tmp/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log"
    
    log "=== Script 0: Nuclear Cleanup ==="
    log "Tenant: ${tenant_id}"
    log "Dry-run: ${dry_run}"
    log "Containers-only: ${containers_only}"
    
    if [[ -z "$tenant_id" ]]; then
        fail "Tenant ID is required"
    fi
    
    # Warning and confirmation
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║         AI Platform — Nuclear Cleanup                 ║"
    echo "║                    Script 0 of 4                        ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo "  ⚠️  WARNING: This will COMPLETELY REMOVE:"
    echo "     • All containers for tenant '${tenant_id}'"
    echo "     • All networks for tenant '${tenant_id}'"
    if [[ "${containers_only}" != "true" ]]; then
        echo "     • All data directories for tenant '${tenant_id}'"
        echo "     • All configuration markers"
        echo "     • All system resources (prune)"
    fi
    echo ""
    echo "  This action cannot be undone!"
    echo ""
    
    if [[ "${dry_run}" != "true" ]]; then
        typed_confirmation "NUKE-${tenant_id}" "NUKE-${tenant_id}"
    fi
    
    # Execute cleanup steps
    cleanup_containers "$tenant_id" "ai"
    cleanup_networks "$tenant_id" "ai"
    cleanup_volumes "$tenant_id"
    cleanup_markers "$tenant_id"
    cleanup_system
    
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║              Script 0 Complete ✓                        ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo "  ✓ All containers stopped and removed"
    echo "  ✓ All networks removed"
    if [[ "${containers_only}" != "true" ]]; then
        echo "  ✓ All data directories removed"
        echo "  ✓ Configuration markers cleared"
        echo "  ✓ System resources pruned"
    fi
    echo ""
    if [[ "${dry_run}" != "true" ]]; then
        echo "  Tenant '${tenant_id}' has been completely nuked"
    else
        echo "  DRY RUN: Tenant '${tenant_id}' would be completely nuked"
    fi
    echo ""
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
