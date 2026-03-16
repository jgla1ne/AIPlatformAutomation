# AI Platform — Final Implementation Blueprint
**For Windsurf. This is the last blueprint. Read it fully before touching any file.**

---

## What Actually Went Wrong (The Real Root Causes)

After reading all scripts, logs, prior Claude recommendations, Windsurf summaries, and the comprehensive analysis, here is what is actually broken — not symptoms, but causes:

### Root Cause 1: The .env variables are inconsistent across scripts
Script 1 writes `POSTGRES_DB=aiplatform` / `POSTGRES_USER=aiplatform` but the live tenant was deployed with `POSTGRES_DB=datasquiz_ai` / `POSTGRES_USER=ds-admin`. Script 3 still references `/opt/ai-platform/.env` which no longer matches the live path. Every downstream service (LiteLLM, OpenWebUI) inherits whichever broken value lands first.

### Root Cause 2: The postgres init script does not honour the env variables
The `init.sql` generated in Script 1 hardcodes role names and schema names. When the user overrides `POSTGRES_USER` or `POSTGRES_DB` at collection time, the init script is not regenerated to match. Result: PostgreSQL starts fine but the database the services try to connect to was never created under the right name/user.

### Root Cause 3: Script 2 cannot find the compose file
Script 2 looks for `docker-compose.yml` at `/home/$REAL_USER/ai-platform/deployment/stack/` but Script 1 writes it to `/opt/ai-platform/`. The `service_exists()` function therefore always returns false, and `deploy_group()` silently skips every service.

### Root Cause 4: Script 3 is a stub
Script 3 defines `main()` but never calls it. `GREEN` is undefined. The GDrive function runs unconditionally even when `GDRIVE_CLIENT_ID` is empty, hitting `set -euo pipefail` and exiting before configuring LiteLLM. Nothing gets configured.

### Root Cause 5: LiteLLM uses the wrong database
`LITELLM_DATABASE_URL` in the .env resolves to the main `aiplatform` or `datasquiz_ai` database — LiteLLM runs Prisma migrations and needs its **own dedicated database** (`litellm`). When it shares a database that has no Prisma schema, Prisma's query engine panics.

### Root Cause 6: No database provisioning step exists in the pipeline
Script 2 deploys postgres and then immediately tries to deploy LiteLLM. There is no step that waits for postgres to be healthy, then creates the per-service databases (`litellm`, `openwebui`, `n8n`) with the correct owner. LiteLLM and OpenWebUI migrations therefore always fail on a fresh deploy.

---

## The Correct Architecture (Non-Negotiable)

```
Script 1: collect → write .env → write all configs from .env → done
Script 2: read .env → start infra → provision DBs → start services → done  
Script 3: mission control library; each function is idempotent; callable standalone
```

**All paths resolve to `/mnt/data/${TENANT}`.**
**`/opt/ai-platform/.env` is the single env file.**
**Script 3 is sourced by Scripts 1 and 2, not the reverse.**

---

## Complete Fix Specification

### Fix 1 — Script 1: Collect tenant name and derive ALL paths from it

At the very top of `main()`, before any other variable is set:

```bash
# Collect tenant identity FIRST
if [ -z "${TENANT:-}" ]; then
    read -p "Tenant ID (e.g. datasquiz, no spaces): " TENANT_NAME
    TENANT_NAME="${TENANT_NAME// /_}"   # sanitise
else
    TENANT_NAME="${TENANT}"
fi

# ALL paths derive from this single variable — no exceptions
DATA_ROOT="/mnt/data/${TENANT_NAME}"
BASE_DIR="/opt/ai-platform"
CONFIG_DIR="${DATA_ROOT}/configs"
DATA_DIR="${DATA_ROOT}/data"
LOGS_DIR="${DATA_ROOT}/logs"
COMPOSE_FILE="${DATA_ROOT}/docker-compose.yml"
ENV_FILE="${BASE_DIR}/.env"
```

The `generate_env_file()` function must write **exactly** these variable names so every downstream consumer can `source "$ENV_FILE"` and get consistent paths.

