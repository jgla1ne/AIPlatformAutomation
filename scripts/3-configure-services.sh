#!/bin/bash
# Script 3: Operations & Management
#
# NOTE: This script runs as root (required for Docker operations)
# STACK_USER_UID owns BASE_DIR for container permissions

set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# UI Functions
print_banner() {
    clear
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            AI PLATFORM - OPERATIONS & MANAGEMENT           ║${NC}"
    echo -e "${CYAN}║              Baseline v1.0.0 - Multi-Stack Ready           ║${NC}"
    echo -e "${CYAN}║           Stack-Aware Operations (renew, restart, status)   ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╝${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    local title="$1"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $title"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Auto-detect stack from current directory or environment
detect_stack() {
    # Load environment using the same pattern as Script 2
    if [ -f /etc/ai-platform/env-pointer ]; then
        DATA_ROOT="$(cat /etc/ai-platform/env-pointer)"
    fi
    
    # ── STRUCTURED LOGGING SETUP ───────────────────────────────────────────────────────
    LOG_DIR="${DATA_ROOT}/logs"
    mkdir -p "${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/script-3-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "${LOG_FILE}") 2>&1
    
    if [ -z "${DATA_ROOT:-}" ]; then
        DATA_ROOT="${BASE_DIR:-/mnt/data}"
    fi
    
    ENV_FILE="${DATA_ROOT}/.env"
    
    if [ ! -f "${ENV_FILE}" ]; then
        print_error "Environment file not found: ${ENV_FILE}"
        print_info "Run Script 1 first to create configuration."
        exit 1
    fi
    
    # Load environment variables
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
    
    if [[ -f "${ENV_FILE}" ]]; then
        print_success "Stack detected: ${DOMAIN_NAME:-localhost}"
    else
        print_error "No stack configuration found. Run Script 1 first."
        exit 1
    fi
}

# Renew SSL certificates
renew_ssl() {
    print_header "Renewing SSL Certificates"
    
    detect_stack
    
    if docker ps --format "{{.Names}}" | grep -q "^caddy$"; then
        print_info "Reloading Caddy configuration for ${DOMAIN_NAME}"
        if docker exec "caddy" caddy reload --config "/etc/caddy/Caddyfile"; then
            print_success "SSL certificates renewed"
        else
            print_error "Failed to reload Caddy"
            return 1
        fi
    else
        print_warning "Caddy container not found"
    fi
}

# Restart specific service
restart_service() {
    local service_name=$1
    
    if [[ -z "$service_name" ]]; then
        print_error "Usage: $0 restart <service_name>"
        return 1
    fi
    
    print_header "Restarting Service: ${service_name}"
    
    detect_stack
    
    if docker ps --format "{{.Names}}" | grep -q "^${service_name}$"; then
        print_info "Restarting ${service_name}..."
        if docker restart "${service_name}"; then
            print_success "${service_name} restarted successfully"
        else
            print_error "Failed to restart ${service_name}"
            return 1
        fi
    else
        print_error "Service ${service_name} not found"
        return 1
    fi
}

# Show stack status
show_status() {
    print_header "Stack Status"
    
    detect_stack
    
    echo "📊 Stack Information:"
    echo "   Domain: ${DOMAIN_NAME}"
    echo "   User UID/GID: ${STACK_USER_UID}:${STACK_USER_GID}"
    echo "   Network: ${DOCKER_NETWORK}"
    echo "   Base Directory: ${BASE_DIR}"
    echo ""
    
    echo "🔧 Running Services:"
    docker ps --network "${DOCKER_NETWORK}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || {
        print_warning "No services found on network ${DOCKER_NETWORK}"
    }
    echo ""
    
    echo "📈 Resource Usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" --filter "network=${DOCKER_NETWORK}" || {
        print_info "No resource data available"
    }
}

