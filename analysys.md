Let me read the current scripts to give Windsurf precise, actionable fixes.
<tool_call>
{"name": "web_fetch", "parameters": {"url": "https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh"}}
</tool_call>
<tool_response>
#!/usr/bin/env bash
# =============================================================================
# Script 2: Deploy Services
# =============================================================================
# PURPOSE: Generate docker-compose.yml and bring up all enabled services
# USAGE:   sudo bash scripts/2-deploy-services.sh
# =============================================================================

set -euo pipefail

# ─── Source environment ───────────────────────────────────────────────────────
DATA_ROOT="/opt/ai-platform"
ENV_FILE="${DATA_ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "❌  ${ENV_FILE} not found — run script 1 first"
    exit 1
fi

source "${ENV_FILE}"

# ─── Colours ─────────────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "  ${GREEN}✅  $*${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠️   $*${NC}"; }
error() { echo -e "  ${RED}❌  $*${NC}"; }
info()  { echo -e "  ${CYAN}ℹ️   $*${NC}"; }

# ─── Paths ────────────────────────────────────────────────────────────────────
COMPOSE_DIR="${DATA_ROOT}/compose"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
CADDY_DIR="${DATA_ROOT}/caddy"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Guard: must have docker ──────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    error "Docker not found — run script 1 first"; exit 1
fi

# ─── Header ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}${BOLD}              🚀  AI Platform — Deploy Services               ${NC}${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ─── Write compose header ────────────────────────────────────────────────────
write_compose_header() {
    mkdir -p "${COMPOSE_DIR}"
    cat > "${COMPOSE_FILE}" << 'EOF'
services:
EOF
}

# ─── Helpers ─────────────────────────────────────────────────────────────────
append() { cat >> "${COMPOSE_FILE}"; }

# ─── Core: Caddy ─────────────────────────────────────────────────────────────
append_caddy() {
    append << 'EOF'

  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    networks:
      - platform
    volumes:
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:2019/metrics"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      com.ai-platform: "true"
EOF
}

# ─── Core: PostgreSQL ─────────────────────────────────────────────────────────
append_postgres() {
    append << EOF

  postgres:
    image: postgres:16-alpine
    container_name: postgres
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init-scripts:/docker-entrypoint-initdb.d:ro
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: platform
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d platform"]
      interval: 10s
      timeout: 5s
      retries: 5
    labels:
      com.ai-platform: "true"
EOF
}

# ─── Core: Redis ──────────────────────────────────────────────────────────────
append_redis() {
    append << 'EOF'

  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - redis_data:/data
    command: redis-server --appendonly yes --maxmemory 512mb --maxmemory-policy allkeys-lru
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    labels:
      com.ai-platform: "true"
EOF
}

# ─── Ollama ───────────────────────────────────────────────────────────────────
append_ollama() {
    local gpu_section=""

    case "${GPU_TYPE:-none}" in
        nvidia)
            gpu_section=$(cat << 'EOF'
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
            )
            ;;
        amd)
            gpu_section=$(cat << 'EOF'
    devices:
      - /dev/kfd:/dev/kfd
      - /dev/dri:/dev/dri
    group_add:
      - video
EOF
            )
            ;;
    esac

    append << EOF

  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - ollama_data:/root/.ollama
    ports:
      - "${OLLAMA_PORT:-11434}:11434"
${gpu_section}    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      com.ai-platform: "true"
EOF
}

# ─── Open WebUI ───────────────────────────────────────────────────────────────
append_openwebui() {
    append << EOF

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - openwebui_data:/app/backend/data
    ports:
      - "${OPENWEBUI_PORT:-8080}:8080"
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=\${SECRET_KEY}
      - ENABLE_SIGNUP=true
    depends_on:
      ollama:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      com.ai-platform: "true"
EOF
}

