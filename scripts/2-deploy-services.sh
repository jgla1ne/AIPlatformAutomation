#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - Deploy Services v2.0
# Path-agnostic: Works with any repo name
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Auto-detect script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
LOG_FILE="$SCRIPT_DIR/logs/deploy-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

echo ""
log "${BLUE}========================================${NC}"
log "${BLUE}AI Platform - Deploy Services v2.0${NC}"
log "${BLUE}Repository: $(basename "$SCRIPT_DIR")${NC}"
log "${BLUE}Started: $(date)${NC}"
log "${BLUE}========================================${NC}"
echo ""

# ============================================
# Load Environment
# ============================================
load_environment() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log "${RED}❌ Environment file not found: $ENV_FILE${NC}"
        log "${YELLOW}Run ./1-setup-system.sh first${NC}"
        exit 1
    fi
    
    source "$ENV_FILE"
    log "${GREEN}✓ Environment loaded${NC}"
    echo ""
}

# ============================================
# [1/8] Preflight Checks
# ============================================
preflight_checks() {
    log "${BLUE}[1/8] Pre-flight checks...${NC}"
    
    # Check Docker
    if ! docker info > /dev/null 2>&1; then
        log "${RED}❌ Docker not running or no permission${NC}"
        log "${YELLOW}Try: sudo systemctl start docker${NC}"
        log "${YELLOW}Or logout/login to apply docker group${NC}"
        exit 1
    fi
    log "   ${GREEN}✓ Docker ready${NC}"
    
    # Check data directory
    if [[ ! -d /mnt/data ]]; then
        log "${RED}❌ /mnt/data not found${NC}"
        exit 1
    fi
    log "   ${GREEN}✓ Data directory exists${NC}"
    
    # Check stacks directory
    if [[ ! -d "$SCRIPT_DIR/stacks" ]]; then
        mkdir -p "$SCRIPT_DIR/stacks"
        log "   ${GREEN}✓ Created stacks directory${NC}"
    else
        log "   ${GREEN}✓ Stacks directory exists${NC}"
    fi
    
    # Check network
    if ! docker network ls | grep -q ai-platform-network; then
        docker network create ai-platform-network
        log "   ${GREEN}✓ Created network: ai-platform-network${NC}"
    else
        log "   ${GREEN}✓ Network exists: ai-platform-network${NC}"
    fi
    
    echo ""
}

# ============================================
# [2/8] Deploy Ollama
# ============================================
deploy_ollama() {
    log "${BLUE}[2/8] Deploying Ollama...${NC}"
    
    cat > "$SCRIPT_DIR/stacks/ollama-compose.yml" <<OLLAMA_COMPOSE
version: '3.8'

services:
  ollama:
    image: ollama/ollama:${OLLAMA_VERSION}
    container_name: ollama
    restart: unless-stopped
    networks:
      - ai-platform-network
    ports:
      - "11434:11434"
    volumes:
      - /mnt/data/ollama:/root/.ollama
    environment:
      - OLLAMA_HOST=0.0.0.0:11434
      - OLLAMA_ORIGINS=*
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform-network:
    external: true
OLLAMA_COMPOSE

    docker compose -f "$SCRIPT_DIR/stacks/ollama-compose.yml" up -d
    
    # Wait for health
    log "   Waiting for Ollama to be ready..."
    local retries=0
    while ! curl -sf http://localhost:11434 > /dev/null 2>&1; do
        sleep 5
        retries=$((retries + 1))
        if [[ $retries -gt 12 ]]; then
            log "   ${RED}❌ Ollama failed to start${NC}"
            exit 1
        fi
    done
    
    log "   ${GREEN}✓ Ollama running at http://localhost:11434${NC}"
    echo ""
}

