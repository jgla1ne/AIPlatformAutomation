#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - Configure Services v2.0
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
LOG_FILE="$SCRIPT_DIR/logs/configure-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

echo ""
log "${BLUE}========================================${NC}"
log "${BLUE}AI Platform - Service Configuration${NC}"
log "${BLUE}Repository: $(basename "$SCRIPT_DIR")${NC}"
log "${BLUE}========================================${NC}"
echo ""

# Load environment
if [[ ! -f "$ENV_FILE" ]]; then
    log "${RED}❌ Environment file not found${NC}"
    exit 1
fi

source "$ENV_FILE"

# ============================================
# [1/5] Configure LiteLLM in Dify
# ============================================
configure_dify_litellm() {
    log "${BLUE}[1/5] Configure LiteLLM in Dify${NC}"
    echo ""
    
    log "${YELLOW}Manual Configuration Required:${NC}"
    echo ""
    echo "1. Open Dify: http://localhost:3000"
    echo "2. Create admin account (first login)"
    echo "3. Go to: Settings → Model Providers"
    echo "4. Add OpenAI-Compatible provider:"
    echo ""
    echo "   Name: LiteLLM"
    echo "   API Base: http://litellm:4000"
    echo "   API Key: $LITELLM_MASTER_KEY"
    echo "   Models: llama3.2, qwen2.5-coder"
    echo ""
    
    read -p "Press Enter after configuring..."
    
    log "${GREEN}✓ LiteLLM configured in Dify${NC}"
    echo ""
}

# ============================================
# [2/5] Configure AnythingLLM
# ============================================
configure_anythingllm() {
    log "${BLUE}[2/5] Configure AnythingLLM${NC}"
    echo ""
    
    log "${YELLOW}Manual Configuration Required:${NC}"
    echo ""
    echo "1. Open AnythingLLM: http://localhost:3001"
    echo "2. Create admin account (first login)"
    echo "3. Go to: Settings → LLM Providers"
    echo "4. Select: OpenAI Compatible"
    echo "5. Configure:"
    echo ""
    echo "   API Base: http://litellm:4000"
    echo "   API Key: $LITELLM_MASTER_KEY"
    echo "   Model: llama3.2"
    echo ""
    echo "6. Test connection"
    echo ""
    
    read -p "Press Enter after configuring..."
    
    log "${GREEN}✓ AnythingLLM configured${NC}"
    echo ""
}

# ============================================
# [3/5] Create Test Workspace
# ============================================
create_test_workspace() {
    log "${BLUE}[3/5] Create Test Workspace${NC}"
    echo ""
    
    log "${YELLOW}Create a test workspace in AnythingLLM:${NC}"
    echo ""
    echo "1. In AnythingLLM, click '+ New Workspace'"
    echo "2. Name: 'Test Workspace'"
    echo "3. Upload a test document (PDF/TXT)"
    echo "4. Ask a question about the document"
    echo "5. Verify RAG is working"
    echo ""
    
    read -p "Press Enter after testing..."
    
    log "${GREEN}✓ Test workspace created${NC}"
    echo ""
}

# ============================================
# [4/5] Configure Dify Workflow
# ============================================
configure_dify_workflow() {
    log "${BLUE}[4/5] Configure Dify Workflow${NC}"
    echo ""
    
    log "${YELLOW}Create a test workflow in Dify:${NC}"
    echo ""
    echo "1. In Dify, click '+ Create App'"
    echo "2. Choose 'Chatbot' type"
    echo "3. Configure:"
    echo "   - Model: LiteLLM / llama3.2"
    echo "   - System prompt: 'You are a helpful assistant'"
    echo "   - Temperature: 0.7"
    echo "4. Test the chatbot"
    echo "5. Publish when ready"
    echo ""
    
    read -p "Press Enter after configuring..."
    
    log "${GREEN}✓ Dify workflow configured${NC}"
    echo ""
}

# ============================================
# [5/5] Verify All Services
# ============================================
verify_services() {
    log "${BLUE}[5/5] Verifying all services...${NC}"
    echo ""
    
    # Check Ollama
    if curl -sf http://localhost:11434 > /dev/null; then
        log "   ${GREEN}✓ Ollama${NC} - http://localhost:11434"
    else
        log "   ${RED}✗ Ollama${NC} - not responding"
    fi
    
    # Check LiteLLM
    if curl -sf http://localhost:4000/health > /dev/null; then
        log "   ${GREEN}✓ LiteLLM${NC} - http://localhost:4000"
    else
        log "   ${RED}✗ LiteLLM${NC} - not responding"
    fi
    
    # Check Signal
    if docker ps | grep -q signal-api; then
        log "   ${GREEN}✓ Signal API${NC} - http://localhost:8080"
    else
        log "   ${RED}✗ Signal API${NC} - not running"
    fi
    
    # Check Dify
    if docker ps | grep -q dify-web; then
        log "   ${GREEN}✓ Dify${NC} - http://localhost:3000"
    else
        log "   ${RED}✗ Dify${NC} - not running"
    fi
    
    # Check AnythingLLM
    if docker ps | grep -q anythingllm; then
        log "   ${GREEN}✓ AnythingLLM${NC} - http://localhost:3001"
    else
        log "   ${RED}✗ AnythingLLM${NC} - not running"
    fi
    
    # Check ClawdBot
    if docker ps | grep -q clawdbot; then
        log "   ${GREEN}✓ ClawdBot${NC} - Active"
    else
        log "   ${RED}✗ ClawdBot${NC} - not running"
    fi
    
    echo ""
}

# ============================================
# Final Summary
# ============================================
print_summary() {
    log "${GREEN}========================================${NC}"
    log "${GREEN}✅ Platform Configuration Complete${NC}"
    log "${GREEN}========================================${NC}"
    echo ""
    
    log "${BLUE}Access URLs:${NC}"
    log "  Ollama:       http://localhost:11434"
    log "  LiteLLM:      http://localhost:4000"
    log "  Signal API:   http://localhost:8080"
    log "  Dify:         http://localhost:3000"
    log "  AnythingLLM:  http://localhost:3001"
    echo ""
    
    log "${BLUE}Credentials:${NC}"
    log "  LiteLLM Key:  $LITELLM_MASTER_KEY"
    log "  Dify DB Pass: $DIFY_DB_PASSWORD"
    log "  Signal Num:   ${SIGNAL_NUMBER:-Not configured}"
    echo ""
    
    log "${BLUE}Quick Commands:${NC}"
    log "  View all logs:     docker ps"
    log "  ClawdBot logs:     docker logs -f clawdbot"
    log "  Restart service:   docker restart <service>"
    log "  Stop all:          cd $SCRIPT_DIR/stacks && docker compose down"
    echo ""
    
    log "${YELLOW}Important Files:${NC}"
    log "  Environment: $ENV_FILE"
    log "  Stacks:      $SCRIPT_DIR/stacks/"
    log "  Logs:        $SCRIPT_DIR/logs/"
    log "  Data:        /mnt/data/"
    echo ""
    
    log "${GREEN}🎉 Your AI Platform is ready!${NC}"
    echo ""
}

# ============================================
# Main Execution
# ============================================
main() {
    configure_dify_litellm
    configure_anythingllm
    create_test_workspace
    configure_dify_workflow
    verify_services
    print_summary
}

main "$@"

chmod +x scripts/5-configure-services.sh
