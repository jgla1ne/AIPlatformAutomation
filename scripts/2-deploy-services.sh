#!/usr/bin/env bash
# =============================================================================
# 2-deploy-services.sh — AI Platform Service Deployment
# =============================================================================
# Deploys all services in dependency order with proper health verification.
# Run as: sudo ./2-deploy-services.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'
log()     { echo -e "${BLUE}[DEPLOY]${NC} $*"; }
ok()      { echo -e "${GREEN}✅${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠️ ${NC} $*"; }
fail()    { echo -e "${RED}❌ FATAL:${NC} $*" >&2; exit 1; }
section() {
  echo ""
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}${BOLD}  $*${NC}"
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

# ── Must be root ──────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && fail "Run as root: sudo $0"

# =============================================================================
# PHASE 0: Load and validate environment
# =============================================================================
section "Phase 0: Environment Validation"

# Find .env file
ENV_FILE=""
# Try paths in order of preference
for candidate in \
    "${TENANT_DIR}/.env" \
    "${DATA_ROOT}/${TENANT_NAME}/.env" \
    "${SCRIPT_DIR}/../.env" \
    "${REPO_ROOT}/.env"; do
  candidate="$(realpath "$candidate" 2>/dev/null || true)"
  if [[ -n "$candidate" && -f "$candidate" ]]; then
    ENV_FILE="$candidate"
    break
  fi
done

# Fallback: find it under /mnt/data
if [[ -z "$ENV_FILE" ]]; then
  ENV_FILE="$(find /mnt/data -maxdepth 3 -name '.env' -newer /etc/hostname 2>/dev/null | head -1 || true)"
fi

[[ -z "$ENV_FILE" || ! -f "$ENV_FILE" ]] && \
  fail ".env not found. Run: sudo ./1-setup-system.sh first"

log "Environment: ${ENV_FILE}"
set -a; source "$ENV_FILE"; set +a

# Validate critical variables — fail fast with clear message
REQUIRED_VARS=(
  COMPOSE_PROJECT_NAME
  DATA_ROOT
  TENANT_DIR
  POSTGRES_USER
  POSTGRES_PASSWORD
  REDIS_PASSWORD
  CODE_EXECUTION_API_KEY
  N8N_ENCRYPTION_KEY
)
MISSING=()
for var in "${REQUIRED_VARS[@]}"; do
  [[ -z "${!var:-}" ]] && MISSING+=("$var")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  fail "Missing required variables in ${ENV_FILE}: ${MISSING[*]}"
fi

# Find compose file
COMPOSE_FILE=""
for candidate in \
    "${REPO_ROOT}/docker-compose.yml" \
    "${SCRIPT_DIR}/../docker-compose.yml" \
    "${SCRIPT_DIR}/docker-compose.yml"; do
  candidate="$(realpath "$candidate" 2>/dev/null || true)"
  if [[ -n "$candidate" && -f "$candidate" ]]; then
    COMPOSE_FILE="$candidate"
    break
  fi
done
[[ -z "$COMPOSE_FILE" ]] && fail "docker-compose.yml not found in repo"

log "Project:  ${COMPOSE_PROJECT_NAME}"
log "Data:     ${DATA_ROOT}"
log "Tenant:   ${TENANT_DIR}"
log "Compose:  ${COMPOSE_FILE}"

# ── Compose shorthand ─────────────────────────────────────────────────────────
DC() {
  docker compose \
    --project-name "${COMPOSE_PROJECT_NAME}" \
    --env-file     "${ENV_FILE}" \
    --file         "${COMPOSE_FILE}" \
    "$@"
}

# ── Validate compose file ─────────────────────────────────────────────────────
log "Validating compose file..."
if ! DC config --quiet 2>/tmp/dc-validate.log; then
  fail "Compose validation failed:\n$(cat /tmp/dc-validate.log)"
fi
ok "Compose file valid"

# Get list of services defined in compose
DEFINED_SERVICES="$(DC config --services 2>/dev/null)"
has_service() { echo "$DEFINED_SERVICES" | grep -qx "$1"; }

