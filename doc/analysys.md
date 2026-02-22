Let me read all three scripts from GitHub.

**Reading:**
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh

---

## What I Found

### rclone — The Hanging Problem

```
Script 2 is calling:
  rclone config create gdrive drive \
    --config "${RCLONE_CONFIG}" \
    client_id="${RCLONE_OAUTH_CLIENT_ID}" \
    client_secret="${RCLONE_OAUTH_CLIENT_SECRET}"

This launches rclone's OAuth flow which:
  1. Tries xdg-open (fails on server — no desktop)
  2. Falls back to: "please go to http://127.0.0.1:53682/auth?state=..."
  3. Hangs forever waiting for the browser callback to 127.0.0.1

127.0.0.1 means the rclone HTTP listener is on THE SERVER.
You cannot reach it from your laptop browser.
This is fundamentally broken for a remote server.
```

### The Fix: rclone Remote Authorization

```
rclone has a built-in flag for exactly this situation:
  --auth-no-browser    ← stops it trying to open a browser
  --auth-url           ← this does NOT exist for remote
  
The CORRECT flag is:
  rclone authorize "drive" \
    --auth-no-browser \
    client_id \
    client_secret

BUT this still binds to 127.0.0.1.

The ONLY working solutions for a remote headless server are:
  A. Service Account JSON       ← no OAuth at all, recommended
  B. Run rclone locally on YOUR laptop, paste token into server
  C. SSH port-forward: ssh -L 53682:localhost:53682 user@server
     then open http://localhost:53682/auth?... in YOUR browser
```

---

## Windsurf Implementation Instructions

### Fix 1 — Script 1: Remove OAuth Collection, Add Port-Forward Option

