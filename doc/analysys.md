Let me read all the current scripts before giving any opinion.

**Reading:**
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/0-complete-cleanup.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/4-add-service.sh

---

## Verdict: Not Production Ready — Specific Issues Found

---

### Issue 1 — COMPOSE_PROJECT_NAME Is Unreadably Long and Will Break Docker

```
Windsurf's output:
  Project: stack-data-1001-1001-45106

This comes from Script 1 generating something like:
  COMPOSE_PROJECT_NAME="stack-${DATA_ROOT//\//-}-${UID}-${GID}-${RANDOM}"

PROBLEMS:
  1. Docker has a 63-character limit on project names
     "stack-data-1001-1001-45106" is borderline but the
     full path version could be "stack-mnt-nvme0-ai-platform-1001-1001-45106"
     which is 45 chars — container names then become:
     "stack-mnt-nvme0-ai-platform-1001-1001-45106-postgres-1"
     = 56 chars before any service suffix

  2. The random suffix (45106) means every Script 1 re-run
     generates a NEW project name. Script 2 can't find
     the volumes or containers from the previous run.
     This breaks idempotency completely.

  3. Human operators cannot read logs or debug. Which tenant
     is "stack-data-1001-1001-45106"?

CORRECT APPROACH:
  TENANT_ID="u${STACK_USER_UID}"          # u1001
  COMPOSE_PROJECT_NAME="aip-${TENANT_ID}" # aip-u1001 — 9 chars, clear, stable

  Rules:
  - Derived from UID only (stable across re-runs)
  - No RANDOM suffix
  - No filesystem path embedded
  - Short enough that container names stay under 63 chars
  - aip-u1001-postgres-1 = 21 chars ✓
```

---

### Issue 2 — Script 1 Re-Run Regenerates RANDOM Suffix, Orphaning Everything

```
Current flow:
  First run:  COMPOSE_PROJECT_NAME=stack-data-1001-1001-45106
              volumes created: stack-data-1001-1001-45106_postgres_data
              
  Re-run:     COMPOSE_PROJECT_NAME=stack-data-1001-1001-91823  ← different
              Script 2 creates NEW volumes
              Old volumes orphaned with all data inside them
              Old containers still running under old project name

This is a silent data loss / resource leak scenario.

FIX: Script 1 must check if .env already exists for this UID.
     If it does, PRESERVE the existing COMPOSE_PROJECT_NAME.
─────────────────────────────────────────────────────────────
if [ -f "${ENV_FILE}" ] && grep -q "^COMPOSE_PROJECT_NAME=" "${ENV_FILE}"; then
  EXISTING_PROJECT="$(grep ^COMPOSE_PROJECT_NAME= "${ENV_FILE}" | cut -d= -f2)"
  echo "ℹ️  Existing project found: ${EXISTING_PROJECT}"
  echo "   Preserving project name to maintain data continuity."
  COMPOSE_PROJECT_NAME="${EXISTING_PROJECT}"
else
  COMPOSE_PROJECT_NAME="aip-u${STACK_USER_UID}"
fi
─────────────────────────────────────────────────────────────
```

---

### Issue 3 — Script 2 Postgres Ownership Fix Is Still Using Bind Mount Pattern

```
CURRENT CODE in Script 2:
─────────────────────────────────────────────────────────────
mkdir -p "${DATA_ROOT}/postgres/data"
chown -R 999:999 "${DATA_ROOT}/postgres/data"
─────────────────────────────────────────────────────────────

This is the ORIGINAL broken pattern we identified.

If docker-compose.yml still has:
  volumes:
    - ${DATA_ROOT}/postgres/data:/var/lib/postgresql/data

Then we are back to the ownership cycle that prevents
postgres from ever starting.

VERIFY docker-compose.yml has:
─────────────────────────────────────────────────────────────
  postgres:
    volumes:
      - postgres_data:/var/lib/postgresql/data   # named volume ✓

volumes:
  postgres_data:
    name: ${COMPOSE_PROJECT_NAME}_postgres_data
    external: true
─────────────────────────────────────────────────────────────

If docker-compose.yml is still using bind mounts for postgres,
the permission issue WILL reoccur regardless of all other fixes.
```

---

### Issue 4 — verify_ports() Checks ss But Caddy Binds 80/443 for ALL Tenants

