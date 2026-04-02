#!/usr/bin/env bash
# =============================================================================
# Script 0: Nuclear Cleanup — README v5.1.0 COMPLIANT
# =============================================================================
# PURPOSE: Stop containers, remove data, clear all state
# USAGE:   sudo bash scripts/0-complete-cleanup.sh [tenant_id] [options]
# OPTIONS: --dry-run           Show what would be removed without action
#          --containers-only  Only remove containers, keep data
#          --unmount-ebs      Unmount EBS volume after cleanup
# =============================================================================

set -euo pipefail
trap 'echo "ERROR at line $LINENO. Check logs."; exit 1' ERR

# =============================================================================
# ROOT EXECUTION CHECK (README P7 exception - script 0 requires root)
# =============================================================================
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root: sudo bash $0 $*"
    exit 1
fi

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_VERSION="5.1.0"

# =============================================================================
# LOGGING (README P11)
# =============================================================================
LOG_FILE="/var/log/ai-platform-cleanup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
}
ok() { log "OK: $*"; }
warn() { log "WARN: $*"; }
fail() { log "FAIL: $*"; exit 1; }
dry_run() { [[ "${DRY_RUN:-false}" == "true" ]] && echo "[DRY-RUN] $1"; }

# =============================================================================
# DRY RUN COMMAND EXECUTOR (README §12)
# =============================================================================
run_cmd() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# =============================================================================
# TYPED CONFIRMATION (README §6 - mandatory pattern)
# =============================================================================
confirm_destructive() {
    echo "  ⚠️  This will permanently delete ALL data for tenant: ${tenant_id}"
    echo "  Type exactly to confirm: DELETE ${tenant_id}"
    read -r response
    [[ "${response}" == "DELETE ${tenant_id}" ]] \
        || { echo "Confirmation did not match. Aborting."; exit 1; }
}

