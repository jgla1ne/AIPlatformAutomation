Let me read all files carefully before writing a single instruction.

**Fetching all files now.**

---

After reading everything, here is my complete ground-truth assessment and exact instructions for Windsurf.

---

# Ground Truth — What Is Actually Failing and Why

## The FRONTIER_MODEL_ASSESSMENT tells us the real problems

Reading that document, the actual failures are:

1. **Dify depends on postgres+redis being healthy — but compose `depends_on` with `condition: service_healthy` only works if the upstream service has a `healthcheck` defined in the compose file.** If postgres has no healthcheck stanza, `service_healthy` never triggers and Dify hangs forever.

2. **The `DC up -d --no-deps` pattern breaks depends_on entirely.** When you pass `--no-deps`, Docker Compose skips the dependency resolution. So postgres may not be running when n8n tries to connect.

3. **Volume mount permissions are set on the host path but the named volume is mounted INSIDE the container at a different inode.** `chown 999:999 /mnt/data/u1001/postgres` does nothing when the actual volume is `aip-u1001_postgres-data` mounted at `/var/lib/postgresql/data` inside the container.

4. **Dify migration failures.** `dify-api` runs `flask db upgrade` on startup. If the `dify` database doesn't exist yet when it starts, it crashes and enters a restart loop. The script creates the database but only AFTER starting the group that includes dify-api.

5. **AnythingLLM fails because it requires a JWT_SECRET and STORAGE_DIR at startup** — if these are blank in `.env`, it crashes immediately.

6. **n8n fails because it requires `N8N_ENCRYPTION_KEY`** — if not set, n8n refuses to start.

7. **The compose file uses `${TENANT_DIR}` in volume definitions but the `.env` file written by script 1 may write `TENANT_DIR` with a trailing slash or wrong path separator**, causing Docker to create directories like `/mnt/data/u1001//postgres`.

8. **Signal-CLI image `0.84` does not exist on Docker Hub for linux/amd64** as a working binary — it exists as a manifest but the actual layer fails to run. The correct working tag is `0.57` or `latest` with `MODE=json`.

---

# The Correct Architecture

Stop fighting Docker Compose. Use it properly:

```
Phase 0: Validate (.env complete, compose file valid, clean state)
Phase 1: docker compose up -d postgres redis qdrant minio
         (WITH --no-deps=false so compose waits for depends_on)
Phase 2: Wait with proper health checks (pg_isready, redis-cli ping)
Phase 3: Create databases inside postgres NOW (before any app starts)
Phase 4: docker compose up -d n8n flowise anythingllm ollama
Phase 5: docker compose up -d dify-api dify-worker dify-web (if defined)
Phase 6: docker compose up -d nginx (last)
Phase 7: Status report
```

**Key change:** Remove `--no-deps` from all `up` calls. Let compose handle dependency ordering. The group separation is only for our health check timing — compose itself is not bypassed.

---

# Complete Instructions for Windsurf

## CRITICAL: Read This First

```
These instructions assume the following about the current codebase:
- Scripts 0,1,2,3,4 exist at scripts/
- docker-compose.yml exists at repo root
- .env is written by script 1 to ${DATA_ROOT}/${TENANT_NAME}/.env

Do NOT preserve any existing logic in script 2 — replace it entirely.
The current logic is architecturally broken and cannot be fixed incrementally.
```

---

## COMMIT 1 — `docker-compose.yml` — This must be fixed first

```
TASK: Fix docker-compose.yml. This is the root cause of most failures.
Make ALL of these changes. Do not skip any.
```

### 1a — Top-level networks block must be exactly this

```yaml
networks:
  net_internal:
    driver: bridge
  net_default:
    driver: bridge
```

```
VERIFY: There must be NO occurrence of ${COMPOSE_PROJECT_NAME} in the 
networks: block. No manual network names. Short names only.
Docker Compose automatically prefixes them with the project name.

grep "COMPOSE_PROJECT_NAME" docker-compose.yml | grep "networks:"
Must return EMPTY.
```

### 1b — Top-level volumes block must list ALL named volumes

```yaml
volumes:
  postgres-data:
  redis-data:
  qdrant-data:
  minio-data:
  n8n-data:
  flowise-data:
  anythingllm-data:
  ollama-data:
  dify-storage-data:
  signal-data:
```

```
VERIFY: Every volume reference in services must match a name here.
docker compose --env-file /mnt/data/u1001/.env config --quiet
Must exit 0.
```

### 1c — Postgres service must have healthcheck AND correct volume

```yaml
  postgres:
    image: pgvector/pgvector:pg16
    container_name: ${COMPOSE_PROJECT_NAME}-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB:-postgres}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - net_internal
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-postgres}"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s
```

