Let me fetch all 5 scripts first.

**Reading:**
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/0-complete-cleanup.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/4-add-service.sh

---

## Master Diagnosis — Root Causes Across All Scripts

### The Single Biggest Problem

```
PostgreSQL container runs as UID 999 internally.
Script creates directories as RUNNING_UID (1001).
Script then tries chown 999:999 — but if postgres dir
already has files owned by 999, and script re-runs,
Docker volume mount resets ownership on re-entry.

The REAL fix is not chown in the script.
The fix is: use a Docker named volume OR use a
postgres init container to set ownership INSIDE Docker
before the main postgres container starts.

Every other problem flows from postgres never starting.
```

---

## Comprehensive Fix Instructions for Windsurf

### INSTRUCTION SET A — Script 0 (Cleanup)

```
PROBLEM: Cleanup script may leave orphaned named volumes
or stale network preventing Script 2 from creating fresh state.

FIND the section that removes containers/networks.
ENSURE it also runs:
────────────────────────────────────────────────────────────────
# Remove named volumes to prevent stale ownership
docker volume rm \
  "${COMPOSE_PROJECT_NAME}_postgres_data" \
  "${COMPOSE_PROJECT_NAME}_redis_data" \
  "${COMPOSE_PROJECT_NAME}_qdrant_data" \
  2>/dev/null || true

# Remove network explicitly
docker network rm ai_platform 2>/dev/null || true
docker network rm "${COMPOSE_PROJECT_NAME}_default" 2>/dev/null || true

# Kill any process holding port 80 or 443
fuser -k 80/tcp 2>/dev/null || true
fuser -k 443/tcp 2>/dev/null || true

log_success "Cleanup complete — safe to run Script 2"
────────────────────────────────────────────────────────────────
```

---

### INSTRUCTION SET B — Script 2, Section 1: .env Loading

```
FIND: wherever .env is loaded at the top of Script 2
REPLACE ENTIRELY WITH:
────────────────────────────────────────────────────────────────
# ── Environment Loading ──────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# DATA_ROOT must be set before this script runs
# It is written by Script 1 to /etc/ai-platform/env-pointer
if [ -f /etc/ai-platform/env-pointer ]; then
  DATA_ROOT="$(cat /etc/ai-platform/env-pointer)"
elif [ -n "${DATA_ROOT}" ]; then
  : # already set in environment
else
  echo "❌ DATA_ROOT not found. Run Script 1 first."
  exit 1
fi

ENV_FILE="${DATA_ROOT}/.env"

if [ ! -f "${ENV_FILE}" ]; then
  echo "❌ .env not found at ${ENV_FILE}"
  echo "   Run Script 1 first."
  exit 1
fi

# Safe load — handles spaces in values, ignores comments
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

# Validate minimum required vars
for REQUIRED in COMPOSE_PROJECT_NAME DOMAIN DATA_ROOT; do
  if [ -z "${!REQUIRED}" ]; then
    echo "❌ Required variable ${REQUIRED} is empty in .env"
    exit 1
  fi
done

# Define canonical compose command used everywhere in this script
COMPOSE="docker compose \
  --project-name ${COMPOSE_PROJECT_NAME} \
  --env-file ${ENV_FILE} \
  --file ${SCRIPT_DIR}/docker-compose.yml"

log_success ".env loaded | Project: ${COMPOSE_PROJECT_NAME} | Domain: ${DOMAIN}"
────────────────────────────────────────────────────────────────

ADD to Script 1 — after writing .env:
────────────────────────────────────────────────────────────────
# Write env pointer so Script 2 can find .env without DATA_ROOT being set
mkdir -p /etc/ai-platform
echo "${DATA_ROOT}" > /etc/ai-platform/env-pointer
chmod 644 /etc/ai-platform/env-pointer
log_success "Env pointer written to /etc/ai-platform/env-pointer"
────────────────────────────────────────────────────────────────
```

---

### INSTRUCTION SET C — Script 2, Section 2: PostgreSQL Fix (THE CRITICAL FIX)

