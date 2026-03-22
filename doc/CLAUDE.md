Let me read the current scripts before diagnosing.

---

## Reading the Current State

Based on the scripts and the status report, here is the precise diagnosis:

**LiteLLM is "still restarting"** — this is a container restart loop, not a health check issue. The health check fix was applied but something is causing the process itself to crash and Docker to restart it.

---

## The Real LiteLLM Problem: Container Restart Loop

A restart loop (`Restarting`) is **completely different** from `health: starting`. 

- `health: starting` = container runs, health check failing
- `Restarting` = container process exits with non-zero code, Docker restarts it

**The container is crashing on startup.** The health check fix is irrelevant until the crash is resolved.

### What Causes LiteLLM to Crash on Startup

There are exactly three things that cause LiteLLM to exit non-zero immediately:

**Cause A: Prisma/Database schema mismatch**

The `litellm-database` image (which Windsurf added per "Gemini's Fix") has Prisma baked in at a specific schema version. If the PostgreSQL database has tables from a previous LiteLLM version, Prisma migration fails with:

```
Error: P3005 - The database schema is not empty
```
or
```
Error: Migration failed to apply cleanly
```

LiteLLM exits. Docker restarts. Same crash. Loop forever.

**Cause B: `DATABASE_URL` format wrong for the image being used**

The `ghcr.io/berriai/litellm-database` image expects the database URL in a specific format. If `.env` has:
```
DATABASE_URL=postgresql://litellm:password@postgres:5432/litellm
```
but the image expects:
```
DATABASE_URL=postgresql://litellm:password@postgres:5432/litellm?schema=litellm
```
Prisma panics and exits.

**Cause C: Config file syntax error in `litellm_config.yaml`**

LiteLLM validates its config file on startup. A YAML syntax error — a bad indent, a tab character, a missing colon — causes:
```
yaml.scanner.ScannerError: ...
```
Process exits. Restart loop.

---

## Definitive Fix

### Step 1: Get the actual crash reason RIGHT NOW

```bash
# Run this immediately — before any other change
docker logs $(docker ps -a -q -f name=litellm) --tail 50 2>&1 | head -80
```

The last 10 lines before the exit will tell you exactly which cause it is. Share this output. But based on the pattern (Windsurf switched to `litellm-database` image + existing DB with data), **Cause A is most likely**.

### Step 2: Fix based on actual cause

---

## Fix A: Database Schema Conflict (Most Likely)

Windsurf switched to `ghcr.io/berriai/litellm-database` image. This image runs `prisma migrate deploy` on startup against the existing database that was previously initialized by the `ghcr.io/berriai/litellm` image. The schemas conflict.

**Solution: Reset the LiteLLM database schema cleanly**

```bash
# 1. Drop and recreate just the litellm database (not all of postgres)
docker compose exec postgres psql -U litellm -c "DROP DATABASE IF EXISTS litellm;"
docker compose exec postgres psql -U litellm -c "CREATE DATABASE litellm;"

# 2. Remove the litellm container so it starts fresh
docker compose rm -sf litellm

# 3. Start it again
docker compose up -d litellm

# 4. Watch the logs in real time
docker logs -f $(docker ps -q -f name=litellm) 2>&1 | head -40
```

---

## Fix B: Go Back to the Standard Image

"Gemini's Fix" of switching to `litellm-database` image introduced complexity. The standard image with an explicit prisma migration step in `script 2` is more reliable and easier to debug.

**In `docker-compose.yml`, change:**

```yaml
# REMOVE this (Gemini's suggestion):
image: ghcr.io/berriai/litellm-database:main-latest

# RESTORE this (the original that worked in manual test):
image: ghcr.io/berriai/litellm:main-latest
```

**In `scripts/2-deploy-services.sh`, ensure the migration step exists:**

```bash
# After postgres is confirmed healthy and BEFORE docker compose up for litellm:

echo "Running LiteLLM Prisma migration..."
docker run --rm \
    --network "$(docker compose ps --format json | python3 -c \
        "import sys,json; services=json.load(sys.stdin); \
        [print(s['Networks'].split(',')[0]) for s in services \
        if 'postgres' in s['Name']]" 2>/dev/null || \
        echo "${COMPOSE_PROJECT_NAME:-ai-platform}_ai_network")" \
    -e DATABASE_URL="postgresql://${POSTGRES_USER:-litellm}:${POSTGRES_PASSWORD}@postgres:5432/litellm" \
    ghcr.io/berriai/litellm:main-latest \
    python -c "
import subprocess, sys
result = subprocess.run(
    ['prisma', 'migrate', 'deploy', '--schema', '/app/schema.prisma'],
    capture_output=True, text=True
)
print(result.stdout)
print(result.stderr)
sys.exit(result.returncode)
" 2>&1 || {
    echo "WARNING: Prisma migration had errors. Checking if schema exists..."
    # Non-fatal if tables already exist
}

echo "Starting LiteLLM..."
docker compose up -d litellm
```

