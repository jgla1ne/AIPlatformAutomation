#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - Complete Cleanup v2.0
# Path-agnostic: Works with any repo name
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Auto-detect script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_NAME="$(basename "$SCRIPT_DIR")"

echo -e "${RED}========================================${NC}"
echo -e "${RED}⚠️  COMPLETE SYSTEM CLEANUP  ⚠️${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${BLUE}Repository: $REPO_NAME${NC}"
echo -e "${BLUE}Location: $SCRIPT_DIR${NC}"
echo ""
echo -e "${YELLOW}This will remove:${NC}"
echo "  • All Docker containers (AI Platform)"
echo "  • All Docker images (AI Platform)"
echo "  • All Docker volumes"
echo "  • All platform data (/mnt/data/*)"
echo "  • All config files (.env, .secrets, stacks/)"
echo "  • Docker Engine (optional)"
echo "  • NVIDIA drivers (optional)"
echo "  • Service users"
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
# [1/12] Stop Containers
# ============================================
cleanup_containers() {
    echo -e "${BLUE}[1/12] Stopping containers...${NC}"
    
    local containers=$(docker ps -aq 2>/dev/null | wc -l)
    if [[ $containers -gt 0 ]]; then
        docker stop $(docker ps -aq) 2>/dev/null || true
        docker rm $(docker ps -aq) 2>/dev/null || true
        echo "   ${GREEN}✓ Removed $containers containers${NC}"
    else
        echo "   ${GREEN}✓ No containers${NC}"
    fi
    echo ""
}

# ============================================
# [2/12] Remove Images
# ============================================
cleanup_images() {
    echo -e "${BLUE}[2/12] Removing images...${NC}"
    
    local images=$(docker images -q 2>/dev/null | wc -l)
    if [[ $images -gt 0 ]]; then
        docker rmi $(docker images -q) -f 2>/dev/null || true
        echo "   ${GREEN}✓ Removed $images images${NC}"
    else
        echo "   ${GREEN}✓ No images${NC}"
    fi
    echo ""
}

# ============================================
# [3/12] Remove Volumes
# ============================================
cleanup_volumes() {
    echo -e "${BLUE}[3/12] Removing volumes...${NC}"
    
    local volumes=$(docker volume ls -q 2>/dev/null | wc -l)
    if [[ $volumes -gt 0 ]]; then
        docker volume rm $(docker volume ls -q) 2>/dev/null || true
        echo "   ${GREEN}✓ Removed $volumes volumes${NC}"
    else
        echo "   ${GREEN}✓ No volumes${NC}"
    fi
    echo ""
}

# ============================================
# [4/12] Remove Networks
# ============================================
cleanup_networks() {
    echo -e "${BLUE}[4/12] Removing networks...${NC}"
    
    docker network rm ai-platform-network 2>/dev/null || true
    docker network prune -f 2>/dev/null || true
    echo "   ${GREEN}✓ Networks cleaned${NC}"
    echo ""
}

# ============================================
# [5/12] Clean Data Directories
# ============================================
cleanup_data() {
    echo -e "${BLUE}[5/12] Cleaning data directories...${NC}"
    
    if [[ -d /mnt/data ]]; then
        sudo rm -rf /mnt/data/ollama
        sudo rm -rf /mnt/data/litellm
        sudo rm -rf /mnt/data/signal
        sudo rm -rf /mnt/data/dify
        sudo rm -rf /mnt/data/anythingllm
        sudo rm -rf /mnt/data/clawdbot
        sudo rm -rf /mnt/data/gateway
        echo "   ${GREEN}✓ Data directories removed${NC}"
    else
        echo "   ${GREEN}✓ No data directories${NC}"
    fi
    echo ""
}

# ============================================
# [6/12] Clean Repo Files
# ============================================
cleanup_repo() {
    echo -e "${BLUE}[6/12] Cleaning repo files...${NC}"
    
    cd "$SCRIPT_DIR"
    
    # Remove generated directories
    [[ -d stacks ]] && rm -rf stacks && echo "   ${GREEN}✓ stacks/ removed${NC}"
    [[ -d logs ]] && rm -rf logs && echo "   ${GREEN}✓ logs/ removed${NC}"
    
    # Remove config files
    [[ -f .env ]] && rm -f .env && echo "   ${GREEN}✓ .env removed${NC}"
    [[ -f .secrets ]] && rm -f .secrets && echo "   ${GREEN}✓ .secrets removed${NC}"
    
    echo ""
}

# ============================================
# [7/12] Remove Service Users
# ============================================
cleanup_users() {
    echo -e "${BLUE}[7/12] Removing service users...${NC}"
    
    local users=("ollama" "litellm" "signal" "dify" "anythingllm" "clawdbot")
    
    for user in "${users[@]}"; do
        if id "$user" &>/dev/null; then
            sudo userdel "$user" 2>/dev/null || true
            echo "   ${GREEN}✓ Removed: $user${NC}"
        fi
    done
    echo ""
}

