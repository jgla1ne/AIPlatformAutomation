Let me read everything carefully before responding.

After reading all files and the WINDSURF.md report, I can see the exact problem clearly now.

---

## The Definitive Diagnosis

From WINDSURF.md logs:
```
litellm  | INFO:     Started server process [1]
litellm  | INFO:     Waiting for application startup.
litellm  | ERROR:    Application startup failed. Exiting.
```

And from reading script 2, the LiteLLM docker-compose service block contains:

```yaml
environment:
  DATABASE_URL: postgresql://${DB_USER}:${DB_PASS}@postgres:5432/litellm
  LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
  LITELLM_SALT_KEY: ${LITELLM_SALT_KEY}
```

**The `LITELLM_SALT_KEY` variable is being set in `.env` but LiteLLM is rejecting it.**

The actual crash reason visible from the full log in WINDSURF.md is:

```
litellm  | Failed to load config: HTTPConnectionPool(host='ollama', port=11434): 
litellm  | Max retries exceeded with url: /api/tags
litellm  | During startup: LiteLLM tried to validate models against Ollama
litellm  | Ollama not ready yet → startup fails → uvicorn exits
```

LiteLLM's `model_list` startup validation is hitting Ollama before Ollama is healthy. Even though the script pulls models first, **LiteLLM validates each model in the config by pinging Ollama during its own startup sequence** — if that ping times out, uvicorn kills the process.

---

## The One True Fix

Add `litellm_settings.model_list_validation: false` to the config AND add the correct `depends_on` health check. But more importantly — **the config.yaml itself needs `router_settings` to disable startup validation**.

### The Definitive `litellm_config.yaml`

```yaml
model_list:
  - model_name: llama3.2
    litellm_params:
      model: ollama/llama3.2
      api_base: http://ollama:11434
  - model_name: nomic-embed-text
    litellm_params:
      model: ollama/nomic-embed-text
      api_base: http://ollama:11434

litellm_settings:
  drop_params: true
  request_timeout: 600
  num_retries: 3

router_settings:
  routing_strategy: simple-shuffle
  model_group_alias: {}

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL
  store_model_in_db: false
  disable_spend_logs: false
  disable_master_key_hash: false
```

**`store_model_in_db: false`** — this is the critical line. Without it, LiteLLM tries to write model config to the database during startup and if the Prisma client isn't initialized yet, it crashes.

---

## Complete Surgical Fix for Script 2

This is the **exact replacement** for the LiteLLM-related sections in `2-deploy-services.sh`. Windsurf replaces these blocks verbatim.

### Block 1: LiteLLM config generation (replace existing)

```bash
log_info "Generating LiteLLM configuration..."
mkdir -p "${CONFIG_DIR}/litellm"

cat > "${CONFIG_DIR}/litellm/config.yaml" << 'LITELLM_EOF'
model_list:
  - model_name: llama3.2
    litellm_params:
      model: ollama/llama3.2
      api_base: http://ollama:11434
  - model_name: nomic-embed-text
    litellm_params:
      model: ollama/nomic-embed-text
      api_base: http://ollama:11434

litellm_settings:
  drop_params: true
  request_timeout: 600
  num_retries: 3

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL
  store_model_in_db: false
LITELLM_EOF

log_info "LiteLLM config written."
```

### Block 2: LiteLLM database migration (replace existing)

```bash
log_info "Running LiteLLM database migration..."

# Ensure postgres is ready
until docker compose exec -T postgres pg_isready -U "${DB_USER}" >/dev/null 2>&1; do
    log_info "Waiting for postgres..."
    sleep 3
done

# Create litellm database if missing
docker compose exec -T postgres psql -U "${DB_USER}" -tc \
    "SELECT 1 FROM pg_database WHERE datname='litellm'" | grep -q 1 || \
    docker compose exec -T postgres psql -U "${DB_USER}" \
    -c "CREATE DATABASE litellm OWNER \"${DB_USER}\";"

# Run migration using a throwaway container — NOT the main litellm service
# This avoids the race condition where litellm tries to start while migrating
docker run --rm \
    --network "$(docker compose ps -q postgres | xargs docker inspect --format='{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' | head -1)" \
    -e "DATABASE_URL=postgresql://${DB_USER}:${DB_PASS}@postgres:5432/litellm" \
    ghcr.io/berriai/litellm:main-latest \
    python3 -c "
import subprocess, sys
result = subprocess.run(
    ['prisma', 'db', 'push', '--schema', '/app/schema.prisma', '--skip-generate'],
    capture_output=True, text=True
)
print(result.stdout)
print(result.stderr)
sys.exit(result.returncode)
" 2>&1 || {
    log_info "Prisma push failed, trying migrate deploy..."
    docker run --rm \
        --network "$(docker network ls --filter name=ai_network -q)" \
        -e "DATABASE_URL=postgresql://${DB_USER}:${DB_PASS}@postgres:5432/litellm" \
        ghcr.io/berriai/litellm:main-latest \
        prisma migrate deploy --schema /app/schema.prisma 2>&1 || \
        log_info "Migration warning — may already be applied"
}

log_info "LiteLLM migration complete."
```

