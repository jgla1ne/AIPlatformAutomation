#!/usr/bin/env bash
# =============================================================================
# Script 2: Idempotent service deployer
# Can be re-run at any time. Sources all logic from script 3.
# =============================================================================
set -euo pipefail

# Define SCRIPT_DIR before using it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set TENANT for script 3 before sourcing
export TENANT="${1:-datasquiz}"

# Load environment from tenant directory (data confinement)
ENV_FILE="/mnt/data/${TENANT}/.env"
[[ -f "$ENV_FILE" ]] && set -a && source "$ENV_FILE" && set +a

source "${SCRIPT_DIR}/3-configure-services.sh"   # ← SOURCES LIBRARY

# ── Helper Functions ────────────────────────────────────────────────
wait_for_healthy() {
    local svc="$1"
    local max_wait="${2:-120}"
    local elapsed=0
    log_info "Waiting for ${svc} to be healthy (max ${max_wait}s)..."
    until [[ "$(docker compose -f "/mnt/data/${TENANT}/docker-compose.yml" ps --format "{{.Health}}" "$svc" 2>/dev/null)" == "healthy" ]]; do
        elapsed=$((elapsed + 5))
        if [[ $elapsed -ge $max_wait ]]; then
            log_warning "${svc} not healthy after ${max_wait}s — proceeding anyway"
            return 0
        fi
        log_info "  ${svc} starting... (${elapsed}s/${max_wait}s)"
        sleep 5
    done
    log_success "${svc} is healthy"
}

# ── Main Deployment Function ────────────────────────────────────────────────
main() {
    log_info "=== DEPLOY START ==="

    # Verify .env exists (script 1 must have run)
    [[ -f "$ENV_FILE" ]] || { 
        log_error ".env not found at ${ENV_FILE}. Run script 1 first."; 
        exit 1; 
    }

    # Load environment
    set -a; source "$ENV_FILE"; set +a

    # 1. Regenerate all config files (idempotent - safe to repeat)
    prepare_directories
    generate_configs
    generate_compose

    # 2. Infra layer — must be healthy before anything else
    log_info "Deploying infrastructure services..."
    deploy_service postgres
    deploy_service redis
    provision_databases          # waits until postgres ready, verifies DBs

    # 3. Vector DB
    [[ "${ENABLE_QDRANT:-false}"     == "true" ]] && {
        # Fix Qdrant permissions - create snapshots directory and set ownership
        mkdir -p "${DATA_DIR}/qdrant/snapshots/tmp"
        chown -R "${QDRANT_UID:-1000}:${QDRANT_UID:-1000}" "${DATA_DIR}/qdrant"
        deploy_service qdrant
    }

    # 4. Local LLM runtime — BEFORE LiteLLM
    [[ "${ENABLE_OLLAMA:-false}"     == "true" ]] && deploy_service ollama

    # 5. AI gateway — depends on postgres, redis; optionally ollama
    [[ "${ENABLE_LITELLM:-false}"    == "true" ]] && {
        deploy_service litellm
        wait_for_healthy litellm 120   # Prisma migration takes 45-90s
    }

    # 6. Monitoring — independent of AI services
    [[ "${ENABLE_MONITORING:-false}" == "true" ]] && {
        deploy_service prometheus
        deploy_service grafana
    }
    
    # 6.5. Additional services from infrastructure
    [[ "${ENABLE_GRAFANA:-false}"    == "true" ]] && deploy_service grafana
    [[ "${ENABLE_PROMETHEUS:-false}" == "true" ]] && deploy_service prometheus

    # 7. Reverse proxy — depends only on infra (postgres, redis healthy)
    deploy_service caddy

    # 8. Web services — AFTER litellm is healthy
    [[ "${ENABLE_OPENWEBUI:-false}"   == "true" ]] && deploy_service open-webui
    [[ "${ENABLE_N8N:-false}"         == "true" ]] && deploy_service n8n
    [[ "${ENABLE_FLOWISE:-false}"     == "true" ]] && deploy_service flowise
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && deploy_service anythingllm
    [[ "${ENABLE_DIFY:-false}"       == "true" ]] && deploy_service dify
    [[ "${ENABLE_AUTHENTIK:-false}"   == "true" ]] && deploy_service authentik
    [[ "${ENABLE_SIGNAL:-false}"      == "true" ]] && deploy_service signal

    # 9. External wiring (non-blocking — skip gracefully if not configured)
    [[ "${ENABLE_TAILSCALE:-false}"  == "true" ]] && configure_tailscale
    [[ "${ENABLE_CODESERVER:-false}" == "true" ]] && deploy_service codeserver
    [[ "${ENABLE_OPENCLAW:-false}"  == "true" ]] && deploy_service openclaw
    [[ "${ENABLE_RCLONE:-false}"    == "true" ]] && deploy_service rclone
    [[ "${ENABLE_CONTINUE:-false}"   == "true" ]] && deploy_service continue
    [[ -n "${GDRIVE_CLIENT_ID:-}" ]] && setup_gdrive_rclone && create_ingestion_systemd

    # 10. Health dashboard — script 2 STOPS after this
    health_dashboard

    log_info "=== DEPLOY COMPLETE ==="
}

# Only run main if executed directly (not when sourced)
(return 0 2>/dev/null) || main "$@"
