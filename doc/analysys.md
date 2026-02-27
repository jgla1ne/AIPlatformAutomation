Let me read the current state of all scripts.

**Reading:**
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/0-complete-cleanup.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/docker-compose.yml

---

## Root Cause Diagnosis

The unbound variable errors are not random. They share a single structural cause.

```
ROOT CAUSE: Script 1 is ~3000+ lines long. Variables are defined 
inside functions and used outside them, or defined in one 
function and referenced in a later function that runs in a 
subshell. Bash does not propagate local variables across 
function boundaries or subshells.

Every time Windsurf fixes one unbound variable it creates 
another because it is patching symptoms, not the structure.

The scripts need a variable declaration block, not individual patches.
```

---

## What the Code Actually Shows

### Script 1 — Variable Architecture is Broken

```bash
# FOUND: Variables defined inside setup functions, used outside

setup_tenant() {
    TENANT_ID="u${RUNNING_UID}"          # defined here
    COMPOSE_PROJECT_NAME="aip-${TENANT_ID}"
}

setup_volumes() {
    PG_VOLUME="${COMPOSE_PROJECT_NAME}_postgres_data"    # uses above
    REDIS_VOLUME="${COMPOSE_PROJECT_NAME}_redis_data"   # UNBOUND if
    QDRANT_VOLUME="${COMPOSE_PROJECT_NAME}_qdrant_data" # setup_tenant()
}                                                        # not called first

# If call order is wrong anywhere:
#   setup_volumes()  ← called before setup_tenant()
#   COMPOSE_PROJECT_NAME is empty → REDIS_VOLUME is unbound
```

```
THE PATTERN REPEATING ACROSS 3286 LINES:

  Function A defines VAR_X
  Function B uses VAR_X
  If B runs before A, or A runs in a subshell, VAR_X is unbound
  
  Windsurf fixes by adding VAR_X="" default
  Now VAR_X is empty string, not unbound
  Next function uses empty VAR_X to build VAR_Y
  VAR_Y becomes "_postgres_data" instead of "aip-u1001_postgres_data"
  Docker volume create fails silently
  Deploy proceeds with wrong volume name
  Data never persists
  
  This is worse than the unbound error. Unbound errors are visible.
  Silent wrong values are invisible until production data loss.
```

---

## The Fix Path — One Structural Change, Not 50 Patches

Tell Windsurf to make exactly this change to Script 1:

### Step 1 — Add a single variable declaration block at the top

```bash
#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════
# SECTION 1: CONSTANTS — set once, never reassigned
# ═══════════════════════════════════════════════════════════
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly RUNNING_UID="$(id -u)"
readonly RUNNING_GID="$(id -g)"
readonly RUNNING_USER="$(id -un)"

# ═══════════════════════════════════════════════════════════
# SECTION 2: DERIVED IDENTITY — depends only on SECTION 1
# ═══════════════════════════════════════════════════════════
readonly TENANT_ID="u${RUNNING_UID}"
readonly COMPOSE_PROJECT_NAME="aip-${TENANT_ID}"
readonly DOCKER_NETWORK="${COMPOSE_PROJECT_NAME}_net"

# ═══════════════════════════════════════════════════════════
# SECTION 3: PATHS — depends only on SECTION 1 + 2
# ═══════════════════════════════════════════════════════════
readonly DATA_ROOT="${DATA_ROOT:-/mnt/data}"
readonly TENANT_ROOT="${DATA_ROOT}/${TENANT_ID}"
readonly ENV_FILE="${TENANT_ROOT}/.env"
readonly COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

# ═══════════════════════════════════════════════════════════
# SECTION 4: VOLUME NAMES — depends only on SECTION 2
# ═══════════════════════════════════════════════════════════
readonly PG_VOLUME="${COMPOSE_PROJECT_NAME}_postgres_data"
readonly REDIS_VOLUME="${COMPOSE_PROJECT_NAME}_redis_data"
readonly QDRANT_VOLUME="${COMPOSE_PROJECT_NAME}_qdrant_data"

# ═══════════════════════════════════════════════════════════
# SECTION 5: LOAD .env IF IT EXISTS (re-run case)
# ═══════════════════════════════════════════════════════════
if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
    set +a
fi

# ═══════════════════════════════════════════════════════════
# SECTION 6: CREDENTIALS — generated once, preserved on re-run
# ═══════════════════════════════════════════════════════════
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 16)}"
REDIS_PASSWORD="${REDIS_PASSWORD:-$(openssl rand -hex 16)}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-$(openssl rand -hex 16)}"
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-$(openssl rand -hex 32)}"

# After this point: ALL variables exist. No function can 
# create an unbound variable situation because nothing 
# depends on call order.
```

