Let me read every file completely before writing a single word.Now I have the complete picture. Let me write the definitive, architecturally correct blueprint.

---

## What Windsurf Got Wrong — and the Actual Root Cause

Windsurf has been chasing symptoms for 48+ hours: Redis flush, DB drops, Prisma cache wipes, image tag changes. Every one of these was wrong because they were all **band-aid fixes on containers that have not actually been redeployed from the current code**. The audit report shows services "Up 23 hours" — meaning the running containers were started by a deployment that predates all the fixes that have been applied.

Windsurf's manual `docker restart` and `docker compose up -d litellm` commands operated on an **old `docker-compose.yml` that was generated 23 hours ago** — before any of the architectural changes. That old compose file pointed to a `config.yaml` that *at the time of the original deployment* still had Azure models. When litellm restarted from that old compose, it may not have had a properly generated config at all, causing it to fall back to the image's baked-in demo config (which has Azure endpoints). Windsurf then concluded this was "image hardcoding" — it is not.

The **architectural gap that caused all of this** is in `generate_compose()` in Script 3.

---

## The Architectural Root Cause

`generate_compose()` uses `<<'EOF'` (single-quoted heredoc, no expansion) for ALL service blocks. This is intentional — it lets Docker Compose resolve `${POSTGRES_USER}`, `${REDIS_PASSWORD}` etc. from `.env` at runtime. **This is correct for credentials.** But it is wrong for **filesystem paths**.

The critical volume mount on line 612:
```yaml
      - ${CONFIG_DIR}/litellm/config.yaml:/app/config.yaml:ro
```

This writes the literal string `${CONFIG_DIR}` into the compose file. Docker Compose resolves it from `.env` at runtime. This works — when the `.env` is present and correct. But there is a fragility: if `CONFIG_DIR` is empty or wrong in the `.env` (e.g. from a previous run with different settings), the bind mount source path becomes empty, Docker cannot mount it, and LiteLLM silently falls back to the demo config baked into the image. This is also why windsurf's testing was unreliable — they were debugging with a stale compose and stale config simultaneously.

The **correct architectural approach** per the README's "Zero Hardcoded Values" + "Dynamic Config Generation" principles is: **path variables that are fully known at `generate_compose()` time should be expanded at generation time, not deferred to Docker Compose runtime.** `CONFIG_DIR`, `DATA_DIR`, `TENANT_DIR` are all known when `generate_compose()` runs. Only credentials (`POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `LITELLM_MASTER_KEY` etc.) should remain as Docker Compose variables.

---

## The Fix — Two Precise Changes to Script 3

### Change 1: `generate_compose()` — write absolute paths for all volume mounts

**File:** `scripts/3-configure-services.sh`  
**Function:** `generate_compose()`

Change the litellm service block from `<<'EOF'` to `<<EOF` (double-quoted, expands `$CONFIG_DIR` and `$DATA_DIR` at generation time). Also change it to use `--force-recreate` equivalent by removing the named `litellm_data` volume for the cache (use bind mount instead, which the reset can wipe):

**Replace lines 588–623** (the entire `ENABLE_LITELLM` block):

```bash
    [[ "${ENABLE_LITELLM:-false}" == "true" ]] && cat >> "$COMPOSE_FILE" <<EOF
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
      LITELLM_MASTER_KEY: \${LITELLM_MASTER_KEY}
      LITELLM_SALT_KEY: \${LITELLM_SALT_KEY}
      DATABASE_URL: \${LITELLM_DATABASE_URL}
      REDIS_URL: \${REDIS_URL}
      REDIS_PASSWORD: \${REDIS_PASSWORD}
      OPENAI_API_KEY: \${OPENAI_API_KEY:-}
      ANTHROPIC_API_KEY: \${ANTHROPIC_API_KEY:-}
      GROQ_API_KEY: \${GROQ_API_KEY:-}
      GOOGLE_API_KEY: \${GOOGLE_API_KEY:-}
      OPENROUTER_API_KEY: \${OPENROUTER_API_KEY:-}
      LITELLM_TELEMETRY: "False"
      PRISMA_DISABLE_WARNINGS: "true"
    volumes:
      - ${CONFIG_DIR}/litellm/config.yaml:/app/config.yaml:ro
      - ${DATA_DIR}/litellm:/root/.cache
    ports:
      - "\${PORT_LITELLM:-4000}:4000"
    command: ["--config", "/app/config.yaml", "--port", "4000"]
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:4000/health/liveliness || exit 1"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 90s
EOF
```