### Fix 2 — Script 1: The .env must be written in dependency order (primitives first)

The generated `.env` must follow this exact ordering. Derived variables must only reference variables that were already written above them in the same file:

```bash
# SECTION 1 — Identity (no dependencies)
TENANT=<tenant_name>
DOMAIN=<base_domain>
ADMIN_EMAIL=<email>
TENANT_UID=<real_uid>
TENANT_GID=<real_gid>

# SECTION 2 — Paths (depend only on TENANT)
DATA_ROOT=/mnt/data/${TENANT}
BASE_DIR=/opt/ai-platform
CONFIG_DIR=${DATA_ROOT}/configs
DATA_DIR=${DATA_ROOT}/data
LOGS_DIR=${DATA_ROOT}/logs
COMPOSE_FILE=${DATA_ROOT}/docker-compose.yml

# SECTION 3 — Database primitives (no dependencies on other DB vars)
POSTGRES_DB=<value_from_user_or_default_aiplatform>
POSTGRES_USER=<value_from_user_or_default_aiplatform>
POSTGRES_PASSWORD=<generated>
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_UID=70
REDIS_PASSWORD=<generated>
REDIS_UID=999

# SECTION 4 — Derived connection strings (depend on Section 3 primitives)
# CRITICAL: These use literal values, NOT shell variable expansion
# They must be written with the actual resolved values, not ${VAR} references
# because Docker Compose will re-expand them and they must be stable
LITELLM_DATABASE_URL=postgresql://<POSTGRES_USER>:<POSTGRES_PASSWORD>@postgres:5432/litellm
OPENWEBUI_DATABASE_URL=postgresql://<POSTGRES_USER>:<POSTGRES_PASSWORD>@postgres:5432/openwebui
N8N_DATABASE_URL=postgresql://<POSTGRES_USER>:<POSTGRES_PASSWORD>@postgres:5432/n8n
REDIS_URL=redis://:<REDIS_PASSWORD>@redis:6379
DATABASE_URL=postgresql://<POSTGRES_USER>:<POSTGRES_PASSWORD>@postgres:5432/litellm

# SECTION 5 — Service secrets
ADMIN_PASSWORD=<generated>
JWT_SECRET=<generated>
ENCRYPTION_KEY=<generated>
LITELLM_MASTER_KEY=<resolved_JWT_SECRET_value>
LITELLM_SALT_KEY=<resolved_ENCRYPTION_KEY_value>
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<resolved_ADMIN_PASSWORD_value>

# SECTION 6 — API keys (empty if not provided)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GEMINI_API_KEY=
GROQ_API_KEY=
OPENROUTER_API_KEY=

# SECTION 7 — Service flags
ENABLE_LITELLM=true
ENABLE_OLLAMA=true
ENABLE_OPENWEBUI=true
ENABLE_QDRANT=false
ENABLE_N8N=false
ENABLE_FLOWISE=false
ENABLE_MONITORING=true
ENABLE_TAILSCALE=false

# SECTION 8 — Ports
PORT_LITELLM=4000
PORT_OPENWEBUI=3000
PORT_N8N=5678
PORT_FLOWISE=3001
PORT_GRAFANA=3002
PORT_PROMETHEUS=9090
PORT_QDRANT=6333
PORT_OLLAMA=11434
```

**CRITICAL IMPLEMENTATION NOTE**: Sections 4 and 5 must be written by resolving variables in bash at write time using the already-set bash variables. Do NOT write `LITELLM_DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@...` in the heredoc because `${POSTGRES_PASSWORD}` will be expanded when the heredoc is evaluated — this is the correct behaviour and what you want. Confirm by checking that the written file shows the literal password string, not `${POSTGRES_PASSWORD}`.

### Fix 3 — Script 1: The postgres init script must honour the collected variables

Replace `generate_postgres_init()` entirely. The init script must create per-service databases and the correct role using the same `POSTGRES_USER` and `POSTGRES_PASSWORD` that were collected:

```bash
generate_postgres_init() {
    mkdir -p "${CONFIG_DIR}/postgres"
    
    # Write init script with variables resolved at generation time
    cat > "${CONFIG_DIR}/postgres/init-all-databases.sh" <<INITEOF
#!/usr/bin/env bash
set -e

# This file was generated by 1-setup-system.sh
# It runs once when the postgres container first starts

PG_USER="${POSTGRES_USER}"
PG_PASS="${POSTGRES_PASSWORD}"

psql -v ON_ERROR_STOP=1 --username "\$PG_USER" --dbname "postgres" <<EOSQL

  -- Ensure the platform role exists (idempotent)
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${POSTGRES_USER}') THEN
      CREATE ROLE ${POSTGRES_USER} WITH LOGIN PASSWORD '${POSTGRES_PASSWORD}';
    END IF;
  END \$\$;

  -- Create per-service databases (idempotent)
  SELECT 'CREATE DATABASE litellm   OWNER ${POSTGRES_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='litellm')   \gexec

  SELECT 'CREATE DATABASE openwebui OWNER ${POSTGRES_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='openwebui') \gexec

  SELECT 'CREATE DATABASE n8n       OWNER ${POSTGRES_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='n8n')       \gexec

  SELECT 'CREATE DATABASE flowise   OWNER ${POSTGRES_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='flowise')   \gexec

  -- Grant all privileges
  GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB}  TO ${POSTGRES_USER};
  GRANT ALL PRIVILEGES ON DATABASE litellm          TO ${POSTGRES_USER};
  GRANT ALL PRIVILEGES ON DATABASE openwebui        TO ${POSTGRES_USER};
  GRANT ALL PRIVILEGES ON DATABASE n8n              TO ${POSTGRES_USER};
  GRANT ALL PRIVILEGES ON DATABASE flowise          TO ${POSTGRES_USER};

EOSQL
INITEOF

    chmod +x "${CONFIG_DIR}/postgres/init-all-databases.sh"
    chown "${REAL_UID}:${REAL_GID}" "${CONFIG_DIR}/postgres/init-all-databases.sh"
    log_success "Postgres init script written — creates all service databases"
}
```

The compose service for postgres must mount this file:
```yaml
volumes:
  - ${CONFIG_DIR}/postgres/init-all-databases.sh:/docker-entrypoint-initdb.d/init-all-databases.sh:ro
```

**CRITICAL**: The `/docker-entrypoint-initdb.d/` directory only runs scripts on first container start (when the data directory is empty). On re-deploys this is idempotent because the scripts won't re-run. If the data directory exists, postgres skips init scripts entirely.

### Fix 4 — Script 1: Generate a real compose file, not a placeholder

The current `generate_docker_compose()` writes a placeholder service and nothing else. Replace it with a function that writes real service definitions based on the `ENABLE_*` flags that were just collected.

The compose file must:
- Always write the `postgres` and `redis` services (they are always required)
- Write conditional services only when `ENABLE_X=true`
- Use `${VAR}` references for all values — never hardcoded strings
- Mount the postgres init script correctly
- Use the correct healthcheck for qdrant (`/collections`, not `/health`)
- Give litellm a `start_period` of 90 seconds (Prisma migration takes time)

**Postgres service** (always written):
```yaml
  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    user: "${POSTGRES_UID:-70}:${TENANT_GID:-1001}"
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
      - ${CONFIG_DIR}/postgres/init-all-databases.sh:/docker-entrypoint-initdb.d/init-all-databases.sh:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
```

**Redis service** (always written):
```yaml
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    user: "${REDIS_UID:-999}:${TENANT_GID:-1001}"
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
    volumes:
      - ${DATA_DIR}/redis:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5
```