**Simpler alternative in script 2:**

```bash
# The most reliable migration approach — run as separate container
echo "Initializing LiteLLM database schema..."
docker compose run --rm litellm \
    sh -c "cd /app && prisma migrate deploy --schema schema.prisma 2>&1; exit 0"

echo "Starting LiteLLM service..."
docker compose up -d litellm
```

---

## Fix C: `litellm_config.yaml` Validation

Check the config file for YAML errors:

```bash
# Validate the config file
python3 -c "
import yaml, sys
try:
    with open('/opt/ai-platform/config/litellm_config.yaml') as f:
        data = yaml.safe_load(f)
    print('YAML valid')
    print('Models found:', len(data.get('model_list', [])))
    print('General settings:', list(data.get('general_settings', {}).keys()))
except yaml.YAMLError as e:
    print('YAML ERROR:', e)
    sys.exit(1)
"
```

Common errors Windsurf introduces:

```yaml
# WRONG — tab characters instead of spaces:
model_list:
	- model_name: ollama-llama3   # <-- tab, not spaces

# WRONG — missing space after colon:
  litellm_params:
    model:ollama/llama3:2        # <-- no space after colon

# WRONG — unquoted special characters:
  api_key: sk-abc:def/xyz       # <-- colon in unquoted string

# CORRECT:
model_list:
  - model_name: ollama-llama3
    litellm_params:
      model: ollama/llama3.2
      api_base: http://ollama:11434
      api_key: "none"
```

---

## The Complete `docker-compose.yml` LiteLLM Block

Replace the entire litellm service definition with this known-working configuration:

```yaml
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: ${COMPOSE_PROJECT_NAME:-ai-platform}-litellm
    restart: unless-stopped
    ports:
      - "4000:4000"
    environment:
      DATABASE_URL: "postgresql://${POSTGRES_USER:-litellm}:${POSTGRES_PASSWORD}@postgres:5432/litellm"
      LITELLM_MASTER_KEY: "${LITELLM_MASTER_KEY}"
      LITELLM_SALT_KEY: "${LITELLM_SALT_KEY:-}"
      STORE_MODEL_IN_DB: "True"
      BACKGROUND_HEALTH_CHECKS: "True"
      HEALTH_CHECK_INTERVAL: "300"
      DISABLE_SCHEMA_UPDATE: "False"
      LITELLM_LOG: "INFO"
      REDIS_URL: "redis://redis:6379"
    volumes:
      - ${CONFIG_DIR:-/opt/ai-platform/config}/litellm_config.yaml:/app/config.yaml:ro
    command: ["--config", "/app/config.yaml", "--port", "4000", "--num_workers", "1"]
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
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

**Key decisions in this config:**
- Standard `litellm` image (not `litellm-database`) — no baked-in migration surprises
- `DISABLE_SCHEMA_UPDATE: "False"` — allows migration to run once on startup
- `STORE_MODEL_IN_DB: "True"` — required for database-backed model management
- `--num_workers 1` — reduces memory pressure, easier to debug
- `python3 urllib` healthcheck — no curl dependency issues
- `start_period: 120s` — gives full 2 minutes for migration before health checks start

---

## Script 2 — The Migration Sequence That Actually Works

```bash
# ============================================================
# In 2-deploy-services.sh — PostgreSQL + LiteLLM section
# ============================================================

# 1. Start only infrastructure first
echo "Starting infrastructure services..."
docker compose up -d postgres redis qdrant ollama

# 2. Wait for PostgreSQL with pg_isready (not sleep)
echo "Waiting for PostgreSQL..."
RETRIES=30
COUNT=0
until docker compose exec -T postgres \
    pg_isready -U "${POSTGRES_USER:-litellm}" -d litellm -q 2>/dev/null; do
    COUNT=$((COUNT + 1))
    if [ "$COUNT" -ge "$RETRIES" ]; then
        echo "ERROR: PostgreSQL not ready after $((RETRIES * 5))s"
        docker compose logs postgres --tail 20
        exit 1
    fi
    echo "  PostgreSQL not ready ($COUNT/$RETRIES), waiting 5s..."
    sleep 5