# Health check all services
health_check() {
    print_header "Health Check"
    
    detect_stack
    
    echo "🔍 Checking service health for ${DOMAIN_NAME}:"
    echo ""
    
    local services=(postgres redis qdrant ollama n8n anythingllm litellm openwebui minio caddy)
    local healthy_count=0
    local unhealthy_count=0
    
    for service in "${services[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${service}$"; then
            # Check if container is healthy
            local health=$(docker inspect --format='{{.State.Health.Status}}' "${service}" 2>/dev/null || echo "none")
            local status=$(docker inspect --format='{{.State.Status}}' "${service}" 2>/dev/null || echo "unknown")
            
            if [[ "$health" == "healthy" ]] || [[ "$status" == "running" && "$health" == "none" ]]; then
                print_success "${service}: Healthy"
                ((healthy_count++))
            elif [[ "$health" == "unhealthy" ]]; then
                print_error "${service}: Unhealthy"
                ((unhealthy_count++))
            else
                print_warning "${service}: $status"
                ((unhealthy_count++))
            fi
        else
            print_error "${service}: Not running"
            ((unhealthy_count++))
        fi
    done
    
    echo ""
    echo "📊 Health Summary:"
    echo "   Healthy: $healthy_count"
    echo "   Unhealthy: $unhealthy_count"
    
    if [[ $unhealthy_count -eq 0 ]]; then
        print_success "All services are healthy!"
    else
        print_warning "Some services need attention"
    fi
}

# Show service logs
show_logs() {
    local service_name=$1
    local lines=${2:-50}
    
    if [[ -z "$service_name" ]]; then
        print_error "Usage: $0 logs <service_name> [lines]"
        return 1
    fi
    
    print_header "Service Logs: ${service_name}"
    
    detect_stack
    
    if docker ps --format "{{.Names}}" | grep -q "^${service_name}$"; then
        print_info "Showing last ${lines} lines of logs for ${service_name}..."
        docker logs --tail "$lines" -f "${service_name}"
    else
        print_error "Service ${service_name} not found"
        return 1
    fi
}

# Show service configuration
show_config() {
    local service_name=$1
    
    if [[ -z "$service_name" ]]; then
        print_error "Usage: $0 config <service_name>"
        return 1
    fi
    
    print_header "Service Configuration: ${service_name}"
    
    detect_stack
    
    if docker ps --format "{{.Names}}" | grep -q "^${service_name}$"; then
        echo "🔧 Container Configuration:"
        docker inspect "${service_name}" --format='{{json .Config}}' | jq -r '
        to_entries | 
        select(.key | test("Env|Labels|User|WorkingDir|ExposedPorts")) |
        "\(.key): \(.value)"'
        
        echo ""
        echo "🌐 Network Configuration:"
        docker inspect "${service_name}" --format='{{json .NetworkSettings}}' | jq -r '
        to_entries | 
        select(.key | test("Networks|Ports")) |
        "\(.key): \(.value)"'
    else
        print_error "Service ${service_name} not found"
        return 1
    fi
}

# Cleanup unused resources
cleanup() {
    print_header "Cleaning Up Unused Resources"
    
    detect_stack
    
    print_info "Removing stopped containers..."
    docker container prune -f
    
    print_info "Removing unused images..."
    docker image prune -f
    
    print_info "Removing unused networks (except stack network)..."
    docker network prune -f --filter "name!=${DOCKER_NETWORK}"
    
    print_success "Cleanup completed"
}

# Backup stack configuration
backup_config() {
    print_header "Backing Up Configuration"
    
    detect_stack
    
    local backup_dir="${BASE_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup .env file
    cp "${BASE_DIR}/config/.env" "$backup_dir/"
    
    # Backup AppArmor templates
    cp -r "${BASE_DIR}/apparmor" "$backup_dir/"
    
    # Backup Caddy configuration
    if [[ -d "${BASE_DIR}/caddy" ]]; then
        cp -r "${BASE_DIR}/caddy" "$backup_dir/"
    fi
    
    # Export running container configurations
    mkdir -p "$backup_dir/containers"
    for container in $(docker ps --format "{{.Names}}" --filter "network=${DOCKER_NETWORK}"); do
        docker inspect "$container" > "$backup_dir/containers/${container}.json"
    done
    
    print_success "Configuration backed up to $backup_dir"
}

# Show stack metrics
show_metrics() {
    show_detailed_metrics
}

