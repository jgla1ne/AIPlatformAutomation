#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform - Complete Cleanup Script
# Version: 5.0 - COMPLETE NETWORK REMOVAL
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║          AI Platform - Complete Cleanup v5              ║
║              THOROUGH NETWORK REMOVAL                   ║
╚════════════════════════════════════════════════════════════╝
EOF

echo ""
log_warning "This will remove ALL AI Platform data and containers!"
read -p "Continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    log_info "Cleanup cancelled"
    exit 0
fi

echo ""
log_info "Starting complete cleanup..."

# ============================================================================
# STOP ALL COMPOSE SERVICES
# ============================================================================
log_info "[1/8] Stopping Docker Compose services..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [[ -f "${PROJECT_ROOT}/docker-compose.yml" ]]; then
    cd "$PROJECT_ROOT"
    docker compose down --remove-orphans -v 2>/dev/null || true
    log_success "Compose services stopped"
else
    log_warning "No docker-compose.yml found, skipping"
fi

# ============================================================================
# STOP AND REMOVE ALL AI PLATFORM CONTAINERS
# ============================================================================
log_info "[2/8] Removing all AI Platform containers..."

# List of all possible container names
containers=(
    "nginx"
    "clawdbot"
    "gdrive-sync"
    "signal-api"
    "n8n"
    "dify-worker"
    "dify-web"
    "dify-api"
    "dify-weaviate"
    "dify-redis"
    "dify-db"
    "anythingllm"
    "litellm"
    "ollama"
)

for container in "${containers[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        log_info "Removing container: $container"
        docker stop "$container" 2>/dev/null || true
        docker rm -f "$container" 2>/dev/null || true
    fi
done

# Remove any remaining containers with ai-platform prefix
docker ps -a --format '{{.Names}}' | grep -i "ai-platform" | xargs -r docker rm -f 2>/dev/null || true

log_success "All containers removed"

# ============================================================================
# REMOVE ALL NETWORKS (BOTH OLD AND NEW)
# ============================================================================
log_info "[3/8] Removing all AI Platform networks..."

# List of all possible network names
networks=(
    "ai-platform"
    "ai-platform-network"
    "ai_platform"
    "aiplatform_default"
    "ai-platform_default"
)

for network in "${networks[@]}"; do
    if docker network ls --format '{{.Name}}' | grep -q "^${network}$"; then
        log_info "Removing network: $network"
        docker network rm "$network" 2>/dev/null || true
    fi
done

# Force remove any network with ai-platform in the name
docker network ls --format '{{.Name}}' | grep -i "ai-platform" | xargs -r docker network rm 2>/dev/null || true

log_success "All networks removed"

# ============================================================================
# REMOVE ALL VOLUMES
# ============================================================================
log_info "[4/8] Removing all volumes..."

volumes=(
    "ollama_data"
    "anythingllm_data"
    "dify_postgres"
    "dify_redis"
    "dify_weaviate"
    "dify_storage"
    "n8n_data"
    "signal_data"
    "clawdbot_data"
    "gdrive_data"
)

for volume in "${volumes[@]}"; do
    if docker volume ls --format '{{.Name}}' | grep -q "^${volume}$"; then
        log_info "Removing volume: $volume"
        docker volume rm "$volume" 2>/dev/null || true
    fi
done

# Remove volumes with ai-platform prefix
docker volume ls --format '{{.Name}}' | grep -i "ai-platform" | xargs -r docker volume rm 2>/dev/null || true

log_success "All volumes removed"

# ============================================================================
# REMOVE IMAGES
# ============================================================================
log_info "[5/8] Removing custom images..."

if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "ai-platform-clawdbot"; then
    docker rmi -f ai-platform-clawdbot:latest 2>/dev/null || true
    log_success "Custom images removed"
else
    log_info "No custom images found"
fi

# ============================================================================
# CLEAN DATA DIRECTORIES
# ============================================================================
log_info "[6/8] Cleaning data directories..."

if [[ -d "${PROJECT_ROOT}/data" ]]; then
    sudo rm -rf "${PROJECT_ROOT}/data"
    mkdir -p "${PROJECT_ROOT}/data"
    log_success "Data directories cleaned"
else
    log_info "No data directory found"
fi

# ============================================================================
# CLEAN CONFIG FILES
# ============================================================================
log_info "[7/8] Cleaning configuration files..."

files_to_remove=(
    "${PROJECT_ROOT}/.env"
    "${PROJECT_ROOT}/docker-compose.yml"
)

for file in "${files_to_remove[@]}"; do
    if [[ -f "$file" ]]; then
        rm -f "$file"
        log_info "Removed: $(basename $file)"
    fi
done

# Clean config directories but keep structure
if [[ -d "${PROJECT_ROOT}/config" ]]; then
    find "${PROJECT_ROOT}/config" -type f -delete 2>/dev/null || true
    log_success "Configuration files cleaned"
fi

# ============================================================================
# DOCKER SYSTEM PRUNE
# ============================================================================
log_info "[8/8] Running Docker system prune..."

docker system prune -af --volumes 2>/dev/null || true

log_success "Docker system cleaned"

# ============================================================================
# VERIFY CLEANUP
# ============================================================================
echo ""
log_info "Verifying cleanup..."

echo ""
echo "Remaining containers:"
docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep -i "ai-platform" || echo "  None"

echo ""
echo "Remaining networks:"
docker network ls --format "table {{.Name}}\t{{.Driver}}" | grep -i "ai-platform" || echo "  None"

echo ""
echo "Remaining volumes:"
docker volume ls --format "table {{.Name}}\t{{.Driver}}" | grep -i "ai-platform" || echo "  None"

echo ""
echo "Remaining images:"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -i "ai-platform" || echo "  None"

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "✅ COMPLETE CLEANUP FINISHED!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Next steps:"
echo "  1. Run: ./1-setup-system.sh"
echo "  2. Run: ./2-deploy-services.sh"
echo ""