```
PROBLEM:
  Only ONE tenant can own ports 80 and 443.
  If Tenant A is running, Tenant B's verify_ports() will
  detect 80/443 as occupied and REFUSE to deploy.

  But both tenants are supposed to be running simultaneously.
  Both need HTTP/HTTPS access via their subdomain.

  Windsurf has not solved this — the port check will
  simply block the second tenant from ever deploying.

THE ACTUAL SOLUTION for multi-tenant HTTPS:
  Option A — Single shared Caddy (runs as root/system service)
             reads all tenant Caddyfiles from /etc/caddy/conf.d/
             Each tenant writes their own conf block.
             Only one process owns 80/443.

  Option B — Tenant-specific ports for direct access
             Tenant A: external 8443 → internal 443
             Tenant B: external 9443 → internal 443
             (requires client to know port — less clean)

  Option C — Traefik as host-level router
             Reads Docker labels per container
             Automatically routes by subdomain

  Windsurf has implemented NONE of these.
  Current design: each tenant tries to own 80/443.
  Result: only first tenant works; second tenant is blocked.

MINIMUM FIX for now (single tenant per machine):
  Add explicit check and clear error message:
─────────────────────────────────────────────────────────────
  if ss -tlnp | grep -q ':80 ' && \
     ! docker ps --format '{{.Names}}' | \
       grep -q "^${COMPOSE_PROJECT_NAME}"; then
    echo "❌ Port 80 is owned by a DIFFERENT tenant's Caddy."
    echo "   Multi-tenant HTTP routing requires a shared reverse proxy."
    echo "   Contact platform admin to add subdomain routing."
    exit 1
  fi
─────────────────────────────────────────────────────────────
```

---

### Issue 5 — Script 0 Cleanup Scope Is Ambiguous

```
CURRENT CODE in Script 0:
─────────────────────────────────────────────────────────────
docker stop $(docker ps -aq)
docker rm $(docker ps -aq)
─────────────────────────────────────────────────────────────

Still nukes ALL tenants. The tenant-scoped cleanup fix
was described in the last review but does not appear
to have been implemented.

REQUIRED:
─────────────────────────────────────────────────────────────
# Load this tenant's .env
ENV_POINTER="/etc/ai-platform/env-pointer"
if [ -f "${ENV_POINTER}" ]; then
  DATA_ROOT="$(cat "${ENV_POINTER}")"
fi
ENV_FILE="${DATA_ROOT}/.env"
set -a; source "${ENV_FILE}"; set +a

# Scoped teardown
docker compose \
  --project-name "${COMPOSE_PROJECT_NAME}" \
  --file "${DOCKER_COMPOSE_FILE}" \
  down --volumes --remove-orphans

docker network rm "${DOCKER_NETWORK}" 2>/dev/null || true
─────────────────────────────────────────────────────────────
```

---

### Issue 6 — Script 3 rclone OAuth Still Has Server-Side Hang Risk

```
Script 3 configure_rclone calls:
  rclone config  (interactive — hangs in non-TTY)
  or
  rclone authorize (opens browser — impossible on headless server)

CURRENT STATE: unclear if this was fixed.
If the OAuth flow tries to open a browser or start a local
HTTP listener on the server, the script will hang indefinitely
in any SSH or automated context.

REQUIRED pattern:
─────────────────────────────────────────────────────────────
  echo "════════════════════════════════════════════"
  echo " rclone OAuth — run this on your LOCAL machine:"
  echo "   rclone authorize \"drive\""
  echo " Then paste the token JSON here:"
  echo "════════════════════════════════════════════"
  read -r RCLONE_TOKEN
  # write token to rclone.conf
─────────────────────────────────────────────────────────────
```

---

### Issue 7 — docker-compose.yml Not in Repository or Not Reviewed

```
All the Script 2 fixes depend on docker-compose.yml having:
  - named volumes with external: true
  - network name from ${COMPOSE_PROJECT_NAME}_net
  - STACK_USER_UID passed to services that need it

The docker-compose.yml was not readable in this review.

If docker-compose.yml still has:
  - bind mounts for postgres/redis/qdrant
  - hardcoded network name "ai_platform"
  - hardcoded container names
  
Then ALL the script fixes are cosmetic — the deploy will
still fail at the postgres permission step.

ACTION: Windsurf must share docker-compose.yml for review.
```

---

## Scorecard

```
Area                              Status          Risk
──────────────────────────────────────────────────────────────────
COMPOSE loaded before .env        ✅ Fixed         —
Container names tenant-scoped     ✅ Fixed         —
COMPOSE_PROJECT_NAME stability    ❌ RANDOM suffix  Data loss on re-run
Project name length               ❌ Too long       Docker 63-char limit
Postgres named volume             ⚠️  Unverified    Will block deploy
Port 80/443 multi-tenant          ❌ Not solved     Tenant 2 can't deploy
Script 0 tenant-scoped cleanup    ❌ Not fixed      Nukes all tenants
rclone OAuth hang                 ⚠️  Unverified    Script hangs on server
docker-compose.yml reviewed       ❌ Not visible    Unknown blast radius
──────────────────────────────────────────────────────────────────
PRODUCTION READY?                 ❌ NO
```

---

## Commit Message for Windsurf

```
BLOCKERS before any production test:

fix(s1): COMPOSE_PROJECT_NAME = "aip-u${UID}" — no RANDOM, no path embedding
fix(s1): preserve existing COMPOSE_PROJECT_NAME on re-run to protect data
fix(s2): verify postgres uses named volume not bind mount
fix(s2): port 80/443 conflict gives clear message about shared proxy need
fix(s0): scope docker compose down to COMPOSE_PROJECT_NAME only
fix(s3): rclone oauth prints local-machine instructions, never hangs
chore:   share docker-compose.yml for review — it is the critical path
```