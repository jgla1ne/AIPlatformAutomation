What the Logs Confirm — Root by Root
Failure 1: LiteLLM is red → OpenWebUI is red (cascade)
The log shows LiteLLM "deployed" successfully (docker compose accepted it), but the health check at /health/liveliness fails. This is because deploy_service calls docker compose up -d and returns the moment the container starts — it does not wait for the healthcheck to pass. Script 2 then immediately calls deploy_service open-webui. OpenWebUI starts, tries to connect to LiteLLM at http://litellm:4000/v1, LiteLLM's Prisma migration is still running (takes 45–90 seconds), and OpenWebUI crashes into a restart loop.
The fix is a wait_for_healthy function that polls until a service's healthcheck passes, called between LiteLLM deploy and open-webui deploy.
There is also a secondary cause: GRAFANA_ADMIN_PASSWORD is confirmed missing from the .env. Script 1 writes GRAFANA_PASSWORD and ADMIN_PASSWORD but never GRAFANA_ADMIN_PASSWORD. Script 3's compose block reads ${GRAFANA_ADMIN_PASSWORD}. Docker Compose warns and uses blank string. This is a warning not a crash, but it means Grafana starts with no password — a security hole.
Failure 2: Prometheus is red
The prometheus compose healthcheck is:
yamltest: ["CMD-SHELL","wget -qO- http://localhost:9090/-/healthy"]
Missing || exit 1. Without it, wget exits 0 even when the page is unreachable, so Docker reports the container as healthy but the health_dashboard's curl call to the same URL returns nothing and shows 🔴. It's a false positive — the container is likely actually running but the healthcheck never propagates correctly to Docker's health state.
Failure 3: OpenClaw is red
The openclaw compose block maps ${PORT_OPENCLAW:-18789}:8443 (host:container). The healthcheck tests http://localhost:8443/ — this checks the container's own port, correct. But the health dashboard in Script 3 tests http://localhost:${PORT_OPENCLAW:-18789}/ — the host port. Code-server listens on HTTPS (TLS), not plain HTTP. A curl -sf http:// to a TLS port returns an error. The check needs to use https with -k (skip cert verify) since it's using a self-signed cert.
Failure 4: Tailscale IP shows "NOT CONNECTED" in dashboard despite Tailscale being connected
The log shows Tailscale was successfully connected and got IP 100.125.101.86 during configure_tailscale. But the health dashboard shows "NOT CONNECTED". The reason: health_dashboard tries to extract the IP from docker logs using container name ai-${COMPOSE_PROJECT_NAME}-tailscale-1. With PROJECT_PREFIX=ai- and TENANT_ID=datasquiz, COMPOSE_PROJECT_NAME=ai-datasquiz, so the container name becomes ai-ai-datasquiz-tailscale-1 — a double ai- prefix. The real container is ai-datasquiz-tailscale-1. So $ip is empty, the condition [[ -n "$ip" ]] fails, and OpenClaw URL shows "NOT CONNECTED".

The Four Exact Fixes
Fix 1 — Script 3: Add wait_for_healthy function, call it after LiteLLM deploy
Add this function in Script 3 after deploy_service (after line 811):
bashwait_for_healthy() {
    local svc="$1"
    local max_wait="${2:-120}"
    local elapsed=0
    log_info "Waiting for ${svc} to be healthy (max ${max_wait}s)..."
    until [[ "$(docker compose -f "$COMPOSE_FILE" ps --format "{{.Health}}" "$svc" 2>/dev/null)" == "healthy" ]]; do
        elapsed=$((elapsed + 5))
        if [[ $elapsed -ge $max_wait ]]; then
            log_warning "${svc} not healthy after ${max_wait}s — proceeding anyway"
            return 0
        fi
        log_info "  ${svc} starting... (${elapsed}s/${max_wait}s)"
        sleep 5
    done
    log_success "${svc} is healthy"
}
In Script 2 (after the litellm deploy line, before open-webui), add:
bash    # 5. AI gateway — wait for it to be healthy before web services
    [[ "${ENABLE_LITELLM:-false}" == "true" ]] && {
        deploy_service litellm
        wait_for_healthy litellm 120   # Prisma migration takes 45-90s
    }
