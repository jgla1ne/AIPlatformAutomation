Let me read all three scripts fresh.

---

After reading all three scripts, here is the full assessment.

---

# Full Assessment

## What Was Implemented Correctly

| Area | Status | Notes |
|------|--------|-------|
| SUDO_UID detection | ✅ | Script 1 correctly uses `SUDO_UID`/`SUDO_GID` |
| Tenant naming `u${UID}` | ✅ | Deterministic, collision-free |
| `process_compose_file()` | ✅ | Variable substitution working |
| Port conflict detection | ✅ | `find_free_port()` logic present |
| Docker network namespacing | ✅ | `aip-u1001_net` pattern correct |
| Wait-for-service gates | ✅ | Health checks before dependent starts |
| `.env` as single source of truth | ✅ | Script 2 sources it correctly |

---

## Identified Problems

### Problem 1 — Redundant Volume Prompts (Your Observation)

Script 1 currently asks:
1. "Which block device to mount?" (EBS detection)
2. "Where is your data root?" (DATA_ROOT location)

These are the same question asked twice. The correct single flow:

```
STEP 1: "Dedicate a new EBS to this tenant? [y/N]"
  → Y: list unattached devices → pick one → format → mount at /mnt/u1001 → DATA_ROOT=/mnt/u1001
  → N: list mounted volumes → pick one → DATA_ROOT={mountpoint}/u1001

No second prompt. DATA_ROOT is fully derived from step 1.
```

**Fix:** Collapse both prompts into `select_storage()`. After the user picks the device or mount point, `DATA_ROOT` is set deterministically. Delete the second prompt entirely.

---

### Problem 2 — Signal Port 8090 Collision

Signal CLI REST API defaults to 8090. This port is commonly taken. Script 1 generates the port but does not run it through `find_free_port()`.

**Fix:** In Script 1 port assignment block:

```bash
# REMOVE:
SIGNAL_PORT=8090

# REPLACE with:
SIGNAL_PORT=$(find_free_port 8090 8190)
```

And in docker-compose.yml Signal service:
```yaml
signal-cli:
  ports:
    - "${SIGNAL_PORT}:8080"   # internal is always 8080, external is dynamic
```

Signal CLI REST API listens on internal port 8080 always. The host-side port should be dynamic.

---

### Problem 3 — GDrive Sync Not Wired to Qdrant Ingestion

Script 1 creates `/mnt/data/u1001/.gdrive` but there is no pipeline from:
```
Google Drive → rclone sync → /mnt/data/u1001/.gdrive → Qdrant embedding
```

**Required additions:**

**In Script 1 — directory creation:**
```bash
mkdir -p "${DATA_ROOT}/.gdrive"
mkdir -p "${DATA_ROOT}/.gdrive/documents"
mkdir -p "${DATA_ROOT}/.gdrive/embeddings_queue"
chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}/.gdrive"
```

**In Script 1 — `.env` additions:**
```bash
GDRIVE_SYNC_DIR="${DATA_ROOT}/.gdrive"
GDRIVE_RCLONE_REMOTE="gdrive-${TENANT_NAME}"
GDRIVE_SYNC_INTERVAL=3600   # seconds
EMBEDDING_WATCH_DIR="${DATA_ROOT}/.gdrive/documents"
```

**In Script 2 — add rclone container:**
```yaml
rclone:
  image: rclone/rclone:latest
  container_name: ${COMPOSE_PROJECT_NAME}-rclone
  restart: unless-stopped
  volumes:
    - ${DATA_ROOT}/.gdrive:/gdrive
    - ${DATA_ROOT}/config/rclone:/config/rclone
  entrypoint: >
    sh -c "while true; do
      rclone sync ${GDRIVE_RCLONE_REMOTE}: /gdrive/documents
        --config /config/rclone/rclone.conf
        --log-level INFO;
      sleep ${GDRIVE_SYNC_INTERVAL};
    done"
  networks:
    - ${DOCKER_NETWORK}_internal
```

