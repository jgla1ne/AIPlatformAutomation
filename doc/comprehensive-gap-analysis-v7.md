# Script 2 — Complete Gap Analysis & Production-Ready Instructions for Windsurf
**Date:** February 17, 2026 | **Based on:** live audit_log.md + current 2-deploy-services.sh

---

## CRITICAL FINDING: TWO ENTIRELY DIFFERENT SCRIPTS ARE FIGHTING EACH OTHER

The audit log shows Script 2 running and restarting **6 times** from scratch before finally getting past cleanup. This is because the current `2-deploy-services.sh` on GitHub is **a completely different script** from the one that was actually running on the server and generating the log output.

The script on GitHub (`v75.2.2`) is a lightweight, streamlined wrapper that:
- Does NOT stop/start the Docker daemon
- Does NOT perform aggressive network cleanup  
- Does NOT call `generate_proxy_config()`, `generate_prometheus_config()`, or any permission-fix functions
- Simply reads `.env` and calls `docker compose up -d` in groups

The script producing the audit log is a **different, older, heavier version** with full network management, permission fixing, config generation, and health checking.

**The server has a different version than what's in Git. Windsurf must reconcile this first.**

---

## ROOT CAUSE ANALYSIS — ALL FAILURES

### Bug 1 — BLOCKER: `docker-compose.yml` has invalid `volumes` syntax
**Evidence (appears on EVERY attempt):**
```
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
```
**Every single `docker compose` command fails with this error** — pulls, ups, everything. Nothing can run until this is fixed.

**Root cause:** The `volumes:` section at the top level of `docker-compose.yml` is a list (sequence) instead of a mapping. Example of the **wrong** structure:
```yaml
# WRONG — list format:
volumes:
  - postgres_data
  - redis_data
```
**Correct structure:**
```yaml
# CORRECT — mapping format:
volumes:
  postgres_data:
  redis_data:
  grafana_data:
  ollama_data:
  prometheus_data:
  minio_data:
  n8n_data:
  flowise_data:
  anythingllm_data:
```
**Fix:** Open `docker-compose.yml` and change the top-level `volumes:` block from a list to a mapping (each volume name followed by a colon, nothing after it or `{}` or `driver: local`).

---

### Bug 2 — BLOCKER: `DATA_ROOT` variable not set — causes compose to warn on every command
**Evidence:**
```
level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
```
This appears 35+ times per command invocation, cluttering logs and indicating the compose file references `${DATA_ROOT}` which is never exported.

**Root cause:** The `docker-compose.yml` uses `${DATA_ROOT}` as a volume path prefix (e.g. `${DATA_ROOT}/volumes/postgres`) but `DATA_ROOT` is not set in `.env` or exported before running compose commands.

**Fix in Script 2:** Add this near the top of the script, after loading `.env`:
```bash
# Derive DATA_ROOT from BASE_DIR if not already set
if [ -z "${DATA_ROOT}" ]; then
    export DATA_ROOT="${BASE_DIR}"
fi
```
**Also fix in `docker-compose.yml`:** Either hardcode paths or ensure the `.env` file always contains:
```
DATA_ROOT=/mnt/data/ai-platform
```
(Match whatever `BASE_DIR` resolves to on this machine — the log shows `/mnt/data` is the real path, not `/home/$USER`.)

---

### Bug 3 — BLOCKER: `BASE_DIR` path mismatch — script uses wrong home directory
**Evidence:** Script hardcodes `BASE_DIR="/home/$REAL_USER/ai-platform"` but all log output shows paths as `/mnt/data/...`:
```
ENV_FILE=/mnt/data/.env
SERVICES_FILE=/mnt/data/metadata/selected_services.json
COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
```

**Root cause:** The running server script uses `/mnt/data` as the base, not `/home/$USER`. The GitHub script would silently look in the wrong place.

**Fix:** Either detect the path dynamically or read it from a known config location:
```bash
# Option A — Read from a canonical location that Script 1 sets
if [ -f "/mnt/data/.env" ]; then
    BASE_DIR="/mnt/data/ai-platform"
    ENV_FILE="/mnt/data/.env"
elif [ -f "/home/${REAL_USER}/ai-platform/deployment/stack/docker-compose.yml" ]; then
    BASE_DIR="/home/${REAL_USER}/ai-platform"
fi

# Option B — Read from /etc/ai-platform.conf if Script 1 writes it
# source /etc/ai-platform.conf  # contains BASE_DIR=...
```

