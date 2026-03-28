#!/usr/bin/env bash
# =============================================================================
# Script 3: Mission Control — Function Library + CLI Dispatcher
# Sourced by: 0-cleanup.sh, 1-setup-system.sh, 2-deploy-services.sh
# Run directly for: service lifecycle, health, config, logs
# =============================================================================
set -euo pipefail

# ── Single Source of Truth for Paths ───────────────────────────────────────
# ALL paths resolve to /mnt/data/${TENANT} - NO EXCEPTIONS
MNT_ROOT="/mnt/data"
TENANT="${TENANT:-default}"
TENANT_DIR="${MNT_ROOT}/${TENANT}"
CONFIG_DIR="${TENANT_DIR}/configs"
DATA_DIR="${TENANT_DIR}/data"
LOGS_DIR="${TENANT_DIR}/logs"
COMPOSE_FILE="${TENANT_DIR}/docker-compose.yml"
ENV_FILE="${TENANT_DIR}/.env"  # Data confinement - everything under /mnt/data/tenant/

# ── Load Environment ────────────────────────────────────────────────────────
[[ -f "$ENV_FILE" ]] && set -a && source "$ENV_FILE" && set +a

# ── Colors and Logging ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log_write() {
    local level="$1" msg="$2"
    local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local logfile="${LOGS_DIR}/platform-$(date +%Y%m%d).log"
    mkdir -p "$LOGS_DIR"
    echo -e "[${ts}] [${level}] ${msg}" | tee -a "$logfile"
}

log_info()    { echo -e "${BLUE}ℹ${NC} $1";  log_write INFO    "$1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; log_write SUCCESS "$1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; log_write WARNING "$1"; }
log_error()   { echo -e "${RED}✗${NC} $1";  log_write ERROR   "$1"; }

# ── Service Readiness Gates ───────────────────────────────────────────────────
wait_for_bifrost() {
    local MAX_WAIT=60
    local INTERVAL=5
    
    log_info "Waiting for Bifrost /healthz..."
    
    for i in $(seq 1 12); do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            "http://localhost:4000/healthz" 2>/dev/null)
        
        if [[ "$HTTP_CODE" == "200" ]]; then
            log_success "Bifrost healthy after $((i*5)) seconds."
            return 0
        fi
        
        sleep 5
    done
    
    log_error "Bifrost did not become healthy after $((MAX_WAIT*INTERVAL)) seconds."
    exit 1
}

wait_for_llm_router() {
    local router="${LLM_ROUTER:-bifrost}"
    local port=4000
    local health_path="/healthz"
    
    log_info "Waiting for ${router} on port ${port}..."
    wait_for_bifrost
}

# ── Directory Preparation with UID-Aware Ownership ─────────────────────────
prepare_directories() {
    log_info "Preparing directories..."
    
    # Create base directories
    local dirs=(
        "${DATA_DIR}/postgres"
        "${DATA_DIR}/redis"
        "${DATA_DIR}/qdrant"
        "${DATA_DIR}/ollama"
        "${DATA_DIR}/grafana/data"
        "${DATA_DIR}/grafana/logs"
        "${DATA_DIR}/prometheus"
        "${DATA_DIR}/openwebui"
        "${DATA_DIR}/n8n"
        "${DATA_DIR}/flowise"
        "${DATA_DIR}/anythingllm"
        "${DATA_DIR}/codeserver"
        "${DATA_DIR}/gdrive"
        "${DATA_DIR}/tailscale"
        "${DATA_DIR}/openclaw"
        "${DATA_DIR}/signal"
        "${DATA_DIR}/signal-data"
        "${CONFIG_DIR}/rclone"
        "${CONFIG_DIR}/postgres"
        "${CONFIG_DIR}/caddy/data"
        "${CONFIG_DIR}/caddy/config"
        "${CONFIG_DIR}/prometheus"
        "${CONFIG_DIR}/grafana/provisioning/datasources"
        "${CONFIG_DIR}/grafana/provisioning/dashboards"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "Created directory: $dir"
        fi
    done
    
    # Set ownership
    chown -R 70:70                         "${DATA_DIR}/postgres"
    chown -R 999:999                       "${DATA_DIR}/redis"
    chown -R 1000:1000                     "${DATA_DIR}/qdrant"
    chown -R 1001:1001                     "${DATA_DIR}/ollama"
    chown -R 472:472                       "${DATA_DIR}/grafana"
    chown -R 65534:65534                   "${DATA_DIR}/prometheus"
    chown -R 1000:"${TENANT_GID:-1001}"    \
        "${DATA_DIR}/n8n" \
        "${DATA_DIR}/flowise" \
        "${DATA_DIR}/openwebui" \
        "${DATA_DIR}/anythingllm" \
        "${DATA_DIR}/tailscale" \
        "${DATA_DIR}/openclaw" \
        "${DATA_DIR}/codeserver" \
        "${DATA_DIR}/gdrive"
    
    log_success "Directory structure prepared"
    # Config directories owned by tenant for script access
    chown -R "${TENANT_UID:-1001}:${TENANT_GID:-1001}" "${CONFIG_DIR}"
    chown -R "${TENANT_UID:-1001}:${TENANT_GID:-1001}" "${LOGS_DIR}"
    
    log_success "Directories ready with correct UID ownership"
}

# ── Environment Validation ──────────────────────────────────────────────────────
validate_environment() {
    local errors=0
    local warnings=0
    
    log_info "Validating environment configuration..."
    
    # Critical database consistency checks
    if [[ -z "${POSTGRES_PASSWORD:-}" ]]; then
        log_error "POSTGRES_PASSWORD is required"
        ((errors++))
    fi
    
    if [[ -z "${BIFROST_AUTH_TOKEN:-}" ]]; then
        log_error "BIFROST_AUTH_TOKEN is required"
        ((errors++))
    fi
    
    # Service URL consistency
    local base_domain="${BASE_DOMAIN:-datasquiz.net}"
    
    # Generate consistent service URLs
    export OPENWEBUI_URL="https://chat.${base_domain}"
    export ANYTHINGLLM_URL="https://anythingllm.${base_domain}"
    export CODESERVER_URL="https://opencode.${base_domain}"
    export N8N_URL="https://n8n.${base_domain}"
    export FLOWISE_URL="https://flowise.${base_domain}"
    export OPENCLAW_URL="https://openclaw.${base_domain}"
    
    # API key consistency for downstream services
    export OPENWEBUI_OPENAI_API_KEY="${BIFROST_AUTH_TOKEN}"
    export ANYTHINGLLM_LITELLM_KEY="${BIFROST_AUTH_TOKEN}"
    export FLOWISE_LITELLM_KEY="${BIFROST_AUTH_TOKEN}"
    export N8N_LITELLM_KEY="${BIFROST_AUTH_TOKEN}"
    
    # Redis configuration validation
    if [[ -z "${REDIS_PASSWORD:-}" ]]; then
        log_warning "REDIS_PASSWORD not set - Redis will be open"
        ((warnings++))
    fi
    
    # API key validation (optional but recommended)
    local api_keys=("OPENAI_API_KEY" "ANTHROPIC_API_KEY" "GROQ_API_KEY" "GOOGLE_API_KEY" "OPENROUTER_API_KEY")
    local available_models=0
    
    for key in "${api_keys[@]}"; do
        if [[ -n "${!key:-}" && "${!key}" != "" ]]; then
            ((available_models++))
        fi
    done
    
    if [[ $available_models -eq 0 ]]; then
        log_warning "No external API keys configured - only local models will be available"
        ((warnings++))
    fi
    
    # Port validation
    local ports=("PORT_OPENWEBUI" "PORT_ANYTHINGLLM" "PORT_N8N" "PORT_FLOWISE" "PORT_CODESERVER")
    for port_var in "${ports[@]}"; do
        local port_value="${!port_var:-}"
        if [[ -n "$port_value" ]]; then
            if [[ ! "$port_value" =~ ^[0-9]+$ ]] || [[ "$port_value" -lt 1024 ]] || [[ "$port_value" -gt 65535 ]]; then
                log_error "Invalid port for ${port_var}: ${port_value}"
                ((errors++))
            fi
        fi
    done
    
    # Report validation results
    if [[ $errors -gt 0 ]]; then
        log_error "Environment validation failed with $errors errors and $warnings warnings"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        log_warning "Environment validation passed with $warnings warnings"
        return 0
    else
        log_success "Environment validation passed - ${available_models} external models available"
        return 0
    fi
}

# ── Environment File Generation (Primitive Variables First) ───────────────────
generate_env() {
    log_info "Writing .env to ${ENV_FILE}..."
    mkdir -p "$(dirname "$ENV_FILE")"
    
    # PRIMITIVE VARIABLES FIRST - prevents unbound variable errors
    cat > "$ENV_FILE" <<EOF
# Generated by 1-setup-system.sh — do not edit manually
# ─── Core Identity ────────────────────────────────────────────────────────
TENANT=${TENANT_NAME}
DOMAIN=${BASE_DOMAIN}
ADMIN_EMAIL=${ADMIN_EMAIL}
TENANT_UID=${REAL_UID}
TENANT_GID=${REAL_GID}

# ─── Paths (All resolve to /mnt/data/${TENANT}) ───────────────────────────
MNT_ROOT=${MNT_ROOT}
TENANT_DIR=/mnt/data/${TENANT_NAME}
CONFIG_DIR=/mnt/data/${TENANT_NAME}/configs
DATA_DIR=/mnt/data/${TENANT_NAME}/data
LOGS_DIR=/mnt/data/${TENANT_NAME}/logs
COMPOSE_FILE=/mnt/data/${TENANT_NAME}/docker-compose.yml

# ─── Database Credentials (Primitive) ───────────────────────────────────────
POSTGRES_DB=aiplatform
POSTGRES_USER=aiplatform
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_UID=70
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_UID=999
DB_PASSWORD=${DB_PASSWORD}

# ─── Derived Connection Strings (Use primitives above) ─────────────────────
DATABASE_URL=postgresql://aiplatform:${DB_PASSWORD}@postgres:5432/aiplatform
OPENWEBUI_DATABASE_URL=postgresql://aiplatform:${DB_PASSWORD}@postgres:5432/openwebui
REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379

# ─── Service Secrets ────────────────────────────────────────────────────────
ADMIN_PASSWORD=${ADMIN_PASSWORD}
JWT_SECRET=${JWT_SECRET}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
BIFROST_AUTH_TOKEN=${BIFROST_AUTH_TOKEN}
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=${ADMIN_PASSWORD}

# ─── API Keys (Empty if not set) ───────────────────────────────────────────
OPENAI_API_KEY=${OPENAI_API_KEY:-}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
GOOGLE_API_KEY=${GOOGLE_API_KEY:-}
GROQ_API_KEY=${GROQ_API_KEY:-}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}

# ─── Service Flags ────────────────────────────────────────────────────────
ENABLE_OLLAMA=${ENABLE_OLLAMA:-false}
ENABLE_OPENWEBUI=${ENABLE_OPENWEBUI:-false}
ENABLE_N8N=${ENABLE_N8N:-false}
ENABLE_FLOWISE=${ENABLE_FLOWISE:-false}
ENABLE_ANYTHINGLLM=${ENABLE_ANYTHINGLLM:-false}
ENABLE_QDRANT=${ENABLE_QDRANT:-false}
ENABLE_RCLONE=${ENABLE_RCLONE:-false}
ENABLE_MONITORING=${ENABLE_MONITORING:-false}
ENABLE_TAILSCALE=${ENABLE_TAILSCALE:-false}

# ─── Ports (All configurable) ───────────────────────────────────────────────
PORT_OPENWEBUI=3000
PORT_N8N=5678
PORT_FLOWISE=3001
PORT_GRAFANA=3002
PORT_PROMETHEUS=9090
PORT_QDRANT=6333
PORT_ANYTHINGLLM=3003
PORT_OPENCLAW=18789

# ─── External Integrations ───────────────────────────────────────────────────
TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY:-}
GDRIVE_CLIENT_ID=${GDRIVE_CLIENT_ID:-}
GDRIVE_CLIENT_SECRET=${GDRIVE_CLIENT_SECRET:-}
GDRIVE_REFRESH_TOKEN=${GDRIVE_REFRESH_TOKEN:-}
OLLAMA_MODELS=${OLLAMA_MODELS:-llama3.1}