# ============================================
# [3/8] Pull Ollama Models
# ============================================
pull_ollama_models() {
    log "${BLUE}[3/8] Pulling Ollama models...${NC}"
    
    local models=("${OLLAMA_MODELS//,/ }")
    
    for model in $models; do
        log "   Pulling $model..."
        docker exec ollama ollama pull "$model"
        log "   ${GREEN}✓ $model ready${NC}"
    done
    
    echo ""
}

# ============================================
# [4/8] Deploy LiteLLM
# ============================================
deploy_litellm() {
    log "${BLUE}[4/8] Deploying LiteLLM...${NC}"
    
    # Create config
    mkdir -p /mnt/data/litellm
    cat > /mnt/data/litellm/config.yaml <<LITELLM_CONFIG
model_list:
  - model_name: llama3.2
    litellm_params:
      model: ollama/llama3.2
      api_base: http://ollama:11434

  - model_name: qwen2.5-coder
    litellm_params:
      model: ollama/qwen2.5-coder:latest
      api_base: http://ollama:11434

litellm_settings:
  drop_params: true
  set_verbose: false

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
LITELLM_CONFIG

    # Create compose
    cat > "$SCRIPT_DIR/stacks/litellm-compose.yml" <<LITELLM_COMPOSE
version: '3.8'

services:
  litellm:
    image: ghcr.io/berriai/litellm:${LITELLM_VERSION}
    container_name: litellm
    restart: unless-stopped
    networks:
      - ai-platform-network
    ports:
      - "4000:4000"
    volumes:
      - /mnt/data/litellm:/app/config
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - DATABASE_URL=
    command: ["--config", "/app/config/config.yaml", "--port", "4000", "--detailed_debug"]
    depends_on:
      - ollama
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform-network:
    external: true
LITELLM_COMPOSE

    docker compose -f "$SCRIPT_DIR/stacks/litellm-compose.yml" up -d
    
    # Wait for health
    log "   Waiting for LiteLLM to be ready..."
    local retries=0
    while ! curl -sf http://localhost:4000/health > /dev/null 2>&1; do
        sleep 5
        retries=$((retries + 1))
        if [[ $retries -gt 12 ]]; then
            log "   ${RED}❌ LiteLLM failed to start${NC}"
            exit 1
        fi
    done
    
    log "   ${GREEN}✓ LiteLLM running at http://localhost:4000${NC}"
    log "   ${YELLOW}Master Key: ${LITELLM_MASTER_KEY}${NC}"
    echo ""
}

# ============================================
# [5/8] Deploy Signal
# ============================================
deploy_signal() {
    log "${BLUE}[5/8] Deploying Signal...${NC}"
    
    cat > "$SCRIPT_DIR/stacks/signal-compose.yml" <<SIGNAL_COMPOSE
version: '3.8'

services:
  signal-api:
    image: bbernhard/signal-cli-rest-api:${SIGNAL_VERSION}
    container_name: signal-api
    restart: unless-stopped
    networks:
      - ai-platform-network
    ports:
      - "8080:8080"
    volumes:
      - /mnt/data/signal:/home/.local/share/signal-cli
    environment:
      - MODE=native
      - AUTO_RECEIVE_SCHEDULE=0 22 * * *

networks:
  ai-platform-network:
    external: true
SIGNAL_COMPOSE

    docker compose -f "$SCRIPT_DIR/stacks/signal-compose.yml" up -d
    
    # Wait for health
    log "   Waiting for Signal API to be ready..."
    sleep 10
    
    if docker ps | grep -q signal-api; then
        log "   ${GREEN}✓ Signal API running at http://localhost:8080${NC}"
        log "   ${YELLOW}⚠️  Link device: Run ./3-link-signal-device.sh${NC}"
    else
        log "   ${RED}❌ Signal API failed to start${NC}"
        exit 1
    fi
    
    echo ""
}

