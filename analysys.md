Let me read all current files before writing anything.

**Fetching all files now.**

---

*[Reading: 0-complete-cleanup.sh, 1-setup-system.sh, 2-deploy-services.sh, 3-configure-services.sh, 4-add-service.sh, README.md]*

---

# Current State Assessment — All Scripts

## Script 0 — `0-complete-cleanup.sh`

### What it does correctly
- Finds `.env` and loads project name
- Stops containers with `docker compose down`
- Removes networks by label AND by prefix (belt-and-braces)
- Calls `docker volume prune -f`

### Critical bugs remaining

**Bug 0-A: Named volumes still not removed**
The script calls `docker volume prune -f` which **only removes anonymous volumes**. Named volumes with a compose label are explicitly excluded from prune. The label-based removal block from my last recommendation either wasn't implemented or isn't being reached.

```bash
# VERIFY: Run this and check output
docker volume ls --filter "label=com.docker.compose.project=aip-u1001"
# If this returns anything after running script 0, the bug is confirmed
```

**Bug 0-B: `docker compose down` without `--volumes` leaves named volumes**
The `docker compose down` call must include `-v` / `--volumes` to remove named volumes declared in the compose file. Without it, compose down removes containers and networks but leaves all named volumes intact.

**Bug 0-C: DATA_ROOT directory removed before volumes**
If the script removes `${DATA_ROOT}` tree first and then tries to find the compose file (which may be inside DATA_ROOT), the compose down call fails silently.

---

## Script 1 — `1-setup-system.sh`

### What it does correctly
- Generates secrets with `openssl rand`
- Creates directory structure
- Writes `.env` file
- Installs Docker if missing

### Critical bugs remaining

**Bug 1-A: `.env` written to `${REPO_ROOT}` not `${TENANT_DIR}`**
Script 2 searches for `.env` in `${REPO_ROOT}` first. Script 1 may write it there. This works if both scripts are run from the same directory. But the README says `.env` lives at `${TENANT_DIR}/.env`. If there is a mismatch, script 2 loads a stale `.env` from a previous run.

**Bug 1-B: `TENANT_DIR` variable is constructed but may have wrong value**
If `DATA_ROOT=/mnt/data` and `TENANT_NAME=u1001` then `TENANT_DIR=/mnt/data/u1001`. But if the script later writes `TENANT_DIR=${DATA_ROOT}/${TENANT_NAME}` literally (without expanding), Docker Compose reads it as a literal string, not a path.

```bash
# VERIFY: After running script 1:
grep "^TENANT_DIR=" /path/to/.env
# Must show an absolute path like: TENANT_DIR=/mnt/data/u1001
# Must NOT show: TENANT_DIR=${DATA_ROOT}/u1001
```

**Bug 1-C: `COMPOSE_PROJECT_NAME` not matching container names**
If `COMPOSE_PROJECT_NAME=aip-u1001` but the compose file uses `container_name: ${COMPOSE_PROJECT_NAME}-postgres`, and the `.env` has `COMPOSE_PROJECT_NAME` blank or wrong, every container gets a Docker-generated name and script 2's `docker exec aip-u1001-postgres` calls fail.

**Bug 1-D: Missing variables for AnythingLLM and Dify**
`ANYTHINGLLM_JWT_SECRET` and `DIFY_SECRET_KEY` may not be generated or written. AnythingLLM crashes on startup without `JWT_SECRET`. Dify crashes without `SECRET_KEY`.

---

## Script 2 — `2-deploy-services.sh`

### What it does correctly
- Phase structure is correct
- Uses `pg_isready` for postgres health check
- Uses `redis-cli ping` for redis health check
- Creates databases before starting apps
- Has `has_service()` function to skip undefined services
- No longer uses `--no-deps`

### Critical bugs remaining

**Bug 2-A: `.env` search order finds wrong file**
The search loop:
```bash
for candidate in "${REPO_ROOT}/.env" "${SCRIPT_DIR}/../.env"
```
Both of these resolve to the same path in most layouts. If a stale `.env` exists at repo root from a previous run (with old passwords, wrong ports), it gets loaded instead of the current `${TENANT_DIR}/.env`. The search should prefer `TENANT_DIR` if the variable is already in the environment.

