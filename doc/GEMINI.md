The "40-hour loop" Windsurf is trapped in is a result of **Architectural Regression**: it is deleting infrastructure (Postgres/Prisma) to fix application errors (LiteLLM startup failures). This causes a domino effect where dependent services (AnythingLLM, OpenWebUI) can't authenticate or persist data, leading to the 502/SSL errors seen in your Service Analysis.

Here is the comprehensive blueprint to finalize the stack and move past the "90% complete" hurdle.

---

### 1. Restore the LiteLLM Core (Postgres + Prisma)
LiteLLM requires the database to store keys and configurations. Removing it was the primary error.

*   **The Blueprint for Windsurf:** 
    *   **Image Change:** Update `2-deploy-services.sh` to use `ghcr.io/berriai/litellm-database:main-latest`.
    *   **Health Dependency:** In the Docker Compose section of Script 2, LiteLLM **must** wait for Postgres to be `healthy`.
    *   **The Wait Script:** LiteLLM often tries to run Prisma migrations before Postgres is ready to accept connections. Add a `command` to the LiteLLM service:
        ```yaml
        command: ["/bin/sh", "-c", "until nc -z postgres 5432; do echo 'Waiting for postgres...'; sleep 1; done; python3 main.py --config /app/config.yaml"]
        ```
    *   **Prisma Fix:** Ensure `DATABASE_URL` in `.env` includes the DB name (e.g., `postgresql://user:pass@postgres:5432/litellm`).

### 2. Password Synchronization & `.env` Validation
The Audit shows `CODEBASE_PASSWORD` is empty, causing CodeServer/OpenClaw confusion.

*   **The Blueprint for Windsurf:**
    *   **Update Script 1:** Modify the password collection block to be explicit.
    ```bash
    # Ensure ONE password variable is used for the "Master Admin" role
    read -sp "Enter Platform Admin Password: " MASTER_PASS
    # Apply to all relevant variables in .env
    sed -i "s/CODEBASE_PASSWORD=.*/CODEBASE_PASSWORD=$MASTER_PASS/" .env
    sed -i "s/OPENCLAW_PASSWORD=.*/OPENCLAW_PASSWORD=$MASTER_PASS/" .env
    sed -i "s/ANYTHINGLLM_PASSWORD=.*/ANYTHINGLLM_PASSWORD=$MASTER_PASS/" .env
    ```

### 3. Nginx Proxy & SSL Routing Fix
The "OpenClaw to CodeServer" redirect and SSL errors mean Nginx is defaulting to the first available server block because it cannot match the hostname or find the certificates.

*   **The Blueprint for Windsurf:**
    *   **Strict Host Matching:** Ensure each service has its own `server_name` in the Nginx config (e.g., `server_name openclaw.ai.datasquiz.net;`).
    *   **SSL Pathing:** Mount the Tailscale certificates directory directly into Nginx:
        *   Host: `/var/lib/tailscale/certs`
        *   Container: `/etc/nginx/certs:ro`
    *   **502 Timeouts:** Dify and Flowise are heavy. Add these to the Nginx `location` blocks:
        ```nginx
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        ```

### 4. Rclone Active Sync & Ingestion Logic (Script 3)
Rclone is currently treated as a one-off command. It needs to be a persistent background sync to fulfill the "Data Squeeze" goal.

*   **The Blueprint for Windsurf:**
    *   **Rclone Service:** Move Rclone into `docker-compose.yml` as a service using the `--vfs-cache-mode writes` and `--poll-interval 1m` flags.
    *   **The Ingestion Trigger (Script 3):** This is the "missing link." Script 3 must tell AnythingLLM to ingest the folder Rclone is syncing.
    ```bash
    # Logic for Script 3 to trigger Qdrant ingestion
    echo "Triggering Vector Ingestion..."
    curl -X POST "http://anythingllm:3001/api/v1/system/provide-document-location" \
         -H "Authorization: Bearer ${ANYTHING_LLM_API_KEY}" \
         -d '{"path": "/data/gdrive"}'
    ```

### 5. Signal-API QR Link (404 Fix)
The 404 occurs because the Signal-API has not initialized a session for the device.

*   **The Blueprint for Windsurf:**
    *   **Initialization:** In Script 3, before trying to get the QR code, trigger the link process:
    ```bash
    curl -X POST "http://signal-api:8080/v1/devices/registration" -d '{"use_untrusted_pin": true}'
    ```

---

### Summary Checklist for Windsurf's Final Implementation:

1.  **Script 1 (Setup):** Ensure `CODEBASE_PASSWORD` is written to `.env`.
2.  **Script 2 (Deploy):** 
    *   Re-introduce Postgres.
    *   Change LiteLLM image to `litellm-database`.
    *   Add `healthcheck` to Postgres and `depends_on: condition: service_healthy` to LiteLLM.
    *   Correct Nginx volume mounts for Tailscale certs.
3.  **Script 3 (Configure):**
    *   Initialize Signal-API with a POST request.
    *   Add the `curl` command to trigger AnythingLLM to scrape the Rclone mount and push to Qdrant.
4.  **Networking:** Ensure Nginx configs use internal Docker service names (e.g., `proxy_pass http://openclaw:18789`) rather than Tailscale IPs to avoid routing loops.

**Why this works:** It stops the "reinstall loop" and addresses the **inter-dependency** of the stack. LiteLLM provides the API logic, Postgres provides the memory, and Nginx provides the specific routing path. Without all three properly sequenced, the UIs will continue to throw 502/SSL errors.