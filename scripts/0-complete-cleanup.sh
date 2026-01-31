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
echo "  • All configuration files"
echo "  • All system users (platform-specific)"
echo "  • All installed packages (NVIDIA, Docker)"
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

    # Stop all AI platform containers
    local containers=$(docker ps -aq --filter "name=ollama" \
                                    --filter "name=litellm" \
                                    --filter "name=signal" \
                                    --filter "name=dify" \
                                    --filter "name=anythingllm" \
                                    --filter "name=clawdbot" \
                                    --filter "name=gateway" 2>/dev/null || true)

    if [[ -n "$containers" ]]; then
        echo "   Stopping containers..."
        docker stop $containers 2>/dev/null || true

        echo "   Removing containers..."
        docker rm -f $containers 2>/dev/null || true

        echo -e "   ${GREEN}✅ Containers removed${NC}"
    else
        echo -e "   ${YELLOW}⚠️  No containers found${NC}"
    fi
}

# ============================================
# Remove Docker Images
# ============================================
cleanup_images() {
    echo -e "\n${BLUE}[2/12] Removing Docker images...${NC}"

    # List of images to remove
    local images=(
        "ollama/ollama"
        "ghcr.io/berriai/litellm"
        "bbernhard/signal-cli-rest-api"
        "langgenius/dify-api"
        "langgenius/dify-web"
        "langgenius/dify-worker"
        "nginx"
        "postgres"
        "redis"
        "weaviate/weaviate"
        "semitechnologies/weaviate"
        "qdrant/qdrant"
        "mintplexlabs/anythingllm"
        "python"
        "squid"
        "clawdbot"
    )

    for img in "${images[@]}"; do
        if docker images | grep -q "$img"; then
            echo "   Removing: $img"
            docker rmi -f $(docker images "$img" -q) 2>/dev/null || true
        fi
    done

    echo -e "   ${GREEN}✅ Images removed${NC}"
}

# ============================================
# Remove Docker Volumes
# ============================================
cleanup_volumes() {
    echo -e "\n${BLUE}[3/12] Removing Docker volumes...${NC}"

    # Remove all volumes with our naming pattern
    local volumes=$(docker volume ls -q | grep -E "ollama|litellm|signal|dify|anythingllm|clawdbot|ai-platform" 2>/dev/null || true)

    if [[ -n "$volumes" ]]; then
        echo "   Removing volumes..."
        echo "$volumes" | xargs docker volume rm -f 2>/dev/null || true
        echo -e "   ${GREEN}✅ Volumes removed${NC}"
    else
        echo -e "   ${YELLOW}⚠️  No volumes found${NC}"
    fi
}

# ============================================
# Remove Docker Networks
# ============================================
cleanup_networks() {
    echo -e "\n${BLUE}[4/12] Removing Docker networks...${NC}"

    if docker network ls | grep -q "ai-platform-network"; then
        echo "   Removing ai-platform-network..."
        docker network rm ai-platform-network 2>/dev/null || true
        echo -e "   ${GREEN}✅ Network removed${NC}"
    else
        echo -e "   ${YELLOW}⚠️  Network not found${NC}"
    fi
}

# ============================================
# Remove Data Directories
# ============================================
cleanup_data() {
    echo -e "\n${BLUE}[5/12] Removing data directories...${NC}"

    local data_dirs=(
        "/home/jglaine/ai-platform-data"
        "/mnt/data"
        "/opt/ai-platform"
    )

    for dir in "${data_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "   Removing: $dir"
            sudo rm -rf "$dir" 2>/dev/null || true
        fi
    done

    echo -e "   ${GREEN}✅ Data directories removed${NC}"
}

# ============================================
# Remove Installer Directory
# ============================================
cleanup_installer() {
    echo -e "\n${BLUE}[6/12] Removing installer files...${NC}"

    if [[ -d "$SCRIPT_DIR" ]]; then
        # Save this script first
        local backup_script="/tmp/cleanup-backup.sh"
        cp "${BASH_SOURCE[0]}" "$backup_script" 2>/dev/null || true

        echo "   Removing: $SCRIPT_DIR"
        rm -rf "$SCRIPT_DIR"

        echo -e "   ${GREEN}✅ Installer removed${NC}"
    fi
}

# ============================================
# Remove System Users
# ============================================
cleanup_users() {
    echo -e "\n${BLUE}[7/12] Removing system users...${NC}"

    local users=("ollama-user" "litellm-user" "signal-user" "dify-user" "anythingllm-user" "clawdbot-user" "gateway-user")

    for user in "${users[@]}"; do
        if id "$user" &>/dev/null; then
            echo "   Removing user: $user"
            sudo userdel -r "$user" 2>/dev/null || true
        fi
    done

    echo -e "   ${GREEN}✅ Users removed${NC}"
}