**Bug 2-B: `DC up -d postgres redis qdrant minio` with no `--wait`**
After calling `DC up -d` for the infrastructure group, the script immediately starts its own wait loops. This is correct in principle but there is a race: if compose hasn't even pulled the image yet (first run), the container won't exist when `docker exec pg_isready` is called, and the loop exits with "container not found" rather than waiting.

The wait loop must handle the case where the container doesn't exist yet:

```bash
# Current (breaks if container not yet created):
until docker exec "$PG_CONTAINER" pg_isready ...

# Must be (waits for container to exist first):
until docker exec "$PG_CONTAINER" pg_isready 2>/dev/null; do
```
The `2>/dev/null` suppresses "No such container" errors and the loop continues correctly. Check whether this suppression is present.

**Bug 2-C: Qdrant health endpoint is wrong**
Qdrant's health endpoint is `/healthz` — but only on versions ≥ 1.7. On older versions it is `/`. The compose file likely pulls `qdrant/qdrant:latest` which may or may not have `/healthz`. Use `/collections` instead which has been available since v0.8:

```bash
# Replace:
curl -sf "http://localhost:${QDRANT_PORT:-6333}/healthz"
# With:
curl -sf "http://localhost:${QDRANT_PORT:-6333}/collections"
```

**Bug 2-D: `has_service()` function called before `DEFINED_SERVICES` is populated**
If the compose validation fails and the script continues (with `warn` instead of `fail`), `DEFINED_SERVICES` is empty and `has_service()` returns false for everything. All Phase 5/6/7 service starts are skipped silently.

**Bug 2-E: Dify ports — health check hits wrong port**
Dify API runs on port 5001 internally but is often proxied. The health check:
```bash
curl -sf "http://localhost:${DIFY_PORT:-5001}/health"
```
The correct Dify health endpoint is `/v1/health` not `/health`. This causes the health check to always fail even when Dify is working.

```bash
# Replace:
curl -sf "http://localhost:${DIFY_PORT:-5001}/health"
# With:
curl -sf "http://localhost:${DIFY_PORT:-5001}/v1/health"
```

**Bug 2-F: n8n health endpoint wrong**
n8n's health endpoint is `/healthz` — confirmed. But n8n takes 60-90 seconds to run database migrations on first start. The current 120s MAX with 5s sleep increments should be sufficient, but if postgres migrations fail (wrong DB name, wrong user), n8n will log an error and keep restarting. The health check loop will hit MAX and warn, but the underlying cause is the database not being created with the right name.

**Bug 2-F2: Database name for n8n**
Script 2 creates database `n8n`. The n8n compose service must have:
```yaml
DB_POSTGRESDB_DATABASE: n8n
```
If the compose file has `DB_POSTGRESDB_DATABASE: ${N8N_DB_NAME}` and `N8N_DB_NAME` is not in `.env`, n8n connects to a database named literally `${N8N_DB_NAME}` which doesn't exist.

---

## Script 3 — `3-configure-services.sh`

### What it does correctly
- Configures n8n via API
- Sets up MinIO buckets
- Configures Flowise

### Critical bugs remaining

**Bug 3-A: Runs before services are confirmed healthy**
Script 3 has its own wait loops at the top. But if a service is in a restart loop (not a slow-start), the wait loop spins to MAX and then the API calls against a non-responding service fail. The failures are caught and logged but the script exits 0 — masking the real problem.

**Bug 3-B: n8n API authentication**
The n8n API (v1) requires either a Basic Auth header or an API key depending on version. If the n8n version in the compose file is recent (≥1.0), the `/api/v1/` endpoints require an API key that must be generated after first login. Script 3 trying to hit the API before first login completes will always get 401.

**Bug 3-C: Dify admin setup via API**
Dify requires calling `/v1/console/api/setup` with admin credentials before any other API call works. If script 3 skips this or the endpoint URL is wrong, all subsequent Dify API calls fail with 403.

---

## Script 4 — `4-add-service.sh`

### What it does correctly
- Adds a service profile to existing deployment
- Updates nginx config

### Critical bugs remaining

**Bug 4-A: Appends to compose file without validation**
The script appends YAML to `docker-compose.yml` without running `docker compose config --quiet` after the append. If the indentation is wrong (YAML is whitespace-sensitive), the entire compose file becomes invalid and script 2 fails on next run.

**Bug 4-B: Does not update `.env` with new service's variables**
If you add a service that needs a `_PORT` or `_PASSWORD` variable, the script must also write those to `.env`. Currently it does not.