**LiteLLM service** (written when `ENABLE_LITELLM=true`):
```yaml
  litellm:
    image: ghcr.io/berriai/litellm:main
    restart: unless-stopped
    user: "root"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      LITELLM_SALT_KEY: ${LITELLM_SALT_KEY}
      DATABASE_URL: ${LITELLM_DATABASE_URL}
      REDIS_URL: ${REDIS_URL}
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      OPENAI_API_KEY: ${OPENAI_API_KEY:-}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}
      GROQ_API_KEY: ${GROQ_API_KEY:-}
      STORE_MODEL_IN_DB: "True"
      LITELLM_TELEMETRY: "False"
      PRISMA_DISABLE_WARNINGS: "true"
    volumes:
      - ${CONFIG_DIR}/litellm/config.yaml:/app/config.yaml:ro
      - ${DATA_DIR}/litellm:/root/.cache
    ports:
      - "${PORT_LITELLM:-4000}:4000"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:4000/health/liveliness || exit 1"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 90s
```

Note: LiteLLM runs as `root` because its Prisma binary writes to `/root/.cache`. This is the pragmatic choice. The cache volume is mounted to a tenant-owned directory so data is persisted. The `start_period: 90s` is mandatory — Prisma migration takes 45-75 seconds on first run.

**OpenWebUI service** (written when `ENABLE_OPENWEBUI=true`):
```yaml
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      OPENAI_API_BASE_URL: "http://litellm:4000/v1"
      OPENAI_API_KEY: "${LITELLM_MASTER_KEY}"
      WEBUI_SECRET_KEY: "${JWT_SECRET}"
      DATABASE_URL: "${OPENWEBUI_DATABASE_URL}"
      VECTOR_DB: "qdrant"
      QDRANT_URI: "http://qdrant:6333"
    volumes:
      - ${DATA_DIR}/openwebui:/app/backend/data
    ports:
      - "${PORT_OPENWEBUI:-3000}:8080"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8080/api/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
```

Do NOT add `depends_on: litellm: condition: service_healthy` for OpenWebUI. OpenWebUI can start without LiteLLM being ready and will reconnect. The hard dependency on LiteLLM health was causing cascade failures.

**Qdrant service** (written when `ENABLE_QDRANT=true`):
```yaml
  qdrant:
    image: qdrant/qdrant:latest
    restart: unless-stopped
    user: "1000:${TENANT_GID:-1001}"
    volumes:
      - ${DATA_DIR}/qdrant:/qdrant/storage
      - ${DATA_DIR}/qdrant/snapshots:/qdrant/snapshots
    ports:
      - "${PORT_QDRANT:-6333}:6333"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:6333/collections || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 30s
```

**Caddy service** (always written):
```yaml
  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "2019:2019"
    volumes:
      - ${CONFIG_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ${CONFIG_DIR}/caddy/data:/data
      - ${CONFIG_DIR}/caddy/config:/config
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:2019/metrics > /dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
```

**Ollama service** (written when `ENABLE_OLLAMA=true`):
```yaml
  ollama:
    image: ollama/ollama:latest
    restart: unless-stopped
    environment:
      OLLAMA_HOST: 0.0.0.0
      OLLAMA_MODELS: ${DATA_DIR}/ollama
    volumes:
      - ${DATA_DIR}/ollama:/root/.ollama
    ports:
      - "${PORT_OLLAMA:-11434}:11434"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:11434/ || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
```

For GPU: add the appropriate `deploy.resources.reservations.devices` section based on `GPU_TYPE` and `GPU_COUNT` detected in the preflight.

**Monitoring services** (written when `ENABLE_MONITORING=true`):
```yaml
  prometheus:
    image: prom/prometheus:latest
    restart: unless-stopped
    user: "65534:65534"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
    volumes:
      - ${CONFIG_DIR}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ${DATA_DIR}/prometheus:/prometheus
    ports:
      - "${PORT_PROMETHEUS:-9090}:9090"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:9090/-/healthy || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  grafana:
    image: grafana/grafana:latest
    restart: unless-stopped
    user: "472:472"
    environment:
      GF_SECURITY_ADMIN_USER: ${GRAFANA_ADMIN_USER:-admin}
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_SERVER_ROOT_URL: "https://grafana.${DOMAIN}"
      GF_ANALYTICS_REPORTING_ENABLED: "false"
    volumes:
      - ${DATA_DIR}/grafana/data:/var/lib/grafana
      - ${DATA_DIR}/grafana/logs:/var/log/grafana
    ports:
      - "${PORT_GRAFANA:-3002}:3000"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:3000/api/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 45s
```

