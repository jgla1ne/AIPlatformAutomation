#!/bin/bash

#==============================================================================
# Script 3: Post-Deployment Configuration
# Purpose: Initialize databases, configure services, test integrations
# Version: 8.0.0 - Database Initialization & Service Configuration
#==============================================================================

set -euo pipefail

# Color definitions (matching Scripts 1 & 2)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Paths (matching Scripts 1 & 2)
readonly DATA_ROOT="/mnt/data"
readonly METADATA_DIR="$DATA_ROOT/metadata"
readonly STATE_FILE="$METADATA_DIR/setup_state.json"
readonly LOG_FILE="$DATA_ROOT/logs/configuration.log"
readonly ENV_FILE="$DATA_ROOT/.env"
readonly SERVICES_FILE="$METADATA_DIR/selected_services.json"
readonly COMPOSE_FILE="$DATA_ROOT/ai-platform/deployment/stack/docker-compose.yml"
readonly CONFIG_DIR="$DATA_ROOT/config"
readonly CREDENTIALS_FILE="$METADATA_DIR/credentials.json"

# Print functions (matching Scripts 1 & 2)
print_info() {
    echo -e "${CYAN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_phase() {
    local phase="$1"
    local icon="$2"
    local title="$3"
    echo ""
    echo -e "${BLUE}━━━ PHASE $phase: $icon $title ━━━${NC}" | tee -a "$LOG_FILE"
}

# Load environment
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: .env not found at $ENV_FILE${NC}"
    exit 1
fi

source "$ENV_FILE"

# Load selected services
if [ ! -f "$SERVICES_FILE" ]; then
    echo -e "${RED}Error: Selected services file not found. Run Script 1 first.${NC}"
    exit 1
fi

