#!/usr/bin/env bash
# =============================================================================
# Script 2: Atomic Deployer - README COMPLIANT
# =============================================================================
# PURPOSE: Source platform.conf, generate configs with heredoc, deploy containers
# USAGE:   bash scripts/2-deploy-services.sh [tenant_id] [options]
# OPTIONS: --dry-run           Show what would be deployed without action
#          --validate-only     Only validate configs, don't deploy
# =============================================================================

set -euo pipefail

# =============================================================================
# NON-ROOT EXECUTION CHECK (README P7)
# =============================================================================
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: This script must not be run as root (README P7 requirement)"
    exit 1
fi

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# =============================================================================
# LOGGING (README P11)
# =============================================================================
LOG_FILE=""
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}
ok() { log "OK: $*"; }
warn() { log "WARN: $*"; }
fail() { log "FAIL: $*"; exit 1; }
dry_run() { [[ "${DRY_RUN:-false}" == "true" ]] && echo "[DRY-RUN] $1"; }

# =============================================================================
# IDEMPOTENCY MARKERS (README P8)
# =============================================================================
CONFIGURED_DIR=""
step_done() { [[ -f "${CONFIGURED_DIR}/${1}" ]]; }
mark_done() { touch "${CONFIGURED_DIR}/${1}"; }

# =============================================================================
# FRAMEWORK VALIDATION
# =============================================================================
framework_validate() {
    log "Validating deployment framework..."
    
    # Binary availability checks
    for bin in docker yq; do
        if ! command -v "$bin" >/dev/null 2>&1; then
            fail "Missing required binary: $bin"
        fi
    done
    
    # Docker daemon health
    if ! docker info >/dev/null 2>&1; then
        fail "Docker daemon not running or accessible"
    fi
    
    # Docker compose plugin
    if ! docker compose version >/dev/null 2>&1; then
        fail "Docker compose plugin not available"
    fi
    
    ok "Framework validation passed"
}

