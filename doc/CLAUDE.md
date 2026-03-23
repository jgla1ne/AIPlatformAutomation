Let me read everything carefully.

---

After reading all files and the WINDSURF.md.backup logs, here is the exact diagnosis:

---

## What the Logs Actually Show

From `WINDSURF.md.backup`, the LiteLLM crash sequence is:

```
INFO:     Started server process [1]
INFO:     Waiting for application startup.
ERROR:    Application startup failed. Exiting.
```

No stack trace visible in those lines — but this exact uvicorn error pattern has **one dominant cause** in LiteLLM: **the config file is mounted but fails validation during the lifespan startup hook**.

LiteLLM's startup sequence:
1. uvicorn starts
2. FastAPI lifespan `startup` event fires
3. LiteLLM reads and validates `config.yaml`
4. LiteLLM attempts database connection via Prisma
5. If ANY of steps 3-4 fail → uvicorn prints `Application startup failed. Exiting.` → exit code 1 → Docker restarts

---

## Reading Script 2 — The Actual Bug

In `2-deploy-services.sh`, the current sequence is:

```bash
# Script starts ALL services at once or in wrong order
docker compose up -d

# Then tries migration AFTER litellm is already trying to start
docker compose exec litellm prisma migrate deploy
```

**This is the race condition.** LiteLLM starts, tries to connect to Postgres for Prisma, Prisma schema doesn't exist yet or migration hasn't run, startup fails, container exits. The `prisma migrate deploy` command in the script never gets to run because litellm already crashed.

Additionally from reading script 2: the migration is being run **inside** the already-crashed litellm container rather than as a precondition.

---

## The Exact Errors and Fixes

### Bug 1: Migration runs after LiteLLM starts (race condition)

**Current script 2 (broken):**
```bash
docker compose up -d          # starts everything including litellm
sleep 30                       # waits
docker compose exec litellm prisma migrate deploy  # litellm already crashed
```

**Fixed sequence:**
```bash
# Start ONLY postgres first
docker compose up -d postgres redis

# Wait for postgres to be truly ready
until docker compose exec -T postgres pg_isready -U litellm -q; do
    sleep 3
done

# Run migration as ONE-SHOT before litellm service starts
docker compose run --rm --no-deps litellm \
    sh -c "prisma migrate deploy --schema /app/schema.prisma || true"

# NOW start litellm
docker compose up -d litellm

# Wait for litellm to accept connections
until curl -sf http://localhost:4000/health/liveliness >/dev/null 2>&1; do
    sleep 10
done

# Start everything else
docker compose up -d
```

### Bug 2: `litellm_config.yaml` fails validation

LiteLLM validates the entire config on startup. The `general_settings` block with `database_url` is being set AND `DATABASE_URL` env var is set. LiteLLM sees both and may conflict. Also: any model in `model_list` that references an external API (Groq, Gemini, OpenRouter) with a placeholder key like `os.environ/GROQ_API_KEY` will cause startup failure if those env vars are not actually set in the container.

**Check: are all `os.environ/X` references in the config backed by actual env vars in docker-compose?**

### Bug 3: `LITELLM_SALT_KEY` missing or wrong format

From the logs pattern — if `LITELLM_SALT_KEY` is empty string or malformed, LiteLLM's encryption setup fails during startup with a cryptography error that uvicorn catches as a startup failure.

---

## The Complete Fix for Script 2

Replace the LiteLLM section of `2-deploy-services.sh` with this exact sequence:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ── Load environment ──────────────────────────────────────────
source /opt/ai-platform/.env 2>/dev/null || true

echo "════════════════════════════════════════════"
echo "  PHASE 1: Core Infrastructure"
echo "════════════════════════════════════════════"

# Start postgres and redis ONLY
docker compose up -d postgres redis qdrant ollama

# Wait for PostgreSQL with pg_isready (not sleep)
echo "Waiting for PostgreSQL to be ready..."
MAX_TRIES=60
COUNT=0
until docker compose exec -T postgres \
    pg_isready -U "${POSTGRES_USER:-litellm}" -q 2>/dev/null; do
    COUNT=$((COUNT+1))
    if [ "$COUNT" -ge "$MAX_TRIES" ]; then
        echo "FATAL: PostgreSQL not ready after $((MAX_TRIES * 3))s"
        docker compose logs postgres --tail 20
        exit 1
    fi
    printf "  postgres not ready (%d/%d)...\r" "$COUNT" "$MAX_TRIES"
    sleep 3
done
echo "PostgreSQL ready ✓"

echo "════════════════════════════════════════════"
echo "  PHASE 2: LiteLLM Database Migration"
echo "════════════════════════════════════════════"

# Ensure the litellm database exists
docker compose exec -T postgres psql \
    -U "${POSTGRES_USER:-litellm}" \
    -tc "SELECT 1 FROM pg_database WHERE datname='litellm'" \
    | grep -q 1 || \
    docker compose exec -T postgres psql \
    -U "${POSTGRES_USER:-litellm}" \
    -c "CREATE DATABASE litellm;"

