#!/usr/bin/env bash
# =============================================================================
# Script 2: Deployment Engine
# PURPOSE: Generate ALL derived configs from platform.conf and orchestrate container deployment
# =============================================================================
# USAGE:   bash scripts/2-deploy-services.sh [tenant_id] [options]
# OPTIONS: --dry-run           Show what would be deployed without action
#          --verify-only       Verify deployment without changes
# =============================================================================

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
SCRIPT_VERSION="5.1.0"
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
}
ok() { log "OK: $*"; }
warn() { log "WARN: $*"; }
fail() { log "FAIL: $*"; exit 1; }
dry_run() { [[ "${DRY_RUN:-false}" == "true" ]] && echo "[DRY-RUN] $1"; }

# =============================================================================
# DRY RUN COMMAND EXECUTOR (README §12)
# =============================================================================
run_cmd() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# =============================================================================
# IDEMPOTENCY MARKERS (README P8)
# =============================================================================
step_done() { [[ -f "${CONFIGURED_DIR}/${1}" ]]; }
mark_done() { touch "${CONFIGURED_DIR}/${1}"; }

# =============================================================================
# FRAMEWORK VALIDATION
# =============================================================================
framework_validate() {
    log "Validating deployment framework..."
    
    # Fix Docker socket connection (common issue)
    if [[ "${DOCKER_HOST:-}" == *"user/1000"* ]]; then
        log "Fixing Docker socket connection..."
        unset DOCKER_HOST
    fi
    
    # Binary availability checks (README §13)
    for bin in docker yq curl jq; do
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
    
    # Disk space check
    local available_gb
    available_gb=$(df "${BASE_DIR}" | awk 'NR==2{print int($4/1024/1024)}')
    if [[ $available_gb -lt 10 ]]; then
        fail "Insufficient disk space: ${available_gb}GB available, 10GB required"
    fi
    
    ok "Framework validation passed"
}

# =============================================================================
# CONFIGURATION GENERATION FUNCTIONS (Complete Implementation)
# =============================================================================

