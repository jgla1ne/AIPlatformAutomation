Let me read all scripts before commenting.

**Reading:**
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/0-complete-cleanup.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/4-add-service.sh

---

## Cross-Check Results

---

### What Was Actually Fixed ✅

```
COMPOSE_PROJECT_NAME format      aip-u${UID} — confirmed in Script 1
Preservation on re-run           grep check present — confirmed
Script 0 scoped cleanup          cleanup_tenant() present — confirmed
Port conflict detection          verify_ports() improved — confirmed
rclone OAuth                     local-machine instruction pattern — confirmed
```

Good. Those five items are genuinely fixed.

---

### What Is Still Broken ❌

---

#### BLOCKER 1 — Script 2 Still Creates Bind Mount Directories for Postgres

```
FOUND in Script 2:
────────────────────────────────────────────────────────────
mkdir -p "${DATA_ROOT}/postgres/data"
chown -R 999:999 "${DATA_ROOT}/postgres/data"
────────────────────────────────────────────────────────────

This only makes sense if docker-compose.yml has:
  volumes:
    - ${DATA_ROOT}/postgres/data:/var/lib/postgresql/data

If docker-compose.yml uses named volumes (as claimed),
this mkdir/chown is HARMLESS but SIGNALS that the
compose file may not have been updated.

If docker-compose.yml was NOT updated to named volumes,
this is the original ownership deadlock bug.

STATUS: Cannot confirm without seeing docker-compose.yml.
This is the single highest-risk unknown in the entire stack.
```

---

#### BLOCKER 2 — Script 2 Layer Sequencing Has a Race Condition

```
FOUND in Script 2 deploy sequence:

  deploy_database_layer()   ← starts postgres, redis, qdrant
  wait_for_postgres()       ← pg_isready loop
  deploy_application_layer()

PROBLEM — wait_for_postgres() uses:
────────────────────────────────────────────────────────────
docker exec ${PG_CONTAINER} pg_isready -U ${POSTGRES_USER}
────────────────────────────────────────────────────────────

PG_CONTAINER="${COMPOSE_PROJECT_NAME}-postgres-1"

Docker Compose does NOT guarantee container name suffix is "-1"
when using 'docker compose up' without '--scale'.
It usually is "-1" but this is an implementation detail,
not a guaranteed contract.

SAFER pattern:
────────────────────────────────────────────────────────────
docker compose \
  --project-name "${COMPOSE_PROJECT_NAME}" \
  exec postgres pg_isready -U "${POSTGRES_USER}"
────────────────────────────────────────────────────────────

This asks Compose to resolve the container — it always works
regardless of the actual container name suffix.
```

---

#### BLOCKER 3 — Pgvector Extension Creation Has No Fallback

```
FOUND in Script 2:
────────────────────────────────────────────────────────────
docker exec ${PG_CONTAINER} psql -U ${POSTGRES_USER} \
  -c "CREATE EXTENSION IF NOT EXISTS vector;"
────────────────────────────────────────────────────────────

PROBLEM: The base postgres image does NOT include pgvector.
Only ankane/pgvector or pgvector/pgvector images include it.

If docker-compose.yml uses image: postgres:15 (the default),
this command will succeed silently on some builds and fail
with "extension not found" on others.

The failure is silent because the script does not check
the exit code of this specific psql command.

REQUIRED:
────────────────────────────────────────────────────────────
# 1. Verify docker-compose.yml uses:
#    image: pgvector/pgvector:pg16
#    or:
#    image: ankane/pgvector

# 2. Add exit code check:
if ! docker compose \
  --project-name "${COMPOSE_PROJECT_NAME}" \
  exec postgres psql -U "${POSTGRES_USER}" \
  -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>&1; then
  echo "⚠️  pgvector extension failed — is pgvector image in use?"
  echo "   Check docker-compose.yml postgres image tag"
fi
────────────────────────────────────────────────────────────
```

---

#### BLOCKER 4 — Caddy Deploy Has No Health Wait Before App Layer Starts

```
FOUND in Script 2:
────────────────────────────────────────────────────────────
deploy_caddy()
deploy_application_layer()
────────────────────────────────────────────────────────────

Caddy needs to:
  1. Start the container
  2. Read the Caddyfile
  3. Request ACME TLS certificates from Let's Encrypt
  4. Begin listening on 80/443

Steps 3-4 take 10-60 seconds depending on DNS propagation.

If application containers start before Caddy is ready,
the first health checks from operators will fail
and will be misread as application failures.

More critically — if ACME challenge fails (DNS not
propagated, rate limit hit), Caddy enters a retry loop
and never becomes healthy. The script reports success
while nothing is actually accessible.

REQUIRED minimum:
────────────────────────────────────────────────────────────
wait_for_caddy() {
  local max_attempts=30
  local attempt=0
  echo "⏳ Waiting for Caddy to bind port 443..."
  while ! ss -tlnp | grep -q ':443 '; do
    attempt=$((attempt + 1))
    if [ ${attempt} -ge ${max_attempts} ]; then
      echo "❌ Caddy did not bind port 443 after ${max_attempts}s"
      echo "   Check: docker logs ${COMPOSE_PROJECT_NAME}-caddy-1"
      echo "   Common causes: DNS not propagated, ACME rate limit"
      exit 1
    fi
    sleep 2
  done
  echo "✅ Caddy is listening on 443"
}
────────────────────────────────────────────────────────────
```

