#!/bin/bash
# 2-deploy-services.sh - Service deployment orchestrator

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_ROOT="/mnt/data"
METADATA_DIR="$DATA_ROOT/metadata"
COMPOSE_DIR="$DATA_ROOT/compose"
ENV_DIR="$DATA_ROOT/env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

show_banner() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════╗
║  🚀 AIPlatformAutomation - Service Deployment v76.5   ║
╚════════════════════════════════════════════════════════╝
EOF
}

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Check if setup was completed
    if [ ! -f "$METADATA_DIR/selected_services.json" ]; then
        log_error "System setup not completed. Run ./1-setup-system.sh first"
        exit 1
    fi
    
    # Detect real user
    if [ -n "${SUDO_USER:-}" ]; then
        REAL_USER="$SUDO_USER"
    else
        REAL_USER="$USER"
    fi
    
    PUID=$(id -u "$REAL_USER")
    PGID=$(id -g "$REAL_USER")
    
    log_info "Deploying as: $REAL_USER (UID=$PUID, GID=$PGID)"
}

load_configuration() {
    log_step "📖 Loading configuration..."
    
    # Load metadata
    SELECTED_SERVICES=($(jq -r '.applications[]' "$METADATA_DIR/selected_services.json"))
    DOMAIN=$(jq -r '.domain' "$METADATA_DIR/network_config.json")
    PROXY_TYPE=$(jq -r '.proxy_type' "$METADATA_DIR/network_config.json")
    VECTORDB_TYPE=$(jq -r '.type' "$METADATA_DIR/vectordb_config.json" 2>/dev/null || echo "none")
    GPU_AVAILABLE=$(jq -r '.gpu.available' "$METADATA_DIR/system_info.json")
    SIGNAL_ENABLED=$(jq -r '.enabled' "$METADATA_DIR/signal_config.json" 2>/dev/null || echo "false")
    
    log_info "Services to deploy: ${#SELECTED_SERVICES[@]}"
    log_info "Domain: $DOMAIN"
    log_info "Vector DB: $VECTORDB_TYPE"
    log_info "GPU: $GPU_AVAILABLE"
}

# =====================================================
# COMPOSE FILE GENERATORS
# =====================================================

generate_postgres_compose() {
    log_info "Generating PostgreSQL compose..."
    
    cat > "$COMPOSE_DIR/postgres.yml" << 'EOCOMPOSE'
version: '3.8'

services:
  postgres:
    image: pgvector/pgvector:pg16
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-aiplatform}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB:-aiplatform}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - /mnt/data/data/postgres:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-aiplatform}"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  ai-platform:
    name: ai-platform
    driver: bridge
EOCOMPOSE

    # Generate .env
    cat > "$ENV_DIR/postgres.env" << EOENV
POSTGRES_USER=aiplatform
POSTGRES_PASSWORD=$(openssl rand -base64 32)
POSTGRES_DB=aiplatform
EOENV

    log_info "✅ PostgreSQL configuration ready"
}

generate_redis_compose() {
    log_info "Generating Redis compose..."
    
    cat > "$COMPOSE_DIR/redis.yml" << 'EOCOMPOSE'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}
    volumes:
      - /mnt/data/data/redis:/data
    ports:
      - "6379:6379"
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  ai-platform:
    external: true
EOCOMPOSE

    cat > "$ENV_DIR/redis.env" << EOENV
REDIS_PASSWORD=$(openssl rand -base64 32)
EOENV

    log_info "✅ Redis configuration ready"
}

generate_vectordb_compose() {
    case $VECTORDB_TYPE in
        qdrant)
            log_info "Generating Qdrant compose..."
            
            QDRANT_API_KEY=$(jq -r '.api_key // ""' "$METADATA_DIR/vectordb_config.json")
            
            cat > "$COMPOSE_DIR/qdrant.yml" << EOCOMPOSE
version: '3.8'

services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    environment:
      QDRANT__SERVICE__API_KEY: ${QDRANT_API_KEY}
    volumes:
      - /mnt/data/data/qdrant:/qdrant/storage
    ports:
      - "6333:6333"
      - "6334:6334"
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/health"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  ai-platform:
    external: true
EOCOMPOSE

            cat > "$ENV_DIR/qdrant.env" << EOENV
QDRANT_API_KEY=${QDRANT_API_KEY:-$(openssl rand -base64 32)}
EOENV
            ;;
            
        milvus)
            log_info "Generating Milvus compose..."
            
            cat > "$COMPOSE_DIR/milvus.yml" << 'EOCOMPOSE'
