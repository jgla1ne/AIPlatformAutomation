#!/bin/bash
set -eo pipefail

# ============================================
# Reinitialize Signal Containers
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Reinitialize Signal Containers${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${BLUE}1. Checking current Signal containers...${NC}"
docker ps -a --filter "name=signal" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"

echo ""
echo -e "${BLUE}2. Stopping and removing existing Signal containers...${NC}"
docker stop signal-cli signal-api 2>/dev/null || echo "No containers to stop"
docker rm signal-cli signal-api 2>/dev/null || echo "No containers to remove"

echo ""
echo -e "${BLUE}3. Cleaning Signal data directory...${NC}"
read -p "Remove existing Signal data? This will require re-linking. (y/n): " clean_data

if [[ "$clean_data" == "y" ]]; then
    rm -rf ~/signal-data/*
    echo -e "${GREEN}✅ Signal data cleaned${NC}"
else
    echo -e "${YELLOW}⚠️  Keeping existing data${NC}"
fi

echo ""
echo -e "${BLUE}4. Creating fresh Signal data directory...${NC}"
mkdir -p ~/signal-data
chmod 777 ~/signal-data
echo -e "${GREEN}✅ Created ~/signal-data${NC}"

echo ""
echo -e "${BLUE}5. Checking docker-compose.yml for Signal services...${NC}"

if ! grep -q "signal-cli:" "$SCRIPT_DIR/docker-compose.yml"; then
    echo -e "${RED}❌ Signal services not found in docker-compose.yml${NC}"
    echo ""
    echo "Adding Signal services to docker-compose.yml..."
    
    # Backup
    cp "$SCRIPT_DIR/docker-compose.yml" "$SCRIPT_DIR/docker-compose.yml.backup-$(date +%s)"
    
    # Add Signal services
    cat >> "$SCRIPT_DIR/docker-compose.yml" <<'SIGNAL_EOF'

  # Signal CLI (native mode - manages accounts)
  signal-cli:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-cli
    environment:
      - MODE=native
    volumes:
      - ~/signal-data:/root/.local/share/signal-cli
    restart: unless-stopped
    networks:
      - ${DOCKER_NETWORK:-ai-platform-network}

  # Signal API (json-rpc mode - REST API)
  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: signal-api
    ports:
      - "8080:8080"
    environment:
      - MODE=json-rpc
    volumes:
      - ~/signal-data:/home/.local/share/signal-cli
    depends_on:
      - signal-cli
    restart: unless-stopped
    networks:
      - ${DOCKER_NETWORK:-ai-platform-network}
SIGNAL_EOF

    echo -e "${GREEN}✅ Signal services added to docker-compose.yml${NC}"
else
    echo -e "${GREEN}✅ Signal services found in docker-compose.yml${NC}"
fi

echo ""
echo -e "${BLUE}6. Checking network...${NC}"
if docker network inspect ai-platform-network > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Network ai-platform-network exists${NC}"
else
    echo -e "${YELLOW}⚠️  Creating network...${NC}"
    docker network create ai-platform-network
    echo -e "${GREEN}✅ Network created${NC}"
fi

echo ""
echo -e "${BLUE}7. Starting Signal containers...${NC}"
cd "$SCRIPT_DIR"
docker-compose up -d signal-cli signal-api

echo ""
echo "Waiting for containers to initialize..."
sleep 15

echo ""
echo -e "${BLUE}8. Checking container status...${NC}"
docker ps --filter "name=signal" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo -e "${BLUE}9. Testing Signal API health...${NC}"
if curl -sf http://localhost:8080/v1/health > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Signal API responding on port 8080${NC}"
    curl -s http://localhost:8080/v1/health | jq '.'
else
    echo -e "${RED}❌ Signal API not responding${NC}"
    echo ""
    echo "Checking logs:"
    docker logs signal-api --tail 50
    exit 1
fi

echo ""
echo -e "${BLUE}10. Checking data directory access...${NC}"

echo "signal-cli:"
if docker exec signal-cli ls -la /root/.local/share/signal-cli 2>/dev/null; then
    echo -e "${GREEN}✅ Can access data directory${NC}"
else
    echo -e "${RED}❌ Cannot access data directory${NC}"
fi

echo ""
echo "signal-api:"
if docker exec signal-api ls -la /home/.local/share/signal-cli 2>/dev/null; then
    echo -e "${GREEN}✅ Can access data directory${NC}"
else
    echo -e "${RED}❌ Cannot access data directory${NC}"
fi

echo ""
echo -e "${BLUE}11. Checking for existing accounts...${NC}"
ACCOUNTS=$(curl -s http://localhost:8080/v1/accounts)
if echo "$ACCOUNTS" | grep -q "Number"; then
    echo -e "${YELLOW}⚠️  Found existing accounts:${NC}"
    echo "$ACCOUNTS" | jq '.'
else
    echo -e "${GREEN}✅ No accounts linked (ready for fresh setup)${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Signal Containers Reinitialized!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Container access:"
echo "  Signal API:  http://localhost:8080"
echo "  Web UI:      http://localhost:8080/v1/qrcodelink?device_name=signal-api"
echo ""
echo "Next step: Link your device"
echo "  ./link-signal-device.sh"
echo ""


chmod +x ~/ai-platform-installer/reinit-signal.sh
./reinit-signal.sh