```
FIND: the postgres directory creation and deployment block
REPLACE ENTIRELY WITH:
────────────────────────────────────────────────────────────────
deploy_postgres() {
  print_section "PostgreSQL"

  # Use Docker NAMED VOLUME — not bind mount — to avoid host ownership issues
  # The named volume is managed by Docker, postgres container owns it internally
  # This eliminates the UID 999 vs 1001 ownership conflict entirely

  # Check if named volume exists
  if ! docker volume inspect "${COMPOSE_PROJECT_NAME}_postgres_data" \
       &>/dev/null; then
    log_info "Creating postgres named volume..."
    docker volume create "${COMPOSE_PROJECT_NAME}_postgres_data"
  fi

  # Write the postgres service with named volume to a override file
  # This overrides any bind-mount in docker-compose.yml
  cat > "${SCRIPT_DIR}/docker-compose.postgres-override.yml" << EOF
version: '3.8'
services:
  postgres:
    volumes:
      - ${COMPOSE_PROJECT_NAME}_postgres_data:/var/lib/postgresql/data

volumes:
  ${COMPOSE_PROJECT_NAME}_postgres_data:
    external: true
EOF

  # Deploy postgres using override
  docker compose \
    --project-name "${COMPOSE_PROJECT_NAME}" \
    --env-file "${ENV_FILE}" \
    --file "${SCRIPT_DIR}/docker-compose.yml" \
    --file "${SCRIPT_DIR}/docker-compose.postgres-override.yml" \
    up -d postgres

  # Wait for postgres to be genuinely ready
  log_info "Waiting for PostgreSQL to accept connections..."
  ATTEMPTS=0
  MAX_ATTEMPTS=30

  until docker exec "${COMPOSE_PROJECT_NAME}-postgres-1" \
        pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
        &>/dev/null 2>&1; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ "${ATTEMPTS}" -ge "${MAX_ATTEMPTS}" ]; then
      log_error "PostgreSQL did not become ready after 60 seconds"
      log_error "Logs:"
      docker logs "${COMPOSE_PROJECT_NAME}-postgres-1" --tail=30
      exit 1
    fi
    sleep 2
  done

  log_success "PostgreSQL ready"

  # Create pgvector extension
  docker exec "${COMPOSE_PROJECT_NAME}-postgres-1" \
    psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    -c "CREATE EXTENSION IF NOT EXISTS vector;" \
    && log_success "pgvector extension created" \
    || log_warning "pgvector extension creation failed — check if pgvector image is used"
}
────────────────────────────────────────────────────────────────

IMPORTANT: Also update docker-compose.yml to use named volume syntax:
────────────────────────────────────────────────────────────────
# In docker-compose.yml postgres service:
  postgres:
    image: pgvector/pgvector:pg16
    container_name: ${COMPOSE_PROJECT_NAME}-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data    # ← named volume
    networks:
      - ai_platform
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

# At the bottom of docker-compose.yml add:
volumes:
  postgres_data:
    name: ${COMPOSE_PROJECT_NAME}_postgres_data
    external: true
────────────────────────────────────────────────────────────────
```

---

### INSTRUCTION SET D — Script 2, Section 3: Deployment Order (Layered)

```
FIND: the main deployment sequence
REPLACE WITH this strict layered order:
────────────────────────────────────────────────────────────────
main_deploy() {

  # ── Layer 0: Infrastructure ───────────────────────────────
  print_section "Layer 0: Network"
  docker network create \
    --driver bridge \
    --label "project=${COMPOSE_PROJECT_NAME}" \
    ai_platform 2>/dev/null \
    || log_info "Network ai_platform already exists"

  # ── Layer 1: Databases ────────────────────────────────────
  print_section "Layer 1: Databases"
  deploy_postgres          # uses named volume, waits for pg_isready
  deploy_redis             # simple, fast
  deploy_qdrant            # waits for HTTP /health

  # ── Layer 2: Core AI Services ─────────────────────────────
  print_section "Layer 2: Core Services"
  [ "${ENABLE_LITELLM}"    = "true" ] && deploy_litellm
  [ "${ENABLE_OPENWEBUI}"  = "true" ] && deploy_openwebui
  [ "${ENABLE_N8N}"        = "true" ] && deploy_n8n
  [ "${ENABLE_FLOWISE}"    = "true" ] && deploy_flowise
  [ "${ENABLE_ANYTHINGLLM}"= "true" ] && deploy_anythingllm
  [ "${ENABLE_DIFY}"       = "true" ] && deploy_dify
  [ "${ENABLE_OPENCLAW}"   = "true" ] && deploy_openclaw
  [ "${ENABLE_MINIO}"      = "true" ] && deploy_minio

  # ── Layer 3: Reverse Proxy (must come AFTER apps) ─────────
  print_section "Layer 3: Caddy Reverse Proxy"
  deploy_caddy             # generates Caddyfile from enabled services

  # ── Layer 4: Monitoring ───────────────────────────────────
  print_section "Layer 4: Monitoring"
  [ "${ENABLE_PROMETHEUS}" = "true" ] && deploy_prometheus
  [ "${ENABLE_GRAFANA}"    = "true" ] && deploy_grafana

  # ── Layer 5: Networking ───────────────────────────────────
  print_section "Layer 5: Networking"
  [ "${ENABLE_TAILSCALE}"  = "true" ] && setup_tailscale
  [ "${ENABLE_GDRIVE}"     = "true" ] && setup_rclone

  # ── Final: Health Report ──────────────────────────────────
  run_health_checks
}
────────────────────────────────────────────────────────────────
```

---