# =============================================================================
# PHASE 1: Pre-flight cleanup of stale Docker resources
# =============================================================================
section "Phase 1: Pre-flight Cleanup"

# Remove networks with bad labels (no compose project label)
# These are left over from failed runs where docker network create was called
# manually before compose had a chance to create them with proper labels.
log "Checking for stale networks..."
while IFS= read -r net; do
  [[ -z "$net" ]] && continue
  LABEL="$(docker network inspect "$net" \
    --format '{{index .Labels "com.docker.compose.project"}}' 2>/dev/null || true)"
  if [[ -z "$LABEL" ]]; then
    warn "Removing stale network (no compose label): ${net}"
    # Disconnect containers before removing
    CONTAINERS="$(docker network inspect "$net" \
      --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || true)"
    for c in $CONTAINERS; do
      docker network disconnect -f "$net" "$c" 2>/dev/null || true
    done
    docker network rm "$net" 2>/dev/null || true
  fi
done < <(docker network ls --format '{{.Name}}' \
           | grep -E "^${COMPOSE_PROJECT_NAME}" || true)

ok "Pre-flight complete"

# =============================================================================
# PHASE 2: Create data directories (bind mounts only — NOT named volume paths)
# =============================================================================
section "Phase 2: Data Directories"

# IMPORTANT: Only create directories for actual bind mounts.
# Named volumes (postgres-data, redis-data etc.) are managed by Docker.
# Do NOT chown directories that are used as named volume destinations.

BIND_DIRS=(
  "${TENANT_DIR}/nginx/certs"
  "${TENANT_DIR}/nginx/conf.d"
  "${TENANT_DIR}/apparmor"
  "${TENANT_DIR}/ollama/models"
)

for d in "${BIND_DIRS[@]}"; do
  mkdir -p "$d"
  log "  Created: $d"
done

ok "Bind mount directories created"

# =============================================================================
# PHASE 3: Start infrastructure services (postgres, redis, qdrant, minio)
# =============================================================================
section "Phase 3: Infrastructure Services"

log "Starting infrastructure: postgres redis qdrant minio"
DC up -d postgres redis qdrant minio
# Note: No --no-deps here. Compose handles dependency order.
# If these services have no depends_on, order doesn't matter for this group.

# ── Wait for PostgreSQL ──────────────────────────────────────────────────────
PG_CONTAINER="${COMPOSE_PROJECT_NAME}-postgres"
log "Waiting for PostgreSQL..."
ELAPSED=0; MAX=120
until docker exec "$PG_CONTAINER" \
    pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-postgres}" -q \
    2>/dev/null; do
  # Check if container exited (crash loop)
  STATUS="$(docker inspect --format '{{.State.Status}}' "$PG_CONTAINER" 2>/dev/null || echo 'missing')"
  if [[ "$STATUS" == "exited" ]]; then
    fail "PostgreSQL container exited — check: docker logs $PG_CONTAINER"
  fi
  sleep 3; ELAPSED=$((ELAPSED+3))
  [[ $ELAPSED -ge $MAX ]] && fail "PostgreSQL not ready after ${MAX}s — check: docker logs $PG_CONTAINER"
  [[ $((ELAPSED % 15)) -eq 0 ]] && log "  PostgreSQL: ${ELAPSED}s elapsed..."
done
ok "PostgreSQL ready (${ELAPSED}s)"

# ── Wait for Redis ───────────────────────────────────────────────────────────
REDIS_CONTAINER="${COMPOSE_PROJECT_NAME}-redis"
log "Waiting for Redis..."
ELAPSED=0; MAX=60
until docker exec "$REDIS_CONTAINER" \
    redis-cli -a "${REDIS_PASSWORD}" ping 2>/dev/null | grep -q "PONG"; do
  sleep 2; ELAPSED=$((ELAPSED+2))
  [[ $ELAPSED -ge $MAX ]] && fail "Redis not ready after ${MAX}s"
done
ok "Redis ready (${ELAPSED}s)"