**What changed:** `<<'EOF'` → `<<EOF`. All `${CREDENTIAL_VAR}` references are escaped with `\${}` so Docker Compose still resolves them at runtime. But `${CONFIG_DIR}` and `${DATA_DIR}` — which are path variables known at generation time — are **not escaped** and therefore expand to absolute paths in the generated file. The generated `docker-compose.yml` will now contain:
```yaml
      - /mnt/data/datasquiz/configs/litellm/config.yaml:/app/config.yaml:ro
      - /mnt/data/datasquiz/data/litellm:/root/.cache
```
No runtime variable resolution needed. The mount cannot fail due to an unset variable.

Apply the exact same `<<'EOF'` → `<<EOF` change with escaped credentials and unescaped paths to **every other service block** that has volume mounts with `${CONFIG_DIR}` or `${DATA_DIR}`: postgres init script mount, all data volume mounts, prometheus config mount, caddyfile mount, and the codeserver/openclaw mounts. The pattern is identical for each: escape `\${CREDENTIAL}`, leave `${PATH_VAR}` unescaped.

---

### Change 2: `generate_compose()` — apply same fix to the static blocks

The initial `cat > "$COMPOSE_FILE" <<'EOF'` block (lines 541–585) containing postgres and redis also has path variables. Change it to `<<EOF` and escape only the credential variables:

**Replace lines 541–585:**

```bash
    cat > "$COMPOSE_FILE" <<EOF
networks:
  default:
    name: ai-\${TENANT}-net
    driver: bridge

volumes:
  postgres_data:
  prometheus_data:
  grafana_data:

services:

  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    user: "\${POSTGRES_UID:-70}:\${TENANT_GID:-1001}"
    environment:
      POSTGRES_DB: \${POSTGRES_DB}
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ${CONFIG_DIR}/postgres/init-all-databases.sh:/docker-entrypoint-initdb.d/init-all-databases.sh:ro
    healthcheck:
      test: ["CMD-SHELL","pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    user: "\${REDIS_UID:-999}:\${TENANT_GID:-1001}"
    command: redis-server --requirepass "\${REDIS_PASSWORD}"
    volumes:
      - ${DATA_DIR}/redis:/data
    healthcheck:
      test: ["CMD","redis-cli","-a","\${REDIS_PASSWORD}","ping"]
      interval: 5s
      timeout: 5s
      retries: 5
EOF
```

**Rule for every heredoc block in `generate_compose()`:**
- `\${POSTGRES_USER}`, `\${REDIS_PASSWORD}`, `\${LITELLM_MASTER_KEY}`, `\${TENANT_GID}`, `\${PORT_*}`, `\${DOMAIN}` — **escape these** (Docker Compose resolves from `.env` at runtime) ✓
- `${CONFIG_DIR}`, `${DATA_DIR}`, `${TENANT_DIR}`, `${COMPOSE_FILE}` — **do NOT escape** (expand to absolute paths at generation time) ✓

---

## What Windsurf Must Do — Exact Sequence

**Step 1:** Apply the changes to `scripts/3-configure-services.sh` as above — convert every `<<'EOF'` in `generate_compose()` to `<<EOF`, escape credential variables with `\${}`, leave path variables unescaped.

**Step 2:** Run the full clean deployment:
```bash
sudo bash scripts/0-complete-cleanup.sh datasquiz
sudo bash scripts/1-setup-system.sh datasquiz
sudo bash scripts/2-deploy-services.sh datasquiz --force
```

This is not optional. The 23-hour-old containers must be fully replaced. Script 0 wipes everything. Script 1 regenerates `.env`. Script 2 `--force` generates a fresh compose with absolute paths, drops and recreates service databases, wipes the litellm Prisma cache, and deploys all services.

**After this, to verify the fix worked:**
```bash
# Confirm the generated compose has absolute paths (not variables):
grep "config.yaml" /mnt/data/datasquiz/docker-compose.yml
# Expected: - /mnt/data/datasquiz/configs/litellm/config.yaml:/app/config.yaml:ro

# Confirm litellm loaded the correct config:
docker logs ai-datasquiz-litellm-1 2>&1 | grep -E "model_name|azure|ollama"
# Expected: only "ollama" references, no "azure"
```

This is the **one architectural change** that resolves the problem permanently. No image tag changes. No Redis flushes. No manual database drops needed on every re-run. The generated compose file becomes self-contained with absolute paths, immune to any `.env` loading order, and correct on every subsequent `docker compose` invocation regardless of how it is called.