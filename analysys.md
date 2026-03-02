🔧 Windsurf Fix Instructions — Remaining Issues After Successful Deployment
Current Status Summary
Copy table


Service
Status
Issue



n8n
✅ Fully working
—


Flowise
✅ Fully working
—


Open WebUI
✅ Fully working
—


AnythingLLM
✅ Fully working
—


Grafana
✅ Fully working
—


Ollama
✅ Fully working
—


PostgreSQL
✅ Fully working
—


Redis
✅ Fully working
—


LiteLLM
⚠️ Running but unhealthy
Wrong health endpoint → Docker reports unhealthy forever


Qdrant
⚠️ Running but unhealthy
Wrong health endpoint → Docker reports unhealthy forever


Open WebUI domain
⚠️ Doc/Caddy mismatch
chat. subdomain referenced in old docs, actual is openwebui.


Prometheus
⚠️ Silent scrape failure
Scrapes node-exporter:9100 which is never deployed


Dify
❌ Not tested yet
Was not in the enabled stack for this run


Signal API
❌ Requires manual step
By design — needs phone registration



Fix 1 — LiteLLM: Wrong Health Check Endpoint
File: scripts/2-deploy-services.sh → append_litellm()
Problem: /health/liveliness returns HTTP 401 (requires Authorization: Bearer <master_key> header). Docker marks container permanently unhealthy. The correct unauthenticated endpoint is /health/readiness.
Exact change — find this block inside append_litellm():
# ❌ REMOVE THIS
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health/liveliness"]
      interval: 30s
      timeout: 10s
      retries: 5
Replace with:
# ✅ REPLACE WITH THIS
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:4000/health/readiness"]
      interval: 30s
      timeout: 15s
      start_period: 60s
      retries: 5

Why start_period: 60s? LiteLLM runs Alembic DB migrations on cold start which takes 30–50 seconds. Without start_period, Docker counts those failures against retries and kills the container before it finishes starting.


Fix 2 — Qdrant: Wrong Health Check Endpoint
File: scripts/2-deploy-services.sh → append_qdrant()
Problem: /healthz returns HTTP 404. Qdrant's actual health endpoint is / (root) which returns {"title":"qdrant","version":"..."} with HTTP 200.
Exact change — find this block inside append_qdrant():
# ❌ REMOVE THIS
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
Replace with:
# ✅ REPLACE WITH THIS
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:6333/"]
      interval: 30s
      timeout: 10s
      start_period: 20s
      retries: 3

Fix 3 — Prometheus: Scrape Target node-exporter Never Exists
File: scripts/2-deploy-services.sh → append_prometheus() → the inline prometheus.yml
Problem: The generated prometheus.yml includes a scrape job for node-exporter:9100 but node-exporter is never deployed as a container. Prometheus logs continuous scrape errors and Grafana shows no system metrics.
Two-part fix:
Part A — Add node-exporter as a companion container inside append_prometheus(), right after the prometheus service block:
append_prometheus() {
    local prom_config_dir="${DATA_ROOT}/prometheus"
    mkdir -p "${prom_config_dir}"

    cat > "${prom_config_dir}/prometheus.yml" << 'PROMEOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
PROMEOF

    append << EOF

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - ${prom_config_dir}/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    ports:
      - "${PROMETHEUS_PORT:-9090}:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      com.ai-platform: "true"

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    networks:
      - platform
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    labels:
      com.ai-platform: "true"
EOF
}
Part B — Add node_exporter_data to the cleanup script volumes list in 0-complete-cleanup.sh (it needs no named volume but add node-exporter to the label-based container removal — it already handles this via the label filter, nothing extra needed).