# ─── n8n ─────────────────────────────────────────────────────────────────────
append_n8n() {
    append << EOF

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - n8n_data:/home/node/.n8n
    ports:
      - "${N8N_PORT:-5678}:5678"
    environment:
      - N8N_HOST=n8n.\${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://n8n.\${DOMAIN}
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - N8N_USER_MANAGEMENT_JWT_SECRET=\${N8N_ENCRYPTION_KEY}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=\${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - EXECUTIONS_MODE=regular
      - N8N_LOG_LEVEL=info
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      com.ai-platform: "true"
EOF
}

# ─── Flowise ─────────────────────────────────────────────────────────────────
append_flowise() {
    append << EOF

  flowise:
    image: flowiseai/flowise:latest
    container_name: flowise
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - flowise_data:/root/.flowise
    ports:
      - "${FLOWISE_PORT:-3001}:3000"
    environment:
      - PORT=3000
      - FLOWISE_USERNAME=\${ADMIN_EMAIL}
      - FLOWISE_PASSWORD=\${FLOWISE_PASSWORD}
      - DATABASE_TYPE=postgres
      - DATABASE_HOST=postgres
      - DATABASE_PORT=5432
      - DATABASE_NAME=flowise
      - DATABASE_USER=\${POSTGRES_USER}
      - DATABASE_PASSWORD=\${POSTGRES_PASSWORD}
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/v1/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      com.ai-platform: "true"
EOF
}

# ─── LiteLLM ─────────────────────────────────────────────────────────────────
append_litellm() {
    # Write LiteLLM config file
    local litellm_config_dir="${DATA_ROOT}/litellm"
    mkdir -p "${litellm_config_dir}"

    cat > "${litellm_config_dir}/config.yaml" << EOF
model_list:
  - model_name: ollama/llama3
    litellm_params:
      model: ollama/llama3
      api_base: http://ollama:11434

litellm_settings:
  telemetry: false
  set_verbose: false

general_settings:
  master_key: "${LITELLM_MASTER_KEY:-sk-placeholder}"
EOF

    append << EOF

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - ${litellm_config_dir}/config.yaml:/app/config.yaml:ro
    ports:
      - "${LITELLM_PORT:-4000}:4000"
    environment:
      - LITELLM_MASTER_KEY=\${LITELLM_MASTER_KEY}
      - DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/litellm
      - STORE_MODEL_IN_DB=true
    command: ["--config", "/app/config.yaml", "--port", "4000", "--num_workers", "1"]
    depends_on:
      postgres:
        condition: service_healthy
      ollama:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health/liveliness"]
      interval: 30s
      timeout: 10s
      retries: 5
    labels:
      com.ai-platform: "true"
EOF
}

# ─── Qdrant ───────────────────────────────────────────────────────────────────
append_qdrant() {
    append << EOF

  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - qdrant_data:/qdrant/storage
    ports:
      - "${QDRANT_PORT:-6333}:6333"
      - "6334:6334"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      com.ai-platform: "true"
EOF
}

# ─── AnythingLLM ──────────────────────────────────────────────────────────────
append_anythingllm() {
    append << EOF

  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - anythingllm_data:/app/server/storage
    ports:
      - "${ANYTHINGLLM_PORT:-3002}:3001"
    environment:
      - STORAGE_DIR=/app/server/storage
      - JWT_SECRET=\${ANYTHINGLLM_JWT_SECRET:-\${SECRET_KEY}}
      - LLM_PROVIDER=ollama
      - OLLAMA_BASE_PATH=http://ollama:11434
      - OLLAMA_MODEL_PREF=llama3
      - EMBEDDING_ENGINE=ollama
      - EMBEDDING_MODEL_PREF=nomic-embed-text
      - VECTOR_DB=qdrant
      - QDRANT_ENDPOINT=http://qdrant:6333
      - AUTH_TOKEN=\${ANYTHINGLLM_AUTH_TOKEN:-\${SECRET_KEY}}
    depends_on:
      ollama:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      com.ai-platform: "true"
EOF
}

# ─── Grafana ──────────────────────────────────────────────────────────────────
append_grafana() {
    append << EOF

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "${GRAFANA_PORT:-3003}:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=\${GRAFANA_PASSWORD:-admin}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SERVER_ROOT_URL=https://grafana.\${DOMAIN}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      com.ai-platform: "true"
EOF
}

# ─── Prometheus ───────────────────────────────────────────────────────────────
append_prometheus() {
    local prom_config_dir="${DATA_ROOT}/prometheus"
    mkdir -p "${prom_config_dir}"

    cat > "${prom_config_dir}/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
EOF

    append << EOF

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - ${prom_config_dir}/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    ports:
      - "${PROMETHEUS_PORT:-9090}:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      com.ai-platform: "true"
EOF
}

# ─── Authentik ────────────────────────────────────────────────────────────────
append_authentik() {
    append << EOF

  authentik-server:
    image: ghcr.io/goauthentik/server:latest
    container_name: authentik-server
    restart: unless-stopped
    command: server
    networks:
      - platform
    volumes:
      - authentik_media:/media
      - authentik_templates:/templates
    ports:
      - "${AUTHENTIK_PORT:-9000}:9000"
    environment:
      - AUTHENTIK_REDIS__HOST=redis
      - AUTHENTIK_POSTGRESQL__HOST=postgres
      - AUTHENTIK_POSTGRESQL__USER=\${POSTGRES_USER}
      - AUTHENTIK_POSTGRESQL__PASSWORD=\${POSTGRES_PASSWORD}
      - AUTHENTIK_POSTGRESQL__NAME=authentik
      - AUTHENTIK_SECRET_KEY=\${AUTHENTIK_SECRET_KEY:-\${SECRET_KEY}}
      - AUTHENTIK_ERROR_REPORTING__ENABLED=false
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:9000/-/health/live/"]
      interval: 30s
      timeout: 10s
      retries: 5
    labels:
      com.ai-platform: "true"

  authentik-worker:
    image: ghcr.io/goauthentik/server:latest
    container_name: authentik-worker
    restart: unless-stopped
    command: worker
    networks:
      - platform
    volumes:
      - authentik_media:/media
      - authentik_templates:/templates
    environment:
      - AUTHENTIK_REDIS__HOST=redis
      - AUTHENTIK_POSTGRESQL__HOST=postgres
      - AUTHENTIK_POSTGRESQL__USER=\${POSTGRES_USER}
      - AUTHENTIK_POSTGRESQL__PASSWORD=\${POSTGRES_PASSWORD}
      - AUTHENTIK_POSTGRESQL__NAME=authentik
      - AUTHENTIK_SECRET_KEY=\${AUTHENTIK_SECRET_KEY:-\${SECRET_KEY}}
      - AUTHENTIK_ERROR_REPORTING__ENABLED=false
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    labels:
      com.ai-platform: "true"
EOF
}

# ─── Signal API ───────────────────────────────────────────────────────────────
append_signal() {
    append << EOF

  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-api
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - signal_data:/home/.local/share/signal-cli
    ports:
      - "${SIGNAL_PORT:-8080}:8080"
    environment:
      - MODE=json-rpc
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/v1/about"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      com.ai-platform: "true"
EOF
}

# ─── Dify ────────────────────────────────────────────────────────────────────
append_dify() {
    append << EOF

  dify-api:
    image: langgenius/dify-api:latest
    container_name: dify-api
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - dify_storage:/app/api/storage
    environment:
      - MODE=api
      - LOG_LEVEL=INFO
      - SECRET_KEY=\${SECRET_KEY}
      - DB_USERNAME=\${POSTGRES_USER}
      - DB_PASSWORD=\${POSTGRES_PASSWORD}
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=dify
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - CELERY_BROKER_URL=redis://redis:6379/1
      - STORAGE_TYPE=local
      - STORAGE_LOCAL_PATH=/app/api/storage
      - VECTOR_STORE=qdrant
      - QDRANT_URL=http://qdrant:6333
      - QDRANT_API_KEY=\${QDRANT_API_KEY:-}
      - MIGRATION_ENABLED=true
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5001/health"]
      interval: 30s
      timeout: 10s
      retries: 5
    labels:
      com.ai-platform: "true"

  dify-worker:
    image: langgenius/dify-api:latest
    container_name: dify-worker
    restart: unless-stopped
    command: worker
    networks:
      - platform
    volumes:
      - dify_storage:/app/api/storage
    environment:
      - MODE=worker
      - LOG_LEVEL=INFO
      - SECRET_KEY=\${SECRET_KEY}
      - DB_USERNAME=\${POSTGRES_USER}
      - DB_PASSWORD=\${POSTGRES_PASSWORD}
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=dify
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - CELERY_BROKER_URL=redis://redis:6379/1
      - STORAGE_TYPE=local
      - STORAGE_LOCAL_PATH=/app/api/storage
      - VECTOR_STORE=qdrant
      - QDRANT_URL=http://qdrant:6333
      - QDRANT_API_KEY=\${QDRANT_API_KEY:-}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    labels:
      com.ai-platform: "true"

  dify-web:
    image: langgenius/dify-web:latest
    container_name: dify-web
    restart: unless-stopped
    networks:
      - platform
    ports:
      - "${DIFY_PORT:-3004}:3000"
    environment:
      - CONSOLE_API_URL=https://dify.\${DOMAIN}
      - APP_API_URL=https://dify.\${DOMAIN}
    labels:
      com.ai-platform: "true"

  dify-sandbox:
    image: langgenius/dify-sandbox:latest
    container_name: dify-sandbox
    restart: unless-stopped
    networks:
      - platform
    environment:
      - API_KEY=\${SECRET_KEY}
      - GIN_MODE=release
      - WORKER_TIMEOUT=15
    labels:
      com.ai-platform: "true"

  dify-nginx:
    image: nginx:alpine
    container_name: dify-nginx
    restart: unless-stopped
    networks:
      - platform
    ports:
      - "${DIFY_NGINX_PORT:-8090}:80"
    volumes:
      - ${DATA_ROOT}/dify/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - dify-api
      - dify-web
    labels:
      com.ai-platform: "true"
EOF
}

# ─── Volumes footer ───────────────────────────────────────────────────────────
write_volumes_footer() {
    append << 'EOF'

networks:
  platform:
    name: ai-platform
    driver: bridge

volumes:
  caddy_data:
  caddy_config:
  postgres_data:
  redis_data:
  ollama_data:
  openwebui_data:
  n8n_data:
  flowise_data:
  litellm_data:
  anythingllm_data:
  qdrant_data:
  grafana_data:
  prometheus_data:
  authentik_media:
  authentik_templates:
  signal_data:
  dify_storage:
EOF
}

# ─── Init SQL scripts ─────────────────────────────────────────────────────────
write_init_scripts() {
    local init_dir="${COMPOSE_DIR}/init-scripts"
    mkdir -p "${init_dir}"

    cat > "${init_dir}/01-create-databases.sql" << 'EOF'
SELECT 'CREATE DATABASE n8n'        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n')\gexec
SELECT 'CREATE DATABASE flowise'    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'flowise')\gexec
SELECT 'CREATE DATABASE litellm'    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'litellm')\gexec
SELECT 'CREATE DATABASE authentik'  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'authentik')\gexec
SELECT 'CREATE DATABASE dify'       WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'dify')\gexec
SELECT 'CREATE DATABASE openwebui'  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'openwebui')\gexec
EOF
}

