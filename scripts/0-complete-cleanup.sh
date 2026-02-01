#!/bin/bash
set -euo pipefail

# ============================================
# AI Platform - Complete System Reset v5.4
# Stops all services before cleanup
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Auto-detect script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
    echo -e "$1"
}

echo ""
log "${RED}========================================${NC}"
log "${RED}⚠️  COMPLETE SYSTEM RESET${NC}"
log "${RED}========================================${NC}"
log "${YELLOW}This will remove:${NC}"
log "  • All Docker containers & images"
log "  • All Docker networks & volumes"
log "  • All service data in /mnt/data"
log "  • Docker Engine"
log "  • NVIDIA drivers (if installed)"
log "  • Tailscale"
log "  • Service users (ollama, litellm, signal, dify, anythingllm)"
echo ""
read -p "Continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    log "${BLUE}Reset cancelled${NC}"
    exit 0
fi

echo ""
log "${BLUE}========================================${NC}"
log "${BLUE}Starting Complete Reset${NC}"
log "${BLUE}Started: $(date)${NC}"
log "${BLUE}========================================${NC}"
echo ""

# ============================================
# [1/12] Stop All Docker Containers
# ============================================
log "${BLUE}[1/12] Stopping all Docker containers...${NC}"
if docker ps -q &>/dev/null; then
    CONTAINERS=$(docker ps -aq)
    if [[ -n "$CONTAINERS" ]]; then
        docker stop $CONTAINERS 2>/dev/null || true
        docker rm -f $CONTAINERS 2>/dev/null || true
        log "   ${GREEN}✓ All containers stopped${NC}"
    else
        log "   ${YELLOW}No containers to stop${NC}"
    fi
else
    log "   ${YELLOW}Docker not running${NC}"
fi
echo ""

# ============================================
# [2/12] Remove All Docker Networks
# ============================================
log "${BLUE}[2/12] Removing all Docker networks...${NC}"
if docker network ls -q &>/dev/null; then
    # Remove custom networks (skip default ones)
    NETWORKS=$(docker network ls --filter "type=custom" -q)
    if [[ -n "$NETWORKS" ]]; then
        docker network rm $NETWORKS 2>/dev/null || true
        log "   ${GREEN}✓ Custom networks removed${NC}"
    else
        log "   ${YELLOW}No custom networks to remove${NC}"
    fi
else
    log "   ${YELLOW}Docker not running${NC}"
fi
echo ""

# ============================================
# [3/12] Remove All Docker Volumes
# ============================================
log "${BLUE}[3/12] Removing all Docker volumes...${NC}"
if docker volume ls -q &>/dev/null; then
    VOLUMES=$(docker volume ls -q)
    if [[ -n "$VOLUMES" ]]; then
        docker volume rm $VOLUMES 2>/dev/null || true
        log "   ${GREEN}✓ All volumes removed${NC}"
    else
        log "   ${YELLOW}No volumes to remove${NC}"
    fi
else
    log "   ${YELLOW}Docker not running${NC}"
fi
echo ""

# ============================================
# [4/12] Stop Docker Service
# ============================================
log "${BLUE}[4/12] Stopping Docker service...${NC}"
if systemctl is-active --quiet docker; then
    sudo systemctl stop docker.socket 2>/dev/null || true
    sudo systemctl stop docker 2>/dev/null || true
    log "   ${GREEN}✓ Docker service stopped${NC}"
else
    log "   ${YELLOW}Docker service not running${NC}"
fi
echo ""

# ============================================
# [5/12] Unmount /mnt/data (Force)
# ============================================
log "${BLUE}[5/12] Unmounting /mnt/data...${NC}"

# Kill processes using /mnt/data
if mountpoint -q /mnt/data; then
    log "   ${YELLOW}Killing processes using /mnt/data...${NC}"
    sudo fuser -km /mnt/data 2>/dev/null || true
    sleep 2
    
    # Force unmount
    if sudo umount -f /mnt/data 2>/dev/null; then
        log "   ${GREEN}✓ /mnt/data unmounted${NC}"
    elif sudo umount -l /mnt/data 2>/dev/null; then
        log "   ${GREEN}✓ /mnt/data lazy unmounted${NC}"
    else
        log "   ${YELLOW}⚠ Could not unmount /mnt/data (may need reboot)${NC}"
    fi
else
    log "   ${YELLOW}/mnt/data not mounted${NC}"
fi
echo ""

