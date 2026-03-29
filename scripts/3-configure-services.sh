#!/usr/bin/env bash
# =============================================================================
# Script 3: Mission Control Hub - BULLETPROOF v4.2
# PURPOSE: System setup AND post-deployment configuration
# USAGE:   sudo bash scripts/3-configure-services.sh [--setup-only]
# =============================================================================

set -euo pipefail
trap 'error_handler $LINENO' ERR

# Script Directory and Repository Root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

# Logging Functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $1"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }
section() { echo "" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && echo "  $*" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

# Error Handler
error_handler() {
    local exit_code=$?
    local line=$1
    echo ""
    echo -e "${RED}[ERROR]${NC} Script failed at line $line with exit code $exit_code"
    exit $exit_code
}

# Global error counter
ERRORS=0

# --------------------------------------------------------------------------
# Load .env
# --------------------------------------------------------------------------
load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        fail ".env not found at $ENV_FILE — Run Script 1 first!"
    fi
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    log "Loaded .env from $ENV_FILE"
    
    # Validate critical vars
    : "${MNT_BASE:?MNT_BASE not set in .env}"
    : "${HOST_IP:?HOST_IP not set in .env}"
    : "${PORTAINER_PORT:?PORTAINER_PORT not set in .env}"
    : "${PORTAINER_ADMIN_PASSWORD:?PORTAINER_ADMIN_PASSWORD not set in .env}"
}

# --------------------------------------------------------------------------
# Install system packages (MOVED from Script 1)
# --------------------------------------------------------------------------
install_system_packages() {
    section "Installing System Packages"
    
    log "Updating package lists..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    
    local packages=(
        "curl"
        "wget"
        "git"
        "jq"
        "htop"
        "openssl"
        "ca-certificates"
        "gnupg"
        "lsb-release"
        "python3-pip"
        "net-tools"
        "dnsutils"
    )
    
    log "Installing packages: ${packages[*]}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}"
    
    log "System packages installed"
}

# --------------------------------------------------------------------------
# Configure Docker (MOVED from Script 1)
# --------------------------------------------------------------------------
configure_docker() {
    section "Configuring Docker"
    
    # Add current user to docker group (if not already)
    if ! groups "$(whoami)" | grep -q docker; then
        sudo usermod -aG docker "$(whoami)"
        log "Added $(whoami) to docker group (re-login may be needed)"
        warn "You may need to log out and back in for docker group to take effect"
        warn "For now, commands will use sudo where needed"
    else
        log "User already in docker group"
    fi
    
    # Configure docker daemon for /mnt and bifrost
    local daemon_config="/etc/docker/daemon.json"
    
    if [[ ! -f "$daemon_config" ]]; then
        sudo tee "$daemon_config" > /dev/null << DAEMON_EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "mtu": ${BIFROST_MTU}
}
DAEMON_EOF
        log "Docker daemon configured (MTU: $BIFROST_MTU)"
        
        # Restart docker to apply daemon config
        sudo systemctl restart docker
        log "Docker daemon restarted"
        
        # Wait for docker to be ready
        local retries=10
        while ! docker info &>/dev/null && [[ $retries -gt 0 ]]; do
            sleep 2
            ((retries--))
        done
        
        if ! docker info &>/dev/null; then
            fail "Docker failed to restart after daemon config change"
        fi
        log "Docker daemon ready"
    else
        log "Docker daemon.json already exists, skipping (review manually if issues)"
    fi
}

# --------------------------------------------------------------------------
# Create directory structure (MOVED from Script 1)
# --------------------------------------------------------------------------
create_directory_structure() {
    section "Creating Directory Structure under $MNT_BASE"
    
    local dirs=(
        "${MNT_BASE}/data/portainer"
        "${MNT_BASE}/data/ollama"
        "${MNT_BASE}/data/open-webui"
        "${MNT_BASE}/data/postgres"
        "${MNT_BASE}/data/redis"
        "${MNT_BASE}/data/n8n"
        "${MNT_BASE}/data/searxng"
        "${MNT_BASE}/data/flowise"
        "${MNT_BASE}/configs/searxng"
        "${MNT_BASE}/configs/nginx"
        "${MNT_BASE}/configs/n8n"
        "${MNT_BASE}/logs/nginx"
        "${MNT_BASE}/logs/n8n"
    )
    
    for dir in "${dirs[@]}"; do
        sudo mkdir -p "$dir"
        log "Created: $dir"
    done
    
    # Set ownership to current user for all data dirs
    sudo chown -R "$(id -u):$(id -g)" "${MNT_BASE}"
    
    # Set service-specific ownership
    sudo chown -R 999:999 "${MNT_BASE}/data/postgres"  # PostgreSQL
    sudo chown -R 999:999 "${MNT_BASE}/data/redis"     # Redis
    sudo chown -R 1000:1000 "${MNT_BASE}/data/n8n"       # n8n
    sudo chown -R 977:977 "${MNT_BASE}/data/searxng"    # SearXNG
    sudo chown -R 977:977 "${MNT_BASE}/configs/searxng"  # SearXNG
    
    log "Directory structure created with correct ownership"
}