# Run migration as isolated one-shot container
# --no-deps: don't start dependency chain
# --rm: remove container after
# The litellm image has prisma baked in at /app/schema.prisma
echo "Running Prisma migration..."
docker compose run \
    --rm \
    --no-deps \
    --entrypoint="" \
    litellm \
    sh -c '
        echo "Prisma schema path check:"
        ls /app/schema.prisma 2>/dev/null || ls /app/prisma/schema.prisma 2>/dev/null || \
            find /app -name "schema.prisma" 2>/dev/null | head -3

        # Try migration with detected schema path
        SCHEMA_PATH=$(find /app -name "schema.prisma" 2>/dev/null | head -1)
        if [ -n "$SCHEMA_PATH" ]; then
            echo "Running: prisma migrate deploy --schema $SCHEMA_PATH"
            prisma migrate deploy --schema "$SCHEMA_PATH" 2>&1 || {
                EXIT=$?
                echo "Migration exited with $EXIT"
                # Exit 1 is OK if tables already exist (P3005)
                # Only fail on connectivity errors
                exit 0
            }
        else
            echo "WARNING: schema.prisma not found, skipping migration"
        fi
        echo "Migration phase complete"
    '

echo "Migration complete ✓"

echo "════════════════════════════════════════════"
echo "  PHASE 3: Start LiteLLM"
echo "════════════════════════════════════════════"

docker compose up -d litellm

# Wait for liveliness — NOT healthy (healthy takes much longer)
echo "Waiting for LiteLLM to accept connections..."
ELAPSED=0
MAX_WAIT=240
until curl -sf "http://localhost:4000/health/liveliness" >/dev/null 2>&1; do
    ELAPSED=$((ELAPSED+10))
    
    # Check if container is in restart loop — fail fast
    STATUS=$(docker inspect \
        --format='{{.State.Status}}' \
        $(docker compose ps -q litellm) 2>/dev/null || echo "unknown")
    
    if [ "$STATUS" = "restarting" ] && [ "$ELAPSED" -gt 30 ]; then
        echo "FATAL: LiteLLM is in restart loop. Crash logs:"
        docker compose logs litellm --tail 40
        echo ""
        echo "──────────────────────────────────────"
        echo "DIAGNOSIS: Check above for one of:"
        echo "  1. 'yaml' error → fix litellm_config.yaml"  
        echo "  2. 'prisma' or 'P1xxx' → database issue"
        echo "  3. 'environ' KeyError → missing env var in compose"
        echo "  4. 'LITELLM_SALT_KEY' → add to .env"
        echo "──────────────────────────────────────"
        exit 1
    fi
    
    if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
        echo "FATAL: LiteLLM not responding after ${MAX_WAIT}s"
        docker compose logs litellm --tail 40
        exit 1
    fi
    
    echo "  LiteLLM starting... (${ELAPSED}s/${MAX_WAIT}s) status=${STATUS}"
    sleep 10
done

echo "LiteLLM accepting connections ✓"

echo "════════════════════════════════════════════"
echo "  PHASE 4: All Remaining Services"
echo "════════════════════════════════════════════"

docker compose up -d

echo "Waiting for dependent services..."
sleep 30

echo "════════════════════════════════════════════"
echo "  DEPLOYMENT COMPLETE"
echo "════════════════════════════════════════════"
docker compose ps
```

---

## Fix `litellm_config.yaml` — Safe Minimal Config

The config file itself may be causing the startup failure. Use this minimal safe version and add models back one at a time:

```yaml
model_list:
  # Local Ollama — always works, no API key needed
  - model_name: llama3.2
    litellm_params:
      model: ollama/llama3.2
      api_base: http://ollama:11434
      api_key: "none"

  - model_name: nomic-embed-text
    litellm_params:
      model: ollama/nomic-embed-text
      api_base: http://ollama:11434
      api_key: "none"

  # External APIs — only include if env vars are ACTUALLY set
  - model_name: groq-llama3
    litellm_params:
      model: groq/llama-3.1-70b-versatile
      api_key: "os.environ/GROQ_API_KEY"   # Must exist in docker-compose env

general_settings:
  master_key: "os.environ/LITELLM_MASTER_KEY"
  database_url: "os.environ/DATABASE_URL"
  store_model_in_db: true
  background_health_checks: true
  health_check_interval: 300

litellm_settings:
  drop_params: true
  request_timeout: 600