# ============================================
# Remove Systemd Services
# ============================================
cleanup_systemd() {
    echo -e "\n${BLUE}[8/12] Removing systemd services...${NC}"

    local services=("ai-platform.service")

    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "$service"; then
            echo "   Stopping and disabling: $service"
            sudo systemctl stop "$service" 2>/dev/null || true
            sudo systemctl disable "$service" 2>/dev/null || true
            sudo rm -f "/etc/systemd/system/$service"
        fi
    done

    sudo systemctl daemon-reload
    echo -e "   ${GREEN}✅ Systemd services removed${NC}"
}

# ============================================
# Clean Docker System
# ============================================
cleanup_docker_system() {
    echo -e "\n${BLUE}[9/12] Cleaning Docker system...${NC}"

    echo "   Running docker system prune..."
    docker system prune -af --volumes 2>/dev/null || true

    echo -e "   ${GREEN}✅ Docker system cleaned${NC}"
}

# ============================================
# Remove NVIDIA/CUDA (Optional)
# ============================================
cleanup_nvidia() {
    echo -e "\n${BLUE}[10/12] Remove NVIDIA drivers? (optional)${NC}"

    read -p "   Remove NVIDIA/CUDA packages? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "   Removing NVIDIA packages..."

        sudo apt-get remove --purge -y \
            nvidia-* \
            cuda-* \
            libnvidia-* \
            nvidia-docker2 \
            nvidia-container-toolkit 2>/dev/null || true

        sudo apt-get autoremove -y

        # Remove NVIDIA repositories
        sudo rm -f /etc/apt/sources.list.d/nvidia-*.list
        sudo rm -f /etc/apt/sources.list.d/cuda*.list
        sudo rm -f /usr/share/keyrings/nvidia-*

        echo -e "   ${GREEN}✅ NVIDIA packages removed${NC}"
    else
        echo -e "   ${YELLOW}⚠️  Keeping NVIDIA packages${NC}"
    fi
}

# ============================================
# Remove Docker (Optional)
# ============================================
cleanup_docker() {
    echo -e "\n${BLUE}[11/12] Remove Docker? (optional)${NC}"

    read -p "   Remove Docker completely? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "   Removing Docker..."

        # Stop Docker
        sudo systemctl stop docker 2>/dev/null || true
        sudo systemctl stop docker.socket 2>/dev/null || true

        # Remove packages
        sudo apt-get remove --purge -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin 2>/dev/null || true

        sudo apt-get autoremove -y

        # Remove Docker data
        sudo rm -rf /var/lib/docker
        sudo rm -rf /var/lib/containerd
        sudo rm -rf /etc/docker
        sudo rm -rf ~/.docker

        # Remove Docker group
        sudo groupdel docker 2>/dev/null || true

        # Remove Docker repository
        sudo rm -f /etc/apt/sources.list.d/docker.list
        sudo rm -f /usr/share/keyrings/docker-archive-keyring.gpg

        echo -e "   ${GREEN}✅ Docker removed${NC}"
    else
        echo -e "   ${YELLOW}⚠️  Keeping Docker${NC}"
    fi
}

# ============================================
# Clean APT Cache
# ============================================
cleanup_apt() {
    echo -e "\n${BLUE}[12/12] Cleaning APT cache...${NC}"

    sudo apt-get clean
    sudo apt-get autoclean
    sudo apt-get autoremove -y

    echo -e "   ${GREEN}✅ APT cache cleaned${NC}"
}

# ============================================
# Remove Log Files
# ============================================
cleanup_logs() {
    echo -e "\n${BLUE}Removing log files...${NC}"

    sudo rm -f /var/log/ai-platform*.log
    rm -f ~/ai-platform*.log

    echo -e "   ${GREEN}✅ Log files removed${NC}"
}

# ============================================
# Final Verification
# ============================================
verify_cleanup() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Verification${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # Check containers
    local container_count=$(docker ps -a | grep -E "ollama|litellm|signal|dify|anythingllm|clawdbot" | wc -l)
    if [[ $container_count -eq 0 ]]; then
        echo -e "  ${GREEN}✅ No AI platform containers${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Found $container_count containers${NC}"
    fi

    # Check images
    local image_count=$(docker images | grep -E "ollama|litellm|signal|dify|anythingllm|clawdbot" | wc -l)
    if [[ $image_count -eq 0 ]]; then
        echo -e "  ${GREEN}✅ No AI platform images${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Found $image_count images${NC}"
    fi

    # Check volumes
    local volume_count=$(docker volume ls | grep -E "ollama|litellm|signal|dify|anythingllm|clawdbot|ai-platform" | wc -l)
    if [[ $volume_count -eq 0 ]]; then
        echo -e "  ${GREEN}✅ No AI platform volumes${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Found $volume_count volumes${NC}"
    fi

    # Check data directories
    if [[ ! -d "/home/jglaine/ai-platform-data" ]] && [[ ! -d "/mnt/data" ]] && [[ ! -d "/opt/ai-platform" ]]; then
        echo -e "  ${GREEN}✅ No data directories${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Some data directories remain${NC}"
    fi

    # Check installer
    if [[ ! -d "$SCRIPT_DIR" ]]; then
        echo -e "  ${GREEN}✅ Installer removed${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Installer directory remains${NC}"
    fi
}

