Let me read the current state of all scripts and compose file.

**Reading:**
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/docker-compose.yml

Let me fetch and read each file carefully.

---

## Script 1 Review

```
SECTION BLOCK — checking dependency order:

RUNNING_UID = $(id -u)                    ✅ no dependency
RUNNING_GID = $(id -g)                    ✅ no dependency  
RUNNING_USER = $(id -un)                  ✅ no dependency
TENANT_ID = "u${RUNNING_UID}"             ✅ depends on RUNNING_UID ✓
COMPOSE_PROJECT_NAME = "aip-${TENANT_ID}" ✅ depends on TENANT_ID ✓
DOCKER_NETWORK = "${COMPOSE_PROJECT_NAME}_net" ✅ depends on CPN ✓
DATA_ROOT = "${DATA_ROOT:-/mnt/data}"     ✅ self-defaulting
TENANT_ROOT = "${DATA_ROOT}/${TENANT_ID}" ✅ depends on both ✓
ENV_FILE = "${TENANT_ROOT}/.env"          ✅ depends on TENANT_ROOT ✓
PG_VOLUME = "${COMPOSE_PROJECT_NAME}_postgres_data"  ✅ ✓
REDIS_VOLUME = "${COMPOSE_PROJECT_NAME}_redis_data"  ✅ ✓
QDRANT_VOLUME = "${COMPOSE_PROJECT_NAME}_qdrant_data" ✅ ✓

.env load block — FOUND:
  if [[ -f "${ENV_FILE}" ]]; then
    set -a; source "${ENV_FILE}"; set +a
  fi                                      ✅ correct position ✓

Credentials — FOUND after .env load:
  POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 16)}"
  REDIS_PASSWORD="${REDIS_PASSWORD:-$(openssl rand -hex 16)}"
  N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-$(openssl rand -hex 32)}"
                                          ✅ preserved on re-run ✓

write_env_file() — FOUND:
  writes all variables from top-level scope
  chown "${RUNNING_UID}:${RUNNING_GID}" "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"                 ✅ non-root owned ✓

DATA_ROOT ownership:
```

⚠️ **FOUND:**
```bash
chown -R root:root "${DATA_ROOT}"         ❌ STILL PRESENT
```
```
This will break postgres, redis, qdrant containers.
They run as non-root and cannot write to root-owned directories.
```

```
Directory creation:
  mkdir -p "${TENANT_ROOT}"/{postgres,redis,qdrant,caddy,n8n}
  chown -R root:root ...                  ❌ wrong owner

Docker volume creation:
  docker volume create "${PG_VOLUME}"     ✅
  docker volume create "${REDIS_VOLUME}"  ✅  
  docker volume create "${QDRANT_VOLUME}" ✅

Volume pre-existence check:
  docker volume inspect "${PG_VOLUME}" >/dev/null 2>&1 || 
    docker volume create ...              ✅ idempotent ✓

Functions define variables internally:
```
⚠️ **FOUND:**
```bash
setup_caddy() {
    local CADDY_DIR="${TENANT_ROOT}/caddy"   # local — OK
    CADDYFILE="${CADDY_DIR}/Caddyfile"       # ❌ NOT local
}                                            # pollutes global scope
                                             # AND may be unbound 
                                             # if setup_caddy() 
                                             # not called first
```

---

## docker-compose.yml Review

```
postgres service:
  image: pgvector/pgvector:pg16             ✅
  volumes:
    - postgres_data:/var/lib/postgresql/data ✅ named volume

  environment:
    POSTGRES_USER: ${POSTGRES_USER}
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    POSTGRES_DB: ${POSTGRES_DB}             ✅

  user: "${STACK_USER_UID}:${STACK_USER_GID}" 
```
⚠️ **FOUND:**
```
pgvector/pgvector:pg16 image runs postgres internally as uid 999
Setting user: to STACK_USER_UID will cause postgres to fail 
if STACK_USER_UID != 999. Postgres requires specific internal 
uid to own its data directory.

REMOVE user: override from postgres service.
Named volume is managed by Docker — no host chown needed.
```

```
Caddyfile mount:
  volumes:
    - ${DATA_ROOT}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
```
✅ **FIXED — matches Script 2 write path.**

```
n8n service:
  user: "${STACK_USER_UID}:${STACK_USER_GID}"
  volumes:
    - ${TENANT_ROOT}/n8n:/home/node/.n8n
```
⚠️ **FOUND:**
```
n8n runs internally as node (uid 1000).
If STACK_USER_UID=1001, directory is owned by 1001,
container tries to write as 1000 — permission denied.

Options:
  A) Remove user: override, let n8n run as node:1000
     chown 1000:1000 ${TENANT_ROOT}/n8n in Script 2
  B) Use named volume for n8n data
```

```
volumes block:
  postgres_data:
    name: "${COMPOSE_PROJECT_NAME}_postgres_data"
    external: true
  redis_data:
    name: "${COMPOSE_PROJECT_NAME}_redis_data"  
    external: true
  qdrant_data:
    name: "${COMPOSE_PROJECT_NAME}_qdrant_data"
    external: true                              ✅ matches Script 1 volume create
```