---

### Bug 4 — Script restarts itself ~6 times before succeeding
**Evidence:** The audit log shows the full startup sequence (Script 2 starting... loading services... cleaning... generating proxy...) repeating 6 times. Each time it gets further.

**Root cause:** The network cleanup logic stops the Docker daemon, then tries to verify networks are gone — but since Docker is stopped, the `docker network ls` call fails in a way that makes the script think the networks still exist, so it retries. This creates a retry loop where each attempt kills the previous script process but the lock file or process detection is unreliable.

**Fix:** Rewrite `cleanup_previous_deployments()` to NOT stop/restart the Docker daemon. That is nuclear overkill and the source of the restart loop:
```bash
cleanup_previous_deployments() {
    log_info "Cleaning up previous deployments..."
    
    # Stop containers gracefully using compose (suppress validation errors)
    docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" down --remove-orphans 2>/dev/null || true
    
    # Remove any stray named containers from this project
    docker ps -a --filter "name=ai_platform" -q | xargs -r docker rm -f 2>/dev/null || true
    
    # Remove networks (without stopping Docker daemon)
    docker network rm ai_platform ai_platform_internal 2>/dev/null || true
    
    # Prune unused volumes only if explicitly requested
    # docker volume prune -f 2>/dev/null || true
    
    log_success "Pre-deployment cleanup completed"
}
```
**Remove entirely:** The `systemctl stop docker` / `systemctl start docker` block. This is what causes the 6-restart loop.

---

### Bug 5 — Script on GitHub is a toy facade, not the real deployment script
**Evidence:** The GitHub script (`v75.2.2`) has no health checking, no config generation, no permission fixing — it literally just calls `docker compose up -d` with cosmetic output. But the server is running a much more sophisticated version.

**The GitHub script will produce zero working containers** because:
1. It doesn't fix the `volumes must be a mapping` error in `docker-compose.yml`
2. It doesn't set `DATA_ROOT`
3. It doesn't generate `prometheus.yml` before starting prometheus
4. It doesn't fix Grafana/Ollama permissions
5. It has no actual health checking — it just prints fake "✓ HEALTHY" statuses

**Fix:** The real, working deployment logic (the version running on the server) must be pushed to Git. The `v75.2.2` version should be **discarded entirely** and replaced with the production version.

---

### Bug 6 — `dify` not defined in `docker-compose.yml`
**Evidence:**
```
[ERROR] Service dify not defined in /mnt/data/ai-platform/deployment/stack/docker-compose.yml
```
**Root cause:** The selected services list includes `dify` but the compose file doesn't have a `dify` service (it may have `dify-api`, `dify-worker`, `dify-web` as separate services).

**Fix:** Either add a `dify` service alias to compose, or update `deploy_service()` to map `dify` → `dify-api dify-worker dify-web` when deploying.

---

## WHAT WINDSURF MUST DO — ORDERED TASK LIST

### TASK 1: Fix `docker-compose.yml` — Invalid volumes syntax (MUST DO FIRST)
**File:** `deployment/stack/docker-compose.yml`

Find the top-level `volumes:` block and convert from list to mapping:
```yaml
# Remove this pattern:
volumes:
  - postgres_data
  - redis_data
  [etc]

# Replace with:
volumes:
  postgres_data:
  redis_data:
  grafana_data:
  ollama_data:
  prometheus_data:
  minio_data:
  n8n_data:
  flowise_data:
  anythingllm_data:
  caddy_data:
  loki_data:
```
**Verify fix works:**
```bash
docker compose -f docker-compose.yml config --quiet
# Must produce NO output and exit code 0
```

---

### TASK 2: Add `DATA_ROOT` to `.env` and Script 2
**File:** `.env` (wherever Script 1 writes it)

Add this line (matching the actual install path on the server):
```
DATA_ROOT=/mnt/data/ai-platform
```
**File:** `scripts/2-deploy-services.sh`