version: '3.8'

services:
  etcd:
    image: quay.io/coreos/etcd:v3.5.5
    container_name: milvus-etcd
    restart: unless-stopped
    environment:
      ETCD_AUTO_COMPACTION_MODE: revision
      ETCD_AUTO_COMPACTION_RETENTION: '1000'
      ETCD_QUOTA_BACKEND_BYTES: '4294967296'
      ETCD_SNAPSHOT_COUNT: '50000'
    volumes:
      - /mnt/data/data/milvus/etcd:/etcd
    command: etcd -advertise-client-urls=http://127.0.0.1:2379 -listen-client-urls http://0.0.0.0:2379 --data-dir /etcd
    networks:
      - ai-platform

  minio:
    image: minio/minio:RELEASE.2023-03-20T20-16-18Z
    container_name: milvus-minio
    restart: unless-stopped
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: ${MINIO_PASSWORD}
    volumes:
      - /mnt/data/data/milvus/minio:/minio_data
    command: minio server /minio_data --console-address ":9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3
    networks:
      - ai-platform

  milvus:
    image: milvusdb/milvus:v2.3.3
    container_name: milvus
    restart: unless-stopped
    depends_on:
      - etcd
      - minio
    environment:
      ETCD_ENDPOINTS: etcd:2379
      MINIO_ADDRESS: minio:9000
      MINIO_ACCESS_KEY_ID: minioadmin
      MINIO_SECRET_ACCESS_KEY: ${MINIO_PASSWORD}
    volumes:
      - /mnt/data/data/milvus:/var/lib/milvus
    ports:
      - "19530:19530"
      - "9091:9091"
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9091/healthz"]
      interval: 30s
      timeout: 20s
      retries: 5

networks:
  ai-platform:
    external: true
EOCOMPOSE

            cat > "$ENV_DIR/milvus.env" << EOENV
MINIO_PASSWORD=$(openssl rand -base64 32)
EOENV
            ;;
            
        chromadb)
            log_info "Generating ChromaDB compose..."
            
            cat > "$COMPOSE_DIR/chromadb.yml" << 'EOCOMPOSE'
version: '3.8'

services:
  chromadb:
    image: chromadb/chroma:latest
    container_name: chromadb
    restart: unless-stopped
    environment:
      IS_PERSISTENT: "TRUE"
      ANONYMIZED_TELEMETRY: "FALSE"
    volumes:
      - /mnt/data/data/chromadb:/chroma/chroma
    ports:
      - "8000:8000"
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/v1/heartbeat"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  ai-platform:
    external: true
EOCOMPOSE

            touch "$ENV_DIR/chromadb.env"
            ;;
            
        weaviate)
            log_info "Generating Weaviate compose..."
            
            cat > "$COMPOSE_DIR/weaviate.yml" << 'EOCOMPOSE'
version: '3.8'

services:
  weaviate:
    image: semitechnologies/weaviate:latest
    container_name: weaviate
    restart: unless-stopped
    environment:
      QUERY_DEFAULTS_LIMIT: 25
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: 'true'
      PERSISTENCE_DATA_PATH: '/var/lib/weaviate'
      DEFAULT_VECTORIZER_MODULE: 'none'
      CLUSTER_HOSTNAME: 'weaviate'
    volumes:
      - /mnt/data/data/weaviate:/var/lib/weaviate
    ports:
      - "8080:8080"
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/v1/.well-known/ready"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  ai-platform:
    external: true
EOCOMPOSE

            touch "$ENV_DIR/weaviate.env"
            ;;
    esac
    
    log_info "✅ Vector DB ($VECTORDB_TYPE) configuration ready"
}

generate_ollama_compose() {
    log_info "Generating Ollama compose..."
    
    if [ "$GPU_AVAILABLE" = "true" ]; then
        GPU_CONFIG='
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]'
    else
        GPU_CONFIG=''
    fi
    
    cat > "$COMPOSE_DIR/ollama.yml" << EOCOMPOSE
version: '3.8'

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    volumes:
      - /mnt/data/data/ollama:/root/.ollama
    ports:
      - "11434:11434"
    networks:
      - ai-platform${GPU_CONFIG}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform:
    external: true
EOCOMPOSE

    touch "$ENV_DIR/ollama.env"
    
    log_info "✅ Ollama configuration ready"
}

