

My Understanding & Key Observations
Before the bugs: a few important architecture notes I want to confirm with you:

Two completely separate network topologies — Tailscale mode = direct IP:port access, no Caddy, no SSL termination inside Docker. Caddy mode = subdomain SSL termination. These must never bleed into each other.
/mnt/data/<tenant-id> is the only valid data root. /opt/ai-platform is a legacy remnant from an older design and must be eliminated entirely.
OpenClaw needs a private registry pull (openclaw:latest doesn't exist on Docker Hub) — this is a deployment blocker unless the image is pre-loaded or the registry is specified.
OpenClaw jail — you want it chown'd to its own UID/GID in an isolated folder, not sharing the tenant's main UID.


🐛 Full Bug Register

🔴 P0 — Hard Blockers (Script will crash or produce broken compose)

P0-1 | Script 2 — compose_append function does not exist
append_ollama() calls compose_append << EOF (line ~210) but no such function is defined anywhere. Every other append_* uses cat >> "${COMPOSE_FILE}" directly.
Fix:
# In append_ollama(), replace:
compose_append << EOF
# With:
cat >> "${COMPOSE_FILE}" << EOF

P0-2 | Script 2 — append_caddy() proxies AnythingLLM to wrong internal port
Caddyfile block says reverse_proxy anythingllm:3001 but the README table and append_anythingllm() expose internal port 3001 for Flowise and 3001 for AnythingLLM — they collide. Per README: AnythingLLM internal = 3001, Flowise internal = 3000. But append_flowise() writes flowise:3000 correctly. The Caddy block for AnythingLLM uses anythingllm:3001 which is correct — however the Flowise Caddy block says flowise:3000 while append_flowise exposes container port 3000. This needs cross-checking:
README table:  Flowise port 3001 (host), AnythingLLM port 3002 (host)
append_flowise: container port 3000 internal → host 3001 ✅
append_anythingllm: container port 3001 internal → host 3002
Caddy flowise block: reverse_proxy flowise:3000 ✅
Caddy anythingllm block: reverse_proxy anythingllm:3001 ✅
Actually consistent — but Grafana's Caddy block says reverse_proxy grafana:3000 while append_grafana exposes internal port 3000. ✅ Consistent.
Real P0-2: Tailscale container uses network_mode: host AND declares ports:
network_mode: host   # ← makes `ports:` invalid, Docker will error
ports:
  - "8443:443"       # ← INVALID with network_mode: host
Docker Compose will refuse to start with this combination.
Fix — remove the ports: stanza from append_tailscale():
# DELETE these lines from append_tailscale():
    ports:
      - "8443:443"
In network_mode: host, the container shares the host network stack directly — port 443 on the Tailscale container IS port 443 on the host. OpenClaw reaching Tailscale on 8443 requires a different approach (see P1-3).

P0-3 | Script 1 — DATA_ROOT hardcoded to /opt/ai-platform at top, used for early logging before tenant is known
readonly DATA_ROOT="/opt/ai-platform"   # line 12
readonly ENV_FILE="${DATA_ROOT}/.env"   # line 13  ← written before tenant step
readonly LOG_FILE="${DATA_ROOT}/setup.log"  # line 14
configure_tenant() sets BASE_DIR and reassigns LOG_FILE — but ENV_FILE is readonly and never updated. Script 11's generate_secrets() writes .env to ${BASE_DIR}/.env correctly, but if anything reads ${ENV_FILE} after configure_tenant() it reads the wrong path.
Script 2 searches "/mnt/data"/*/.env first so it recovers — but Script 3 does:
ENV_FILE="${DATA_ROOT}/.env"   # ← still /opt/ai-platform/.env — FAILS
Fix in Script 1: Remove readonly from DATA_ROOT, ENV_FILE, LOG_FILE. Update them in configure_tenant():
# At top - remove readonly:
DATA_ROOT="/opt/ai-platform"
ENV_FILE="${DATA_ROOT}/.env"
LOG_FILE="${DATA_ROOT}/setup.log"

# In configure_tenant(), after BASE_DIR is set:
DATA_ROOT="${BASE_DIR}"
ENV_FILE="${BASE_DIR}/.env"
LOG_FILE="${BASE_DIR}/setup.log"
mkdir -p "${BASE_DIR}"
touch "${LOG_FILE}"
Fix in Script 3: Replace the ENV_FILE detection with the same glob search Script 2 uses:
# Replace:
DATA_ROOT="/opt/ai-platform"
ENV_FILE="${DATA_ROOT}/.env"

# With:
ENV_FILE=""
for candidate in "/mnt/data"/*/.env "/opt/ai-platform/.env"; do
    if [[ -f "${candidate}" ]]; then
        ENV_FILE="${candidate}"
        break
    fi
done
if [[ -z "${ENV_FILE}" ]]; then
    echo "❌  No .env file found — run script 1 first"
    exit 1
fi
source "${ENV_FILE}"

P0-4 | Script 2 — DOCKER_NETWORK and COMPOSE_PROJECT_NAME variables never defined
Both are used extensively throughout the compose generation but are never assigned in Script 1's generate_secrets() or anywhere else.
Fix — add to generate_secrets() in Script 1, before the .env write:
DOCKER_NETWORK="aip-${TENANT_ID}"
COMPOSE_PROJECT_NAME="aip-${TENANT_ID}"
And add to the .env heredoc:
DOCKER_NETWORK=${DOCKER_NETWORK}
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}

