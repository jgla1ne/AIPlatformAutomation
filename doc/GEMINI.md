Based on the **Deployment Audit** and the current state of the repository, Windsurf has fallen into the "Sunk Cost Fallacy" of debugging: it is trying to fix networking issues by deleting the database layer (Prisma/Postgres), which only makes the application layer more unstable.

The platform is **90% functional**, but the final 10% is failing due to **Race Conditions** (LiteLLM starting before Postgres) and **Configuration Drift** (Passwords collected but not mapped).

Here is the comprehensive blueprint to fix the stack.

---

### 1. The Core Infrastructure Fix (Reverting the "Bandaid")
**The Problem:** LiteLLM was failing because the Postgres container takes ~10 seconds to initialize its internal file structure, but LiteLLM tries to run Prisma migrations in ~2 seconds.
**The Solution:**
*   **Re-enable Postgres:** Restore the `postgres` service in `docker-compose.yml`.
*   **Use the Database Image:** LiteLLM must use `ghcr.io/berriai/litellm-database:main-latest`.
*   **Implement a Healthcheck:** Do not rely on `depends_on` alone. Use a proper healthcheck in `docker-compose.yml`:
    ```yaml
    postgres:
      healthcheck:
        test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
        interval: 5s
        timeout: 5s
        retries: 5
    litellm:
      depends_on:
        postgres:
          condition: service_healthy
    ```

### 2. Password & Variable Synchronization
**The Problem:** The Audit shows `CODEBASE_PASSWORD` is empty. Script 1 collects a password but doesn't map it to all services.
**The Solution (Modify Script 1):**
Ensure the input variable is explicitly written to all required fields in the `.env`:
```bash
# In 1-setup-system.sh
read -sp "Set the Master Admin Password: " MASTER_PASS
sed -i "s/^CODEBASE_PASSWORD=.*/CODEBASE_PASSWORD=$MASTER_PASS/" .env
sed -i "s/^OPENCLAW_PASSWORD=.*/OPENCLAW_PASSWORD=$MASTER_PASS/" .env
sed -i "s/^ANYTHINGLLM_PASSWORD=.*/ANYTHINGLLM_PASSWORD=$MASTER_PASS/" .env
```

### 3. Nginx Proxy & Routing (OpenClaw vs. CodeServer)
**The Problem:** `openclaw.ai.datasquiz.net` is resolving to CodeServer. This happens because Nginx uses the first "default_server" or a wildcard when a specific match isn't found.
**The Solution:**
*   **Specific Server Blocks:** In the Nginx config, create distinct files in `/etc/nginx/conf.d/` for each subdomain.
*   **OpenClaw Fix:** Ensure the `server_name` is exactly `openclaw.ai.datasquiz.net` and the `proxy_pass` points to `http://openclaw:18789`.
*   **CodeServer Fix:** Ensure its block is restricted to `codeserver.ai.datasquiz.net`.
*   **SSL Protocol Error:** This occurs because Nginx is listening on 443 but the `ssl_certificate` paths are likely invalid or pointing to empty files. Mount the Tailscale cert directory: `/var/lib/tailscale/certs:/etc/nginx/certs:ro`.

### 4. Rclone and the "Ingestion Gap"
**The Problem:** Rclone isn't active, and Script 3 isn't triggering the Qdrant ingestion of synced Google Drive data.
**The Solution:**
*   **Mount as a Service:** Instead of a one-time sync, run Rclone in Docker with the `--vfs-cache-mode writes` flag.
*   **The Ingestion Script (Add to Script 3):**
    Windsurf needs to add a logic block that uses AnythingLLM’s API to "fetch" files from the mounted GDrive folder.
    ```bash
    # Logical snippet for Script 3
    curl -X POST "http://anythingllm:3001/api/v1/document/upload" \
         -H "Authorization: Bearer ${ANYTHING_LLM_API_KEY}" \
         -F "file=@/data/gdrive/synced_doc.pdf"
    ```

### 5. Signal-API 404 Fix
**The Problem:** `/v1/qrcodelink` fails because the container hasn't started a "session" yet.
**The Solution:**
In `3-configure-services.sh`, Windsurf must add a "wait and initialize" step:
1. `curl -X POST http://signal-api:8080/v1/devices/registration`
2. Only *after* this call will the `/v1/qrcodelink` endpoint return a valid 200 OK image.

---

### Comprehensive Summary for Windsurf

| Service | Status | Required Action |
| :--- | :--- | :--- |
| **LiteLLM** | Broken | Revert to `litellm-database` image; link to Postgres with `service_healthy`. |
| **Postgres** | Missing | Re-add to stack; essential for LiteLLM persistence. |
| **OpenClaw** | Misrouted | Update Nginx `server_name` to prevent CodeServer collision. |
| **Passwords**| Broken | Sync `MASTER_PASS` to `CODEBASE_PASSWORD` in `.env`. |
| **Flowise** | 502 | Increase `proxy_read_timeout` to 300s in Nginx. |
| **Rclone** | Inactive | Change from script-based sync to a persistent Docker mount. |
| **Ingestion** | Missing | Add API call in Script 3 to push `/mnt/gdrive` files to Qdrant/AnythingLLM. |

**Final Recommendation:**
Stop the "Cleanup" loop. Tell Windsurf to **manually update the `.env` and `docker-compose.yml`** using the structures above. The issues are not with the code logic, but with the **timing and dependencies** between services. Once LiteLLM has a stable DB and the Proxy has specific server blocks, the 502 and SSL errors will vanish.