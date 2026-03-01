#!/usr/bin/env bash
# 0-complete-cleanup.sh
# Full wipe for a tenant — containers, networks, volumes, EBS data
# Usage: sudo bash scripts/0-complete-cleanup.sh [--keep-data]
set -euo pipefail

TENANT_UID=$(id -u)
TENANT_ID="u${TENANT_UID}"
DATA_ROOT="/mnt/data/${TENANT_ID}"
COMPOSE_PROJECT_NAME="aip-${TENANT_ID}"
DOCKER_NETWORK="${COMPOSE_PROJECT_NAME}_net"
KEEP_DATA=false

[[ "${1:-}" == "--keep-data" ]] && KEEP_DATA=true

echo "WARNING: This will destroy all containers, networks, volumes for ${TENANT_ID}"
[ "${KEEP_DATA}" = "false" ] && \
    echo "AND wipe all data under ${DATA_ROOT}"
read -r -p "Type tenant ID to confirm [${TENANT_ID}]: " confirm
[ "${confirm}" != "${TENANT_ID}" ] && { echo "Aborted"; exit 0; }

# Stop + remove all tenant containers
docker ps -aq --filter "name=${COMPOSE_PROJECT_NAME}" | \
    xargs -r docker rm -f 2>/dev/null || true

# Remove all tenant networks
docker network ls --filter "name=${COMPOSE_PROJECT_NAME}" -q | \
    xargs -r docker network rm 2>/dev/null || true

# Remove named volumes
docker volume ls --filter "name=${COMPOSE_PROJECT_NAME}" -q | \
    xargs -r docker volume rm 2>/dev/null || true

# Prune dangling networks (safe)
docker network prune -f 2>/dev/null || true

# Wipe EBS data (only if not --keep-data)
if [ "${KEEP_DATA}" = "false" ]; then
    echo "Wiping ${DATA_ROOT}..."
    rm -rf "${DATA_ROOT}"
    echo "Done — ${DATA_ROOT} removed"
else
    echo "Data preserved at ${DATA_ROOT}"
    echo "Compose file removed (will be regenerated)"
    rm -f "${DATA_ROOT}/docker-compose.yml"
fi

echo "Cleanup complete for ${TENANT_ID}"
