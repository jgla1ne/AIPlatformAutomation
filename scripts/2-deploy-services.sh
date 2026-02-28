#!/usr/bin/env bash
# 2-deploy-services.sh — AI Platform Service Deployment
# Deploys services in dependency-ordered groups using single compose calls
# Usage: sudo ./2-deploy-services.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colour helpers ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'
log()     { echo -e "${BLUE}[DEPLOY]${NC} $*"; }
ok()      { echo -e "${GREEN}✅${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠️ ${NC} $*"; }
err()     { echo -e "${RED}❌${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; \
            echo -e "${CYAN}${BOLD}  $*${NC}"; \
            echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

# ── Must be root ───────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && err "Run as root: sudo $0"

# ── Load environment ───────────────────────────────────────────────────────
ENV_FILE=""
for candidate in \
  "${SCRIPT_DIR}/../.env" \
  "/mnt/data/u1001/.env" \
  "/mnt/data/$(ls /mnt/data 2>/dev/null | head -1)/.env" \
  "/home/ubuntu/aip/.env"; do
  candidate=$(realpath "$candidate" 2>/dev/null || echo "")
  [[ -f "$candidate" ]] && { ENV_FILE="$candidate"; break; }
done
[[ -z "$ENV_FILE" ]] && err "No .env file found. Run 1-setup-system.sh first."

log "Loading environment from: ${ENV_FILE}"
set -a; source "$ENV_FILE"; set +a

# Validate required variables
for var in COMPOSE_PROJECT_NAME DATA_ROOT TENANT_DIR; do
  [[ -z "${!var:-}" ]] && err "Required variable ${var} not set in ${ENV_FILE}"
done

COMPOSE_FILE="${SCRIPT_DIR}/../docker-compose.yml"
[[ ! -f "$COMPOSE_FILE" ]] && COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
[[ ! -f "$COMPOSE_FILE" ]] && err "docker-compose.yml not found"
COMPOSE_FILE="$(realpath "$COMPOSE_FILE")"

log "Project : ${COMPOSE_PROJECT_NAME}"
log "Data    : ${DATA_ROOT}"
log "Compose : ${COMPOSE_FILE}"

# ── Compose wrapper ────────────────────────────────────────────────────────
DC() {
  docker compose \
    --project-name "${COMPOSE_PROJECT_NAME}" \
    --env-file     "${ENV_FILE}" \
    --file         "${COMPOSE_FILE}" \
    "$@"
}

# ── Validate compose file first ────────────────────────────────────────────
section "Validating Configuration"
if ! DC config --quiet 2>/tmp/compose-validate.log; then
  err "docker-compose.yml validation failed:\n$(cat /tmp/compose-validate.log)"
fi
ok "Compose file valid"

# ── Pre-flight: remove stale networks with bad labels ─────────────────────
section "Pre-flight Cleanup"
log "Checking for stale networks..."
for net in \
  "${COMPOSE_PROJECT_NAME}_net_internal" \
  "${COMPOSE_PROJECT_NAME}_net_default"; do
  if docker network inspect "$net" >/dev/null 2>&1; then
    LABEL=$(docker network inspect "$net" \
      --format '{{index .Labels "com.docker.compose.network"}}' 2>/dev/null || true)
    if [[ -z "$LABEL" ]]; then
      warn "Removing stale network with no compose label: ${net}"
      # Disconnect any containers first
      docker network inspect "$net" \
        --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null \
        | tr ' ' '\n' | grep -v '^$' \
        | xargs -r -I{} docker network disconnect -f "$net" {} 2>/dev/null || true
      docker network rm "$net" 2>/dev/null || true
    else
      log "Network ${net} has valid label — leaving in place"
    fi
  fi
done
ok "Pre-flight complete"

# ── Create data directories ────────────────────────────────────────────────
section "Creating Data Directories"
DIRS=(
  "${TENANT_DIR}/postgres"
  "${TENANT_DIR}/redis"
  "${TENANT_DIR}/qdrant"
  "${TENANT_DIR}/minio"
  "${TENANT_DIR}/n8n"
  "${TENANT_DIR}/flowise"
  "${TENANT_DIR}/anythingllm"
  "${TENANT_DIR}/ollama"
  "${TENANT_DIR}/dify/api"
  "${TENANT_DIR}/dify/storage"
  "${TENANT_DIR}/signal"
  "${TENANT_DIR}/nginx/certs"
  "${TENANT_DIR}/nginx/conf.d"
  "${TENANT_DIR}/apparmor"
)

for d in "${DIRS[@]}"; do
  mkdir -p "$d"
done

# Set ownership AFTER directory creation, to host UID
# Named volumes are managed by Docker — we only set ownership on 
# bind-mount directories, not volume mount points
chown -R 1000:1000 "${TENANT_DIR}/n8n" \
                   "${TENANT_DIR}/flowise" \
                   "${TENANT_DIR}/anythingllm" 2>/dev/null || true
chown -R 999:999   "${TENANT_DIR}/postgres" 2>/dev/null || true
# Dify storage needs www-data equivalent
chown -R 1000:1000 "${TENANT_DIR}/dify" 2>/dev/null || true

ok "Data directories created"

# ── Health check functions ─────────────────────────────────────────────────

# Wait for postgres using pg_isready (not curl)
wait_for_postgres() {
  local container="${COMPOSE_PROJECT_NAME}-postgres-1"
  local max_wait=120
  local elapsed=0
  log "Waiting for PostgreSQL to be ready (max ${max_wait}s)..."
  while [[ $elapsed -lt $max_wait ]]; do
    if docker exec "$container" \
        pg_isready -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}" \
        -q 2>/dev/null; then
      ok "PostgreSQL ready (${elapsed}s)"
      return 0
    fi
    sleep 3; elapsed=$((elapsed + 3))
    [[ $((elapsed % 15)) -eq 0 ]] && log "  Still waiting for PostgreSQL... ${elapsed}s"
  done
  err "PostgreSQL did not become ready in ${max_wait}s"
}

