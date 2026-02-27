Let me fetch the current Script 2 before giving recommendations.

**Fetching:**
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/docker-compose.yml

---

## Pre-Run Diagnosis

### 🔴 STILL BROKEN — .env has duplicate keys (Script 1 was NOT fixed)

```
DOCKER_NETWORK=aip-u1001_net    ← line 12
DOCKER_NETWORK=ai_platform      ← line 27  ← STILL THERE, OVERWRITES

POSTGRES_PORT=5432              ← line ~38
POSTGRES_PORT=5432              ← line ~57  ← duplicate

REDIS_PORT=6379                 ← line ~40
REDIS_PORT=6379                 ← line ~58  ← duplicate

SIGNAL_API_PORT=8080            ← line ~70
SIGNAL_API_PORT=8090            ← line ~80  ← OVERWRITES, which is correct but 8080 is wrong

LITELLM_MASTER_KEY=Ace1Z3z...   ← line ~60
LITELLM_MASTER_KEY=5173eef...   ← last line ← OVERWRITES, longer one wins but both active
```

**Run this RIGHT NOW before anything else:**

```bash
ENV_FILE="/mnt/data/u1001/.env"

# Deduplicate — last value wins (which is correct for all cases above)
tac "${ENV_FILE}" | awk -F= '!seen[$1]++' | tac > /tmp/env_clean
mv /tmp/env_clean "${ENV_FILE}"
chmod 600 "${ENV_FILE}"
chown jglaine:jglaine "${ENV_FILE}"

# Verify the critical ones
grep -E "^DOCKER_NETWORK=|^POSTGRES_PORT=|^REDIS_PORT=|^SIGNAL_API_PORT=|^LITELLM_MASTER_KEY=" "${ENV_FILE}"
```

Expected output after fix:
```
DOCKER_NETWORK=ai_platform        ← last value wins — THIS IS STILL WRONG
POSTGRES_PORT=5432
REDIS_PORT=6379
SIGNAL_API_PORT=8090
LITELLM_MASTER_KEY=5173eef88...
```

⚠️ `DOCKER_NETWORK=ai_platform` will still win because it's the **last** occurrence. You need a hard fix:

```bash
# After dedup, force the correct tenant network
sed -i 's/^DOCKER_NETWORK=.*/DOCKER_NETWORK=aip-u1001_net/' "${ENV_FILE}"

# Also fix OPENCLAW paths — they still reference /mnt/data not /mnt/data/u1001
sed -i 's|OPENCLAW_SANDBOX_DIR=/mnt/data/data/openclaw|OPENCLAW_SANDBOX_DIR=/mnt/data/u1001/data/openclaw|' "${ENV_FILE}"
sed -i 's|OPENCLAW_CONFIG_DIR=/mnt/data/config/openclaw|OPENCLAW_CONFIG_DIR=/mnt/data/u1001/config/openclaw|' "${ENV_FILE}"
sed -i 's|OPENCLAW_DATA_PATH=/mnt/data/data/openclaw|OPENCLAW_DATA_PATH=/mnt/data/u1001/data/openclaw|' "${ENV_FILE}"
sed -i 's|OPENCLAW_CONFIG_PATH=/mnt/data/config/openclaw|OPENCLAW_CONFIG_PATH=/mnt/data/u1001/config/openclaw|' "${ENV_FILE}"
sed -i 's|OPENCLAW_BASE_URL=http://localhost:8082|OPENCLAW_BASE_URL=http://localhost:18789|' "${ENV_FILE}"

# Fix SIGNAL pairing URL port (8081 is wrong, should match SIGNAL_API_PORT=8090)
sed -i 's|SIGNAL_API_PAIRING_URL=http://localhost:8081|SIGNAL_API_PAIRING_URL=http://localhost:8090|' "${ENV_FILE}"

# Fix COMPOSE_FILE to tenant path
sed -i 's|COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml|COMPOSE_FILE=/mnt/data/u1001/docker-compose.yml|' "${ENV_FILE}"
```

