#!/bin/bash

#############################################
# Script 2: Deploy Services
# Purpose: Deploy all AI platform services using Docker Compose
# Usage: ./2-deploy-services.sh [--skip-build] [--service SERVICE_NAME]
#############################################

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

#############################################
# Configuration
#############################################

readonly PROJECT_ROOT="${SCRIPT_DIR}/.."
readonly DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
readonly ENV_FILE="${PROJECT_ROOT}/.env"
readonly DEPLOYMENT_TIMEOUT=300
readonly HEALTH_CHECK_RETRIES=30
readonly HEALTH_CHECK_INTERVAL=10

# Command line options
SKIP_BUILD=false
SPECIFIC_SERVICE=""

#############################################
# Validation Functions
#############################################

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check Docker
    if ! check_docker; then
        log_error "Docker is not available"
        return 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not available"
        return 1
    fi
    
    # Check docker-compose.yml exists
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        log_error "docker-compose.yml not found at $DOCKER_COMPOSE_FILE"
        return 1
    fi
    
    # Check .env file exists
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found. Please run script 1 first."
        return 1
    fi
    
    log_success "Prerequisites validated"
    return 0
}

validate_compose_file() {
    log_info "Validating Docker Compose file..."
    
    if docker-compose -f "$DOCKER_COMPOSE_FILE" config > /dev/null 2>&1; then
        log_success "Docker Compose file is valid"
        return 0
    elif docker compose -f "$DOCKER_COMPOSE_FILE" config > /dev/null 2>&1; then
        log_success "Docker Compose file is valid"
        return 0
    else
        log_error "Docker Compose file validation failed"
        return 1
    fi
}

#############################################
# Deployment Functions
#############################################

create_networks() {
    log_info "Creating Docker networks..."
    
    local networks=("ai_platform_network")
    
    for network in "${networks[@]}"; do
        if ! docker network inspect "$network" &> /dev/null; then
            log_info "Creating network: $network"
            docker network create "$network" || {
                log_error "Failed to create network: $network"
                return 1
            }
        else
            log_info "Network already exists: $network"
        fi
    done
    
    log_success "Networks created"
    return 0
}

create_volumes() {
    log_info "Creating Docker volumes..."
    
    local volumes=(
        "ollama_data"
        "open_webui_data"
        "n8n_data"
        "postgres_data"
        "qdrant_data"
    )
    
    for volume in "${volumes[@]}"; do
        if ! docker volume inspect "$volume" &> /dev/null; then
            log_info "Creating volume: $volume"
            docker volume create "$volume" || {
                log_error "Failed to create volume: $volume"
                return 1
            }
        else
            log_info "Volume already exists: $volume"
        fi
    done
    
    log_success "Volumes created"
    return 0
}

pull_images() {
    log_info "Pulling Docker images..."
    
    local compose_cmd
    if command -v docker-compose &> /dev/null; then
        compose_cmd="docker-compose"
    else
        compose_cmd="docker compose"
    fi
    
    if [[ -n "$SPECIFIC_SERVICE" ]]; then
        $compose_cmd -f "$DOCKER_COMPOSE_FILE" pull "$SPECIFIC_SERVICE" || {
            log_error "Failed to pull image for service: $SPECIFIC_SERVICE"
            return 1
        }
    else
        $compose_cmd -f "$DOCKER_COMPOSE_FILE" pull || {
            log_error "Failed to pull images"
            return 1
        }
    fi
    
    log_success "Images pulled"
    return 0
}

build_services() {
    if [[ "$SKIP_BUILD" == "true" ]]; then
        log_info "Skipping build step"
        return 0
    fi
    
    log_info "Building services..."
    
    local compose_cmd
    if command -v docker-compose &> /dev/null; then
        compose_cmd="docker-compose"
    else
        compose_cmd="docker compose"
    fi
    
    if [[ -n "$SPECIFIC_SERVICE" ]]; then
        $compose_cmd -f "$DOCKER_COMPOSE_FILE" build "$SPECIFIC_SERVICE" || {
            log_error "Failed to build service: $SPECIFIC_SERVICE"
            return 1
        }
    else
        $compose_cmd -f "$DOCKER_COMPOSE_FILE" build || {
            log_error "Failed to build services"
            return 1
        }
    fi
    
    log_success "Services built"
    return 0
}

