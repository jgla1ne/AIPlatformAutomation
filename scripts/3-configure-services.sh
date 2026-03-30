#!/usr/bin/env bash
# =============================================================================
# Script 3: Mission Control - BULLETPROOF v5.0 FINAL
# =============================================================================
# PURPOSE: Verification + operations + per-service rotation
# USAGE:   sudo bash scripts/3-configure-services.sh [tenant_id] [options]
# OPTIONS: --setup-only         System setup mode (called by Script 1)
#          --verify-only       Verification only, no operations
#          --show-credentials  Display service credentials
#          --rotate-keys [service] Rotate keys for specific service or all
#          --reload-proxy      Reload reverse proxy configuration
#          --test-connectivity Test inter-service connectivity
# =============================================================================

set -euo pipefail

# =============================================================================
# NON-ROOT EXECUTION CHECK (README P7 - mandatory)
# =============================================================================
if [[ $EUID -eq 0 ]]; then
    fail "This script must not be run as root (README P7 requirement)"
fi

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# =============================================================================
# LOGGING AND UTILITIES (README P11 - mandatory dual logging)
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# Set up log file (will be set after tenant_id is known)
LOG_FILE=""

log() { 
    local msg="[$(date +%H:%M:%S)] $*"
    echo -e "${CYAN}[INFO]${NC}    $1"
    [[ -n "$LOG_FILE" ]] && echo "${msg}" >> "$LOG_FILE"
}
ok() { 
    local msg="[$(date +%H:%M:%S)] $*"
    echo -e "${GREEN}[OK]${NC}      $*"
    [[ -n "$LOG_FILE" ]] && echo "${msg}" >> "$LOG_FILE"
}
warn() { 
    local msg="[$(date +%H:%M:%S)] $*"
    echo -e "${YELLOW}[WARN]${NC}    $*"
    [[ -n "$LOG_FILE" ]] && echo "${msg}" >> "$LOG_FILE"
}
fail() { 
    local msg="[$(date +%H:%M:%S)] $*"
    echo -e "${RED}[FAIL]${NC}    $*"
    [[ -n "$LOG_FILE" ]] && echo "${msg}" >> "$LOG_FILE"
    exit 1
}
section() { 
    echo "" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && echo "  $*" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    [[ -n "$LOG_FILE" ]] && echo "" >> "$LOG_FILE" && echo "=== $* ===" >> "$LOG_FILE"
}
dry_run() { [[ "${DRY_RUN:-false}" == "true" ]] && echo -e "${BLUE}[DRY-RUN]${NC} $1"; }

