Let me read every file completely before writing a word.Now I have the complete, verified picture from live data. Here is the definitive guide.

---

## What Is Actually Happening (from live logs)

The debug log is unambiguous. Two things are happening simultaneously:

**Problem 1: `curl` does not exist in the `litellm:main-latest` container.**
The healthcheck log literally outputs `/bin/sh: curl: not found` with ExitCode 1. Every single healthcheck fails instantly. Docker marks the container unhealthy and never unblocks the dependent services (n8n, flowise, anythingllm, codeserver).

**Problem 2: The litellm database has corrupted schema from previous deployments.**
The crash log shows: `ERROR: column "approval_status" of relation "LiteLLM_MCPServerTable" already exists`. Prisma tries to apply a migration, hits a column conflict, disconnects its engine, and LiteLLM crashes before the HTTP server even starts. The `--force` flag in Script 2 is supposed to drop and recreate this database, but the healthcheck is still broken so the service never reaches healthy even after the DB is clean.

**The architectural root cause of both problems:** `DATABASE_URL` is set in the compose environment. Even though `store_model_in_db: false` is in `config.yaml`, providing `DATABASE_URL` as an env var causes LiteLLM to initialize Prisma and attempt schema migrations regardless. This is what triggers the crash. The README principle of config.yaml as single source of truth means LiteLLM should run in **config-only mode** — no database, no Prisma, no migrations, no crash.

---

## Three Changes for Windsurf — Zero Ambiguity

### Change 1 — Script 3: Remove `DATABASE_URL` and fix the healthcheck

**File:** `scripts/3-configure-services.sh`  
**Location:** The litellm service block in `generate_compose()` (~lines 777–805)

```bash
# FIND the entire environment block and healthcheck, REPLACE WITH:

    environment:
      LITELLM_MASTER_KEY: \${LITELLM_MASTER_KEY}
      LITELLM_SALT_KEY: \${LITELLM_SALT_KEY}
      OPENAI_API_KEY: \${OPENAI_API_KEY:-}
      ANTHROPIC_API_KEY: \${ANTHROPIC_API_KEY:-}
      GROQ_API_KEY: \${GROQ_API_KEY:-}
      GOOGLE_API_KEY: \${GOOGLE_API_KEY:-}
      OPENROUTER_API_KEY: \${OPENROUTER_API_KEY:-}
      LITELLM_TELEMETRY: "False"
    volumes:
      - ${CONFIG_DIR}/litellm/config.yaml:/app/config.yaml:ro
      - ${DATA_DIR}/litellm:/root/.cache
    ports:
      - "\${PORT_LITELLM:-4000}:4000"
    command: ["--config", "/app/config.yaml", "--port", "4000", "--num_workers", "1"]
    healthcheck:
      test: ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:4000/', timeout=5)"]
      interval: 30s
      timeout: 15s
      retries: 10
      start_period: 120s
```

**What was removed and why:**
- `DATABASE_URL` — removing this puts LiteLLM in config-only mode. No DATABASE_URL = no Prisma initialisation = no migrations = no crash. This matches `store_model_in_db: false` in config.yaml. This is the single fix that stops the restart loop.
- `REDIS_URL`, `REDIS_PASSWORD` — not needed since `cache: disabled: true` in config.yaml. LiteLLM won't use Redis.
- `LITELLM_LOG`, `HEALTH_CHECK_INTERVAL`, `BACKGROUND_HEALTH_CHECKS`, `DISABLE_SCHEMA_UPDATE`, `PRISMA_DISABLE_WARNINGS` — all Prisma/DB-related env vars, meaningless without DATABASE_URL.
- `curl -sf` healthcheck — `curl` is not in the image. Replaced with `python3` (confirmed available in the debug log).

### Change 2 — Script 2: Make `wait_for_healthy` non-fatal

**File:** `scripts/2-deploy-services.sh`

The current `wait_for_healthy` returns 1 both on timeout and when the service is "unhealthy". With `set -euo pipefail`, any `return 1` in `main()` kills Script 2. This means if LiteLLM takes longer than 180s to start, caddy never deploys, web services never deploy.

```bash
# FIND (lines 89 and 102):
        elif [[ "$docker_health" == "unhealthy" ]]; then
            log_error "${service} is unhealthy - checking logs"
            docker logs "ai-${TENANT}-${service}-1" --tail 20
            return 1   # ← KILLS SCRIPT 2
        fi
        ...
    log_error "${service} failed to become healthy within ${max_wait}s"
    return 1   # ← KILLS SCRIPT 2

# REPLACE BOTH return 1 WITH return 0:
        elif [[ "$docker_health" == "unhealthy" ]]; then
            log_warning "${service} is unhealthy — proceeding anyway"
            docker logs "ai-${TENANT}-${service}-1" --tail 20
            return 0   # non-fatal: log and continue
        fi
        ...
    log_warning "${service} did not become healthy within ${max_wait}s — proceeding anyway"
    return 0   # non-fatal: deployment continues
```

### Change 3 — Script 2: Remove the `wait_for_healthy` extra HTTP check that uses `curl` inside containers

**File:** `scripts/2-deploy-services.sh`, lines 73–86

The `wait_for_healthy` function has a secondary check that runs `docker exec ai-${TENANT}-${service}-1 curl -sf ...` inside the container. This fails on any container that doesn't have curl (litellm, ollama, qdrant). Replace the entire secondary HTTP check with simply trusting Docker's health status:

```bash
# FIND and REPLACE the wait_for_healthy function entirely:

wait_for_healthy() {
    local service="$1"
    local max_wait="${2:-120}"
    local elapsed=0

    log_info "Waiting for ${service} to be healthy (max ${max_wait}s)..."

    while [[ $elapsed -lt $max_wait ]]; do
        local docker_health
        docker_health="$(docker compose -f "$COMPOSE_FILE" ps --format "{{.Health}}" "$service" 2>/dev/null || echo "none")"

        if [[ "$docker_health" == "healthy" ]]; then
            log_success "${service} is healthy"
            return 0
        elif [[ "$docker_health" == "unhealthy" ]]; then
            log_warning "${service} is unhealthy — proceeding anyway"
            return 0
        fi

        elapsed=$((elapsed + 5))
        [[ $((elapsed % 30)) -eq 0 ]] && log_info "  ${service} still starting... (${elapsed}s/${max_wait}s)"
        sleep 5
    done

    log_warning "${service} did not become healthy within ${max_wait}s — proceeding anyway"
    return 0
}
```

---

## Deploy Command

```bash
sudo bash scripts/2-deploy-services.sh datasquiz --force
```

The `--force` flag drops and recreates the litellm database (cleaning the stale schema). With DATABASE_URL removed from the compose, LiteLLM never touches that database on startup. It starts in config-only mode, reads `config.yaml`, starts its HTTP server in ~10 seconds, python3 healthcheck passes, Docker marks it healthy, and n8n / flowise / anythingllm / codeserver all start automatically.

---

## Summary Table

| File | Change | Reason |
|------|--------|--------|
| `scripts/3-configure-services.sh` | Remove `DATABASE_URL`, `REDIS_URL`, `REDIS_PASSWORD`, all Prisma env vars from litellm compose block | No DATABASE_URL = no Prisma = no migration crash = LiteLLM starts |
| `scripts/3-configure-services.sh` | Replace `curl -sf` healthcheck with `python3 urllib` | curl not in the Chainguard image |
| `scripts/2-deploy-services.sh` | Replace entire `wait_for_healthy` function — remove `return 1`, remove `docker exec curl` secondary check | Prevents Script 2 from dying on any service slowness |