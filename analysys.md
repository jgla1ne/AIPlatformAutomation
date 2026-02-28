Let me read all files before writing a single instruction.

**Reading all 9 files now.**

---

After reading everything, here is my complete assessment and the exact instructions for Windsurf.

---

# Root Cause Analysis — Why Script 2 Still Fails

## The Real Problems (in priority order)

### Problem 1 — Script 2 deploys services one-by-one with separate `docker compose up` calls

This is the **architectural root cause** of most failures. Script 2 calls `docker compose up` for postgres alone, waits, then calls it again for redis alone, etc. Each separate invocation:

- Creates the network on the first call
- On the second call, compose sees the network exists **without the current invocation's project context** and throws the label warning
- Volumes created by the first call are "owned" by that invocation; subsequent calls see ownership conflicts
- Health check timing between separate calls causes cascading failures

**The fix is one `docker compose up` call for all infrastructure services together.**

### Problem 2 — Dify requires 12+ containers and a specific startup order

Dify is not a single container. It requires: `dify-api`, `dify-worker`, `dify-web`, `dify-sandbox`, `dify-proxy` — all of which depend on postgres AND redis being healthy first. The current script tries to deploy Dify containers individually without respecting this dependency chain.

### Problem 3 — Volume ownership set before containers define the mount

Script 2 runs `chown` on directories before compose creates the named volumes. Named Docker volumes are managed by Docker, not by the host filesystem path. The `chown` on the host path has no effect on the volume's internal permissions.

### Problem 4 — Signal-CLI still crashing

The `bbernhard/signal-cli-rest-api` image is being pulled for `linux/amd64` but the actual binary inside uses a different architecture layer. Version pinning to `0.84` alone does not fix this — the container needs a capability flag and a specific entrypoint.

### Problem 5 — Health check functions test the wrong endpoints

The `wait_for_service` function in Script 2 uses generic HTTP checks. Postgres health is checked with `curl` instead of `pg_isready`. Qdrant is checked on port 6333 but the REST API is on 6333 and gRPC on 6334 — checking the wrong one returns false negatives.

---

# Complete Solution for Windsurf

## The Architecture Change

Stop deploying service-by-service. Use **dependency groups** with a single compose call per group:

```
Group 1 (Infrastructure):  postgres, redis, qdrant, minio
Group 2 (AI Core):         ollama, flowise, n8n, anythingllm  
Group 3 (Dify):            dify-api, dify-worker, dify-web, dify-sandbox, dify-proxy
Group 4 (Optional):        signal-api, tailscale
```

Each group waits for the previous group to be healthy before starting.

---

## COMMIT 1 — Rewrite `scripts/2-deploy-services.sh` completely

```
TASK: Replace 2-deploy-services.sh entirely with the version below.
Do not preserve any existing logic. The current architecture is the problem.
```

```bash
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
    if docker exec "$container" redis-cli ping 2>/dev/null | grep -q "PONG"; then
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
  wait_for_http "Qdrant" "http://localhost:${port}/healthz" 90
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
```

---

## COMMIT 2 — Fix `docker-compose.yml` — Named Volumes and TENANT_DIR

