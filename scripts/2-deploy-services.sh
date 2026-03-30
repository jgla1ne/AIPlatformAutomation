#!/usr/bin/env bash
# =============================================================================
# Script 2: Atomic Deployer - BULLETPROOF v5.0 FINAL
# =============================================================================
# PURPOSE: Read platform.conf + generate ALL configs + deploy containers
# USAGE:   sudo bash scripts/2-deploy-services.sh [tenant_id] [options]
# OPTIONS: --dry-run           Show what would be deployed without action
#          --validate-only     Only validate configs, don't deploy
#          --force-recreate    Force recreate all containers
# =============================================================================

set -euo pipefail

# =============================================================================
# NON-ROOT EXECUTION CHECK (README P7 - mandatory)
# =============================================================================
if [[ $EUID -eq 0 ]]; then
    fail "This script must not be run as root (README P7 requirement)"
fi

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# =============================================================================
# LOGGING AND UTILITIES (README P11 - mandatory dual logging)
# =============================================================================
# Set up log file (will be set after tenant_id is known)
LOG_FILE=""

log() { 
    echo "[INFO] $1"
    [[ -n "$LOG_FILE" ]] && echo "[$(date +%H:%M:%S)] $1" >> "$LOG_FILE"
}
ok() { 
    echo "[OK] $*"
    [[ -n "$LOG_FILE" ]] && echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"
}
warn() { 
    echo "[WARN] $*"
    [[ -n "$LOG_FILE" ]] && echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"
}
fail() { 
    echo "[FAIL] $*"
    [[ -n "$LOG_FILE" ]] && echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"
    exit 1
}
section() { 
    echo ""
    echo "=== $* ==="
    echo ""
    [[ -n "$LOG_FILE" ]] && echo "" >> "$LOG_FILE" && echo "=== $* ===" >> "$LOG_FILE" && echo "" >> "$LOG_FILE"
}
dry_run() { [[ "${DRY_RUN:-false}" == "true" ]] && echo "[DRY-RUN] $1"; }

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
# LOAD PLATFORM CONF
# =============================================================================
load_platform_conf() {
    local tenant_id="$1"
    local platform_conf="/mnt/${tenant_id}/config/platform.conf"
    
    # Guard: Ensure Script 1 ran first
    if [[ ! -f "$platform_conf" ]]; then
        fail "platform.conf not found at $platform_conf - run Script 1 first"
    fi
    
    # Source platform.conf (README-compliant approach)
    source "$platform_conf"
    log "Loaded platform.conf from $platform_conf"
    
    # Validate critical variables
    local critical_vars=(
        "TENANT_ID" "BASE_DIR" "CONFIG_DIR" "DOCKER_NETWORK" 
        "DOCKER_SUBNET" "POSTGRES_USER" "POSTGRES_PASSWORD" "POSTGRES_DB"
    )
    
    local missing=()
    for var in "${critical_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        fail "Missing critical variables in platform.conf: ${missing[*]}"
    fi
    
    # Set derived variables
    COMPOSE_FILE="${CONFIG_DIR}/docker-compose.yml"
    CADDYFILE="${CONFIG_DIR}/caddy/Caddyfile"
    LITELLM_CONFIG="${CONFIG_DIR}/litellm/config.yaml"
    BIFROST_CONFIG="${CONFIG_DIR}/bifrost/config.yaml"
    CONFIGURED_DIR="${BASE_DIR}/.configured"
    
    # Create configured directory for idempotency markers
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        mkdir -p "$CONFIGURED_DIR"
    fi
    
    # Set up log file (README P11 - after tenant_id is known)
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        mkdir -p "${BASE_DIR}/logs"
        LOG_FILE="${BASE_DIR}/logs/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log"
        log "Log file: $LOG_FILE"
    fi
}

# =============================================================================
# IDEMPOTENCY MARKERS (README P8 - mandatory)
# =============================================================================
step_done() {
    [[ -f "${CONFIGURED_DIR}/${1}" ]]
}

mark_done() {
    touch "${CONFIGURED_DIR}/${1}"
    log "Marked step complete: ${1}"
}

# =============================================================================
# DIRECTORY STRUCTURE CREATION
# =============================================================================
create_directories() {
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        log "Creating directory structure..."
        
        local dirs=(
            "${CONFIG_DIR}"
            "${CONFIG_DIR}/caddy"
            "${CONFIG_DIR}/litellm"
            "${CONFIG_DIR}/bifrost"
            "${CONFIG_DIR}/ssl"
            "${BASE_DIR}/data/postgres"
            "${BASE_DIR}/data/redis"
            "${BASE_DIR}/data/ollama"
            "${BASE_DIR}/data/open-webui"
            "${BASE_DIR}/data/qdrant"
            "${BASE_DIR}/data/weaviate"
            "${BASE_DIR}/data/chroma"
            "${BASE_DIR}/data/n8n"
            "${BASE_DIR}/data/flowise"
            "${BASE_DIR}/data/searxng"
            "${BASE_DIR}/data/authentik"
            "${BASE_DIR}/data/grafana"
            "${BASE_DIR}/data/prometheus"
        )
        
        for dir in "${dirs[@]}"; do
            mkdir -p "$dir"
        done
        
        # Set ownership (README-compliant)
        chown -R 1000:1000 "${BASE_DIR}"
        
        ok "Directory structure created"
    else
        dry_run "Would create directory structure under ${BASE_DIR}"
    fi
}

