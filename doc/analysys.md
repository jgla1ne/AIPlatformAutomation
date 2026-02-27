## Architecture Correction — Multi-Tenant Reality

The folder structure tells the full story:

```
/mnt/data/                    ← BASE_DIR (shared platform layer)
├── apparmor/                 ← shared security profiles
├── cache/                    ← shared cache
├── caddy/                    ← shared reverse proxy config
├── config/                   ← shared service configs
├── data/                     ← shared data layer
├── logs/                     ← shared logs
├── metadata/                 ← shared metadata
├── postgres-init/            ← shared DB init scripts
└── u1001/                    ← TENANT ROOT
    └── .env                  ← tenant-scoped config (correct location)
```

**The .env lives at `/mnt/data/u1001/.env` — NOT `/mnt/data/.env`**

Every script that reads `ENV_FILE` must point to the tenant path, not the base path.

---

## Full Action Plan for Windsurf

### ACTION 1 — Fix ENV_FILE path across ALL 5 scripts

```bash
# WRONG (what scripts likely have now):
ENV_FILE="${BASE_DIR}/.env"
ENV_FILE="/mnt/data/.env"

# CORRECT (what every script must have):
TENANT_ID="${TENANT_ID:-u1001}"
TENANT_DIR="${BASE_DIR}/${TENANT_ID}"
ENV_FILE="${TENANT_DIR}/.env"
```

Every script must resolve `TENANT_ID` first, then derive `ENV_FILE`. The pattern at the top of **each** script:

```bash
#!/usr/bin/env bash
set -o pipefail

# ── Resolve tenant context ──────────────────────────────────────────
BASE_DIR="${BASE_DIR:-/mnt/data}"
TENANT_ID="${TENANT_ID:-u1001}"
TENANT_DIR="${BASE_DIR}/${TENANT_ID}"
ENV_FILE="${TENANT_DIR}/.env"

[[ -f "${ENV_FILE}" ]] || { echo "FATAL: .env not found at ${ENV_FILE}"; exit 1; }
source "${ENV_FILE}"
# ────────────────────────────────────────────────────────────────────
```

---

### ACTION 2 — Fix duplicate keys in .env RIGHT NOW

```bash
ENV_FILE="/mnt/data/u1001/.env"

# Deduplicate — last value wins (awk keeps first occurrence, reverse trick keeps last)
tac "${ENV_FILE}" | awk -F= '!seen[$1]++' | tac > /tmp/env_clean
mv /tmp/env_clean "${ENV_FILE}"
chmod 600 "${ENV_FILE}"
chown jglaine:jglaine "${ENV_FILE}"

# Verify the problem keys
grep -E "^DOCKER_NETWORK=|^POSTGRES_PORT=|^REDIS_PORT=|^SIGNAL_API_PORT=|^LITELLM_MASTER_KEY=" "${ENV_FILE}"
```

Expected clean output:
```
DOCKER_NETWORK=aip-u1001_net       ← tenant-scoped only
POSTGRES_PORT=5432                 ← once
REDIS_PORT=6379                    ← once
SIGNAL_API_PORT=8090               ← once (8090 is correct)
LITELLM_MASTER_KEY=739201db8...    ← once (longer key wins)
```

---

### ACTION 3 — Fix tenant directory structure

Current state shows `u1001/` only has `.env`. Script 2 must create the full tenant data tree before starting containers:

```bash
# Script 2 must create this structure under TENANT_DIR:
setup_tenant_dirs() {
  local dirs=(
    "${TENANT_DIR}/data/n8n"
    "${TENANT_DIR}/data/dify"
    "${TENANT_DIR}/data/openwebui"
    "${TENANT_DIR}/data/anythingllm"
    "${TENANT_DIR}/data/flowise"
    "${TENANT_DIR}/data/openclaw"
    "${TENANT_DIR}/data/signal-api"
    "${TENANT_DIR}/config/n8n"
    "${TENANT_DIR}/config/dify"
    "${TENANT_DIR}/config/litellm"
    "${TENANT_DIR}/config/rclone"
    "${TENANT_DIR}/logs"
    "${TENANT_DIR}/backups"
  )

  for dir in "${dirs[@]}"; do
    mkdir -p "${dir}"
    chown "${RUNNING_UID}:${RUNNING_GID}" "${dir}"
  done

  # Shared platform dirs (not tenant-scoped)
  mkdir -p "${BASE_DIR}/apparmor"
  mkdir -p "${BASE_DIR}/caddy"
  mkdir -p "${BASE_DIR}/postgres-init"

  log_success "Tenant directory tree created under ${TENANT_DIR}"
}
```

