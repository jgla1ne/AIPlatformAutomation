# Refactoring Plan for Windsurf

## Current State Assessment

After reading all three scripts, the issues fall into **4 distinct problem areas**. I'll give Windsurf precise, scoped instructions for each — no restructuring, targeted fixes only.

---

## Problem Area 1 — Tenant Identity (Script 1)

**Root cause:** Script 1 uses `id -u` which returns `0` when run via `sudo`. All files get owned by root. Second tenant run collides with first.

**Exact fix — replace the identity block at the top of Script 1:**

```bash
# REMOVE this pattern wherever it appears:
RUNNING_UID=$(id -u)
RUNNING_GID=$(id -g)

# REPLACE with:
if [[ -z "${SUDO_UID}" ]]; then
  echo "ERROR: Run this script with sudo: sudo ./1-setup-system.sh"
  echo "Running without sudo creates files owned by root."
  exit 1
fi

TENANT_UID="${SUDO_UID}"
TENANT_GID="${SUDO_GID}"
TENANT_USER=$(getent passwd "${TENANT_UID}" | cut -d: -f1)

if [[ -z "${TENANT_USER}" ]]; then
  echo "ERROR: Cannot resolve username for UID ${TENANT_UID}"
  echo "Ensure the user account exists before running this script."
  exit 1
fi

TENANT_NAME="u${TENANT_UID}"
```

**Then replace ALL subsequent references:**
```bash
# Find and replace in Script 1:
# RUNNING_UID  → TENANT_UID
# RUNNING_GID  → TENANT_GID  
# RUNNING_USER → TENANT_USER

# Every chown call must use TENANT_UID:TENANT_GID
chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}"
chown "${TENANT_UID}:${TENANT_GID}" "${ENV_FILE}"
```

---

## Problem Area 2 — EBS Volume Selection (Script 1)

**Root cause:** Script 1 hardcodes or assumes a DATA_ROOT without asking the operator how storage should be allocated.

**Insert this block in Script 1 AFTER tenant identity is established, BEFORE directory creation:**

```bash
# ─── EBS VOLUME SELECTION ───────────────────────────────────────────────
select_storage() {
  echo ""
  echo "═══════════════════════════════════════════"
  echo "  STORAGE CONFIGURATION for ${TENANT_USER}"
  echo "═══════════════════════════════════════════"
  echo ""
  echo "Option A: Use existing mounted volume (shared EBS, folder per tenant)"
  echo "Option B: Dedicate a new EBS volume to this tenant"
  echo ""
  read -p "Dedicate a new EBS volume to this tenant? [y/N]: " DEDICATE_EBS
  DEDICATE_EBS=${DEDICATE_EBS:-N}

  if [[ "${DEDICATE_EBS}" =~ ^[Yy]$ ]]; then
    # Mode B — dedicated EBS
    echo ""
    echo "Available unattached block devices:"
    lsblk -o NAME,SIZE,MOUNTPOINT,FSTYPE | \
      awk 'NR==1 || ($3=="" && $4=="")'
    echo ""
    read -p "Enter device name to use (e.g. nvme1n1, xvdb): " SELECTED_DEVICE
    DEVICE_PATH="/dev/${SELECTED_DEVICE}"

    if [[ ! -b "${DEVICE_PATH}" ]]; then
      echo "ERROR: ${DEVICE_PATH} is not a valid block device"
      exit 1
    fi

    MOUNT_POINT="/mnt/${TENANT_NAME}"
    echo "Formatting ${DEVICE_PATH} as ext4..."
    mkfs.ext4 -F "${DEVICE_PATH}"
    mkdir -p "${MOUNT_POINT}"
    mount "${DEVICE_PATH}" "${MOUNT_POINT}"

    # Persist in fstab
    DEVICE_UUID=$(blkid -s UUID -o value "${DEVICE_PATH}")
    FSTAB_ENTRY="UUID=${DEVICE_UUID} ${MOUNT_POINT} ext4 defaults,nofail 0 2"
    if ! grep -q "${DEVICE_UUID}" /etc/fstab; then
      echo "${FSTAB_ENTRY}" >> /etc/fstab
      echo "Added to /etc/fstab: ${FSTAB_ENTRY}"
    fi

    DATA_ROOT="${MOUNT_POINT}"

  else
    # Mode A — shared EBS, folder per tenant
    echo ""
    echo "Currently mounted volumes:"
    lsblk -o NAME,SIZE,MOUNTPOINT | grep -v "loop\|sr0" | grep -v "^$"
    echo ""
    read -p "Base mount point to use [/mnt/data]: " MOUNT_BASE
    MOUNT_BASE=${MOUNT_BASE:-/mnt/data}

    if [[ ! -d "${MOUNT_BASE}" ]]; then
      echo "ERROR: ${MOUNT_BASE} does not exist or is not mounted"
      exit 1
    fi

    DATA_ROOT="${MOUNT_BASE}/${TENANT_NAME}"
  fi

  echo "DATA_ROOT set to: ${DATA_ROOT}"
}

select_storage
# ─── END EBS VOLUME SELECTION ───────────────────────────────────────────
```

---

## Problem Area 3 — Service Deployment Failures (Script 2)

**Root cause:** Multiple independent failures. Fix each one in place.

### Fix 3a — PostgreSQL pgvector extension

Add this function to Script 2 and call it after postgres health check passes:

```bash
setup_postgres_extensions() {
  log "Setting up PostgreSQL extensions..."
  
  local max_attempts=10
  local attempt=0
  
  while [[ $attempt -lt $max_attempts ]]; do
    if $COMPOSE exec -T postgres psql \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null; then
      log "✅ pgvector extension created"
      return 0
    fi
    attempt=$((attempt + 1))
    log "Waiting for postgres to accept connections... (${attempt}/${max_attempts})"
    sleep 3
  done
  
  log "❌ ERROR: Could not create pgvector extension after ${max_attempts} attempts"
  return 1
}
```

