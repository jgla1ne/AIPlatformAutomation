# Windsurf Instructions: Phase 3 — Fix Remaining Issues

## Context
System is now 75% functional. Three specific issues need fixing:
1. LiteLLM restart loop
2. Missing environment variables (TENANT, OPENWEBUI_DB_PASSWORD)
3. Missing database provisioning (ds-admin)

**Read before touching anything.**

---

## STEP 1: Read Current State First

```
Open and read these files completely before making any changes:
1. .env (current state)
2. docker-compose.yml OR the compose section in scripts/2-deploy-services.sh
3. scripts/3-configure-services.sh
4. Any litellm config file (config.yaml or similar in DATA_ROOT/litellm/)
5. Run mentally: what does the LiteLLM service definition look like right now?

Do not modify anything yet.
```

---

## STEP 2: Fix .env — Add Missing Variables

```
Open .env file.

Find or add these variables. 
For each one, use set_if_missing logic: 
  - If the variable EXISTS with a real value, do NOT overwrite it
  - If it is MISSING or EMPTY, add/fill it

# --- Missing critical variables ---

# TENANT: Used by Caddy/Authentik for domain/tenant routing
# Set to your domain name (same as DOMAIN value)
TENANT=${DOMAIN:-localhost}

# OPENWEBUI_DB_PASSWORD: Must match POSTGRES_PASSWORD or be its own credential
OPENWEBUI_DB_PASSWORD=$(grep "^POSTGRES_PASSWORD=" .env | cut -d'=' -f2)
# If POSTGRES_PASSWORD not found, generate:
# OPENWEBUI_DB_PASSWORD=$(openssl rand -hex 16)

# Azure OpenAI keys - currently MISSING, causing LiteLLM crash
# These must be real keys or LiteLLM must be reconfigured to not use Azure
AZURE_OPENAI_API_KEY_1=placeholder-replace-with-real-azure-key
AZURE_OPENAI_API_KEY_2=placeholder-replace-with-real-azure-key

# Add these if not present
LITELLM_MASTER_KEY=$(grep "^LITELLM_MASTER_KEY=" .env | cut -d'=' -f2 || openssl rand -hex 32)
LITELLM_SALT_KEY=$(grep "^LITELLM_SALT_KEY=" .env | cut -d'=' -f2 || openssl rand -hex 32)
DATABASE_URL=postgresql://$(grep "^POSTGRES_USER=" .env | cut -d'=' -f2):$(grep "^POSTGRES_PASSWORD=" .env | cut -d'=' -f2)@postgres:5432/litellm
```