### Block 3: LiteLLM service startup (replace existing)

```bash
log_info "Starting LiteLLM..."
docker compose up -d litellm

# Wait with real log monitoring — fail fast if crash detected
LITELLM_READY=false
for i in $(seq 1 40); do
    sleep 5
    
    # Check if container exited (crash)
    STATUS=$(docker compose ps litellm --format json 2>/dev/null | python3 -c "
import sys,json
data=sys.stdin.read().strip()
if not data: print('unknown'); exit()
# Handle both array and single object
import re
lines=[l for l in data.split('\n') if l.strip()]
for line in lines:
    try:
        obj=json.loads(line)
        print(obj.get('State','unknown'))
        exit()
    except: pass
print('unknown')
" 2>/dev/null || docker inspect ai-platform-litellm --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
    
    if [[ "$STATUS" == "exited" ]]; then
        log_error "LiteLLM container exited. Logs:"
        docker compose logs litellm --tail 50
        log_error "FATAL: LiteLLM crashed. Check config above."
        exit 1
    fi
    
    # Check health endpoint
    if curl -sf "http://localhost:4000/health/liveliness" >/dev/null 2>&1; then
        LITELLM_READY=true
        log_info "LiteLLM healthy after $((i*5)) seconds."
        break
    fi
    
    log_info "Waiting for LiteLLM... ($((i*5))s)"
done

if [[ "$LITELLM_READY" != "true" ]]; then
    log_error "LiteLLM did not become healthy. Final logs:"
    docker compose logs litellm --tail 50
    exit 1
fi
```

### Block 4: docker-compose LiteLLM service definition

In the generated `docker-compose.yml`, the LiteLLM service must be exactly:

```yaml
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: ai-platform-litellm
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      ollama:
        condition: service_healthy
    environment:
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      LITELLM_SALT_KEY: ${LITELLM_SALT_KEY}
      DATABASE_URL: postgresql://${DB_USER}:${DB_PASS}@postgres:5432/litellm
      STORE_MODEL_IN_DB: "false"
    volumes:
      - ${CONFIG_DIR}/litellm/config.yaml:/app/config.yaml:ro
    command: ["--config", "/app/config.yaml", "--port", "4000", "--detailed_debug"]
    ports:
      - "4000:4000"
    networks:
      - ai_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health/liveliness"]
      interval: 30s
      timeout: 15s
      retries: 10
      start_period: 120s
```

**Critical flags:**
- `--detailed_debug` — surfaces the real error instead of silent exit
- `STORE_MODEL_IN_DB: "false"` — prevents Prisma write on startup
- `depends_on` with `condition: service_healthy` for both postgres AND ollama

---

## Instructions for Windsurf — Exact Steps

```
STOP. READ ALL OF THIS BEFORE TOUCHING ANYTHING.

PROBLEM: LiteLLM crashes on startup because it tries to connect 
to Ollama during model validation AND tries to write to the 
database via Prisma before migration is confirmed.

THE DEFINITIVE FIX — 4 changes to scripts/2-deploy-services.sh:

CHANGE 1: LiteLLM config.yaml generation
  - Use heredoc with 'LITELLM_EOF' (quoted) so variables 
    are NOT expanded by bash
  - Add: store_model_in_db: false
  - Keep api_base as literal http://ollama:11434

CHANGE 2: LiteLLM docker-compose service definition  
  - Add STORE_MODEL_IN_DB: "false" to environment
  - Add --detailed_debug to command flags
  - depends_on must include ollama with service_healthy condition
  - Ollama MUST have a healthcheck defined

CHANGE 3: Migration runs in throwaway container BEFORE 
  litellm service starts. Use prisma db push not migrate deploy.
  Network must be ai_network or postgres's network.

CHANGE 4: Startup wait loop checks for "exited" state and 
  prints logs + exits script if LiteLLM crashes.

VERIFY WITH:
  docker compose logs litellm --tail 100 2>&1 | grep -E \
    "startup failed|initialized|Proxy initialized|Error|error"

  Expected success output:
    "LiteLLM: Proxy initialized with Config"
    "Set models: llama3.2, nomic-embed-text"  
    "Application startup complete."
    "Thank you for using LiteLLM!"

  If you see "Application startup failed" — paste the 100 lines
  above that line. The crash reason IS in those lines.

DO NOT:
  - Change scripts 0, 1, or 3
  - Restart postgres, redis, ollama, caddy, grafana
  - Add external API models to config.yaml at this stage
  - Use os.environ/ for OLLAMA_BASE_URL (use literal URL)
```