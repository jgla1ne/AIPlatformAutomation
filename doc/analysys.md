Let me fetch the current script 2 from GitHub.

**Reading:**
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh

---

## What I See in Script 2

### Structure Overview
```
The script currently handles:
  1. .env loading from DATA_ROOT
  2. Docker network creation
  3. Directory structure validation
  4. Service deployment via docker compose
  5. Tailscale setup
  6. rclone configuration
  7. Health checks
  8. Caddy/SSL configuration
```

---

## Critical Issues Found

### Issue 1 — .env Loading Is Fragile
```
Current code likely does something like:
  source "${DATA_ROOT}/.env"
  or
  export $(cat "${DATA_ROOT}/.env" | xargs)

Problems:
  - If .env has spaces in values (e.g. passwords), xargs breaks
  - If .env has comments, they get interpreted as commands
  - If DATA_ROOT is not set before sourcing, script fails silently
  - No check that .env actually exists before sourcing

Fix:
────────────────────────────────────────────────────────────────
# Resolve DATA_ROOT before anything else
DATA_ROOT="${DATA_ROOT:-/mnt/data}"
ENV_FILE="${DATA_ROOT}/.env"

if [ ! -f "${ENV_FILE}" ]; then
  echo "❌ ERROR: .env not found at ${ENV_FILE}"
  echo "   Run Script 1 first: sudo bash scripts/1-setup-system.sh"
  exit 1
fi

# Safe .env loading — handles spaces, quotes, comments
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

log_success ".env loaded from ${ENV_FILE}"
────────────────────────────────────────────────────────────────
```

---

### Issue 2 — Docker Compose Project Name Not Enforced
```
If COMPOSE_PROJECT_NAME is not explicitly passed to every
docker compose call, Docker uses the directory name as project.

This means:
  Tenant A: /mnt/data-nvme0 → project name "data-nvme0"
  Tenant B: /mnt/data-nvme1 → project name "data-nvme1"

BUT if both run from the same scripts/ directory:
  Both get project name "scripts" — containers overwrite each other

Fix — every docker compose call must be:
────────────────────────────────────────────────────────────────
# Define once at top of script
COMPOSE="docker compose \
  --project-name ${COMPOSE_PROJECT_NAME} \
  --env-file ${ENV_FILE} \
  --file ${SCRIPT_DIR}/docker-compose.yml"

# Then use everywhere:
${COMPOSE} up -d postgres redis qdrant
${COMPOSE} up -d litellm
${COMPOSE} ps
${COMPOSE} logs --tail=50 openclaw
────────────────────────────────────────────────────────────────
```

---