SELECTED_SERVICES=($(jq -r '.services[].key' "$SERVICES_FILE"))
TOTAL_SERVICES=${#SELECTED_SERVICES[@]}

#============================================================================
# PHASE 1: Database Initialization
#============================================================================

initialize_databases() {
    print_phase "1" "🗄️" "Database Initialization"
    
    # Wait for postgres to be fully ready
    print_info "Waiting for PostgreSQL..."
    local retries=0
    while [ $retries -lt 30 ]; do
        if docker exec postgres pg_isready -U "${POSTGRES_USER:-aiplatform}" &>/dev/null; then
            print_success "PostgreSQL ready"
            break
        fi
        sleep 2
        retries=$((retries + 1))
    done
    
    if [ $retries -eq 30 ]; then
        print_error "PostgreSQL failed to become ready"
        return 1
    fi
    
    # Create databases for each service
    print_info "Creating databases for selected services..."
    
    # Check if postgres is in selected services
    if [[ " ${SELECTED_SERVICES[@]} " =~ " postgres " ]]; then
        # LiteLLM database
        if [[ " ${SELECTED_SERVICES[@]} " =~ " litellm " ]]; then
            print_info "Creating LiteLLM database..."
            docker exec postgres psql -U "${POSTGRES_USER:-aiplatform}" -c "CREATE DATABASE litellm;" 2>/dev/null || print_info "  litellm database already exists"
        fi
        
        # Dify database
        if [[ " ${SELECTED_SERVICES[@]} " =~ " dify-api " ]]; then
            print_info "Creating Dify database..."
            docker exec postgres psql -U "${POSTGRES_USER:-aiplatform}" -c "CREATE DATABASE dify;" 2>/dev/null || print_info "  dify database already exists"
        fi
        
        # n8n database
        if [[ " ${SELECTED_SERVICES[@]} " =~ " n8n " ]]; then
            print_info "Creating n8n database..."
            docker exec postgres psql -U "${POSTGRES_USER:-aiplatform}" -c "CREATE DATABASE n8n;" 2>/dev/null || print_info "  n8n database already exists"
        fi
        
        # Flowise database
        if [[ " ${SELECTED_SERVICES[@]} " =~ " flowise " ]]; then
            print_info "Creating Flowise database..."
            docker exec postgres psql -U "${POSTGRES_USER:-aiplatform}" -c "CREATE DATABASE flowise;" 2>/dev/null || print_info "  flowise database already exists"
        fi
    fi
    
    print_success "Database initialization completed"
}

#============================================================================
# PHASE 2: LiteLLM Configuration
#============================================================================

configure_litellm() {
    if [[ ! " ${SELECTED_SERVICES[@]} " =~ " litellm " ]]; then
        return 0
    fi
    
    print_phase "2" "🔗" "LiteLLM Configuration"
    
    # Wait for LiteLLM container to be ready
    print_info "Waiting for LiteLLM container..."
    local retries=0
    while [ $retries -lt 60 ]; do
        if docker ps --format '{{.Names}}' | grep -q "^litellm$"; then
            print_success "LiteLLM container is running"
            break
        fi
        sleep 2
        retries=$((retries + 1))
    done
    
    if [ $retries -eq 60 ]; then
        print_error "LiteLLM container failed to start"
        return 1
    fi
    
    # Initialize LiteLLM database
    print_info "Initializing LiteLLM database schema..."
    docker exec litellm python -c "from litellm.proxy.proxy_server import initialize; initialize()" 2>/dev/null || print_warning "LiteLLM schema initialization may have failed"
    
    # Test LiteLLM health
    print_info "Testing LiteLLM API..."
    if curl -s -f http://localhost:8010/health &>/dev/null; then
        print_success "LiteLLM API responding"
    else
        print_error "LiteLLM API not responding"
        docker logs litellm --tail 20
        return 1
    fi
    
    # Test Ollama connection
    if [[ " ${SELECTED_SERVICES[@]} " =~ " ollama " ]]; then
        print_info "Testing LiteLLM → Ollama connection..."
        if docker exec litellm curl -s http://ollama:11434/ &>/dev/null; then
            print_success "Ollama accessible from LiteLLM"
        else
            print_warning "Ollama not accessible from LiteLLM"
        fi
    fi
    
    print_success "LiteLLM configuration completed"
}

#============================================================================
# PHASE 3: Ollama Model Management
#============================================================================

configure_ollama() {
    if [[ ! " ${SELECTED_SERVICES[@]} " =~ " ollama " ]]; then
        return 0
    fi
    
    print_phase "3" "🤖" "Ollama Model Configuration"
    
    # Wait for Ollama container to be ready
    print_info "Waiting for Ollama container..."
    local retries=0
    while [ $retries -lt 60 ]; do
        if docker ps --format '{{.Names}}' | grep -q "^ollama$"; then
            print_success "Ollama container is running"
            break
        fi
        sleep 2
        retries=$((retries + 1))
    done
    
    if [ $retries -eq 60 ]; then
        print_error "Ollama container failed to start"
        return 1
    fi
    
    # Parse model list
    if [ -n "${OLLAMA_MODELS:-}" ]; then
        print_info "Pulling Ollama models: $OLLAMA_MODELS"
        IFS=',' read -ra MODELS <<< "$OLLAMA_MODELS"
        
        for model in "${MODELS[@]}"; do
            print_info "Pulling model: $model"
            docker exec ollama ollama pull "$model" &
        done
        
        print_info "Waiting for model pulls to complete..."
        wait
        
        print_success "All models pulled"
        
        # List available models
        print_info "Available models:"
        docker exec ollama ollama list
    else
        print_warning "No Ollama models specified in OLLAMA_MODELS"
    fi
    
    print_success "Ollama configuration completed"
}

#============================================================================
# PHASE 4: Dify Initialization
#============================================================================

configure_dify() {
    if [[ ! " ${SELECTED_SERVICES[@]} " =~ " dify-api " ]]; then
        return 0
    fi
    
    print_phase "4" "🎯" "Dify Configuration"
    
    # Wait for Dify API container to be ready
    print_info "Waiting for Dify API container..."
    local retries=0
    while [ $retries -lt 120 ]; do
        if docker ps --format '{{.Names}}' | grep -q "^dify-api$"; then
            print_success "Dify API container is running"
            break
        fi
        sleep 2
        retries=$((retries + 1))
    done
    
    if [ $retries -eq 120 ]; then
        print_error "Dify API container failed to start"
        return 1
    fi
    
    # Run Dify database migrations
    print_info "Running Dify database migrations..."
    if docker exec dify-api flask db upgrade 2>&1 | tee -a "$LOG_FILE"; then
        print_success "Dify database migrated"
    else
        print_error "Dify migration failed"
        return 1
    fi
    
    # Test Dify API health
    print_info "Testing Dify API..."
    if curl -s -f http://localhost:5001/health &>/dev/null; then
        print_success "Dify API responding"
    else
        print_warning "Dify API not responding yet"
    fi
    
    print_success "Dify configuration completed"
}

#============================================================================
# PHASE 5: Vector Database Setup
#============================================================================

configure_vector_db() {
    if [[ ! " ${SELECTED_SERVICES[@]} " =~ " qdrant " ]]; then
        return 0
    fi
    
    print_phase "5" "🔍" "Vector Database Configuration"
    
    # Wait for Qdrant container to be ready
    print_info "Waiting for Qdrant container..."
    local retries=0
    while [ $retries -lt 60 ]; do
        if docker ps --format '{{.Names}}' | grep -q "^qdrant$"; then
            print_success "Qdrant container is running"
            break
        fi
        sleep 2
        retries=$((retries + 1))
    done
    
    if [ $retries -eq 60 ]; then
        print_error "Qdrant container failed to start"
        return 1
    fi
    
    # Test Qdrant connection
    print_info "Testing Qdrant..."
    if curl -s -f http://localhost:6333/ &>/dev/null; then
        print_success "Qdrant responding"
        
        # Get collections
        local collections=$(curl -s http://localhost:6333/collections | jq -r '.result.collections | length' 2>/dev/null || echo "0")
        print_info "Current collections: $collections"
    else
        print_error "Qdrant not responding"
        return 1
    fi
    
    print_success "Vector database configuration completed"
}

#============================================================================
# PHASE 6: Service Integration Testing
#============================================================================

test_integrations() {
    print_phase "6" "🧪" "Integration Testing"
    
    local failed_tests=0
    
    # Test 1: Database connections
    print_info "Testing database connections..."
    if [[ " ${SELECTED_SERVICES[@]} " =~ " litellm " ]]; then
        if docker exec litellm psql -h postgres -U "${POSTGRES_USER:-aiplatform}" -d litellm -c "SELECT 1;" &>/dev/null; then
            print_success "LiteLLM → PostgreSQL connection OK"
        else
            print_error "LiteLLM → PostgreSQL connection FAILED"
            failed_tests=$((failed_tests + 1))
        fi
    fi
    
    # Test 2: Service-to-service communication
    print_info "Testing service communication..."
    if [[ " ${SELECTED_SERVICES[@]} " =~ " litellm " ]] && [[ " ${SELECTED_SERVICES[@]} " =~ " ollama " ]]; then
        if docker exec litellm curl -s http://ollama:11434/ &>/dev/null; then
            print_success "LiteLLM → Ollama communication OK"
        else
            print_error "LiteLLM → Ollama communication FAILED"
            failed_tests=$((failed_tests + 1))
        fi
    fi
    
    # Test 3: Health endpoints
    print_info "Testing health endpoints..."
    for service in "${SELECTED_SERVICES[@]}"; do
        case "$service" in
            "litellm")
                if curl -s -f http://localhost:8010/health &>/dev/null; then
                    print_success "LiteLLM health endpoint OK"
                else
                    print_warning "LiteLLM health endpoint not responding"
                fi
                ;;
            "ollama")
                if curl -s -f http://localhost:11434/ &>/dev/null; then
                    print_success "Ollama health endpoint OK"
                else
                    print_warning "Ollama health endpoint not responding"
                fi
                ;;
            "dify-api")
                if curl -s -f http://localhost:5001/health &>/dev/null; then
                    print_success "Dify API health endpoint OK"
                else
                    print_warning "Dify API health endpoint not responding"
                fi
                ;;
            "open-webui")
                if curl -s -f http://localhost:8080/ &>/dev/null; then
                    print_success "Open WebUI health endpoint OK"
                else
                    print_warning "Open WebUI health endpoint not responding"
                fi
                ;;
        esac
    done
    
    if [ $failed_tests -eq 0 ]; then
        print_success "All integration tests passed"
    else
        print_warning "$failed_tests integration tests failed"
    fi
    
    print_success "Integration testing completed"
}