# Google Drive rclone OAuth authorization
authorize_rclone_oauth() {
    # This is the ONE-TIME token acquisition for OAuth method
    # Two sub-options: SSH tunnel (on server) or paste token from local machine

    echo ""
    print_header "rclone OAuth Authorization"
    echo ""
    echo "Option A — Run on THIS SERVER (requires SSH tunnel from your laptop):"
    echo ""
    echo "  1. On your LOCAL machine, open a NEW terminal and run:"
    echo "     ssh -L 53682:localhost:53682 $(whoami)@<THIS_SERVER_IP>"
    echo "     Keep this terminal open."
    echo ""
    echo "  2. Press Enter below to start rclone authorization..."
    echo "     When rclone shows a URL, copy the URL."
    echo "     REPLACE '127.0.0.1' with 'localhost' (already correct for tunnel)."
    echo "     Open it in your LOCAL browser."
    echo "     Authorize, then come back here."
    echo ""
    echo "Option B — Run on YOUR LOCAL MACHINE (no tunnel needed):"
    echo ""
    echo "  On your LOCAL machine (must have rclone installed), run:"
    echo "  rclone authorize 'drive' \\"
    echo "    '${RCLONE_OAUTH_CLIENT_ID}' \\"
    echo "    '${RCLONE_OAUTH_CLIENT_SECRET}'"
    echo ""
    echo "  Copy the token JSON that rclone prints."
    echo "  Select option B below to paste it."
    echo ""
    echo -n -e "${YELLOW}Choose [A=SSH tunnel on server / B=paste token from local]:${NC} "
    read -r AUTH_CHOICE

    case "${AUTH_CHOICE^^}" in
        A)
            echo ""
            print_info "Starting rclone authorization on this server..."
            print_info "Make sure your SSH tunnel is open first!"
            echo ""
            echo -n -e "${YELLOW}Press Enter when SSH tunnel is ready...${NC} "
            read -r
            
            # Run rclone with --auth-no-browser so it prints the URL instead of opening it
            # The URL will be http://127.0.0.1:53682/auth?... 
            # which works through the SSH tunnel as http://localhost:53682/auth?...
            rclone authorize "drive" \
                --auth-no-browser \
                "${RCLONE_OAUTH_CLIENT_ID}" \
                "${RCLONE_OAUTH_CLIENT_SECRET}" \
                --config "${DATA_ROOT}/config/rclone/rclone.conf"
            
            # rclone writes the token directly to rclone.conf
            if grep -q "token" "${DATA_ROOT}/config/rclone/rclone.conf" 2>/dev/null; then
                echo "RCLONE_TOKEN_OBTAINED=true" >> "$ENV_FILE"
                print_success "Token obtained and saved to rclone.conf"
                offer_to_start_rclone_container
            else
                print_error "Token not found in rclone.conf — authorization may have failed"
            fi
            ;;
            
        B)
            echo ""
            print_info "Paste the complete [gdrive] config block from your local rclone config."
            echo "It should look like:"
            echo ""
            echo "  [gdrive]"
            echo "  type = drive"
            echo "  client_id = ..."
            echo "  client_secret = ..."
            echo "  token = {\"access_token\":\"...\",\"refresh_token\":\"...\", ...}"
            echo ""
            echo "Paste below, then press Ctrl+D on an empty line when done:"
            echo ""
            
            mkdir -p "${DATA_ROOT}/config/rclone"
            cat > "${DATA_ROOT}/config/rclone/rclone.conf"
            chmod 600 "${DATA_ROOT}/config/rclone/rclone.conf"
            
            if grep -q "token" "${DATA_ROOT}/config/rclone/rclone.conf" 2>/dev/null; then
                echo "RCLONE_TOKEN_OBTAINED=true" >> "$ENV_FILE"
                print_success "Token saved to rclone.conf"
                offer_to_start_rclone_container
            else
                print_error "Pasted config does not appear to contain a token"
                print_error "Make sure you included the full [gdrive] block with token line"
            fi
            ;;
    esac
}

offer_to_start_rclone_container() {
    echo ""
    echo -n -e "${YELLOW}Start rclone sync container now? [Y/n]:${NC} "
    read -r START_NOW
    if [[ "${START_NOW:-Y}" =~ ^[Yy]$ ]]; then
        docker compose -f "${DATA_ROOT}/docker/docker-compose.yml" up -d rclone-gdrive
        print_success "rclone container started"
    fi
}

