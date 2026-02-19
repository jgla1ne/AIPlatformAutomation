#!/bin/bash

# **2-deploy-enhanced.sh**
# **Enhanced deployment with frontier patterns - graceful degradation and recovery**

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] INFO: $*${NC}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN: $*${NC}" | tee -a "$LOG_FILE"; }
err() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $*${NC}" | tee -a "$LOG_FILE"; exit 1; }
section() { echo -e "\n${BLUE}━━━ $* ━━━${NC}" | tee -a "$LOG_FILE"; }

PLATFORM_DIR="/mnt/data"
ENV_FILE="${PLATFORM_DIR}/.env"
COMPOSE_FILE="${PLATFORM_DIR}/ai-platform/deployment/stack/docker-compose.yml"
LOG_FILE="${PLATFORM_DIR}/logs/deployment.log"
DEPLOYMENT_LOCK="${PLATFORM_DIR}/.deployment.lock"

# **── Load & validate env ───────────────────────────────────────────────────────**
load_env() {
    [[ -f "$ENV_FILE" ]] || err "No config found at $ENV_FILE. Run 1-setup-wizard.sh first."
    set -a; source "$ENV_FILE"; set +a
    log "Loaded config from: $ENV_FILE"
    
    [[ -n "${DEPLOYMENT_MODE:-}" ]] || err "DEPLOYMENT_MODE missing from .env"
    [[ -n "${BASE_DOMAIN:-}" ]] || err "BASE_DOMAIN missing from .env"
}

# **── Health check helpers (frontier style) ───────────────────────────────────────**
MAX_WAIT=120  # Increased from 30s to 120s
POLL=5

wait_for_container_healthy() {
    local name="$1"
    local start elapsed status health
    
    log "  Waiting for ${name}..."
    start=$(date +%s)
    
    while true; do
        elapsed=$(( $(date +%s) - start ))
        [[ $elapsed -ge $MAX_WAIT ]] && {
            warn "  TIMEOUT: ${name} not healthy after ${MAX_WAIT}s"
            docker logs "$name" --tail 20 2>/dev/null | sed 's/^/    /' | tee -a "$LOG_FILE"
            return 1
        }
        
        # Check container exists
        if ! docker inspect "$name" &>/dev/null; then
            log "    ${name}: container not yet created (${elapsed}s)..."
            sleep "$POLL"; continue
        fi
        
        status=$(docker inspect --format='{{.State.Status}}' "$name" 2>/dev/null || echo "unknown")
        health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name" 2>/dev/null || echo "none")
        
        case "$status" in
            running)
                case "$health" in
                    healthy)
                        log "  ✓ ${name}: healthy (${elapsed}s)"
                        return 0
                        ;;
                    none)
                        # No healthcheck defined - running is good enough
                        log "  ✓ ${name}: running, no healthcheck (${elapsed}s)"
                        return 0
                        ;;
                    starting)
                        log "    ${name}: starting... (${elapsed}s)"
                        sleep "$POLL"
                        ;;
                    unhealthy)
                        warn "  ✗ ${name}: UNHEALTHY"
                        docker logs "$name" --tail 20 2>/dev/null | sed 's/^/    /' | tee -a "$LOG_FILE"
                        return 1
                        ;;
                    *)
                        log "    ${name}: health=${health} (${elapsed}s)"
                        sleep "$POLL"
                        ;;
                esac
                ;;
            exited|dead)
                warn "  ✗ ${name}: ${status}"
                docker logs "$name" --tail 20 2>/dev/null | sed 's/^/    /' | tee -a "$LOG_FILE"
                return 1
                ;;
            *)
                log "    ${name}: status=${status} (${elapsed}s)"
                sleep "$POLL"
                ;;
        esac
    done
}

# **── Tier-based deployment with graceful degradation ───────────────────────────**
wait_for_tier() {
    local tier="$1"
    shift
    local containers=("$@")
    local failed=0
    
    section "Health Checks: ${tier}"
    for c in "${containers[@]}"; do
        wait_for_container_healthy "$c" || failed=$((failed + 1))
    done
    
    if [[ $failed -gt 0 ]]; then
        warn "${failed} container(s) in '${tier}' not healthy - deployment may be partial"
        echo "$(date): Tier '${tier}': ${failed} failed containers" >> "$LOG_FILE"
    else
        log "Tier '${tier}': all containers healthy"
        echo "$(date): Tier '${tier}': all healthy" >> "$LOG_FILE"
    fi
    return $failed
}

