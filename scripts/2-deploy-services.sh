#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - Deploy Services v5.0
# Idempotent deployment with proper cleanup
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="/var/log/ai-platform-deploy.log"

sudo touch "$LOG_FILE" 2>/dev/null || LOG_FILE="$HOME/ai-platform-deploy.log"
sudo chown $USER:$USER "$LOG_FILE" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================
# Load Environment
# ============================================
load_environment() {
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        echo -e "${RED}❌ .env not found. Run 1-setup-system.sh first${NC}"
        exit 1
    fi

    source "$SCRIPT_DIR/.env"

    if [[ -f "$SCRIPT_DIR/.secrets" ]]; then
        source "$SCRIPT_DIR/.secrets"
    fi
}

# ============================================
# Parse Arguments
# ============================================
ROLLBACK=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --rollback)
            ROLLBACK=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--rollback] [--force]"
            exit 1
            ;;
    esac
done

# ============================================
# Rollback Function
# ============================================
do_rollback() {
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Rollback Mode${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo "This will:"
    echo "  • Stop all containers"
    echo "  • Remove all containers"
    echo "  • Clean stacks/ directory"
    echo ""
    echo "Preserved:"
    echo "  ✅ .env and .secrets"
    echo "  ✅ configs/ templates"
    echo "  ✅ Data in $DATA_PATH"
    echo ""

    read -p "Continue with rollback? (y/n): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi

    echo ""
    echo -e "${BLUE}Stopping all containers...${NC}"
    docker ps -q | xargs -r docker stop

    echo -e "${BLUE}Removing all containers...${NC}"
    docker ps -aq | xargs -r docker rm

    echo -e "${BLUE}Cleaning stacks directory...${NC}"
    rm -rf "$SCRIPT_DIR/stacks/*"

    echo ""
    echo -e "${GREEN}✅ Rollback complete${NC}"
    echo "Run ./2-deploy-services.sh to redeploy"
    exit 0
}

[[ "$ROLLBACK" == "true" ]] && do_rollback

# ============================================
# Pre-deployment Checks
# ============================================
preflight_checks() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}AI Platform - Deploy Services v5.0${NC}"
    echo -e "${BLUE}Started: $(date)${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    echo -e "${BLUE}[1/9] Pre-deployment checks...${NC}"

    # Check Docker
    if ! docker info &> /dev/null; then
        echo -e "   ${RED}❌ Docker not running${NC}"
        exit 1
    fi

    # Check network
    if ! docker network ls | grep -q "ai-platform-network"; then
        echo -e "   ${RED}❌ Docker network missing${NC}"
        exit 1
    fi

    # Check configs
    if [[ ! -d "$SCRIPT_DIR/configs" ]]; then
        echo -e "   ${RED}❌ configs/ directory missing${NC}"
        exit 1
    fi

    # Check GPU if needed
    if command -v nvidia-smi &> /dev/null; then
        echo -e "   ${GREEN}✅ GPU available${NC}"
    else
        echo -e "   ${YELLOW}⚠️  No GPU (Ollama will use CPU)${NC}"
    fi

    echo -e "   ${GREEN}✅ Pre-flight checks passed${NC}"
}

