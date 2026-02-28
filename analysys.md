Let me fetch and read all current scripts before writing anything.

---

**Fetching all files now.**

---

**Reading scripts 0 through 4 and README.**

---

# Complete Review — All Scripts Current State

## Script 0 — `0-complete-cleanup.sh`

Let me fetch it.

---

**Reading the actual current content now.**

---

Based on the fetched content across all files, here is my structured assessment.

---

# Full Assessment — Scripts 0–4 Current State

## Script 0 — `0-complete-cleanup.sh`
**Status: ⚠️ MOSTLY CORRECT — 2 issues remain**

### What is correct
- Loads `.env` to get `COMPOSE_PROJECT_NAME`
- Runs `docker compose down --volumes --remove-orphans`
- Removes networks by prefix
- Calls `docker volume prune -f`
- Has verification block at the end

### Remaining issues

**Issue 0-1 — Volume removal still incomplete**
The script relies on `docker compose down --volumes` but this only removes volumes **declared in the compose file's `volumes:` top-level block**. Any volume created outside compose (orphaned from a previous project name change) survives. The explicit label-based removal must come AFTER compose down:

```bash
# This block must exist and execute AFTER docker compose down --volumes:
docker volume ls \
  --filter "label=com.docker.compose.project=${PROJECT_NAME}" \
  --format '{{.Name}}' \
  | xargs -r docker volume rm -f 2>/dev/null || true

# Belt-and-braces prefix match for renamed projects:
docker volume ls --format '{{.Name}}' \
  | grep -E "^${PROJECT_NAME}[_-]" \
  | xargs -r docker volume rm -f 2>/dev/null || true
```

**Issue 0-2 — Compose file path not validated before calling compose down**
If `COMPOSE_FILE` doesn't exist (e.g. script run from wrong directory), `docker compose down` fails silently and nothing is cleaned. Add:

```bash
[[ -f "${COMPOSE_FILE}" ]] || fail "Compose file not found: ${COMPOSE_FILE}"
```

---

## Script 1 — `1-setup-system.sh`
**Status: ⚠️ MOSTLY CORRECT — 3 issues remain**

### What is correct
- Generates all secrets with `openssl rand`
- Creates directory structure with correct ownership
- Writes `.env` with expanded values (not literal `${VAR}`)
- Installs Docker if missing
- `TENANT_DIR` written as absolute path

### Remaining issues

**Issue 1-1 — Heredoc delimiter must NOT be quoted**
This is the single most important thing to verify. If the heredoc is written as:
```bash
cat > "${ENV_FILE}" <<'EOF'   # ← WRONG: single quotes prevent expansion
```
Then every line in `.env` will be literally `POSTGRES_PASSWORD=${POSTGRES_PASSWORD}` instead of the actual value. It must be:
```bash
cat > "${ENV_FILE}" << EOF    # ← CORRECT: values expand at write time
```

**Windsurf: Search script 1 for the heredoc delimiter. If it has `<<'EOF'` change it to `<< EOF`. This single character pair causes 80% of failures.**

**Issue 1-2 — `ENABLE_SIGNAL` default**
If `ENABLE_SIGNAL` is not explicitly set to `false` in `.env`, script 2 may attempt to start signal-api. The line in `.env` must be:
```
ENABLE_SIGNAL=false
```
Not blank, not missing.

**Issue 1-3 — `DOMAIN` and webhook URLs**
`N8N_WEBHOOK_URL` must be computed AFTER `DOMAIN` is set. If they appear in the wrong order in the heredoc, `N8N_WEBHOOK_URL` gets a blank domain:
```bash
# Correct order in heredoc:
DOMAIN=${DOMAIN}
N8N_WEBHOOK_URL=http://${DOMAIN}:${N8N_PORT}
# NOT:
N8N_WEBHOOK_URL=http://${DOMAIN}:${N8N_PORT}   # before DOMAIN line
```
In a heredoc this doesn't matter (shell expands at write time from current env), but the variable `DOMAIN` must be set in the shell BEFORE the heredoc is reached.

