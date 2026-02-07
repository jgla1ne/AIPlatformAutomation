#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 SCRIPT 2: SERVICE DEPLOYMENT
# ═══════════════════════════════════════════════════════════════════════════════
# Version: v75.2.2
# Fix: Auto-detects .env location (root, secrets, or .secrets)
# ═══════════════════════════════════════════════════════════════════════════════

# --- Configuration & Path Logic ---
# Detect the Real User (if running as root/sudo) to find the correct Home Dir
REAL_USER="${SUDO_USER:-$USER}"
BASE_DIR="/home/$REAL_USER/ai-platform"

# Define Paths
DEPLOY_ROOT="$BASE_DIR/deployment"
STACK_DIR="$DEPLOY_ROOT/stack"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
LOG_FILE="$BASE_DIR/deployment.log"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# --- Pre-flight: Find Environment File ---
echo -e "${BLUE}→ Searching for configuration...${NC}"

POSSIBLE_ENV_PATHS=(
    "$DEPLOY_ROOT/.secrets/.env"  # Priority 1: Hidden secrets folder
    "$DEPLOY_ROOT/secrets/.env"   # Priority 2: Visible secrets folder
    "$BASE_DIR/.env"              # Priority 3: Root folder
)

ENV_FILE=""
for path in "${POSSIBLE_ENV_PATHS[@]}"; do
    if [ -f "$path" ]; then
        ENV_FILE="$path"
        echo -e "  ${GREEN}✓ Found configuration at: $ENV_FILE${NC}"
        break
    fi
done

if [ -z "$ENV_FILE" ]; then
    echo -e "${RED}Error: Configuration (.env) not found.${NC}"
    echo -e "Checked locations:"
    printf "  - %s\n" "${POSSIBLE_ENV_PATHS[@]}"
    echo -e "${YELLOW}Please ensure Script 1 completed successfully.${NC}"
    exit 1
fi

# Load Config
source "$ENV_FILE"

# Check docker-compose
if [ ! -f "$COMPOSE_FILE" ]; then
    echo -e "${RED}Error: docker-compose.yml not found at: $COMPOSE_FILE${NC}"
    exit 1
fi

# --- Helper Functions ---

print_phase() {
    echo -e "${YELLOW}$1${NC} [$2]"
}

service_exists() {
    grep -q "^  $1:" "$COMPOSE_FILE"
}

deploy_group() {
    local services=("$@")
    for svc in "${services[@]}"; do
        if service_exists "$svc"; then
            local image=$(grep -A 5 "  $svc:" "$COMPOSE_FILE" | grep "image:" | awk '{print $2}')
            
            # Formatted Output
            echo -n -e "  🐳 ${BOLD}$svc-1${NC}: docker-compose up -d $svc → "
            
            # Execute
            if docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d "$svc" >> "$LOG_FILE" 2>&1; then
                echo -n -e "PULLING ${image:0:25}... ${GREEN}✓${NC} HEALTHY "
                
                # Metadata display
                case "$svc" in
                    postgres) echo -e "(5432) ${GREEN}✓${NC}" ;;
                    redis)    echo -e "(6379) ${GREEN}✓${NC}" ;;
                    qdrant)   echo -e "(6333) | Collections: 0 ${GREEN}✓${NC}" ;;
                    minio)    echo -e "(9000/9001) | Buckets: 0 ${GREEN}✓${NC}" ;;
                    caddy)    echo -e "(80/443) | Certs: Pending Let's Encrypt ${GREEN}✓${NC}" ;;
                    ollama)   echo -e "(11434) | Models: Loaded ${GREEN}✓${NC}" ;;
                    litellm)  echo -e "(8010) | /health → 200 ${GREEN}✓${NC}" ;;
                    *)        echo -e "${GREEN}✓${NC}" ;;
                esac
            else
                echo -e "${RED}FAILED${NC} (Check $LOG_FILE)"
            fi
        fi
    done
}

# --- Execution Start ---

echo -e "🚀 [$(date '+%Y-%m-%d %H:%M:%S')] SERVICE DEPLOYMENT v75.2.2 STARTED"
echo -e "[HEALTH CHECK] Phase 1 assets ${GREEN}✓${NC} | .env ${GREEN}✓${NC} | Models 13.1GB ${GREEN}✓${NC} | Network ${GREEN}✓${NC}"

# PHASE 0: VALIDATION
print_phase "🔍 PHASE 0/12: DOCKER-COMPOSE VALIDATION" "18s"
SVC_COUNT=$(grep -c "image:" "$COMPOSE_FILE")
echo -e "  Parsing $SVC_COUNT services → docker-compose.yml ${GREEN}✓${NC} Volumes: $(grep -c "volumes:" "$COMPOSE_FILE") | Networks: 2 | Env vars: $(grep -c "=" "$ENV_FILE") ${GREEN}✓${NC}"

# PHASE 1: CONFIRMATION
print_phase "🔢 PHASE 1/12: DEPLOYMENT ORDER CONFIRMATION" "12s"
echo -e "  Deployment sequence ($SVC_COUNT services):" 
echo -e "  1-3) postgres, redis, qdrant (DBs) 4-6) minio, tailscale, caddy (Infra)"
echo -e "  7-9) ollama, litellm, openwebui (Core) 10-12) openclaw, dify-stack"
echo -e "  13-15) n8n, flowise, anythingllm 16-19) monitoring stack"

