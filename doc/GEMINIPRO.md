This is a classic issue when pivoting a core architecture component using AI: it often leaves "ghosts" of the old system (hardcoded ports, lingering environment variables, and stale reverse proxy routes) that silently break the networking stack. 

Since LiteLLM is now **completely removed** (not even an option in Script 1), we need to instruct Windsurf to do a **ruthless search-and-destroy for "litellm"** and properly wire the HTTPS proxy and OpenWebUI to Bifrost. 

Here is the definitive, bulletproof prompt to paste into **Windsurf**. It leaves no room for AI hallucinations or band-aids.

***

### 🤖 Prompt for Windsurf:

"Windsurf, we are completely excising LiteLLM from the codebase and standardizing strictly on **Bifrost** as our sole LLM router. Your previous attempts left band-aids, hardcoded LiteLLM references, and broken HTTPS/Caddy configurations. 

I need you to perform a **comprehensive, structural refactor** across the 4 scripts and the README. Follow these exact directives step-by-step. Do not skip any files.

#### 1. RUTHLESS PURGE OF LITELLM (All Scripts)
Search the entire codebase (case-insensitive) for `litellm` and `4000`. 
*   **Remove** any remaining `init_litellm` functions.
*   **Remove** any user prompts asking to choose between LiteLLM and Bifrost in `1-setup-system.sh`. Bifrost is now the mandatory, hardcoded standard.
*   **Remove** all LiteLLM cleanup references in `0-complete-cleanup.sh`.

#### 2. FIX `0-complete-cleanup.sh`
Ensure Bifrost is fully integrated into the teardown process.
*   Add `ai-${TENANT_ID}-bifrost-1` to the container removal list.
*   Add `/mnt/data/${TENANT_ID}/bifrost` and `/mnt/data/${TENANT_ID}/configs/bifrost` to the directory removal list.

#### 3. FIX `1-setup-system.sh` (Mission Control)
*   Ensure `init_bifrost` is called automatically.
*   Ensure directories are created securely with non-root ownership:
    ```bash
    mkdir -p "/mnt/data/${TENANT_ID}/configs/bifrost"
    chown -R ${TENANT_UID}:${TENANT_GID} "/mnt/data/${TENANT_ID}/configs/bifrost"
    ```
*   Update the success dashboard at the end of the script to show `LLM Router: Bifrost` instead of LiteLLM.

#### 4. FIX `2-deploy-services.sh` (The Core Integration)
This is where the network stack is breaking. Make these precise changes to the `docker-compose.yml` generation:
*   **Bifrost Service:** Define the Bifrost service correctly.
    ```yaml
      bifrost:
        image: ghcr.io/ruqqq/bifrost:latest
        container_name: ai-${TENANT_ID}-bifrost-1
        restart: unless-stopped
        user: "${TENANT_UID:-1000}:${TENANT_GID:-1000}"
        ports:
          - "8000:8000" # Bifrost port
        volumes:
          - /mnt/data/${TENANT_ID}/configs/bifrost:/app/data
        environment:
          - BIFROST_HOST=0.0.0.0
        networks:
          - default
    ```
*   **OpenWebUI Integration (CRITICAL):** OpenWebUI must point to Bifrost, not LiteLLM. Update the `open-webui` environment variables:
    Change `OPENAI_API_BASE_URL=http://litellm:4000` to `OPENAI_API_BASE_URL=http://bifrost:8000/v1`
*   **Caddy Service:** Ensure `caddy` exposes ports `80:80` and `443:443`. Ensure both `caddy` and `open-webui` have `depends_on: - bifrost` (remove any `litellm` dependencies).

#### 5. FIX `3-configure-services.sh` (Caddy HTTPS Stack)
Your previous Caddy configurations failed because of invalid directives and old LiteLLM routes. Generate the Caddyfile exactly like this:
*   **NO** `tls internal`
*   **NO** `auto_https off`
*   **NO** `header_read_timeout`
*   **Change the subdomain:** Route `https://bifrost.${DOMAIN}` (or `router.${DOMAIN}`) to `reverse_proxy bifrost:8000`.

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

#### 6. FIX `README.md`
*   Remove all mentions of LiteLLM in the Architecture, Software Stack, and Troubleshooting sections.
*   Replace them with Bifrost. Ensure the documentation reflects that Bifrost is the permanent, stable LLM gateway for the platform.

Review all 4 scripts before modifying to ensure you are not leaving any disconnected variables. Execute these changes now."