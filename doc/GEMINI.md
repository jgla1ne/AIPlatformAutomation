The "Application startup failed, exiting" error in LiteLLM, despite the rest of the stack being healthy, is the "final boss" of this deployment. Based on the logs in `WINDSURF.md.backup` and the current scripts, Windsurf is missing **three specific technical requirements** that Prisma (LiteLLM's database layer) demands.

Here is the comprehensive, minimal-impact solution to fix `2-deploy-services.sh` and `1-setup-system.sh`.

---

### 1. The "Protocol & Key" Fix (Script 1)
LiteLLM's database driver (Prisma) **refuses** to connect if the protocol is `postgres://` (it must be `postgresql://`) or if the `LITELLM_MASTER_KEY` is not explicitly set for the database-backed version.

**Action for Windsurf in `scripts/1-setup-system.sh`:**
Ensure these lines are present to transform the variables correctly:
```bash
# Fix the Postgres URL for Prisma compatibility
DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/litellm"
echo "DATABASE_URL=\"$DATABASE_URL\"" >> .env

# Mirror the Master Password to LiteLLM's specific key
echo "LITELLM_MASTER_KEY=\"$CODEBASE_PASSWORD\"" >> .env
```

---

### 2. The "LiteLLM Survival Block" (Script 2)
The reason LiteLLM fails with "Application startup failed" is a **race condition**. It tries to run database migrations while Postgres is "ready" but not yet "accepting queries." 

**Action for Windsurf in `scripts/2-deploy-services.sh`:**
Replace the current LiteLLM service definition with this **hardened** version. This uses the `ghcr.io/berriai/litellm-database` image and a "wait-for-it" logic that is much more reliable than Docker's default `depends_on`.

```yaml
  litellm:
    image: ghcr.io/berriai/litellm-database:main-latest
    container_name: litellm
    depends_on:
      postgres:
        condition: service_healthy
    # CRITICAL: We must wait for the DB to be fully operational before starting the python app
    entrypoint: >
      /bin/sh -c "
      echo 'Waiting for Postgres...';
      until nc -z postgres 5432; do sleep 1; done;
      echo 'Postgres is up. Performing 5s stability delay...';
      sleep 5;
      python3 main.py --config /app/config.yaml --port 4000 --host 0.0.0.0
      "
    environment:
      DATABASE_URL: ${DATABASE_URL}
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
    volumes:
      - ./config/litellm/config.yaml:/app/config.yaml:ro
    ports:
      - "4000:4000"
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:4000/health/liveliness || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
```

---

### 3. The Config Schema Fix (Script 2)
If `config.yaml` is empty or lacks the `general_settings` block when LiteLLM starts in database mode, it will crash.

**Action for Windsurf in `scripts/2-deploy-services.sh` (Config generation section):**
Ensure the `config.yaml` includes the `store_model_in_db` flag. This is what allows the UI to work.

```bash
cat <<EOF > ./config/litellm/config.yaml
model_list: []
litellm_settings:
  drop_params: True
  set_verbose: True
general_settings:
  master_key: "${LITELLM_MASTER_KEY}"
  database_url: "${DATABASE_URL}"
  store_model_in_db: True  # This is the key for the Database Image
EOF
```

---

### 4. Correcting the Caddy Route (Script 2)
The `WINDSURF.md.backup` shows the UI was 404ing. This is because LiteLLM serves its UI at `/ui`, but your Caddy config might be stripping the path incorrectly.

**Action for Windsurf in `scripts/2-deploy-services.sh` (Caddy Block):**
```caddy
# Use a clear handle for the proxy to avoid path-stripping issues
ai.datasquiz.net {
    handle /litellm/* {
        reverse_proxy litellm:4000
    }
    # Direct UI access
    handle /ui* {
        reverse_proxy litellm:4000
    }
    # ... other services
}
```

---

### Summary of what Windsurf must do to finish:
1.  **Script 1:** Add the `postgresql://` string fix and set `LITELLM_MASTER_KEY`.
2.  **Script 2:** Update the `litellm` service with the `entrypoint` wait-loop and the `store_model_in_db: True` flag in the config.
3.  **Script 3:** Ensure the health check for LiteLLM looks for `http://localhost:4000/health/liveliness`.

**Why this will work:** It addresses the specific failure modes of the BerriAI/LiteLLM database container: (1) Protocol name strictness, (2) Migration timing/race conditions, and (3) Missing DB-persistence flags in the YAML. This will move you from 90% to 100% stable.