# Google Drive management menu
gdrive_management() {
    # Load configuration
    local env_file="${DATA_ROOT:-/mnt/data}/.env"
    if [[ ! -f "$env_file" ]]; then
        print_error "Configuration file not found: $env_file"
        print_info "Please run Script 1 first"
        return 1
    fi
    
    source "$env_file"
    
    if [[ "${GDRIVE_ENABLED:-false}" != "true" ]]; then
        print_error "Google Drive sync is not enabled"
        print_info "Please run Script 1 and enable Google Drive sync"
        return 1
    fi
    
    print_header "Google Drive Sync Management"
    echo ""
    echo "💾 Storage Usage:"
    echo "   Base Directory: $(du -sh ${BASE_DIR} | cut -f1)"
    echo "   Data Directory: $(du -sh ${BASE_DIR}/data | cut -f1)"
    echo "   Logs Directory: $(du -sh ${BASE_DIR}/logs | cut -f1)"
    
    echo ""
    echo "🌐 Network Statistics:"
    for container in $(docker ps --format "{{.Names}}" --filter "network=${DOCKER_NETWORK}"); do
        local network_io=$(docker stats --no-stream --format "{{.NetIO}}" "$container")
        echo "   $container: $network_io"

# ── CONFIGURATION FUNCTIONS ───────────────────────────────────────────

configure_postgres() {
    log "Configuring PostgreSQL and creating databases..."
    
    # Wait for postgres to be ready
    local retries=0
    until docker exec "${COMPOSE_PROJECT_NAME}-postgres" pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; do
        ((retries++))
        [[ ${retries} -gt 30 ]] && { log "❌ PostgreSQL not ready"; return 1; }
        sleep 2
    done
    
    log "✅ PostgreSQL is ready"
    
    # Create Dify database
    log "Creating Dify database..."
    docker exec "${COMPOSE_PROJECT_NAME}-postgres" \
        psql -U "${POSTGRES_USER}" \
        -c "CREATE DATABASE dify OWNER ${POSTGRES_USER};" \
        2>/dev/null || log "Dify database already exists, skipping"
    
    log "✅ PostgreSQL configuration completed"
}

configure_dify() {
    log "Configuring Dify..."
    
    # Wait for Dify API to be ready
    local retries=0
    until curl -sf "http://localhost:${DIFY_PORT:-3002}/v1/health" >/dev/null 2>&1; do
        ((retries++))
        [[ ${retries} -gt 60 ]] && { log "❌ Dify API not ready"; return 1; }
        sleep 5
    done
    
    log "✅ Dify API is ready"
    
    # Initialize Dify admin account (required before any other API calls)
    log "Initializing Dify admin account..."
    local setup_response
    local setup_http_code
    
    # Get HTTP status code and response
    setup_response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "http://localhost:${DIFY_PORT:-3002}/console/api/setup" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"${DIFY_ADMIN_EMAIL:-admin@example.com}\",
            \"name\": \"Admin\",
            \"password\": \"${DIFY_ADMIN_PASSWORD:-admin123}\"
        }" 2>/dev/null)
    setup_http_code=$setup_response
    
    # Get response body on success
    if [[ "${setup_http_code}" =~ ^(200|201)$ ]]; then
        setup_response=$(curl -sf -X POST \
            "http://localhost:${DIFY_PORT:-3002}/console/api/setup" \
            -H "Content-Type: application/json" \
            -d "{
                \"email\": \"${DIFY_ADMIN_EMAIL:-admin@example.com}\",
                \"name\": \"Admin\",
                \"password\": \"${DIFY_ADMIN_PASSWORD:-admin123}\"
            }" 2>/dev/null || echo "")
    fi
    
    case "${setup_http_code}" in
        200|201)
            if echo "${setup_response}" | grep -q '"result":"success"'; then
                log "✅ Dify admin account created"
            else
                log "⚠️ Dify setup returned unexpected response: ${setup_response}"
            fi
            ;;
        400)
            log "✅ Dify already initialised — skipping"
            ;;
        *)
            log "⚠️ Dify setup failed (HTTP ${setup_http_code}) - checking if already configured"
            # Check if already set up
            if curl -sf "http://localhost:${DIFY_PORT:-3002}/console/api/account" >/dev/null 2>&1; then
                log "✅ Dify already configured"
            else
                log "❌ Dify configuration failed"
                return 1
            fi
            ;;
    esac
    
    log "✅ Dify configuration completed"
}