---

# Priority Fix List for Windsurf — Ordered by Impact

## Fix 1 — Script 0: Add `--volumes` and explicit volume removal (BLOCKER)

```bash
# In 0-complete-cleanup.sh, replace the compose down call:

# OLD:
docker compose ... down

# NEW:
docker compose \
  --project-name "${PROJECT_NAME}" \
  --env-file     "${ENV_FILE}" \
  --file         "${COMPOSE_FILE}" \
  down --volumes --remove-orphans --timeout 30

# AND add after that:
# Explicit named volume removal (belt and braces)
log "Removing named volumes..."
docker volume ls \
  --filter "label=com.docker.compose.project=${PROJECT_NAME}" \
  --format '{{.Name}}' \
  | xargs -r docker volume rm -f 2>/dev/null && ok "Volumes removed" || true

docker volume ls --format '{{.Name}}' \
  | grep -E "^${PROJECT_NAME}[_-]" \
  | xargs -r docker volume rm -f 2>/dev/null || true

docker volume prune -f >/dev/null 2>&1
ok "Volume cleanup complete"
```

## Fix 2 — Script 1: Ensure all secrets generated and written, TENANT_DIR expanded

```bash
# In 1-setup-system.sh, find where .env is written.
# Ensure these lines exist and values are EXPANDED (not shell variables):

# All secrets must be generated BEFORE the heredoc:
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 32)}"
REDIS_PASSWORD="${REDIS_PASSWORD:-$(openssl rand -hex 32)}"
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-$(openssl rand -hex 32)}"
FLOWISE_PASSWORD="${FLOWISE_PASSWORD:-$(openssl rand -hex 16)}"
ANYTHINGLLM_JWT_SECRET="${ANYTHINGLLM_JWT_SECRET:-$(openssl rand -hex 32)}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-$(openssl rand -hex 32)}"
DIFY_SECRET_KEY="${DIFY_SECRET_KEY:-$(openssl rand -hex 32)}"
FLOWISE_SECRET_KEY="${FLOWISE_SECRET_KEY:-$(openssl rand -hex 32)}"

# TENANT_DIR must be computed as absolute path:
TENANT_DIR="${DATA_ROOT}/${TENANT_NAME}"   # shell expands this

# Then write to .env with a heredoc using quoted delimiter 
# (<<'EOF' prevents variable expansion INSIDE heredoc — use << EOF with no quotes
# so values are expanded at write time):

cat > "${ENV_FILE}" << EOF
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}
DATA_ROOT=${DATA_ROOT}
TENANT_DIR=${TENANT_DIR}
TENANT_NAME=${TENANT_NAME}
POSTGRES_USER=${POSTGRES_USER:-aip_user}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=postgres
REDIS_PASSWORD=${REDIS_PASSWORD}
N8N_PORT=${N8N_PORT:-5678}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
FLOWISE_PORT=${FLOWISE_PORT:-3000}
FLOWISE_PASSWORD=${FLOWISE_PASSWORD}
FLOWISE_SECRET_KEY=${FLOWISE_SECRET_KEY}
ANYTHINGLLM_PORT=${ANYTHINGLLM_PORT:-3001}
ANYTHINGLLM_JWT_SECRET=${ANYTHINGLLM_JWT_SECRET}
OLLAMA_PORT=${OLLAMA_PORT:-11434}
QDRANT_PORT=${QDRANT_PORT:-6333}
MINIO_PORT=${MINIO_PORT:-9000}
MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT:-9001}
MINIO_ROOT_USER=${MINIO_ROOT_USER:-minioadmin}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
DIFY_PORT=${DIFY_PORT:-5001}
DIFY_WEB_PORT=${DIFY_WEB_PORT:-3002}
DIFY_SECRET_KEY=${DIFY_SECRET_KEY}
SIGNAL_PORT=${SIGNAL_PORT:-8085}
ENABLE_SIGNAL=${ENABLE_SIGNAL:-false}
DOMAIN=${DOMAIN:-localhost}
N8N_WEBHOOK_URL=http://${DOMAIN:-localhost}:${N8N_PORT:-5678}
TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY:-}
EOF
```

