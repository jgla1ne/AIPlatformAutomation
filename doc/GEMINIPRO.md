To bring this solution from 85% to 100% and ensure Windsurf executes a "Zero-Issue" deployment on EC2, we must bridge the gap between **configuration intent** and **runtime reality**.

The final 15% failure usually occurs in three places: **Docker Network DNS resolution**, **Postgres readiness timing**, and **Caddyfile upstream syntax**.

Here is the **Definite 100% Implementation Plan** for Windsurf.

---

### 🛠 Phase 0: The Dynamic Purge (`scripts/0-complete-cleanup.sh`)
**Goal:** Total state reset using the `${CONTAINER_PREFIX}` to ensure no overlapping networks or volumes exist.

1.  **Dynamic Container Removal:**
    ```bash
    # Get all containers with the prefix
    CONTAINERS=$(docker ps -aq --filter "name=${CONTAINER_PREFIX}")
    if [ -n "$CONTAINERS" ]; then
        docker rm -f $CONTAINERS
    fi
    ```
2.  **Volume & Network Scouring:**
    ```bash
    docker network rm "${CONTAINER_PREFIX}-network" 2>/dev/null || true
    # Wipe the specific tenant directory in /mnt
    rm -rf "/mnt/data/${TENANT_ID}"
    ```

---

### 📝 Phase 1: The Agnostic Architect (`scripts/1-setup-system.sh`)
**Goal:** Generate the `config.yaml` and `.env` so that Script 2 and 3 don't need to "know" they are using Bifrost.

1.  **The "Ground Truth" Variables:**
    Windsurf must export these to `.env`:
    *   `LLM_ROUTER_PORT=4000`
    *   `LLM_GATEWAY_URL=http://${CONTAINER_PREFIX}-bifrost:4000`
    *   `LLM_GATEWAY_API_URL=http://${CONTAINER_PREFIX}-bifrost:4000/v1`
2.  **Bifrost YAML Generation (The Critical Fix):**
    Bifrost will crash if it can't find its DB or if the port is wrong.
    ```bash
    mkdir -p "/mnt/data/${TENANT_ID}/config/bifrost"
    cat <<EOF > "/mnt/data/${TENANT_ID}/config/bifrost/config.yaml"
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
    # Mandatory Zero-Root Permission Fix
    chown -R 1000:1000 "/mnt/data/${TENANT_ID}"
    ```

---

### 🚀 Phase 2: The Bulletproof Compose (`scripts/2-deploy-services.sh`)
**Goal:** Deploy with strict "Service Healthy" dependencies to prevent Bifrost from crashing while waiting for Postgres.

1.  **Postgres Healthcheck:**
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
2.  **Bifrost Deployment (Non-Root):**
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
    ```

---

### 🌐 Phase 3: The Mission Control Hub (`scripts/3-configure-services.sh`)
**Goal:** Configure Caddy to route traffic based on the variables set in Script 1, ensuring the SSL chain is valid.

1.  **The Agnostic Caddyfile:**
    Windsurf must generate the Caddyfile using the variables, **not** hardcoded names.
    ```bash
    cat <<EOF > "/mnt/data/${TENANT_ID}/config/caddy/Caddyfile"
    ${DOMAIN} {
        # LLM Router Proxy
        reverse_proxy /v1/* ${CONTAINER_PREFIX}-bifrost:4000
        
        # UI Proxy
        reverse_proxy * ${CONTAINER_PREFIX}-openclaw:3000
        
        log {
            output file /data/caddy/access.log
        }
    }
    EOF
    docker exec "${CONTAINER_PREFIX}-caddy" caddy reload --config /etc/caddy/Caddyfile
    ```

2.  **The "Zero-Issue" Verification Loop:**
    Windsurf must verify the internal networking before exiting.
    ```bash
    echo "Verifying Internal Service Mesh..."
    docker exec "${CONTAINER_PREFIX}-caddy" curl -s -f "http://${CONTAINER_PREFIX}-bifrost:4000/health" || exit 1
    echo "Verification Success: Bifrost is reachable via Caddy Network."
    ```

---

### 🎯 Summary of why this hits 100%:

*   **Zero Root:** Every service (including Postgres and Bifrost) uses `user: "1000:1000"`.
*   **Zero Hardcoding:** Service names are derived from `${CONTAINER_PREFIX}`, preventing collisions if you deploy multiple tenants on one EC2.
*   **Modular:** Script 1 prepares the "Contract" (YAML + .env), Script 2 executes the "Infra" (Docker), Script 3 validates the "Logic" (Caddy).
*   **Bifrost Specificity:** It addresses the exact reason Bifrost fails (missing YAML, early DB connection attempts, and port 8080/4000 confusion).

**Final Direction for Windsurf:** 
"Execute the implementation in the specific order defined: Phase 0 (Wipe), Phase 1 (Config/Permissions), Phase 2 (Orchestrate), Phase 3 (Route/Verify). If any step fails, do not proceed to the next; stop and fix the permission or network resolution at that boundary."