# Implementation Plan for Windsurf — rclone + Tailscale + OpenClaw + LiteLLM

---

## Pre-Implementation Rules

```
DO NOT refactor any code unrelated to these 4 feature areas.
DO NOT change script structure or menu numbering.
DO NOT add new scripts.
Make changes in this exact order — commit after each phase.
Show a diff after each phase before proceeding to the next.
```

---

## Phase 1 — Script 1: Collect rclone and Tailscale Credentials

### 1A — rclone Auth Collection

```
In Script 1, find the Google Drive / rclone section.
Replace whatever is there with this exact flow:

────────────────────────────────────────────────
print_section "Google Drive Sync (rclone)"

prompt: "Enable Google Drive sync? [y/N]"
if no → skip entire section, set GDRIVE_ENABLED=false in .env, continue

if yes:
  print:
  "Select authentication method:
   1. Service Account JSON (recommended — fully headless)
   2. OAuth Client ID + Secret (personal Google account)"

  prompt: "Method [1/2]:"

  IF method 1 (Service Account):
    prompt: "Full path to service account JSON file:"
    → validate file exists and is valid JSON
    → copy file to ${DATA_ROOT}/config/rclone/service-account.json
    → set chmod 600 on the file
    → write to .env:
         RCLONE_AUTH_METHOD=service_account
         RCLONE_SA_JSON_PATH=${DATA_ROOT}/config/rclone/service-account.json

  IF method 2 (OAuth Client):
    prompt: "GCP OAuth Client ID:"
    → store as RCLONE_OAUTH_CLIENT_ID
    prompt: "GCP OAuth Client Secret:"
    → store as RCLONE_OAUTH_CLIENT_SECRET
    → write to .env:
         RCLONE_AUTH_METHOD=oauth_client
         RCLONE_OAUTH_CLIENT_ID=<value>
         RCLONE_OAUTH_CLIENT_SECRET=<value>

  COMMON to both methods:
    prompt: "Google Drive folder to sync (blank = root):"
    → default to empty string (root)
    → write to .env: RCLONE_GDRIVE_FOLDER=<value>

    prompt: "Local sync destination (default: ${DATA_ROOT}/gdrive):"
    → default to ${DATA_ROOT}/gdrive
    → write to .env: RCLONE_MOUNT_POINT=${DATA_ROOT}/gdrive

    prompt: "Sync interval in seconds (default: 3600):"
    → default to 3600
    → validate integer
    → write to .env: RCLONE_SYNC_INTERVAL=3600

    → write to .env:
         GDRIVE_ENABLED=true

    → create directories:
         mkdir -p ${DATA_ROOT}/config/rclone
         mkdir -p ${DATA_ROOT}/gdrive
         mkdir -p ${DATA_ROOT}/logs/rclone
         chown -R ${RUNNING_UID}:${RUNNING_GID} all above dirs
```

### 1B — Tailscale Credential Collection

```
In Script 1, find the Tailscale section (or add after networking section).
Replace/add this exact flow:

────────────────────────────────────────────────
print_section "Tailscale VPN (required for OpenClaw)"

print:
"Tailscale is required for OpenClaw internal access.
 Get an auth key at: https://login.tailscale.com/admin/settings/keys
 Use a reusable auth key for persistent installs."

prompt: "Tailscale auth key (tskey-auth-...):"
→ validate starts with "tskey-"
→ write to .env: TAILSCALE_AUTH_KEY=<value>

prompt: "Tailscale hostname for this machine (default: ai-platform):"
→ default to ai-platform
→ write to .env: TAILSCALE_HOSTNAME=<value>

Note: TAILSCALE_IP will be populated automatically by Script 2
→ write placeholder to .env: TAILSCALE_IP=pending
```

---

## Phase 2 — Script 2: Deploy rclone Container and Tailscale

### 2A — Generate rclone.conf Before Container Start

```
In Script 2, in the deployment section, BEFORE docker compose up, add:

────────────────────────────────────────────────
generate_rclone_config() {
  if [ "${GDRIVE_ENABLED}" != "true" ]; then
    log_info "Google Drive sync disabled — skipping rclone config"
    return
  fi

  local conf_path="${DATA_ROOT}/config/rclone/rclone.conf"

  if [ "${RCLONE_AUTH_METHOD}" = "service_account" ]; then
    cat > "${conf_path}" << EOF
[gdrive]
type = drive
scope = drive
service_account_file = /config/rclone/service-account.json
EOF

  elif [ "${RCLONE_AUTH_METHOD}" = "oauth_client" ]; then
    # Run headless OAuth flow inside temporary rclone container
    # This generates a token and writes it to rclone.conf
    log_info "Running rclone OAuth headless authorization..."

    docker run --rm \
      --user ${RUNNING_UID}:${RUNNING_GID} \
      -v ${DATA_ROOT}/config/rclone:/config/rclone \
      rclone/rclone:latest \
      config create gdrive drive \
        scope=drive \
        client_id="${RCLONE_OAUTH_CLIENT_ID}" \
        client_secret="${RCLONE_OAUTH_CLIENT_SECRET}"

    # Headless OAuth will print a URL — user must visit it
    # and paste the verification code back into the terminal
    # rclone handles this natively in --config create flow
  fi

  chmod 600 "${conf_path}"
  chown ${RUNNING_UID}:${RUNNING_GID} "${conf_path}"
  log_success "rclone config written to ${conf_path}"
}

Call generate_rclone_config early in the deploy sequence.
```