# ============================================
# Final Summary
# ============================================
print_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Cleanup Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}System Status:${NC}"
    echo "  • All containers:    Removed"
    echo "  • All images:        Removed"
    echo "  • All volumes:       Removed"
    echo "  • All data:          Removed"
    echo "  • All configs:       Removed"
    echo "  • System users:      Removed"
    echo "  • Systemd services:  Removed"
    echo ""

    if docker --version &>/dev/null; then
        echo -e "  ${YELLOW}⚠️  Docker:          Still installed${NC}"
    else
        echo -e "  ${GREEN}✅ Docker:          Removed${NC}"
    fi

    if nvidia-smi &>/dev/null; then
        echo -e "  ${YELLOW}⚠️  NVIDIA drivers:  Still installed${NC}"
    else
        echo -e "  ${GREEN}✅ NVIDIA drivers:  Removed${NC}"
    fi

    echo ""
    echo -e "${BLUE}Your system is now clean!${NC}"
    echo ""
    echo "To start fresh:"
    echo "  1. Clone installer again:"
    echo "     git clone <repo-url> ~/ai-platform-installer"
    echo "     cd ~/ai-platform-installer/scripts"
    echo ""
    echo "  2. Run setup from scratch:"
    echo "     ./1-setup-system.sh"
    echo ""
    echo -e "${YELLOW}Note: You may want to reboot before reinstalling${NC}"
    echo ""
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
    cleanup_users
    cleanup_systemd
    cleanup_docker_system
    cleanup_logs
    cleanup_nvidia
    cleanup_docker
    cleanup_apt
    verify_cleanup
    cleanup_installer  # This removes the installer directory (including this script)
    print_summary

    echo ""
    echo -e "${BLUE}Recommended: Reboot your system${NC}"
    read -p "Reboot now? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo reboot
    fi
}

main "$@"
CLEANUP_EOF

chmod +x ~/ai-platform-installer/scripts/0-complete-cleanup.sh

🎯 QUICK CLEANUP OPTIONS
If you want partial cleanup instead, here are targeted scripts:
Option A: Clean Data Only (Keep Docker/NVIDIA)
cat > ~/ai-platform-installer/scripts/0-clean-data-only.sh <<'DATA_CLEANUP_EOF'
#!/bin/bash
set -euo pipefail

echo "🧹 Cleaning AI Platform data (keeping Docker/NVIDIA)..."

# Stop containers
docker stop $(docker ps -aq --filter "name=ollama" --filter "name=litellm" --filter "name=signal" --filter "name=dify" --filter "name=anythingllm" --filter "name=clawdbot") 2>/dev/null || true

# Remove containers
docker rm -f $(docker ps -aq --filter "name=ollama" --filter "name=litellm" --filter "name=signal" --filter "name=dify" --filter "name=anythingllm" --filter "name=clawdbot") 2>/dev/null || true

# Remove volumes
docker volume rm $(docker volume ls -q | grep -E "ollama|litellm|signal|dify|anythingllm|clawdbot|ai-platform") 2>/dev/null || true

# Remove data directories
sudo rm -rf /home/jglaine/ai-platform-data
sudo rm -rf /mnt/data
sudo rm -rf /opt/ai-platform

# Remove installer
rm -rf ~/ai-platform-installer

echo "✅ Data cleaned! Docker and NVIDIA remain installed."
echo "Ready to run: ./1-setup-system.sh"
DATA_CLEANUP_EOF

chmod +x ~/ai-platform-installer/scripts/0-clean-data-only.sh
Option B: Clean Containers Only (Keep Images)
cat > ~/ai-platform-installer/scripts/0-clean-containers-only.sh <<'CONTAINER_CLEANUP_EOF'
#!/bin/bash
set -euo pipefail

echo "🧹 Stopping and removing AI Platform containers..."

# Stop all containers
docker stop $(docker ps -aq --filter "name=ollama" --filter "name=litellm" --filter "name=signal" --filter "name=dify" --filter "name=anythingllm" --filter "name=clawdbot" --filter "name=gateway") 2>/dev/null || true

# Remove containers
docker rm -f $(docker ps -aq --filter "name=ollama" --filter "name=litellm" --filter "name=signal" --filter "name=dify" --filter "name=anythingllm" --filter "name=clawdbot" --filter "name=gateway") 2>/dev/null || true

# Remove network
docker network rm ai-platform-network 2>/dev/null || true

echo "✅ Containers removed! Images and data remain."
echo "Ready to run: ./2-deploy-services.sh"

chmod +x ~/ai-platform-installer/scripts/0-clean-containers-only.sh