**In Script 3 — rclone config wiring:**
```bash
configure_rclone() {
  log "Configuring rclone for Google Drive..."
  mkdir -p "${DATA_ROOT}/config/rclone"
  
  # Generate rclone config skeleton — user must complete OAuth
  cat > "${DATA_ROOT}/config/rclone/rclone.conf" <<EOF
[${GDRIVE_RCLONE_REMOTE}]
type = drive
scope = drive.readonly
EOF

  log "⚠️  GDrive OAuth required. Run:"
  log "   docker exec -it ${COMPOSE_PROJECT_NAME}-rclone rclone config reconnect ${GDRIVE_RCLONE_REMOTE}:"
  log "   Then paste the auth URL in your browser."
}
```

**Qdrant auto-ingestion via n8n workflow (not a script — a deployed workflow):**
- n8n watches `${EMBEDDING_WATCH_DIR}` via filesystem trigger
- Sends new/changed files to the embedding pipeline
- Upserts vectors into Qdrant collection `${TENANT_NAME}_docs`
- This workflow JSON should live in `scripts/templates/n8n-gdrive-ingest.json` and be imported by Script 3

---

### Problem 4 — Tailscale Not Fully Stood Up

Script 2 deploys the Tailscale container but `tailscale up` is never called with the auth key. The container starts but does not join the tailnet, so the Tailscale IP is never assigned and the service URL at the end of Script 1 is wrong.

**Fix in Script 3:**
```bash
configure_tailscale() {
  log "Bringing up Tailscale..."
  
  if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
    log "⚠️  No TAILSCALE_AUTH_KEY in .env"
    log "   Get one from https://login.tailscale.com/admin/settings/keys"
    read -p "   Paste auth key (or press Enter to skip): " TAILSCALE_AUTH_KEY
    if [[ -n "${TAILSCALE_AUTH_KEY}" ]]; then
      echo "TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}" >> "${ENV_FILE}"
    else
      log "⚠️  Skipping Tailscale — configure manually later"
      return 0
    fi
  fi

  # Run tailscale up inside the container
  docker exec "${COMPOSE_PROJECT_NAME}-tailscale" \
    tailscale up \
    --authkey="${TAILSCALE_AUTH_KEY}" \
    --hostname="${TENANT_NAME}-aiplatform" \
    --accept-routes

  # Retrieve assigned Tailscale IP
  sleep 5
  TAILSCALE_IP=$(docker exec "${COMPOSE_PROJECT_NAME}-tailscale" \
    tailscale ip -4 2>/dev/null || echo "pending")
  
  log "✅ Tailscale IP: ${TAILSCALE_IP}"
  echo "TAILSCALE_IP=${TAILSCALE_IP}" >> "${ENV_FILE}"
}
```

---

### Problem 5 — OpenClaw Not Deployed Properly

OpenClaw requires:
1. Internal-only network (no internet egress)
2. Specific env vars for the LLM endpoint
3. Connection to Qdrant on the shared vector DB

**docker-compose.yml addition:**
```yaml
openclaw:
  image: openclaw/openclaw:latest
  container_name: ${COMPOSE_PROJECT_NAME}-openclaw
  restart: unless-stopped
  networks:
    - ${DOCKER_NETWORK}_internal   # internal only — no internet
  environment:
    - QDRANT_URL=http://qdrant:${QDRANT_PORT}
    - QDRANT_COLLECTION=${TENANT_NAME}_docs
    - OLLAMA_URL=http://ollama:11434
    - OPENCLAW_PORT=8080
  volumes:
    - ${DATA_ROOT}/data/openclaw:/app/data
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL
  labels:
    - "ai-platform.tenant=${TENANT_NAME}"
    - "ai-platform.service=openclaw"
```

Note: OpenClaw is on `_internal` network only. It reaches Qdrant and Ollama (also on internal). It cannot reach the internet or other tenants.

---

### Problem 6 — Shared VectorDB Not Explicitly Wired

All AI services (AnythingLLM, Dify, n8n, OpenClaw) should point to the **same Qdrant instance**. Currently each service has its own connection config that may or may not be consistent.

