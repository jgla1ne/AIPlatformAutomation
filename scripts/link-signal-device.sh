#!/bin/bash
set -eo pipefail

# ============================================
# Signal Device Linking Script
# Uses Signal API for device verification
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Link Signal Device via API${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check Signal API is running
if ! curl -sf http://localhost:8080/v1/health > /dev/null 2>&1; then
    echo -e "${RED}❌ Signal API not responding on port 8080${NC}"
    echo ""
    echo "Start services first:"
    echo "  ./deploy-services.sh"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ Signal API is running${NC}"
echo ""

# Check if device already linked
echo -e "${BLUE}Checking for existing linked devices...${NC}"

ACCOUNTS=$(curl -s http://localhost:8080/v1/accounts)

if echo "$ACCOUNTS" | grep -q "+61410594574"; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ Device Already Linked!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Account details:"
    echo "$ACCOUNTS" | jq '.'
    echo ""
    
    # Update .env
    if grep -q "^SIGNAL_NUMBER=" "$SCRIPT_DIR/.env" 2>/dev/null; then
        sed -i "s|^SIGNAL_NUMBER=.*|SIGNAL_NUMBER=+61410594574|" "$SCRIPT_DIR/.env"
    else
        echo "SIGNAL_NUMBER=+61410594574" >> "$SCRIPT_DIR/.env"
    fi
    
    echo -e "${GREEN}✅ .env updated with SIGNAL_NUMBER=+61410594574${NC}"
    echo ""
    
    echo -e "${BLUE}Test sending a message:${NC}"
    echo ""
    echo "  curl -X POST http://localhost:8080/v2/send \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"number\":\"+61410594574\",\"recipients\":[\"+61410594574\"],\"message\":\"Test from Signal API\"}'"
    echo ""
    
    read -p "Would you like to send a test message to yourself? (y/n): " test_msg
    if [[ "$test_msg" == "y" ]]; then
        echo ""
        echo "Sending test message..."
        
        RESPONSE=$(curl -s -X POST http://localhost:8080/v2/send \
          -H 'Content-Type: application/json' \
          -d '{"number":"+61410594574","recipients":["+61410594574"],"message":"✅ Signal API test message from ClawdBot platform"}')
        
        if echo "$RESPONSE" | grep -q "timestamp"; then
            echo -e "${GREEN}✅ Test message sent successfully!${NC}"
            echo "Check your Signal app for the message."
        else
            echo -e "${YELLOW}⚠️  Message response:${NC}"
            echo "$RESPONSE" | jq '.'
        fi
    fi
    
    echo ""
    echo -e "${GREEN}Next step: Deploy ClawdBot${NC}"
    echo "  ./deploy-clawdbot.sh"
    echo ""
    exit 0
fi

echo -e "${YELLOW}No device linked yet${NC}"
echo ""
echo -e "${BLUE}Choose linking method:${NC}"
echo ""
echo "  1. Web UI (Recommended - works perfectly as you mentioned)"
echo "  2. CLI QR Code"
echo "  3. Clean data and re-link"
echo ""

read -p "Select option (1/2/3): " choice

case $choice in
    1)
        echo ""
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}Web UI Linking Method${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        echo "1. Open this URL in your browser:"
        echo ""
        echo -e "${GREEN}   http://ai.datasquiz.net:8080/v1/qrcodelink?device_name=signal-api${NC}"
        echo ""
        echo "2. QR code will appear in browser"
        echo "3. Open Signal app on your phone (+61410594574)"
        echo "4. Go to: Settings → Linked Devices → Link New Device"
        echo "5. Scan the QR code from browser"
        echo ""
        
        read -p "Press Enter when you've scanned the QR code..." 
        
        echo ""
        echo -e "${BLUE}Verifying device link...${NC}"
        sleep 3
        
        ACCOUNTS=$(curl -s http://localhost:8080/v1/accounts)
        
        if echo "$ACCOUNTS" | grep -q "+61410594574"; then
            echo ""
            echo -e "${GREEN}✅ Successfully linked via Web UI!${NC}"
            echo ""
            echo "$ACCOUNTS" | jq '.'
            
            # Update .env
            if grep -q "^SIGNAL_NUMBER=" "$SCRIPT_DIR/.env" 2>/dev/null; then
                sed -i "s|^SIGNAL_NUMBER=.*|SIGNAL_NUMBER=+61410594574|" "$SCRIPT_DIR/.env"
            else
                echo "SIGNAL_NUMBER=+61410594574" >> "$SCRIPT_DIR/.env"
            fi
            
            echo ""
            echo -e "${GREEN}✅ .env updated${NC}"
        else
            echo -e "${YELLOW}⚠️  Device not detected yet${NC}"
            echo "It may take a moment. Check accounts:"
            echo "  curl -s http://localhost:8080/v1/accounts | jq '.'"
        fi
        ;;
        
    2)
        echo ""
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}CLI QR Code Method${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        echo "1. Keep this terminal visible"
        echo "2. Open Signal app on your phone (+61410594574)"
        echo "3. Go to: Settings → Linked Devices → Link New Device"
        echo "4. Have camera ready"
        echo ""
        
        read -p "Press Enter to generate QR code..." 
        
        echo ""
        echo -e "${BLUE}Generating QR code...${NC}"
        echo ""
        
        docker exec -it signal-cli signal-cli link -n "signal-api"
        
        echo ""
        echo -e "${BLUE}Checking if linked...${NC}"
        sleep 3
        
        ACCOUNTS=$(curl -s http://localhost:8080/v1/accounts)
        
        if echo "$ACCOUNTS" | grep -q "+61410594574"; then
            echo ""
            echo -e "${GREEN}✅ Successfully linked via CLI!${NC}"
            echo ""
            echo "$ACCOUNTS" | jq '.'
            
            # Update .env
            if grep -q "^SIGNAL_NUMBER=" "$SCRIPT_DIR/.env" 2>/dev/null; then
                sed -i "s|^SIGNAL_NUMBER=.*|SIGNAL_NUMBER=+61410594574|" "$SCRIPT_DIR/.env"
            else
                echo "SIGNAL_NUMBER=+61410594574" >> "$SCRIPT_DIR/.env"
            fi
            
            echo ""
            echo -e "${GREEN}✅ .env updated${NC}"
        else
            echo -e "${YELLOW}⚠️  Device not detected${NC}"
            echo "Check: curl -s http://localhost:8080/v1/accounts | jq '.'"
        fi
        ;;
        
    3)
        echo ""
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}Clean and Re-link${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        echo -e "${YELLOW}This will remove all Signal CLI data and start fresh${NC}"
        echo ""
        
        read -p "Continue? (y/n): " confirm
        if [[ "$confirm" != "y" ]]; then
            echo "Cancelled"
            exit 0
        fi
        
        echo ""
        echo -e "${BLUE}Cleaning Signal data...${NC}"
        
        # Remove existing data
        docker exec signal-cli rm -rf /root/.local/share/signal-cli/data/*
        
        echo -e "${GREEN}✅ Data cleaned${NC}"
        
        # Restart Signal API to recognize clean state
        echo ""
        echo -e "${BLUE}Restarting Signal API...${NC}"
        docker restart signal-api
        
        echo "Waiting for API to be ready..."
        sleep 10
        
        # Now link via web UI (the method that works perfectly)
        echo ""
        echo -e "${BLUE}Now link via Web UI:${NC}"
        echo ""
        echo "1. Open: ${GREEN}http://ai.datasquiz.net:8080/v1/qrcodelink?device_name=signal-api${NC}"
        echo "2. Scan QR code with Signal app"
        echo ""
        
        read -p "Press Enter when you've scanned the QR code..." 
        
        echo ""
        echo -e "${BLUE}Verifying...${NC}"
        sleep 3
        
        ACCOUNTS=$(curl -s http://localhost:8080/v1/accounts)
        
        if echo "$ACCOUNTS" | grep -q "+61410594574"; then
            echo ""
            echo -e "${GREEN}✅ Successfully linked after clean!${NC}"
            echo ""
            echo "$ACCOUNTS" | jq '.'
            
            # Update .env
            if grep -q "^SIGNAL_NUMBER=" "$SCRIPT_DIR/.env" 2>/dev/null; then
                sed -i "s|^SIGNAL_NUMBER=.*|SIGNAL_NUMBER=+61410594574|" "$SCRIPT_DIR/.env"
            else
                echo "SIGNAL_NUMBER=+61410594574" >> "$SCRIPT_DIR/.env"
            fi
            
            echo ""
            echo -e "${GREEN}✅ .env updated${NC}"
        else
            echo -e "${RED}❌ Still not linked${NC}"
            echo ""
            echo "Manual check:"
            echo "  curl -s http://localhost:8080/v1/accounts | jq '.'"
        fi
        ;;
        
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Testing Signal API${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

read -p "Send test message to yourself? (y/n): " test_choice
if [[ "$test_choice" == "y" ]]; then
    echo ""
    echo "Sending test message..."
    
    RESPONSE=$(curl -s -X POST http://localhost:8080/v2/send \
      -H 'Content-Type: application/json' \
      -d '{"number":"+61410594574","recipients":["+61410594574"],"message":"✅ Signal device successfully linked! Ready for ClawdBot."}')
    
    if echo "$RESPONSE" | grep -q "timestamp"; then
        echo -e "${GREEN}✅ Test message sent!${NC}"
        echo "Check Signal app on your phone."
    else
        echo -e "${YELLOW}Response:${NC}"
        echo "$RESPONSE" | jq '.'
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Signal Device Linking Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next step: Deploy ClawdBot"
echo "  ./deploy-clawdbot.sh"
echo ""


chmod +x ~/ai-platform-installer/link-signal-device.sh