### INSTRUCTION SET E — Script 2, Section 4: Caddy Dynamic Config

```
FIND: Caddy deployment / Caddyfile generation
REPLACE WITH dynamic generation based on ENABLE_* flags:
────────────────────────────────────────────────────────────────
deploy_caddy() {
  CADDY_CONFIG_DIR="${DATA_ROOT}/config/caddy"
  mkdir -p "${CADDY_CONFIG_DIR}"

  # Always include global options and health endpoint
  cat > "${CADDY_CONFIG_DIR}/Caddyfile" << EOF
{
  email ${CADDY_EMAIL:-admin@${DOMAIN}}
  admin off
}

# Health check endpoint
:2019 {
  respond /health 200
}

EOF

  # Build routes only for enabled services
  append_route() {
    local SUBDOMAIN="$1"
    local BACKEND_PORT="$2"
    local ENABLED="$3"
    local PATH_PREFIX="${4:-}"

    [ "${ENABLED}" != "true" ] && return 0

    if [ -n "${PATH_PREFIX}" ]; then
      cat >> "${CADDY_CONFIG_DIR}/Caddyfile" << EOF
${SUBDOMAIN}.${DOMAIN} {
  handle ${PATH_PREFIX}* {
    reverse_proxy localhost:${BACKEND_PORT}
  }
}

EOF
    else
      cat >> "${CADDY_CONFIG_DIR}/Caddyfile" << EOF
${SUBDOMAIN}.${DOMAIN} {
  reverse_proxy localhost:${BACKEND_PORT}
}

EOF
    fi
  }

  # Root domain → OpenWebUI (if enabled) else LiteLLM
  if [ "${ENABLE_OPENWEBUI}" = "true" ]; then
    cat >> "${CADDY_CONFIG_DIR}/Caddyfile" << EOF
${DOMAIN} {
  reverse_proxy localhost:${OPENWEBUI_PORT:-5006}
}

EOF
  fi

  append_route "n8n"          "${N8N_PORT:-5678}"       "${ENABLE_N8N}"
  append_route "flowise"      "${FLOWISE_PORT:-3001}"   "${ENABLE_FLOWISE}"
  append_route "anythingllm"  "${ANYTHINGLLM_PORT:-3001}" "${ENABLE_ANYTHINGLLM}"
  append_route "dify"         "${DIFY_PORT:-3000}"      "${ENABLE_DIFY}"
  append_route "openclaw"     "${OPENCLAW_PORT:-8080}"  "${ENABLE_OPENCLAW}"
  append_route "minio"        "${MINIO_CONSOLE_PORT:-9001}" "${ENABLE_MINIO}"
  append_route "prometheus"   "${PROMETHEUS_PORT:-9090}" "${ENABLE_PROMETHEUS}"
  append_route "grafana"      "${GRAFANA_PORT:-3000}"   "${ENABLE_GRAFANA}"
  append_route "signal"       "${SIGNAL_API_PORT:-8090}" "${ENABLE_SIGNAL_API}"

  log_success "Caddyfile written with routes for enabled services"

  # Start Caddy
  ${COMPOSE} up -d caddy

  # Wait for Caddy admin endpoint
  ATTEMPTS=0
  until curl -sf http://localhost:2019/health &>/dev/null; do
    ATTEMPTS=$((ATTEMPTS + 1))
    [ "${ATTEMPTS}" -ge 15 ] && { log_error "Caddy failed to start"; \
      docker logs "${COMPOSE_PROJECT_NAME}-caddy-1" --tail=30; exit 1; }
    sleep 2
  done

  log_success "Caddy running and accepting requests"
}
────────────────────────────────────────────────────────────────
```

---

### INSTRUCTION SET F — Script 2, Section 5: Redis and Qdrant

```
ADD these two deploy functions (currently likely missing proper wait logic):
────────────────────────────────────────────────────────────────
deploy_redis() {
  ${COMPOSE} up -d redis

  ATTEMPTS=0
  until docker exec "${COMPOSE_PROJECT_NAME}-redis-1" \
        redis-cli ping 2>/dev/null | grep -q PONG; do
    ATTEMPTS=$((ATTEMPTS + 1))
    [ "${ATTEMPTS}" -ge 20 ] && {
      log_error "Redis did not become ready"
      docker logs "${COMPOSE_PROJECT_NAME}-redis-1" --tail=20
      exit 1
    }
    sleep 2
  done
  log_success "Redis ready"
}

deploy_qdrant() {
  # Qdrant runs as UID 1000 internally
  # Use named volume to avoid host ownership issues (same fix as postgres)
  docker volume create "${COMPOSE_PROJECT_NAME}_qdrant_data" 2>/dev/null || true

  ${COMPOSE} up -d qdrant

  ATTEMPTS=0
  until curl -sf "http://localhost:${QDRANT_PORT:-6333}/health" \
        &>/dev/null; do
    ATTEMPTS=$((ATTEMPTS + 1))
    [ "${ATTEMPTS}" -ge 20 ] && {
      log_error "Qdrant did not become ready"
      docker logs "${COMPOSE_PROJECT_NAME}-qdrant-1" --tail=20
      exit 1
    }
    sleep 2
  done
  log_success "Qdrant ready"
}
────────────────────────────────────────────────────────────────
```