# **── Permission fixing (based on failure analysis) ────────────────────────────────**
fix_permissions() {
    section "Fixing Service Permissions"
    
    # Fix anythingllm storage
    if [[ "${SERVICE_ANYTHINGLLM_ENABLED:-false}" == "true" ]]; then
        log "  Fixing AnythingLLM storage permissions..."
        mkdir -p "${PLATFORM_DIR}/anythingllm/storage"
        chown -R 1001:1001 "${PLATFORM_DIR}/anythingllm"
    fi
    
    # Fix n8n config
    if [[ "${SERVICE_N8N_ENABLED:-false}" == "true" ]]; then
        log "  Fixing n8n config permissions..."
        mkdir -p "${PLATFORM_DIR}/n8n"
        chown -R 1001:1001 "${PLATFORM_DIR}/n8n"
    fi
    
    # Fix prometheus volumes
    if [[ "${SERVICE_PROMETHEUS_ENABLED:-false}" == "true" ]]; then
        log "  Fixing Prometheus permissions..."
        chown -R 65534:65534 "${PLATFORM_DIR}/prometheus"
    fi
    
    # Fix litellm config
    if [[ "${SERVICE_LITELLM_ENABLED:-false}" == "true" ]]; then
        log "  Ensuring LiteLLM config exists..."
        mkdir -p "${PLATFORM_DIR}/config/litellm"
        if [[ ! -f "${PLATFORM_DIR}/config/litellm/config.yaml" ]]; then
            cat > "${PLATFORM_DIR}/config/litellm/config.yaml" << EOF
model_list:
  - model_name: ollama/llama3.2
    litellm_params:
      model: ollama/llama3.2
      api_base: http://ollama:11434

general_settings:
  master_key: "${LITELLM_MASTER_KEY}"
  database_url: "postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/litellm"
  
litellm_settings:
  drop_params: ["api_key", "api_base"]
EOF
        fi
    fi
}

# **── Generate compose file for enabled services only ───────────────────────────────**
generate_compose() {
    section "Generating docker-compose.yml"
    
    # Use existing compose generation from 1-setup-system.sh
    log "  Using existing compose generation..."
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        warn "  Compose file not found, running setup first..."
        bash "${PLATFORM_DIR}/../scripts/1-setup-system.sh"
    fi
}

