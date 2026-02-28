#!/usr/bin/env bash
# 0-complete-cleanup.sh — Full tenant cleanup for AI Platform
# Removes: containers, named volumes, networks, data directories
# Usage: sudo ./0-complete-cleanup.sh [tenant_uid]

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'
log()  { echo -e "${BLUE}[CLEANUP]${NC} $*"; }
ok()   { echo -e "${GREEN}✅${NC} $*"; }
warn() { echo -e "${YELLOW}⚠️ ${NC} $*"; }
err()  { echo -e "${RED}❌${NC} $*"; }

# ── Must be root ──────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"; exit 1
fi

# ── Discover tenant ───────────────────────────────────────────────
TENANT_UID="${1:-}"
MOUNT_POINTS=()

# Find all EBS mount points that contain a .env file
while IFS= read -r env_file; do
  MOUNT_POINTS+=("$(dirname "$env_file")")
done < <(find /mnt/data -maxdepth 2 -name ".env" 2>/dev/null)

# Also check /home for non-EBS setups
while IFS= read -r env_file; do
  MOUNT_POINTS+=("$(dirname "$env_file")")
done < <(find /home -maxdepth 3 -name ".env" 2>/dev/null | grep -v '\.npm\|snap\|\.config')

if [[ ${#MOUNT_POINTS[@]} -eq 0 ]]; then
  warn "No tenant .env files found — will still clean Docker artifacts"
  MOUNT_POINTS=()
fi

# ── Confirm before destruction ────────────────────────────────────
echo ""
echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}${BOLD}  ⚠️  COMPLETE DESTRUCTIVE CLEANUP ⚠️${NC}"
echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "This will PERMANENTLY DELETE:"
echo "  • All AI platform containers"
echo "  • All named Docker volumes (postgres, qdrant, minio, redis, etc.)"
echo "  • All Docker networks prefixed with 'aip-'"
echo "  • All tenant data directories:"
for mp in "${MOUNT_POINTS[@]}"; do
  echo "    - ${mp}"
done
echo ""
read -rp "Type CONFIRM to proceed: " CONFIRM
if [[ "$CONFIRM" != "CONFIRM" ]]; then
  echo "Aborted."; exit 0
fi

# ── Phase 1: Stop and remove containers ──────────────────────────
log "Phase 1: Stopping all AI platform containers..."

# Stop via compose for each tenant
for TENANT_DIR in "${MOUNT_POINTS[@]}"; do
  ENV_FILE="${TENANT_DIR}/.env"
  COMPOSE_FILE="${TENANT_DIR}/docker-compose.yml"
  # Also check script directory for compose file
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [[ ! -f "$COMPOSE_FILE" ]] && COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

  if [[ -f "$ENV_FILE" && -f "$COMPOSE_FILE" ]]; then
    PROJECT=$(grep "^COMPOSE_PROJECT_NAME=" "$ENV_FILE" | cut -d= -f2 || true)
    if [[ -n "$PROJECT" ]]; then
      log "  Stopping compose project: ${PROJECT}"
      docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" \
        down --remove-orphans --timeout 10 2>/dev/null || true
    fi
  fi
done

# Force-remove any remaining aip- prefixed containers
log "  Force-removing any remaining aip- containers..."
docker ps -aq --filter "name=aip-" | xargs -r docker rm -f 2>/dev/null || true

# Also catch containers with project label
docker ps -aq --filter "label=com.docker.compose.project" \
  | xargs -r docker inspect --format '{{.Name}} {{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null \
  | grep "aip-" \
  | awk '{print $1}' \
  | xargs -r docker rm -f 2>/dev/null || true

ok "Containers removed"

# ── Phase 2: Remove ALL named volumes ────────────────────────────
log "Phase 2: Removing named Docker volumes..."

# Remove volumes by tenant project name
for TENANT_DIR in "${MOUNT_POINTS[@]}"; do
  ENV_FILE="${TENANT_DIR}/.env"
  if [[ -f "$ENV_FILE" ]]; then
    PROJECT=$(grep "^COMPOSE_PROJECT_NAME=" "$ENV_FILE" | cut -d= -f2 || true)
    if [[ -n "$PROJECT" ]]; then
      log "  Removing volumes for project: ${PROJECT}"
      # List and remove all volumes with this project prefix
      docker volume ls --format '{{.Name}}' | grep "^${PROJECT}" \
        | xargs -r docker volume rm -f 2>/dev/null || true
      # Also try explicit names that compose creates
      for VOL in postgres-data redis-data qdrant-data minio-data \
                 n8n-data flowise-data anythingllm-data \
                 dify-api-data signal-data; do
        docker volume rm -f "${PROJECT}_${VOL}" 2>/dev/null || true
      done
    fi
  fi
done

# Catch-all: remove any remaining aip- prefixed volumes
log "  Removing any remaining aip- volumes..."
docker volume ls --format '{{.Name}}' | grep "^aip-" \
  | xargs -r docker volume rm -f 2>/dev/null || true

# Remove anonymous volumes left over
docker volume prune -f 2>/dev/null || true

ok "Named volumes removed"

# ── Phase 3: Remove networks ──────────────────────────────────────
log "Phase 3: Removing AI platform networks..."

# Disconnect all containers from aip- networks first
docker network ls --format '{{.Name}}' | grep "^aip-" | while read -r net; do
  log "  Disconnecting containers from network: ${net}"
  docker network inspect "$net" \
    --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null \
    | tr ' ' '\n' \
    | xargs -r -I{} docker network disconnect -f "$net" {} 2>/dev/null || true
  docker network rm "$net" 2>/dev/null || true
done

# Also remove bridge networks that may have been created manually
docker network ls --format '{{.Name}} {{.Driver}}' \
  | grep ' bridge$' \
  | awk '{print $1}' \
  | grep -v '^bridge$\|^host$\|^none$' \
  | grep 'aip\|aiplatform\|net_internal\|net_default' \
  | xargs -r docker network rm 2>/dev/null || true

ok "Networks removed"

# ── Phase 4: Remove tenant data directories ───────────────────────
log "Phase 4: Removing tenant data directories..."

for TENANT_DIR in "${MOUNT_POINTS[@]}"; do
  if [[ -d "$TENANT_DIR" ]]; then
    log "  Removing: ${TENANT_DIR}"
    # Unmount any bind mounts inside the directory first
    mount | grep "${TENANT_DIR}" | awk '{print $3}' \
      | sort -r | xargs -r umount -f 2>/dev/null || true
    rm -rf "${TENANT_DIR:?}"
    ok "  Removed: ${TENANT_DIR}"
  fi
done

# ── Phase 5: Remove AppArmor profiles ────────────────────────────
log "Phase 5: Cleaning AppArmor profiles..."
for profile in /etc/apparmor.d/aip-* /etc/apparmor.d/docker-aip-*; do
  [[ -f "$profile" ]] || continue
  apparmor_parser -R "$profile" 2>/dev/null || true
  rm -f "$profile"
  log "  Removed AppArmor profile: $(basename $profile)"
done
ok "AppArmor profiles cleaned"

# ── Phase 6: Clean Docker build cache ────────────────────────────
log "Phase 6: Cleaning Docker build cache..."
docker builder prune -f 2>/dev/null || true
ok "Build cache cleared"

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  ✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Remaining Docker state:"
echo "  Containers : $(docker ps -aq | wc -l) total ($(docker ps -q | wc -l) running)"
echo "  Volumes    : $(docker volume ls -q | wc -l) total"
echo "  Networks   : $(docker network ls -q | wc -l) total (bridge/host/none = 3 baseline)"
echo ""
echo "Run 'sudo ./1-setup-system.sh' to start fresh."
