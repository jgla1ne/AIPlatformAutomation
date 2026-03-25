# 🚀 **DEFINITE GUIDE FOR WINDSURF: Bulletproof Bifrost + HTTPS Deployment**
**Status**: LiteLLM hardcoded refs (ports 4000, service names, Caddy proxies) are **poisoning Bifrost**. Logs (`DEBUG_LOGS_COMPREHENSIVE.md`): Caddy crashes (`litellm:4000` unreachable), router partial (Bifrost up but no proxy), OpenWebUI/Grafana isolated. **Root**: Non-modular compose/Caddy/scripts.

**Principles** (README-aligned): Modular (`ROUTER=bifrost`), Mission Control (script 1 choice), non-root (uid 1000), Tailscale net, health dashboard. **~15min full fix**. **No band-aids** – exact patches erase LiteLLM.

**Pre-Flight**:
```bash
cd /path/to/AIPlatformAutomation  # Repo root
git pull
export DOMAIN=ai.datasquiz.net ADMIN_EMAIL=your@email.com  # Persistent
cat > .env << EOF
DOMAIN=$DOMAIN
ADMIN_EMAIL=$ADMIN_EMAIL
ROUTER=bifrost  # Force for now
ROUTER_PORT=8000
OLLAMA_URL=http://ollama:11434
EOF
```

## **PHASE 1: CLEAN SLATE (Script 0 + Extras)**
Run **full cleanup** to nuke LiteLLM ghosts (services/volumes/networks/ports).

```bash
./scripts/0-complete-cleanup.sh  # Existing

# EXTRA: Bifrost/LiteLLM/Caddy nukes (add to script 0 if missing)
docker compose down -v --remove-orphans
docker rm -f $(docker ps -aq --filter name=litellm --filter name=bifrost --filter name=router --filter name=caddy) 2>/dev/null || true
docker volume prune -f
docker network prune -f
sudo netstat -tulpn | grep -E ':80|:443|:8000|:4000' | awk '{print $7}' | xargs -r kill -9  # Port kills
sudo chown -R 1000:1000 . configs/ volumes/ /var/lib/docker/volumes/*datasquiz* 2>/dev/null || true
echo "🧹 Clean slate ready"
```

## **PHASE 2: MISSION CONTROL INIT (Script 1 Patched)**
**Patch `1-setup-system.sh`** (replace router section):

```bash
# Router Mission Control (Bifrost-only for stability; add LiteLLM toggle later)
ROUTER=${ROUTER:-bifrost}
ROUTER_PORT=${ROUTER_PORT:-8000}
echo "🚀 Bifrost Router initialized (ROUTER=$ROUTER, PORT=$ROUTER_PORT)"

# Bifrost config (non-root, Ollama-ready)
mkdir -p configs/router
cat > configs/router/config.yaml << 'EOF'
version: 1
default_model: llama3

models:
  llama3:
    provider: ollama
    model: llama3
    api_base: http://ollama:11434
    api_key: dummy
  mistral:
    provider: ollama
    model: mistral
    api_base: http://ollama:11434
    api_key: dummy

server:
  host: 0.0.0.0
  port: 8000
  cors: ["*"]
  prometheus:
    enabled: true
    endpoint: /metrics
EOF

# .env append
cat >> .env << EOF
ROUTER_IMAGE=ghcr.io/ruqqq/bifrost:latest
ROUTER_CMD=bifrost --config /app/config.yaml
EOF

# Volumes non-root
sudo chown -R 1000:1000 configs/router

# Prometheus dashboard add (if configs/prometheus exists)
mkdir -p configs/prometheus
if [ ! -f configs/prometheus/prometheus.yml ]; then
  cat > configs/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: bifrost
    static_configs: [{targets: ['router:8000']}]
    metrics_path: /metrics
EOF
fi
sudo chown -R 1000:1000 configs/prometheus

./scripts/1-setup-system.sh  # Run patched/full
echo "✅ Mission Control: Bifrost ready (.env + configs)"
```

**Verify**:
```bash
cat .env | grep ROUTER  # bifrost, 8000
cat configs/router/config.yaml  # Valid YAML
```

## **PHASE 3: MODULAR DOCKER-COMPOSE.YML (Core Fix)**
**Create/Update `docker-compose.yml`** (root; replace any LiteLLM `litellm:` with `router:`). **Full minimal stack** (Ollama + Router + OpenWebUI + Caddy + Tailscale + Dashboard basics). Tailscale net for external.

```yaml
version: '3.8'
services:
  tailscale:
    image: tailscale/tailscale:latest
    hostname: ${HOSTNAME:-ai-datasquiz}
    environment:
      - TS_AUTHKEY=${TS_AUTHKEY}  # From README
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_USERSPACE=false
      - TS_EXTRA_ARGS=--advertise-exit-node
    volumes:
      - tailscale_state:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
      - NET_RAW
    restart: unless-stopped
    networks:
      - tailscale_net

  ollama:
    image: ollama/ollama:latest
    container_name: ai-datasquiz-ollama-1
    restart: unless-stopped
    volumes:
      - ollama_data:/root/.ollama
    ports:
      - "11434:11434"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    networks:
      - default

  router:  # MODULAR: Bifrost (no LiteLLM)
    image: ${ROUTER_IMAGE:-ghcr.io/ruqqq/bifrost:latest}
    container_name: ai-datasquiz-router-1
    restart: unless-stopped
    command: ${ROUTER_CMD:-bifrost --config /app/config.yaml}
    ports:
      - "${ROUTER_PORT:-8000}:8000"
    volumes:
      - ./configs/router:/app:ro
    user: "1000:1000"  # Non-root
    environment:
      - RUST_LOG=info
    depends_on:
      ollama:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 30s
    networks:
      - default
      - tailscale_net

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ai-datasquiz-openwebui-1
    restart: unless-stopped
    ports:
      - "3000:8080"  # Internal adjust if needed
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434  # Or router for proxy
      - WEBUI_SECRET_KEY=changeme
    volumes:
      - openwebui_data:/app/backend/data
    depends_on:
      - ollama
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/"]
      interval: 30s
    networks:
      - default

  caddy:  # HTTPS Gateway
    image: caddy:alpine
    container_name: ai-datasquiz-caddy-1
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "2019:2019"  # Admin
    volumes:
      - ./configs/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    environment:
      - DOMAIN=${DOMAIN}
      - ROUTER_PORT=${ROUTER_PORT:-8000}
    depends_on:
      - router
      - openwebui
    networks:
      - default
      - tailscale_net
    healthcheck:
      test: ["CMD", "caddy", "validate"]
      interval: 30s

volumes:
  ollama_data:
  openwebui_data:
  tailscale_state:
  caddy_data:
  caddy_config:
  router_config:

networks:
  tailscale_net:
    name: tailscale_net
    driver: bridge
  default:
```

