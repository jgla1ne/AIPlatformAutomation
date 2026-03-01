#!/usr/bin/env bash
# =============================================================================
# 2-deploy-services.sh — Deploy AI Platform Services
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }
section() { echo -e "\n${CYAN}════════════════════════════════════════${NC}"; \
            echo -e "${CYAN}  $*${NC}"; \
            echo -e "${CYAN}══════════════════════════════════════${NC}"; }

# ── Locate .env ───────────────────────────────────────────────────────────────
# Priority 1: TENANT_DIR environment variable
# Priority 2: Search under /mnt/data
# Priority 3: Search under /opt/ai-platform
if [[ -n "${TENANT_DIR:-}" && -f "${TENANT_DIR}/.env" ]]; then
  ENV_FILE="${TENANT_DIR}/.env"
elif [[ -f "/mnt/data/u1001/.env" ]]; then
  ENV_FILE="/mnt/data/u1001/.env"
else
  ENV_FILE="$(find /mnt/data /opt/ai-platform -maxdepth 5 \
    -name '.env' -not -path '*/\.*' 2>/dev/null | head -1)"
fi

[[ -z "${ENV_FILE:-}" || ! -f "${ENV_FILE}" ]] && \
  fail "Cannot find .env file. Run script 1 first."

ok "Using .env: ${ENV_FILE}"

# ── Load environment — must happen before DC() is defined ─────────────────────
set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

# ── Critical Validations ───────────────────────────────────────────────────────
if [ "${DOMAIN}" = "localhost" ] || [ -z "${DOMAIN}" ]; then
    fail "DOMAIN is '${DOMAIN}'. Set DOMAIN_NAME in .env and re-run script 1 first."
fi

log "Domain: ${DOMAIN}"

check_tailscale_auth() {
    if [ -z "${TAILSCALE_AUTH_KEY}" ]; then
        warn "TAILSCALE_AUTH_KEY not set in .env"
        warn "Tailscale will start but NOT authenticate"
        warn "Get a key: https://login.tailscale.com/admin/settings/keys"
        warn "Add to .env: TAILSCALE_AUTH_KEY=tskey-auth-xxxxx"
        warn "Then re-run: sudo bash scripts/2-deploy-services.sh"
    else
        log "Tailscale auth key found — will auto-authenticate"
    fi
}
check_tailscale_auth

# ── STRUCTURED LOGGING SETUP ───────────────────────────────────────────────────────
LOG_DIR="${DATA_ROOT}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/script-2-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

# Validate required variables
required_vars=(
  POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB
  TENANT_ID COMPOSE_PROJECT_NAME DATA_ROOT
)
for var in "${required_vars[@]}"; do
  [[ -z "${!var:-}" ]] && fail "Required variable not set: ${var}. Check .env file."
done

ok "Environment loaded. Project: ${COMPOSE_PROJECT_NAME}, Data: ${DATA_ROOT}"

# ── Compose file location ─────────────────────────────────────────────────────
TENANT_DIR="$(dirname "${ENV_FILE}")"
COMPOSE_FILE="${SCRIPT_DIR}/../docker-compose.yml"
[[ ! -f "${COMPOSE_FILE}" ]] && fail "docker-compose.yml not found at: ${COMPOSE_FILE}"

