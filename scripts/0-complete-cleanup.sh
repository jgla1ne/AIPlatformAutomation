#!/usr/bin/env bash
# =============================================================================
# Script 0: Complete Cleanup and Fresh Deployment
# =============================================================================
# PURPOSE: Clean slate deployment after architectural fixes
# USAGE:   sudo bash scripts/0-complete-cleanup.sh <tenant_id>
# =============================================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'

log() { echo -e "${CYAN}[INFO]${NC}    $*"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }

# --- Tenant ID Check ---
if [[ -z "${1:-}" ]]; then
    echo "ERROR: TENANT_ID is required. Usage: sudo bash $0 <tenant_id>" >&2
    exit 1
fi

TENANT_ID="$1"
DATA_ROOT="/mnt/data/datasquiz"

log "INFO" "Starting complete cleanup for tenant '${TENANT_ID}'..."

# --- 1. Stop All Containers ---
log "INFO" "Stopping all running containers..."
cd "${DATA_ROOT}"
if docker compose ps -q | grep -q .; then
    docker compose down --remove-orphans
    ok "All containers stopped and removed."
else
    ok "No containers were running."
fi

# --- 2. Clean Up Docker Resources ---
log "INFO" "Cleaning up Docker resources..."
docker system prune -f
ok "Docker resources cleaned up."

# --- 3. Reset Permissions with Script 3 Functions ---
log "INFO" "Resetting permissions with dynamic service-aware ownership..."

# Load environment variables
ENV_FILE="${DATA_ROOT}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    source "${ENV_FILE}"
fi

source "/home/jglaine/AIPlatformAutomation/scripts/3-configure-services.sh"

# Apply correct permissions for all services
ALL_SERVICES="postgres redis qdrant grafana prometheus litellm authentik signal n8n weaviate chromadb milvus ollama localai vllm openwebui anythingllm flowise"

for service in ${ALL_SERVICES}; do
    permissions_set_ownership "${service}"
done

ok "All service permissions reset with dynamic UIDs."

# --- 4. Fresh Deployment ---
log "INFO" "Ready for fresh deployment with architectural fixes..."
echo ""
echo "🎯 CLEANUP COMPLETE - READY FOR FRESH DEPLOYMENT"
echo ""
echo "✅ All containers stopped and cleaned"
echo "✅ Docker resources pruned"  
echo "✅ Permissions reset with dynamic UIDs"
echo "✅ Script 3 functions loaded and ready"
echo ""
echo "🚀 NEXT STEP: Run Script 2 for fresh deployment"
echo "   sudo bash scripts/2-deploy-services.sh ${TENANT_ID}"
echo ""
echo "📊 This will deploy with:"
echo "   • Complete Caddyfile generation"
echo "   • All enabled services" 
echo "   • Dynamic permissions (qdrant: 1000:1000)"
echo "   • Zero hardcoding principles"
echo "   • Modular architecture working"