generate_litellm_compose() {
    log_info "Generating LiteLLM compose..."
    
    cat > "$COMPOSE_DIR/litellm.yml" << 'EOCOMPOSE'
version: '3.8'

services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    volumes:
      - /mnt/data/config/litellm_config.yaml:/app/config.yaml:ro
    ports:
      - "4000:4000"
    environment:
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
    command: ["--config", "/app/config.yaml", "--port", "4000", "--num_workers", "8"]
    networks:
      - ai-platform
    depends_on:
      - postgres
      - ollama
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform:
    external: true
EOCOMPOSE

    cat > "$ENV_DIR/litellm.env" << EOENV
LITELLM_MASTER_KEY=$(openssl rand -base64 32)
POSTGRES_USER=aiplatform
POSTGRES_PASSWORD=$(cat "$ENV_DIR/postgres.env" | grep POSTGRES_PASSWORD | cut -d= -f2)
POSTGRES_DB=aiplatform
EOENV

    log_info "✅ LiteLLM configuration ready"
}

generate_signal_api_compose() {
    if [ "$SIGNAL_ENABLED" != "true" ]; then
        log_info "Signal not enabled, skipping..."
        return 0
    fi
    
    log_info "Generating Signal-API compose..."
    
    cat > "$COMPOSE_DIR/signal-api.yml" << 'EOCOMPOSE'
version: '3.8'

services:
  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-api
    restart: unless-stopped
    environment:
      MODE: native
      AUTO_RECEIVE_SCHEDULE: "0 22 * * *"
    volumes:
      - /mnt/data/data/signal-api:/home/.local/share/signal-cli
    ports:
      - "8090:8080"
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform:
    external: true
EOCOMPOSE

    touch "$ENV_DIR/signal-api.env"
    
    log_info "✅ Signal-API configuration ready"
}

generate_openclaw_compose() {
    # Check if OpenClaw is in selected services
    if ! printf '%s\n' "${SELECTED_SERVICES[@]}" | grep -q "openclaw"; then
        return 0
    fi
    
    log_info "Generating OpenClaw UI compose..."
    
    SIGNAL_WEBHOOK_URL=$(jq -r '.webhook_url' "$METADATA_DIR/signal_config.json")
    
    cat > "$COMPOSE_DIR/openclaw-ui.yml" << EOCOMPOSE
version: '3.8'

services:
  openclaw-ui:
    image: ghcr.io/openclaw/openclaw-ui:latest
    container_name: openclaw-ui
    restart: unless-stopped
    environment:
      SIGNAL_API_URL: ${SIGNAL_WEBHOOK_URL}
      LITELLM_API_URL: http://litellm:4000
      LITELLM_API_KEY: \${LITELLM_MASTER_KEY}
      PORT: 3000
    ports:
      - "3000:3000"
    networks:
      - ai-platform
    depends_on:
      - signal-api
      - litellm
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform:
    external: true
EOCOMPOSE

    cat > "$ENV_DIR/openclaw-ui.env" << EOENV
SIGNAL_WEBHOOK_URL=$SIGNAL_WEBHOOK_URL
LITELLM_MASTER_KEY=$(cat "$ENV_DIR/litellm.env" | grep LITELLM_MASTER_KEY | cut -d= -f2)
EOENV

    log_info "✅ OpenClaw UI configuration ready"
}

generate_anythingllm_compose() {
    if ! printf '%s\n' "${SELECTED_SERVICES[@]}" | grep -q "anythingllm"; then
        return 0
    fi
    
    log_info "Generating AnythingLLM compose..."
    
    # Get vector DB connection string
    case $VECTORDB_TYPE in
        qdrant)
            VECTOR_DB_URL="http://qdrant:6333"
            VECTOR_DB_TYPE="qdrant"
            ;;
        milvus)
            VECTOR_DB_URL="http://milvus:19530"
            VECTOR_DB_TYPE="milvus"
            ;;
        chromadb)
            VECTOR_DB_URL="http://chromadb:8000"
            VECTOR_DB_TYPE="chroma"
            ;;
        weaviate)
            VECTOR_DB_URL="http://weaviate:8080"
            VECTOR_DB_TYPE="weaviate"
            ;;
        *)
            VECTOR_DB_URL="http://qdrant:6333"
            VECTOR_DB_TYPE="qdrant"
            ;;
    esac
    
    cat > "$COMPOSE_DIR/anythingllm.yml" << EOCOMPOSE
version: '3.8'

