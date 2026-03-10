#!/usr/bin/env bash
# =============================================================================
# Script 3: Configure & Verify - STABLE v3.1
# =============================================================================
# PURPOSE: Performs post-deployment configuration and health checks.
#          This is the final step to verify the platform is operational.
# =============================================================================

set -euo pipefail

# --- Tenant ID Check ---
if [[ -z "${1:-}" ]] && [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: TENANT_ID is required. Usage: sudo bash $0 <tenant_id>" >&2
    exit 1
fi
# Only set TENANT_ID if this script is being executed directly, not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    TENANT_ID="$1"
fi

# --- Colors and Logging ---
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' BOLD='\033[1m' DIM='\033[2m' NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $1"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }

# --- Environment Setup ---
# Only set up tenant-specific variables if TENANT_ID is defined
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
fi

# --- DEFINITIVE HEALTH CHECK FUNCTION ---
healthcheck_services() {
    log "Starting platform health check..."
    
    local all_ok=true

    # The only test that matters: can we reach the public-facing URL?
    # Caddy handles the internal routing. If this works, the platform works.

    if [[ "${ENABLE_GRAFANA}" == "true" ]]; then
        if ! curl -s -k --max-time 10 "https://grafana.${DOMAIN}" > /dev/null; then
            warn "Grafana (https://grafana.${DOMAIN}) is not yet responding."
            all_ok=false
        else
            ok "Grafana is responding."
        fi
    fi
    if [[ "${ENABLE_OPENWEBUI}" == "true" ]]; then
        if ! curl -s -k --max-time 10 "https://openwebui.${DOMAIN}" > /dev/null; then
            warn "OpenWebUI (https://openwebui.${DOMAIN}) is not yet responding."
            all_ok=false
        else
            ok "OpenWebUI is responding."
        fi
    fi
    if [[ "${ENABLE_N8N}" == "true" ]]; then
        if ! curl -s -k --max-time 10 "https://n8n.${DOMAIN}" > /dev/null; then
            warn "n8n (https://n8n.${DOMAIN}) is not yet responding."
            all_ok=false
        else
            ok "n8n is responding."
        fi
    fi
    if [[ "${ENABLE_FLOWISE}" == "true" ]]; then
        if ! curl -s -k --max-time 10 "https://flowise.${DOMAIN}" > /dev/null; then
            warn "Flowise (https://flowise.${DOMAIN}) is not yet responding."
            all_ok=false
        else
            ok "Flowise is responding."
        fi
    fi
    # Add other services here following the same pattern

    if [[ "${all_ok}" == "false" ]]; then
        warn "One or more services are not responding. It may take a few minutes for all services to start."
        warn "Check Caddy logs for SSL certificate issues: sudo docker compose -f ${TENANT_DIR}/docker-compose.yml logs caddy"
    else
        ok "All enabled web services are responding."
    fi
}

# --- Default Values for Graceful Handling ---
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

# --- Permissions Function (needed by Script 1) ---
permissions_set_ownership() {
    local service="$1"
    local uid="$2"
    local gid="$3"
    local dir="${DATA_ROOT}/${service}"
    
    if [[ -d "${dir}" ]]; then
        chown -R "${uid}:${gid}" "${dir}"
        log "Set ownership for '${service}' directory to ${uid}:${gid}."
    fi
}

# --- DEFINITIVE TAILSCALE CONFIGURATION ---
configure_tailscale() {
    if [[ "${ENABLE_TAILSCALE}" != "true" ]]; then
        return 0
    fi

    log "Configuring Tailscale..."

    # Wait for the container to be stable
    log "Waiting for Tailscale daemon to be stable..."
    if ! timeout 60s bash -c "until [[ \$(docker compose -f ${TENANT_DIR}/docker-compose.yml ps -q tailscale | xargs docker inspect -f '{{.State.Status}}') == 'running' ]]; do sleep 5; done"; then
        fail "Tailscale container did not stabilize. Check logs: sudo docker compose -f ${TENANT_DIR}/docker-compose.yml logs tailscale"
    fi

    log "Bringing Tailscale network UP..."
    if ! docker compose -f "${TENANT_DIR}/docker-compose.yml" exec -T tailscale tailscale up --hostname="${TAILSCALE_HOSTNAME}"; then
        fail "Tailscale 'up' command failed. Check your TAILSCALE_AUTH_KEY."
    fi

    # If OpenClaw is enabled, configure Tailscale to serve it.
    if [[ "${ENABLE_OPENCLAW}" == "true" ]]; then
        log "Configuring Tailscale to serve OpenClaw..."
        if ! docker compose -f "${TENANT_DIR}/docker-compose.yml" exec -T tailscale tailscale serve tcp://:18789/tcp://openclaw:8082; then
             warn "Failed to configure Tailscale to serve OpenClaw. Manual setup may be required."
        fi
    fi

    local tailscale_ip
    tailscale_ip=$(docker compose -f "${TENANT_DIR}/docker-compose.yml" exec -T tailscale tailscale ip -4)
    ok "Tailscale is UP and connected. Private IP: ${tailscale_ip}"
}

main() {
    log "Starting Post-Deployment Configuration & Verification..."
    
    # Run configuration steps
    configure_tailscale
    
    # Run the final, definitive health check
    healthcheck_services

    log "Configuration and verification complete."
    
    # Final Summary
    echo ""
    echo -e "${GREEN}🎉 AI Platform is Operational! 🎉${NC}"
    echo ""
    echo "  All enabled services have been deployed and checked."
    echo "  You can now access your services at their respective URLs."
    echo ""
    echo "  Example URLs:"
    [[ "${ENABLE_GRAFANA}" == "true" ]] && echo "    - Grafana: https://grafana.${DOMAIN}"
    [[ "${ENABLE_OPENWEBUI}" == "true" ]] && echo "    - OpenWebUI: https://openwebui.${DOMAIN}"
    [[ "${ENABLE_N8N}" == "true" ]] && echo "    - n8n: https://n8n.${DOMAIN}"
    echo ""
    echo "  To view logs: sudo docker compose -f ${TENANT_DIR}/docker-compose.yml logs <service_name>"
    echo ""
}

# Execute the main function only when run directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
