#!/bin/bash
set -euo pipefail

# ============================================================================
# AI Platform - Service Management Script
# Version: 17.0 - WITH INDIVIDUAL SERVICE CONTROL
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOGFILE="${PROJECT_ROOT}/logs/services-${TIMESTAMP}.log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}ℹ${NC} $1" | tee -a "$LOGFILE"; }
log_success() { echo -e "${GREEN}✓${NC} $1" | tee -a "$LOGFILE"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOGFILE"; }
log_error() { echo -e "${RED}✗${NC} $1" | tee -a "$LOGFILE"; }
log_step() { echo -e "\n${CYAN}[$1]${NC} $2" | tee -a "$LOGFILE"; }

# ============================================================================
# LOAD ENVIRONMENT
# ============================================================================
load_environment() {
    if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
        log_error "Environment file not found: ${PROJECT_ROOT}/.env"
        log_error "Please run ./scripts/1-setup-system.sh first"
        exit 1
    fi
    
    set -a
    source "${PROJECT_ROOT}/.env"
    set +a
    
    log_success "Environment loaded"
}

# ============================================================================
# SERVICE DEFINITIONS
# ============================================================================
declare -A SERVICES=(
    ["ollama"]="Ollama (Local LLM)"
    ["litellm"]="LiteLLM (LLM Gateway)"
    ["weaviate"]="Weaviate (Vector DB)"
    ["qdrant"]="Qdrant (Vector DB)"
    ["milvus"]="Milvus (Vector DB)"
    ["dify"]="Dify (LLM Platform)"
    ["n8n"]="n8n (Workflow Automation)"
    ["anythingllm"]="AnythingLLM (Document Chat)"
    ["flowise"]="Flowise (Visual AI Builder)"
    ["signal"]="Signal API"
    ["clawdbot"]="ClawdBot (AI Assistant)"
    ["nginx"]="Nginx (Reverse Proxy)"
)

declare -A SERVICE_URLS=(
    ["ollama"]="http://localhost:${OLLAMA_PORT:-11434}"
    ["litellm"]="http://localhost:${LITELLM_PORT:-4000}"
    ["weaviate"]="http://localhost:${WEAVIATE_PORT:-8080}"
    ["qdrant"]="http://localhost:${QDRANT_PORT:-6333}"
    ["milvus"]="http://localhost:${MILVUS_PORT:-19530}"
    ["dify"]="http://${DOMAIN:-localhost}/dify"
    ["n8n"]="http://${DOMAIN:-localhost}/n8n"
    ["anythingllm"]="http://${DOMAIN:-localhost}/anythingllm"
    ["flowise"]="http://${DOMAIN:-localhost}/flowise"
    ["signal"]="http://localhost:${SIGNAL_PORT:-8081}"
    ["clawdbot"]="http://${DOMAIN:-localhost}/clawdbot"
    ["nginx"]="http://${DOMAIN:-localhost}"
)

# ============================================================================
# CHECK IF SERVICE IS ENABLED
# ============================================================================
is_service_enabled() {
    local service=$1
    local enable_var=""
    
    case "$service" in
        ollama) enable_var="${ENABLE_OLLAMA:-false}" ;;
        litellm) enable_var="${ENABLE_LITELLM:-false}" ;;
        weaviate) enable_var="${ENABLE_WEAVIATE:-false}" ;;
        qdrant) enable_var="${ENABLE_QDRANT:-false}" ;;
        milvus) enable_var="${ENABLE_MILVUS:-false}" ;;
        dify) enable_var="${ENABLE_DIFY:-false}" ;;
        n8n) enable_var="${ENABLE_N8N:-false}" ;;
        anythingllm) enable_var="${ENABLE_ANYTHINGLLM:-false}" ;;
        flowise) enable_var="${ENABLE_FLOWISE:-false}" ;;
        signal) enable_var="${ENABLE_SIGNAL:-false}" ;;
        clawdbot) enable_var="${ENABLE_CLAWDBOT:-false}" ;;
        nginx) enable_var="true" ;; # Always enabled
        *) return 1 ;;
    esac
    
    [[ "$enable_var" == "true" ]]
}

# ============================================================================
# GET SERVICE CONTAINERS
# ============================================================================
get_service_containers() {
    local service=$1
    
    case "$service" in
        ollama) echo "ai-ollama" ;;
        litellm) echo "ai-litellm" ;;
        weaviate) echo "ai-weaviate" ;;
        qdrant) echo "ai-qdrant" ;;
        milvus) echo "ai-milvus milvus-etcd milvus-minio" ;;
        dify) echo "dify-api dify-worker dify-web" ;;
        n8n) echo "ai-n8n" ;;
        anythingllm) echo "ai-anythingllm" ;;
        flowise) echo "ai-flowise" ;;
        signal) echo "ai-signal" ;;
        clawdbot) echo "ai-clawdbot" ;;
        nginx) echo "ai-nginx" ;;
        *) echo "" ;;
    esac
}