```
CRITICAL: The volume must be postgres-data (named volume), NOT:
  - ${TENANT_DIR}/postgres:/var/lib/postgresql/data  ← WRONG
  - ./data/postgres:/var/lib/postgresql/data         ← WRONG
Named volumes do not have permission problems. Bind mounts do.
```

### 1d — Redis service must have healthcheck

```yaml
  redis:
    image: redis:7-alpine
    container_name: ${COMPOSE_PROJECT_NAME}-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD} --maxmemory 512mb --maxmemory-policy allkeys-lru
    volumes:
      - redis-data:/data
    networks:
      - net_internal
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a ${REDIS_PASSWORD} ping | grep PONG"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 10s
```

### 1e — Qdrant service must have healthcheck

```yaml
  qdrant:
    image: qdrant/qdrant:latest
    container_name: ${COMPOSE_PROJECT_NAME}-qdrant
    restart: unless-stopped
    volumes:
      - qdrant-data:/qdrant/storage
    networks:
      - net_internal
    ports:
      - "${QDRANT_PORT:-6333}:6333"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:6333/healthz || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 8
      start_period: 20s
```

### 1f — n8n service must have depends_on with condition

```yaml
  n8n:
    image: n8nio/n8n:latest
    container_name: ${COMPOSE_PROJECT_NAME}-n8n
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: ${COMPOSE_PROJECT_NAME}-postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: n8n
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      WEBHOOK_URL: ${N8N_WEBHOOK_URL:-http://localhost:5678}
      N8N_HOST: 0.0.0.0
      N8N_PORT: 5678
    volumes:
      - n8n-data:/home/node/.n8n
    networks:
      - net_internal
      - net_default
    ports:
      - "${N8N_PORT:-5678}:5678"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:5678/healthz || exit 1"]
      interval: 20s
      timeout: 10s
      retries: 8
      start_period: 60s
```

### 1g — Dify services must depend on postgres AND redis being healthy

```yaml
  dify-api:
    image: langgenius/dify-api:latest
    container_name: ${COMPOSE_PROJECT_NAME}-dify-api
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      MODE: api
      SECRET_KEY: ${DIFY_SECRET_KEY}
      DB_USERNAME: ${POSTGRES_USER}
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: ${COMPOSE_PROJECT_NAME}-postgres
      DB_PORT: 5432
      DB_DATABASE: dify
      REDIS_HOST: ${COMPOSE_PROJECT_NAME}-redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      STORAGE_TYPE: local
      STORAGE_LOCAL_PATH: /app/api/storage
      VECTOR_STORE: qdrant
      QDRANT_URL: http://${COMPOSE_PROJECT_NAME}-qdrant:6333
    volumes:
      - dify-storage-data:/app/api/storage
    networks:
      - net_internal
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:5001/health || exit 1"]
      interval: 30s
      timeout: 15s
      retries: 10
      start_period: 120s
```

### 1h — Signal service must use profiles and correct image

```yaml
  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    platform: linux/amd64
    container_name: ${COMPOSE_PROJECT_NAME}-signal-api
    restart: unless-stopped
    environment:
      MODE: json
      PORT: ${SIGNAL_PORT:-8085}
    volumes:
      - signal-data:/home/.local/share/signal-cli
    networks:
      - net_internal
    ports:
      - "${SIGNAL_PORT:-8085}:${SIGNAL_PORT:-8085}"
    profiles:
      - signal
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:${SIGNAL_PORT:-8085}/v1/about || exit 1"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 90s
```

```
CRITICAL: The profiles: [signal] line means signal-api ONLY starts when 
explicitly requested. This prevents it from being included in the default
`docker compose up` and crashing the entire deployment.

VERIFY after all changes:
  docker compose --env-file /path/to/.env config --quiet
  Exit code must be 0. Zero warnings about undefined variables.
  
  docker compose --env-file /path/to/.env config --services
  Must list services cleanly without error.
```

---

## COMMIT 2 — `scripts/1-setup-system.sh` — Ensure ALL variables are written to .env

```
TASK: Find the section of 1-setup-system.sh that writes the .env file.
Ensure ALL of these variables are present. Add any that are missing.
```

The `.env` write block must include at minimum:

```bash
# In the write-env-file section of 1-setup-system.sh,
# ensure these exact lines exist (add missing ones):

cat >> "$ENV_FILE" << EOF

# ── Core Identity ─────────────────────────────────────────────
COMPOSE_PROJECT_NAME=${PROJECT_NAME}
DATA_ROOT=${DATA_ROOT}
TENANT_DIR=${DATA_ROOT}/${TENANT_NAME}
TENANT_NAME=${TENANT_NAME}

# ── PostgreSQL ────────────────────────────────────────────────
POSTGRES_USER=aip_user
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=postgres

# ── Redis ─────────────────────────────────────────────────────
REDIS_PASSWORD=${REDIS_PASSWORD}

# ── Service Ports ─────────────────────────────────────────────
N8N_PORT=${N8N_PORT:-5678}
FLOWISE_PORT=${FLOWISE_PORT:-3000}
ANYTHINGLLM_PORT=${ANYTHINGLLM_PORT:-3001}
OLLAMA_PORT=${OLLAMA_PORT:-11434}
QDRANT_PORT=${QDRANT_PORT:-6333}
MINIO_PORT=${MINIO_PORT:-9000}
MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT:-9001}
DIFY_PORT=${DIFY_PORT:-5001}
DIFY_WEB_PORT=${DIFY_WEB_PORT:-3002}
SIGNAL_PORT=${SIGNAL_PORT:-8085}

# ── Service Secrets ───────────────────────────────────────────
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
FLOWISE_PASSWORD=${FLOWISE_PASSWORD}
ANYTHINGLLM_JWT_SECRET=${ANYTHINGLLM_JWT_SECRET}
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
DIFY_SECRET_KEY=${DIFY_SECRET_KEY}

# ── Optional Services ─────────────────────────────────────────
ENABLE_SIGNAL=false
TAILSCALE_AUTH_KEY=
TAILSCALE_EXTRA_ARGS=

# ── Webhook / External URLs ───────────────────────────────────
N8N_WEBHOOK_URL=https://${DOMAIN}/n8n
DOMAIN=${DOMAIN}
EOF
```

```
ALSO: Ensure all the *_PASSWORD, *_KEY, *_SECRET values are generated
randomly if not already set. The pattern to use:

generate_secret() {
  openssl rand -hex 32
}

# Only generate if not already set
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(generate_secret)}"
REDIS_PASSWORD="${REDIS_PASSWORD:-$(generate_secret)}"
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-$(generate_secret)}"
FLOWISE_PASSWORD="${FLOWISE_PASSWORD:-$(generate_secret)}"
ANYTHINGLLM_JWT_SECRET="${ANYTHINGLLM_JWT_SECRET:-$(generate_secret)}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-$(generate_secret)}"
DIFY_SECRET_KEY="${DIFY_SECRET_KEY:-$(generate_secret)}"

VERIFY:
  sudo ./1-setup-system.sh
  Then:
  grep "^N8N_ENCRYPTION_KEY=" /mnt/data/u1001/.env
  grep "^TENANT_DIR=" /mnt/data/u1001/.env
  grep "^ANYTHINGLLM_JWT_SECRET=" /mnt/data/u1001/.env
  grep "^DIFY_SECRET_KEY=" /mnt/data/u1001/.env
  ALL must return non-empty values. None can be empty after the = sign.
```

---

## COMMIT 3 — `scripts/2-deploy-services.sh` — Full Replacement

```
TASK: Replace the entire contents of scripts/2-deploy-services.sh
with the script below. Do not preserve any existing logic.
```

```bash
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
    "${REPO_ROOT}/.env" \
    "${SCRIPT_DIR}/../.env"; do
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
  sleep 3; ELAPSED=$((ELAPSED+3))
  [[ $ELAPSED -ge $MAX ]] && fail "PostgreSQL not ready after ${MAX}s"
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
until curl -sf "http://localhost:${QDRANT_PORT:-6333}/healthz" \
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
      "http://localhost:${DIFY_PORT:-5001}/health" >/dev/null 2>&1; do
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
```

---

## COMMIT 4 — `scripts/0-complete-cleanup.sh` — Fix volume removal

```
TASK: Replace the volume and network removal sections with the following.
Leave the rest of the script intact.
```

Find and replace the volume removal logic:

```bash
# ── Remove volumes ─────────────────────────────────────────────────────────
section "Removing Volumes"

# Named volumes created by compose have this label:
# com.docker.compose.project=${PROJECT_NAME}
# We use that label to find them reliably.

log "Removing volumes for project: ${PROJECT_NAME}"
VOLS="$(docker volume ls \
  --filter "label=com.docker.compose.project=${PROJECT_NAME}" \
  --format '{{.Name}}' 2>/dev/null || true)"

if [[ -n "$VOLS" ]]; then
  echo "$VOLS" | xargs -r docker volume rm -f 2>/dev/null && \
    ok "Removed $(echo "$VOLS" | wc -l) volumes" || \
    warn "Some volumes could not be removed (may be in use)"
else
  log "No volumes found for project ${PROJECT_NAME}"
fi

# Belt and braces: also remove by name prefix
docker volume ls --format '{{.Name}}' \
  | grep -E "^${PROJECT_NAME}[_-]" \
  | xargs -r docker volume rm -f 2>/dev/null || true

# Remove anonymous volumes
docker volume prune -f >/dev/null 2>&1 || true
ok "Volume cleanup complete"
```