Fix 4 — Open WebUI: Caddy Subdomain Standardisation
File: scripts/2-deploy-services.sh → write_caddyfile()
Problem: The report shows openwebui.ai.datasquiz.net works, but any existing documentation/script still references chat.${DOMAIN}. The Caddyfile currently uses openwebui.${DOMAIN} which is correct. The fix is to ensure script 1's summary display and the post-deploy URL output in main() both print openwebui. not chat..
In main() of 2-deploy-services.sh, confirm this line reads:
# ✅ Already correct — verify it reads openwebui not chat
[[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] && echo "    🌐  Open WebUI    → https://openwebui.${DOMAIN}"
Also check scripts/1-setup-system.sh print_summary() — if it prints chat.${DOMAIN} anywhere, change it to openwebui.${DOMAIN}.

Fix 5 — LiteLLM: start_period Missing Causes Restart Loop on Fresh Deploy
Problem: On a clean deploy (no existing DB), LiteLLM runs Alembic migrations for ~45 seconds. Docker's health check starts immediately and hits retries: 5 × 10s = 50s window. The container gets marked unhealthy and restart: unless-stopped doesn't restart it — but dependent service ordering in future scripts will fail.
This is already covered by the start_period: 60s in Fix 1 above — no additional change needed beyond that.

Fix 6 — AnythingLLM: Shell Variable Expansion Bug in append_anythingllm()
File: scripts/2-deploy-services.sh → append_anythingllm()
Problem: This line uses :- fallback inside a double-quoted heredoc with \${} escaping:
      - JWT_SECRET=\${ANYTHINGLLM_JWT_SECRET:-\${SECRET_KEY}}
Inside a << EOF (not << 'EOF') heredoc, bash tries to expand ${ANYTHINGLLM_JWT_SECRET:-${SECRET_KEY}} at script generation time, not at Docker runtime. If ANYTHINGLLM_JWT_SECRET is unset in the shell environment when script 2 runs, the fallback works — but the resulting compose file will contain the literal secret value rather than a ${VAR} reference, meaning re-runs or .env changes won't be picked up.
The correct fix is to ensure ANYTHINGLLM_JWT_SECRET is always set in .env by script 1, then reference it cleanly:
In scripts/1-setup-system.sh → generate_secrets(), add:
ANYTHINGLLM_JWT_SECRET="$(openssl rand -hex 32)"
ANYTHINGLLM_AUTH_TOKEN="$(openssl rand -hex 32)"
In scripts/2-deploy-services.sh → append_anythingllm(), change:
# ❌ REMOVE
      - JWT_SECRET=\${ANYTHINGLLM_JWT_SECRET:-\${SECRET_KEY}}
      - AUTH_TOKEN=\${ANYTHINGLLM_AUTH_TOKEN:-\${SECRET_KEY}}

# ✅ REPLACE WITH (clean references, no fallback needed since script 1 guarantees them)
      - JWT_SECRET=\${ANYTHINGLLM_JWT_SECRET}
      - AUTH_TOKEN=\${ANYTHINGLLM_AUTH_TOKEN}

Fix 7 — Script 4 (4-add-service.sh): Shebang Typo
File: scripts/4-add-service.sh line 1
# ❌ CURRENT (broken — space after !)
#!/usr/bin/en bash

# ✅ CORRECT
#!/usr/bin/env bash
This will silently fail on any system where /usr/bin/en doesn't exist. Change en → env.

Fix 8 — Script 4: Missing append_openwebui Function
File: scripts/4-add-service.sh
Problem: The service menu includes open-webui and the case statement routes to append_openwebui — but that function is never defined in script 4. It will throw command not found.
Add this function in script 4, after append_ollama():
append_openwebui() {
    cat >> "${COMPOSE_FILE}" << EOF
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    networks:
      - platform
    volumes:
      - openwebui_data:/app/backend/data
    ports:
      - "${OPENWEBUI_PORT:-8080}:8080"
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=${SECRET_KEY}
      - ENABLE_SIGNUP=true
    depends_on:
      ollama:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      com.ai-platform: "true"
EOF
}

Fix 9 — Cleanup Script: Missing Dify Nginx Config Directory
File: scripts/0-complete-cleanup.sh
Problem: Script 2 creates ${DATA_ROOT}/dify/nginx.conf. The cleanup script removes ${DATA_ROOT} with rm -rf which handles it — but the volume dify_storage must be in the named volumes list.
Verify 0-complete-cleanup.sh has dify_storage in its volume removal loop. Currently it does — ✅ no change needed.
However, add node-exporter to the container label removal — it already uses the label filter com.ai-platform=true which node-exporter has, so ✅ also handled.

Summary Table for Windsurf
Copy table


Fix #
File
Location
Type
Priority



1
2-deploy-services.sh
append_litellm() healthcheck
Change endpoint + add start_period
High


2
2-deploy-services.sh
append_qdrant() healthcheck
Change endpoint + add start_period
High


3
2-deploy-services.sh
append_prometheus()
Add node-exporter container + fix yml
Medium


4
2-deploy-services.sh
write_caddyfile() + main()
Verify openwebui. not chat.
Low


5
1-setup-system.sh
generate_secrets()
Add ANYTHINGLLM_JWT_SECRET + AUTH_TOKEN
Medium


6
2-deploy-services.sh
append_anythingllm()
Remove :- fallback, use clean \${VAR}
Medium


7
4-add-service.sh
Line 1 shebang
en → env
High


8
4-add-service.sh
After append_ollama()
Add missing append_openwebui() function
High