# ============================================
# [6/8] Deploy Dify
# ============================================
deploy_dify() {
    log "${BLUE}[6/8] Deploying Dify...${NC}"
    
    cat > "$SCRIPT_DIR/stacks/dify-compose.yml" <<DIFY_COMPOSE
version: '3.8'

services:
  # PostgreSQL
  dify-db:
    image: postgres:15-alpine
    container_name: dify-db
    restart: unless-stopped
    networks:
      - ai-platform-network
    volumes:
      - /mnt/data/dify/db:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=dify
      - POSTGRES_PASSWORD=${DIFY_DB_PASSWORD}
      - POSTGRES_DB=dify
      - PGDATA=/var/lib/postgresql/data/pgdata
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dify"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis
  dify-redis:
    image: redis:7-alpine
    container_name: dify-redis
    restart: unless-stopped
    networks:
      - ai-platform-network
    volumes:
      - /mnt/data/dify/redis:/data
    command: redis-server --appendonly yes
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Dify API
  dify-api:
    image: langgenius/dify-api:${DIFY_VERSION}
    container_name: dify-api
    restart: unless-stopped
    networks:
      - ai-platform-network
    depends_on:
      dify-db:
        condition: service_healthy
      dify-redis:
        condition: service_healthy
    volumes:
      - /mnt/data/dify/storage:/app/api/storage
    environment:
      - MODE=api
      - LOG_LEVEL=INFO
      - SECRET_KEY=${DIFY_SECRET_KEY}
      - DB_USERNAME=dify
      - DB_PASSWORD=${DIFY_DB_PASSWORD}
      - DB_HOST=dify-db
      - DB_PORT=5432
      - DB_DATABASE=dify
      - REDIS_HOST=dify-redis
      - REDIS_PORT=6379
      - REDIS_DB=0
      - CELERY_BROKER_URL=redis://dify-redis:6379/1
      - STORAGE_TYPE=local
      - STORAGE_LOCAL_PATH=/app/api/storage
      - VECTOR_STORE=qdrant
      - QDRANT_URL=http://dify-qdrant:6333
      - QDRANT_API_KEY=${DIFY_SECRET_KEY}

  # Dify Worker
  dify-worker:
    image: langgenius/dify-api:${DIFY_VERSION}
    container_name: dify-worker
    restart: unless-stopped
    networks:
      - ai-platform-network
    depends_on:
      dify-db:
        condition: service_healthy
      dify-redis:
        condition: service_healthy
    volumes:
      - /mnt/data/dify/storage:/app/api/storage
    environment:
      - MODE=worker
      - LOG_LEVEL=INFO
      - SECRET_KEY=${DIFY_SECRET_KEY}
      - DB_USERNAME=dify
      - DB_PASSWORD=${DIFY_DB_PASSWORD}
      - DB_HOST=dify-db
      - DB_PORT=5432
      - DB_DATABASE=dify
      - REDIS_HOST=dify-redis
      - REDIS_PORT=6379
      - REDIS_DB=0
      - CELERY_BROKER_URL=redis://dify-redis:6379/1
      - STORAGE_TYPE=local
      - STORAGE_LOCAL_PATH=/app/api/storage
      - VECTOR_STORE=qdrant
      - QDRANT_URL=http://dify-qdrant:6333
      - QDRANT_API_KEY=${DIFY_SECRET_KEY}

  # Dify Web
  dify-web:
    image: langgenius/dify-web:${DIFY_VERSION}
    container_name: dify-web
    restart: unless-stopped
    networks:
      - ai-platform-network
    ports:
      - "3000:3000"
    depends_on:
      - dify-api
    environment:
      - CONSOLE_API_URL=http://dify-api:5001
      - APP_API_URL=http://dify-api:5001

  # Qdrant Vector DB
  dify-qdrant:
    image: qdrant/qdrant:latest
    container_name: dify-qdrant
    restart: unless-stopped
    networks:
      - ai-platform-network
    volumes:
      - /mnt/data/dify/qdrant:/qdrant/storage
    environment:
      - QDRANT__SERVICE__API_KEY=${DIFY_SECRET_KEY}

networks:
  ai-platform-network:
    external: true
DIFY_COMPOSE

    docker compose -f "$SCRIPT_DIR/stacks/dify-compose.yml" up -d
    
    log "   Waiting for Dify to initialize..."
    sleep 30
    
    if docker ps | grep -q dify-web; then
        log "   ${GREEN}✓ Dify running at http://localhost:3000${NC}"
        log "   ${YELLOW}First login: Create admin account${NC}"
    else
        log "   ${RED}❌ Dify failed to start${NC}"
        docker compose -f "$SCRIPT_DIR/stacks/dify-compose.yml" logs
        exit 1
    fi
    
    echo ""
}