# ── Wait for Qdrant ──────────────────────────────────────────────────────────
log "Waiting for Qdrant..."
ELAPSED=0; MAX=90
until curl -sf "http://localhost:${QDRANT_PORT:-6333}/collections" \
    >/dev/null 2>&1; do
  sleep 3; ELAPSED=$((ELAPSED+3))
  [[ $ELAPSED -ge $MAX ]] && { warn "Qdrant not ready after ${MAX}s — continuing"; break; }
done
ok "Qdrant ready (${ELAPSED}s)"

# ── MinIO ────────────────────────────────────────────────────────────────────
ELAPSED=0; MAX=60
until curl -sf "http://localhost:${MINIO_PORT:-9000}/minio/health/live" \
    >/dev/null 2>&1; do
  sleep 3; ELAPSED=$((ELAPSED+3))
  [[ $ELAPSED -ge $MAX ]] && { warn "MinIO health endpoint not responding — continuing"; break; }
done
ok "MinIO ready (${ELAPSED}s)"

# =============================================================================
# PHASE 4: Create databases (BEFORE any application starts)
# =============================================================================
section "Phase 4: Database Initialisation"

create_db() {
  local db="$1"
  if docker exec "$PG_CONTAINER" \
      psql -U "${POSTGRES_USER}" -lqt 2>/dev/null \
      | cut -d'|' -f1 | grep -qw "$db"; then
    log "  Database exists: ${db}"
  else
    log "  Creating database: ${db}"
    docker exec "$PG_CONTAINER" \
      psql -U "${POSTGRES_USER}" \
      -c "CREATE DATABASE \"${db}\";" 2>/dev/null
    ok "  Created: ${db}"
  fi
}

create_db "n8n"
create_db "flowise"
create_db "dify"

# Enable pgvector in dify database
log "Enabling pgvector extension in dify database..."
docker exec "$PG_CONTAINER" \
  psql -U "${POSTGRES_USER}" -d "dify" \
  -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null && \
  ok "pgvector enabled" || warn "pgvector not available — install pgvector image"

ok "Database initialisation complete"

# =============================================================================
# PHASE 5: Start AI core services
# =============================================================================
section "Phase 5: AI Core Services"

# Build service list dynamically — only include services that exist in compose
AI_SERVICES=()
for svc in ollama n8n flowise anythingllm; do
  has_service "$svc" && AI_SERVICES+=("$svc")
done

