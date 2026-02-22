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
    show_detailed_metrics
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
    echo "  gdrive              Google Drive sync management menu"
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
        gdrive)
            gdrive_management
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
        echo "  8. Back to main menu"
        echo ""
        echo -n -e "${YELLOW}Select option [1-8]:${NC} "
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
                print_info "Returning to main menu..."
                break
                ;;
            *)
                print_warning "Invalid option. Please select 1-8."
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
