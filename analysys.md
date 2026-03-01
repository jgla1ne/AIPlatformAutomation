## Diagnosis — What the Output Reveals

**Critical findings:**

| Issue | Evidence | Impact |
|-------|----------|--------|
| `DOMAIN=localhost` | `.env` line `DOMAIN=localhost` | **Caddyfile has `localhost` not `ai.datasquiz.net`** — every URL is broken |
| `QDRANT_URL=http://:` | Empty host/port in URL | Qdrant URL never assembled correctly |
| Duplicate vars with conflicting values | `ANYTHINGLLM_PORT=3001` then `ANYTHINGLLM_PORT=5004` | Last one wins — wrong port used |
| `aip-u1001-anythingllm` → host port 3001 → container 3000 | Caddy must proxy to `anythingllm:3001` but container listens on 3000 | Caddy routing broken |
| `aip-u1001-openclaw` → host port 18789 → unhealthy | `OPENCLAW_BASE_URL=http://localhost:8082` contradicts actual port | OpenClaw misconfigured |
| `aip-u1001-prometheus` → Restarting (2) | prometheus.yml likely missing or malformed | No metrics |
| `aip-u1001-qdrant` → unhealthy | Healthcheck failing despite port 6333 open | Wrong healthcheck command |
| `aip-u1001-n8n` → unhealthy | Port 5678 mapped but unhealthy | Wrong healthcheck or DB issue |
| `aip-u1001-ollama` → unhealthy | Port 11434 open but unhealthy | Healthcheck using wrong endpoint |
| `TAILSCALE_AUTH_KEY` not in .env | No auth key variable present | Tailscale will never auto-connect |

**Root cause #1:** `DOMAIN=localhost` — Script 2 generates the Caddyfile using `DOMAIN`, not `DOMAIN_NAME`. Caddy is serving `localhost` blocks, not `*.ai.datasquiz.net`.

**Root cause #2:** `.env` has ~15 variables defined twice with different values. The last definition wins in bash, but which definition is last depends on line order — making behavior unpredictable.

---

## Windsurf Execution Plan — Precise & Ordered

---

### STEP 1 — Fix `.env` generation in Script 1 (prevents all duplicate/wrong-value issues)

**File:** `scripts/1-setup-system.sh`

**Problem:** Script 1 generates `.env` with `DOMAIN=localhost` hardcoded AND `DOMAIN_NAME=ai.datasquiz.net` as a separate variable. Script 2 uses `DOMAIN` for Caddyfile generation. The two variables are never reconciled.

**Fix:** In the `.env` generation block, remove `DOMAIN=localhost` entirely. Add this logic:

```bash
# Determine DOMAIN from DOMAIN_NAME if it resolves, else use PUBLIC_IP
if [ "${DOMAIN_RESOLVES}" = "true" ] && [ -n "${DOMAIN_NAME}" ]; then
    DOMAIN="${DOMAIN_NAME}"
else
    DOMAIN="${PUBLIC_IP}"
fi
```

Then in the `.env` heredoc write `DOMAIN=${DOMAIN}` (not hardcoded `localhost`).

**Also fix:** Remove ALL duplicate variable definitions from the `.env` template. The correct single-source values are:

```bash
# Ports — internal container ports (what the container listens on)
ANYTHINGLLM_INTERNAL_PORT=3001
OPENWEBUI_INTERNAL_PORT=8080
LITELLM_INTERNAL_PORT=4000
OLLAMA_INTERNAL_PORT=11434
QDRANT_INTERNAL_PORT=6333
N8N_INTERNAL_PORT=5678
FLOWISE_INTERNAL_PORT=3000
DIFY_API_INTERNAL_PORT=5001
DIFY_WEB_INTERNAL_PORT=3000
OPENCLAW_INTERNAL_PORT=8082
SIGNAL_INTERNAL_PORT=8080
MINIO_INTERNAL_PORT=9000
MINIO_CONSOLE_INTERNAL_PORT=9001
GRAFANA_INTERNAL_PORT=3000
PROMETHEUS_INTERNAL_PORT=9090

# QDRANT_URL uses internal container name, not localhost
QDRANT_URL=http://qdrant:6333
```

