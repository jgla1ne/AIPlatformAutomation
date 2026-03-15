Good progress from Windsurf. Let me fetch the updated scripts to see what actually changed vs what was claimed.I've now read all three scripts as they actually exist in the repo. The Windsurf summary claims all issues fixed, but the committed code tells a different story. Here's the honest post-fix assessment.

---

## Windsurf's claimed fixes vs what's actually in the repo

**Script 2 — UNCHANGED.** The file committed is byte-for-byte identical to the pre-fix version. `BASE_DIR` is still `/home/$REAL_USER/ai-platform`. The `.env` search paths are still wrong. The `service_exists` grep still silently skips every service when the compose skeleton has only a `placeholder:`. The cosmetic health check outputs are still hardcoded. None of the 6 claimed script 2 fixes are present in the code.

**Script 1 — UNCHANGED.** All `ENABLE_*` flags still default to `false`. The `select_services` phase still opts everything out by default. The compose generation still outputs a placeholder-only file. No "Lite Stack" default was added.

**Script 3 — UNCHANGED.** `GREEN` is still undefined. The compose path `/opt/ai-platform/compose/docker-compose.yml` still doesn't exist. `setup_gdrive_rclone` still runs unconditionally even if GDrive vars are unset, and will error out at `set -euo pipefail`. `main()` is still defined but never called.

The Qdrant permission fix and the service enablement on the live machine (`ENABLE_LITELLM=true` etc.) may have been applied directly to the running deployment outside of git, which is why Ollama shows as running. But the scripts themselves are unchanged and would reproduce the original failures on any fresh deploy.

---

## What still needs to be fixed in the codebase

These are the concrete code changes needed, prioritised in dependency order.

### Fix 1 — Script 1: Align `BASE_DIR` to the live tenant path convention

Script 1 writes to `/opt/ai-platform/` but the live deployment is at `/mnt/data/datasquiz/`. The README describes a multi-tenant architecture. Script 1 needs to accept a `TENANT_ID` argument (like script 2 already does) and derive `BASE_DIR` accordingly:

```bash
TENANT_ID="${1:-}"
if [ -z "$TENANT_ID" ]; then
    read -p "Enter tenant ID (e.g. datasquiz): " TENANT_ID
fi
DATA_ROOT="/mnt/data/${TENANT_ID}"
BASE_DIR="${DATA_ROOT}"
```

### Fix 2 — Script 2: Align `BASE_DIR` to match script 1

Replace the first block of script 2:

```bash
# CURRENT (broken):
REAL_USER="${SUDO_USER:-$USER}"
BASE_DIR="/home/$REAL_USER/ai-platform"
DEPLOY_ROOT="$BASE_DIR/deployment"
STACK_DIR="$DEPLOY_ROOT/stack"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"

# CORRECT:
TENANT_ID="${1:?Usage: $0 <tenant_id>}"
BASE_DIR="/mnt/data/${TENANT_ID}"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
LOG_FILE="${BASE_DIR}/deployment.log"
```

And update the `POSSIBLE_ENV_PATHS` to:
```bash
POSSIBLE_ENV_PATHS=("${BASE_DIR}/.env")
```

### Fix 3 — Script 1: Generate a real compose file, not a placeholder

The `generate_docker_compose` phase needs to emit actual service blocks based on the `ENABLE_*` flags. This is the single most impactful missing piece — without it, script 2's `deploy_group` will always find `service_exists` returning false. The minimum viable addition inside `generate_docker_compose`:

```bash
# Always-on infra
cat >> "$COMPOSE_FILE" <<EOF
  postgres:
    image: postgres:15-alpine
    ...
  redis:
    image: redis:7-alpine
    ...
  caddy:
    image: caddy:2-alpine
    ...
EOF

# Conditional AI services
if [ "$ENABLE_QDRANT" = true ]; then
  cat >> "$COMPOSE_FILE" <<EOF
  qdrant:
    image: qdrant/qdrant:latest
    user: "${QDRANT_UID}:${QDRANT_UID}"
    volumes:
      - ${DATA_DIR}/qdrant:/qdrant/storage
      - ${DATA_DIR}/qdrant/snapshots:/qdrant/snapshots
    ...
EOF
fi
# ... same pattern for litellm, openwebui, ollama, etc.
```

The `user:` directive using `QDRANT_UID` also fixes the snapshots permissions bug at the source rather than via a pre-run workaround.

### Fix 4 — Script 1: Invert defaults for the core triad

```bash
# Current (wrong):
ENABLE_LITELLM=false
ENABLE_OLLAMA=false
ENABLE_OPENWEBUI=false

# Correct:
ENABLE_LITELLM=true
ENABLE_OLLAMA=true
ENABLE_OPENWEBUI=true
```

And in `select_services`, change the prompts for these three to `(Y/n)` (opt-out) rather than `(y/N)` (opt-in). Everything else can remain opt-in.

### Fix 5 — Script 1: Conditional Caddyfile generation

The `grafana` and `prometheus` Caddyfile blocks must only be emitted when those services are enabled. Wrap them:

```bash
if [ "$ENABLE_MONITORING" = true ]; then
  cat >> "$CADDYFILE" <<EOF
grafana.${BASE_DOMAIN} {
    ...
}
prometheus.${BASE_DOMAIN} {
    ...
}
EOF
fi
```

### Fix 6 — Script 3: Three correctness bugs

**Bug A** — `GREEN` undefined. Add to the top of script 3:
```bash
GREEN='\033[0;32m'
NC='\033[0m'
```

**Bug B** — `main()` is defined but never invoked. Add at the end of the file:
```bash
main "$@"
```

**Bug C** — `setup_gdrive_rclone` runs unconditionally. Wrap it:
```bash
setup_gdrive_rclone() {
    [[ -n "${GDRIVE_CLIENT_ID:-}" ]] || return 0
    ...
}
```

**Bug D** — `configure_litellm_routing` references `/opt/ai-platform/compose/docker-compose.yml` which doesn't exist. Should be `${BASE_DIR}/docker-compose.yml`.

---

## Current live status vs what the scripts would produce on a fresh deploy

The live machine (datasquiz) is partially working because fixes were applied directly — Ollama running, Tailscale connected. But these are not in the scripts. If someone ran scripts 1→2→3 fresh today against a new tenant, they would get: an infra-only stack with all AI services disabled, a compose file with only a placeholder service, script 2 unable to find its `.env`, and script 3 crashing on the undefined `GREEN` variable before doing anything.

The gap between "what Windsurf applied to the live machine" and "what's in the repo" needs to be closed. The live machine's working state should be reverse-engineered back into the scripts so the next deployment is reproducible — which is the README's first core objective: deterministic setup.