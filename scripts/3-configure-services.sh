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
    if [[ -f "${BASE_DIR:-/mnt/data}/config/.env" ]]; then
        source "${BASE_DIR:-/mnt/data}/config/.env"
        print_success "Stack detected: ${DOMAIN_NAME}"
    else
        print_error "No stack configuration found. Run from stack directory or set BASE_DIR."
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
    print_header "Stack Metrics"
    
    detect_stack
    
    echo "📊 Resource Usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" --filter "network=${DOCKER_NETWORK}"
    
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
    done
}

# Display help
show_help() {
    print_header "Operations Help"
    
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  status              Show stack status and resource usage"
    echo "  health              Check health of all services"
    echo "  restart <service>   Restart a specific service"
    echo "  renew               Renew SSL certificates"
    echo "  logs <service> [n]  Show service logs (default 50 lines)"
    echo "  config <service>   Show service configuration"
    echo "  cleanup             Clean up unused Docker resources"
    echo "  backup              Backup stack configuration"
    echo "  metrics             Show detailed stack metrics"
    echo "  help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 restart n8n"
    echo "  $0 logs postgres 100"
    echo "  $0 config openclaw"
}

# Main function
main() {
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    local command="${1:-help}"
    
    case "$command" in
        status)
            show_status
            ;;
        health)
            health_check
            ;;
        restart)
            restart_service "${2:-}"
            ;;
        renew)
            renew_ssl
            ;;
        logs)
            show_logs "${2:-}" "${3:-50}"
            ;;
        config)
            show_config "${2:-}"
            ;;
        cleanup)
            cleanup
            ;;
        backup)
            backup_config
            ;;
        metrics)
            show_metrics
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