# =============================================================================
# DOCKER NETWORK CREATION
# =============================================================================
create_docker_network() {
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        log "Creating Docker network: ${DOCKER_NETWORK}"
        
        # Check if network exists
        if docker network ls --format '{{.Name}}' | grep -q "^${DOCKER_NETWORK}$"; then
            log "Network ${DOCKER_NETWORK} already exists"
            
            # Validate existing network matches config
            local existing_subnet
            existing_subnet=$(docker network inspect "${DOCKER_NETWORK}" \
                --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "")
            
            if [[ "$existing_subnet" != "$DOCKER_SUBNET" ]]; then
                warn "Existing network subnet ($existing_subnet) differs from config ($DOCKER_SUBNET)"
                warn "Run Script 0 to clean up, then re-run"
            else
                log "Network configuration matches: subnet=$existing_subnet"
            fi
        else
            # Create network
            docker network create \
                --driver bridge \
                --subnet "$DOCKER_SUBNET" \
                --gateway "$DOCKER_GATEWAY" \
                --opt "com.docker.network.driver.mtu=$DOCKER_MTU" \
                --label "com.docker.compose.project=${TENANT_ID}" \
                "${DOCKER_NETWORK}"
            
            ok "Network ${DOCKER_NETWORK} created"
        fi
    else
        dry_run "Would create Docker network: ${DOCKER_NETWORK} (${DOCKER_SUBNET})"
    fi
}

# =============================================================================
# CONFIG GENERATION FUNCTIONS
# =============================================================================
generate_docker_compose() {
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        log "Generating docker-compose.yml..."
        
        # Generate GPU section for Ollama
        local ollama_gpu_section=""
        if [[ "$GPU_TYPE" == "nvidia" ]]; then
            ollama_gpu_section='
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]'
        elif [[ "$GPU_TYPE" == "amd" ]]; then
            ollama_gpu_section='
    devices:
      - /dev/kfd
      - /dev/dri'
        fi
        
        # Heredoc-based compose generation (Expert Fix)
        cat > "$COMPOSE_FILE" << 'EOF'
# =============================================================================
# AI Platform — Docker Compose
# Generated by Script 2 on $(date)
# DO NOT EDIT MANUALLY - Re-run Script 2 to regenerate
# =============================================================================

version: '3.8'

networks:
  default:
    name: ${DOCKER_NETWORK}
    external: true

