#!/bin/bash
# Script 4: Add Service to Stack
#
# NOTE: This script runs as root (required for Docker, AppArmor operations)
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
    echo -e "${CYAN}║            AI PLATFORM - ADD SERVICE TO STACK               ║${NC}"
    echo -e "${CYAN}║              Baseline v1.0.0 - Multi-Stack Ready           ║${NC}"
    echo -e "${CYAN}║           Extensible Service Addition with Isolation        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╝${NC}\n"
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

# Check if port is available
check_port_availability() {
    local port=$1
    
    if ss -tlnp | grep -q ":${port} "; then
        print_error "Port ${port} is already in use"
        return 1
    fi
    
    return 0
}

# Add service to stack
add_service() {
    local service_name=$1
    local service_image=$2
    local internal_port=$3
    local host_port=$4
    local extra_env="${5:-}"
    
    print_header "Adding Service: ${service_name}"
    
    detect_stack
    
    # Validate inputs
    if [[ -z "$service_name" || -z "$service_image" || -z "$internal_port" || -z "$host_port" ]]; then
        print_error "Usage: $0 add <name> <image> <internal_port> <host_port> [extra_env]"
        return 1
    fi
    
    # Check if service already exists
    if docker ps --format "{{.Names}}" | grep -q "^${service_name}$"; then
        print_error "Service $service_name already exists"
        return 1
    fi
    
    # Check port availability
    if ! check_port_availability "$host_port"; then
        return 1
    fi
    
    # Create service directories
    mkdir -p "${BASE_DIR}/data/${service_name}" "${BASE_DIR}/logs/${service_name}"
    chown -R ${STACK_USER_UID}:${STACK_USER_GID} "${BASE_DIR}/data/${service_name}"
    chown -R ${STACK_USER_UID}:${STACK_USER_GID} "${BASE_DIR}/logs/${service_name}"
    
    print_info "Created directories for ${service_name}"
    
    # Create service-specific AppArmor profile
    create_service_apparmor_profile "$service_name"
    
    # Get vector DB environment variables
    local vectordb_env=($(build_vectordb_env))
    
    # Deploy service
    print_info "Deploying ${service_name}..."
    docker run -d \
        --name "${service_name}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --security-opt "apparmor=${DOCKER_NETWORK}-${service_name}" \
        --user "${STACK_USER_UID}:${STACK_USER_GID}" \
        -p "${host_port}:${internal_port}" \
        -v "${BASE_DIR}/data/${service_name}:/app/data" \
        -v "${BASE_DIR}/logs/${service_name}:/app/logs" \
        ${vectordb_env[@]} \
        ${extra_env} \
        "${service_image}"
    
    # Add route to Caddy
    add_caddy_route "$service_name" "$internal_port"
    
    # Reload Caddy
    reload_caddy
    
    print_success "Service $service_name added to stack ${DOMAIN_NAME}"
    print_info "   Internal port: $internal_port"
    print_info "   Host port: $host_port"
    print_info "   URL: http://${DOMAIN_NAME}/${service_name}/"
}

# Create service-specific AppArmor profile
create_service_apparmor_profile() {
    local service_name=$1
    
    print_info "Creating AppArmor profile for ${service_name}..."
    
    # Copy default profile as base
    local src="/etc/apparmor.d/${APPARMOR_DEFAULT}"
    local dst="/etc/apparmor.d/${DOCKER_NETWORK}-${service_name}"
    
    if [[ -f "$src" ]]; then
        cp "$src" "$dst"
        
        # Update profile name
        sed -i "s/profile ai-platform-default/profile ai-platform-${service_name}/" "$dst"
        
        # Load the profile
        if apparmor_parser -r "$dst"; then
            print_success "AppArmor profile created: ${DOCKER_NETWORK}-${service_name}"
        else
            print_warning "Failed to load AppArmor profile for ${service_name}"
        fi
    else
        print_warning "Default AppArmor profile not found, skipping profile creation"
    fi
}

