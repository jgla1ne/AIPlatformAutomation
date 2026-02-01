#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - Service Deployment v5.3
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

# ============================================
# [0/8] Load Environment & Fix Permissions
# ============================================
echo ""
log "${BLUE}========================================${NC}"
log "${BLUE}AI Platform - Service Deployment v5.3${NC}"
log "${BLUE}Location: $SCRIPT_DIR${NC}"
log "${BLUE}Started: $(date)${NC}"
log "${BLUE}========================================${NC}"
echo ""

log "${BLUE}[0/8] Loading environment...${NC}"

if [[ ! -f "$ENV_FILE" ]]; then
    log "${RED}✗ Environment file not found: $ENV_FILE${NC}"
    log "${YELLOW}Run: ./1-setup-system.sh first${NC}"
    exit 1
fi

# Load environment
set -a
source "$ENV_FILE"
set +a

log "   ${GREEN}✓ Environment loaded${NC}"

# Fix script permissions automatically
log "${BLUE}[0/8] Ensuring script permissions...${NC}"
if [[ -d "$SCRIPT_DIR/scripts" ]]; then
    chmod +x "$SCRIPT_DIR/scripts"/*.sh 2>/dev/null || true
    log "   ${GREEN}✓ All scripts are executable${NC}"
fi

echo ""

# Verify Docker group membership
if ! groups | grep -q docker; then
    log "${RED}✗ User not in docker group${NC}"
    log "${YELLOW}Did you logout and reconnect after running script 1?${NC}"
    exit 1
fi

log "   ${GREEN}✓ Docker access verified${NC}"
echo ""

# ============================================
# [1/8] Preflight Checks
# ============================================
preflight_checks() {
    log "${BLUE}[1/8] Running preflight checks...${NC}"
    
    # Check Docker
    if ! docker ps &>/dev/null; then
        log "${RED}✗ Docker not accessible${NC}"
        exit 1
    fi
    log "   ${GREEN}✓ Docker running${NC}"
    
    # Check data directory
    if [[ ! -d "$DATA_DIR" ]]; then
        log "${RED}✗ Data directory not found: $DATA_DIR${NC}"
        exit 1
    fi
    log "   ${GREEN}✓ Data directory exists${NC}"
    
    # Check GPU availability
    if [[ "$GPU_AVAILABLE" == "true" ]]; then
        if ! docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
            log "${YELLOW}⚠ GPU detected but Docker GPU access failed${NC}"
            log "${YELLOW}  Continuing in CPU-only mode${NC}"
            GPU_AVAILABLE=false
        else
            log "   ${GREEN}✓ GPU access verified${NC}"
        fi
    else
        log "   ${YELLOW}⚠ Running in CPU-only mode${NC}"
    fi
    
    echo ""
}

# ============================================
# [2/8] Prepare Stack Files
# ============================================
prepare_stacks() {
    log "${BLUE}[2/8] Preparing Docker stack files...${NC}"
    
    mkdir -p "$SCRIPT_DIR/stacks"
    
    # Ollama Stack
    cat > "$SCRIPT_DIR/stacks/ollama-stack.yml" <<'OLLAMA_STACK'
version: '3.8'

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    networks:
      - ai-platform-network
    ports:
      - "11434:11434"
    volumes:
      - ${DATA_DIR}/ollama:/root/.ollama
    environment:
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_ORIGINS=*
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

networks:
  ai-platform-network:
    external: true
OLLAMA_STACK
    
    # LiteLLM Stack
    cat > "$SCRIPT_DIR/stacks/litellm-stack.yml" <<'LITELLM_STACK'
version: '3.8'

services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    networks:
      - ai-platform-network
    ports:
      - "4000:4000"
    volumes:
      - ${DATA_DIR}/litellm/config.yaml:/app/config.yaml:ro
      - ${DATA_DIR}/litellm/data:/app/data
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - DATABASE_URL=sqlite:////app/data/litellm.db
      - STORE_MODEL_IN_DB=True
    command: --config /app/config.yaml --detailed_debug
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform-network:
    external: true
LITELLM_STACK
    
    # Signal Stack
    cat > "$SCRIPT_DIR/stacks/signal-stack.yml" <<'SIGNAL_STACK'
version: '3.8'

services:
  signal-cli:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-cli
    restart: unless-stopped
    networks:
      - ai-platform-network
    ports:
      - "8080:8080"
    volumes:
      - ${DATA_DIR}/signal-cli:/home/.local/share/signal-cli
    environment:
      - MODE=json-rpc
      - AUTO_RECEIVE_SCHEDULE=0 */1 * * * *
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform-network:
    external: true
