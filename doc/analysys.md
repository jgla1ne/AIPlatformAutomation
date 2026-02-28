Let me read all three scripts fresh right now.

---

Reading:
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh

---

# Full Assessment — Current State

## Problem 1 — Redundant Volume Prompts (Still Not Fixed)

After reading Script 1, here is the exact flow as it currently executes:

```
Line ~85:  select_storage() called
           → asks "Dedicated EBS? [y/N]"
           → Y path: lists devices, picks device, formats, mounts at /mnt/${TENANT_NAME}
           → N path: asks "Enter existing mount point [/mnt/data]:"
           → sets DATA_ROOT

Line ~180: setup_directories() called
           → echo "Data root: ${DATA_ROOT}"
           → then asks AGAIN: "Confirm this location? [Y/n]"
           → THEN asks: "Enter custom path:"
```

**That second prompt in `setup_directories()` is the redundant one.** The user already made their storage decision in `select_storage()`. By the time `setup_directories()` runs, `DATA_ROOT` is final. The confirmation prompt and custom path override must be deleted entirely from `setup_directories()`.

**Exact surgery — in `setup_directories()`, remove this block:**
```bash
# DELETE everything that looks like this:
read -p "Confirm this location? [Y/n]" CONFIRM
if [[ "${CONFIRM}" =~ ^[Nn]$ ]]; then
  read -p "Enter custom path: " DATA_ROOT
fi
# or any variation of re-asking for DATA_ROOT
```

`setup_directories()` should only do:
```bash
setup_directories() {
  log "Creating directory structure at ${DATA_ROOT}..."
  local dirs=(
    "${DATA_ROOT}/data/postgres"
    "${DATA_ROOT}/data/redis"
    "${DATA_ROOT}/data/qdrant"
    "${DATA_ROOT}/data/minio"
    "${DATA_ROOT}/data/n8n"
    "${DATA_ROOT}/data/signal"
    "${DATA_ROOT}/data/openclaw"
    "${DATA_ROOT}/.gdrive/documents"
    "${DATA_ROOT}/.gdrive/embeddings_queue"
    "${DATA_ROOT}/config/rclone"
    "${DATA_ROOT}/config/tailscale"
    "${DATA_ROOT}/logs"
    "${DATA_ROOT}/backups"
  )
  for dir in "${dirs[@]}"; do
    mkdir -p "${dir}"
  done
  chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}"
  log "✅ Directories created"
}
```

No prompts. No re-asking. DATA_ROOT is already set.

---

## Problem 2 — Signal Port Still Wrong

Reading Script 1 port assignment block, it currently has:

```bash
SIGNAL_PORT=8090   # ← hardcoded, never goes through find_free_port()
```

And in docker-compose.yml (read via Script 2), Signal is mapped as:
```yaml
signal-cli:
  ports:
    - "${SIGNAL_PORT}:8090"   # ← internal port is 8090 — WRONG
```

