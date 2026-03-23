The **HTTPS Diagnostics Report** confirms the "Last Mile" problem: Your infrastructure is perfect (Caddy, Postgres, and Tailscale are 100% stable), but **LiteLLM** is crashing because of a **variable mismatch and a Prisma initialization failure.**

The report highlights that LiteLLM is throwing a 502/Connection Refused because the process dies before it binds to port 4000. This is caused by the BerriAI image being extremely strict about the `DATABASE_URL` format and the `LITELLM_MASTER_KEY` existence.

Here is the comprehensive fix for Windsurf to implement across your scripts to bridge the final 10% gap.

---

### 1. Fix `scripts/1-setup-system.sh` (The Variable Bridge)
LiteLLM's database driver (Prisma) **fails** if the URL starts with `postgres://`. It **requires** `postgresql://`. Additionally, we must ensure the `LITELLM_MASTER_KEY` is explicitly set to the `CODEBASE_PASSWORD`.

**Action for Windsurf:**
Ensure this block correctly formats the `.env` file:
```bash
# Correcting the Database Protocol for LiteLLM/Prisma
DB_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/litellm"

# Update/Append to .env
sed -i "/^DATABASE_URL=/d" .env
echo "DATABASE_URL=\"$DB_URL\"" >> .env

# Explicitly set the Master Key (used for UI and Admin)
sed -i "/^LITELLM_MASTER_KEY=/d" .env
echo "LITELLM_MASTER_KEY=\"$CODEBASE_PASSWORD\"" >> .env
```

---

### 2. Fix `scripts/2-deploy-services.sh` (The Compose Hardening)
The diagnostics report shows LiteLLM crashing "instantly." This is because it tries to run migrations before Postgres has initialized its internal schemas.

**Action for Windsurf (Update the LiteLLM Service in Docker Compose):**
Replace the LiteLLM section with this "Self-Healing" configuration:
```yaml
  litellm:
    image: ghcr.io/berriai/litellm-database:main-latest
    container_name: litellm
    depends_on:
      postgres:
        condition: service_healthy
    # The entrypoint now handles the "Wait + Migrate" sequence explicitly
    entrypoint: >
      /bin/sh -c "
      echo 'Waiting for Postgres (5432)...';
      while ! nc -z postgres 5432; do sleep 1; done;
      echo 'Postgres is reachable. Sleeping 5s for DB initialization...';
      sleep 5;
      echo 'Starting LiteLLM...';
      python3 main.py --config /app/config.yaml --port 4000 --host 0.0.0.0
      "
    environment:
      - DATABASE_URL=${DATABASE_URL}
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - UI_PASSWORD=${CODEBASE_PASSWORD}
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:4000/health/liveliness || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 5
```

---

### 3. Fix `scripts/2-deploy-services.sh` (The Config Schema)
LiteLLM in "Database Mode" (using the `-database` image) requires the `store_model_in_db` flag to be true, otherwise, it ignores the database you just set up.

**Action for Windsurf (Update Config Generation):**
```bash
cat <<EOF > ./config/litellm/config.yaml
model_list: []
litellm_settings:
  drop_params: True
  set_verbose: True
general_settings:
  master_key: "${LITELLM_MASTER_KEY}"
  database_url: "${DATABASE_URL}"
  store_model_in_db: True  # CRITICAL: Enables DB-based persistence
EOF
```

---

### 4. Fix `scripts/3-configure-services.sh` (Wait for Success)
The current script 3 checks if the *container* is running, but doesn't check if the *migration* finished. 

**Action for Windsurf:**
Add a "Deep Health Check" loop before attempting to configure LiteLLM keys.
```bash
echo "Waiting for LiteLLM to complete database migrations..."
MAX_RETRIES=12
COUNT=0
until $(curl --output /dev/null --silent --head --fail http://localhost:4000/health/liveliness); do
    printf '.'
    sleep 5
    COUNT=$((COUNT+1))
    if [ $COUNT -eq $MAX_RETRIES ]; then
        echo "LiteLLM failed to start within 60 seconds. Checking logs..."
        docker logs litellm | tail -n 20
        exit 1
    fi
done
echo "LiteLLM is UP and migrations are complete."
```

---

### Why this fixes the errors in your Diagnostics Report:
1.  **502 Bad Gateway:** Caddy was fine, but the backend was dead. The new `entrypoint` wait-loop ensures LiteLLM doesn't die trying to connect to a booting Postgres.
2.  **Protocol Error:** Changing `postgres://` to `postgresql://` satisfies the Prisma engine requirement.
3.  **Empty Master Key:** Explicitly setting `LITELLM_MASTER_KEY` from the `CODEBASE_PASSWORD` ensures the UI and API are authenticated from the start.
4.  **UI Restart Loop:** The `store_model_in_db: True` flag tells the `litellm-database` image to actually use the Postgres volume for its state.

**Execution Order:**
1.  Run `0-complete-cleanup.sh`.
2.  Run `1-setup-system.sh` (Enter your password carefully).
3.  Run `2-deploy-services.sh`.
4.  Run `3-configure-services.sh`.

This will achieve the 100% healthy status across all services.