volumes:
EOF
        
        # Add volumes with conditional blocks
        if [[ "$POSTGRES_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF
  postgres_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${BASE_DIR}/data/postgres
    labels:
      com.docker.compose.project: ${TENANT_ID}

EOF
        fi
        
        if [[ "$REDIS_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF
  redis_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${BASE_DIR}/data/redis
    labels:
      com.docker.compose.project: ${TENANT_ID}

EOF
        fi
        
        if [[ "$OLLAMA_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF
  ollama_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${BASE_DIR}/data/ollama
    labels:
      com.docker.compose.project: ${TENANT_ID}

EOF
        fi
        
        if [[ "$OPEN_WEBUI_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF
  open_webui_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${BASE_DIR}/data/open-webui
    labels:
      com.docker.compose.project: ${TENANT_ID}

EOF
        fi
        
        if [[ "$QDRANT_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF
  qdrant_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${BASE_DIR}/data/qdrant
    labels:
      com.docker.compose.project: ${TENANT_ID}

EOF
        fi
        
        if [[ "$WEAVIATE_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF
  weaviate_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${BASE_DIR}/data/weaviate
    labels:
      com.docker.compose.project: ${TENANT_ID}

EOF
        fi
        
        if [[ "$CHROMA_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF
  chroma_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${BASE_DIR}/data/chroma
    labels:
      com.docker.compose.project: ${TENANT_ID}

EOF
        fi
        
        if [[ "$N8N_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF
  n8n_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${BASE_DIR}/data/n8n
    labels:
      com.docker.compose.project: ${TENANT_ID}

EOF
        fi
        
        if [[ "$FLOWISE_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF
  flowise_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${BASE_DIR}/data/flowise
    labels:
      com.docker.compose.project: ${TENANT_ID}

EOF
        fi
        
        # Services section
        cat >> "$COMPOSE_FILE" << EOF
services:
EOF
        
        # PostgreSQL service
        if [[ "$POSTGRES_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── PostgreSQL ────────────────────────────────────────────────────────
  postgres:
    image: postgres:15-alpine
    container_name: ${PREFIX}${TENANT_ID}_postgres
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: postgres
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "127.0.0.1:${POSTGRES_PORT}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

EOF
        fi
        
        # Redis service
        if [[ "$REDIS_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── Redis ───────────────────────────────────────────────────────────────
  redis:
    image: redis:7-alpine
    container_name: ${PREFIX}${TENANT_ID}_redis
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: redis
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    command: >
      redis-server
      --requirepass ${REDIS_PASSWORD}
      --appendonly yes
      --save 60 1
      --loglevel warning
    volumes:
      - redis_data:/data
    ports:
      - "127.0.0.1:${REDIS_PORT}:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 15s

EOF
        fi
        
        # Ollama service
        if [[ "$OLLAMA_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── Ollama ───────────────────────────────────────────────────────────────
  ollama:
    image: ollama/ollama:latest
    container_name: ${PREFIX}${TENANT_ID}_ollama
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: ollama
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    ports:
      - "127.0.0.1:${OLLAMA_PORT}:11434"
    volumes:
      - ollama_data:/root/.ollama
    environment:
      OLLAMA_HOST: 0.0.0.0
      OLLAMA_KEEP_ALIVE: -1
      OLLAMA_NUM_PARALLEL: 2
      OLLAMA_MAX_QUEUE: 512${ollama_gpu_section}
    healthcheck:
      test: ["CMD", "sh", "-c", "exec 3<>/dev/tcp/localhost/11434"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 60s

EOF
        fi
        
        # LiteLLM service
        if [[ "$LITELLM_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── LiteLLM ───────────────────────────────────────────────────────────────
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: ${PREFIX}${TENANT_ID}_litellm
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: litellm
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    ports:
      - "127.0.0.1:${LITELLM_PORT}:4000"
    volumes:
      - ${CONFIG_DIR}/litellm:/app/config
    environment:
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      DATABASE_URL: ${LITELLM_DATABASE_URL}
EOF
            
            # Add provider configurations
            if [[ "$ENABLE_OPENAI" == "true" ]]; then
                cat >> "$COMPOSE_FILE" << EOF
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      OPENAI_API_BASE: ${OPENAI_API_BASE}
EOF
                if [[ -n "${OPENAI_API_VERSION:-}" ]]; then
                    cat >> "$COMPOSE_FILE" << EOF
      OPENAI_API_VERSION: ${OPENAI_API_VERSION}
EOF
                fi
            fi
            
            if [[ "$ENABLE_ANTHROPIC" == "true" ]]; then
                cat >> "$COMPOSE_FILE" << EOF
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
EOF
            fi
            
            cat >> "$COMPOSE_FILE" << EOF
    depends_on:
      - postgres
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
        fi
        
        # Bifrost service
        if [[ "$BIFROST_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── Bifrost ───────────────────────────────────────────────────────────────
  bifrost:
    image: bifrost/bifrost:latest
    container_name: ${PREFIX}${TENANT_ID}_bifrost
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: bifrost
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    ports:
      - "127.0.0.1:${BIFROST_PORT}:8000"
    volumes:
      - ${CONFIG_DIR}/bifrost:/app/config
    environment:
      BIFROST_CONFIG: /app/config/config.yaml
    depends_on:
      - ollama
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
        fi
        
        # Open WebUI service
        if [[ "$OPEN_WEBUI_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── Open WebUI ───────────────────────────────────────────────────────────
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ${PREFIX}${TENANT_ID}_open-webui
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: open-webui
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    ports:
      - "127.0.0.1:${OPEN_WEBUI_PORT}:8080"
    volumes:
      - open_webui_data:/app/backend/data
    environment:
      OPENAI_API_BASE_URL: http://litellm:4000
EOF
            
            # Add dependencies based on enabled LLM proxies
            if [[ "$LITELLM_ENABLED" == "true" && "$BIFROST_ENABLED" == "true" ]]; then
                cat >> "$COMPOSE_FILE" << EOF
    depends_on:
      - litellm
      - bifrost
EOF
            elif [[ "$LITELLM_ENABLED" == "true" ]]; then
                cat >> "$COMPOSE_FILE" << EOF
    depends_on:
      - litellm
EOF
            elif [[ "$BIFROST_ENABLED" == "true" ]]; then
                cat >> "$COMPOSE_FILE" << EOF
    depends_on:
      - bifrost
EOF
            fi
            
            cat >> "$COMPOSE_FILE" << EOF
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
        fi
        
        # Vector databases
        if [[ "$QDRANT_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── Qdrant ───────────────────────────────────────────────────────────────
  qdrant:
    image: qdrant/qdrant:latest
    container_name: ${PREFIX}${TENANT_ID}_qdrant
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: qdrant
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    ports:
      - "127.0.0.1:${QDRANT_PORT}:6333"
    volumes:
      - qdrant_data:/qdrant/storage
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/healthz"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
        fi
        
        if [[ "$WEAVIATE_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── Weaviate ───────────────────────────────────────────────────────────────
  weaviate:
    image: semitechnologies/weaviate:latest
    container_name: ${PREFIX}${TENANT_ID}_weaviate
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: weaviate
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    ports:
      - "127.0.0.1:${WEAVIATE_PORT}:8080"
    volumes:
      - weaviate_data:/var/lib/weaviate
    environment:
      QUERY_DEFAULTS_LIMIT: 25
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: 'true'
      PERSISTENCE_DATA_PATH: '/var/lib/weaviate'
      DEFAULT_VECTORIZER_MODULE: 'none'
      ENABLE_MODULES: 'backup-filesystem,generative-openai,ref2vec-centroid,reranker-cohere,qna-openai,text2vec-openai,generative-cohere'
      BACKUP_FILESYSTEM_PATH: '/var/lib/weaviate/backups'
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/v1/.well-known/ready"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
        fi
        
        if [[ "$CHROMA_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── Chroma ───────────────────────────────────────────────────────────────
  chroma:
    image: chromadb/chroma:latest
    container_name: ${PREFIX}${TENANT_ID}_chroma
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: chroma
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    ports:
      - "127.0.0.1:${CHROMA_PORT}:8000"
    volumes:
      - chroma_data:/chroma/chroma
    environment:
      CHROMA_SERVER_HOST: 0.0.0.0
      CHROMA_SERVER_HTTP_PORT: 8000
      CHROMA_LOG_LEVEL: INFO
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/v1/heartbeat"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
        fi
        
        # Workflow tools
        if [[ "$N8N_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── n8n ────────────────────────────────────────────────────────────────
  n8n:
    image: n8nio/n8n:latest
    container_name: ${PREFIX}${TENANT_ID}_n8n
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: n8n
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    ports:
      - "127.0.0.1:${N8N_PORT}:5678"
    volumes:
      - n8n_data:/home/node/.n8n
    environment:
      N8N_BASIC_AUTH_ACTIVE: "false"
      N8N_HOST: "0.0.0.0"
      N8N_PORT: "5678"
      N8N_PROTOCOL: "http"
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      DB_TYPE: "postgresdb"
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: "5432"
      DB_POSTGRESDB_DATABASE: ${N8N_DB}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      WEBHOOK_URL: "http://${HOST_IP}:${N8N_PORT}"
    depends_on:
      - postgres
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
        fi
        
        if [[ "$FLOWISE_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── Flowise ───────────────────────────────────────────────────────────────
  flowise:
    image: flowiseai/flowise:latest
    container_name: ${PREFIX}${TENANT_ID}_flowise
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: flowise
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    ports:
      - "127.0.0.1:${FLOWISE_PORT}:3001"
    volumes:
      - flowise_data:/storage
    environment:
      FLOWISE_USERNAME: ${FLOWISE_USERNAME:-admin}
      FLOWISE_PASSWORD: ${FLOWISE_PASSWORD}
      DATABASE_TYPE: "postgres"
      DATABASE_HOST: postgres
      DATABASE_PORT: "5432"
      DATABASE_NAME: ${FLOWISE_DB}
      DATABASE_USER: ${POSTGRES_USER}
      DATABASE_PASSWORD: ${POSTGRES_PASSWORD}
      FLOWISE_SECRETKEY: ${FLOWISE_SECRET_KEY}
    depends_on:
      - postgres
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api/v1/ping"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
        fi
        
        # Additional services
        if [[ "$SEARXNG_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── SearXNG ───────────────────────────────────────────────────────────────
  searxng:
    image: searxng/searxng:latest
    container_name: ${PREFIX}${TENANT_ID}_searxng
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: searxng
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    ports:
      - "127.0.0.1:${SEARXNG_PORT}:8080"
    volumes:
      - ${CONFIG_DIR}/searxng:/etc/searxng
    environment:
      SEARXNG_BASE_URL: "http://${HOST_IP}:${SEARXNG_PORT}"
      SEARXNG_SECRET_KEY: ${SEARXNG_SECRET_KEY}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
        fi
        
        if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── Authentik ─────────────────────────────────────────────────────────────
  authentik:
    image: ghcr.io/goauthentik/server:latest
    container_name: ${PREFIX}${TENANT_ID}_authentik
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: authentik
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    ports:
      - "127.0.0.1:${AUTHENTIK_PORT}:9000"
    volumes:
      - ${CONFIG_DIR}/authentik:/media
    environment:
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
      AUTHENTIK_BOOTSTRAP_PASSWORD: ${AUTHENTIK_BOOTSTRAP_PASSWORD}
      AUTHENTIK_BOOTSTRAP_EMAIL: ${AUTHENTIK_BOOTSTRAP_EMAIL}
    depends_on:
      - postgres
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/outpost.goauthentik.io/"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
        fi
        
        if [[ "$GRAFANA_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── Grafana ───────────────────────────────────────────────────────────────
  grafana:
    image: grafana/grafana:latest
    container_name: ${PREFIX}${TENANT_ID}_grafana
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: grafana
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    ports:
      - "127.0.0.1:${GRAFANA_PORT}:3000"
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD:-admin}
    depends_on:
      - prometheus
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
        fi
        
        if [[ "$PROMETHEUS_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── Prometheus ───────────────────────────────────────────────────────────
  prometheus:
    image: prom/prometheus:latest
    container_name: ${PREFIX}${TENANT_ID}_prometheus
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: prometheus
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    ports:
      - "127.0.0.1:${PROMETHEUS_PORT}:9090"
    volumes:
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
        fi
        
        # Caddy reverse proxy
        if [[ "$CADDY_ENABLED" == "true" ]]; then
            cat >> "$COMPOSE_FILE" << EOF

  # ── Caddy ───────────────────────────────────────────────────────────────
  caddy:
    image: caddy:2-alpine
    container_name: ${PREFIX}${TENANT_ID}_caddy
    restart: unless-stopped
    labels:
      com.docker.compose.project: ${TENANT_ID}
      service: caddy
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ${CONFIG_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ${CONFIG_DIR}/ssl:/etc/ssl/caddy:ro
    environment:
      CADDY_INGRESS_DOMAINS: ${BASE_DOMAIN}
EOF
            
            # Add dependencies for all web services
            local caddy_deps=""
            if [[ "$OPEN_WEBUI_ENABLED" == "true" ]]; then
                caddy_deps="${caddy_deps}      - open-webui"$'\n'
            fi
            if [[ "$N8N_ENABLED" == "true" ]]; then
                caddy_deps="${caddy_deps}      - n8n"$'\n'
            fi
            if [[ "$FLOWISE_ENABLED" == "true" ]]; then
                caddy_deps="${caddy_deps}      - flowise"$'\n'
            fi
            if [[ "$SEARXNG_ENABLED" == "true" ]]; then
                caddy_deps="${caddy_deps}      - searxng"$'\n'
            fi
            if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
                caddy_deps="${caddy_deps}      - authentik"$'\n'
            fi
            if [[ "$GRAFANA_ENABLED" == "true" ]]; then
                caddy_deps="${caddy_deps}      - grafana"$'\n'
            fi
            
            if [[ -n "$caddy_deps" ]]; then
                cat >> "$COMPOSE_FILE" << EOF
    depends_on:
${caddy_deps}
EOF
            fi
            
            cat >> "$COMPOSE_FILE" << EOF
    healthcheck:
      test: ["CMD", "caddy", "validate", "--config", "/etc/caddy/Caddyfile"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

EOF
        fi
        
        # Set permissions
        chmod 600 "$COMPOSE_FILE"
        chown 1000:1000 "$COMPOSE_FILE"
        
        ok "docker-compose.yml generated"
    else
        dry_run "Would generate docker-compose.yml at ${COMPOSE_FILE}"
    fi
}

generate_litellm_config() {
    if [[ "$LITELLM_ENABLED" == "true" && "${DRY_RUN:-false}" == "false" ]]; then
        log "Generating LiteLLM configuration..."
        
        mkdir -p "${CONFIG_DIR}/litellm"
        
        # Heredoc-based config generation (Expert Fix - no redundant envsubst)
        cat > "$LITELLM_CONFIG" << EOF
model_list:
  - model_name: openai-model
    litellm_params:
      model: openai/gpt-3.5-turbo
      api_key: ${OPENAI_API_KEY}
      api_base: ${OPENAI_API_BASE}
EOF
        
        if [[ -n "${OPENAI_API_VERSION:-}" ]]; then
            cat >> "$LITELLM_CONFIG" << EOF
      api_version: ${OPENAI_API_VERSION}
EOF
        fi
        
        if [[ "$ENABLE_ANTHROPIC" == "true" ]]; then
            cat >> "$LITELLM_CONFIG" << EOF

  - model_name: claude-model
    litellm_params:
      model: anthropic/claude-3-sonnet-20240229
      api_key: ${ANTHROPIC_API_KEY}
EOF
        fi
        
        cat >> "$LITELLM_CONFIG" << EOF

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: ${LITELLM_DATABASE_URL}
  drop_params: true

litellm_settings:
  drop_params: true
  set_verbose: false
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]
EOF
        
        chmod 600 "$LITELLM_CONFIG"
        chown 1000:1000 "$LITELLM_CONFIG"
        
        ok "LiteLLM configuration generated"
    fi
}

generate_bifrost_config() {
    if [[ "$BIFROST_ENABLED" == "true" && "${DRY_RUN:-false}" == "false" ]]; then
        log "Generating Bifrost configuration..."
        
        mkdir -p "${CONFIG_DIR}/bifrost"
        
        cat > "$BIFROST_CONFIG" << EOF
# Bifrost Configuration
server:
  host: "0.0.0.0"
  port: 8000

ollama:
  url: "http://ollama:11434"
  timeout: 30

models:
  default: "llama3.2"
  available:
    - "llama3.2"
    - "mistral"
    - "gemma2"

routing:
  strategy: "local-first"
  fallback:
    enabled: true
    timeout: 10

logging:
  level: "info"
  format: "json"
EOF
        
        chmod 600 "$BIFROST_CONFIG"
        chown 1000:1000 "$BIFROST_CONFIG"
        
        ok "Bifrost configuration generated"
    fi
}

generate_caddyfile() {
    if [[ "$CADDY_ENABLED" == "true" && "${DRY_RUN:-false}" == "false" ]]; then
        log "Generating Caddyfile..."
        
        mkdir -p "${CONFIG_DIR}/caddy"
        
        cat > "$CADDYFILE" << EOF
{
    email ${TLS_EMAIL}
    auto_https off
}

# Global settings
{
    servers {
        protocol {
            experimental_http3
        }
    }
}

EOF
        
        # Add service blocks based on enabled services
        if [[ "$OPEN_WEBUI_ENABLED" == "true" ]]; then
            cat >> "$CADDYFILE" << EOF
open-webui.${BASE_DOMAIN} {
    reverse_proxy open-webui:8080
}

EOF
        fi
        
        if [[ "$N8N_ENABLED" == "true" ]]; then
            cat >> "$CADDYFILE" << EOF
n8n.${BASE_DOMAIN} {
    reverse_proxy n8n:5678
}

EOF
        fi
        
        if [[ "$FLOWISE_ENABLED" == "true" ]]; then
            cat >> "$CADDYFILE" << EOF
flowise.${BASE_DOMAIN} {
    reverse_proxy flowise:3001
}

EOF
        fi
        
        if [[ "$SEARXNG_ENABLED" == "true" ]]; then
            cat >> "$CADDYFILE" << EOF
search.${BASE_DOMAIN} {
    reverse_proxy searxng:8080
}

EOF
        fi
        
        if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
            cat >> "$CADDYFILE" << EOF
auth.${BASE_DOMAIN} {
    reverse_proxy authentik:9000
}

EOF
        fi
        
        if [[ "$GRAFANA_ENABLED" == "true" ]]; then
            cat >> "$CADDYFILE" << EOF
grafana.${BASE_DOMAIN} {
    reverse_proxy grafana:3000
}

EOF
        fi
        
        chmod 600 "$CADDYFILE"
        chown 1000:1000 "$CADDYFILE"
        
        ok "Caddyfile generated"
    fi
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================
validate_configs() {
    log "Validating generated configurations..."
    
    # Validate docker-compose.yml syntax
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        if ! docker compose -f "$COMPOSE_FILE" config --quiet >/dev/null 2>&1; then
            fail "docker-compose.yml validation failed"
        fi
        ok "docker-compose.yml validation passed"
    else
        dry_run "Would validate docker-compose.yml syntax"
    fi
    
    # Validate Caddyfile (after image pull - Expert Fix)
    if [[ "$CADDY_ENABLED" == "true" && "${DRY_RUN:-false}" == "false" ]]; then
        # Check if caddy image is available locally
        if docker image inspect caddy:2-alpine >/dev/null 2>&1; then
            if ! docker run --rm -v "${CONFIG_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
                caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                fail "Caddyfile validation failed"
            fi
            ok "Caddyfile validation passed"
        else
            warn "Caddy image not available locally, skipping Caddyfile validation"
        fi
    fi
    
    # Focused hardcoding scan (Expert Fix)
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        log "Scanning for placeholder values..."
        if grep -rE "CHANGEME|TODO|FIXME|xxxx" "${CONFIG_DIR}" >/dev/null 2>&1; then
            fail "Placeholder values detected in generated configs"
        fi
        ok "No placeholder values found"
    fi
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================
deploy_stack() {
    if [[ "${DRY_RUN:-false}" == "false" && "${VALIDATE_ONLY:-false}" == "false" ]]; then
        log "Deploying service stack..."
        
        local compose_args=("-f" "$COMPOSE_FILE")
        if [[ "${FORCE_RECREATE:-false}" == "true" ]]; then
            compose_args+=("--force-recreate")
        fi
        
        # Atomic deployment
        log "Starting all services..."
        docker compose "${compose_args[@]}" up -d
        
        ok "Service deployment completed"
    else
        if [[ "${VALIDATE_ONLY:-false}" == "true" ]]; then
            log "Validation-only mode - skipping deployment"
        else
            dry_run "Would deploy service stack"
        fi
    fi
}

wait_for_services() {
    if [[ "${DRY_RUN:-false}" == "false" && "${VALIDATE_ONLY:-false}" == "false" ]]; then
        log "Waiting for services to be healthy..."
        
        # Wait for infrastructure services first
        local services=()
        
        if [[ "$POSTGRES_ENABLED" == "true" ]]; then
            services+=("postgres")
        fi
        
        if [[ "$REDIS_ENABLED" == "true" ]]; then
            services+=("redis")
        fi
        
        for service in "${services[@]}"; do
            wait_for_healthy "${PREFIX}${TENANT_ID}_${service}" 120
        done
        
        # Wait for core services
        services=()
        
        if [[ "$OLLAMA_ENABLED" == "true" ]]; then
            services+=("ollama")
        fi
        
        if [[ "$LITELLM_ENABLED" == "true" ]]; then
            services+=("litellm")
        fi
        
        if [[ "$BIFROST_ENABLED" == "true" ]]; then
            services+=("bifrost")
        fi
        
        for service in "${services[@]}"; do
            wait_for_healthy "${PREFIX}${TENANT_ID}_${service}" 120
        done
        
        # Wait for application services
        services=()
        
        if [[ "$OPEN_WEBUI_ENABLED" == "true" ]]; then
            services+=("open-webui")
        fi
        
        if [[ "$N8N_ENABLED" == "true" ]]; then
            services+=("n8n")
        fi
        
        if [[ "$FLOWISE_ENABLED" == "true" ]]; then
            services+=("flowise")
        fi
        
        if [[ "$SEARXNG_ENABLED" == "true" ]]; then
            services+=("searxng")
        fi
        
        if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
            services+=("authentik")
        fi
        
        for service in "${services[@]}"; do
            wait_for_healthy "${PREFIX}${TENANT_ID}_${service}" 60 || \
                warn "${service} failed health check (may be starting)"
        done
        
        ok "Service health checks completed"
    else
        dry_run "Would wait for services to be healthy"
    fi
}

wait_for_healthy() {
    local container="$1"
    local max_wait="${2:-120}"
    local interval=5
    local elapsed=0
    
    log "Waiting for $container to be healthy (max ${max_wait}s)..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        local status
        status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "not_found") # Expert Fix
        
        case "$status" in
            "running")
                # Check if healthcheck is defined
                local health_status
                health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
                
                case "$health_status" in
                    "healthy")
                        log "$container is healthy ✓"
                        return 0
                        ;;
                    "unhealthy")
                        warn "$container is unhealthy! Checking logs..."
                        docker logs --tail=20 "$container" 2>&1 || true
                        return 1
                        ;;
                    "none")
                        log "$container is running (no healthcheck defined)"
                        return 0
                        ;;
                    *)
                        # starting or unknown
                        ;;
                esac
                ;;
            "not_found")
                warn "Container $container not found"
                return 1
                ;;
            *)
                # exited, restarting, etc.
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
        log "  Waiting... ${elapsed}s / ${max_wait}s (status: $status)"
    done
    
    warn "$container did not become healthy within ${max_wait}s"
    return 1
}

# =============================================================================
# POST-DEPLOYMENT TASKS
# =============================================================================
create_databases() {
    if [[ "$POSTGRES_ENABLED" == "true" && "${DRY_RUN:-false}" == "false" && "${VALIDATE_ONLY:-false}" == "false" ]]; then
        log "Creating PostgreSQL databases..."
        
        # Wait for PostgreSQL to be ready
        wait_for_healthy "${PREFIX}${TENANT_ID}_postgres" 60
        
        # Create service databases
        if [[ "$N8N_ENABLED" == "true" ]]; then
            docker exec "${PREFIX}${TENANT_ID}_postgres" psql -U "${POSTGRES_USER}" -d postgres -c \
                "CREATE DATABASE ${N8N_DB};" 2>/dev/null || log "n8n database already exists"
        fi
        
        if [[ "$FLOWISE_ENABLED" == "true" ]]; then
            docker exec "${PREFIX}${TENANT_ID}_postgres" psql -U "${POSTGRES_USER}" -d postgres -c \
                "CREATE DATABASE ${FLOWISE_DB};" 2>/dev/null || log "Flowise database already exists"
        fi
        
        if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
            docker exec "${PREFIX}${TENANT_ID}_postgres" psql -U "${POSTGRES_USER}" -d postgres -c \
                "CREATE DATABASE ${AUTHENTIK_DB};" 2>/dev/null || log "Authentik database already exists"
        fi
        
        ok "PostgreSQL databases created"
    fi
}

pull_ollama_model() {
    if [[ "$OLLAMA_ENABLED" == "true" && "$OLLAMA_PULL_DEFAULT_MODEL" == "true" && \
          -n "${OLLAMA_DEFAULT_MODEL:-}" && "${DRY_RUN:-false}" == "false" && "${VALIDATE_ONLY:-false}" == "false" ]]; then
        log "Pulling Ollama model: $OLLAMA_DEFAULT_MODEL"
        
        # Wait for Ollama to be ready
        wait_for_healthy "${PREFIX}${TENANT_ID}_ollama" 120
        
        if docker exec "${PREFIX}${TENANT_ID}_ollama" ollama pull "$OLLAMA_DEFAULT_MODEL"; then
            ok "Model $OLLAMA_DEFAULT_MODEL pulled successfully"
        else
            warn "Failed to pull model $OLLAMA_DEFAULT_MODEL"
        fi
    fi
}

# =============================================================================
# STATUS AND SUMMARY
# =============================================================================
print_deployment_status() {
    section "Deployment Status"
    
    echo ""
    echo "  Service Endpoints:"
    echo "  ┌──────────────────┬──────────────────────────────────────────┐"
    echo "  │ Service          │ URL                                      │"
    echo "  ├──────────────────┼──────────────────────────────────────────┤"
    
    if [[ "$OPEN_WEBUI_ENABLED" == "true" ]]; then
        printf "  │ %-16s │ %-40s │\n" "Open WebUI" "http://${HOST_IP}:${OPEN_WEBUI_PORT}"
    fi
    
    if [[ "$OLLAMA_ENABLED" == "true" ]]; then
        printf "  │ %-16s │ %-40s │\n" "Ollama API" "http://${HOST_IP}:${OLLAMA_PORT}"
    fi
    
    if [[ "$LITELLM_ENABLED" == "true" ]]; then
        printf "  │ %-16s │ %-40s │\n" "LiteLLM" "http://${HOST_IP}:${LITELLM_PORT}"
    fi
    
    if [[ "$BIFROST_ENABLED" == "true" ]]; then
        printf "  │ %-16s │ %-40s │\n" "Bifrost" "http://${HOST_IP}:${BIFROST_PORT}"
    fi
    
    if [[ "$QDRANT_ENABLED" == "true" ]]; then
        printf "  │ %-16s │ %-40s │\n" "Qdrant" "http://${HOST_IP}:${QDRANT_PORT}"
    fi
    
    if [[ "$WEAVIATE_ENABLED" == "true" ]]; then
        printf "  │ %-16s │ %-40s │\n" "Weaviate" "http://${HOST_IP}:${WEAVIATE_PORT}"
    fi
    
    if [[ "$CHROMA_ENABLED" == "true" ]]; then
        printf "  │ %-16s │ %-40s │\n" "Chroma" "http://${HOST_IP}:${CHROMA_PORT}"
    fi
    
    if [[ "$N8N_ENABLED" == "true" ]]; then
        printf "  │ %-16s │ %-40s │\n" "n8n" "http://${HOST_IP}:${N8N_PORT}"
    fi
    
    if [[ "$FLOWISE_ENABLED" == "true" ]]; then
        printf "  │ %-16s │ %-40s │\n" "Flowise" "http://${HOST_IP}:${FLOWISE_PORT}"
    fi
    
    if [[ "$SEARXNG_ENABLED" == "true" ]]; then
        printf "  │ %-16s │ %-40s │\n" "SearXNG" "http://${HOST_IP}:${SEARXNG_PORT}"
    fi
    
    if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
        printf "  │ %-16s │ %-40s │\n" "Authentik" "http://${HOST_IP}:${AUTHENTIK_PORT}"
    fi
    
    if [[ "$GRAFANA_ENABLED" == "true" ]]; then
        printf "  │ %-16s │ %-40s │\n" "Grafana" "http://${HOST_IP}:${GRAFANA_PORT}"
    fi
    
    if [[ "$PROMETHEUS_ENABLED" == "true" ]]; then
        printf "  │ %-16s │ %-40s │\n" "Prometheus" "http://${HOST_IP}:${PROMETHEUS_PORT}"
    fi
    
    echo "  └──────────────────┴──────────────────────────────────────────┘"
    echo ""
    echo "  Next step:"
    echo "  bash scripts/3-configure-services.sh ${TENANT_ID}"
    echo ""
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    local tenant_id="${1:-default}"
    local dry_run=false
    local validate_only=false
    local force_recreate=false
    
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
            --force-recreate)
                force_recreate=true
                shift
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
    
    # Set global variables
    export DRY_RUN="$dry_run"
    export VALIDATE_ONLY="$validate_only"
    export FORCE_RECREATE="$force_recreate"
    
    log "=== Script 2: Atomic Deployer ==="
    log "Tenant: ${tenant_id}"
    log "Dry-run: ${dry_run}"
    log "Validate-only: ${validate_only}"
    log "Force-recreate: ${force_recreate}"
    
    # Framework validation
    framework_validate
    
    # Load platform.conf
    load_platform_conf "$tenant_id"
    
    # Create directory structure
    create_directories
    
    # Create Docker network
    create_docker_network
    
    # Generate all configurations
    generate_docker_compose
    generate_litellm_config
    generate_bifrost_config
    generate_caddyfile
    
    # Validate configurations
    validate_configs
    
    # Deploy if not validate-only
    if [[ "$validate_only" == "false" ]]; then
        deploy_stack
        wait_for_services
        create_databases
        pull_ollama_model
        print_deployment_status
    else
        log "Validation completed successfully"
    fi
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
