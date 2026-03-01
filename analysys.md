Let me fetch every file fresh.

**Script 0:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/0-complete-cleanup.sh
**Script 1:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh
**Script 2:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh
**Script 3:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh
**Script 4:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/4-add-service.sh
**README:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/README.md
**Test Results:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/COMPREHENSIVE_TEST_RESULTS.md

---

I have read all 7 files completely. Here is the precise, regression-safe plan for Windsurf.

---

# Windsurf Execution Plan — Round 5

**Governing rule:** 5 scripts only. No new files. No new scripts. Every change is a targeted edit inside an existing script. Changes are listed in priority order — stop if a change causes a test failure before moving to the next.

---

## BLOCK A — Script 2: Self-Healing Boot (Do This First)

**Rationale:** If script 2 fails mid-run you currently end up with a broken partial state requiring a manual 0→1→2 cycle. The fix is to make script 2 clean itself at the start.

### A1 — Add self-purge at top of script 2, before any deployment logic

Insert immediately after the initial variable loading and log setup, before any `docker` commands:

```bash
# ── SELF-PURGE: clean any previous partial deployment ──────────────────
log "INFO" "Purging any previous deployment before fresh start..."

# Stop and remove all containers on this project network
docker ps -aq --filter "network=${PROJECT_NAME}_net" | xargs -r docker rm -f
docker ps -aq --filter "name=${PROJECT_NAME}-" | xargs -r docker rm -f

# Remove project network if it exists
docker network rm "${PROJECT_NAME}_net" 2>/dev/null || true

# Remove orphaned volumes only for this project (named volumes with prefix)
docker volume ls -q --filter "name=${PROJECT_NAME}_" | xargs -r docker volume rm 2>/dev/null || true

# Remove the old Caddyfile so it is always regenerated fresh
rm -f "${DATA_DIR}/caddy/config/Caddyfile"

log "INFO" "Self-purge complete. Starting fresh deployment."
# ── END SELF-PURGE ──────────────────────────────────────────────────────
```

**What this does NOT touch:** host packages, UFW rules, SSL certs in `${DATA_DIR}/caddy/data` (preserved so Caddy does not re-request certs unnecessarily), `.env` file, `${DATA_DIR}` directory structure. Those were set up in script 1 and must survive.

---

## BLOCK B — Script 2: Fix the Caddyfile Heredoc (The URL Bug)

**Rationale:** Single-quoted heredoc `<< 'CADDYFILE'` prevents `${DOMAIN}` and `${ADMIN_EMAIL}` from expanding. Caddy serves the literal string `${DOMAIN}` as the hostname, matches no real request, provisions no certificates. This is why every URL fails.

### B1 — Change heredoc delimiter

```bash
# FIND this exact line in script 2:
cat > "${DATA_DIR}/caddy/config/Caddyfile" << 'CADDYFILE'

# REPLACE with:
cat > "${DATA_DIR}/caddy/config/Caddyfile" << CADDYFILE
```

### B2 — Escape any Caddy-native braces that bash would misinterpret

After removing the single quotes, bash will try to expand anything that looks like `${...}`. Caddy's config uses `{` and `}` but NOT `${...}` syntax, so no escaping is needed for Caddy directives. However, verify the heredoc contains no bash-style `${VAR}` except `${DOMAIN}` and `${ADMIN_EMAIL}` (which we WANT expanded). If any other `${...}` appears in the Caddyfile block, escape it as `\${...}`.

### B3 — Add immediate verification after Caddyfile is written

```bash
# After the heredoc closes, add:
log "INFO" "Verifying Caddyfile variable expansion..."
if grep -q '\${DOMAIN}' "${DATA_DIR}/caddy/config/Caddyfile"; then
    log "FAIL" "Caddyfile still contains literal \${DOMAIN} — variable expansion failed"
    log "FAIL" "Check that DOMAIN is set in ${ENV_FILE} and sourced before this point"
    exit 1
fi
if grep -q '\${ADMIN_EMAIL}' "${DATA_DIR}/caddy/config/Caddyfile"; then
    log "FAIL" "Caddyfile still contains literal \${ADMIN_EMAIL} — variable expansion failed"
    exit 1
fi
log "SUCCESS" "Caddyfile correctly expanded:"
cat "${DATA_DIR}/caddy/config/Caddyfile"
```

