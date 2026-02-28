#!/bin/bash
set -euo pipefail

# ─── LOAD TENANT CONTEXT ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"

# Identify tenant
TENANT_UID=${SUDO_UID:-$(id -u)}
TENANT_NAME="u${TENANT_UID}"
ENV_FILE="/home/$(getent passwd ${TENANT_UID} | cut -d: -f6)/.aip/${TENANT_NAME}.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: No environment file found at ${ENV_FILE}"
  echo "Run 1-setup-system.sh first."
  exit 1
fi

source "${ENV_FILE}"

# ─── SERVICE SELECTION ───────────────────────────────────────────────────
SERVICE=${1:-}
if [[ -z "${SERVICE}" ]]; then
  echo "Available services:"
  ls "${TEMPLATE_DIR}/" | sed 's/.yml//'
  read -p "Enter service name to add: " SERVICE
fi

TEMPLATE="${TEMPLATE_DIR}/${SERVICE}.yml"
if [[ ! -f "${TEMPLATE}" ]]; then
  echo "ERROR: No template for service '${SERVICE}'"
  echo "Available: $(ls ${TEMPLATE_DIR}/ | sed 's/.yml//' | tr '\n' ' ')"
  exit 1
fi

# ─── PORT ASSIGNMENT ─────────────────────────────────────────────────────
# Script 4 reuses Script 1's port-finding logic via sourcing
SERVICE_PORT_VAR="${SERVICE^^}_PORT"
if [[ -z "${!SERVICE_PORT_VAR:-}" ]]; then
  # Simple port finding for Script 4
  find_free_port() {
    local start_port=$1
    local end_port=$2
    for port in $(seq $start_port $end_port); do
      if ! netstat -tuln 2>/dev/null | grep -q ":$port "; then
        echo $port
        return 0
      fi
    done
    return 1
  }
  
  NEW_PORT=$(find_free_port 3100 3200)
  echo "${SERVICE_PORT_VAR}=${NEW_PORT}" >> "${ENV_FILE}"
  export "${SERVICE_PORT_VAR}=${NEW_PORT}"
fi

# ─── APPEND AND DEPLOY ───────────────────────────────────────────────────
COMPOSE_FILE="${DATA_ROOT}/docker-compose.yml"
COMPOSE="docker compose --project-name ${COMPOSE_PROJECT_NAME} \
  --env-file ${ENV_FILE} \
  --file ${COMPOSE_FILE}"

# Render template with current env vars
envsubst < "${TEMPLATE}" >> "${COMPOSE_FILE}"

# Validate compose file after modification
docker compose \
  --env-file "${ENV_FILE}" \
  --file "${COMPOSE_FILE}" \
  config --quiet || {
    echo "ERROR: Compose file invalid after adding ${SERVICE}"
    echo "Last 10 lines of ${COMPOSE_FILE}:"
    tail -10 "${COMPOSE_FILE}"
    exit 1
  }

# Deploy only the new service
$COMPOSE up -d "${SERVICE}"

echo "✅ Service '${SERVICE}' added to tenant ${TENANT_NAME}"