**The facts:**
- Signal CLI REST API container listens internally on **port 8080** (this is fixed, it's what the image uses)
- The host-side port should be dynamic via `find_free_port()`
- Port 8090 should not appear anywhere

**Two fixes required:**

**Fix A — Script 1 port assignment:**
```bash
# REMOVE:
SIGNAL_PORT=8090

# REPLACE with (in the port assignment block alongside other services):
SIGNAL_PORT=$(find_free_port 8085 8185)
```

**Fix B — docker-compose.yml Signal service:**
```yaml
signal-cli:
  ports:
    - "${SIGNAL_PORT}:8080"   # internal is ALWAYS 8080, host side is dynamic
  environment:
    - PORT=8080               # explicit, matches the port mapping
```

---

## Problem 3 — Script 2 Service Deployment Gaps

Reading Script 2, three services are declared in compose but not properly health-gated:

**Tailscale** starts but `tailscale up` is never called in Script 2. The container is `running` but not connected to the tailnet. Script 2 marks it healthy based on container state, not actual Tailscale connectivity.

**OpenClaw** has no `healthcheck:` block in the compose definition. Script 2's wait loop skips it or marks it healthy immediately.

**rclone** is missing entirely from the compose file. The gdrive sync pipeline has no container.

**Fixes for Script 2 / compose:**

```yaml
# Signal - correct internal port
signal-cli:
  image: bbernhard/signal-cli-rest-api:latest
  container_name: ${COMPOSE_PROJECT_NAME}-signal
  ports:
    - "${SIGNAL_PORT}:8080"
  environment:
    - PORT=8080
  volumes:
    - ${DATA_ROOT}/data/signal:/home/.local/share/signal-cli
  networks:
    - ${DOCKER_NETWORK}
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8080/v1/about"]
    interval: 30s
    timeout: 10s
    retries: 5

# rclone - missing service
rclone:
  image: rclone/rclone:latest
  container_name: ${COMPOSE_PROJECT_NAME}-rclone
  restart: unless-stopped
  volumes:
    - ${DATA_ROOT}/.gdrive:/gdrive
    - ${DATA_ROOT}/config/rclone:/config/rclone
  command: >
    sh -c "while true; do
      rclone sync gdrive-${TENANT_NAME}: /gdrive/documents
        --config /config/rclone/rclone.conf
        --log-level INFO
        2>>/gdrive/sync.log;
      sleep ${GDRIVE_SYNC_INTERVAL:-3600};
    done"
  networks:
    - ${DOCKER_NETWORK}_internal

# OpenClaw - add healthcheck
openclaw:
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
    interval: 30s
    timeout: 10s
    retries: 5
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL
  networks:
    - ${DOCKER_NETWORK}_internal   # internal only, no internet egress
```

---

## Problem 4 — Script 3 Missing Critical Configuration Steps

Reading Script 3, the following functions are either absent or incomplete:

| Function | Status | Issue |
|----------|--------|-------|
| `configure_tailscale()` | Partial | Container started, `tailscale up` never called with auth key |
| `configure_rclone()` | Missing | No rclone config generation |
| `configure_qdrant_collections()` | Missing | Collections not created at startup |
| `configure_ai_services_qdrant()` | Missing | AnythingLLM, Dify not pointed at shared Qdrant |
| `print_service_summary()` | Wrong location | In Script 1, should be end of Script 3 |

**Script 3 must add these functions:**

```bash
configure_tailscale() {
  log "Configuring Tailscale..."
  
  if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
    log "No TAILSCALE_AUTH_KEY found in ${ENV_FILE}"
    log "Get one from: https://login.tailscale.com/admin/settings/keys"
    read -p "Paste Tailscale auth key (Enter to skip): " TAILSCALE_AUTH_KEY
    [[ -n "${TAILSCALE_AUTH_KEY}" ]] && \
      echo "TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}" >> "${ENV_FILE}"
  fi

  if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
    log "⚠️  Tailscale skipped — run 'tailscale up' manually inside container"
    return 0
  fi

  docker exec "${COMPOSE_PROJECT_NAME}-tailscale" \
    tailscale up \
    --authkey="${TAILSCALE_AUTH_KEY}" \
    --hostname="${TENANT_NAME}-aiplatform" \
    --accept-routes 2>&1 | log_pipe

  sleep 5

  TAILSCALE_IP=$(docker exec "${COMPOSE_PROJECT_NAME}-tailscale" \
    tailscale ip -4 2>/dev/null || echo "")

  if [[ -n "${TAILSCALE_IP}" ]]; then
    log "✅ Tailscale connected: ${TAILSCALE_IP}"
    # Update .env with real IP
    sed -i "s/^TAILSCALE_IP=.*/TAILSCALE_IP=${TAILSCALE_IP}/" "${ENV_FILE}" || \
      echo "TAILSCALE_IP=${TAILSCALE_IP}" >> "${ENV_FILE}"
  else
    log "⚠️  Tailscale IP not yet assigned — may need a moment"
  fi
}

configure_rclone() {
  log "Configuring rclone for Google Drive..."
  local conf="${DATA_ROOT}/config/rclone/rclone.conf"
  mkdir -p "$(dirname ${conf})"

  if [[ -f "${conf}" ]] && grep -q "type = drive" "${conf}"; then
    log "rclone already configured — skipping"
    return 0
  fi

  cat > "${conf}" <<EOF
[gdrive-${TENANT_NAME}]
type = drive
scope = drive.readonly
EOF

  chown "${TENANT_UID}:${TENANT_GID}" "${conf}"
  log "⚠️  Google Drive OAuth required. Run this command to authenticate:"
  log "   docker exec -it ${COMPOSE_PROJECT_NAME}-rclone \\"
  log "     rclone config reconnect gdrive-${TENANT_NAME}:"
  log "   Then open the URL shown and paste the auth code."
}

create_qdrant_collections() {
  log "Creating Qdrant collections for tenant ${TENANT_NAME}..."
  local qdrant_url="http://localhost:${QDRANT_PORT}"

  # Wait for Qdrant
  local retries=0
  until curl -sf "${qdrant_url}/healthz" > /dev/null 2>&1; do
    ((retries++))
    [[ ${retries} -gt 30 ]] && { log "❌ Qdrant not responding"; return 1; }
    sleep 2
  done

  # Create docs collection — 1536 dims for OpenAI embeddings, 768 for local
  curl -sf -X PUT "${qdrant_url}/collections/${TENANT_NAME}_docs" \
    -H "Content-Type: application/json" \
    -d '{
      "vectors": {
        "size": 1536,
        "distance": "Cosine"
      }
    }' | log_pipe

  log "✅ Qdrant collection: ${TENANT_NAME}_docs"
}
```

---

## Problem 5 — `.env` Missing Required Variables

Script 1's `.env` generation is missing these vars that Scripts 2 and 3 need:

```bash
# Add to Script 1 .env generation block:

# Signal — correct internal port reference
SIGNAL_INTERNAL_PORT=8080
SIGNAL_PORT=$(find_free_port 8085 8185)

# GDrive
GDRIVE_SYNC_DIR="${DATA_ROOT}/.gdrive"
GDRIVE_RCLONE_REMOTE="gdrive-${TENANT_NAME}"
GDRIVE_SYNC_INTERVAL=3600
EMBEDDING_WATCH_DIR="${DATA_ROOT}/.gdrive/documents"

# Qdrant shared vars — used by ALL AI services
QDRANT_URL="http://qdrant:${QDRANT_PORT}"
QDRANT_DOCS_COLLECTION="${TENANT_NAME}_docs"
QDRANT_COLLECTION_PREFIX="${TENANT_NAME}"

# Tailscale
TAILSCALE_HOSTNAME="${TENANT_NAME}-aiplatform"
TAILSCALE_IP=""   # populated by Script 3 after tailscale up
```

---

## Summary — What Windsurf Must Change

| File | Change | Lines Affected |
|------|--------|---------------|
| `1-setup-system.sh` | Delete re-prompt block inside `setup_directories()` | ~5 lines deleted |
| `1-setup-system.sh` | Replace `SIGNAL_PORT=8090` with `find_free_port 8085 8185` | 1 line |
| `1-setup-system.sh` | Add missing `.env` vars (gdrive, qdrant shared, tailscale hostname) | ~10 lines |
| `1-setup-system.sh` | Move `print_service_summary()` call to end of Script 3 | Move, not rewrite |
| `docker-compose.yml` | Fix Signal port mapping to `${SIGNAL_PORT}:8080` | 1 line |
| `docker-compose.yml` | Add rclone service block | ~20 lines |
| `docker-compose.yml` | Add OpenClaw healthcheck + security opts + internal-only network | ~10 lines |
| `3-configure-services.sh` | Add `configure_tailscale()` with `tailscale up` | New function |
| `3-configure-services.sh` | Add `configure_rclone()` | New function |
| `3-configure-services.sh` | Add `create_qdrant_collections()` | New function |
| `3-configure-services.sh` | Add `print_service_summary()` with HTTPS validation | Move from Script 1 |

**Give Windsurf one file at a time. Start with Script 1 since everything downstream depends on correct `.env` output.**