# ============================================================================
# START SERVICE
# ============================================================================
start_service() {
    local service=$1
    
    if ! is_service_enabled "$service"; then
        log_warning "${SERVICES[$service]} is not enabled in configuration"
        return 1
    fi
    
    local service_dir="${PROJECT_ROOT}/stacks/${service}"
    
    if [[ ! -d "$service_dir" ]]; then
        log_error "Service directory not found: $service_dir"
        return 1
    fi
    
    if [[ ! -f "$service_dir/docker-compose.yml" ]]; then
        log_error "Docker compose file not found: $service_dir/docker-compose.yml"
        return 1
    fi
    
    log_info "Starting ${SERVICES[$service]}..."
    
    cd "$service_dir"
    
    # Start with environment variables
    export $(cat "${PROJECT_ROOT}/.env" | grep -v '^#' | xargs)
    docker-compose up -d 2>&1 | tee -a "$LOGFILE"
    
    # Wait for service to be healthy
    sleep 3
    
    local containers=$(get_service_containers "$service")
    local all_running=true
    
    for container in $containers; do
        if docker ps --filter "name=${container}" --filter "status=running" | grep -q "$container"; then
            log_success "  ✓ $container is running"
        else
            log_error "  ✗ $container failed to start"
            all_running=false
        fi
    done
    
    if $all_running; then
        log_success "${SERVICES[$service]} started successfully"
        if [[ -n "${SERVICE_URLS[$service]:-}" ]]; then
            log_info "  Access at: ${SERVICE_URLS[$service]}"
        fi
        return 0
    else
        log_error "${SERVICES[$service]} failed to start properly"
        return 1
    fi
}

# ============================================================================
# STOP SERVICE
# ============================================================================
stop_service() {
    local service=$1
    
    local service_dir="${PROJECT_ROOT}/stacks/${service}"
    
    if [[ ! -d "$service_dir" ]]; then
        log_warning "Service directory not found: $service_dir"
        return 0
    fi
    
    log_info "Stopping ${SERVICES[$service]}..."
    
    cd "$service_dir"
    docker-compose down 2>&1 | tee -a "$LOGFILE"
    
    log_success "${SERVICES[$service]} stopped"
}

# ============================================================================
# RESTART SERVICE
# ============================================================================
restart_service() {
    local service=$1
    
    log_info "Restarting ${SERVICES[$service]}..."
    stop_service "$service"
    sleep 2
    start_service "$service"
}

# ============================================================================
# START ALL SERVICES
# ============================================================================
start_all() {
    log_step "START" "Starting all enabled services"
    
    # Start in dependency order
    local start_order=(
        "ollama"
        "litellm"
        "weaviate"
        "qdrant"
        "milvus"
        "dify"
        "n8n"
        "anythingllm"
        "flowise"
        "signal"
        "clawdbot"
        "nginx"
    )
    
    local started=0
    local failed=0
    
    for service in "${start_order[@]}"; do
        if is_service_enabled "$service"; then
            if start_service "$service"; then
                ((started++))
            else
                ((failed++))
            fi
        fi
    done
    
    echo ""
    log_step "SUMMARY" "Startup complete"
    log_success "$started services started successfully"
    [[ $failed -gt 0 ]] && log_error "$failed services failed to start"
    
    show_status
}

# ============================================================================
# STOP ALL SERVICES
# ============================================================================
stop_all() {
    log_step "STOP" "Stopping all services"
    
    # Stop in reverse order
    local stop_order=(
        "nginx"
        "clawdbot"
        "signal"
        "flowise"
        "anythingllm"
        "n8n"
        "dify"
        "milvus"
        "qdrant"
        "weaviate"
        "litellm"
        "ollama"
    )
    
    for service in "${stop_order[@]}"; do
        if [[ -d "${PROJECT_ROOT}/stacks/${service}" ]]; then
            stop_service "$service"
        fi
    done
    
    log_success "All services stopped"
}

# ============================================================================
# RESTART ALL SERVICES
# ============================================================================
restart_all() {
    log_step "RESTART" "Restarting all services"
    stop_all
    sleep 3
    start_all
}