# =============================================================================
# FRAMEWORK VALIDATION
# =============================================================================
framework_validate() {
    log "Validating mission control framework..."
    
    # Binary availability checks
    local missing_bins=()
    for bin in docker curl jq; do
        if ! command -v "$bin" >/dev/null 2>&1; then
            missing_bins+=("$bin")
        fi
    done
    
    if [[ ${#missing_bins[@]} -gt 0 ]]; then
        fail "Missing required binaries: ${missing_bins[*]}"
    fi
    
    # Docker daemon health
    if ! docker info >/dev/null 2>&1; then
        fail "Docker daemon not running or accessible"
    fi
    
    ok "Framework validation passed"
}

# =============================================================================
# LOAD PLATFORM CONF
# =============================================================================
load_platform_conf() {
    local tenant_id="$1"
    local platform_conf="/mnt/${tenant_id}/config/platform.conf"
    
    # Guard: Ensure Script 1 ran first
    if [[ ! -f "$platform_conf" ]]; then
        fail "platform.conf not found at $platform_conf - run Script 1 first"
    fi
    
    # Source platform.conf (README-compliant approach)
    source "$platform_conf"
    log "Loaded platform.conf from $platform_conf"
    
    # Validate critical variables
    local critical_vars=(
        "TENANT_ID" "BASE_DIR" "CONFIG_DIR" "DOCKER_NETWORK"
        "POSTGRES_USER" "POSTGRES_PASSWORD" "POSTGRES_DB"
    )
    
    local missing=()
    for var in "${critical_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        fail "Missing critical variables in platform.conf: ${missing[*]}"
    fi
    
    # Set derived variables
    CONFIGURED_DIR="${BASE_DIR}/.configured"
    
    # Set up log file (README P11 - after tenant_id is known)
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        mkdir -p "${BASE_DIR}/logs"
        LOG_FILE="${BASE_DIR}/logs/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S).log"
        log "Log file: $LOG_FILE"
    fi
}

# =============================================================================
# IDEMPOTENCY MARKERS (README P8 - mandatory)
# =============================================================================
step_done() {
    [[ -f "${CONFIGURED_DIR}/${1}" ]]
}

mark_done() {
    touch "${CONFIGURED_DIR}/${1}"
    log "Marked step complete: ${1}"
}

# =============================================================================
# SETUP MODE FUNCTIONS (called by Script 1)
# =============================================================================
install_system_packages() {
    section "Installing System Packages"
    
    log "Updating package lists..."
    apt-get update -qq
    
    # Install required packages including yq (Expert Fix)
    local packages=(
        "curl"
        "wget"
        "git"
        "jq"
        "yq"  # Added for YAML validation (Expert Fix)
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
    apt-get install -y -qq "${packages[@]}"
    
    ok "System packages installed"
}

configure_docker() {
    section "Configuring Docker"
    
    # Add current user to docker group
    if ! groups "$(whoami)" | grep -q docker; then
        usermod -aG docker "$(whoami)"
        log "Added $(whoami) to docker group (re-login may be needed)"
        warn "You may need to log out and back in for docker group to take effect"
    else
        log "User already in docker group"
    fi
    
    # Configure docker daemon
    local daemon_config="/etc/docker/daemon.json"
    
    if [[ ! -f "$daemon_config" ]]; then
        cat > "$daemon_config" << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "mtu": ${DOCKER_MTU}
}
EOF
        log "Docker daemon configured (MTU: $DOCKER_MTU)"
        
        # Restart docker to apply daemon config
        systemctl restart docker
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
        log "Docker daemon.json already exists, skipping"
    fi
}

create_directory_structure() {
    section "Creating Directory Structure"
    
    local dirs=(
        "${BASE_DIR}/data/postgres"
        "${BASE_DIR}/data/redis"
        "${BASE_DIR}/data/ollama"
        "${BASE_DIR}/data/open-webui"
        "${BASE_DIR}/data/qdrant"
        "${BASE_DIR}/data/weaviate"
        "${BASE_DIR}/data/chroma"
        "${BASE_DIR}/data/n8n"
        "${BASE_DIR}/data/flowise"
        "${BASE_DIR}/data/searxng"
        "${BASE_DIR}/data/authentik"
        "${BASE_DIR}/data/grafana"
        "${BASE_DIR}/data/prometheus"
        "${CONFIG_DIR}/ssl"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    # Set ownership (README-compliant)
    chown -R 1000:1000 "${BASE_DIR}"
    
    ok "Directory structure created"
}

# =============================================================================
# VERIFICATION FUNCTIONS
# =============================================================================
verify_deployment_health() {
    section "Verifying Deployment Health"
    
    log "Checking if services are deployed..."
    
    # Check if any containers are running for this tenant
    local running_containers
    running_containers=$(docker ps --filter "label=com.docker.compose.project=${TENANT_ID}" -q)
    
    if [[ -z "$running_containers" ]]; then
        fail "No containers found for tenant ${TENANT_ID}. Run Script 2 first."
    fi
    
    log "Found $(echo "$running_containers" | wc -l) running containers"
    
    # Pre-flight health check of running stack (Expert Fix)
    verify_service_health
    
    ok "Deployment health verified"
}

verify_service_health() {
    log "Verifying individual service health..."
    
    local services=()
    local passed=0
    local failed=0
    
    # Build service list based on enabled services
    if [[ "$POSTGRES_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_postgres")
    fi
    
    if [[ "$REDIS_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_redis")
    fi
    
    if [[ "$OLLAMA_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_ollama")
    fi
    
    if [[ "$LITELLM_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_litellm")
    fi
    
    if [[ "$BIFROST_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_bifrost")
    fi
    
    if [[ "$OPEN_WEBUI_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_open-webui")
    fi
    
    if [[ "$QDRANT_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_qdrant")
    fi
    
    if [[ "$WEAVIATE_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_weaviate")
    fi
    
    if [[ "$CHROMA_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_chroma")
    fi
    
    if [[ "$N8N_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_n8n")
    fi
    
    if [[ "$FLOWISE_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_flowise")
    fi
    
    if [[ "$SEARXNG_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_searxng")
    fi
    
    if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_authentik")
    fi
    
    if [[ "$GRAFANA_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_grafana")
    fi
    
    if [[ "$PROMETHEUS_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_prometheus")
    fi
    
    if [[ "$CADDY_ENABLED" == "true" ]]; then
        services+=("${PREFIX}${TENANT_ID}_caddy")
    fi
    
    for service in "${services[@]}"; do
        if wait_for_healthy "$service" 60; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
        fi
    done
    
    log "Service health results: $passed passed, $failed failed"
    
    if [[ $failed -gt 0 ]]; then
        warn "Some services failed health check - check logs"
    else
        ok "All services healthy"
    fi
}

wait_for_healthy() {
    local container="$1"
    local max_wait="${2:-120}"
    local interval=5
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        local status
        status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "not_found") # Expert Fix
        
        case "$status" in
            "running")
                # Check if healthcheck is defined
                local health_status
                health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
                
                case "$health_status" in
                    "healthy")
                        return 0
                        ;;
                    "unhealthy")
                        return 1
                        ;;
                    "none")
                        return 0  # No healthcheck defined, but running
                        ;;
                esac
                ;;
            "not_found")
                return 1
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    return 1
}

verify_inter_service_connectivity() {
    section "Verifying Inter-Service Connectivity"
    
    log "Testing connectivity between services..."
    
    local tests=()
    local passed=0
    local failed=0
    
    # Build connectivity tests based on enabled services
    if [[ "$OPEN_WEBUI_ENABLED" == "true" && "$LITELLM_ENABLED" == "true" ]]; then
        tests+=("${PREFIX}${TENANT_ID}_open-webui:litellm:4000:Open WebUI → LiteLLM")
    fi
    
    if [[ "$OPEN_WEBUI_ENABLED" == "true" && "$BIFROST_ENABLED" == "true" ]]; then
        tests+=("${PREFIX}${TENANT_ID}_open-webui:bifrost:8000:Open WebUI → Bifrost")
    fi
    
    if [[ "$N8N_ENABLED" == "true" && "$POSTGRES_ENABLED" == "true" ]]; then
        tests+=("${PREFIX}${TENANT_ID}_n8n:postgres:5432:n8n → PostgreSQL")
    fi
    
    if [[ "$N8N_ENABLED" == "true" && "$REDIS_ENABLED" == "true" ]]; then
        tests+=("${PREFIX}${TENANT_ID}_n8n:redis:6379:n8n → Redis")
    fi
    
    if [[ "$FLOWISE_ENABLED" == "true" && "$POSTGRES_ENABLED" == "true" ]]; then
        tests+=("${PREFIX}${TENANT_ID}_flowise:postgres:5432:Flowise → PostgreSQL")
    fi
    
    echo ""
    echo "  Connectivity Matrix:"
    echo "  ┌────────────────────────────────────────────┬──────────┐"
    echo "  │ Test                                   │ Status   │"
    echo "  ├────────────────────────────────────────────┼──────────┤"
    
    for test in "${tests[@]}"; do
        IFS=':' read -r from_container to_host to_port description <<< "$test"
        
        # Use docker exec to test connectivity (Expert Fix)
        if docker exec "$from_container" \
            sh -c "nc -z -w3 ${to_host} ${to_port}" \
            2>/dev/null; then
            printf "  │ %-42s │ %-8s │\n" "$description" "✓ OK"
            passed=$((passed + 1))
        else
            printf "  │ %-42s │ %-8s │\n" "$description" "✗ FAIL"
            failed=$((failed + 1))
        fi
    done
    
    echo "  └────────────────────────────────────────────┴──────────┘"
    echo ""
    
    log "Connectivity results: $passed passed, $failed failed"
    
    if [[ $failed -gt 0 ]]; then
        warn "Some connectivity tests failed"
    else
        ok "All connectivity tests passed"
    fi
}

verify_api_functionality() {
    section "Verifying API Functionality"
    
    log "Testing service API endpoints..."
    
    local tests=()
    local passed=0
    local failed=0
    
    # Build API tests based on enabled services
    if [[ "$POSTGRES_ENABLED" == "true" ]]; then
        tests+=("postgres:${POSTGRES_PORT}:pg_isready:PostgreSQL API")
    fi
    
    if [[ "$REDIS_ENABLED" == "true" ]]; then
        tests+=("redis:${REDIS_PORT}:redis-cli:Redis API")
    fi
    
    if [[ "$OLLAMA_ENABLED" == "true" ]]; then
        tests+=("ollama:${OLLAMA_PORT}:/api/tags:Ollama API")
    fi
    
    if [[ "$LITELLM_ENABLED" == "true" ]]; then
        tests+=("litellm:${LITELLM_PORT}:/health:LiteLLM API")
    fi
    
    if [[ "$BIFROST_ENABLED" == "true" ]]; then
        tests+=("bifrost:${BIFROST_PORT}:/health:Bifrost API")
    fi
    
    if [[ "$QDRANT_ENABLED" == "true" ]]; then
        tests+=("qdrant:${QDRANT_PORT}:/healthz:Qdrant API")
    fi
    
    if [[ "$WEAVIATE_ENABLED" == "true" ]]; then
        tests+=("weaviate:${WEAVIATE_PORT}:/v1/.well-known/ready:Weaviate API")
    fi
    
    if [[ "$CHROMA_ENABLED" == "true" ]]; then
        tests+=("chroma:${CHROMA_PORT}:/api/v1/heartbeat:Chroma API")
    fi
    
    echo ""
    echo "  API Functionality Tests:"
    echo "  ┌────────────────────────────────────────────┬──────────┐"
    echo "  │ Test                                   │ Status   │"
    echo "  ├────────────────────────────────────────────┼──────────┤"
    
    for test in "${tests[@]}"; do
        IFS=':' read -r service port endpoint description <<< "$test"
        
        # Test API using docker run with network (Expert Fix)
        if docker run --rm --network "${DOCKER_NETWORK}" \
            alpine/curl:latest \
            curl -f -s --max-time 5 \
            "http://${service}:${port}${endpoint}" >/dev/null 2>&1; then
            printf "  │ %-42s │ %-8s │\n" "$description" "✓ OK"
            passed=$((passed + 1))
        else
            printf "  │ %-42s │ %-8s │\n" "$description" "✗ FAIL"
            failed=$((failed + 1))
        fi
    done
    
    echo "  └────────────────────────────────────────────┴──────────┘"
    echo ""
    
    log "API functionality results: $passed passed, $failed failed"
    
    if [[ $failed -gt 0 ]]; then
        warn "Some API tests failed"
    else
        ok "All API tests passed"
    fi
}

# =============================================================================
# OPERATIONS FUNCTIONS
# =============================================================================
show_credentials() {
    section "Service Credentials"
    
    warn "🔐 SENSITIVE INFORMATION - Keep this secure!"
    echo ""
    
    echo "  Database Credentials:"
    if [[ "$POSTGRES_ENABLED" == "true" ]]; then
        echo "    PostgreSQL User: ${POSTGRES_USER}"
        echo "    PostgreSQL Password: ${POSTGRES_PASSWORD}"
        echo "    PostgreSQL Database: ${POSTGRES_DB}"
    fi
    
    if [[ "$REDIS_ENABLED" == "true" ]]; then
        echo "    Redis Password: ${REDIS_PASSWORD}"
    fi
    
    echo ""
    echo "  LLM Proxy Credentials:"
    if [[ "$LITELLM_ENABLED" == "true" ]]; then
        echo "    LiteLLM Master Key: ${LITELLM_MASTER_KEY}"
    fi
    
    echo ""
    echo "  Authentication Credentials:"
    if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
        echo "    Authentik Bootstrap Email: ${AUTHENTIK_BOOTSTRAP_EMAIL}"
        echo "    Authentik Bootstrap Password: ${AUTHENTIK_BOOTSTRAP_PASSWORD}"
    fi
    
    echo ""
    echo "  Generated Secrets:"
    echo "    n8n Encryption Key: ${N8N_ENCRYPTION_KEY}"
    echo "    SearXNG Secret Key: ${SEARXNG_SECRET_KEY}"
    echo "    Flowise Secret Key: ${FLOWISE_SECRET_KEY}"
    
    echo ""
}

rotate_keys() {
    local service="${1:-all}"
    
    section "Rotating Keys"
    
    case "$service" in
        "litellm")
            if [[ "$LITELLM_ENABLED" == "true" ]]; then
                log "Rotating LiteLLM master key..."
                local new_key=$(openssl rand -hex 32)
                
                # Update platform.conf
                sed -i "s/^LITELLM_MASTER_KEY=.*/LITELLM_MASTER_KEY=${new_key}/" "/mnt/${TENANT_ID}/config/platform.conf"
                
                # Restart LiteLLM container
                local container="${PREFIX}${TENANT_ID}_litellm"
                if docker restart "$container" >/dev/null 2>&1; then
                    wait_for_healthy "$container" 60
                    ok "LiteLLM key rotated and service restarted"
                else
                    fail "Failed to restart LiteLLM service"
                fi
            else
                fail "LiteLLM service not enabled"
            fi
            ;;
        "authentik")
            if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
                log "Rotating Authentik bootstrap password..."
                local new_password=$(openssl rand -hex 16)
                
                # Update platform.conf
                sed -i "s/^AUTHENTIK_BOOTSTRAP_PASSWORD=.*/AUTHENTIK_BOOTSTRAP_PASSWORD=${new_password}/" "/mnt/${TENANT_ID}/config/platform.conf"
                
                # Restart Authentik container
                local container="${PREFIX}${TENANT_ID}_authentik"
                if docker restart "$container" >/dev/null 2>&1; then
                    wait_for_healthy "$container" 60
                    ok "Authentik password rotated and service restarted"
                else
                    fail "Failed to restart Authentik service"
                fi
            else
                fail "Authentik service not enabled"
            fi
            ;;
        "all")
            log "Rotating all service keys..."
            
            # Rotate all enabled services
            if [[ "$LITELLM_ENABLED" == "true" ]]; then
                rotate_keys "litellm"
            fi
            
            if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
                rotate_keys "authentik"
            fi
            
            ok "All service keys rotated"
            ;;
        *)
            fail "Unknown service for key rotation: $service. Use: litellm, authentik, or all"
            ;;
    esac
}

reload_proxy() {
    section "Reloading Reverse Proxy"
    
    if [[ "$CADDY_ENABLED" == "true" ]]; then
        log "Reloading Caddy configuration..."
        
        local container="${PREFIX}${TENANT_ID}_caddy"
        
        # Validate Caddyfile first
        if ! docker exec "$container" caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
            fail "Caddyfile validation failed"
        fi
        
        # Reload Caddy
        if docker exec "$container" caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
            ok "Caddy reloaded successfully"
        else
            fail "Failed to reload Caddy"
        fi
    else
        warn "No reverse proxy enabled"
    fi
}

# =============================================================================
# AUTHENTIK BOOTSTRAP VERIFICATION (Expert Fix)
# =============================================================================
verify_authentik_bootstrap() {
    if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
        log "Verifying Authentik bootstrap..."
        
        # Wait for Authentik to be ready
        wait_for_healthy "${PREFIX}${TENANT_ID}_authentik" 120
        
        # Verify bootstrap worked (Expert Fix - verification only, not creation)
        local response
        response=$(docker run --rm --network "${DOCKER_NETWORK}" \
            alpine/curl:latest \
            curl -s -o /dev/null -w "%{http_code}" \
            -u "${AUTHENTIK_BOOTSTRAP_EMAIL}:${AUTHENTIK_BOOTSTRAP_PASSWORD}" \
            "http://authentik:9000/api/v2/-/core/users/me/" 2>/dev/null || echo "000")
        
        if [[ "$response" == "200" ]]; then
            ok "Authentik bootstrap verification successful"
        else
            fail "Authentik bootstrap verification failed (HTTP $response)"
        fi
    fi
}

# =============================================================================
# REPORTING FUNCTIONS
# =============================================================================
write_access_summary() {
    section "Writing Access Summary"
    
    local summary_file="${BASE_DIR}/ACCESS_SUMMARY.md"
    
    cat > "$summary_file" << EOF
# AI Platform — Access Summary
Generated: $(date)
Tenant: ${TENANT_ID}

## Service Endpoints

| Service | URL | Credentials |
|---|---|---|
EOF
    
    if [[ "$OPEN_WEBUI_ENABLED" == "true" ]]; then
        echo "| **Open WebUI** | http://${HOST_IP}:${OPEN_WEBUI_PORT} | Register on first visit |" >> "$summary_file"
    fi
    
    if [[ "$OLLAMA_ENABLED" == "true" ]]; then
        echo "| **Ollama API** | http://${HOST_IP}:${OLLAMA_PORT} | No auth (internal) |" >> "$summary_file"
    fi
    
    if [[ "$LITELLM_ENABLED" == "true" ]]; then
        echo "| **LiteLLM** | http://${HOST_IP}:${LITELLM_PORT} | API key required |" >> "$summary_file"
    fi
    
    if [[ "$BIFROST_ENABLED" == "true" ]]; then
        echo "| **Bifrost** | http://${HOST_IP}:${BIFROST_PORT} | No auth (internal) |" >> "$summary_file"
    fi
    
    if [[ "$QDRANT_ENABLED" == "true" ]]; then
        echo "| **Qdrant** | http://${HOST_IP}:${QDRANT_PORT} | No auth (internal) |" >> "$summary_file"
    fi
    
    if [[ "$WEAVIATE_ENABLED" == "true" ]]; then
        echo "| **Weaviate** | http://${HOST_IP}:${WEAVIATE_PORT} | No auth (internal) |" >> "$summary_file"
    fi
    
    if [[ "$CHROMA_ENABLED" == "true" ]]; then
        echo "| **Chroma** | http://${HOST_IP}:${CHROMA_PORT} | No auth (internal) |" >> "$summary_file"
    fi
    
    if [[ "$N8N_ENABLED" == "true" ]]; then
        echo "| **n8n** | http://${HOST_IP}:${N8N_PORT} | Register on first visit |" >> "$summary_file"
    fi
    
    if [[ "$FLOWISE_ENABLED" == "true" ]]; then
        echo "| **Flowise** | http://${HOST_IP}:${FLOWISE_PORT} | admin / (set during setup) |" >> "$summary_file"
    fi
    
    if [[ "$SEARXNG_ENABLED" == "true" ]]; then
        echo "| **SearXNG** | http://${HOST_IP}:${SEARXNG_PORT} | No auth required |" >> "$summary_file"
    fi
    
    if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
        echo "| **Authentik** | http://${HOST_IP}:${AUTHENTIK_PORT} | ${AUTHENTIK_BOOTSTRAP_EMAIL} / (set during setup) |" >> "$summary_file"
    fi
    
    if [[ "$GRAFANA_ENABLED" == "true" ]]; then
        echo "| **Grafana** | http://${HOST_IP}:${GRAFANA_PORT} | admin / (set during setup) |" >> "$summary_file"
    fi
    
    if [[ "$PROMETHEUS_ENABLED" == "true" ]]; then
        echo "| **Prometheus** | http://${HOST_IP}:${PROMETHEUS_PORT} | No auth (internal) |" >> "$summary_file"
    fi
    
    cat >> "$summary_file" << EOF

## Network Configuration
- **Docker Network**: ${DOCKER_NETWORK}
- **Subnet**: ${DOCKER_SUBNET}
- **Gateway**: ${DOCKER_GATEWAY}
- **MTU**: ${DOCKER_MTU}

## Data Location
All data is stored under: \`${BASE_DIR}/\`

## Stack Configuration
- **Preset**: ${STACK_PRESET}
- **GPU Type**: ${GPU_TYPE}
- **Platform Architecture**: ${PLATFORM_ARCH}

## Useful Commands

\`\`\`bash
# View all AI Platform containers
docker ps --filter "label=com.docker.compose.project=${TENANT_ID}"

# Follow logs for any service
docker logs -f <service-name>

# Pull a new Ollama model
docker exec ${PREFIX}${TENANT_ID}_ollama ollama pull <model-name>

# Full restart
docker compose -f ${CONFIG_DIR}/docker-compose.yml restart

# Full teardown
bash scripts/0-complete-cleanup.sh ${TENANT_ID}

# Show credentials
bash scripts/3-configure-services.sh ${TENANT_ID} --show-credentials

# Rotate keys
bash scripts/3-configure-services.sh ${TENANT_ID} --rotate-keys [service]
\`\`\`
EOF

    ok "Access summary written to: $summary_file"
}

print_final_report() {
    section "Final Health Report"
    
    echo ""
    echo "  Container Health:"
    echo ""
    
    local all_healthy=true
    local containers
    containers=$(docker ps --filter "label=com.docker.compose.project=${TENANT_ID}" --format "{{.Names}}")
    
    echo "  ┌────────────────────┬───────────────────┬──────────────┐"
    echo "  │ Service            │ Status            │ Health       │"
    echo "  ├────────────────────┼───────────────────┼──────────────┤"
    
    for container in $containers; do
        local running status health
        running=$(docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null || echo "false")
        status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "not found")
        health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-check{{end}}' \
            "$container" 2>/dev/null || echo "unknown")
        
        local status_icon="✓"
        if [[ "$running" != "true" ]]; then
            status_icon="✗"
            all_healthy=false
        fi
        
        printf "  │ %-18s │ %-17s │ %-12s │\n" \
            "$container" "${status_icon} ${status}" "$health"
    done
    
    echo "  └────────────────────┴───────────────────┴──────────────┘"
    echo ""
    
    if [[ "$all_healthy" == "true" ]]; then
        echo "  ✅ ALL SYSTEMS OPERATIONAL"
    else
        echo "  ⚠️  SOME SERVICES NEED ATTENTION"
    fi
    
    echo ""
    echo "  Access summary: ${BASE_DIR}/ACCESS_SUMMARY.md"
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║           AI Platform Mission Control Complete! 🚀         ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    local tenant_id="${1:-default}"
    local mode="default"
    local target_service=""
    
    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --setup-only)
                mode="setup"
                shift
                ;;
            --verify-only)
                mode="verify"
                shift
                ;;
            --show-credentials)
                mode="credentials"
                shift
                ;;
            --rotate-keys)
                mode="rotate"
                target_service="${2:-all}"
                shift 2
                ;;
            --reload-proxy)
                mode="reload"
                shift
                ;;
            --test-connectivity)
                mode="connectivity"
                shift
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
    
    log "=== Script 3: Mission Control ==="
    log "Tenant: ${tenant_id}"
    log "Mode: ${mode}"
    
    # Framework validation
    framework_validate
    
    # Load platform.conf
    load_platform_conf "$tenant_id"
    
    case "$mode" in
        "setup")
            log "Setup mode - preparing system for deployment"
            install_system_packages
            configure_docker
            create_directory_structure
            ok "System setup complete"
            ;;
        "verify")
            log "Verification mode - checking deployment health"
            verify_deployment_health
            verify_service_health
            verify_inter_service_connectivity
            verify_api_functionality
            verify_authentik_bootstrap
            write_access_summary
            print_final_report
            ;;
        "credentials")
            show_credentials
            ;;
        "rotate")
            rotate_keys "$target_service"
            ;;
        "reload")
            reload_proxy
            ;;
        "connectivity")
            verify_inter_service_connectivity
            ;;
        "default")
            log "Default mode - full mission control"
            verify_deployment_health
            verify_service_health
            verify_inter_service_connectivity
            verify_api_functionality
            verify_authentik_bootstrap
            write_access_summary
            print_final_report
            ;;
    esac
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