```
FILE: scripts/1-setup-system.sh
FIND: the Google Drive / rclone section that collects credentials
REPLACE THE ENTIRE SECTION WITH:

────────────────────────────────────────────────────────────────
print_section "Google Drive Sync (rclone)"
echo ""
echo "Select authentication method:"
echo "  1. Service Account JSON  (RECOMMENDED — fully headless, no browser)"
echo "  2. OAuth via SSH tunnel  (personal Google account — requires extra step)"
echo "  3. Skip — disable Google Drive sync"
echo ""
read -rp "Method [1/2/3, default 3]: " GDRIVE_METHOD
GDRIVE_METHOD=${GDRIVE_METHOD:-3}

case "${GDRIVE_METHOD}" in

  1)  # Service Account
      echo ""
      echo "Download your service account JSON from:"
      echo "  GCP Console → IAM & Admin → Service Accounts → Keys → Add Key → JSON"
      echo "The service account must have Google Drive API enabled and"
      echo "the target Drive folder shared with the service account email."
      echo ""
      read -rp "Full path to service account JSON file: " SA_JSON_PATH
      
      if [ ! -f "${SA_JSON_PATH}" ]; then
        echo "ERROR: File not found: ${SA_JSON_PATH}"
        exit 1
      fi
      
      # Validate it's a service account JSON
      if ! python3 -c "
import json,sys
d=json.load(open('${SA_JSON_PATH}'))
assert d.get('type')=='service_account', 'Not a service account JSON'
" 2>/dev/null; then
        echo "ERROR: File does not appear to be a GCP service account JSON"
        exit 1
      fi
      
      mkdir -p "${DATA_ROOT}/config/rclone"
      cp "${SA_JSON_PATH}" "${DATA_ROOT}/config/rclone/service-account.json"
      chmod 600 "${DATA_ROOT}/config/rclone/service-account.json"
      
      # Write rclone.conf directly — no interactive auth ever needed
      cat > "${DATA_ROOT}/config/rclone/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
service_account_file = /data/config/rclone/service-account.json
EOF
      chmod 600 "${DATA_ROOT}/config/rclone/rclone.conf"
      
      read -rp "Google Drive folder ID to sync (blank = root of My Drive): " RCLONE_GDRIVE_FOLDER
      read -rp "Sync interval in seconds [3600]: " RCLONE_SYNC_INTERVAL
      RCLONE_SYNC_INTERVAL=${RCLONE_SYNC_INTERVAL:-3600}
      
      write_env GDRIVE_ENABLED true
      write_env RCLONE_AUTH_METHOD service_account
      write_env RCLONE_GDRIVE_FOLDER "${RCLONE_GDRIVE_FOLDER}"
      write_env RCLONE_SYNC_INTERVAL "${RCLONE_SYNC_INTERVAL}"
      write_env RCLONE_MOUNT_POINT "${DATA_ROOT}/gdrive"
      
      echo "✅ Service account configured — no browser interaction needed"
      ;;

  2)  # OAuth via SSH tunnel
      echo ""
      echo "This method requires a ONE-TIME step from your local machine."
      echo ""
      echo "You need your GCP OAuth Client ID and Secret."
      echo "Get them from: GCP Console → APIs & Services → Credentials → OAuth 2.0 Client IDs"
      echo ""
      read -rp "GCP OAuth Client ID: " RCLONE_OAUTH_CLIENT_ID
      read -rsp "GCP OAuth Client Secret: " RCLONE_OAUTH_CLIENT_SECRET
      echo ""
      read -rp "Google Drive folder ID to sync (blank = root of My Drive): " RCLONE_GDRIVE_FOLDER
      read -rp "Sync interval in seconds [3600]: " RCLONE_SYNC_INTERVAL
      RCLONE_SYNC_INTERVAL=${RCLONE_SYNC_INTERVAL:-3600}
      
      write_env GDRIVE_ENABLED true
      write_env RCLONE_AUTH_METHOD oauth_tunnel
      write_env RCLONE_OAUTH_CLIENT_ID "${RCLONE_OAUTH_CLIENT_ID}"
      write_env RCLONE_OAUTH_CLIENT_SECRET "${RCLONE_OAUTH_CLIENT_SECRET}"
      write_env RCLONE_GDRIVE_FOLDER "${RCLONE_GDRIVE_FOLDER}"
      write_env RCLONE_SYNC_INTERVAL "${RCLONE_SYNC_INTERVAL}"
      write_env RCLONE_MOUNT_POINT "${DATA_ROOT}/gdrive"
      write_env RCLONE_TOKEN_OBTAINED false
      
      echo ""
      echo "✅ Credentials saved."
      echo ""
      echo "⚠️  IMPORTANT: Before running Script 2, you must obtain a token."
      echo "   Run Script 3 → Google Drive → 'Authorize rclone (SSH tunnel)'"
      echo "   OR run this on your LOCAL machine:"
      echo ""
      echo "   rclone authorize 'drive' '${RCLONE_OAUTH_CLIENT_ID}' '${RCLONE_OAUTH_CLIENT_SECRET}'"
      echo ""
      echo "   Paste the resulting token into Script 3 → Google Drive → Paste token"
      ;;

  3)  # Skip
      write_env GDRIVE_ENABLED false
      echo "Google Drive sync disabled"
      ;;

esac
────────────────────────────────────────────────────────────────
```

### Fix 2 — Script 2: Never Call rclone config, Validate Token Exists

```
FILE: scripts/2-deploy-services.sh
FIND: any function that calls rclone config create, rclone authorize, 
      or any rclone interactive command
      
REPLACE WITH:

────────────────────────────────────────────────────────────────
setup_rclone() {
  if [ "${GDRIVE_ENABLED}" != "true" ]; then
    log_info "Google Drive sync disabled — skipping rclone setup"
    return 0
  fi

  log_info "Setting up rclone..."
  mkdir -p "${DATA_ROOT}/config/rclone"
  mkdir -p "${DATA_ROOT}/gdrive"
  mkdir -p "${DATA_ROOT}/logs/rclone"

  # Config must already exist from Script 1
  if [ ! -f "${DATA_ROOT}/config/rclone/rclone.conf" ]; then
    if [ "${RCLONE_AUTH_METHOD}" = "service_account" ]; then
      log_error "rclone.conf missing. Re-run Script 1 and select Service Account."
      exit 1
    elif [ "${RCLONE_AUTH_METHOD}" = "oauth_tunnel" ]; then
      if [ "${RCLONE_TOKEN_OBTAINED}" != "true" ]; then
        log_warning "rclone OAuth token not yet obtained."
        log_warning "Run Script 3 → Google Drive → Authorize rclone to complete setup."
        log_warning "rclone container will NOT be started until token is present."
        return 0   # ← DO NOT HANG. Continue deploy without rclone.
      fi
    fi
  fi

  log_success "rclone config present — container will sync on start"
}
────────────────────────────────────────────────────────────────

CRITICAL: Script 2 must NEVER hang waiting for user input or a browser.
If rclone is not ready, log a warning and continue. Do not exit 1.
Do not call any rclone command that opens a URL or waits for input.
```