# --------------------------------------------------------------------------
# Generate SearXNG config (MOVED from Script 1)
# --------------------------------------------------------------------------
generate_searxng_config() {
    section "Generating SearXNG Configuration"
    
    local searxng_config="${MNT_BASE}/configs/searxng/settings.yml"
    
    cat > "$searxng_config" << SEARXNG_EOF
# SearXNG Settings — Generated by Script 3
# Reference: https://docs.searxng.org/admin/settings/settings.html
use_default_settings: true

general:
  debug: false
  instance_name: "AI Platform Search"
  privacypolicy_url: false
  contact_url: false
  enable_metrics: false

server:
  secret_key: "${SEARXNG_SECRET_KEY}"
  limiter: false
  image_proxy: true
  method: "GET"
  base_url: false

ui:
  static_use_hash: true
  default_locale: "en"
  query_in_title: true
  infinite_scroll: false
  center_alignment: false
  default_theme: simple
  theme_args:
    simple_style: auto

search:
  safe_search: 0
  autocomplete: ""
  default_lang: "en"
  max_ban_time_on_fail: 5
  ban_time_on_fail: 5
  formats:
    - html
    - json

redis:
  url: redis://:${REDIS_PASSWORD}@redis:6379/0

engines:
  - name: google
    engine: google
    shortcut: g

  - name: duckduckgo
    engine: duckduckgo
    shortcut: d

  - name: wikipedia
    engine: wikipedia
    shortcut: wp

outgoing:
  request_timeout: 3.0
  useragent_suffix: ""
  pool_connections: 100
  pool_maxsize: 20
SEARXNG_EOF

    log "SearXNG config written to: $searxng_config"
    
    # SearXNG requires specific permissions
    chmod 644 "$searxng_config"
}

# --------------------------------------------------------------------------
# Generate Nginx config (MOVED from Script 1)
# --------------------------------------------------------------------------
generate_nginx_config() {
    [[ "$ENABLE_NGINX" != "true" ]] && return
    
    section "Generating Nginx Configuration"
    
    local nginx_conf="${MNT_BASE}/configs/nginx/nginx.conf"
    
    cat > "$nginx_conf" << NGINX_EOF
# Nginx Configuration — Generated by Script 3
# Reference: https://nginx.org/en/docs/

events {
  worker_connections 1024;
}

http {
  # Security headers
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header X-Content-Type-Options "nosniff" always;

  # Logging
  access_log /var/log/nginx/access.log;
  error_log  /var/log/nginx/error.log warn;

  # Open WebUI
  upstream open_webui {
    server open-webui:${OPEN_WEBUI_PORT};
  }

  # n8n
  upstream n8n_backend {
    server n8n:${N8N_PORT};
  }

  # SearXNG
  upstream searxng_backend {
    server searxng:${SEARXNG_PORT};
  }

  # Flowise
  upstream flowise_backend {
    server flowise:${FLOWISE_PORT};
  }

  server {
    listen 80;
    server_name _;

    # Open WebUI (default)
    location / {
      proxy_pass http://open_webui;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_read_timeout 300s;
    }

    location /n8n/ {
      proxy_pass http://n8n_backend/;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host \$host;
    }

    location /search/ {
      proxy_pass http://searxng_backend/;
      proxy_set_header Host \$host;
    }

    location /flowise/ {
      proxy_pass http://flowise_backend/;
      proxy_set_header Host \$host;
    }
  }
}
NGINX_EOF

    log "Nginx config written to: $nginx_conf"
}

# --------------------------------------------------------------------------
# Generate all configs (orchestrator)
# --------------------------------------------------------------------------
generate_all_configs() {
    generate_searxng_config
    generate_nginx_config
    log "All service configurations generated"
}

# --------------------------------------------------------------------------
# Print setup summary
# --------------------------------------------------------------------------
print_setup_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║           System Setup Complete ✓                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ✓ System packages installed"
    echo "  ✓ Docker configured"
    echo "  ✓ Directory structure created"
    echo "  ✓ Service configurations generated"
    echo ""
    echo "  Next step:"
    echo "  bash scripts/2-deploy-services.sh"
    echo ""
}