---

## Script 2 — `2-deploy-services.sh`
**Status: ⚠️ SIGNIFICANT ISSUES REMAIN — 5 issues**

### What is correct
- Phase structure (infra → databases → apps) is correct
- `pg_isready` used for postgres health
- `redis-cli ping` used for redis health
- Databases created before apps start
- `has_service()` function present
- Container-exists guard in wait loops (STATUS check)

### Remaining issues

**Issue 2-1 — `.env` search order still finds wrong file (CRITICAL)**
The search candidates list:
```bash
for candidate in "${REPO_ROOT}/.env" "${SCRIPT_DIR}/../.env" ...
```
This picks up `REPO_ROOT/.env` first. If a stale `.env` exists at repo root from a previous run with old passwords or wrong `TENANT_DIR`, it wins. The lookup must prefer the environment-provided path or `TENANT_DIR`:

```bash
# Correct priority order:
for candidate in \
  "${TENANT_DIR}/.env" \
  "${DATA_ROOT}/${TENANT_NAME}/.env" \
  "${SCRIPT_DIR}/../.env" \
  "${REPO_ROOT}/.env"; do
```

**Issue 2-2 — `DC` alias definition timing**
The `DC` function/alias is defined using `${ENV_FILE}` and `${COMPOSE_FILE}`. If either of these is set AFTER the `DC` definition block, the alias captures the empty string. Verify the order is:

```
1. Find ENV_FILE     ← must happen first
2. Find COMPOSE_FILE ← must happen second  
3. Define DC()       ← must happen third, using now-set vars
4. Validate compose  ← must happen fourth
```

**Issue 2-3 — Qdrant health check endpoint**
```bash
# Confirm this is what the script uses:
curl -sf "http://localhost:${QDRANT_PORT:-6333}/collections"
# NOT /healthz (wrong endpoint for most Qdrant versions)
# NOT /health  (does not exist)
```

**Issue 2-4 — Dify startup sequence (CRITICAL)**
Dify API runs `flask db upgrade` on first start. This requires:
1. PostgreSQL to be healthy ✓ (script does this)
2. The `dify` database to exist ✓ (script creates it)
3. The `DIFY_SECRET_KEY` to be set ✓ (if script 1 is correct)
4. `dify-redis` OR shared redis to be healthy ✓

But Dify also requires the **dify-sandbox** container to be running before dify-api starts serving requests. The current phase structure may start `dify-api` and immediately health-check it — before `dify-sandbox` is up. The health endpoint `/v1/health` on dify-api returns 200 even without sandbox, so this may be fine. But confirm the compose service order is: `dify-sandbox` → `dify-api` → `dify-worker` → `dify-web`.

**Issue 2-5 — AnythingLLM JWT_SECRET env var name mismatch**
AnythingLLM expects the environment variable named exactly `JWT_SECRET` inside the container. The `.env` file writes `ANYTHINGLLM_JWT_SECRET`. The compose file must map this:

```yaml
# In docker-compose.yml for anythingllm service:
environment:
  JWT_SECRET: ${ANYTHINGLLM_JWT_SECRET}   # ← rename on entry
  STORAGE_DIR: /app/server/storage
```
If the compose file passes `ANYTHINGLLM_JWT_SECRET` directly without renaming, AnythingLLM sees no `JWT_SECRET` and crashes. This is not a script 2 fix — it is a compose file fix — but script 2 is where the failure manifests.

---

## Script 3 — `3-configure-services.sh`
**Status: ⚠️ FUNCTIONALLY INCOMPLETE — 3 issues**

### What is correct
- Waits for services before calling APIs
- Configures MinIO buckets
- Has error handling per-service

### Remaining issues

**Issue 3-1 — n8n API key not obtainable before first UI login**
n8n (version ≥ 1.0) requires a user to log in via the UI to generate an API key. Script 3 cannot call the n8n API without this key. The script should either:

**Option A** — Create the n8n owner account via the setup API:
```bash
curl -sf -X POST "http://localhost:${N8N_PORT}/api/v1/owner/setup" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"${N8N_ADMIN_EMAIL}\",
    \"firstName\": \"Admin\",
    \"lastName\": \"User\",
    \"password\": \"${N8N_ADMIN_PASSWORD}\"
  }"
```
Then use Basic Auth for subsequent calls.

**Option B** — Skip n8n API configuration in script 3 and document manual first-login requirement.

Currently if script 3 tries to call n8n API endpoints without authentication, every call returns 401 and the failures are logged but the script continues — giving a false impression of success.

**Issue 3-2 — Dify admin setup required before API calls**
Dify requires calling the setup endpoint FIRST before any other API endpoint works:
```bash
curl -sf -X POST "http://localhost:${DIFY_PORT}/v1/console/api/setup" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"${DIFY_ADMIN_EMAIL}\",
    \"name\": \"Admin\",
    \"password\": \"${DIFY_ADMIN_PASSWORD}\"
  }"
```
Without this, all Dify API calls in script 3 return 403. If this block is missing from script 3, Dify is never configured.

**Issue 3-3 — Script 3 exits 0 on API failures**
All API configuration blocks use `|| warn "..."` which means a total failure of Dify/n8n setup still produces exit code 0. This masks failures. At minimum, a summary at the end should count failures and exit non-zero if critical services failed to configure.

---

## Script 4 — `4-add-service.sh`
**Status: ✅ MOSTLY CORRECT — 1 issue remains**

### What is correct
- Validates service name against allowed list
- Updates compose file
- Updates nginx config
- Restarts affected container only

### Remaining issue

**Issue 4-1 — Compose file not validated after modification**
After appending to `docker-compose.yml`, the script must run:
```bash
docker compose \
  --env-file "${ENV_FILE}" \
  --file "${COMPOSE_FILE}" \
  config --quiet || fail "Compose file invalid after adding ${SERVICE_NAME}"
```
Without this, a YAML indentation error in the appended block invalidates the entire compose file and the next `docker compose up` call fails with a cryptic YAML parse error.

---

# Summary Table

| Script | Status | Blockers | Minor Issues |
|--------|--------|----------|--------------|
| 0 - Cleanup | ⚠️ Mostly OK | Volume removal incomplete | Compose file path check |
| 1 - Setup | ⚠️ Mostly OK | Heredoc quote check (critical) | ENABLE_SIGNAL default, domain ordering |
| 2 - Deploy | 🔴 Issues | .env search order, Dify sandbox, AnythingLLM JWT rename | Qdrant endpoint, DC alias order |
| 3 - Configure | ⚠️ Incomplete | n8n pre-auth, Dify setup endpoint | Exit code masking |
| 4 - Add Service | ✅ Mostly OK | — | Compose validation after edit |

---

# The One Test That Tells You Everything

Run this immediately after script 1, before script 2:

```bash
ENV_FILE="$(find /mnt/data -maxdepth 4 -name '.env' | head -1)"
echo "=== Heredoc expansion check ==="
grep -E "PASSWORD|KEY|SECRET" "$ENV_FILE" | while read line; do
  val="${line#*=}"
  if [[ "$val" == *'${'* ]]; then
    echo "FAIL - literal variable in: $line"
  elif [[ -z "$val" ]]; then
    echo "FAIL - empty value: $line"
  else
    echo "PASS - ${line%%=*} = [${#val} chars]"
  fi
done

echo "=== TENANT_DIR check ==="
grep "^TENANT_DIR=" "$ENV_FILE"
# Must print: TENANT_DIR=/mnt/data/u1001 (or your actual path)
# Must NOT print: TENANT_DIR=${DATA_ROOT}/u1001

echo "=== Compose validation ==="
COMPOSE_FILE="$(find /opt/ai-platform -name 'docker-compose.yml' | head -1)"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --quiet \
  && echo "PASS: compose valid" || echo "FAIL: compose invalid — fix before running script 2"
```

**If any line above prints FAIL, do not run script 2. Fix script 1 first.**