SIGNAL_STACK
    
    # Dify Stack
    cat > "$SCRIPT_DIR/stacks/dify-stack.yml" <<'DIFY_STACK'
version: '3.8'

services:
  dify-db:
    image: postgres:15-alpine
    container_name: dify-db
    restart: unless-stopped
    networks:
      - ai-platform-network
    environment:
      POSTGRES_USER: ${DIFY_DB_USER}
      POSTGRES_PASSWORD: ${DIFY_DB_PASSWORD}
      POSTGRES_DB: ${DIFY_DB_NAME}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ${DATA_DIR}/dify/db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "${DIFY_DB_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  dify-redis:
    image: redis:7-alpine
    container_name: dify-redis
    restart: unless-stopped
    networks:
      - ai-platform-network
    volumes:
      - ${DATA_DIR}/dify/redis:/data
    command: redis-server --requirepass ${DIFY_REDIS_PASSWORD}
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  dify-api:
    image: langgenius/dify-api:latest
    container_name: dify-api
    restart: unless-stopped
    networks:
      - ai-platform-network
    depends_on:
      - dify-db
      - dify-redis
    environment:
      MODE: api
      LOG_LEVEL: INFO
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: ${DIFY_DB_USER}
      DB_PASSWORD: ${DIFY_DB_PASSWORD}
      DB_HOST: dify-db
      DB_PORT: 5432
      DB_DATABASE: ${DIFY_DB_NAME}
      REDIS_HOST: dify-redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${DIFY_REDIS_PASSWORD}
      CELERY_BROKER_URL: redis://:${DIFY_REDIS_PASSWORD}@dify-redis:6379/1
      CONSOLE_WEB_URL: http://localhost:3000
      CONSOLE_API_URL: http://localhost:5001
      SERVICE_API_URL: http://localhost:5001
    volumes:
      - ${DATA_DIR}/dify/app:/app/api/storage

  dify-worker:
    image: langgenius/dify-api:latest
    container_name: dify-worker
    restart: unless-stopped
    networks:
      - ai-platform-network
    depends_on:
      - dify-db
      - dify-redis
    environment:
      MODE: worker
      LOG_LEVEL: INFO
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: ${DIFY_DB_USER}
      DB_PASSWORD: ${DIFY_DB_PASSWORD}
      DB_HOST: dify-db
      DB_PORT: 5432
      DB_DATABASE: ${DIFY_DB_NAME}
      REDIS_HOST: dify-redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${DIFY_REDIS_PASSWORD}
      CELERY_BROKER_URL: redis://:${DIFY_REDIS_PASSWORD}@dify-redis:6379/1
    volumes:
      - ${DATA_DIR}/dify/app:/app/api/storage

  dify-web:
    image: langgenius/dify-web:latest
    container_name: dify-web
    restart: unless-stopped
    networks:
      - ai-platform-network
    ports:
      - "3000:3000"
    depends_on:
      - dify-api
    environment:
      CONSOLE_API_URL: http://dify-api:5001
      APP_API_URL: http://dify-api:5001

networks:
  ai-platform-network:
    external: true
DIFY_STACK
    
    # AnythingLLM Stack
    cat > "$SCRIPT_DIR/stacks/anythingllm-stack.yml" <<'ANYTHINGLLM_STACK'
version: '3.8'

services:
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    restart: unless-stopped
    networks:
      - ai-platform-network
    ports:
      - "3001:3001"
    volumes:
      - ${DATA_DIR}/anythingllm:/app/server/storage
    environment:
      - STORAGE_DIR=/app/server/storage
    cap_add:
      - SYS_ADMIN

networks:
  ai-platform-network:
    external: true
ANYTHINGLLM_STACK
    
    log "   ${GREEN}✓ Stack files created${NC}"
    echo ""
}