configure_n8n() {
    log "Configuring n8n..."
    
    # Wait for n8n to be ready
    local retries=0
    until curl -sf "http://localhost:${N8N_PORT:-5678}/healthz" >/dev/null 2>&1; do
        ((retries++))
        [[ ${retries} -gt 60 ]] && { log "❌ n8n not ready"; return 1; }
        sleep 5
    done
    
    log "✅ n8n is ready"
    
    # Create n8n owner account (required before any API calls)
    log "Creating n8n owner account..."
    local setup_response
    setup_response=$(curl -sf -X POST \
        "http://localhost:${N8N_PORT:-5678}/api/v1/owner/setup" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"${N8N_ADMIN_EMAIL:-admin@example.com}\",
            \"firstName\": \"Admin\",
            \"lastName\": \"User\",
            \"password\": \"${N8N_ADMIN_PASSWORD:-admin123}\"
        }" 2>/dev/null) || {
        log "⚠️ n8n setup failed - checking if already configured"
        # Check if already set up
        if curl -sf "http://localhost:${N8N_PORT:-5678}/api/v1/owner" >/dev/null 2>&1; then
            log "✅ n8n already configured"
        else
            log "❌ n8n configuration failed"
            return 1
        fi
    }
    
    # Extract API key from response for subsequent calls
    fetch_token_with_retry() {
      local url="$1" body="$2" token=""
      local attempts=0
      until [[ -n "${token}" ]] || [[ $attempts -ge 5 ]]; do
        token=$(curl -sf -X POST "${url}" \
          -H "Content-Type: application/json" \
          -d "${body}" 2>/dev/null | \
          python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('access_token',''))" \
          2>/dev/null || true)
        [[ -z "${token}" ]] && sleep 5
        ((attempts++))
      done
      [[ -z "${token}" ]] && fail "Could not obtain auth token from ${url} after ${attempts} attempts"
      echo "${token}"
    }
    
    local api_key
    api_key=$(fetch_token_with_retry \
      "http://localhost:${N8N_PORT:-5678}/api/v1/owner/setup" \
      "{
        \"email\": \"${N8N_ADMIN_EMAIL:-admin@example.com}\",
        \"firstName\": \"Admin\",
        \"lastName\": \"User\",
        \"password\": \"${N8N_ADMIN_PASSWORD:-admin123}\"
      }")
    
    if [[ -n "$api_key" ]]; then
        log "✅ n8n owner account created with API key"
        # Store API key for potential future use
        echo "N8N_API_KEY=${api_key}" >> "${DATA_ROOT:-/mnt/data}/.env" 2>/dev/null || true
    elif echo "${setup_response}" | grep -q 'already_setup'; then
        log "✅ n8n already configured"
    else
        log "⚠️ n8n setup returned unexpected response: ${setup_response}"
    fi
    
    log "✅ n8n configuration completed"
}

configure_all_services() {
    print_header "Configuring All Services"
    
    # Load environment
    load_env
    
    # Configure services in order
    configure_postgres
    configure_redis
    configure_qdrant
    create_qdrant_collections
    configure_minio
    configure_n8n
    configure_anythingllm
    configure_dify
    configure_flowise
    configure_signal
    configure_openclaw
    configure_tailscale
    configure_rclone
    print_service_summary
}

configure_flowise() {
    log "Configuring Flowise..."
    
    # Wait for Flowise to be ready
    local retries=0
    until curl -sf "http://localhost:${FLOWISE_PORT:-3000}/" >/dev/null 2>&1; do
        ((retries++))
        [[ ${retries} -gt 60 ]] && { log "❌ Flowise not ready"; return 1; }
        sleep 5
    done
    
    log "✅ Flowise is ready"
    
    # Wait 20s for Flowise database migrations to complete
    log "Waiting 20s for Flowise database migrations to complete..."
    sleep 20
    
    log "✅ Flowise configuration completed"
}

configure_signal() {
    log "Configuring Signal..."
    
    # Wait for Signal to be ready
    local retries=0
    until curl -sf "http://localhost:${SIGNAL_PORT:-3001}/" >/dev/null 2>&1; do
        ((retries++))
        [[ ${retries} -gt 60 ]] && { log "❌ Signal not ready"; return 1; }
        sleep 5
    done
    
    log "✅ Signal is ready"
    
    log "✅ Signal configuration completed"
}

configure_openclaw() {
    log "Configuring OpenClaw..."
    
    # Wait for OpenClaw to be ready
    local retries=0
    until curl -sf "http://localhost:${OPENCLAW_PORT:-3003}/" >/dev/null 2>&1; do
        ((retries++))
        [[ ${retries} -gt 60 ]] && { log "❌ OpenClaw not ready"; return 1; }
        sleep 5
    done
    
    log "✅ OpenClaw is ready"
    
    log "✅ OpenClaw configuration completed"
}

configure_tailscale() {
    log "Configuring Tailscale..."
    
    # Wait for Tailscale to be ready
    local retries=0
    until curl -sf "http://localhost:${TAILSCALE_PORT:-3004}/" >/dev/null 2>&1; do
        ((retries++))
        [[ ${retries} -gt 60 ]] && { log "❌ Tailscale not ready"; return 1; }
        sleep 5
    done
    
    log "✅ Tailscale is ready"
    
    log "✅ Tailscale configuration completed"
}

