#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

source ~/ai-platform-installer/.secrets

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}AI Platform Configuration Wizard${NC}"
echo -e "${BLUE}========================================${NC}"

echo ""
echo "This wizard will guide you through:"
echo "  1. Dify initial setup"
echo "  2. AnythingLLM workspace configuration"
echo "  3. Signal bot testing"
echo "  4. End-to-end pipeline verification"
echo ""

read -p "Press ENTER to begin..."

# ============================================
# 1. Dify Setup
# ============================================
echo ""
echo -e "${CYAN}[1/4] Dify Setup${NC}"
echo "--------------------------------------"
echo ""
echo "1. Open your browser and navigate to:"
echo ""
echo -e "   ${BLUE}https://$TAILSCALE_IP:8443/${NC}"
echo ""
echo "2. Accept the self-signed certificate warning"
echo "   (Click 'Advanced' → 'Proceed')"
echo ""
echo "3. Create admin account:"
echo "   - Email: admin@example.com (or your email)"
echo -e "   - Password: ${GREEN}$DIFY_INIT_PASSWORD${NC}"
echo "   - Display name: Admin"
echo ""
echo "4. Initial workspace setup:"
echo "   - Workspace name: AI Platform"
echo "   - Language: English"
echo ""
echo "5. Configure LLM provider:"
echo "   - Go to 'Settings' → 'Model Provider'"
echo "   - Click '+ Add Model Provider'"
echo "   - Select 'OpenAI-Compatible'"
echo "   - Configuration:"
echo "       • API Base URL: http://litellm:4000/v1"
echo -e "       • API Key: ${GREEN}$LITELLM_MASTER_KEY${NC}"
echo "   - Click 'Test' to verify"
echo "   - Save"
echo ""
echo "6. Test model:"
echo "   - Go to 'Studio'"
echo "   - Click '+ New App'"
echo "   - Select 'Chatbot'"
echo "   - Name: Test Bot"
echo "   - Model: llama3.2-3b"
echo "   - Send test message: 'Hello!'"
echo ""

read -p "Press ENTER after completing Dify setup..."

# ============================================
# 2. AnythingLLM Setup
# ============================================
echo ""
echo -e "${CYAN}[2/4] AnythingLLM Setup${NC}"
echo "--------------------------------------"
echo ""
echo "1. Open your browser:"
echo ""
echo -e "   ${BLUE}https://$TAILSCALE_IP:8443/anythingllm/${NC}"
echo ""
echo "2. Initial setup wizard:"
echo "   - Welcome screen: Click 'Get Started'"
echo "   - LLM Provider: Select 'Ollama'"
echo "   - Ollama Configuration:"
echo "       • Base URL: http://ollama:11434"
echo "       • Model: llama3.2:3b"
echo "   - Click 'Test Connection'"
echo ""
echo "3. Embedding Configuration:"
echo "   - Provider: Ollama"
echo "   - Model: nomic-embed-text"
echo "   - Click 'Test'"
echo ""
echo "4. Vector Database:"
echo "   - Keep default (LanceDB)"
echo ""
echo "5. Create API key:"
echo "   - Click 'Settings' (gear icon)"
echo "   - Go to 'API Keys'"
echo "   - Click 'Generate New API Key'"
echo "   - Copy the key"
echo ""

read -p "Paste your AnythingLLM API key: " ANYTHINGLLM_NEW_KEY

if [[ -n "$ANYTHINGLLM_NEW_KEY" ]]; then
    # Update ClawDBot config with new key
    sed -i "s/REPLACE_WITH_ANYTHINGLLM_API_KEY/$ANYTHINGLLM_NEW_KEY/" /opt/ai-platform/clawdbot/config.json
    sed -i "s/$ANYTHINGLLM_API_KEY/$ANYTHINGLLM_NEW_KEY/" /opt/ai-platform/clawdbot/config.json
    
    echo ""
    echo "6. Create default workspace:"
    echo "   - Click 'New Workspace'"
    echo "   - Name: default"
    echo "   - Click 'Create Workspace'"
    echo ""
    echo "7. Test the workspace:"
    echo "   - Type a question: 'What can you do?'"
    echo "   - Verify you get a response"
    echo ""
fi

read -p "Press ENTER after completing AnythingLLM setup..."

# Restart ClawDBot with updated config
cd ~/stacks/clawdbot
docker compose restart
sleep 3

