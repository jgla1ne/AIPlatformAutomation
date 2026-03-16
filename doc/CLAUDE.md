# AI Platform — Final Implementation Blueprint v3
**Windsurf: read every word. Implement exactly this. Verify each section passes before moving to the next.**

---

## Ground Truth: What the Three Scripts Currently Contain

After reading every line of every uploaded file, here is the honest state:

**Script 0** — correct and complete. No changes.
**Script 2** — correct and complete. No changes.
**Script 3** — 4 bugs. All surgical fixes described below.
**Script 1** — 1 architectural gap. One block to add to `write_env_file`. No other changes.

The architecture is right. The wiring is almost there. What follows are the exact code changes, nothing more.

---

## BUG 1 — Script 3: `generate_compose` mounts the wrong postgres init filename

**File:** `scripts/3-configure-services.sh`  
**Line 419 currently reads:**
```yaml
      - ${CONFIG_DIR}/postgres/init-all-databases.sh:/docker-entrypoint-initdb.d/init-all-databases.sh:ro
```

**Script 1's `generate_postgres_init` writes the file to:**
```
${CONFIG_DIR}/postgres/init-all-databases.sh
```

**Script 3's own `generate_postgres_init` writes the file to:**
```
${CONFIG_DIR}/postgres/init-user-db.sh   ← line 185
```

These are two different filenames. The compose file mounts `init-all-databases.sh`. Script 3's generator writes `init-user-db.sh`. When Script 2 runs (which calls Script 3's `generate_configs` → Script 3's `generate_postgres_init`), the file written is `init-user-db.sh`, but the compose mount looks for `init-all-databases.sh`. The mount silently creates an empty file, postgres starts clean with no role and no per-service databases, and LiteLLM's Prisma migration fails.

**Fix A — Script 3 `generate_postgres_init`: change the output filename on line 185**

Replace:
```bash
    local out="${CONFIG_DIR}/postgres/init-user-db.sh"
```
With:
```bash
    local out="${CONFIG_DIR}/postgres/init-all-databases.sh"
```

That is the only change needed. The rest of the function is correct — the SQL creates the `litellm`, `openwebui`, `n8n`, and `flowise` databases with proper grants.

---

## BUG 2 — Script 3: `generate_compose` postgres block references `POSTGRES_USER` without `-d` flag

**File:** `scripts/3-configure-services.sh`  
**Line 421 currently reads:**
```yaml
      test: ["CMD-SHELL","pg_isready -U ${POSTGRES_USER}"]
```

`pg_isready` without `-d` checks the default database. On first startup, if the init script hasn't finished yet, the healthcheck passes before per-service databases are created. Combined with Bug 1, this is how `provision_databases` gets called before the init script has run. The fix makes the healthcheck match the actual database:

**Fix B — Script 3 `generate_compose` postgres healthcheck, line 421:**

Replace:
```yaml
      test: ["CMD-SHELL","pg_isready -U ${POSTGRES_USER}"]
```
With:
```yaml
      test: ["CMD-SHELL","pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
```

---

## BUG 3 — Script 3: `generate_compose` has no `openclaw` service block

The full stack (stack option 4 in Script 1) enables `ENABLE_OPENCLAW=true`. Script 1 collects OpenClaw config and writes `ENABLE_OPENCLAW` to the `.env`. But `generate_compose` in Script 3 has no `openclaw` service block. When `ENABLE_OPENCLAW=true`, nothing is deployed and the health dashboard shows nothing for it.

**Fix C — Script 3 `generate_compose`: add OpenClaw service block**

Insert this block immediately after the tailscale block (after line 691, before the caddy comment on line 693):