services:
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    restart: unless-stopped
    environment:
      STORAGE_DIR: /app/server/storage
      VECTOR_DB: ${VECTOR_DB_TYPE}
      VECTOR_DB_URL: ${VECTOR_DB_URL}
      LLM_PROVIDER: litellm
      LLM_BASE_URL: http://litellm:4000
      LLM_API_KEY: \${LITELLM_MASTER_KEY}
      EMBEDDING_PROVIDER: ollama
      EMBEDDING_BASE_URL: http://ollama:11434
      PUID: ${PUID}
      PGID: ${PGID}
    volumes:
      - /mnt/data/data/anythingllm:/app/server/storage
    ports:
      - "3001:3001"
    networks:
      - ai-platform
    depends_on:
      - litellm
      - ollama
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api/ping"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform:
    external: true
EOCOMPOSE

    cat > "$ENV_DIR/anythingllm.env" << EOENV
VECTOR_DB_TYPE=$VECTOR_DB_TYPE
VECTOR_DB_URL=$VECTOR_DB_URL
LITELLM_MASTER_KEY=$(cat "$ENV_DIR/litellm.env" | grep LITELLM_MASTER_KEY | cut -d= -f2)
PUID=$PUID
PGID=$PGID
EOENV

    log_info "✅ AnythingLLM configuration ready"
}

generate_dify_compose() {
    if ! printf '%s\n' "${SELECTED_SERVICES[@]}" | grep -q "dify"; then
        return 0
    fi
    
    log_info "Generating Dify compose (3-container setup)..."
    
    # Get vector DB connection
    case $VECTORDB_TYPE in
        qdrant)
            VECTOR_DB_URL="http://qdrant:6333"
            VECTOR_TYPE="qdrant"
            ;;
        milvus)
            VECTOR_DB_URL="milvus:19530"
            VECTOR_TYPE="milvus"
            ;;
        chromadb)
            VECTOR_DB_URL="http://chromadb:8000"
            VECTOR_TYPE="chroma"
            ;;
        weaviate)
            VECTOR_DB_URL="http://weaviate:8080"
            VECTOR_TYPE="weaviate"
            ;;
    esac
    
    # Generate shared environment
    cat > "$ENV_DIR/dify.env" << EOENV
# Dify Configuration
LOG_LEVEL=INFO
SECRET_KEY=$(openssl rand -base64 42)

# Database
DB_USERNAME=aiplatform
DB_PASSWORD=$(cat "$ENV_DIR/postgres.env" | grep POSTGRES_PASSWORD | cut -d= -f2)
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=dify

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=$(cat "$ENV_DIR/redis.env" | grep REDIS_PASSWORD | cut -d= -f2)

# Celery
CELERY_BROKER_URL=redis://:$(cat "$ENV_DIR/redis.env" | grep REDIS_PASSWORD | cut -d= -f2)@redis:6379/1

# Vector Database
VECTOR_STORE=$VECTOR_TYPE
VECTOR_STORE_URL=$VECTOR_DB_URL

# Storage (MinIO)
S3_ENDPOINT=http://minio:9000
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=$(openssl rand -base64 32)
S3_BUCKET_NAME=dify
S3_REGION=us-east-1

# LLM Provider (LiteLLM)
LLM_PROVIDER=openai_api_compatible
LLM_API_BASE=http://litellm:4000/v1
LLM_API_KEY=$(cat "$ENV_DIR/litellm.env" | grep LITELLM_MASTER_KEY | cut -d= -f2)
EOENV

    # Generate compose with 3 containers + MinIO
    cat > "$COMPOSE_DIR/dify.yml" << 'EOCOMPOSE'
version: '3.8'

services:
  # MinIO for S3-compatible storage
  dify-minio:
    image: minio/minio:latest
    container_name: dify-minio
    restart: unless-stopped
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: ${S3_SECRET_KEY}
    volumes:
      - /mnt/data/data/dify/minio:/data
    command: server /data --console-address ":9001"
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Dify API
  dify-api:
    image: langgenius/dify-api:latest
    container_name: dify-api
    restart: unless-stopped
    env_file:
      - /mnt/data/env/dify.env
    volumes:
      - /mnt/data/data/dify/api:/app/api/storage
    ports:
      - "5001:5001"
    networks:
      - ai-platform
    depends_on:
      - postgres
      - redis
      - dify-minio
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5001/health"]
      interval: 30s
      timeout: 10s
      retries: 5

  # Dify Worker (Celery)
  dify-worker:
    image: langgenius/dify-api:latest
    container_name: dify-worker
    restart: unless-stopped
    env_file:
      - /mnt/data/env/dify.env
    command: celery -A app.celery worker --loglevel INFO
    volumes:
      - /mnt/data/data/dify/worker:/app/api/storage
    networks:
      - ai-platform
    depends_on:
      - redis
      - postgres

  # Dify Web UI
  dify-web:
    image: langgenius/dify-web:latest
    container_name: dify-web
    restart: unless-stopped
    environment:
      CONSOLE_API_URL: http://dify-api:5001
      APP_API_URL: http://dify-api:5001
    ports:
      - "3002:3000"
    networks:
      - ai-platform
    depends_on:
      - dify-api
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform:
    external: true