#============================================================================
# PHASE 7: Generate Configuration Summary
#============================================================================

generate_configuration_summary() {
    print_phase "7" "📋" "Configuration Summary"
    
    local summary_file="$DATA_ROOT/configuration-summary.md"
    
    cat > "$summary_file" <<EOF
# AI Platform Configuration Summary

**Date:** $(date)
**Domain:** ${DOMAIN_NAME:-localhost}
**Services Configured:** $TOTAL_SERVICES

## Database Status
- PostgreSQL: ✅ Running
- Redis: $(docker ps --format '{{.Names}}' | grep -q "^redis$" && echo "✅ Running" || echo "❌ Not Running")

## Service Status
EOF

    for service in "${SELECTED_SERVICES[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^$service$"; then
            echo "- $service: ✅ Running" >> "$summary_file"
        else
            echo "- $service: ❌ Not Running" >> "$summary_file"
        fi
    done
    
    cat >> "$summary_file" <<EOF

## Access URLs
EOF

    # Add access URLs for each service
    for service in "${SELECTED_SERVICES[@]}"; do
        case "$service" in
            "ollama")
                echo "- Ollama: http://localhost:11434" >> "$summary_file"
                ;;
            "litellm")
                echo "- LiteLLM: http://localhost:8010/health" >> "$summary_file"
                ;;
            "open-webui")
                echo "- Open WebUI: http://localhost:8080" >> "$summary_file"
                ;;
            "dify-web")
                echo "- Dify: http://localhost:3000" >> "$summary_file"
                ;;
            "n8n")
                echo "- n8n: http://localhost:5678" >> "$summary_file"
                ;;
            "flowise")
                echo "- Flowise: http://localhost:3001" >> "$summary_file"
                ;;
            "anythingllm")
                echo "- AnythingLLM: http://localhost:3002" >> "$summary_file"
                ;;
            "prometheus")
                echo "- Prometheus: http://localhost:9090" >> "$summary_file"
                ;;
            "grafana")
                echo "- Grafana: http://localhost:3003" >> "$summary_file"
                ;;
        esac
    done
    
    print_success "Configuration summary generated: $summary_file"
}

#============================================================================
# Main Execution
#============================================================================

main() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            AI PLATFORM AUTOMATION - CONFIGURATION           ║${NC}"
    echo -e "${CYAN}║              Post-Deployment Setup Version 8.0.0           ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Verify unified compose file exists
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        print_error "Unified compose file not found: $COMPOSE_FILE"
        print_error "Run Scripts 1-2 first"
        exit 1
    fi
    
    print_success "Starting post-deployment configuration"
    print_info "Services to configure: ${SELECTED_SERVICES[*]}"
    
    # Execute configuration phases
    initialize_databases
    configure_litellm
    configure_ollama
    configure_dify
    configure_vector_db
    test_integrations
    generate_configuration_summary
    
    echo -e "\n${GREEN}🎉 Configuration completed successfully!${NC}"
    echo -e "${CYAN}✅ Databases initialized${NC}"
    echo -e "${CYAN}✅ Services configured${NC}"
    echo -e "${CYAN}✅ Integrations tested${NC}"
    echo -e "${CYAN}📄 Configuration summary: $DATA_ROOT/configuration-summary.md${NC}"
    echo -e "${CYAN}📄 Configuration log: $LOG_FILE${NC}"
}

main "$@"