if [[ ${#AI_SERVICES[@]} -gt 0 ]]; then
  log "Starting: ${AI_SERVICES[*]}"
  DC up -d "${AI_SERVICES[@]}"

  # Health checks — non-fatal (service may still be starting)
  declare -A SERVICE_URLS=(
    [n8n]="http://localhost:${N8N_PORT:-5678}/healthz"
    [flowise]="http://localhost:${FLOWISE_PORT:-3000}"
    [anythingllm]="http://localhost:${ANYTHINGLLM_PORT:-3001}/api/ping"
  )

  for svc in "${!SERVICE_URLS[@]}"; do
    has_service "$svc" || continue
    url="${SERVICE_URLS[$svc]}"
    log "Waiting for ${svc} at ${url}..."
    ELAPSED=0; MAX=120
    until curl -sf --max-time 5 "$url" >/dev/null 2>&1; do
      sleep 5; ELAPSED=$((ELAPSED+5))
      if [[ $ELAPSED -ge $MAX ]]; then
        warn "${svc} not responding after ${MAX}s — check: docker logs ${COMPOSE_PROJECT_NAME}-${svc}"
        break
      fi
    done
    [[ $ELAPSED -lt $MAX ]] && ok "${svc} ready (${ELAPSED}s)"
  done
else
  warn "No AI core services found in compose file"
fi

# =============================================================================
# PHASE 6: Start Dify (if defined)
# =============================================================================
section "Phase 6: Dify Platform"

DIFY_SERVICES=()
for svc in dify-api dify-worker dify-web dify-sandbox dify-proxy; do
  has_service "$svc" && DIFY_SERVICES+=("$svc")
done

if [[ ${#DIFY_SERVICES[@]} -gt 0 ]]; then
  log "Starting Dify services: ${DIFY_SERVICES[*]}"
  # Dify depends_on postgres+redis (defined in compose) — they're already healthy
  DC up -d "${DIFY_SERVICES[@]}"

  # Dify API runs migrations — give it extra time
  log "Waiting for Dify API (runs DB migrations, allow 3 minutes)..."
  ELAPSED=0; MAX=180
  until curl -sf --max-time 10 \
      "http://localhost:${DIFY_PORT:-5001}/v1/health" >/dev/null 2>&1; do
    sleep 10; ELAPSED=$((ELAPSED+10))
    if [[ $ELAPSED -ge $MAX ]]; then
      warn "Dify API not ready after ${MAX}s — check: docker logs ${COMPOSE_PROJECT_NAME}-dify-api"
      break
    fi
    log "  Dify API: ${ELAPSED}s elapsed..."
  done
  [[ $ELAPSED -lt $MAX ]] && ok "Dify API ready (${ELAPSED}s)"
else
  log "Dify services not defined in compose — skipping"
fi

# =============================================================================
# PHASE 7: Start optional services
# =============================================================================
section "Phase 7: Optional Services"

# Tailscale
if has_service "tailscale" && [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
  log "Starting Tailscale..."
  DC up -d tailscale && ok "Tailscale started" || warn "Tailscale failed to start"
else
  log "Tailscale: skipped (no TAILSCALE_AUTH_KEY or service not defined)"
fi

# Signal — only if ENABLE_SIGNAL=true and profile is supported
if has_service "signal-api" && [[ "${ENABLE_SIGNAL:-false}" == "true" ]]; then
  log "Starting Signal CLI..."
  DC --profile signal up -d signal-api && \
    ok "Signal CLI started (takes 90s to initialise)" || \
    warn "Signal CLI failed to start — check docker logs ${COMPOSE_PROJECT_NAME}-signal-api"
else
  log "Signal: skipped (ENABLE_SIGNAL=${ENABLE_SIGNAL:-false})"
fi

# =============================================================================
# PHASE 8: Start Nginx (last — reverse proxy for all upstream services)
# =============================================================================
section "Phase 8: Nginx Reverse Proxy"

if has_service "nginx"; then
  log "Starting Nginx..."
  DC up -d nginx
  ELAPSED=0
  until curl -sf --max-time 5 "http://localhost:80" >/dev/null 2>&1; do
    sleep 3; ELAPSED=$((ELAPSED+3))
    [[ $ELAPSED -ge 30 ]] && { warn "Nginx not responding on :80"; break; }
  done
  [[ $ELAPSED -lt 30 ]] && ok "Nginx ready"
else
  log "Nginx not defined in compose — skipping"
fi

# =============================================================================
# PHASE 9: Final status report
# =============================================================================
section "Deployment Complete"

echo -e "${BOLD}Container Status:${NC}"
DC ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || \
  docker ps --filter "name=${COMPOSE_PROJECT_NAME}" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
RUNNING=$(docker ps --filter "name=${COMPOSE_PROJECT_NAME}" \
  --filter "status=running" --format '{{.Names}}' | wc -l)
TOTAL=$(echo "$DEFINED_SERVICES" | grep -v '^signal-api$' | wc -l)
UNHEALTHY=$(docker ps --filter "name=${COMPOSE_PROJECT_NAME}" \
  --filter "health=unhealthy" --format '{{.Names}}' | wc -l)

if [[ $UNHEALTHY -gt 0 ]]; then
  warn "${UNHEALTHY} containers in unhealthy state"
  docker ps --filter "name=${COMPOSE_PROJECT_NAME}" \
    --filter "health=unhealthy" --format "  {{.Names}}: {{.Status}}"
fi

echo ""
echo -e "${GREEN}${BOLD}✅ Deployment complete: ${RUNNING} containers running${NC}"
echo ""
echo "Run next: sudo ./3-configure-services.sh"