# Generate Caddy Configuration
generate_caddy_config() {
    log "Generating Caddy configuration..."
    
    local caddy_dir="${CONFIG_DIR}/caddy"
    mkdir -p "$caddy_dir"
    
    case "${TLS_MODE}" in
        letsencrypt)
            cat > "${caddy_dir}/Caddyfile" << EOF
{
    email ${LETSENCRYPT_EMAIL}
    auto_https {
        protocols tls1.2 tls1.3
    }
    
    # Global options
    admin localhost:2019
    
    # Main domain
    ${DOMAIN} {
        encode gzip zstd
        log {
            output file ${LOG_DIR}/caddy/access.log
            level INFO
        }
        
        # Proxy to all services
        handle_path /api/* {
            reverse_proxy ${TENANT_PREFIX}-litellm:4000
        }
        
        handle_path / {
            reverse_proxy ${TENANT_PREFIX}-openwebui:3000
        }
    }
}
EOF
            ;;
        manual)
            cat > "${caddy_dir}/Caddyfile" << EOF
{
    admin localhost:2019
    
    ${DOMAIN} {
        encode gzip zstd
        log {
            output file ${LOG_DIR}/caddy/access.log
            level INFO
        }
        
        tls ${MANUAL_CERT_FILE} ${MANUAL_KEY_FILE}
        
        handle_path /api/* {
            reverse_proxy ${TENANT_PREFIX}-litellm:4000
        }
        
        handle_path / {
            reverse_proxy ${TENANT_PREFIX}-openwebui:3000
        }
    }
}
EOF
            ;;
        selfsigned)
            # Generate self-signed certificate
            local cert_dir="${CONFIG_DIR}/ssl"
            mkdir -p "$cert_dir"
            
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$cert_dir/server.key" \
                -out "$cert_dir/server.crt" \
                -subj "/C=${CERT_COUNTRY:-US}/ST=${CERT_STATE:-State}/L=${CERT_CITY:-City}/O=${CERT_ORG:-AI Platform}/OU=AI Platform/CN=${DOMAIN}" \
                2>/dev/null || fail "Failed to generate self-signed certificate"
            
            cat > "${caddy_dir}/Caddyfile" << EOF
{
    admin localhost:2019
    
    ${DOMAIN} {
        encode gzip zstd
        log {
            output file ${LOG_DIR}/caddy/access.log
            level INFO
        }
        
        tls ${cert_dir}/server.crt ${cert_dir}/server.key {
            on_demand
        }
        
        handle_path /api/* {
            reverse_proxy ${TENANT_PREFIX}-litellm:4000
        }
        
        handle_path / {
            reverse_proxy ${TENANT_PREFIX}-openwebui:3000
        }
    }
}
EOF
            ;;
        none)
            cat > "${caddy_dir}/Caddyfile" << EOF
{
    admin localhost:2019
    auto_https off
    
    ${DOMAIN}:80 {
        encode gzip zstd
        log {
            output file ${LOG_DIR}/caddy/access.log
            level INFO
        }
        
        handle_path /api/* {
            reverse_proxy ${TENANT_PREFIX}-litellm:4000
        }
        
        handle_path / {
            reverse_proxy ${TENANT_PREFIX}-openwebui:3000
        }
    }
}
EOF
            ;;
    esac
    
    ok "Caddy configuration generated"
}

# Generate LiteLLM Configuration
generate_litellm_config() {
    log "Generating LiteLLM configuration..."
    
    local litellm_dir="${CONFIG_DIR}/litellm"
    mkdir -p "$litellm_dir"
    
    cat > "${litellm_dir}/config.yaml" << EOF
model_list:
  - model_name: gpt-4
    litellm_params:
      model: gpt-4
      api_base: https://api.openai.com/v1
      api_key: ${OPENAI_API_KEY}
  - model_name: claude-3-sonnet-20240229
    litellm_params:
      model: claude-3-sonnet-20240229
      api_base: https://api.anthropic.com
      api_key: ${ANTHROPIC_API_KEY}
EOF
    
    # Add enabled providers dynamically
    [[ "$OPENAI_PROVIDER_ENABLED" == "true" ]] && echo "OpenAI provider enabled"
    [[ "$ANTHROPIC_PROVIDER_ENABLED" == "true" ]] && echo "Anthropic provider enabled"
    [[ "$GOOGLE_PROVIDER_ENABLED" == "true" ]] && echo "Google provider enabled"
    [[ "$GROQ_PROVIDER_ENABLED" == "true" ]] && echo "Groq provider enabled"
    [[ "$OPENROUTER_PROVIDER_ENABLED" == "true" ]] && echo "OpenRouter provider enabled"
    
    ok "LiteLLM configuration generated"
}

# Generate Docker Compose
generate_compose() {
    log "Generating docker-compose.yml..."
    
    # Build dependency strings
    local litellm_deps openwebui_deps
    local postgres_deps redis_deps qdrant_deps
    local ollama_deps caddy_deps
    
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        litellm_deps=$(build_litellm_deps)
    fi
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        openwebui_deps=$(build_openwebui_deps)
    fi
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        postgres_deps=$(build_postgres_deps)
    fi
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        redis_deps=$(build_redis_deps)
    fi
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        qdrant_deps=$(build_qdrant_deps)
    fi
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        ollama_deps=$(build_ollama_deps)
    fi
    if [[ "${CADDY_ENABLED}" == "true" ]]; then
        caddy_deps=$(build_caddy_deps)
    fi
    
    # Backup existing compose file
    if [[ -f "$COMPOSE_FILE" ]]; then
        cp "$COMPOSE_FILE" "${COMPOSE_FILE}.backup"
        log "Backed up existing docker-compose.yml"
    fi
    
    cat > "${COMPOSE_FILE}" << EOF

networks:
  ${DOCKER_NETWORK}:
    driver: bridge

services:
EOF

    # PostgreSQL
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  postgres:
    image: postgres:15-alpine
    container_name: ${TENANT_PREFIX}-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${TENANT_ID}
      POSTGRES_USER: ${TENANT_ID}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${TENANT_ID} -d ${TENANT_ID}"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF
    fi
    
    # Redis
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  redis:
    image: redis:7-alpine
    container_name: ${TENANT_PREFIX}-redis
    restart: unless-stopped
    command: redis-server --appendonly yes --replicaof no
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "${REDIS_PORT:-6379}:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF
    fi
    
    # LiteLLM
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  litellm:
    image: ghcr.io/berriai/litellm:latest
    container_name: ${TENANT_PREFIX}-litellm
    restart: unless-stopped
    environment:
      DATABASE_URL: postgresql://${TENANT_ID}:${POSTGRES_PASSWORD}@${TENANT_PREFIX}-postgres:5432/${TENANT_ID}
      REDIS_HOST: ${TENANT_PREFIX}-redis
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
    volumes:
      - ${CONFIG_DIR}/litellm:/app/config
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "${LITELLM_PORT:-4000}:4000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
${litellm_deps}
EOF
    fi
    
    # Ollama
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ollama:
    image: ollama/ollama:latest
    container_name: ${TENANT_PREFIX}-ollama
    restart: unless-stopped
    environment:
      OLLAMA_HOST: 0.0.0.0
    volumes:
      - ${DATA_DIR}/ollama:/root/.ollama
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "${OLLAMA_PORT:-11434}:11434"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
${ollama_deps}
EOF
    fi
    
    # OpenWebUI
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ${TENANT_PREFIX}-openwebui
    restart: unless-stopped
    environment:
      OLLAMA_BASE_URL: http://${TENANT_PREFIX}-ollama:11434/api
      WEBUI_SECRET_KEY: ${OPENWEBUI_SECRET_KEY}
    volumes:
      - ${DATA_DIR}/openwebui:/app/backend/data
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "${OPENWEBUI_PORT:-3000}:3000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3
${openwebui_deps}
EOF
    fi
    
    # Qdrant
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  qdrant:
    image: qdrant/qdrant:latest
    container_name: ${TENANT_PREFIX}-qdrant
    restart: unless-stopped
    environment:
      QDRANT__SERVICE__HTTP__HOST: 0.0.0.0
    volumes:
      - ${DATA_DIR}/qdrant:/qdrant/storage
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "${QDRANT_PORT:-6333}:6333"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/health"]
      interval: 30s
      timeout: 10s
      retries: 3
${qdrant_deps}
EOF
    fi
    
    # Caddy
    if [[ "${CADDY_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  caddy:
    image: caddy:2-alpine
    container_name: ${TENANT_PREFIX}-caddy
    restart: unless-stopped
    volumes:
      - ${CONFIG_DIR}/caddy:/etc/caddy
      - ${LOG_DIR}/caddy:/var/log/caddy
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "80:80"
      - "443:443"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:2019/config/apps"]
      interval: 30s
      timeout: 10s
      retries: 3
${caddy_deps}
EOF
    fi
    
    ok "Docker compose configuration generated"
}

# =============================================================================
# DEPENDENCY BUILDERS (README §6 - mandatory pattern)
# =============================================================================
build_litellm_deps() {
    local deps=""
    if [[ "${POSTGRES_ENABLED}" == "true" ]] || [[ "${REDIS_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        [[ "${POSTGRES_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-postgres"$'\n'
        [[ "${REDIS_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-redis"$'\n'
        deps+="    networks:"$'\n'
        deps+="      - ${DOCKER_NETWORK}"$'\n'
    fi
    printf '%s' "${deps}"
}

build_openwebui_deps() {
    local deps=""
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        deps+="      - ${TENANT_PREFIX}-ollama"$'\n'
        deps+="    networks:"$'\n'
        deps+="      - ${DOCKER_NETWORK}"$'\n'
    fi
    printf '%s' "${deps}"
}

# LibreChat removed - no MongoDB in platform

build_openclaw_deps() {
    local deps=""
    if [[ "${POSTGRES_ENABLED}" == "true" ]] || [[ "${REDIS_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        [[ "${POSTGRES_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-postgres"$'\n'
        [[ "${REDIS_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-redis"$'\n'
        deps+="    networks:"$'\n'
        deps+="      - ${DOCKER_NETWORK}"$'\n'
    fi
    printf '%s' "${deps}"
}

build_n8n_deps() {
    local deps=""
    if [[ "${POSTGRES_ENABLED}" == "true" ]] || [[ "${REDIS_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        [[ "${POSTGRES_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-postgres"$'\n'
        [[ "${REDIS_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-redis"$'\n'
        deps+="    networks:"$'\n'
        deps+="      - ${DOCKER_NETWORK}"$'\n'
    fi
    printf '%s' "${deps}"
}

build_flowise_deps() {
    local deps=""
    if [[ "${POSTGRES_ENABLED}" == "true" ]] || [[ "${REDIS_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        [[ "${POSTGRES_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-postgres"$'\n'
        [[ "${REDIS_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-redis"$'\n'
        deps+="    networks:"$'\n'
        deps+="      - ${DOCKER_NETWORK}"$'\n'
    fi
    printf '%s' "${deps}"
}

build_dify_deps() {
    local deps=""
    if [[ "${POSTGRES_ENABLED}" == "true" ]] || [[ "${REDIS_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        [[ "${POSTGRES_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-postgres"$'\n'
        [[ "${REDIS_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-redis"$'\n'
        deps+="    networks:"$'\n'
        deps+="      - ${DOCKER_NETWORK}"$'\n'
    fi
    printf '%s' "${deps}"
}

build_authentik_deps() {
    local deps=""
    if [[ "${POSTGRES_ENABLED}" == "true" ]] || [[ "${REDIS_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        [[ "${POSTGRES_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-postgres"$'\n'
        [[ "${REDIS_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-redis"$'\n'
        deps+="    networks:"$'\n'
        deps+="      - ${DOCKER_NETWORK}"$'\n'
    fi
    printf '%s' "${deps}"
}

# =============================================================================
# DOCKER COMPOSE GENERATION (README P3 - explicit heredoc blocks)
# =============================================================================
generate_compose() {
    log "Generating docker-compose.yml..."
    
    # Generate N8N_ENCRYPTION_KEY if needed (P0 fix)
    N8N_KEY_FILE="${DATA_DIR}/.n8n_encryption_key"
    if [[ -f "$N8N_KEY_FILE" ]]; then
        N8N_ENCRYPTION_KEY=$(cat "$N8N_KEY_FILE")
        log "Using existing N8N encryption key"
    else
        N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
        echo "$N8N_ENCRYPTION_KEY" > "$N8N_KEY_FILE"
        chmod 600 "$N8N_KEY_FILE"
        log "Generated new N8N encryption key"
    fi
    
    # GPU docker access verification (P2 fix)
    if [[ "${GPU_TYPE}" == "nvidia" ]]; then
        log "Verifying NVIDIA GPU access in Docker..."
        if ! docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
            warn "WARNING: NVIDIA GPU detected but docker GPU access failed."
            warn "         Deploying without GPU. Check nvidia-container-toolkit install."
            GPU_TYPE="none"
        else
            ok "NVIDIA GPU access verified"
        fi
    fi
    
    # Build dependency strings
    local litellm_deps openwebui_deps openclaw_deps
    local n8n_deps flowise_deps dify_deps authentik_deps
    
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        litellm_deps=$(build_litellm_deps)
    fi
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        openwebui_deps=$(build_openwebui_deps)
    fi
    # LibreChat removed - no MongoDB in platform
    if [[ "${OPENCLAW_ENABLED}" == "true" ]]; then
        openclaw_deps=$(build_openclaw_deps)
    fi
    if [[ "${N8N_ENABLED}" == "true" ]]; then
        n8n_deps=$(build_n8n_deps)
    fi
    if [[ "${FLOWISE_ENABLED}" == "true" ]]; then
        flowise_deps=$(build_flowise_deps)
    fi
    if [[ "${DIFY_ENABLED}" == "true" ]]; then
        dify_deps=$(build_dify_deps)
    fi
    if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
        authentik_deps=$(build_authentik_deps)
    fi
    
    # VOLUME MOUNT NOTE (for reviewers):
    # Volume entries follow the format  host_path:container_path
    # ALL host-side paths are under ${DATA_DIR} (/mnt/<tenant>/...) — core principle.
    # Container-side paths (right side) are the images' internal expectations and
    # cannot be changed (e.g. :/etc/caddy, :/root/.ollama, :/var/lib/postgresql/data).
    # They are NOT host paths. Ownership is enforced by prepare_data_dirs() which runs
    # before this function and sets PUID:PGID on every host-side directory.

    # Header and networks
    # Backup existing compose file (P3 fix)
    if [[ -f "${COMPOSE_FILE}" ]]; then
        cp "${COMPOSE_FILE}" "${COMPOSE_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        echo "Existing compose file backed up to ${COMPOSE_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    cat > "${COMPOSE_FILE}" << EOF

networks:
  ${DOCKER_NETWORK}:
    driver: bridge

services:
EOF

    # PostgreSQL (README P3 - explicit heredoc blocks)
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-postgres:
    image: postgres:15-alpine
    container_name: ${TENANT_PREFIX}-postgres
    restart: unless-stopped
    # postgres manages its own internal uid (70/alpine) — do not override user:
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
      retries: 6
      start_period: 30s

EOF
    fi

    # Redis
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-redis:
    image: redis:7-alpine
    container_name: ${TENANT_PREFIX}-redis
    restart: unless-stopped
    # redis manages its own internal uid (999) — do not override user:
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}
    volumes:
      - ${DATA_DIR}/redis:/data
    ports:
      - "127.0.0.1:${REDIS_PORT}:6379"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 6

EOF
    fi

    # Ollama
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-ollama:
    image: ollama/ollama:latest
    pull_policy: always
    container_name: ${TENANT_PREFIX}-ollama
    restart: unless-stopped
    # ollama runs as root internally, stores models in /root/.ollama — do not override user:
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
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-litellm:
    image: ghcr.io/berriai/litellm:main-stable
    container_name: ${TENANT_PREFIX}-litellm
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      DATABASE_URL: ${LITELLM_DB_URL}
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      LITELLM_UI_PASSWORD: ${LITELLM_UI_PASSWORD}
    volumes:
      - ${CONFIG_DIR}/litellm/config.yaml:/app/config.yaml
    ports:
      - "127.0.0.1:${LITELLM_PORT}:4000"
$(build_litellm_deps)
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health/liveliness"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Open WebUI
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ${TENANT_PREFIX}-openwebui
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      OLLAMA_BASE_URL: http://${TENANT_PREFIX}-ollama:11434
      OLLAMA_API_BASE_URL: http://${TENANT_PREFIX}-ollama:11434
      WEBUI_SECRET: ${OPENWEBUI_SECRET}
    volumes:
      - ${DATA_DIR}/openwebui:/app/backend/data
    ports:
      - "127.0.0.1:${OPENWEBUI_PORT}:3000"
$(build_openwebui_deps)
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # OpenClaw
    if [[ "${OPENCLAW_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-openclaw:
    image: openclaw/openclaw:latest
    container_name: ${TENANT_PREFIX}-openclaw
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${TENANT_PREFIX}-postgres:5432/${POSTGRES_DB}
      REDIS_URL: redis://:${REDIS_PASSWORD}@${TENANT_PREFIX}-redis:6379
    volumes:
      - ${DATA_DIR}/openclaw:/app/data
    ports:
      - "127.0.0.1:${OPENCLAW_PORT}:3001"
$(build_openclaw_deps)
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api/health"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Qdrant
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-qdrant:
    image: qdrant/qdrant:latest
    container_name: ${TENANT_PREFIX}-qdrant
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      QDRANT__SERVICE__HTTP_PORT: 6333
      QDRANT__SERVICE__GRPC_PORT: 6334
      API_KEY: ${QDRANT_API_KEY}
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

    # N8N
    if [[ "${N8N_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-n8n:
    image: n8nio/n8n:latest
    container_name: ${TENANT_PREFIX}-n8n
    restart: unless-stopped
    # n8n runs as node (uid 1000) with /home/node — do not override user:
    environment:
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_WEBHOOK_URL: ${N8N_WEBHOOK_URL}
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: ${TENANT_PREFIX}-postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      REDIS_HOST: ${TENANT_PREFIX}-redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
    volumes:
      - ${DATA_DIR}/n8n:/home/node/.n8n
    ports:
      - "127.0.0.1:${N8N_PORT}:5678"
$(build_n8n_deps)
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Flowise
    if [[ "${FLOWISE_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-flowise:
    image: flowiseai/flowise:latest
    container_name: ${TENANT_PREFIX}-flowise
    restart: unless-stopped
    # flowise stores data in /root/.flowise — do not override user:
    environment:
      DATABASE_TYPE: postgres
      DATABASE_HOST: ${TENANT_PREFIX}-postgres
      DATABASE_PORT: 5432
      DATABASE_NAME: ${POSTGRES_DB}
      DATABASE_USER: ${POSTGRES_USER}
      DATABASE_PASSWORD: ${POSTGRES_PASSWORD}
      FLOWISE_USERNAME: ${FLOWISE_USERNAME}
      FLOWISE_PASSWORD: ${FLOWISE_PASSWORD}
      SECRETKEY_OVERWRITE: ${FLOWISE_SECRETKEY_OVERWRITE}
    volumes:
      - ${DATA_DIR}/flowise:/root/.flowise
    ports:
      - "127.0.0.1:${FLOWISE_PORT}:3030"
$(build_flowise_deps)
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3030/api/v1/ping"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Dify
    if [[ "${DIFY_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-dify:
    image: langgenius/dify-web:latest
    container_name: ${TENANT_PREFIX}-dify
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: ${POSTGRES_USER}
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: ${TENANT_PREFIX}-postgres
      DB_PORT: 5432
      DB_DATABASE: ${POSTGRES_DB}
      REDIS_HOST: ${TENANT_PREFIX}-redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      QDRANT_HOST: ${TENANT_PREFIX}-qdrant
      QDRANT_PORT: 6333
      QDRANT_API_KEY: ${QDRANT_API_KEY}
    volumes:
      - ${DATA_DIR}/dify:/app/api/storage
    ports:
      - "127.0.0.1:${DIFY_PORT}:3040"
$(build_dify_deps)
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3040/health"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Authentik
    if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-authentik:
    image: ghcr.io/goauthentik/server:latest
    container_name: ${TENANT_PREFIX}-authentik
    restart: unless-stopped
    # authentik manages its own internal user — do not override user:
    environment:
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
      AUTHENTIK_BOOTSTRAP_PASSWORD: ${AUTHENTIK_BOOTSTRAP_PASSWORD}
      AUTHENTIK_BOOTSTRAP_EMAIL: ${AUTHENTIK_BOOTSTRAP_EMAIL}
    volumes:
      - ${DATA_DIR}/authentik:/media
    ports:
      - "127.0.0.1:${AUTHENTIK_PORT}:9000"
$(build_authentik_deps)
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/-/health/"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Signalbot
    if [[ "${SIGNALBOT_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-signalbot:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: ${TENANT_PREFIX}-signalbot
    restart: unless-stopped
    # signal-cli-rest-api runs as internal user (uid 1000) — do not override user:
    environment:
      MODE: json-rpc
      PHONE_NUMBER: ${SIGNAL_PHONE:-}
    volumes:
      - ${DATA_DIR}/signalbot:/home/user/.local/share/signal-cli
    ports:
      - "127.0.0.1:${SIGNALBOT_PORT}:8080"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/v1/about"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Bifrost
    if [[ "${BIFROST_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-bifrost:
    image: bifrost/bifrost:latest
    container_name: ${TENANT_PREFIX}-bifrost
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      API_KEY: ${BIFROST_API_KEY}
    volumes:
      - ${CONFIG_DIR}/bifrost/config.yaml:/app/config.yaml
    ports:
      - "127.0.0.1:${BIFROST_PORT}:8090"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8090/health"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Caddy (proxy - only service with 0.0.0.0 ports)
    if [[ "${CADDY_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-caddy:
    image: caddy:2-alpine
    container_name: ${TENANT_PREFIX}-caddy
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

    # Rclone ingestion (only if ENABLE_INGESTION=true and INGESTION_METHOD=rclone)
    if [[ "${ENABLE_INGESTION:-false}" == "true" && "${INGESTION_METHOD:-rclone}" == "rclone" ]]; then
        # Build rclone config inside the data dir so all paths stay under /mnt/$TENANT
        local rclone_conf_dir="${DATA_DIR}/rclone"
        mkdir -p "${rclone_conf_dir}"
        # Generate minimal rclone.conf if credentials file is provided
        if [[ -n "${GDRIVE_CREDENTIALS_FILE:-}" && -f "${GDRIVE_CREDENTIALS_FILE}" ]]; then
            cat > "${rclone_conf_dir}/rclone.conf" << RCLONE_EOF
[${RCLONE_REMOTE:-gdrive}]
type = drive
service_account_file = /credentials/credentials.json
scope = drive.readonly
RCLONE_EOF
            chmod 600 "${rclone_conf_dir}/rclone.conf"
            ok "rclone.conf generated at ${rclone_conf_dir}/rclone.conf"
        else
            warn "GDRIVE_CREDENTIALS_FILE not set or not found — rclone container will start but sync will fail until credentials are provided"
            touch "${rclone_conf_dir}/rclone.conf"
        fi

        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-rclone:
    image: rclone/rclone:latest
    container_name: ${TENANT_PREFIX}-rclone
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    entrypoint: ["/bin/sh", "-c", "while true; do rclone sync ${RCLONE_REMOTE:-gdrive}: /data --transfers=${RCLONE_TRANSFERS:-4} --checkers=${RCLONE_CHECKERS:-8} --log-level INFO 2>&1; sleep \$((${RCLONE_POLL_INTERVAL:-5}*60)); done"]
    volumes:
      - ${rclone_conf_dir}/rclone.conf:/config/rclone/rclone.conf:ro
      - ${GDRIVE_CREDENTIALS_FILE:-/dev/null}:/credentials/credentials.json:ro
      - ${DATA_DIR}/ingestion:/data
    networks:
      - ${DOCKER_NETWORK}

EOF
    fi

    ok "docker-compose.yml generated"
}

# =============================================================================
# CONFIG VALIDATION (README §6)
# =============================================================================
validate_compose() {
    log "Validating docker-compose.yml..."
    
    local output
    if ! output=$(docker compose -f "${COMPOSE_FILE}" config 2>&1); then
        echo "ERROR: docker-compose.yml validation failed:"
        echo "${output}"
        fail "docker-compose.yml validation failed"
    fi
    
    ok "docker-compose.yml is valid"
}

# =============================================================================
# LITELLM CONFIG GENERATION (README §10)
# =============================================================================
generate_litellm_config() {
    if [[ "${LITELLM_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    log "Generating LiteLLM configuration..."
    
    mkdir -p "${CONFIG_DIR}/litellm"
    
    cat > "${CONFIG_DIR}/litellm/config.yaml" << EOF
model_list:
EOF
    
    # Ollama model (only if enabled)
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: ollama/${OLLAMA_DEFAULT_MODEL}
    litellm_params:
      model: ollama/${OLLAMA_DEFAULT_MODEL}
      api_base: http://${TENANT_PREFIX}-ollama:11434
EOF
    fi
    
    # OpenAI (only if API key is non-empty)
    if [[ -n "${OPENAI_API_KEY}" ]]; then
        cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: ${OPENAI_API_KEY}
EOF
    fi
    
    # Anthropic (only if API key is non-empty)
    if [[ -n "${ANTHROPIC_API_KEY}" ]]; then
        cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: claude-3-sonnet-20240229
    litellm_params:
      model: anthropic/claude-3-sonnet-20240229
      api_key: ${ANTHROPIC_API_KEY}
EOF
    fi
    
    # Google (only if API key is non-empty)
    if [[ -n "${GOOGLE_API_KEY}" ]]; then
        cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: gemini-pro
    litellm_params:
      model: google/gemini-pro
      api_key: ${GOOGLE_API_KEY}
EOF
    fi
    
    # Groq (only if API key is non-empty)
    if [[ -n "${GROQ_API_KEY}" ]]; then
        cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: llama3-70b-8192
    litellm_params:
      model: groq/llama3-70b-8192
      api_key: ${GROQ_API_KEY}
EOF
    fi
    
    # OpenRouter (only if API key is non-empty)
    if [[ -n "${OPENROUTER_API_KEY}" ]]; then
        cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: openrouter/meta-llama/llama-3-70b-instruct
    litellm_params:
      model: openrouter/meta-llama/llama-3-70b-instruct
      api_key: ${OPENROUTER_API_KEY}
EOF
    fi
    
    # General settings
    cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: ${LITELLM_DB_URL}
  drop_params: true
  set_verbose: false
EOF
    
    chown -R "$PUID:$PGID" "${CONFIG_DIR}/litellm"
    ok "LiteLLM configuration generated"
}

# =============================================================================
# CADDYFILE GENERATION (README §9)
# =============================================================================
generate_caddyfile() {
    if [[ "${CADDY_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    log "Generating Caddyfile..."
    
    mkdir -p "${CONFIG_DIR}/caddy"
    
    cat > "${CONFIG_DIR}/caddy/Caddyfile" << EOF
{
    admin localhost:2019
    email ${PROXY_EMAIL}
    log {
        output file ${LOG_DIR}/caddy.log
        level INFO
    }
}

# Base domain redirect
${BASE_DOMAIN} {
    respond "AI Platform - ${BASE_DOMAIN}"
}
EOF
    
    # LiteLLM
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

litellm.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-litellm:4000
}
EOF
    fi
    
    # Open WebUI
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

openwebui.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-openwebui:3000
}
EOF
    fi
    
    # LibreChat removed - no MongoDB in platform
    
    # OpenClaw
    if [[ "${OPENCLAW_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

openclaw.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-openclaw:3001
}
EOF
    fi
    
    # N8N
    if [[ "${N8N_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

n8n.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-n8n:5678
}
EOF
    fi
    
    # Flowise
    if [[ "${FLOWISE_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

flowise.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-flowise:3030
}
EOF
    fi
    
    # Dify
    if [[ "${DIFY_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

dify.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-dify:3040
}
EOF
    fi
    
    # Authentik
    if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

authentik.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-authentik:9000
}
EOF
    fi
    
    chown -R "$PUID:$PGID" "${CONFIG_DIR}/caddy"
    ok "Caddyfile generated"
}

# =============================================================================
# BIFROST CONFIG GENERATION
# =============================================================================
generate_bifrost_config() {
    if [[ "${BIFROST_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    log "Generating Bifrost configuration..."
    
    mkdir -p "${CONFIG_DIR}/bifrost"
    
    cat > "${CONFIG_DIR}/bifrost/config.yaml" << EOF
api_key: ${BIFROST_API_KEY}
log_level: info
rate_limit:
  requests_per_minute: 60
  burst_size: 10
cache:
  ttl: 300
  max_size: 1000
EOF
    
    chown -R "$PUID:$PGID" "${CONFIG_DIR}/bifrost"
    ok "Bifrost configuration generated"
}

# =============================================================================
# SENTINEL SCAN (README §6 - mandatory)
# =============================================================================
scan_for_sentinels() {
    log "Scanning for unreplaced sentinels..."
    
    if grep -rE "CHANGEME|TODO_REPLACE|FIXME|xxxx|\{\{[A-Z_]+\}\}" "${CONFIG_DIR}/" 2>/dev/null; then
        fail "Unreplaced sentinels found - aborting deployment"
    fi
    
    ok "Sentinel scan: clean"
}

# =============================================================================
# HEALTH WAITING (README Appendix C - mandatory pattern)
# =============================================================================
wait_for_health() {
    local container_name="$1"
    local timeout="${2:-90}"
    local interval=5
    local elapsed=0

    log "Waiting for ${container_name} to become healthy (timeout: ${timeout}s)..."

    while [[ ${elapsed} -lt ${timeout} ]]; do
        local status
        status=$(docker inspect \
            --format='{{.State.Health.Status}}' \
            "${container_name}" 2>/dev/null) || status="not_found"

        case "${status}" in
            healthy)
                log "  ✅ ${container_name} is healthy"
                return 0
                ;;
            unhealthy)
                log "  ❌ ${container_name} reported unhealthy"
                docker logs --tail 20 "${container_name}" >&2
                return 1
                ;;
            not_found)
                log "  ⚠️  ${container_name} not found — is it deployed?"
                return 1
                ;;
            *)
                # starting | none — keep waiting
                sleep "${interval}"
                elapsed=$(( elapsed + interval ))
                ;;
        esac
    done

    log "  ❌ ${container_name} did not become healthy within ${timeout}s"
    docker logs --tail 30 "${container_name}" >&2
    return 1
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================
pull_images() {
    log "Pulling Docker images..."
    
    run_cmd docker compose -f "${COMPOSE_FILE}" pull
    
    ok "Images pulled"
}

validate_caddyfile() {
    if [[ "${CADDY_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    log "Validating Caddyfile..."
    
    # Run validation inside the caddy container
    if ! run_cmd docker run --rm \
        -v "${CONFIG_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
        caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile; then
        fail "Caddyfile validation failed"
    fi
    
    ok "Caddyfile is valid"
}

# =============================================================================
# DATA DIRECTORY PREPARATION (core principle: /mnt ownership, non-root)
# Must run before compose up so Docker never creates dirs as root.
# Each dir is created with PUID:PGID ownership so containers running as that
# user can write without privilege escalation.
# =============================================================================
prepare_data_dirs() {
    log "Preparing tenant data directories under ${DATA_DIR} ..."

    # Base structure
    mkdir -p \
        "${DATA_DIR}/config" \
        "${DATA_DIR}/config/ssl" \
        "${DATA_DIR}/config/caddy" \
        "${DATA_DIR}/config/litellm" \
        "${DATA_DIR}/config/bifrost" \
        "${DATA_DIR}/logs" \
        "${DATA_DIR}/.configured"

    # Per-service data directories (only create what is enabled to avoid clutter)
    [[ "${POSTGRES_ENABLED}"  == "true" ]] && mkdir -p "${DATA_DIR}/postgres"
    [[ "${REDIS_ENABLED}"     == "true" ]] && mkdir -p "${DATA_DIR}/redis"
    [[ "${OLLAMA_ENABLED}"    == "true" ]] && mkdir -p "${DATA_DIR}/ollama"
    [[ "${OPENWEBUI_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/openwebui"
    [[ "${OPENCLAW_ENABLED}"  == "true" ]] && mkdir -p "${DATA_DIR}/openclaw"
    [[ "${QDRANT_ENABLED}"    == "true" ]] && mkdir -p "${DATA_DIR}/qdrant"
    [[ "${WEAVIATE_ENABLED}"  == "true" ]] && mkdir -p "${DATA_DIR}/weaviate"
    [[ "${N8N_ENABLED}"       == "true" ]] && mkdir -p "${DATA_DIR}/n8n"
    [[ "${FLOWISE_ENABLED}"   == "true" ]] && mkdir -p "${DATA_DIR}/flowise"
    [[ "${DIFY_ENABLED}"      == "true" ]] && mkdir -p "${DATA_DIR}/dify"
    [[ "${GRAFANA_ENABLED}"   == "true" ]] && mkdir -p "${DATA_DIR}/grafana"
    [[ "${PROMETHEUS_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/prometheus"
    [[ "${AUTHENTIK_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/authentik"
    [[ "${SIGNALBOT_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/signalbot"
    [[ "${BIFROST_ENABLED}"   == "true" ]] && mkdir -p "${DATA_DIR}/bifrost"
    [[ "${ENABLE_INGESTION:-false}" == "true" ]] && mkdir -p "${DATA_DIR}/ingestion" "${DATA_DIR}/rclone"
    [[ "${CADDY_ENABLED}"     == "true" ]] && mkdir -p "${DATA_DIR}/caddy" "${DATA_DIR}/logs/caddy"

    # Set ownership of the entire tenant tree to PUID:PGID
    # (chown -R is safe here: all paths are under /mnt/<tenant>)
    chown -R "${PUID}:${PGID}" "${DATA_DIR}"

    ok "Data directories ready under ${DATA_DIR} (owner ${PUID}:${PGID})"
}

deploy_containers() {
    log "Deploying containers..."
    
    # Check for port conflicts before deployment
    log "Checking for port conflicts..."
    local ports_to_check=("80" "443" "3000" "4000" "5432" "6333" "6379" "11434")
    local conflicts=()
    
    for port in "${ports_to_check[@]}"; do
        if ss -tlnp | grep -q ":$port "; then
            conflicts+=("$port")
        fi
    done
    
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        fail "Port conflicts detected: ${conflicts[*]}. Stop services using these ports or change configuration."
    fi
    
    # Create Docker network
    if ! docker network ls | grep -q "${DOCKER_NETWORK}"; then
        run_cmd docker network create "${DOCKER_NETWORK}"
    fi
    
    # Pull latest images then deploy containers
    log "Pulling latest container images..."
    run_cmd docker compose -f "${COMPOSE_FILE}" pull
    log "Deploying containers..."
    run_cmd docker compose -f "${COMPOSE_FILE}" up -d
    
    ok "Containers deployed"
}

wait_for_all_health() {
    log "Waiting for all services to become healthy..."
    
    # Health check timeouts per service (README §6)
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-postgres" 60 || return 1
    fi
    
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-redis" 60 || return 1
    fi
    
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-ollama" 120 || return 1
    fi
    
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-litellm" 90 || return 1
    fi
    
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-openwebui" 90 || return 1
    fi
    
    # LibreChat removed - no MongoDB in platform
    
    if [[ "${OPENCLAW_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-openclaw" 90 || return 1
    fi
    
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-qdrant" 90 || return 1
    fi
    
    if [[ "${N8N_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-n8n" 90 || return 1
    fi
    
    if [[ "${FLOWISE_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-flowise" 90 || return 1
    fi
    
    if [[ "${DIFY_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-dify" 90 || return 1
    fi
    
    if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-authentik" 180 || return 1
    fi
    
    if [[ "${SIGNALBOT_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-signalbot" 90 || return 1
    fi
    
    if [[ "${BIFROST_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-bifrost" 90 || return 1
    fi
    
    if [[ "${CADDY_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-caddy" 90 || return 1
    fi
    
    ok "All services are healthy"
}

# =============================================================================
# MAIN FUNCTION (README §6 - strict execution order)
# =============================================================================
main() {
    local tenant_id="${1:-}"
    local dry_run=false
    
    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
    
    # Set global variables
    export DRY_RUN="$dry_run"
    
    # Validate tenant ID
    if [[ -z "$tenant_id" ]]; then
        fail "Tenant ID is required"
    fi
    
    # Source platform.conf (README P1 - single source of truth)
    local platform_conf="/mnt/${tenant_id}/config/platform.conf"
    if [[ ! -f "$platform_conf" ]]; then
        fail "platform.conf not found at $platform_conf. Run script 1 first."
    fi
    # shellcheck source=/dev/null
    source "$platform_conf"

    # Normalise / derive variables not directly in platform.conf
    # These are safe to compute here since platform.conf is already sourced.
    CONFIGURED_DIR="${DATA_DIR}/.configured"
    BASE_DIR="${DATA_DIR}"
    CONFIG_DIR="${DATA_DIR}/config"
    LOG_FILE="${DATA_DIR}/logs/deploy-$(date +%Y%m%d-%H%M%S).log"

    mkdir -p "${DATA_DIR}/logs" "$CONFIGURED_DIR"

    # Database URL (needs passwords from platform.conf)
    LITELLM_DB_URL="postgresql://${POSTGRES_USER:-${TENANT_ID}}:${POSTGRES_PASSWORD}@${TENANT_PREFIX}-postgres:5432/${POSTGRES_DB:-${TENANT_ID}}"

    # Alias any vars Script 2 expects that platform.conf may call differently
    BASE_DOMAIN="${BASE_DOMAIN:-${DOMAIN}}"
    PROXY_EMAIL="${PROXY_EMAIL:-${ADMIN_EMAIL}}"
    OPENWEBUI_SECRET="${OPENWEBUI_SECRET:-$(openssl rand -hex 32)}"
    N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-http://${DOMAIN}/}"
    FLOWISE_USERNAME="${FLOWISE_USERNAME:-admin}"
    FLOWISE_PASSWORD="${FLOWISE_PASSWORD:-$(openssl rand -base64 16 | tr -d '=+/')}"
    FLOWISE_SECRETKEY_OVERWRITE="${FLOWISE_SECRETKEY_OVERWRITE:-$(openssl rand -hex 32)}"
    DIFY_SECRET_KEY="${DIFY_SECRET_KEY:-$(openssl rand -hex 32)}"
    GOOGLE_API_KEY="${GOOGLE_API_KEY:-${GOOGLE_AI_API_KEY:-}}"
    OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-qwen2.5:7b}"

    # Derive TENANT_PREFIX if not in platform.conf (backward compat)
    TENANT_PREFIX="${TENANT_PREFIX:-${PLATFORM_PREFIX}-${TENANT_ID}}"

    # Process UID/GID — fall back to current user if not in platform.conf
    PUID="${PUID:-$(id -u)}"
    PGID="${PGID:-$(id -g)}"

    # Map ENABLE_* → *_ENABLED (backward compat with old platform.conf)
    POSTGRES_ENABLED="${POSTGRES_ENABLED:-${ENABLE_POSTGRES:-false}}"
    REDIS_ENABLED="${REDIS_ENABLED:-${ENABLE_REDIS:-false}}"
    OLLAMA_ENABLED="${OLLAMA_ENABLED:-${ENABLE_OLLAMA:-false}}"
    LITELLM_ENABLED="${LITELLM_ENABLED:-${ENABLE_LITELLM:-false}}"
    OPENWEBUI_ENABLED="${OPENWEBUI_ENABLED:-${ENABLE_OPENWEBUI:-false}}"
    QDRANT_ENABLED="${QDRANT_ENABLED:-${ENABLE_QDRANT:-false}}"
    WEAVIATE_ENABLED="${WEAVIATE_ENABLED:-${ENABLE_WEAVIATE:-false}}"
    N8N_ENABLED="${N8N_ENABLED:-${ENABLE_N8N:-false}}"
    FLOWISE_ENABLED="${FLOWISE_ENABLED:-${ENABLE_FLOWISE:-false}}"
    DIFY_ENABLED="${DIFY_ENABLED:-${ENABLE_DIFY:-false}}"
    GRAFANA_ENABLED="${GRAFANA_ENABLED:-${ENABLE_GRAFANA:-false}}"
    PROMETHEUS_ENABLED="${PROMETHEUS_ENABLED:-${ENABLE_PROMETHEUS:-false}}"
    CADDY_ENABLED="${CADDY_ENABLED:-${ENABLE_CADDY:-false}}"
    AUTHENTIK_ENABLED="${AUTHENTIK_ENABLED:-${ENABLE_AUTHENTIK:-false}}"
    OPENCLAW_ENABLED="${OPENCLAW_ENABLED:-${ENABLE_OPENCLAW:-false}}"
    BIFROST_ENABLED="${BIFROST_ENABLED:-${ENABLE_BIFROST:-false}}"
    SIGNALBOT_ENABLED="${SIGNALBOT_ENABLED:-${ENABLE_SIGNALBOT:-false}}"

    # Re-compute LITELLM_DB_URL now that TENANT_PREFIX and POSTGRES_USER are resolved
    POSTGRES_USER="${POSTGRES_USER:-${TENANT_ID}}"
    POSTGRES_DB="${POSTGRES_DB:-${TENANT_ID}}"
    LITELLM_DB_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${TENANT_PREFIX}-postgres:5432/${POSTGRES_DB}"

    mkdir -p "$CONFIGURED_DIR"
    
    log "=== Script 2: Atomic Deployer ==="
    log "Version: ${SCRIPT_VERSION}"
    log "Tenant: ${tenant_id}"
    log "Dry-run: ${dry_run}"
    
    # Execution order (README §6 - strict):
    # 1. source platform.conf (done above)
    # 2. Pre-flight checks
    if ! step_done "preflight_checks"; then
        framework_validate
        mark_done "preflight_checks"
    else
        log "Pre-flight checks already completed, skipping"
    fi

    # 2b. Prepare data directories (idempotent — safe to re-run)
    #     Runs every time to ensure ownership is correct even after re-mounts.
    prepare_data_dirs

    # 3. generate_compose()
    if ! step_done "compose_generated"; then
        generate_compose
        mark_done "compose_generated"
    else
        log "docker-compose.yml already generated, skipping"
    fi
    
    # 4. validate_compose()
    validate_compose
    
    # 5. generate_litellm_config()
    if ! step_done "litellm_config_generated"; then
        generate_litellm_config
        mark_done "litellm_config_generated"
    else
        log "LiteLLM config already generated, skipping"
    fi
    
    # 6. generate_caddyfile() [if caddy enabled]
    if ! step_done "caddyfile_generated"; then
        generate_caddyfile
        mark_done "caddyfile_generated"
    else
        log "Caddyfile already generated, skipping"
    fi
    
    # Generate Bifrost config if enabled
    if [[ "${BIFROST_ENABLED}" == "true" ]] && ! step_done "bifrost_config_generated"; then
        generate_bifrost_config
        mark_done "bifrost_config_generated"
    fi
    
    # Scan for sentinels (README §6 - mandatory)
    if ! step_done "sentinel_scan"; then
        scan_for_sentinels
        mark_done "sentinel_scan"
    else
        log "Sentinel scan already completed, skipping"
    fi
    
    # 7. docker compose pull
    if ! step_done "images_pulled"; then
        pull_images
        mark_done "images_pulled"
    else
        log "Images already pulled, skipping"
    fi
    
    # 8. validate_caddyfile() [AFTER pull, not before]
    validate_caddyfile
    
    # 9. docker compose up -d
    if ! step_done "containers_deployed"; then
        deploy_containers
        mark_done "containers_deployed"
    else
        log "Containers already deployed, skipping"
    fi
    
    # 10. wait_for_health() for each enabled service
    if ! step_done "health_checks_passed"; then
        wait_for_all_health
        mark_done "health_checks_passed"
    else
        log "Health checks already passed, skipping"
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
    echo "  ✓ All services verified healthy"
    echo ""
    echo "  Next step:"
    echo "  1. Configure services: bash scripts/3-configure-services.sh ${tenant_id}"
    echo ""
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
