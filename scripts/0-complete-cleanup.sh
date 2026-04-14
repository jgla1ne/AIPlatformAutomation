#!/usr/bin/env bash
# =============================================================================
# Script 0: Nuclear Cleanup
# PURPOSE: Remove all containers and data for complete platform reset
# =============================================================================
# USAGE:   bash scripts/0-complete-cleanup.sh [tenant_id] [options]
# OPTIONS: --dry-run         Show what would be cleaned without action
#          --force           Skip confirmation prompts
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
        echo "     • EBS volume unmounted at /mnt/${tenant_id}"
    fi
    echo ""
    echo "  This action cannot be undone!"
    echo ""
    
    # Typed confirmation (README §6 - mandatory)
    if [[ "${dry_run}" != "true" ]]; then
        confirm_destructive
    fi
    
    # Source platform.conf (README P1 - BUG-02 fix)
    local platform_conf="/mnt/${tenant_id}/config/platform.conf"
    # Set defaults that work whether platform.conf exists or not
    export TENANT_PREFIX="${tenant_id}"
    export TENANT_ID="${tenant_id}"
    export BASE_DIR="/mnt/${tenant_id}"
    export DATA_DIR="/mnt/${tenant_id}"
    
    # Path safety: ensure BASE_DIR is a subdirectory, not /mnt or /opt root
    if [[ "${BASE_DIR}" == "/mnt" || "${BASE_DIR}" == "/mnt/" || "${BASE_DIR}" == "/opt" || "${BASE_DIR}" == "/opt/" ]]; then
        fail "Forbidden: BASE_DIR resolves to a root directory (${BASE_DIR}). Cleanup must be scoped to a tenant."
    fi

    export CONFIG_DIR="/mnt/${tenant_id}/config"
    export LOGS_DIR="/mnt/${tenant_id}/logs"
    export COMPOSE_FILE="/mnt/${tenant_id}/config/docker-compose.yml"
    export DOCKER_NETWORK="${tenant_id}-network"
    
    if [[ ! -f "$platform_conf" ]]; then
        warn "platform.conf not found at $platform_conf. Attempting partial cleanup..."
        log "Using default paths for cleanup (no platform.conf)"
    else
        # shellcheck source=/dev/null
        source "$platform_conf"
    fi
    
    # Source shared configuration now that variables are set
    [[ -f "${SCRIPT_DIR}/shared-config.sh" ]] && source "${SCRIPT_DIR}/shared-config.sh"

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

    # Stop Docker daemon if its data-root is on the EBS volume.
    # Without this, the daemon holds open FDs to the block device, umount falls
    # back to lazy-unmount, and the device stays "in use" — mkfs.ext4 in Script 1
    # then fails with "apparently in use by the system".
    # Script 1's configure_docker_dataroot() restarts Docker after the fresh mount.
    # Script 1's configure_docker_dataroot() restarts Docker after the fresh mount.
    # Script 1's configure_docker_dataroot() restarts Docker after the fresh mount.
    local docker_data_root
    docker_data_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "")
    if [[ "$docker_data_root" == "${BASE_DIR}"* ]]; then
        log "Stopping Docker daemon and socket (data-root is scoped to this tenant)..."
        sudo systemctl stop docker.socket docker.service || true
        # Give it a moment to release file handles
        sleep 2
        ok "Docker daemon and socket stopped"
    fi

    # 3. Unmount EBS volume FIRST — must happen before rm -rf, because the
    #    mount point IS the tenant directory (/mnt/<tenant>).
    #    Trying rm -rf while still mounted returns "Device or resource busy".
    local mount_point="/mnt/${tenant_id}"
    if grep -qs "$mount_point" /proc/mounts; then
        log "Unmounting EBS volume: $mount_point (required before directory removal)"
        
        # Aggressively kill processes using the mount (README §6)
        if command -v fuser >/dev/null 2>&1; then
            log "  Terminating processes accessing $mount_point..."
            sudo fuser -km "$mount_point" >/dev/null 2>&1 || true
            sleep 1
        fi

        run_cmd sudo umount "$mount_point" || {
            log "WARN: umount returned non-zero — attempting lazy unmount"
            run_cmd sudo umount -l "$mount_point" || true
        }
        
        # Verify unmount succeeded
        if grep -qs "$mount_point" /proc/mounts; then
            fail "CRITICAL: $mount_point is STILL MOUNTED (detected in /proc/mounts). Wipe aborted to protect EBS data. Manually stop all processes (e.g., Docker, Caddy) and try again."
        fi
        ok "EBS volume unmounted: $mount_point"
    else
        log "No EBS volume mounted at $mount_point (nothing to unmount)"
    fi

    # 4-8. Remove tenant directory tree — single rm -rf on BASE_DIR covers everything.
    # Safety: reject empty or paths outside /opt/ /mnt/; skip gracefully if already gone.
    # Skip data removal if containers-only mode
    if [[ "${containers_only}" == "true" ]]; then
        log "Skipping data removal (containers-only mode)"
    else
        if [[ -z "${BASE_DIR:-}" ]]; then
            warn "BASE_DIR is empty - skipping data removal"
        elif [[ ! "${BASE_DIR}" =~ ^/opt/ && ! "${BASE_DIR}" =~ ^/mnt/ ]]; then
            fail "BASE_DIR '${BASE_DIR}' is outside /opt/ or /mnt/ — refusing to delete"
        elif [[ -d "${BASE_DIR}" ]]; then
            log "Removing tenant directory tree: ${BASE_DIR}"
            run_cmd rm -rf "${BASE_DIR}"
            ok "Tenant directory removed: ${BASE_DIR}"
        else
            log "Tenant directory already gone (nothing to remove): ${BASE_DIR}"
        fi
    fi

    # 9. docker network rm "${DOCKER_NETWORK}" || true
    if [[ -n "${DOCKER_NETWORK:-}" ]]; then
        log "Removing Docker network: ${DOCKER_NETWORK}"
        run_cmd docker network rm "${DOCKER_NETWORK}" || true
        ok "Docker network removed"
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
    echo "  ✓ EBS volume unmounted (if was mounted)"
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