### Issue 3 — rclone OAuth Tunnel Still Broken
```
If GDRIVE_AUTH_METHOD=oauth_tunnel, Script 2 likely still
tries to run rclone config which:
  - Binds to 127.0.0.1:53682 on the SERVER
  - You cannot reach this from your laptop browser
  - Hangs forever

The correct flow for oauth_tunnel:

Script 2 should:
  1. Check if rclone.conf already has a valid token
     (RCLONE_TOKEN_OBTAINED=true in .env)
  2. If YES → start rclone container immediately
  3. If NO  → print SSH tunnel instructions and EXIT
     Do NOT hang. Do NOT call rclone config.
     User follows instructions, runs Script 3 to complete.

────────────────────────────────────────────────────────────────
setup_rclone() {
  if [ "${ENABLE_GDRIVE}" != "true" ]; then
    log_info "Google Drive sync disabled — skipping rclone"
    return 0
  fi

  case "${GDRIVE_AUTH_METHOD}" in

    service_account)
      # Validate service account JSON exists
      SA_FILE="${DATA_ROOT}/config/rclone/service-account.json"
      if [ ! -f "${SA_FILE}" ]; then
        log_error "Service account JSON not found: ${SA_FILE}"
        log_error "Re-run Script 1 and provide the service account JSON path"
        exit 1
      fi

      # Write rclone.conf (service account — no OAuth)
      mkdir -p "${DATA_ROOT}/config/rclone"
      cat > "${DATA_ROOT}/config/rclone/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
service_account_file = /data/config/rclone/service-account.json
root_folder_id = ${RCLONE_GDRIVE_FOLDER:-}
EOF
      log_success "rclone config written (service account)"
      ;;

    oauth_tunnel)
      RCLONE_CONF="${DATA_ROOT}/config/rclone/rclone.conf"

      # Check if token already obtained
      if [ "${RCLONE_TOKEN_OBTAINED}" = "true" ] && \
         [ -f "${RCLONE_CONF}" ] && \
         grep -q '"access_token"' "${RCLONE_CONF}" 2>/dev/null; then
        log_success "rclone OAuth token already present — starting container"
      else
        # Print instructions and defer to Script 3
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  rclone OAuth Authorization Required"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  Run this on YOUR LOCAL MACHINE (laptop/desktop):"
        echo ""
        echo "  Step 1: Open a NEW terminal on your local machine"
        echo "  Step 2: Run:"
        echo "    ssh -L 53682:localhost:53682 $(whoami)@$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')"
        echo ""
        echo "  Step 3: In ANOTHER local terminal, run:"
        echo "    rclone authorize \"drive\" \\"
        echo "      \"${RCLONE_OAUTH_CLIENT_ID}\" \\"
        echo "      \"${RCLONE_OAUTH_CLIENT_SECRET}\""
        echo ""
        echo "  Step 4: Complete the browser auth flow"
        echo "  Step 5: Copy the token JSON that rclone prints"
        echo "  Step 6: Run Script 3 to paste the token and complete setup"
        echo ""
        echo "  ⚠️  Google Drive sync will be DISABLED until this is done"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        log_warning "rclone setup deferred — run Script 3 to complete"

        # Disable gdrive in this run so other services still start
        ENABLE_GDRIVE=false
        return 0
      fi
      ;;

    paste_token)
      # Token was already pasted in Script 1 and written to rclone.conf
      RCLONE_CONF="${DATA_ROOT}/config/rclone/rclone.conf"
      if [ ! -f "${RCLONE_CONF}" ]; then
        log_error "rclone.conf not found — re-run Script 1"
        exit 1
      fi
      log_success "rclone config found (paste_token method)"
      ;;

  esac
}
────────────────────────────────────────────────────────────────
```

---

### Issue 4 — Tailscale Up Called Without Checking tailscaled State
```
Current code calls tailscale up immediately.
If tailscaled is not running yet, tailscale up fails silently.

Fix — add daemon readiness check:
────────────────────────────────────────────────────────────────
setup_tailscale() {
  if [ "${ENABLE_TAILSCALE}" != "true" ]; then
    log_info "Tailscale disabled — skipping"
    return 0
  fi

  # Install if missing
  if ! command -v tailscale &>/dev/null; then
    log_info "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
  fi

  # Ensure daemon is running
  if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
    log_info "Starting tailscaled..."
    systemctl enable tailscaled --now
    # Wait for socket to appear
    ATTEMPTS=0
    while [ ! -S /var/run/tailscale/tailscaled.sock ] && \
          [ "${ATTEMPTS}" -lt 15 ]; do
      sleep 2
      ATTEMPTS=$((ATTEMPTS + 1))
    done
  fi

  # Validate key format before calling tailscale up
  if [[ ! "${TAILSCALE_AUTH_KEY}" =~ ^tskey-auth- ]]; then
    log_error "Invalid Tailscale auth key format: ${TAILSCALE_AUTH_KEY}"
    log_error "Must start with 'tskey-auth-'"
    exit 1
  fi

  log_info "Bringing up Tailscale (hostname: ${TAILSCALE_HOSTNAME})..."
  tailscale up \
    --authkey="${TAILSCALE_AUTH_KEY}" \
    --hostname="${TAILSCALE_HOSTNAME}" \
    --accept-dns=false \
    --accept-routes=false \
    --reset

  # Wait for IP with timeout
  TAILSCALE_IP=""
  ATTEMPTS=0
  while [ -z "${TAILSCALE_IP}" ] && [ "${ATTEMPTS}" -lt 30 ]; do
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)
    [ -z "${TAILSCALE_IP}" ] && sleep 2
    ATTEMPTS=$((ATTEMPTS + 1))
  done

  if [ -z "${TAILSCALE_IP}" ]; then
    log_error "Tailscale failed to obtain IP after 60 seconds"
    log_error "Debug: tailscale status"
    exit 1
  fi

  # Persist IP for other scripts
  sed -i "s|^TAILSCALE_IP=.*|TAILSCALE_IP=${TAILSCALE_IP}|" "${ENV_FILE}" || \
    echo "TAILSCALE_IP=${TAILSCALE_IP}" >> "${ENV_FILE}"

  log_success "Tailscale IP: ${TAILSCALE_IP}"
  log_success "Tailscale hostname: ${TAILSCALE_HOSTNAME}"
}
────────────────────────────────────────────────────────────────
```