# =============================================================================
# MAIN FUNCTION (README §6 - strict execution order)
# =============================================================================
main() {
    local tenant_id="${1:-}"
    local dry_run=false
    local containers_only=false
    local unmount_ebs=false
    
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
            --unmount-ebs)
                unmount_ebs=true
                shift
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
    
    # Set global variables
    export DRY_RUN="$dry_run"
    
    # Validate tenant ID
    if [[ -z "$tenant_id" ]]; then
        fail "Tenant ID is required"
    fi
    
    # Set up logging
    LOG_FILE="/tmp/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log"
    
    log "=== Script 0: Nuclear Cleanup ==="
    log "Version: ${SCRIPT_VERSION}"
    log "Tenant: ${tenant_id}"
    log "Dry-run: ${dry_run}"
    log "Containers-only: ${containers_only}"
    log "Unmount-ebs: ${unmount_ebs}"
    
    # Display banner
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         AI Platform — Nuclear Cleanup                 ║"
    echo "║                    Script 0 of 4                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
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
    
    # Typed confirmation (README §6 - mandatory)
    if [[ "${dry_run}" != "true" ]]; then
        confirm_destructive
    fi
    
    # Source platform.conf (README P1 - BUG-02 fix)
    local platform_conf="/mnt/${tenant_id}/platform.conf"
    # Set defaults that work whether platform.conf exists or not
    export TENANT_PREFIX="${tenant_id}"
    export TENANT_ID="${tenant_id}"
    export BASE_DIR="/mnt/${tenant_id}"
    export DATA_DIR="${BASE_DIR}/data"
    export CONFIG_DIR="${BASE_DIR}/config"
    export CONFIGURED_DIR="${BASE_DIR}/.configured"
    export LOG_DIR="${BASE_DIR}/logs"
    export DOCKER_NETWORK="${tenant_id}-network"
    
    if [[ ! -f "$platform_conf" ]]; then
        warn "platform.conf not found at $platform_conf. Attempting partial cleanup..."
        # Skip docker compose cleanup since we don't have compose file path
        log "Skipping docker compose cleanup (no platform.conf)"
    else
        # shellcheck source=/dev/null
        source "$platform_conf"
    fi
    
    # Source shared configuration now that variables are set
    [[ -f "${SCRIPT_DIR}/shared-config.sh" ]] && source "${SCRIPT_DIR}/shared-config.sh"
    
    # Remove nginx config and reload if active
    rm -f /etc/nginx/sites-enabled/ai-platform
    rm -f /etc/nginx/sites-available/ai-platform
    if systemctl is-active nginx &>/dev/null; then
        nginx -t && systemctl reload nginx || warn "Nginx config reload failed"
    fi
    
    # Remove systemd service and reload daemon
    systemctl disable ai-platform 2>/dev/null || true
    rm -f /etc/systemd/system/ai-platform.service
    systemctl daemon-reload
    
    # Execution order (README §6 - strict):
    # 1. Typed confirmation: DELETE ${TENANT_ID} (done above)
    
    # 2. docker compose down --volumes --remove-orphans
    log "Stopping and removing containers with docker compose..."
    [[ -n "$DATA_DIR" && "$DATA_DIR" != "/" ]] || { echo "ERROR: Invalid DATA_DIR: $DATA_DIR"; exit 1; }
    
    # Stop and remove containers with timeout
    if [[ -f "$COMPOSE_FILE" ]]; then
        docker compose -f "$COMPOSE_FILE" down --timeout 30 --volumes 2>/dev/null || true
        ok "Containers stopped and removed via docker compose"
    else
        log "No compose file found at $COMPOSE_FILE"
        # Try manual container removal
        local containers
        containers=$(docker ps -aq --filter "label=com.docker.compose.project=${tenant_id}" 2>/dev/null || true)
        if [[ -n "$containers" ]]; then
            for container in $containers; do
                run_cmd docker stop "$container" >/dev/null 2>&1 || true
                run_cmd docker rm "$container" >/dev/null 2>&1 || true
            done
            ok "Containers stopped and removed manually"
        else
            log "No containers found for tenant ${tenant_id}"
        fi
    fi
    
    # 3. Remove images (scoped by label AND tenant prefix - README §6)
    log "Removing Docker images (scoped to tenant)..."
    
    # By compose project label
    local images_by_label
    images_by_label=$(docker images \
        --filter "label=com.docker.compose.project=${TENANT_ID}" \
        -q 2>/dev/null || true)
    if [[ -n "$images_by_label" ]]; then
        echo "$images_by_label" | xargs -r run_cmd docker rmi --force
        log "  Removed images by project label"
    fi
    
    # By name prefix (catches label-less images)
    local images_by_prefix
    images_by_prefix=$(docker images --format "{{.Repository}}:{{.Tag}}" \
        | grep "^${TENANT_PREFIX}-" 2>/dev/null || true)
    if [[ -n "$images_by_prefix" ]]; then
        echo "$images_by_prefix" | xargs -r run_cmd docker rmi --force
        log "  Removed images by name prefix"
    fi
    
    ok "Docker images removed (scoped)"
    
    # Skip data removal if containers-only mode
    if [[ "${containers_only}" == "true" ]]; then
        log "Skipping data removal (containers-only mode)"
    else
        # 4. rm -rf "${DATA_DIR}" (P1 fix - safety guard)
        if [[ -n "${DATA_DIR:-}" && -d "${DATA_DIR}" && ("${DATA_DIR}" =~ ^/opt/ || "${DATA_DIR}" =~ ^/mnt/) ]]; then
            log "Removing data directory: ${DATA_DIR}"
            run_cmd rm -rf "${DATA_DIR}"
            ok "Data directory removed"
        elif [[ -z "${DATA_DIR:-}" ]]; then
            warn "DATA_DIR is empty - skipping data removal"
        else
            fail "DATA_DIR '${DATA_DIR}' is invalid. Refusing to delete (must be in /opt/ or /mnt/)."
        fi
        
        # 5. rm -rf "${CONFIG_DIR}"
        if [[ -n "${CONFIG_DIR:-}" && -d "${CONFIG_DIR}" ]]; then
            log "Removing config directory: ${CONFIG_DIR}"
            run_cmd rm -rf "${CONFIG_DIR}"
            ok "Config directory removed"
        fi
        
        # 6. rm -rf "${CONFIGURED_DIR}" ← CRITICAL: clears idempotency markers
        if [[ -n "${CONFIGURED_DIR:-}" && -d "${CONFIGURED_DIR}" ]]; then
            log "Removing configuration markers: ${CONFIGURED_DIR}"
            run_cmd rm -rf "${CONFIGURED_DIR}"
            ok "Configuration markers removed"
        fi
        
        # 7. rm -rf "${LOG_DIR}"
        if [[ -n "${LOG_DIR:-}" && -d "${LOG_DIR}" ]]; then
            log "Removing logs directory: ${LOG_DIR}"
            run_cmd rm -rf "${LOG_DIR}"
            ok "Logs directory removed"
        fi
        
        # 8. rm -rf "${BASE_DIR}" ← CRITICAL: remove the entire tenant directory
        if [[ -n "${BASE_DIR:-}" && -d "${BASE_DIR}" ]]; then
            log "Removing base tenant directory: ${BASE_DIR}"
            if [[ "${dry_run}" != "true" ]]; then
                rm -rf "${BASE_DIR}"
            fi
            ok "Base tenant directory removed"
        fi
    fi
    
    # 9. docker network rm "${DOCKER_NETWORK}" || true
    if [[ -n "${DOCKER_NETWORK:-}" ]]; then
        log "Removing Docker network: ${DOCKER_NETWORK}"
        run_cmd docker network rm "${DOCKER_NETWORK}" || true
        ok "Docker network removed"
    fi
    
    # 9. Optional: unmount EBS (--unmount-ebs flag)
    if [[ "${unmount_ebs}" == "true" ]]; then
        local mount_point="/mnt/${tenant_id}"
        if mountpoint -q "$mount_point" 2>/dev/null; then
            log "Unmounting EBS volume: $mount_point"
            run_cmd umount "$mount_point"
            ok "EBS volume unmounted"
        else
            log "EBS volume not mounted or mount point not found"
        fi
    fi
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              Script 0 Complete ✓                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ✓ All containers stopped and removed"
    echo "  ✓ All networks removed"
    if [[ "${containers_only}" != "true" ]]; then
        echo "  ✓ All data directories removed"
        echo "  ✓ Configuration markers cleared"
        echo "  ✓ Logs directory removed"
    fi
    echo "  ✓ Docker images removed (scoped)"
    if [[ "${unmount_ebs}" == "true" ]]; then
        echo "  ✓ EBS volume unmounted"
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