---

## BLOCK C — Script 2: Tailscale Activation

**Rationale:** Tailscale container starts but `tailscale up` is never called. The node has no IP, no mesh connectivity, and the auth key from `.env` is never used.

### C1 — Add Tailscale bring-up after container health check

After the section that waits for the tailscale container to be healthy, add:

```bash
# ── TAILSCALE ACTIVATION ────────────────────────────────────────────────
log "INFO" "Activating Tailscale..."

# Wait for tailscale daemon to be ready inside the container
TAILSCALE_READY=false
for i in $(seq 1 30); do
    if docker exec "${PROJECT_NAME}-tailscale" tailscale status &>/dev/null; then
        TAILSCALE_READY=true
        break
    fi
    sleep 2
done

if [ "$TAILSCALE_READY" = "true" ]; then
    docker exec "${PROJECT_NAME}-tailscale" tailscale up \
        --authkey="${TAILSCALE_AUTH_KEY}" \
        --hostname="${PROJECT_NAME}" \
        --accept-routes \
        2>&1 | tee -a "${LOG_FILE}"
    
    TAILSCALE_IP=$(docker exec "${PROJECT_NAME}-tailscale" tailscale ip -4 2>/dev/null || echo "pending")
    log "SUCCESS" "Tailscale activated. IP: ${TAILSCALE_IP}"
else
    log "WARN" "Tailscale daemon not ready after 60s — skipping activation (non-fatal)"
fi
# ── END TAILSCALE ────────────────────────────────────────────────────────
```

**Required in `.env`:** `TAILSCALE_AUTH_KEY=tskey-auth-...` — script 1 must prompt for this and write it to `.env` if not present. Add to script 1's `.env` generation section:

```bash
# In script 1, in the .env writing block, add:
TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY:-""}   # User must populate
```

---

## BLOCK D — Script 2: Signal API Port Fix

**Rationale:** Signal API is exposed on port 8080 externally but the Caddyfile proxies to `signal-api:8080` (internal). The external URL `https://signal-api.ai.datasquiz.net:8080/...` is wrong — HTTPS already implies port 443. The QR code link URL must not include `:8080`.

### D1 — Fix the Signal API Caddyfile entry

The Caddyfile entry for Signal must be:

```
signal-api.${DOMAIN} {
    reverse_proxy signal-api:8080
}
```

No port number in the subdomain hostname. The public URL is `https://signal-api.ai.datasquiz.net/v1/qrcodelink?device_name=signal-api` — port 443 implied by HTTPS, Caddy terminates SSL and proxies to internal port 8080. This is already how all other services work. Verify the Caddyfile block for signal does not include `:8080` in the site address line.

### D2 — Fix Signal's environment variable for its own URL

In the Signal API service definition in script 2's compose block, ensure:

```yaml
signal-api:
  environment:
    - SIGNAL_CLI_REST_API_PUBLIC_URL=https://signal-api.${DOMAIN}
```

Not `http://localhost:8080` or `https://signal-api.${DOMAIN}:8080`.

---

## BLOCK E — Script 2: rclone / Backblaze Configuration

**Rationale:** rclone config requires credentials. It should not be in script 3 (which configures running services), and it should not hardcode anything. The correct place is script 2, in the environment block, reading from `.env`.

### E1 — Add rclone env vars to `.env` template in script 1

In script 1's `.env` generation, add:

```bash
# Backblaze B2 / rclone
B2_ACCOUNT_ID=""          # Backblaze Application Key ID
B2_APPLICATION_KEY=""     # Backblaze Application Key
B2_BUCKET_NAME=""         # Bucket name for backups
RCLONE_REMOTE_NAME="b2backup"
```

