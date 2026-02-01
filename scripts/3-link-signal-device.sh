#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - Link Signal Device v2.0
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

# Load environment
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}❌ Environment file not found${NC}"
    exit 1
fi

source "$ENV_FILE"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Signal Device Linking${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Signal is running
if ! docker ps | grep -q signal-api; then
    echo -e "${RED}❌ Signal API not running${NC}"
    echo -e "${YELLOW}Run ./2-deploy-services.sh first${NC}"
    exit 1
fi

echo -e "${BLUE}Step 1: Generate QR Code Link${NC}"
echo ""
echo "Generating device link URL..."
echo ""

# Get link URL
LINK_URL=$(curl -s -X GET "http://localhost:8080/v1/qrcodelink?device_name=AI-Platform" | jq -r '.url')

if [[ -z "$LINK_URL" || "$LINK_URL" == "null" ]]; then
    echo -e "${RED}❌ Failed to generate link URL${NC}"
    echo "Check Signal API logs: docker logs signal-api"
    exit 1
fi

echo -e "${GREEN}✓ Link URL generated${NC}"
echo ""

# Generate QR code
echo -e "${BLUE}Step 2: Display QR Code${NC}"
echo ""
echo "Install qrencode if needed:"
echo -e "${YELLOW}sudo apt-get install -y qrencode${NC}"
echo ""

if command -v qrencode &> /dev/null; then
    echo "Scan this QR code with Signal app:"
    echo ""
    echo "$LINK_URL" | qrencode -t UTF8
    echo ""
else
    echo -e "${YELLOW}⚠️  qrencode not installed${NC}"
    echo ""
    echo "Manual link URL:"
    echo -e "${GREEN}$LINK_URL${NC}"
    echo ""
fi

echo -e "${BLUE}Step 3: Link Device in Signal App${NC}"
echo ""
echo "1. Open Signal on your phone"
echo "2. Go to Settings → Linked Devices"
echo "3. Tap '+' (Add Device)"
echo "4. Scan the QR code above"
echo "5. Enter device name: AI-Platform"
echo ""

read -p "Press Enter after linking device..."

echo ""
echo -e "${BLUE}Step 4: Verify Link${NC}"
echo ""

# Wait for registration
sleep 5

# Check registered numbers
NUMBERS=$(curl -s -X GET "http://localhost:8080/v1/accounts" | jq -r '.[].number')

if [[ -n "$NUMBERS" ]]; then
    echo -e "${GREEN}✓ Device linked successfully!${NC}"
    echo ""
    echo "Registered numbers:"
    echo "$NUMBERS"
    echo ""
    
    # Save to env
    echo "SIGNAL_NUMBER=$(echo "$NUMBERS" | head -1)" >> "$ENV_FILE"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ Signal Ready${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Next: Deploy ClawdBot"
    echo -e "${YELLOW}./4-deploy-clawdbot.sh${NC}"
    echo ""
else
    echo -e "${RED}❌ Device not linked${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  • Check Signal API logs: docker logs signal-api"
    echo "  • Verify QR code scanned correctly"
    echo "  • Try restarting: docker restart signal-api"
    exit 1
fi

