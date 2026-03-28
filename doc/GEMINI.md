Here is the ultimate, definitive master plan to push this implementation from 85% to 100%. This is specifically engineered to be pasted directly into **Windsurf**. 

It guarantees adherence to your core principles: **Zero Root, Zero Hardcoded Values, 100% /mnt contained, and Mission Control variable state management.**

***

### 🤖 COPY AND PASTE THIS PROMPT INTO WINDSURF:

"Windsurf, you are acting as an expert DevOps and Platform Architect. We are moving this AI Platform deployment from 85% to 100% completion. You are replacing **LiteLLM** entirely with **Bifrost (ruqqq/bifrost)**. 

Previous attempts failed because they violated our core principles: running containers as non-root, failing to pre-initialize directories leading to permission crashes, leaving hardcoded LiteLLM references, or deploying invalid Caddy configurations.

Execute this precise, 6-step architectural refactor across the 4 core scripts and `README.md`. **Do not skip steps. Do not use hardcoded values where variables exist. Ensure 100% zero-root compliance.**

#### STEP 1: Total Eradication of LiteLLM (All Files)
Perform a global search and destroy for `litellm`, `LiteLLM`, and port `4000`.
*   **Remove** `init_litellm()` and any related user prompts.
*   **Remove** LiteLLM from the success dashboard outputs.
*   Bifrost is now the mandatory routing engine. 

#### STEP 2: Perfect Cleanup (`0-complete-cleanup.sh`)
Ensure Bifrost is fully integrated into the teardown process using variable-based targeting.
*   **Containers array:** Replace `ai-${TENANT_ID}-litellm-1` with `ai-${TENANT_ID}-bifrost-1`.
*   **Directories array:** Replace LiteLLM paths with `/mnt/data/${TENANT_ID}/configs/bifrost` and `/mnt/data/${TENANT_ID}/data/bifrost`.

#### STEP 3: Mission Control & Zero-Root Initialization (`1-setup-system.sh`)
If we do not pre-create Bifrost's directories as the non-root user, Docker will create them as `root`, causing Bifrost to crash on startup with a `Permission denied` error.
*   Create an `init_bifrost()` function.
*   Declare dynamic ports to avoid hardcoding. Add `BIFROST_PORT="8000"` to the environment state export block.

```bash
init_bifrost() {
    echo -e "${YELLOW}Initializing Bifrost directories (Zero-Root Compliance)...${NC}"
    local BIFROST_CONFIG_DIR="/mnt/data/${TENANT_ID}/configs/bifrost"
    local BIFROST_DATA_DIR="/mnt/data/${TENANT_ID}/data/bifrost"

    # Pre-create directories
    mkdir -p "${BIFROST_CONFIG_DIR}"
    mkdir -p "${BIFROST_DATA_DIR}"
    
    # Pre-create standard config file so Docker doesn't map it as a root directory
    touch "${BIFROST_CONFIG_DIR}/bifrost.yaml"
    
    # Enforce non-root ownership
    chown -R ${TENANT_UID}:${TENANT_GID} "${BIFROST_CONFIG_DIR}"
    chown -R ${TENANT_UID}:${TENANT_GID} "${BIFROST_DATA_DIR}"
    
    echo -e "${GREEN}Bifrost initialized successfully.${NC}"
}
```
*   Call `init_bifrost` in the main execution flow.
*   Update the `.env` generation block to include `BIFROST_PORT=8000`.

#### STEP 4: Strict Docker Implementation (`2-deploy-services.sh`)
Inject the Bifrost service into the `docker-compose.yml` generation block. 
*   **Bifrost Service:** Must use `${TENANT_UID}:${TENANT_GID}`.

```yaml
  bifrost:
    image: ghcr.io/ruqqq/bifrost:latest
    container_name: ai-\${TENANT_ID}-bifrost-1
    restart: unless-stopped
    user: "\${TENANT_UID:-1000}:\${TENANT_GID:-1000}"
    ports:
      - "\${BIFROST_PORT:-8000}:8000"
    volumes:
      - /mnt/data/\${TENANT_ID}/configs/bifrost:/app/config
      - /mnt/data/\${TENANT_ID}/data/bifrost:/app/data
    environment:
      - BIFROST_HOST=0.0.0.0
      - BIFROST_PORT=8000
    networks:
      - default
```
*   **OpenWebUI Integration:** Change the `OPENAI_API_BASE_URL` to connect internally to Bifrost's v1 endpoint. 
    *   Change: `OPENAI_API_BASE_URL=http://bifrost:8000/v1`
    *   Update `depends_on` to require `bifrost`.
*   **Caddy Service:** Ensure `depends_on` requires `bifrost` instead of `litellm`.

#### STEP 5: Bulletproof Caddy Routing (`3-configure-services.sh`)
Replace all LiteLLM proxy rules with Bifrost. Do not use invalid directives like `tls internal` or `auto_https off` which break standard Caddy deployments. Use dynamic variables for domains and ports.

```bash
cat << EOF > /mnt/data/${TENANT_ID}/configs/caddy/Caddyfile
{
    admin 0.0.0.0:2019
    email ${ADMIN_EMAIL}
}

https://router.${DOMAIN} {
    reverse_proxy bifrost:8000 {
        header_up Host {http.reverse_proxy.upstream.hostport}
        header_up X-Real-IP {http.request.remote_host}
        header_up X-Forwarded-For {http.request.remote_addr}
        header_up X-Forwarded-Proto https
    }
}

https://chat.${DOMAIN} {
    reverse_proxy open-webui:8080 {
        header_up Host {http.reverse_proxy.upstream.hostport}
        header_up X-Real-IP {http.request.remote_host}
        header_up X-Forwarded-For {http.request.remote_addr}
        header_up X-Forwarded-Proto https
        header_up Upgrade {http.request.header.Upgrade}
        header_up Connection {http.request.header.Connection}
    }
}
EOF
```

#### STEP 6: README.md Alignment
*   Remove all mentions of LiteLLM.
*   Add **Bifrost (LLM Gateway/Router)** to the Software Stack section.
*   Ensure the documentation clearly states that Bifrost serves as the OpenAI-compatible gateway handling the upstream API keys, and OpenWebUI connects directly to it via the internal Docker network on port 8000.

Execute these updates across all 5 files immediately. Ensure no variables are left disconnected."