#!/usr/bin/env bash
# SYSTEMATIC Nuclear Cleanup - Removes ALL AI Platform remnants
# Automatically detects and cleans selected tenant containers

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${BLUE}[CLEANUP]${NC} $*"; }
ok()   { echo -e "${GREEN}✅${NC} $*"; }
warn() { echo -e "${YELLOW}⚠️ ${NC} $*"; }
err()  { echo -e "${RED}❌${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"; exit 1
fi

# ── DISCOVER TENANTS ───────────────────────────────────────────────────────
discover_tenants() {
  local tenants=()
  
  # Find tenants by looking for .env files
  while IFS= read -r env_file; do
    local tenant_dir="$(dirname "$env_file")"
    local tenant_name="$(basename "$tenant_dir")"
    [[ "$tenant_name" =~ ^u[0-9]+$ ]] && tenants+=("$tenant_name")
  done < <(find /mnt/data -maxdepth 2 -name ".env" 2>/dev/null)
  
  # Also check for running containers to find orphaned tenants
  while IFS= read -r container; do
    local name="${container#aip-}"
    [[ "$name" =~ ^u[0-9]+$ ]] && tenants+=("$name")
  done < <(docker ps --format "{{.Names}}" | grep "^aip-u" | sed 's/^aip-//' 2>/dev/null)
  
  # Remove duplicates
  printf '%s\n' "${tenants[@]}" | sort -u
}

# ── SELECT TENANT ───────────────────────────────────────────────────────
select_tenant() {
  local tenants=($(discover_tenants))
  
  if [[ ${#tenants[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No AI Platform tenants found.${NC}"
    echo "All containers, networks, and volumes appear to be clean."
    exit 0
  fi
  
  echo -e "${CYAN}${BOLD}Discovered Tenants:${NC}"
  echo ""
  for i in "${!tenants[@]}"; do
    local tenant="${tenants[$i]}"
    local container_count=$(docker ps --filter "name=aip-${tenant}" --format "{{.Names}}" | wc -l)
    echo "  $((i+1)). $tenant ($container_count containers running)"
  done
  echo ""
  
  if [[ ${#tenants[@]} -eq 1 ]]; then
    echo "Auto-selecting single tenant: ${tenants[0]}"
    SELECTED_TENANT="${tenants[0]}"
  else
    echo -e "${YELLOW}Select tenant to clean (1-${#tenants[@]}):${NC}"
    read -p "Enter number: " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#tenants[@]} ]]; then
      SELECTED_TENANT="${tenants[$((selection-1))]}"
    else
      echo "Invalid selection. Aborting."
      exit 1
    fi
  fi
  
  echo -e "${CYAN}Selected tenant: ${SELECTED_TENANT}${NC}"
}

# ── SYSTEMATIC CONTAINER CLEANUP ───────────────────────────────────────
cleanup_containers() {
  local tenant="$1"
  local project="aip-${tenant}"
  
  log "Phase 1: Systematic container cleanup for ${tenant}..."
  
  # Get all containers for this tenant (including those not matching naming convention)
  local containers=()
  while IFS= read -r container; do
    containers+=("$container")
  done < <(docker ps -a --format "{{.Names}}" | grep -E "(aip-${tenant}|${project})" || true)
  
  if [[ ${#containers[@]} -eq 0 ]]; then
    log "No containers found for tenant ${tenant}"
    return 0
  fi
  
  log "Found ${#containers[@]} containers to clean"
  
  # Force stop all containers
  for container in "${containers[@]}"; do
    log "  Stopping: $container"
    docker stop "$container" 2>/dev/null || true
  done
  
  # Force remove all containers
  for container in "${containers[@]}"; do
    log "  Removing: $container"
    docker rm -f "$container" 2>/dev/null || true
  done
  
  ok "All containers for ${tenant} removed"
}

# ── SYSTEMATIC NETWORK CLEANUP ───────────────────────────────────────
cleanup_networks() {
  local tenant="$1"
  local project="aip-${tenant}"
  
  log "Phase 2: Systematic network cleanup for ${tenant}..."
  
  # Get all networks related to this tenant
  local networks=()
  while IFS= read -r network; do
    networks+=("$network")
  done < <(docker network ls --format "{{.Name}}" | grep -E "(aip-${tenant}|${project})" || true)
  
  if [[ ${#networks[@]} -eq 0 ]]; then
    log "No networks found for tenant ${tenant}"
    return 0
  fi
  
  log "Found ${#networks[@]} networks to clean"
  
  # Force disconnect all containers from networks first
  for network in "${networks[@]}"; do
    log "  Disconnecting containers from: $network"
    while IFS= read -r container; do
      docker network disconnect -f "$network" "$container" 2>/dev/null || true
    done < <(docker network inspect "$network" --format '{{range .Containers}}{{.Name}}{{end}}' 2>/dev/null || true)
  done
  
  # Remove networks
  for network in "${networks[@]}"; do
    log "  Removing: $network"
    docker network rm -f "$network" 2>/dev/null || true
  done
  
  ok "All networks for ${tenant} removed"
}

# ── SYSTEMATIC VOLUME CLEANUP ───────────────────────────────────────────
cleanup_volumes() {
  local tenant="$1"
  local project="aip-${tenant}"
  
  log "Phase 3: Systematic volume cleanup for ${tenant}..."
  
  # Get all volumes related to this tenant
  local volumes=()
  while IFS= read -r volume; do
    volumes+=("$volume")
  done < <(docker volume ls --format "{{.Name}}" | grep -E "(aip-${tenant}|${project})" || true)
  
  if [[ ${#volumes[@]} -eq 0 ]]; then
    log "No volumes found for tenant ${tenant}"
    return 0
  fi
  
  log "Found ${#volumes[@]} volumes to clean"
  
  # Remove volumes
  for volume in "${volumes[@]}"; do
    log "  Removing: $volume"
    docker volume rm -f "$volume" 2>/dev/null || true
  done
  
  ok "All volumes for ${tenant} removed"
}

# ── SYSTEMATIC DATA CLEANUP ─────────────────────────────────────────────
cleanup_data() {
  local tenant="$1"
  local tenant_dir="/mnt/data/${tenant}"
  
  log "Phase 4: Systematic data cleanup for ${tenant}..."
  
  if [[ -d "$tenant_dir" ]]; then
    log "Removing tenant directory: $tenant_dir"
    rm -rf "$tenant_dir"
    ok "Tenant data directory removed"
  else
    log "No tenant data directory found: $tenant_dir"
  fi
}

# ── SYSTEMATIC STATE CLEANUP ───────────────────────────────────────────
cleanup_state() {
  log "Phase 5: Systematic state cleanup..."
  
  # Remove state files
  if [[ -d "/mnt/data/metadata" ]]; then
    log "Removing metadata directory"
    rm -rf "/mnt/data/metadata"
  fi
  
  # Remove env pointer
  if [[ -f "/etc/ai-platform/env-pointer" ]]; then
    log "Removing environment pointer"
    rm -f "/etc/ai-platform/env-pointer"
  fi
  
  ok "All state files removed"
}

# ── FINAL DOCKER CLEANUP ───────────────────────────────────────────────
final_cleanup() {
  log "Phase 6: Final Docker cleanup..."
  
  # Prune everything
  docker system prune -af --volumes >/dev/null 2>&1 || true
  docker network prune -f >/dev/null 2>&1 || true
  
  ok "Docker system cleanup complete"
}

# ── VERIFICATION ───────────────────────────────────────────────────────────
verify_cleanup() {
  local tenant="$1"
  local project="aip-${tenant}"
  
  log "Phase 7: Verification..."
  
  local remaining_containers=$(docker ps -a --format "{{.Names}}" | grep -E "(aip-${tenant}|${project})" | wc -l)
  local remaining_networks=$(docker network ls --format "{{.Name}}" | grep -E "(aip-${tenant}|${project})" | wc -l)
  local remaining_volumes=$(docker volume ls --format "{{.Name}}" | grep -E "(aip-${tenant}|${project})" | wc -l)
  
  if [[ $remaining_containers -eq 0 ]] && [[ $remaining_networks -eq 0 ]] && [[ $remaining_volumes -eq 0 ]]; then
    ok "✅ Verification passed - ${tenant} completely cleaned"
  else
    warn "⚠️ Some resources may remain:"
    [[ $remaining_containers -gt 0 ]] && warn "  - $remaining_containers containers"
    [[ $remaining_networks -gt 0 ]] && warn "  - $remaining_networks networks"
    [[ $remaining_volumes -gt 0 ]] && warn "  - $remaining_volumes volumes"
  fi
}

# ── MAIN EXECUTION ───────────────────────────────────────────────────────
main() {
  echo -e "${RED}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${RED}${BOLD}  🧹 SYSTEMATIC NUCLEAR CLEANUP 🧹${NC}"
  echo -e "${RED}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
  echo ""
  
  select_tenant
  echo ""
  echo -e "${YELLOW}Starting systematic cleanup of ${SELECTED_TENANT}...${NC}"
  echo ""
  
  cleanup_containers "$SELECTED_TENANT"
  cleanup_networks "$SELECTED_TENANT"
  cleanup_volumes "$SELECTED_TENANT"
  cleanup_data "$SELECTED_TENANT"
  cleanup_state
  final_cleanup
  verify_cleanup "$SELECTED_TENANT"
  
  echo ""
  echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}  ✅ SYSTEMATIC CLEANUP COMPLETE ✅${NC}"
  echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
  echo ""
  log "Tenant ${SELECTED_TENANT} has been completely removed"
  log "You can now run script 1 for a fresh deployment"
}

# Run main function
main "$@"
