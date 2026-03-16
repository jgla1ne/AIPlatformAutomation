# AI Platform — Definitive Implementation Blueprint v2
**Read every line. Implement exactly what is written. Verify each section before moving to the next.**

---

## Confirmed Architecture from README (Non-Negotiable)

```
0-complete-cleanup.sh   → Nuclear wipe, no sourcing required
1-setup-system.sh       → Input collector ONLY, sources Script 3 for ALL operations
2-deploy-services.sh    → Deployment engine ONLY, sources Script 3 for ALL operations  
3-configure-services.sh → Mission Control library: all functions, all config generation
```

**Core principles that cannot be violated:**
- Nothing as root — all services run under tenant UID/GID
- Data confinement — **everything under `/mnt/data/<tenant>/`**, no exceptions, no `/opt`
- Zero hardcoded values — all configuration via `.env`
- `.env` lives at `/mnt/data/<tenant>/.env` — this is Script 3's `ENV_FILE`
- Script 3 is sourced, not called. Its `(return 0 2>/dev/null) && return` guard handles this correctly
- `generate_compose` is called by Script 2, NOT Script 1

---

## What the Uploaded Code Actually Contains (Honest Audit)

### Script 3 (3-configure-services.sh) — STATUS: SOLID, has one broken function

Script 3 is architecturally correct. The library pattern works. Functions are well-written.
`deploy_service`, `provision_databases`, `generate_compose`, `generate_configs`, `health_dashboard`,
`configure_tailscale`, `setup_gdrive_rclone` are all correct.

**ONE broken function: `generate_caddyfile` (lines 284–349)**

The heredoc is opened but never closed before the conditional blocks start.
Line 303 attempts a bash `[[ ... ]] && cat >> ...` INSIDE a heredoc — this is treated as literal text,
not executed code. The result is a Caddyfile containing bash source code, not Caddy directives.

**Exact bug — lines 296–309:**
```bash
cat > "$out" <<EOF
{
    admin 0.0.0.0:2019
    email ${ADMIN_EMAIL:-admin@${DOMAIN}}
}

# Only add service blocks if services are enabled
[[ "${ENABLE_GRAFANA:-false}" == "true" ]] && cat >> "$out" <<EOF   ← THIS IS INSIDE THE HEREDOC
```

The EOF that closes the `cat > "$out"` heredoc is never reached because the `[[ ... ]]` line
is treated as literal content. The Caddyfile that gets written contains bash conditionals as text.

**Fix: close the global block heredoc, then use separate conditional appends.**

Also: the `generate_postgres_init` function (lines 184–213) uses `$POSTGRES_PASSWORD` unquoted
inside the inner psql heredoc. The psql `CREATE ROLE` syntax requires the password to be a
quoted string literal. Without quotes around the password value, psql will fail to parse it.

**Fix: quote the password in the CREATE ROLE statement.**

Also: `generate_compose` (line 393) uses a `<<'EOF'` (single-quoted, no expansion) for the
postgres service block (lines 393–437) but then the postgres service references
`${CONFIG_DIR}/postgres/init-all-databases.sh` on line 417. With `<<'EOF'`, this `${CONFIG_DIR}`
is NOT expanded — Docker Compose will receive the literal string `${CONFIG_DIR}` and try to
expand it at runtime from the `.env` file. This is actually **correct behaviour** — Docker Compose
does expand `${VAR}` from `--env-file`. **This is fine, no change needed.**

However: the `caddy` service block (lines 692–718) switches to a `<<EOF` (no quotes, expands now)
which means `${CONFIG_DIR}` and `${DATA_DIR}` ARE expanded at generation time into absolute paths.
This is inconsistent — caddy will have hardcoded paths while postgres uses runtime expansion.
For consistency and correctness, **make caddy use `<<'EOF'` like the other services.**

### Script 2 (2-deploy-services.sh) — STATUS: CORRECT

