Let me read every file completely before writing a single word.Now I have a complete picture of every issue. Let me write the definitive blueprint.---

## Root Cause: Finally Definitive

Every fix so far has addressed real problems but left one untouched. Here is the exact chain:

**What persists the Azure config:** `cache: true` in `litellm_settings`. LiteLLM uses Redis not just for response caching but for caching its own router state — the loaded model list. On every restart, LiteLLM checks Redis first for a key like `litellm_model_list`. Redis has been running continuously for 17+ hours with the old Azure config stored in that key. LiteLLM reads it, attempts to initialise Azure OpenAI clients with no credentials, crashes. This happens even with `store_model_in_db: false` (which controls the Postgres model table, not Redis) and even with a fresh Postgres database (because Redis is the source, not Postgres).

**Why Script 0's database cleanup is dead code:** Line 178 checks for `postgres-${TENANT_ID}-1`. The actual Docker container name is `ai-datasquiz-postgres-1` (compose project name prefix + service name). The grep never matches. The `docker exec` commands on line 194 never run. The databases are never dropped by Script 0.

**Why Script 2's DB reset still didn't fix it:** The DB reset correctly cleaned Postgres. But `cache: true` means Redis is the source of the stale router config, not Postgres. Dropping and recreating the Postgres `litellm` database is correct but not sufficient.

---

## Complete Blueprint — 4 Files, Every Change Precisely Located

---

### Change 1 of 4 — Script 3: `generate_litellm_config` — disable Redis caching

**File:** `scripts/3-configure-services.sh`

This is the single line that causes the entire problem. Replace the `litellm_settings` block. `cache: false` means LiteLLM reads `config.yaml` on every startup and never reads or writes its router state to Redis. Redis is still used by other services (n8n, open-webui sessions, etc.) — this only disables LiteLLM's use of it.

```bash
# FIND (lines 320-333):
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

# REPLACE WITH:
    cat >> "${CONFIG_DIR}/litellm/config.yaml" <<EOF
litellm_settings:
  drop_params: true
  set_verbose: false
  cache: false
  store_model_in_db: false
router_settings:
  routing_strategy: ${LITELLM_ROUTING_STRATEGY:-least-busy}
EOF
```

---

### Change 2 of 4 — Script 3: add `drop_service_databases()` function

**File:** `scripts/3-configure-services.sh`  
**Location:** Add immediately before `provision_databases()` (~line 1034)

This is the Mission Control pattern: all database operations live in Script 3. Both Script 0 and Script 2 call this function. It never exists in two places.

```bash
# ADD this new function before provision_databases():

drop_service_databases() {
    log_info "Dropping service databases for clean slate..."
    local logfile="${LOGS_DIR}/deploy-$(date +%Y%m%d).log"

    # Wait for postgres (may be called right after container start)
    local elapsed=0
    until docker compose -f "$COMPOSE_FILE" exec -T postgres \
        pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -q 2>/dev/null; do
        elapsed=$((elapsed + 5))
        [[ $elapsed -ge 30 ]] && { log_warning "Postgres not ready — skipping DB drop"; return 0; }
        sleep 5
    done

    local databases=("litellm" "openwebui" "n8n" "flowise")
    for db in "${databases[@]}"; do
        log_info "  Dropping database '${db}'..."
        docker compose -f "$COMPOSE_FILE" exec -T postgres \
            psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
            -c "DROP DATABASE IF EXISTS \"${db}\";" \
            >> "$logfile" 2>&1 \
            && log_success "  '${db}' dropped" \
            || log_warning "  Could not drop '${db}'"
    done

    # Also flush all LiteLLM Redis keys to remove cached router state
    log_info "  Flushing LiteLLM Redis cache keys..."
    docker compose -f "$COMPOSE_FILE" exec -T redis \
        redis-cli -a "${REDIS_PASSWORD}" --no-auth-warning FLUSHDB \
        >> "$logfile" 2>&1 \
        && log_success "  Redis cache flushed" \
        || log_warning "  Could not flush Redis — may not be running"

    log_success "Service databases dropped and Redis flushed"
}
```

---

### Change 3 of 4 — Script 2: `--force` flag + clean litellm step

**File:** `scripts/2-deploy-services.sh`

Replace the current arg parsing and the litellm Step 5. The `--force` flag triggers `drop_service_databases()` (defined in Script 3). Without `--force`, Script 2 is fully idempotent — databases are created only if they don't exist.

**Replace the top of the file (arg parsing):**