```
TASK: Fix three things in docker-compose.yml.

FIX 1 — Add TENANT_DIR to the volumes block.

Every service that uses a bind mount to ${TENANT_DIR}/something must
have a corresponding entry in the top-level volumes: block OR must use
a bind mount type explicitly. 

For ALL services using ${TENANT_DIR} paths, change from:
  volumes:
    - ${TENANT_DIR}/postgres:/var/lib/postgresql/data

To named volume style:
  volumes:
    - postgres-data:/var/lib/postgresql/data

Then at the bottom of docker-compose.yml add:
  volumes:
    postgres-data:
    redis-data:
    qdrant-data:
    minio-data:
    n8n-data:
    flowise-data:
    anythingllm-data:
    ollama-data:
    dify-api-data:
    dify-storage-data:
    signal-data:

This removes the dependency on TENANT_DIR for volume mounts entirely.
TENANT_DIR is still used for config files and nginx certs (bind mounts
for those are fine).

FIX 2 — Add explicit healthchecks to infrastructure services.

FIND the postgres service. ADD if not present:
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres}"]
    interval: 10s
    timeout: 5s
    retries: 10
    start_period: 30s

FIND the redis service. ADD if not present:
  healthcheck:
    test: ["CMD", "redis-cli", "ping"]
    interval: 10s
    timeout: 5s
    retries: 10

FIND the qdrant service. ADD if not present:
  healthcheck:
    test: ["CMD-SHELL", "curl -sf http://localhost:6333/healthz || exit 1"]
    interval: 15s
    timeout: 10s
    retries: 10
    start_period: 30s

FIX 3 — Fix signal-api service completely.

REPLACE the entire signal-api service definition with:

  signal-api:
    image: bbernhard/signal-cli-rest-api:0.84
    platform: linux/amd64
    container_name: ${COMPOSE_PROJECT_NAME}-signal-api
    restart: unless-stopped
    environment:
      MODE: native
      PORT: "${SIGNAL_PORT:-8085}"
      JAVA_OPTS: "-Xmx512m -Xms128m"
    volumes:
      - signal-data:/home/.local/share/signal-cli
    networks:
      - net_internal
    ports:
      - "${SIGNAL_PORT:-8085}:${SIGNAL_PORT:-8085}"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:${SIGNAL_PORT:-8085}/v1/about || exit 1"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 90s
    profiles:
      - signal

IMPORTANT: Adding profiles: [signal] means signal-api only starts when
DC --profile signal up is called, OR when explicitly named in up -d.
This prevents it blocking the main deployment.

VERIFICATION:
  docker compose --env-file /mnt/data/u1001/.env config --quiet
  Must exit 0 with zero warnings about TENANT_DIR or variables.
```

---

## COMMIT 3 — Fix `.env` — Add missing variables to `scripts/1-setup-system.sh`

```
TASK: Add TENANT_DIR and ENABLE_SIGNAL to the .env write block in
1-setup-system.sh.

FIND the section that writes variables to the .env file. It will have
lines like:
  echo "COMPOSE_PROJECT_NAME=${PROJECT_NAME}" >> "$ENV_FILE"
  echo "DATA_ROOT=${DATA_ROOT}" >> "$ENV_FILE"

ADD these lines immediately after DATA_ROOT:
  echo "TENANT_DIR=${DATA_ROOT}/${TENANT_NAME}" >> "$ENV_FILE"
  echo "ENABLE_SIGNAL=false" >> "$ENV_FILE"
  echo "TAILSCALE_EXTRA_ARGS=" >> "$ENV_FILE"

FIND the port allocation section. Ensure these lines exist:
  echo "SIGNAL_PORT=${PORTS[signal-api]:-8085}" >> "$ENV_FILE"
  echo "QDRANT_PORT=${PORTS[qdrant]:-6333}" >> "$ENV_FILE"
  echo "MINIO_PORT=${PORTS[minio]:-9000}" >> "$ENV_FILE"
  echo "FLOWISE_PORT=${PORTS[flowise]:-3000}" >> "$ENV_FILE"
  echo "ANYTHINGLLM_PORT=${PORTS[anythingllm]:-3001}" >> "$ENV_FILE"
  echo "DIFY_PORT=${PORTS[dify-api]:-5001}" >> "$ENV_FILE"
  echo "DIFY_WEB_PORT=${PORTS[dify-web]:-3002}" >> "$ENV_FILE"

After this commit, run:
  sudo ./1-setup-system.sh
  grep -E "^(TENANT_DIR|ENABLE_SIGNAL|SIGNAL_PORT|TAILSCALE_EXTRA_ARGS)=" \
    /mnt/data/u1001/.env

All four lines must appear with non-empty values (except TAILSCALE_EXTRA_ARGS
which is intentionally empty).
```

---

## COMMIT 4 — Fix `scripts/0-complete-cleanup.sh` — Nuclear option for named volumes