# **── Deploy services in tiers ────────────────────────────────────────────────────**
deploy_services() {
    section "Deploying Services"
    
    local tier1_services=()
    local tier2_services=()
    local tier3_services=()
    
    # Tier 1: Infrastructure
    [[ "${SERVICE_POSTGRES_ENABLED:-false}" == "true" ]] && tier1_services+=("postgres")
    [[ "${SERVICE_REDIS_ENABLED:-false}" == "true" ]] && tier1_services+=("redis")
    
    # Tier 2: Core services
    [[ "${SERVICE_OLLAMA_ENABLED:-false}" == "true" ]] && tier2_services+=("ollama")
    [[ "${SERVICE_OPENWEBUI_ENABLED:-false}" == "true" ]] && tier2_services+=("openwebui")
    [[ "${SERVICE_LITELLM_ENABLED:-false}" == "true" ]] && tier2_services+=("litellm")
    
    # Tier 3: Application services
    [[ "${SERVICE_FLOWISE_ENABLED:-false}" == "true" ]] && tier3_services+=("flowise")
    [[ "${SERVICE_N8N_ENABLED:-false}" == "true" ]] && tier3_services+=("n8n")
    [[ "${SERVICE_DIFY_ENABLED:-false}" == "true" ]] && tier3_services+=("dify-api" "dify-web")
    [[ "${SERVICE_ANYTHINGLLM_ENABLED:-false}" == "true" ]] && tier3_services+=("anythingllm")
    [[ "${SERVICE_PROMETHEUS_ENABLED:-false}" == "true" ]] && tier3_services+=("prometheus")
    [[ "${SERVICE_GRAFANA_ENABLED:-false}" == "true" ]] && tier3_services+=("grafana")
    [[ "${SERVICE_MINIO_ENABLED:-false}" == "true" ]] && tier3_services+=("minio")
    [[ "${SERVICE_SIGNAL_ENABLED:-false}" == "true" ]] && tier3_services+=("signal-api")
    [[ "${SERVICE_OPENCLAW_ENABLED:-false}" == "true" ]] && tier3_services+=("openclaw")
    
    # Deploy Tier 1
    if [[ ${#tier1_services[@]} -gt 0 ]]; then
        log "  Deploying Tier 1: Infrastructure"
        for service in "${tier1_services[@]}"; do
            log "    Starting $service..."
            DATA_ROOT=/mnt/data docker compose -f "$COMPOSE_FILE" up -d "$service" 2>&1 | tee -a "$LOG_FILE"
        done
        wait_for_tier "Infrastructure" "${tier1_services[@]}" || true
    fi
    
    # Deploy Tier 2
    if [[ ${#tier2_services[@]} -gt 0 ]]; then
        log "  Deploying Tier 2: Core Services"
        for service in "${tier2_services[@]}"; do
            log "    Starting $service..."
            DATA_ROOT=/mnt/data docker compose -f "$COMPOSE_FILE" up -d "$service" 2>&1 | tee -a "$LOG_FILE"
        done
        wait_for_tier "Core Services" "${tier2_services[@]}" || true
    fi
    
    # Deploy Tier 3
    if [[ ${#tier3_services[@]} -gt 0 ]]; then
        log "  Deploying Tier 3: Application Services"
        for service in "${tier3_services[@]}"; do
            log "    Starting $service..."
            DATA_ROOT=/mnt/data docker compose -f "$COMPOSE_FILE" up -d "$service" 2>&1 | tee -a "$LOG_FILE"
        done
        wait_for_tier "Application Services" "${tier3_services[@]}" || true
    fi
}

# **── Generate proxy configuration ───────────────────────────────────────────────────**
generate_proxy_config() {
    section "Generating Proxy Configuration"
    
    if [[ "${USE_SSL:-false}" == "true" ]]; then
        log "  Generating Caddy configuration for ${BASE_DOMAIN}..."
        
        cat > "${PLATFORM_DIR}/config/caddy/Caddyfile" << EOF
# AI Platform - Caddy Configuration (Frontier Style)
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

{
    email hosting@datasquiz.net
    acme_ca https://acme-v02.api.letsencrypt.org/directory
    log {
        output file /var/log/caddy/access.log
        format json
    }
}

${BASE_DOMAIN} {
    # Root - landing page
    handle / {
        respond "AI Platform - Services available at /servicename"
    }
    
EOF
        
        # Add routes for enabled services
        if [[ "${SERVICE_OPENWEBUI_ENABLED:-false}" == "true" ]]; then
            cat >> "${PLATFORM_DIR}/config/caddy/Caddyfile" << EOF
    # Open WebUI
    handle /webui* {
        reverse_proxy openwebui:8080
    }
    
EOF
        fi
        
        if [[ "${SERVICE_OLLAMA_ENABLED:-false}" == "true" ]]; then
            cat >> "${PLATFORM_DIR}/config/caddy/Caddyfile" << EOF
    # Ollama
    handle /ollama* {
        reverse_proxy ollama:11434
    }
    
EOF
        fi
        
        if [[ "${SERVICE_N8N_ENABLED:-false}" == "true" ]]; then
            cat >> "${PLATFORM_DIR}/config/caddy/Caddyfile" << EOF
    # n8n
    handle /n8n* {
        reverse_proxy n8n:5678
    }
    
EOF
        fi
        
        if [[ "${SERVICE_FLOWISE_ENABLED:-false}" == "true" ]]; then
            cat >> "${PLATFORM_DIR}/config/caddy/Caddyfile" << EOF
    # Flowise
    handle /flowise* {
        reverse_proxy flowise:3000
    }
    
EOF
        fi
        
        if [[ "${SERVICE_DIFY_ENABLED:-false}" == "true" ]]; then
            cat >> "${PLATFORM_DIR}/config/caddy/Caddyfile" << EOF
    # Dify
    handle /dify* {
        reverse_proxy dify-web:3000
    }
    
EOF
        fi
        
        if [[ "${SERVICE_ANYTHINGLLM_ENABLED:-false}" == "true" ]]; then
            cat >> "${PLATFORM_DIR}/config/caddy/Caddyfile" << EOF
    # AnythingLLM
    handle /anythingllm* {
        reverse_proxy anythingllm:3000
    }
    
EOF
        fi
        
        if [[ "${SERVICE_LITELLM_ENABLED:-false}" == "true" ]]; then
            cat >> "${PLATFORM_DIR}/config/caddy/Caddyfile" << EOF
    # LiteLLM
    handle /litellm* {
        reverse_proxy litellm:4000
    }
    
EOF
        fi
        
        if [[ "${SERVICE_GRAFANA_ENABLED:-false}" == "true" ]]; then
            cat >> "${PLATFORM_DIR}/config/caddy/Caddyfile" << EOF
    # Grafana
    handle /grafana* {
        reverse_proxy grafana:3000
    }
    
EOF
        fi
        
        if [[ "${SERVICE_PROMETHEUS_ENABLED:-false}" == "true" ]]; then
            cat >> "${PLATFORM_DIR}/config/caddy/Caddyfile" << EOF
    # Prometheus
    handle /prometheus* {
        reverse_proxy prometheus:9090
    }
    
EOF
        fi
        
        if [[ "${SERVICE_MINIO_ENABLED:-false}" == "true" ]]; then
            cat >> "${PLATFORM_DIR}/config/caddy/Caddyfile" << EOF
    # MinIO Console
    handle /minio* {
        reverse_proxy minio:9001
    }
    
EOF
        fi
        
        if [[ "${SERVICE_SIGNAL_ENABLED:-false}" == "true" ]]; then
            cat >> "${PLATFORM_DIR}/config/caddy/Caddyfile" << EOF
    # Signal API
    handle /signal* {
        reverse_proxy signal-api:8080
    }
    
EOF
        fi
        
        if [[ "${SERVICE_OPENCLAW_ENABLED:-false}" == "true" ]]; then
            cat >> "${PLATFORM_DIR}/config/caddy/Caddyfile" << EOF
    # OpenClaw
    handle /openclaw* {
        reverse_proxy openclaw:8083
    }
    
EOF
        fi
        
        cat >> "${PLATFORM_DIR}/config/caddy/Caddyfile" << EOF
}
EOF
        
        log "  Caddy configuration generated"
    fi
}

# **── Start proxy ───────────────────────────────────────────────────────────────────**
start_proxy() {
    section "Starting Proxy"
    
    if [[ "${USE_SSL:-false}" == "true" ]]; then
        log "  Starting Caddy proxy..."
        DATA_ROOT=/mnt/data docker compose -f "$COMPOSE_FILE" up -d caddy 2>&1 | tee -a "$LOG_FILE"
        
        # Wait for Caddy to be ready
        sleep 10
        if docker ps --format "{{.Names}}" | grep -q "caddy"; then
            log "  ✓ Caddy proxy started"
        else
            warn "  ✗ Caddy proxy failed to start"
        fi
    fi
}

# **── Deployment summary ────────────────────────────────────────────────────────────**
generate_deployment_summary() {
    section "Deployment Summary"
    
    local total_services=0
    local running_services=0
    local failed_services=0
    
    echo "$(date): === DEPLOYMENT SUMMARY ===" >> "$LOG_FILE"
    
    # Count enabled services
    for service in postgres redis ollama openwebui flowise n8n dify-api dify-web anythingllm litellm prometheus grafana minio signal-api openclaw caddy; do
        local service_var="SERVICE_${service^^}_ENABLED"
        service_var="${service_var//-API/_API}"
        if [[ "${!service_var:-false}" == "true" ]]; then
            total_services=$((total_services + 1))
            if docker ps --format "{{.Names}}" | grep -q "^${service}$"; then
                running_services=$((running_services + 1))
                echo "$(date): $service: running" >> "$LOG_FILE"
            else
                failed_services=$((failed_services + 1))
                echo "$(date): $service: failed" >> "$LOG_FILE"
            fi
        fi
    done
    
    log "Total services: $total_services"
    log "Running services: $running_services"
    log "Failed services: $failed_services"
    log "Success rate: $(echo "scale=1; $running_services * 100 / $total_services" | bc)%"
    
    if [[ $failed_services -gt 0 ]]; then
        warn "Deployment completed with $failed_services service failures"
        warn "Check logs: $LOG_FILE"
    else
        log "🎉 Deployment completed successfully!"
    fi
    
    # Show service URLs
    if [[ "${USE_SSL:-false}" == "true" ]]; then
        echo ""
        log "Service URLs:"
        [[ "${SERVICE_OPENWEBUI_ENABLED:-false}" == "true" ]] && log "  OpenWebUI: https://${BASE_DOMAIN}/webui"
        [[ "${SERVICE_OLLAMA_ENABLED:-false}" == "true" ]] && log "  Ollama: https://${BASE_DOMAIN}/ollama"
        [[ "${SERVICE_N8N_ENABLED:-false}" == "true" ]] && log "  n8n: https://${BASE_DOMAIN}/n8n"
        [[ "${SERVICE_FLOWISE_ENABLED:-false}" == "true" ]] && log "  Flowise: https://${BASE_DOMAIN}/flowise"
        [[ "${SERVICE_DIFY_ENABLED:-false}" == "true" ]] && log "  Dify: https://${BASE_DOMAIN}/dify"
        [[ "${SERVICE_ANYTHINGLLM_ENABLED:-false}" == "true" ]] && log "  AnythingLLM: https://${BASE_DOMAIN}/anythingllm"
        [[ "${SERVICE_LITELLM_ENABLED:-false}" == "true" ]] && log "  LiteLLM: https://${BASE_DOMAIN}/litellm"
        [[ "${SERVICE_GRAFANA_ENABLED:-false}" == "true" ]] && log "  Grafana: https://${BASE_DOMAIN}/grafana"
        [[ "${SERVICE_PROMETHEUS_ENABLED:-false}" == "true" ]] && log "  Prometheus: https://${BASE_DOMAIN}/prometheus"
        [[ "${SERVICE_MINIO_ENABLED:-false}" == "true" ]] && log "  MinIO: https://${BASE_DOMAIN}/minio"
        [[ "${SERVICE_SIGNAL_ENABLED:-false}" == "true" ]] && log "  Signal: https://${BASE_DOMAIN}/signal"
        [[ "${SERVICE_OPENCLAW_ENABLED:-false}" == "true" ]] && log "  OpenClaw: https://${BASE_DOMAIN}/openclaw"
    fi
}

# **── Main ──────────────────────────────────────────────────────────────────────────**
main() {
    # Deployment lock
    if [[ -f "$DEPLOYMENT_LOCK" ]]; then
        local lock_pid=$(cat "$DEPLOYMENT_LOCK")
        if kill -0 "$lock_pid" 2>/dev/null; then
            err "Deployment already running (PID: $lock_pid)"
        else
            warn "Removing stale deployment lock"
            rm -f "$DEPLOYMENT_LOCK"
        fi
    fi
    
    echo $$ > "$DEPLOYMENT_LOCK"
    trap 'rm -f "$DEPLOYMENT_LOCK"' EXIT
    
    clear
    echo -e "${BOLD}${BLUE}"
    echo " ╔═══════════════════════════════════════╗"
    echo " ║ Enhanced AI Platform Deployment ║"
    echo " ╚═══════════════════════════════════════╝"
    echo -e "${NC}"
    
    load_env
    fix_permissions
    generate_compose
    generate_proxy_config
    deploy_services
    start_proxy
    generate_deployment_summary
    
    echo ""
    log "🚀 Enhanced deployment completed!"
    log "📋 Check logs: $LOG_FILE"
    log "🔧 Management: sudo bash 3-configure-services.sh"
}

main "$@"