# ============================================
# [8/12] Unmount EBS (optional)
# ============================================
unmount_ebs() {
    echo -e "${BLUE}[8/12] Unmount EBS volume?${NC}"
    read -p "Unmount /mnt/data? (y/N): " unmount
    
    if [[ "$unmount" =~ ^[Yy]$ ]]; then
        if mountpoint -q /mnt/data; then
            sudo umount /mnt/data
            sudo sed -i '/\/mnt\/data/d' /etc/fstab
            echo "   ${GREEN}✓ Unmounted${NC}"
        else
            echo "   ${GREEN}✓ Not mounted${NC}"
        fi
    else
        echo "   ${YELLOW}⊘ Skipped${NC}"
    fi
    echo ""
}

# ============================================
# [9/12] Uninstall Docker (optional)
# ============================================
uninstall_docker() {
    echo -e "${BLUE}[9/12] Uninstall Docker?${NC}"
    read -p "Remove Docker Engine? (y/N): " remove_docker
    
    if [[ "$remove_docker" =~ ^[Yy]$ ]]; then
        sudo systemctl stop docker 2>/dev/null || true
        sudo apt-get purge -y docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
        
        sudo rm -rf /var/lib/docker
        sudo rm -rf /var/lib/containerd
        sudo rm -rf /etc/docker
        sudo rm -f /etc/apt/sources.list.d/docker.list
        sudo rm -f /etc/apt/keyrings/docker.gpg
        
        sudo groupdel docker 2>/dev/null || true
        
        echo "   ${GREEN}✓ Docker uninstalled${NC}"
    else
        echo "   ${YELLOW}⊘ Skipped${NC}"
    fi
    echo ""
}

# ============================================
# [10/12] Uninstall NVIDIA (optional)
# ============================================
uninstall_nvidia() {
    echo -e "${BLUE}[10/12] Uninstall NVIDIA?${NC}"
    
    if ! lspci | grep -i nvidia > /dev/null; then
        echo "   ${YELLOW}⊘ No GPU${NC}"
        echo ""
        return 0
    fi
    
    read -p "Remove NVIDIA drivers? (y/N): " remove_nvidia
    
    if [[ "$remove_nvidia" =~ ^[Yy]$ ]]; then
        sudo apt-get purge -y '*nvidia*' 2>/dev/null || true
        sudo apt-get purge -y nvidia-container-toolkit 2>/dev/null || true
        
        sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
        sudo rm -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        
        echo "   ${GREEN}✓ NVIDIA uninstalled (reboot needed)${NC}"
    else
        echo "   ${YELLOW}⊘ Skipped${NC}"
    fi
    echo ""
}

# ============================================
# [11/12] Clean Package Cache
# ============================================
cleanup_packages() {
    echo -e "${BLUE}[11/12] Cleaning package cache...${NC}"
    
    sudo apt-get autoremove -y
    sudo apt-get clean
    
    echo "   ${GREEN}✓ Cache cleaned${NC}"
    echo ""
}

# ============================================
# [12/12] Verify Cleanup
# ============================================
verify_cleanup() {
    echo -e "${BLUE}[12/12] Verifying cleanup...${NC}"
    echo ""
    
    # Check containers
    local containers=$(docker ps -aq 2>/dev/null | wc -l)
    if [[ $containers -eq 0 ]]; then
        echo "   ${GREEN}✓ All containers removed${NC}"
    else
        echo "   ${YELLOW}⚠ $containers containers remain${NC}"
    fi
    
    # Check data dirs
    if [[ ! -d /mnt/data/ollama ]] && [[ ! -d /mnt/data/dify ]]; then
        echo "   ${GREEN}✓ Data directories cleaned${NC}"
    else
        echo "   ${YELLOW}⚠ Some data remains${NC}"
    fi
    
    # Check repo files
    if [[ ! -d "$SCRIPT_DIR/stacks" ]] && [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        echo "   ${GREEN}✓ Repo files cleaned${NC}"
    else
        echo "   ${YELLOW}⚠ Some files remain${NC}"
    fi
    
    # Check Docker
    if command -v docker &> /dev/null; then
        echo "   ${YELLOW}⚠ Docker still installed${NC}"
    else
        echo "   ${GREEN}✓ Docker uninstalled${NC}"
    fi
    
    # Check NVIDIA
    if command -v nvidia-smi &> /dev/null; then
        echo "   ${YELLOW}⚠ NVIDIA drivers remain${NC}"
    else
        echo "   ${GREEN}✓ NVIDIA uninstalled${NC}"
    fi
    
    echo ""
}

# ============================================
# Summary
# ============================================
print_summary() {
    echo -e "${GREEN}✅ Cleanup completed!${NC}"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Next Steps${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}To start fresh:${NC}"
    echo "  1. Reboot: ${YELLOW}sudo reboot${NC}"
    echo "  2. Reconnect: ${YELLOW}ssh $(whoami)@$(hostname)${NC}"
    echo "  3. Go to repo: ${YELLOW}cd $SCRIPT_DIR/scripts${NC}"
    echo "  4. Run setup: ${YELLOW}./1-setup-system.sh${NC}"
    echo ""
}

# ============================================
# Main
# ============================================
main() {
    cleanup_containers
    cleanup_images
    cleanup_volumes
    cleanup_networks
    cleanup_data
    cleanup_repo
    cleanup_users
    unmount_ebs
    uninstall_docker
    uninstall_nvidia
    cleanup_packages
    verify_cleanup
    print_summary
}

main "$@"

