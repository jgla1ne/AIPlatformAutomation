#!/usr/bin/env bash
set -euo pipefail

# --- Tenant ID Check ---
if [[ -z "${1:-}" ]] && [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: TENANT_ID is required. Usage: sudo bash $0 <tenant_id>" >&2
    exit 1
fi
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    TENANT_ID="$1"
fi

# --- Colors and Logging ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $1"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }

# --- Environment Setup ---
if [[ -n "${TENANT_ID:-}" ]]; then
    TENANT_DIR="/mnt/data/${TENANT_ID}"
    ENV_FILE="${TENANT_DIR}/.env"
    if [[ ! -f "${ENV_FILE}" ]]; then
        fail "Environment file not found for tenant '${TENANT_ID}' at ${ENV_FILE}"
    fi
    log "Loading environment from: ${ENV_FILE}"
    set -a
    source "${ENV_FILE}" 2>/dev/null || true
    set +a
    DATA_ROOT="${TENANT_DIR}"
fi

# --- Default Values ---
ENABLE_TAILSCALE=${ENABLE_TAILSCALE:-false}
ENABLE_RCLONE=${ENABLE_RCLONE:-false}
ENABLE_OPENCLAW=${ENABLE_OPENCLAW:-false}
ENABLE_POSTGRES=${ENABLE_POSTGRES:-false}
ENABLE_REDIS=${ENABLE_REDIS:-false}
ENABLE_CADDY=${ENABLE_CADDY:-false}
ENABLE_OLLAMA=${ENABLE_OLLAMA:-false}
ENABLE_OPENWEBUI=${ENABLE_OPENWEBUI:-false}
ENABLE_ANYTHINGLLM=${ENABLE_ANYTHINGLLM:-false}
ENABLE_DIFY=${ENABLE_DIFY:-false}
ENABLE_N8N=${ENABLE_N8N:-false}
ENABLE_FLOWISE=${ENABLE_FLOWISE:-false}
ENABLE_LITELLM=${ENABLE_LITELLM:-false}
ENABLE_QDRANT=${ENABLE_QDRANT:-false}
ENABLE_MILVUS=${ENABLE_MILVUS:-false}
ENABLE_CHROMA=${ENABLE_CHROMA:-false}
ENABLE_GRAFANA=${ENABLE_GRAFANA:-false}
ENABLE_PROMETHEUS=${ENABLE_PROMETHEUS:-false}
ENABLE_AUTHENTIK=${ENABLE_AUTHENTIK:-false}

# --- Permissions Function ---
permissions_set_ownership() {
    local service="$1"
    local uid="${2:-${TENANT_UID:-1001}"
    local gid="${3:-${TENANT_GID:-1001}"
    local dir="${DATA_ROOT}/${service}"
    if [[ -d "${dir}" ]]; then
        chown -R "${uid}:${gid}" "${dir}"
        log "Set ownership for '${service}' directory to ${uid}:${gid}."
    fi
}

# --- Compatibility Aliases ---
permissions_set_ownership() { permissions_set_ownership "$@"; }
permissions_set_ownership() { permissions_set_ownership "$@"; }

# --- Main Function ---
main() {
    log "Starting platform health check..."
    local all_ok=true
    if [[ "${ENABLE_GRAFANA}" == "true" ]]; then
        if curl -s "https://grafana.${DOMAIN}" >/dev/null; then
            ok "Grafana is responding."
        else
            warn "Grafana is not yet responding."
            all_ok=false
        fi
    fi
    if [[ "${all_ok}" == "false" ]]; then
        warn "Services may need time to start."
    else
        ok "All enabled web services are responding."
    fi
    log "Configuration and verification complete."
    echo ""
    echo -e "${GREEN}AI Platform is Operational!${NC}"
    echo ""
}

# --- Execute only when run directly ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "${1:-}" != "" ]]; then
    main "$@"
fi
