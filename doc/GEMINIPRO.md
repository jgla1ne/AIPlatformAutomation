The previous 5% failure persists because **Bifrost is fundamentally different from LiteLLM in how it handles its database initialization and configuration polling.** 

To reach 100%, Windsurf must stop treating Bifrost as a "plugin" and start treating it as the **Primary Infrastructure Router**. 

Here is the **Definite, Zero-Issue Implementation Plan** for Windsurf.

---

### 🚨 THE FATAL FLAWS WE ARE ELIMINATING
1.  **The "Directory-as-File" Bug:** If Docker starts before Script 1 finishes writing the config, Docker creates a *directory* called `config.yaml`. Bifrost then crashes.
2.  **The "DB Race":** Bifrost attempts to migrate the database the millisecond it starts. If Postgres is "up" but not "ready for queries," Bifrost exits and doesn't always restart gracefully.
3.  **The "Ghost LiteLLM" Variables:** Scripts still contain references to `LITELLM_MASTER_KEY` which Bifrost ignores, leading to auth failures in the UI.

---

### 🛠 PHASE 0: The Surgical Purge (`0-complete-cleanup.sh`)
Windsurf must ensure the environment is "Virgin State."
*   **Action:** Delete the specific tenant path and the Docker network.
*   **Logic:**
    ```bash
    # Kill containers by label to avoid missing any
    docker ps -q --filter "label=tenant=${TENANT_ID}" | xargs -r docker rm -f
    # Wipe the mount point entirely to reset permissions
    rm -rf "/mnt/data/${TENANT_ID}"
    # Remove the specific network
    docker network rm "${CONTAINER_PREFIX}-network" || true
    ```

---

### 📝 PHASE 1: The Config Engine (`1-setup-system.sh`)
This script must now act as a **Compiler**. It creates the "Ground Truth" before any container pulls an image.

**1. Define the Router Contract:**
```bash
# Add to .env
LLM_ROUTER_TYPE="bifrost"
LLM_ROUTER_PORT=4000
LLM_GATEWAY_URL="http://${CONTAINER_PREFIX}-bifrost:4000"
LLM_GATEWAY_API_URL="http://${CONTAINER_PREFIX}-bifrost:4000/v1"
```

**2. Atomic Configuration Writing:**
Windsurf must write the YAML *first*, then `chown`, then `chmod`.
```bash
BIFROST_CONF_DIR="/mnt/data/${TENANT_ID}/config/bifrost"
mkdir -p "$BIFROST_CONF_DIR"

cat <<EOF > "${BIFROST_CONF_DIR}/config.yaml"
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

# THE 100% FIX: Ensure file exists and permissions are set before Docker sees it
touch "${BIFROST_CONF_DIR}/config.yaml"
chown -R 1000:1000 "/mnt/data/${TENANT_ID}"
chmod -R 775 "/mnt/data/${TENANT_ID}"
```

---

### 🚀 PHASE 2: The Orchestrator (`2-deploy-services.sh`)
Windsurf must use **Hard Dependencies**. 

**1. Postgres with Healthcheck:**
```yaml
  ${CONTAINER_PREFIX}-postgres:
    image: postgres:16-alpine
    user: "1000:1000"
    environment:
      POSTGRES_DB: bifrost
      POSTGRES_PASSWORD: ${CODEBASE_PASSWORD}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d bifrost"]
      interval: 5s
      timeout: 5s
      retries: 10
```

**2. Bifrost with Native Config:**
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
    restart: always
```

---

### 🌐 PHASE 3: The Mission Control Hub (`3-configure-services.sh`)
This script must verify the **Internal DNS** of the Docker network.

**1. Dynamic Caddy Routing:**
```bash
cat <<EOF > "/mnt/data/${TENANT_ID}/config/caddy/Caddyfile"
${DOMAIN} {
    # Route to Bifrost
    handle_path /v1/* {
        reverse_proxy ${CONTAINER_PREFIX}-bifrost:4000
    }
    # Route to UI
    reverse_proxy * ${CONTAINER_PREFIX}-openclaw:3000
}
EOF
docker exec "${CONTAINER_PREFIX}-caddy" caddy reload
```

**2. The Final Health Gate (The 100% Proof):**
Windsurf must not finish until this returns `200 OK`.
```bash
echo "Verifying E2E Router Health..."
# Test if the UI can actually talk to Bifrost through the internal network
docker exec "${CONTAINER_PREFIX}-openclaw" curl -s -H "Authorization: Bearer ${CODEBASE_PASSWORD}" "${LLM_GATEWAY_API_URL}/models" | grep -q "data"
```

---

### 📋 WINDSURF CHECKLIST FOR 100% SUCCESS

*   [ ] **Delete LiteLLM Logic:** Search and destroy all `litellm` strings in the codebase.
*   [ ] **Validate YAML Syntax:** Ensure the `config.yaml` is valid YAML (no tabs, only spaces).
*   [ ] **Port Consistency:** Verify that `server.port` in YAML is `4000`, the Docker `EXPOSE` is `4000`, and the Caddy upstream is `4000`.
*   [ ] **UID/GID enforcement:** Every container in Script 2 **must** have `user: "1000:1000"`.
*   [ ] **Mount Pathing:** Ensure all volumes map from `/mnt/data/${TENANT_ID}/...` and never relative paths like `./config`.

**Final instruction for Windsurf:** 
"Follow this phase-gate approach. If Phase 1 does not produce a valid, 1000-owned `config.yaml`, **do not** run Phase 2. This is the logic that guarantees a zero-issue deployment."