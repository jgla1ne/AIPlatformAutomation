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
  
  # Check for existing variable to avoid duplicates
  if grep -q "^${SERVICE_PORT_VAR}=" "${ENV_FILE}" 2>/dev/null; then
    echo "Variable ${SERVICE_PORT_VAR} already exists in .env - skipping"
    return 0
  fi
  
  echo "${SERVICE_PORT_VAR}=${NEW_PORT}" >> "${ENV_FILE}"
  export "${SERVICE_PORT_VAR}=${NEW_PORT}"
fi

# ─── APPEND AND DEPLOY ───────────────────────────────────────────────────
COMPOSE_FILE="${DATA_ROOT}/docker-compose.yml"

# Validate generated compose file before restarting services
if ! docker compose -f "${COMPOSE_FILE}" config >/dev/null 2>&1; then
  echo "Generated docker-compose.yml is invalid YAML. Rolling back."
  # Remove the broken file to avoid using it
  rm -f "${COMPOSE_FILE}"
  exit 1
fi

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

# ─── DATABASE CREATION (if needed) ───────────────────────────────────────
# Check if this service needs a database by looking for POSTGRES_DB in env
DB_NAME=$(grep "^${SERVICE^^}_POSTGRES_DB=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 || true)
if [[ -n "${DB_NAME}" ]]; then
  echo "Creating database ${DB_NAME} for service ${SERVICE}..."
  
  # Wait for postgres to be ready
  PG_CONTAINER="${COMPOSE_PROJECT_NAME}-postgres"
  until docker exec "${PG_CONTAINER}" pg_isready -U postgres -q 2>/dev/null; do
    echo "Waiting for PostgreSQL..."
    sleep 3
  done
  
  # Create database using postgres superuser
  if ! docker exec "${PG_CONTAINER}" \
    psql -U postgres \
    -c "CREATE DATABASE \"${DB_NAME}\" OWNER \"${POSTGRES_USER}\";" \
    2>/dev/null; then
    echo "Database ${DB_NAME} may already exist or failed to create"
  else
    echo "✅ Database ${DB_NAME} created successfully"
  fi
fi

echo "✅ Service '${SERVICE}' added to tenant ${TENANT_NAME}"