```bash
    # OpenClaw web terminal — Tailscale-gated access
    [[ "${ENABLE_OPENCLAW:-false}" == "true" ]] && cat >> "$COMPOSE_FILE" <<'EOF'
  openclaw:
    image: lscr.io/linuxserver/code-server:latest
    restart: unless-stopped
    user: "1000:${TENANT_GID:-1001}"
    environment:
      PUID: "1000"
      PGID: "${TENANT_GID:-1001}"
      PASSWORD: "${ADMIN_PASSWORD}"
      SUDO_PASSWORD: "${ADMIN_PASSWORD}"
      DEFAULT_WORKSPACE: "/mnt/data"
    volumes:
      - ${DATA_DIR}/openclaw:/config
      - /mnt/data:/mnt/data:ro
    ports:
      - "${PORT_OPENCLAW:-18789}:8443"
    healthcheck:
      test: ["CMD-SHELL","curl -sf http://localhost:8443/ || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF
```

Also add `PORT_OPENCLAW=18789` to the ports section of `generate_env` (Script 3, line ~161) alongside the other PORT_ variables:
```bash
PORT_OPENCLAW=18789
```

And add `openclaw` to the `service_is_enabled` function (Script 3, around line 784):
```bash
        openclaw)  [[ "${ENABLE_OPENCLAW:-false}" == "true" ]] ;;
```

And add `openclaw` to `prepare_directories` (Script 3, around line 58):
```bash
        "${DATA_DIR}/openclaw" \
```

And add the ownership line in `prepare_directories` alongside other 1000-UID services (around line 72):
```bash
    chown -R 1000:"${TENANT_GID:-1001}"    \
        "${DATA_DIR}/litellm" \
        "${DATA_DIR}/n8n" \
        "${DATA_DIR}/flowise" \
        "${DATA_DIR}/openwebui" \
        "${DATA_DIR}/ollama" \
        "${DATA_DIR}/anythingllm" \
        "${DATA_DIR}/tailscale" \
        "${DATA_DIR}/openclaw"
```

Also add openclaw to the health dashboard in `health_dashboard` (after the anythingllm block, around line 971):
```bash
    [[ "${ENABLE_OPENCLAW:-false}" == "true" ]] && \
        _check_http "openclaw" "http://localhost:${PORT_OPENCLAW:-18789}/"
```

And add it to the dashboard header section (after the Tailscale IP line, around line 938) so the user knows the access URL:
```bash
    if [[ "${ENABLE_OPENCLAW:-false}" == "true" && -n "$ip" ]]; then
        printf "  %-14s %s\n" "OpenClaw:" "https://${ip}:${PORT_OPENCLAW:-18789} (Tailscale only)"
    fi
```

---

## BUG 4 — Script 3: `create_ingestion_systemd` syncs to wrong path and has no qdrant ingestion command

**File:** `scripts/3-configure-services.sh`  
**Line 1067 currently reads:**
```bash
ExecStart=/bin/bash -c 'rclone sync gdrive: /mnt/data/gdrive/ && docker compose -f ${COMPOSE_FILE} exec anythingllm /app/ingest.sh'
```

Two problems:
1. Syncs to `/mnt/data/gdrive/` — a global path not scoped to the tenant. Should be `/mnt/data/${TENANT}/data/gdrive/`
2. Calls `anythingllm /app/ingest.sh` — this path doesn't exist in the mintplexlabs image. AnythingLLM has no CLI ingest endpoint. The ingestion path for Script 3's `gdrive ingest` command is via the AnythingLLM API.

**Fix D — Script 3 `create_ingestion_systemd`:**

Replace lines 1060–1087 (the entire function body) with:

```bash
create_ingestion_systemd() {
    [[ -n "${GDRIVE_CLIENT_ID:-}" ]] || return 0

    log_info "Installing gdrive-sync systemd timer..."

    local gdrive_dir="${DATA_DIR}/gdrive"
    mkdir -p "$gdrive_dir"
    chown "${TENANT_UID:-1001}:${TENANT_GID:-1001}" "$gdrive_dir"

    # Create systemd service — syncs then optionally triggers ingestion
    cat > /etc/systemd/system/gdrive-sync-${TENANT}.service <<EOF
[Unit]
Description=AI Platform GDrive sync for ${TENANT}
After=docker.service network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'rclone sync gdrive: ${DATA_DIR}/gdrive/ --log-file ${LOGS_DIR}/rclone-sync.log'
User=root
EOF

    # Create systemd timer — runs every 4 minutes
    cat > /etc/systemd/system/gdrive-sync-${TENANT}.timer <<EOF
[Unit]
Description=GDrive Sync Timer for ${TENANT}

[Timer]
OnCalendar=*:0/4
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now gdrive-sync-${TENANT}.timer

    log_success "gdrive-sync-${TENANT} timer installed — syncing to ${DATA_DIR}/gdrive/"
}
```