Add after `source "$ENV_FILE"`:
```bash
# Ensure DATA_ROOT is always set
export DATA_ROOT="${DATA_ROOT:-${BASE_DIR}}"
```

---

### TASK 3: Fix `BASE_DIR` auto-detection
**File:** `scripts/2-deploy-services.sh`

Replace the hardcoded path logic with detection:
```bash
REAL_USER="${SUDO_USER:-$USER}"

# Auto-detect base directory — check canonical locations in order
if [ -f "/mnt/data/.env" ]; then
    BASE_DIR="/mnt/data/ai-platform"
    ENV_FILE="/mnt/data/.env"
elif [ -f "/home/${REAL_USER}/ai-platform/deployment/.env" ]; then
    BASE_DIR="/home/${REAL_USER}/ai-platform"
    ENV_FILE="$BASE_DIR/deployment/.env"
elif [ -f "/home/${REAL_USER}/ai-platform/.env" ]; then
    BASE_DIR="/home/${REAL_USER}/ai-platform"
    ENV_FILE="$BASE_DIR/.env"
else
    echo "[ERROR] Cannot find .env — run Script 1 first"
    exit 1
fi

DEPLOY_ROOT="$BASE_DIR/deployment"
STACK_DIR="$DEPLOY_ROOT/stack"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
```

---

### TASK 4: Replace `cleanup_previous_deployments()` — Remove Docker daemon restart
**File:** `scripts/2-deploy-services.sh`

Replace the existing function (which stops Docker, causing the 6-restart loop) with:
```bash
cleanup_previous_deployments() {
    log_info "Cleaning up previous deployments..."
    
    # Stop running containers without stopping Docker itself
    if [ -f "${COMPOSE_FILE}" ]; then
        docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" \
            down --remove-orphans --timeout 30 2>/dev/null || true
    fi
    
    # Remove any stray containers with our project prefix
    docker ps -a --filter "label=com.docker.compose.project=stack" -q \
        | xargs -r docker rm -f 2>/dev/null || true
    
    # Remove networks directly (no daemon restart needed)
    for net in ai_platform ai_platform_internal; do
        if docker network inspect "$net" &>/dev/null 2>&1; then
            docker network rm "$net" 2>/dev/null || true
        fi
    done
    
    # Prune volumes only if --clean flag passed
    if [[ "${1}" == "--clean" ]]; then
        docker volume prune -f 2>/dev/null || true
    fi
    
    log_success "Pre-deployment cleanup completed"
}
```

---

### TASK 5: Add pre-flight config generation (consolidated)
**File:** `scripts/2-deploy-services.sh`

Add this function and call it before any `docker compose up` commands:
```bash
generate_all_configs() {
    log_info "Generating required service configurations..."
    
    # --- Prometheus ---
    local prom_dir="${BASE_DIR}/config/prometheus"
    mkdir -p "${prom_dir}"
    cat > "${prom_dir}/prometheus.yml" << 'PROMEOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
PROMEOF
    log_success "Prometheus config generated"
    
    # --- Grafana provisioning dir ---
    mkdir -p "${BASE_DIR}/config/grafana/provisioning/datasources"
    mkdir -p "${BASE_DIR}/config/grafana/provisioning/dashboards"
    
    # --- LiteLLM config ---
    local litellm_dir="${BASE_DIR}/config/litellm"
    mkdir -p "${litellm_dir}"
    if [ ! -f "${litellm_dir}/config.yaml" ]; then
        cat > "${litellm_dir}/config.yaml" << LITEOF
model_list:
  - model_name: ollama/llama3
    litellm_params:
      model: ollama/llama3
      api_base: http://ollama:11434
  - model_name: ollama/mistral
    litellm_params:
      model: ollama/mistral
      api_base: http://ollama:11434

general_settings:
  master_key: "${LITELLM_MASTER_KEY}"
  database_url: "postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/litellm"
LITEOF
        log_success "LiteLLM config generated"
    fi
}
```

---

### TASK 6: Add volume permission pre-fixing
**File:** `scripts/2-deploy-services.sh`