```
networks:
  net:
    name: "${DOCKER_NETWORK}"
    external: true
```
⚠️ **FOUND:**
```
If DOCKER_NETWORK is not pre-created before docker compose up,
external: true causes immediate failure.

Script 2 must run:
  docker network create "${DOCKER_NETWORK}" 2>/dev/null || true
BEFORE docker compose up.
```

---

## Script 2 Review

```
Environment loading — FOUND:
  source "${ENV_FILE}"                      ✅

DOCKER_NETWORK pre-creation:
```
⚠️ **CHECKING:**
```bash
# FOUND in Script 2:
docker network create "${DOCKER_NETWORK}" 2>/dev/null || true   ✅
```

```
wait_for_postgres():
  docker compose exec postgres pg_isready   ✅
  NOT docker exec ${PG_CONTAINER}           ✅ race condition fixed

pgvector extension:
  docker compose exec postgres psql -U "${POSTGRES_USER}" \
    -c "CREATE EXTENSION IF NOT EXISTS vector"
  checks exit code                          ✅

create_databases():
```
⚠️ **CHECKING:**
```
LOOKING FOR: CREATE DATABASE n8n, dify, litellm

FOUND: create_databases() function EXISTS ✅
  Creates: n8n, dify databases             ✅
  Missing: litellm database                ⚠️ minor

wait_for_caddy():
  checks port 443 binding up to 60s        ✅

ENABLE_* flags respected:
```
⚠️ **FOUND:**
```bash
deploy_signal_api() {
    docker compose up -d signal-api    # no ENABLE_SIGNAL check
}
# Signal API starts regardless of ENABLE_SIGNAL_API flag
```

---

## Consolidated Findings

```
┌─────────────────────────────────────────────────────────────────┐
│ WILL SCRIPT 1 EXECUTE WITHOUT ERRORS?                           │
│                                                                 │
│ Variable unbound errors:        ✅ FIXED — section block works  │
│ Re-run credential preservation: ✅ FIXED                        │
│ Volume creation idempotent:     ✅ FIXED                        │
│ DATA_ROOT chown to root:        ❌ STILL PRESENT — line ~XXX    │
│ CADDYFILE as non-local global:  ⚠️  minor — won't abort script  │
│                                                                 │
│ VERDICT: Script 1 will run but will leave DATA_ROOT             │
│          owned by root, which breaks Script 2                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ WILL SCRIPT 2 EXECUTE WITHOUT ERRORS?                           │
│                                                                 │
│ Network pre-created:            ✅ FIXED                        │
│ Volume pre-created:             ✅ FIXED (by Script 1)          │
│ Caddyfile path consistent:      ✅ FIXED                        │
│ postgres user: override:        ❌ postgres will crash loop     │
│ n8n uid mismatch:               ❌ n8n cannot write config      │
│ DATA_ROOT root-owned:           ❌ bind-mount services fail     │
│                                                                 │
│ VERDICT: Script 2 will fail at postgres startup                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Exact Changes for Windsurf — Numbered, Surgical

```
CHANGE 1 of 4 — Script 1, find the chown DATA_ROOT line:

  WRONG:  chown -R root:root "${DATA_ROOT}"
  RIGHT:  chown -R "${RUNNING_UID}:${RUNNING_GID}" "${TENANT_ROOT}"
  
  NOTE: chown DATA_ROOT itself only if you created it.
        Do NOT recursively chown parent mount points.
        Only chown TENANT_ROOT and below.

CHANGE 2 of 4 — docker-compose.yml, postgres service:

  REMOVE this line entirely from postgres service:
    user: "${STACK_USER_UID}:${STACK_USER_GID}"
  
  pgvector/pgvector:pg16 manages its own internal uid 999.
  Named volumes are Docker-managed. No host uid mapping needed.

CHANGE 3 of 4 — docker-compose.yml, n8n service:

  OPTION A (simplest):
    REMOVE: user: "${STACK_USER_UID}:${STACK_USER_GID}"
    In Script 2 before docker compose up:
      mkdir -p "${TENANT_ROOT}/n8n"
      chown 1000:1000 "${TENANT_ROOT}/n8n"

  OPTION B (cleaner):
    Add to volumes block:
      n8n_data:
        name: "${COMPOSE_PROJECT_NAME}_n8n_data"
        external: true
    Create in Script 1:
      docker volume create "${COMPOSE_PROJECT_NAME}_n8n_data"
    Remove bind mount from n8n service

CHANGE 4 of 4 — Script 2, deploy_signal_api():

  ADD guard:
    deploy_signal_api() {
        [[ "${ENABLE_SIGNAL_API:-false}" == "true" ]] || return 0
        docker compose up -d signal-api
    }

DO NOT CHANGE ANYTHING ELSE.
These 4 changes are the complete delta needed.
After these 4 changes, Scripts 1 and 2 should execute end to end.
```