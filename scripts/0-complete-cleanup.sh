#!/usr/bin/env bash
# =============================================================================
# Script 0: Nuclear Cleanup - BULLETPROOF v5.0 FINAL
# =============================================================================
# PURPOSE: Complete system wipe with enhanced safety and validation
# USAGE:   sudo bash scripts/0-complete-cleanup.sh [tenant_id] [options]
# OPTIONS: --confirm-destroy    Skip interactive confirmation
#          --remove-images      Remove all tenant-specific images
#          --dry-run           Show what would be removed without action
# =============================================================================

set -euo pipefail

# =============================================================================
# FRAMEWORK VALIDATION
# =============================================================================
framework_validate() {
    # Binary availability checks
    local missing_bins=()
    for bin in docker jq; do
        if ! command -v "$bin" >/dev/null 2>&1; then
            missing_bins+=("$bin")
        fi
    done
    
    if [[ ${#missing_bins[@]} -gt 0 ]]; then
        echo "ERROR: Missing required binaries: ${missing_bins[*]}" >&2
        exit 1
    fi
    
    # Docker daemon health
    if ! docker info >/dev/null 2>&1; then
        echo "ERROR: Docker daemon not running or accessible" >&2
        exit 1
    fi
    
    # Root permission check
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This script must be run as root for complete cleanup" >&2
        exit 1
    fi
}

# =============================================================================
# LOGGING AND UTILITIES
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${CYAN}[INFO]${NC}    $1"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }
dry_run() { echo -e "${BLUE}[DRY-RUN]${NC} $1"; }

# =============================================================================
# TYPED CONFIRMATION (Expert Fix)
# =============================================================================
typed_confirmation() {
    local tenant_id="$1"
    echo
    warn "🚨 NUCLEAR CLEANUP CONFIRMATION 🚨"
    echo
    echo "This will COMPLETELY DESTROY all data for tenant: ${RED}${tenant_id}${NC}"
    echo "Including:"
    echo "  • All containers and networks"
    echo "  • All volumes and data"
    echo "  • All configuration files"
    echo "  • All tenant-specific images (if --remove-images specified)"
    echo
    echo -e "${RED}THIS ACTION IS IRREVERSIBLE${NC}"
    echo
    
    # Typed confirmation requirement
    echo -n "Type '${RED}DESTROY-${tenant_id}${NC}' to confirm: "
    read -r confirmation
    
    if [[ "$confirmation" != "DESTROY-${tenant_id}" ]]; then
        fail "Confirmation mismatch. Aborting cleanup."
    fi
    
    ok "Confirmation verified. Proceeding with nuclear cleanup..."
}

# =============================================================================
# MAIN CLEANUP FUNCTIONS
# =============================================================================
cleanup_containers() {
    local tenant_id="$1"
    local dry_run="$2"
    
    log "Cleaning up containers for tenant '${tenant_id}'..."
    
    # Kill any running AI platform scripts
    if [[ "$dry_run" == "false" ]]; then
        pkill -f "1-setup-system.sh" || true
        pkill -f "2-deploy-services.sh" || true
        pkill -f "3-configure-services.sh" || true
        sleep 2
        ok "Platform scripts terminated."
    else
        dry_run "Would terminate platform scripts"
    fi
    
    # Define container patterns (README-compliant naming)
    local container_patterns=(
        "ai-${tenant_id}-"
        "${tenant_id}-"
    )
    
    for pattern in "${container_patterns[@]}"; do
        local containers
        containers=$(docker ps -aq --filter "name=${pattern}" 2>/dev/null || true)
        
        if [[ -n "$containers" ]]; then
            if [[ "$dry_run" == "false" ]]; then
                log "Stopping containers matching pattern '${pattern}'..."
                docker stop $containers 2>/dev/null || true
                docker rm $containers 2>/dev/null || true
                ok "Removed containers matching '${pattern}'"
            else
                dry_run "Would stop and remove containers: $(echo $containers | tr '\n' ' ')"
            fi
        fi
    done
}

cleanup_networks() {
    local tenant_id="$1"
    local dry_run="$2"
    
    log "Cleaning up networks for tenant '${tenant_id}'..."
    
    local networks
    networks=$(docker network ls --filter "name=ai-${tenant_id}" -q 2>/dev/null || true)
    
    if [[ -n "$networks" ]]; then
        if [[ "$dry_run" == "false" ]]; then
            docker network rm $networks 2>/dev/null || true
            ok "Removed networks for tenant '${tenant_id}'"
        else
            dry_run "Would remove networks: $(echo $networks | tr '\n' ' ')"
        fi
    fi
}

cleanup_volumes() {
    local tenant_id="$1"
    local dry_run="$2"
    
    log "Cleaning up volumes for tenant '${tenant_id}'..."
    
    # Safe volume filtering with compose project labels (Expert Fix)
    local volumes
    volumes=$(docker volume ls --filter "label=com.docker.compose.project=ai-${tenant_id}" -q 2>/dev/null || true)
    
    if [[ -n "$volumes" ]]; then
        if [[ "$dry_run" == "false" ]]; then
            docker volume rm $volumes 2>/dev/null || true
            ok "Removed volumes for tenant '${tenant_id}'"
        else
            dry_run "Would remove volumes: $(echo $volumes | tr '\n' ' ')"
        fi
    fi
    
    # Fallback: pattern-based volume removal
    local pattern_volumes
    pattern_volumes=$(docker volume ls --filter "name=ai-${tenant_id}" -q 2>/dev/null || true)
    
    if [[ -n "$pattern_volumes" ]]; then
        if [[ "$dry_run" == "false" ]]; then
            docker volume rm $pattern_volumes 2>/dev/null || true
            ok "Removed pattern-based volumes for tenant '${tenant_id}'"
        else
            dry_run "Would remove pattern-based volumes: $(echo $pattern_volumes | tr '\n' ' ')"
        fi
    fi
}

cleanup_images() {
    local tenant_id="$1"
    local dry_run="$2"
    
    log "Cleaning up images for tenant '${tenant_id}'..."
    
    # Safe image filtering with compose project labels (Expert Fix)
    local images
    images=$(docker images --filter "label=com.docker.compose.project=ai-${tenant_id}" -q 2>/dev/null || true)
    
    if [[ -n "$images" ]]; then
        if [[ "$dry_run" == "false" ]]; then
            docker rmi $images 2>/dev/null || true
            ok "Removed images for tenant '${tenant_id}'"
        else
            dry_run "Would remove images: $(echo $images | tr '\n' ' ')"
        fi
    fi
}

cleanup_data_directories() {
    local tenant_id="$1"
    local dry_run="$2"
    
    log "Cleaning up data directories for tenant '${tenant_id}'..."
    
    local data_dirs=(
        "/mnt/${tenant_id}"
        "/mnt/data/${tenant_id}"
        "/tmp/${tenant_id}"
    )
    
    for dir in "${data_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if [[ "$dry_run" == "false" ]]; then
                rm -rf "$dir"
                ok "Removed directory: $dir"
            else
                dry_run "Would remove directory: $dir"
            fi
        fi
    done
}

cleanup_systemd_units() {
    local tenant_id="$1"
    local dry_run="$2"
    
    log "Cleaning up systemd units for tenant '${tenant_id}'..."
    
    local unit_patterns=(
        "ai-${tenant_id}-"
        "${tenant_id}-"
    )
    
    for pattern in "${unit_patterns[@]}"; do
        local units
        units=$(systemctl list-unit-files "${pattern}*.service" 2>/dev/null | awk '{print $1}' | grep -v '^UNIT FILE$' || true)
        
        for unit in $units; do
            if [[ -n "$unit" ]]; then
                if [[ "$dry_run" == "false" ]]; then
                    systemctl stop "$unit" 2>/dev/null || true
                    systemctl disable "$unit" 2>/dev/null || true
                    rm -f "/etc/systemd/system/$unit"
                    ok "Removed systemd unit: $unit"
                else
                    dry_run "Would remove systemd unit: $unit"
                fi
            fi
        done
    done
    
    if [[ "$dry_run" == "false" ]]; then
        systemctl daemon-reload 2>/dev/null || true
    fi
}

cleanup_cron_entries() {
    local tenant_id="$1"
    local dry_run="$2"
    
    log "Cleaning up cron entries for tenant '${tenant_id}'..."
    
    local temp_cron
    temp_cron=$(mktemp)
    
    # Filter out tenant-specific cron entries
    if crontab -l 2>/dev/null | grep -v "ai-${tenant_id}" | grep -v "${tenant_id}-" > "$temp_cron"; then
        if [[ "$dry_run" == "false" ]]; then
            crontab "$temp_cron" 2>/dev/null || true
            ok "Removed cron entries for tenant '${tenant_id}'"
        else
            dry_run "Would remove cron entries for tenant '${tenant_id}'"
        fi
    fi
    
    rm -f "$temp_cron"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    # Parse arguments
    local tenant_id="${1:-default}"
    local confirm_destroy=false
    local remove_images=false
    local dry_run=false
    
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --confirm-destroy)
                confirm_destroy=true
                shift
                ;;
            --remove-images)
                remove_images=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
    
    # Framework validation
    framework_validate
    
    # Dry run mode
    if [[ "$dry_run" == "true" ]]; then
        log "DRY RUN MODE - No actual changes will be made"
    fi
    
    # Confirmation unless skipped
    if [[ "$confirm_destroy" == "false" && "$dry_run" == "false" ]]; then
        typed_confirmation "$tenant_id"
    elif [[ "$confirm_destroy" == "true" && "$dry_run" == "false" ]]; then
        log "Confirmation skipped via --confirm-destroy flag"
        ok "Proceeding with nuclear cleanup for tenant '${tenant_id}'..."
    fi
    
    # Execute cleanup in safe order
    cleanup_containers "$tenant_id" "$dry_run"
    cleanup_networks "$tenant_id" "$dry_run"
    cleanup_volumes "$tenant_id" "$dry_run"
    
    if [[ "$remove_images" == "true" ]]; then
        cleanup_images "$tenant_id" "$dry_run"
    fi
    
    cleanup_data_directories "$tenant_id" "$dry_run"
    cleanup_systemd_units "$tenant_id" "$dry_run"
    cleanup_cron_entries "$tenant_id" "$dry_run"
    
    # Final system cleanup
    if [[ "$dry_run" == "false" ]]; then
        log "Performing final system cleanup..."
        docker system prune -af >/dev/null 2>&1 || true
        
        # Create fresh base directory with proper permissions
        mkdir -p "/mnt/${tenant_id}"
        chown 1000:1000 "/mnt/${tenant_id}" 2>/dev/null || true
        
        ok "Nuclear cleanup for tenant '${tenant_id}' completed successfully!"
    else
        dry_run "Would perform final system prune and create fresh directory"
        ok "DRY RUN completed for tenant '${tenant_id}'"
    fi
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
