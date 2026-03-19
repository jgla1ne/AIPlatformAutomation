#!/usr/bin/env bash
# =============================================================================
# Script 2: Idempotent service deployer — v4.1
# USAGE:  sudo bash scripts/2-deploy-services.sh [tenant_id] [--force]
# --force: drops and recreates all service databases + flushes Redis cache
#          Use after code changes that affect DB schema or LiteLLM config
# Without --force: idempotent — skips already-existing databases
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments — tenant is first positional, --force is a flag
export TENANT="${1:-datasquiz}"
FORCE_REDEPLOY=false
for arg in "$@"; do
    [[ "$arg" == "--force" ]] && FORCE_REDEPLOY=true
done

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

pull_ollama_models() {
    [[ "${ENABLE_OLLAMA:-false}" == "true" ]] || return 0
    [[ -n "${OLLAMA_MODELS:-}" ]] || { log_info "No OLLAMA_MODELS configured — skipping pull"; return 0; }

    log_info "Pulling Ollama models: ${OLLAMA_MODELS}"
    log_info "  (This runs in background — models are available as each pull completes)"

    # Wait for ollama HTTP server to be up
    local elapsed=0
    until docker compose -f "/mnt/data/${TENANT}/docker-compose.yml" exec -T ollama \
        curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; do
        elapsed=$((elapsed + 5))
        if [[ $elapsed -ge 60 ]]; then
            log_warning "Ollama HTTP not ready after 60s — skipping model pull"
            return 0
        fi
        log_info "  Waiting for ollama HTTP... (${elapsed}s)"
        sleep 5
    done

    for model in ${OLLAMA_MODELS//,/ }; do
        [[ -z "$model" ]] && continue
        log_info "  Pulling ${model}..."
        # Background pull — don't block deployment
        docker compose -f "/mnt/data/${TENANT}/docker-compose.yml" exec -T ollama \
            ollama pull "$model" \
            >> "/mnt/data/${TENANT}/logs/ollama-pull-$(date +%Y%m%d).log" 2>&1 &
        log_info "  ↳ Pull started in background (PID: $!)"
    done

    log_success "Ollama model pulls initiated — check /mnt/data/${TENANT}/logs/ollama-pull-$(date +%Y%m%d).log"
    log_info "  LiteLLM requests to ollama models will succeed once pulls complete"
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

    # With --force: drop all service databases before provisioning
    if [[ "$FORCE_REDEPLOY" == "true" ]]; then
        log_info "--force: dropping all service databases for clean slate..."
        drop_service_databases
    fi

    provision_databases          # waits until postgres ready, verifies DBs

    # 3. Vector DB
    [[ "${ENABLE_QDRANT:-false}"     == "true" ]] && {
        # Fix Qdrant permissions - create snapshots directory and set ownership
        mkdir -p "${DATA_DIR}/qdrant/snapshots/tmp"
        chown -R "${QDRANT_UID:-1000}:${QDRANT_UID:-1000}" "${DATA_DIR}/qdrant"
        deploy_service qdrant
    }

    # 4. Local LLM runtime — BEFORE LiteLLM
    [[ "${ENABLE_OLLAMA:-false}"     == "true" ]] && {
        deploy_service ollama
        pull_ollama_models
    }

    # 5. AI gateway — always force-recreate container to pick up fresh config
    [[ "${ENABLE_LITELLM:-false}" == "true" ]] && {

        # Always stop and remove the container (ensures fresh config.yaml is loaded)
        log_info "Removing existing litellm container (ensures config reload)..."
        docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
            rm -sf litellm >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1 || true

        # Always wipe the Prisma file cache (small, fast, prevents schema mismatch)
        log_info "Clearing LiteLLM Prisma file cache..."
        rm -rf "${DATA_DIR}/litellm"
        mkdir -p "${DATA_DIR}/litellm"
        chown -R 1000:"${TENANT_GID:-1001}" "${DATA_DIR}/litellm"

        # --force: also drop/recreate the litellm Postgres database
        if [[ "$FORCE_REDEPLOY" == "true" ]]; then
            log_info "  --force: dropping and recreating litellm database..."
            docker compose -f "$COMPOSE_FILE" exec -T postgres \
                psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
                -c "DROP DATABASE IF EXISTS litellm;" \
                >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1 || true
            docker compose -f "$COMPOSE_FILE" exec -T postgres \
                psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
                -c "CREATE DATABASE litellm OWNER \"${POSTGRES_USER}\";" \
                >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1 \
                && log_success "  litellm database reset" \
                || log_warning "  Could not reset litellm database"
        fi

        deploy_service litellm
        wait_for_healthy litellm 180
    }

    # 6. Monitoring — independent of AI services
    [[ "${ENABLE_MONITORING:-false}" == "true" ]] && {
        deploy_service prometheus
        deploy_service grafana
    }

    # 7. Reverse proxy — depends only on infra (postgres, redis healthy)
    deploy_service caddy

    # 8. Web services — only deploy services with compose blocks
    [[ "${ENABLE_OPENWEBUI:-false}"   == "true" ]] && deploy_service open-webui
    [[ "${ENABLE_N8N:-false}"         == "true" ]] && deploy_service n8n
    [[ "${ENABLE_FLOWISE:-false}"     == "true" ]] && deploy_service flowise
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && deploy_service anythingllm
    # dify/authentik/signal: compose blocks not yet implemented — skip

    # 9. External wiring (non-blocking — skip gracefully if not configured)
    [[ "${ENABLE_TAILSCALE:-false}"  == "true" ]] && configure_tailscale || true
    [[ "${ENABLE_CODESERVER:-false}" == "true" ]] && deploy_service codeserver
    [[ "${ENABLE_OPENCLAW:-false}"  == "true" ]] && deploy_service openclaw
    [[ -n "${GDRIVE_CLIENT_ID:-}" ]] && { setup_gdrive_rclone && create_ingestion_systemd || true; }

    # 10. Health dashboard — script 2 STOPS after this
    health_dashboard

    log_info "=== DEPLOY COMPLETE ==="
}

# Only run main if executed directly (not when sourced)
(return 0 2>/dev/null) || main "$@"