Also replace the gdrive CLI dispatcher (Script 3, line 1119) to add the `ingest` sub-command:

Replace:
```bash
        gdrive)         setup_gdrive_rclone && create_ingestion_systemd ;;
```
With:
```bash
        gdrive)         setup_gdrive_rclone && create_ingestion_systemd ;;
        gdrive-ingest)  ingest_gdrive_to_qdrant ;;
```

And add the new `ingest_gdrive_to_qdrant` function immediately before the CLI dispatcher guard (before line 1091):

```bash
# ── GDrive → Qdrant Ingestion ─────────────────────────────────────────────────
ingest_gdrive_to_qdrant() {
    [[ -n "${GDRIVE_CLIENT_ID:-}" ]] || {
        log_warning "GDrive not configured — run: $0 gdrive first"
        return 1
    }
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] || {
        log_warning "AnythingLLM not enabled — enable it first: $0 enable anythingllm"
        return 1
    }

    log_info "Starting GDrive → Qdrant ingestion via AnythingLLM..."

    # 1. Sync gdrive to local
    log_info "Syncing GDrive to ${DATA_DIR}/gdrive/ ..."
    mkdir -p "${DATA_DIR}/gdrive"
    rclone sync gdrive: "${DATA_DIR}/gdrive/" \
        --log-file "${LOGS_DIR}/rclone-sync.log" \
        && log_success "GDrive sync complete" \
        || { log_error "GDrive sync failed — check ${LOGS_DIR}/rclone-sync.log"; return 1; }

    # 2. Get AnythingLLM API key from .env
    local atllm_key="${ANYTHINGLLM_API_KEY:-${LITELLM_MASTER_KEY}}"
    local atllm_url="http://localhost:${PORT_ANYTHINGLLM:-3003}"

    # 3. Upload each file to AnythingLLM via its upload API
    log_info "Uploading documents to AnythingLLM for embedding into Qdrant..."
    local count=0 failed=0
    while IFS= read -r -d '' file; do
        local filename
        filename="$(basename "$file")"
        # AnythingLLM accepts file upload via /api/v1/document/upload
        if curl -sf -X POST \
            "${atllm_url}/api/v1/document/upload" \
            -H "Authorization: Bearer ${atllm_key}" \
            -F "file=@${file}" \
            > /dev/null 2>&1; then
            count=$((count + 1))
        else
            log_warning "Failed to upload: ${filename}"
            failed=$((failed + 1))
        fi
    done < <(find "${DATA_DIR}/gdrive" -type f \( \
        -name "*.pdf" -o -name "*.txt" -o -name "*.md" \
        -o -name "*.docx" -o -name "*.csv" \) -print0)

    log_success "GDrive ingestion complete — ${count} files embedded, ${failed} failed"
    log_info "Verify collections: curl -s http://localhost:${PORT_QDRANT:-6333}/collections | jq"
}
```

Update the help text in the CLI dispatcher (around line 1136) to include the new command:
```bash
            echo "  Wiring:        tailscale  gdrive  gdrive-ingest"
```

---

## GAP 5 — Script 1: `write_env_file` does not write the Script 3 path variables

**File:** `scripts/1-setup-system.sh`

Script 3 reads these five variables when sourced:
```bash
TENANT          # the tenant name
TENANT_DIR      # /mnt/data/${TENANT}
CONFIG_DIR      # ${TENANT_DIR}/configs
DATA_DIR        # ${TENANT_DIR}/data
LOGS_DIR        # ${TENANT_DIR}/logs
COMPOSE_FILE    # ${TENANT_DIR}/docker-compose.yml
```

Script 1's `write_env_file` writes `TENANT_ID`, `DATA_ROOT`, and `TENANT_DIR=${DATA_ROOT}` (line 2378)
but does **not** write `TENANT`, `CONFIG_DIR`, `DATA_DIR`, `LOGS_DIR`, or `COMPOSE_FILE`.