# ============================================
# [6/12] Clean /mnt/data Directory
# ============================================
log "${BLUE}[6/12] Cleaning /mnt/data directory...${NC}"
if [[ -d /mnt/data ]]; then
    sudo rm -rf /mnt/data/* 2>/dev/null || true
    log "   ${GREEN}✓ /mnt/data cleaned${NC}"
fi
echo ""

# ============================================
# [7/12] Remove fstab Entry
# ============================================
log "${BLUE}[7/12] Removing /mnt/data from fstab...${NC}"
if grep -q "/mnt/data" /etc/fstab 2>/dev/null; then
    sudo sed -i '\|/mnt/data|d' /etc/fstab
    sudo systemctl daemon-reload
    log "   ${GREEN}✓ fstab entry removed${NC}"
else
    log "   ${YELLOW}No fstab entry found${NC}"
fi
echo ""

# ============================================
# [8/12] Remove Docker Completely
# ============================================
log "${BLUE}[8/12] Uninstalling Docker...${NC}"

# Remove Docker packages
if dpkg -l | grep -q docker; then
    log "   ${YELLOW}Removing Docker packages...${NC}"
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
    sudo apt-get autoremove -y 2>/dev/null || true
    log "   ${GREEN}✓ Docker packages removed${NC}"
fi

# Remove Docker data
if [[ -d /var/lib/docker ]]; then
    log "   ${YELLOW}Removing Docker data...${NC}"
    sudo rm -rf /var/lib/docker
    sudo rm -rf /var/lib/containerd
    log "   ${GREEN}✓ Docker data removed${NC}"
fi

# Remove Docker group
if getent group docker &>/dev/null; then
    sudo groupdel docker 2>/dev/null || true
    log "   ${GREEN}✓ Docker group removed${NC}"
fi

echo ""

# ============================================
# [9/12] Remove Docker Compose
# ============================================
log "${BLUE}[9/12] Removing Docker Compose...${NC}"
if [[ -f /usr/local/bin/docker-compose ]]; then
    sudo rm -f /usr/local/bin/docker-compose
    log "   ${GREEN}✓ Docker Compose removed${NC}"
else
    log "   ${YELLOW}Docker Compose not installed${NC}"
fi
echo ""

# ============================================
# [10/12] Uninstall NVIDIA Drivers
# ============================================
log "${BLUE}[10/12] Uninstalling NVIDIA drivers...${NC}"
if dpkg -l | grep -q nvidia; then
    sudo apt-get purge -y 'nvidia-*' 2>/dev/null || true
    sudo apt-get autoremove -y 2>/dev/null || true
    log "   ${GREEN}✓ NVIDIA drivers removed${NC}"
else
    log "   ${YELLOW}⚠ NVIDIA drivers not installed${NC}"
fi
echo ""

# ============================================
# [11/12] Uninstall Tailscale
# ============================================
log "${BLUE}[11/12] Uninstalling Tailscale...${NC}"
if command -v tailscale &>/dev/null; then
    sudo tailscale down 2>/dev/null || true
    sudo apt-get purge -y tailscale 2>/dev/null || true
    sudo rm -rf /var/lib/tailscale
    log "   ${GREEN}✓ Tailscale removed${NC}"
else
    log "   ${YELLOW}Tailscale not installed${NC}"
fi
echo ""

# ============================================
# [12/12] Remove Service Users
# ============================================
log "${BLUE}[12/12] Removing service users...${NC}"

USERS=("ollama" "litellm" "signal" "dify" "anythingllm")
for user in "${USERS[@]}"; do
    if id "$user" &>/dev/null; then
        sudo userdel -r "$user" 2>/dev/null || true
        log "   ${GREEN}✓ Removed user: $user${NC}"
    fi
done

echo ""

# ============================================
# Summary
# ============================================
log "${GREEN}========================================${NC}"
log "${GREEN}✅ Reset Complete${NC}"
log "${GREEN}========================================${NC}"
echo ""
log "${BLUE}System Status:${NC}"
log "  Docker:     $(command -v docker &>/dev/null && echo 'Removed' || echo '✓ Not installed')"
log "  NVIDIA:     $(command -v nvidia-smi &>/dev/null && echo 'Still installed' || echo '✓ Not installed')"
log "  Tailscale:  $(command -v tailscale &>/dev/null && echo 'Still installed' || echo '✓ Not installed')"
log "  /mnt/data:  $(mountpoint -q /mnt/data && echo 'Still mounted' || echo '✓ Unmounted')"
echo ""
log "${YELLOW}Next Steps:${NC}"
log "  1. ${YELLOW}Reboot system:${NC} sudo reboot"
log "  2. ${YELLOW}Reconnect:${NC}     ssh $USER@$(hostname)"
log "  3. ${YELLOW}Start fresh:${NC}   cd $SCRIPT_DIR/scripts && ./1-setup-system.sh"
echo ""