Find and replace the network removal logic:

```bash
# ── Remove networks ────────────────────────────────────────────────────────
section "Removing Networks"

log "Removing networks for project: ${PROJECT_NAME}"
NETS="$(docker network ls \
  --filter "label=com.docker.compose.project=${PROJECT_NAME}" \
  --format '{{.Name}}' 2>/dev/null || true)"

# Also get networks by name prefix (catches unlabelled stale networks)
NETS_PREFIX="$(docker network ls --format '{{.Name}}' \
  | grep -E "^${PROJECT_NAME}[_-]" || true)"

ALL_NETS="$(echo -e "${NETS}\n${NETS_PREFIX}" | sort -u | grep -v '^$' || true)"

if [[ -n "$ALL_NETS" ]]; then
  while IFS= read -r net; do
    [[ -z "$net" ]] && continue
    log "  Removing network: ${net}"
    # Disconnect all containers first
    CONNECTED="$(docker network inspect "$net" \
      --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || true)"
    for c in $CONNECTED; do
      docker network disconnect -f "$net" "$c" 2>/dev/null || true
    done
    docker network rm "$net" 2>/dev/null || true
  done <<< "$ALL_NETS"
  ok "Network cleanup complete"
else
  log "No networks found for project ${PROJECT_NAME}"
fi
```

---

## Pre-Test Cleanup — Run Before First Test of New Scripts

```bash
# WINDSURF: Run this ONCE to clear all state before testing
# Adjust PROJECT_NAME if different

PROJECT="aip-u1001"

echo "=== Stopping all containers for ${PROJECT} ==="
docker ps -aq --filter "name=${PROJECT}" | xargs -r docker rm -f 2>/dev/null || true

echo "=== Removing named volumes ==="
docker volume ls \
  --filter "label=com.docker.compose.project=${PROJECT}" \
  --format '{{.Name}}' | xargs -r docker volume rm -f 2>/dev/null || true

docker volume ls --format '{{.Name}}' | grep "^${PROJECT}" \
  | xargs -r docker volume rm -f 2>/dev/null || true

echo "=== Removing networks ==="
docker network ls --format '{{.Name}}' | grep "^${PROJECT}" \
  | while read -r net; do
      docker network disconnect -f "$net" \
        $(docker network inspect "$net" \
          --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null) \
        2>/dev/null || true
      docker network rm "$net" 2>/dev/null || true
    done

echo "=== Pruning anonymous volumes ==="
docker volume prune -f

echo "=== Verification — ALL must be empty ==="
docker ps -a --filter "name=${PROJECT}" --format '{{.Names}}'
docker volume ls | grep "${PROJECT}" || echo "(none)"
docker network ls | grep "${PROJECT}" || echo "(none)"
```

---

## Acceptance Criteria — Definition of 100% Success

```bash
# After running: sudo ./1-setup-system.sh && sudo ./2-deploy-services.sh

# 1. No warnings about missing variables
docker compose --env-file /mnt/data/u1001/.env config --quiet
# Exit code 0, zero output

# 2. All core containers running and healthy
docker ps --filter "name=aip-u1001" \
  --format "table {{.Names}}\t{{.Status}}" | sort
# Every line: "Up X minutes" or "Up X minutes (healthy)"
# Zero lines with "Restarting" or "Exited"

# 3. PostgreSQL accepting connections
docker exec aip-u1001-postgres \
  psql -U aip_user -c "\l" | grep -E "n8n|flowise|dify"
# Must show all three databases

# 4. n8n accessible
curl -sf http://localhost:5678/healthz && echo "n8n OK"

# 5. No network label errors
docker network ls | grep aip-u1001
# Must show networks WITH proper labels (not blank)
docker network inspect aip-u1001_net_internal \
  --format '{{index .Labels "com.docker.compose.project"}}'
# Must print: aip-u1001
```

---

## Summary Table

| Commit | File | Root Cause Fixed |
|--------|------|-----------------|
| 1 | `docker-compose.yml` | Missing healthchecks prevent `depends_on condition:service_healthy` from working; bad network names cause label conflicts; bind mounts cause permission errors; signal image wrong |
| 2 | `1-setup-system.sh` | Missing variables in .env cause blank substitution warnings and app startup failures (n8n needs N8N_ENCRYPTION_KEY, AnythingLLM needs JWT_SECRET) |
| 3 | `2-deploy-services.sh` | `--no-deps` bypasses compose dependency resolution; health checks use wrong methods; databases created after apps start; phases not in dependency order |
| 4 | `0-complete-cleanup.sh` | Named volumes not removed (prune only removes anonymous volumes); networks not found by label |