### Task 2.1 — Create scripts/fix-env.sh to do this safely
```
Create NEW file scripts/fix-env.sh:

#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] .env file not found. Run scripts/3-configure-services.sh first."
  exit 1
fi

echo "[INFO] Auditing and fixing .env file..."

# Helper: add variable only if missing or empty
set_env_if_missing() {
  local key="$1"
  local value="$2"
  
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    local current
    current=$(grep "^${key}=" "$ENV_FILE" | cut -d'=' -f2-)
    if [[ -z "$current" ]] || [[ "$current" == "placeholder"* ]]; then
      echo "[UPDATE] $key was empty/placeholder, updating..."
      sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
      echo "[SKIP]   $key already set"
    fi
  else
    echo "[ADD]    $key"
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

# Load current .env to use existing values
source "$ENV_FILE" 2>/dev/null || true

# Fix TENANT
set_env_if_missing "TENANT" "${DOMAIN:-localhost}"

# Fix OPENWEBUI_DB_PASSWORD - reuse POSTGRES_PASSWORD
PG_PASS="${POSTGRES_PASSWORD:-$(openssl rand -hex 16)}"
set_env_if_missing "OPENWEBUI_DB_PASSWORD" "$PG_PASS"

# Fix database URLs with correct credentials
PG_USER="${POSTGRES_USER:-aiplatform}"
PG_DB="${POSTGRES_DB:-aiplatform}"

set_env_if_missing "DATABASE_URL" \
  "postgresql://${PG_USER}:${PG_PASS}@postgres:5432/litellm"

set_env_if_missing "OPENWEBUI_DATABASE_URL" \
  "postgresql://${PG_USER}:${PG_PASS}@postgres:5432/openwebui"

set_env_if_missing "N8N_DB_TYPE" "postgresdb"
set_env_if_missing "N8N_DB_POSTGRESDB_HOST" "postgres"
set_env_if_missing "N8N_DB_POSTGRESDB_PORT" "5432"
set_env_if_missing "N8N_DB_POSTGRESDB_DATABASE" "n8n"
set_env_if_missing "N8N_DB_POSTGRESDB_USER" "$PG_USER"
set_env_if_missing "N8N_DB_POSTGRESDB_PASSWORD" "$PG_PASS"

# Azure OpenAI placeholders if not set
set_env_if_missing "AZURE_OPENAI_API_KEY_1" "replace-with-real-azure-key"
set_env_if_missing "AZURE_OPENAI_API_KEY_2" "replace-with-real-azure-key"

# LiteLLM keys
set_env_if_missing "LITELLM_MASTER_KEY" "$(openssl rand -hex 32)"
set_env_if_missing "LITELLM_SALT_KEY" "$(openssl rand -hex 32)"

# Redis URL with password if REDIS_PASSWORD is set
REDIS_PASS="${REDIS_PASSWORD:-}"
if [[ -n "$REDIS_PASS" ]]; then
  set_env_if_missing "REDIS_URL" "redis://:${REDIS_PASS}@redis:6379"
else
  set_env_if_missing "REDIS_URL" "redis://redis:6379"
fi

echo ""
echo "[DONE] .env audit complete."
echo "[INFO] Review changes: grep -E 'TENANT|OPENWEBUI_DB|DATABASE_URL|LITELLM|AZURE' .env"
echo ""
echo "[IMPORTANT] Set real Azure API keys before starting LiteLLM:"
echo "  nano .env"
echo "  Find: AZURE_OPENAI_API_KEY_1=replace-with-real-azure-key"
echo "  Replace with your actual Azure OpenAI API key"
```

Make executable: chmod +x scripts/fix-env.sh

---

## STEP 3: Fix LiteLLM Configuration

### Task 3.1 — Fix the LiteLLM config.yaml
```
Find the LiteLLM config file. It is likely at one of:
  - $DATA_ROOT/litellm/config.yaml
  - configs/litellm/config.yaml
  - The path mounted in the LiteLLM service volumes

The CURRENT broken config has:
  - Duplicate model names (three entries all named "gpt-4")
  - Azure endpoints that may be invalid/unreachable
  - Missing API key references

Replace the LiteLLM config generation in scripts/1-setup-system.sh.
Find the LITELLM_CONFIG block from Phase 8, Task 8.2.
Replace the entire LITELLM_EOF heredoc content with:

model_list:
  # Azure OpenAI Models
  - model_name: azure-gpt-4
    litellm_params:
      model: azure/chatgpt-v-2
      api_base: https://openai-gpt-4-test-v-1.openai.azure.com/
      api_key: os.environ/AZURE_OPENAI_API_KEY_1
      api_version: "2024-02-15-preview"

  - model_name: azure-gpt-4-v2
    litellm_params:
      model: azure/gpt-4
      api_base: https://openai-gpt-4-test-v-2.openai.azure.com/
      api_key: os.environ/AZURE_OPENAI_API_KEY_2
      api_version: "2024-02-15-preview"
      rpm: 100

  # Fallback: OpenAI direct (only if OPENAI_API_KEY is set)
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY

  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: os.environ/OPENAI_API_KEY

  # Local Ollama (no key needed)
  - model_name: ollama/llama3
    litellm_params:
      model: ollama/llama3
      api_base: http://ollama:11434

litellm_settings:
  drop_params: true
  set_verbose: false
  success_callback: []
  failure_callback: []
  cache: true
  cache_params:
    type: redis
    host: redis
    port: 6379
    password: os.environ/REDIS_PASSWORD

router_settings:
  routing_strategy: least-busy
  fallbacks:
    - azure-gpt-4: ["azure-gpt-4-v2", "gpt-4o"]

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL
  store_model_in_db: true
  disable_spend_logs: false
  proxy_budget_rescheduler_min_time: 60
  proxy_budget_rescheduler_max_time: 120
```

