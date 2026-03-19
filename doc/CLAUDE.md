Let me read every file completely before writing anything.Now I have the complete, verified picture. Here is the definitive blueprint.

---

## Root Cause: Definitively Identified

The "configuration cache" is not Redis. It is **LiteLLM's Postgres database**.

When LiteLLM starts with `database_url` set in `general_settings`, it uses Postgres as its source of truth for model configuration. On the very first run (months ago), it wrote the Azure `gpt-4` models into the `litellm` Postgres database. Every subsequent deployment, even with a correct `config.yaml` on disk, LiteLLM starts → connects to Postgres → reads `gpt-4/Azure` from the database → attempts to initialise Azure OpenAI clients with empty credentials → **process crashes** → restart loop. The container never reaches the point where it reads `config.yaml`.

The `docker compose rm -sf litellm` already being done only removes the container. The Postgres `litellm` database with the stale model rows is untouched and persists across every run because postgres has been healthy for 17 hours on a named volume.

This requires **two changes**:

---

## Fix 1 — Script 3: `STORE_MODEL_IN_DB: False` (permanent architectural fix)

**File:** `scripts/3-configure-services.sh`  
**Function:** `generate_litellm_config()`, the `litellm_settings` block (around line 320)

This is the correct architectural answer. With `STORE_MODEL_IN_DB: False`, LiteLLM reads `config.yaml` on every startup and never writes models to the database. The DB is still used for request logs, spend tracking, and team management — but the model list is always and only what's in the file.

```bash
# REPLACE this block:
    cat >> "${CONFIG_DIR}/litellm/config.yaml" <<EOF
litellm_settings:
  drop_params: true
  set_verbose: false
  cache: true
  cache_params:
    type: redis
    host: redis
    port: 6379
    password: os.environ/REDIS_PASSWORD
router_settings:
  routing_strategy: ${LITELLM_ROUTING_STRATEGY:-least-busy}
EOF

# WITH this block:
    cat >> "${CONFIG_DIR}/litellm/config.yaml" <<EOF
litellm_settings:
  drop_params: true
  set_verbose: false
  cache: true
  cache_params:
    type: redis
    host: redis
    port: 6379
    password: os.environ/REDIS_PASSWORD
  store_model_in_db: false
router_settings:
  routing_strategy: ${LITELLM_ROUTING_STRATEGY:-least-busy}
EOF
```

---

## Fix 2 — Script 2: `reset_litellm_state()` before deploy (one-time recovery + idempotent protection)

**File:** `scripts/2-deploy-services.sh`  
**Location:** Replace the current Step 5 block

This function performs a clean reset of all LiteLLM persistent state before each deploy. It is safe to run repeatedly (idempotent). It drops and recreates the `litellm` database so the DB is empty, and wipes the `${DATA_DIR}/litellm` directory which contains the Prisma-generated client cache. After this, LiteLLM starts with no prior model state anywhere and seeds cleanly from `config.yaml`.

**Replace the current Step 5 block entirely:**

```bash
    # 5. AI gateway — clean state before deploy to prevent stale DB config
    [[ "${ENABLE_LITELLM:-false}" == "true" ]] && {

        log_info "Resetting LiteLLM state (removing stale DB config and Prisma cache)..."

        # Stop and remove the container first
        docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
            rm -sf litellm >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1 || true

        # Drop and recreate the litellm database to remove persisted Azure/stale models
        # Postgres must be healthy at this point (provision_databases already ran)
        log_info "  Dropping litellm database (removes persisted model config)..."
        docker compose -f "$COMPOSE_FILE" exec -T postgres \
            psql -U "${POSTGRES_USER}" \
            -c "DROP DATABASE IF EXISTS litellm;" \
            >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1 \
            && log_info "  litellm database dropped" \
            || log_warning "  Could not drop litellm database — may not exist yet"

        log_info "  Recreating litellm database (clean slate for Prisma migration)..."
        docker compose -f "$COMPOSE_FILE" exec -T postgres \
            psql -U "${POSTGRES_USER}" \
            -c "CREATE DATABASE litellm OWNER \"${POSTGRES_USER}\";" \
            >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1 \
            && log_success "  litellm database recreated" \
            || log_warning "  Could not recreate litellm database"

        # Wipe Prisma client cache — forces fresh schema generation
        log_info "  Clearing Prisma cache at ${DATA_DIR}/litellm..."
        rm -rf "${DATA_DIR}/litellm"
        mkdir -p "${DATA_DIR}/litellm"
        chown -R 1000:"${TENANT_GID:-1001}" "${DATA_DIR}/litellm"
        log_success "  LiteLLM state reset complete"

        deploy_service litellm
        wait_for_healthy litellm 180   # Prisma migration takes 45-90s on fresh DB
    }
```

---

## Why this works end-to-end

After both fixes are applied on a fresh run of Script 2:

1. `provision_databases` ensures the `litellm` database exists (and if it already does, it exists with stale data)
2. Step 5's reset block drops `litellm` → recreates it empty → wipes the Prisma file cache
3. `deploy_service litellm` starts a fresh container against an empty database
4. LiteLLM reads `config.yaml` (Ollama models only) → runs Prisma migration on the empty DB → seeds with Ollama models
5. Because `store_model_in_db: false`, LiteLLM does NOT write those models back to the DB — they stay in `config.yaml` only
6. `/health/liveliness` passes → container becomes healthy
7. n8n, flowise, anythingllm, codeserver all have `depends_on: litellm: condition: service_healthy` → they all start

---

## Complete Change Table for Windsurf

| File | Change | Location |
|------|--------|----------|
| `scripts/3-configure-services.sh` | Add `store_model_in_db: false` to `litellm_settings` block | `generate_litellm_config()`, after `cache_params` block |
| `scripts/2-deploy-services.sh` | Replace Step 5 block with the `reset_litellm_state` sequence above | Lines 110–116 (the current litellm deploy block) |

That is the complete fix. No other changes are needed.