### E2 — Write rclone config in script 2 from `.env` variables

After directory setup and before `docker compose up`, add:

```bash
# ── RCLONE CONFIG ────────────────────────────────────────────────────────
if [ -n "${B2_ACCOUNT_ID}" ] && [ -n "${B2_APPLICATION_KEY}" ]; then
    log "INFO" "Writing rclone Backblaze config..."
    mkdir -p "${DATA_DIR}/rclone"
    cat > "${DATA_DIR}/rclone/rclone.conf" << RCLONECONF
[${RCLONE_REMOTE_NAME}]
type = b2
account = ${B2_ACCOUNT_ID}
key = ${B2_APPLICATION_KEY}
RCLONECONF
    log "SUCCESS" "rclone config written"
else
    log "WARN" "B2_ACCOUNT_ID or B2_APPLICATION_KEY not set — rclone backup not configured"
fi
# ── END RCLONE ────────────────────────────────────────────────────────────
```

---

## BLOCK F — Script 2: VectorDB Connectivity Across Stack

**Rationale:** Qdrant must be reachable by AnythingLLM, Dify, and LiteLLM. All must use the Docker service name `qdrant`, not `localhost`. Verify these environment variables in the compose definitions:

### F1 — AnythingLLM must point to Qdrant by service name

```yaml
anythingllm:
  environment:
    - VECTOR_DB=qdrant
    - QDRANT_ENDPOINT=http://qdrant:6333
```

### F2 — Dify API must point to Qdrant by service name

```yaml
dify-api:
  environment:
    - VECTOR_STORE=qdrant
    - QDRANT_URL=http://qdrant:6333
```

### F3 — LiteLLM must reference Qdrant correctly if semantic caching is enabled

```yaml
litellm:
  environment:
    - QDRANT_URL=http://qdrant:6333
```

**Verify these are using `qdrant:6333` not `localhost:6333` in the current script 2. If any say localhost, change to service name.**

---

## BLOCK G — Script 2: Final Status Report (End of Script)

**Rationale:** Script 2 ends without telling you whether anything actually works. Add a status dashboard as the final section.

### G1 — Add health check and HTTP reachability report at end of script 2

```bash
# ── FINAL STATUS REPORT ──────────────────────────────────────────────────
log "INFO" "======================================================"
log "INFO" "FINAL DEPLOYMENT STATUS REPORT"
log "INFO" "======================================================"

# Container health
log "INFO" "--- Container Status ---"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" \
    --filter "network=${PROJECT_NAME}_net" | tee -a "${LOG_FILE}"

# Internal connectivity (from Caddy container to each service)
log "INFO" "--- Internal Connectivity (Caddy → Services) ---"
declare -A SERVICE_INTERNAL=(
    ["litellm"]="litellm:4000"
    ["openwebui"]="openwebui:8080"
    ["anythingllm"]="anythingllm:3000"
    ["dify"]="dify-web:3000"
    ["n8n"]="n8n:5678"
    ["flowise"]="flowise:3000"
    ["signal-api"]="signal-api:8080"
    ["openclaw"]="openclaw:8082"
    ["prometheus"]="prometheus:9090"
    ["grafana"]="grafana:3000"
    ["minio"]="minio:9001"
)

for svc in "${!SERVICE_INTERNAL[@]}"; do
    target="${SERVICE_INTERNAL[$svc]}"
    if docker exec "${PROJECT_NAME}-caddy" wget -q --spider --timeout=5 \
        "http://${target}" 2>/dev/null; then
        log "SUCCESS" "  ✅ ${svc} → http://${target} reachable"
    else
        log "WARN"    "  ⚠️  ${svc} → http://${target} NOT reachable"
    fi
done

# External URL reachability
log "INFO" "--- External URL Reachability ---"
EXTERNAL_URLS=(
    "https://litellm.${DOMAIN}"
    "https://openwebui.${DOMAIN}"
    "https://anythingllm.${DOMAIN}"
    "https://dify.${DOMAIN}"
    "https://n8n.${DOMAIN}"
    "https://flowise.${DOMAIN}"
    "https://signal-api.${DOMAIN}"
    "https://openclaw.${DOMAIN}"
    "https://prometheus.${DOMAIN}"
    "https://grafana.${DOMAIN}"
    "https://minio.${DOMAIN}"
)

for url in "${EXTERNAL_URLS[@]}"; do
    HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" \
        --max-time 10 --connect-timeout 5 "${url}" 2>/dev/null || echo "000")
    if [[ "${HTTP_CODE}" =~ ^(200|301|302|303|401|403)$ ]]; then
        log "SUCCESS" "  ✅ ${url} → HTTP ${HTTP_CODE}"
    else
        log "FAIL"    "  ❌ ${url} → HTTP ${HTTP_CODE} (no response or error)"
    fi
done

# Tailscale status
log "INFO" "--- Tailscale Status ---"
TAILSCALE_IP=$(docker exec "${PROJECT_NAME}-tailscale" tailscale ip -4 2>/dev/null || echo "not connected")
log "INFO" "  Tailscale IP: ${TAILSCALE_IP}"

log "INFO" "======================================================"
log "INFO" "Log file: ${LOG_FILE}"
log "INFO" "======================================================"
# ── END STATUS REPORT ────────────────────────────────────────────────────
```

