This is a smart and necessary architectural pivot. If a core component like the LLM router takes 200+ hours to stabilize, it violates the core principle of a resilient, automated platform. Replacing it with (or offering an alternative like) **Bifrost** (`ruqqq/bifrost`) is the right move. 

Here is the comprehensive, bulletproof prompt you should paste into **Windsurf** to implement this architectural change cleanly across the 4 scripts and the README.

***

### 🤖 Prompt for Windsurf:

"Windsurf, we are making a critical architectural pivot. After extensive testing, LiteLLM has proven too fragile and unpredictable for our automated, non-root Dockerized deployment. We are going to introduce **Bifrost (ruqqq/bifrost)** as a robust alternative LLM router. 

Please implement this new option gracefully across the scripts. Our goal is a modular approach where the user chooses the router in Script 1, and the rest of the scripts adapt automatically. 

**Do not rewrite the scripts from scratch.** Inject/modify the following targeted areas carefully:

#### 1. Update `0-complete-cleanup.sh`
Add Bifrost to the cleanup arrays to ensure proper teardown.
*   **Containers:** Add `ai-datasquiz-bifrost-1` (or your standard prefix naming convention).
*   **Volumes/Directories:** Add `/mnt/data/${TENANT_ID}/bifrost` and `/mnt/data/${TENANT_ID}/configs/bifrost` to the cleanup lists.

#### 2. Update `1-setup-system.sh` (Mission Control & Prompts)
We need to ask the user which router they want and save it to the state.
*   **Prompt User:** Add an interactive prompt: `Which LLM router would you like to use? [1] LiteLLM (Legacy) [2] Bifrost (Recommended)`.
*   **State Management:** Export this choice as `LLM_ROUTER="bifrost"` (or `"litellm"`) into the global `.env` file.
*   **Init Function:** Create an `init_bifrost` function alongside the existing `init_litellm` function. It should create the required directories with non-root ownership (`${TENANT_UID}:${TENANT_GID}`):
    ```bash
    mkdir -p "/mnt/data/${TENANT_ID}/configs/bifrost"
    # Create baseline empty config or touch files needed by Bifrost
    chown -R ${TENANT_UID}:${TENANT_GID} "/mnt/data/${TENANT_ID}/configs/bifrost"
    ```
*   **Health Dashboard:** Update the end-of-script dashboard to display `LLM Router: ${LLM_ROUTER}`.

#### 3. Update `2-deploy-services.sh` (Modular Docker Compose)
Modify the `docker-compose.yml` generation to be conditional based on `$LLM_ROUTER`.
*   Wrap the LiteLLM service block in an `if [ "$LLM_ROUTER" = "litellm" ]; then ... fi` block.
*   Add the Bifrost service block in the `elif [ "$LLM_ROUTER" = "bifrost" ]; then` block.
*   **Bifrost Docker Config:**
    ```yaml
      bifrost:
        image: ghcr.io/ruqqq/bifrost:latest
        container_name: ai-${TENANT_ID}-bifrost-1
        restart: unless-stopped
        user: "${TENANT_UID:-1000}:${TENANT_GID:-1000}"
        ports:
          - "8000:8000" # Adjust to Bifrost's actual internal port if different
        volumes:
          - /mnt/data/${TENANT_ID}/configs/bifrost:/app/data # Map data/config dir
        environment:
          - BIFROST_HOST=0.0.0.0
        networks:
          - default
    ```
*   **Dependency updates:** Ensure `open-webui` and `caddy` depend on `${LLM_ROUTER}` rather than hardcoding `litellm`.

#### 4. Update `3-configure-services.sh` (Caddy Routing)
Update the Caddyfile generation to route external requests to the correct internal container.
*   Conditionally generate the `Caddyfile` reverse proxy block.
    *   If `$LLM_ROUTER == "litellm"`, route `https://router.${DOMAIN}` to `litellm:4000`.
    *   If `$LLM_ROUTER == "bifrost"`, route `https://router.${DOMAIN}` to `bifrost:8000`.
*   Inject the necessary baseline configuration files for Bifrost into `/mnt/data/${TENANT_ID}/configs/bifrost/` based on Bifrost's documentation (e.g., config.yaml or SQLite db initialization).

#### 5. Update `README.md`
*   **Software Stack Section:** Add "Bifrost (LLM Gateway/Router)" as a primary option alongside LiteLLM.
*   **Architecture:** Maintain the existing documentation regarding the Network Stack (Tailscale / 443 internal network) and non-root security posture, but explicitly mention that the system now supports hot-swapping the LLM routing layer.

Please read the current scripts to ensure variables like `${TENANT_ID}`, `${DOMAIN}`, and user/group IDs match the existing codebase perfectly. Implement this cleanly."