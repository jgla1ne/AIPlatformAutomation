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

# Load router choice from environment
LLM_ROUTER=$(grep "^LLM_ROUTER=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo "bifrost")
echo "ℹ LLM Router selected: ${LLM_ROUTER}"

# Source script 3 for helper functions
source "${SCRIPT_DIR}/3-configure-services.sh"

# ── Helper Functions ────────────────────────────────────────────────
# Service port mapping for health checks
declare -A SERVICE_PORTS=(
    ["postgres"]="5432"
    ["redis"]="6379"
    ["qdrant"]="6333"
    ["litellm"]="4000"
    ["ollama"]="11434"
    ["open-webui"]="8081"
    ["anythingllm"]="3001"
    ["flowise"]="3000"
    ["n8n"]="5678"
    ["codeserver"]="8444"
    ["openclaw"]="18789"
)

# Service startup timeouts
declare -A SERVICE_STARTUP_TIMEOUTS=(
    ["postgres"]="60"
    ["redis"]="30"
    ["qdrant"]="60"
    ["litellm"]="180"
    ["ollama"]="120"
    ["open-webui"]="60"
    ["anythingllm"]="90"
    ["flowise"]="60"
    ["n8n"]="60"
    ["codeserver"]="60"
    ["openclaw"]="60"
)

wait_for_healthy() {
    local service="$1"
    local max_wait="${2:-120}"
    local check_interval="${3:-5}"
    local elapsed=0
    
    log_info "Waiting for ${service} to be healthy (max ${max_wait}s)..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        # Check Docker health status first
        local docker_health
        docker_health="$(docker compose -f "/mnt/data/${TENANT}/docker-compose.yml" ps --format "{{.Health}}" "$service" 2>/dev/null || echo "none")"
        
        if [[ "$docker_health" == "healthy" ]]; then
            # Trust Docker health status - no secondary HTTP check needed
            log_success "${service} is healthy"
            return 0
        elif [[ "$docker_health" == "unhealthy" ]]; then
            log_warning "${service} is unhealthy — proceeding anyway"
            docker logs "ai-${TENANT}-${service}-1" --tail 20
            return 0
        fi
        
        elapsed=$((elapsed + check_interval))
        
        if [[ $((elapsed % 15)) -eq 0 ]]; then
            log_info "${service} still starting... (${elapsed}s/${max_wait}s)"
        fi
        
        sleep $check_interval
    done
    
    log_warning "${service} did not become healthy within ${max_wait}s — proceeding anyway"
    return 0
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

    # Validate Caddyfile before proceeding with deployment
    log_info "Validating Caddyfile configuration..."
    if docker run --rm \
        -v "${CONFIG_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
        caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile \
        >> "${LOGS_DIR}/caddy-validate-$(date +%Y%m%d).log" 2>&1; then
        log_success "Caddyfile validation passed"
    else
        log_error "Caddyfile validation failed - aborting deployment"
        log_error "Check validation log: ${LOGS_DIR}/caddy-validate-$(date +%Y%m%d).log"
        exit 1
    fi

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
        
        # Wait for Ollama HTTP server to be ready BEFORE pulling models
        log_info "Waiting for Ollama HTTP server to be ready..."
        local elapsed=0
        until docker compose -f "/mnt/data/${TENANT}/docker-compose.yml" exec -T ollama \
            curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; do
            elapsed=$((elapsed + 5))
            if [[ $elapsed -ge 60 ]]; then
                log_error "Ollama HTTP not ready after 60s — cannot proceed"
                exit 1
            fi
            log_info "  Waiting for ollama HTTP... (${elapsed}s)"
            sleep 5
        done
        log_success "Ollama HTTP server is ready"

        # Pull models SYNCHRONOUSLY before starting LiteLLM
        log_info "Pulling required Ollama models before starting LiteLLM..."
        local required_models="llama3.2 nomic-embed-text"
        for model in ${required_models}; do
            log_info "  Pulling ${model}..."
            docker compose -f "/mnt/data/${TENANT}/docker-compose.yml" exec -T ollama \
                ollama pull "$model" \
                >> "/mnt/data/${TENANT}/logs/ollama-pull-$(date +%Y%m%d).log" 2>&1
            [[ $? -eq 0 ]] && log_success "  ✓ ${model} pulled successfully" || {
                log_error "  ✗ Failed to pull ${model}"
                exit 1
            }
        done
        log_success "All required Ollama models are ready"
    }

    # 5. AI gateway — conditional deployment based on router choice
    if [[ "${LLM_ROUTER}" == "bifrost" ]]; then
        deploy_bifrost
    elif [[ "${LLM_ROUTER}" == "litellm" ]]; then
        deploy_litellm
    else
        log_error "Unknown LLM router: ${LLM_ROUTER}"
        exit 1
    fi

        # Always stop and remove the container (ensures fresh config.yaml is loaded)
        log_info "Removing existing litellm container (ensures config reload)..."
        docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
            rm -sf litellm >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1 || true

        # --force only: wipe Prisma cache and reset litellm database (clean slate)
        if [[ "$FORCE_REDEPLOY" == "true" ]]; then
            log_info "  --force: clearing LiteLLM Prisma file cache..."
            rm -rf "${DATA_DIR}/litellm"
            mkdir -p "${DATA_DIR}/litellm"
            chown -R 1000:"${TENANT_GID:-1001}" "${DATA_DIR}/litellm"
            log_success "  Prisma cache cleared"

            log_info "  --force: dropping and recreating litellm database..."
            docker compose -f "$COMPOSE_FILE" exec -T postgres \
                psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
                -c "DROP DATABASE IF EXISTS litellm;" \
                >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1 || true
        fi
    }

    # Helper functions
