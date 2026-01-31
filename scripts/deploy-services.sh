#!/bin/bash
set -eo pipefail

# ============================================
# AI Platform Services Deployment v4.1
# With orphan cleanup and full rollback
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/ai-platform-deploy.log"
CHECKPOINT_FILE="$SCRIPT_DIR/.deployment_checkpoint"
BACKUP_DIR="$SCRIPT_DIR/backups/$(date +%Y%m%d_%H%M%S)"

sudo touch "$LOG_FILE"
sudo chown $USER:$USER "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}AI Platform Services Deployment v4.1${NC}"
echo -e "${BLUE}Started: $(date)${NC}"
echo -e "${BLUE}========================================${NC}"

# ============================================
# Cleanup Functions
# ============================================
cleanup_orphans() {
    echo -e "\n${BLUE}[1/13] Cleaning up orphaned containers...${NC}"
    
    local containers=(
        "ollama"
        "litellm"
        "dify-web" "dify-worker" "dify-api" "dify-db" "dify-redis" "dify-weaviate" "dify-nginx" "dify-sandbox"
        "anythingllm"
        "signal-cli"
    )
    
    for container in "${containers[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            echo -e "   ${YELLOW}Removing orphaned container: $container${NC}"
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        fi
    done
    
    echo -e "   ${GREEN}✅ Orphan cleanup complete${NC}"
}

full_rollback() {
    echo -e "\n${RED}========================================${NC}"
    echo -e "${RED}FULL ROLLBACK INITIATED${NC}"
    echo -e "${RED}========================================${NC}"
    
    # Create backup of data before rollback
    if [[ -d "$DATA_PATH" ]] && [[ -n "$(ls -A $DATA_PATH 2>/dev/null)" ]]; then
        echo -e "${YELLOW}Creating backup of data...${NC}"
        mkdir -p "$BACKUP_DIR"
        sudo cp -r "$DATA_PATH" "$BACKUP_DIR/" 2>/dev/null || true
        echo -e "   ${GREEN}✅ Backup saved to: $BACKUP_DIR${NC}"
    fi
    
    # Stop and remove all containers
    echo -e "\n${YELLOW}Stopping all AI platform containers...${NC}"
    for stack in ollama litellm dify anythingllm signal; do
        if [[ -d "$SCRIPT_DIR/stacks/$stack" ]]; then
            echo -e "   Stopping $stack..."
            cd "$SCRIPT_DIR/stacks/$stack"
            docker compose down -v 2>/dev/null || true
        fi
    done
    
    # Remove orphaned containers
    cleanup_orphans
    
    # Clean up volumes (optional - preserves data by default)
    read -p "Remove Docker volumes? This will DELETE ALL DATA (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Removing volumes...${NC}"
        docker volume rm $(docker volume ls -q | grep -E "ollama|litellm|dify|anythingllm|signal") 2>/dev/null || true
        echo -e "   ${GREEN}✅ Volumes removed${NC}"
    else
        echo -e "   ${BLUE}ℹ️  Volumes preserved${NC}"
    fi
    
    # Remove stack directories but preserve .env
    echo -e "\n${YELLOW}Cleaning stack directories...${NC}"
    if [[ -d "$SCRIPT_DIR/stacks" ]]; then
        for stack in ollama litellm dify anythingllm signal; do
            if [[ -d "$SCRIPT_DIR/stacks/$stack" ]]; then
                rm -rf "$SCRIPT_DIR/stacks/$stack"
                echo -e "   Removed stacks/$stack"
            fi
        done
    fi
    
    # Clean checkpoint
    rm -f "$CHECKPOINT_FILE"
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Rollback Complete${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "What was preserved:"
    echo "  ✅ .env configuration"
    echo "  ✅ Docker network (ai-platform-network)"
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "  ✅ Docker volumes (data preserved)"
    fi
    echo ""
    echo "What was removed:"
    echo "  ❌ All containers"
    echo "  ❌ Stack configurations"
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "  ❌ All data volumes"
    fi
    echo ""
    if [[ -d "$BACKUP_DIR" ]]; then
        echo "Data backup location: $BACKUP_DIR"
        echo ""
    fi
    echo "You can now run ./deploy-services.sh to redeploy"
    echo ""
    
    exit 0
}

# ============================================
# GPU Detection
# ============================================
HAS_GPU=false

detect_gpu() {
    echo -e "\n${BLUE}Detecting GPU...${NC}"
    
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            HAS_GPU=true
            echo -e "   ${GREEN}✅ NVIDIA GPU detected${NC}"
            nvidia-smi --query-gpu=name --format=csv,noheader | head -1
        else
            echo -e "   ${YELLOW}⚠️  nvidia-smi found but not working${NC}"
        fi
    else
        echo -e "   ${YELLOW}⚠️  No NVIDIA GPU detected - using CPU${NC}"
    fi
    
    export HAS_GPU
}

# ============================================
# State Tracking
# ============================================
declare -a DEPLOYED_STACKS=()

add_deployed_stack() {
    local stack="$1"
    DEPLOYED_STACKS+=("$stack")
    echo "DEPLOYED_STACK:$stack" >> "$CHECKPOINT_FILE"
}

# ============================================
# Partial Rollback (on error)
# ============================================
perform_rollback() {
    echo -e "\n${RED}⚠️  DEPLOYMENT ERROR - ROLLING BACK${NC}"
    
    if [[ -f "$CHECKPOINT_FILE" ]]; then
        while IFS=: read -r type value; do
            case "$type" in
                DEPLOYED_STACK)
                    echo -e "${YELLOW}Rolling back stack: $value${NC}"
                    cd "$SCRIPT_DIR/stacks/$value" && docker compose down -v || true
                    ;;
            esac
        done < "$CHECKPOINT_FILE"
    fi
    
    cleanup_orphans
    rm -f "$CHECKPOINT_FILE"
    
    echo -e "\n${RED}Rollback complete. Check logs above for errors.${NC}"
    echo -e "${YELLOW}To start fresh, run: ./deploy-services.sh --rollback${NC}"
    exit 1
}

