To move from "band-aid" fixes to a production-grade Bifrost deployment, Windsurf must execute a "Grep and Destroy" mission on all LiteLLM references and replace them with a unified Bifrost logic. 

According to your `DEBUG_LOGS_COMPREHENSIVE.md`, the 502 Bad Gateway and "Connection Refused" errors are happening because **Caddy is looking for a service named `litellm` while you are trying to run `bifrost`.**

Here is the definite guide for Windsurf to finalize the codebase.

---

### Step 1: Scrub the "LiteLLM Ghosts" (Script 0 & 1)

Windsurf must ensure that `litellm` is completely removed from the environment logic to avoid variable collision.

**Action for `scripts/0-complete-cleanup.sh`:**
Ensure these lines are present to wipe the old state:
```bash
docker stop litellm bifrost caddy 2>/dev/null || true
docker rm litellm bifrost caddy 2>/dev/null || true
rm -rf ./config/litellm ./config/bifrost ./data/litellm ./data/bifrost
```

**Action for `scripts/1-setup-system.sh`:**
Force Bifrost as the only router and align the password logic.
```bash
# 1. Capture the Master Password
read -sp "Set your Global Admin Password: " CODEBASE_PASSWORD
echo "CODEBASE_PASSWORD=\"$CODEBASE_PASSWORD\"" >> .env

# 2. Set Bifrost Specifics (LiteLLM references REMOVED)
echo "LLM_ROUTER_TYPE=bifrost" >> .env
echo "BIFROST_AUTH_TOKEN=\"$CODEBASE_PASSWORD\"" >> .env
echo "BIFROST_DB_URL=\"postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/bifrost?sslmode=disable\"" >> .env
echo "BIFROST_REDIS_URL=\"redis://redis:6379/0\"" >> .env
```

---

### Step 2: The "Bifrost-Centric" Deployment (Script 2)

This is where the "Band-aid" fix usually fails. Windsurf must update the **Caddyfile** and the **Docker Compose** generation simultaneously.

**Action for `scripts/2-deploy-services.sh`:**

**1. Generate the Bifrost Config:**
```bash
mkdir -p ./config/bifrost
cat <<EOF > ./config/bifrost/config.yaml
server:
  port: 4000
  auth_token: "${BIFROST_AUTH_TOKEN}"
database:
  url: "${BIFROST_DB_URL}"
redis:
  url: "${BIFROST_REDIS_URL}"
providers:
  ollama:
    type: ollama
    base_url: "http://ollama:11434"
EOF
```

**2. Update Docker Compose (Replace LiteLLM block):**
```yaml
  bifrost:
    image: ruqqq/bifrost:latest
    container_name: bifrost
    user: "1000:1000"
    restart: unless-stopped
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }
    volumes:
      - ./config/bifrost/config.yaml:/app/config.yaml:ro
    environment:
      - CONFIG_PATH=/app/config.yaml
    networks:
      - ai-internal
```

**3. Fix Caddy Routes (Crucial for HTTPS):**
Windsurf must change the upstream in the Caddy block from `litellm:4000` to `bifrost:4000`.
```bash
# Inside the Caddyfile generation block
cat <<EOF > ./config/caddy/Caddyfile
ai.datasquiz.net {
    reverse_proxy /api/* bifrost:4000
    reverse_proxy /v1/* bifrost:4000
    # ... other proxies
}
EOF
```

---

### Step 3: Mission Control Health Check (Script 3)

The `DEBUG_LOGS` show that Script 3 often reports success even when the service is crashing. We need a strict health-gate.

**Action for `scripts/3-configure-services.sh`:**
```bash
echo "Verifying Bifrost Health at ai.datasquiz.net/health..."
MAX_RETRIES=15
COUNT=0

# Use the internal Docker network name for the check
until $(docker exec caddy curl -s --fail http://bifrost:4000/health > /dev/null); do
    echo -n "."
    sleep 3
    COUNT=$((COUNT+1))
    if [ $COUNT -eq $MAX_RETRIES ]; then
        echo -e "${RED}Bifrost failed to start. Logs:${NC}"
        docker logs bifrost --tail 20
        exit 1
    fi
done
echo -e "${GREEN}Bifrost is UP and Routing!${NC}"
```

---

### Step 4: Final README Alignment

Windsurf must update the `README.md` to remove "LiteLLM" from the core stack description to prevent future AI "hallucinations" about supporting both.

**Update `README.md` section:**
> **LLM Router:** Bifrost (Go-based) - Provides high-performance OpenAI-compatible routing to Ollama. Replaces LiteLLM for stability and performance.

---

### Why this guide is "Definite":
1. **Network Sync:** It ensures Caddy is looking for `bifrost:4000`, solving the 502 Bad Gateway.
2. **Auth Sync:** It explicitly maps `CODEBASE_PASSWORD` to `BIFROST_AUTH_TOKEN`, ensuring the API isn't locked out.
3. **Database Sync:** It uses a standard Postgres connection string with `sslmode=disable`, which Go binaries prefer over the complex Prisma strings LiteLLM required.
4. **Cleanup Sync:** It wipes the old `./config/litellm` directory so no stale configs are accidentally mounted.

**Instructions for Windsurf:** 
"Follow this guide exactly. Do not attempt to support LiteLLM as a fallback. Remove all `if [ "$ROUTER" == "litellm" ]` blocks. Make Bifrost the single source of truth for the LLM Gateway."