---

### 🔴 CRITICAL — COMPOSE_FILE path is wrong

```
COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
```

That path doesn't exist. The compose file is in the repo at:
```
/mnt/data/ai-platform/scripts/docker-compose.yml   ← likely
# OR wherever the repo was cloned
```

**Verify actual location:**
```bash
find /mnt/data -name "docker-compose.yml" 2>/dev/null
```

Then fix in .env and ensure Script 2 uses `COMPOSE_FILE` from .env correctly.

---

### 🔴 CRITICAL — `DOMAIN=localhost` conflicts with `DOMAIN_NAME=ai.datasquiz.net`

```
DOMAIN_NAME=ai.datasquiz.net    ← correct public domain
DOMAIN=localhost                 ← leftover default, used by some services
```

Script 2 must consistently use `DOMAIN_NAME`. Any service template that interpolates `${DOMAIN}` will generate `localhost` URLs. Fix:

```bash
sed -i 's/^DOMAIN=localhost$/DOMAIN=ai.datasquiz.net/' "${ENV_FILE}"
```

---

### 🔴 CRITICAL — MINIO port conflict

```
MINIO_PORT=5007         ← set in ports section
MINIO_API_PORT=5007     ← same value
MINIO_CONSOLE_PORT=5008
MINIO_S3_PORT=9000
```

If docker-compose maps `MINIO_PORT` AND `MINIO_API_PORT` as separate port bindings both to `5007`, MinIO will fail to start. Script 2 must use only one variable for the API port.

---

### 🟠 MEDIUM — RCLONE_PORT and SIGNAL port gap

```
RCLONE_PORT=3000        ← rclone web UI
SIGNAL_API_PORT=8090    ← correct per SIGNAL_WEBHOOK_URL
SIGNAL_API_PAIRING_URL=http://localhost:8081/...  ← WRONG PORT (8081 ≠ 8090)
```

---

### 🟠 MEDIUM — Tailscale auth key is single-use

```
TAILSCALE_AUTH_KEY=tskey-auth-kBUfH3Mufi11CNTRL-ke8AertcMqcsqqEM4bGUqcKosUswX5du
TAILSCALE_IP=pending
```

If Script 2 has been run or partially run before (even failed), the auth key may already be consumed. Script 2 must check:

```bash
setup_tailscale() {
  # Check if already authenticated
  if docker exec tailscale tailscale status &>/dev/null; then
    TS_IP=$(docker exec tailscale tailscale ip -4 2>/dev/null | head -1)
    log_info "Tailscale already authenticated — IP: ${TS_IP}"
  else
    # Use auth key
    docker exec tailscale tailscale up \
      --authkey="${TAILSCALE_AUTH_KEY}" \
      --hostname="${TAILSCALE_HOSTNAME}" \
      ${TAILSCALE_EXIT_NODE:+--advertise-exit-node} \
      ${TAILSCALE_ACCEPT_ROUTES:+--accept-routes}
    TS_IP=$(docker exec tailscale tailscale ip -4 2>/dev/null | head -1)
  fi

  [[ -z "${TS_IP}" ]] && { log_error "Tailscale IP not obtained"; return 1; }

  # Write back to .env
  sed -i "s/^TAILSCALE_IP=.*/TAILSCALE_IP=${TS_IP}/" "${ENV_FILE}"
  log_success "Tailscale IP: ${TS_IP}"
}
```

---

## Full Action Plan for Windsurf

