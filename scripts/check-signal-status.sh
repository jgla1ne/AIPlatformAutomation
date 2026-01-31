#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Signal Configuration Status${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check Signal CLI container
if ! docker ps | grep -q signal-cli; then
    echo -e "${RED}❌ Signal CLI container not running${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Signal CLI container running${NC}"
echo ""

# Check registered accounts
echo -e "${BLUE}Registered Signal accounts:${NC}"
accounts=$(docker exec signal-cli signal-cli listAccounts 2>&1)

if echo "$accounts" | grep -q "Number:"; then
    echo "$accounts"
    echo ""
    echo -e "${GREEN}✅ Signal account is configured${NC}"
    
    # Extract number
    number=$(echo "$accounts" | grep "Number:" | awk '{print $2}')
    echo ""
    echo "Detected number: $number"
    
    # Test sending capability
    echo ""
    echo -e "${BLUE}Testing Signal API...${NC}"
    
    if curl -sf http://localhost:8080/v1/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Signal API responding${NC}"
        
        echo ""
        echo "You can now:"
        echo "  1. Deploy ClawdBot: ./deploy-clawdbot.sh"
        echo "  2. Send test message via API:"
        echo "     curl -X POST http://localhost:8080/v2/send \\"
        echo "       -H 'Content-Type: application/json' \\"
        echo "       -d '{\"number\":\"$number\",\"recipients\":[\"+YOUR_NUMBER\"],\"message\":\"Test\"}'"
    else
        echo -e "${RED}❌ Signal API not responding${NC}"
    fi
    
else
    echo -e "${YELLOW}⚠️  No registered accounts found${NC}"
    echo ""
    echo "You need to either:"
    echo ""
    echo "  Option A: Register this number as primary account"
    echo "    ./register-signal-account.sh"
    echo "    (Requires SMS access to +61410594574)"
    echo ""
    echo "  Option B: Link as secondary device (if you have Signal on phone)"
    echo "    - Install Signal app on phone with your number"
    echo "    - Link via web: http://ai.datasquiz.net:8080/v1/qrcodelink?device_name=signal-api"
    echo "    - Or CLI: docker exec -it signal-cli signal-cli link -n signal-api"
    echo ""
fi


chmod +x ~/ai-platform-installer/check-signal-status.sh