### Task 3.2 — Fix LiteLLM Docker service definition for Azure
```
In scripts/2-deploy-services.sh, find the LiteLLM service definition.
Add the Azure environment variables to the environment section:

    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - LITELLM_SALT_KEY=${LITELLM_SALT_KEY}
      - DATABASE_URL=${DATABASE_URL}
      - REDIS_URL=${REDIS_URL}
      - REDIS_PASSWORD=${REDIS_PASSWORD}
      - AZURE_OPENAI_API_KEY_1=${AZURE_OPENAI_API_KEY_1}
      - AZURE_OPENAI_API_KEY_2=${AZURE_OPENAI_API_KEY_2}
      - OPENAI_API_KEY=${OPENAI_API_KEY:-}
      - STORE_MODEL_IN_DB=True
      - LITELLM_LOG=INFO
      - LITELLM_TELEMETRY=False

Also update the health check to be more forgiving during startup:

    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:4000/health/liveliness || curl -sf http://localhost:4000/v1/models || exit 1"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 90s

Note: start_period is 90s because LiteLLM needs time to connect to 
PostgreSQL and run migrations before serving requests.
```

### Task 3.3 — Add LiteLLM startup probe to emergency fix script
```
In scripts/0-emergency-fix.sh, find the section that starts LiteLLM.
Add this debug block BEFORE starting LiteLLM:

echo "[INFO] Validating LiteLLM prerequisites..."

# Check database is accessible
if docker compose exec -T postgres psql \
  -U "${POSTGRES_USER:-aiplatform}" \
  -lqt 2>/dev/null | cut -d\| -f1 | grep -qw "litellm"; then
  echo "[OK] LiteLLM database exists"
else
  echo "[WARN] LiteLLM database missing - creating..."
  docker compose exec -T postgres psql \
    -U "${POSTGRES_USER:-aiplatform}" \
    -c "CREATE DATABASE litellm;" 2>/dev/null || true
fi

# Check Azure keys are not placeholders
AZURE_KEY_1=$(grep "^AZURE_OPENAI_API_KEY_1=" .env | cut -d'=' -f2)
if [[ "$AZURE_KEY_1" == "replace-with-real-azure-key" ]] || [[ -z "$AZURE_KEY_1" ]]; then
  echo "[WARN] AZURE_OPENAI_API_KEY_1 is not set with a real key."
  echo "[WARN] LiteLLM will start but Azure models will fail."
  echo "[WARN] Set real keys in .env then run: docker compose restart litellm"
fi

echo "[INFO] Starting LiteLLM..."
docker compose up -d litellm
```

---

## STEP 4: Fix Database Provisioning