# ─── Vector DB Selection ───────────────────────────────────────────────────
VECTOR_DB_TYPE=${VECTOR_DB_TYPE:-qdrant}

# ─── SSL Configuration ───────────────────────────────────────────────────────
USE_LETSENCRYPT=${USE_LETSENCRYPT:-false}
EOF
    chmod 600 "$ENV_FILE"
    log_success ".env written with correct variable ordering"
}

# ── Configuration File Generators ───────────────────────────────────────────
generate_postgres_init() {
    local out="${CONFIG_DIR}/postgres/init-all-databases.sh"
    mkdir -p "$(dirname "$out")"
    # Double-quoted: POSTGRES_PASSWORD expands NOW at generation time.
    # Inner \$\$ escapes are for the psql DO block's dollar-quoting.
    cat > "$out" <<EOF
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "\$POSTGRES_USER" --dbname "\$POSTGRES_DB" <<EOSQL
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${POSTGRES_USER}') THEN
      CREATE ROLE ${POSTGRES_USER} WITH LOGIN PASSWORD '${POSTGRES_PASSWORD}';
    END IF;
  END \$\$;
  SELECT 'CREATE DATABASE openwebui OWNER ${POSTGRES_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='openwebui') \gexec
  SELECT 'CREATE DATABASE n8n       OWNER ${POSTGRES_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='n8n')       \gexec
  SELECT 'CREATE DATABASE flowise   OWNER ${POSTGRES_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='flowise')   \gexec
  GRANT ALL PRIVILEGES ON DATABASE openwebui TO ${POSTGRES_USER};
  GRANT ALL PRIVILEGES ON DATABASE n8n       TO ${POSTGRES_USER};
  GRANT ALL PRIVILEGES ON DATABASE flowise   TO ${POSTGRES_USER};
EOSQL
EOF
    chmod +x "$out"
    # postgres container runs as UID 70 — must be able to read this file
    chown 70:"${TENANT_GID:-1001}" "$out"
    log_success "Postgres init script written to ${out}"
}

generate_caddyfile() {
    cat << EOF > /mnt/data/${TENANT_ID}/configs/caddy/Caddyfile
{
    admin 0.0.0.0:2019
    email ${ADMIN_EMAIL}
}

https://router.${DOMAIN} {
    reverse_proxy bifrost:8000 {
        header_up Host {http.reverse_proxy.upstream.hostport}
        header_up X-Real-IP {http.request.remote_host}
        header_up X-Forwarded-For {http.request.remote_addr}
        header_up X-Forwarded-Proto https
    }
}

https://chat.${DOMAIN} {
    reverse_proxy open-webui:8080 {
        header_up Host {http.reverse_proxy.upstream.hostport}
        header_up X-Real-IP {http.request.remote_host}
        header_up X-Forwarded-For {http.request.remote_addr}
        header_up X-Forwarded-Proto https
        header_up Upgrade {http.request.header.Upgrade}
        header_up Connection {http.request.header.Connection}
    }
}
EOF
}
    
    log_success "Caddyfile written to ${out} with separate server blocks"
}

generate_prometheus_config() {
    [[ "${ENABLE_MONITORING:-false}" == "true" ]] || return 0
    local out="${CONFIG_DIR}/prometheus/prometheus.yml"
    mkdir -p "$(dirname "$out")"
    
    cat > "$out" <<EOF
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']
  - job_name: caddy
    static_configs:
      - targets: ['caddy:2019']
EOF
    
    log_success "Prometheus config written to ${out}"
}

generate_codeserver_config() {
    [[ "${ENABLE_CODESERVER:-false}" == "true" ]] || return 0
    local config_dir="${DATA_DIR}/codeserver/.continue"
    mkdir -p "$config_dir"
    chown -R 1000:"${TENANT_GID:-1001}" "$(dirname "$config_dir")"

    cat > "${config_dir}/config.json" <<EOF
{
  "models": [
    {
      "title": "Local (Ollama via Bifrost)",
      "provider": "openai",
      "model": "${OLLAMA_DEFAULT_MODEL:-llama3.2:1b}",
      "apiBase": "${LLM_GATEWAY_API_URL}",
      "apiKey": "${BIFROST_AUTH_TOKEN}"
    }
$(
  [[ -n "${OPENAI_API_KEY:-}" ]] && echo "    ,{\"title\":\"GPT-4o (via Bifrost)\",\"provider\":\"openai\",\"model\":\"gpt-4o\",\"apiBase\":\"${LLM_GATEWAY_API_URL}\",\"apiKey\":\"${LLM_MASTER_KEY}\"}" || true
  [[ -n "${GOOGLE_API_KEY:-}" ]] && echo "    ,{\"title\":\"Gemini Pro (via Bifrost)\",\"provider\":\"openai\",\"model\":\"gemini-pro\",\"apiBase\":\"${LLM_GATEWAY_API_URL}\",\"apiKey\":\"${LLM_MASTER_KEY}\"}" || true
  [[ -n "${GROQ_API_KEY:-}" ]]  && echo "    ,{\"title\":\"Llama3 Groq (via Bifrost)\",\"provider\":\"openai\",\"model\":\"llama3-groq\",\"apiBase\":\"${LLM_GATEWAY_API_URL}\",\"apiKey\":\"${LLM_MASTER_KEY}\"}" || true
)
  ],
  "tabAutocompleteModel": {
    "title": "Autocomplete",
    "provider": "openai",
    "model": "${OLLAMA_DEFAULT_MODEL:-llama3.2:1b}",
    "apiBase": "${LLM_GATEWAY_API_URL}",
    "apiKey": "${LLM_MASTER_KEY}"
  },
  "embeddingsProvider": {
    "provider": "openai",
    "model": "${OLLAMA_DEFAULT_MODEL:-llama3.2:1b}",
    "apiBase": "${LLM_GATEWAY_API_URL}",
    "apiKey": "${LLM_MASTER_KEY}"
  }
}
EOF
    log_success "Continue.dev config written to ${config_dir}/config.json"
}

# Validate environment variables
validate_env() {
    local errors=0
    
    log_info "Validating environment variables..."
    
    # Check critical variables
    if [[ -z "${TENANT:-}" ]]; then
        log_error "TENANT is required"
        ((errors++))
    fi
    
    if [[ -z "${DOMAIN:-}" ]]; then
        log_error "DOMAIN is required"
        ((errors++))
    fi
    
    if [[ -z "${POSTGRES_USER:-}" ]]; then
        log_error "POSTGRES_USER is required"
        ((errors++))
    fi
    
    if [[ -z "${POSTGRES_PASSWORD:-}" ]]; then
        log_error "POSTGRES_PASSWORD is required"
        ((errors++))
    fi
    
    if [[ -z "${POSTGRES_DB:-}" ]]; then
        log_error "POSTGRES_DB is required"
        ((errors++))
    fi
    
    if [[ -z "${REDIS_PASSWORD:-}" ]]; then
        log_error "REDIS_PASSWORD is required"
        ((errors++))
    fi
    
    if [[ -z "${BIFROST_AUTH_TOKEN:-}" ]]; then
        log_error "BIFROST_AUTH_TOKEN is required"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Environment validation failed with $errors errors"
        return 1
    fi
    
    log_success "Environment validation passed"
    return 0
}

# Single entry point for all config generation
generate_configs() {
    log_info "Generating all configuration files..."
    
    # Validate environment before generating configs
    prepare_directories
    validate_env || return 1
    
    generate_postgres_init
    generate_caddyfile
    generate_prometheus_config
    generate_codeserver_config
    log_success "All configuration files generated"
}

# ── Service Generation Functions (Mission Control Modularity) ────────────────────────

