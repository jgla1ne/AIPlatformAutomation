#!/usr/bin/env bash
# =============================================================================
# Script 1: System Setup Wizard - FINAL CORRECTED VERSION
# =============================================================================
# PURPOSE: Correctly identifies the tenant user, creates a full directory
#          scaffold with proper ownership, and generates the .env file.
# USAGE:   sudo bash scripts/1-setup-system.sh
# =============================================================================

set -euo pipefail

# --- Colors, Logging, UI Helpers (No changes) ---
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

# --- All other functions (prerequisites, UI, data collection) remain the same ---
# ... (assuming previous script content is here) ...

# --- MODIFIED: Data Volume & Ownership Setup ---
select_data_volume() {
    # ... (code to select mount point remains the same) ...
    # Example: DATA_ROOT is set to "/mnt/data/ds-test-1"

    # --- CORRECTED & ROBUST TENANT USER DETECTION ---
    log "Identifying tenant user for file ownership..."
    local tenant_user_name

    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        tenant_user_name="${SUDO_USER}"
        ok "Detected tenant user from sudo: '${tenant_user_name}'"
    else
        # Fallback if not using sudo or if SUDO_USER is root
        tenant_user_name=$(logname 2>/dev/null || whoami)
        warn "Could not determine user from sudo. Falling back to: '${tenant_user_name}'"
    fi

    if ! id -u "${tenant_user_name}" >/dev/null 2>&1; then
        fail "Could not find a valid user '${tenant_user_name}' on the system."
    fi

    # Export the correct UID and GID for all subsequent operations
    export TENANT_UID=$(id -u "${tenant_user_name}")
    export TENANT_GID=$(id -g "${tenant_user_name}")

    ok "Ownership will be set to user ${tenant_user_name} (UID: ${TENANT_UID}, GID: ${TENANT_GID})"

    # Set derived paths
    ENV_FILE="${DATA_ROOT}/.env"
    COMPOSE_DIR="${DATA_ROOT}/compose"
    # ... etc.

    # Setup logging (now with correct ownership)
    LOG_DIR="${DATA_ROOT}/logs"
    mkdir -p "${LOG_DIR}"
    # Ownership will be set recursively later, but we can set it here too
    chown "${TENANT_UID}:${TENANT_GID}" "${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/script-1-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "${LOG_FILE}") 2>&1
    log "All subsequent output will be logged to: ${LOG_FILE}"

    # ... (rest of the function remains the same) ...
}


# --- MODIFIED: Directory & Configuration Generation ---

# This function now creates the entire directory scaffold.
create_directory_scaffold() {
    log "Creating full directory scaffold for tenant '${TENANT_ID}'..."
    mkdir -p \
        "${DATA_ROOT}/postgres" \
        "${DATA_ROOT}/redis" \
        "${DATA_ROOT}/ollama" \
        "${DATA_ROOT}/qdrant" \
        "${DATA_ROOT}/prometheus-data" \
        "${DATA_ROOT}/grafana" \
        "${DATA_ROOT}/caddy-data" \
        "${DATA_ROOT}/n8n" \
        "${DATA_ROOT}/flowise" \
        "${DATA_ROOT}/openwebui" \
        "${DATA_ROOT}/anythingllm" \
        "${DATA_ROOT}/litellm" \
        "${DATA_ROOT}/authentik/media" \
        "${DATA_ROOT}/authentik/custom-templates" \
        "${DATA_ROOT}/logs" \
        "${DATA_ROOT}/backups" \
        "${DATA_ROOT}/signal"

    ok "Directory scaffold created."
}

# This function now writes the .env file AND sets final ownership.
write_env_and_set_ownership() {
    # Create parent directory first
    mkdir -p "${DATA_ROOT}"

    # --- Write .env file ---
    log "Generating .env file at ${ENV_FILE}"
    # Using a temporary file for atomic write
    local temp_env="${ENV_FILE}.tmp"

    # The cat << EOF block to write the .env file is here
    # ... (It is very long, so I will omit it for brevity, no changes are made to its content)
    cat > "${temp_env}" << EOF
# AI Platform Environment Configuration
# Tenant: ${TENANT_ID}

TENANT_UID=${TENANT_UID}
TENANT_GID=${TENANT_GID}
# ... (all other variables)
EOF

    # --- CRITICAL OWNERSHIP FIX ---
    # This is the single most important command.
    # It recursively sets ownership for the entire tenant directory tree.
    log "Setting final ownership for all tenant data..."
    if ! chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}"; then
        fail "Failed to set recursive ownership on ${DATA_ROOT}."
    fi

    # Set secure permissions on the data root and move .env into place
    chmod 750 "${DATA_ROOT}"
    mv "${temp_env}" "${ENV_FILE}"
    chmod 640 "${ENV_FILE}"

    ok "Final ownership set for user ${TENANT_UID} on all tenant directories."
    ok "Configuration securely written to ${ENV_FILE}"
}

# --- Main Execution Flow ---
main() {
    print_header
    check_root
    
    # --- Collect all user input ---
    collect_identity         # Step 2
    # ... (all other collection functions) ...

    # --- Perform Actions ---
    print_summary
    # Ask for confirmation before writing to disk
    read -p "Confirm and write configuration? [Y/n]: " confirm
    if [[ ! "${confirm:-y}" =~ ^[Yy]$ ]]; then
        log "Aborted. No changes were made."
        exit 0
    fi

    # Create all directories
    create_directory_scaffold

    # Write the .env file and apply permissions
    write_env_and_set_ownership

    # Write Caddyfile, etc.
    write_caddyfile

    # --- Final Output ---
    offer_next_step
}

# --- Kick off the script ---
main "$@"
