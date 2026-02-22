Let me fetch the current script 1 from GitHub first.

**Reading:**
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh

---

## What I See in Script 1

### Structure Overview
```
The script currently handles:
  1. EBS volume detection and mounting
  2. Directory structure creation
  3. Port assignment (dynamic, per tenant)
  4. Service configuration (LiteLLM, Qdrant, OpenClaw, Caddy)
  5. Tailscale auth key collection
  6. rclone / Google Drive credentials
  7. .env file generation

This is the RIGHT scope for Script 1.
```

### What Is Good
```
✅ Runs under current user (UID/GID aware)
✅ Dynamic port allocation per tenant
✅ EBS volume detection per tenant
✅ .env written to DATA_ROOT (tenant-isolated)
✅ rclone auth method selection added
✅ Tailscale auth key collected
```

### What Is Problematic

---

## Problem 1 — Stack Combinations Are Not Modeled

```
Script 1 currently asks about services as independent toggles.
But the real architecture has meaningful COMBINATIONS:

  Combination A — Local only (no cloud sync, no Tailscale)
    → LiteLLM + Qdrant + OpenClaw + Caddy
    → Caddy handles HTTPS on public IP or localhost
    → No rclone, no Tailscale

  Combination B — Tailscale only (private mesh access)
    → LiteLLM + Qdrant + OpenClaw + Caddy
    → OpenClaw accessible via Tailscale IP only
    → No rclone

  Combination C — rclone only (Drive sync, no mesh)
    → Full stack + rclone sidecar
    → Public or Caddy access

  Combination D — Full stack (most common production)
    → LiteLLM + Qdrant + OpenClaw + Caddy
    → Tailscale for private access to OpenClaw
    → rclone for Drive sync

  Combination E — LiteLLM only (API gateway, no UI)
    → LiteLLM + Qdrant only
    → No OpenClaw, no Caddy
    → Tailscale optional

Currently Script 1 has no concept of these combinations.
It asks individual questions with no awareness of dependencies.
Script 2 then tries to deploy everything regardless.
```

---

## Problem 2 — Tailscale Auth Key Has No Validation

```
Current code:
  read -rp "Tailscale Auth Key: " TAILSCALE_AUTH_KEY

Issues:
  - No format validation (tskey-auth-... prefix)
  - No check whether it's a reusable key vs one-time key
  - No distinction between:
      ephemeral keys  (device disappears after disconnect — wrong for server)
      one-time keys   (can only be used once — breaks re-deploy)
      reusable keys   (correct for this use case)
  - TAILSCALE_HOSTNAME never set here — collisions in multi-tenant
```

---

## Problem 3 — rclone OAuth Path Still Incomplete in Script 1

```
The oauth_tunnel method collects:
  RCLONE_OAUTH_CLIENT_ID
  RCLONE_OAUTH_CLIENT_SECRET

But does NOT set:
  RCLONE_TOKEN_OBTAINED=false   ← Script 2 needs this to know to skip container start
  RCLONE_GDRIVE_FOLDER          ← asked but may not be written correctly
  RCLONE_MOUNT_POINT            ← may not be set at all

The service_account method copies the JSON but the path written to rclone.conf
uses /data/config/rclone/service-account.json (container-side path).
This is correct ONLY IF the container mounts DATA_ROOT to /data.
Needs to be verified against docker-compose volume mapping.
```

---

## Problem 4 — No Tenant Hostname Generation

```
Multi-tenant architecture means multiple users run Script 1.
Each gets their own DATA_ROOT (e.g. /mnt/data-nvme0, /mnt/data-nvme1).

But there is no:
  STACK_NAME or TENANT_ID generated
  TAILSCALE_HOSTNAME per tenant (e.g. ai-platform-user-a, ai-platform-user-b)
  CADDY_HOSTNAME per tenant
  Container name prefix per tenant

Script 2 will create containers with the same names for every tenant.
docker compose will overwrite tenant A's containers when tenant B deploys.
```

---

## Problem 5 — Port Assignment Logic vs What Script 2 Actually Uses

```
Script 1 assigns ports dynamically:
  LITELLM_PORT=4000 (or next available)
  QDRANT_PORT=6333 (or next available)
  etc.

But Script 2 likely has hardcoded ports in docker-compose.yml.
The .env ports need to flow into docker-compose via variable substitution.
Needs verification that docker-compose.yml uses ${LITELLM_PORT} not 4000.
```

---

## Recommended Fix: Stack Profile Selection in Script 1