# ============================================
# [3/8] Deploy Ollama
# ============================================
deploy_ollama() {
    log "${BLUE}[3/8] Deploying Ollama...${NC}"
    
    # Create data directory
    mkdir -p "$DATA_DIR/ollama"
    chown -R ollama:ollama "$DATA_DIR/ollama"
    
    # Deploy based on GPU availability
    if [[ "$GPU_AVAILABLE" == "true" ]]; then
        log "   ${YELLOW}Deploying with GPU support...${NC}"
        docker compose -f "$SCRIPT_DIR/stacks/ollama-stack.yml" up -d
    else
        log "   ${YELLOW}Deploying in CPU-only mode...${NC}"
        # Remove GPU configuration for CPU-only
        cat > "$SCRIPT_DIR/stacks/ollama-stack-cpu.yml" <<'OLLAMA_CPU'
version: '3.8'

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    networks:
      - ai-platform-network
    ports:
      - "11434:11434"
    volumes:
      - ${DATA_DIR}/ollama:/root/.ollama
    environment:
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_ORIGINS=*

networks:
  ai-platform-network:
    external: true
OLLAMA_CPU
        docker compose -f "$SCRIPT_DIR/stacks/ollama-stack-cpu.yml" up -d
    fi
    
    # Wait for Ollama to be ready
    log "   ${YELLOW}Waiting for Ollama to be ready...${NC}"
    for i in {1..30}; do
        if curl -s http://localhost:11434/api/tags &>/dev/null; then
            log "   ${GREEN}✓ Ollama is ready${NC}"
            break
        fi
        sleep 2
    done
    
    echo ""
}

# ============================================
# [4/8] Pull Ollama Models
# ============================================
pull_ollama_models() {
    log "${BLUE}[4/8] Pulling Ollama models...${NC}"
    
    # Parse model list from environment
    IFS=',' read -ra MODELS <<< "$OLLAMA_MODELS"
    
    for model in "${MODELS[@]}"; do
        model=$(echo "$model" | xargs)  # Trim whitespace
        log "   ${YELLOW}Pulling $model...${NC}"
        
        if docker exec ollama ollama pull "$model"; then
            log "   ${GREEN}✓ $model pulled successfully${NC}"
        else
            log "   ${RED}✗ Failed to pull $model${NC}"
        fi
    done
    
    echo ""
}

# ============================================
# [5/8] Deploy LiteLLM
# ============================================
deploy_litellm() {
    log "${BLUE}[5/8] Deploying LiteLLM...${NC}"
    
    # Create directories
    mkdir -p "$DATA_DIR/litellm/data"
    chown -R litellm:litellm "$DATA_DIR/litellm"
    
    # Create LiteLLM configuration
    cat > "$DATA_DIR/litellm/config.yaml" <<LITELLM_CONFIG
model_list:
  # Ollama Models
  - model_name: llama3.2
    litellm_params:
      model: ollama/llama3.2
      api_base: http://ollama:11434
  
  - model_name: qwen2.5-coder
    litellm_params:
      model: ollama/qwen2.5-coder:latest
      api_base: http://ollama:11434
  
  - model_name: phi4
    litellm_params:
      model: ollama/phi4:latest
      api_base: http://ollama:11434

litellm_settings:
  drop_params: true
  set_verbose: true
  
general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: sqlite:////app/data/litellm.db
LITELLM_CONFIG
    
    chown litellm:litellm "$DATA_DIR/litellm/config.yaml"
    
    # Deploy
    docker compose -f "$SCRIPT_DIR/stacks/litellm-stack.yml" up -d
    
    # Wait for LiteLLM
    log "   ${YELLOW}Waiting for LiteLLM to be ready...${NC}"
    for i in {1..30}; do
        if curl -s http://localhost:4000/health &>/dev/null; then
            log "   ${GREEN}✓ LiteLLM is ready${NC}"
            break
        fi
        sleep 2
    done
    
    echo ""
}

# ============================================
# [6/8] Deploy Signal
# ============================================
deploy_signal() {
    log "${BLUE}[6/8] Deploying Signal...${NC}"
    
    # Create directories
    mkdir -p "$DATA_DIR/signal-cli"
    chown -R signal:signal "$DATA_DIR/signal-cli"
    
    # Deploy
    docker compose -f "$SCRIPT_DIR/stacks/signal-stack.yml" up -d
    
    # Wait for Signal
    log "   ${YELLOW}Waiting for Signal to be ready...${NC}"
    for i in {1..30}; do
        if curl -s http://localhost:8080/v1/health &>/dev/null; then
            log "   ${GREEN}✓ Signal is ready${NC}"
            break
        fi
        sleep 2
    done
    
    log "   ${YELLOW}⚠ Signal requires manual linking${NC}"
    log "   ${YELLOW}  Run: ./3-link-signal.sh${NC}"
    
    echo ""
}

