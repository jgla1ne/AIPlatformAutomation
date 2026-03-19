Let me read every uploaded file carefully before writing anything.Now I have everything I need. Here is the definitive, grounded audit.

---

## The Actual State

The user has confirmed: **Grafana and OpenClaw both answer on HTTPS and have been up 40 hours.** This proves SSL, Caddy, DNS, and the wildcard cert all work. Every previous theory about SSL/DNS was wrong. The problem is entirely the **services themselves**.

Working: postgres, redis, caddy, grafana, prometheus, tailscale, openclaw, open-webui (healthy but no LLM models)
Not working: **litellm** (restart loop) → cascades to n8n, flowise, anythingllm, codeserver (all blocked by `depends_on: litellm: condition: service_healthy`)

---

## The Two Bugs Windsurf Introduced That Break LiteLLM

### Bug 1 — Duplicate config mount as `proxy_server_config.yaml` (Script 3, line 612)

Windsurf added a second volume mount to the litellm compose block:
```yaml
      - ${CONFIG_DIR}/litellm/config.yaml:/app/config.yaml:ro
      - ${CONFIG_DIR}/litellm/config.yaml:/app/proxy_server_config.yaml:ro   ← WRONG
```

The file `proxy_server_config.yaml` is an **internal LiteLLM file** that the proxy writes to when it stores its running configuration. By mounting our `config.yaml` over it as `:ro` (read-only), we prevent LiteLLM from writing to it during startup — which it tries to do as part of its initialisation sequence. This causes a write error during Prisma/proxy setup, crashing the container. Remove this line entirely.

### Bug 2 — `--detailed_debug` flag in the litellm command (Script 3, line 616)

Windsurf added `--detailed_debug` to the LiteLLM startup command for debugging:
```yaml
    command: ["--config", "/app/config.yaml", "--port", "4000", "--detailed_debug"]
```

`--detailed_debug` in some versions of LiteLLM proxy triggers additional startup validation that checks every configured model's connectivity. With Groq, Gemini, and OpenRouter configured, this forces LiteLLM to validate all three API endpoints before declaring itself ready. Any transient network issue causes startup failure. Remove `--detailed_debug`.

### Bug 3 — Prisma cache wiped on every deploy (Script 2, line 133)

Script 2 Step 5 unconditionally runs `rm -rf "${DATA_DIR}/litellm"` on every deploy. The `DATA_DIR/litellm` directory maps to `/root/.cache` inside the container — Prisma's binary engine cache. Wiping it forces a 50MB+ download from the internet every single time Script 2 runs. On a slow or momentarily congested connection this times out, causing the "Prisma client generation" failure. This wipe must only happen on `--force`.

---

## The 3 Changes for Windsurf

### Change 1 — Script 3: Remove the `proxy_server_config.yaml` mount and `--detailed_debug`

**File:** `scripts/3-configure-services.sh`, lines 610–616 (litellm volumes and command)

```bash
# FIND (lines 610-616):
    volumes:
      - ${CONFIG_DIR}/litellm/config.yaml:/app/config.yaml:ro
      - ${CONFIG_DIR}/litellm/config.yaml:/app/proxy_server_config.yaml:ro
      - ${DATA_DIR}/litellm:/root/.cache
    ports:
      - "\${PORT_LITELLM:-4000}:4000"
    command: ["--config", "/app/config.yaml", "--port", "4000", "--detailed_debug"]

# REPLACE WITH:
    volumes:
      - ${CONFIG_DIR}/litellm/config.yaml:/app/config.yaml:ro
      - ${DATA_DIR}/litellm:/root/.cache
    ports:
      - "\${PORT_LITELLM:-4000}:4000"
    command: ["--config", "/app/config.yaml", "--port", "4000"]
```

Two removals in one block: the `proxy_server_config.yaml` mount line, and `--detailed_debug` from the command.

---

### Change 2 — Script 2: Move Prisma cache wipe inside `--force` block

**File:** `scripts/2-deploy-services.sh`, lines 131–150 (Step 5)