EOCOMPOSE

    log_info "✅ Dify (3-container + MinIO) configuration ready"
}

generate_openwebui_compose() {
    if ! printf '%s\n' "${SELECTED_SERVICES[@]}" | grep -q "openwebui"; then
        return 0
    fi
    
    log_info "Generating Open WebUI compose..."
    
    cat > "$COMPOSE_DIR/openwebui.yml" << EOCOMPOSE
version: '3.8'

services:
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    environment:
      OLLAMA_BASE_URL: http://ollama:11434
      OPENAI_API_BASE_URL: http://litellm:4000/v1
      OPENAI_API_KEY: \${LITELLM_MASTER_KEY}
      WEBUI_AUTH: true
      PUID: ${PUID}
      PGID: ${PGID}
    volumes:
      - /mnt/data/data/openwebui:/app/backend/data
    ports:
      - "8080:8080"
    networks:
      - ai-platform
    depends_on:
      - ollama
      - litellm
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform:
    external: true
EOCOMPOSE

    cat > "$ENV_DIR/openwebui.env" << EOENV
LITELLM_MASTER_KEY=$(cat "$ENV_DIR/litellm.env" | grep LITELLM_MASTER_KEY | cut -d= -f2)
PUID=$PUID
PGID=$PGID
EOENV

    log_info "✅ Open WebUI configuration ready"
}

generate_n8n_compose() {
    if ! printf '%s\n' "${SELECTED_SERVICES[@]}" | grep -q "n8n"; then
        return 0
    fi
    
    log_info "Generating n8n compose..."
    
    cat > "$COMPOSE_DIR/n8n.yml" << EOCOMPOSE
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    environment:
      N8N_HOST: ${DOMAIN}
      N8N_PORT: 5678
      N8N_PROTOCOL: https
      WEBHOOK_URL: https://${DOMAIN}/webhook/
      GENERIC_TIMEZONE: America/New_York
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: n8n
      DB_POSTGRESDB_USER: aiplatform
      DB_POSTGRESDB_PASSWORD: \${POSTGRES_PASSWORD}
      PUID: ${PUID}
      PGID: ${PGID}
    volumes:
      - /mnt/data/data/n8n:/home/node/.n8n
    ports:
      - "5678:5678"
    networks:
      - ai-platform
    depends_on:
      - postgres
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform:
    external: true
EOCOMPOSE

    cat > "$ENV_DIR/n8n.env" << EOENV
POSTGRES_PASSWORD=$(cat "$ENV_DIR/postgres.env" | grep POSTGRES_PASSWORD | cut -d= -f2)
DOMAIN=$DOMAIN
PUID=$PUID
PGID=$PGID
EOENV

    log_info "✅ n8n configuration ready"
}

generate_flowise_compose() {
    if ! printf '%s\n' "${SELECTED_SERVICES[@]}" | grep -q "flowise"; then
        return 0
    fi
    
    log_info "Generating Flowise compose..."
    
    cat > "$COMPOSE_DIR/flowise.yml" << EOCOMPOSE
version: '3.8'

services:
  flowise:
    image: flowiseai/flowise:latest
    container_name: flowise
    restart: unless-stopped
    environment:
      PORT: 3000
      DATABASE_TYPE: postgres
      DATABASE_HOST: postgres
      DATABASE_PORT: 5432
      DATABASE_USER: aiplatform
      DATABASE_PASSWORD: \${POSTGRES_PASSWORD}
      DATABASE_NAME: flowise
      APIKEY_PATH: /root/.flowise
      SECRETKEY_PATH: /root/.flowise
      LOG_LEVEL: info
      PUID: ${PUID}
      PGID: ${PGID}
    volumes:
      - /mnt/data/data/flowise:/root/.flowise
    ports:
      - "3003:3000"
    networks:
      - ai-platform
    depends_on:
      - postgres
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3000/api/v1/ping"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform:
    external: true
EOCOMPOSE

    cat > "$ENV_DIR/flowise.env" << EOENV
POSTGRES_PASSWORD=$(cat "$ENV_DIR/postgres.env" | grep POSTGRES_PASSWORD | cut -d= -f2)
PUID=$PUID
PGID=$PGID
EOENV

    log_info "✅ Flowise configuration ready"
}