Script 2 is architecturally correct. It:
- Sets `TENANT` before sourcing Script 3 ✓
- Loads `.env` from `/mnt/data/${TENANT}/.env` ✓
- Sources Script 3 which exports all functions ✓
- Calls `prepare_directories`, `generate_configs`, `generate_compose` ✓
- Calls `provision_databases` after postgres starts ✓
- Deploys in correct dependency order ✓
- Uses `service_is_enabled()` instead of grep ✓
- Uses `(return 0 2>/dev/null) || main "$@"` guard ✓

**No changes needed to Script 2.**

### Script 1 (1-setup-system.sh) — STATUS: ARCHITECTURALLY BROKEN in 4 ways

**Problem 1: TENANT_ID vs TENANT_NAME variable confusion (lines 2940–2965)**

`main()` collects input into `TENANT_NAME` but the rest of Script 1 uses `TENANT_ID` everywhere.
Line 2961 sets `TENANT_ID` from the CLI argument. Line 2944 sets `TENANT_NAME` from interactive input.
These are never reconciled. `write_env_file` uses `TENANT_ID` (line 2149: `COMPOSE_PROJECT_NAME="${PROJECT_PREFIX}${TENANT_ID}"`).
But the `source` of Script 3 on line 3005 does `export TENANT="${TENANT_ID}"` — which may be empty
if the user went through the interactive path (which sets `TENANT_NAME`, not `TENANT_ID`).

**Fix: After the interactive collection block, always set `TENANT_ID="${TENANT_NAME}"`**

**Problem 2: Script 1 calls `write_caddyfile` and `write_prometheus_config` directly (lines 3013–3014)**

The README states: **"Script 1 MUST source Script 3 for ALL operations — No direct operations in Script 1"**

Script 1 has its own `write_caddyfile` function (starting line 2550) and calls it directly.
Script 3 has `generate_caddyfile`. These are two separate implementations of the same function.
This violates the single-source-of-truth principle and means the Caddyfile is generated twice —
first by Script 1's own `write_caddyfile`, then again by Script 2 via Script 3's `generate_caddyfile`.
The two implementations produce different output (different path variables, different format).

**Fix: Remove `write_caddyfile` and `write_prometheus_config` calls from Script 1's `main()`.
Script 2 calls `generate_configs()` which calls `generate_caddyfile()` and `generate_prometheus_config()`.**

**Problem 3: Script 1 calls `generate_postgres_init` directly (line 3002)**

Same principle violation. Script 1 calls `generate_postgres_init` which is defined in Script 3
(Script 1 sources Script 3 on line 3005 — but calls `generate_postgres_init` at line 3002,
BEFORE sourcing Script 3). This means `generate_postgres_init` is not yet defined when called.

**Fix: Move the `source "${SCRIPTS_DIR}/3-configure-services.sh"` call to BEFORE any calls
to Script 3 functions. Then remove the direct `generate_postgres_init` call from Script 1 —
Script 2 calls `generate_configs()` which handles this.**

**Problem 4: `ENV_FILE` path inconsistency between Script 1 and Script 3**

Script 1 `main()` sets:
```bash
ENV_FILE="${DATA_ROOT}/.env"   # = /mnt/data/${TENANT_NAME}/.env
```

Script 3 sets:
```bash
ENV_FILE="${TENANT_DIR}/.env"  # = /mnt/data/${TENANT}/.env
```

These resolve to the same path IF `TENANT_NAME` in Script 1 matches `TENANT` in Script 3.
But Script 1 `write_env_file` writes `TENANT_DIR=${DATA_ROOT}` (line 2378), and Script 3 sets
`TENANT_DIR="${MNT_ROOT}/${TENANT}"`. These are equivalent. The path is consistent.
**No change needed here — just confirm the TENANT_ID fix in Problem 1 resolves the variable.**

### Script 0 (0-complete-cleanup.sh) — STATUS: CORRECT

Script 0 is correct. Nuclear wipe works. `COMPLETE_WIPE=true` support works.
No changes needed.

---

## The Four Exact Fixes Required

### FIX 1 — Script 3: Repair `generate_caddyfile`

**File:** `scripts/3-configure-services.sh`
**Lines to replace:** 284–349 (the entire `generate_caddyfile` function)

Replace with:

```bash
generate_caddyfile() {
    local out="${CONFIG_DIR}/caddy/Caddyfile"
    mkdir -p "$(dirname "$out")"

    # Choose TLS directive once based on USE_LETSENCRYPT
    local tls_line
    if [[ "${USE_LETSENCRYPT:-false}" == "true" ]]; then
        tls_line="tls ${ADMIN_EMAIL}"
    else
        tls_line="tls internal"
    fi

    # Write global block — heredoc closed BEFORE conditional appends
    cat > "$out" <<EOF
{
    admin 0.0.0.0:2019
    email ${ADMIN_EMAIL:-admin@${DOMAIN:-localhost}}
}
EOF

    # Append one block per enabled service — each is a separate cat call
    [[ "${ENABLE_MONITORING:-false}" == "true" ]] && cat >> "$out" <<EOF
grafana.${DOMAIN} {
    ${tls_line}
    reverse_proxy grafana:3000
}
prometheus.${DOMAIN} {
    ${tls_line}
    reverse_proxy prometheus:9090
}
EOF

    [[ "${ENABLE_LITELLM:-false}" == "true" ]] && cat >> "$out" <<EOF
litellm.${DOMAIN} {
    ${tls_line}
    reverse_proxy litellm:4000
}
EOF

    [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] && cat >> "$out" <<EOF
chat.${DOMAIN} {
    ${tls_line}
    reverse_proxy open-webui:8080
}
EOF

    [[ "${ENABLE_N8N:-false}" == "true" ]] && cat >> "$out" <<EOF
n8n.${DOMAIN} {
    ${tls_line}
    reverse_proxy n8n:5678
}
EOF

    [[ "${ENABLE_FLOWISE:-false}" == "true" ]] && cat >> "$out" <<EOF
flowise.${DOMAIN} {
    ${tls_line}
    reverse_proxy flowise:3000
}
EOF

    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && cat >> "$out" <<EOF
anythingllm.${DOMAIN} {
    ${tls_line}
    reverse_proxy anythingllm:3001
}
EOF

    log_success "Caddyfile written to ${out}"
}
```

---

### FIX 2 — Script 3: Fix `generate_postgres_init` password quoting

**File:** `scripts/3-configure-services.sh`
**Lines to replace:** 195–196 (the CREATE ROLE statement inside the init script heredoc)

Current broken line:
```bash
      CREATE ROLE aiplatform WITH LOGIN PASSWORD \$POSTGRES_PASSWORD;
```

Replace with (single-quoted literal — the init script resolves this at container startup):
```bash
      CREATE ROLE aiplatform WITH LOGIN PASSWORD '${POSTGRES_PASSWORD}';
```

**Full corrected function context** — the relevant psql block should read:
```sql
  DO $$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'aiplatform') THEN
      CREATE ROLE aiplatform WITH LOGIN PASSWORD '${POSTGRES_PASSWORD}';
    END IF;
  END $$;
```

Note: `${POSTGRES_PASSWORD}` is expanded by bash at generation time (double-quoted heredoc `<<EOF`),
so the actual password value is written into the init script. This is correct.

---

### FIX 3 — Script 3: Fix `generate_compose` caddy block to use `<<'EOF'`

**File:** `scripts/3-configure-services.sh`
**Lines to replace:** 692–718 (the caddy service block)

Change `<<EOF` to `<<'EOF'` so caddy uses runtime expansion consistent with all other services:

```bash
    # Caddy - always deployed as reverse proxy
    cat >> "$COMPOSE_FILE" <<'EOF'
  caddy:
    image: caddy:2-alpine
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
    volumes:
      - ${CONFIG_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ${CONFIG_DIR}/caddy/data:/data
      - ${CONFIG_DIR}/caddy/config:/config
    healthcheck:
      test: ["CMD-SHELL","wget -qO- http://localhost:2019/metrics > /dev/null"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF
```

Also remove the `environment:` block from caddy (lines 709–711 in current file):
```yaml
    environment:
      - CONFIG_DIR=${CONFIG_DIR}
      - DATA_DIR=${DATA_DIR}
```
Caddy does not use these env vars — they serve no purpose and clutter the config.

---