### 2B — rclone Docker Compose Service

```
In the docker-compose.yml (or equivalent compose block in Script 2),
add this service IF GDRIVE_ENABLED=true:

  rclone-gdrive:
    image: rclone/rclone:latest
    container_name: rclone-gdrive
    user: "${RUNNING_UID}:${RUNNING_GID}"
    restart: unless-stopped
    volumes:
      - ${DATA_ROOT}/config/rclone:/config/rclone:ro
      - ${DATA_ROOT}/gdrive:/data/gdrive
      - ${DATA_ROOT}/logs/rclone:/logs
    environment:
      - RCLONE_CONFIG=/config/rclone/rclone.conf
    command: >
      sync
      gdrive:${RCLONE_GDRIVE_FOLDER}
      /data/gdrive
      --log-file=/logs/rclone.log
      --log-level=INFO
      --transfers=4
      --checkers=8
    networks:
      - ai-platform

Note: This runs a one-shot sync on container start.
Repeat sync is handled by Script 3 management menu (manual trigger or interval).
For interval sync, Script 3 will use a wrapper that restarts the container on schedule.
DO NOT use a cron loop inside the container — keep containers single-purpose.
```

### 2C — Tailscale Bring-Up and IP Retrieval

```
In Script 2, after core services are up, add this block:

────────────────────────────────────────────────
setup_tailscale() {
  log_info "Setting up Tailscale..."

  # Install tailscale if not present
  if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
  fi

  # Start tailscaled daemon if not running
  if ! systemctl is-active --quiet tailscaled; then
    systemctl enable tailscaled
    systemctl start tailscaled
  fi

  # Authenticate
  tailscale up \
    --authkey="${TAILSCALE_AUTH_KEY}" \
    --hostname="${TAILSCALE_HOSTNAME}" \
    --accept-routes \
    --ssh

  # Wait for IP assignment (max 30 seconds)
  local ts_ip=""
  local attempts=0
  while [ -z "${ts_ip}" ] && [ ${attempts} -lt 15 ]; do
    ts_ip=$(tailscale ip -4 2>/dev/null || true)
    [ -z "${ts_ip}" ] && sleep 2
    attempts=$((attempts + 1))
  done

  if [ -z "${ts_ip}" ]; then
    log_error "Tailscale did not assign an IP within 30 seconds"
    log_error "Check: tailscale status"
    exit 1
  fi

  # Write IP back to .env (replace placeholder)
  sed -i "s/TAILSCALE_IP=pending/TAILSCALE_IP=${ts_ip}/" "${ENV_FILE}"

  log_success "Tailscale IP: ${ts_ip}"
  log_success "OpenClaw accessible at: http://${ts_ip}:18789"
}

Call setup_tailscale BEFORE docker compose up so OpenClaw
has the correct env at start time.
```

### 2D — OpenClaw: Remove from Caddyfile, Display Tailscale URL

```
In Script 2, in the Caddyfile generation section:

REMOVE this block entirely if it exists:
  openclaw.ai.datasquiz.net {
      reverse_proxy openclaw:18789
  }

OpenClaw is NOT exposed via Caddy. It is Tailscale-only.

INSTEAD, in the final summary printed at end of Script 2, add:

  🔒 OpenClaw (internal only):
     URL: http://${TAILSCALE_IP}:18789
     Access via Tailscale VPN only
     Install Tailscale client on your device: https://tailscale.com/download
```

### 2E — LiteLLM: Generate config.yaml Before Container Start

```
In Script 2, before docker compose up, add:

────────────────────────────────────────────────
generate_litellm_config() {
  local conf_path="${DATA_ROOT}/config/litellm/config.yaml"
  mkdir -p "${DATA_ROOT}/config/litellm"

  # Read which providers were selected in Script 1
  # LITELLM_OPENAI_ENABLED, LITELLM_ANTHROPIC_ENABLED etc from .env

  cat > "${conf_path}" << EOF
model_list:
EOF

  if [ "${LITELLM_OPENAI_ENABLED}" = "true" ]; then
    cat >> "${conf_path}" << EOF
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: ${OPENAI_API_KEY}
  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: ${OPENAI_API_KEY}
EOF
  fi

  if [ "${LITELLM_ANTHROPIC_ENABLED}" = "true" ]; then
    cat >> "${conf_path}" << EOF
  - model_name: claude-sonnet-4-5
    litellm_params:
      model: anthropic/claude-sonnet-4-5
      api_key: ${ANTHROPIC_API_KEY}
  - model_name: claude-haiku-3-5
    litellm_params:
      model: anthropic/claude-haiku-3-5
      api_key: ${ANTHROPIC_API_KEY}
EOF
  fi

  # Always add the general settings block
  cat >> "${conf_path}" << EOF

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/litellm

litellm_settings:
  drop_params: true
  request_timeout: 120
EOF

  chmod 600 "${conf_path}"
  chown ${RUNNING_UID}:${RUNNING_GID} "${conf_path}"
  log_success "LiteLLM config written to ${conf_path}"
}

Call generate_litellm_config before docker compose up.

Also ensure the litellm service in compose has:
  volumes:
    - ${DATA_ROOT}/config/litellm/config.yaml:/app/config.yaml:ro
  command: ["--config", "/app/config.yaml", "--port", "4000"]
```

