#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - Complete System Cleanup
# WARNING: This will remove ALL platform data!
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${RED}========================================${NC}"
echo -e "${RED}⚠️  COMPLETE SYSTEM CLEANUP  ⚠️${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}This will remove:${NC}"
echo "  • All Docker containers (AI Platform)"
echo "  • All Docker images (AI Platform)"
echo "  • All Docker volumes"
echo "  • All platform data directories"
echo "  • All configuration files (.env, .secrets, stacks/)"
echo "  • All installed packages (NVIDIA, Docker)"
echo "  • All system users (platform-specific)"
echo "  • All systemd services"
echo ""
echo -e "${RED}⚠️  THIS CANNOT BE UNDONE!  ⚠️${NC}"
echo ""
read -p "Type 'DELETE EVERYTHING' to confirm: " confirmation

if [[ "$confirmation" != "DELETE EVERYTHING" ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo ""
echo -e "${BLUE}Starting cleanup...${NC}"
echo ""

# ============================================
# Stop and Remove Containers
# ============================================
cleanup_containers() {
    echo -e "${BLUE}[1/12] Stopping and removing containers...${NC}"
    
    local containers=$(docker ps -aq 2>/dev/null || true)
    
    if [[ -n "$containers" ]]; then
        echo "   Stopping containers..."
        docker stop $containers 2>/dev/null || true
        
        echo "   Removing containers..."
        docker rm -f $containers 2>/dev/null || true
        
        echo -e "   ${GREEN}✅ Containers removed${NC}"
    else
        echo -e "   ${YELLOW}⚠ No containers found${NC}"
    fi
}

# ============================================
# Remove Images
# ============================================
cleanup_images() {
    echo ""
    echo -e "${BLUE}[2/12] Removing Docker images...${NC}"
    
    local images=$(docker images -q 2>/dev/null || true)
    
    if [[ -n "$images" ]]; then
        echo "   Removing images..."
        docker rmi -f $images 2>/dev/null || true
        echo -e "   ${GREEN}✅ Images removed${NC}"
    else
        echo -e "   ${YELLOW}⚠ No images found${NC}"
    fi
}

# ============================================
# Remove Volumes
# ============================================
cleanup_volumes() {
    echo ""
    echo -e "${BLUE}[3/12] Removing Docker volumes...${NC}"
    
    local volumes=$(docker volume ls -q 2>/dev/null || true)
    
    if [[ -n "$volumes" ]]; then
        echo "   Removing volumes..."
        docker volume rm -f $volumes 2>/dev/null || true
        echo -e "   ${GREEN}✅ Volumes removed${NC}"
    else
        echo -e "   ${YELLOW}⚠ No volumes found${NC}"
    fi
}

# ============================================
# Remove Networks
# ============================================
cleanup_networks() {
    echo ""
    echo -e "${BLUE}[4/12] Removing Docker networks...${NC}"
    
    docker network rm ai-platform-network 2>/dev/null || true
    docker network prune -f 2>/dev/null || true
    
    echo -e "   ${GREEN}✅ Networks removed${NC}"
}

# ============================================
# Remove Data Directories
# ============================================
cleanup_data() {
    echo ""
    echo -e "${BLUE}[5/12] Removing data directories...${NC}"
    
    # Remove main data directory
    if [[ -d "/mnt/data" ]]; then
        echo "   Removing /mnt/data..."
        sudo rm -rf /mnt/data/*
        echo -e "   ${GREEN}✅ /mnt/data cleaned${NC}"
    fi
    
    # Remove home data directory
    if [[ -d "$HOME/ai-platform-data" ]]; then
        echo "   Removing $HOME/ai-platform-data..."
        sudo rm -rf "$HOME/ai-platform-data"
        echo -e "   ${GREEN}✅ Home data removed${NC}"
    fi
    
    # Remove /opt directory
    if [[ -d "/opt/ai-platform" ]]; then
        echo "   Removing /opt/ai-platform..."
        sudo rm -rf /opt/ai-platform
        echo -e "   ${GREEN}✅ /opt/ai-platform removed${NC}"
    fi
}

# ============================================
# Remove Configuration Files
# ============================================
cleanup_config() {
    echo ""
    echo -e "${BLUE}[6/12] Removing configuration files...${NC}"
    
    # Remove installer directory configs
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        rm -f "$SCRIPT_DIR/.env"
        echo "   Removed .env"
    fi
    
    if [[ -f "$SCRIPT_DIR/.secrets" ]]; then
        rm -f "$SCRIPT_DIR/.secrets"
        echo "   Removed .secrets"
    fi
    
    # Remove stacks directory
    if [[ -d "$SCRIPT_DIR/stacks" ]]; then
        echo "   Removing stacks/ directory..."
        rm -rf "$SCRIPT_DIR/stacks"
        echo -e "   ${GREEN}✅ stacks/ removed${NC}"
    fi
    
    # Remove configs directory if exists
    if [[ -d "$SCRIPT_DIR/configs" ]]; then
        echo "   Removing configs/ directory..."
        rm -rf "$SCRIPT_DIR/configs"
        echo -e "   ${GREEN}✅ configs/ removed${NC}"
    fi
    
    echo -e "   ${GREEN}✅ Configuration files removed${NC}"
}

# ============================================
# Remove System Users
# ============================================
cleanup_users() {
    echo ""
    echo -e "${BLUE}[7/12] Removing system users...${NC}"
    
    local users=("ollama" "litellm" "signal" "dify" "anythingllm" "clawdbot")
    
    for user in "${users[@]}"; do
        if id "$user" &>/dev/null; then
            sudo userdel -r "$user" 2>/dev/null || true
            echo "   Removed user: $user"
        fi
    done
    
    echo -e "   ${GREEN}✅ Service users removed${NC}"
}

# ============================================
# Stop Systemd Services
# ============================================
cleanup_systemd() {
    echo ""
    echo -e "${BLUE}[8/12] Stopping systemd services...${NC}"
    
    local services=("ollama" "litellm" "signal-api" "dify" "anythingllm" "clawdbot")
    
    for service in "${services[@]}"; do
        if systemctl list-units --full -all | grep -q "$service.service"; then
            sudo systemctl stop "$service" 2>/dev/null || true
            sudo systemctl disable "$service" 2>/dev/null || true
            sudo rm -f "/etc/systemd/system/$service.service"
            echo "   Removed service: $service"
        fi
    done
    
    sudo systemctl daemon-reload
    echo -e "   ${GREEN}✅ Systemd services removed${NC}"
}

# ============================================
# Uninstall Docker
# ============================================
uninstall_docker() {
    echo ""
    echo -e "${BLUE}[9/12] Uninstalling Docker...${NC}"
    
    if command -v docker &> /dev/null; then
        echo "   Stopping Docker service..."
        sudo systemctl stop docker docker.socket containerd
        
        echo "   Removing Docker packages..."
        sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
        
        echo "   Removing Docker data..."
        sudo rm -rf /var/lib/docker
        sudo rm -rf /var/lib/containerd
        sudo rm -rf /etc/docker
        sudo rm -rf ~/.docker
        
        echo "   Removing Docker group..."
        sudo groupdel docker 2>/dev/null || true
        
        echo -e "   ${GREEN}✅ Docker uninstalled${NC}"
    else
        echo -e "   ${YELLOW}⚠ Docker not installed${NC}"
    fi
}

# ============================================
# Uninstall NVIDIA Drivers
# ============================================
uninstall_nvidia() {
    echo ""
    echo -e "${BLUE}[10/12] Uninstalling NVIDIA drivers...${NC}"
    
    if command -v nvidia-smi &> /dev/null; then
        echo "   Removing NVIDIA packages..."
        sudo apt-get purge -y '*nvidia*' '*cuda*' 2>/dev/null || true
        sudo apt-get autoremove -y
        
        echo "   Removing NVIDIA container toolkit..."
        sudo apt-get purge -y nvidia-container-toolkit 2>/dev/null || true
        
        echo -e "   ${GREEN}✅ NVIDIA drivers uninstalled${NC}"
        echo -e "   ${YELLOW}⚠ Reboot required to complete removal${NC}"
    else
        echo -e "   ${YELLOW}⚠ NVIDIA drivers not installed${NC}"
    fi
}

# ============================================
# Clean Package Cache
# ============================================
cleanup_packages() {
    echo ""
    echo -e "${BLUE}[11/12] Cleaning package cache...${NC}"
    
    sudo apt-get autoremove -y
    sudo apt-get autoclean -y
    
    echo -e "   ${GREEN}✅ Package cache cleaned${NC}"
}

# ============================================
# Verify Cleanup
# ============================================
verify_cleanup() {
    echo ""
    echo -e "${BLUE}[12/12] Verifying cleanup...${NC}"
    echo ""
    
    local remaining_issues=0
    
    # Check containers
    if [[ -n "$(docker ps -aq 2>/dev/null)" ]]; then
        echo -e "   ${RED}✗ Some containers remain${NC}"
        remaining_issues=$((remaining_issues + 1))
    else
        echo -e "   ${GREEN}✓ All containers removed${NC}"
    fi
    
    # Check data directories
    if [[ -d "/mnt/data" ]] && [[ -n "$(ls -A /mnt/data 2>/dev/null)" ]]; then
        echo -e "   ${YELLOW}⚠ /mnt/data not empty (mount point preserved)${NC}"
    else
        echo -e "   ${GREEN}✓ Data directories cleaned${NC}"
    fi
    
    # Check stacks directory
    if [[ -d "$SCRIPT_DIR/stacks" ]]; then
        echo -e "   ${RED}✗ stacks/ directory still exists${NC}"
        remaining_issues=$((remaining_issues + 1))
    else
        echo -e "   ${GREEN}✓ stacks/ directory removed${NC}"
    fi
    
    # Check config files
    if [[ -f "$SCRIPT_DIR/.env" ]] || [[ -f "$SCRIPT_DIR/.secrets" ]]; then
        echo -e "   ${RED}✗ Config files remain${NC}"
        remaining_issues=$((remaining_issues + 1))
    else
        echo -e "   ${GREEN}✓ Config files removed${NC}"
    fi
    
    # Check Docker
    if command -v docker &> /dev/null; then
        echo -e "   ${YELLOW}⚠ Docker still installed${NC}"
    else
        echo -e "   ${GREEN}✓ Docker uninstalled${NC}"
    fi
    
    # Check NVIDIA
    if command -v nvidia-smi &> /dev/null; then
        echo -e "   ${YELLOW}⚠ NVIDIA drivers still installed (reboot required)${NC}"
    else
        echo -e "   ${GREEN}✓ NVIDIA drivers uninstalled${NC}"
    fi
    
    echo ""
    if [[ $remaining_issues -gt 0 ]]; then
        echo -e "${YELLOW}⚠ Cleanup completed with $remaining_issues warnings${NC}"
    else
        echo -e "${GREEN}✅ Cleanup completed successfully!${NC}"
    fi
}

# ============================================
# Main Execution
# ============================================
main() {
    cleanup_containers
    cleanup_images
    cleanup_volumes
    cleanup_networks
    cleanup_data
    cleanup_config
    cleanup_users
    cleanup_systemd
    uninstall_docker
    uninstall_nvidia
    cleanup_packages
    verify_cleanup
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}Cleanup Complete!${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Reboot the system: sudo reboot"
    echo "  2. After reboot, run: cd ~/ai-platform-installer/scripts"
    echo "  3. Then run: ./1-setup-system.sh"
    echo ""
}

main "$@"

chmod +x ~/ai-platform-installer/scripts/0-complete-cleanup.sh