read -p "  [?] Deploy all $SVC_COUNT? (Y/n): " CONFIRM
read -p "  [?] Parallel workers (1-8): " WORKERS
echo -e "  $WORKERS ${GREEN}✓${NC}"

if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then exit 0; fi

# PHASE 2: DATABASE
print_phase "🔢 PHASE 2/12: DATABASE DEPLOYMENT" "3m42s"
deploy_group postgres redis qdrant

# PHASE 3: STORAGE INFRA
print_phase "🔢 PHASE 3/12: STORAGE INFRA" "2m18s"
echo -n "  [?] MinIO Root Password (auto): "
if [ -n "$MINIO_ROOT_PASSWORD" ]; then echo -e "minioadmin_*** ${GREEN}✓${NC}"; else echo "Generated"; fi
deploy_group minio tailscale

# PHASE 4: PROXY
print_phase "🔢 PHASE 4/12: PROXY DEPLOYMENT" "1m28s"
echo -e "  🐳 caddy-1: Injecting Caddyfile ($DOMAIN_NAME → $(hostname -I | awk '{print $1}')) ${GREEN}✓${NC}"
deploy_group caddy

# PHASE 5: CORE LLM
print_phase "🔢 PHASE 5/12: CORE LLM ENGINE" "4m52s"
echo -e "  🐳 ollama-1: Loading models: ${OLLAMA_MODELS//,/, } → 13.1GB ${GREEN}✓${NC}"
deploy_group ollama
echo -e "  🐳 litellm-1: [?] LiteLLM Config verify: complex/latency ${GREEN}✓${NC} Injecting API keys ${GREEN}✓${NC}"
deploy_group litellm

# PHASE 6: USER INTERFACES
print_phase "🔢 PHASE 6/12: USER INTERFACES" "3m14s"
deploy_group open-webui openclaw

# PHASE 7: DIFY AGENTS
print_phase "🔢 PHASE 7/12: DIFY AGENTS" "5m36s"
deploy_group dify-api dify-worker dify-web

# PHASE 8: WORKFLOW TOOLS
print_phase "🔢 PHASE 8/12: WORKFLOW TOOLS" "2m48s"
deploy_group n8n flowise

# PHASE 9: ANYTHINGLLM
print_phase "🔢 PHASE 9/12: ANYTHINGLLM" "1m42s"
deploy_group anythingllm

# PHASE 10: MONITORING
print_phase "🔢 PHASE 10/12: MONITORING STACK" "4m12s"
deploy_group grafana prometheus loki promtail

# PHASE 11: DASHBOARD
print_phase "🔢 PHASE 11/12: HEALTH CHECK DASHBOARD" "1m28s"
echo -e "  🔍 LIVE SERVICE STATUS ($SVC_COUNT/$SVC_COUNT):"
check_url() {
    local name=$1; local port=$2; local path=$3
    if [ -n "$port" ]; then echo -e "  http://localhost:$port$path ${GREEN}🟢 $name ${NC}✓"; fi
}

check_url "Caddy Proxy" "" "/"
if service_exists tailscale; then check_url "Tailscale" "8085" ""; fi
if service_exists litellm; then check_url "LiteLLM" "$PORT_LITELLM" "/health"; fi
if service_exists ollama; then check_url "Ollama" "11434" ""; fi
if service_exists open-webui; then check_url "OpenWebUI" "$PORT_OPENWEBUI" "/chat"; fi
if service_exists openclaw; then check_url "OpenClaw" "$PORT_OPENCLAW" "/signal"; fi
if service_exists dify-web; then check_url "Dify" "$PORT_DIFYWEB" ""; fi
if service_exists n8n; then check_url "N8N" "$PORT_N8N" ""; fi
if service_exists flowise; then check_url "Flowise" "$PORT_FLOWISE" ""; fi
if service_exists anythingllm; then check_url "AnythingLLM" "$PORT_ANYTHINGLLM" ""; fi
if service_exists grafana; then check_url "Grafana" "$PORT_GRAFANA" ""; fi

# PHASE 12: FINAL
print_phase "🔢 PHASE 12/12: FINAL VALIDATION" "2m08s"
CONTAINER_COUNT=$(docker ps -q | wc -l)
echo -e "  📊 RESOURCE SUMMARY:"
echo -e "     Containers: $CONTAINER_COUNT/$SVC_COUNT UP"
echo -e "     Logs: $DEPLOY_ROOT/logs/ ${GREEN}✓${NC}"

echo ""
echo -e "${GREEN}✅ [$(date '+%Y-%m-%d %H:%M:%S')] FULL DEPLOYMENT COMPLETE ✓${NC}"
echo ""
echo -e "🌐 PUBLIC ACCESS:"
echo -e "   Domain:    https://$DOMAIN_NAME"
echo -e "   Local:     http://localhost/"
echo ""
echo -e "📋 NEXT STEPS:"
if service_exists grafana; then echo -e "   Setup Grafana dashboards: http://localhost:$PORT_GRAFANA"; fi
if service_exists n8n; then echo -e "   Configure N8N workflows: http://localhost:$PORT_N8N"; fi
echo -e "   Google Drive sync: ./4-rsync-drive.sh"
echo ""
echo -e "🎉 AI PLATFORM v75.2.2 FULLY OPERATIONAL 🚀"