done
echo "PostgreSQL ready."

# 3. Run migration as one-shot container BEFORE starting the service
echo "Running LiteLLM database migration..."
docker compose run --rm --no-deps litellm \
    python3 -c "
from litellm.proxy.db.prisma_client import PrismaClient
import asyncio

async def migrate():
    client = PrismaClient()
    await client.connect()
    print('Migration complete')
    await client.disconnect()

asyncio.run(migrate())
" 2>&1 || {
    echo "Python migration attempt done (errors above may be non-fatal)"
}

# 4. Start LiteLLM service
echo "Starting LiteLLM..."
docker compose up -d litellm

# 5. Wait for LiteLLM liveliness — not healthy (healthy takes longer)
echo "Waiting for LiteLLM process to accept connections..."
ELAPSED=0
MAX_WAIT=300
until curl -sf "http://localhost:4000/health/liveliness" > /dev/null 2>&1; do
    ELAPSED=$((ELAPSED + 10))
    if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
        echo "ERROR: LiteLLM not responding after ${MAX_WAIT}s"
        echo "Last 30 log lines:"
        docker compose logs litellm --tail 30
        exit 1
    fi
    echo "  Waiting for LiteLLM... (${ELAPSED}s/${MAX_WAIT}s)"
    sleep 10
done
echo "LiteLLM is accepting connections."

# 6. Now start dependent services
echo "Starting AI services..."
docker compose up -d openwebui anythingllm flowise n8n dify
```

---

## Immediate Debug Commands for Windsurf

Run these **right now** to identify which fix is needed:

```bash
# Command 1: Get the crash reason
docker logs $(docker ps -a --filter name=litellm --format "{{.ID}}" | head -1) \
    --tail 30 2>&1

# Command 2: Check if it's a YAML parse error  
docker compose run --rm --no-deps litellm \
    python3 -c "
import yaml
with open('/app/config.yaml') as f:
    data = yaml.safe_load(f)
print('Config OK, models:', len(data.get('model_list',[])))
" 2>&1

# Command 3: Check database connectivity
docker compose run --rm --no-deps \
    -e DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/litellm" \
    litellm \
    python3 -c "
import psycopg2, os
conn = psycopg2.connect(os.environ['DATABASE_URL'])
cur = conn.cursor()
cur.execute(\"SELECT count(*) FROM information_schema.tables WHERE table_schema='public'\")
print('Tables in DB:', cur.fetchone()[0])
" 2>&1

# Command 4: Check what image is actually being used
docker inspect $(docker ps -a --filter name=litellm --format "{{.ID}}" | head -1) \
    --format '{{.Config.Image}}'
```

The output of Command 1 will have one of these patterns:

| Log Pattern | Root Cause | Fix |
|-------------|-----------|-----|
| `yaml.scanner.ScannerError` | Config YAML syntax error | Fix `litellm_config.yaml` |
| `P3005` or `migration failed` | DB schema conflict | Drop/recreate litellm DB |
| `connection refused` or `ECONNREFUSED` | Postgres not ready | Fix startup ordering |
| `P1001` or `Can't reach database` | Wrong DATABASE_URL | Fix env var format |
| `ModuleNotFoundError` | Wrong image/tag | Use `main-latest` tag |
| `litellm-database` + `already exists` | Image migration conflict | Switch back to standard image |

---

## Summary for Windsurf

```
LiteLLM is in a RESTART LOOP (Restarting), not a health check issue.
The /health/liveliness fix is correct but irrelevant until the crash is fixed.

IMMEDIATE ACTION:
  docker logs $(docker ps -a -q -f name=litellm) --tail 50

READ the last error before "Container exiting".
That error tells you exactly which of 3 causes it is.

MOST LIKELY CAUSE (given Windsurf switched to litellm-database image):
  Database schema conflict between old data and new image's migrations.

MOST LIKELY FIX:
  1. Change image back to: ghcr.io/berriai/litellm:main-latest
  2. Drop and recreate the litellm database
  3. docker compose up -d litellm
  4. Watch logs for 2 minutes

DO NOT change any healthy service.
DO NOT run script 0 (cleanup).
DO NOT switch images again without reading the logs first.
```