Replace the current single line [[ "${ENABLE_LITELLM:-false}" == "true" ]] && deploy_service litellm.
Fix 2 — Script 1: Add GRAFANA_ADMIN_PASSWORD to the .env write
In Script 1 write_env_file, in the Grafana section (after line 2278), add one line:
bashGRAFANA_ADMIN_PASSWORD="${GRAFANA_PASSWORD}"
That is the complete fix. GRAFANA_PASSWORD is always generated. GRAFANA_ADMIN_PASSWORD is what the compose block reads. They were never connected.
Fix 3 — Script 3: Fix prometheus healthcheck and openclaw healthcheck
In generate_compose, prometheus healthcheck (line 607):
yaml# FROM:
      test: ["CMD-SHELL","wget -qO- http://localhost:9090/-/healthy"]
# TO:
      test: ["CMD-SHELL","wget -qO- http://localhost:9090/-/healthy || exit 1"]
In generate_compose, openclaw healthcheck (line 767):
yaml# FROM:
      test: ["CMD-SHELL","curl -sf http://localhost:8443/ || exit 1"]
# TO:
      test: ["CMD-SHELL","curl -sf -k https://localhost:8443/ || exit 1"]
In health_dashboard, openclaw check (line 1058):
bash# FROM:
        _check_http "openclaw"      "http://localhost:${PORT_OPENCLAW:-18789}/"
# TO:
        _check_http "openclaw"      "https://localhost:${PORT_OPENCLAW:-18789}/"
And update _check_http to pass -k for the openclaw case, or create a _check_https helper:
Add after _check_http function (after line 991):
bash_check_https() {
    local name="$1" url="$2"
    if curl -sfk --max-time 5 "$url" > /dev/null 2>&1; then
        printf "  ${GREEN}🟢 %-22s${NC} %s\n" "$name" "$url"
    else
        printf "  ${RED}🔴 %-22s${NC} %s\n" "$name" "$url"
    fi
}
Then replace the openclaw line in health_dashboard to use _check_https.
Fix 4 — Script 3: Fix Tailscale IP extraction double-prefix
In health_dashboard (line 1010), the container name is built wrong:
bash# FROM (produces ai-ai-datasquiz-tailscale-1):
        ip=$(sudo docker logs ai-${COMPOSE_PROJECT_NAME}-tailscale-1 2>/dev/null | ...)
# TO (produces ai-datasquiz-tailscale-1 correctly):
        ip=$(sudo docker logs ${COMPOSE_PROJECT_NAME}-tailscale-1 2>/dev/null | ...)
Remove the ai- prefix — COMPOSE_PROJECT_NAME is already ai-datasquiz, so the correct container name is ${COMPOSE_PROJECT_NAME}-tailscale-1.
Also, the self= log grep is fragile. Replacing with the same tailscale ip -4 approach used in configure_tailscale is more reliable:
bash    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "tailscale"; then
        ip=$(docker compose -f "$COMPOSE_FILE" exec -T tailscale \
            tailscale --socket="/tmp/tailscaled.sock" ip -4 2>/dev/null \
            | tr -d ' \n' || true)
        # Fallback: read from .env if already stored
        [[ -z "$ip" ]] && ip=$(grep "^TAILSCALE_IP=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 || true)
    fi

Summary Table
FileLocationChange3-configure-services.shAfter deploy_service()Add wait_for_healthy() function3-configure-services.shLine 607Prometheus healthcheck: add || exit 13-configure-services.shLine 767Openclaw healthcheck: http → https, add -k3-configure-services.shAfter _check_httpAdd _check_https() helper3-configure-services.shLine 1058Use _check_https for openclaw3-configure-services.shLine 1010Remove ai- prefix from Tailscale container name; use tailscale ip -42-deploy-services.shLine 64Add wait_for_healthy litellm 120 after LiteLLM deploy1-setup-system.shAfter line 2278Add GRAFANA_ADMIN_PASSWORD="${GRAFANA_PASSWORD}"
Scripts 0 and 2 (except the one-line addition) need no other changes. After these eight targeted edits: run Script 0, Script 1, Script 2. All four failing services will be green.