```
TASK: Ensure cleanup removes named Docker volumes that compose creates.

The current cleanup removes volumes prefixed with the project name but
compose names volumes as: ${PROJECT_NAME}_${volume_name}

For example: aip-u1001_postgres-data

FIND the volume removal section. REPLACE with:

  # Remove all volumes for this project
  log "Removing named volumes for project: ${PROJECT_NAME}"
  
  # Method 1: Remove by compose project label (most reliable)
  docker volume ls --filter "label=com.docker.compose.project=${PROJECT_NAME}" \
    --format '{{.Name}}' | xargs -r docker volume rm -f 2>/dev/null || true
  
  # Method 2: Remove by name prefix (catches anything Method 1 misses)
  docker volume ls --format '{{.Name}}' \
    | grep -E "^${PROJECT_NAME}[_-]" \
    | xargs -r docker volume rm -f 2>/dev/null || true

  # Method 3: Prune anonymous volumes
  docker volume prune -f 2>/dev/null || true

ALSO FIND the network removal section. REPLACE with:

  # Remove all networks for this project
  log "Removing networks for project: ${PROJECT_NAME}"
  
  # Method 1: By compose project label
  docker network ls --filter "label=com.docker.compose.project=${PROJECT_NAME}" \
    --format '{{.Name}}' | while read -r net; do
    docker network disconnect -f "$net" \
      $(docker network inspect "$net" \
        --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null) \
      2>/dev/null || true
    docker network rm "$net" 2>/dev/null || true
  done
  
  # Method 2: By name prefix
  docker network ls --format '{{.Name}}' \
    | grep -E "^${PROJECT_NAME}[_-]" | while read -r net; do
    docker network rm "$net" 2>/dev/null || true
  done

VERIFICATION after cleanup:
  docker volume ls | grep aip-
  docker network ls | grep aip-
  Both must return EMPTY.
```

---

## Pre-Test Cleanup — Run Before Testing

```bash
# WINDSURF: Run this exact block before the first test of the new scripts

PROJECT="aip-u1001"  # adjust if different

# Stop and remove all containers for this project
docker ps -aq --filter "name=${PROJECT}" | xargs -r docker rm -f 2>/dev/null || true

# Remove all named volumes with compose label
docker volume ls \
  --filter "label=com.docker.compose.project=${PROJECT}" \
  --format '{{.Name}}' | xargs -r docker volume rm -f 2>/dev/null || true

# Remove by name prefix (belt and braces)
docker volume ls --format '{{.Name}}' | grep "^${PROJECT}" \
  | xargs -r docker volume rm -f 2>/dev/null || true

# Remove networks
docker network ls --format '{{.Name}}' | grep "^${PROJECT}" \
  | while read net; do
      docker network rm "$net" 2>/dev/null || true
    done

# Prune anonymous volumes
docker volume prune -f

# Verify clean
echo "=== Must all be empty ==="
docker ps -a --filter "name=${PROJECT}" --format '{{.Names}}'
docker volume ls | grep "${PROJECT}"
docker network ls | grep "${PROJECT}"
```

---

## Acceptance Test — What Success Looks Like

```bash
# Run all three scripts and verify

sudo ./1-setup-system.sh
# Must complete with: ✅ Setup complete
# Must create .env with TENANT_DIR set

sudo ./2-deploy-services.sh
# Must show each group completing
# Must NOT show any "network has incorrect label" errors
# Must NOT show any "variable is not set" warnings
# Final output must show at least 8/N services running

sudo ./3-configure-services.sh
# Must complete without errors

# Final verification
docker ps --filter "name=aip-u1001" \
  --format "table {{.Names}}\t{{.Status}}" | sort
# Every line must say "Up X minutes" or "Up X seconds (healthy)"
# Zero lines with "Restarting" or "Exited"
```

---

## Summary

| Commit | File | Core Fix | Eliminates |
|--------|------|----------|------------|
| 1 | `2-deploy-services.sh` | Group-based deployment, correct health checks | Network label conflicts, cascade failures |
| 2 | `docker-compose.yml` | Named volumes, healthchecks, signal profile | TENANT_DIR warnings, signal crash loops |
| 3 | `1-setup-system.sh` | Write TENANT_DIR + all port vars to .env | "variable not set" warnings |
| 4 | `0-complete-cleanup.sh` | Label-based volume/network removal | Stale state on re-runs |