P0-5 | Script 2 — All bind-mount device directories never created before compose up
The volumes block uses type: none / o: bind / device: ${BASE_DIR}/postgres etc. If those directories don't exist, Docker Compose will fail with a bind mount error.
Fix — add a create_directories() function in Script 2, called before docker compose up:
create_directories() {
    local dirs=(
        postgres redis ollama openwebui n8n flowise
        qdrant anythingllm grafana prometheus
        authentik/media authentik/templates
        signal dify/storage caddy/config caddy/data
        tailscale
    )
    for d in "${dirs[@]}"; do
        mkdir -p "${BASE_DIR}/${d}"
    done

    # OpenClaw gets its own jail (separate from tenant UID)
    if [[ "${DEPLOY_OPENCLAW:-false}" == "true" ]]; then
        mkdir -p "${BASE_DIR}/openclaw"
        chown "${OPENCLAW_UID:-65534}:${OPENCLAW_GID:-65534}" "${BASE_DIR}/openclaw"
        chmod 750 "${BASE_DIR}/openclaw"
    fi

    log "Data directories created under ${BASE_DIR}"
}

P0-6 | Script 2 — append_openwebui() healthcheck heredoc is cut off
The fetched source ends mid-line:
test: ["CMD", "curl", "-f", "http://localhost:8080/health
The closing "] and the rest of the healthcheck + labels block are missing. This produces a malformed YAML that will fail docker compose config validation.
Fix — complete the healthcheck block:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    labels:
      com.ai-platform: "true"
      com.ai-platform.tenant: "${TENANT_ID}"

🟡 P1 — Network Mode Correctness

P1-1 | Script 2 — Tailscale + OpenClaw: port 8443 approach
Since network_mode: host was fixed in P0-2 (removing ports:), OpenClaw needs to reach Tailscale's HTTPS on 8443. The correct pattern is to have Tailscale serve on 443 (host network) and expose 8443 via a host-level iptables redirect, OR simply have OpenClaw connect directly to https://localhost:443 via the Tailscale host interface.
Fix — add to Script 1's Tailscale setup after tailscale up:
# Add iptables redirect so 8443 → 443 for OpenClaw compatibility
if [[ "${DEPLOY_OPENCLAW:-false}" == "true" ]]; then
    iptables -t nat -A PREROUTING -p tcp --dport 8443 -j REDIRECT --to-port 443 2>/dev/null || true
    iptables -t nat -A OUTPUT -p tcp --dport 8443 -j REDIRECT --to-port 443 2>/dev/null || true
    info "iptables rule added: 8443 → 443 for OpenClaw/Tailscale"
fi

P1-2 | Script 2 — n8n webhook URL hardcoded regardless of NETWORK_MODE
n8n needs WEBHOOK_URL and N8N_PROTOCOL set correctly:

Tailscale mode: http://<tailscale-ip>:<N8N_PORT>  
Caddy mode: https://n8n.<DOMAIN>

Fix in append_n8n():
local webhook_url protocol
if [[ "${NETWORK_MODE}" == "caddy" ]]; then
    protocol="https"
    webhook_url="https://n8n.${DOMAIN}"
else
    protocol="http"
    webhook_url="http://${TAILSCALE_IP:-localhost}:${N8N_PORT:-5678}"
fi
Then use ${protocol} and ${webhook_url} in the environment block.

P1-3 | Script 2 — Grafana GF_SERVER_ROOT_URL must be network-mode-aware
Fix in append_grafana():
local root_url
if [[ "${NETWORK_MODE}" == "caddy" ]]; then
    root_url="https://grafana.${DOMAIN}"
else
    root_url="http://${TAILSCALE_IP:-localhost}:${GRAFANA_PORT:-3003}"
fi
# Use ${root_url} in environment block

P1-4 | Script 2 — Prometheus scrape config includes caddy target unconditionally
If NETWORK_MODE=tailscale, Caddy doesn't exist and Prometheus will log scrape errors permanently.
Fix in append_prometheus():
# Only write caddy scrape job if DEPLOY_CADDY == "true"
if [[ "${DEPLOY_CADDY:-false}" == "true" ]]; then
    cat >> "${prom_cfg}" << EOF
  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']
EOF
fi

🟠 P2 — Security & Isolation

P2-1 | OpenClaw — No image source, no jail, no network isolation
OpenClaw currently shares the tenant Docker network and uses openclaw:latest which has no registry prefix — this will fail on any machine that hasn't pre-built the image.
Fix — three-part:
Part A — Image pull policy: Add pull_policy: always and document that OPENCLAW_IMAGE must be set to a reachable registry image (e.g. ghcr.io/yourorg/openclaw:latest).
Part B — Network jail: Create a dedicated openclaw_net bridge network isolated from the main AI platform network:
# In write_compose_header(), add second network if DEPLOY_OPENCLAW:
  openclaw_net:
    name: ${COMPOSE_PROJECT_NAME}-openclaw
    driver: bridge
    internal: true   # no external internet access from openclaw
Then append_openclaw() connects to both openclaw_net (primary) and ${DOCKER_NETWORK} (only if integration needed), or just openclaw_net alone if it only talks to Tailscale.
Part C — Filesystem jail (from P0-5 above): chown OPENCLAW_UID:OPENCLAW_GID on ${BASE_DIR}/openclaw with mode 750. Script 1 should generate a dedicated OPENCLAW_UID (e.g. 65534 = nobody, or a new system UID):
# In generate_secrets(), Script 1:
OPENCLAW_UID=$(id -u nobody 2>/dev/null || echo "65534")
OPENCLAW_GID=$(id -g nobody 2>/dev/null || echo "65534")

P2-2 | Script 1 — .env file permissions set after write, not before
chmod 600 is called after the heredoc writes credentials including ADMIN_PASSWORD and all secrets. If another process reads it in that window, all secrets are exposed.
Fix:
# Create the file with correct permissions BEFORE writing secrets:
install -m 600 /dev/null "${BASE_DIR}/.env"
# Then do the heredoc cat >> "${BASE_DIR}/.env"

P2-3 | Secret rotation via Script 3
Per your answer: rotation can be initiated via Script 3. Script 3 currently has no rotation capability.
Fix — add rotate_secrets() function to Script 3:
rotate_secrets() {
    info "Rotating platform secrets…"
    local new_secret new_litellm new_redis new_postgres

    read -p "  ➤ Rotate ALL secrets? This will restart affected services [y/N]: " ans
    [[ "${ans,,}" != "y" ]] && return

    new_secret=$(openssl rand -hex 32)
    new_litellm="sk-$(openssl rand -hex 24)"
    new_redis=$(openssl rand -hex 24)
    new_postgres=$(openssl rand -hex 24)

    sed -i "s/^SECRET_KEY=.*/SECRET_KEY=${new_secret}/" "${ENV_FILE}"
    sed -i "s/^LITELLM_MASTER_KEY=.*/LITELLM_MASTER_KEY=${new_litellm}/" "${ENV_FILE}"
    # etc.

    warn "Secrets rotated — restart services with: docker compose -f ${COMPOSE_FILE} up -d"
}

🟢 P3 — Health Check Accuracy

P3-1 | LiteLLM healthcheck endpoint is wrong
Current: http://localhost:4000/healthCorrect: http://localhost:4000/health/readiness
P3-2 | Qdrant healthcheck endpoint is wrong
Current: http://localhost:6333/healthzCorrect: http://localhost:6333/ (root returns 200)
P3-3 | All healthchecks need start_period tuning
Copy table


Service
Recommended start_period



Ollama
60s (model loading)


LiteLLM
60s (DB migrations)


Open WebUI
60s


AnythingLLM
45s


Authentik
120s


Dify
90s



📋 Windsurf Step-by-Step Implementation Plan
PHASE 1 — Core Blockers (do these first, in order)
TASK 1.1
File: scripts/2-deploy-services.sh
Action: In append_ollama(), replace `compose_append << EOF` with `cat >> "${COMPOSE_FILE}" << EOF`

TASK 1.2
File: scripts/2-deploy-services.sh
Action: In append_tailscale(), delete the `ports:` stanza (2 lines: `ports:` and `- "8443:443"`)
Reason: network_mode: host + ports: is invalid Docker Compose

TASK 1.3
File: scripts/1-setup-system.sh
Action: Remove `readonly` keyword from DATA_ROOT, ENV_FILE, LOG_FILE declarations (lines 12-14)
Action: In configure_tenant(), after BASE_DIR is set, add:
  DATA_ROOT="${BASE_DIR}"
  ENV_FILE="${BASE_DIR}/.env"
  LOG_FILE="${BASE_DIR}/setup.log"
  mkdir -p "${BASE_DIR}"
  touch "${LOG_FILE}"

TASK 1.4
File: scripts/3-configure-services.sh
Action: Replace the ENV_FILE detection block at top with the same glob search used in script 2:
  ENV_FILE=""
  for candidate in "/mnt/data"/*/.env "/opt/ai-platform/.env"; do
      [[ -f "${candidate}" ]] && { ENV_FILE="${candidate}"; break; }
  done
  [[ -z "${ENV_FILE}" ]] && { echo "❌ No .env found"; exit 1; }
  source "${ENV_FILE}"

TASK 1.5
File: scripts/1-setup-system.sh
Action: In generate_secrets(), before the .env heredoc, add:
  DOCKER_NETWORK="aip-${TENANT_ID}"
  COMPOSE_PROJECT_NAME="aip-${TENANT_ID}"
Action: Add these two lines to the .env heredoc:
  DOCKER_NETWORK=${DOCKER_NETWORK}
  COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}

TASK 1.6
File: scripts/2-deploy-services.sh
Action: Add create_directories() function (full code in P0-5 above)
Action: Call create_directories() in main() BEFORE write_compose_header()

TASK 1.7
File: scripts/2-deploy-services.sh
Action: Complete the truncated append_openwebui() healthcheck block:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 60s
  labels:
    com.ai-platform: "true"
    com.ai-platform.tenant: "${TENANT_ID}"

PHASE 2 — Network Mode Correctness
TASK 2.1
File: scripts/2-deploy-services.sh → append_n8n()
Action: Make N8N_PROTOCOL and WEBHOOK_URL conditional on NETWORK_MODE
  if caddy: protocol=https, webhook=https://n8n.${DOMAIN}
  if tailscale/direct: protocol=http, webhook=http://${TAILSCALE_IP:-localhost}:${N8N_PORT}

TASK 2.2
File: scripts/2-deploy-services.sh → append_grafana()
Action: Make GF_SERVER_ROOT_URL conditional on NETWORK_MODE
  if caddy: https://grafana.${DOMAIN}
  if tailscale/direct: http://${TAILSCALE_IP:-localhost}:${GRAFANA_PORT}

TASK 2.3
File: scripts/2-deploy-services.sh → append_prometheus()
Action: Wrap caddy scrape job in:
  if [[ "${DEPLOY_CADDY:-false}" == "true" ]]; then ... fi

TASK 2.4
File: scripts/1-setup-system.sh → configure_network() Tailscale block
Action: After tailscale up, if DEPLOY_OPENCLAW=true, add iptables 8443→443 redirect

PHASE 3 — OpenClaw Jail & Security
TASK 3.1
File: scripts/1-setup-system.sh → generate_secrets()
Action: Add OPENCLAW_UID and OPENCLAW_GID generation:
  OPENCLAW_UID=$(id -u nobody 2>/dev/null || echo "65534")
  OPENCLAW_GID=$(id -g nobody 2>/dev/null || echo "65534")
Action: Add to .env heredoc:
  OPENCLAW_UID=${OPENCLAW_UID}
  OPENCLAW_GID=${OPENCLAW_GID}

TASK 3.2
File: scripts/2-deploy-services.sh → write_compose_header()
Action: If DEPLOY_OPENCLAW=true, add openclaw_net to networks block:
  openclaw_net:
    name: ${COMPOSE_PROJECT_NAME}-openclaw
    driver: bridge
    internal: true

TASK 3.3
File: scripts/2-deploy-services.sh → append_openclaw()  [CREATE if not exists]
Action: Write full service block with:
  - networks: [openclaw_net only]
  - user: "${OPENCLAW_UID}:${OPENCLAW_GID}"
  - volumes: openclaw_data with device: ${BASE_DIR}/openclaw
  - image: ${OPENCLAW_IMAGE:-openclaw:latest}
  - pull_policy: always
  - ports: - "${OPENCLAW_PORT:-18789}:8082"
  - restart: unless-stopped
  - labels: com.ai-platform=true, com.ai-platform.tenant=${TENANT_ID}

TASK 3.4
File: scripts/2-deploy-services.sh → create_directories()
Action: Ensure openclaw dir is chown'd to OPENCLAW_UID:OPENCLAW_GID with chmod 750
  (covered in P0-5 fix above)

TASK 3.5
File: scripts/2-deploy-services.sh → write_compose_header() volumes section
Action: Ensure openclaw_data named volume is present:
  openclaw_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${BASE_DIR}/openclaw

PHASE 4 — Health Checks & Reliability
TASK 4.1
File: scripts/2-deploy-services.sh → append_litellm()
Action: Change healthcheck test to:
  ["CMD", "curl", "-sf", "http://localhost:4000/health/readiness"]
Action: Add start_period: 60s

TASK 4.2
File: scripts/2-deploy-services.sh → append_qdrant()
Action: Change healthcheck test to:
  ["CMD", "curl", "-sf", "http://localhost:6333/"]
Action: Add start_period: 20s

TASK 4.3
File: scripts/2-deploy-services.sh
Action: Set start_period on all remaining services per the table in P3-3

TASK 4.4
File: scripts/3-configure-services.sh
Action: Add rotate_secrets() function (full code in P2-3 above)
Action: Add "Rotate secrets" option to Script 3's main menu

PHASE 5 — Security Hardening
TASK 5.1
File: scripts/1-setup-system.sh → generate_secrets()
Action: Replace the bare cat heredoc with:
  install -m 600 /dev/null "${BASE_DIR}/.env"
  cat >> "${BASE_DIR}/.env" << EOF
  ...
  EOF
  (remove the chmod 600 line that follows — it's now redundant)

TASK 5.2
File: scripts/2-deploy-services.sh → append_prometheus()
Action: Add node-exporter service if DEPLOY_PROMETHEUS=true (it is referenced in README
  but append_nodeexporter() may not be called from main())
Action: Verify main() calls append_nodeexporter when DEPLOY_PROMETHEUS=true

TASK 5.3
File: All scripts
Action: Audit every remaining reference to /opt/ai-platform and replace
  with the appropriate ${BASE_DIR} or the glob search pattern

Priority Summary Table
Copy table


Priority
Tasks
Impact if skipped



🔴 P0
1.1 → 1.7
Scripts crash, compose fails to generate or deploy


🟡 P1
2.1 → 2.4
Tailscale/Caddy mode misconfigured, n8n/Grafana broken


🟠 P2
3.1 → 3.5
OpenClaw uncontained, secrets exposed during write window


🟢 P3
4.1 → 4.4
False unhealthy states, rotation not available


🔵 P4
5.1 → 5.3
Security hardening gap, stale legacy paths


Recommended Windsurf execution order: P0 → full test run → P1 → full test run → P2+P3+P4 together.