---

## Phase 3 — Script 3: rclone Management Menu

```
In Script 3, add a menu section for Google Drive management.
Only show this section if GDRIVE_ENABLED=true.

────────────────────────────────────────────────
gdrive_management_menu() {
  while true; do
    print_section "Google Drive Sync Management"
    echo "  1. Run sync now (one-shot)"
    echo "  2. View sync logs (last 50 lines)"
    echo "  3. View sync status (last run result)"
    echo "  4. Change sync folder"
    echo "  5. Change sync interval"
    echo "  6. Enable auto-sync (restart container on interval)"
    echo "  7. Disable auto-sync"
    echo "  8. Back to main menu"

    prompt: "Select option [1-8]:"

    case selection:
      1) # Run sync now
         docker restart rclone-gdrive
         echo "Sync started. View progress with option 2."
         ;;

      2) # View logs
         docker logs rclone-gdrive --tail 50
         tail -n 50 ${DATA_ROOT}/logs/rclone/rclone.log
         ;;

      3) # Status
         docker inspect rclone-gdrive \
           --format "Status: {{.State.Status}} | Exit: {{.State.ExitCode}} | Started: {{.State.StartedAt}}"
         ;;

      4) # Change folder
         prompt: "New Google Drive folder path (blank = root):"
         → update RCLONE_GDRIVE_FOLDER in .env
         → update docker-compose.yml command line
         → docker compose up -d rclone-gdrive
         ;;

      5) # Change interval
         prompt: "New sync interval in seconds:"
         → validate integer
         → update RCLONE_SYNC_INTERVAL in .env
         → if auto-sync is enabled, restart the interval mechanism
         ;;

      6) # Enable auto-sync
         → Create a systemd timer OR a lightweight wrapper container
         → Recommended: use a simple bash loop in a wrapper script
         → Write /mnt/data/scripts/gdrive-autosync.sh:
              #!/bin/bash
              while true; do
                docker restart rclone-gdrive
                sleep ${RCLONE_SYNC_INTERVAL}
              done
         → Run as a detached process: nohup bash /mnt/data/scripts/gdrive-autosync.sh &
         → Write PID to /mnt/data/run/gdrive-autosync.pid
         → Update RCLONE_AUTOSYNC_ENABLED=true in .env
         ;;

      7) # Disable auto-sync
         → Read PID from /mnt/data/run/gdrive-autosync.pid
         → kill PID
         → Update RCLONE_AUTOSYNC_ENABLED=false in .env
         ;;
    esac
  done
}
```

---

## Phase 4 — Verification Checklist for Windsurf

```
After all changes, run these checks and show output:

1. rclone config:
   cat ${DATA_ROOT}/config/rclone/rclone.conf
   → must show [gdrive] block with correct auth method
   → must NOT show plaintext passwords if service account

2. rclone container:
   docker ps --filter name=rclone-gdrive
   → must show running status

3. Tailscale:
   tailscale status
   tailscale ip -4
   → must show assigned IP
   grep TAILSCALE_IP ${ENV_FILE}
   → must NOT show "pending"

4. LiteLLM config:
   cat ${DATA_ROOT}/config/litellm/config.yaml
   → must show at least one model in model_list
   → must show master_key and database_url

5. LiteLLM API:
   curl -s http://localhost:4000/health \
     -H "Authorization: Bearer ${LITELLM_MASTER_KEY}"
   → must return {"status": "healthy"}

6. Caddyfile:
   grep -i openclaw /mnt/data/config/caddy/Caddyfile
   → must return NOTHING (openclaw removed from caddy)

7. OpenClaw direct:
   curl -s http://$(tailscale ip -4):18789
   → must return a response (not connection refused)

8. Script 3 menu:
   Run Script 3 → navigate to Google Drive section
   → must show menu options 1-8
   → option 1 must restart rclone-gdrive container
```

---

## Commit Order

```
Phase 1 complete → commit: "feat(s1): collect rclone auth and tailscale credentials"
Phase 2A-B complete → commit: "feat(s2): generate rclone.conf and deploy container"
Phase 2C-D complete → commit: "feat(s2): tailscale bringup, IP retrieval, openclaw caddy removal"
Phase 2E complete → commit: "feat(s2): generate litellm config.yaml before compose up"
Phase 3 complete → commit: "feat(s3): gdrive sync management menu"
Phase 4 complete → commit: "verify: all checklist items passing"
```