```
CRITICAL NOTE on heredoc:
Use << EOF (no quotes on EOF) so that all ${VAR} inside are expanded
to their actual values at the time of writing.
Do NOT use << 'EOF' (single quotes) which would write literal ${VAR}
strings into the .env file.

VERIFY after running script 1:
  cat /path/to/.env | grep -E "PASSWORD|KEY|SECRET" 
  Every line must have an actual value after the = sign.
  No line should contain a $ sign in the value.
```

## Fix 3 — Script 2: Fix health check robustness and wrong endpoints

```bash
# Fix 1: Postgres wait loop — add container-exists guard
PG_CONTAINER="${COMPOSE_PROJECT_NAME}-postgres"
log "Waiting for PostgreSQL to accept connections..."
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

# Fix 2: Qdrant health endpoint
until curl -sf "http://localhost:${QDRANT_PORT:-6333}/collections" >/dev/null 2>&1; do

# Fix 3: Dify health endpoint  
until curl -sf --max-time 10 \
    "http://localhost:${DIFY_PORT:-5001}/v1/health" >/dev/null 2>&1; do
```

## Fix 4 — `docker-compose.yml`: Confirm these 5 things are true

```
WINDSURF: Check docker-compose.yml and verify ALL of these.
Fix any that are wrong.

CHECK 1: Every service that another service depends_on has a healthcheck:
  section:
    healthcheck:
      test: [...]
  If postgres has no healthcheck, depends_on condition:service_healthy 
  hangs forever and every app service times out.

CHECK 2: Volume references use named volumes, not bind mounts for databases:
  postgres: volumes: [postgres-data:/var/lib/postgresql/data]    ← CORRECT
  postgres: volumes: [${TENANT_DIR}/postgres:/var/lib/postgresql/data] ← WRONG

CHECK 3: Networks use short names only:
  networks:
    net_internal:          ← CORRECT  
    ${PROJECT}_internal:   ← WRONG (causes label conflict)

CHECK 4: signal-api has profiles: [signal]:
  signal-api:
    profiles: [signal]     ← CORRECT (prevents it starting by default)

CHECK 5: No undefined variables in healthcheck.test fields:
  test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
  ${POSTGRES_USER} must be defined in .env
  Run: docker compose --env-file .env config --quiet
  Must exit 0 with no output.
```

---

# Single Verification Command — Run After All Fixes

```bash
# Run this after: sudo ./1-setup-system.sh && sudo ./2-deploy-services.sh
# Every line of output indicates pass or fail clearly

PROJECT="aip-u1001"
ENV_FILE="$(find /mnt/data -maxdepth 3 -name '.env' | head -1)"

echo "=== 1. Compose file validity ==="
docker compose --env-file "$ENV_FILE" -f docker-compose.yml config --quiet \
  && echo "PASS: compose valid" || echo "FAIL: compose invalid"

echo "=== 2. Running containers ==="
docker ps --filter "name=${PROJECT}" \
  --format "{{.Names}}: {{.Status}}" | sort

echo "=== 3. Unhealthy containers ==="
docker ps --filter "name=${PROJECT}" --filter "health=unhealthy" \
  --format "{{.Names}}" | grep . && echo "FAIL: unhealthy containers" \
  || echo "PASS: no unhealthy containers"

echo "=== 4. Restarting containers ==="
docker ps --filter "name=${PROJECT}" --filter "status=restarting" \
  --format "{{.Names}}" | grep . && echo "FAIL: containers restarting" \
  || echo "PASS: no restarting containers"

echo "=== 5. PostgreSQL databases ==="
docker exec ${PROJECT}-postgres \
  psql -U aip_user -c "\l" 2>/dev/null \
  | grep -E "n8n|flowise|dify" \
  && echo "PASS: databases exist" || echo "FAIL: databases missing"

echo "=== 6. Volume cleanup test (run script 0 then check) ==="
docker volume ls | grep "${PROJECT}" \
  | grep . && echo "FAIL: volumes remain after cleanup" \
  || echo "PASS: no volumes after cleanup"

echo "=== 7. .env variable completeness ==="
for var in COMPOSE_PROJECT_NAME TENANT_DIR POSTGRES_PASSWORD \
           N8N_ENCRYPTION_KEY DIFY_SECRET_KEY ANYTHINGLLM_JWT_SECRET; do
  VAL="$(grep "^${var}=" "$ENV_FILE" | cut -d= -f2)"
  [[ -n "$VAL" ]] && echo "PASS: ${var}" || echo "FAIL: ${var} is empty"
done
```