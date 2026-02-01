#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - Deploy ClawdBot v2.0
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
LOG_FILE="$SCRIPT_DIR/logs/clawdbot-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

echo ""
log "${BLUE}========================================${NC}"
log "${BLUE}ClawdBot Deployment${NC}"
log "${BLUE}Repository: $(basename "$SCRIPT_DIR")${NC}"
log "${BLUE}========================================${NC}"
echo ""

# Load environment
if [[ ! -f "$ENV_FILE" ]]; then
    log "${RED}❌ Environment file not found${NC}"
    exit 1
fi

source "$ENV_FILE"

# Check Signal number
if [[ -z "${SIGNAL_NUMBER:-}" ]]; then
    log "${RED}❌ Signal not linked${NC}"
    log "${YELLOW}Run ./3-link-signal-device.sh first${NC}"
    exit 1
fi

log "${GREEN}✓ Environment loaded${NC}"
log "${GREEN}✓ Signal number: $SIGNAL_NUMBER${NC}"
echo ""

# ============================================
# Get Anthropic API Key
# ============================================
log "${BLUE}Step 1: Configure Anthropic${NC}"
echo ""

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "Enter your Anthropic API key:"
    read -s ANTHROPIC_API_KEY
    echo ""
    
    if [[ -z "$ANTHROPIC_API_KEY" ]]; then
        log "${RED}❌ API key required${NC}"
        exit 1
    fi
    
    echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY" >> "$ENV_FILE"
    source "$ENV_FILE"
fi

log "${GREEN}✓ API key configured${NC}"
echo ""

# ============================================
# Get Authorized Users
# ============================================
log "${BLUE}Step 2: Configure Authorized Users${NC}"
echo ""

if [[ -z "${CLAWDBOT_AUTHORIZED_USERS:-}" ]]; then
    echo "Enter authorized phone numbers (comma-separated):"
    echo "Example: +1234567890,+0987654321"
    read CLAWDBOT_AUTHORIZED_USERS
    echo ""
    
    if [[ -z "$CLAWDBOT_AUTHORIZED_USERS" ]]; then
        log "${YELLOW}⚠️  No users specified, using Signal number${NC}"
        CLAWDBOT_AUTHORIZED_USERS="$SIGNAL_NUMBER"
    fi
    
    echo "CLAWDBOT_AUTHORIZED_USERS=$CLAWDBOT_AUTHORIZED_USERS" >> "$ENV_FILE"
    source "$ENV_FILE"
fi

log "${GREEN}✓ Authorized users: $CLAWDBOT_AUTHORIZED_USERS${NC}"
echo ""

# ============================================
# Create ClawdBot Configuration
# ============================================
log "${BLUE}Step 3: Creating configuration...${NC}"

mkdir -p /mnt/data/clawdbot

cat > /mnt/data/clawdbot/config.json <<CLAWDBOT_CONFIG
{
  "signal_api_url": "http://signal-api:8080",
  "signal_number": "$SIGNAL_NUMBER",
  "authorized_users": [
    $(echo "$CLAWDBOT_AUTHORIZED_USERS" | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/')
  ],
  "anthropic_api_key": "$ANTHROPIC_API_KEY",
  "model": "claude-3-5-sonnet-20241022",
  "max_tokens": 4096,
  "temperature": 1.0,
  "system_prompt": "You are a helpful AI assistant accessible via Signal messenger. Be concise but informative.",
  "conversation_timeout": 3600,
  "log_level": "INFO"
}
CLAWDBOT_CONFIG

log "${GREEN}✓ Configuration created${NC}"
echo ""

# ============================================
# Create Docker Compose
# ============================================
log "${BLUE}Step 4: Creating compose file...${NC}"

cat > "$SCRIPT_DIR/stacks/clawdbot-compose.yml" <<CLAWDBOT_COMPOSE
version: '3.8'

services:
  clawdbot:
    image: ghcr.io/yourusername/clawdbot:${CLAWDBOT_VERSION}
    container_name: clawdbot
    restart: unless-stopped
    networks:
      - ai-platform-network
    volumes:
      - /mnt/data/clawdbot:/app/data
    environment:
      - CONFIG_FILE=/app/data/config.json
      - LOG_LEVEL=INFO
    depends_on:
      - signal-api
    healthcheck:
      test: ["CMD", "python", "-c", "import requests; requests.get('http://signal-api:8080/v1/health')"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  ai-platform-network:
    external: true
CLAWDBOT_COMPOSE

log "${GREEN}✓ Compose file created${NC}"
echo ""

# ============================================
# Deploy ClawdBot
# ============================================
log "${BLUE}Step 5: Deploying ClawdBot...${NC}"

docker compose -f "$SCRIPT_DIR/stacks/clawdbot-compose.yml" up -d

sleep 5

if docker ps | grep -q clawdbot; then
    log "${GREEN}✓ ClawdBot deployed successfully${NC}"
else
    log "${RED}❌ ClawdBot failed to start${NC}"
    log "Check logs: docker logs clawdbot"
    exit 1
fi

echo ""

# ============================================
# Test ClawdBot
# ============================================
log "${BLUE}Step 6: Testing ClawdBot...${NC}"
echo ""

log "Send a test message to $SIGNAL_NUMBER"
log "Example: 'Hello, are you there?'"
echo ""

read -p "Press Enter after sending test message..."

echo ""
log "Checking for response..."
sleep 5

RECENT_MESSAGES=$(docker logs clawdbot --tail 20)

if echo "$RECENT_MESSAGES" | grep -q "Received message"; then
    log "${GREEN}✓ ClawdBot received message${NC}"
    
    if echo "$RECENT_MESSAGES" | grep -q "Sent response"; then
        log "${GREEN}✓ ClawdBot sent response${NC}"
        log "${GREEN}✅ ClawdBot is working!${NC}"
    else
        log "${YELLOW}⚠️  Message received but no response${NC}"
        log "Check logs: docker logs clawdbot"
    fi
else
    log "${YELLOW}⚠️  No messages received yet${NC}"
    log "Troubleshooting:"
    log "  • Verify authorized numbers in config"
    log "  • Check Signal API: docker logs signal-api"
    log "  • Check ClawdBot: docker logs clawdbot"
fi

echo ""
log "${GREEN}========================================${NC}"
log "${GREEN}✅ ClawdBot Deployment Complete${NC}"
log "${GREEN}========================================${NC}"
echo ""

log "${BLUE}Configuration:${NC}"
log "  Signal Number: $SIGNAL_NUMBER"
log "  Authorized Users: $CLAWDBOT_AUTHORIZED_USERS"
log "  Model: claude-3-5-sonnet-20241022"
log "  Config: /mnt/data/clawdbot/config.json"
echo ""

log "${BLUE}Next Steps:${NC}"
log "  1. Test by messaging: $SIGNAL_NUMBER"
log "  2. View logs: ${YELLOW}docker logs -f clawdbot${NC}"
log "  3. Configure services: ${YELLOW}./5-configure-services.sh${NC}"
echo ""