# ─── Caddyfile ────────────────────────────────────────────────────────────────
write_caddyfile() {
    mkdir -p "${CADDY_DIR}"
    local caddyfile="${CADDY_DIR}/Caddyfile"

    # Start with global options
    cat > "${caddyfile}" << EOF
{
    admin off
    email ${ADMIN_EMAIL}
}

EOF

    # Add routes only for enabled services
    [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]]   && cat >> "${caddyfile}" << EOF
openwebui.${DOMAIN} {
    reverse_proxy open-webui:8080
}

EOF

    [[ "${ENABLE_N8N:-false}" == "true" ]]         && cat >> "${caddyfile}" << EOF
n8n.${DOMAIN} {
    reverse_proxy n8n:5678
}

EOF

    [[ "${ENABLE_FLOWISE:-false}" == "true" ]]     && cat >> "${caddyfile}" << EOF
flowise.${DOMAIN} {
    reverse_proxy flowise:3000
}

EOF

    [[ "${ENABLE_LITELLM:-false}" == "true" ]]     && cat >> "${caddyfile}" << EOF
litellm.${DOMAIN} {
    reverse_proxy litellm:4000
}

EOF

    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && cat >> "${caddyfile}" << EOF
anythingllm.${DOMAIN} {
    reverse_proxy anythingllm:3001
}

