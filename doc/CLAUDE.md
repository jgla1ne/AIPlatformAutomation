This is the final, definitive prompt you must provide to **Windsurf**. It is rigorously aligned with your README.md, WINDSURF.md, and core principles. It eliminates all LiteLLM remnants, strictly enforces the zero-root/Mission Control architecture, and configures the Caddy HTTPS stack correctly based on standard reverse-proxy documentation.

Copy and paste this exact prompt into Windsurf:

***

### 🤖 MASTER PROMPT FOR WINDSURF:

"Windsurf, act as a Lead Platform Architect. We are pushing the AI Platform Automation deployment to 100% completion. You are to permanently and flawlessly replace **LiteLLM** with **Bifrost (ruqqq/bifrost)** across the entire codebase. 

Read our README.md and doc/WINDSURF.md. All previous failures occurred because you violated our core principles: **Zero Root, Zero Hardcoded Values, 100% Dockerized, and strictly contained within /mnt/data/${TENANT_ID}.**

Review and rewrite the following 5 files. **Do not hallucinate external dependencies. Do not skip any steps.**

#### 1. RUTHLESS PURGE & CLEANUP (0-complete-cleanup.sh)
*   **Search and Destroy:** Remove every single reference to litellm and port 4000 globally.
*   **Update Cleanup Target:** In the containers array, remove the LiteLLM container and add ai-${TENANT_ID}-bifrost-1.
*   **Update Directory Target:** In the directories array, add /mnt/data/${TENANT_ID}/configs/bifrost and /mnt/data/${TENANT_ID}/data/bifrost.

#### 2. MISSION CONTROL INITIALIZATION (1-setup-system.sh)
Bifrost fails on startup because Docker creates missing volume mounts as root. We must pre-initialize them as the non-root tenant user.
*   Remove any user prompts asking to select an LLM router. Bifrost is the only router.
*   Create a strictly compliant init_bifrost() function:
```bash
init_bifrost() {
    echo -e "${YELLOW}Initializing Bifrost directories (Zero-Root Compliance)...${NC}"
    local BIFROST_CONFIG_DIR="/mnt/data/${TENANT_ID}/configs/bifrost"
    local BIFROST_DATA_DIR="/mnt/data/${TENANT_ID}/data/bifrost"

    # Pre-create directories as tenant
    mkdir -p "${BIFROST_CONFIG_DIR}"
    mkdir -p "${BIFROST_DATA_DIR}"
    
    # Enforce non-root ownership BEFORE Docker starts
    chown -R ${TENANT_UID}:${TENANT_GID} "${BIFROST_CONFIG_DIR}"
    chown -R ${TENANT_UID}:${TENANT_GID} "${BIFROST_DATA_DIR}"
    
    echo -e "${GREEN}Bifrost initialized successfully.${NC}"
}
```
*   Ensure init_bifrost is called. Add BIFROST_PORT="8000" to the .env generation block to avoid hardcoding.

#### 3. STRICT DOCKER IMPLEMENTATION (2-deploy-services.sh)
Inject the Bifrost service into the docker-compose.yml generation block. 
*   **Bifrost Service:** Must use the Mission Control UID/GID variables.
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
*   **OpenWebUI Integration:** Update OpenWebUI to connect to Bifrost internally. Set OPENAI_API_BASE_URL=http://bifrost:8000/v1. Change depends_on to bifrost.
*   **Caddy Service:** Ensure Caddy's depends_on targets bifrost.

#### 4. BULLETPROOF HTTPS ROUTING (3-configure-services.sh)
Your previous Caddyfiles used invalid directives. Use standard, dynamic reverse-proxy blocks.
*   **Remove** tls internal and auto_https off.
*   Generate the Caddyfile perfectly:
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

#### 5. README ALIGNMENT (README.md)
*   Scrub all mentions of LiteLLM.
*   Add **Bifrost (LLM Gateway/Router)** to the Software Stack section. 

Execute these changes directly on the codebase now. Ensure every variable dynamically connects."