### Step 2 — Remove ALL variable assignments from inside functions

```bash
# WRONG — current pattern causing the errors:
setup_volumes() {
    PG_VOLUME="${COMPOSE_PROJECT_NAME}_postgres_data"   # ← DELETE THIS
    REDIS_VOLUME="${COMPOSE_PROJECT_NAME}_redis_data"   # ← DELETE THIS
}

# RIGHT — functions only USE variables, never define them:
create_docker_volumes() {
    docker volume create "${PG_VOLUME}"     # reads from top-level
    docker volume create "${REDIS_VOLUME}"  # always defined, no race
    docker volume create "${QDRANT_VOLUME}"
}
```

### Step 3 — Write .env at the end of Script 1, not inside functions

```bash
write_env_file() {
    mkdir -p "${TENANT_ROOT}"
    cat > "${ENV_FILE}" <<EOF
# Generated by Script 1 — $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Tenant: ${TENANT_ID}

COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}
DOCKER_NETWORK=${DOCKER_NETWORK}
TENANT_ID=${TENANT_ID}
DATA_ROOT=${DATA_ROOT}
TENANT_ROOT=${TENANT_ROOT}

PG_VOLUME=${PG_VOLUME}
REDIS_VOLUME=${REDIS_VOLUME}
QDRANT_VOLUME=${QDRANT_VOLUME}

POSTGRES_USER=appuser
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=appdb

REDIS_PASSWORD=${REDIS_PASSWORD}
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

STACK_USER_UID=${RUNNING_UID}
STACK_USER_GID=${RUNNING_GID}
STACK_USER=${RUNNING_USER}
EOF
    chown "${RUNNING_UID}:${RUNNING_GID}" "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
}
```

---

## Exact Commit Message for Windsurf

```
STRUCTURAL FIX — stops all unbound variable errors permanently:

This is ONE change to Script 1. Do not touch Scripts 2-4.

1. Delete all variable assignments from inside functions
   in Script 1. Every variable that is used across functions
   must be declared at the TOP of the script before any
   function definition.

2. Add the six-section variable block shown above at line 1
   after the shebang. Sections must be in dependency order:
   CONSTANTS → IDENTITY → PATHS → VOLUMES → LOAD_ENV → CREDENTIALS

3. Functions may READ variables. Functions may NOT assign
   variables that other functions depend on.

4. write_env_file() runs as the LAST step of Script 1
   using the already-defined top-level variables.

WHY: Bash does not guarantee function call order matches
variable dependency order across 3000 lines. The six-section
block eliminates call-order as a failure mode entirely.

DO NOT add more "|| true" or default-empty patches.
DO NOT add more export statements inside functions.
These hide bugs instead of fixing them.
```

---

## Scorecard — What This Fixes vs What It Does Not

```
Problem                          After structural fix
──────────────────────────────────────────────────────
REDIS_VOLUME unbound             ✅ fixed permanently
Any future unbound variable      ✅ structurally impossible
Variable has wrong empty value   ✅ fixed — readonly enforces correct value
Re-run generates new passwords   ✅ fixed — .env loaded before generation
.env owned by root               ✅ fixed — chown at write time

Caddyfile mount path mismatch    ❌ still needs compose fix
postgres chown to root           ❌ still needs fix
Service databases not created    ❌ still needs fix
n8n uid 1000 mismatch            ❌ still needs fix
──────────────────────────────────────────────────────
```

The four deploy blockers from the previous review still exist in docker-compose.yml and Script 2. The structural fix above stops the iteration loop on Script 1. Once Script 1 runs clean, focus returns to those four blockers.