update_env() {
    local key="$1"
    local value="$2"
    local env_file="${ENV_FILE}"
    
    # Remove existing key if present
    if grep -q "^${key}=" "${env_file}" 2>/dev/null; then
        sed -i "/^${key}=/d" "${env_file}"
    fi
    
    # Add new key-value pair
    echo "${key}=${value}" >> "${env_file}"
}

verify_bifrost_image() {
    log_info "Verifying Bifrost image availability..."
    
    if ! docker pull ruqqq/bifrost:latest 2>&1; then
        log_error "Cannot pull ruqqq/bifrost:latest"
        log_error "Check: https://github.com/ruqqq/bifrost for correct image name"
        exit 1
    fi
    
    # Verify the actual health endpoint by running a test container
    log_info "Verifying Bifrost health endpoint..."
    local test_output
    test_output=$(docker run --rm -d \
        --name bifrost-probe \
        -p 4001:4000 \
        -e BIFROST_PORT=4000 \
        -e BIFROST_AUTH_TOKEN=test-probe \
        ruqqq/bifrost:latest 2>&1)
    
    sleep 5
    
    # Try both common health paths
    local health_path=""
    for path in /health /healthz /; do
        if curl -sf "http://localhost:4001${path}" > /dev/null 2>&1; then
            health_path="$path"
            log_success "Bifrost health endpoint confirmed: ${path}"
            break
        fi
    done
    
    docker rm -f bifrost-probe 2>/dev/null || true
    
    if [[ -z "$health_path" ]]; then
        log_warning "Could not confirm health endpoint. Defaulting to /health"
        health_path="/health"
    fi
    
    # Write confirmed health path to env for use in compose healthcheck
    update_env "BIFROST_HEALTH_PATH" "$health_path"
    
    log_success "Bifrost image verified"
}

deploy_bifrost() {
    log_info "Deploying Bifrost LLM Router..."
    
    # Verify image first
    verify_bifrost_image
    
    # Generate Bifrost service in compose file
    generate_bifrost_service
    
    # Deploy Bifrost service
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d bifrost
    
    # Wait for Bifrost to be healthy
    wait_for_llm_router
    
    log_success "Bifrost deployed and healthy"
}

generate_bifrost_service() {
    log_info "Generating Bifrost docker-compose service..."

    # NO config file. NO volume mount. NO CLI flags.
    # Bifrost is 100% environment variable configured.
    cat >> "${COMPOSE_FILE}" << 'BIFROST_COMPOSE_EOF'

  bifrost:
    image: ruqqq/bifrost:latest
    container_name: ai-platform-bifrost
    restart: unless-stopped
    depends_on:
      ollama:
        condition: service_healthy
    environment:
      BIFROST_PORT: "4000"
      BIFROST_AUTH_TOKEN: ${BIFROST_AUTH_TOKEN}
      BIFROST_PROVIDERS: ${BIFROST_PROVIDERS}
    ports:
      - "4000:4000"
    networks:
      - ai_network
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:4000/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 10s

BIFROST_COMPOSE_EOF

    log_success "Bifrost service definition generated"
}

wait_for_llm_router() {
    local router="${LLM_ROUTER:-bifrost}"
    local container="ai-platform-${router}"
    local max_wait=90
    local elapsed=0

    log_info "Waiting for ${router} to become healthy (max ${max_wait}s)..."

    while [[ $elapsed -lt $max_wait ]]; do
        # Fail fast — detect crash immediately
        local status
        status=$(docker inspect "${container}" --format='{{.State.Status}}' 2>/dev/null || echo "missing")
        
        if [[ "$status" == "exited" ]]; then
            log_error "${router} container exited. Full logs:"
            echo "════════════════════════════════════════"
            docker logs "${container}" 2>&1 | tail -30
            echo "════════════════════════════════════════"
            log_error "Exit code: $(docker inspect ${container} --format='{{.State.ExitCode}}' 2>/dev/null)"
            exit 1
        fi

        # Health check
        if curl -sf "http://localhost:4000/health" > /dev/null 2>&1; then
            log_success "${router} is healthy and accepting requests"
            return 0
        fi

        sleep 3
        elapsed=$((elapsed + 3))
        echo -n "."
    done

    echo ""
    log_error "${router} did not become healthy after ${max_wait}s"
    docker logs "${container}" --tail 30 2>&1
    exit 1
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
