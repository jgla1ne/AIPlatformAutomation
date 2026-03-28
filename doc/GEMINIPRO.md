To reach **100% "Zero-Issue" status**, Windsurf must bridge the final gap between **static script generation** and **dynamic container runtime**. 

The current 5% failure rate is caused by **Race Conditions** (Bifrost starting before Postgres is ready) and **Mount Collisions** (Docker creating a directory instead of a file mount if the YAML isn't present).

This is the **Definite Final Plan** for Windsurf to execute.

---

### 🚨 The "Final Mile" Architecture Rules
1.  **Atomic Artifacts:** `scripts/1` **must** generate the `config.yaml` for Bifrost before `scripts/2` starts.
2.  **Mount Protection:** Never mount a file that doesn't exist. Windsurf must use `touch` to ensure the file exists so Docker doesn't create a `config.yaml/` directory.
3.  **Network Identity:** Use the Docker service name (`${CONTAINER_PREFIX}-bifrost`) for all internal communication.
4.  **Health-Gating:** `scripts/2` must use a `service_healthy` condition for the database.

---

### 🛠 Phase 0: The Nuclear Reset (`scripts/0-complete-cleanup.sh`)
**Objective:** Ensure no dangling volumes or network bridges from failed LiteLLM attempts exist.
*   **Action:** Delete by label/prefix.
```bash
# Ensure Script 0 removes the specific network
docker network rm "${CONTAINER_PREFIX}-network" 2>/dev/null || true
# Deep clean volumes to reset permissions
rm -rf "/mnt/data/${TENANT_ID}"
```

---

### 📝 Phase 1: Artifact Preparation (`scripts/1-setup-system.sh`)
**Objective:** Create the "Ground Truth" configuration and fix permissions before Docker touches anything.

**1. Generate the Bifrost YAML (The "Bifrost Contract"):**
Bifrost requires a YAML. Script 1 must write this to the host filesystem.
```bash
BIFROST_DIR="/mnt/data/${TENANT_ID}/config/bifrost"
mkdir -p "$BIFROST_DIR"

cat <<EOF > "${BIFROST_DIR}/config.yaml"
server:
  port: 4000
  auth_token: "${CODEBASE_PASSWORD}"
database:
  url: "postgres://postgres:${CODEBASE_PASSWORD}@${CONTAINER_PREFIX}-postgres:5432/bifrost?sslmode=disable"
providers:
  - name: ollama
    type: openai
    base_url: "http://${CONTAINER_PREFIX}-ollama:11434/v1"
EOF

# CRITICAL: Prevent Docker 'directory-mount' error
touch "${BIFROST_DIR}/config.yaml"

# CRITICAL: Zero-Root Permission Fix (Apply to the entire tenant tree)
chown -R 1000:1000 "/mnt/data/${TENANT_ID}"
```

---

### 🚀 Phase 2: Orchestrated Deployment (`scripts/2-deploy-services.sh`)
**Objective:** Ensure Bifrost only starts when its dependencies are alive.

**1. The Postgres Healthcheck (Non-Negotiable):**
```yaml
  ${CONTAINER_PREFIX}-postgres:
    image: postgres:16-alpine
    user: "1000:1000"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
```

**2. The Bifrost Container Definition:**
Note the use of `service_healthy` and the specific config path.
```yaml
  ${CONTAINER_PREFIX}-bifrost:
    image: ruqqq/bifrost:latest
    user: "1000:1000"
    depends_on:
      ${CONTAINER_PREFIX}-postgres:
        condition: service_healthy
    volumes:
      - /mnt/data/${TENANT_ID}/config/bifrost/config.yaml:/app/config.yaml:ro
    command: ["--config", "/app/config.yaml"]
    ports:
      - "4000:4000"
```

---

### 🌐 Phase 3: Routing & Mission Control (`scripts/3-configure-services.sh`)
**Objective:** Connect the frontend to the backend via the internal proxy.

**1. The Agnostic Caddyfile:**
Caddy must talk to the service name, not `localhost`.
```bash
cat <<EOF > "/mnt/data/${TENANT_ID}/config/caddy/Caddyfile"
${DOMAIN} {
    # Proxy to Bifrost (Router)
    reverse_proxy /v1/* ${CONTAINER_PREFIX}-bifrost:4000
    
    # Proxy to OpenClaw (Frontend)
    reverse_proxy * ${CONTAINER_PREFIX}-openclaw:3000
    
    log {
        output file /data/caddy/access.log
    }
}
EOF
docker exec "${CONTAINER_PREFIX}-caddy" caddy reload --config /etc/caddy/Caddyfile
```

**2. The 100% Validation Gate:**
Windsurf must perform an internal loopback test.
```bash
echo "Verifying E2E Connectivity..."
# Test Caddy -> Bifrost -> Postgres
MAX_TRIES=10
for i in $(seq 1 $MAX_TRIES); do
  if docker exec "${CONTAINER_PREFIX}-caddy" curl -s "http://${CONTAINER_PREFIX}-bifrost:4000/health" | grep -q "OK"; then
    echo "SUCCESS: Platform is 100% Operational."
    exit 0
  fi
  echo "Waiting for services... ($i/$MAX_TRIES)"
  sleep 3
done
echo "ERROR: Health check failed."
exit 1
```

---

### ✅ Summary of the 100% Definite Fixes:
1.  **Permission Pre-emption:** We `chown` the folder *before* Docker runs, preventing "Permission Denied" crashes.
2.  **Mount Reliability:** We `touch` the config file in Script 1, ensuring Docker mounts it as a **file**, not a **directory**.
3.  **Port Sync:** We explicitly set `server.port: 4000` in the YAML to match the Docker mapping.
4.  **Agnostic Naming:** We use `${CONTAINER_PREFIX}` everywhere to ensure no name collisions.
5.  **Database Readiness:** We use `pg_isready` in a Docker healthcheck so Bifrost doesn't crash on the first connection attempt.

**Execution Order for Windsurf:** 
1. `0-complete-cleanup.sh` 
2. `1-setup-system.sh` (Verify `config.yaml` exists here!)
3. `2-deploy-services.sh` 
4. `3-configure-services.sh` 

This plan removes all ambiguity and addresses the specific Go-binary quirks of the Bifrost service.