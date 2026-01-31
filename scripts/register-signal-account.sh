#!/bin/bash
set -eo pipefail

# ============================================
# Signal Account Registration Script
# Registers a phone number with Signal
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Signal Account Registration${NC}"
echo -e "${BLUE}========================================${NC}"

# Load environment
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    source "$SCRIPT_DIR/.env"
fi

PHONE_NUMBER="${SIGNAL_NUMBER:-+61410594574}"

echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo "  - You need access to SMS on $PHONE_NUMBER"
echo "  - Signal will send a verification code"
echo "  - This registers the number as a PRIMARY Signal account"
echo "  - Different from 'linking' a device"
echo ""

read -p "Continue with registration of $PHONE_NUMBER? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "Registration cancelled"
    exit 0
fi

echo ""
echo -e "${BLUE}Step 1: Checking Signal CLI status...${NC}"

if ! docker ps | grep -q signal-cli; then
    echo -e "${RED}❌ Signal CLI container not running${NC}"
    echo "Please run deploy-services.sh first"
    exit 1
fi

echo -e "${GREEN}✅ Signal CLI container is running${NC}"

echo ""
echo -e "${BLUE}Step 2: Registering $PHONE_NUMBER with Signal...${NC}"
echo -e "${YELLOW}This will send an SMS verification code to your phone${NC}"
echo ""

# Register the number
if docker exec -it signal-cli signal-cli -a "$PHONE_NUMBER" register; then
    echo ""
    echo -e "${GREEN}✅ Registration request sent!${NC}"
    echo ""
    echo -e "${BLUE}Step 3: Enter the verification code${NC}"
    echo "Check your SMS messages on $PHONE_NUMBER"
    echo ""
    read -p "Enter the 6-digit verification code: " verification_code
    
    # Verify the code
    echo ""
    echo -e "${BLUE}Verifying code...${NC}"
    
    if docker exec -it signal-cli signal-cli -a "$PHONE_NUMBER" verify "$verification_code"; then
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}✅ Success! Account registered!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo "Your Signal account is now active:"
        echo "  Number: $PHONE_NUMBER"
        echo ""
        echo "Verifying registration:"
        docker exec signal-cli signal-cli -a "$PHONE_NUMBER" listAccounts
        echo ""
        echo "Updating .env file..."
        
        # Update .env
        if grep -q "^SIGNAL_NUMBER=" "$SCRIPT_DIR/.env"; then
            sed -i "s|^SIGNAL_NUMBER=.*|SIGNAL_NUMBER=$PHONE_NUMBER|" "$SCRIPT_DIR/.env"
        else
            echo "SIGNAL_NUMBER=$PHONE_NUMBER" >> "$SCRIPT_DIR/.env"
        fi
        
        echo -e "${GREEN}✅ Configuration updated${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. Test sending a message:"
        echo "     docker exec signal-cli signal-cli -a $PHONE_NUMBER send -m \"Test message\" +YOUR_OTHER_NUMBER"
        echo ""
        echo "  2. Deploy ClawdBot:"
        echo "     ./deploy-clawdbot.sh"
        echo ""
        
    else
        echo ""
        echo -e "${RED}❌ Verification failed${NC}"
        echo "Please check the code and try again:"
        echo "  docker exec -it signal-cli signal-cli -a $PHONE_NUMBER verify CODE"
        exit 1
    fi
    
else
    echo ""
    echo -e "${RED}❌ Registration failed${NC}"
    echo ""
    echo "Possible issues:"
    echo "  - Number already registered with Signal"
    echo "  - Number format incorrect (must include country code)"
    echo "  - SMS delivery issues"
    echo ""
    echo "If number is already registered, you have two options:"
    echo ""
    echo "  Option A: Use your existing Signal account (recommended)"
    echo "    - Install Signal on your phone with this number"
    echo "    - Then link signal-cli as a secondary device:"
    echo "      docker exec -it signal-cli signal-cli link -n signal-api"
    echo "      (Scan QR code from Signal app > Settings > Linked Devices)"
    echo ""
    echo "  Option B: Use the web linking interface:"
    echo "    - http://ai.datasquiz.net:8080/v1/qrcodelink?device_name=signal-api"
    echo "    - Scan with Signal app > Settings > Linked Devices"
    echo ""
    exit 1
fi


chmod +x ~/ai-platform-installer/register-signal-account.sh
