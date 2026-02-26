Let me fetch all current scripts.

**Reading:**
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/0-complete-cleanup.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/4-add-service.sh

---

## Full Audit — Multi-Tenant Identity & Deploy Confidence

---

### First: What Script 1 Currently Generates

```
After reading Script 1, the tenant identity block produces:

  TENANT_ID         = u${UID}                     e.g. u1001
  COMPOSE_PROJECT_NAME = ai-platform-u${UID}      e.g. ai-platform-u1001
  STACK_USER_UID    = ${UID}                       e.g. 1001
  STACK_USER_GID    = ${GID}                       e.g. 1001

This is CORRECT in principle.
The problem is what happens DOWNSTREAM in Script 2.
```

---

## Critical Problems in Script 2

### Problem 1 — COMPOSE Variable Built BEFORE .env Is Loaded

```
CURRENT CODE (Script 2, near top):
────────────────────────────────────────────────────────────────
COMPOSE="docker compose --project-name ${COMPOSE_PROJECT_NAME} ..."
# Then later:
source "${ENV_FILE}"
────────────────────────────────────────────────────────────────

WHAT HAPPENS:
  COMPOSE_PROJECT_NAME is empty at the time COMPOSE is built.
  Every docker compose call uses --project-name ""
  Docker defaults to directory name: "scripts"
  
  Tenant A: project = "scripts"
  Tenant B: project = "scripts"
  
  They OVERWRITE each other. Multi-tenancy is silently broken.

FIX — COMPOSE must be built AFTER source:
────────────────────────────────────────────────────────────────
# 1. Load env first
set -a; source "${ENV_FILE}"; set +a

# 2. Validate COMPOSE_PROJECT_NAME is not empty
if [ -z "${COMPOSE_PROJECT_NAME}" ]; then
  echo "❌ COMPOSE_PROJECT_NAME is empty after loading .env"
  echo "   Check that Script 1 wrote it to ${ENV_FILE}"
  exit 1
fi

# 3. NOW build COMPOSE
COMPOSE="docker compose \
  --project-name ${COMPOSE_PROJECT_NAME} \
  --env-file ${ENV_FILE} \
  --file ${SCRIPT_DIR}/docker-compose.yml"

echo "✅ Project: ${COMPOSE_PROJECT_NAME}"
────────────────────────────────────────────────────────────────
```

---

### Problem 2 — Container Name Hardcoded, Not Tenant-Scoped

```
CURRENT CODE scattered through Script 2:
────────────────────────────────────────────────────────────────
docker exec postgres pg_isready ...
docker exec redis redis-cli ping ...
docker logs postgres --tail=30
────────────────────────────────────────────────────────────────

WHAT HAPPENS:
  When docker compose uses --project-name ai-platform-u1001,
  the actual container name becomes:
    ai-platform-u1001-postgres-1
  
  But the script exec's into "postgres" — which either:
    a) Finds the WRONG tenant's container
    b) Fails with "No such container"

FIX — derive container name from COMPOSE_PROJECT_NAME:
────────────────────────────────────────────────────────────────
# Define after COMPOSE_PROJECT_NAME is loaded
PG_CONTAINER="${COMPOSE_PROJECT_NAME}-postgres-1"
REDIS_CONTAINER="${COMPOSE_PROJECT_NAME}-redis-1"
QDRANT_CONTAINER="${COMPOSE_PROJECT_NAME}-qdrant-1"
CADDY_CONTAINER="${COMPOSE_PROJECT_NAME}-caddy-1"

# Then use everywhere:
docker exec "${PG_CONTAINER}" pg_isready -U "${POSTGRES_USER}"
docker exec "${REDIS_CONTAINER}" redis-cli ping
docker logs "${CADDY_CONTAINER}" --tail=30
────────────────────────────────────────────────────────────────
```

---

### Problem 3 — Named Volume Names Not Tenant-Scoped

