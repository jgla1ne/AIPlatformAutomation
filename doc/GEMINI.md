Here is the **Zero-Assumption, Framework-Tested Master Execution Plan** to paste directly into Windsurf. This prompt forces the AI to validate every single architectural constraint against your North Star `README.md` *before* modifying code, ensuring the output works on the first run.

***

### 🤖 COPY AND PASTE THIS EXACT PROMPT INTO WINDSURF:

"Windsurf, act as Lead Platform Architect. We have a new North Star: the `README.md`. We are executing a 100% rigorous, zero-assumption alignment of our deployment scripts (`0-complete-cleanup.sh`, `1-setup-system.sh`, `2-deploy-services.sh`, `3-configure-services.sh`).

**CORE PRINCIPLES (NON-NEGOTIABLE):**
1. **Zero Root:** All runtime execution and mounted volumes MUST be owned by `${TENANT_UID}:${TENANT_GID}`. No container runs as root.
2. **Zero Hardcoded Values:** Every domain, port, and credential MUST flow from the Mission Control `.env` file.
3. **100% Dockerized & /mnt Contained:** Everything lives in `/mnt/data/${TENANT_ID}`.
4. **Internal Network Security:** Services (Bifrost, OpenWebUI) communicate exclusively via internal Docker DNS. Only Caddy exposes ports (80/443).

You are to rewrite the 4 scripts to flawlessly implement **Bifrost (`maximhq/bifrost:latest`)** as our LLM Gateway. Execute the following framework-tested plan:

#### STEP 1: SCRIPT 0 (`0-complete-cleanup.sh`) - Absolute Idempotency
*   **Audit & Purge:** Recursively search and destroy any lingering mentions of `litellm` or hardcoded `4000` ports.
*   **Target Definitions:** Ensure `ai-${TENANT_ID}-bifrost-1` is in the container array. Add `/mnt/data/${TENANT_ID}/data/bifrost` to the directory wipe array.

#### STEP 2: SCRIPT 1 (`1-setup-system.sh`) - Pre-Emptive State Management
*   **Mission Control Validation:** Ensure the `.env` generation includes `BIFROST_PORT="8000"`.
*   **Strict UID/GID Enforcement:** Rewrite `init_bifrost()` to create `/mnt/data/${TENANT_ID}/data/bifrost` and execute `chown -R ${TENANT_UID}:${TENANT_GID}` **before** Docker starts. This prevents SQLite permission crashes.

#### STEP 3: SCRIPT 2 (`2-deploy-services.sh`) - The Immutable Compose File
*   **Bifrost Integration:** 
    *   Image: `maximhq/bifrost:latest`
    *   User: `"${TENANT_UID:-1000}:${TENANT_GID:-1000}"`
    *   Volumes: `/mnt/data/${TENANT_ID}/data/bifrost:/app/data`
    *   Ports: `"${BIFROST_PORT:-8000}:8080"` (Internal application port for maximhq is 8080).
*   **OpenWebUI Alignment:** 
    *   Set `OPENAI_API_BASE_URL=http://bifrost:8080/v1` (Using Docker internal DNS, bypassing the host).
    *   Ensure `depends_on: - bifrost` is set.

#### STEP 4: SCRIPT 3 (`3-configure-services.sh`) - Bulletproof Routing
*   **Dynamic Caddyfile:** Generate the reverse proxy configurations strictly using variables.
```text
https://router.${DOMAIN} {
    reverse_proxy bifrost:8080
}
https://chat.${DOMAIN} {
    reverse_proxy open-webui:8080
}
```
*   **Zero Assumption Check:** Ensure Caddy reloads via: `docker exec ai-${TENANT_ID}-caddy-1 caddy reload --config /etc/caddy/Caddyfile`

**Execution Mandate:** Do not hallucinate external tools. Do not skip directory ownership steps. Review your generated code against the Core Principles before finalizing the output. Execute the updates now."