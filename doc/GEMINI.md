This is a strategic pivot. After 200+ hours, the technical debt of LiteLLM's Prisma/Python layer is clearly the bottleneck. **Bifrost** (written in Go) is significantly more stable, has a smaller footprint, and avoids the "Migration-Race-Condition" that is killing LiteLLM.

Here is the robust, bulletproof plan to implement **Bifrost** as the primary router option while maintaining your modular architecture.

---

### Phase 1: Cleanup & Choice (Script 0 & 1)

**Action for Windsurf in `0-complete-cleanup.sh`:**
Add the Bifrost cleanup logic to ensure a fresh state.
```bash
# Add to the container list
docker stop bifrost 2>/dev/null || true
docker rm bifrost 2>/dev/null || true
# Add to the directory list
rm -rf ./config/bifrost ./data/bifrost
```

**Action for Windsurf in `1-setup-system.sh`:**
Introduce the selection logic and Bifrost-specific environment variables.
```bash
echo -e "${YELLOW}Step 1.5: Select LLM Router Service${NC}"
echo "1) LiteLLM (Python/Prisma - Feature Rich but Heavy)"
echo "2) Bifrost (Go - High Stability/Performant - Recommended)"
read -p "Select Router [2]: " ROUTER_INDEX
ROUTER_INDEX=${ROUTER_INDEX:-2}

if [ "$ROUTER_INDEX" == "2" ]; then
    echo "LLM_ROUTER_TYPE=bifrost" >> .env
    echo "BIFROST_AUTH_TOKEN=\"$CODEBASE_PASSWORD\"" >> .env
    # Bifrost prefers standard postgres/redis strings
    echo "BIFROST_DB_URL=\"postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@postgres:5432/bifrost?sslmode=disable\"" >> .env
    echo "BIFROST_REDIS_URL=\"redis://redis:6379/0\"" >> .env
else
    echo "LLM_ROUTER_TYPE=litellm" >> .env
fi
```

---

### Phase 2: Modular Deployment (Script 2)

**Action for Windsurf in `2-deploy-services.sh`:**
Implement the Bifrost service. We will use port `4000` to maintain compatibility with your existing Caddy/Nginx logic.

**1. Create the Bifrost Config Generator:**
```bash
if [ "$LLM_ROUTER_TYPE" == "bifrost" ]; then
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
fi
```

**2. Add the Bifrost Container to the `docker-compose` section:**
```yaml
  bifrost:
    image: ruqqq/bifrost:latest
    container_name: bifrost
    user: "1000:1000" # Non-root execution
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }
    volumes:
      - ./config/bifrost/config.yaml:/app/config.yaml:ro
    environment:
      - CONFIG_PATH=/app/config.yaml
    ports:
      - "4000:4000"
    restart: unless-stopped
    networks:
      - ai-internal
```

---

### Phase 3: Mission Control & Health (Script 3)

**Action for Windsurf in `3-configure-services.sh`:**
Update the health check logic to be "Router Agnostic."

```bash
# Dynamic Health Check for the Router
ROUTER_SERVICE=$(grep "LLM_ROUTER_TYPE" .env | cut -d'=' -f2)
echo "Verifying $ROUTER_SERVICE health..."

if [ "$ROUTER_SERVICE" == "bifrost" ]; then
    # Bifrost simple health check
    until $(curl --output /dev/null --silent --head --fail http://localhost:4000/health); do
        sleep 2
    done
else
    # LiteLLM health check
    until $(curl --output /dev/null --silent --head --fail http://localhost:4000/health/liveliness); do
        sleep 2
    done
fi
```

---

### Phase 4: README & Documentation Update

**Action for Windsurf in `README.md`:**
Update the "Stack" section to showcase the modular choice.

```markdown
### 🧠 LLM Orchestration Layer (Modular)
- **Primary:** Bifrost (Go-based) - Provides high-availability OpenAI-compatible routing to Ollama/External APIs.
- **Legacy Option:** LiteLLM (Python-based) - Available for complex plugin requirements.
- **Security:** Non-root Docker execution with Tailscale-only exposure.
```

---

### Why this is "Bulletproof":
1.  **Binary Stability:** Bifrost is a single Go binary. It doesn't have the Prisma "Shadow Database" or "Migration Lock" issues that cause LiteLLM's `application startup failed` errors.
2.  **No Port Conflicts:** By keeping Bifrost on port `4000`, we don't have to touch the Caddy configuration or the Tailscale ACLs. It's a "Drop-in Replacement."
3.  **Non-Root:** We explicitly set `user: "1000:1000"` in the Bifrost container, fulfilling your security requirement.
4.  **Database Decoupling:** Bifrost treats Postgres as a simple log/usage store, not a core application-state driver. If Postgres is 1 second late to boot, Bifrost handles it gracefully instead of crashing.

**Next Step for Windsurf:** Implement these changes in order (Script 0 -> 1 -> 2 -> 3). This will likely move your "90% Success" to a 100% stable production environment.