# Wait for Redis using redis-cli ping
wait_for_redis() {
  local container="${COMPOSE_PROJECT_NAME}-redis-1"
  local max_wait=60
  local elapsed=0
  log "Waiting for Redis to be ready (max ${max_wait}s)..."
  while [[ $elapsed -lt $max_wait ]]; do
    if docker exec "$container" redis-cli -a "${REDIS_PASSWORD}" ping 2>/dev/null | grep -q "PONG"; then
      ok "Redis ready (${elapsed}s)"
      return 0
    fi
    sleep 2; elapsed=$((elapsed + 2))
  done
  err "Redis did not become ready in ${max_wait}s"
}

# Wait for HTTP service
wait_for_http() {
  local name="$1"
  local url="$2"
  local max_wait="${3:-120}"
  local elapsed=0
  log "Waiting for ${name} at ${url} (max ${max_wait}s)..."
  while [[ $elapsed -lt $max_wait ]]; do
    if curl -sf --max-time 5 "$url" >/dev/null 2>&1; then
      ok "${name} ready (${elapsed}s)"
      return 0
    fi
    sleep 5; elapsed=$((elapsed + 5))
    [[ $((elapsed % 30)) -eq 0 ]] && log "  Still waiting for ${name}... ${elapsed}s"
  done
  warn "${name} not responding after ${max_wait}s — continuing anyway"
  return 0  # Non-fatal — log and continue
}

# Wait for Qdrant REST API
wait_for_qdrant() {
  local port="${QDRANT_PORT:-6333}"
  wait_for_http "Qdrant" "http://localhost:${port}/" 90
}

# ── GROUP 1: Infrastructure ────────────────────────────────────────────────
section "Group 1: Infrastructure Services"
log "Starting: postgres, redis, qdrant, minio"

DC up -d --no-deps \
  postgres redis qdrant minio

log "Waiting for infrastructure to be healthy..."
wait_for_postgres
wait_for_redis
wait_for_qdrant

# MinIO — just wait for container to be running, HTTP check optional
MINIO_CONTAINER="${COMPOSE_PROJECT_NAME}-minio-1"
if docker ps --format '{{.Names}}' | grep -q "^${MINIO_CONTAINER}$"; then
  wait_for_http "MinIO" "http://localhost:${MINIO_PORT:-9000}/minio/health/live" 60 || true
fi

ok "Group 1 (Infrastructure) healthy"

# ── Postgres: create required databases ───────────────────────────────────
section "Database Initialisation"
PG_CONTAINER="${COMPOSE_PROJECT_NAME}-postgres-1"