# Build vector DB environment variables
build_vectordb_env() {
    local vectordb_env=()
    
    case "${VECTOR_DB}" in
        qdrant)
            vectordb_env=(
                -e "VECTOR_DB=qdrant"
                -e "QDRANT_ENDPOINT=${VECTORDB_URL:-http://qdrant:6333}"
                -e "QDRANT_API_KEY="
                -e "QDRANT_COLLECTION=${VECTORDB_COLLECTION:-ai-platform}"
            )
            ;;
        pgvector)
            vectordb_env=(
                -e "VECTOR_DB=pgvector"
                -e "PGVECTOR_CONNECTION_STRING=${VECTORDB_URL}"
                -e "PGVECTOR_SCHEMA=ai_platform"
            )
            ;;
        weaviate)
            vectordb_env=(
                -e "VECTOR_DB=weaviate"
                -e "WEAVIATE_ENDPOINT=${VECTORDB_URL:-http://weaviate:8080}"
                -e "WEAVIATE_API_KEY="
                -e "WEAVIATE_CLASS=${VECTORDB_COLLECTION:-AIPlatform}"
            )
            ;;
        chroma)
            vectordb_env=(
                -e "VECTOR_DB=chroma"
                -e "CHROMA_HOST=${VECTORDB_HOST:-chroma}"
                -e "CHROMA_PORT=${VECTORDB_PORT:-8000}"
                -e "CHROMA_COLLECTION=${VECTORDB_COLLECTION:-ai-platform}"
            )
            ;;
    esac
    
    echo "${vectordb_env[@]}"
}