### Fix 5 — Script 1: UID-Aware directory ownership

The `create_directory_structure()` function must set ownership to match the UID that each container runs as. This prevents the permission failures seen with qdrant, grafana, and prometheus:

```bash
create_directory_structure() {
    # Create all dirs
    mkdir -p \
        "${DATA_DIR}/postgres" \
        "${DATA_DIR}/redis" \
        "${DATA_DIR}/qdrant/snapshots" \
        "${DATA_DIR}/ollama" \
        "${DATA_DIR}/openwebui" \
        "${DATA_DIR}/n8n" \
        "${DATA_DIR}/flowise" \
        "${DATA_DIR}/litellm" \
        "${DATA_DIR}/grafana/data" \
        "${DATA_DIR}/grafana/logs" \
        "${DATA_DIR}/prometheus" \
        "${CONFIG_DIR}/litellm" \
        "${CONFIG_DIR}/postgres" \
        "${CONFIG_DIR}/caddy/data" \
        "${CONFIG_DIR}/caddy/config" \
        "${CONFIG_DIR}/prometheus" \
        "${LOGS_DIR}"

    # Set ownership to match container UIDs exactly
    chown -R 70:"${REAL_GID}"     "${DATA_DIR}/postgres"
    chown -R 999:"${REAL_GID}"    "${DATA_DIR}/redis"
    chown -R 1000:"${REAL_GID}"   "${DATA_DIR}/qdrant"
    chown -R 472:472              "${DATA_DIR}/grafana"
    chown -R 65534:65534          "${DATA_DIR}/prometheus"
    chown -R 1000:"${REAL_GID}"   \
        "${DATA_DIR}/litellm" \
        "${DATA_DIR}/n8n" \
        "${DATA_DIR}/flowise" \
        "${DATA_DIR}/openwebui" \
        "${DATA_DIR}/ollama"
    
    # Config dirs owned by the operator (readable by scripts)
    chown -R "${REAL_UID}:${REAL_GID}" "${CONFIG_DIR}"
    chown -R "${REAL_UID}:${REAL_GID}" "${LOGS_DIR}"
}
```

### Fix 6 — Script 2: Fix ALL path variables

Replace the entire top block of Script 2:

```bash
# ── Path Resolution — Single Source of Truth ──────────────────────────────
# Script 2 always loads .env first; all paths come from it.
BASE_DIR="/opt/ai-platform"
ENV_FILE="${BASE_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "ERROR: ${ENV_FILE} not found. Run 1-setup-system.sh first."
    exit 1
fi

set -a
source "${ENV_FILE}"
set +a

# Validate critical variables loaded from .env
for var in TENANT DATA_ROOT CONFIG_DIR DATA_DIR LOGS_DIR COMPOSE_FILE; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: ${var} is not set in ${ENV_FILE}"
        exit 1
    fi
done

LOG_FILE="${LOGS_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "${LOGS_DIR}"
```

The `POSSIBLE_ENV_PATHS` array and the `service_exists()` grep-based function must both be removed. Replace `service_exists()` with:

```bash
service_is_enabled() {
    local svc="$1"
    case "$svc" in
        litellm)   [[ "${ENABLE_LITELLM:-false}"   == "true" ]] ;;
        ollama)    [[ "${ENABLE_OLLAMA:-false}"    == "true" ]] ;;
        open-webui)[[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] ;;
        qdrant)    [[ "${ENABLE_QDRANT:-false}"    == "true" ]] ;;
        n8n)       [[ "${ENABLE_N8N:-false}"       == "true" ]] ;;
        flowise)   [[ "${ENABLE_FLOWISE:-false}"   == "true" ]] ;;
        prometheus|grafana) [[ "${ENABLE_MONITORING:-false}" == "true" ]] ;;
        *) return 1 ;;
    esac
}
```