---

### ACTION 4 — Fix DOCKER_NETWORK consistency

```
# .env must have ONE network entry:
DOCKER_NETWORK=aip-u1001_net

# docker-compose.yml must reference it:
networks:
  default:
    name: ${DOCKER_NETWORK}
    driver: bridge

# Script 2 must create it before docker compose up:
docker network inspect "${DOCKER_NETWORK}" &>/dev/null || \
  docker network create "${DOCKER_NETWORK}"
```

---

### ACTION 5 — Fix missing functions (add_caddy_service, add_rclone_service)

These must be defined **inline** in Script 2. Full implementations:

```bash
# ── CADDY SERVICE REGISTRATION ──────────────────────────────────────
add_caddy_service() {
  local service_name="$1"
  local upstream_port="$2"
  local subdomain="${3:-$service_name}"
  local caddyfile="${BASE_DIR}/caddy/Caddyfile"

  # Avoid duplicate entries
  if grep -q "${subdomain}.${DOMAIN_NAME}" "${caddyfile}" 2>/dev/null; then
    log_info "Caddy route already exists for ${subdomain}.${DOMAIN_NAME}"
    return 0
  fi

  cat >> "${caddyfile}" <<EOF

${subdomain}.${DOMAIN_NAME} {
    reverse_proxy localhost:${upstream_port}
    tls ${SSL_EMAIL}
    encode gzip
    header {
        X-Frame-Options SAMEORIGIN
        X-Content-Type-Options nosniff
    }
}
EOF
  log_success "Caddy route: ${subdomain}.${DOMAIN_NAME} → :${upstream_port}"
}

# ── RCLONE SERVICE SETUP ────────────────────────────────────────────
add_rclone_service() {
  local rclone_conf="${TENANT_DIR}/config/rclone/rclone.conf"
  mkdir -p "$(dirname "${rclone_conf}")"

  if [[ "${RCLONE_TOKEN_OBTAINED}" == "true" ]]; then
    log_info "rclone token already obtained — skipping OAuth"
    return 0
  fi

  # Write config skeleton
  cat > "${rclone_conf}" <<EOF
[gdrive]
type = drive
client_id = ${RCLONE_OAUTH_CLIENT_ID}
client_secret = ${RCLONE_OAUTH_CLIENT_SECRET}
scope = drive
token =
root_folder_id =
EOF
  chown "${RUNNING_UID}:${RUNNING_GID}" "${rclone_conf}"
  chmod 600 "${rclone_conf}"

  log_warn "GDrive OAuth required. Visit this URL to authenticate:"
  log_warn "${SIGNAL_API_PAIRING_URL}"
  log_info "Waiting 120s for OAuth completion..."

  # Non-blocking — mark for completion in Script 3
  log_warn "If OAuth not completed now, re-run: bash 3-configure-services.sh --gdrive"
}
```

---

### ACTION 6 — Vector DB injection into AI services

Script 2 must inject Qdrant connection vars into each service **at compose deploy time** via the compose file or via post-start `docker exec`. The compose file must have:

```yaml
# docker-compose.yml — per service Qdrant wiring

anythingllm:
  environment:
    - VECTOR_DB=qdrant
    - QDRANT_ENDPOINT=http://qdrant:${QDRANT_PORT}
    - QDRANT_API_KEY=${QDRANT_API_KEY}

dify:
  environment:
    - VECTOR_STORE=qdrant
    - QDRANT_URL=http://qdrant:${QDRANT_PORT}
    - QDRANT_API_KEY=${QDRANT_API_KEY}

open-webui:
  environment:
    - VECTOR_DB=qdrant
    - QDRANT_URI=http://qdrant:${QDRANT_PORT}

flowise:
  environment:
    - FLOWISE_QDRANT_HOST=http://qdrant:${QDRANT_PORT}
```

---

### ACTION 7 — Tailscale before Caddy

Script 2 execution order must be:

```
1. create_tenant_dirs()
2. create_docker_network()
3. start_infrastructure()     ← postgres, redis, qdrant, minio
4. wait_for_infrastructure()  ← health gates
5. init_databases()           ← pgvector ext, minio buckets, qdrant collections
6. setup_tailscale()          ← get real IP, update .env
7. generate_caddy_config()    ← uses real TAILSCALE_IP + DOMAIN_NAME
8. start_all_services()       ← all AI services
9. setup_rclone()             ← gdrive OAuth prompt
10. print_service_urls()      ← correct subdomain URLs only
```

---

### ACTION 8 — Fix service URL output in Script 1

```bash
# Script 1 final output must be based on PROXY_CONFIG_METHOD:

print_service_summary() {
  source "${ENV_FILE}"

  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  Tenant: ${TENANT_ID}  |  Domain: ${DOMAIN_NAME}"
  echo "═══════════════════════════════════════════════════"
  echo "  Services will be available after Script 2 at:"
  echo ""

  if [[ "${PROXY_CONFIG_METHOD}" == "subdomain" ]]; then
    echo "  n8n:          https://n8n.${DOMAIN_NAME}"
    echo "  Dify:         https://dify.${DOMAIN_NAME}"
    echo "  AnythingLLM:  https://anythingllm.${DOMAIN_NAME}"
    echo "  Flowise:      https://flowise.${DOMAIN_NAME}"
    echo "  OpenWebUI:    https://openwebui.${DOMAIN_NAME}"
    echo "  LiteLLM:      https://litellm.${DOMAIN_NAME}"
    echo "  MinIO:        https://minio.${DOMAIN_NAME}"
    echo "  Grafana:      https://grafana.${DOMAIN_NAME}"
    echo "  Prometheus:   https://prometheus.${DOMAIN_NAME}"
    echo "  OpenClaw:     https://openclaw.${DOMAIN_NAME}"
    echo "  Signal API:   https://signal-api.${DOMAIN_NAME}"
    echo ""
    echo "  Internal only (no public route):"
    echo "  Ollama:       http://ollama:${OLLAMA_PORT}"
    echo "  Qdrant:       http://qdrant:${QDRANT_PORT}"
    echo "  Postgres:     postgresql://postgres:${POSTGRES_PORT}"
    echo "  Redis:        redis://redis:${REDIS_PORT}"
  fi

  echo ""
  echo "  Next step: bash 2-deploy-services.sh"
  echo "═══════════════════════════════════════════════════"
}
```

---

## Summary for Windsurf

```
BEFORE touching Script 2, do these in order:

1. IMMEDIATE — on server now:
   tac /mnt/data/u1001/.env | awk -F= '!seen[$1]++' | tac > /tmp/env_clean
   mv /tmp/env_clean /mnt/data/u1001/.env
   chmod 600 /mnt/data/u1001/.env

2. ALL 5 SCRIPTS — fix ENV_FILE path:
   TENANT_DIR="${BASE_DIR}/${TENANT_ID}"
   ENV_FILE="${TENANT_DIR}/.env"

3. SCRIPT 2 — inline add_caddy_service() and add_rclone_service()

4. SCRIPT 2 — enforce execution order (Actions 6 + 7 above)

5. DOCKER-COMPOSE.YML — add Qdrant env vars to all 4 AI services

6. SCRIPT 1 — fix print_service_summary() to use subdomain format

7. SCRIPT 2 — fix DOCKER_NETWORK to use aip-u1001_net consistently

DO NOT run Script 2 until items 1-4 are verified.
```