# Add route to Caddy
add_caddy_route() {
    local name=$1
    local port=$2
    
    print_info "Adding route to Caddy for ${name}..."
    
    local caddyfile="${BASE_DIR}/caddy/Caddyfile"
    
    if [[ ! -f "$caddyfile" ]]; then
        print_warning "Caddyfile not found, creating basic configuration"
        mkdir -p "${BASE_DIR}/caddy"
        cat > "$caddyfile" << EOF
{
    admin off
    auto_https off
}

:80 {
    handle /health {
        respond "OK" 200
    }
    
    handle_path /${name}/* {
        reverse_proxy ${name}:${port}
    }
    
    respond "AI Platform - use /servicename to access services" 200
}
EOF
        return
    fi
    
    # Insert route before the final respond directive
    if grep -q "respond.*AI Platform.*use /servicename" "$caddyfile"; then
        # Insert before the fallback response
        sed -i "/respond.*AI Platform.*use \/servicename/i\\
    handle_path /${name}/* {\\
        reverse_proxy ${name}:${port}\\
    }\\
" "$caddyfile"
    else
        # Append to the end
        cat >> "$caddyfile" << EOF

    handle_path /${name}/* {
        reverse_proxy ${name}:${port}
    }
EOF
    fi
    
    print_success "Caddy route added for ${name}"
}

# Reload Caddy
reload_caddy() {
    print_info "Reloading Caddy configuration..."
    
    if docker ps --format "{{.Names}}" | grep -q "^caddy$"; then
        if docker exec "caddy" caddy reload --config "/etc/caddy/Caddyfile"; then
            print_success "Caddy reloaded successfully"
        else
            print_warning "Failed to reload Caddy, restarting container..."
            docker restart "caddy"
        fi
    else
        print_warning "Caddy container not found"
    fi
}

# List available services templates
list_templates() {
    print_header "Available Service Templates"
    
    echo "📋 Predefined service templates:"
    echo ""
    
    cat << 'EOF'
1. Grafana
   Command: add grafana grafana/grafana:latest 3000 <host_port>
   Description: Monitoring and visualization platform
   
2. Prometheus
   Command: add prometheus prom/prometheus:latest 9090 <host_port>
   Description: Time series database and monitoring
   
3. Redis Exporter
   Command: add redis-exporter oliver006/redis_exporter:latest 9121 <host_port>
   Description: Redis metrics exporter for Prometheus
   
4. Node Exporter
   Command: add node-exporter prom/node-exporter:latest 9100 <host_port>
   Description: System metrics exporter for Prometheus
   
5. Custom Service
   Command: add <name> <image> <internal_port> <host_port>
   Description: Add any custom Docker image
   
EOF
    
    echo "💡 Examples:"
    echo "   $0 add grafana grafana/grafana:latest 3000 5012"
    echo "   $0 add prometheus prom/prometheus:latest 9090 5013"
    echo "   $0 add myservice myrepo/myservice:latest 8080 5014"
}

# Remove service from stack
remove_service() {
    local service_name=$1
    
    if [[ -z "$service_name" ]]; then
        print_error "Usage: $0 remove <service_name>"
        return 1
    fi
    
    print_header "Removing Service: ${service_name}"
    
    detect_stack
    
    # Check if service exists
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${service_name}$"; then
        print_error "Service $service_name not found"
        return 1
    fi
    
    # Stop and remove container
    print_info "Stopping ${service_name}..."
    docker stop "$service_name" 2>/dev/null || true
    
    print_info "Removing ${service_name} container..."
    docker rm "$service_name" 2>/dev/null || true
    
    # Remove AppArmor profile
    local profile_path="/etc/apparmor.d/${DOCKER_NETWORK}-${service_name}"
    if [[ -f "$profile_path" ]]; then
        print_info "Removing AppArmor profile..."
        apparmor_parser -R "$profile_path" 2>/dev/null || true
        rm -f "$profile_path"
    fi
    
    # Remove from Caddy
    remove_caddy_route "$service_name"
    
    # Reload Caddy
    reload_caddy
    
    # Ask about data removal
    read -p "Remove service data from ${BASE_DIR}/data/${service_name}? (y/N): " remove_data
    if [[ "$remove_data" =~ ^[Yy]$ ]]; then
        rm -rf "${BASE_DIR}/data/${service_name}"
        rm -rf "${BASE_DIR}/logs/${service_name}"
        print_success "Service data removed"
    fi
    
    print_success "Service $service_name removed from stack"
}

# Remove route from Caddy
remove_caddy_route() {
    local name=$1
    
    print_info "Removing route from Caddy for ${name}..."
    
    local caddyfile="${BASE_DIR}/caddy/Caddyfile"
    
    if [[ -f "$caddyfile" ]]; then
        # Remove the service block
        sed -i "/handle_path \/${name}\//,/}/d" "$caddyfile"
        print_success "Caddy route removed for ${name}"
    fi
}

# List services in stack
list_services() {
    print_header "Services in Stack"
    
    detect_stack
    
    echo "📊 Stack: ${DOMAIN_NAME}"
    echo ""
    
    echo "🔧 Running Services:"
    docker ps --filter "network=${DOCKER_NETWORK}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || {
        print_warning "No services found on network ${DOCKER_NETWORK}"
    }
    
    echo ""
    echo "📋 All Services (including stopped):"
    docker ps -a --filter "network=${DOCKER_NETWORK}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || {
        print_warning "No services found on network ${DOCKER_NETWORK}"
    }
}

# Show help
show_help() {
    print_header "Add Service Help"
    
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  add <name> <image> <internal_port> <host_port> [env]  Add a service to the stack"
    echo "  remove <service>                                     Remove a service from the stack"
    echo "  list                                                List all services in the stack"
    echo "  templates                                            Show available service templates"
    echo "  help                                                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 add grafana grafana/grafana:latest 3000 5012"
    echo "  $0 add prometheus prom/prometheus:latest 9090 5013"
    echo "  $0 add myservice myrepo/myservice:latest 8080 5014"
    echo "  $0 remove grafana"
    echo "  $0 list"
    echo ""
    echo "Environment Variables (from .env):"
    echo "  BASE_DIR, DOCKER_NETWORK, DOMAIN_NAME"
    echo "  STACK_USER_UID, STACK_USER_GID"
    echo "  VECTOR_DB, APPARMOR_DEFAULT"
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
        add)
            add_service "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
            ;;
        remove)
            remove_service "${2:-}"
            ;;
        list)
            list_services
            ;;
        templates)
            list_templates
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