Add this function and call it after `generate_all_configs()`:
```bash
fix_all_volume_permissions() {
    log_info "Setting volume permissions..."
    local vol_base="${BASE_DIR}/volumes"
    
    # Create all volume directories first
    mkdir -p "${vol_base}"/{postgres,redis,grafana,ollama,prometheus,minio,n8n,flowise,anythingllm,loki,caddy}
    
    # PostgreSQL — runs as UID 999
    chown -R 999:999 "${vol_base}/postgres" 2>/dev/null || true
    
    # Redis — runs as UID 999  
    chown -R 999:999 "${vol_base}/redis" 2>/dev/null || true
    
    # Grafana — runs as UID 472
    chown -R 472:472 "${vol_base}/grafana" 2>/dev/null || true
    chmod 755 "${vol_base}/grafana"
    
    # Ollama — runs as current user (RUNNING_UID from .env)
    chown -R "${RUNNING_UID}:${RUNNING_GID}" "${vol_base}/ollama" 2>/dev/null || true
    
    # Prometheus — runs as UID 65534 (nobody)
    chown -R 65534:65534 "${vol_base}/prometheus" 2>/dev/null || true
    
    # MinIO — runs as UID 1000
    chown -R 1000:1000 "${vol_base}/minio" 2>/dev/null || true
    
    log_success "All volume permissions set"
}
```

---

### TASK 7: Fix health check functions — use container-internal checks
**File:** `scripts/2-deploy-services.sh`

Replace any `wait_for_port localhost PORT` calls with container-internal checks:

```bash
# Redis — check from inside container
wait_for_redis() {
    local max=60 attempt=0
    while [ $attempt -lt $max ]; do
        if docker exec redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
            return 0
        fi
        sleep 2; ((attempt++))
    done
    log_error "Redis did not respond to ping after ${max} attempts"
    return 1
}

# Postgres — check from inside container
wait_for_postgres() {
    local max=60 attempt=0
    while [ $attempt -lt $max ]; do
        if docker exec postgres pg_isready -U "${POSTGRES_USER}" 2>/dev/null | grep -q "accepting"; then
            return 0
        fi
        sleep 2; ((attempt++))
    done
    log_error "PostgreSQL not ready after ${max} attempts"
    return 1
}

# Ollama — check via HTTP (runs on host-accessible port)
wait_for_ollama() {
    local max=90 attempt=0
    while [ $attempt -lt $max ]; do
        if curl -sf "http://localhost:11434/api/tags" >/dev/null 2>&1; then
            return 0
        fi
        sleep 3; ((attempt++))
    done
    log_error "Ollama not ready after ${max} attempts"
    return 1
}

# Generic HTTP health check
wait_for_http() {
    local name=$1 url=$2 max=${3:-60} attempt=0
    while [ $attempt -lt $max ]; do
        if curl -sf "${url}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 3; ((attempt++))
    done
    log_warning "${name} did not respond at ${url} — continuing"
    return 1
}
```

---

### TASK 8: Fix `dify` service name mapping
**File:** `scripts/2-deploy-services.sh`

In whatever function deploys services by name, add a mapping for `dify`:
```bash
deploy_service() {
    local service_name=$1
    
    # Map logical names to actual compose service names
    case "$service_name" in
        dify)
            for svc in dify-api dify-worker dify-web; do
                _deploy_single_service "$svc"
            done
            return
            ;;
        openwebui|open-webui)
            _deploy_single_service "open-webui"
            return
            ;;
    esac
    
    _deploy_single_service "$service_name"
}
```

---

### TASK 9: Suppress `DATA_ROOT` warning noise in logs
**File:** `scripts/2-deploy-services.sh`

All `docker compose` calls should pipe stderr through a filter that strips the DATA_ROOT warning:
```bash
# Wrapper for docker compose that suppresses known harmless warnings
dc() {
    docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" "$@" \
        2> >(grep -v 'variable is not set' >&2)
}
# Then use: dc up -d postgres  instead of: docker compose -f ... up -d postgres
```
Or better, ensure `DATA_ROOT` is always exported before any docker compose call.

---

## COMPLETE CORRECTED SCRIPT 2 — PRODUCTION STRUCTURE

The script must have this structure (Windsurf: use this as the definitive blueprint):