### Fix 3 — Script 3: Add rclone Token Authorization Menu

```
FILE: scripts/3-configure-services.sh
ADD this function and menu item to the Google Drive section:

────────────────────────────────────────────────────────────────
authorize_rclone_oauth() {
  # This is the ONE-TIME token acquisition for OAuth method
  # Two sub-options: SSH tunnel (on server) or paste token from local machine

  echo ""
  echo "rclone OAuth Authorization"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Option A — Run on THIS SERVER (requires SSH tunnel from your laptop):"
  echo ""
  echo "  1. On your LOCAL machine, open a NEW terminal and run:"
  echo "     ssh -L 53682:localhost:53682 $(whoami)@<THIS_SERVER_IP>"
  echo "     Keep this terminal open."
  echo ""
  echo "  2. Press Enter below to start rclone authorization..."
  echo "     When rclone shows a URL, copy the URL."
  echo "     REPLACE '127.0.0.1' with 'localhost' (already correct for tunnel)."
  echo "     Open it in your LOCAL browser."
  echo "     Authorize, then come back here."
  echo ""
  echo "Option B — Run on YOUR LOCAL MACHINE (no tunnel needed):"
  echo ""
  echo "  On your LOCAL machine (must have rclone installed), run:"
  echo "  rclone authorize 'drive' \\"
  echo "    '${RCLONE_OAUTH_CLIENT_ID}' \\"
  echo "    '${RCLONE_OAUTH_CLIENT_SECRET}'"
  echo ""
  echo "  Copy the token JSON that rclone prints."
  echo "  Select option B below to paste it."
  echo ""
  read -rp "Choose [A=SSH tunnel on server / B=paste token from local]: " AUTH_CHOICE

  case "${AUTH_CHOICE^^}" in
    A)
      echo ""
      echo "Starting rclone authorization on this server..."
      echo "Make sure your SSH tunnel is open first!"
      echo ""
      read -rp "Press Enter when SSH tunnel is ready..."
      
      # Run rclone with --auth-no-browser so it prints the URL instead of opening it
      # The URL will be http://127.0.0.1:53682/auth?... 
      # which works through the SSH tunnel as http://localhost:53682/auth?...
      rclone authorize "drive" \
        --auth-no-browser \
        "${RCLONE_OAUTH_CLIENT_ID}" \
        "${RCLONE_OAUTH_CLIENT_SECRET}" \
        --config "${DATA_ROOT}/config/rclone/rclone.conf"
      
      # rclone writes the token directly to rclone.conf
      if grep -q "token" "${DATA_ROOT}/config/rclone/rclone.conf" 2>/dev/null; then
        write_env RCLONE_TOKEN_OBTAINED true
        log_success "Token obtained and saved to rclone.conf"
        offer_to_start_rclone_container
      else
        log_error "Token not found in rclone.conf — authorization may have failed"
      fi
      ;;
      
    B)
      echo ""
      echo "Paste the complete [gdrive] config block from your local rclone config."
      echo "It should look like:"
      echo ""
      echo "  [gdrive]"
      echo "  type = drive"
      echo "  client_id = ..."
      echo "  client_secret = ..."
      echo "  token = {\"access_token\":\"...\",\"refresh_token\":\"...\", ...}"
      echo ""
      echo "Paste below, then press Ctrl+D on an empty line when done:"
      echo ""
      
      mkdir -p "${DATA_ROOT}/config/rclone"
      cat > "${DATA_ROOT}/config/rclone/rclone.conf"
      chmod 600 "${DATA_ROOT}/config/rclone/rclone.conf"
      
      if grep -q "token" "${DATA_ROOT}/config/rclone/rclone.conf" 2>/dev/null; then
        write_env RCLONE_TOKEN_OBTAINED true
        log_success "Token saved to rclone.conf"
        offer_to_start_rclone_container
      else
        log_error "Pasted config does not appear to contain a token"
        log_error "Make sure you included the full [gdrive] block with token line"
      fi
      ;;
  esac
}

offer_to_start_rclone_container() {
  echo ""
  read -rp "Start rclone sync container now? [Y/n]: " START_NOW
  if [[ "${START_NOW:-Y}" =~ ^[Yy] ]]; then
    docker compose -f "${DATA_ROOT}/docker/docker-compose.yml" up -d rclone-gdrive
    log_success "rclone container started"
  fi
}
────────────────────────────────────────────────────────────────

ADD to the Google Drive menu in Script 3:
  "8) Authorize rclone (SSH tunnel or paste token)" → authorize_rclone_oauth
```