### FIX 4 — Script 1: Three surgical changes to `main()`

**File:** `scripts/1-setup-system.sh`
**Section:** The `main()` function (lines 2941–3018)

**Change A:** After the tenant collection block (after line 2963), add the reconciliation line:
```bash
    # Reconcile — TENANT_ID is the canonical variable used throughout Script 1
    # TENANT_NAME comes from interactive input; TENANT_ID from CLI arg
    # After this line both are always set and equal
    TENANT_ID="${TENANT_ID:-${TENANT_NAME}}"
    TENANT_NAME="${TENANT_ID}"
```

**Change B:** Move the `source` of Script 3 to BEFORE any calls to Script 3 functions.
Current order (broken):
```
line 2999: write_env_file
line 3002: generate_postgres_init   ← Script 3 function, called BEFORE source
line 3004: export TENANT
line 3005: source Script 3          ← too late
```

Correct order:
```bash
    write_env_file
    
    # Source Script 3 FIRST — all subsequent operations use its functions
    export TENANT="${TENANT_ID}"
    source "${SCRIPTS_DIR}/3-configure-services.sh"
    
    create_directories
    apply_final_ownership
    # DO NOT call generate_postgres_init, write_caddyfile, write_prometheus_config here.
    # Script 2 calls generate_configs() which handles all of these.
```

**Change C:** Remove these three lines from `main()`:
```bash
    generate_postgres_init       # ← DELETE: Script 2 does this via generate_configs()
    write_caddyfile              # ← DELETE: Script 2 does this via generate_configs()
    write_prometheus_config      # ← DELETE: Script 2 does this via generate_configs()
```

The corrected `main()` call sequence:
```bash
main() {
    # ... (unchanged: tenant collection, path derivation, arg handling)
    
    print_header
    check_root
    check_prerequisites
    collect_identity
    detect_and_mount_ebs
    select_data_volume
    detect_gpu
    select_stack
    configure_dify
    select_vector_db
    collect_database
    collect_llm_config
    collect_litellm_routing
    collect_network_config
    collect_ports
    generate_secrets
    
    # Generate all application secrets
    load_or_generate_secret "N8N_ENCRYPTION_KEY"
    load_or_generate_secret "FLOWISE_SECRET_KEY"
    load_or_generate_secret "LITELLM_MASTER_KEY"
    load_or_generate_secret "LITELLM_SALT_KEY"
    load_or_generate_secret "ANYTHINGLLM_JWT_SECRET"
    load_or_generate_secret "JWT_SECRET"
    load_or_generate_secret "ENCRYPTION_KEY"
    load_or_generate_secret "QDRANT_API_KEY"
    load_or_generate_secret "GRAFANA_PASSWORD"
    load_or_generate_secret "AUTHENTIK_SECRET_KEY"
    load_or_generate_secret "OPENWEBUI_SECRET_KEY"
    load_or_generate_secret "REDIS_PASSWORD"
    load_or_generate_secret "POSTGRES_PASSWORD"
    
    # Reconcile tenant variables
    TENANT_ID="${TENANT_ID:-${TENANT_NAME}}"
    TENANT_NAME="${TENANT_ID}"
    
    print_summary
    write_env_file
    
    # Source Script 3 AFTER .env is written so functions can load it
    export TENANT="${TENANT_ID}"
    source "${SCRIPTS_DIR}/3-configure-services.sh"
    
    # Directories and ownership — Script 1's responsibility
    create_directories
    apply_final_ownership
    
    # Config generation is Script 2's responsibility (via generate_configs)
    # DO NOT call generate_postgres_init, write_caddyfile, write_prometheus_config here
    
    offer_next_step
}
```

---

## Verification Steps After Each Fix

Run these in order. Do not proceed to the next fix until the current one passes.