configure_rclone() {
    log "Configuring RClone..."
    
    # Wait for RClone to be ready
    local retries=0
    until curl -sf "http://localhost:${RCLONE_PORT:-3005}/" >/dev/null 2>&1; do
        ((retries++))
        [[ ${retries} -gt 60 ]] && { log "❌ RClone not ready"; return 1; }
        sleep 5
    done
    
    log "✅ RClone is ready"
    
    log "✅ RClone configuration completed"
}

load_env() {
    local env_file="${DATA_ROOT:-/mnt/data}/${TENANT_ID:-u1001}/.env"
    if [[ -f "$env_file" ]]; then
        source "$env_file"
        log "Environment loaded from $env_file"
    else
        print_error "Environment file not found: $env_file"
        exit 1
    fi
}

# Main function
main() {
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    configure_all_services
}

# Run main function
main "$@"

# Google Drive management functions
gdrive_management() {
    # Load configuration
    local env_file="${DATA_ROOT:-/mnt/data}/.env"
    if [[ ! -f "$env_file" ]]; then
        print_error "Configuration file not found: $env_file"
        print_info "Please run Script 1 first"
        return 1
    fi
    
    source "$env_file"
    
    if [[ "${GDRIVE_ENABLED:-false}" != "true" ]]; then
        print_error "Google Drive sync is not enabled"
        print_info "Please run Script 1 and enable Google Drive sync"
        return 1
    fi
    
    print_header "Google Drive Sync Management"
    
    local choice=""
    while true; do
        echo ""
        echo "Google Drive Sync Options:"
        echo "  1. Run sync now (one-shot)"
        echo "  2. View sync logs (last 50 lines)"
        echo "  3. View sync status (last run result)"
        echo "  4. Change sync folder"
        echo "  5. Change sync interval"
        echo "  6. Enable auto-sync (restart container on interval)"
        echo "  7. Disable auto-sync"
        if [[ "${RCLONE_AUTH_METHOD}" == "oauth_tunnel" && "${RCLONE_TOKEN_OBTAINED:-false}" != "true" ]]; then
            echo -e "  8. ${YELLOW}Authorize rclone (SSH tunnel or paste token)${NC}"
            echo "  9. Back to main menu"
            echo ""
            echo -n -e "${YELLOW}Select option [1-9]:${NC} "
        else
            echo "  8. Back to main menu"
            echo ""
            echo -n -e "${YELLOW}Select option [1-8]:${NC} "
        fi
        read -r choice
        
        case "$choice" in
            1)
                print_info "Restarting rclone container for sync..."
                if docker restart rclone-gdrive; then
                    print_success "Sync started. View progress with option 2."
                else
                    print_error "Failed to restart rclone container"
                fi
                ;;
            2)
                print_header "RClone Sync Logs"
                echo "Container logs:"
                docker logs rclone-gdrive --tail 50 2>/dev/null || print_warning "No container logs found"
                echo ""
                echo "Sync logs:"
                if [[ -f "${DATA_ROOT}/logs/rclone/rclone.log" ]]; then
                    tail -n 50 "${DATA_ROOT}/logs/rclone/rclone.log"
                else
                    print_warning "No sync logs found"
                fi
                ;;
            3)
                print_header "RClone Container Status"
                docker inspect rclone-gdrive \
                    --format "Status: {{.State.Status}} | Exit: {{.State.ExitCode}} | Started: {{.State.StartedAt}}" 2>/dev/null || print_warning "Container not found"
                ;;
            4)
                echo -n -e "${YELLOW}New Google Drive folder path (blank = root):${NC} "
                read -r new_folder
                sed -i "s/RCLONE_GDRIVE_FOLDER=.*/RCLONE_GDRIVE_FOLDER=${new_folder}/" "$env_file"
                print_success "Sync folder updated to: ${new_folder:-root}"
                print_info "Restart sync with option 1 to apply changes"
                ;;
            5)
                echo -n -e "${YELLOW}New sync interval in seconds:${NC} "
                read -r new_interval
                if [[ "$new_interval" =~ ^[0-9]+$ ]]; then
                    sed -i "s/RCLONE_SYNC_INTERVAL=.*/RCLONE_SYNC_INTERVAL=${new_interval}/" "$env_file"
                    print_success "Sync interval updated to: ${new_interval} seconds"
                    if [[ "${RCLONE_AUTOSYNC_ENABLED:-false}" == "true" ]]; then
                        print_info "Restarting auto-sync to apply new interval..."
                        gdrive_disable_autosync
                        gdrive_enable_autosync
                    fi
                else
                    print_error "Invalid interval. Please enter a number."
                fi
                ;;
            6)
                gdrive_enable_autosync
                ;;
            7)
                gdrive_disable_autosync
                ;;
            8)
                if [[ "${RCLONE_AUTH_METHOD}" == "oauth_tunnel" && "${RCLONE_TOKEN_OBTAINED:-false}" != "true" ]]; then
                    authorize_rclone_oauth
                else
                    print_info "Returning to main menu..."
                    break
                fi
                ;;
            9)
                if [[ "${RCLONE_AUTH_METHOD}" == "oauth_tunnel" && "${RCLONE_TOKEN_OBTAINED:-false}" != "true" ]]; then
                    print_info "Returning to main menu..."
                    break
                else
                    print_warning "Invalid option. Please select 1-8."
                fi
                ;;
            *)
                if [[ "${RCLONE_AUTH_METHOD}" == "oauth_tunnel" && "${RCLONE_TOKEN_OBTAINED:-false}" != "true" ]]; then
                    print_warning "Invalid option. Please select 1-9."
                else
                    print_warning "Invalid option. Please select 1-8."
                fi
                ;;
        esac
    done
}