# ============================================
# [7/8] Deploy Dify
# ============================================
deploy_dify() {
    log "${BLUE}[7/8] Deploying Dify...${NC}"
    
    # Create directories
    mkdir -p "$DATA_DIR/dify"/{db,redis,app}
    chown -R dify:dify "$DATA_DIR/dify"
    
    # Deploy
    docker compose -f "$SCRIPT_DIR/stacks/dify-stack.yml" up -d
    
    # Wait for Dify
    log "   ${YELLOW}Waiting for Dify to be ready...${NC}"
    sleep 30  # Dify takes longer to initialize
    
    for i in {1..60}; do
        if curl -s http://localhost:3000 &>/dev/null; then
            log "   ${GREEN}✓ Dify is ready${NC}"
            break
        fi
        sleep 2
    done
    
    echo ""
}

# ============================================
# [8/8] Deploy AnythingLLM
# ============================================
deploy_anythingllm() {
    log "${BLUE}[8/8] Deploying AnythingLLM...${NC}"
    
    # Create directories
    mkdir -p "$DATA_DIR/anythingllm"
    chown -R anythingllm:anythingllm "$DATA_DIR/anythingllm"
    
    # Deploy
    docker compose -f "$SCRIPT_DIR/stacks/anythingllm-stack.yml" up -d
    
    # Wait for AnythingLLM
    log "   ${YELLOW}Waiting for AnythingLLM to be ready...${NC}"
    for i in {1..30}; do
        if curl -s http://localhost:3001 &>/dev/null; then
            log "   ${GREEN}✓ AnythingLLM is ready${NC}"
            break
        fi
        sleep 2
    done
    
    echo ""
}

# ============================================
# Print Deployment Summary
# ============================================
print_summary() {
    log "${GREEN}========================================${NC}"
    log "${GREEN}✅ Deployment Complete${NC}"
    log "${GREEN}========================================${NC}"
    echo ""
    
    log "${BLUE}Services Status:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "ollama|litellm|signal|dify|anythingllm" || log "   ${YELLOW}No services running${NC}"
    echo ""
    
    log "${BLUE}Access URLs:${NC}"
    log "  Ollama:       http://localhost:11434"
    log "  LiteLLM:      http://localhost:4000"
    log "  Signal:       http://localhost:8080"
    log "  Dify:         http://localhost:3000"
    log "  AnythingLLM:  http://localhost:3001"
    echo ""
    
    if [[ "$TAILSCALE_ENABLED" == "true" ]]; then
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "Not available")
        log "${BLUE}Tailscale Access:${NC}"
        log "  Ollama:       http://$TAILSCALE_IP:11434"
        log "  LiteLLM:      http://$TAILSCALE_IP:4000"
        log "  Signal:       http://$TAILSCALE_IP:8080"
        log "  Dify:         http://$TAILSCALE_IP:3000"
        log "  AnythingLLM:  http://$TAILSCALE_IP:3001"
        echo ""
    fi
    
    log "${BLUE}Credentials:${NC}"
    log "  LiteLLM Master Key: $LITELLM_MASTER_KEY"
    log "  Dify DB User:       $DIFY_DB_USER"
    log "  Dify DB Password:   $DIFY_DB_PASSWORD"
    echo ""
    
    log "${YELLOW}Next Steps:${NC}"
    log "  1. Link Signal: ${YELLOW}./3-link-signal.sh${NC}"
    log "  2. Deploy ClawdBot: ${YELLOW}./4-deploy-clawdbot.sh${NC}"
    log "  3. Configure services: ${YELLOW}./5-configure-services.sh${NC}"
    echo ""
    
    log "${BLUE}Log file: $LOG_FILE${NC}"
    echo ""
}

# ============================================
# Main Execution
# ============================================
main() {
    preflight_checks
    prepare_stacks
    deploy_ollama
    pull_ollama_models
    deploy_litellm
    deploy_signal
    deploy_dify
    deploy_anythingllm
    print_summary
}

main "$@"