**In Script 1 `.env` generation — add explicit shared DB vars:**
```bash
# Single VectorDB for all services — one set of vars, referenced everywhere
QDRANT_HOST=qdrant
QDRANT_HTTP_PORT=${QDRANT_PORT}
QDRANT_GRPC_PORT=${QDRANT_GRPC_PORT}
QDRANT_COLLECTION_PREFIX=${TENANT_NAME}
QDRANT_DOCS_COLLECTION=${TENANT_NAME}_docs
QDRANT_URL=http://qdrant:${QDRANT_PORT}
```

**Then in docker-compose.yml, every AI service references the same vars:**
```yaml
anythingllm:
  environment:
    - VECTOR_DB=qdrant
    - QDRANT_ENDPOINT=${QDRANT_URL}
    - QDRANT_API_KEY=${QDRANT_API_KEY:-}

dify:
  environment:
    - VECTOR_STORE=qdrant
    - QDRANT_URL=${QDRANT_URL}
    - QDRANT_API_KEY=${QDRANT_API_KEY:-}

n8n:
  environment:
    - QDRANT_URL=${QDRANT_URL}

openclaw:
  environment:
    - QDRANT_URL=${QDRANT_URL}
    - QDRANT_COLLECTION=${QDRANT_DOCS_COLLECTION}
```

One Qdrant instance. One collection namespace. All services share it. The `${TENANT_NAME}_` prefix on collection names ensures no cross-tenant data bleed on a shared EBS deployment.

---

### Problem 7 — HTTPS Validation at End of Script 1

Script 1 lists service URLs at the end but does not validate them. Given that Tailscale IP is only known after Script 3 runs `tailscale up`, Script 1 cannot show the correct HTTPS URLs.

**Correct approach:**

Move the service URL summary to the **end of Script 3**, after Tailscale is configured:

```bash
print_service_summary() {
  # Re-source env to get TAILSCALE_IP set by configure_tailscale()
  source "${ENV_FILE}"
  
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  SERVICE ENDPOINTS — Tenant: ${TENANT_NAME}"
  echo "═══════════════════════════════════════════════════════"
  
  local base_url="https://${TAILSCALE_IP}"
  
  services=(
    "AnythingLLM|${ANYTHINGLLM_PORT}"
    "Dify|${DIFY_PORT}"
    "n8n|${N8N_PORT}"
    "OpenClaw|${OPENCLAW_PORT}"
    "MinIO|${MINIO_CONSOLE_PORT}"
    "Signal|${SIGNAL_PORT}"
    "Qdrant|${QDRANT_PORT}"
  )
  
  for entry in "${services[@]}"; do
    name="${entry%|*}"
    port="${entry#*|}"
    url="${base_url}:${port}"
    
    # Validate reachability
    if curl -sk --max-time 5 "${url}" > /dev/null 2>&1; then
      echo "  ✅ ${name}: ${url}"
    else
      echo "  ❌ ${name}: ${url} (not responding)"
    fi
  done
  
  echo ""
  echo "  GDrive sync: ${GDRIVE_SYNC_DIR}"
  echo "  VectorDB:    ${QDRANT_URL}"
  echo "  Config:      ${ENV_FILE}"
  echo "═══════════════════════════════════════════════════════"
}
```

---

## Refactoring Priority Order for Windsurf

| Priority | Change | Script | Scope |
|----------|--------|--------|-------|
| P0 | Collapse redundant volume prompts into single `select_storage()` | 1 | 30 lines |
| P0 | Fix Signal port — run through `find_free_port()` | 1 + compose | 3 lines |
| P1 | Wire all AI services to shared Qdrant vars | compose | env vars only |
| P1 | `tailscale up` with auth key in Script 3 | 3 | new function |
| P1 | OpenClaw on `_internal` network with security opts | compose | service block |
| P2 | rclone container + gdrive sync pipeline | 2 + compose | new service |
| P2 | Script 3 rclone config + OAuth instructions | 3 | new function |
| P2 | Move service summary + HTTPS validation to Script 3 | 3 | new function |
| P3 | n8n gdrive ingestion workflow template | templates/ | new JSON |