gdrive_enable_autosync() {
    local env_file="${DATA_ROOT:-/mnt/data}/.env"
    source "$env_file"
    
    if [[ "${RCLONE_AUTOSYNC_ENABLED:-false}" == "true" ]]; then
        print_warning "Auto-sync is already enabled"
        return
    fi
    
    print_info "Enabling auto-sync..."
    
    # Create autosync script
    mkdir -p "${DATA_ROOT}/scripts"
    cat > "${DATA_ROOT}/scripts/gdrive-autosync.sh" << EOF
#!/bin/bash
# Auto-sync script for Google Drive
# This script runs in a loop, restarting rclone container on interval

echo "Starting Google Drive auto-sync..."
echo "Interval: ${RCLONE_SYNC_INTERVAL:-3600} seconds"
echo "Press Ctrl+C to stop"

while true; do
    echo "\$(date): Starting sync..."
    if docker restart rclone-gdrive; then
        echo "\$(date): Sync completed successfully"
    else
        echo "\$(date): Sync failed - check logs"
    fi
    
    echo "Next sync in \${RCLONE_SYNC_INTERVAL:-3600} seconds..."
    sleep "${RCLONE_SYNC_INTERVAL:-3600}"
done
EOF
    
    chmod +x "${DATA_ROOT}/scripts/gdrive-autosync.sh"
    
    # Start autosync in background
    mkdir -p "${DATA_ROOT}/run"
    nohup bash "${DATA_ROOT}/scripts/gdrive-autosync.sh" > "${DATA_ROOT}/logs/gdrive-autosync.log" 2>&1 &
    echo $! > "${DATA_ROOT}/run/gdrive-autosync.pid"
    
    # Update .env
    sed -i "s/RCLONE_AUTOSYNC_ENABLED=.*/RCLONE_AUTOSYNC_ENABLED=true/" "$env_file"
    
    print_success "Auto-sync enabled"
    print_info "PID: $(cat "${DATA_ROOT}/run/gdrive-autosync.pid")"
    print_info "Logs: ${DATA_ROOT}/logs/gdrive-autosync.log"
}

gdrive_disable_autosync() {
    local env_file="${DATA_ROOT:-/mnt/data}/.env"
    
    if [[ "${RCLONE_AUTOSYNC_ENABLED:-false}" != "true" ]]; then
        print_warning "Auto-sync is not enabled"
        return
    fi
    
    print_info "Disabling auto-sync..."
    
    # Kill autosync process
    if [[ -f "${DATA_ROOT}/run/gdrive-autosync.pid" ]]; then
        local pid=$(cat "${DATA_ROOT}/run/gdrive-autosync.pid")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            print_success "Auto-sync process stopped (PID: $pid)"
        fi
        rm -f "${DATA_ROOT}/run/gdrive-autosync.pid"
    fi
    
    # Update .env
    sed -i "s/RCLONE_AUTOSYNC_ENABLED=.*/RCLONE_AUTOSYNC_ENABLED=false/" "$env_file"
    
    print_success "Auto-sync disabled"
}