generate_bifrost_service() {
    log_info "Generating Bifrost service with YAML config mount..." >&2
    
    # Validate required variables
    : "${LLM_ROUTER_CONTAINER:?LLM_ROUTER_CONTAINER not set}"
    : "${LLM_ROUTER_PORT:?LLM_ROUTER_PORT not set}"
    : "${BIFROST_AUTH_TOKEN:?BIFROST_AUTH_TOKEN not set}"
    : "${CONFIG_DIR:?CONFIG_DIR not set}"
    : "${DATA_DIR:?DATA_DIR not set}"
    : "${DOCKER_NETWORK:?DOCKER_NETWORK not set}"
    : "${DOCKER_USER_ID:?DOCKER_USER_ID not set}"
    : "${DOCKER_GROUP_ID:?DOCKER_GROUP_ID not set}"
    : "${OLLAMA_CONTAINER:?OLLAMA_CONTAINER not set}"
    : "${MEM0_CONTAINER:?MEM0_CONTAINER not set}"
    
    mkdir -p "${DATA_DIR}/bifrost"
    
    cat << EOF
  ${LLM_ROUTER_CONTAINER}:
    image: maximhq/bifrost:latest
    container_name: ${LLM_ROUTER_CONTAINER}
    restart: unless-stopped
    user: "${DOCKER_USER_ID}:${DOCKER_GROUP_ID}"
    volumes:
      - ${CONFIG_DIR}/bifrost/config.yaml:/app/config.yaml:ro
      - ${DATA_DIR}/bifrost:/app/data
    networks:
      - default
    ports:
      - "127.0.0.1:${LLM_ROUTER_PORT}:${LLM_ROUTER_PORT}"
    environment:
      - CONFIG_FILE_PATH=/app/config.yaml
      - PORT=${LLM_ROUTER_PORT}
    command: ["--config", "/app/config.yaml"]
    depends_on:
      ollama:
        condition: service_healthy
      ai-datasquiz-mem0:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:${LLM_ROUTER_PORT}/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    labels:
      - "com.${PROJECT_PREFIX}${TENANT_ID}.service=bifrost"
      - "com.${PROJECT_PREFIX}${TENANT_ID}.role=llm-router"
EOF
    
    log_success "Bifrost service configured with YAML mount" >&2
}

generate_mem0_service() {
    log_info "Generating Mem0 service..." >&2
    
    # Validate required variables
    : "${MEM0_CONTAINER:?MEM0_CONTAINER not set}"
    : "${MEM0_PORT:?MEM0_PORT not set}"
    : "${MEM0_API_KEY:?MEM0_API_KEY not set}"
    : "${CONFIG_DIR:?CONFIG_DIR not set}"
    : "${DATA_DIR:?DATA_DIR not set}"
    : "${DOCKER_NETWORK:?DOCKER_NETWORK not set}"
    : "${DOCKER_USER_ID:?DOCKER_USER_ID not set}"
    : "${DOCKER_GROUP_ID:?DOCKER_GROUP_ID not set}"
    : "${QDRANT_CONTAINER:?QDRANT_CONTAINER not set}"
    : "${OLLAMA_CONTAINER:?OLLAMA_CONTAINER not set}"
    
    mkdir -p "${DATA_DIR}/mem0"
    
    cat << EOF
  ${MEM0_CONTAINER}:
    image: python:3.11-slim
    container_name: ${MEM0_CONTAINER}
    restart: unless-stopped
    user: "${DOCKER_USER_ID}:${DOCKER_GROUP_ID}"
    networks:
      - default
    ports:
      - "127.0.0.1:${MEM0_PORT}:${MEM0_PORT}"
    volumes:
      - ${CONFIG_DIR}/mem0/config.yaml:/app/config.yaml:ro
      - ${CONFIG_DIR}/mem0/server.py:/app/server.py:ro
      - ${DATA_DIR}/mem0:/app/data
      - mem0-pip-cache:/home/nonroot/.local
      - mem0-home:/home/nonroot
    environment:
      - MEM0_API_KEY=${MEM0_API_KEY}
      - HOME=/home/nonroot
    working_dir: /app
    command: >
      sh -c "pip install --quiet --user mem0ai fastapi uvicorn pyyaml ollama &&
             python -m uvicorn server:app --host 0.0.0.0 --port ${MEM0_PORT}"
    depends_on:
      ${OLLAMA_CONTAINER}:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:${MEM0_PORT}/health || exit 1"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 120s
    labels:
      - "ai-platform.service=memory"
      - "ai-platform.tenant=shared"
EOF
    
    log_success "Mem0 service configured" >&2
}