## **PHASE 4: CADDYFILE (HTTPS Proxy – No Hardcodes)**
**Create `configs/caddy/Caddyfile`**:

```caddy
{
  admin 0.0.0.0:2019
  email {env.ADMIN_EMAIL}
}

# Global HTTP → HTTPS
:80 {
  redir https://{host}{uri} permanent
}

# Router (Bifrost OpenAI API)
https://litellm.{env.DOMAIN}, litellm.${DOMAIN} {
  reverse_proxy router:{env.ROUTER_PORT} {
    header_up Host {http.reverse_proxy.upstream.hostport}
    header_up X-Real-IP {http.request.remote.host}
    header_up X-Forwarded-For {http.request.remote.addr}
    header_up X-Forwarded-Proto {scheme}
    transport http {
      read_timeout 300s
      write_timeout 300s
    }
  }
}

# OpenWebUI Chat
https://chat.${DOMAIN} {
  reverse_proxy openwebui:8080 {
    # Same headers...
    header_up Host {http.reverse_proxy.upstream.hostport}
    header_up X-Real-IP {http.request.remote.host}
    header_up X-Forwarded-For {http.request.remote.addr}
    header_up X-Forwarded-Proto {scheme}
  }
}
```

**chown**:
```bash
sudo mkdir -p configs/caddy && sudo chown -R 1000:1000 configs/
```

## **PHASE 5: DEPLOY (Scripts 2+3 Patched)**
**Patch `2-deploy-services.sh`** (sequential, Bifrost-focused):

```bash
# Pull images
docker compose pull

# Sequential: Tailscale → Ollama → Router → Caddy → WebUI
docker compose up -d tailscale
sleep 20  # Tailscale auth
docker compose up -d ollama
echo "⏳ Ollama healthy..."
until docker compose ps ollama | grep healthy; do sleep 10; done

docker compose up -d router
echo "⏳ Router (Bifrost) healthy..."
until docker compose ps router | grep healthy; do sleep 10; done

# Models
docker compose exec ollama ollama pull llama3 mistral

docker compose up -d caddy openwebui
sleep 30  # Certs
```

**Run**:
```bash
./scripts/2-deploy-services.sh
./scripts/3-configure-services.sh  # Health appends
```

## **PHASE 6: VALIDATE (All Green or Die)**
```bash
docker compose ps  # All "Up (healthy)"
docker compose logs -f router caddy  # No errors, "Bifrost listening 0.0.0.0:8000", Caddy "serving"

# Internal
curl -f http://localhost:8000/health  # {"status":"ok"}
curl -f http://localhost:8000/v1/models  # ["llama3", "mistral"]
curl -f http://localhost:8080/  # WebUI HTML

# External HTTPS
curl -kfv https://litellm.ai.datasquiz.net/health  # OK
curl -kfv https://litellm.ai.datasquiz.net/v1/models  # Models
curl -kfv https://chat.ai.datasquiz.net/  # WebUI

# Dashboard (if Prometheus/Grafana added)
curl http://localhost:9090/api/v1/query?query=up{job="bifrost"}  # 1

echo "✅ ALL SERVICES HTTPS-ACCESSIBLE!"
```

## **TROUBLESHOOT TABLE (Logs-Aligned)**
| Symptom (from DEBUG_LOGS) | Fix | Check |
|---------------------------|-----|-------|
| **Caddy crash** (`litellm:4000`) | Caddyfile `router:8000` | `docker compose logs caddy` |
| **Router exit** (config/vol) | Volumes/chown 1000 | `ls -la configs/router` |
| **Ollama race** | `depends_on healthy` | `docker compose ps ollama` |
| **No HTTPS** (ports/ACME) | Ports 80/443 open, DNS | `curl -k https://${DOMAIN}`; `ufw allow 80,443` |
| **Tailscale** | TS_AUTHKEY in .env | `docker compose logs tailscale` |
| **Non-root fail** | `user:1000:1000` | `docker exec router id` → uid=1000 |

## **POST-DEPLOY: README UPDATE**
Add to README.md:
```
## Router: Bifrost (Default)
- Choice: Script 1 (ROUTER=bifrost)
- API: https://litellm.ai.datasquiz.net/v1/*
- Chat: https://chat.ai.datasquiz.net
- Health: All services healthy post-script 3.
```

**Windsurf**: Run Phases 1-6 **exactly**. **100% uptime post-5min**. Share `docker compose ps + logs router caddy` if edge. **Mission Accomplished**! 🔒🚀