trap perform_rollback ERR

# ============================================
# Environment Loading
# ============================================
load_environment() {
    echo -e "\n${BLUE}[2/13] Loading environment...${NC}"
    
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        echo -e "   ${RED}❌ .env file not found${NC}"
        exit 1
    fi
    
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
    
    echo -e "   ${GREEN}✅ Environment loaded${NC}"
    echo -e "   Network: $NETWORK_NAME"
    echo -e "   Data path: $DATA_PATH"
    echo -e "   Models: $OLLAMA_MODELS"
}

# ============================================
# Prerequisites Check
# ============================================
check_prerequisites() {
    echo -e "\n${BLUE}[3/13] Checking prerequisites...${NC}"
    
    detect_gpu
    
    # Create network if it doesn't exist
    echo -e "   Creating network: $NETWORK_NAME"
    if docker network inspect "$NETWORK_NAME" &> /dev/null; then
        echo -e "   ${GREEN}✅ Network already exists: $NETWORK_NAME${NC}"
    else
        docker network create "$NETWORK_NAME"
        echo -e "   ${GREEN}✅ Network created: $NETWORK_NAME${NC}"
    fi
    
    # Create data directories
    sudo mkdir -p "$DATA_PATH"/{ollama,litellm,dify,anythingllm,signal}
    sudo chown -R $USER:$USER "$DATA_PATH"
    
    echo -e "   ${GREEN}✅ Prerequisites OK${NC}"
}

# ============================================
# Stack Directory Creation
# ============================================
create_stack_dirs() {
    echo -e "\n${BLUE}[4/13] Creating stack directories...${NC}"
    
    mkdir -p "$SCRIPT_DIR/stacks"/{ollama,litellm,dify,anythingllm,signal}
    
    echo -e "   ${GREEN}✅ Directories created${NC}"
}

# ============================================
# Ollama Stack
# ============================================
create_ollama_stack() {
    echo -e "\n${BLUE}[5/13] Creating Ollama stack...${NC}"
    
    if [[ "$HAS_GPU" == "true" ]]; then
        echo -e "   Creating GPU-enabled Ollama configuration"
        cat > "$SCRIPT_DIR/stacks/ollama/docker-compose.yml" <<'OLLAMA_GPU_EOF'
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ${DATA_PATH}/ollama:/root/.ollama
    networks:
      - ai-platform-network
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
    name: ${NETWORK_NAME}
OLLAMA_GPU_EOF
    else
        echo -e "   Creating CPU-only Ollama configuration"
        cat > "$SCRIPT_DIR/stacks/ollama/docker-compose.yml" <<'OLLAMA_CPU_EOF'
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ${DATA_PATH}/ollama:/root/.ollama
    networks:
      - ai-platform-network

networks:
  ai-platform-network:
    external: true
    name: ${NETWORK_NAME}
OLLAMA_CPU_EOF
    fi
    
    cp "$SCRIPT_DIR/.env" "$SCRIPT_DIR/stacks/ollama/.env"
    echo -e "   ${GREEN}✅ Ollama stack created${NC}"
}