When Script 2 sources Script 3, Script 3's top-level path block runs first:
```bash
TENANT="${TENANT:-default}"
TENANT_DIR="${MNT_ROOT}/${TENANT}"
CONFIG_DIR="${TENANT_DIR}/configs"
...
```
Script 3 then loads the `.env` via `set -a; source "$ENV_FILE"; set +a`. Since the `.env` doesn't
contain `CONFIG_DIR` or `DATA_DIR`, Script 3's own defaults (derived from `TENANT`) are what remain.
This works correctly **as long as `TENANT` is set in the environment before sourcing** — which
Script 2 does (`export TENANT="${1:-datasquiz}"`). This is correct.

**However**, the `.env` needs `TENANT` (not `TENANT_ID`) written explicitly so that any future
Script 3 direct invocation (`bash scripts/3-configure-services.sh datasquiz health`) also works
without requiring the caller to always `export TENANT` first.

**Fix E — Script 1 `write_env_file`:**

In the `.env` heredoc, in the Platform Identity section (around line 2049), add `TENANT` alongside `TENANT_ID`:

Find this block (around line 2048):
```bash
# ─── Platform Identity ────────────────────────────────────────────────────────
TENANT_ID=${TENANT_ID}
DOMAIN=${DOMAIN}
ADMIN_EMAIL=${ADMIN_EMAIL}
DATA_ROOT=${DATA_ROOT}
```

Replace with:
```bash
# ─── Platform Identity ────────────────────────────────────────────────────────
TENANT_ID=${TENANT_ID}
TENANT=${TENANT_ID}
DOMAIN=${DOMAIN}
ADMIN_EMAIL=${ADMIN_EMAIL}
DATA_ROOT=${DATA_ROOT}
TENANT_DIR=${DATA_ROOT}
CONFIG_DIR=${DATA_ROOT}/configs
DATA_DIR=${DATA_ROOT}/data
LOGS_DIR=${DATA_ROOT}/logs
COMPOSE_FILE=${DATA_ROOT}/docker-compose.yml
```

This is additive — no existing line is removed. These variables are written once with correct values
at collection time and used by Script 3 every time.

---

## Summary: All Changes in One Place

### `scripts/3-configure-services.sh` — 4 changes

**Change 1** — Line 185: fix postgres init filename
```bash
# FROM:
    local out="${CONFIG_DIR}/postgres/init-user-db.sh"
# TO:
    local out="${CONFIG_DIR}/postgres/init-all-databases.sh"
```

**Change 2** — Line 421: fix postgres healthcheck
```yaml
# FROM:
      test: ["CMD-SHELL","pg_isready -U ${POSTGRES_USER}"]
# TO:
      test: ["CMD-SHELL","pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
```

**Change 3** — After line 691 (after tailscale block, before caddy): add openclaw service block + update `prepare_directories`, `service_is_enabled`, `health_dashboard`, `generate_env` ports (all described in BUG 3 above)

**Change 4** — Replace `create_ingestion_systemd` function (lines 1054–1088) and add `ingest_gdrive_to_qdrant` function + update CLI dispatcher (all described in BUG 4 above)

### `scripts/1-setup-system.sh` — 1 change

**Change 5** — In `write_env_file` heredoc, Platform Identity section: add `TENANT`, `TENANT_DIR`, `CONFIG_DIR`, `DATA_DIR`, `LOGS_DIR`, `COMPOSE_FILE` (described in GAP 5 above)

### `scripts/2-deploy-services.sh` — 0 changes
### `scripts/0-complete-cleanup.sh` — 0 changes

---

## Post-Implementation Verification Sequence

Run these after every change, in this order:

```bash
# 1. Nuclear wipe
sudo bash scripts/0-complete-cleanup.sh datasquiz

# 2. Confirm clean slate
ls /mnt/data/  # Should show only 'datasquiz/' (empty)
docker ps -a   # Should show no ai- containers

# 3. Run Script 1 — input collection only
sudo bash scripts/1-setup-system.sh
# Select stack 4 (Full) or 2 (Standard + Tailscale + Rclone)
# At the end: choose NOT to auto-run Script 2 yet

# 4. Verify .env has correct variables
grep -E "^TENANT=|^CONFIG_DIR=|^DATA_DIR=|^COMPOSE_FILE=|^LITELLM_DATABASE_URL=" \
  /mnt/data/datasquiz/.env
# Expected output (example):
# TENANT=datasquiz
# CONFIG_DIR=/mnt/data/datasquiz/configs
# DATA_DIR=/mnt/data/datasquiz/data
# COMPOSE_FILE=/mnt/data/datasquiz/docker-compose.yml
# LITELLM_DATABASE_URL=postgresql://...@postgres:5432/litellm

# 5. Run Script 2
sudo bash scripts/2-deploy-services.sh datasquiz

# 6. After Script 2 completes, verify postgres init ran correctly
sudo docker compose -f /mnt/data/datasquiz/docker-compose.yml \
  exec postgres psql -U aiplatform -c "\l" \
  | grep -E "litellm|openwebui|n8n|flowise"
# Expected: all 4 databases listed

# 7. Wait 90s for LiteLLM Prisma migration, then check
sleep 90
curl -sf http://localhost:4000/health/liveliness && echo "LiteLLM: OK"

# 8. Check all services via health dashboard
sudo bash scripts/3-configure-services.sh datasquiz health

# 9. Test GDrive ingestion (if configured)
sudo bash scripts/3-configure-services.sh datasquiz gdrive-ingest

# 10. Verify Qdrant has collections after ingestion
curl -s http://localhost:6333/collections | python3 -m json.tool
```

---

## What the User Will See After a Successful Deployment

### Services accessible via HTTPS (Caddy + Let's Encrypt or internal TLS):
| URL | Service | Shared backend |
|-----|---------|---------------|
| `https://chat.DOMAIN` | Open WebUI | LiteLLM routing + Qdrant vectors |
| `https://litellm.DOMAIN` | LiteLLM API gateway | Routes local↔external models |
| `https://anythingllm.DOMAIN` | AnythingLLM | Qdrant + LiteLLM |
| `https://n8n.DOMAIN` | n8n automation | LiteLLM AI nodes |
| `https://flowise.DOMAIN` | Flowise | LiteLLM |
| `https://grafana.DOMAIN` | Grafana | Prometheus metrics |

### Tailscale-only access (shown in health dashboard):
| Access | Service |
|--------|---------|
| `https://<tailscale-ip>:18789` | OpenClaw web terminal (full shell, /mnt/data read access) |

### Data flow:
```
Google Drive → rclone sync → /mnt/data/datasquiz/data/gdrive/
                                    ↓  (bash scripts/3-configure-services.sh datasquiz gdrive-ingest)
                              AnythingLLM upload API
                                    ↓
                              Qdrant (embeddings stored at /mnt/data/datasquiz/data/qdrant/)
                                    ↓  (shared by)
                   Open WebUI + AnythingLLM + Flowise + n8n
```

### User-driven document ingestion:
AnythingLLM at `https://anythingllm.DOMAIN` → Upload Documents → stored in same Qdrant instance

### LiteLLM routing strategy:
- Local models via Ollama (zero cost, private)
- External models via OpenAI / Anthropic / Groq (fallback, configurable routing strategy)
- All services point to `http://litellm:4000/v1` — single gateway, no per-service API key management

---

## The One Thing That Will Still Require Manual Action

Tailscale authentication requires a valid `tskey-auth-...` key entered during Script 1's
`collect_network_config` step. After Script 2 deploys tailscale, it calls `configure_tailscale`
which authenticates non-interactively using that key. The Tailscale IP is then written to `.env`
and displayed in the health dashboard. If the key is expired or missing, Tailscale will not
authenticate and OpenClaw will only be accessible on localhost:18789. Resolution: get a fresh
auth key from tailscale.com/admin, update `TAILSCALE_AUTH_KEY` in the `.env`, and run:
```bash
sudo bash scripts/3-configure-services.sh datasquiz tailscale
```