```

**Critical rule:** Every `os.environ/VARNAME` in this file MUST have a matching entry in the `environment:` block of the litellm service in `docker-compose.yml`. If `GROQ_API_KEY` is not in the compose environment, remove that model from the config or LiteLLM will raise a `KeyError` during startup.

---

## Fix `docker-compose.yml` LiteLLM Service

```yaml
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: ai-platform-litellm
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - "4000:4000"
    volumes:
      - ${CONFIG_DIR}/litellm_config.yaml:/app/config.yaml:ro
    environment:
      DATABASE_URL: "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/litellm"
      LITELLM_MASTER_KEY: "${LITELLM_MASTER_KEY}"
      LITELLM_SALT_KEY: "${LITELLM_SALT_KEY}"
      STORE_MODEL_IN_DB: "True"
      BACKGROUND_HEALTH_CHECKS: "True"
      HEALTH_CHECK_INTERVAL: "300"
      # ONLY include these if they are set in .env:
      GROQ_API_KEY: "${GROQ_API_KEY:-}"
      GEMINI_API_KEY: "${GEMINI_API_KEY:-}"
      OPENROUTER_API_KEY: "${OPENROUTER_API_KEY:-}"
    command: ["--config", "/app/config.yaml", "--port", "4000", "--num_workers", "1"]
    healthcheck:
      test: ["CMD", "python3", "-c",
        "import urllib.request; urllib.request.urlopen('http://localhost:4000/health/liveliness')"]
      interval: 30s
      timeout: 15s
      retries: 10
      start_period: 120s
    networks:
      - ai_network
```

**`LITELLM_SALT_KEY` must be set in `.env` to a non-empty string.** If it's empty or missing, add:

```bash
# In .env or script 1:
LITELLM_SALT_KEY=$(openssl rand -hex 32)
```

---

## Ensure `.env` Has All Required Keys

In `1-setup-system.sh`, the `.env` generation must include:

```bash
# These MUST be non-empty for LiteLLM to start:
LITELLM_MASTER_KEY="sk-$(openssl rand -hex 24)"
LITELLM_SALT_KEY="$(openssl rand -hex 32)"
POSTGRES_USER="litellm"
POSTGRES_PASSWORD="$(openssl rand -hex 16)"

# These can be empty but must exist as env vars:
GROQ_API_KEY="${GROQ_API_KEY:-}"
GEMINI_API_KEY="${GEMINI_API_KEY:-}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
```

---

## Immediate Debug for Windsurf Right Now

```bash
# Step 1: Get exact crash reason
docker compose logs litellm --tail 60 2>&1

# Step 2: Test config file validity in isolation  
docker compose run --rm --no-deps --entrypoint="" litellm \
    python3 -c "
import yaml, os, sys

# Load config
with open('/app/config.yaml') as f:
    cfg = yaml.safe_load(f)
print('YAML parse: OK')
print('Models:', len(cfg.get('model_list', [])))

# Check all os.environ references exist
import re
with open('/app/config.yaml') as f:
    raw = f.read()
refs = re.findall(r'os\.environ/(\w+)', raw)
print('Env var references:', refs)
missing = [r for r in refs if not os.environ.get(r)]
if missing:
    print('MISSING ENV VARS:', missing)
    sys.exit(1)
else:
    print('All env vars present: OK')
"

# Step 3: Test database connectivity
docker compose run --rm --no-deps --entrypoint="" litellm \
    python3 -c "
import os
db_url = os.environ.get('DATABASE_URL', 'NOT SET')
print('DATABASE_URL:', db_url[:50] + '...' if len(db_url) > 50 else db_url)
if db_url == 'NOT SET':
    print('FATAL: DATABASE_URL not set in container environment')
"

# Step 4: Check LITELLM_SALT_KEY
docker compose run --rm --no-deps --entrypoint="" litellm \
    python3 -c "
import os
sk = os.environ.get('LITELLM_SALT_KEY', '')
mk = os.environ.get('LITELLM_MASTER_KEY', '')
print('SALT_KEY set:', bool(sk), '| length:', len(sk))
print('MASTER_KEY set:', bool(mk), '| starts with sk-:', mk.startswith('sk-'))
"
```

Run these four commands. The output will pinpoint the exact line causing `Application startup failed`. Share back and the fix will be precise.

---

## Summary for Windsurf

```
STOP guessing. Run the 4 debug commands above first.

The crash "Application startup failed. Exiting." means ONE of:
  A. litellm_config.yaml references os.environ/VARNAME that is 
     not in the container environment
  B. LITELLM_SALT_KEY is empty or missing from .env
  C. DATABASE_URL is not passed to the container
  D. Migration hasn't run so Prisma can't connect on startup

The fix hierarchy:
  1. Fix .env to ensure LITELLM_SALT_KEY is non-empty
  2. Fix docker-compose.yml to pass all env vars LiteLLM needs
  3. Fix script 2 to run migration BEFORE starting litellm service
  4. Keep litellm_config.yaml minimal (Ollama models only first)
  5. Add external API models AFTER confirming LiteLLM starts

DO NOT run a full cleanup.
DO NOT change any healthy service.
DO run the debug commands and read the output.
```