# ============================================
# [7/8] Deploy AnythingLLM
# ============================================
deploy_anythingllm() {
    log "${BLUE}[7/8] Deploying AnythingLLM...${NC}"
    
    cat > "$SCRIPT_DIR/stacks/anythingllm-compose.yml" <<ANYTHINGLLM_COMPOSE
version: '3.8'

services:
  anythingllm:
    image: mintplexlabs/anythingllm:${ANYTHINGLLM_VERSION}
    container_name: anythingllm
    restart: unless-stopped
    networks:
      - ai-platform-network
    ports:
      - "3001:3001"
    volumes:
      - /mnt/data/anythingllm:/app/server/storage
    environment:
      - STORAGE_DIR=/app/server/storage
      - UID=1000
      - GID=1000
    cap_add:
      - SYS_ADMIN

networks:
  ai-platform-network:
    external: true
ANYTHINGLLM_COMPOSE

    docker compose -f "$SCRIPT_DIR/stacks/anythingllm-compose.yml" up -d
    
    log "   Waiting for AnythingLLM to be ready..."
    sleep 15
    
    if docker ps | grep -q anythingllm; then
        log "   ${GREEN}✓ AnythingLLM running at http://localhost:3001${NC}"
        log "   ${YELLOW}First login: Create admin account${NC}"
    else
        log "   ${RED}❌ AnythingLLM failed to start${NC}"
        exit 1
    fi
    
    echo ""
}

# ============================================
# [8/8] Summary
# ============================================
print_summary() {
    log "${BLUE}[8/8] Deployment complete!${NC}"
    echo ""
    log "${GREEN}========================================${NC}"
    log "${GREEN}✅ All Services Running${NC}"
    log "${GREEN}========================================${NC}"
    echo ""
    
    log "${BLUE}Service Status:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "ollama|litellm|signal|dify|anythingllm"
    echo ""
    
    log "${BLUE}Access URLs:${NC}"
    log "  ${GREEN}Ollama:${NC}       http://localhost:11434"
    log "  ${GREEN}LiteLLM:${NC}      http://localhost:4000"
    log "  ${GREEN}Signal API:${NC}   http://localhost:8080"
    log "  ${GREEN}Dify:${NC}         http://localhost:3000"
    log "  ${GREEN}AnythingLLM:${NC}  http://localhost:3001"
    echo ""
    
    log "${BLUE}Next Steps:${NC}"
    log "  1. Link Signal device: ${YELLOW}./3-link-signal-device.sh${NC}"
    log "  2. Deploy ClawdBot: ${YELLOW}./4-deploy-clawdbot.sh${NC}"
    log "  3. Configure services: ${YELLOW}./5-configure-services.sh${NC}"
    echo ""
    
    log "${YELLOW}Important:${NC}"
    log "  • LiteLLM Master Key: ${LITELLM_MASTER_KEY}"
    log "  • Dify DB Password: ${DIFY_DB_PASSWORD}"
    log "  • Save these credentials securely!"
    echo ""
}

# ============================================
# Main Execution
# ============================================
main() {
    load_environment
    preflight_checks
    deploy_ollama
    pull_ollama_models
    deploy_litellm
    deploy_signal
    deploy_dify
    deploy_anythingllm
    print_summary
}

main "$@"

chmod +x scripts/2-deploy-services.sh