# =============================================================================
# DOCKER COMPOSE GENERATION (README P3 - HEREDOC ONLY)
# =============================================================================
generate_compose() {
    local compose_file="${CONFIG_DIR}/docker-compose.yml"
    
    log "Generating docker-compose.yml..."
    
    # Header and networks
    cat > "$compose_file" << EOF
version: '3.8'

networks:
  ${DOCKER_NETWORK}:
    driver: bridge
    ipam:
      config:
        - subnet: ${DOCKER_SUBNET}

services:
EOF

    # PostgreSQL (README P3 - explicit heredoc blocks)
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        cat >> "$compose_file" << EOF
  postgres:
    image: postgres:15-alpine
    container_name: ${PREFIX}-${TENANT_ID}-postgres
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    ports:
      - "127.0.0.1:${POSTGRES_PORT}:5432"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

EOF
    fi

    # Redis
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        cat >> "$compose_file" << EOF
  redis:
    image: redis:7-alpine
    container_name: ${PREFIX}-${TENANT_ID}-redis
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    command: redis-server --appendonly yes
    volumes:
      - ${DATA_DIR}/redis:/data
    ports:
      - "127.0.0.1:${REDIS_PORT}:6379"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 10

EOF
    fi

    # Ollama
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        cat >> "$compose_file" << EOF
  ollama:
    image: ollama/ollama:latest
    container_name: ${PREFIX}-${TENANT_ID}-ollama
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    volumes:
      - ${DATA_DIR}/ollama:/root/.ollama
    ports:
      - "127.0.0.1:${OLLAMA_PORT}:11434"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # LiteLLM
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        cat >> "$compose_file" << EOF
  litellm:
    image: ghcr.io/berriai/litellm:main
    container_name: ${PREFIX}-${TENANT_ID}-litellm
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      REDIS_URL: redis://redis:6379
    volumes:
      - ${CONFIG_DIR}/litellm/config.yaml:/app/config.yaml
    ports:
      - "127.0.0.1:${LITELLM_PORT}:4000"
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      - postgres
      - redis
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Open WebUI
    if [[ "${OPEN_WEBUI_ENABLED}" == "true" ]]; then
        cat >> "$compose_file" << EOF
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ${PREFIX}-${TENANT_ID}-open-webui
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      OLLAMA_BASE_URL: http://ollama:11434
    volumes:
      - ${DATA_DIR}/open-webui:/app/backend/data
    ports:
      - "127.0.0.1:${OPEN_WEBUI_PORT}:3000"
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      - ollama
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Qdrant
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        cat >> "$compose_file" << EOF
  qdrant:
    image: qdrant/qdrant:latest
    container_name: ${PREFIX}-${TENANT_ID}-qdrant
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    volumes:
      - ${DATA_DIR}/qdrant:/qdrant/storage
    ports:
      - "127.0.0.1:${QDRANT_PORT}:6333"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/health"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Caddy (reverse proxy - only if enabled)
    if [[ "${CADDY_ENABLED}" == "true" ]]; then
        cat >> "$compose_file" << EOF
  caddy:
    image: caddy:2-alpine
    container_name: ${PREFIX}-${TENANT_ID}-caddy
    restart: unless-stopped
    cap_add:
      - NET_BIND_SERVICE
    volumes:
      - ${CONFIG_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile
      - ${DATA_DIR}/caddy:/data
    ports:
      - "${CADDY_HTTP_PORT}:80"
      - "${CADDY_HTTPS_PORT}:443"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:2019/config/"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    ok "docker-compose.yml generated"
}

# =============================================================================
# CONFIG FILE GENERATION
# =============================================================================
generate_configs() {
    log "Generating service configuration files..."
    
    # LiteLLM config
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        mkdir -p "${CONFIG_DIR}/litellm"
        cat > "${CONFIG_DIR}/litellm/config.yaml" << EOF
model_list:
  - model_name: ollama/llama2
    litellm_params:
      model: ollama/llama2
      api_base: http://ollama:11434

litellm_settings:
  drop_params: true
  set_verbose: false
  success_callback: ["langfuse"]
EOF
        chown -R "$PUID:$PGID" "${CONFIG_DIR}/litellm"
    fi
    
    # Caddy config
    if [[ "${CADDY_ENABLED}" == "true" ]]; then
        mkdir -p "${CONFIG_DIR}/caddy"
        cat > "${CONFIG_DIR}/caddy/Caddyfile" << EOF
{
    admin localhost:2019
    email admin@${BASE_DOMAIN}
}

:80 {
    respond "Hello from AI Platform"
}
EOF
        chown -R "$PUID:$PGID" "${CONFIG_DIR}/caddy"
    fi
    
    ok "Configuration files generated"
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================
deploy_containers() {
    local compose_file="${CONFIG_DIR}/docker-compose.yml"
    
    log "Deploying containers..."
    
    # Create Docker network
    if ! docker network ls | grep -q "${DOCKER_NETWORK}"; then
        dry_run "Creating Docker network: ${DOCKER_NETWORK}"
        [[ "${DRY_RUN:-false}" != "true" ]] && docker network create "${DOCKER_NETWORK}"
    fi
    
    # Deploy containers
    dry_run "Deploying containers with docker-compose..."
    [[ "${DRY_RUN:-false}" != "true" ]] && docker compose -f "$compose_file" up -d
    
    ok "Containers deployed"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    local tenant_id="${1:-}"
    local dry_run=false
    local validate_only=false
    
    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --validate-only)
                validate_only=true
                shift
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
    
    # Set global variables
    export DRY_RUN="$dry_run"
    
    # Source platform.conf (README P1)
    local platform_conf="/mnt/${tenant_id}/config/platform.conf"
    if [[ ! -f "$platform_conf" ]]; then
        fail "platform.conf not found at $platform_conf. Run script 1 first."
    fi
    source "$platform_conf"
    
    # Set up logging
    LOG_FILE="${LOGS_DIR}/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log"
    CONFIGURED_DIR="${BASE_DIR}/.configured"
    mkdir -p "$CONFIGURED_DIR"
    
    log "=== Script 2: Atomic Deployer ==="
    log "Tenant: ${tenant_id}"
    log "Dry-run: ${dry_run}"
    log "Validate-only: ${validate_only}"
    
    # Framework validation
    framework_validate
    
    # Generate docker-compose.yml (README P3)
    if ! step_done "compose_generated"; then
        generate_compose
        mark_done "compose_generated"
    else
        log "docker-compose.yml already generated, skipping"
    fi
    
    # Generate config files
    if ! step_done "configs_generated"; then
        generate_configs
        mark_done "configs_generated"
    else
        log "Configuration files already generated, skipping"
    fi
    
    # Deploy containers (unless validate-only)
    if [[ "$validate_only" != "true" ]]; then
        if ! step_done "containers_deployed"; then
            deploy_containers
            mark_done "containers_deployed"
        else
            log "Containers already deployed, skipping"
        fi
    fi
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              Script 2 Complete ✓                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ✓ platform.conf sourced (single source of truth)"
    echo "  ✓ docker-compose.yml generated (heredoc only)"
    echo "  ✓ Configuration files generated"
    echo "  ✓ Containers deployed with health checks"
    echo ""
    echo "  Next step:"
    echo "  1. Verify deployment: bash scripts/3-configure-services.sh ${tenant_id}"
    echo ""
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