```
1. PATH DETECTION        — find BASE_DIR, ENV_FILE (handle /mnt/data vs /home/$USER)
2. SOURCE CONFIG         — load .env, export DATA_ROOT
3. VALIDATION            — verify compose file exists, run `docker compose config`
                           ABORT if compose validates with errors
4. CLEANUP               — stop containers, remove networks (NO Docker daemon restart)
5. GENERATE CONFIGS      — prometheus.yml, litellm config.yaml, caddy Caddyfile
6. FIX PERMISSIONS       — chown all volume directories before any container starts
7. CREATE NETWORKS       — docker network create (idempotent, skip if exists)
8. DEPLOY PHASE 1        — postgres + redis (wait for healthy)
9. DEPLOY PHASE 2        — prometheus + grafana (wait for healthy)
10. DEPLOY PHASE 3       — ollama (wait for healthy — slowest)
11. DEPLOY PHASE 4       — litellm (depends on ollama + postgres)
12. DEPLOY PHASE 5       — minio
13. DEPLOY PHASE 6       — open-webui, anythingllm, dify-*, n8n, flowise
14. DEPLOY PHASE 7       — signal-api, tailscale, openclaw (soft-start, non-blocking)
15. DEPLOY PHASE 8       — caddy (LAST — after everything else is up)
16. FINAL HEALTH REPORT  — curl each service endpoint, print access URLs
```

---

## VALIDATION CHECKLIST — TEST EACH FIX

Before running the full deployment, verify each fix independently:

```bash
# 1. Compose file is valid (MUST be zero errors):
docker compose -f docker-compose.yml config --quiet
echo "Exit code: $?"   # Must be 0

# 2. DATA_ROOT warning gone (must show NO warning lines):
docker compose -f docker-compose.yml --env-file .env config 2>&1 | grep "DATA_ROOT"
# Expected: no output

# 3. Permissions check (run after fix_all_volume_permissions):
stat volumes/grafana | grep Uid    # Expected Uid: 472
stat volumes/ollama | grep Uid     # Expected Uid: 1001 (RUNNING_UID)
stat volumes/prometheus | grep Uid # Expected Uid: 65534

# 4. Configs exist before deploy:
ls -la config/prometheus/prometheus.yml    # Must exist
ls -la config/litellm/config.yaml         # Must exist

# 5. After full deploy — all services up:
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -v "Up" | grep -v NAMES
# Expected: no output (all containers Up)

# 6. Proxy working:
curl -sk https://localhost/webui | grep -c "html"   # Expected: > 0
curl -sf http://localhost:11434/api/tags             # Expected: JSON
```

---

## SUMMARY OF ALL BUGS

| # | Bug | Impact | File | Fix |
|---|-----|--------|------|-----|
| 1 | `volumes must be a mapping` in docker-compose.yml | **TOTAL BLOCKER** — nothing deploys | docker-compose.yml | Convert volumes list to mapping |
| 2 | `DATA_ROOT` not set | Noisy logs, possible wrong paths | .env + script | Add `DATA_ROOT` to .env, export in script |
| 3 | `BASE_DIR` wrong path (`/home/$USER` vs `/mnt/data`) | Script looks in wrong place | 2-deploy-services.sh | Auto-detect base path |
| 4 | Docker daemon restart in cleanup | Script restarts itself 6 times | 2-deploy-services.sh | Remove `systemctl stop/start docker` |
| 5 | GitHub script is v75.2.2 facade (no real logic) | Would deploy nothing | 2-deploy-services.sh | Replace with production version |
| 6 | `dify` not in compose file | Error on dify deploy | docker-compose.yml + script | Add dify services or map name |
| 7 | No prometheus.yml before container start | Prometheus crash loops | 2-deploy-services.sh | Add `generate_all_configs()` call |
| 8 | Grafana/Ollama volume permissions wrong | Containers crash on start | 2-deploy-services.sh | Add `fix_all_volume_permissions()` |
| 9 | Health checks use `localhost:PORT` not container-internal | False failures | 2-deploy-services.sh | Replace with `docker exec` checks |

**Fix Bug 1 first. Everything else is blocked until the compose file validates.**