# --------------------------------------------------------------------------
# Configure Portainer (Post-deployment)
# --------------------------------------------------------------------------
configure_portainer() {
    section "Configuring Portainer — Mission Control"
    
    local portainer_url="https://${HOST_IP}:${PORTAINER_PORT}"
    local api="${portainer_url}/api"
    
    # Wait for Portainer API
    log "Waiting for Portainer API..."
    local attempt=0
    local max=24  # 2 minutes
    until curl -sf -k "${api}/status" -o /dev/null 2>/dev/null; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max ]]; then
            fail "Portainer API not responding after $((max * 5))s"
        fi
        log "  Waiting for Portainer... ${attempt}/${max}"
        sleep 5
    done
    log "Portainer API is up ✓"
    
    # Initialize admin user (if needed)
    log "Initializing Portainer admin user..."
    
    local init_response
    init_response=$(curl -sf -k \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"Username\":\"admin\",\"Password\":\"${PORTAINER_ADMIN_PASSWORD}\"}" \
        "${api}/users/admin/init" 2>/dev/null || echo "ALREADY_INIT")
    
    if echo "$init_response" | grep -q "ALREADY_INIT\|already been set"; then
        log "Portainer admin already initialized, proceeding with login"
    else
        log "Portainer admin initialized ✓"
    fi
    
    # Get JWT token
    log "Authenticating with Portainer..."
    local auth_response
    auth_response=$(curl -sf -k \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"Username\":\"admin\",\"Password\":\"${PORTAINER_ADMIN_PASSWORD}\"}" \
        "${api}/auth" 2>/dev/null)
    
    if [[ -z "$auth_response" ]]; then
        fail "Failed to authenticate with Portainer — check admin password"
    fi
    
    local portainer_token
    portainer_token=$(echo "$auth_response" | \
        python3 -c "import sys,json; print(json.load(sys.stdin)['jwt'])" 2>/dev/null || \
        echo "$auth_response" | grep -oP '"jwt":"\K[^"]+')
    
    if [[ -z "$portainer_token" ]]; then
        fail "Could not extract Portainer JWT token"
    fi
    log "Portainer authenticated ✓"
    
    # Configure local Docker endpoint
    log "Checking Portainer endpoints..."
    local endpoints_response
    endpoints_response=$(curl -sf -k \
        -H "Authorization: Bearer ${portainer_token}" \
        "${api}/endpoints" 2>/dev/null || echo "[]")
    
    local endpoint_count
    endpoint_count=$(echo "$endpoints_response" | \
        python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    
    if [[ "$endpoint_count" -eq 0 ]]; then
        log "Creating local Docker endpoint..."
        curl -sf -k \
            -X POST \
            -H "Authorization: Bearer ${portainer_token}" \
            -F "Name=local" \
            -F "EndpointCreationType=1" \
            "${api}/endpoints" 2>/dev/null || warn "Could not create local endpoint"
        log "Local Docker endpoint created ✓"
    else
        log "Portainer endpoints already configured ($endpoint_count found)"
    fi
    
    log "Portainer configuration complete ✓"
}

# --------------------------------------------------------------------------
# Wait for service health
# --------------------------------------------------------------------------
wait_for_healthy() {
    local container="$1"
    local max_wait="${2:-120}"
    local interval=5
    local elapsed=0
    
    log "Waiting for $container to be healthy (max ${max_wait}s)..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not_found")
        
        case "$status" in
            "healthy")
                log "$container is healthy ✓"
                return 0
                ;;
            "unhealthy")
                warn "$container is unhealthy! Checking logs..."
                docker logs --tail=20 "$container" 2>&1 || true
                return 1
                ;;
            "not_found")
                # Container may not have healthcheck — check if running
                local running
                running=$(docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null || echo "false")
                if [[ "$running" == "true" ]]; then
                    log "$container is running (no healthcheck defined)"
                    return 0
                fi
                ;;
            *)
                # starting or unknown
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
        log "  Waiting... ${elapsed}s / ${max_wait}s (status: $status)"
    done
    
    warn "$container did not become healthy within ${max_wait}s"
    return 1
}