generate_comfyui_compose() {
    if ! printf '%s\n' "${SELECTED_SERVICES[@]}" | grep -q "comfyui"; then
        return 0
    fi
    
    log_info "Generating ComfyUI compose..."
    
    if [ "$GPU_AVAILABLE" = "true" ]; then
        GPU_CONFIG='
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]'
    else
        GPU_CONFIG=''
    fi
    
    cat > "$COMPOSE_DIR/comfyui.yml" << EOCOMPOSE
version: '3.8'

services:
  comfyui:
    image: yanwk/comfyui-boot:latest
    container_name: comfyui
    restart: unless-stopped
    environment:
      PUID: ${PUID}
      PGID: ${PGID}
    volumes:
      - /mnt/data/data/comfyui:/root
    ports:
      - "8188:8188"
    networks:
      - ai-platform${GPU_CONFIG}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8188"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform:
    external: true
EOCOMPOSE

    cat > "$ENV_DIR/comfyui.env" << EOENV
PUID=$PUID
PGID=$PGID
EOENV

    log_info "✅ ComfyUI configuration ready"
}

generate_gdrive_sync_compose() {
    GDRIVE_ENABLED=$(jq -r '.enabled' "$METADATA_DIR/gdrive_config.json" 2>/dev/null || echo "false")
    
    if [ "$GDRIVE_ENABLED" != "true" ]; then
        return 0
    fi
    
    log_info "Generating Google Drive sync compose..."
    
    cat > "$COMPOSE_DIR/gdrive-sync.yml" << 'EOCOMPOSE'
version: '3.8'

services:
  gdrive-sync:
    image: rclone/rclone:latest
    container_name: gdrive-sync
    restart: unless-stopped
    environment:
      PUID: ${PUID}
      PGID: ${PGID}
      SYNC_INTERVAL: ${SYNC_INTERVAL:-1800}
    volumes:
      - /mnt/data/config/rclone/rclone.conf:/config/rclone/rclone.conf:ro
      - /mnt/data/data/gdrive-sync:/data
    command: >
      rcd
      --rc-web-gui
      --rc-addr :5572
      --rc-user admin
      --rc-pass ${RC_PASSWORD}
    ports:
      - "5572:5572"
    networks:
      - ai-platform

networks:
  ai-platform:
    external: true
EOCOMPOSE

    cat > "$ENV_DIR/gdrive-sync.env" << EOENV
PUID=$PUID
PGID=$PGID
SYNC_INTERVAL=1800
RC_PASSWORD=$(openssl rand -base64 16)
EOENV

    log_info "✅ GDrive sync configuration ready"
}

generate_swag_compose() {
    if [ "$PROXY_TYPE" != "swag" ]; then
        return 0
    fi
    
    log_info "Generating SWAG (LinuxServer reverse proxy) compose..."
    
    cat > "$COMPOSE_DIR/swag.yml" << EOCOMPOSE
version: '3.8'

services:
  swag:
    image: lscr.io/linuxserver/swag:latest
    container_name: swag
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    environment:
      PUID: ${PUID}
      PGID: ${PGID}
      TZ: America/New_York
      URL: ${DOMAIN}
      VALIDATION: http
      STAGING: false
    volumes:
      - /mnt/data/data/swag:/config
    ports:
      - "443:443"
      - "80:80"
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "curl", "-f", "-k", "https://localhost:443"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform:
    external: true
EOCOMPOSE

    cat > "$ENV_DIR/swag.env" << EOENV
PUID=$PUID
PGID=$PGID
DOMAIN=$DOMAIN
EOENV

    log_info "✅ SWAG configuration ready"
}