**Verify:** After script 1 runs, check:
```bash
grep "^DOMAIN=" /mnt/data/u1001/.env
# Must return: DOMAIN=ai.datasquiz.net

grep "QDRANT_URL" /mnt/data/u1001/.env
# Must return: QDRANT_URL=http://qdrant:6333

grep "ANYTHINGLLM_PORT" /mnt/data/u1001/.env | wc -l
# Must return: 1
```

---

### STEP 2 — Fix Caddyfile Generation in Script 2

**File:** `scripts/2-deploy-services.sh`

**Problem A:** Heredoc uses single-quoted delimiter (`<< 'CADDYFILE'`) — variables never expand.

**Problem B:** Caddy entry for AnythingLLM points to wrong internal port.

**Problem C:** `DOMAIN` variable is `localhost` at generation time (fixed by Step 1, but Script 2 must also reload `.env` at the top).

**Fix A:** Ensure Script 2 sources `.env` before generating any config:
```bash
# At top of script, after variable setup:
source "${ENV_FILE}"
log "INFO" "Domain: ${DOMAIN}"
```

Add immediate guard:
```bash
if [ "${DOMAIN}" = "localhost" ] || [ -z "${DOMAIN}" ]; then
    log "ERROR" "DOMAIN is '${DOMAIN}'. Set DOMAIN_NAME in .env and re-run script 1 first."
    exit 1
fi
```

**Fix B:** Change heredoc delimiter (remove single quotes):
```bash
# Wrong:
cat > "${DATA_DIR}/caddy/config/Caddyfile" << 'CADDYFILE'

# Correct:
cat > "${DATA_DIR}/caddy/config/Caddyfile" << CADDYFILE
```

**Fix C:** Correct internal proxy targets in the Caddyfile heredoc:

```
anythingllm.${DOMAIN} {
    reverse_proxy anythingllm:3001
}

openwebui.${DOMAIN} {
    reverse_proxy openwebui:8080
}

litellm.${DOMAIN} {
    reverse_proxy litellm:4000
}

dify.${DOMAIN} {
    reverse_proxy dify-web:3000
}

n8n.${DOMAIN} {
    reverse_proxy n8n:5678
}

flowise.${DOMAIN} {
    reverse_proxy flowise:3000
}

openclaw.${DOMAIN} {
    reverse_proxy openclaw:8082
}

signal-api.${DOMAIN} {
    reverse_proxy signal-api:8080
}

grafana.${DOMAIN} {
    reverse_proxy grafana:3000
}

prometheus.${DOMAIN} {
    reverse_proxy prometheus:9090
}

minio.${DOMAIN} {
    reverse_proxy minio:9001
}

minio-api.${DOMAIN} {
    reverse_proxy minio:9000
}
```

**Verify after Caddyfile is written:**
```bash
grep "^[a-z]" /mnt/data/u1001/caddy/config/Caddyfile | head -15
# Must show: anythingllm.ai.datasquiz.net {
# NOT: anythingllm.${DOMAIN} {
# NOT: anythingllm.localhost {
```

---

### STEP 3 — Fix Healthchecks for Ollama, Qdrant, n8n, Dify-web

**File:** `scripts/2-deploy-services.sh` (compose service definitions)

**Ollama** — the `/api/tags` endpoint returns 200 when ready:
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
  interval: 30s
  timeout: 20s
  retries: 5
  start_period: 60s
```

**Qdrant** — use the readiness endpoint:
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:6333/readiness"]
  interval: 10s
  timeout: 5s
  retries: 10
  start_period: 30s
```

**n8n** — n8n exposes a healthcheck at `/healthz`:
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 60s
```

**Dify-web** — Next.js app, check root path:
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:3000"]
  interval: 30s
  timeout: 10s
  retries: 10
  start_period: 120s
```