# ============================================
# 3. Signal Bot Testing
# ============================================
echo ""
echo -e "${CYAN}[3/4] Signal Bot Testing${NC}"
echo "--------------------------------------"
echo ""

if [[ -z "${SIGNAL_PHONE:-}" ]]; then
    echo -e "${YELLOW}⚠️  Signal not registered yet${NC}"
    echo "Run: ./register-signal.sh first"
else
    echo "Signal account: $SIGNAL_PHONE"
    echo ""
    echo "Test ClawDBot:"
    echo "  1. Open Signal on your phone"
    echo "  2. Send a message to $SIGNAL_PHONE:"
    echo ""
    echo "     ${GREEN}Hello ClawDBot!${NC}"
    echo ""
    echo "  3. You should receive a response from AnythingLLM"
    echo ""
    
    read -p "Did you receive a response? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✅ ClawDBot is working!${NC}"
    else
        echo -e "${YELLOW}⚠️  Troubleshooting:${NC}"
        echo ""
        echo "Check ClawDBot logs:"
        echo "  docker logs -f clawdbot"
        echo ""
        echo "Check Signal API logs:"
        echo "  docker logs -f signal-api"
        echo ""
        echo "Verify webhook configuration:"
        echo "  curl http://localhost:8080/v1/configuration | jq"
    fi
fi

read -p "Press ENTER to continue..."

# ============================================
# 4. Dify → Signal Integration Test
# ============================================
echo ""
echo -e "${CYAN}[4/4] Dify → Signal Integration${NC}"
echo "--------------------------------------"
echo ""
echo "Configure Dify to send Signal messages:"
echo ""
echo "1. In Dify, create a new workflow:"
echo "   - Go to 'Studio' → '+ New App' → 'Workflow'"
echo "   - Name: Signal Notifier"
echo ""
echo "2. Add HTTP Request node:"
echo "   - Method: POST"
echo "   - URL: http://signal-api:8080/v2/send"
echo "   - Headers:"
echo "       Content-Type: application/json"
echo "   - Body (JSON):"
echo '       {'
echo '         "message": "Test from Dify!",''
echo "         \"number\": \"$SIGNAL_PHONE\","
echo "         \"recipients\": [\"$SIGNAL_PHONE\"]"
echo '       }'
echo ""
echo "3. Test the workflow"
echo "   - Click 'Run'"
echo "   - Check your Signal app for the message"
echo ""
echo "4. Create more complex workflows:"
echo "   - LLM node → HTTP Request (Signal)"
echo "   - Schedule trigger → LLM → Signal"
echo "   - Webhook → Process → Signal notification"
echo ""

read -p "Press ENTER after testing..."

# ============================================
# Final Summary
# ============================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Configuration Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Your AI Platform is fully configured:"
echo ""
echo -e "${BLUE}Access Points:${NC}"
echo "  • Dify:        https://$TAILSCALE_IP:8443/"
echo "  • AnythingLLM: https://$TAILSCALE_IP:8443/anythingllm/"
echo "  • Signal Bot:  Send messages to $SIGNAL_PHONE"
echo ""
echo -e "${BLUE}Credentials (saved in ~/.secrets):${NC}"
echo "  • Dify admin:       $DIFY_INIT_PASSWORD"
echo "  • LiteLLM API key:  $LITELLM_MASTER_KEY"
echo "  • AnythingLLM key:  $ANYTHINGLLM_NEW_KEY"
echo ""
echo -e "${BLUE}Architecture:${NC}"
echo "  Signal → Signal API → ClawDBot → AnythingLLM → LiteLLM → Ollama (GPU)"
echo "  Dify → Signal API → Signal Network"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "  • View all services:  docker ps"
echo "  • Check logs:         docker logs -f <container-name>"
echo "  • Restart service:    cd ~/stacks/<service> && docker compose restart"
echo "  • Stop all:           cd ~/stacks && for d in */; do (cd \$d && docker compose down); done"
echo "  • Start all:          cd ~/stacks && for d in */; do (cd \$d && docker compose up -d); done"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Explore Dify workflow builder"
echo "  2. Upload documents to AnythingLLM for RAG"
echo "  3. Create custom Signal bot responses"
echo "  4. Monitor GPU usage: watch -n 1 nvidia-smi"
echo ""
echo -e "${GREEN}Happy building! 🚀${NC}"
echo ""
CONFIGURE_EOF

chmod +x ~/ai-platform-installer/configure-services.sh