```
CURRENT CODE:
────────────────────────────────────────────────────────────────
docker volume create postgres_data
docker volume create qdrant_data
────────────────────────────────────────────────────────────────

WHAT HAPPENS:
  Tenant A creates volume: postgres_data
  Tenant B creates volume: postgres_data  ← same volume
  Tenant B's postgres reads Tenant A's data.
  
  This is a DATA LEAK between tenants.

FIX — prefix every volume with COMPOSE_PROJECT_NAME:
────────────────────────────────────────────────────────────────
PG_VOLUME="${COMPOSE_PROJECT_NAME}_postgres_data"
QDRANT_VOLUME="${COMPOSE_PROJECT_NAME}_qdrant_data"
REDIS_VOLUME="${COMPOSE_PROJECT_NAME}_redis_data"

docker volume create "${PG_VOLUME}"   2>/dev/null || true
docker volume create "${QDRANT_VOLUME}" 2>/dev/null || true
docker volume create "${REDIS_VOLUME}"  2>/dev/null || true
────────────────────────────────────────────────────────────────

AND in docker-compose.yml the volumes block must use:
────────────────────────────────────────────────────────────────
volumes:
  postgres_data:
    name: ${COMPOSE_PROJECT_NAME}_postgres_data
    external: true
  qdrant_data:
    name: ${COMPOSE_PROJECT_NAME}_qdrant_data
    external: true
  redis_data:
    name: ${COMPOSE_PROJECT_NAME}_redis_data
    external: true
────────────────────────────────────────────────────────────────
```

---

### Problem 4 — Docker Network Not Tenant-Scoped

```
CURRENT CODE:
────────────────────────────────────────────────────────────────
docker network create ai_platform
────────────────────────────────────────────────────────────────

WHAT HAPPENS:
  Tenant A creates network: ai_platform
  Tenant B tries to create: ai_platform — already exists, skips.
  Tenant B's containers JOIN Tenant A's network.
  They can see each other's services on that network.

FIX:
────────────────────────────────────────────────────────────────
DOCKER_NETWORK="${COMPOSE_PROJECT_NAME}_net"

docker network create \
  --driver bridge \
  --label "tenant=${COMPOSE_PROJECT_NAME}" \
  "${DOCKER_NETWORK}" 2>/dev/null \
  || echo "  ℹ Network ${DOCKER_NETWORK} already exists"
────────────────────────────────────────────────────────────────

AND in docker-compose.yml:
────────────────────────────────────────────────────────────────
networks:
  ai_platform:
    name: ${COMPOSE_PROJECT_NAME}_net
    external: true
────────────────────────────────────────────────────────────────
```

---

### Problem 5 — Port Collision Between Tenants Not Verified at Deploy Time

```
CURRENT CODE: Script 2 trusts whatever ports Script 1 wrote.

WHAT HAPPENS:
  If Script 1 was run twice with same UID (re-run scenario),
  or if .env was manually edited, Script 2 blindly tries to
  bind already-occupied ports.
  
  Caddy fails to bind 80/443 (only one tenant can own these).
  litellm fails to bind if port already taken.
  Script gives no clear error about which port conflicts.

FIX — add port pre-flight check in Script 2:
────────────────────────────────────────────────────────────────
verify_ports() {
  print_section "Port Pre-flight Check"
  local FAILED=0

  check_port() {
    local NAME="$1"
    local PORT="$2"
    local ENABLED="$3"
    [ "${ENABLED}" != "true" ] && return 0

    if ss -tlnp "sport = :${PORT}" 2>/dev/null | grep -q ":${PORT}"; then
      # Check if it's OUR project already holding it
      if docker ps --format '{{.Names}}' | \
         grep -q "^${COMPOSE_PROJECT_NAME}"; then
        echo "  ♻  ${NAME}:${PORT} — held by this project (OK)"
      else
        echo "  ❌ ${NAME}:${PORT} — IN USE by another process"
        FAILED=$((FAILED + 1))
      fi
    else
      echo "  ✅ ${NAME}:${PORT} — available"
    fi
  }

  check_port "HTTP"       "80"                      "true"
  check_port "HTTPS"      "443"                     "true"
  check_port "LiteLLM"    "${LITELLM_PORT}"         "${ENABLE_LITELLM}"
  check_port "OpenWebUI"  "${OPENWEBUI_PORT}"       "${ENABLE_OPENWEBUI}"
  check_port "n8n"        "${N8N_PORT}"             "${ENABLE_N8N}"
  check_port "Qdrant"     "${QDRANT_PORT}"          "${ENABLE_QDRANT}"
  check_port "Prometheus" "${PROMETHEUS_PORT}"      "${ENABLE_PROMETHEUS}"

  if [ "${FAILED}" -gt 0 ]; then
    echo ""
    echo "❌ ${FAILED} port conflict(s) detected."
    echo "   Run Script 1 again to reassign ports, or run Script 0 to clean up."
    exit 1
  fi

  log_success "All ports available"
}
────────────────────────────────────────────────────────────────
```

---

### Problem 6 — Script 0 Cleanup Not Tenant-Aware