# ============================================================================
# SHOW STATUS
# ============================================================================
show_status() {
    log_step "STATUS" "Service status"
    
    echo ""
    printf "${CYAN}%-15s %-30s %-10s %-50s${NC}\n" "SERVICE" "DESCRIPTION" "STATUS" "URL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    for service in ollama litellm weaviate qdrant milvus dify n8n anythingllm flowise signal clawdbot nginx; do
        if is_service_enabled "$service"; then
            local containers=$(get_service_containers "$service")
            local status="${RED}STOPPED${NC}"
            local all_running=true
            
            for container in $containers; do
                if ! docker ps --filter "name=${container}" --filter "status=running" | grep -q "$container"; then
                    all_running=false
                    break
                fi
            done
            
            if $all_running; then
                status="${GREEN}RUNNING${NC}"
            fi
            
            printf "%-15s %-30s %-20b %-50s\n" \
                "$service" \
                "${SERVICES[$service]}" \
                "$status" \
                "${SERVICE_URLS[$service]:-N/A}"
        else
            printf "%-15s %-30s %-20s %-50s\n" \
                "$service" \
                "${SERVICES[$service]}" \
                "${YELLOW}DISABLED${NC}" \
                "Not configured"
        fi
    done
    
    echo ""
}

# ============================================================================
# VIEW LOGS
# ============================================================================
view_logs() {
    local service=${1:-}
    
    if [[ -z "$service" ]]; then
        log_error "Please specify a service name"
        list_services
        return 1
    fi
    
    if [[ ! -d "${PROJECT_ROOT}/stacks/${service}" ]]; then
        log_error "Service not found: $service"
        list_services
        return 1
    fi
    
    local containers=$(get_service_containers "$service")
    
    if [[ -z "$containers" ]]; then
        log_error "No containers found for service: $service"
        return 1
    fi
    
    log_info "Showing logs for ${SERVICES[$service]}..."
    echo ""
    
    cd "${PROJECT_ROOT}/stacks/${service}"
    docker-compose logs -f --tail=100
}

# ============================================================================
# LIST SERVICES
# ============================================================================
list_services() {
    echo ""
    echo "${CYAN}Available services:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    for service in "${!SERVICES[@]}"; do
        local enabled="disabled"
        if is_service_enabled "$service"; then
            enabled="${GREEN}enabled${NC}"
        else
            enabled="${YELLOW}disabled${NC}"
        fi
        printf "  %-15s %-30s [%b]\n" "$service" "${SERVICES[$service]}" "$enabled"
    done
    echo ""
}

# ============================================================================
# HEALTH CHECK
# ============================================================================
health_check() {
    log_step "HEALTH" "Running health checks"
    
    echo ""
    
    # Check infrastructure first
    log_info "Checking infrastructure..."
    
    # PostgreSQL
    if docker exec ai-postgres pg_isready -U "${POSTGRES_USER}" &>/dev/null; then
        log_success "PostgreSQL: Healthy"
    else
        log_error "PostgreSQL: Unhealthy"
    fi
    
    # Redis
    if docker exec ai-redis redis-cli -a "${REDIS_PASSWORD}" ping &>/dev/null 2>&1; then
        log_success "Redis: Healthy"
    else
        log_error "Redis: Unhealthy"
    fi
    
    echo ""
    log_info "Checking application services..."
    
    # Check each enabled service
    for service in ollama litellm weaviate qdrant milvus dify n8n anythingllm flowise signal clawdbot; do
        if is_service_enabled "$service"; then
            local containers=$(get_service_containers "$service")
            local all_healthy=true
            
            for container in $containers; do
                if docker ps --filter "name=${container}" --filter "status=running" | grep -q "$container"; then
                    : # Container is running
                else
                    all_healthy=false
                    break
                fi
            done
            
            if $all_healthy; then
                log_success "${SERVICES[$service]}: Healthy"
            else
                log_error "${SERVICES[$service]}: Unhealthy"
            fi
        fi
    done
    
    echo ""
}