---

## BLOCK H — All Scripts: Structured Logging to `/mnt/data/{tenant}/logs/`

**Rationale:** Every script should write a timestamped log file to a consistent location.

### H1 — Standardize log file path across all 5 scripts

Each script should define at its top (after loading `.env` and setting `PROJECT_NAME`):

```bash
LOG_DIR="${DATA_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/script-N-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1
```

Replace `N` with the script number. The `exec` line redirects ALL output (stdout and stderr) to both the terminal and the log file for the entire script — no need to pipe individual commands.

**This is a 4-line change at the top of each script. It cannot break anything.**

### H2 — Script 0 logs to `/tmp` since DATA_DIR may not exist during cleanup

```bash
# Script 0 only:
LOG_FILE="/tmp/script-0-cleanup-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1
```

---

## BLOCK I — Script 0: Ensure It Catches All Containers

**Rationale:** Containers without the `${PROJECT_NAME}-` prefix survive script 0 cleanup (confirmed in earlier rounds).

### I1 — Add network-based cleanup to script 0

```bash
# After existing container removal logic, add:
# Remove ALL containers attached to the project network (catches unprefixed names)
if docker network inspect "${PROJECT_NAME}_net" &>/dev/null; then
    NETWORK_CONTAINERS=$(docker network inspect "${PROJECT_NAME}_net" \
        --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)
    if [ -n "${NETWORK_CONTAINERS}" ]; then
        log "INFO" "Removing containers on ${PROJECT_NAME}_net: ${NETWORK_CONTAINERS}"
        echo "${NETWORK_CONTAINERS}" | xargs -r docker rm -f
    fi
fi
```

---

## Execution Order for Windsurf

Make these changes in this exact order. After each block, commit and do not proceed until the block is verified not to break existing passing tests.

| Order | Block | Script | Risk of Regression |
|-------|-------|--------|--------------------|
| 1 | H — Logging | All | None — additive only |
| 2 | A — Self-purge | Script 2 | None — runs before deployment |
| 3 | B — Heredoc fix | Script 2 | **High impact, verify immediately** |
| 4 | F — VectorDB names | Script 2 | Low — env var change only |
| 5 | C — Tailscale up | Script 2 | None — new section |
| 6 | D — Signal port | Script 2 | Low — Caddyfile entry only |
| 7 | E — rclone config | Scripts 1+2 | None — new section |
| 8 | G — Status report | Script 2 | None — additive only |
| 9 | I — Script 0 cleanup | Script 0 | None — adds to cleanup |

**The single change most likely to make all URLs work is Block B (heredoc fix). If Windsurf does only one thing, it must be Block B.**