generate_npm_compose() {
    if [ "$PROXY_TYPE" != "npm" ]; then
        return 0
    fi
    
    log_info "Generating Nginx Proxy Manager compose..."
    
    cat > "$COMPOSE_DIR/nginx-proxy-manager.yml" << 'EOCOMPOSE'
version: '3.8'

services:
  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    environment:
      DB_MYSQL_HOST: npm-db
      DB_MYSQL_PORT: 3306
      DB_MYSQL_USER: npm
      DB_MYSQL_PASSWORD: ${NPM_DB_PASSWORD}
      DB_MYSQL_NAME: npm
    volumes:
      - /mnt/data/data/npm:/data
      - /mnt/data/data/npm/letsencrypt:/etc/letsencrypt
    networks:
      - ai-platform
    depends_on:
      - npm-db

  npm-db:
    image: jc21/mariadb-aria:latest
    container_name: npm-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${NPM_DB_ROOT_PASSWORD}
      MYSQL_DATABASE: npm
      MYSQL_USER: npm
      MYSQL_PASSWORD: ${NPM_DB_PASSWORD}
    volumes:
      - /mnt/data/data/npm-db:/var/lib/mysql
    networks:
      - ai-platform

networks:
  ai-platform:
    external: true
EOCOMPOSE

    cat > "$ENV_DIR/nginx-proxy-manager.env" << EOENV
NPM_DB_PASSWORD=$(openssl rand -base64 32)
NPM_DB_ROOT_PASSWORD=$(openssl rand -base64 32)
EOENV

    log_info "✅ Nginx Proxy Manager configuration ready"
}

generate_monitoring_compose() {
    log_info "Generating monitoring stack (Prometheus + Grafana) compose..."
    
    mkdir -p "$DATA_ROOT/config/prometheus"
    
    # Generate Prometheus config
    cat > "$DATA_ROOT/config/prometheus/prometheus.yml" << 'EOPROM'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'docker'
    static_configs:
      - targets: ['host.docker.internal:9323']
EOPROM

    cat > "$COMPOSE_DIR/monitoring-stack.yml" << 'EOCOMPOSE'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    volumes:
      - /mnt/data/config/prometheus:/etc/prometheus
      - /mnt/data/data/prometheus:/prometheus
    ports:
      - "9090:9090"
    networks:
      - ai-platform

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_USERS_ALLOW_SIGN_UP: false
    volumes:
      - /mnt/data/data/grafana:/var/lib/grafana
    ports:
      - "3004:3000"
    networks:
      - ai-platform
    depends_on:
      - prometheus

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    ports:
      - "9100:9100"
    networks:
      - ai-platform

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    privileged: true
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    ports:
      - "8081:8080"
    networks:
      - ai-platform

networks:
  ai-platform:
    external: true
EOCOMPOSE

    cat > "$ENV_DIR/monitoring-stack.env" << EOENV
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 16)
EOENV

    log_info "✅ Monitoring stack configuration ready"
}

# =====================================================
# DEPLOYMENT ORCHESTRATION
# =====================================================

deploy_service() {
    local compose_file=$1
    local service_name=$(basename "$compose_file" .yml)
    
    log_info "🚀 Deploying $service_name..."
    
    # Check if compose file exists
    if [ ! -f "$compose_file" ]; then
        log_warn "Compose file not found: $compose_file"
        return 1
    fi
    
    # Check if env file exists
    local env_file="$ENV_DIR/${service_name}.env"
    if [ -f "$env_file" ]; then
        export $(cat "$env_file" | xargs)
    fi
    
    # Deploy
    if docker compose -f "$compose_file" up -d --remove-orphans; then
        log_info "✅ $service_name deployed successfully"
        
        # Wait for health check
        wait_for_service_health "$service_name"
        return 0
    else
        log_error "❌ Failed to deploy $service_name"
        return 1
    fi
}

wait_for_service_health() {
    local service_name=$1
    local max_wait=120
    local wait_time=0
    
    log_info "Waiting for $service_name to be healthy..."
    
    while [ $wait_time -lt $max_wait ]; do
        if docker ps --filter "name=$service_name" --filter "health=healthy" | grep -q "$service_name"; then
            log_info "✅ $service_name is healthy"
            return 0
        fi
        
        sleep 5
        wait_time=$((wait_time + 5))
        echo -n "."
    done
    
    echo
    log_warn "⚠️  $service_name health check timeout (may still be starting)"
    return 1
}