### Fix 7 — Script 2: Add a database provisioning step between postgres startup and litellm startup

This is the most important fix for reliability on re-deploys. Add this function and call it before any LiteLLM or OpenWebUI startup:

```bash
provision_databases() {
    log_info "Provisioning per-service databases..."
    
    local max_wait=60
    local elapsed=0
    
    # Wait for postgres to accept connections
    until docker compose -f "${COMPOSE_FILE}" exec -T postgres \
        pg_isready -U "${POSTGRES_USER}" -q 2>/dev/null; do
        elapsed=$((elapsed + 5))
        if [[ $elapsed -ge $max_wait ]]; then
            log_error "PostgreSQL not ready after ${max_wait}s"
            exit 1
        fi
        log_info "Waiting for postgres... (${elapsed}s)"
        sleep 5
    done
    
    log_success "PostgreSQL is ready"
    
    # Create per-service databases (idempotent — safe to re-run)
    local databases=("litellm" "openwebui" "n8n" "flowise")
    for db in "${databases[@]}"; do
        local exists
        exists=$(docker compose -f "${COMPOSE_FILE}" exec -T postgres \
            psql -U "${POSTGRES_USER}" -tAc \
            "SELECT 1 FROM pg_database WHERE datname='${db}'" 2>/dev/null || echo "")
        
        if [[ "$exists" == "1" ]]; then
            log_info "Database '${db}' already exists — skipping"
        else
            log_info "Creating database '${db}'..."
            docker compose -f "${COMPOSE_FILE}" exec -T postgres \
                psql -U "${POSTGRES_USER}" \
                -c "CREATE DATABASE \"${db}\" OWNER \"${POSTGRES_USER}\";" \
                >> "${LOG_FILE}" 2>&1 \
                && log_success "Database '${db}' created" \
                || log_warning "Could not create '${db}' — may already exist"
        fi
    done
    
    log_success "Database provisioning complete"
}
```

Call order in Script 2's `main()`:
1. Start postgres + redis
2. Wait for postgres healthy
3. Call `provision_databases()`
4. Start litellm (if enabled)
5. Start ollama (if enabled)
6. Start open-webui (if enabled)
7. Start qdrant (if enabled)
8. Start caddy
9. Start monitoring stack

### Fix 8 — Script 3: Three mandatory fixes and call `main`

Script 3 must be rewritten as a proper mission control library. The minimal fixes to make it functional:

**Fix A — Define all colour variables at the top:**
```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'
```

**Fix B — Guard all optional operations:**
```bash
setup_gdrive_rclone() {
    [[ -n "${GDRIVE_CLIENT_ID:-}" ]] || { log_info "GDrive not configured — skipping"; return 0; }
    # ... rest of function
}

configure_tailscale() {
    [[ -n "${TAILSCALE_AUTH_KEY:-}" ]] || { log_info "Tailscale not configured — skipping"; return 0; }
    # ... rest of function
}
```

**Fix C — Fix the compose path reference:**
Replace any reference to `/opt/ai-platform/compose/docker-compose.yml` with `${COMPOSE_FILE}` which is loaded from the env.

**Fix D — Call main:**
The very last line of the file must be:
```bash
main "$@"
```

**Fix E — Source env at the top:**
```bash
BASE_DIR="/opt/ai-platform"
ENV_FILE="${BASE_DIR}/.env"
[[ -f "${ENV_FILE}" ]] && set -a && source "${ENV_FILE}" && set +a
```

---

## Deployment Order (Windsurf Must Implement This Exactly)