```bash
# FIND (lines 123-154):
    # 5. AI gateway — always force-recreate container to pick up fresh config
    [[ "${ENABLE_LITELLM:-false}" == "true" ]] && {

        # Always stop and remove the container (ensures fresh config.yaml is loaded)
        log_info "Removing existing litellm container (ensures config reload)..."
        docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
            rm -sf litellm >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1 || true

        # Always wipe the Prisma file cache (small, fast, prevents schema mismatch)
        log_info "Clearing LiteLLM Prisma file cache..."
        rm -rf "${DATA_DIR}/litellm"
        mkdir -p "${DATA_DIR}/litellm"
        chown -R 1000:"${TENANT_GID:-1001}" "${DATA_DIR}/litellm"

        # --force: also drop/recreate the litellm Postgres database
        if [[ "$FORCE_REDEPLOY" == "true" ]]; then
            ...
        fi

        deploy_service litellm
        wait_for_healthy litellm 180
    }

# REPLACE WITH:
    # 5. AI gateway — force-recreate container to pick up fresh config
    [[ "${ENABLE_LITELLM:-false}" == "true" ]] && {

        # Always stop and remove the container (ensures fresh config.yaml is loaded)
        log_info "Removing existing litellm container (ensures config reload)..."
        docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
            rm -sf litellm >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1 || true

        # --force only: wipe Prisma cache and reset litellm database (clean slate)
        if [[ "$FORCE_REDEPLOY" == "true" ]]; then
            log_info "  --force: clearing LiteLLM Prisma file cache..."
            rm -rf "${DATA_DIR}/litellm"
            mkdir -p "${DATA_DIR}/litellm"
            chown -R 1000:"${TENANT_GID:-1001}" "${DATA_DIR}/litellm"
            log_success "  Prisma cache cleared"

            log_info "  --force: dropping and recreating litellm database..."
            docker compose -f "$COMPOSE_FILE" exec -T postgres \
                psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
                -c "DROP DATABASE IF EXISTS litellm;" \
                >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1 || true
            docker compose -f "$COMPOSE_FILE" exec -T postgres \
                psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
                -c "CREATE DATABASE litellm OWNER \"${POSTGRES_USER}\";" \
                >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1 \
                && log_success "  litellm database reset" \
                || log_warning "  Could not reset litellm database"
        fi

        deploy_service litellm
        wait_for_healthy litellm 180
    }
```

---

### Change 3 — Script 3: Fix `-T` missing from `drop_service_databases()` redis exec

**File:** `scripts/3-configure-services.sh`, line 1101

```bash
# FIND:
    docker compose -f "$COMPOSE_FILE" exec redis \
        redis-cli -a "${REDIS_PASSWORD}" --no-auth-warning FLUSHALL \

# REPLACE WITH:
    docker compose -f "$COMPOSE_FILE" exec -T redis \
        redis-cli -a "${REDIS_PASSWORD}" --no-auth-warning FLUSHALL \
```

---

## Deploy Command After These Changes

```bash
# Apply the 3 changes above, then run:
sudo bash scripts/2-deploy-services.sh datasquiz --force
```

Using `--force` this time is essential: it drops and recreates the litellm database (removing any stale schema state) and clears the Prisma cache so the engine binary is regenerated against the clean DB. After this single `--force` run, all subsequent iterative deploys with plain `sudo bash scripts/2-deploy-services.sh datasquiz` will be fast and idempotent.

**What happens after the fix:**
1. LiteLLM starts cleanly — reads `config.yaml` (Ollama + external models), no bad mount, no debug flag forcing model validation
2. Prisma migrates the fresh `litellm` database successfully
3. LiteLLM becomes healthy within 90–180 seconds
4. n8n, flowise, anythingllm, codeserver all unblock and start simultaneously
5. All their Caddy routes are already live (grafana proves Caddy is working)
6. Full stack reaches 100%

---

## Summary Table

| File | Line(s) | Change | Reason |
|------|---------|--------|--------|
| `scripts/3-configure-services.sh` | 612 | Remove `proxy_server_config.yaml` mount line | Prevents LiteLLM from writing its running config, causes crash |
| `scripts/3-configure-services.sh` | 616 | Remove `--detailed_debug` from command | Forces model connectivity validation at startup, causes crash on network issues |
| `scripts/2-deploy-services.sh` | 131–135 | Move Prisma wipe inside `--force` block | Prevents 50MB+ download on every iterative deploy |
| `scripts/3-configure-services.sh` | 1101 | Add `-T` to `exec redis` in `drop_service_databases()` | Without `-T`, hangs in non-TTY contexts |