---

#### BLOCKER 5 — Script 1 Writes DOCKER_NETWORK but Script 2 Does Not Use It Consistently

```
Script 1 writes:
  DOCKER_NETWORK="aip-u${UID}_net"

Script 2 in several places still constructs the network name inline:
────────────────────────────────────────────────────────────
docker network create "${COMPOSE_PROJECT_NAME}_net"
────────────────────────────────────────────────────────────

These should be identical but are two separate code paths.
If someone changes the network naming convention in Script 1
without updating Script 2, they diverge silently.

FIX — single source of truth:
────────────────────────────────────────────────────────────
# Script 2 — after sourcing .env:
if [ -z "${DOCKER_NETWORK}" ]; then
  echo "❌ DOCKER_NETWORK not set in .env"
  exit 1
fi

# Then everywhere:
docker network create "${DOCKER_NETWORK}" 2>/dev/null || true
# NOT: docker network create "${COMPOSE_PROJECT_NAME}_net"
────────────────────────────────────────────────────────────
```

---

#### ISSUE 6 — Script 3 Rclone Config Path Is Hardcoded

```
FOUND in Script 3:
────────────────────────────────────────────────────────────
RCLONE_CONFIG="/home/${USER}/.config/rclone/rclone.conf"
────────────────────────────────────────────────────────────

In a multi-tenant setup, each tenant may be a system
user without a home directory, or the script may run
as root on behalf of a UID.

$USER when running with sudo is "root", not the tenant user.
The rclone.conf ends up in /root/.config/rclone/rclone.conf
and is inaccessible to the tenant's containers.

FIX:
────────────────────────────────────────────────────────────
# Read from .env which has DATA_ROOT
RCLONE_CONFIG="${DATA_ROOT}/rclone/rclone.conf"
mkdir -p "${DATA_ROOT}/rclone"
chmod 700 "${DATA_ROOT}/rclone"
────────────────────────────────────────────────────────────
```

---

#### ISSUE 7 — Script 4 (Add Service) Does Not Validate ENABLE_ Flag Pattern

```
Script 4 adds a new service at runtime.
It appears to directly modify docker-compose.yml or run
a standalone docker run command without:

  1. Checking if the service's ENABLE_* flag is in .env
  2. Adding the Caddy route for the new service
  3. Reloading Caddy after adding the route
  4. Verifying the new service joins DOCKER_NETWORK

If Caddy is not reloaded after Script 4 runs,
the new service is running but unreachable via HTTPS.

REQUIRED in Script 4:
────────────────────────────────────────────────────────────
# After deploying new service:
add_caddy_route "${SERVICE_SUBDOMAIN}" "${SERVICE_PORT}"
reload_caddy()
verify_service_on_network "${SERVICE_NAME}" "${DOCKER_NETWORK}"
────────────────────────────────────────────────────────────
```

---

## Revised Scorecard

```
Item                                     Previous    Now
─────────────────────────────────────────────────────────────────
COMPOSE_PROJECT_NAME stable/short        ❌          ✅
Tenant-scoped cleanup                    ❌          ✅
Port conflict detection                  ❌          ✅
rclone OAuth non-hanging                 ❌          ✅
Re-run preservation                      ❌          ✅

Postgres named volume confirmed          ❌          ❌ unverified
docker-compose.yml reviewed              ❌          ❌ still not visible
Container name race condition            ❌          ❌ new finding
pgvector image verification              ❌          ❌ new finding
Caddy health wait before app layer       ❌          ❌ new finding
DOCKER_NETWORK single source of truth    ❌          ❌ new finding
rclone.conf path tenant-safe             ❌          ❌ new finding
Script 4 Caddy reload after add          ❌          ❌ new finding
─────────────────────────────────────────────────────────────────
PRODUCTION READY?                        ❌ NO        ❌ NOT YET
```

---

## Commit Message for Windsurf

```
REMAINING BLOCKERS — fix before any production test:

fix(compose):  share docker-compose.yml — confirm postgres uses
               named volume + pgvector image tag
fix(s2):       replace all "docker exec ${PG_CONTAINER}" with
               "docker compose exec postgres" — removes name race
fix(s2):       add pgvector extension exit code check with
               clear image tag guidance on failure
fix(s2):       add wait_for_caddy() after deploy_caddy() that
               checks port 443 is bound before proceeding
fix(s2):       use ${DOCKER_NETWORK} from .env everywhere —
               never recompute inline
fix(s3):       RCLONE_CONFIG="${DATA_ROOT}/rclone/rclone.conf"
               not /home/${USER}/.config
fix(s4):       after adding service: add_caddy_route(),
               reload_caddy(), verify_service_on_network()

GATE: Do not mark production ready until docker-compose.yml
      postgres volume type is confirmed as named, not bind mount.
      This is the original failure mode. Everything else is
      secondary to this one verification.
```