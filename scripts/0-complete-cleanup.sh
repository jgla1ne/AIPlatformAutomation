#!/bin/bash

#==============================================================================
# Script 0: Complete Platform Reset
# Purpose: Remove all containers, volumes, networks, and configurations
# WARNING: This will DELETE ALL DATA - Use with extreme caution!
#==============================================================================

set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

echo -e "${RED}${BOLD}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    ⚠️  DANGER ZONE  ⚠️                          ║"
echo "║                                                               ║"
echo "║  This script will COMPLETELY RESET the AI platform:          ║"
echo "║                                                               ║"
echo "║  ✗ Stop and remove ALL Docker containers                     ║"
echo "║  ✗ Delete ALL Docker volumes                                 ║"
echo "║  ✗ Remove ALL Docker networks                                ║"
echo "║  ✗ Delete /mnt/data directory and ALL its contents           ║"
echo "║  ✗ Remove metadata and configuration files                   ║"
echo "║                                                               ║"
echo "║  THIS CANNOT BE UNDONE!                                      ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Triple confirmation
echo -e "${YELLOW}Type 'DELETE EVERYTHING' to confirm:${NC}"
read -r confirm1
if [[ "$confirm1" != "DELETE EVERYTHING" ]]; then
    echo "Reset cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Type 'I UNDERSTAND THIS IS PERMANENT' to proceed:${NC}"
read -r confirm2
if [[ "$confirm2" != "I UNDERSTAND THIS IS PERMANENT" ]]; then
    echo "Reset cancelled."
    exit 0
fi

echo ""
echo -e "${RED}Final confirmation - Type 'RESET NOW':${NC}"
read -r confirm3
if [[ "$confirm3" != "RESET NOW" ]]; then
    echo "Reset cancelled."
    exit 0
fi

echo ""
echo -e "${GREEN}[1/5]${NC} Stopping all containers..."
docker stop $(docker ps -aq) 2>/dev/null || true

echo -e "${GREEN}[2/5]${NC} Removing all containers..."
docker rm -f $(docker ps -aq) 2>/dev/null || true

echo -e "${GREEN}[3/5]${NC} Removing all volumes..."
docker volume rm $(docker volume ls -q) 2>/dev/null || true

echo -e "${GREEN}[4/5]${NC} Removing Docker networks..."
docker network rm ai_platform 2>/dev/null || true

echo -e "${GREEN}[5/5]${NC} Deleting /mnt/data directory..."
rm -rf /mnt/data

echo ""
echo -e "${GREEN}${BOLD}✓ Platform reset complete${NC}"
echo ""
echo "You can now run script 1 to start fresh."
