This is the definitive, zero-hallucination master plan. The reason Windsurf keeps failing with Bifrost is that it is treating it like a drop-in replacement for LiteLLM without respecting the **Zero-Root, Dockerized, and /mnt Contained** core principles outlined in your `README.md`. 

When running containers as a non-root user (`${TENANT_UID}:${TENANT_GID}`), if the application expects a configuration file or database file to exist, and it tries to create it inside a mounted directory it doesn't have permissions for, **it will crash on startup**.

Here is the exact, unyielding prompt you must paste into **Windsurf**. It leaves absolutely no room for interpretation and enforces your platform's strict architectural constraints.

***

### 🤖 MASTER PROMPT FOR WINDSURF:

"Windsurf, we are executing a final, flawless transition from LiteLLM to **Bifrost (ruqqq/bifrost)**. All previous attempts failed because they violated our core principles (Zero-Root, fully contained in `/mnt/data/${TENANT_ID}`) or left stale configurations. 

Read the platform's `README.md` to ground yourself in the architecture. Then, modify the 4 shell scripts exactly as specified below. **Do not hallucinate external dependencies or bypass the non-root constraints.**

#### STEP 1: Total Eradication of LiteLLM (All Scripts)
Search the entire codebase for `litellm` (case-insensitive) and port `4000`. 
*   Remove all functions, variables, and UI prompts referencing LiteLLM. 
*   Bifrost is now the **only** routing engine. Do not offer a choice in Script 1.

#### STEP 2: Perfect Cleanup (`0-complete-cleanup.sh`)
Add Bifrost to the cleanup arrays.
*   **Containers array:** Add `ai-datasquiz-bifrost-1` (match your exact tenant prefix format).
*   **Directories array:** Add `/mnt/data/${TENANT_ID}/configs/bifrost` and `/mnt/data/${TENANT_ID}/bifrost_data`.

#### STEP 3: Zero-Root Initialization (`1-setup-system.sh`)
This is where previous iterations failed. Bifrost needs its configuration directories created and owned by the non-root tenant **before** Docker starts, otherwise, the container will crash due to write permission errors.
*   Create an `init_bifrost()` function.
*   It MUST create the data and config directories.
*   It MUST create an empty baseline config file so Bifrost doesn't crash trying to write one as a restricted user.
*   It MUST apply strict `chown` using the platform's variables.

```bash
init_bifrost() {
    echo -e "${YELLOW}Initializing Bifrost directories...${NC}"
    mkdir -p "/mnt/data/${TENANT_ID}/configs/bifrost"
    mkdir -p "/mnt/data/${TENANT_ID}/bifrost_data"
    
    # Pre-create standard files to avoid Docker root-ownership creation
    touch "/mnt/data/${TENANT_ID}/configs/bifrost/config.yaml"
    
    chown -R ${TENANT_UID}:${TENANT_GID} "/mnt/data/${TENANT_ID}/configs/bifrost"
    chown -R ${TENANT_UID}:${TENANT_GID} "/mnt/data/${TENANT_ID}/bifrost_data"
    echo -e "${GREEN}Bifrost initialized.${NC}"
}
```
*   Ensure `init_bifrost` is called in the main execution flow.
*   Update the final Summary Dashboard to display `LLM Gateway: Bifrost`.

#### STEP 4: Strict Docker Implementation (`2-deploy-services.sh`)
Inject the Bifrost service into the `docker-compose.yml` generation block. It must adhere to the zero-root policy.
```yaml
  bifrost:
    image: ghcr.io/ruqqq/bifrost:latest
    container_name: ai-${TENANT_ID}-bifrost-1
    restart: unless-stopped
    user: "${TENANT_UID:-1000}:${TENANT_GID:-1000}"
    ports:
      - "8000:8000"
    volumes:
      - /mnt/data/${TENANT_ID}/configs/bifrost:/app/config
      - /mnt/data/${TENANT_ID}/bifrost_data:/app/data
    environment:
      - BIFROST_HOST=0.0.0.0
      - BIFROST_PORT=8000
    networks:
      - default
```
**CRITICAL:** Update the `open-webui` service to connect to Bifrost. 
*   Change `OPENAI_API_BASE_URL` to `http://bifrost:8000/v1`
*   Change `depends_on` in `open-webui` to `bifrost`.

#### STEP 5: Bulletproof Caddy Routing (`3-configure-services.sh`)
Generate the `Caddyfile` perfectly. No invalid directives (`header_read_timeout`), no `tls internal` (which breaks external HTTPS), and no `auto_https off`.

```bash
cat << EOF > /mnt/data/${TENANT_ID}/configs/caddy/Caddyfile
{
    admin 0.0.0.0:2019
    email ${ADMIN_EMAIL}
}

https://bifrost.${DOMAIN} {
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

#### STEP 6: README Documentation Alignment
*   Update `README.md` to officially list **Bifrost (LLM Gateway/Router)** in the Software Stack section.
*   Remove all legacy mentions of LiteLLM in the troubleshooting, architecture, and feature lists.

Execute this exactly as written. Verify variable names match the existing script ecosystem."