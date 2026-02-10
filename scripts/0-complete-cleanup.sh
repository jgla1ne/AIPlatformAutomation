#!/bin/bash
# ==============================================================================
# Script 0: Nuclear Cleanup Script ☢️
# Version: 4.0 - Modular Architecture Support
# Purpose: Complete system reset for fresh deployment
# WARNING: This script destroys ALL data and configurations
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="/var/log/nuclear_cleanup_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

# ==============================================================================
# SAFETY CHECKS
# ==============================================================================

echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║           ☢️  NUCLEAR CLEANUP SCRIPT v3.0 ☢️              ║${NC}"
echo -e "${RED}║                                                            ║${NC}"
echo -e "${RED}║  THIS SCRIPT WILL PERMANENTLY DESTROY:                    ║${NC}"
echo -e "${RED}║  • All Docker containers, images, and volumes             ║${NC}"
echo -e "${RED}║  • All data in /mnt/data/*                                ║${NC}"
echo -e "${RED}║  • All configurations in /root/scripts/                   ║${NC}"
echo -e "${RED}║  • PostgreSQL databases                                   ║${NC}"
echo -e "${RED}║  • Ollama models                                          ║${NC}"
echo -e "${RED}║  • n8n workflows                                          ║${NC}"
echo -e "${RED}║  • Qdrant collections                                     ║${NC}"
echo -e "${RED}║  • SSL certificates                                       ║${NC}"
echo -e "${RED}║  • Systemd services                                       ║${NC}"
echo -e "${RED}║  • Network configurations                                 ║${NC}"
echo -e "${RED}║                                                            ║${NC}"
echo -e "${RED}║  ⚠️  DATA LOSS IS IRREVERSIBLE ⚠️                         ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Require explicit confirmation
read -p "Type 'DESTROY EVERYTHING' to proceed: " confirmation
if [ "$confirmation" != "DESTROY EVERYTHING" ]; then
    echo -e "${GREEN}Cleanup cancelled. System unchanged.${NC}"
    exit 0
fi

echo ""
read -p "Are you ABSOLUTELY SURE? Type 'YES' to continue: " final_confirm
if [ "$final_confirm" != "YES" ]; then
    echo -e "${GREEN}Cleanup cancelled. System unchanged.${NC}"
    exit 0
fi

echo -e "${RED}Starting nuclear cleanup in 5 seconds... Press Ctrl+C to abort${NC}"
sleep 5

# ==============================================================================
# CLEANUP FUNCTIONS
# ==============================================================================

log_step() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗${NC} $1"
}

# ==============================================================================
# STEP 1: Stop All Services
# ==============================================================================

log_step "Stopping all Docker services..."
if command -v docker &> /dev/null; then
    # Stop modular compose files first
    if [ -d "/mnt/data/ai-platform/docker" ]; then
        for compose_file in /mnt/data/ai-platform/docker/docker-compose.*.yml; do
            if [ -f "$compose_file" ]; then
                log_step "Stopping services from $(basename "$compose_file")..."
                docker compose -f "$compose_file" down --remove-orphans 2>/dev/null || true
            fi
        done
    fi
    
    # Legacy monolithic compose (backwards compatibility)
    docker compose -f /root/scripts/docker-compose.yml down --remove-orphans 2>/dev/null || true
    docker stop $(docker ps -aq) 2>/dev/null || true
    log_success "Docker services stopped"
else
    log_error "Docker not found, skipping"
fi

# ==============================================================================
# STEP 2: Stop Systemd Services
# ==============================================================================

log_step "Stopping and disabling systemd services..."
SERVICES=(
    "ai-platform"
    "ollama"
    "qdrant"
    "n8n"
    "postgresql"
    "redis"
    "litellm"
    "dify-api"
    "dify-web"
    "dify-worker"
    "dify-sandbox"
    "open-webui"
    "flowise"
    "anythingllm"
    "openclaw"
    "prometheus"
    "grafana"
    "loki"
    "minio"
    "tailscale"
    "supertokens"
    "signal"
    "chromadb"
    "weaviate"
    "caddy"
    "traefik"
    "portainer"
)

for service in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        systemctl stop "$service" 2>/dev/null || true
        systemctl disable "$service" 2>/dev/null || true
        log_success "Stopped and disabled $service"
    fi
done

# Remove service files
for service in "${SERVICES[@]}"; do
    rm -f "/etc/systemd/system/${service}.service"
done
systemctl daemon-reload
log_success "Systemd services removed"

# ==============================================================================
# STEP 3: Remove Docker Resources
# ==============================================================================

log_step "Removing all Docker containers..."
if command -v docker &> /dev/null; then
    docker rm -f $(docker ps -aq) 2>/dev/null || true
    log_success "Docker containers removed"
    
    log_step "Removing all Docker images..."
    docker rmi -f $(docker images -aq) 2>/dev/null || true
    log_success "Docker images removed"
    
    log_step "Removing all Docker volumes..."
    docker volume rm -f $(docker volume ls -q) 2>/dev/null || true
    log_success "Docker volumes removed"
    
    log_step "Removing all Docker networks..."
    docker network rm $(docker network ls -q) 2>/dev/null || true
    log_success "Docker networks removed"
    
    log_step "Pruning Docker system..."
    docker system prune -af --volumes 2>/dev/null || true
    log_success "Docker system pruned"