# ============================================
# Prepare Stacks Directory
# ============================================
prepare_stacks() {
    echo -e "\n${BLUE}[2/9] Preparing stacks directory...${NC}"

    # Create stacks if missing
    mkdir -p "$SCRIPT_DIR/stacks"

    # Copy configs to stacks (idempotent)
    for service in signal ollama litellm dify anythingllm; do
        if [[ -d "$SCRIPT_DIR/configs/$service" ]]; then
            mkdir -p "$SCRIPT_DIR/stacks/$service"

            # Copy docker-compose.yml if exists
            if [[ -f "$SCRIPT_DIR/configs/$service/docker-compose.yml" ]]; then
                cp "$SCRIPT_DIR/configs/$service/docker-compose.yml" \
                   "$SCRIPT_DIR/stacks/$service/docker-compose.yml"
                echo "   Prepared: $service"
            fi

            # Copy additional configs
            for file in "$SCRIPT_DIR/configs/$service"/*; do
                if [[ -f "$file" ]] && [[ "$(basename "$file")" != "docker-compose.yml" ]]; then
                    cp "$file" "$SCRIPT_DIR/stacks/$service/"
                fi
            done
        fi
    done

    echo -e "   ${GREEN}✅ Stacks prepared from configs/\${NC}"
}

# ============================================
# Deploy Ollama
# ============================================
deploy_ollama() {
    echo -e "\n${BLUE}[3/9] Deploying Ollama...${NC}"

    cd "$SCRIPT_DIR/stacks/ollama"

    # Substitute environment variables
    envsubst < docker-compose.yml > docker-compose.tmp.yml
    mv docker-compose.tmp.yml docker-compose.yml

    # Deploy
    docker compose up -d

    # Wait for ready
    echo -n "   Waiting for Ollama"
    for i in {1..30}; do
        if curl -sf http://localhost:11434/api/tags &> /dev/null; then
            echo ""
            echo -e "   ${GREEN}✅ Ollama ready${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
    done

    echo ""
    echo -e "   ${YELLOW}⚠️  Ollama slow to start${NC}"
}

# ============================================
# Pull Ollama Models
# ============================================
pull_ollama_models() {
    echo -e "\n${BLUE}[4/9] Pulling Ollama models...${NC}"

    if [[ -z "${OLLAMA_MODELS:-}" ]]; then
        echo -e "   ${YELLOW}⚠️  No models specified${NC}"
        return 0
    fi

    IFS=',' read -ra MODELS <<< "$OLLAMA_MODELS"

    for model in "${MODELS[@]}"; do
        model=$(echo "$model" | xargs)
        echo -e "   Pulling: $model"

        if docker exec ollama ollama pull "$model" 2>&1 | grep -q "success"; then
            echo -e "   ${GREEN}✅ $model${NC}"
        else
            echo -e "   ${YELLOW}⚠️  $model failed${NC}"
        fi
    done
}

# ============================================
# Deploy LiteLLM
# ============================================
deploy_litellm() {
    echo -e "\n${BLUE}[5/9] Deploying LiteLLM...${NC}"

    cd "$SCRIPT_DIR/stacks/litellm"

    envsubst < docker-compose.yml > docker-compose.tmp.yml
    mv docker-compose.tmp.yml docker-compose.yml

    docker compose up -d

    echo -n "   Waiting for LiteLLM"
    for i in {1..20}; do
        if curl -sf http://localhost:4000/health &> /dev/null; then
            echo ""
            echo -e "   ${GREEN}✅ LiteLLM ready${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
    done

    echo ""
    echo -e "   ${YELLOW}⚠️  LiteLLM slow to start${NC}"
}

# ============================================
# Deploy Signal
# ============================================
deploy_signal() {
    echo -e "\n${BLUE}[6/9] Deploying Signal API...${NC}"

    cd "$SCRIPT_DIR/stacks/signal"

    envsubst < docker-compose.yml > docker-compose.tmp.yml
    mv docker-compose.tmp.yml docker-compose.yml

    docker compose up -d

    echo -n "   Waiting for Signal API"
    for i in {1..30}; do
        if curl -sf http://localhost:8080/v1/health &> /dev/null; then
            echo ""
            echo -e "   ${GREEN}✅ Signal API ready${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
    done

    echo ""
    echo -e "   ${YELLOW}⚠️  Signal API slow to start${NC}"
}

# ============================================
# Deploy Dify
# ============================================
deploy_dify() {
    echo -e "\n${BLUE}[7/9] Deploying Dify...${NC}"

    cd "$SCRIPT_DIR/stacks/dify"

    envsubst < docker-compose.yml > docker-compose.tmp.yml
    mv docker-compose.tmp.yml docker-compose.yml

    docker compose up -d

    echo -n "   Waiting for Dify"
    for i in {1..60}; do
        if curl -sf http://localhost:5001/health &> /dev/null; then
            echo ""
            echo -e "   ${GREEN}✅ Dify ready${NC}"
            return 0
        fi
        echo -n "."
        sleep 3
    done

    echo ""
    echo -e "   ${YELLOW}⚠️  Dify slow to start (check logs)${NC}"
}

# ============================================
# Deploy AnythingLLM
# ============================================
deploy_anythingllm() {
    echo -e "\n${BLUE}[8/9] Deploying AnythingLLM...${NC}"

    cd "$SCRIPT_DIR/stacks/anythingllm"

    envsubst < docker-compose.yml > docker-compose.tmp.yml
    mv docker-compose.tmp.yml docker-compose.yml

    docker compose up -d

    echo -n "   Waiting for AnythingLLM"
    for i in {1..30}; do
        if curl -sf http://localhost:3001/ &> /dev/null; then
            echo ""
            echo -e "   ${GREEN}✅ AnythingLLM ready${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
    done

    echo ""
    echo -e "   ${YELLOW}⚠️  AnythingLLM slow to start${NC}"
}

# ============================================
# Deployment Summary
# ============================================
print_summary() {
    echo -e "\n${BLUE}[9/9] Deployment summary...${NC}"
    echo ""

    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(ollama|litellm|signal|dify|anythingllm)"

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Services Deployed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}Service Status:${NC}"

    # Check each service
    curl -sf http://localhost:11434/api/tags &> /dev/null && \
        echo -e "  ${GREEN}✅${NC} Ollama      http://localhost:11434" || \
        echo -e "  ${RED}❌${NC} Ollama      http://localhost:11434"

    curl -sf http://localhost:4000/health &> /dev/null && \
        echo -e "  ${GREEN}✅${NC} LiteLLM     http://localhost:4000" || \
        echo -e "  ${RED}❌${NC} LiteLLM     http://localhost:4000"

    curl -sf http://localhost:8080/v1/health &> /dev/null && \
        echo -e "  ${GREEN}✅${NC} Signal API  http://localhost:8080" || \
        echo -e "  ${RED}❌${NC} Signal API  http://localhost:8080"

    curl -sf http://localhost:5001/health &> /dev/null && \
        echo -e "  ${GREEN}✅${NC} Dify        http://localhost:5001" || \
        echo -e "  ${RED}❌${NC} Dify        http://localhost:5001"

    curl -sf http://localhost:3001/ &> /dev/null && \
        echo -e "  ${GREEN}✅${NC} AnythingLLM http://localhost:3001" || \
        echo -e "  ${RED}❌${NC} AnythingLLM http://localhost:3001"

    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Link Signal device:"
    echo "     ./3-link-signal-device.sh"
    echo ""
    echo "  2. Deploy ClawdBot (after Signal linked):"
    echo "     ./4-deploy-clawdbot.sh"
    echo ""
    echo "  3. Configure all services:"
    echo "     ./5-configure-services.sh"
    echo ""
    echo -e "${BLUE}Management:${NC}"
    echo "  • View logs:    docker logs -f <container-name>"
    echo "  • Restart:      cd stacks/<service> && docker compose restart"
    echo "  • Full rollback: ./2-deploy-services.sh --rollback"
    echo ""
}

# ============================================
# Main Execution
# ============================================
main() {
    load_environment
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

chmod +x ~/ai-platform-installer/scripts/2-deploy-services.sh