---

### INSTRUCTION SET G — Script 3: rclone OAuth Completion

```
FIND: rclone configuration section in Script 3
REPLACE WITH:
────────────────────────────────────────────────────────────────
configure_rclone_oauth() {
  if [ "${ENABLE_GDRIVE}" != "true" ]; then
    log_info "Google Drive disabled — skipping"
    return 0
  fi

  if [ "${GDRIVE_AUTH_METHOD}" != "oauth_tunnel" ]; then
    log_info "rclone auth method is ${GDRIVE_AUTH_METHOD} — no action needed here"
    return 0
  fi

  if [ "${RCLONE_TOKEN_OBTAINED}" = "true" ]; then
    log_success "rclone token already obtained — skipping"
    return 0
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  rclone Google Drive OAuth — Token Entry"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  On YOUR LOCAL machine run:"
  echo ""
  echo "    rclone authorize \"drive\" \\"
  echo "      \"${RCLONE_OAUTH_CLIENT_ID}\" \\"
  echo "      \"${RCLONE_OAUTH_CLIENT_SECRET}\""
  echo ""
  echo "  Complete the browser flow, then paste the token JSON below."
  echo "  Token looks like: {\"access_token\":\"ya29...\", ...}"
  echo ""
  read -rp "Paste token JSON: " RCLONE_TOKEN_JSON
  echo ""

  # Validate it looks like JSON with access_token
  if ! echo "${RCLONE_TOKEN_JSON}" | grep -q '"access_token"'; then
    log_error "Token does not look valid — missing access_token field"
    exit 1
  fi

  # Write rclone.conf
  RCLONE_CONF_DIR="${DATA_ROOT}/config/rclone"
  mkdir -p "${RCLONE_CONF_DIR}"
  cat > "${RCLONE_CONF_DIR}/rclone.conf" << EOF
[gdrive]
type = drive
client_id = ${RCLONE_OAUTH_CLIENT_ID}
client_secret = ${RCLONE_OAUTH_CLIENT_SECRET}
scope = drive
token = ${RCLONE_TOKEN_JSON}
root_folder_id = ${RCLONE_GDRIVE_FOLDER:-}
EOF

  # Mark token as obtained in .env
  sed -i "s|^RCLONE_TOKEN_OBTAINED=.*|RCLONE_TOKEN_OBTAINED=true|" \
    "${ENV_FILE}" || echo "RCLONE_TOKEN_OBTAINED=true" >> "${ENV_FILE}"

  log_success "rclone.conf written with OAuth token"

  # Start rclone container now that token exists
  ${COMPOSE} up -d rclone
  log_success "rclone container started — Google Drive sync active"
}
────────────────────────────────────────────────────────────────
```

---

## Summary: What Windsurf Must Do — In Order

```
Step  File              Change
────────────────────────────────────────────────────────────────
 1    Script 0          Add named volume removal to cleanup

 2    Script 1          Write /etc/ai-platform/env-pointer
                        after .env is created

 3    docker-compose.yml Change postgres + qdrant + redis to
                        named volumes (not bind mounts)
                        Add volumes: block at bottom

 4    Script 2          Replace .env loading with set -a/source
                        + validation + COMPOSE var definition

 5    Script 2          Replace postgres deploy with named volume
                        + pg_isready wait + pgvector creation

 6    Script 2          Add deploy_redis with redis-cli ping wait

 7    Script 2          Add deploy_qdrant with named volume
                        + HTTP health wait

 8    Script 2          Replace deployment sequence with strict
                        5-layer order

 9    Script 2          Replace Caddyfile generation with dynamic
                        ENABLE_*-aware route builder

10    Script 2          Replace rclone block — never hang,
                        print tunnel instructions, set
                        ENABLE_GDRIVE=false for this run

11    Script 2          Replace Tailscale block with daemon
                        socket check + retry IP loop

12    Script 3          Add configure_rclone_oauth function
                        with token paste + rclone.conf write
────────────────────────────────────────────────────────────────

COMMIT MESSAGE:
fix: resolve postgres ownership deadlock using named volumes;
fix: strict 5-layer deploy order with readiness gates at each layer;
fix: dynamic Caddyfile generation respects ENABLE_* flags;
fix: rclone oauth never hangs on server — deferred to Script 3;
fix: tailscale daemon socket check before up;
fix: .env loaded safely with set -a/source across all scripts;
fix: Script 0 removes named volumes on cleanup
```