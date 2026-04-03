#!/usr/bin/env bash
# =============================================================================
# Script 1: System Setup & Input Collection
# PURPOSE: Complete system setup, input gathering, and platform.conf generation
# =============================================================================
# USAGE:   bash scripts/1-setup-system.sh [tenant_id] [options]
# OPTIONS: --ingest-from <file>    Ingest credentials from existing .env file
#          --preserve-secrets       Preserve existing secrets from .env
#          --generate-new          Generate new secrets for all services
#          --deployment-mode <mode> Set deployment mode (minimal|standard|full)
#          --template FILE         Use template file for configuration
#          --dry-run               Show what would be configured
# =============================================================================

set -euo pipefail

# =============================================================================
# NON-INTERACTIVE MODE (P3 fix)
# =============================================================================
export DEBIAN_FRONTEND=noninteractive

# =============================================================================
# NON-ROOT EXECUTION CHECK (README P7)
# =============================================================================
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: This script must not run as root (README P7 requirement)"
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
LOG_FILE="/tmp/ai-platform-setup.log"
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
}
ok() { log "OK: $*"; }
warn() { log "WARN: $*"; }
fail() { log "FAIL: $*"; exit 1; }
section() { echo "" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && echo "  $*" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

# =============================================================================
# SECRET GENERATION FUNCTIONS (README §5)
# =============================================================================
gen_secret() { openssl rand -hex 32; }
gen_password() { openssl rand -base64 24 | tr -d '=+/' | cut -c1-20; }

# =============================================================================
# NON-INTERACTIVE SAFE INPUT WRAPPER
# =============================================================================
safe_read() {
    # Usage: safe_read "Prompt text" DEFAULT_VALUE VARIABLE_NAME
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local value

    # Check for env var override first
    value=$(printenv "${varname}" 2>/dev/null || true)

    if [ -n "${value}" ]; then
        echo "  ${prompt}: ${value} (from environment)"
    elif [ -t 0 ]; then
        # Real TTY — show prompt and wait for input
        read -rp "  ${prompt} [${default}]: " value
        value="${value:-${default}}"
    else
        # Non-TTY — use default silently
        value="${default}"
        echo "  ${prompt}: ${value} (default — non-interactive mode)"
    fi

    printf -v "${varname}" '%s' "${value}"
}

# =============================================================================
# INTERACTIVE COLLECTION FUNCTIONS
# =============================================================================
run_interactive_collection() {
    collect_identity
    configure_storage
    select_stack_preset
    
    # TODO: Add remaining interactive functions
    log "Interactive collection completed"
}

apply_preset_defaults() {
    log "Applying preset defaults for: $STACK_PRESET"
    # TODO: Implement preset logic
}

# =============================================================================
# IDENTITY COLLECTION (README §4.1)
# =============================================================================
collect_identity() {
    section "PLATFORM IDENTITY"
    
    safe_read "Platform prefix" "ai" "PLATFORM_PREFIX"
    safe_read "Tenant ID [required, alphanumeric]" "" "TENANT_ID"
    safe_read "Base domain [required, e.g., example.com]" "" "DOMAIN"
    
    # Validate inputs
    if [[ -z "$TENANT_ID" ]]; then
        fail "Tenant ID is required"
    fi
    
    if [[ ! "$TENANT_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        fail "Invalid tenant ID format: $TENANT_ID"
    fi
    
    if [[ -z "$DOMAIN" ]]; then
        fail "Domain is required"
    fi
    
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        fail "Invalid domain format: $DOMAIN"
    fi
    
    echo "  Platform Prefix: $PLATFORM_PREFIX"
    echo "  Tenant ID: $TENANT_ID"
    echo "  Base Domain: $DOMAIN"
}

# =============================================================================
# STORAGE CONFIGURATION (README §4.2)
# =============================================================================
configure_storage() {
    section "STORAGE CONFIGURATION"
    
    safe_read "Data directory" "/mnt/${TENANT_ID}" "DATA_DIR"
    safe_read "Use EBS volume (auto-detected)" "true" "USE_EBS"
    
    if [[ "$USE_EBS" == "true" ]]; then
        detect_and_mount_ebs
    fi
    
    # Create directories
    mkdir -p "${DATA_DIR}/data" "${DATA_DIR}/config" "${DATA_DIR}/logs"
    echo "  Data Directory: $DATA_DIR"
}

detect_and_mount_ebs() {
    log "Detecting EBS volumes..."
    # TODO: Implement EBS detection and mounting
    echo "  EBS detection not yet implemented - using OS disk"
}

# =============================================================================
# STACK PRESET SELECTION (README §4.3)
# =============================================================================
select_stack_preset() {
    section "STACK PRESET SELECTION"
    
    echo "Select stack preset:"
    echo "  1) Minimal (PostgreSQL + Redis + LiteLLM + OpenWebUI)"
    echo "  2) Development (Minimal + Code Server)"
    echo "  3) Standard (Development + N8N + Flowise + Monitoring)"
    echo "  4) Full (Standard + All integrations)"
    echo "  5) Custom (select individual services)"
    
    safe_read "Stack preset [1-5]" "3" "STACK_PRESET"
    
    # Apply preset defaults
    apply_preset_defaults
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    local tenant_id="${1:-}"
    local dry_run=false
    local ingest_from=""
    litellm_master_key="$(gen_secret)"
    local preserve_secrets=false
    local generate_new=false
    local deployment_mode=""
    local template_file=""
    
    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --ingest-from)
                ingest_from="$2"
                shift 2
                ;;
            --preserve-secrets)
                preserve_secrets=true
                shift
                ;;
            --generate-new)
                generate_new=true
                shift
                ;;
            --deployment-mode)
                deployment_mode="$2"
                shift 2
                ;;
            --template)
                template_file="$2"
                shift 2
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
    
    # Validate tenant ID
    if [[ -z "$tenant_id" ]]; then
        fail "Tenant ID is required"
    fi
    
    # Set up tenant-specific logging
    local TENANT_LOG_FILE="/tmp/ai-platform-setup-$(date +%Y%m%d-%H%M%S).log"
    
    log "=== Script 1: System Setup & Input Collection ==="
    log "Version: ${SCRIPT_VERSION}"
    log "Tenant: $tenant_id"
    log "Dry-run: ${dry_run}"
    
    # Display banner
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║         AI Platform — System Setup                 ║"
    echo "║                    Script 1 of 4                        ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo ""
    
    # Run interactive collection or template processing
    if [[ -n "$template_file" ]]; then
        log "Processing template file: $template_file"
        # TODO: Implement template processing
        fail "Template processing not yet implemented"
    else
        run_interactive_collection
    fi
    
    echo "=== SYSTEM SETUP COMPLETE ==="
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