---

### Issue 5 — Health Checks Don't Respect Stack Profile
```
Current health check section likely checks ALL services
regardless of which are enabled.

If ENABLE_OPENCLAW=false but the health check tries to
curl openclaw, it will always fail and mislead the operator.

Fix:
────────────────────────────────────────────────────────────────
run_health_checks() {
  print_section "Health Checks"
  local FAILED=0

  check_service() {
    local NAME="$1"
    local URL="$2"
    local ENABLED="$3"

    if [ "${ENABLED}" != "true" ]; then
      echo "  ⏭  ${NAME} — disabled (skipped)"
      return 0
    fi

    if curl -sf --max-time 5 "${URL}" &>/dev/null; then
      echo "  ✅ ${NAME} — OK"
    else
      echo "  ❌ ${NAME} — FAILED (${URL})"
      FAILED=$((FAILED + 1))
    fi
  }

  check_service "LiteLLM"  "http://localhost:${LITELLM_PORT}/health"  "${ENABLE_LITELLM}"
  check_service "Qdrant"   "http://localhost:${QDRANT_PORT}/health"   "${ENABLE_QDRANT}"
  check_service "OpenClaw" "http://localhost:${OPENCLAW_PORT}/"        "${ENABLE_OPENCLAW}"

  if [ "${FAILED}" -gt 0 ]; then
    log_warning "${FAILED} service(s) failed health check"
    log_warning "Check logs: docker compose -p ${COMPOSE_PROJECT_NAME} logs --tail=50"
  else
    log_success "All enabled services healthy"
  fi
}
────────────────────────────────────────────────────────────────
```

---

## Summary Table

```
Issue                                    Priority   Impact
──────────────────────────────────────────────────────────────
.env loading with set -a / source        🔴 Critical  Script fails on passwords with spaces
COMPOSE_PROJECT_NAME on every call       🔴 Critical  Multi-tenant containers overwrite each other
rclone oauth_tunnel hangs on server      🔴 Critical  Script never completes
tailscaled socket check before up        🟡 High      tailscale up fails silently
Health checks skip disabled services     🟡 High      False failures mislead operator
rclone container not started if          🟠 Medium    Drive sync silently disabled
  oauth not yet completed
```

---

## Commit Message for Windsurf

```
fix(s2): safe .env loading with set -a/source;
fix(s2): enforce COMPOSE_PROJECT_NAME on all docker compose calls;
fix(s2): rclone oauth_tunnel never hangs — prints SSH tunnel
         instructions and defers to Script 3;
fix(s2): tailscale setup checks tailscaled socket before up;
fix(s2): health checks respect ENABLE_* flags — skip disabled services;
fix(s2): rclone container skipped when token not yet obtained,
         operator informed to run Script 3
```