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
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

#------------------------------------------------------------------------------
# Output Structure (Per README)
#------------------------------------------------------------------------------
# ╔════════════════════════════════════════════════════════════╗
# ║           🚨 COMPLETE PLATFORM CLEANUP 🚨                  ║
# ╚════════════════════════════════════════════════════════════╝
# 
# [WARNING] This will:
#   • Stop all Docker containers
#   • Remove all Docker volumes
#   • Delete /mnt/data contents
#   • Reset all configurations
# 
# Type 'DELETE EVERYTHING' to proceed: _
#
# [1/5] 🛑 Stopping containers...
#   ✓ 8 containers stopped
# 
# [2/5] 🗑️  Removing containers...
#   ✓ 8 containers removed
# 
# [3/5] 💾 Cleaning volumes...
#   ✓ 12 volumes removed
# 
# [4/5] 🌐 Removing networks...
#   ✓ Network ai_platform removed
# 
# [5/5] 📁 Cleaning data directory...
#   ✓ /mnt/data cleaned (523GB freed)
# 
# ╔════════════════════════════════════════════════════════════╗
# ║              ✅ CLEANUP COMPLETE                           ║
# ╚════════════════════════════════════════════════════════════╝
# 
# Run ./scripts/1-setup-system.sh to start fresh
#------------------------------------------------------------------------------

print_header() {
    echo -e "${RED}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║           🚨 COMPLETE PLATFORM CLEANUP 🚨                  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_warning_block() {
    echo ""
    echo -e "${YELLOW}[WARNING]${NC} This will:"
    echo "  • Stop all Docker containers"
    echo "  • Remove all Docker volumes"
    echo "  • Delete /mnt/data contents"
    echo "  • Reset all configurations"
    echo ""
}

print_step() {
    local step=$1
    local total=$2
    local icon=$3
    local message=$4
    echo ""
    echo -e "${BLUE}[$step/$total] $icon $message${NC}"
}

print_success() {
    echo -e "${GREEN}  ✓${NC} $1"
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

clear
print_header
print_warning_block

# Triple confirmation
echo -e "${YELLOW}Type 'DELETE EVERYTHING' to proceed:${NC} "
read -r confirm1
if [[ "$confirm1" != "DELETE EVERYTHING" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Type 'I UNDERSTAND THIS IS PERMANENT':${NC} "
read -r confirm2
if [[ "$confirm2" != "I UNDERSTAND THIS IS PERMANENT" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo -e "${RED}${BOLD}Final confirmation - Type 'RESET NOW':${NC} "
read -r confirm3
if [[ "$confirm3" != "RESET NOW" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Step 1: Stop containers
print_step "1" "5" "🛑" "Stopping containers..."
container_count=0
if docker ps -q | grep -q .; then
    container_count=$(docker ps -q | wc -l)
    docker stop $(docker ps -aq) 2>/dev/null || true
fi
print_success "$container_count containers stopped"

# Step 2: Remove containers
print_step "2" "5" "🗑️ " "Removing containers..."
if docker ps -aq | grep -q .; then
    docker rm -f $(docker ps -aq) 2>/dev/null || true
fi
print_success "$container_count containers removed"

# Step 3: Clean volumes
print_step "3" "5" "💾" "Cleaning volumes..."
volume_count=0
if docker volume ls -q | grep -q .; then
    volume_count=$(docker volume ls -q | wc -l)
    docker volume rm $(docker volume ls -q) 2>/dev/null || true
fi
print_success "$volume_count volumes removed"

# Step 4: Remove networks
print_step "4" "5" "🌐" "Removing networks..."
docker network rm ai_platform 2>/dev/null || true
print_success "Network ai_platform removed"

# Step 5: Clean data directory
print_step "5" "5" "📁" "Cleaning data directory..."

# Get initial size
initial_size=$(du -sb /mnt/data 2>/dev/null | awk '{print $1}' || echo "0")

if mountpoint -q /mnt/data; then
    # Kill processes using /mnt/data
    lsof +D /mnt/data 2>/dev/null | awk 'NR>1 {print $2}' | xargs -r kill -9 2>/dev/null || true
    sleep 2
    
    # Remove contents
    cd /mnt/data
    rm -rf ./* 2>/dev/null || true
    rm -rf ./.[!.]* 2>/dev/null || true
    cd - > /dev/null
else
    rm -rf /mnt/data 2>/dev/null || true
fi

# Calculate freed space
freed_gb=$((initial_size / 1024 / 1024 / 1024))
print_success "/mnt/data cleaned (${freed_gb}GB freed)"

# Docker system prune
docker system prune -af --volumes 2>/dev/null || true

# Final success message
echo ""
echo -e "${GREEN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              ✅ CLEANUP COMPLETE                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "Run ${BOLD}./scripts/1-setup-system.sh${NC} to start fresh"
echo ""

exit 0