# --------------------------------------------------------------------------
# Validate all services
# --------------------------------------------------------------------------
validate_all_services() {
    section "Validating All Services"
    
    local services=(
        "${PORTAINER_CONTAINER_NAME}"
        "${POSTGRES_CONTAINER_NAME}"
        "${REDIS_CONTAINER_NAME}"
        "${OLLAMA_CONTAINER_NAME}"
        "${OPEN_WEBUI_CONTAINER_NAME}"
        "${SEARXNG_CONTAINER_NAME}"
        "${N8N_CONTAINER_NAME}"
        "${FLOWISE_CONTAINER_NAME}"
    )
    
    local passed=0
    local failed=0
    
    for service in "${services[@]}"; do
        if wait_for_healthy "$service" 60; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
        fi
    done
    
    log "Service validation results: $passed passed, $failed failed"
    
    if [[ $failed -gt 0 ]]; then
        warn "Some services failed validation — check logs above"
        ERRORS=$((ERRORS + 1))
    else
        log "All services validated successfully ✓"
    fi
}

# --------------------------------------------------------------------------
# Validate bifrost connectivity
# --------------------------------------------------------------------------
validate_bifrost_connectivity() {
    section "Validating Bifrost Inter-Service Connectivity"
    
    # Test connectivity between key services
    local tests=(
        "${OPEN_WEBUI_CONTAINER_NAME}:${OLLAMA_CONTAINER_NAME}:${OLLAMA_PORT}:Open WebUI → Ollama"
        "${N8N_CONTAINER_NAME}:${POSTGRES_CONTAINER_NAME}:5432:n8n → PostgreSQL"
        "${N8N_CONTAINER_NAME}:${REDIS_CONTAINER_NAME}:6379:n8n → Redis"
        "${FLOWISE_CONTAINER_NAME}:${POSTGRES_CONTAINER_NAME}:5432:Flowise → PostgreSQL"
        "${SEARXNG_CONTAINER_NAME}:${REDIS_CONTAINER_NAME}:6379:SearXNG → Redis"
    )
    
    local passed=0
    local failed=0
    
    echo ""
    echo "  Connectivity Matrix:"
    echo "  ┌────────────────────────────────────────────┬──────────┐"
    echo "  │ Test                                   │ Status   │"
    echo "  ├────────────────────────────────────────────┼──────────┤"
    
    for test in "${tests[@]}"; do
        IFS=':' read -r from_container to_host to_port description <<< "$test"
        
        # Use nc (netcat) inside source container to test connectivity
        if docker exec "$from_container" \
            sh -c "nc -z -w3 ${to_host} ${to_port}" \
            2>/dev/null; then
            printf "  │ %-42s │ %-8s │\n" "$description" "✓ OK"
            passed=$((passed + 1))
        else
            printf "  │ %-42s │ %-8s │\n" "$description" "✗ FAIL"
            failed=$((failed + 1))
            warn "CONNECTIVITY FAIL: $description (${from_container} → ${to_host}:${to_port})"
        fi
    done
    
    echo "  └────────────────────────────────────────────┴──────────┘"
    echo ""
    log "Connectivity results: $passed passed, $failed failed"
    
    if [[ $failed -gt 0 ]]; then
        ERRORS=$((ERRORS + 1))
    fi
}