deploy_in_order() {
    log_step "🚀 Starting deployment in dependency order..."
    
    # Create Docker network
    if ! docker network ls | grep -q "ai-platform"; then
        log_info "Creating Docker network: ai-platform"
        docker network create ai-platform
    fi
    
    # Deployment order based on dependencies
    DEPLOYMENT_ORDER=(
        "postgres"
        "redis"
        "$VECTORDB_TYPE"
        "ollama"
        "litellm"
        "signal-api"
        "openclaw-ui"
        "anythingllm"
        "dify"
        "openwebui"
        "n8n"
        "flowise"
        "comfyui"
        "gdrive-sync"
        "$PROXY_TYPE"
        "monitoring-stack"
    )
    
    FAILED_SERVICES=()
    
    for service in "${DEPLOYMENT_ORDER[@]}"; do
        # Skip if service not selected
        if [ "$service" = "none" ] || [ -z "$service" ]; then
            continue
        fi
        
        compose_file="$COMPOSE_DIR/${service}.yml"
        
        if [ -f "$compose_file" ]; then
            if ! deploy_service "$compose_file"; then
                FAILED_SERVICES+=("$service")
                log_warn "⚠️  $service failed to deploy, continuing..."
            fi
            sleep 3
        fi
    done
    
    # Summary
    if [ ${#FAILED_SERVICES[@]} -eq 0 ]; then
        log_info "✅ All services deployed successfully!"
    else
        log_warn "⚠️  Some services failed to deploy:"
        printf '%s\n' "${FAILED_SERVICES[@]}" | sed 's/^/  • /'
    fi
}

show_deployment_summary() {
    cat << 'EOF'

╔════════════════════════════════════════════════════════════╗
║          ✅ DEPLOYMENT COMPLETED                           ║
╚════════════════════════════════════════════════════════════╝

🌐 Service Access URLs:
EOF

    printf '%s\n' "${SELECTED_SERVICES[@]}" | while read service; do
        case $service in
            openclaw)
                echo "  • OpenClaw UI:      http://$DOMAIN:3000"
                ;;
            anythingllm)
                echo "  • AnythingLLM:      http://$DOMAIN:3001"
                ;;
            dify)
                echo "  • Dify:             http://$DOMAIN:3002"
                ;;
            openwebui)
                echo "  • Open WebUI:       http://$DOMAIN:8080"
                ;;
            n8n)
                echo "  • n8n:              http://$DOMAIN:5678"
                ;;
            flowise)
                echo "  • Flowise:          http://$DOMAIN:3003"
                ;;
            comfyui)
                echo "  • ComfyUI:          http://$DOMAIN:8188"
                ;;
        esac
    done
    
    cat << EOF

🔧 Infrastructure Services:
  • LiteLLM Proxy:    http://$DOMAIN:4000
  • Ollama:           http://$DOMAIN:11434
  • Qdrant:           http://$DOMAIN:6333
  • PostgreSQL:       localhost:5432
  • Redis:            localhost:6379

📊 Monitoring:
  • Prometheus:       http://$DOMAIN:9090
  • Grafana:          http://$DOMAIN:3004
    Default login: admin / $(cat "$ENV_DIR/monitoring-stack.env" | grep GRAFANA_ADMIN_PASSWORD | cut -d= -f2)

🔐 Important Credentials:
  • LiteLLM API Key:  $(cat "$ENV_DIR/litellm.env" | grep LITELLM_MASTER_KEY | cut -d= -f2)
  • Postgres:         aiplatform / $(cat "$ENV_DIR/postgres.env" | grep POSTGRES_PASSWORD | cut -d= -f2)

📝 Next Steps:
  1. Access services via the URLs above
  2. Run ./3-configure-services.sh for API key configuration
  3. Check service logs: docker compose -f /mnt/data/compose/<service>.yml logs -f

💾 Data Location: /mnt/data/data/
📦 Compose Files: /mnt/data/compose/
🔧 Config Files: /mnt/data/config/

EOF

    if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
        cat << EOF
⚠️  Failed Services:
EOF
        printf '%s\n' "${FAILED_SERVICES[@]}" | sed 's/^/  • /'
        echo
        echo "  Troubleshoot: docker compose -f /mnt/data/compose/<service>.yml logs"
    fi
}

main() {
    show_banner
    
    check_prerequisites
    load_configuration
    
    log_step "📦 Generating compose files..."
    
    # Generate all compose files
    generate_postgres_compose
    generate_redis_compose
    generate_vectordb_compose
    generate_ollama_compose
    generate_litellm_compose
    generate_signal_api_compose
    generate_openclaw_compose
    generate_anythingllm_compose
    generate_dify_compose
    generate_openwebui_compose
    generate_n8n_compose
    generate_flowise_compose
    generate_comfyui_compose
    generate_gdrive_sync_compose
    
    # Generate proxy (SWAG or NPM)
    if [ "$PROXY_TYPE" = "swag" ]; then
        generate_swag_compose
    elif [ "$PROXY_TYPE" = "npm" ]; then
        generate_npm_compose
    fi
    
    # Generate monitoring
    generate_monitoring_compose
    
    log_info "✅ All compose files generated"
    
    # Deploy services
    deploy_in_order
    
    # Show summary
    show_deployment_summary
    
    log_info "✅ Deployment complete!"
    log_info "Next: Run ./3-configure-services.sh"
}

main "$@"