```
FILE: scripts/1-setup-system.sh
FIND: the section that asks about individual services
REPLACE WITH this stack profile selector FIRST, then ask sub-questions:

────────────────────────────────────────────────────────────────
print_section "Stack Configuration"
echo ""
echo "Select your deployment profile:"
echo ""
echo "  1. Full Stack (RECOMMENDED)"
echo "     LiteLLM + Qdrant + OpenClaw + Caddy"
echo "     + Tailscale (private mesh access)"
echo "     + rclone (Google Drive sync)"
echo ""
echo "  2. Core Stack (no external integrations)"
echo "     LiteLLM + Qdrant + OpenClaw + Caddy"
echo "     No Tailscale, no rclone"
echo ""
echo "  3. API Gateway Only"
echo "     LiteLLM + Qdrant only"
echo "     No OpenClaw UI, no Caddy"
echo "     Tailscale optional"
echo ""
echo "  4. Custom (choose each service individually)"
echo ""
read -rp "Profile [1-4, default 1]: " STACK_PROFILE
STACK_PROFILE=${STACK_PROFILE:-1}

case "${STACK_PROFILE}" in
  1)
    ENABLE_LITELLM=true
    ENABLE_QDRANT=true
    ENABLE_OPENCLAW=true
    ENABLE_CADDY=true
    ENABLE_TAILSCALE=true
    ENABLE_GDRIVE=true          # will ask sub-questions
    ;;
  2)
    ENABLE_LITELLM=true
    ENABLE_QDRANT=true
    ENABLE_OPENCLAW=true
    ENABLE_CADDY=true
    ENABLE_TAILSCALE=false
    ENABLE_GDRIVE=false
    ;;
  3)
    ENABLE_LITELLM=true
    ENABLE_QDRANT=true
    ENABLE_OPENCLAW=false
    ENABLE_CADDY=false
    ENABLE_TAILSCALE=false      # will ask
    ENABLE_GDRIVE=false
    ;;
  4)
    # ask each individually — existing logic
    ;;
esac

# Write profile flags to .env immediately
write_env STACK_PROFILE "${STACK_PROFILE}"
write_env ENABLE_LITELLM "${ENABLE_LITELLM}"
write_env ENABLE_QDRANT "${ENABLE_QDRANT}"
write_env ENABLE_OPENCLAW "${ENABLE_OPENCLAW}"
write_env ENABLE_CADDY "${ENABLE_CADDY}"
write_env ENABLE_TAILSCALE "${ENABLE_TAILSCALE}"
write_env ENABLE_GDRIVE "${ENABLE_GDRIVE}"
────────────────────────────────────────────────────────────────
```

---

## Recommended Fix: Tenant Identity Block

```
ADD this block EARLY in Script 1, right after EBS selection:

────────────────────────────────────────────────────────────────
print_section "Tenant Identity"

# Generate a stable tenant ID from the EBS mount point
# e.g. /mnt/data-nvme0 → nvme0 → tenant-nvme0
VOLUME_SUFFIX=$(basename "${DATA_ROOT}" | sed 's/[^a-zA-Z0-9]/-/g')
DEFAULT_TENANT_ID="tenant-${VOLUME_SUFFIX}"

read -rp "Tenant/Stack name [${DEFAULT_TENANT_ID}]: " TENANT_ID
TENANT_ID=${TENANT_ID:-${DEFAULT_TENANT_ID}}

# Sanitize: lowercase, alphanumeric + hyphen only
TENANT_ID=$(echo "${TENANT_ID}" | tr '[:upper:]' '[:lower:]' | \
            sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

write_env TENANT_ID "${TENANT_ID}"
write_env COMPOSE_PROJECT_NAME "${TENANT_ID}"   # ← makes all container names unique
write_env TAILSCALE_HOSTNAME "${TENANT_ID}"     # ← unique node in Tailscale network

log_success "Tenant ID: ${TENANT_ID}"
log_success "Compose project: ${TENANT_ID}"
log_success "Tailscale hostname: ${TENANT_ID}"
────────────────────────────────────────────────────────────────
```

---

## Recommended Fix: Tailscale Key Validation

```
FIND: Tailscale auth key prompt
REPLACE WITH:

────────────────────────────────────────────────────────────────
if [ "${ENABLE_TAILSCALE}" = "true" ]; then
  print_section "Tailscale Configuration"
  echo ""
  echo "You need a REUSABLE, NON-EPHEMERAL auth key from:"
  echo "  https://login.tailscale.com/admin/settings/keys"
  echo ""
  echo "  ✅ Use: Reusable key (so re-deploys work)"
  echo "  ❌ Avoid: Ephemeral key (device disappears on disconnect)"
  echo "  ❌ Avoid: One-time key (breaks on second deploy)"
  echo ""
  
  while true; do
    read -rsp "Tailscale Auth Key (tskey-auth-...): " TAILSCALE_AUTH_KEY
    echo ""
    
    if [[ "${TAILSCALE_AUTH_KEY}" =~ ^tskey-auth- ]]; then
      break
    else
      echo "❌ Key must start with 'tskey-auth-' — please try again"
    fi
  done
  
  write_env TAILSCALE_AUTH_KEY "${TAILSCALE_AUTH_KEY}"
  write_env TAILSCALE_HOSTNAME "${TENANT_ID}"
  log_success "Tailscale key saved"
fi
────────────────────────────────────────────────────────────────
```

---

## Summary Table for Windsurf

```
Change                            File      Priority
─────────────────────────────────────────────────────
Add TENANT_ID + COMPOSE_PROJECT   Script 1  🔴 Critical
  NAME block after EBS selection            (multi-tenant breaks without it)

Add Stack Profile selector        Script 1  🔴 Critical
  before individual service asks            (combinations not modeled)

Tailscale key format validation   Script 1  🟡 High
  + reusable key guidance

Fix RCLONE_TOKEN_OBTAINED=false   Script 1  🟡 High
  written for oauth_tunnel method

Verify RCLONE_MOUNT_POINT         Script 1  🟡 High
  written for all rclone paths

Verify docker-compose.yml uses    Script 2  🔴 Critical
  ${LITELLM_PORT} not hardcoded 4000

COMPOSE_PROJECT_NAME from .env    Script 2  🔴 Critical
  used in all docker compose calls
```

---

## Commit Message for Windsurf

```
feat(s1): add tenant identity block + COMPOSE_PROJECT_NAME;
add stack profile selector (full/core/api-gateway/custom);
add tailscale key format validation with reusable key guidance;
fix rclone oauth_tunnel missing RCLONE_TOKEN_OBTAINED=false;
ensure all enable flags written to .env before Script 2 reads them
```