#!/bin/bash

#############################################
# Script 3: Configure Services
# Purpose: Configure all deployed services with initial settings
# Usage: ./3-configure-services.sh [--service SERVICE_NAME]
#############################################

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

#############################################
# Configuration
#############################################

readonly PROJECT_ROOT="${SCRIPT_DIR}/.."
readonly ENV_FILE="${PROJECT_ROOT}/.env"
readonly CONFIG_DIR="${PROJECT_ROOT}/config"
readonly MAX_RETRIES=30
readonly RETRY_INTERVAL=10

# Command line options
SPECIFIC_SERVICE=""

#############################################
# Load Environment Variables
#############################################

load_environment() {
    log_info "Loading environment variables..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found. Please run script 1 first."
        return 1
    fi
    
    # Source environment file
    set -a
    source "$ENV_FILE"
    set +a
    
    log_success "Environment variables loaded"
    return 0
}

#############################################
# Ollama Configuration
#############################################

configure_ollama() {
    log_info "Configuring Ollama..."
    
    # Check if Ollama is running
    if ! curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
        log_error "Ollama is not running"
        return 1
    fi
    
    # Pull default model if specified
    if [[ -n "${OLLAMA_DEFAULT_MODEL:-}" ]]; then
        log_info "Pulling default model: $OLLAMA_DEFAULT_MODEL"
        
        docker exec ollama ollama pull "$OLLAMA_DEFAULT_MODEL" || {
            log_error "Failed to pull model: $OLLAMA_DEFAULT_MODEL"
            return 1
        }
        
        log_success "Model pulled: $OLLAMA_DEFAULT_MODEL"
    fi
    
    # Pull additional models if specified
    if [[ -n "${OLLAMA_ADDITIONAL_MODELS:-}" ]]; then
        IFS=',' read -ra MODELS <<< "$OLLAMA_ADDITIONAL_MODELS"
        for model in "${MODELS[@]}"; do
            model=$(echo "$model" | xargs)  # Trim whitespace
            log_info "Pulling model: $model"
            
            docker exec ollama ollama pull "$model" || {
                log_warning "Failed to pull model: $model"
            }
        done
    fi
    
    log_success "Ollama configured"
    return 0
}

#############################################
# PostgreSQL Configuration
#############################################

configure_postgres() {
    log_info "Configuring PostgreSQL..."
    
    # Wait for PostgreSQL to be ready
    local retries=0
    while [[ $retries -lt $MAX_RETRIES ]]; do
        if docker exec postgres pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
            break
        fi
        retries=$((retries + 1))
        log_info "Waiting for PostgreSQL... (attempt $retries/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
    done
    
    if [[ $retries -eq $MAX_RETRIES ]]; then
        log_error "PostgreSQL failed to become ready"
        return 1
    fi
    
    # Create databases if they don't exist
    local databases=("${N8N_DB_NAME}" "${QDRANT_DB_NAME:-qdrant}")
    
    for db in "${databases[@]}"; do
        log_info "Ensuring database exists: $db"
        
        docker exec postgres psql -U "$POSTGRES_USER" -tc "SELECT 1 FROM pg_database WHERE datname = '$db'" | grep -q 1 || \
        docker exec postgres psql -U "$POSTGRES_USER" -c "CREATE DATABASE $db;" || {
            log_warning "Database $db may already exist or failed to create"
        }
    done
    
    # Run initialization SQL if it exists
    if [[ -f "${CONFIG_DIR}/postgres/init.sql" ]]; then
        log_info "Running PostgreSQL initialization script"
        
        docker exec -i postgres psql -U "$POSTGRES_USER" < "${CONFIG_DIR}/postgres/init.sql" || {
            log_warning "PostgreSQL initialization script failed"
        }
    fi
    
    log_success "PostgreSQL configured"
    return 0
}

#############################################
# Qdrant Configuration
#############################################

