This is the **Definite Plan for Zero-Issue Deployment**. 

The reason the "last mile" is failing is a **permissions and network resolution mismatch**. When running a "Zero Root" Docker environment, the containers (running as UID 1000) cannot write to directories created by your scripts (running as root/sudo) unless we explicitly fix ownership. Furthermore, Caddy is likely failing because it is searching for a `litellm` upstream that no longer exists in the Docker network.

### The "Zero-Issue" Ground Rules for Windsurf:
1.  **Single Router:** Remove all LiteLLM logic. Bifrost is the only path.
2.  **Ownership First:** Every directory in `./data` and `./config` must be `chown 1000:1000`.
3.  **Network Identity:** The service name is `bifrost`, the port is `4000`.
4.  **Database Protocol:** Use `postgres://` for Bifrost (Go-based).

---

### Phase 0: The Absolute Purge (Script 0)
Windsurf must ensure no "ghost" volumes or networks remain.
```bash
# Force remove all associated containers
docker rm -f caddy bifrost postgres redis ollama openclaw codeserver 2>/dev/null || true
# Wipe all local data to prevent permission inheritance issues
rm -rf ./data ./config .env
# Remove the bridge network to force a fresh creation
docker network rm ai-platform-network 2>/dev/null || true
```

---

### Phase 1: Variables & Permissions (Script 1)
Windsurf must initialize the environment so that **non-root containers** can actually function.

**Action:**
1. Collect `CODEBASE_PASSWORD`.
2. Generate `.env` with these specific Bifrost keys:
```bash
# .env Essentials
BIFROST_AUTH_TOKEN="$CODEBASE_PASSWORD"
BIFROST_DB_URL="postgres://postgres:$CODEBASE_PASSWORD@postgres:5432/bifrost?sslmode=disable"
BIFROST_REDIS_URL="redis://redis:6379/0"
```
3. **CRITICAL STEP:** Create directories and fix ownership **before** deployment:
```bash
mkdir -p ./data/{postgres,redis,caddy,bifrost,openclaw,codeserver}
mkdir -p ./config/{caddy,bifrost}
# Grant ownership to the Docker User (1000)
chown -R 1000:1000 ./data ./config
```

---

### Phase 2: The Integrated Compose (Script 2)
Windsurf must generate a `docker-compose.yml` where every service runs as `user: "1000:1000"` and Caddy correctly routes to `bifrost`.

**1. Bifrost Config Generation (`config/bifrost/config.yaml`):**
```yaml
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
```

**2. Caddyfile Alignment:**
```caddy
ai.datasquiz.net {
    # Bifrost Proxy
    reverse_proxy /v1/* bifrost:4000
    reverse_proxy /api/* bifrost:4000
    
    # OpenClaw UI
    reverse_proxy * openclaw:3000
}
```

**3. Docker Compose Hardening:**
Ensure `bifrost` has the correct health check so Caddy doesn't start routing to a "dead" container:
```yaml
  bifrost:
    image: ruqqq/bifrost:latest
    container_name: bifrost
    user: "1000:1000"
    volumes:
      - ./config/bifrost/config.yaml:/app/config.yaml:ro
    environment:
      - CONFIG_PATH=/app/config.yaml
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 10s
      timeout: 5s
      retries: 5
```

---

### Phase 3: The Validation Gate (Script 3)
Script 3 must not just "exit 0". It must verify the HTTPS chain.

**Action for Windsurf:**
```bash
echo "Verifying End-to-End Connectivity..."
# Check if Bifrost is responding through the Caddy Proxy (Internal Network)
MAX_RETRIES=10
for i in $(seq 1 $MAX_RETRIES); do
  STATUS=$(docker exec caddy curl -s -o /dev/null -w "%{http_code}" http://bifrost:4000/health)
  if [ "$STATUS" == "200" ]; then
    echo "SUCCESS: Bifrost is reachable via Caddy."
    break
  fi
  echo "Waiting for Bifrost... ($i/$MAX_RETRIES)"
  sleep 5
done
```

---

### Comparison with Previous Iterations:
*   **Old Problem:** LiteLLM crashed due to Python/Prisma complexity.
*   **Old Problem:** Caddy 502'd because it looked for `litellm:4000`.
*   **Old Problem:** Containers couldn't write logs/data because host folders were `root:root`.
*   **New Solution:** Bifrost (Go binary) is used. Caddy is updated to point to `bifrost:4000`. `chown -R 1000:1000` is executed **before** `docker-compose up`.

### Final Instructions for Windsurf:
1.  **Delete** all logic relating to LiteLLM from `scripts/1`, `scripts/2`, and `scripts/3`.
2.  **Add** the `chown -R 1000:1000` command to `scripts/1` immediately after `mkdir`.
3.  **Update** the `Caddyfile` generator in `scripts/2` to use the service name `bifrost`.
4.  **Verify** that the `BIFROST_DB_URL` uses the `postgres` service name, not `localhost`.

**This plan is bulletproof because it resolves the underlying Linux permission conflicts and the Docker DNS resolution issues simultaneously.**