---

## Tailscale Audit

```
Reading Script 2 for Tailscale implementation...
```

### What Script 2 Currently Does (Tailscale)

```
From the code I can see it:
  1. Installs tailscale via apt if not present
  2. Calls: tailscale up --authkey="${TAILSCALE_AUTH_KEY}"
  3. Retrieves IP with: tailscale ip -4
  4. Writes TAILSCALE_IP to .env

Problems I can see:
  - No check for --accept-dns=false (needed to avoid DNS conflicts with Docker)
  - No check for tailscaled daemon running before tailscale up
  - IP retrieval may run before tailscale finishes negotiating
  - No timeout/retry on IP retrieval
  - Missing --hostname flag (defaults to machine hostname — may collide in Tailscale network)
```

### Fix 4 — Script 2: Correct Tailscale Bringup

```
FILE: scripts/2-deploy-services.sh
FIND: the tailscale setup function
REPLACE WITH:

────────────────────────────────────────────────────────────────
setup_tailscale() {
  log_info "Setting up Tailscale..."

  # Install if not present
  if ! command -v tailscale &>/dev/null; then
    log_info "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
  fi

  # Ensure tailscaled daemon is running
  if ! systemctl is-active --quiet tailscaled; then
    systemctl enable tailscaled
    systemctl start tailscaled
    sleep 3
  fi

  # Bring up tailscale with correct flags for a Docker host
  log_info "Bringing up Tailscale..."
  tailscale up \
    --authkey="${TAILSCALE_AUTH_KEY}" \
    --hostname="${TAILSCALE_HOSTNAME:-ai-platform}" \
    --accept-dns=false \
    --accept-routes=false \
    --reset
  # --accept-dns=false   ← critical: prevents Tailscale overwriting /etc/resolv.conf
  #                         which breaks Docker DNS
  # --accept-routes=false ← don't accept subnet routes from other nodes
  # --reset              ← ensures flags apply cleanly even if previously configured

  # Wait for IP assignment with timeout
  log_info "Waiting for Tailscale IP assignment..."
  TAILSCALE_IP=""
  ATTEMPTS=0
  MAX_ATTEMPTS=30   # 30 × 2s = 60 seconds max

  while [ -z "${TAILSCALE_IP}" ] && [ "${ATTEMPTS}" -lt "${MAX_ATTEMPTS}" ]; do
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)
    if [ -z "${TAILSCALE_IP}" ]; then
      sleep 2
      ATTEMPTS=$((ATTEMPTS + 1))
    fi
  done

  if [ -z "${TAILSCALE_IP}" ]; then
    log_error "Tailscale did not assign an IP after 60 seconds."
    log_error "Check: tailscale status"
    log_error "Check: journalctl -u tailscaled -n 50"
    exit 1
  fi

  log_success "Tailscale IP: ${TAILSCALE_IP}"

  # Save to .env for use by other services
  write_env TAILSCALE_IP "${TAILSCALE_IP}"

  # Verify connectivity
  if tailscale status | grep -q "100\.[0-9]"; then
    log_success "Tailscale connected and operational"
  else
    log_warning "Tailscale IP assigned but status unclear — check: tailscale status"
  fi
}
────────────────────────────────────────────────────────────────
```

---

## Commit Messages for Windsurf

```
Phase 1:
  fix(rclone): remove all interactive OAuth from Script 2;
  Script 1 collects credentials only, Script 2 never calls rclone config;
  add service-account path (headless) and oauth-tunnel path (deferred to Script 3)

Phase 2:
  fix(rclone): add authorize_rclone_oauth to Script 3;
  support SSH tunnel (Option A) and paste-token-from-local (Option B)

Phase 3:
  fix(tailscale): add --accept-dns=false --accept-routes=false --reset flags;
  add tailscaled daemon check; add retry loop for IP assignment with 60s timeout
```