```
STEP 1 — Run on server RIGHT NOW (before any code changes):

  ENV_FILE="/mnt/data/u1001/.env"
  tac "${ENV_FILE}" | awk -F= '!seen[$1]++' | tac > /tmp/env_clean
  mv /tmp/env_clean "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"
  chown jglaine:jglaine "${ENV_FILE}"
  sed -i 's/^DOCKER_NETWORK=.*/DOCKER_NETWORK=aip-u1001_net/' "${ENV_FILE}"
  sed -i 's/^DOMAIN=localhost$/DOMAIN=ai.datasquiz.net/' "${ENV_FILE}"
  sed -i 's|OPENCLAW_SANDBOX_DIR=.*|OPENCLAW_SANDBOX_DIR=/mnt/data/u1001/data/openclaw|' "${ENV_FILE}"
  sed -i 's|OPENCLAW_CONFIG_DIR=.*|OPENCLAW_CONFIG_DIR=/mnt/data/u1001/config/openclaw|' "${ENV_FILE}"
  sed -i 's|OPENCLAW_DATA_PATH=.*|OPENCLAW_DATA_PATH=/mnt/data/u1001/data/openclaw|' "${ENV_FILE}"
  sed -i 's|OPENCLAW_CONFIG_PATH=.*|OPENCLAW_CONFIG_PATH=/mnt/data/u1001/config/openclaw|' "${ENV_FILE}"
  sed -i 's|OPENCLAW_BASE_URL=.*|OPENCLAW_BASE_URL=http://localhost:18789|' "${ENV_FILE}"
  sed -i 's|SIGNAL_API_PAIRING_URL=.*|SIGNAL_API_PAIRING_URL=http://localhost:8090/v1/qrcodelink?device_name=signal-api|' "${ENV_FILE}"
  find /mnt/data -name "docker-compose.yml" 2>/dev/null

STEP 2 — Fix COMPOSE_FILE in .env:
  # After finding compose path from step 1:
  sed -i 's|COMPOSE_FILE=.*|COMPOSE_FILE=<actual_path_from_find>|' "${ENV_FILE}"

STEP 3 — Windsurf code fixes in Script 1 (prevent recurrence):
  - Write DOCKER_NETWORK only once using tenant ID
  - Write DOMAIN same as DOMAIN_NAME when domain resolves
  - Write POSTGRES_PORT, REDIS_PORT only once (not in two sections)
  - Write SIGNAL_API_PORT only once (8090)
  - Write LITELLM_MASTER_KEY only once
  - Fix OPENCLAW paths to use TENANT_DIR not BASE_DIR
  - Fix print_service_summary() to use subdomain format (no port in URL)

STEP 4 — Windsurf code fixes in Script 2:
  - ENV_FILE="${BASE_DIR}/${TENANT_ID}/.env" at top
  - Inline add_caddy_service() function (full implementation above)
  - Inline add_rclone_service() function (full implementation above)
  - setup_tailscale() must check if already authed before using key
  - MINIO: use MINIO_API_PORT for API, MINIO_CONSOLE_PORT for console
  - Execution order: dirs → network → infra → health → DBs → tailscale → caddy → services → rclone → print

STEP 5 — Windsurf code fixes in docker-compose.yml:
  - All services use network: ${DOCKER_NETWORK}
  - AnythingLLM: VECTOR_DB=qdrant, QDRANT_ENDPOINT=http://qdrant:${QDRANT_PORT}
  - Dify: VECTOR_STORE=qdrant, QDRANT_URL=http://qdrant:${QDRANT_PORT}
  - OpenWebUI: VECTOR_DB=qdrant, QDRANT_URI=http://qdrant:${QDRANT_PORT}
  - Flowise: FLOWISE_QDRANT_HOST=http://qdrant:${QDRANT_PORT}
  - LiteLLM: internal URL used by AI services = http://litellm:${LITELLM_PORT}
  - MinIO: only ONE port binding for API (MINIO_API_PORT), one for console

STEP 6 — Verify before running Script 2:
  grep -E "^DOCKER_NETWORK=|^DOMAIN=|^COMPOSE_FILE=" /mnt/data/u1001/.env
  # Must show:
  # DOCKER_NETWORK=aip-u1001_net
  # DOMAIN=ai.datasquiz.net
  # COMPOSE_FILE=<valid path that exists>
  ls -la $(grep "^COMPOSE_FILE=" /mnt/data/u1001/.env | cut -d= -f2)
  # Must show the actual file
```

**Do not run Script 2 until Step 1 and Step 2 are verified on the server.**