create_db_if_missing() {
  local dbname="$1"
  if ! docker exec "$PG_CONTAINER" \
      psql -U "${POSTGRES_USER:-postgres}" -lqt 2>/dev/null \
      | cut -d'|' -f1 | grep -qw "$dbname"; then
    log "Creating database: ${dbname}"
    docker exec "$PG_CONTAINER" \
      psql -U "${POSTGRES_USER:-postgres}" \
      -c "CREATE DATABASE \"${dbname}\";" 2>/dev/null
    ok "Database created: ${dbname}"
  else
    log "Database already exists: ${dbname}"
  fi
}

create_db_if_missing "n8n"
create_db_if_missing "flowise"
create_db_if_missing "dify"

# Enable pgvector extension in dify database
log "Enabling pgvector in dify database..."
docker exec "$PG_CONTAINER" \
  psql -U "${POSTGRES_USER:-postgres}" -d "dify" \
  -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null || true
ok "pgvector enabled"

# ── GROUP 2: AI Core Services ──────────────────────────────────────────────
section "Group 2: AI Core Services"
log "Starting: ollama, n8n, flowise, anythingllm"

DC up -d --no-deps \
  ollama n8n flowise anythingllm

wait_for_http "n8n"          "http://localhost:${N8N_PORT:-5678}/healthz"           120
wait_for_http "Flowise"      "http://localhost:${FLOWISE_PORT:-3000}"                90
wait_for_http "AnythingLLM"  "http://localhost:${ANYTHINGLLM_PORT:-3001}/api/ping"  120

ok "Group 2 (AI Core) healthy"

# ── GROUP 3: Dify ──────────────────────────────────────────────────────────
section "Group 3: Dify Platform"

# Only deploy if Dify services are defined in compose file
if DC config --services 2>/dev/null | grep -q "^dify-api$"; then
  log "Starting: dify-api, dify-worker, dify-web, dify-sandbox, dify-proxy"

  DC up -d --no-deps \
    dify-api dify-worker dify-web dify-sandbox dify-proxy 2>/dev/null || {
    warn "Some Dify services failed to start — checking individually..."
    for svc in dify-api dify-worker dify-web; do
      DC up -d --no-deps "$svc" 2>/dev/null || warn "Failed to start ${svc}"
    done
  }

  # Dify API takes longer to start — it runs database migrations
  wait_for_http "Dify API"  "http://localhost:${DIFY_PORT:-5001}/health"  180
  wait_for_http "Dify Web"  "http://localhost:${DIFY_WEB_PORT:-3002}"      90

  ok "Group 3 (Dify) healthy"
else
  warn "Dify services not found in compose file — skipping"
fi

# ── GROUP 4: Optional Services ─────────────────────────────────────────────
section "Group 4: Optional Services"

# Signal CLI — only if enabled
if DC config --services 2>/dev/null | grep -q "^signal-api$"; then
  if [[ "${ENABLE_SIGNAL:-false}" == "true" ]]; then
    log "Starting: signal-api"
    DC up -d --no-deps signal-api 2>/dev/null || warn "signal-api failed to start"
    # Signal takes 60s+ to initialise Java runtime — don't block on it
    log "Signal CLI started — it will take 60-90s to fully initialise"
  else
    log "Signal disabled (ENABLE_SIGNAL != true) — skipping"
  fi
fi

# Tailscale — only if auth key present
if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
  log "Starting: tailscale"
  DC up -d --no-deps tailscale 2>/dev/null || warn "Tailscale failed to start"
  ok "Tailscale started"
else
  log "TAILSCALE_AUTH_KEY not set — skipping Tailscale"
fi

# ── GROUP 5: Nginx (last — depends on all upstream services) ───────────────
section "Group 5: Nginx Reverse Proxy"

if DC config --services 2>/dev/null | grep -q "^nginx$"; then
  log "Starting: nginx"
  DC up -d --no-deps nginx 2>/dev/null || warn "nginx failed to start"
  wait_for_http "Nginx" "http://localhost:80" 60 || true
  ok "Nginx started"
fi

# ── Final Status ───────────────────────────────────────────────────────────
section "Deployment Complete"

echo "Container status:"
DC ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || \
  docker ps --filter "name=${COMPOSE_PROJECT_NAME}" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
RUNNING=$(docker ps --filter "name=${COMPOSE_PROJECT_NAME}" --format '{{.Names}}' | wc -l)
TOTAL=$(DC config --services 2>/dev/null | wc -l)
echo -e "${GREEN}${BOLD}Services running: ${RUNNING}/${TOTAL}${NC}"
echo ""
echo "Next step: sudo ./3-configure-services.sh"