# ============================================
# LiteLLM Stack
# ============================================
create_litellm_stack() {
    echo -e "\n${BLUE}[6/13] Creating LiteLLM stack...${NC}"
    
    cat > "$SCRIPT_DIR/stacks/litellm/docker-compose.yml" <<'LITELLM_EOF'
services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    ports:
      - "4000:4000"
    environment:
      - OLLAMA_API_BASE=http://ollama:11434
      - LITELLM_MASTER_KEY=${LITELLM_API_KEY}
      - LITELLM_LOG=INFO
    volumes:
      - ${DATA_PATH}/litellm:/app/data
    networks:
      - ai-platform-network
    command: --config /app/data/config.yaml

networks:
  ai-platform-network:
    external: true
    name: ${NETWORK_NAME}
LITELLM_EOF
    
    mkdir -p "$DATA_PATH/litellm"
    cat > "$DATA_PATH/litellm/config.yaml" <<'LITELLM_CONFIG_EOF'
model_list:
  - model_name: llama3.2
    litellm_params:
      model: ollama/llama3.2
      api_base: http://ollama:11434
  - model_name: codellama
    litellm_params:
      model: ollama/codellama
      api_base: http://ollama:11434
  - model_name: mistral
    litellm_params:
      model: ollama/mistral
      api_base: http://ollama:11434

litellm_settings:
  drop_params: true
  success_callback: ["langfuse"]
LITELLM_CONFIG_EOF
    
    cp "$SCRIPT_DIR/.env" "$SCRIPT_DIR/stacks/litellm/.env"
    echo -e "   ${GREEN}✅ LiteLLM stack created${NC}"
}

