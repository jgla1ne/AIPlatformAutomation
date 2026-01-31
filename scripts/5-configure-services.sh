#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - Configure Services v5.0
# Post-deployment configuration and testing
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="/var/log/ai-platform-configure.log"

sudo touch "$LOG_FILE" 2>/dev/null || LOG_FILE="$HOME/ai-platform-configure.log"
sudo chown $USER:$USER "$LOG_FILE" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================
# Load Environment
# ============================================
load_environment() {
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        echo -e "${RED}❌ .env not found${NC}"
        exit 1
    fi

    source "$SCRIPT_DIR/.env"

    if [[ -f "$SCRIPT_DIR/.secrets" ]]; then
        source "$SCRIPT_DIR/.secrets"
    fi
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Configure AI Platform v5.0${NC}"
echo -e "${BLUE}Started: $(date)${NC}"
echo -e "${BLUE}========================================${NC}"

load_environment

# ============================================
# Verify All Services
# ============================================
verify_services() {
    echo -e "\n${BLUE}[1/8] Verifying all services...${NC}"
    echo ""

    local all_ok=true

    # Ollama
    echo -n "  Ollama (11434)... "
    if curl -sf http://localhost:11434/api/tags &> /dev/null; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${RED}❌${NC}"
        all_ok=false
    fi

    # LiteLLM
    echo -n "  LiteLLM (4000)... "
    if curl -sf http://localhost:4000/health &> /dev/null; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${YELLOW}⚠️${NC}"
    fi

    # Signal API
    echo -n "  Signal API (8080)... "
    if curl -sf http://localhost:8080/v1/health &> /dev/null; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${RED}❌${NC}"
        all_ok=false
    fi

    # Dify
    echo -n "  Dify (5001)... "
    if curl -sf http://localhost:5001/health &> /dev/null; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${YELLOW}⚠️${NC}"
    fi

    # AnythingLLM
    echo -n "  AnythingLLM (3001)... "
    if curl -sf http://localhost:3001/ &> /dev/null; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${YELLOW}⚠️${NC}"
    fi

    # ClawdBot
    echo -n "  ClawdBot... "
    if docker ps | grep -q "clawdbot"; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${YELLOW}⚠️${NC}"
    fi

    if [[ "$all_ok" != "true" ]]; then
        echo ""
        echo -e "${YELLOW}⚠️  Some services not responding${NC}"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
}

# ============================================
# Test Ollama Models
# ============================================
test_ollama() {
    echo -e "\n${BLUE}[2/8] Testing Ollama models...${NC}"

    local models=$(curl -sf http://localhost:11434/api/tags | jq -r '.models[].name' 2>/dev/null)

    if [[ -z "$models" ]]; then
        echo -e "   ${YELLOW}⚠️  No models found${NC}"
        return 0
    fi

    echo "   Available models:"
    echo "$models" | sed 's/^/     • /'

    echo ""
    read -p "   Test a model? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        local test_model=$(echo "$models" | head -1)
        echo ""
        echo "   Testing: $test_model"

        local response=$(curl -sf http://localhost:11434/api/generate -d "{
            \"model\": \"$test_model\",
            \"prompt\": \"Say hello in one sentence.\",
            \"stream\": false
        }" | jq -r '.response' 2>/dev/null)

        if [[ -n "$response" ]]; then
            echo -e "   ${GREEN}✅ Response: $response${NC}"
        else
            echo -e "   ${RED}❌ No response${NC}"
        fi
    fi
}

# ============================================
# Configure LiteLLM
# ============================================
configure_litellm() {
    echo -e "\n${BLUE}[3/8] Configuring LiteLLM...${NC}"

    if ! curl -sf http://localhost:4000/health &> /dev/null; then
        echo -e "   ${YELLOW}⚠️  LiteLLM not running, skipping${NC}"
        return 0
    fi

    # Test LiteLLM
    echo "   Testing LiteLLM proxy..."

    local test_response=$(curl -sf http://localhost:4000/v1/models 2>/dev/null)

    if [[ -n "$test_response" ]]; then
        echo -e "   ${GREEN}✅ LiteLLM responding${NC}"
        echo "   Available models:"
        echo "$test_response" | jq -r '.data[].id' 2>/dev/null | sed 's/^/     • /' || echo "     (none)"
    else
        echo -e "   ${YELLOW}⚠️  LiteLLM not configured properly${NC}"
    fi
}

# ============================================
# Configure AnythingLLM
# ============================================
configure_anythingllm() {
    echo -e "\n${BLUE}[4/8] Configuring AnythingLLM...${NC}"

    if ! curl -sf http://localhost:3001/ &> /dev/null; then
        echo -e "   ${YELLOW}⚠️  AnythingLLM not running, skipping${NC}"
        return 0
    fi

    echo "   AnythingLLM is running"
    echo ""
    echo "   Setup steps:"
    echo "     1. Open: http://$TAILSCALE_IP:3001"
    echo "     2. Create admin account (first time)"
    echo "     3. Configure LLM provider:"
    echo "        - Type: Ollama"
    echo "        - URL: http://ollama:11434"
    echo "        - Model: llama3.2:latest"
    echo "     4. Create workspace"
    echo "     5. Get API key from Settings"
    echo ""

    read -p "   Have you completed setup? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        read -p "   Enter AnythingLLM API key: " anythingllm_key

        # Update .secrets
        if grep -q "^export ANYTHINGLLM_API_KEY=" "$SCRIPT_DIR/.secrets"; then
            sed -i "s|^export ANYTHINGLLM_API_KEY=.*|export ANYTHINGLLM_API_KEY=\"$anythingllm_key\"|" "$SCRIPT_DIR/.secrets"
        else
            echo "export ANYTHINGLLM_API_KEY=\"$anythingllm_key\"" >> "$SCRIPT_DIR/.secrets"
        fi

        echo -e "   ${GREEN}✅ API key saved${NC}"
    fi
}

# ============================================
# Configure Dify
# ============================================
configure_dify() {
    echo -e "\n${BLUE}[5/8] Configuring Dify...${NC}"

    if ! curl -sf http://localhost:5001/health &> /dev/null; then
        echo -e "   ${YELLOW}⚠️  Dify not running, skipping${NC}"
        return 0
    fi

    echo "   Dify is running"
    echo ""
    echo "   Setup steps:"
    echo "     1. Open: http://$TAILSCALE_IP:5001"
    echo "     2. Create admin account"
    echo "        Email: admin@example.com"
    echo "        Password: (from .secrets)"
    echo "     3. Configure model provider:"
    echo "        - Add Ollama provider"
    echo "        - URL: http://ollama:11434"
    echo "     4. Create workflow or agent"
    echo ""

    echo "   Admin password: $DIFY_INIT_PASSWORD"
    echo ""
}

# ============================================
# Test Signal Integration
# ============================================
test_signal() {
    echo -e "\n${BLUE}[6/8] Testing Signal integration...${NC}"

    if [[ -z "${SIGNAL_NUMBER:-}" ]]; then
        echo -e "   ${RED}❌ SIGNAL_NUMBER not configured${NC}"
        return 1
    fi

    # Check Signal API
    if ! curl -sf http://localhost:8080/v1/health &> /dev/null; then
        echo -e "   ${RED}❌ Signal API not responding${NC}"
        return 1
    fi

    # Check registered accounts
    local accounts=$(curl -sf http://localhost:8080/v1/accounts)
    echo "   Registered accounts:"
    echo "$accounts" | jq -r '.[] | "     • \(.number) (\(.deviceId // "primary"))"' 2>/dev/null

    # Test send
    echo ""
    read -p "   Send test message to $SIGNAL_NUMBER? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "   Sending test message..."

        local test_msg="✅ AI Platform configuration test - $(date)"

        local response=$(curl -sf -X POST http://localhost:8080/v2/send \
            -H "Content-Type: application/json" \
            -d "{
                \"message\": \"$test_msg\",
                \"number\": \"$SIGNAL_NUMBER\",
                \"recipients\": [\"$SIGNAL_NUMBER\"]
            }")

        if echo "$response" | jq -e '.timestamp' &> /dev/null; then
            echo -e "   ${GREEN}✅ Test message sent${NC}"
        else
            echo -e "   ${YELLOW}⚠️  Uncertain result${NC}"
            echo "$response" | jq '.' 2>/dev/null || echo "$response"
        fi
    fi
}

# ============================================
# Test ClawdBot
# ============================================
test_clawdbot() {
    echo -e "\n${BLUE}[7/8] Testing ClawdBot...${NC}"

    if ! docker ps | grep -q "clawdbot"; then
        echo -e "   ${YELLOW}⚠️  ClawdBot not running${NC}"
        return 0
    fi

    echo "   ClawdBot status:"
    docker ps --filter "name=clawdbot" --format "     • {{.Status}}"

    echo ""
    echo "   Recent logs:"
    docker logs --tail 10 clawdbot 2>&1 | sed 's/^/     /'

    echo ""
    echo "   To test ClawdBot:"
    echo "     1. Send a message to $SIGNAL_NUMBER from your phone"
    echo "     2. ClawdBot should respond with AI-generated text"
    echo "     3. Try commands: /help, /status"
    echo ""
}

# ============================================
# Setup Systemd Services (Optional)
# ============================================
setup_systemd() {
    echo -e "\n${BLUE}[8/8] Setup auto-start (optional)...${NC}"

    read -p "   Enable services to start on boot? (y/n): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi

    echo ""
    echo "   Creating systemd service..."

    sudo tee /etc/systemd/system/ai-platform.service > /dev/null <<SERVICE_EOF
[Unit]
Description=AI Platform Services
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$SCRIPT_DIR/stacks
User=$USER

# Start all services
ExecStart=/bin/bash -c 'for dir in ollama litellm signal dify anythingllm clawdbot; do [ -d "\$dir" ] && (cd "\$dir" && /usr/bin/docker compose up -d); done'

# Stop all services
ExecStop=/bin/bash -c 'for dir in ollama litellm signal dify anythingllm clawdbot; do [ -d "\$dir" ] && (cd "\$dir" && /usr/bin/docker compose down); done'

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    sudo systemctl daemon-reload
    sudo systemctl enable ai-platform.service

    echo -e "   ${GREEN}✅ Systemd service enabled${NC}"
    echo "   Services will start automatically on boot"
}

# ============================================
# Final Summary
# ============================================
print_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Configuration Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}🎉 Your AI Platform is ready!${NC}"
    echo ""
    echo -e "${BLUE}Access Points:${NC}"
    echo "  • Ollama:       http://$TAILSCALE_IP:11434"
    echo "  • LiteLLM:      http://$TAILSCALE_IP:4000"
    echo "  • Signal API:   http://$TAILSCALE_IP:8080"
    echo "  • Dify:         http://$TAILSCALE_IP:5001"
    echo "  • AnythingLLM:  http://$TAILSCALE_IP:3001"
    echo "  • ClawdBot:     Signal $SIGNAL_NUMBER"
    echo ""
    echo -e "${BLUE}Architecture:${NC}"
    echo "  📱 Signal → Signal API → ClawdBot → AI Providers"
    echo "                            ├─→ Claude (if key set)"
    echo "                            ├─→ Ollama (local)"
    echo "                            ├─→ LiteLLM (proxy)"
    echo "                            └─→ AnythingLLM (RAG)"
    echo ""
    echo -e "${BLUE}Credentials (.secrets):${NC}"
    echo "  • Dify admin password:     $DIFY_INIT_PASSWORD"
    echo "  • LiteLLM API key:         $LITELLM_MASTER_KEY"
    echo "  • AnythingLLM JWT secret:  (hidden)"
    echo ""
    echo -e "${BLUE}Management Commands:${NC}"
    echo "  • View all containers:   docker ps"
    echo "  • View logs:             docker logs -f <container>"
    echo "  • Restart service:       docker restart <container>"
    echo "  • Stop all:              cd ~/ai-platform-installer/stacks && for d in */; do (cd \$d && docker compose down); done"
    echo "  • Start all:             cd ~/ai-platform-installer/stacks && for d in */; do (cd \$d && docker compose up -d); done"
    echo "  • Full rebuild:          ./2-deploy-services.sh --rollback && ./2-deploy-services.sh"
    echo ""
    echo -e "${BLUE}Data Locations:${NC}"
    echo "  • Configs:  $SCRIPT_DIR/configs/"
    echo "  • Stacks:   $SCRIPT_DIR/stacks/"
    echo "  • Data:     $DATA_PATH/"
    echo "  • Logs:     /var/log/ai-platform-*.log"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Test ClawdBot by messaging $SIGNAL_NUMBER"
    echo "  2. Explore Dify workflow builder"
    echo "  3. Upload documents to AnythingLLM"
    echo "  4. Create Signal → Dify integration workflows"
    echo ""
    echo -e "${BLUE}Troubleshooting:${NC}"
    echo "  • Service not working:     docker logs -f <service-name>"
    echo "  • Signal issues:           ./3-link-signal-device.sh"
    echo "  • ClawdBot not responding: docker logs -f clawdbot"
    echo "  • Reset everything:        ./2-deploy-services.sh --rollback"
    echo ""
    echo "📖 Full documentation: $SCRIPT_DIR/README.md"
    echo ""
}

# ============================================
# Main Execution
# ============================================
verify_services
test_ollama
configure_litellm
configure_anythingllm
configure_dify
test_signal
test_clawdbot
setup_systemd
print_summary

chmod +x ~/ai-platform-installer/scripts/5-configure-services.sh