### Task 4.1 — Create scripts/provision-databases.sh 
```
Create NEW file scripts/provision-databases.sh:

#!/usr/bin/env bash
set -euo pipefail

echo "================================================"
echo " DATABASE PROVISIONING"
echo "================================================"
echo ""

# Load environment
if [[ -f ".env" ]]; then
  set -a
  source .env
  set +a
else
  echo "[ERROR] .env file not found."
  exit 1
fi

PG_USER="${POSTGRES_USER:-aiplatform}"
PG_PASS="${POSTGRES_PASSWORD:-}"
MAX_WAIT=60
WAIT_INTERVAL=5

# --- Wait for PostgreSQL ---
echo "[INFO] Waiting for PostgreSQL to be ready..."
elapsed=0
until docker compose exec -T postgres pg_isready \
  -U "$PG_USER" -q 2>/dev/null; do
  elapsed=$((elapsed + WAIT_INTERVAL))
  if [[ $elapsed -ge $MAX_WAIT ]]; then
    echo "[ERROR] PostgreSQL not ready after ${MAX_WAIT}s. Is postgres container running?"
    echo "        Run: docker compose ps postgres"
    exit 1
  fi
  echo "[INFO] Waiting... (${elapsed}s/${MAX_WAIT}s)"
  sleep $WAIT_INTERVAL
done
echo "[OK] PostgreSQL is ready."
echo ""

# --- Database creation function ---
create_db_if_missing() {
  local db_name="$1"
  local owner="${2:-$PG_USER}"
  
  local exists
  exists=$(docker compose exec -T postgres psql \
    -U "$PG_USER" \
    -tAc "SELECT 1 FROM pg_database WHERE datname='${db_name}'" 2>/dev/null || echo "")
  
  if [[ "$exists" == "1" ]]; then
    echo "[SKIP] Database '$db_name' already exists"
  else
    echo "[CREATE] Creating database '$db_name'..."
    docker compose exec -T postgres psql \
      -U "$PG_USER" \
      -c "CREATE DATABASE \"${db_name}\" OWNER \"${owner}\";" 2>/dev/null && \
    echo "[OK] Database '$db_name' created" || \
    echo "[WARN] Failed to create '$db_name' - may already exist"
  fi
}

# --- Create all required databases ---
echo "[INFO] Provisioning databases..."
echo ""

# Core platform databases
create_db_if_missing "aiplatform"     "$PG_USER"
create_db_if_missing "litellm"        "$PG_USER"
create_db_if_missing "openwebui"      "$PG_USER"
create_db_if_missing "n8n"            "$PG_USER"
create_db_if_missing "flowise"        "$PG_USER"
create_db_if_missing "authentik"      "$PG_USER"

# Fix the ds-admin connection error
# ds-admin is likely the POSTGRES_DB default that was changed
# Create it as an alias/redirect
DS_ADMIN_EXISTS=$(docker compose exec -T postgres psql \
  -U "$PG_USER" \
  -tAc "SELECT 1 FROM pg_database WHERE datname='ds-admin'" 2>/dev/null || echo "")

if [[ "$DS_ADMIN_EXISTS" != "1" ]]; then
  echo "[CREATE] Creating 'ds-admin' database (referenced by services)..."
  docker compose exec -T postgres psql \
    -U "$PG_USER" \
    -c "CREATE DATABASE \"ds-admin\" OWNER \"${PG_USER}\";" 2>/dev/null && \
  echo "[OK] 'ds-admin' database created" || \
  echo "[WARN] Could not create ds-admin"
else
  echo "[SKIP] 'ds-admin' already exists"
fi

echo ""

# --- List all databases ---
echo "[INFO] Current databases:"
docker compose exec -T postgres psql \
  -U "$PG_USER" \
  -c "\l" 2>/dev/null | grep -v "^$" || true

echo ""
echo "================================================"
echo " DATABASE PROVISIONING COMPLETE"
echo "================================================"
echo ""
echo "Next steps:"
echo "  1. Run: bash scripts/fix-env.sh"
echo "  2. Run: docker compose restart litellm"
echo "  3. Run: bash scripts/3-configure-services.sh"
```

Make executable: chmod +x scripts/provision-databases.sh
```

### Task 4.2 — Fix the ds-admin reference in script 3
```
In scripts/3-configure-services.sh, search for any hardcoded 
reference to "ds-admin" database name.

Replace any instance of:
  psql -d ds-admin
  -d ds-admin
  database: ds-admin
  dbname=ds-admin

With the variable reference:
  psql -d "${POSTGRES_DB:-aiplatform}"
  -d "${POSTGRES_DB:-aiplatform}"
  database: ${POSTGRES_DB:-aiplatform}
  dbname=${POSTGRES_DB:-aiplatform}

Also check .env for:
  POSTGRES_DB=ds-admin

If found, this is the root cause. The variable should be:
  POSTGRES_DB=aiplatform

Update .env accordingly BUT check if services depend on 
the current value first by grepping:
  grep -r "ds-admin" scripts/ docker-compose.yml .env 2>/dev/null
