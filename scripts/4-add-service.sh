#!/usr/bin/env bash
set -euo pipefail

# --- Logging functions ---
log() { echo "[INFO]  $*"; }
ok() { echo "[OK]    $*"; }
fail() { echo "[FAIL]  $*" >&2; exit 1; }

# --- setup_logging function ---
setup_logging() {
    if [[ -z "${DATA_ROOT:-}" ]]; then return; fi
    local script_name
    script_name=$(basename "$0" .sh)
    LOG_DIR="${DATA_ROOT}/logs"
    mkdir -p "${LOG_DIR}"
    [[ -n "${TENANT_GID:-}" ]] && chown :"${TENANT_GID}" "${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/${script_name}-$(date +%Y%m%d-%H%M%S).log"

    # Redirect all subsequent output
    exec > >(tee -a "${LOG_FILE}") 2>&1
    log "INFO" "All output is now logged to: ${LOG_FILE}"
}

# --- Argument & Environment Handling ---
if [[ -z "${1:-}" || -z "${2:-}" ]]; then
    fail "Usage: sudo bash $0 <tenant_id> <service_name>"
fi

TENANT_ID="$1"
SERVICE="$2"
ENV_FILE="/mnt/data/${TENANT_ID}/.env"
SCRIPT_DIR="$(dirname "$0")"

if [[ ! -f "${ENV_FILE}" ]]; then
    fail "Environment file not found for tenant '${TENANT_ID}' at ${ENV_FILE}"
fi

log "Loading environment from: ${ENV_FILE}"
set -a; source "${ENV_FILE}"; set +a

ENV_KEY="ENABLE_$(echo "${SERVICE}" | tr '[:lower:]' '[:upper:]')"

log "Adding service '${SERVICE}' to tenant '${TENANT_ID}'..."

# --- Update .env file ---
if grep -q "^${ENV_KEY}=" "${ENV_FILE}"; then
    sed -i "s/^${ENV_KEY}=.*/${ENV_KEY}=true/" "${ENV_FILE}"
else
    echo "${ENV_KEY}=true" >> "${ENV_FILE}"
fi

ok "Enabled ${SERVICE} in ${ENV_FILE}"
log "Re-running script 2 to regenerate and redeploy for tenant '${TENANT_ID}'..."

# --- Re-run script 2 to apply changes ---
exec bash "${SCRIPT_DIR}/2-deploy-services.sh" "${TENANT_ID}"