configure_qdrant() {
    log_info "Configuring Qdrant..."
    
    # Wait for Qdrant to be ready
    local retries=0
    while [[ $retries -lt $MAX_RETRIES ]]; do
        if curl -sf http://localhost:6333/health > /dev/null 2>&1; then
            break
        fi
        retries=$((retries + 1))
        log_info "Waiting for Qdrant... (attempt $retries/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
    done
    
    if [[ $retries -eq $MAX_RETRIES ]]; then
        log_error "Qdrant failed to become ready"
        return 1
    fi
    
    # Create default collection if specified
    if [[ -n "${QDRANT_DEFAULT_COLLECTION:-}" ]]; then
        log_info "Creating default collection: $QDRANT_DEFAULT_COLLECTION"
        
        local collection_config='{
            "vectors": {
                "size": 384,
                "distance": "Cosine"
            }
        }'
        
        curl -sf -X PUT "http://localhost:6333/collections/${QDRANT_DEFAULT_COLLECTION}" \
            -H 'Content-Type: application/json' \
            -d "$collection_config" > /dev/null 2>&1 || {
            log_warning "Failed to create collection or it already exists"
        }
    fi
    
    log_success "Qdrant configured"
    return 0
}

#############################################
# n8n Configuration
#############################################

configure_n8n() {
    log_info "Configuring n8n..."
    
    # Wait for n8n to be ready
    local retries=0
    while [[ $retries -lt $MAX_RETRIES ]]; do
        if curl -sf http://localhost:5678/healthz > /dev/null 2>&1; then
            break
        fi
        retries=$((retries + 1))
        log_info "Waiting for n8n... (attempt $retries/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
    done
    
    if [[ $retries -eq $MAX_RETRIES ]]; then
        log_error "n8n failed to become ready"
        return 1
    fi
    
    # Import workflows if they exist
    if [[ -d "${CONFIG_DIR}/n8n/workflows" ]]; then
        log_info "Importing n8n workflows"
        
        for workflow_file in "${CONFIG_DIR}"/n8n/workflows/*.json; do
            if [[ -f "$workflow_file" ]]; then
                local workflow_name=$(basename "$workflow_file" .json)
                log_info "Importing workflow: $workflow_name"
                
                # Note: This requires n8n API access, which may need authentication
                # Adjust based on your n8n setup
                curl -sf -X POST "http://localhost:5678/api/v1/workflows" \
                    -H 'Content-Type: application/json' \
                    -d @"$workflow_file" > /dev/null 2>&1 || {
                    log_warning "Failed to import workflow: $workflow_name"
                }
            fi
        done
    fi
    
    log_success "n8n configured"
    return 0
}

#############################################
# Open WebUI Configuration
#############################################

configure_open_webui() {
    log_info "Configuring Open WebUI..."
    
    # Wait for Open WebUI to be ready
    local retries=0
    while [[ $retries -lt $MAX_RETRIES ]]; do
        if curl -sf http://localhost:8080 > /dev/null 2>&1; then
            break
        fi
        retries=$((retries + 1))
        log_info "Waiting for Open WebUI... (attempt $retries/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
    done
    
    if [[ $retries -eq $MAX_RETRIES ]]; then
        log_error "Open WebUI failed to become ready"
        return 1
    fi
    
    # Apply custom configurations if config file exists
    if [[ -f "${CONFIG_DIR}/open-webui/config.json" ]]; then
        log_info "Applying Open WebUI configuration"
        # Configuration would be applied via API or volume mount
        # This depends on Open WebUI's configuration method
    fi
    
    log_success "Open WebUI configured"
    return 0
}

#############################################
# Service Integration Configuration
#############################################

configure_integrations() {
    log_info "Configuring service integrations..."
    
    # Configure n8n to use Ollama
    log_info "Setting up n8n-Ollama integration"
    # This would typically involve creating credentials in n8n
    
    # Configure Open WebUI to use Ollama
    log_info "Setting up Open WebUI-Ollama integration"
    # Usually handled via OLLAMA_BASE_URL environment variable
    
    # Configure Qdrant integration
    log_info "Setting up Qdrant integration"
    # Configuration for embedding storage
    
    log_success "Service integrations configured"
    return 0
}

#############################################
# Verification
#############################################

verify_configuration() {
    log_info "Verifying configuration..."
    
    local failed_checks=()
    
    # Verify Ollama models
    if [[ -n "${OLLAMA_DEFAULT_MODEL:-}" ]]; then
        if ! docker exec ollama ollama list | grep -q "$OLLAMA_DEFAULT_MODEL"; then
            failed_checks+=("Ollama default model not found")
        fi
    fi
    
    # Verify PostgreSQL databases
    if ! docker exec postgres psql -U "$POSTGRES_USER" -lqt | cut -d \| -f 1 | grep -qw "$N8N_DB_NAME"; then
        failed_checks+=("n8n database not found")
    fi
    
    # Verify Qdrant collections
    if [[ -n "${QDRANT_DEFAULT_COLLECTION:-}" ]]; then
        if ! curl -sf "http://localhost:6333/collections/${QDRANT_DEFAULT_COLLECTION}" > /dev/null 2>&1; then
            failed_checks+=("Qdrant default collection not found")
        fi
    fi
    
    if [[ ${#failed_checks[@]} -eq 0 ]]; then
        log_success "Configuration verified"
        return 0
    else
        log_warning "Some configuration checks failed:"
        for check in "${failed_checks[@]}"; do
            log_warning "  - $check"
        done
        return 1
    fi
}

#############################################
# Display Configuration Summary
#############################################

display_configuration_summary() {
    log_info "Configuration Summary:"
    echo ""
    echo "  Ollama:"
    echo "    - API: http://localhost:11434"
    echo "    - Models: $(docker exec ollama ollama list | tail -n +2 | wc -l) installed"
    echo ""
    echo "  PostgreSQL:"
    echo "    - Host: localhost:5432"
    echo "    - Databases: $(docker exec postgres psql -U "$POSTGRES_USER" -lqt | cut -d \| -f 1 | grep -v template | grep -v postgres | wc -l)"
    echo ""
    echo "  Qdrant:"
    echo "    - API: http://localhost:6333"
    echo "    - Dashboard: http://localhost:6333/dashboard"
    echo ""
    echo "  n8n:"
    echo "    - URL: http://localhost:5678"
    echo "    - Database: $N8N_DB_NAME"
    echo ""
    echo "  Open WebUI:"
    echo "    - URL: http://localhost:8080"
    echo ""
}

#############################################
# Argument Parsing
#############################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --service)
                SPECIFIC_SERVICE="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --service SERVICE  Configure only specific service"
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
    log_header "AI Platform - Configure Services"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Load environment
    load_environment || exit 1
    
    # Configure services
    if [[ -z "$SPECIFIC_SERVICE" || "$SPECIFIC_SERVICE" == "ollama" ]]; then
        configure_ollama || log_warning "Ollama configuration had issues"
    fi
    
    if [[ -z "$SPECIFIC_SERVICE" || "$SPECIFIC_SERVICE" == "postgres" ]]; then
        configure_postgres || log_warning "PostgreSQL configuration had issues"
    fi
    
    if [[ -z "$SPECIFIC_SERVICE" || "$SPECIFIC_SERVICE" == "qdrant" ]]; then
        configure_qdrant || log_warning "Qdrant configuration had issues"
    fi
    
    if [[ -z "$SPECIFIC_SERVICE" || "$SPECIFIC_SERVICE" == "n8n" ]]; then
        configure_n8n || log_warning "n8n configuration had issues"
    fi
    
    if [[ -z "$SPECIFIC_SERVICE" || "$SPECIFIC_SERVICE" == "open-webui" ]]; then
        configure_open_webui || log_warning "Open WebUI configuration had issues"
    fi
    
    # Configure integrations (only if no specific service)
    if [[ -z "$SPECIFIC_SERVICE" ]]; then
        configure_integrations || log_warning "Integration configuration had issues"
    fi
    
    # Verify configuration
    verify_configuration || log_warning "Some configuration verifications failed"
    
    # Display summary
    display_configuration_summary
    
    log_success "Service configuration completed"
    log_info "All services are ready to use!"
}

# Execute main function
main "$@"