```

---

## STEP 5: Fix Qdrant Health Check

```
In scripts/2-deploy-services.sh, find the Qdrant health check.

Current broken state: uses /health or /readyz (returns 404)
Correct fix: use /collections endpoint

Replace Qdrant healthcheck with:

    healthcheck:
      test: ["CMD", "curl", "--fail", "--silent", "--max-time", "5", "http://localhost:6333/collections"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

This matches the confirmed working endpoint:
  {"result":{"collections":[]},"status":"ok"}
```

---

## STEP 6: Deploy Caddy

### Task 6.1 — Add Caddy deployment gate to script 2
```
In scripts/2-deploy-services.sh, find where Caddy is deployed.
Replace the Caddy startup section with a gated deployment:

echo "[INFO] Checking if core services are healthy before starting Caddy..."

CADDY_DEPS=("postgres" "redis")
ALL_READY=true

for dep in "${CADDY_DEPS[@]}"; do
  DEP_STATUS=$(docker compose ps --format "{{.Health}}" "$dep" 2>/dev/null || echo "unknown")
  if [[ "$DEP_STATUS" != "healthy" ]]; then
    echo "[WARN] $dep is not healthy yet (status: $DEP_STATUS)"
    ALL_READY=false
  fi
done

if $ALL_READY; then
  echo "[INFO] Prerequisites healthy. Starting Caddy..."
  docker compose up -d caddy
  
  echo "[INFO] Waiting 15s for Caddy to initialize..."
  sleep 15
  
  CADDY_STATUS=$(docker compose ps --format "{{.Status}}" caddy 2>/dev/null || echo "unknown")
  echo "[INFO] Caddy status: $CADDY_STATUS"
else
  echo "[WARN] Some prerequisites not healthy. Caddy will start when they are ready."
  echo "[WARN] Run manually: docker compose up -d caddy"
fi
```

### Task 6.2 — Verify Caddy service definition in compose
```
In scripts/2-deploy-services.sh, find the Caddy service definition.
Verify or add:

  caddy:
    image: caddy:2.8.4-alpine
    container_name: caddy
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - "80:80"
      - "443:443"
      - "2019:2019"
    environment:
      - DOMAIN=${DOMAIN:-localhost}
      - GRAFANA_ADMIN_PASSWORD_HASH=${GRAFANA_ADMIN_PASSWORD_HASH:-}
    volumes:
      - ${DATA_ROOT}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ${DATA_ROOT}/caddy/data:/data
      - ${DATA_ROOT}/caddy/config:/config
      - ${DATA_ROOT}/caddy/logs:/data/logs
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:2019/metrics"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.25'
        reservations:
          memory: 64M
```

---

## STEP 7: Final Validation Checklist for Windsurf

```
After ALL changes above are complete:

VERIFY THESE SPECIFIC ITEMS
=============================

□ scripts/fix-env.sh              — EXISTS, handles TENANT + OPENWEBUI_DB_PASSWORD
□ scripts/provision-databases.sh  — EXISTS, creates ds-admin + all service DBs
□ LiteLLM config.yaml             — Has UNIQUE model names (no duplicate "gpt-4")
□ LiteLLM service env             — Has AZURE_OPENAI_API_KEY_1, AZURE_OPENAI_API_KEY_2
□ LiteLLM healthcheck             — Uses /health/liveliness OR /v1/models, 90s start_period
□ Qdrant healthcheck              — Uses /collections NOT /health or /readyz
□ ds-admin reference in script 3  — Replaced with ${POSTGRES_DB:-aiplatform}
□ Caddy service definition        — EXISTS with correct depends_on

DO NOT run any scripts.

Output this exact message when done:

"✅ Phase 3 fixes applied.

Run in this exact order:
  1. bash scripts/fix-env.sh
  2. bash scripts/provision-databases.sh
  3. nano .env  ← set real AZURE_OPENAI_API_KEY_1 and _2
  4. docker compose restart litellm
  5. docker compose up -d caddy
  6. bash scripts/4-monitor-health.sh

Expected result: 8/8 services healthy"
```