# --------------------------------------------------------------------------
# Write access summary
# --------------------------------------------------------------------------
write_access_summary() {
    section "Writing Access Summary"
    
    local summary_file="${MNT_BASE}/ACCESS_SUMMARY.md"
    
    cat > "$summary_file" << EOF
# AI Platform — Access Summary
Generated: $(date)

## Service Endpoints

| Service | URL | Credentials |
|---|---|---|
| **Portainer (Mission Control)** | https://${HOST_IP}:${PORTAINER_PORT} | admin / (set during setup) |
| **Open WebUI** | http://${HOST_IP}:${OPEN_WEBUI_PORT} | Register on first visit |
| **n8n** | http://${HOST_IP}:${N8N_PORT} | Register on first visit |
| **SearXNG** | http://${HOST_IP}:${SEARXNG_PORT} | No auth required |
| **Flowise** | http://${HOST_IP}:${FLOWISE_PORT} | ${FLOWISE_USERNAME} / (set during setup) |
| **Ollama API** | http://${HOST_IP}:${OLLAMA_PORT} | No auth (internal) |

## Internal Service Addresses (via Bifrost)

| Service | Internal Host | Port |
|---|---|---|
| PostgreSQL | ${POSTGRES_CONTAINER_NAME} | 5432 |
| Redis | ${REDIS_CONTAINER_NAME} | 6379 |
| Ollama | ${OLLAMA_CONTAINER_NAME} | ${OLLAMA_PORT} |
| Open WebUI | ${OPEN_WEBUI_CONTAINER_NAME} | ${OPEN_WEBUI_PORT} |
| n8n | ${N8N_CONTAINER_NAME} | ${N8N_PORT} |
| SearXNG | ${SEARXNG_CONTAINER_NAME} | ${SEARXNG_PORT} |
| Flowise | ${FLOWISE_CONTAINER_NAME} | ${FLOWISE_PORT} |

## Network
-- **Bifrost Subnet**: ${BIFROST_SUBNET}
-- **Bifrost Gateway**: ${BIFROST_GATEWAY}
-- **Bifrost MTU**: ${BIFROST_MTU}

## Data Location
All data is stored under: \`${MNT_BASE}/\`

## Useful Commands

\`\`\`bash
# View all AI Platform containers
docker ps --filter "label=ai-platform=true"

# Follow logs for any service
docker logs -f <service-name>

# Pull a new Ollama model
docker exec ollama ollama pull <model-name>

# Full restart
docker compose -f ${MNT_BASE}/docker-compose.yml restart

# Full teardown
bash scripts/0-complete-cleanup.sh
\`\`\`
EOF

    log "Access summary written to: $summary_file"
}

# --------------------------------------------------------------------------
# Final health report
# --------------------------------------------------------------------------
print_final_report() {
    section "Final Health Report"
    
    echo ""
    echo "  Container Health:"
    echo ""
    
    local all_healthy=true
    local services=(
        "${PORTAINER_CONTAINER_NAME}"
        "${POSTGRES_CONTAINER_NAME}"
        "${REDIS_CONTAINER_NAME}"
        "${OLLAMA_CONTAINER_NAME}"
        "${OPEN_WEBUI_CONTAINER_NAME}"
        "${SEARXNG_CONTAINER_NAME}"
        "${N8N_CONTAINER_NAME}"
        "${FLOWISE_CONTAINER_NAME}"
    )
    [[ "${ENABLE_NGINX}" == "true" ]] && services+=("nginx")
    
    echo "  ┌────────────────────┬───────────────────┬──────────────┐"
    echo "  │ Service            │ Status            │ Health       │"
    echo "  ├────────────────────┼───────────────────┼──────────────┤"
    
    for svc in "${services[@]}"; do
        local running status health
        running=$(docker inspect --format='{{.State.Running}}' "$svc" 2>/dev/null || echo "false")
        status=$(docker inspect --format='{{.State.Status}}' "$svc" 2>/dev/null || echo "not found")
        health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-check{{end}}' \
            "$svc" 2>/dev/null || echo "unknown")
        
        local status_icon="✓"
        if [[ "$running" != "true" ]]; then
            status_icon="✗"
            all_healthy=false
        fi
        
        printf "  │ %-18s │ %-17s │ %-12s │\n" \
            "$svc" "${status_icon} ${status}" "$health"
    done
    
    echo "  └────────────────────┴───────────────────┴──────────────┘"
    echo ""
    
    if [[ "$all_healthy" == "true" && $ERRORS -eq 0 ]]; then
        echo "  ✅ ALL SYSTEMS OPERATIONAL"
    else
        echo "  ⚠️  SOME SERVICES NEED ATTENTION — check logs above"
    fi
    
    echo ""
    echo "  Access summary: ${MNT_BASE}/ACCESS_SUMMARY.md"
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║           AI Platform Deployment Complete! 🚀            ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
}

# --------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------
main() {
    if [[ "${1:-}" == "--setup-only" ]]; then
        # PRE-DEPLOYMENT setup (called by Script 1)
        log "=== Script 3: Mission Control (Setup Mode) ==="
        
        load_env                    # Load before any operations
        install_system_packages      # Moved from Script 1
        configure_docker           # Moved from Script 1
        create_directory_structure   # Moved from Script 1
        generate_all_configs       # Moved from Script 1
        print_setup_summary
        return 0
    fi

    # DEFAULT MODE - POST-DEPLOYMENT configuration
    log "=== Script 3: Mission Control (Configuration Mode) ==="
    
    # Load env FIRST, then use its variables in guard
    load_env

    local portainer_name="${PORTAINER_CONTAINER_NAME:-portainer}"
    
    if ! docker ps \
        --filter "name=${portainer_name}" \
        --filter "status=running" \
        -q 2>/dev/null | grep -q .; then
        echo ""
        echo "  ERROR: ${portainer_name} is not running."
        echo "  Run Script 2 first: bash scripts/2-deploy-services.sh"
        echo ""
        echo "  If you want pre-deployment setup only:"
        echo "  bash scripts/3-configure-services.sh --setup-only"
        echo ""
        exit 1
    fi

    # Post-deployment functions
    configure_portainer
    validate_all_services
    validate_bifrost_connectivity
    write_access_summary
    print_final_report
}

main "$@"