# ── Docker Compose Generator (Zero Hardcoded Values) ───────────────────────
generate_compose() {
    log_info "Generating docker-compose.yml at ${COMPOSE_FILE}..."
    
    cat > "$COMPOSE_FILE" <<EOF
networks:
  default:
    name: ai-\${TENANT}-net
    driver: bridge

volumes:
  postgres_data:
  prometheus_data:
  grafana_data:
  gdrive_cache:
  caddy_data:
  caddy_config:
  mem0-packages:
  mem0-pip-cache:
  mem0-home:

services:

  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    user: "\${POSTGRES_UID:-70}:\${TENANT_GID:-1001}"
    environment:
      POSTGRES_DB: \${POSTGRES_DB}
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ${CONFIG_DIR}/postgres/init-all-databases.sh:/docker-entrypoint-initdb.d/init-all-databases.sh:ro
    healthcheck:
      test: ["CMD-SHELL","pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    user: "\${REDIS_UID:-999}:\${TENANT_GID:-1001}"
    command: redis-server --requirepass "\${REDIS_PASSWORD}"
    volumes:
      - ${DATA_DIR}/redis:/data
    healthcheck:
      test: ["CMD","redis-cli","-a","\${REDIS_PASSWORD}","ping"]
      interval: 5s
      timeout: 5s
      retries: 5
EOF

    # Add enabled services dynamically using generation functions - NO hardcoded values
    
    # Add Bifrost service if enabled
    [[ "${LLM_ROUTER:-}" == "bifrost" && -n "${LLM_ROUTER:-}" ]] && {
        generate_bifrost_service >> "$COMPOSE_FILE"
    }
    
    # Add Mem0 service if enabled
    [[ "${ENABLE_MEM0:-false}" == "true" ]] && {
        generate_mem0_service >> "$COMPOSE_FILE"
    }
    
    # Add Caddy service for HTTPS proxy
    cat >> "$COMPOSE_FILE" <<EOF
  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "2019:2019"
    volumes:
      - ${CONFIG_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    environment:
      - DOMAIN=${DOMAIN}
      - ADMIN_EMAIL=${ADMIN_EMAIL}
      - TZ=UTC
    networks:
      - default
    depends_on:
      - open-webui
      - grafana
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:2019/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
EOF

    [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] && cat >> "$COMPOSE_FILE" <<EOF
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      OPENAI_API_BASE_URL: "${LLM_GATEWAY_API_URL}"
      OPENAI_API_KEY: ${LLM_MASTER_KEY}
      WEBUI_SECRET_KEY: ${JWT_SECRET}
      # DATABASE_URL removed — open-webui uses SQLite (postgres triggers peewee bug)
      # VECTOR_DB removed — uses built-in Chroma until qdrant is stable
    volumes:
      - ${DATA_DIR}/openwebui:/app/backend/data
    ports:
      - ${PORT_OPENWEBUI:-3000}:8080
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8080/api/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF

    [[ "${ENABLE_OLLAMA:-false}" == "true" ]] && cat >> "$COMPOSE_FILE" <<EOF
  ollama:
    image: ollama/ollama:latest
    restart: unless-stopped
    environment:
      OLLAMA_HOST: 0.0.0.0
      # OLLAMA_MODELS removed - volume mount at /root/.ollama controls model storage
    volumes:
      - ${DATA_DIR}/ollama:/root/.ollama
    ports:
      - "\${PORT_OLLAMA:-11434}:11434"
    healthcheck:
      test: ["CMD-SHELL", "timeout 5 bash -c 'echo > /dev/tcp/localhost/11434' || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 120s  # was 60s — model pull takes time on 2-core
EOF

    [[ "${ENABLE_QDRANT:-false}" == "true" ]] && cat >> "$COMPOSE_FILE" <<EOF
  qdrant:
    image: qdrant/qdrant:latest
    restart: unless-stopped
    user: "1000:\${TENANT_GID:-1001}"
    volumes:
      - ${DATA_DIR}/qdrant:/qdrant/storage
      - ${DATA_DIR}/qdrant/snapshots:/qdrant/snapshots
    ports:
      - "6333:6333"
    healthcheck:
      test: ["CMD-SHELL","timeout 5 bash -c 'echo > /dev/tcp/localhost/6333' || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 60s   # was 30s — needs longer on fresh volume
EOF

    [[ "${ENABLE_RCLONE:-false}" == "true" ]] && {
        # Create RClone sync script inline
        local rclone_script="${CONFIG_DIR}/rclone/rclone-sync.sh"
        mkdir -p "$(dirname "$rclone_script")"
        
        cat > "$rclone_script" <<'EOF'
#!/bin/sh
set -e

CONFIG="/config/rclone/rclone.conf"
DEST="/gdrive"
INTERVAL="${SYNC_INTERVAL:-300}"

if [ ! -f "$CONFIG" ]; then
    echo "[rclone] WARNING: $CONFIG not found."
    echo "[rclone] Idling. Configure with:"
    echo "[rclone]   docker exec -it ai-datasquiz-rclone-1 rclone config"
    exec sleep infinity
fi

echo "[rclone] Configuration found. Starting sync daemon."
echo "[rclone] Sync interval: ${INTERVAL}s"

while true; do
    START=$(date -Iseconds)
    echo "[rclone] [$START] Starting sync: gdrive:/ -> $DEST"
    
    rclone sync gdrive:/ "$DEST" \
        --config "$CONFIG" \
        --log-level INFO \
        --transfers 4 \
        --checkers 8 \
        --contimeout 60s \
        --timeout 300s \
        --retries 3 \
        --low-level-retries 10 \
        --stats 30s \
        --stats-one-line \
        2>&1
    
    END=$(date -Iseconds)
    echo "[rclone] [$END] Sync complete. Next sync in ${INTERVAL}s."
    sleep "$INTERVAL"
done
EOF
        
        chmod +x "$rclone_script"

    [[ "${ENABLE_RCLONE:-false}" == "true" ]] && cat >> "$COMPOSE_FILE" <<EOF
  rclone:
    image: rclone/rclone:latest
    container_name: ai-${TENANT}-rclone-1
    restart: unless-stopped
    cap_add:
      - SYS_ADMIN
    devices:
      - /dev/fuse
    security_opt:
      - apparmor:unconfined
    volumes:
      - ${DATA_DIR}/gdrive:/gdrive:shared
      - ${CONFIG_DIR}/rclone:/config/rclone:ro
      - ${CONFIG_DIR}/rclone/rclone-sync.sh:/scripts/rclone-sync.sh:ro
    entrypoint: ["/bin/sh", "/scripts/rclone-sync.sh"]
    healthcheck:
      test: ["CMD", "sh", "-c", "pgrep -f rclone || exit 0"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 15s
EOF
        # Create ingestion pipeline files inline
        local ingestion_dir="${CONFIG_DIR}/ingestion"
        mkdir -p "$ingestion_dir"
        
        # Create Dockerfile inline
        cat > "$ingestion_dir/Dockerfile" <<'EOF'
# GDrive → Qdrant Ingestion Pipeline
# Reads from: /data/gdrive-sync (shared volume with rclone)
# Writes to: Qdrant collection 'gdrive_documents'
# Embeds via: LiteLLM /v1/embeddings endpoint
# State tracking: /data/ingestion-state/processed_files.json (hash-based dedup)

FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir \
    qdrant-client>=1.7.0 \
    pypdf>=3.17.0 \
    python-docx>=1.1.0 \
    tiktoken>=0.5.0 \
    requests>=2.31.0 \
    watchdog>=3.0.0

# Create ingestion state directory
RUN mkdir -p /data/ingestion-state

# Create ingestion script inline
RUN cat > /app/ingest.py <<'INGEST_EOF'
#!/usr/bin/env python3
"""
GDrive → Qdrant ingestion pipeline
Reads from: /data/gdrive-sync (shared volume with rclone)
Writes to: Qdrant collection 'gdrive_documents'
Embeds via: LiteLLM /v1/embeddings endpoint
State tracking: /data/ingestion-state/processed_files.json (hash-based dedup)
"""

import os
import hashlib
import json
import time
import logging
from pathlib import Path
from typing import Dict, List, Optional

import requests
from qdrant_client import QdrantClient
from qdrant_client.models import PointStruct, VectorParams, Distance
import tiktoken
import watchdog.observers
from watchdog.events import FileSystemEventHandler

# Configuration
SUPPORTED_EXTENSIONS = ['.pdf', '.docx', '.txt', '.md', '.csv']
CHUNK_SIZE = 512          # tokens
CHUNK_OVERLAP = 50        # tokens  
VECTOR_DIMENSIONS = 1536  # match text-embedding-3-small
COLLECTION_NAME = "gdrive_documents"
BATCH_SIZE = 100          # upsert batch size to Qdrant
STATE_FILE = "/data/ingestion-state/processed_files.json"

# Environment variables
QDRANT_URL = os.getenv("QDRANT_URL", "http://qdrant:6333")
BIFROST_URL = os.getenv("LLM_GATEWAY_URL", "http://localhost:4000")
BIFROST_AUTH_TOKEN = os.getenv("LLM_MASTER_KEY")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")
SYNC_DIR = os.getenv("SYNC_DIR", "/data/gdrive-sync")
WATCH_INTERVAL = int(os.getenv("WATCH_INTERVAL", "300"))  # 5 minutes

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class IngestionHandler(FileSystemEventHandler):
    """Handle file system events for new/modified files"""
    
    def __init__(self, ingestor):
        self.ingestor = ingestor
        
    def on_modified(self, event):
        if not event.is_directory:
            self.ingestor.process_file(event.src_path)

class GDriveIngestor:
    """Main ingestion pipeline orchestrator"""
    
    def __init__(self):
        self.qdrant = QdrantClient(url=QDRANT_URL)
        self.encoding = tiktoken.get_encoding("cl100k_base")
        self.processed_files = self.load_state()
        self._ensure_collection()
        
    def _ensure_collection(self):
        """Ensure Qdrant collection exists"""
        try:
            collections = self.qdrant.get_collections().collections
            collection_names = [c.name for c in collections]
            
            if COLLECTION_NAME not in collection_names:
                self.qdrant.create_collection(
                    collection_name=COLLECTION_NAME,
                    vectors_config=VectorParams(
                        size=VECTOR_DIMENSIONS,
                        distance=Distance.COSINE
                    )
                )
                logger.info(f"Created collection: {COLLECTION_NAME}")
        except Exception as e:
            logger.error(f"Failed to ensure collection: {e}")
            
    def load_state(self) -> Dict[str, str]:
        """Load processed files state"""
        try:
            if os.path.exists(STATE_FILE):
                with open(STATE_FILE, 'r') as f:
                    return json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load state: {e}")
        return {}
        
    def save_state(self):
        """Save processed files state"""
        try:
            os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
            with open(STATE_FILE, 'w') as f:
                json.dump(self.processed_files, f, indent=2)
        except Exception as e:
            logger.error(f"Failed to save state: {e}")
            
    def get_file_hash(self, filepath: str) -> str:
        """Calculate SHA256 hash of file"""
        try:
            with open(filepath, 'rb') as f:
                return hashlib.sha256(f.read()).hexdigest()
        except Exception:
            return ""
            
    def extract_text(self, filepath: str) -> str:
        """Extract text from supported file types"""
        ext = Path(filepath).suffix.lower()
        
        try:
            if ext == '.pdf':
                import pypdf
                reader = pypdf.PdfReader(filepath)
                text = ""
                for page in reader.pages:
                    text += page.extract_text() + "\n"
                return text
                
            elif ext == '.docx':
                import docx
                doc = docx.Document(filepath)
                return "\n".join([para.text for para in doc.paragraphs])
                
            elif ext in ['.txt', '.md', '.csv']:
                with open(filepath, 'r', encoding='utf-8') as f:
                    return f.read()
                    
        except Exception as e:
            logger.error(f"Failed to extract text from {filepath}: {e}")
            return ""
            
        return ""
        
    def chunk_text(self, text: str) -> List[str]:
        """Chunk text into semantic pieces"""
        if not text.strip():
            return []
            
        tokens = self.encoding.encode(text)
        chunks = []
        
        start = 0
        while start < len(tokens):
            end = min(start + CHUNK_SIZE, len(tokens))
            chunk_tokens = tokens[start:end]
            chunk_text = self.encoding.decode(chunk_tokens)
            chunks.append(chunk_text.strip())
            
            if end >= len(tokens):
                break
                
            start = end - CHUNK_OVERLAP
            
        return [c for c in chunks if len(c.split()) > 10]  # Filter very short chunks
        
    def get_embedding(self, text: str) -> List[float]:
        """Get embedding from LiteLLM"""
        try:
            response = requests.post(
                f"{BIFROST_URL}/v1/embeddings",
                headers={
                    "Authorization": f"Bearer {BIFROST_AUTH_TOKEN}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": EMBEDDING_MODEL,
                    "input": text
                },
                timeout=30
            )
            
            if response.status_code == 200:
                return response.json()["data"][0]["embedding"]
            else:
                logger.error(f"Embedding API error: {response.status_code} - {response.text}")
                return []
                
        except Exception as e:
            logger.error(f"Failed to get embedding: {e}")
            return []
            
    def process_file(self, filepath: str):
        """Process a single file"""
        if not Path(filepath).exists():
            return
            
        ext = Path(filepath).suffix.lower()
        if ext not in SUPPORTED_EXTENSIONS:
            return
            
        file_hash = self.get_file_hash(filepath)
        if filepath in self.processed_files and self.processed_files[filepath] == file_hash:
            return  # Already processed
            
        logger.info(f"Processing file: {filepath}")
        
        # Extract text
        text = self.extract_text(filepath)
        if not text.strip():
            logger.warning(f"No text extracted from {filepath}")
            return
            
        # Chunk text
        chunks = self.chunk_text(text)
        if not chunks:
            logger.warning(f"No chunks created from {filepath}")
            return
            
        logger.info(f"Created {len(chunks)} chunks from {filepath}")
        
        # Create points for Qdrant
        points = []
        for i, chunk in enumerate(chunks):
            embedding = self.get_embedding(chunk)
            if not embedding:
                continue
                
            point = PointStruct(
                id=f"{filepath}_{i}_{int(time.time())}",
                vector=embedding,
                payload={
                    "text": chunk,
                    "source_file": filepath,
                    "chunk_index": i,
                    "file_hash": file_hash,
                    "processed_at": time.time()
                }
            )
            points.append(point)
            
        # Batch upsert to Qdrant
        if points:
            try:
                self.qdrant.upsert(
                    collection_name=COLLECTION_NAME,
                    points=points,
                    batch_size=BATCH_SIZE
                )
                logger.info(f"Upserted {len(points)} points to Qdrant")
                
                # Update state
                self.processed_files[filepath] = file_hash
                self.save_state()
                
            except Exception as e:
                logger.error(f"Failed to upsert points: {e}")
                
    def scan_existing_files(self):
        """Scan existing files in sync directory"""
        if not os.path.exists(SYNC_DIR):
            logger.warning(f"Sync directory not found: {SYNC_DIR}")
            return
            
        logger.info(f"Scanning existing files in {SYNC_DIR}")
        
        for root, dirs, files in os.walk(SYNC_DIR):
            for file in files:
                filepath = os.path.join(root, file)
                self.process_file(filepath)
                
    def start_watching(self):
        """Start file system watcher"""
        if not os.path.exists(SYNC_DIR):
            logger.warning(f"Sync directory not found: {SYNC_DIR}")
            return
            
        event_handler = IngestionHandler(self)
        observer = watchdog.observers.Observer()
        observer.schedule(event_handler, SYNC_DIR, recursive=True)
        observer.start()
        
        logger.info(f"Started watching {SYNC_DIR} for changes")
        
        try:
            while True:
                time.sleep(WATCH_INTERVAL)
        except KeyboardInterrupt:
            observer.stop()
        observer.join()

def main():
    """Main entry point"""
    logger.info("Starting GDrive → Qdrant ingestion pipeline")
    
    ingestor = GDriveIngestor()
    
    # Process existing files first
    ingestor.scan_existing_files()
    
    # Start watching for changes
    ingestor.start_watching()

if __name__ == "__main__":
    main()
INGEST_EOF

# Set permissions
RUN chmod +x /app/ingest.py

# Environment variables will be passed from docker-compose.yml
CMD ["python", "ingest.py"]
EOF
        
        # Add ingestion service to docker-compose.yml
        cat >> "$COMPOSE_FILE" <<EOF
  gdrive-ingestion:
    build:
      context: ${CONFIG_DIR}/ingestion
      dockerfile: Dockerfile
    depends_on:
      qdrant:
        condition: service_healthy
      rclone:
        condition: service_started
    volumes:
      - gdrive_data:/data/gdrive-sync:ro
      - ingestion_state:/data/ingestion-state
    environment:
      QDRANT_URL: "http://qdrant:6333"
      LLM_GATEWAY_URL: "${LLM_GATEWAY_URL}"
      BIFROST_AUTH_TOKEN: "${LLM_MASTER_KEY}"
      EMBEDDING_MODEL: "text-embedding-3-small"
      COLLECTION_NAME: "gdrive_documents"
      SYNC_DIR: "/data/gdrive-sync"
      WATCH_INTERVAL: "300"
    restart: unless-stopped
    profiles:
      - ingestion
EOF
    }

    [[ "${ENABLE_MONITORING:-false}" == "true" ]] && cat >> "$COMPOSE_FILE" <<EOF
  prometheus:
    image: prom/prometheus:latest
    restart: unless-stopped
    user: "65534:65534"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
    volumes:
      - ${CONFIG_DIR}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    healthcheck:
      test: ["CMD-SHELL","curl -sf http://localhost:9090/-/healthy || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  grafana:
    image: grafana/grafana:latest
    restart: unless-stopped
    user: "472:472"
    ports:
      - "\${PORT_GRAFANA:-3002}:3000"
    environment:
      GF_SECURITY_ADMIN_USER: \${GRAFANA_ADMIN_USER:-admin}
      GF_SECURITY_ADMIN_PASSWORD: \${GRAFANA_ADMIN_PASSWORD}
      GF_SERVER_ROOT_URL: "https://grafana.\${DOMAIN}"
      GF_ANALYTICS_REPORTING_ENABLED: "false"
    volumes:
      - ${DATA_DIR}/grafana/data:/var/lib/grafana
      - ${DATA_DIR}/grafana/logs:/var/log/grafana
    healthcheck:
      test: ["CMD-SHELL","curl -sf http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 45s
EOF

    [[ "${ENABLE_N8N:-false}" == "true" ]] && cat >> "$COMPOSE_FILE" <<EOF
  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    user: "1000:\${TENANT_GID:-1001}"
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      N8N_AI_OPENAI_API_KEY: "\${LLM_MASTER_KEY}"
      N8N_AI_OPENAI_BASE_URL: "${LLM_GATEWAY_API_URL}"
      DB_TYPE: "postgresdb"
      DB_POSTGRESDB_HOST: "postgres"
      DB_POSTGRESDB_PORT: "5432"
      DB_POSTGRESDB_DATABASE: "n8n"
      DB_POSTGRESDB_USER: "\${POSTGRES_USER}"
      DB_POSTGRESDB_PASSWORD: "\${POSTGRES_PASSWORD}"
      N8N_ENCRYPTION_KEY: "\${ENCRYPTION_KEY}"
      WEBHOOK_URL: "https://n8n.\${DOMAIN}"
    volumes:
      - ${DATA_DIR}/n8n:/home/node/.n8n
    ports:
      - "\${PORT_N8N:-5678}:5678"
    healthcheck:
      test: ["CMD-SHELL","curl -sf http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF

    [[ "${ENABLE_FLOWISE:-false}" == "true" ]] && cat >> "$COMPOSE_FILE" <<EOF
  flowise:
    image: flowiseai/flowise:latest
    restart: unless-stopped
    user: "1000:\${TENANT_GID:-1001}"
    environment:
      OPENAI_API_KEY: "\${LLM_MASTER_KEY}"
      OPENAI_API_BASE: "${LLM_GATEWAY_API_URL}"
      DATABASE_PATH: "/root/.flowise"
      FLOWISE_USERNAME: "admin"
      FLOWISE_PASSWORD: "\${ADMIN_PASSWORD}"
      SECRETKEY_PATH: "/root/.flowise"
    volumes:
      - ${DATA_DIR}/flowise:/root/.flowise
    ports:
      - "\${PORT_FLOWISE:-3001}:3000"
    healthcheck:
      test: ["CMD-SHELL","curl -sf http://localhost:3000/api/v1/ping || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF

    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && cat >> "$COMPOSE_FILE" <<EOF
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    restart: unless-stopped
    user: "1000:\${TENANT_GID:-1001}"
    environment:
      LLM_PROVIDER: "openai"
      OPEN_AI_KEY: "\${LLM_MASTER_KEY}"
      OPEN_AI_BASE_PATH: "${LLM_GATEWAY_API_URL}"
      EMBEDDING_ENGINE: "openai"
      EMBEDDING_BASE_PATH: "${LLM_GATEWAY_API_URL}"
      VECTOR_DB: "\${VECTOR_DB_TYPE:-qdrant}"
      QDRANT_ENDPOINT: "http://qdrant:6333"
      STORAGE_DIR: "/app/server/storage"
    volumes:
      - ${DATA_DIR}/anythingllm:/app/server/storage
    ports:
      - "\${PORT_ANYTHINGLLM:-3003}:3001"
    healthcheck:
      test: ["CMD-SHELL","curl -sf http://localhost:3001/api/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF

    # Tailscale VPN
    [[ "${ENABLE_TAILSCALE:-false}" == "true" ]] && cat >> "$COMPOSE_FILE" <<EOF
  tailscale:
    image: tailscale/tailscale:latest
    restart: unless-stopped
    # Removed user: directive - Tailscale needs root for /dev/net/tun access
    volumes:
      - ${DATA_DIR}/tailscale:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      TS_AUTHKEY: \${TAILSCALE_AUTH_KEY}
      TS_EXTRA_ARGS: "--hostname=\${TENANT:-platform}"
    healthcheck:
      test: ["CMD-SHELL","tailscale --socket=\"/tmp/tailscaled.sock\" status | grep -q '@'"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF

    # OpenClaw web terminal — Tailscale-gated access
    [[ "${ENABLE_OPENCLAW:-false}" == "true" ]] && cat >> "$COMPOSE_FILE" <<EOF
  openclaw:
    image: lscr.io/linuxserver/code-server:latest
    restart: unless-stopped
    user: "1000:\${TENANT_GID:-1001}"
    environment:
      PUID: "1000"
      PGID: "\${TENANT_GID:-1001}"
      PASSWORD: "\${ADMIN_PASSWORD}"
      SUDO_PASSWORD: "\${ADMIN_PASSWORD}"
      DEFAULT_WORKSPACE: "/mnt/data"
    volumes:
      - ${DATA_DIR}/openclaw:/config
      - /mnt/data:/mnt/data:ro
    ports:
      - "\${PORT_OPENCLAW:-18789}:8443"
    healthcheck:
      test: ["CMD-SHELL","curl -sf http://localhost:8443/ || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF

    # Code Server - VS Code in browser with Continue.dev extension
    [[ "${ENABLE_CODESERVER:-false}" == "true" ]] && cat >> "$COMPOSE_FILE" <<EOF
  codeserver:
    image: lscr.io/linuxserver/code-server:latest
    restart: unless-stopped
    user: "1000:\${TENANT_GID:-1001}"
    environment:
      PUID: "1000"
      PGID: "\${TENANT_GID:-1001}"
      PASSWORD: "\${CODESERVER_PASSWORD}"
      SUDO_PASSWORD: "\${CODESERVER_PASSWORD}"
      DEFAULT_WORKSPACE: "/mnt/data"
      BIFROST_API_KEY: "\${LLM_MASTER_KEY}"
      BIFROST_BASE_URL: "${LLM_GATEWAY_API_URL}"
      # Continue.dev extension configuration
      EXTENSIONS_GALLERY: "https://open-vsx.org/vsx-extension-gallery"
      EXTENSIONS: "continuedev.continue"
      # Git repository access
      GIT_REPO: "\${GIT_REPO:-/mnt/data/git}"
    volumes:
      - ${DATA_DIR}/codeserver:/config
      - ${DATA_DIR}/codeserver/.continue:/home/abc/.continue:rw
      - /mnt/data:/mnt/data:rw
      - ${DATA_DIR}/git:/mnt/data/git:rw
      - ${TENANT_DIR}/\${GITHUB_PROJECT:-github}:/config/workspace
    ports:
      - "\${PORT_CODESERVER:-8443}:8443"
    healthcheck:
      test: ["CMD-SHELL","curl -sf http://localhost:8443/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF

    # Continue.dev - AI-powered development assistant (runs inside Code Server)
    # Note: This is configured as an extension, not a separate service

    log_success "docker-compose.yml generated at ${COMPOSE_FILE}"
}

# ── Service Lifecycle Functions ───────────────────────────────────────────────
deploy_service() {
    local svc="$1"
    local logfile="${LOGS_DIR}/deploy-$(date +%Y%m%d).log"
    local timeout="${SERVICE_STARTUP_TIMEOUTS[$svc]:-120}"
    
    log_info "Deploying ${svc}..."
    
    # Check dependencies before deployment
    case "$svc" in
        "bifrost"|"ai-datasquiz-bifrost")
            # Core AI Gateway - depends on infrastructure
            wait_for_healthy postgres 60 || { log_error "Postgres not ready - cannot deploy ${svc}"; return 1; }
            wait_for_healthy redis 30 || { log_error "Redis not ready - cannot deploy ${svc}"; return 1; }
            ;;
        "open-webui"|"anythingllm"|"flowise"|"n8n")
            # AI Applications - depend on Bifrost + Qdrant
            wait_for_healthy ai-datasquiz-bifrost 60 || { log_error "Bifrost not ready - cannot deploy ${svc}"; return 1; }
            if [[ "${ENABLE_QDRANT:-false}" == "true" ]]; then
                wait_for_healthy qdrant 30 || { log_error "Qdrant not ready - cannot deploy ${svc}"; return 1; }
            fi
            ;;
        "caddy"|"nginx")
            # Proxy - depends on all application services being ready
            for app_service in ai-datasquiz-bifrost open-webui anythingllm flowise n8n ollama qdrant; do
                local enable_var="ENABLE_$(echo "$app_service" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
                if [[ "${!enable_var:-false}" == "true" ]]; then
                    wait_for_healthy "$app_service" 30 || { 
                        log_error "${app_service} not ready - cannot deploy ${svc}"; 
                        return 1; 
                    }
                fi
            done
            ;;
    esac
    
    if docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d "$svc" \
            >> "$logfile" 2>&1; then
        log_success "${svc} deployed"
        
        # Post-deployment health verification
        if [[ "${ENABLE_HEALTH_CHECKS:-true}" == "true" ]]; then
            wait_for_healthy "$svc" "$timeout" || {
                log_warning "${svc} deployment completed but health check failed"
                return 1
            }
        fi
    else
        log_error "${svc} failed — last 20 lines from ${logfile}:"
        tail -20 "$logfile" | sed 's/^/  │ /' || true
        return 1   # fatal: dependency failed
    fi
}

stop_service() {
    local svc="$1"
    docker compose -f "$COMPOSE_FILE" stop "$svc" \
        && log_success "${svc} stopped" \
        || log_warning "${svc} was not running"
}

wait_for_healthy() {
    local svc="$1"
    local max_wait="${2:-120}"
    local elapsed=0
    log_info "Waiting for ${svc} to be healthy (max ${max_wait}s)..."
    until [[ "$(docker compose -f "$COMPOSE_FILE" ps --format "{{.Health}}" "$svc" 2>/dev/null)" == "healthy" ]]; do
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

reconfigure_service() {
    local svc="$1"
    log_info "Reconfiguring ${svc}..."
    generate_configs
    generate_compose
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
        up -d --force-recreate "$svc" \
        >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1
    log_success "${svc} reconfigured"
}

enable_service() {
    local svc="$1"
    local flag="ENABLE_$(echo "$svc" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
    log_info "Enabling ${svc} (sets ${flag}=true in .env)..."
    grep -q "^${flag}=" "$ENV_FILE" \
        && sed -i "s|^${flag}=.*|${flag}=true|" "$ENV_FILE" \
        || echo "${flag}=true" >> "$ENV_FILE"
    generate_configs
    generate_compose
    deploy_service "$svc"
    log_success "${svc} enabled and deployed"
}

disable_service() {
    local svc="$1"
    local flag="ENABLE_$(echo "$svc" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
    log_info "Disabling ${svc}..."
    stop_service "$svc"
    grep -q "^${flag}=" "$ENV_FILE" \
        && sed -i "s|^${flag}=.*|${flag}=false|" "$ENV_FILE" \
        || echo "${flag}=false" >> "$ENV_FILE"
    log_success "${svc} stopped and disabled"
}

# ── Service Detection ─────────────────────────────────────────────────────────────
service_is_enabled() {
    local svc="$1"
    case "$svc" in
        bifrost)   [[ "${ENABLE_BIFROST:-false}"   == "true" ]] ;;
        ollama)    [[ "${ENABLE_OLLAMA:-false}"    == "true" ]] ;;
        open-webui)[[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] ;;
        qdrant)    [[ "${ENABLE_QDRANT:-false}"    == "true" ]] ;;
        n8n)       [[ "${ENABLE_N8N:-false}"       == "true" ]] ;;
        flowise)   [[ "${ENABLE_FLOWISE:-false}"   == "true" ]] ;;
        anythingllm)[[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] ;;
        codeserver) [[ "${ENABLE_CODESERVER:-false}" == "true" ]] ;;
        openclaw)  [[ "${ENABLE_OPENCLAW:-false}"  == "true" ]] ;;
        prometheus|grafana) [[ "${ENABLE_MONITORING:-false}" == "true" ]] ;;
        *) return 1 ;;
    esac
}

provision_databases() {
    log_info "Provisioning per-service databases..."
    
    local max_wait=60
    local elapsed=0
    
    # Wait for postgres to accept connections
    until docker compose -f "$COMPOSE_FILE" exec postgres \
        pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -q 2>/dev/null; do
        elapsed=$((elapsed + 5))
        if [[ $elapsed -ge $max_wait ]]; then
            log_error "PostgreSQL not ready after ${max_wait}s"
            return 1
        fi
        log_info "Waiting for postgres... (${elapsed}s)"
        sleep 5
    done
    
    log_success "PostgreSQL is ready"
    
    # Create per-service databases (idempotent — safe to re-run)
    local databases=("bifrost" "openwebui" "n8n" "flowise")
    for db in "${databases[@]}"; do
        local exists
        exists=$(docker compose -f "$COMPOSE_FILE" exec postgres \
            psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -tAc \
            "SELECT 1 FROM pg_database WHERE datname='${db}'" 2>/dev/null || echo "")
        
        if [[ "$exists" == "1" ]]; then
            log_info "Database '${db}' already exists — skipping"
        else
            log_info "Creating database '${db}'..."
            docker compose -f "$COMPOSE_FILE" exec postgres \
                psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
                -c "CREATE DATABASE \"${db}\" OWNER \"${POSTGRES_USER}\";" \
                >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1 \
                && log_success "Database '${db}' created" \
                || log_warning "Could not create '${db}' — may already exist"
        fi
    done
    
    log_success "Database provisioning complete"
}

# ─── Database Cleanup (Mission Control Pattern) ────────────────────────
drop_service_databases() {
    log_info "Dropping service databases for clean slate..."
    local logfile="${LOGS_DIR}/deploy-$(date +%Y%m%d).log"

    # Wait for postgres (may be called right after container start)
    local elapsed=0
    until docker compose -f "$COMPOSE_FILE" exec -T postgres \
        pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -q 2>/dev/null; do
        elapsed=$((elapsed + 5))
        [[ $elapsed -ge 30 ]] && { log_warning "Postgres not ready — skipping DB drop"; return 0; }
        sleep 5
    done

    local databases=("bifrost" "openwebui" "n8n" "flowise")
    for db in "${databases[@]}"; do
        log_info "  Dropping database '${db}'..."
        docker compose -f "$COMPOSE_FILE" exec -T postgres \
            psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
            -c "DROP DATABASE IF EXISTS \"${db}\";" \
            >> "$logfile" 2>&1 \
            && log_success "  '${db}' dropped" \
            || log_warning "  Could not drop '${db}'"
    done

    # Also flush all LiteLLM Redis keys to remove cached router state
    log_info "  Flushing LiteLLM Redis cache keys..."
    docker compose -f "$COMPOSE_FILE" exec -T redis \
        redis-cli -a "${REDIS_PASSWORD}" --no-auth-warning FLUSHALL \
        >> "$logfile" 2>&1 \
        && log_success "  Redis cache flushed" \
        || log_warning "  Could not flush Redis — may not be running"

    log_success "Service databases dropped and Redis flushed"
}

# ─── Log Management ────────────────────────────────────────────────────
log_enable() {
    
    # Kill by PID file if exists
    local pidfile="${LOGS_DIR}/.${svc}.pid"
    if [[ -f "$pidfile" ]]; then
        local pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            log_success "Log stream stopped for ${svc} (PID $pid)"
        fi
        rm -f "$pidfile"
    fi
    
    # Fallback: kill by process name
    pkill -f "docker compose.*logs.*${svc}" 2>/dev/null || true
    
    log_success "Log streaming disabled for ${svc}"
}

log_rotate() {
    local svc="${1:-}"
    local keep_days="${2:-7}"
    
    if [[ -n "$svc" ]]; then
        log_info "Rotating logs for ${svc} (keep ${keep_days} days)..."
        find "$LOGS_DIR" -name "${svc}-*.log" -mtime +${keep_days} -delete
    else
        log_info "Rotating all service logs (keep ${keep_days} days)..."
        find "$LOGS_DIR" -name "*-*.log" -mtime +${keep_days} -delete
    fi
    
    log_success "Log rotation completed"
}

log_cleanup() {
    local keep_days="${1:-30}"
    log_info "Cleaning up old logs (keep ${keep_days} days)..."
    
    # Clean old log files
    find "$LOGS_DIR" -name "*.log" -mtime +${keep_days} -delete
    find "$LOGS_DIR" -name "*.log.*" -mtime +${keep_days} -delete
    
    # Clean old PID files
    find "$LOGS_DIR" -name ".*.pid" -mtime +1 -delete
    
    log_success "Log cleanup completed"
}

# ── Health Dashboard Functions ───────────────────────────────────────────────
_check_http() {
    local name="$1" url="$2"
    if curl -sf --max-time 5 "$url" > /dev/null 2>&1; then
        printf "  ${GREEN}🟢 %-22s${NC} %s\n" "$name" "$url"
    else
        printf "  ${RED}🔴 %-22s${NC} %s\n" "$name" "$url"
    fi
}

_check_https() {
    local name="$1" url="$2"
    if curl -sfk --max-time 5 "$url" > /dev/null 2>&1; then
        printf "  ${GREEN}🟢 %-22s${NC} %s\n" "$name" "$url"
    else
        printf "  ${RED}🔴 %-22s${NC} %s\n" "$name" "$url"
    fi
}

_check_cmd() {
    local name="$1"; shift
    if "$@" > /dev/null 2>&1; then
        printf "  ${GREEN}🟢 %-22s${NC} %s\n" "$name" "$(docker compose -f "$COMPOSE_FILE" ps --format "{{.Status}}" "$name" 2>/dev/null | head -1)"
    else
        printf "  ${RED}🔴 %-22s${NC} %s\n" "$name" "not responding"
    fi
}

health_dashboard() {
    set -a; source "$ENV_FILE"; set +a
    local ts ip=""
    ts=$(date '+%Y-%m-%d %H:%M:%S')

    # Tailscale IP - use reliable tailscale ip -4 method
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "tailscale"; then
        ip=$(docker compose -f "$COMPOSE_FILE" exec -T tailscale \
            tailscale --socket="/tmp/tailscaled.sock" ip -4 2>/dev/null \
            | tr -d ' \n' || true)
        # Fallback: read from .env if already stored
        [[ -z "$ip" ]] && ip=$(grep "^TAILSCALE_IP=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 || true)
    else
        ip="NOT CONNECTED"
    fi

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  AI PLATFORM HEALTH DASHBOARD — ${ts}    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    printf "  %-14s %s\n" "Domain:"       "https://${DOMAIN}"
    printf "  %-14s %s\n" "Tailscale IP:" "${ip:-NOT CONNECTED}"
    if [[ "${ENABLE_OPENCLAW:-false}" == "true" && -n "$ip" ]]; then
        printf "  %-14s %s\n" "OpenClaw:" "https://${ip}:${PORT_OPENCLAW:-18789} (Tailscale only)"
    fi
    printf "  %-14s %s\n" "Tenant:"       "${TENANT}"
    printf "  %-14s %s\n" "Data:"         "${TENANT_DIR}"
    echo ""
    echo -e "  ${BOLD}Infrastructure${NC}"
    _check_cmd  "postgres"   docker compose -f "$COMPOSE_FILE" exec -T postgres \
                             pg_isready -U "${POSTGRES_USER}" -q
    _check_cmd  "redis"      docker compose -f "$COMPOSE_FILE" exec -T redis \
                             redis-cli -a "${REDIS_PASSWORD}" ping
    [[ "${ENABLE_QDRANT:-false}"    == "true" ]] && \
        _check_http "qdrant"     "http://localhost:${PORT_QDRANT:-6333}/collections"
    echo ""
    echo -e "  ${BOLD}Monitoring${NC}"
    [[ "${ENABLE_MONITORING:-false}" == "true" ]] && {
        _check_http "prometheus" "http://localhost:${PORT_PROMETHEUS:-9090}/-/healthy"
        _check_http "grafana"    "http://localhost:${PORT_GRAFANA:-3002}/api/health"
    }
    _check_http "caddy"      "http://localhost:2019/metrics"
    echo ""
    echo -e "  ${BOLD}AI Services${NC}"
    [[ "${ENABLE_BIFROST:-false}"    == "true" ]] && \
        _check_http "bifrost"    "http://localhost:${BIFROST_PORT:-4000}/healthz"
    [[ "${ENABLE_OLLAMA:-false}"     == "true" ]] && \
        _check_http "ollama"     "http://localhost:11434/"
    echo ""
    echo -e "  ${BOLD}Development Environment${NC}"
    [[ "${ENABLE_CODESERVER:-false}" == "true" ]] && \
        _check_http "codeserver"     "http://localhost:${PORT_CODESERVER:-8443}/"
    echo ""
    echo -e "  ${BOLD}Web Services (all routed via ${LLM_ROUTER:-LiteLLM})${NC}"
    [[ "${ENABLE_OPENWEBUI:-false}"  == "true" ]] && \
        _check_http "open-webui"     "http://localhost:${PORT_OPENWEBUI:-3000}/"
    [[ "${ENABLE_N8N:-false}"        == "true" ]] && \
        _check_http "n8n"            "http://localhost:${PORT_N8N:-5678}/healthz"
    [[ "${ENABLE_FLOWISE:-false}"    == "true" ]] && \
        _check_http "flowise"        "http://localhost:${PORT_FLOWISE:-3001}/"
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && \
        _check_http "anythingllm"    "http://localhost:${PORT_ANYTHINGLLM:-3003}/"
    [[ "${ENABLE_OPENCLAW:-false}"  == "true" ]] && \
        _check_https "openclaw"      "https://openclaw.${DOMAIN}/"
    echo ""
    echo -e "  ${BOLD}Quick Tests${NC}"
    echo -e "  Bifrost models:"
    echo -e "    curl -s http://localhost:${BIFROST_PORT:-4000}/v1/models \\"
    echo -e "      -H 'Authorization: Bearer \${LLM_MASTER_KEY}' | jq '.data[].id'"
    echo ""
    echo -e "  ${BOLD}🌐 Access URLs${NC}"
    printf "  %-26s %s\n" "Chat (OpenWebUI):"     "https://chat.${DOMAIN}"
    [[ "${ENABLE_BIFROST:-false}"    == "true" ]] && printf "  %-26s %s\n" "Bifrost API:"        "https://bifrost.${DOMAIN}"
    [[ "${ENABLE_N8N:-false}"        == "true" ]] && printf "  %-26s %s\n" "n8n Automation:"     "https://n8n.${DOMAIN}"
    [[ "${ENABLE_FLOWISE:-false}"    == "true" ]] && printf "  %-26s %s\n" "Flowise:"            "https://flowise.${DOMAIN}"
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && printf "  %-26s %s\n" "AnythingLLM:"       "https://anythingllm.${DOMAIN}"
    [[ "${ENABLE_CODESERVER:-false}" == "true" ]] && printf "  %-26s %s\n" "OpenCode IDE:"       "https://opencode.${DOMAIN}"
    [[ "${ENABLE_MONITORING:-false}" == "true" ]] && {
        printf "  %-26s %s\n" "Grafana:"           "https://grafana.${DOMAIN}"
        printf "  %-26s %s\n" "Prometheus:"        "https://prometheus.${DOMAIN}"
    }
    [[ "${ENABLE_OPENCLAW:-false}"  == "true" ]] && \
        printf "  %-26s %s\n" "OpenClaw (Tailscale):" "https://${ip:-<tailscale-ip>}:${PORT_OPENCLAW:-18789}"
    echo ""
    echo -e "  ${BOLD}⚡ Bifrost Quick Test${NC}"
    echo -e "    curl -s https://bifrost.${DOMAIN}/healthz \\"
    echo -e "      -H 'Authorization: Bearer \${LLM_MASTER_KEY}' | jq '.status'"
    echo ""
    log_write INFO "Health dashboard printed at ${ts}"
}

# ── External Integration Functions ───────────────────────────────────────────
configure_tailscale() {
    [[ -n "${TAILSCALE_AUTH_KEY:-}" ]] || { 
        log_info "TAILSCALE_AUTH_KEY not set — skipping"; 
        return 0; 
    }
    
    # Check if tailscale service exists in compose
    if ! docker compose -f "$COMPOSE_FILE" config | grep -q "tailscale:"; then
        log_warning "Tailscale service not found in compose configuration"
        return 1
    fi
    
    log_info "Configuring Tailscale..."
    
    # Deploy tailscale if not running
    if ! docker ps --format '{{.Names}}' | grep -q tailscale; then
        deploy_service tailscale
        sleep 10  # Give tailscale time to start
    fi
    
    # Authenticate (only if not already authenticated)
    if ! docker compose -f "$COMPOSE_FILE" exec -T tailscale \
        tailscale --socket="/tmp/tailscaled.sock" status | grep -q "Logged in as"; then
        docker compose -f "$COMPOSE_FILE" exec -T tailscale \
            tailscale --socket="/tmp/tailscaled.sock" up --authkey="${TAILSCALE_AUTH_KEY}" --hostname="${TENANT:-platform}" --accept-dns=false || {
            log_error "Tailscale authentication failed"
            return 1
        }
    fi
    
    sleep 5
    local ip
    ip=$(docker compose -f "$COMPOSE_FILE" exec -T tailscale \
        tailscale --socket="/tmp/tailscaled.sock" ip -4 2>/dev/null | tr -d ' \n' || true)
    
    if [[ -n "$ip" ]]; then
        # Update .env with Tailscale IP
        grep -q "^TAILSCALE_IP=" "$ENV_FILE" \
            && sed -i "s|^TAILSCALE_IP=.*|TAILSCALE_IP=${ip}|" "$ENV_FILE" \
            || echo "TAILSCALE_IP=${ip}" >> "$ENV_FILE"
        log_success "Tailscale configured with IP: ${ip}"
    else
        log_warning "Could not get Tailscale IP"
    fi
}

configure_mem0() {
    log "INFO" "Verifying Mem0 memory layer..."
    local mem0_url="http://localhost:${MEM0_PORT}"
    local waited=0

    # Wait for Mem0 to be ready (pip install takes time on first boot)
    while ! curl -sf "${mem0_url}/health" > /dev/null 2>&1; do
        if [[ ${waited} -ge 180 ]]; then
            log "ERROR" "Mem0 failed to become healthy after 180s"
            return 1
        fi
        log "INFO" "Waiting for Mem0... (${waited}s)"
        sleep 10
        waited=$((waited + 10))
    done
    log "SUCCESS" "Mem0 is healthy"

    # Verify tenant isolation — write to tenant A, search from tenant B
    local tenant_a="${MEM0_COLLECTION_PREFIX}_test_a"
    local tenant_b="${MEM0_COLLECTION_PREFIX}_test_b"

    curl -sf -X POST "${mem0_url}/v1/memories" \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"messages\":[{\"role\":\"user\",\"content\":\"isolation_marker_xyz\"}],
             \"user_id\":\"${tenant_a}\"}" > /dev/null \
        || { log "ERROR" "Mem0 write failed"; return 1; }

    local result
    result="$(curl -sf -X POST "${mem0_url}/v1/memories/search" \
        -H "Authorization: Bearer ${MEM0_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"query\":\"isolation_marker_xyz\",
             \"user_id\":\"${tenant_b}\"}")"

    if echo "${result}" | grep -q "isolation_marker_xyz"; then
        log "ERROR" "CRITICAL: Tenant memory isolation FAILED"
        return 1
    fi

    log "SUCCESS" "Mem0 tenant isolation verified"
}

setup_gdrive_rclone() {
    [[ -n "${GDRIVE_CLIENT_ID:-}" ]] || { 
        log_info "GDrive not configured — skipping"; 
        return 0; 
    }
    
    log_info "Configuring rclone GDrive remote..."
    
    # Check if rclone is installed
    if ! command -v rclone &> /dev/null; then
        log_info "Installing rclone..."
        curl -fsSL https://rclone.org/install.sh | bash
    fi
    
    # Configure GDrive remote
    rclone config create gdrive drive \
        client_id="${GDRIVE_CLIENT_ID}" \
        client_secret="${GDRIVE_CLIENT_SECRET}" \
        token="{\"access_token\":\"\",\"token_type\":\"Bearer\",\"refresh_token\":\"${GDRIVE_REFRESH_TOKEN}\",\"expiry\":\"\"}" || {
        log_error "Failed to configure rclone GDrive remote"
        return 1
    }
    
    log_success "rclone GDrive configured"
}

create_ingestion_systemd() {
    [[ -n "${GDRIVE_CLIENT_ID:-}" ]] || return 0

    log_info "Installing gdrive-sync systemd timer..."

    local gdrive_dir="${DATA_DIR}/gdrive"
    mkdir -p "$gdrive_dir"
    chown "${TENANT_UID:-1001}:${TENANT_GID:-1001}" "$gdrive_dir"

    # Create systemd service — syncs then optionally triggers ingestion
    cat > /etc/systemd/system/gdrive-sync-${TENANT}.service <<EOF
[Unit]
Description=AI Platform GDrive sync for ${TENANT}
After=docker.service network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'rclone sync gdrive: ${DATA_DIR}/gdrive/ --log-file ${LOGS_DIR}/rclone-sync.log'
User=root
EOF

    # Create systemd timer — runs every 4 minutes
    cat > /etc/systemd/system/gdrive-sync-${TENANT}.timer <<EOF
[Unit]
Description=GDrive Sync Timer for ${TENANT}

[Timer]
OnCalendar=*:0/4
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now gdrive-sync-${TENANT}.timer

    log_success "gdrive-sync-${TENANT} timer installed — syncing to ${DATA_DIR}/gdrive/"
}

# ── Service Recovery ─────────────────────────────────────────────────────
recover_services() {
    log_info "Recovering failed services..."
    
    # Restart Bifrost with configuration validation
    if [[ "${ENABLE_BIFROST:-false}" == "true" ]]; then
        log_info "Restarting Bifrost with configuration validation..."
        docker compose -f "$COMPOSE_FILE" restart bifrost
        sleep 10
    fi
    
    # Restart OpenWebUI with environment validation
    if [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]]; then
        log_info "Restarting OpenWebUI with environment validation..."
        docker compose -f "$COMPOSE_FILE" restart open-webui
        sleep 15
    fi
    
    log_success "Service recovery completed"
}

# ── GDrive → Qdrant Ingestion ─────────────────────────────────────────────────
ingest_gdrive_to_qdrant() {
    [[ -n "${GDRIVE_CLIENT_ID:-}" ]] || {
        log_warning "GDrive not configured — run: $0 gdrive first"
        return 1
    }
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] || {
        log_warning "AnythingLLM not enabled — enable it first: $0 enable anythingllm"
        return 1
    }

    log_info "Starting GDrive → Qdrant ingestion via AnythingLLM..."

    # 1. Sync gdrive to local
    log_info "Syncing GDrive to ${DATA_DIR}/gdrive/ ..."
    mkdir -p "${DATA_DIR}/gdrive"
    rclone sync gdrive: "${DATA_DIR}/gdrive/" \
        --log-file "${LOGS_DIR}/rclone-sync.log" \
        && log_success "GDrive sync complete" \
        || { log_error "GDrive sync failed — check ${LOGS_DIR}/rclone-sync.log"; return 1; }

    # 2. Get AnythingLLM API key from .env
    local atllm_key="${ANYTHINGLLM_API_KEY:-${LITELLM_MASTER_KEY}}"
    local atllm_url="http://localhost:${PORT_ANYTHINGLLM:-3003}"

    # 3. Upload each file to AnythingLLM via its upload API
    log_info "Uploading documents to AnythingLLM for embedding into Qdrant..."
    local count=0 failed=0
    while IFS= read -r -d '' file; do
        local filename
        filename="$(basename "$file")"
        # AnythingLLM accepts file upload via /api/v1/document/upload
        if curl -sf -X POST \
            "${atllm_url}/api/v1/document/upload" \
            -H "Authorization: Bearer ${atllm_key}" \
            -F "file=@${file}" \
            > /dev/null 2>&1; then
            count=$((count + 1))
        else
            log_warning "Failed to upload: ${filename}"
            failed=$((failed + 1))
        fi
    done < <(find "${DATA_DIR}/gdrive" -type f \( \
        -name "*.pdf" -o -name "*.txt" -o -name "*.md" \
        -o -name "*.docx" -o -name "*.csv" \) -print0)

    log_success "GDrive ingestion complete — ${count} files embedded, ${failed} failed"
    log_info "Verify collections: curl -s http://localhost:${PORT_QDRANT:-6333}/collections | jq"
}

# ── CLI Dispatcher (Only runs when script executed directly) ──────────────────
(return 0 2>/dev/null) && return   # sourced - export functions and stop here

main() {
    local tenant="${1:-help}"
    [[ "$tenant" == "help" ]] && {
        echo "Usage: $0 <tenant> <command> [service]"
        echo ""
        echo "Tenants:"
        ls -1 /mnt/data/ 2>/dev/null | sed 's/^/  /' || echo "  (none found)"
        echo ""
        echo "Commands:"
        echo "  Deployment:    deploy <svc>  stop <svc>  restart <svc>  deploy-all  stop-all"
        echo "  Configuration: generate  compose  dirs"
        echo "  Health:        health  status  logs [svc]  logs-on <svc>  logs-off <svc>"
        echo "  Logging:       logs-rotate [svc] [days]  logs-cleanup [days]"
        echo "  Recovery:      recover"
        echo "  Wiring:        tailscale  gdrive  gdrive-ingest"
        echo "  Lifecycle:     enable <svc>  disable <svc>  reconfigure <svc>"
        echo ""
        return 1
    }
    
    # Set TENANT and load environment
    export TENANT="$tenant"
    TENANT_DIR="/mnt/data/${TENANT}"
    CONFIG_DIR="${TENANT_DIR}/configs"
    DATA_DIR="${TENANT_DIR}/data"
    LOGS_DIR="${TENANT_DIR}/logs"
    COMPOSE_FILE="${TENANT_DIR}/docker-compose.yml"
    ENV_FILE="${TENANT_DIR}/.env"
    
    # Load environment variables
    [[ -f "$ENV_FILE" ]] || {
        echo "ERROR: Environment file not found: $ENV_FILE"
        echo "Run script 1 first to create it"
        return 1
    }
    set -a
    source "$ENV_FILE"
    set +a
    
    local cmd="${2:-help}"
    shift 2 || true
    case "$cmd" in
        # ── Deployment ──────────────────────────────────────────────
        deploy)         deploy_service "${1:?usage: deploy <service>}" ;;
        deploy-all)     bash "$(dirname "$0")/2-deploy-services.sh" ;;
        stop)           stop_service   "${1:?usage: stop <service>}" ;;
        stop-all)       docker compose -f "$COMPOSE_FILE" down ;;
        restart)        reconfigure_service "${1:?usage: restart <service>}" ;;

        # ── Configuration ────────────────────────────────────────────
        generate)       generate_configs ;;
        compose)        generate_compose ;;
        dirs)           prepare_directories ;;
        env)            echo "Re-run script 1 to regenerate .env safely" ;;

        # ── Health & Monitoring ──────────────────────────────────────
        health)         health_dashboard ;;
        status)         
            if [[ "${LLM_ROUTER:-bifrost}" == "bifrost" ]]; then
                echo "LLM Router: Bifrost (port ${BIFROST_PORT:-4000})"
                curl -s "http://localhost:${BIFROST_PORT:-4000}/healthz" | jq .
            else
                echo "LLM Router: LiteLLM (port 4000)"
                curl -s "http://localhost:4000/healthz" | jq .
            fi
            docker compose -f "$COMPOSE_FILE" ps ;;
        logs)           docker compose -f "$COMPOSE_FILE" logs --tail=50 "${1:-}" ;;
        logs-on)        log_enable  "${1:?usage: logs-on <service>}" ;;
        logs-off)       log_disable "${1:?usage: logs-off <service>}" ;;

        # ── External Wiring ──────────────────────────────────────────
        tailscale)      configure_tailscale ;;
        mem0)           configure_mem0 ;;
        gdrive)         setup_gdrive_rclone && create_ingestion_systemd ;;
        gdrive-ingest)  ingest_gdrive_to_qdrant ;;
        logs-rotate)    log_rotate "${1:-}" "${2:-7}" ;;
        logs-cleanup)   log_cleanup "${1:-30}" ;;

        # ── Service Recovery ───────────────────────────────────────
        recover)        recover_services ;;

        # ── Service Reconfiguration ──────────────────────────────────
        reconfigure)    reconfigure_service "${1:?usage: reconfigure <service>}" ;;
        enable)         enable_service  "${1:?usage: enable <service>}" ;;
        disable)        disable_service "${1:?usage: disable <service>}" ;;
        update)         update_service  "${1:?usage: update <service>}" ;;
        upgrade)        upgrade_service "${1:?usage: upgrade <service>}" ;;

        # ── Help ─────────────────────────────────────────────────────
        help|*)
            echo ""
            echo "Usage: $0 <command> [service]"
            echo ""
            echo "  Deployment:    deploy <svc>  stop <svc>  restart <svc>  deploy-all  stop-all"
            echo "  Configuration: generate  compose  dirs"
            echo "  Health:        health  status  logs [svc]  logs-on <svc>  logs-off <svc>"
            echo "  Logging:       logs-rotate [svc] [days]  logs-cleanup [days]"
            echo "  Wiring:        tailscale  gdrive  gdrive-ingest"
            echo "  Lifecycle:     enable <svc>  disable <svc>  reconfigure <svc>"
            echo ""
            ;;
    esac
}

# Only run main if executed directly (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