### After Fix 1 (generate_caddyfile):
```bash
# Test by sourcing Script 3 and calling the function with test vars
TENANT=test DOMAIN=example.com ADMIN_EMAIL=test@example.com \
  ENABLE_LITELLM=true ENABLE_OPENWEBUI=true ENABLE_MONITORING=false \
  CONFIG_DIR=/tmp/caddy-test bash -c '
    mkdir -p /tmp/caddy-test/caddy
    source scripts/3-configure-services.sh
    generate_caddyfile
    echo "=== Generated Caddyfile ==="
    cat /tmp/caddy-test/caddy/Caddyfile
    grep -v "^\s*$" /tmp/caddy-test/caddy/Caddyfile | grep "\[\[" \
      && echo "FAIL: bash code in Caddyfile" \
      || echo "PASS: no bash code in Caddyfile"
  '
```
Expected: clean Caddyfile with global block + litellm and chat blocks. No `[[` characters.

### After Fix 2 (postgres init password quoting):
```bash
grep "CREATE ROLE" /mnt/data/datasquiz/configs/postgres/init-all-databases.sh 2>/dev/null \
  || grep "CREATE ROLE" scripts/3-configure-services.sh
```
Expected: `CREATE ROLE aiplatform WITH LOGIN PASSWORD '...'` with single quotes around the value.

### After Fix 3 (caddy heredoc):
```bash
grep -A 5 "caddy:" /mnt/data/datasquiz/docker-compose.yml 2>/dev/null | grep CONFIG_DIR
```
Expected: `${CONFIG_DIR}` (literal, not expanded path).

### After Fix 4 (Script 1 main):
```bash
# Dry run — check the call order in main()
grep -n "source.*3-configure\|generate_postgres_init\|write_caddyfile\|write_prometheus\|export TENANT" \
  scripts/1-setup-system.sh | tail -20
```
Expected: `export TENANT` and `source ...3-configure-services.sh` appear BEFORE the end of `main()`,
and `generate_postgres_init`, `write_caddyfile`, `write_prometheus_config` do NOT appear in `main()`.

---

## Full End-to-End Test After All Four Fixes

```bash
# 1. Nuclear wipe
sudo bash scripts/0-complete-cleanup.sh datasquiz

# 2. Collect config (Script 1 — input only, sources Script 3)
sudo bash scripts/1-setup-system.sh
# → Enter tenant: datasquiz
# → Follow prompts, select LiteLLM + Ollama + OpenWebUI + Qdrant + Monitoring
# → Script writes /mnt/data/datasquiz/.env and creates directories
# → Script does NOT generate compose, does NOT start services

# 3. Verify .env exists and has correct paths
grep "TENANT_DIR\|ENV_FILE\|COMPOSE_FILE\|LITELLM_DATABASE_URL\|OPENWEBUI_DATABASE_URL" \
  /mnt/data/datasquiz/.env

# 4. Deploy (Script 2 — generates compose, starts services)
sudo bash scripts/2-deploy-services.sh datasquiz

# 5. Verify per-service databases were created
sudo docker compose -f /mnt/data/datasquiz/docker-compose.yml \
  exec postgres psql -U aiplatform -c "\l" | grep -E "litellm|openwebui|n8n"

# 6. Verify LiteLLM starts (allow 90s for Prisma migration)
sleep 90
curl -sf http://localhost:4000/health/liveliness && echo "LiteLLM: OK"

# 7. Health dashboard
sudo bash scripts/3-configure-services.sh datasquiz health

# 8. Enable a service post-deploy
sudo bash scripts/3-configure-services.sh datasquiz enable n8n
```

---

## Summary Table

| Script | Changes Required | Lines Affected |
|--------|-----------------|----------------|
| `3-configure-services.sh` | Fix `generate_caddyfile` — close heredoc before conditionals | 284–349 |
| `3-configure-services.sh` | Fix `generate_postgres_init` — quote password in CREATE ROLE | ~196 |
| `3-configure-services.sh` | Fix caddy block — `<<'EOF'` not `<<EOF`, remove useless env vars | 692–718 |
| `1-setup-system.sh` | Reconcile `TENANT_ID`/`TENANT_NAME`; move `source` before function calls; remove direct config-gen calls from `main()` | 2941–3018 |
| `2-deploy-services.sh` | **No changes needed** | — |
| `0-complete-cleanup.sh` | **No changes needed** | — |

**Total: 4 fixes across 2 files. Script 2 and Script 0 are correct as committed.**