# ── DC() defined after ENV_FILE and COMPOSE_FILE are resolved ─────────────────
DC() { docker compose --project-name "${COMPOSE_PROJECT_NAME}" \
         -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" "$@"; }

PG_CONTAINER="${COMPOSE_PROJECT_NAME}-postgres"

# ── SELF-PURGE: clean any previous partial deployment ──────────────────
log "INFO" "Purging any previous deployment before fresh start..."

# Stop and remove all containers on this project network
docker ps -aq --filter "network=${COMPOSE_PROJECT_NAME}_net" | xargs -r docker rm -f 2>/dev/null || true
docker ps -aq --filter "name=${COMPOSE_PROJECT_NAME}-" | xargs -r docker rm -f 2>/dev/null || true

# Remove project network if it exists
docker network rm "${COMPOSE_PROJECT_NAME}_net" 2>/dev/null || true

# Remove orphaned volumes only for this project (named volumes with prefix)
docker volume ls -q --filter "name=${COMPOSE_PROJECT_NAME}_" | xargs -r docker volume rm 2>/dev/null || true

# Remove old Caddyfile so it is always regenerated fresh
rm -f "${DATA_ROOT}/caddy/config/Caddyfile" 2>/dev/null || true

log "INFO" "Self-purge complete. Starting fresh deployment."
# ── END SELF-PURGE ──────────────────────────────────────────────────────

# =============================================================================
section "Phase 1: Pre-flight Checks"
# =============================================================================

# Check Docker is running
docker info >/dev/null 2>&1 || fail "Docker is not running."
ok "Docker is running"

# Check compose file is valid YAML
docker compose -f "${COMPOSE_FILE}" config >/dev/null 2>&1 || \
  fail "docker-compose.yml is invalid. Fix YAML errors before deploying."
ok "docker-compose.yml is valid"

# Check DATA_ROOT exists and is writable
[[ -d "${DATA_ROOT}" ]] || fail "DATA_ROOT does not exist: ${DATA_ROOT}. Run script 1 first."
[[ -w "${DATA_ROOT}" ]] || fail "DATA_ROOT is not writable: ${DATA_ROOT}. Check permissions."
ok "DATA_ROOT accessible: ${DATA_ROOT}"

# Check disk space (require at least 20GB free)
FREE_GB=$(df -BG "${DATA_ROOT}" | awk 'NR==2{gsub("G","",$4); print $4}')
[[ "${FREE_GB}" -lt 20 ]] && \
  warn "Less than 20GB free on DATA_ROOT (${FREE_GB}GB). Deployment may fail."
ok "Disk space: ${FREE_GB}GB free"

# =============================================================================
section "Phase 2: Pull Images"
# =============================================================================

# === Prometheus Configuration ===
log "Creating Prometheus configuration..."
PROMETHEUS_CONFIG="${DATA_ROOT}/prometheus/prometheus.yml"
mkdir -p "$(dirname "${PROMETHEUS_CONFIG}")"
cat > "${PROMETHEUS_CONFIG}" << PROMETHEUS_EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
PROMETHEUS_EOF

chmod 644 "${PROMETHEUS_CONFIG}"
chown 65534:65534 "${PROMETHEUS_CONFIG}" 2>/dev/null || true
log "INFO" "Prometheus config written to ${PROMETHEUS_CONFIG}"

log "Pulling all service images (this may take several minutes on first run)..."
DC pull --quiet 2>&1 | grep -v "^$" || warn "Some images could not be pulled — will use cached versions"
ok "Image pull complete"

# =============================================================================
section "Phase 3: Deploy Infrastructure Services"
# =============================================================================

log "Starting infrastructure services: postgres, redis, minio, qdrant..."
DC up -d postgres redis minio qdrant

# ── Wait for PostgreSQL — two-stage: port open, then query acceptance ──────────
wait_for_postgres() {
  log "Waiting for PostgreSQL port to open..."
  local attempts=0
  local max_port=60

  until docker exec "${PG_CONTAINER}" \
      pg_isready -U "${POSTGRES_USER}" -q 2>/dev/null; do
    attempts=$((attempts + 1))
    [[ $attempts -ge $max_port ]] && \
      fail "PostgreSQL port never opened after $((max_port * 3))s. Check container: docker logs ${PG_CONTAINER}"
    sleep 3
  done
  ok "PostgreSQL port open"

  # Stage 2: wait for actual query acceptance
  # pg_isready passes before pg_hba.conf is loaded and before init scripts run
  log "Waiting for PostgreSQL to accept queries..."
  attempts=0
  local max_query=40
  until docker exec "${PG_CONTAINER}" \
      psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "SELECT 1;" -q --no-align --tuples-only 2>/dev/null \
      | grep -q "1"; do
    attempts=$((attempts + 1))
    [[ $attempts -ge $max_query ]] && \
      fail "PostgreSQL not accepting queries after $((max_query * 3))s. Check: docker logs ${PG_CONTAINER}"
    sleep 3
  done
  ok "PostgreSQL is fully ready and accepting queries"
}

wait_for_postgres

# ── Wait for Redis ─────────────────────────────────────────────────────────────
log "Waiting for Redis..."
attempts=0
until docker exec "${COMPOSE_PROJECT_NAME}-redis" \
    redis-cli -a "${REDIS_PASSWORD}" ping 2>/dev/null | grep -q "PONG"; do
  attempts=$((attempts + 1))
  [[ $attempts -ge 20 ]] && fail "Redis not ready after 60s. Check: docker logs ${COMPOSE_PROJECT_NAME}-redis"
  sleep 3
done
ok "Redis is ready"

# ── Wait for MinIO ─────────────────────────────────────────────────────────────
log "Waiting for MinIO..."
attempts=0
until curl -sf "http://localhost:9000/minio/health/live" >/dev/null 2>&1; do
  attempts=$((attempts + 1))
  [[ $attempts -ge 20 ]] && fail "MinIO not ready after 60s. Check: docker logs ${COMPOSE_PROJECT_NAME}-minio"
  sleep 3
done
ok "MinIO is ready"

# ── RCLONE CONFIG ───────────────────────────────────────────────────────
if [ -n "${B2_ACCOUNT_ID}" ] && [ -n "${B2_APPLICATION_KEY}" ]; then
    log "INFO" "Writing rclone Backblaze config..."
    mkdir -p "${DATA_ROOT}/rclone"
    cat > "${DATA_ROOT}/rclone/rclone.conf" << RCLONECONF
[${RCLONE_REMOTE_NAME}]
type = b2
account = ${B2_ACCOUNT_ID}
key = ${B2_APPLICATION_KEY}
RCLONECONF
    log "SUCCESS" "rclone config written"
else
    log "WARN" "B2_ACCOUNT_ID or B2_APPLICATION_KEY not set — rclone backup not configured"
fi
# ── END RCLONE ────────────────────────────────────────────────────────────

# =============================================================================
section "Phase 4: Create Databases"
# =============================================================================
# IMPORTANT: All psql commands run as 'postgres' superuser.
# aip_user does not have CREATEDB privilege — using it here causes silent failures.
# Databases are created with OWNER set to POSTGRES_USER so the app user has full access.

create_database() {
  local db="$1"

  # Check if already exists
  if docker exec "${PG_CONTAINER}" \
      psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -lqt 2>/dev/null \
      | cut -d'|' -f1 | tr -d ' ' | grep -qx "${db}"; then
    ok "  Database already exists: ${db}"
    return 0
  fi

  log "  Creating database: ${db}"

  # Create as POSTGRES_USER (which is the superuser in this setup)
  local create_output
  create_output=$(docker exec "${PG_CONTAINER}" \
    psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    -c "CREATE DATABASE \"${db}\";" \
    2>&1)

  if echo "${create_output}" | grep -qi "error\|fatal\|permission denied"; then
    warn "  First attempt failed for ${db}: ${create_output}"
    sleep 5
    # Retry
    create_output=$(docker exec "${PG_CONTAINER}" \
      psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
      -c "CREATE DATABASE \"${db}\";" \
      2>&1)
    if echo "${create_output}" | grep -qi "error\|fatal\|permission denied"; then
      fail "  Cannot create database ${db}: ${create_output}"
    fi
  fi

  # Verify creation
  if docker exec "${PG_CONTAINER}" \
      psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -lqt 2>/dev/null \
      | cut -d'|' -f1 | tr -d ' ' | grep -qx "${db}"; then
    ok "  Created and verified: ${db}"
  else
    fail "  Database creation reported success but ${db} is not in pg_list — aborting"
  fi
}

grant_privileges() {
  local db="$1"
  docker exec "${PG_CONTAINER}" \
    psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    -c "GRANT ALL PRIVILEGES ON DATABASE \"${db}\" TO \"${POSTGRES_USER}\";" \
    2>/dev/null && ok "  Privileges granted on: ${db}" \
    || warn "  Could not grant privileges on ${db}"
}

enable_pgvector() {
  local db="$1"
  docker exec "${PG_CONTAINER}" \
    psql -U "${POSTGRES_USER}" -d "${db}" \
    -c "CREATE EXTENSION IF NOT EXISTS vector;" \
    2>/dev/null && ok "  pgvector enabled in: ${db}" \
    || warn "  pgvector not available in ${db} (non-fatal if not using vector search)"
}

# Create all required databases
DATABASES=("n8n" "flowise" "dify" "anythingllm")
for db in "${DATABASES[@]}"; do
  create_database "${db}"
  grant_privileges "${db}"
done

# Enable pgvector in services that use vector search
enable_pgvector "dify"
enable_pgvector "anythingllm"

# Final verification — list all created databases
log "Database verification:"
docker exec "${PG_CONTAINER}" \
  psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -lqt 2>/dev/null \
  | cut -d'|' -f1 | tr -d ' ' | grep -v "^$" \
  | while read -r dbname; do
    ok "  ✓ ${dbname}"
  done

# =============================================================================
section "Phase 5: Deploy Application Services"
# =============================================================================

# Fix Grafana directory ownership before starting services
if [[ -d "${DATA_ROOT}/grafana" ]]; then
  chown -R 472:472 "${DATA_ROOT}/grafana" 2>/dev/null || \
    warn "Could not chown grafana directory — Grafana may fail to start"
fi

# Guard rclone startup if credentials not configured
if [[ -z "${RCLONE_ACCESS_KEY:-}" || -z "${RCLONE_SECRET_KEY:-}" ]]; then
  warn "rclone credentials not configured — rclone backup disabled"
  # Remove rclone service from compose startup by setting scale to 0
  DC up -d --scale rclone=0
else
  log "Starting application services..."
  DC up -d
fi

# =============================================================================
section "Phase 6: Wait for Services"
# =============================================================================

# Wait for n8n
log "Waiting for n8n to be ready..."
attempts=0
until curl -sf "http://localhost:${N8N_PORT:-5678}/healthz" >/dev/null 2>&1 || \
      curl -sf "http://localhost:${N8N_PORT:-5678}/" >/dev/null 2>&1; do
  attempts=$((attempts + 1))
  [[ $attempts -ge 40 ]] && { warn "n8n not responding after 120s — may still be initializing"; break; }
  sleep 3
done
[[ $attempts -lt 40 ]] && ok "n8n is ready"

# Wait for Flowise
log "Waiting for Flowise to be ready..."
attempts=0
until curl -sf "http://localhost:${FLOWISE_PORT:-3000}/" >/dev/null 2>&1; do
  attempts=$((attempts + 1))
  [[ $attempts -ge 40 ]] && { warn "Flowise not responding after 120s — may still be initializing"; break; }
  sleep 3
done
[[ $attempts -lt 40 ]] && ok "Flowise is ready"

log "Waiting 15s for Flowise database migrations to complete..."
sleep 15

# Wait for Dify
log "Waiting for Dify API to be ready..."
attempts=0
until curl -sf "http://localhost:${DIFY_PORT:-80}/health" >/dev/null 2>&1 || \
      curl -sf "http://localhost:${DIFY_PORT:-80}/v1/ping" >/dev/null 2>&1; do
  attempts=$((attempts + 1))
  [[ $attempts -ge 40 ]] && { warn "Dify API not responding after 120s — may still be initializing"; break; }
  sleep 3
done
[[ $attempts -lt 40 ]] && ok "Dify API is ready"

# ── TAILSCALE ACTIVATION ───────────────────────────────────────────────────────
log "INFO" "Activating Tailscale..."

# Wait for tailscale daemon to be ready inside container
TAILSCALE_READY=false
for i in $(seq 1 30); do
    if docker exec "${COMPOSE_PROJECT_NAME}-tailscale" tailscale status &>/dev/null; then
        TAILSCALE_READY=true
        break
    fi
    sleep 2
done

if [ "$TAILSCALE_READY" = "true" ]; then
    docker exec "${COMPOSE_PROJECT_NAME}-tailscale" tailscale up \
        --authkey="${TAILSCALE_AUTH_KEY}" \
        --hostname="${COMPOSE_PROJECT_NAME}" \
        --accept-routes \
        2>&1 | tee -a "${LOG_FILE}"
    
    TAILSCALE_IP=$(docker exec "${COMPOSE_PROJECT_NAME}-tailscale" tailscale ip -4 2>/dev/null || echo "pending")
    log "SUCCESS" "Tailscale activated. IP: ${TAILSCALE_IP}"
    
    # Update .env with actual Tailscale IP
    if [ "${TAILSCALE_IP}" != "pending" ] && [ -n "${ENV_FILE}" ]; then
        sed -i "s/^TAILSCALE_IP=.*/TAILSCALE_IP=${TAILSCALE_IP}/" "${ENV_FILE}" 2>/dev/null || echo "TAILSCALE_IP=${TAILSCALE_IP}" >> "${ENV_FILE}"
        log "SUCCESS" "Tailscale IP: ${TAILSCALE_IP} — saved to .env"
    fi
else
    log "WARN" "Tailscale daemon not ready after 60s — skipping activation (non-fatal)"
fi
# ── END TAILSCALE ──────────────────────────────────────────────────────────────

# =============================================================================
section "Phase 7: Final Validation"
# =============================================================================

log "Container status:"
DC ps

echo ""
log "Checking for unhealthy or exited containers..."
UNHEALTHY=$(DC ps --format json 2>/dev/null | \
  python3 -c "
import sys, json
containers = []
for line in sys.stdin:
    line = line.strip()
    if line:
        try:
            c = json.loads(line)
            if isinstance(c, list):
                containers.extend(c)
            else:
                containers.append(c)
        except:
            pass
problems = []
for c in containers:
    state = c.get('State','')
    health = c.get('Health','')
    name = c.get('Name', c.get('Service','unknown'))
    if state == 'exited' or health == 'unhealthy':
        problems.append(f'{name}: state={state} health={health}')
for p in problems:
    print(p)
" 2>/dev/null || true)

if [[ -n "${UNHEALTHY}" ]]; then
  warn "The following containers need attention:"
  echo "${UNHEALTHY}" | while read -r line; do warn "  ${line}"; done
  echo ""
  warn "These services may still be initializing. Wait 2 minutes and check again with:"
  warn "  docker compose -p ${COMPOSE_PROJECT_NAME} ps"
else
  ok "All containers are healthy"
fi

# ── FINAL STATUS REPORT ──────────────────────────────────────────────────
log "INFO" "======================================================"
log "INFO" "FINAL DEPLOYMENT STATUS REPORT"
log "INFO" "======================================================"

# Container health
log "INFO" "--- Container Status ---"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" \
    --filter "network=${COMPOSE_PROJECT_NAME}_net" | tee -a "${LOG_FILE}"

# Internal connectivity (from Caddy container to each service)
log "INFO" "--- Internal Connectivity (Caddy → Services) ---"
declare -A SERVICE_INTERNAL=(
    ["litellm"]="litellm:4000"
    ["openwebui"]="openwebui:8080"
    ["anythingllm"]="anythingllm:3000"
    ["dify"]="dify-web:3000"
    ["n8n"]="n8n:5678"
    ["flowise"]="flowise:3000"
    ["signal-api"]="signal-api:8085"
    ["openclaw"]="openclaw:8082"
    ["prometheus"]="prometheus:9090"
    ["grafana"]="grafana:3000"
    ["minio"]="minio:9001"
)

for svc in "${!SERVICE_INTERNAL[@]}"; do
    target="${SERVICE_INTERNAL[$svc]}"
    if docker exec "${COMPOSE_PROJECT_NAME}-caddy" wget -q --spider --timeout=5 \
        "http://${target}" 2>/dev/null; then
        log "SUCCESS" "  ✅ ${svc} → http://${target} reachable"
    else
        log "WARN"    "  ⚠️  ${svc} → http://${target} NOT reachable"
    fi
done

# External URL reachability
log "INFO" "--- External URL Reachability ---"
EXTERNAL_URLS=(
    "https://litellm.${DOMAIN}"
    "https://openwebui.${DOMAIN}"
    "https://anythingllm.${DOMAIN}"
    "https://dify.${DOMAIN}"
    "https://n8n.${DOMAIN}"
    "https://flowise.${DOMAIN}"
    "https://signal.${DOMAIN}"
    "https://openclaw.${DOMAIN}"
    "https://prometheus.${DOMAIN}"
    "https://grafana.${DOMAIN}"
    "https://minio.${DOMAIN}"
)

for url in "${EXTERNAL_URLS[@]}"; do
    HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" \
        --max-time 10 --connect-timeout 5 "${url}" 2>/dev/null || echo "000")
    if [[ "${HTTP_CODE}" =~ ^(200|301|302|303|401|403)$ ]]; then
        log "SUCCESS" "  ✅ ${url} → HTTP ${HTTP_CODE}"
    else
        log "FAIL"    "  ❌ ${url} → HTTP ${HTTP_CODE} (no response or error)"
    fi
done

# Tailscale status
log "INFO" "--- Tailscale Status ---"
TAILSCALE_IP=$(docker exec "${COMPOSE_PROJECT_NAME}-tailscale" tailscale ip -4 2>/dev/null || echo "not connected")
log "INFO" "  Tailscale IP: ${TAILSCALE_IP}"

log "INFO" "======================================================"
log "INFO" "Log file: ${LOG_FILE}"
log "INFO" "======================================================"
# ── END STATUS REPORT ────────────────────────────────────────────────────

# ════════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         AI PLATFORM — DEPLOYMENT COMPLETE                    ║"
echo "╠══════════════════════════════════════════════════════════════╣"

echo ""
echo "── Container Health ───────────────────────────────────────────"
docker ps --format "  {{.Names}}\t{{.Status}}" \
    --filter "name=${COMPOSE_PROJECT_NAME}-" | sort | \
    sed 's/healthy/✅ healthy/; s/unhealthy/❌ unhealthy/; s/starting/⏳ starting/'

echo ""
echo "── External URLs ──────────────────────────────────────────────"

check_url() {
    local name=$1 url=$2
    local code
    code=$(curl -o /dev/null -s -w "%{http_code}" \
        --max-time 10 --connect-timeout 5 "${url}" 2>/dev/null || echo "000")
    local icon="❌"
    [[ "${code}" =~ ^(200|301|302|401|403)$ ]] && icon="✅"
    printf "  %s  %-20s %s\n" "${icon}" "${name}" "${url}"
}

check_url "AnythingLLM"  "https://anythingllm.${DOMAIN}"
check_url "OpenClaw"     "https://openclaw.${DOMAIN}"
check_url "Open WebUI"   "https://openwebui.${DOMAIN}"
check_url "Dify"         "https://dify.${DOMAIN}"
check_url "n8n"          "https://n8n.${DOMAIN}"
check_url "Flowise"      "https://flowise.${DOMAIN}"
check_url "LiteLLM"      "https://litellm.${DOMAIN}/health"
check_url "Grafana"      "https://grafana.${DOMAIN}"
check_url "MinIO"        "https://minio.${DOMAIN}"
check_url "Signal API"   "https://signal.${DOMAIN}/v1/about"

echo ""
echo "── Tailscale ──────────────────────────────────────────────────"
TS_IP=$(docker exec "${COMPOSE_PROJECT_NAME}-tailscale" tailscale ip -4 2>/dev/null || echo "not connected")
echo "  IP: ${TS_IP}"

echo ""
echo "── Log ────────────────────────────────────────────────────────"
echo "  ${LOG_FILE}"
echo "╚══════════════════════════════════════════════════════════════╝"

echo ""
section "Deployment Complete"
ok "Script 2 finished."
ok "Infrastructure: PostgreSQL ✓  Redis ✓  MinIO ✓"
ok "Databases:      n8n ✓  flowise ✓  dify ✓  anythingllm ✓"
echo ""
log "Next step: sudo bash scripts/3-configure-services.sh"
echo ""
log "Service URLs:"
log "  n8n:         http://$(hostname -I | awk '{print $1}'):${N8N_PORT:-5678}"
log "  Flowise:     http://$(hostname -I | awk '{print $1}'):${FLOWISE_PORT:-3000}"
log "  Dify:        http://$(hostname -I | awk '{print $1}'):${DIFY_PORT:-80}"
log "  AnythingLLM: http://$(hostname -I | awk '{print $1}'):${ANYTHINGLLM_PORT:-3001}"
log "  MinIO:       http://$(hostname -I | awk '{print $1}'):9001"