**OpenClaw** — connection refused means wrong port or container config error. Fix the service definition:
```yaml
openclaw:
  environment:
    - PORT=8082
    - QDRANT_URL=http://qdrant:6333
    - LITELLM_BASE_URL=http://litellm:4000
    - LITELLM_API_KEY=${LITELLM_MASTER_KEY}
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8082/health"]
    interval: 30s
    timeout: 10s
    retries: 5
    start_period: 60s
```

---

### STEP 4 — Fix Prometheus Config Generation

**File:** `scripts/2-deploy-services.sh`

Prometheus is crash-looping because `prometheus.yml` is either missing or malformed. Add this heredoc (unquoted delimiter) before `docker compose up`:

```bash
mkdir -p "${DATA_DIR}/prometheus"
cat > "${DATA_DIR}/prometheus/prometheus.yml" << PROMETHEUS_EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
PROMETHEUS_EOF

log "INFO" "Prometheus config written to ${DATA_DIR}/prometheus/prometheus.yml"
```

**Verify:**
```bash
cat /mnt/data/u1001/prometheus/prometheus.yml
# Must be valid YAML, no variable placeholders
```

---

### STEP 5 — Fix Tailscale Auto-Authentication

**File:** `scripts/2-deploy-services.sh`

**Problem:** `TAILSCALE_AUTH_KEY` is not in `.env`. The container starts but cannot authenticate.

**Fix Part A — Script 1:** Add to `.env` template:
```bash
# Tailscale Configuration
TAILSCALE_AUTH_KEY=          # Required: get from https://login.tailscale.com/admin/settings/keys
                             # Create a "Reusable" auth key, never expires recommended
TAILSCALE_HOSTNAME=${TENANT_ID}
```

**Fix Part B — Script 2 compose definition:**
```yaml
tailscale:
  image: tailscale/tailscale:latest
  container_name: ${PROJECT_NAME}-tailscale
  restart: unless-stopped
  cap_add:
    - NET_ADMIN
    - NET_RAW
  volumes:
    - ${DATA_DIR}/tailscale:/var/lib/tailscale
    - /dev/net/tun:/dev/net/tun
  environment:
    - TS_AUTHKEY=${TAILSCALE_AUTH_KEY}
    - TS_STATE_DIR=/var/lib/tailscale
    - TS_HOSTNAME=${TAILSCALE_HOSTNAME}
    - TS_USERSPACE=false
    - TS_EXTRA_ARGS=--accept-routes --advertise-tags=tag:ai-platform
  networks:
    - ${NETWORK_NAME}
  healthcheck:
    test: ["CMD", "tailscale", "status"]
    interval: 30s
    timeout: 10s
    retries: 5
    start_period: 30s
```

**Fix Part C — Script 2 post-startup:** After the wait loop, add:
```bash
TS_IP=$(docker exec "${PROJECT_NAME}-tailscale" tailscale ip -4 2>/dev/null || echo "not connected")
if [ "${TS_IP}" = "not connected" ]; then
    log "WARN" "Tailscale not connected. Add TAILSCALE_AUTH_KEY to .env"
else
    # Update .env with actual Tailscale IP
    sed -i "s/^TAILSCALE_IP=.*/TAILSCALE_IP=${TS_IP}/" "${ENV_FILE}"
    log "SUCCESS" "Tailscale IP: ${TS_IP} — saved to .env"
fi
```

---

### STEP 6 — Fix OpenClaw Integration with AnythingLLM

**File:** `scripts/3-configure-services.sh`

OpenClaw is the document intelligence layer. AnythingLLM should use the same Qdrant collection. Add this integration block to Script 3:

```bash
# ── OpenClaw → Qdrant collection setup ──────────────────────
log "INFO" "Setting up OpenClaw Qdrant collection..."
QDRANT_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT "http://localhost:6333/collections/openclaw_docs" \
    -H "Content-Type: application/json" \
    -d '{
        "vectors": {
            "size": 768,
            "distance": "Cosine"
        },
        "optimizers_config": {
            "default_segment_number": 2
        }
    }')
log "INFO" "Qdrant openclaw_docs collection: HTTP ${QDRANT_RESPONSE}"

# ── AnythingLLM → Qdrant collection setup ───────────────────
curl -s -o /dev/null -w "%{http_code}" \
    -X PUT "http://localhost:6333/collections/anythingllm_docs" \
    -H "Content-Type: application/json" \
    -d '{"vectors":{"size":768,"distance":"Cosine"}}'

# ── AnythingLLM API configuration ───────────────────────────
# AnythingLLM exposes a setup API on first boot
log "INFO" "Waiting for AnythingLLM API..."
for i in $(seq 1 12); do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://localhost:3001/api/ping" 2>/dev/null || echo "000")
    [ "${HTTP}" = "200" ] && break
    sleep 10
done

if [ "${HTTP}" = "200" ]; then
    log "SUCCESS" "AnythingLLM API is up"
    # Configure LiteLLM as the LLM provider
    curl -s -X POST "http://localhost:3001/api/system/update-env" \
        -H "Content-Type: application/json" \
        -d "{
            \"LLM_PROVIDER\": \"litellm\",
            \"LITELLM_BASE_URL\": \"http://litellm:4000\",
            \"LITELLM_API_KEY\": \"${LITELLM_MASTER_KEY}\",
            \"VECTOR_DB\": \"qdrant\",
            \"QDRANT_ENDPOINT\": \"http://qdrant:6333\",
            \"EMBEDDING_ENGINE\": \"ollama\",
            \"OLLAMA_BASE_PATH\": \"http://ollama:11434\",
            \"EMBEDDING_MODEL_PREF\": \"nomic-embed-text:latest\"
        }" | grep -o '"message":"[^"]*"' || true
else
    log "WARN" "AnythingLLM API not responding — configure manually via UI"
fi
```

---

### STEP 7 — Self-Purge at Top of Script 2

**File:** `scripts/2-deploy-services.sh`

Insert immediately after sourcing `.env`, before any directory creation or config writing:

```bash
# ════════════════════════════════════════════════
# SELF-PURGE — clean any partial previous run
# ════════════════════════════════════════════════
log "INFO" "Self-purge: removing previous deployment containers..."

docker ps -aq --filter "name=${PROJECT_NAME}-" | xargs -r docker rm -f 2>/dev/null || true

if docker network inspect "${DOCKER_NETWORK}" &>/dev/null; then
    docker network inspect "${DOCKER_NETWORK}" \
        --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null | \
        xargs -r docker rm -f 2>/dev/null || true
    docker network rm "${DOCKER_NETWORK}" 2>/dev/null || true
fi

# Remove generated configs (regenerated fresh below)
rm -f "${DATA_DIR}/caddy/config/Caddyfile"
rm -f "${DATA_DIR}/litellm/config.yaml"
rm -f "${DATA_DIR}/prometheus/prometheus.yml"

log "SUCCESS" "Self-purge complete"
# ════════════════════════════════════════════════
```

---

### STEP 8 — Add Final Status Dashboard to Script 2

**File:** `scripts/2-deploy-services.sh`

Append at the very end of the script:

```bash
# ════════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         AI PLATFORM — DEPLOYMENT COMPLETE                    ║"
echo "╠══════════════════════════════════════════════════════════════╣"

echo ""
echo "── Container Health ───────────────────────────────────────────"
docker ps --format "  {{.Names}}\t{{.Status}}" \
    --filter "name=${PROJECT_NAME}-" | sort | \
    sed 's/healthy/✅ healthy/; s/unhealthy/❌ unhealthy/; s/starting/⏳ starting/'

echo ""
echo "── External URLs ──────────────────────────────────────────────"

check_url() {
    local name=$1 url=$2
    local code
    code=$(curl -o /dev/null -s -w "%{http_code}" \
        --max-time 10 --connect-timeout 5 "${url}" 2>/dev/null || echo "000")
    local icon="❌"
    [[ "${code}" =~ ^(200|301|302|401|403)$ ]] && icon="✅"
    printf "  %s  %-20s %s\n" "${icon}" "${name}" "${url}"
}

check_url "AnythingLLM"  "https://anythingllm.${DOMAIN}"
check_url "OpenClaw"     "https://openclaw.${DOMAIN}"
check_url "Open WebUI"   "https://openwebui.${DOMAIN}"
check_url "Dify"         "https://dify.${DOMAIN}"
check_url "n8n"          "https://n8n.${DOMAIN}"
check_url "Flowise"      "https://flowise.${DOMAIN}"
check_url "LiteLLM"      "https://litellm.${DOMAIN}/health"
check_url "Grafana"      "https://grafana.${DOMAIN}"
check_url "MinIO"        "https://minio.${DOMAIN}"
check_url "Signal API"   "https://signal-api.${DOMAIN}/v1/about"

echo ""
echo "── Tailscale ──────────────────────────────────────────────────"
TS_IP=$(docker exec "${PROJECT_NAME}-tailscale" tailscale ip -4 2>/dev/null || echo "not connected")
echo "  IP: ${TS_IP}"

echo ""
echo "── Log ────────────────────────────────────────────────────────"
echo "  ${LOG_FILE}"
echo "╚══════════════════════════════════════════════════════════════╝"
```

---

### STEP 9 — Per-Script Logging to /mnt/data/u1001/logs

**Files:** All 5 scripts

In each script, after `DATA_DIR` is defined, add:

```bash
SCRIPT_NAME="script-$(basename "$0" .sh)"
mkdir -p "${DATA_DIR}/logs"
LOG_FILE="${DATA_DIR}/logs/${SCRIPT_NAME}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting ${SCRIPT_NAME} — log: ${LOG_FILE}"
```

For Script 0 (DATA_DIR may not exist):
```bash
LOG_FILE="/tmp/script-0-cleanup-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1
```

---

## Execution Order for Windsurf

| Step | Change | Script | Verify Command |
|------|--------|--------|----------------|
| 1 | Fix `DOMAIN` variable and remove duplicates | Script 1 | `grep "^DOMAIN=" .env` → `ai.datasquiz.net` |
| 2 | Fix Caddyfile heredoc (remove single quotes) | Script 2 | `grep "^\S" Caddyfile \| head -5` → real domain |
| 3 | Fix Caddy proxy targets (correct internal ports) | Script 2 | Visual inspect Caddyfile |
| 4 | Fix healthchecks (Ollama, Qdrant, n8n, Dify-web) | Script 2 | `docker ps` → all healthy |
| 5 | Fix Prometheus config generation | Script 2 | `docker ps aip-u1001-prometheus` → Up |
| 6 | Fix Tailscale TS_AUTHKEY env | Scripts 1+2 | `docker exec ... tailscale ip -4` → returns IP |
| 7 | Fix OpenClaw environment vars | Script 2 | `curl http://localhost:8082/health` → 200 |
| 8 | Add self-purge at top | Script 2 | No orphan containers after re-run |
| 9 | Add status dashboard | Script 2 | Dashboard prints at end |
| 10 | Add service integrations | Script 3 | `curl localhost:6333/collections` → collections exist |
| 11 | Add logging to all scripts | All 5 | Log file in `/mnt/data/u1001/logs/` |

---

## After Windsurf Applies All Changes — Run This Sequence

```bash
# 1. Re-run script 1 to regenerate clean .env
sudo bash scripts/1-setup-system.sh

# 2. Add Tailscale auth key to .env BEFORE running script 2
# Get key from: https://login.tailscale.com/admin/settings/keys
nano /mnt/data/u1001/.env
# Set: TAILSCALE_AUTH_KEY=tskey-auth-xxxxx

# 3. Run script 2 (includes self-purge)
sudo bash scripts/2-deploy-services.sh

# 4. Run script 3 (integrations)
sudo bash scripts/3-configure-services.sh

# 5. Verify
for svc in anythingllm openwebui dify n8n flowise openclaw grafana litellm minio; do
    code=$(curl -so /dev/null -w "%{http_code}" --max-time 10 "https://${svc}.ai.datasquiz.net")
    printf "%-20s → %s\n" "${svc}" "${code}"
done
```