deploy_services() {
    log_info "Deploying services..."
    
    local compose_cmd
    if command -v docker-compose &> /dev/null; then
        compose_cmd="docker-compose"
    else
        compose_cmd="docker compose"
    fi
    
    if [[ -n "$SPECIFIC_SERVICE" ]]; then
        $compose_cmd -f "$DOCKER_COMPOSE_FILE" up -d "$SPECIFIC_SERVICE" || {
            log_error "Failed to deploy service: $SPECIFIC_SERVICE"
            return 1
        }
    else
        $compose_cmd -f "$DOCKER_COMPOSE_FILE" up -d || {
            log_error "Failed to deploy services"
            return 1
        }
    fi
    
    log_success "Services deployed"
    return 0
}

#############################################
# Health Check Functions
#############################################

check_service_health() {
    local service_name=$1
    local port=$2
    local endpoint=${3:-"/"}
    
    log_info "Checking health of $service_name..."
    
    local retries=0
    while [[ $retries -lt $HEALTH_CHECK_RETRIES ]]; do
        if curl -sf "http://localhost:${port}${endpoint}" > /dev/null 2>&1; then
            log_success "$service_name is healthy"
            return 0
        fi
        
        retries=$((retries + 1))
        if [[ $retries -lt $HEALTH_CHECK_RETRIES ]]; then
            log_info "Waiting for $service_name... (attempt $retries/$HEALTH_CHECK_RETRIES)"
            sleep $HEALTH_CHECK_INTERVAL
        fi
    done
    
    log_error "$service_name failed health check"
    return 1
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    local services_to_check=(
        "ollama:11434"
        "open-webui:8080"
        "n8n:5678"
        "postgres:5432"
        "qdrant:6333"
    )
    
    local failed_services=()
    
    for service_info in "${services_to_check[@]}"; do
        IFS=':' read -r service port <<< "$service_info"
        
        # Skip if specific service requested and this isn't it
        if [[ -n "$SPECIFIC_SERVICE" && "$service" != "$SPECIFIC_SERVICE" ]]; then
            continue
        fi
        
        # Check if container is running
        if ! docker ps --filter "name=${service}" --filter "status=running" | grep -q "$service"; then
            log_error "Container $service is not running"
            failed_services+=("$service")
            continue
        fi
        
        # Health check based on service type
        case $service in
            ollama)
                check_service_health "$service" "$port" "/api/tags" || failed_services+=("$service")
                ;;
            open-webui)
                check_service_health "$service" "$port" "/" || failed_services+=("$service")
                ;;
            n8n)
                check_service_health "$service" "$port" "/healthz" || failed_services+=("$service")
                ;;
            qdrant)
                check_service_health "$service" "$port" "/health" || failed_services+=("$service")
                ;;
            postgres)
                if docker exec postgres pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
                    log_success "$service is healthy"
                else
                    log_error "$service failed health check"
                    failed_services+=("$service")
                fi
                ;;
        esac
    done
    
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        log_success "All services are healthy"
        return 0
    else
        log_error "Failed services: ${failed_services[*]}"
        return 1
    fi
}

#############################################
# Display Functions
#############################################

display_service_info() {
    log_info "Deployed Services:"
    echo ""
    echo "  Ollama API:      http://localhost:11434"
    echo "  Open WebUI:      http://localhost:8080"
    echo "  n8n:             http://localhost:5678"
    echo "  Qdrant:          http://localhost:6333"
    echo "  PostgreSQL:      localhost:5432"
    echo ""
    log_info "Use 'docker-compose logs -f [service]' to view logs"
    log_info "Use 'docker-compose ps' to check service status"
}

#############################################
# Argument Parsing
#############################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --service)
                SPECIFIC_SERVICE="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-build       Skip building services"
                echo "  --service SERVICE  Deploy only specific service"
                echo "  -h, --help        Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

#############################################
# Main Execution
#############################################

main() {
    log_header "AI Platform - Deploy Services"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Validate prerequisites
    validate_prerequisites || exit 1
    validate_compose_file || exit 1
    
    # Create infrastructure
    create_networks || exit 1
    create_volumes || exit 1
    
    # Deploy services
    pull_images || exit 1
    build_services || exit 1
    deploy_services || exit 1
    
    # Verify deployment
    log_info "Waiting for services to stabilize..."
    sleep 10
    
    verify_deployment || {
        log_error "Deployment verification failed"
        log_info "Check logs with: docker-compose logs"
        exit 1
    }
    
    # Display information
    display_service_info
    
    log_success "Service deployment completed successfully"
}

# Execute main function
main "$@"
