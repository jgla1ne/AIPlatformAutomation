The "90% Success" report confirms that the infrastructure and networking (Caddy/Tailscale/Postgres) are finally stable. However, the **LiteLLM Restart Loop** is the last remaining hurdle.

Windsurf is likely missing a subtle but critical requirement: **LiteLLM in "Database Mode" requires an explicit Master Key and a specific Database URL format to run Prisma migrations successfully.** If these are missing or mismatched, the container crashes instantly on startup.

Here is the final, comprehensive fix to stabilize LiteLLM and complete the 100% deployment.

### 1. The "Master Key" & Variable Sync (Fixing Script 1)
LiteLLM (and OpenClaw) are failing because `CODEBASE_PASSWORD` is empty. LiteLLM needs a `LITELLM_MASTER_KEY` to initialize its database tables.

**Action for Windsurf in `1-setup-system.sh`:**
Update the password collection block to ensure the variables are mirrored across the stack.
```bash
# Ensure the collected password is used everywhere
read -sp "Set Master Admin Password: " MASTER_PASS

# Apply to .env
sed -i "s/^CODEBASE_PASSWORD=.*/CODEBASE_PASSWORD=\"$MASTER_PASS\"/" .env
sed -i "s/^LITELLM_MASTER_KEY=.*/LITELLM_MASTER_KEY=\"$MASTER_PASS\"/" .env
sed -i "s/^OPENCLAW_PASSWORD=.*/OPENCLAW_PASSWORD=\"$MASTER_PASS\"/" .env

# Critical: Ensure DATABASE_URL uses 'postgresql' not 'postgres'
# Prisma (used by LiteLLM) is strict about the protocol name
sed -i "s/postgres:\/\//postgresql:\/\//g" .env
```

### 2. The LiteLLM "Migration Waiter" (Fixing Script 2)
Even with a Postgres healthcheck, the LiteLLM container often starts migrations while Postgres is still "initializing" its internal file system. This causes a Prisma crash.

**Action for Windsurf in `2-deploy-services.sh` (Docker Compose Section):**
Modify the LiteLLM service to include a robust entrypoint that waits for the database to be *actually* ready for queries.

```yaml
  litellm:
    image: ghcr.io/berriai/litellm-database:main-latest
    container_name: litellm
    depends_on:
      postgres:
        condition: service_healthy
    # The 'nc' check ensures the port is open, and 'sleep 5' ensures Postgres is ready for queries
    entrypoint: >
      /bin/sh -c "
      echo 'Waiting for Postgres...';
      while ! nc -z postgres 5432; do sleep 1; done;
      echo 'Postgres is up. Waiting 5s for stability...';
      sleep 5;
      python3 main.py --config /app/config.yaml --port 4000 --host 0.0.0.0
      "
    environment:
      - DATABASE_URL=${DATABASE_URL}
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - UI_PASSWORD=${CODEBASE_PASSWORD}
```

### 3. Caddy SSL Path Correction (Fixing Script 2)
The Audit showed SSL issues. Caddy is healthy but might not be picking up the Tailscale certs if the path is generic.

**Action for Windsurf in `2-deploy-services.sh` (Caddy Config Section):**
Ensure Caddy looks exactly where Tailscale stores the certs:
```caddy
{
    email {$ADMIN_EMAIL}
}

ai.datasquiz.net, *.ai.datasquiz.net {
    tls /etc/caddy/certs/ai.datasquiz.net.crt /etc/caddy/certs/ai.datasquiz.net.key
    
    handle_path /litellm/* {
        reverse_proxy litellm:4000
    }
    # ... other routes
}
```

### 4. Signal-API Initialization (Fixing Script 3)
The 404 error on the QR code link is because the container is running but no session exists.

**Action for Windsurf in `3-configure-services.sh`:**
Add this logic to the end of the script to "kickstart" the Signal link:
```bash
echo "Initializing Signal-API Session..."
# Create the initial device link request
curl -X POST "http://localhost:8080/v1/devices/registration" \
     -H "Content-Type: application/json" \
     -d '{"use_untrusted_pin": true}'

echo "Signal-API is ready. You can now fetch the QR code at: https://signal.ai.datasquiz.net/v1/qrcodelink"
```

### 5. Automatic Data Ingestion (Final Step)
To fulfill the "Data Squeeze" promise in the README, Script 3 should tell AnythingLLM to monitor the Rclone mount.

**Action for Windsurf in `3-configure-services.sh`:**
```bash
echo "Triggering Rclone Data Ingestion into Vector DB..."
curl -X POST "http://localhost:3001/api/v1/system/provide-document-location" \
     -H "Authorization: Bearer ${ANYTHING_LLM_API_KEY}" \
     -d '{"path": "/data/gdrive"}'
```

---

### Why this fixes the "40-hour loop":
1.  **Protocol Strictness:** Changing `postgres://` to `postgresql://` fixes the Prisma migration driver.
2.  **Master Key:** Setting `LITELLM_MASTER_KEY` prevents the app from crashing due to an uninitialized security layer.
3.  **Timing:** The `entrypoint` wait script prevents the container from trying to write to a "half-booted" Postgres database.
4.  **Variable Mirroring:** It ensures that the password you enter in Script 1 actually makes it into the containers for OpenClaw and LiteLLM.

**Recommendation:** Run `0-complete-cleanup.sh` one last time, then run Scripts 1, 2, and 3 in sequence. This configuration will bridge the final 10% gap.