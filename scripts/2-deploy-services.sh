#!/usr/bin/env bash
# =============================================================================
# Script 2: Idempotent service deployer — v4.1
# USAGE:  sudo bash scripts/2-deploy-services.sh [tenant_id] [--force]
# --force: drops and recreates all service databases + flushes Redis cache
#          Use after code changes that affect DB schema or router config
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

# Source script 3 for helper functions (must be before using log_info)
source "${SCRIPT_DIR}/3-configure-services.sh"

# Load router choice from environment
LLM_ROUTER=$(grep "^LLM_ROUTER=" "$ENV_FILE" 2>/dev/null | grep -v "^#" | cut -d= -f2- | tr -d '"' | tr -d "'" || echo "")
log_info "LLM Router selected: ${LLM_ROUTER}"
echo "ℹ LLM Router selected: ${LLM_ROUTER}"

# ── Helper Functions ────────────────────────────────────────────────
# Service port mapping for health checks
declare -A SERVICE_PORTS=(
    ["postgres"]="5432"
    ["redis"]="6379"
    ["qdrant"]="6333"
    ["bifrost"]="4000"
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
    ["bifrost"]="60"
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
    log_info "  Bifrost requests to ollama models will succeed once pulls complete"
}

generate_compose() {
    log_info "Generating Docker Compose configuration..."
    
    # Create minimal compose file with essential services
    cat > "${COMPOSE_FILE}" << EOF
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: ${COMPOSE_PROJECT_NAME}_postgres
    restart: unless-stopped
    user: "70:70"
    environment:
      - POSTGRES_DB=${POSTGRES_DB:-datasquiz}
      - POSTGRES_USER=${POSTGRES_USER:-datasquiz}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-datasquiz123}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - default
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-datasquiz}"]
      interval: 10s
      timeout: 5s
      retries: 5
    labels:
      - "ai-platform.service=postgres"
      - "ai-platform.tenant=${TENANT_ID}"

  redis:
    image: redis:7-alpine
    container_name: ${COMPOSE_PROJECT_NAME}_redis
    restart: unless-stopped
    user: "999:999"
    command: redis-server --requirepass ${REDIS_PASSWORD:-datasquiz123}
    volumes:
      - redis_data:/data
    networks:
      - default
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    labels:
      - "ai-platform.service=redis"
      - "ai-platform.tenant=${TENANT_ID}"

  ollama:
    image: ollama/ollama:latest
    container_name: ${COMPOSE_PROJECT_NAME}_ollama
    restart: unless-stopped
    user: "${OLLAMA_UID:-1001}:${OLLAMA_GID:-1001}"
    volumes:
      - ollama_data:/root/.ollama
    networks:
      - default
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:11434/api/tags || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    labels:
      - "ai-platform.service=ollama"
      - "ai-platform.tenant=${TENANT_ID}"

  bifrost:
    image: ghcr.io/ruqqq/bifrost:latest
    container_name: ai-${TENANT_ID}-bifrost-1
    restart: unless-stopped
    user: "${TENANT_UID:-1000}:${TENANT_GID:-1000}"
    ports:
      - "${BIFROST_PORT:-8000}:8000"
    volumes:
      - /mnt/data/${TENANT_ID}/configs/bifrost:/app/config
      - /mnt/data/${TENANT_ID}/data/bifrost:/app/data
    environment:
      - BIFROST_HOST=0.0.0.0
      - BIFROST_PORT=8000
    networks:
      - default
    labels:
      - "ai-platform.service=bifrost"
      - "ai-platform.tenant=${TENANT_ID}"

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
  ollama_data:
    driver: local

networks:
  default:
    driver: bridge
EOF
    
    log_success "Docker Compose configuration generated: ${COMPOSE_FILE}"
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
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d postgres redis

    # Wait for infrastructure to be healthy
    wait_for_healthy postgres 60
    wait_for_healthy redis 30

    # With --force: drop all service databases before provisioning
    if [[ "$FORCE_REDEPLOY" == "true" ]]; then
        log_info "--force: dropping all service databases for clean slate..."
        drop_service_databases
    fi

    provision_databases          # waits until postgres ready, verifies DBs

    # 4. Local LLM runtime — BEFORE Bifrost
    [[ "${ENABLE_OLLAMA:-false}"     == "true" ]] && {
        docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d ollama
        
        # Wait for Ollama HTTP server to be ready BEFORE pulling models
        log_info "Waiting for Ollama HTTP server to be ready..."
        local elapsed=0
        until curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; do
            elapsed=$((elapsed + 5))
            if [[ $elapsed -ge 60 ]]; then
                log_error "Ollama HTTP not ready after 60s — cannot proceed"
                exit 1
            fi
            log_info "  Waiting for ollama HTTP... (${elapsed}s)"
            sleep 5
        done
        log_success "Ollama HTTP server is ready"

        # Pull models SYNCHRONOUSLY before starting Bifrost
        log_info "Pulling required Ollama models before starting Bifrost..."
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

    # 5. Skip complex services for now - focus on core infrastructure
    log_info "Core infrastructure deployment complete"
    
    # 10. Health dashboard — script 2 STOPS after this
    health_dashboard

    log_info "=== DEPLOY COMPLETE ==="
}

# Only run main if executed directly (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