EOF

    [[ "${ENABLE_GRAFANA:-false}" == "true" ]]     && cat >> "${caddyfile}" << EOF
grafana.${DOMAIN} {
    reverse_proxy grafana:3000
}

EOF

    [[ "${ENABLE_OLLAMA:-false}" == "true" ]]      && cat >> "${caddyfile}" << EOF
ollama.${DOMAIN} {
    reverse_proxy ollama:11434
}

EOF

    [[ "${ENABLE_QDRANT:-false}" == "true" ]]      && cat >> "${caddyfile}" << EOF
qdrant.${DOMAIN} {
    reverse_proxy qdrant:6333
}

EOF

    [[ "${ENABLE_AUTHENTIK:-false}" == "true" ]]   && cat >> "${caddyfile}" << EOF
auth.${DOMAIN} {
    reverse_proxy authentik-server:9000
}

EOF

    [[ "${ENABLE_DIFY:-false}" == "true" ]]        && cat >> "${caddyfile}" << EOF
dify.${DOMAIN} {
    reverse_proxy dify-nginx:80
}

EOF

    [[ "${ENABLE_SIGNAL:-false}" == "true" ]]      && cat >> "${caddyfile}" << EOF
signal.${DOMAIN} {
    reverse_proxy signal-api:8080
}

