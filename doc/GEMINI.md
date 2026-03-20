This blueprint identifies the "Iterative Patching Loop" Windsurf has fallen into and provides the structural corrections needed to move from a collection of containers to a unified AI platform.

### 1. Restore the LiteLLM Core (Postgres + Prisma)
LiteLLM is the gateway for your entire stack. Running it in "lite" mode (without a DB) means AnythingLLM and OpenWebUI lose their connection every time the container restarts because API keys aren't persistent.

*   **The Blueprint:** 
    *   **Image Switch:** Use `ghcr.io/berriai/litellm-database:main-latest` instead of the standard image. This image contains the Prisma engine required for database migrations.
    *   **Orchestration Logic:** In `docker-compose.yml`, LiteLLM must have a `depends_on` block with a `service_healthy` condition for Postgres.
    *   **Connection String:** Pass `DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/litellm` explicitly.
    *   **The "Wait" Fix:** Add a `command` wrapper: `sh -c "/app/wait-for-it.sh postgres:5432 -- python3 main.py --config /app/config.yaml"`. This prevents LiteLLM from crashing while Postgres is still performing its initial internal disk setup.

### 2. Resolution of SSL/502 Errors & Proxy Routing
The SSL errors and the OpenClaw-to-CodeServer routing conflict stem from a collision in the Nginx/Reverse Proxy configuration.

*   **The Conflict:** OpenClaw (18789) and CodeServer (8443/8080) are likely sharing a "catch-all" block or have overlapping `server_name` definitions.
*   **The Blueprint:**
    *   **Explicit Host Headers:** In the Nginx config, ensure `openclaw.ai.datasquiz.net` is a dedicated `server {}` block that proxies to `http://openclaw:18789`. 
    *   **CodeServer Isolation:** Ensure CodeServer is explicitly bound to `codeserver.ai.datasquiz.net`.
    *   **SSL Pathing:** The "SSL Protocol Error" usually means Nginx is trying to serve HTTPS but can't find the Tailscale certificates. Script 1 must verify the certs are in `/etc/ssl/certs/tailscale/` and Script 2 must mount that *entire* directory into the Nginx container as a read-only volume.
    *   **Upstream 502s:** Flowise and OpenWebUI take 60-90 seconds to start. Nginx times out. Add `proxy_read_timeout 300;` and `proxy_connect_timeout 300;` to the proxy config.

### 3. Password Synchronization & `.env` Validation
Windsurf has a variable mismatch. It collects an "OpenClaw Password" but fails to map it to `CODEBASE_PASSWORD`, leaving CodeServer unauthenticated or unreachable.

*   **The Blueprint:**
    *   **Script 1 Update:** Modify the variable collection to be explicit: `read -p "Enter Platform Admin Password: " ADMIN_PASS`.
    *   **Universal Mapping:** In `.env`, map this single variable to all services requiring it:
        ```bash
        OPENCLAW_PASSWORD=$ADMIN_PASS
        CODEBASE_PASSWORD=$ADMIN_PASS
        ANYTHINGLLM_PASSWORD=$ADMIN_PASS
        ```
    *   **Script 3 Verification:** Add a check to `3-configure-services.sh` that fails if any password variable in `.env` is empty.

### 4. Rclone Active Sync & Qdrant Ingestion
Rclone is currently behaving like a one-time copy tool rather than a file stream.

*   **The Blueprint:**
    *   **Rclone as a Service:** Add an `rclone` service to `docker-compose.yml` using the `--vfs-cache-mode writes` and `--poll-interval 1m` flags. This mounts your GDrive as a local volume that "lives" and updates.
    *   **The Ingestion Trigger:** Create a small Python bridge (or use AnythingLLM's API) in `3-configure-services.sh`.
    *   **Logic:** `If /mnt/gdrive/ingest contains new files -> Trigger AnythingLLM/Qdrant Vectorization`. This fulfills the README's goal of shared embeddings.

### 5. Signal-API QR Code Fix
The 404 on `/v1/qrcodelink` happens because the Signal-API container hasn't "provisioned" a link to the underlying `signal-cli`.

*   **The Blueprint:**
    *   **Environment Check:** Ensure `SIGNAL_API_TELEMETRY=true` and `SIGNAL_API_MODE=normal` are set.
    *   **Initialization:** Script 3 should execute a `curl -X POST` to initialize the device *before* attempting to retrieve the QR link.

### Summary Checklist for Windsurf's Final Iteration:
1.  **Revert:** Put Postgres back and use the `litellm-database` image.
2.  **Network:** Use container names (not IPs) for internal proxying.
3.  **Volume Mapping:** Mount the Tailscale certs directory directly into Nginx.
4.  **Wait Logic:** Implement health-checks in Compose so services don't try to connect to LiteLLM before it is ready.
5.  **Passwords:** Ensure `CODEBASE_PASSWORD` is populated in `.env` during Script 1.

**Why Windsurf failed for 40 hours:** It was trying to fix *connectivity* by removing *dependencies* (Prisma). In a complex stack, you fix connectivity by **strengthening** dependencies with healthchecks and proper wait-times. Moving Prisma back in with a `wait-for-it` script will resolve the 502/SSL domino effect.