### Fix 3b — MinIO bucket creation

```bash
setup_minio_buckets() {
  log "Creating MinIO buckets..."

  # Wait for MinIO to be ready
  local max_attempts=15
  local attempt=0
  while [[ $attempt -lt $max_attempts ]]; do
    if $COMPOSE exec -T minio mc ready local 2>/dev/null; then
      break
    fi
    attempt=$((attempt + 1))
    sleep 3
  done

  # Configure mc alias inside container
  $COMPOSE exec -T minio mc alias set local \
    "http://localhost:9000" \
    "${MINIO_ROOT_USER}" \
    "${MINIO_ROOT_PASSWORD}" 2>/dev/null

  # Create required buckets
  for bucket in uploads documents models backups; do
    $COMPOSE exec -T minio mc mb --ignore-existing "local/${bucket}" && \
      log "✅ Bucket created: ${bucket}" || \
      log "⚠️  Bucket already exists: ${bucket}"
  done
}
```

### Fix 3c — Health gate using correct method

Replace any TCP-based health checks in Script 2 with this pattern:

```bash
wait_for_service() {
  local service_name=$1
  local check_command=$2   # the actual command to run
  local max_wait=${3:-120}
  local interval=5
  local elapsed=0

  log "Waiting for ${service_name}..."
  while [[ $elapsed -lt $max_wait ]]; do
    if eval "${check_command}" &>/dev/null; then
      log "✅ ${service_name} is ready"
      return 0
    fi
    sleep $interval
    elapsed=$((elapsed + interval))
  done
  log "❌ ${service_name} did not become ready within ${max_wait}s"
  return 1
}

# Usage:
wait_for_service "postgres" \
  "$COMPOSE exec -T postgres pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"

wait_for_service "qdrant" \
  "curl -sf http://localhost:${QDRANT_PORT}/health"

wait_for_service "minio" \
  "curl -sf http://localhost:${MINIO_PORT}/minio/health/live"

wait_for_service "n8n" \
  "curl -sf http://localhost:${N8N_PORT}/healthz"
```

### Fix 3d — Qdrant data directory ownership

Add to Script 1 directory creation block:

```bash
# Qdrant requires UID 1000 internally — but our bind mount must be world-writable
# OR we accept UID mismatch and use a named volume approach for qdrant only
mkdir -p "${DATA_ROOT}/data/qdrant"
# qdrant container runs as UID 1000, set accordingly
chown -R 1000:1000 "${DATA_ROOT}/data/qdrant"
chmod 755 "${DATA_ROOT}/data/qdrant"
```

### Fix 3e — n8n WEBHOOK_URL

Ensure this is in the `.env` generation block of Script 1:

```bash
# In Script 1 .env generation:
N8N_WEBHOOK_URL="https://${TENANT_NAME}.${BASE_DOMAIN}/n8n/webhook"
# Write to .env:
echo "N8N_WEBHOOK_URL=${N8N_WEBHOOK_URL}" >> "${ENV_FILE}"
echo "WEBHOOK_URL=${N8N_WEBHOOK_URL}" >> "${ENV_FILE}"
```

And in docker-compose.yml n8n service:
```yaml
n8n:
  environment:
    - WEBHOOK_URL=${WEBHOOK_URL}
    - N8N_EDITOR_BASE_URL=https://${TENANT_NAME}.${BASE_DOMAIN}/n8n/
```

---

## Problem Area 4 — Script 4 Template System

**Root cause:** Script 4 exists but has no template directory or append logic.

**Step 1 — Create `scripts/templates/` directory with one example:**

`scripts/templates/flowise.yml`:
```yaml
  flowise:
    image: flowiseai/flowise:latest
    container_name: ${COMPOSE_PROJECT_NAME}-flowise
    restart: unless-stopped
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "${FLOWISE_PORT}:3000"
    environment:
      - PORT=3000
      - DATABASE_PATH=/root/.flowise
      - APIKEY_PATH=/root/.flowise
      - SECRETKEY_PATH=/root/.flowise
    volumes:
      - ${DATA_ROOT}/data/flowise:/root/.flowise
    labels:
      - "ai-platform.tenant=${TENANT_NAME}"
      - "ai-platform.service=flowise"
```

**Step 2 — Rewrite Script 4 body:**

```bash
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
  NEW_PORT=$(find_free_port 3100 3200)    # source this function from Script 1
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

# Deploy only the new service
$COMPOSE up -d "${SERVICE}"

echo "✅ Service '${SERVICE}' added to tenant ${TENANT_NAME}"
```

---

## Execution Order for Windsurf

Give Windsurf these changes **one problem area at a time**, not all at once:

```
1. Apply Problem Area 1 (SUDO_UID) to Script 1 only. Test: run sudo ./1-setup-system.sh, 
   confirm DATA_ROOT owned by the real user, not root.

2. Apply Problem Area 2 (EBS selection) to Script 1 only. Test: both Mode A and Mode B 
   produce correct DATA_ROOT.

3. Apply Problem Area 3 fixes 3a-3e to Script 2 only. Test: all services reach healthy 
   state with wait_for_service gates passing.

4. Apply Problem Area 4 to Script 4 + create templates/ dir. Test: ./4-add-service.sh 
   flowise adds service without touching other tenant's compose file.
```

**Do not combine areas in a single Windsurf prompt.** Windsurf loses context and reverts working code when given too much at once.