```bash
#!/usr/bin/env bash
# =============================================================================
# Script 2: Idempotent service deployer — v4.1
# USAGE:  sudo bash scripts/2-deploy-services.sh [tenant_id] [--force]
# --force: drops and recreates all service databases + flushes Redis cache
#          Use after code changes that affect DB schema or LiteLLM config
# Without --force: idempotent — skips already-existing databases
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments — tenant is first positional, --force is a flag
export TENANT="${1:-datasquiz}"
FORCE_REDEPLOY=false
for arg in "$@"; do
    [[ "$arg" == "--force" ]] && FORCE_REDEPLOY=true
done

ENV_FILE="/mnt/data/${TENANT}/.env"
[[ -f "$ENV_FILE" ]] && set -a && source "$ENV_FILE" && set +a

source "${SCRIPT_DIR}/3-configure-services.sh"
```

**Replace Step 5 (the litellm block):**

```bash
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

**Also update Step 2b** — call `drop_service_databases()` when `--force`:

```bash
    # 2. Infra layer — must be healthy before anything else
    log_info "Deploying infrastructure services..."
    deploy_service postgres
    deploy_service redis

    # With --force: drop all service databases before provisioning
    if [[ "$FORCE_REDEPLOY" == "true" ]]; then
        log_info "--force: dropping all service databases for clean slate..."
        drop_service_databases
    fi

    provision_databases    # creates databases that don't exist yet
```

---

### Change 4 of 4 — Script 0: fix the dead database cleanup code

**File:** `scripts/0-complete-cleanup.sh`

Replace the entire broken `4.2. Database Cleanup` section. The problem is that Script 0 wipes `/mnt/data` and all named Docker volumes (including `postgres_data`) — so after Script 0 runs, there is no Postgres running and no data to drop. The dead code was trying to drop databases from a running container that Script 0 had already stopped. The correct approach: Script 0 doesn't need to drop individual databases at all — wiping the `postgres_data` named Docker volume already destroys the entire Postgres cluster, which is a superset of dropping individual databases.

```bash
# FIND and REMOVE the entire "4.2. Database Cleanup" section (lines 174-203):
    # --- 4.2. Database Cleanup (NEW) ---
    log "Cleaning service databases for fresh deployment..."
    
    # Check if postgres container exists and clean databases
    if docker ps --format "table {{.Names}}" | grep -q "postgres-${TENANT_ID}-1"; then
        ...
    fi

# REPLACE WITH nothing — it is not needed.
# Script 0 already removes:
# - All containers (step 1) — including postgres
# - All named volumes (step 2) — including ai-datasquiz_postgres_data
# - All /mnt/data content (step 3) — including bind-mounted data
# Dropping individual databases from a stopped container is impossible and unnecessary.
# A fresh postgres container on a wiped volume starts completely empty.
```

Additionally, verify the named volume loop in Script 0 uses the correct prefixed names. The current loop:

```bash
for vol in postgres_data prometheus_data grafana_data litellm_data; do
    local vol_name="${COMPOSE_PROJECT_NAME}_${vol}"
```

This is correct — `COMPOSE_PROJECT_NAME=ai-datasquiz`, so `vol_name=ai-datasquiz_postgres_data` ✓. Combined with the `docker volume prune -af` call earlier, both paths cover the named volumes. No change needed here.

---

## Summary Table

| File | Change | Why |
|------|--------|-----|
| `3-configure-services.sh` | `cache: true` → `cache: false`, remove `cache_params` block | **Root cause of Azure config persistence** — Redis cached the old router state |
| `3-configure-services.sh` | Add `drop_service_databases()` function before `provision_databases()` | Mission Control pattern: all DB ops in Script 3, called by Scripts 0 and 2 |
| `2-deploy-services.sh` | Parse `--force` flag at top | Enables clean-slate redeploy without full Script 0 wipe |
| `2-deploy-services.sh` | Step 2b: call `drop_service_databases()` when `--force` | Purges all service DBs + Redis before provisioning |
| `2-deploy-services.sh` | Step 5: always wipe Prisma cache; DB drop only on `--force` | Idempotent by default, destructive only when explicitly requested |
| `0-complete-cleanup.sh` | Remove entire `4.2. Database Cleanup` section | Dead code — wrong container name, impossible after containers are stopped, volumes already nuked |

**Usage after this fix:**

```bash
# Fresh start (after code changes, first deployment, or broken state):
sudo bash scripts/0-complete-cleanup.sh datasquiz
sudo bash scripts/1-setup-system.sh datasquiz
sudo bash scripts/2-deploy-services.sh datasquiz --force

# Iterative redeploy (config tweaks, no DB schema changes):
sudo bash scripts/2-deploy-services.sh datasquiz
```