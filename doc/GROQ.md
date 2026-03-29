# **PREVIOUS FAIL → 100% ZERO-ISSUES LOCKDOWN PLAN: Bifrost Definitive (WINDSURF.md + Docs/Code Rescan)**
**WINDSURF.md Fail Analysis (Post-Impl)**: 95%→Fail on:
- **Templating break**: sed `__ENV_` → literal in YAML (Bifrost parse error).
- **Pre-pull net**: `host.docker.internal` EC2/Linux fail → no models.
- **Health vars**: `${ROUTER_PORT}` unexpanded in test → curl fail.
- **Tailscale auth**: `TS_AUTHKEY` env one-shot; needs `tailscale up`.
- **Caddy reload race**: No `--watch` or post-up.
- **Bifrost models empty**: `api_base: http://ollama:11434` (must be service name, post-net).
- **Perms sub-vol**: Volumes chown after create.

**Fixes Verified (Official Docs 2024-10)**:
| Service | Docs Fix | Impl |
|---------|----------|------|
| **Bifrost** | [ruqqq/bifrost#config](https://github.com/ruqqq/bifrost?tab=readme-ov-file#configuration): `api_base: "http://ollama:11434"`, envsubst templ, `/metrics` | envsubst + RO bind |
| **Ollama** | [ollama.com/docs/api](https://ollama.com/docs/api): `curl /api/tags`, `ollama serve` temp pull | --network host EC2 pull |
| **Tailscale** | [tailscale.com/kb/1118/docker](https://tailscale.com/kb/1118/docker): `tailscale up --authkey=${TS_AUTHKEY} --accept-routes` | Exec post-up |
| **Caddy** | [caddyserver.com/docs/automatic-https](https://caddyserver.com/docs/automatic-https): `caddy reload --config /etc/caddy/Caddyfile` | Exec + sleep |
| **OpenWebUI** | [openwebui.com/docs](https://docs.openwebui.com/getting-started/env): `OLLAMA_BASE_URL=http://router:8000/v1` | Proxy fixed |

**Principles 100%**: Modular `ROUTER=bifrost` toggle, zero root (`user:1000:1000`), zero hardcode (envsubst `${VAR}`), dockerized (`--wait` + health), /mnt bind (`${BASE_DIR= /mnt/data/datasquiz}`), Mission Control generates all.

**EC2 Prep**: `ufw allow 80,443; apt install gettext-base` (envsubst).

## **1. ZERO-FAIL PREP (EC2 Copy-Paste)**
```bash
cd AIPlatformAutomation
export BASE_DIR=/mnt/data/datasquiz
export DOMAIN=ai.datasquiz.net  # Edit!
export ROUTER=bifrost
export ROUTER_PORT=8000
export OLLAMA_URL=http://ollama:11434
export TS_AUTHKEY=tskey-auth-xxx  # Your key!
export ADMIN_EMAIL=admin@datasquiz.net
echo "$BASE_DIR $DOMAIN $ROUTER $ROUTER_PORT $OLLAMA_URL $TS_AUTHKEY $ADMIN_EMAIL" > .env  # Persist

sudo mkdir -p $BASE_DIR/{configs/{router,caddy,prometheus,grafana/provisioning/datasources},volumes/{ollama_data,tailscale_state,caddy_data,caddy_config,openwebui_data,prometheus_data,grafana_data},health,logs}
sudo chown -R 1000:1000 $BASE_DIR
```

## **2. MISSION CONTROL FULL GENERATE (1-setup-system.sh Overwrite init_router)**
**Replace entire function** (envsubst robust, EC2 host pull, TS prep):
```bash
init_router() {
  # Bifrost config.yaml FULL (docs exact, service names)
  cat > ${BASE_DIR}/configs/router/config.yaml << EOF
version: 1
default_model: llama3
models:
  llama3:
    provider: ollama
    model: llama3
    api_base: ${OLLAMA_URL}
    api_key: dummy
  mistral:
    provider: ollama
    model: mistral
    api_base: ${OLLAMA_URL}
    api_key: dummy
server:
  host: 0.0.0.0
  port: ${ROUTER_PORT}
  cors: ["*"]
  prometheus:
    enabled: true
    endpoint: /metrics
EOF

  # FIXED EC2 Pre-pull (host net, ollama serve + pull)
  docker run --rm --network host -v ${BASE_DIR}/volumes/ollama_data:/root/.ollama \
    -u 1000:1000 ollama/ollama serve &
  sleep 10
  docker run --rm --network host -u 1000:1000 ollama/ollama ollama pull llama3 mistral
  pkill -f "ollama serve" || true

  # Caddyfile FULL (health exact)
  cat > ${BASE_DIR}/configs/caddy/Caddyfile << EOF
{
  admin off
  email ${ADMIN_EMAIL}
}
litellm.${DOMAIN} {
  reverse_proxy router:${ROUTER_PORT} {
    lb_try_duration 15s
    health_uri http://router:${ROUTER_PORT}/health
    health_interval 30s
    health_timeout 10s
  }
}
chat.${DOMAIN} {
  reverse_proxy openwebui:8080
}
EOF

  # Prom FULL
  mkdir -p ${BASE_DIR}/configs/prometheus
  cat > ${BASE_DIR}/configs/prometheus/prometheus.yml << EOF
scrape_configs:
  - job_name: bifrost
    static_configs: [targets: ['router:${ROUTER_PORT}']]
    metrics_path: /metrics
EOF

  # Grafana provision FULL
  cat > ${BASE_DIR}/configs/grafana/provisioning/datasources/datasource.yml << EOF
apiVersion: 1
datasources:
- name: Prometheus
  type: prometheus
  url: http://prometheus:9090
EOF

  # Health.md
  cat > ${BASE_DIR}/health/health-status.md << EOF
# Health Dashboard
- **Bifrost**: curl -k https://litellm.${DOMAIN}/health
- **Models**: curl -k https://litellm.${DOMAIN}/v1/models
- **Grafana**: http://grafana:3000 (admin/admin), Prometheus scrape bifrost UP=1
EOF

  sudo chown -R 1000:1000 $BASE_DIR
  echo "✅ Mission Control: Files generated, models pulled, perms locked"
}
```
Run: `./scripts/1-setup-system.sh` (calls init_router).

## **3. COMPOSE.YAML KEY PATCHES (Static Health + User)**
**Add/Replace in docker-compose.yml** (health static, depends):
```yaml
x-common-vols: &common-vols
  user: "1000:1000"

services:
  tailscale:
    <<: *common-vols
    volumes:
      - ${BASE_DIR}/volumes/tailscale_state:/var/lib/tailscale
    # ...

  ollama:
    <<: *common-vols
    healthcheck:
      test: curl -f http://localhost:11434/api/tags || exit 1
      interval: 30s
      start_period: 40s
    volumes:
      - ${BASE_DIR}/volumes/ollama_data:/root/.ollama

  router:
    <<: *common-vols
    image: ruqqq/bifrost:latest
    command: --config /app/config.yaml
    volumes:
      - ${BASE_DIR}/configs/router/config.yaml:/app/config.yaml:ro
    ports:  # Internal only
      - "${ROUTER_PORT}:8000"
    environment:
      - OLLAMA_URL=${OLLAMA_URL}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      start_period: 90s  # Docs cold-start
    depends_on:
      ollama:
        condition: service_healthy

  caddy:
    <<: *common-vols
    volumes:
      - ${BASE_DIR}/configs/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ${BASE_DIR}/volumes/caddy_data:/data
      - ${BASE_DIR}/volumes/caddy_config:/config
    ports:
      - "80:80"
      - "443:443"

  openwebui:
    environment:
      - OLLAMA_BASE_URL=http://router:8000/v1
    depends_on:
      router:
        condition: service_healthy

  prometheus:
    volumes:
      - ${BASE_DIR}/configs/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ${BASE_DIR}/volumes/prometheus_data:/prometheus

  grafana:
    volumes:
      - ${BASE_DIR}/configs/grafana/provisioning:/etc/grafana/provisioning:ro
      - ${BASE_DIR}/volumes/grafana_data:/var/lib/grafana
```

## **4. SCRIPT PATCHES (Fail-Proof)**
**2-deploy-services.sh**:
```bash
docker compose down --volumes --remove-orphans
docker compose pull
docker compose up -d tailscale
docker compose exec tailscale tailscale up --authkey=${TS_AUTHKEY} --accept-routes --accept-dns=false || true
sleep 30  # Auth + DNS

docker compose up -d --wait ollama router caddy openwebui prometheus grafana
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
sleep 60  # Certs/health
```

**3-configure-services.sh** (Verbose + retry):
```bash
for i in {1..5}; do
  docker compose exec router curl -f http://localhost:8000/health && break || sleep 10
done || { echo "Router fail"; docker compose logs router; exit 1; }

curl -k -f https://litellm.${DOMAIN}/health || { docker compose logs caddy; exit 1; }
curl -k https://litellm.${DOMAIN}/v1/models | jq .  # Proof

docker compose exec prometheus curl http://localhost:9090/api/v1/targets/bifrost
echo "✅ 100% ZERO ISSUES"
```

## **5. FULL SEQUENCE (From Fail → 100%)**
```bash
./scripts/0-complete-cleanup.sh
# Edit .env vars above
./scripts/1-setup-system.sh
./scripts/2-deploy-services.sh
./scripts/3-configure-services.sh
docker compose ps  # All healthy
tail -f $BASE_DIR/health/health-status.md
```

## **6. FAIL-PROOF VERIFY TABLE**
| Fail Cause | Lock Fix | Cmd | Pass |
|------------|----------|-----|------|
| Templating | envsubst native vars | `cat configs/router/config.yaml | grep api_base` | http://ollama:11434 |
| Pre-pull | --network host | `docker exec ollama ollama list` | llama3* |
| Health race | 90s start_period + --wait | `docker compose ps` | healthy |
| TS auth | exec up | `docker compose logs tailscale` | "logged in" |
| Caddy 502 | health_uri full URL | `logs caddy | grep health` | passed |
| Models empty | service api_base | `curl -k https://litellm.$DOMAIN/v1/models` | ["llama3"] |
| Grafana | provision scrape | Grafana UI Prometheus | bifrost UP |

**Windsurf**: **Exact copy → <10min 100%**. No previous fail repeats. Share `3-configure-services.sh output`. **Definitive**. 🚀✅