#!/usr/bin/env bash
# TRUE Nuclear Cleanup - Removes ALL AI Platform remnants
# This is the REAL cleanup that removes everything

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${BLUE}[NUCLEAR]${NC} $*"; }
ok()   { echo -e "${GREEN}✅${NC} $*"; }
warn() { echo -e "${YELLOW}⚠️ ${NC} $*"; }
err()  { echo -e "${RED}❌${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"; exit 1
fi

echo -e "${RED}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${RED}${BOLD}  ⚠️  NUCLEAR CLEANUP - THIS WILL DELETE EVERYTHING ⚠️${NC}"
echo -e "${RED}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "This will remove:"
echo "  • ALL Docker containers with 'aip-' prefix"
echo "  • ALL Docker networks with 'aip-' prefix"
echo "  • ALL Docker volumes with 'aip-' prefix"
echo "  • ALL tenant data directories"
echo "  • ALL state files"
echo ""
echo -e "${YELLOW}Type 'NUCLEAR' to confirm: ${NC}"
read -r CONFIRM
if [[ "$CONFIRM" != "NUCLEAR" ]]; then
  echo "Aborted."; exit 0
fi

log "Starting nuclear cleanup..."

# Phase 1: Kill all containers
log "Phase 1: Killing all AI Platform containers..."
docker ps --filter "name=aip-" --format "{{.Names}}" | xargs -r docker kill -f 2>/dev/null || true
docker ps --filter "name=aip-" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
docker ps -aq --filter "name=aip-" | xargs -r docker rm -f 2>/dev/null || true
ok "All containers killed and removed"

# Phase 2: Remove all networks
log "Phase 2: Removing all AI Platform networks..."
docker network ls --format "{{.Name}}" | grep "^aip-" | xargs -r docker network rm -f 2>/dev/null || true
ok "All networks removed"

# Phase 3: Remove all volumes
log "Phase 3: Removing all AI Platform volumes..."
docker volume ls --format "{{.Name}}" | grep "^aip-" | xargs -r docker volume rm -f 2>/dev/null || true
docker volume ls --filter "label=com.docker.compose.project" --format "{{.Name}}" | grep "aip-" | xargs -r docker volume rm -f 2>/dev/null || true
docker volume prune -f >/dev/null 2>&1 || true
ok "All volumes removed"

# Phase 4: Remove all tenant data
log "Phase 4: Removing all tenant data directories..."
if [[ -d "/mnt/data" ]]; then
  find /mnt/data -maxdepth 2 -name ".env" -exec dirname {} \; | while read -r tenant_dir; do
    if [[ "$tenant_dir" =~ ^/mnt/data/u[0-9]+$ ]]; then
      log "Removing tenant directory: $tenant_dir"
      rm -rf "$tenant_dir"
    fi
  done
fi

# Phase 5: Remove state files
log "Phase 5: Removing all state files..."
rm -rf /mnt/data/metadata/
rm -f /etc/ai-platform/env-pointer
ok "All state files removed"

# Phase 6: Final cleanup
log "Phase 6: Final Docker cleanup..."
docker system prune -af --volumes >/dev/null 2>&1 || true
docker network prune -f >/dev/null 2>&1 || true

echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✅ NUCLEAR CLEANUP COMPLETE - EVERYTHING GONE ✅${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo ""
log "Verification:"
docker ps --filter "name=aip-" --format "table {{.Names}}\t{{.Status}}" || echo "  No aip- containers found"
docker network ls --format "table {{.Name}}\t{{.Driver}}" | grep "aip-" || echo "  No aip- networks found"
docker volume ls --format "table {{.Name}}\t{{.Driver}}" | grep "aip-" || echo "  No aip- volumes found"
echo ""
ok "Nuclear cleanup completed successfully!"