```
CURRENT CODE in Script 0:
────────────────────────────────────────────────────────────────
docker stop $(docker ps -aq) 2>/dev/null
docker rm $(docker ps -aq) 2>/dev/null
docker volume prune -f
docker network prune -f
────────────────────────────────────────────────────────────────

WHAT HAPPENS:
  This nukes ALL tenants on the machine.
  If Tenant A runs cleanup, Tenant B's containers are destroyed.

FIX — Script 0 must load .env first and scope to project:
────────────────────────────────────────────────────────────────
# Script 0 must accept DATA_ROOT as argument or read env-pointer
if [ -f /etc/ai-platform/env-pointer ]; then
  DATA_ROOT="$(cat /etc/ai-platform/env-pointer)"
fi

ENV_FILE="${DATA_ROOT}/.env"
set -a; source "${ENV_FILE}"; set +a

echo "🧹 Cleaning up project: ${COMPOSE_PROJECT_NAME}"
echo "   This will NOT affect other tenants."
read -rp "Confirm? (yes/no): " CONFIRM
[ "${CONFIRM}" != "yes" ] && exit 0

# Scoped cleanup
docker compose \
  --project-name "${COMPOSE_PROJECT_NAME}" \
  --file "${SCRIPT_DIR}/docker-compose.yml" \
  down --volumes --remove-orphans 2>/dev/null || true

docker volume rm \
  "${COMPOSE_PROJECT_NAME}_postgres_data" \
  "${COMPOSE_PROJECT_NAME}_qdrant_data" \
  "${COMPOSE_PROJECT_NAME}_redis_data" \
  2>/dev/null || true

docker network rm "${COMPOSE_PROJECT_NAME}_net" 2>/dev/null || true

# Remove env pointer for this tenant only
rm -f /etc/ai-platform/env-pointer

log_success "Cleanup complete for ${COMPOSE_PROJECT_NAME}"
────────────────────────────────────────────────────────────────
```

---

## The Correct Sequence End-to-End

```
Script 1 generates and writes to DATA_ROOT/.env:
─────────────────────────────────────────────────
  TENANT_ID=u1001
  COMPOSE_PROJECT_NAME=ai-platform-u1001
  STACK_USER_UID=1001
  STACK_USER_GID=1001
  DOCKER_NETWORK=ai-platform-u1001_net
  DATA_ROOT=/mnt/nvme0/ai-platform
  
  PG_VOLUME=ai-platform-u1001_postgres_data
  QDRANT_VOLUME=ai-platform-u1001_qdrant_data
  REDIS_VOLUME=ai-platform-u1001_redis_data
  
  LITELLM_PORT=4000
  OPENWEBUI_PORT=5006
  N8N_PORT=5678
  QDRANT_PORT=6333
  ...

Script 2 reads DATA_ROOT/.env then:
─────────────────────────────────────────────────
  1. Builds COMPOSE with --project-name ai-platform-u1001
  2. Creates volumes ai-platform-u1001_postgres_data etc.
  3. Creates network ai-platform-u1001_net
  4. Deploys in strict layer order
  5. Runs port pre-flight BEFORE any docker compose up
  6. All docker exec uses PG_CONTAINER=ai-platform-u1001-postgres-1

Result — Tenant B (u1002) has entirely separate:
─────────────────────────────────────────────────
  Project:  ai-platform-u1002
  Network:  ai-platform-u1002_net
  Volumes:  ai-platform-u1002_postgres_data
  Containers: ai-platform-u1002-postgres-1
  Ports:    offset set, no collision
```

---

## Consolidated Commit Message for Windsurf

```
CRITICAL MULTI-TENANT FIXES:

fix(s2): build COMPOSE variable AFTER source .env — not before
fix(s2): validate COMPOSE_PROJECT_NAME non-empty before any docker call
fix(s2): all docker exec uses ${COMPOSE_PROJECT_NAME}-<service>-1
fix(s2): all named volumes prefixed ${COMPOSE_PROJECT_NAME}_<vol>
fix(s2): docker network named ${COMPOSE_PROJECT_NAME}_net
fix(s2): add verify_ports() pre-flight before layer 1 deploy
fix(s0): scope cleanup to COMPOSE_PROJECT_NAME only — not all containers
fix(s1): write DOCKER_NETWORK, PG_VOLUME, QDRANT_VOLUME, REDIS_VOLUME
         to .env so Script 2 reads not recomputes them
fix(compose): volumes block uses name: ${COMPOSE_PROJECT_NAME}_<vol>
              external: true for all stateful volumes
```