EOF
}

# ─── Dify nginx config ────────────────────────────────────────────────────────
write_dify_nginx_config() {
    if [[ "${ENABLE_DIFY:-false}" != "true" ]]; then return; fi

    local dify_dir="${DATA_ROOT}/dify"
    mkdir -p "${dify_dir}"

    cat > "${dify_dir}/nginx.conf" << 'EOF'
events { worker_connections 1024; }

http {
    upstream dify_api {
        server dify-api:5001;
    }
    upstream dify_web {
        server dify-web:3000;
    }

    server {
        listen 80;

        location /console/api {
            proxy_pass http://dify_api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
        location /api {
            proxy_pass http://dify_api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
        location /v1 {
            proxy_pass http://dify_api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
        location /files {
            proxy_pass http://dify_api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
        location / {
            proxy_pass http://dify_web;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF
}

# ─── Wait for a container to be healthy ──────────────────────────────────────
wait_healthy() {
    local name="${1}" timeout="${2:-120}"
    info "Waiting for ${name} to be healthy…"
    local i=0
    while [[ $i -lt $timeout ]]; do
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "${name}" 2>/dev/null || echo "missing")
        case "${status}" in
            healthy) log "${name} is healthy"; return 0 ;;
            missing|"") warn "${name} not found yet…" ;;
            *) : ;;
        esac
        sleep 5
        (( i += 5 ))
    done
    warn "${name} did not become healthy within ${timeout}s — continuing anyway"
}

# ─── Pull images ──────────────────────────────────────────────────────────────
pull_images() {
    info "Pulling images (this may take a while)…"
    docker compose -f "${COMPOSE_FILE}" pull --quiet 2>/dev/null || true
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    info "Building compose configuration…"
    write_compose_header
    write_init_scripts

    # Always: core infrastructure
    append_caddy
    append_postgres
    append_redis

    # Conditional services
    [[ "${ENABLE_OLLAMA:-false}"      == "true" ]] && append_ollama
    [[ "${ENABLE_OPENWEBUI:-false}"   == "true" ]] && append_openwebui
    [[ "${ENABLE_N8N:-false}"         == "true" ]] && append_n8n
    [[ "${ENABLE_FLOWISE:-false}"     == "true" ]] && append_flowise
    [[ "${ENABLE_LITELLM:-false}"     == "true" ]] && append_litellm
    [[ "${ENABLE_QDRANT:-false}"      == "true" ]] && append_qdrant
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && append_anythingllm
    [[ "${ENABLE_GRAFANA:-false}"     == "true" ]] && append_grafana
    [[ "${ENABLE_PROMETHEUS:-false}"  == "true" ]] && append_prometheus
    [[ "${ENABLE_AUTHENTIK:-false}"   == "true" ]] && append_authentik
    [[ "${ENABLE_SIGNAL:-false}"      == "true" ]] && append_signal
    [[ "${ENABLE_DIFY:-false}"        == "true" ]] && append_dify

    write_volumes_footer
    write_caddyfile
    write_dify_nginx_config

    log "Compose file written to ${COMPOSE_FILE}"

    pull_images

    info "Starting infrastructure layer…"
    docker compose -f "${COMPOSE_FILE}" up -d postgres redis
    wait_healthy postgres 60
    wait_healthy redis 30

    info "Starting Caddy…"
    docker compose -f "${COMPOSE_FILE}" up -d caddy

    if [[ "${ENABLE_OLLAMA:-false}" == "true" ]]; then
        info "Starting Ollama…"
        docker compose -f "${COMPOSE_FILE}" up -d ollama
        wait_healthy ollama 120
    fi

    info "Starting application services…"
    docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans

    echo ""
    log "Deployment complete"
    echo ""
    info "Service URLs:"
    [[ "${ENABLE_OPENWEBUI:-false}"   == "true" ]] && echo "    🌐  Open WebUI    → https://openwebui.${DOMAIN}"
    [[ "${ENABLE_N8N:-false}"         == "true" ]] && echo "    🔄  n8n           → https://n8n.${DOMAIN}"
    [[ "${ENABLE_FLOWISE:-false}"     == "true" ]] && echo "    🌊  Flowise        → https://flowise.${DOMAIN}"
    [[ "${ENABLE_LITELLM:-false}"     == "true" ]] && echo "    🔀  LiteLLM        → https://litellm.${DOMAIN}"
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && echo "    🤖  AnythingLLM   → https://anythingllm.${DOMAIN}"
    [[ "${ENABLE_GRAFANA:-false}"     == "true" ]] && echo "    📈  Grafana        → https://grafana.${DOMAIN}"
    [[ "${ENABLE_OLLAMA:-false}"      == "true" ]] && echo "    🦙  Ollama         → https://ollama.${DOMAIN}"
    [[ "${ENABLE_QDRANT:-false}"      == "true" ]] && echo "    🗄️   Qdrant         → https://qdrant.${DOMAIN}"
    [[ "${ENABLE_AUTHENTIK:-false}"   == "true" ]] && echo "    🔑  Authentik      → https://auth.${DOMAIN}"
    [[ "${ENABLE_DIFY:-false}"        == "true" ]] && echo "    🏗️   Dify            → https://dify.${DOMAIN}"
    [[ "${ENABLE_SIGNAL:-false}"      == "true" ]] && echo "    📱  Signal API     → https://signal.${DOMAIN}"
    echo ""
    info "Check status: docker compose -f ${COMPOSE_FILE} ps"
}

main "$@"
</tool_response>

Now I have the full picture. Here is the complete, precise fix guide for Windsurf.

---

# 🔧 Windsurf Fix Instructions — Remaining Issues After Successful Deployment

## Current Status Summary

| Service | Status | Issue |
|---|---|---|
| n8n | ✅ Fully working | — |
| Flowise | ✅ Fully working | — |
| Open WebUI | ✅ Fully working | — |
| AnythingLLM | ✅ Fully working | — |
| Grafana | ✅ Fully working | — |
| Ollama | ✅ Fully working | — |
| PostgreSQL | ✅ Fully working | — |
| Redis | ✅ Fully working | — |
| **LiteLLM** | ⚠️ Running but unhealthy | Wrong health endpoint → Docker reports unhealthy forever |
| **Qdrant** | ⚠️ Running but unhealthy | Wrong health endpoint → Docker reports unhealthy forever |
| **Open WebUI domain** | ⚠️ Doc/Caddy mismatch | `chat.` subdomain referenced in old docs, actual is `openwebui.` |
| **Prometheus** | ⚠️ Silent scrape failure | Scrapes `node-exporter:9100` which is never deployed |
| **Dify** | ❌ Not tested yet | Was not in the enabled stack for this run |
| **Signal API** | ❌ Requires manual step | By design — needs phone registration |

---

## Fix 1 — LiteLLM: Wrong Health Check Endpoint

**File:** `scripts/2-deploy-services.sh` → `append_litellm()`

**Problem:** `/health/liveliness` returns HTTP 401 (requires `Authorization: Bearer <master_key>` header). Docker marks container permanently unhealthy. The correct unauthenticated endpoint is `/health/readiness`.

**Exact change** — find this block inside `append_litellm()`:

```yaml
# ❌ REMOVE THIS
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health/liveliness"]
      interval: 30s
      timeout: 10s
      retries: 5
```

Replace with:

```yaml
# ✅ REPLACE WITH THIS
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:4000/health/readiness"]
      interval: 30s
      timeout: 15s
      start_period: 60s
      retries: 5
```

> **Why `start_period: 60s`?** LiteLLM runs Alembic DB migrations on cold start which takes 30–50 seconds. Without `start_period`, Docker counts those failures against `retries` and kills the container before it finishes starting.

---

## Fix 2 — Qdrant: Wrong Health Check Endpoint

**File:** `scripts/2-deploy-services.sh` → `append_qdrant()`

**Problem:** `/healthz` returns HTTP 404. Qdrant's actual health endpoint is `/` (root) which returns `{"title":"qdrant","version":"..."}` with HTTP 200.

**Exact change** — find this block inside `append_qdrant()`:

```yaml
# ❌ REMOVE THIS
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
```

Replace with:

```yaml
# ✅ REPLACE WITH THIS
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:6333/"]
      interval: 30s
      timeout: 10s
      start_period: 20s
      retries: 3
```

---

## Fix 3 — Prometheus: Scrape Target `node-exporter` Never Exists

**File:** `scripts/2-deploy-services.sh` → `append_prometheus()` → the inline `prometheus.yml`

**Problem:** The generated `prometheus.yml` includes a scrape job for `node-exporter:9100` but `node-exporter` is never deployed as a container. Prometheus logs continuous scrape errors and Grafana shows no system metrics.

**Two-part fix:**

**Part A** — Add `node-exporter` as a companion container inside `append_prometheus()`, right after the prometheus service block:

```bash
append_prometheus() {
    local prom_config_dir="${DATA_ROOT}/prometheus"
    mkdir -p "${prom_config_dir}"

    cat > "${prom_config_dir}/prometheus.yml" << 'PROMEOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
PROMEOF

    append << EOF

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - ${prom_config_dir}/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    ports:
      - "${PROMETHEUS_PORT:-9090}:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      com.ai-platform: "true"

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    networks:
      - platform
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    labels:
      com.ai-platform: "true"
EOF
}
```

**Part B** — Add `node_exporter_data` to the cleanup script volumes list in `0-complete-cleanup.sh` (it needs no named volume but add `node-exporter` to the label-based container removal — it already handles this via the label filter, nothing extra needed).

---

## Fix 4 — Open WebUI: Caddy Subdomain Standardisation

**File:** `scripts/2-deploy-services.sh` → `write_caddyfile()`

**Problem:** The report shows `openwebui.ai.datasquiz.net` works, but any existing documentation/script still references `chat.${DOMAIN}`. The Caddyfile currently uses `openwebui.${DOMAIN}` which is correct. The fix is to ensure **script 1's summary display** and the **post-deploy URL output** in `main()` both print `openwebui.` not `chat.`.

**In `main()` of `2-deploy-services.sh`**, confirm this line reads:
```bash
# ✅ Already correct — verify it reads openwebui not chat
[[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] && echo "    🌐  Open WebUI    → https://openwebui.${DOMAIN}"
```

**Also check `scripts/1-setup-system.sh` `print_summary()`** — if it prints `chat.${DOMAIN}` anywhere, change it to `openwebui.${DOMAIN}`.

---

## Fix 5 — LiteLLM: `start_period` Missing Causes Restart Loop on Fresh Deploy

**Problem:** On a clean deploy (no existing DB), LiteLLM runs Alembic migrations for ~45 seconds. Docker's health check starts immediately and hits `retries: 5` × 10s = 50s window. The container gets marked `unhealthy` and `restart: unless-stopped` doesn't restart it — but dependent service ordering in future scripts will fail.

This is already covered by the `start_period: 60s` in Fix 1 above — no additional change needed beyond that.

---

## Fix 6 — AnythingLLM: Shell Variable Expansion Bug in `append_anythingllm()`

**File:** `scripts/2-deploy-services.sh` → `append_anythingllm()`

**Problem:** This line uses `:-` fallback inside a double-quoted heredoc with `\${}` escaping:

```bash
      - JWT_SECRET=\${ANYTHINGLLM_JWT_SECRET:-\${SECRET_KEY}}
```

Inside a `<< EOF` (not `<< 'EOF'`) heredoc, bash tries to expand `${ANYTHINGLLM_JWT_SECRET:-${SECRET_KEY}}` **at script generation time**, not at Docker runtime. If `ANYTHINGLLM_JWT_SECRET` is unset in the shell environment when script 2 runs, the fallback works — but the resulting compose file will contain the **literal secret value** rather than a `${VAR}` reference, meaning re-runs or `.env` changes won't be picked up.

The correct fix is to ensure `ANYTHINGLLM_JWT_SECRET` is always set in `.env` by script 1, then reference it cleanly:

**In `scripts/1-setup-system.sh` → `generate_secrets()`**, add:
```bash
ANYTHINGLLM_JWT_SECRET="$(openssl rand -hex 32)"
ANYTHINGLLM_AUTH_TOKEN="$(openssl rand -hex 32)"
```

**In `scripts/2-deploy-services.sh` → `append_anythingllm()`**, change:
```yaml
# ❌ REMOVE
      - JWT_SECRET=\${ANYTHINGLLM_JWT_SECRET:-\${SECRET_KEY}}
      - AUTH_TOKEN=\${ANYTHINGLLM_AUTH_TOKEN:-\${SECRET_KEY}}

# ✅ REPLACE WITH (clean references, no fallback needed since script 1 guarantees them)
      - JWT_SECRET=\${ANYTHINGLLM_JWT_SECRET}
      - AUTH_TOKEN=\${ANYTHINGLLM_AUTH_TOKEN}
```

---

## Fix 7 — Script 4 (`4-add-service.sh`): Shebang Typo

**File:** `scripts/4-add-service.sh` line 1

```bash
# ❌ CURRENT (broken — space after !)
#!/usr/bin/en bash

# ✅ CORRECT
#!/usr/bin/env bash
```

This will silently fail on any system where `/usr/bin/en` doesn't exist. Change `en` → `env`.

---

## Fix 8 — Script 4: Missing `append_openwebui` Function

**File:** `scripts/4-add-service.sh`

**Problem:** The service menu includes `open-webui` and the `case` statement routes to `append_openwebui` — but that function is **never defined** in script 4. It will throw `command not found`.

**Add this function** in script 4, after `append_ollama()`:

```bash
append_openwebui() {
    cat >> "${COMPOSE_FILE}" << EOF
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - openwebui_data:/app/backend/data
    ports:
      - "${OPENWEBUI_PORT:-8080}:8080"
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=${SECRET_KEY}
      - ENABLE_SIGNUP=true
    depends_on:
      ollama:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      com.ai-platform: "true"
EOF
}
```

---

## Fix 9 — Cleanup Script: Missing Dify Nginx Config Directory

**File:** `scripts/0-complete-cleanup.sh`

**Problem:** Script 2 creates `${DATA_ROOT}/dify/nginx.conf`. The cleanup script removes `${DATA_ROOT}` with `rm -rf` which handles it — **but** the volume `dify_storage` must be in the named volumes list.

**Verify** `0-complete-cleanup.sh` has `dify_storage` in its volume removal loop. Currently it does — ✅ no change needed.

However, add `node-exporter` to the container label removal — it already uses the label filter `com.ai-platform=true` which node-exporter has, so ✅ also handled.

---

## Summary Table for Windsurf

| Fix # | File | Location | Type | Priority |
|---|---|---|---|---|
| 1 | `2-deploy-services.sh` | `append_litellm()` healthcheck | Change endpoint + add `start_period` | **High** |
| 2 | `2-deploy-services.sh` | `append_qdrant()` healthcheck | Change endpoint + add `start_period` | **High** |
| 3 | `2-deploy-services.sh` | `append_prometheus()` | Add `node-exporter` container + fix yml | **Medium** |
| 4 | `2-deploy-services.sh` | `write_caddyfile()` + `main()` | Verify `openwebui.` not `chat.` | **Low** |
| 5 | `1-setup-system.sh` | `generate_secrets()` | Add `ANYTHINGLLM_JWT_SECRET` + `AUTH_TOKEN` | **Medium** |
| 6 | `2-deploy-services.sh` | `append_anythingllm()` | Remove `:-` fallback, use clean `\${VAR}` | **Medium** |
| 7 | `4-add-service.sh` | Line 1 shebang | `en` → `env` | **High** |
| 8 | `4-add-service.sh` | After `append_ollama()` | Add missing `append_openwebui()` function | **High** |