# ============================================================================
# SHOW USAGE
# ============================================================================
show_usage() {
    cat << EOF

${CYAN}╔════════════════════════════════════════════════════════════╗
║                                                            ║
║         AI PLATFORM - SERVICE MANAGEMENT v17.0             ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝${NC}

${YELLOW}USAGE:${NC}
  $0 <command> [service]

${YELLOW}COMMANDS:${NC}
  ${GREEN}start${NC} [service]        Start all services or specific service
  ${GREEN}stop${NC} [service]         Stop all services or specific service
  ${GREEN}restart${NC} [service]      Restart all services or specific service
  ${GREEN}status${NC}                 Show status of all services
  ${GREEN}logs${NC} <service>         View logs for specific service
  ${GREEN}health${NC}                 Run health checks on all services
  ${GREEN}list${NC}                   List all available services

${YELLOW}EXAMPLES:${NC}
  $0 start                    # Start all enabled services
  $0 start dify               # Start only Dify
  $0 stop n8n                 # Stop only n8n
  $0 restart anythingllm      # Restart AnythingLLM
  $0 logs flowise             # View Flowise logs
  $0 status                   # Show service status
  $0 health                   # Run health checks

${YELLOW}AVAILABLE SERVICES:${NC}
EOF
    
    list_services
}

# ============================================================================
# SHOW ACCESS INFO
# ============================================================================
show_access_info() {
    cat << EOF

${GREEN}╔════════════════════════════════════════════════════════════╗
║                                                            ║
║              ✓ SERVICES STARTED SUCCESSFULLY               ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝${NC}

${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🌐 ACCESS URLS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${MAGENTA}Main Portal:${NC}
  • http://${DOMAIN:-localhost}

${MAGENTA}Applications (via Nginx):${NC}
EOF

    [[ "${ENABLE_DIFY}" == "true" ]] && echo "  • Dify:        http://${DOMAIN:-localhost}/dify"
    [[ "${ENABLE_N8N}" == "true" ]] && echo "  • n8n:         http://${DOMAIN:-localhost}/n8n"
    [[ "${ENABLE_ANYTHINGLLM}" == "true" ]] && echo "  • AnythingLLM: http://${DOMAIN:-localhost}/anythingllm"
    [[ "${ENABLE_FLOWISE}" == "true" ]] && echo "  • Flowise:     http://${DOMAIN:-localhost}/flowise"
    [[ "${ENABLE_CLAWDBOT}" == "true" ]] && echo "  • ClawdBot:    http://${DOMAIN:-localhost}/clawdbot"

    cat << EOF

${MAGENTA}Direct Access (without proxy):${NC}
EOF

    [[ "${ENABLE_OLLAMA}" == "true" ]] && echo "  • Ollama:      http://localhost:${OLLAMA_PORT:-11434}"
    [[ "${ENABLE_LITELLM}" == "true" ]] && echo "  • LiteLLM:     http://localhost:${LITELLM_PORT:-4000}"
    [[ "${ENABLE_WEAVIATE}" == "true" ]] && echo "  • Weaviate:    http://localhost:${WEAVIATE_PORT:-8080}"
    [[ "${ENABLE_QDRANT}" == "true" ]] && echo "  • Qdrant:      http://localhost:${QDRANT_PORT:-6333}"

    [[ "${ENABLE_TAILSCALE}" == "true" ]] && cat << EOF

${MAGENTA}Tailscale VPN:${NC}
  • Port: ${TAILSCALE_PORT:-8443}
  • All services accessible via Tailscale network
EOF

    cat << EOF

${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📖 USEFUL COMMANDS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

  View status:        ./2-start-services.sh status
  View service logs:  ./2-start-services.sh logs <service>
  Restart service:    ./2-start-services.sh restart <service>
  Health check:       ./2-start-services.sh health
  Stop all:           ./2-start-services.sh stop

${GREEN}All services are now running!${NC}

EOF
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    load_environment
    
    local command="${1:-}"
    local service="${2:-}"
    
    case "$command" in
        start)
            if [[ -n "$service" ]]; then
                if [[ -n "${SERVICES[$service]:-}" ]]; then
                    start_service "$service"
                else
                    log_error "Unknown service: $service"
                    list_services
                    exit 1
                fi
            else
                start_all
                show_access_info
            fi
            ;;
        stop)
            if [[ -n "$service" ]]; then
                if [[ -n "${SERVICES[$service]:-}" ]]; then
                    stop_service "$service"
                else
                    log_error "Unknown service: $service"
                    list_services
                    exit 1
                fi
            else
                stop_all
            fi
            ;;
        restart)
            if [[ -n "$service" ]]; then
                if [[ -n "${SERVICES[$service]:-}" ]]; then
                    restart_service "$service"
                else
                    log_error "Unknown service: $service"
                    list_services
                    exit 1
                fi
            else
                restart_all
            fi
            ;;
        status)
            show_status
            ;;
        logs)
            if [[ -z "$service" ]]; then
                log_error "Please specify a service name"
                list_services
                exit 1
            fi
            view_logs "$service"
            ;;
        health)
            health_check
            ;;
        list)
            list_services
            ;;
        "")
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