configure_tailscale() {
    log "Configuring Tailscale..."
    
    if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
        log "No TAILSCALE_AUTH_KEY found in ${ENV_FILE}"
        log "Get one from: https://login.tailscale.com/admin/settings/keys"
        read -p "Paste Tailscale auth key (Enter to skip): " TAILSCALE_AUTH_KEY
        [[ -n "${TAILSCALE_AUTH_KEY}" ]] && \
           echo "TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}" >> "${ENV_FILE}"
    fi
    
    if [[ -z "${TAILSCALE_AUTH_KEY:-}" ]]; then
        log " Tailscale skipped — run 'tailscale up' manually inside container"
        return 0
    fi
    
    docker exec "${COMPOSE_PROJECT_NAME}-tailscale" \
        tailscale up \
        --authkey="${TAILSCALE_AUTH_KEY}" \
        --hostname="${TAILSCALE_HOSTNAME}" \
        --accept-routes \
        --accept-dns=false 2>&1 | log_pipe
    
    sleep 5
    
    TAILSCALE_IP=$(docker exec "${COMPOSE_PROJECT_NAME}-tailscale" \
        tailscale ip -4 2>/dev/null || echo "")
    
    if [[ -n "${TAILSCALE_IP}" ]]; then
        log " Tailscale connected: ${TAILSCALE_IP}"
        # Update .env with real IP
        sed -i "s/^TAILSCALE_IP=.*/TAILSCALE_IP=${TAILSCALE_IP}/" "${ENV_FILE}" || \
          echo "TAILSCALE_IP=${TAILSCALE_IP}" >> "${ENV_FILE}"
    else
        log "  Tailscale IP not yet assigned — may need a moment"
    fi
}

configure_rclone() {
    log "Configuring rclone for Google Drive..."
    local conf="${DATA_ROOT}/config/rclone/rclone.conf"
    mkdir -p "$(dirname ${conf})"
    
    if [[ -f "${conf}" ]] && grep -q "type = drive" "${conf}"; then
        log "rclone already configured — skipping"
        return 0
    fi
    
    cat > "${conf}" <<EOF
[gdrive-${TENANT_NAME}]
type = drive
scope = drive.readonly
EOF
    
    chown "${TENANT_UID}:${TENANT_GID}" "${conf}"
    log "  Google Drive OAuth required. Run this command to authenticate:"
    log "   docker run --rm -it \\"
    log "     -v \"${DATA_ROOT}/config/rclone:/config/rclone\" \\"
    log "     rclone/rclone:latest \\"
    log "     config reconnect gdrive-${TENANT_NAME}:"
    log "   Then open the URL shown and paste the auth code."
}

create_qdrant_collections() {
    log "Creating Qdrant collections for tenant ${TENANT_NAME}..."
    local qdrant_url="http://localhost:${QDRANT_PORT}"
    
    # Wait for Qdrant
    local retries=0
    until curl -sf "${qdrant_url}/healthz" > /dev/null 2>&1; do
        ((retries++))
        [[ ${retries} -gt 30 ]] && { log " Qdrant not responding"; return 1; }
        sleep 2
    done
    
    # Create docs collection — 1536 dims for OpenAI embeddings, 768 for local
    curl -sf -X PUT "${qdrant_url}/collections/${TENANT_NAME}_docs" \
        -H "Content-Type: application/json" \
        -d '{
          "vectors": {
            "size": 1536,
            "distance": "Cosine"
          }
        }' | log_pipe
    
    log " Qdrant collection: ${TENANT_NAME}_docs"
}

print_service_summary() {
    # Re-source env to get TAILSCALE_IP set by configure_tailscale()
    source "${ENV_FILE}"
    
    echo ""
    echo "═════════════════════════════════════════════════════════"
    echo "  SERVICE ENDPOINTS — Tenant: ${TENANT_NAME}"
    echo "═══════════════════════════════════════════════════════"
    
    local base_url="https://${TAILSCALE_IP}"
    
    services=(
        "AnythingLLM|${ANYTHINGLLM_PORT}"
        "Dify|${DIFY_PORT}"
        "n8n|${N8N_PORT}"
        "OpenClaw|${OPENCLAW_PORT}"
        "MinIO|${MINIO_CONSOLE_PORT}"
        "Signal|${SIGNAL_PORT}"
        "Qdrant|${QDRANT_PORT}"
    )
    
    for entry in "${services[@]}"; do
        name="${entry%|*}"
        port="${entry#*|}"
        url="${base_url}:${port}"
        
        # Validate reachability
        if curl -sk --max-time 5 "${url}" > /dev/null 2>&1; then
            echo "  ${name}: ${url}"
        else
            echo "  ${name}: ${url} (not responding)"
        fi
    done
    
    echo ""
    echo "  GDrive sync: ${GDRIVE_SYNC_DIR}"
    echo "  VectorDB:    ${QDRANT_URL}"
    echo "  Config:      ${ENV_FILE}"
    echo "═════════════════════════════════════════════════════"
}

# Main execution
