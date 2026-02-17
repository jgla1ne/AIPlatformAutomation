AI Platform Automation
Script 2 — End-to-End Gap Analysis & Remediation Plan
Based on live deployment audit log  |  February 2026
1. Executive Summary
The deployment log reveals that Script 2 progresses through its phases but halts due to four distinct, independent failure classes — none of which are related to business logic. All failures are infrastructure/permissions issues that must be resolved before any service can be used. The good news: the compose structure, proxy generation, and service ordering are working correctly. These are fixable issues.
✅  Working Correctly Proxy config generation (Caddy) Docker network creation PostgreSQL starts & becomes healthy Service selection loading (15 services) Compose file detection Pre-deployment cleanup	❌  Failing (4 distinct issues) Redis health check — wrong endpoint (localhost) Prometheus — config file never created Grafana — volume directory permissions Ollama — tries to write to /.ollama (root path) LiteLLM — fails to start (likely depends on Ollama)
2. Issue-by-Issue Root Cause Analysis
The following table maps each logged failure to its root cause and required fix:
#	Issue	Severity	Root Cause & Fix
1	Redis health check fails	HIGH	Health check uses 'localhost' but container's redis-cli must target 127.0.0.1 or use 'redis-cli ping' without host. Change wait_for_port logic to check from inside container: docker exec redis redis-cli ping
2	Prometheus: no such file or directory /etc/prometheus/prometheus.yml	CRITICAL	Script 2 never generates prometheus.yml before starting the container. Must create config/prometheus/prometheus.yml before 'docker compose up prometheus'. Add generate_prometheus_config() call in deployment setup phase.
3	Grafana: GF_PATHS_DATA not writable, permission denied	CRITICAL	The host volume directory (e.g. volumes/grafana) is created as root but Grafana runs as UID 472. Must: mkdir -p volumes/grafana && chown 472:472 volumes/grafana before starting container.
4	Ollama: mkdir /.ollama permission denied	CRITICAL	Ollama is mapping its data to /.ollama (root path). The compose volume mount is wrong. Should be: volumes: - ./volumes/ollama:/home/ollama (or OLLAMA_HOME env var set to a writable path). Also needs chown to match RUNNING_UID.
5	LiteLLM: FAILED TO START	HIGH	LiteLLM depends on a running database (postgres) and likely tries to connect to Ollama. Since Ollama failed, LiteLLM startup fails. Fix Ollama first. Also verify litellm compose definition has correct DB_URL and no dependency on unhealthy services.
6	OpenWebUI: status unknown	MEDIUM	Log is cut off mid-health-check. OpenWebUI depends on Ollama being accessible. Will likely fail until Ollama is fixed. Monitor once upstream issues resolved.
3. Detailed Fix Instructions for Windsurf
These are ordered by dependency — fix in this sequence to avoid cascading failures.
Fix 1 — Prometheus Config Generation (CRITICAL — Blocks monitoring stack)
Prometheus crashes immediately because its config file doesn't exist. Script 2 must generate it before starting the container.
Add this function to scripts/2-deploy-services.sh and call it during the setup phase, before any docker compose up commands:
generate_prometheus_config() {     local config_dir="${BASE_DIR}/config/prometheus"     mkdir -p "${config_dir}"     cat > "${config_dir}/prometheus.yml" << 'EOF' global:   scrape_interval: 15s   evaluation_interval: 15s scrape_configs:   - job_name: 'prometheus'     static_configs:       - targets: ['localhost:9090']   - job_name: 'node'     static_configs:       - targets: ['node-exporter:9100']   - job_name: 'cadvisor'     static_configs:       - targets: ['cadvisor:8080'] EOF     log_info "Prometheus config generated at ${config_dir}/prometheus.yml" }
Call site — add immediately before the monitoring services deployment block:
# In the deployment setup phase (before docker compose up prometheus): generate_prometheus_config # Also ensure the volume mount in docker-compose.yml points here: # volumes: #   - ./config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
Fix 2 — Grafana Volume Permissions (CRITICAL — Blocks metrics UI)
Grafana runs as UID 472 internally. The host volume directory must be pre-created and owned by that UID before container start.
fix_grafana_permissions() {     local grafana_vol="${BASE_DIR}/volumes/grafana"     mkdir -p "${grafana_vol}"     # Grafana's internal UID is 472     chown -R 472:472 "${grafana_vol}"     chmod 755 "${grafana_vol}"     log_info "Grafana volume permissions set (UID 472)" }
Call site — add to the permissions setup block alongside the existing PostgreSQL/Redis permission fixes:
log_debug "Fixing volume permissions..." fix_postgres_volume_permissions fix_redis_volume_permissions fix_grafana_permissions   # ← ADD THIS
Fix 3 — Ollama Volume Mount Path (CRITICAL — Blocks all AI inference)
Ollama is trying to write to /.ollama which is a root-owned path. The docker-compose.yml volume definition must be corrected to map to a user-writable path.
In docker-compose.yml, the ollama service volumes section must be:
ollama:     image: ollama/ollama:latest     environment:       - OLLAMA_HOME=/ollama_data     volumes:       - ./volumes/ollama:/ollama_data   # ← NOT /.ollama     user: "${RUNNING_UID}:${RUNNING_GID}"
And add a pre-start permission fix:
fix_ollama_permissions() {     local ollama_vol="${BASE_DIR}/volumes/ollama"     mkdir -p "${ollama_vol}"     chown -R "${RUNNING_UID}:${RUNNING_GID}" "${ollama_vol}"     chmod 755 "${ollama_vol}"     log_info "Ollama volume permissions set" }
Note: If the compose file is generated dynamically by Script 1/2, ensure the ollama service template uses OLLAMA_HOME=/ollama_data and the correct volume path. Search the compose generation code for 'ollama' and patch accordingly.
Fix 4 — Redis Health Check Method (HIGH — Causes spurious timeout warnings)
The health check is connecting to localhost:6379 from outside the container, which fails because the service isn't bound to the host interface. Redis is healthy but the checker reports timeout.
Replace the external port check with an in-container command:
| # WRONG — checking from host (localhost doesn't resolve inside container network): wait_for_port localhost 6379 # CORRECT — check from inside the container: wait_for_redis() {     local max_attempts=60     local attempt=0     while [ $attempt -lt $max_attempts ]; do         if docker exec redis redis-cli ping 2>/dev/null | grep -q PONG; then             log_success "Redis is ready"             return 0         fi         sleep 1         ((attempt++))     done     log_error "Redis failed to respond to ping"     return 1 } |
| :---- |
Fix 5 — LiteLLM Start Failure (HIGH — Blocks LLM routing layer)
LiteLLM fails because it depends on Ollama being healthy, and Ollama is crashing. Once Fix 3 is applied, also verify:
The litellm compose definition has depends_on: ollama with condition: service_healthy
The OLLAMA_API_BASE env var points to http://ollama:11434 (not localhost)
The DATABASE_URL points to the postgres service by container name, not localhost
LiteLLM's config.yaml (if used) is generated before container start, similar to Prometheus
4. Correct Deployment Order
The current deployment order is causing cascade failures. Services that depend on others must wait for their dependencies to be truly healthy. Recommended order:
Phase	Services	Pre-conditions
0	Generate configs	generate_prometheus_config(), fix permissions for grafana, ollama, postgres, redis
1	postgres, redis	Volumes created & chowned. Wait for postgres healthy, redis ping.
2	prometheus, grafana	prometheus.yml exists. Grafana vol chowned to 472. Wait healthy.
3	ollama	OLLAMA_HOME set, volume chowned to RUNNING_UID. Wait healthy (GET /api/tags).
4	litellm	ollama healthy, postgres healthy, litellm config.yaml generated.
5	minio	Volume dir exists, chowned. Wait for health endpoint.
6	n8n, flowise	postgres healthy, redis healthy.
7	open-webui, anythingllm, dify	litellm healthy, postgres healthy.
8	signal-api, tailscale, openclaw	Network ready. These can be soft-start (don't block).
9	caddy	All services started. Caddy config already generated. Start last.
5. Windsurf Implementation Checklist
The following is an ordered task list for Windsurf to implement. Each task maps to a specific file and function.
5.1 — scripts/2-deploy-services.sh Changes
A	Add generate_prometheus_config() function Place in the 'Config Generation' section near generate_proxy_config(). Call immediately after proxy config generation.

# Location: after generate_proxy_config() call, around line 120 generate_prometheus_config # Then ensure compose volume: ./config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro

B	Add fix_grafana_permissions() function Place in the permissions setup block. Call alongside existing postgres/redis permission fixes.

# Add function definition near other fix_*_permissions functions # Call in permissions setup block: fix_grafana_permissions   # chown 472:472 volumes/grafana

C	Add fix_ollama_permissions() function Place in the permissions setup block. Ensure OLLAMA_HOME env var is also set in the ollama service definition.

# Add function definition # Call in permissions setup block: fix_ollama_permissions    # chown RUNNING_UID:RUNNING_GID volumes/ollama

D	Replace Redis health check with wait_for_redis() Find all wait_for_port calls targeting 6379 and replace with docker exec redis redis-cli ping.
| # Find: wait_for_port localhost 6379 (or similar) # Replace with: docker exec redis redis-cli ping | grep -q PONG |
| :---- |
5.2 — docker-compose.yml (or compose generation) Changes
E	Fix Ollama volume mount and OLLAMA_HOME Change the ollama volumes entry from /.ollama to ./volumes/ollama and add OLLAMA_HOME env var.

# In ollama service definition: environment:   - OLLAMA_HOME=/ollama_data volumes:   - ./volumes/ollama:/ollama_data

F	Add prometheus volume mount Ensure prometheus service in compose has the config file mounted read-only.

# In prometheus service definition: volumes:   - ./config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro   - ./volumes/prometheus:/prometheus
5.3 — Validation Steps After Implementation
After applying all fixes, verify with these targeted checks:
| # 1. Verify Prometheus config was generated: ls -la ${BASE_DIR}/config/prometheus/prometheus.yml # 2. Verify Grafana volume ownership: stat ${BASE_DIR}/volumes/grafana | grep Uid # Expected: Uid: ( 472/   ?) # 3. Verify Ollama volume ownership: stat ${BASE_DIR}/volumes/ollama | grep Uid # Expected: Uid: ( 1001/  your-user) # 4. Verify Redis responds to ping: docker exec redis redis-cli ping # Expected: PONG # 5. Verify Ollama is accessible: curl -s http://localhost:11434/api/tags | head -c 100 # Expected: {"models":[...]} # 6. Verify Prometheus is running: curl -s http://localhost:9090/-/healthy # Expected: Prometheus Server is Healthy. # 7. Verify Caddy proxy routing: curl -sk https://localhost/webui | head -c 200 # Expected: HTML from Open WebUI |
| :---- |
6. Script 3 Readiness — When to Proceed
Do not begin Script 3 implementation until the following gates are all green:
Gate	Status
postgres is healthy (Script 2 log shows SUCCESS)	✅ Pass
redis responds: docker exec redis redis-cli ping → PONG	⚠ Fix #4
prometheus container is healthy (no config error in logs)	❌ Fix #1
grafana container is healthy (no permission error in logs)	❌ Fix #2
ollama container is healthy (GET /api/tags returns JSON)	❌ Fix #3
litellm container is healthy (GET /health returns 200)	❌ After Ollama
caddy proxy serving: curl -sk https://localhost/webui returns HTML	⚠ After all above
Once all gates are green, Script 3 (menu-driven service management) can be implemented as planned — adding services, updating Caddy config dynamically, SSL management, and integration configuration.
7. Summary — What Windsurf Needs to Do
In order of priority:
Generate prometheus.yml before starting the prometheus container (add generate_prometheus_config() call in the pre-flight setup phase)
Fix Grafana volume ownership: chown 472:472 on the grafana volume directory before container start
Fix Ollama volume path: change compose mount from /.ollama to ./volumes/ollama, add OLLAMA_HOME=/ollama_data env var, chown directory to RUNNING_UID
Fix Redis health check: replace localhost port check with docker exec redis redis-cli ping
After the above 4 fixes, redeploy and verify all services reach healthy state before proceeding to Script 3
These are the only blockers. The overall architecture is sound.