```
1-setup-system.sh
  ├─ collect tenant name → derive ALL paths
  ├─ collect domain, SSL, services, API keys
  ├─ generate_secrets()
  ├─ generate_env_file()        ← primitives first, derived strings resolved at write time
  ├─ create_directory_structure() ← UID-aware ownership
  ├─ create_docker_networks()
  ├─ generate_postgres_init()   ← honours POSTGRES_USER / POSTGRES_DB
  ├─ generate_litellm_config()  ← conditional on ENABLE_* and API key presence
  ├─ generate_caddyfile()       ← conditional blocks per enabled service
  ├─ generate_prometheus_config() ← only if ENABLE_MONITORING=true
  └─ generate_docker_compose()  ← real services, not placeholder

2-deploy-services.sh
  ├─ source /opt/ai-platform/.env (single source of truth)
  ├─ validate required env vars
  ├─ docker compose up -d postgres redis
  ├─ provision_databases()      ← BEFORE any app service starts
  ├─ [if ENABLE_OLLAMA] up -d ollama
  ├─ [if ENABLE_LITELLM] up -d litellm
  ├─ [if ENABLE_OPENWEBUI] up -d open-webui
  ├─ [if ENABLE_QDRANT] up -d qdrant
  ├─ up -d caddy
  └─ [if ENABLE_MONITORING] up -d prometheus grafana

3-configure-services.sh
  ├─ source /opt/ai-platform/.env
  ├─ configure_tailscale()      ← guarded: [[ -n TAILSCALE_AUTH_KEY ]]
  ├─ setup_gdrive_rclone()      ← guarded: [[ -n GDRIVE_CLIENT_ID ]]
  ├─ create_ingestion_systemd() ← guarded: [[ -n GDRIVE_CLIENT_ID ]]
  ├─ configure_litellm_routing() ← restarts litellm after writing config
  └─ main "$@"                  ← CALLED AT END OF FILE
```

---

## Validation Checklist (Windsurf Must Verify These Before Committing)

Run these manually to confirm the fix is correct:

```bash
# 1. .env is readable and has correct values
grep "POSTGRES_USER\|POSTGRES_DB\|LITELLM_DATABASE_URL\|COMPOSE_FILE" /opt/ai-platform/.env

# 2. Compose file exists at the path referenced in .env
source /opt/ai-platform/.env && ls -la "${COMPOSE_FILE}"

# 3. Postgres init script exists and has variables resolved
cat /mnt/data/<tenant>/configs/postgres/init-all-databases.sh | head -20

# 4. LiteLLM config exists
ls -la /mnt/data/<tenant>/configs/litellm/config.yaml

# 5. Caddyfile exists and only has enabled services
cat /mnt/data/<tenant>/configs/caddy/Caddyfile

# 6. After deploying: all per-service databases exist
docker compose exec postgres psql -U aiplatform -c "\l" | grep -E "litellm|openwebui|n8n"

# 7. LiteLLM eventually reports healthy (wait 90s)
curl -sf http://localhost:4000/health/liveliness && echo "OK"

# 8. Script 3 exits cleanly with no errors
bash -x scripts/3-configure-services.sh 2>&1 | tail -20
```

---

## What Windsurf Must NOT Do

- Do not re-architect the three-script structure. Fix it in place.
- Do not add a fourth "fix" or "patch" script. Fixes belong in the original scripts.
- Do not apply fixes only to the live machine without updating the scripts. The scripts ARE the deployment.
- Do not hardcode the tenant name, database name, or user. All of these come from `.env`.
- Do not write `main()` without calling it.
- Do not expand `${POSTGRES_PASSWORD}` inside heredocs using single-quote delimiters — use double-quote heredoc delimiters so bash resolves variables at write time.
- Do not add `depends_on: litellm: condition: service_healthy` to open-webui. It causes cascade failures.
- Do not use the `/health` endpoint for qdrant healthchecks — it returns 404. Use `/collections`.

---

## Summary of Files to Modify

| File | Changes Required |
|------|-----------------|
| `scripts/1-setup-system.sh` | Tenant collection at top; path derivation; UID-aware dirs; real compose generation; postgres init with vars; dependency-ordered .env |
| `scripts/2-deploy-services.sh` | Remove path guessing; source .env; use `service_is_enabled()`; add `provision_databases()` before app services |
| `scripts/3-configure-services.sh` | Add colour vars; guard optional functions; fix compose path; call `main "$@"` at end |

No new scripts are required. No structural changes beyond what is specified above. The architecture is sound — the implementation has gaps that are all enumerated here.