fi

# ==============================================================================
# STEP 4: Remove Data Directories
# ==============================================================================

log_step "Removing data directories..."
DATA_DIRS=(
    "/mnt/data/ai-platform"           # New modular structure
    "/mnt/data/postgresql"            # Legacy structure
    "/mnt/data/ollama"
    "/mnt/data/n8n"
    "/mnt/data/qdrant"
    "/mnt/data/backups"
    "/mnt/data/logs"
)

for dir in "${DATA_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        rm -rf "$dir"
        log_success "Removed $dir"
    fi
done

# Recreate empty structure for new architecture
mkdir -p /mnt/data/ai-platform/{docker,config,data,logs,scripts,backups}
log_success "Recreated empty modular data structure"

# ==============================================================================
# STEP 5: Remove Configuration Files
# ==============================================================================

log_step "Removing configuration files..."
CONFIG_FILES=(
    "/root/scripts/config.env"
    "/root/scripts/docker-compose.yml"
    "/root/scripts/.env"
    "/root/scripts/nginx.conf"
    "/root/scripts/postgres-init.sql"
    "/mnt/data/ai-platform/config/master.env"        # New structure
    "/mnt/data/ai-platform/config/service-selection.env"
    "/mnt/data/ai-platform/config/hardware-profile.env"
)

for file in "${CONFIG_FILES[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file"
        log_success "Removed $file"
    fi
done

# ==============================================================================
# STEP 6: Remove SSL Certificates
# ==============================================================================

log_step "Removing SSL certificates..."
if [ -d "/etc/letsencrypt" ]; then
    rm -rf /etc/letsencrypt
    log_success "Removed Let's Encrypt certificates"
fi

if [ -d "/root/scripts/ssl" ]; then
    rm -rf /root/scripts/ssl
    log_success "Removed local SSL certificates"
fi

# ==============================================================================
# STEP 7: Clean Package Managers
# ==============================================================================

log_step "Cleaning package manager caches..."
if command -v apt-get &> /dev/null; then
    apt-get clean
    apt-get autoclean
    apt-get autoremove -y
    log_success "APT cache cleaned"
fi

# ==============================================================================
# STEP 8: Remove Temporary Files
# ==============================================================================

log_step "Removing temporary files..."
rm -rf /tmp/ai-platform-* 2>/dev/null || true
rm -rf /var/tmp/ai-platform-* 2>/dev/null || true
log_success "Temporary files removed"

# ==============================================================================
# STEP 9: Clean Logs
# ==============================================================================

log_step "Cleaning system logs..."
journalctl --vacuum-time=1s 2>/dev/null || true
rm -rf /var/log/ai-platform-* 2>/dev/null || true
log_success "System logs cleaned"

# ==============================================================================
# STEP 10: Remove Firewall Rules
# ==============================================================================

log_step "Resetting firewall rules..."
if command -v ufw &> /dev/null; then
    ufw --force reset 2>/dev/null || true
    ufw --force disable 2>/dev/null || true
    log_success "UFW reset"
fi

# ==============================================================================
# STEP 11: Clean User Profiles
# ==============================================================================

log_step "Cleaning user profiles..."
rm -f /root/.n8n_* 2>/dev/null || true
rm -f /root/.ollama_* 2>/dev/null || true
rm -rf /root/.config/qdrant 2>/dev/null || true
log_success "User profiles cleaned"

# ==============================================================================
# STEP 12: Verify Cleanup
# ==============================================================================

log_step "Verifying cleanup..."

VERIFICATION_PASSED=true

# Check Docker
if [ "$(docker ps -aq 2>/dev/null | wc -l)" -gt 0 ]; then
    log_error "Docker containers still exist"
    VERIFICATION_PASSED=false
fi

# Check data directories
for dir in "${DATA_DIRS[@]}"; do
    if [ -n "$(ls -A $dir 2>/dev/null)" ]; then
        log_error "$dir is not empty"
        VERIFICATION_PASSED=false
    fi
done

# Check systemd services
for service in "${SERVICES[@]}"; do
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        log_error "$service is still enabled"
        VERIFICATION_PASSED=false
    fi
done

if [ "$VERIFICATION_PASSED" = true ]; then
    log_success "All verification checks passed"
else
    log_error "Some verification checks failed"
fi

# ==============================================================================
# FINAL REPORT
# ==============================================================================

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Nuclear Cleanup Complete ✓                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Cleanup Summary:"
echo "  • Docker containers: Removed"
echo "  • Docker images: Removed"
echo "  • Docker volumes: Removed"
echo "  • Data directories: Cleaned"
echo "  • Configuration files: Removed"
echo "  • SSL certificates: Removed"
echo "  • Systemd services: Disabled and removed"
echo "  • System logs: Cleaned"
echo ""
echo "Log file saved to: $LOG_FILE"
echo ""
echo -e "${YELLOW}System is ready for fresh deployment.${NC}"
echo -e "${YELLOW}Reboot recommended: sudo reboot${NC}"
echo ""

# Optional automatic reboot
read -p "Reboot now? (y/N): " reboot_confirm
if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
    echo "Rebooting in 5 seconds..."
    sleep 5
    reboot
fi

exit 0