# ============================================
# Dify Stack
# ============================================
create_dify_stack() {
    echo -e "\n${BLUE}[7/13] Creating Dify stack...${NC}"
    
    cat > "$SCRIPT_DIR/stacks/dify/docker-compose.yml" <<'DIFY_EOF'
services:
  db:
    image: postgres:15-alpine
    container_name: dify-db
    restart: unless-stopped
    environment:
      PGUSER: ${DIFY_DB_USER}
      POSTGRES_PASSWORD: ${DIFY_DB_PASSWORD}
      POSTGRES_DB: ${DIFY_DB_NAME}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ${DATA_PATH}/dify/db:/var/lib/postgresql/data
    networks:
      - ai-platform-network
    healthcheck:
      test: ["CMD", "pg_isready"]
      interval: 1s
      timeout: 3s
      retries: 30

  redis:
    image: redis:7-alpine
    container_name: dify-redis
    restart: unless-stopped
    volumes:
      - ${DATA_PATH}/dify/redis:/data
    networks:
      - ai-platform-network
    command: redis-server --requirepass ${DIFY_REDIS_PASSWORD}
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 1s
      timeout: 3s
      retries: 30

  api:
    image: langgenius/dify-api:latest
    container_name: dify-api
    restart: unless-stopped
    environment:
      MODE: api
      LOG_LEVEL: INFO
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: ${DIFY_DB_USER}
      DB_PASSWORD: ${DIFY_DB_PASSWORD}
      DB_HOST: db
      DB_PORT: 5432
      DB_DATABASE: ${DIFY_DB_NAME}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${DIFY_REDIS_PASSWORD}
      REDIS_USE_SSL: false
      REDIS_DB: 0
      CELERY_BROKER_URL: redis://:${DIFY_REDIS_PASSWORD}@redis:6379/1
      WEB_API_CORS_ALLOW_ORIGINS: '*'
      CONSOLE_CORS_ALLOW_ORIGINS: '*'
      STORAGE_TYPE: local
      STORAGE_LOCAL_PATH: storage
      VECTOR_STORE: weaviate
      WEAVIATE_ENDPOINT: http://weaviate:8080
      WEAVIATE_API_KEY: ${DIFY_WEAVIATE_API_KEY}
    volumes:
      - ${DATA_PATH}/dify/api/storage:/app/api/storage
    networks:
      - ai-platform-network

  worker:
    image: langgenius/dify-api:latest
    container_name: dify-worker
    restart: unless-stopped
    environment:
      MODE: worker
      LOG_LEVEL: INFO
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: ${DIFY_DB_USER}
      DB_PASSWORD: ${DIFY_DB_PASSWORD}
      DB_HOST: db
      DB_PORT: 5432
      DB_DATABASE: ${DIFY_DB_NAME}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${DIFY_REDIS_PASSWORD}
      REDIS_USE_SSL: false
      REDIS_DB: 0
      CELERY_BROKER_URL: redis://:${DIFY_REDIS_PASSWORD}@redis:6379/1
      STORAGE_TYPE: local
      STORAGE_LOCAL_PATH: storage
      VECTOR_STORE: weaviate
      WEAVIATE_ENDPOINT: http://weaviate:8080
      WEAVIATE_API_KEY: ${DIFY_WEAVIATE_API_KEY}
    volumes:
      - ${DATA_PATH}/dify/api/storage:/app/api/storage
    networks:
      - ai-platform-network

  web:
    image: langgenius/dify-web:latest
    container_name: dify-web
    restart: unless-stopped
    environment:
      CONSOLE_API_URL: http://localhost:5001
      APP_API_URL: http://localhost:5001
    networks:
      - ai-platform-network

  weaviate:
    image: semitechnologies/weaviate:latest
    container_name: dify-weaviate
    restart: unless-stopped
    environment:
      QUERY_DEFAULTS_LIMIT: 25
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: false
      AUTHENTICATION_APIKEY_ENABLED: true
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: ${DIFY_WEAVIATE_API_KEY}
      PERSISTENCE_DATA_PATH: /var/lib/weaviate
      DEFAULT_VECTORIZER_MODULE: none
      CLUSTER_HOSTNAME: node1
    volumes:
      - ${DATA_PATH}/dify/weaviate:/var/lib/weaviate
    networks:
      - ai-platform-network

  nginx:
    image: nginx:alpine
    container_name: dify-nginx
    restart: unless-stopped
    ports:
      - "5001:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - ai-platform-network

networks:
  ai-platform-network:
    external: true
    name: ${NETWORK_NAME}
DIFY_EOF
    
    cat > "$SCRIPT_DIR/stacks/dify/nginx.conf" <<'NGINX_EOF'
events {
    worker_connections 1024;
}

http {
    upstream api {
        server dify-api:5001;
    }

    upstream web {
        server dify-web:3000;
    }

    server {
        listen 80;
        server_name _;

        location /console/api {
            proxy_pass http://api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /api {
            proxy_pass http://api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /v1 {
            proxy_pass http://api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /files {
            proxy_pass http://api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location / {
            proxy_pass http://web;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
NGINX_EOF
    
    cp "$SCRIPT_DIR/.env" "$SCRIPT_DIR/stacks/dify/.env"
    echo -e "   ${GREEN}✅ Dify stack created${NC}"
}

# ============================================
# AnythingLLM Stack
# ============================================
create_anythingllm_stack() {
    echo -e "\n${BLUE}[8/13] Creating AnythingLLM stack...${NC}"
    
    cat > "$SCRIPT_DIR/stacks/anythingllm/docker-compose.yml" <<'ANYTHINGLLM_EOF'
services:
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    restart: unless-stopped
    ports:
      - "3001:3001"
    environment:
      - STORAGE_DIR=/app/server/storage
      - JWT_SECRET=${ANYTHINGLLM_JWT_SECRET}
      - LLM_PROVIDER=ollama
      - OLLAMA_BASE_PATH=http://ollama:11434
      - EMBEDDING_ENGINE=ollama
      - EMBEDDING_BASE_PATH=http://ollama:11434
      - VECTOR_DB=lancedb
    volumes:
      - ${DATA_PATH}/anythingllm:/app/server/storage
    networks:
      - ai-platform-network
    cap_add:
      - SYS_ADMIN

networks:
  ai-platform-network:
    external: true
    name: ${NETWORK_NAME}
ANYTHINGLLM_EOF
    
    cp "$SCRIPT_DIR/.env" "$SCRIPT_DIR/stacks/anythingllm/.env"
    echo -e "   ${GREEN}✅ AnythingLLM stack created${NC}"
}

# ============================================
# Signal CLI REST API Stack
# ============================================
create_signal_stack() {
    echo -e "\n${BLUE}[9/13] Creating Signal CLI REST API stack...${NC}"
    
    cat > "$SCRIPT_DIR/stacks/signal/docker-compose.yml" <<'SIGNAL_EOF'
services:
  signal-cli:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-cli
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - MODE=native
    volumes:
      - ${DATA_PATH}/signal:/home/.local/share/signal-cli
    networks:
      - ai-platform-network

networks:
  ai-platform-network:
    external: true
    name: ${NETWORK_NAME}
SIGNAL_EOF
    
    cp "$SCRIPT_DIR/.env" "$SCRIPT_DIR/stacks/signal/.env"
    echo -e "   ${GREEN}✅ Signal CLI REST API stack created${NC}"
}

# ============================================
# Deployment Function
# ============================================
deploy_stack() {
    local stack_name="$1"
    local step="$2"
    
    echo -e "\n${BLUE}[${step}/13] Deploying ${stack_name}...${NC}"
    
    cd "$SCRIPT_DIR/stacks/$stack_name"
    
    if docker compose up -d; then
        add_deployed_stack "$stack_name"
        echo -e "   ${GREEN}✅ ${stack_name} deployed${NC}"
        
        # Wait for service to be ready
        sleep 5
        
        return 0
    else
        echo -e "   ${RED}❌ ${stack_name} deployment failed${NC}"
        return 1
    fi
}

# ============================================
# Model Pulling
# ============================================
pull_models() {
    echo -e "\n${BLUE}[11/13] Pulling Ollama models...${NC}"
    
    if [[ -z "$OLLAMA_MODELS" ]]; then
        echo -e "   ${YELLOW}⚠️  No models specified in OLLAMA_MODELS${NC}"
        return 0
    fi
    
    IFS=',' read -ra MODELS <<< "$OLLAMA_MODELS"
    
    for model in "${MODELS[@]}"; do
        model=$(echo "$model" | xargs)  # Trim whitespace
        echo -e "   Pulling model: $model"
        
        if docker exec ollama ollama pull "$model"; then
            echo -e "   ${GREEN}✅ $model pulled successfully${NC}"
        else
            echo -e "   ${YELLOW}⚠️  Failed to pull $model${NC}"
        fi
    done
}

# ============================================
# Signal Linking
# ============================================
link_signal() {
    echo -e "\n${BLUE}[12/13] Signal device linking...${NC}"
    
    if [[ -z "$SIGNAL_NUMBER" ]]; then
        echo -e "   ${YELLOW}⚠️  SIGNAL_NUMBER not set in .env${NC}"
        echo -e "   ${YELLOW}Run this command after updating .env:${NC}"
        echo -e "   ${BLUE}docker exec -it signal-cli signal-cli link -n ai-platform${NC}"
        return 0
    fi
    
    # Check if already linked
    if docker exec signal-cli signal-cli listAccounts 2>/dev/null | grep -q "$SIGNAL_NUMBER"; then
        echo -e "   ${GREEN}✅ Signal already linked to $SIGNAL_NUMBER${NC}"
        return 0
    fi
    
    echo -e "   ${YELLOW}⚠️  Signal not linked yet${NC}"
    echo -e "   ${BLUE}Run: docker exec -it signal-cli signal-cli link -n ai-platform${NC}"
    echo -e "   ${BLUE}Then scan QR code with Signal mobile app${NC}"
}

# ============================================
# Verification
# ============================================
verify_deployment() {
    echo -e "\n${BLUE}[13/13] Verifying deployment...${NC}"
    
    local all_healthy=true
    
    # Check Ollama
    if curl -sf http://localhost:11434/api/tags &> /dev/null; then
        echo -e "   ${GREEN}✅ Ollama responding${NC}"
    else
        echo -e "   ${YELLOW}⚠️  Ollama not responding${NC}"
        all_healthy=false
    fi
    
    # Check LiteLLM
    if curl -sf http://localhost:4000/health &> /dev/null; then
        echo -e "   ${GREEN}✅ LiteLLM responding${NC}"
    else
        echo -e "   ${YELLOW}⚠️  LiteLLM not responding${NC}"
        all_healthy=false
    fi
    
    # Check Dify
    if curl -sf http://localhost:5001 &> /dev/null; then
        echo -e "   ${GREEN}✅ Dify responding${NC}"
    else
        echo -e "   ${YELLOW}⚠️  Dify not responding${NC}"
        all_healthy=false
    fi
    
    # Check AnythingLLM
    if curl -sf http://localhost:3001 &> /dev/null; then
        echo -e "   ${GREEN}✅ AnythingLLM responding${NC}"
    else
        echo -e "   ${YELLOW}⚠️  AnythingLLM not responding${NC}"
        all_healthy=false
    fi
    
    # Check Signal API
    if curl -sf http://localhost:8080/v1/health &> /dev/null; then
        echo -e "   ${GREEN}✅ Signal API responding${NC}"
    else
        echo -e "   ${YELLOW}⚠️  Signal API not responding${NC}"
        all_healthy=false
    fi
    
    if [[ "$all_healthy" == "true" ]]; then
        echo -e "\n   ${GREEN}✅ All services verified${NC}"
    else
        echo -e "\n   ${YELLOW}⚠️  Some services may need more time to start${NC}"
        echo -e "   ${BLUE}Check with: docker ps${NC}"
    fi
}

# ============================================
# Cleanup checkpoint file
# ============================================
cleanup_checkpoint() {
    rm -f "$CHECKPOINT_FILE"
}

# ============================================
# Summary Display
# ============================================
show_summary() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "GPU Status: $([ "$HAS_GPU" == "true" ] && echo "Enabled" || echo "CPU-only")"
    echo ""
    echo "Services running:"
    echo "  Ollama:       http://localhost:11434"
    echo "  LiteLLM:      http://localhost:4000"
    echo "  Dify:         http://localhost:5001"
    echo "  AnythingLLM:  http://localhost:3001"
    echo "  Signal API:   http://localhost:8080"
    echo ""
    
    if command -v tailscale &> /dev/null && tailscale status &> /dev/null; then
        echo "Tailscale access:"
        echo "  Ollama:       http://$(tailscale ip -4):11434"
        echo "  LiteLLM:      http://$(tailscale ip -4):4000"
        echo "  Dify:         http://$(tailscale ip -4):5001"
        echo "  AnythingLLM:  http://$(tailscale ip -4):3001"
        echo "  Signal API:   http://$(tailscale ip -4):8080"
        echo ""
    fi
    
    echo "Next steps:"
    echo "  1. Link Signal device:"
    echo "     docker exec -it signal-cli signal-cli link -n ai-platform"
    echo ""
    echo "  2. After linking, verify:"
    echo "     docker exec signal-cli signal-cli listAccounts"
    echo ""
    echo "  3. Update .env with your Signal number"
    echo ""
    echo "  4. Deploy ClawdBot:"
    echo "     ./deploy-clawdbot.sh"
    echo ""
    echo "  5. Test services:"
    echo "     curl http://localhost:11434/api/tags"
    echo ""
    echo "Management:"
    echo "  Full rollback: ./deploy-services.sh --rollback"
    echo "  View logs:     docker compose -f stacks/<service>/docker-compose.yml logs -f"
    echo "  Restart:       docker compose -f stacks/<service>/docker-compose.yml restart"
    echo ""
}

# ============================================
# Main Execution
# ============================================
main() {
    # Check for rollback flag
    if [[ "$1" == "--rollback" ]] || [[ "$1" == "-r" ]]; then
        load_environment
        full_rollback
        exit 0
    fi
    
    rm -f "$CHECKPOINT_FILE"
    touch "$CHECKPOINT_FILE"
    
    cleanup_orphans
    load_environment
    check_prerequisites
    create_stack_dirs
    create_ollama_stack
    create_litellm_stack
    create_dify_stack
    create_anythingllm_stack
    create_signal_stack
    
    deploy_stack "ollama" "10"
    deploy_stack "litellm" "10"
    deploy_stack "signal" "10"
    deploy_stack "dify" "10"
    deploy_stack "anythingllm" "10"
    
    pull_models
    link_signal
    verify_deployment
    cleanup_checkpoint
    show_summary
}

main "$@"

chmod +x ~/ai-platform-installer/deploy-services.sh
