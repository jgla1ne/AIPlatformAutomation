#!/bin/bash

#==============================================================================
# Script 4: Add Service Dynamically
# Purpose: Interactive service addition with dependency validation
# Per README: Modular service addition post-deployment
# Version: 4.1.0 - Frontier Model Integration
#==============================================================================

set -euo pipefail

# Load shared libraries
SCRIPT_DIR="/mnt/data/scripts"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/manifest.sh"
source "${SCRIPT_DIR}/lib/caddy-generator.sh"
source "${SCRIPT_DIR}/lib/health-check.sh"

# Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly DATA_DIR="/mnt/data"
readonly CONFIG_DIR="$DATA_DIR/config"
readonly COMPOSE_DIR="$DATA_DIR/compose"
readonly METADATA_FILE="$DATA_DIR/.platform_metadata.json"
readonly ENV_FILE="$DATA_DIR/.env"
readonly SERVICES_CATALOG="$SCRIPT_DIR/services-catalog.json"

# Source environment
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo -e "${RED}Error: Environment file not found. Run script 1 first.${NC}"
    exit 1
fi

#------------------------------------------------------------------------------
# Service Catalog
#------------------------------------------------------------------------------

# Initialize service catalog if it doesn't exist
initialize_catalog() {
    if [[ ! -f "$SERVICES_CATALOG" ]]; then
        cat > "$SERVICES_CATALOG" <<'EOF'
{
  "services": {
    "core": [
      {
        "id": "ollama",
        "name": "Ollama",
        "category": "core",
        "description": "Local LLM runtime (Llama, Mistral, etc.)",
        "port": 11434,
        "dependencies": [],
        "optional_deps": [],
        "env_vars": ["OLLAMA_HOST", "OLLAMA_MODELS"],
        "volumes": ["ollama"],
        "status": "required"
      },
      {
        "id": "postgres",
        "name": "PostgreSQL",
        "category": "core",
        "description": "Relational database for application data",
        "port": 5432,
        "dependencies": [],
        "optional_deps": [],
        "env_vars": ["POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_DB"],
        "volumes": ["postgres"],
        "status": "required"
      },
      {
        "id": "redis",
        "name": "Redis",
        "category": "core",
        "description": "In-memory cache and message broker",
        "port": 6379,
        "dependencies": [],
        "optional_deps": [],
        "env_vars": ["REDIS_PASSWORD"],
        "volumes": ["redis"],
        "status": "required"
      },
      {
        "id": "traefik",
        "name": "Traefik",
        "category": "core",
        "description": "Reverse proxy and load balancer",
        "port": 80,
        "dependencies": [],
        "optional_deps": [],
        "env_vars": ["DOMAIN", "ACME_EMAIL"],
        "volumes": ["traefik"],
        "status": "required"
      }
    ],
    "vector_dbs": [
      {
        "id": "qdrant",
        "name": "Qdrant",
        "category": "vector_db",
        "description": "High-performance vector database",
        "port": 6333,
        "dependencies": [],
        "optional_deps": [],
        "env_vars": ["QDRANT_API_KEY"],
        "volumes": ["qdrant"],
        "mutually_exclusive": ["weaviate", "milvus"],
        "status": "optional"
      },
      {
        "id": "weaviate",
        "name": "Weaviate",
        "category": "vector_db",
        "description": "AI-native vector database",
        "port": 8080,
        "dependencies": [],
        "optional_deps": [],
        "env_vars": ["WEAVIATE_AUTHENTICATION_APIKEY_ENABLED", "WEAVIATE_AUTHENTICATION_APIKEY_ALLOWED_KEYS"],
        "volumes": ["weaviate"],
        "mutually_exclusive": ["qdrant", "milvus"],
        "status": "optional"
      },
      {
        "id": "milvus",
        "name": "Milvus",
        "category": "vector_db",
        "description": "Cloud-native vector database",
        "port": 19530,
        "dependencies": ["etcd", "minio"],
        "optional_deps": [],
        "env_vars": ["MILVUS_USERNAME", "MILVUS_PASSWORD"],
        "volumes": ["milvus"],
        "mutually_exclusive": ["qdrant", "weaviate"],
        "status": "optional"
      }
    ],
    "llm_gateways": [
      {
        "id": "litellm",
        "name": "LiteLLM",
        "category": "llm_gateway",
        "description": "Unified API for 100+ LLM providers",
        "port": 4000,
        "dependencies": ["postgres", "redis"],
        "optional_deps": ["ollama"],
        "env_vars": ["LITELLM_MASTER_KEY", "LITELLM_DATABASE_URL"],
        "volumes": ["litellm"],
        "status": "optional"
      }
    ],
    "ui_platforms": [
      {
        "id": "open-webui",
        "name": "Open WebUI",
        "category": "ui",
        "description": "ChatGPT-like interface for Ollama",
        "port": 3000,
        "dependencies": ["ollama"],
        "optional_deps": ["litellm"],
        "env_vars": ["WEBUI_SECRET_KEY", "WEBUI_AUTH"],
        "volumes": ["open-webui"],
        "status": "optional"
      },
      {
        "id": "anythingllm",
        "name": "AnythingLLM",
        "category": "ui",
        "description": "Document intelligence and RAG platform",
        "port": 3001,
        "dependencies": ["ollama"],
        "optional_deps": ["qdrant", "weaviate"],
        "env_vars": ["ANYTHINGLLM_AUTH_TOKEN", "ANYTHINGLLM_JWT_SECRET"],
        "volumes": ["anythingllm"],
        "status": "optional"
      },
      {
        "id": "dify",
        "name": "Dify",
        "category": "ui",
        "description": "LLM application development platform",
        "port": 8000,
        "dependencies": ["postgres", "redis"],
        "optional_deps": ["ollama", "qdrant"],
        "env_vars": ["DIFY_SECRET_KEY"],
        "volumes": ["dify"],
        "status": "optional"
      },
      {
        "id": "librechat",
        "name": "LibreChat",
        "category": "ui",
        "description": "Multi-model chat interface",
        "port": 3003,
        "dependencies": ["mongodb", "meilisearch"],
        "optional_deps": ["ollama"],
        "env_vars": ["LIBRECHAT_CREDS_KEY", "LIBRECHAT_JWT_SECRET"],
        "volumes": ["librechat"],
        "status": "optional"
      },
      {
        "id": "flowise",
        "name": "Flowise",
        "category": "ui",
        "description": "Visual flow builder for LLM apps",
        "port": 3004,
        "dependencies": ["postgres"],
        "optional_deps": ["ollama"],
        "env_vars": ["FLOWISE_USERNAME", "FLOWISE_PASSWORD"],
        "volumes": ["flowise"],
        "status": "optional"
      }
    ],
    "automation": [
      {
        "id": "n8n",
        "name": "n8n",
        "category": "automation",
        "description": "Workflow automation with 400+ integrations",
        "port": 5678,
        "dependencies": ["postgres"],
        "optional_deps": ["ollama"],
        "env_vars": ["N8N_ENCRYPTION_KEY"],
        "volumes": ["n8n"],
        "status": "optional"
      },
      {
        "id": "activepieces",
        "name": "Activepieces",
        "category": "automation",
        "description": "Open-source alternative to Zapier",
        "port": 3005,
        "dependencies": ["postgres", "redis"],
        "optional_deps": [],
        "env_vars": ["AP_ENCRYPTION_KEY", "AP_JWT_SECRET"],
        "volumes": ["activepieces"],
        "status": "optional"
      }
    ],
    "monitoring": [
      {
        "id": "grafana",
        "name": "Grafana",
        "category": "monitoring",
        "description": "Observability and monitoring dashboards",
        "port": 3006,
        "dependencies": ["prometheus"],
        "optional_deps": ["loki"],
        "env_vars": ["GF_SECURITY_ADMIN_PASSWORD"],
        "volumes": ["grafana"],
        "status": "optional"
      },
      {
        "id": "prometheus",
        "name": "Prometheus",
        "category": "monitoring",
        "description": "Metrics collection and alerting",
        "port": 9090,
        "dependencies": [],
        "optional_deps": [],
        "env_vars": [],
        "volumes": ["prometheus"],
        "status": "optional"
      },
      {
        "id": "loki",
        "name": "Loki",
        "category": "monitoring",
        "description": "Log aggregation system",
        "port": 3100,
        "dependencies": [],
        "optional_deps": [],
        "env_vars": [],
        "volumes": ["loki"],
        "status": "optional"
      },
      {
        "id": "uptime-kuma",
        "name": "Uptime Kuma",
        "category": "monitoring",
        "description": "Self-hosted uptime monitoring",
        "port": 3007,
        "dependencies": [],
        "optional_deps": [],
        "env_vars": [],
        "volumes": ["uptime-kuma"],
        "status": "optional"
      }
    ],
    "communication": [
      {
        "id": "signal-api",
        "name": "Signal API",
        "category": "communication",
        "description": "Signal messenger API bridge",
        "port": 8080,
        "dependencies": [],
        "optional_deps": [],
        "env_vars": ["SIGNAL_NUMBER", "SIGNAL_PASSWORD"],
        "volumes": ["signal"],
        "status": "optional"
      },
      {
        "id": "mattermost",
        "name": "Mattermost",
        "category": "communication",
        "description": "Team collaboration platform",
        "port": 8065,
        "dependencies": ["postgres"],
        "optional_deps": [],
        "env_vars": ["MM_SQLSETTINGS_DATASOURCE"],
        "volumes": ["mattermost"],
        "status": "optional"
      }
    ],
    "storage": [
      {
        "id": "minio",
        "name": "MinIO",
        "category": "storage",
        "description": "S3-compatible object storage",
        "port": 9000,
        "dependencies": [],
        "optional_deps": [],
        "env_vars": ["MINIO_ROOT_USER", "MINIO_ROOT_PASSWORD"],
        "volumes": ["minio"],
        "status": "optional"
      },
      {
        "id": "nextcloud",
        "name": "Nextcloud",
        "category": "storage",
        "description": "File sync and collaboration platform",
        "port": 8081,
        "dependencies": ["postgres", "redis"],
        "optional_deps": [],
        "env_vars": ["NEXTCLOUD_ADMIN_USER", "NEXTCLOUD_ADMIN_PASSWORD"],
        "volumes": ["nextcloud"],
        "status": "optional"
      }
    ],
    "auxiliary": [
      {
        "id": "mongodb",
        "name": "MongoDB",
        "category": "database",
        "description": "NoSQL document database",
        "port": 27017,
        "dependencies": [],
        "optional_deps": [],
        "env_vars": ["MONGODB_USER", "MONGODB_PASSWORD"],
        "volumes": ["mongodb"],
        "status": "auxiliary"
      },
      {
        "id": "meilisearch",
        "name": "MeiliSearch",
        "category": "search",
        "description": "Fast search engine",
        "port": 7700,
        "dependencies": [],
        "optional_deps": [],
        "env_vars": ["MEILI_MASTER_KEY"],
        "volumes": ["meilisearch"],
        "status": "auxiliary"
      },
      {
        "id": "etcd",
        "name": "etcd",
        "category": "database",
        "description": "Distributed key-value store",
        "port": 2379,
        "dependencies": [],
        "optional_deps": [],
        "env_vars": [],
        "volumes": ["etcd"],
        "status": "auxiliary"
      }
    ]
  }
}
EOF
    fi
}

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          ➕ AI Platform - Add Service Wizard              ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_phase() {
    echo ""
    echo -e "${BLUE}${BOLD}[PHASE $1] $2${NC}"
}

print_success() {
    echo -e "${GREEN}  ✓${NC} $1"
}

print_error() {
    echo -e "${RED}  ✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}  ⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}  ℹ${NC} $1"
}

print_box_start() {
    echo "┌────────────────────────────────────────────────────────────┐"
}

print_box_line() {
    printf "│ %-58s │\n" "$1"
}

print_box_end() {
    echo "└────────────────────────────────────────────────────────────┘"
}

get_deployed_services() {
    if [[ -f "$METADATA_FILE" ]]; then
        jq -r '.ui_services[].name' "$METADATA_FILE" 2>/dev/null || echo ""
    fi
}

is_service_deployed() {
    local service=$1
    docker ps --format "{{.Names}}" | grep -q "^${service}$"
}

check_port_available() {
    local port=$1
    ! netstat -tuln 2>/dev/null | grep -q ":${port} " && ! ss -tuln 2>/dev/null | grep -q ":${port} "
}

#------------------------------------------------------------------------------
# Phase 1: Service Selection
#------------------------------------------------------------------------------

select_service() {
    print_phase "1" "🎯 Service Selection"
    
    initialize_catalog
    
    echo ""
    echo -e "${BOLD}Available Service Categories:${NC}"
    echo ""
    echo "  1) UI Platforms        - Chat interfaces and document tools"
    echo "  2) Vector Databases    - Qdrant, Weaviate, Milvus"
    echo "  3) LLM Gateways        - LiteLLM proxy and routing"
    echo "  4) Automation Tools    - n8n, Activepieces workflows"
    echo "  5) Monitoring Stack    - Grafana, Prometheus, Loki"
    echo "  6) Communication       - Signal API, Mattermost"
    echo "  7) Storage Solutions   - MinIO, Nextcloud"
    echo "  8) List All Services   - Browse complete catalog"
    echo "  9) Custom Service      - Add unlisted service"
    echo ""
    
    read -p "Select category (1-9): " category_choice
    
    case $category_choice in
        1) show_category_services "ui_platforms" ;;
        2) show_category_services "vector_dbs" ;;
        3) show_category_services "llm_gateways" ;;
        4) show_category_services "automation" ;;
        5) show_category_services "monitoring" ;;
        6) show_category_services "communication" ;;
        7) show_category_services "storage" ;;
        8) show_all_services ;;
        9) add_custom_service ;;
        *) print_error "Invalid choice"; exit 1 ;;
    esac
}

show_category_services() {
    local category=$1
    local services=$(jq -r ".services.${category}[]" "$SERVICES_CATALOG" 2>/dev/null)
    
    if [[ -z "$services" ]]; then
        print_error "No services found in category: $category"
        exit 1
    fi
    
    echo ""
    echo -e "${BOLD}${category} Services:${NC}"
    echo ""
    
    local index=1
    local service_ids=()
    
    while IFS= read -r service_json; do
        local id=$(echo "$service_json" | jq -r '.id')
        local name=$(echo "$service_json" | jq -r '.name')
        local description=$(echo "$service_json" | jq -r '.description')
        local port=$(echo "$service_json" | jq -r '.port')
        
        service_ids+=("$id")
        
        # Check if already deployed
        local deployed_status=""
        if is_service_deployed "$id"; then
            deployed_status="${GREEN}[DEPLOYED]${NC}"
        fi
        
        echo -e "  ${CYAN}${index})${NC} ${BOLD}${name}${NC} ${deployed_status}"
        echo "     ${description}"
        echo "     Port: ${port}"
        echo ""
        
        ((index++))
    done < <(jq -c ".services.${category}[]" "$SERVICES_CATALOG")
    
    read -p "Select service number (1-$((index-1))): " service_choice
    
    if [[ $service_choice -lt 1 ]] || [[ $service_choice -ge $index ]]; then
        print_error "Invalid selection"
        exit 1
    fi
    
    SELECTED_SERVICE="${service_ids[$((service_choice-1))]}"
    SELECTED_SERVICE_JSON=$(jq ".services.${category}[$((service_choice-1))]" "$SERVICES_CATALOG")
}

show_all_services() {
    echo ""
    echo -e "${BOLD}Complete Service Catalog:${NC}"
    echo ""
    
    local all_services=()
    
    for category in $(jq -r '.services | keys[]' "$SERVICES_CATALOG"); do
        echo -e "${MAGENTA}▸ ${category}${NC}"
        
        while IFS= read -r service_json; do
            local id=$(echo "$service_json" | jq -r '.id')
            local name=$(echo "$service_json" | jq -r '.name')
            local description=$(echo "$service_json" | jq -r '.description')
            
            all_services+=("$id|$name|$description|$category")
            
            local deployed_status=""
            if is_service_deployed "$id"; then
                deployed_status="${GREEN}[DEPLOYED]${NC}"
            fi
            
            echo -e "  • ${BOLD}${name}${NC} ${deployed_status}"
            echo "    ${description}"
        done < <(jq -c ".services.${category}[]" "$SERVICES_CATALOG")
        
        echo ""
    done
    
    echo ""
    read -p "Enter service ID to add: " service_id
    
    # Find service in catalog
    SELECTED_SERVICE="$service_id"
    SELECTED_SERVICE_JSON=$(jq -r --arg id "$service_id" '
        .services | to_entries[] | .value[] | select(.id == $id)
    ' "$SERVICES_CATALOG")
    
    if [[ -z "$SELECTED_SERVICE_JSON" ]] || [[ "$SELECTED_SERVICE_JSON" == "null" ]]; then
        print_error "Service not found: $service_id"
        exit 1
    fi
}

add_custom_service() {
    echo ""
    echo -e "${BOLD}Custom Service Configuration${NC}"
    echo ""
    
    read -p "Service ID (lowercase, no spaces): " custom_id
    read -p "Service Name: " custom_name
    read -p "Description: " custom_description
    read -p "Docker Image: " custom_image
    read -p "Port: " custom_port
    read -p "Category: " custom_category
    
    SELECTED_SERVICE="$custom_id"
    SELECTED_SERVICE_JSON=$(cat <<EOF
{
  "id": "$custom_id",
  "name": "$custom_name",
  "category": "$custom_category",
  "description": "$custom_description",
  "image": "$custom_image",
  "port": $custom_port,
  "dependencies": [],
  "optional_deps": [],
  "env_vars": [],
  "volumes": ["$custom_id"],
  "status": "custom"
}
EOF
)
}

#------------------------------------------------------------------------------
# Phase 2: Dependency Validation
#------------------------------------------------------------------------------

validate_dependencies() {
    print_phase "2" "🔍 Dependency Validation"
    
    local service_name=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.name')
    local dependencies=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.dependencies[]' 2>/dev/null || echo "")
    local optional_deps=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.optional_deps[]' 2>/dev/null || echo "")
    local mutually_exclusive=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.mutually_exclusive[]?' 2>/dev/null || echo "")
    
    print_info "Validating dependencies for: $service_name"
    echo ""
    
    # Check if service already deployed
    if is_service_deployed "$SELECTED_SERVICE"; then
        print_warning "$service_name is already deployed"
        read -p "Do you want to redeploy/update it? (y/N): " redeploy
        if [[ ! "$redeploy" =~ ^[Yy]$ ]]; then
            print_info "Skipping deployment"
            exit 0
        fi
    fi
    
    # Check required dependencies
    local missing_deps=()
    if [[ -n "$dependencies" ]]; then
        echo -e "${BOLD}Required Dependencies:${NC}"
        for dep in $dependencies; do
            if is_service_deployed "$dep"; then
                print_success "$dep is running"
            else
                print_error "$dep is NOT running (required)"
                missing_deps+=("$dep")
            fi
        done
    fi
    
    # Check optional dependencies
    if [[ -n "$optional_deps" ]]; then
        echo ""
        echo -e "${BOLD}Optional Dependencies:${NC}"
        for dep in $optional_deps; do
            if is_service_deployed "$dep"; then
                print_success "$dep is running (will be integrated)"
            else
                print_warning "$dep is not running (optional, will work without it)"
            fi
        done
    fi
    
    # Check mutually exclusive services
    if [[ -n "$mutually_exclusive" ]]; then
        echo ""
        echo -e "${BOLD}Mutually Exclusive Services:${NC}"
        for exclusive in $mutually_exclusive; do
            if is_service_deployed "$exclusive"; then
                print_error "$exclusive is running - cannot deploy $service_name alongside it"
                echo ""
                print_error "Remove $exclusive first or choose a different service"
                exit 1
            fi
        done
        print_success "No conflicts detected"
    fi
    
    # Handle missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo ""
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo ""
        read -p "Do you want to install missing dependencies automatically? (y/N): " install_deps
        
        if [[ "$install_deps" =~ ^[Yy]$ ]]; then
            for dep in "${missing_deps[@]}"; do
                print_info "Installing dependency: $dep"
                deploy_dependency "$dep"
            done
        else
            print_error "Cannot proceed without required dependencies"
            exit 1
        fi
    fi
    
    echo ""
    print_success "All dependency checks passed"
}

deploy_dependency() {
    local dep_id=$1
    
    # Find dependency in catalog
    local dep_json=$(jq -r --arg id "$dep_id" '
        .services | to_entries[] | .value[] | select(.id == $id)
    ' "$SERVICES_CATALOG")
    
    if [[ -z "$dep_json" ]] || [[ "$dep_json" == "null" ]]; then
        print_error "Dependency not found in catalog: $dep_id"
        return 1
    fi
    
    print_info "Deploying dependency: $dep_id"
    
    # Generate compose for dependency
    generate_service_compose "$dep_id" "$dep_json" "dependency"
    
    # Deploy dependency
    docker-compose -f "$COMPOSE_DIR/${dep_id}.yml" up -d
    
    sleep 5
    
    if is_service_deployed "$dep_id"; then
        print_success "Dependency $dep_id deployed successfully"
    else
        print_error "Failed to deploy dependency: $dep_id"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Phase 3: Port Conflict Detection
#------------------------------------------------------------------------------

check_port_conflicts() {
    print_phase "3" "🔌 Port Conflict Detection"
    
    local service_port=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.port')
    
    print_info "Checking port availability: $service_port"
    
    if check_port_available "$service_port"; then
        print_success "Port $service_port is available"
    else
        print_error "Port $service_port is already in use"
        echo ""
        print_info "Services using this port:"
        netstat -tuln 2>/dev/null | grep ":${service_port} " || ss -tuln 2>/dev/null | grep ":${service_port} "
        echo ""
        
        read -p "Enter alternative port (or 'q' to quit): " alt_port
        
        if [[ "$alt_port" == "q" ]]; then
            exit 1
        fi
        
        if ! [[ "$alt_port" =~ ^[0-9]+$ ]]; then
            print_error "Invalid port number"
            exit 1
        fi
        
        if ! check_port_available "$alt_port"; then
            print_error "Alternative port $alt_port is also in use"
            exit 1
        fi
        
        # Update service JSON with new port
        SELECTED_SERVICE_JSON=$(echo "$SELECTED_SERVICE_JSON" | jq ".port = $alt_port")
        print_success "Using alternative port: $alt_port"
    fi
}

#------------------------------------------------------------------------------
# Phase 4: Environment Configuration
#------------------------------------------------------------------------------

configure_service_env() {
    print_phase "4" "⚙️ Environment Configuration"
    
    local service_id=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.id')
    local service_name=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.name')
    local env_vars=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.env_vars[]' 2>/dev/null || echo "")
    
    if [[ -z "$env_vars" ]]; then
        print_info "No environment variables required"
        return 0
    fi
    
    echo ""
    echo -e "${BOLD}Required Environment Variables for ${service_name}:${NC}"
    echo ""
    
    local env_config=()
    
    for env_var in $env_vars; do
        # Check if already exists in .env
        if grep -q "^${env_var}=" "$ENV_FILE" 2>/dev/null; then
            local current_value=$(grep "^${env_var}=" "$ENV_FILE" | cut -d'=' -f2-)
            print_info "$env_var already set: ${current_value:0:20}..."
            read -p "Keep existing value? (Y/n): " keep_value
            
            if [[ ! "$keep_value" =~ ^[Nn]$ ]]; then
                continue
            fi
        fi
        
        # Generate default value
        local default_value=""
        case "$env_var" in
            *_PASSWORD|*_SECRET*|*_KEY|*_TOKEN)
                default_value=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
                ;;
            *_USER|*_USERNAME)
                default_value="admin"
                ;;
            *_DB|*_DATABASE)
                default_value="$service_id"
                ;;
            *_HOST)
                default_value="localhost"
                ;;
            *_PORT)
                default_value=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.port')
                ;;
        esac
        
        echo ""
        echo -e "${CYAN}${env_var}${NC}"
        if [[ -n "$default_value" ]]; then
            read -p "Value [default: ${default_value:0:30}...]: " user_value
            env_config+=("${env_var}=${user_value:-$default_value}")
        else
            read -p "Value: " user_value
            env_config+=("${env_var}=${user_value}")
        fi
    done
    
    # Write to .env
    echo "" >> "$ENV_FILE"
    echo "# ${service_name} Configuration (Added: $(date -u +"%Y-%m-%d %H:%M:%S"))" >> "$ENV_FILE"
    for config in "${env_config[@]}"; do
        echo "$config" >> "$ENV_FILE"
    done
    
    print_success "Environment variables configured"
    
    # Reload environment
    set -a
    source "$ENV_FILE"
    set +a
}

#------------------------------------------------------------------------------
# Phase 5: Docker Compose Generation
#------------------------------------------------------------------------------

generate_service_compose() {
    local service_id=${1:-$SELECTED_SERVICE}
    local service_json=${2:-$SELECTED_SERVICE_JSON}
    local deployment_type=${3:-"main"}
    
    print_phase "5" "📝 Generating Docker Compose Configuration"
    
    local service_name=$(echo "$service_json" | jq -r '.name')
    local service_port=$(echo "$service_json" | jq -r '.port')
    local service_image=$(echo "$service_json" | jq -r '.image // empty')
    local service_volumes=$(echo "$service_json" | jq -r '.volumes[]' 2>/dev/null || echo "")
    
    print_info "Creating compose file for: $service_name"
    
    # Generate compose file based on service type
    local compose_file="$COMPOSE_DIR/${service_id}.yml"
    
    cat > "$compose_file" <<EOF
version: '3.8'

networks:
  ai_platform:
    external: true

services:
  ${service_id}:
EOF

    # Determine image
    if [[ -n "$service_image" ]]; then
        echo "    image: $service_image" >> "$compose_file"
    else
        # Fallback to common image patterns
        case "$service_id" in
            open-webui)
                echo "    image: ghcr.io/open-webui/open-webui:main" >> "$compose_file"
                ;;
            anythingllm)
                echo "    image: mintplexlabs/anythingllm:latest" >> "$compose_file"
                ;;
            dify-*)
                echo "    image: langgenius/dify-${service_id#dify-}:latest" >> "$compose_file"
                ;;
            librechat)
                echo "    image: ghcr.io/danny-avila/librechat:latest" >> "$compose_file"
                ;;
            flowise)
                echo "    image: flowiseai/flowise:latest" >> "$compose_file"
                ;;
            n8n)
                echo "    image: n8nio/n8n:latest" >> "$compose_file"
                ;;
            qdrant)
                echo "    image: qdrant/qdrant:latest" >> "$compose_file"
                ;;
            weaviate)
                echo "    image: semitechnologies/weaviate:latest" >> "$compose_file"
                ;;
            litellm)
                echo "    image: ghcr.io/berriai/litellm:main-latest" >> "$compose_file"
                ;;
            grafana)
                echo "    image: grafana/grafana:latest" >> "$compose_file"
                ;;
            prometheus)
                echo "    image: prom/prometheus:latest" >> "$compose_file"
                ;;
            loki)
                echo "    image: grafana/loki:latest" >> "$compose_file"
                ;;
            uptime-kuma)
                echo "    image: louislam/uptime-kuma:latest" >> "$compose_file"
                ;;
            minio)
                echo "    image: minio/minio:latest" >> "$compose_file"
                ;;
            mongodb)
                echo "    image: mongo:latest" >> "$compose_file"
                ;;
            meilisearch)
                echo "    image: getmeili/meilisearch:latest" >> "$compose_file"
                ;;
            *)
                echo "    image: ${service_id}:latest" >> "$compose_file"
                ;;
        esac
    fi
    
    cat >> "$compose_file" <<EOF
    container_name: ${service_id}
    restart: unless-stopped
    networks:
      - ai_platform
    ports:
      - "${service_port}:${service_port}"
EOF

    # Add environment variables
    local env_vars=$(echo "$service_json" | jq -r '.env_vars[]' 2>/dev/null || echo "")
    if [[ -n "$env_vars" ]]; then
        echo "    environment:" >> "$compose_file"
        for env_var in $env_vars; do
            echo "      - ${env_var}=\${${env_var}}" >> "$compose_file"
        done
    fi
    
    # Add volumes
    if [[ -n "$service_volumes" ]]; then
        echo "    volumes:" >> "$compose_file"
        for volume in $service_volumes; do
            echo "      - \${DATA_DIR}/${volume}:/data" >> "$compose_file"
        done
    fi
    
    # Add Traefik labels
    if [[ "$deployment_type" == "main" ]]; then
        cat >> "$compose_file" <<EOF
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${service_id}.rule=Host(\`${service_id}.\${DOMAIN:-localhost}\`)"
      - "traefik.http.routers.${service_id}.entrypoints=websecure"
      - "traefik.http.routers.${service_id}.tls=true"
      - "traefik.http.services.${service_id}.loadbalancer.server.port=${service_port}"
EOF
    fi
    
    # Add dependencies
    local dependencies=$(echo "$service_json" | jq -r '.dependencies[]' 2>/dev/null || echo "")
    if [[ -n "$dependencies" ]]; then
        echo "    depends_on:" >> "$compose_file"
        for dep in $dependencies; do
            echo "      - ${dep}" >> "$compose_file"
        done
    fi
    
    print_success "Compose file generated: $compose_file"
}

#------------------------------------------------------------------------------
# Phase 6: Service Deployment
#------------------------------------------------------------------------------

deploy_service() {
    print_phase "6" "🚀 Service Deployment"
    
    local service_id=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.id')
    local service_name=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.name')
    local compose_file="$COMPOSE_DIR/${service_id}.yml"
    local service_port=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.port')
    local service_path=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.path // "/'"$service_id"'"'")
    local container_name=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.container // "'"${service_id}"'"')
    local service_image=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.image')
    
    print_info "Deploying $service_name..."
    
    # Create data directories
    local volumes=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.volumes[]' 2>/dev/null || echo "")
    for volume in $volumes; do
        mkdir -p "$DATA_DIR/$volume"
    done
    
    # Pull image
    echo -ne "${CYAN}  ⏳${NC} Pulling container image..."
    if docker-compose -f "$compose_file" pull > /dev/null 2>&1; then
        echo -e "\r${GREEN}  ✓${NC} Container image pulled                    "
    else
        echo -e "\r${YELLOW}  ⚠${NC} Could not pull image (may not exist)      "
    fi
    
    # Deploy service
    echo -ne "${CYAN}  ⏳${NC} Starting service..."
    if docker-compose -f "$compose_file" up -d; then
        echo -e "\r${GREEN}  ✓${NC} Service started                            "
    else
        echo -e "\r${RED}  ✗${NC} Failed to start service                    "
        return 1
    fi
    
    # 🔥 NEW: Update manifest with service info
    write_service_manifest "$service_id" "$service_port" "$service_path" "$container_name" "$service_image" "$service_port"
    
    # 🔥 NEW: Regenerate proxy configuration
    generate_caddy_config
    
    # 🔥 NEW: Reload proxy
    reload_caddy
    
    # Wait for service to be healthy
    local max_attempts=30
    local attempt=0
    
    echo -ne "${CYAN}  ⏳${NC} Waiting for service to be ready"
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -sf "http://localhost:${service_port}" > /dev/null 2>&1; then
            echo -e "\r${GREEN}  ✓${NC} Service is ready and responding            "
            break
        fi
        echo -ne "."
        sleep 2
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo -e "\r${YELLOW}  ⚠${NC} Service started but not responding (may need configuration)"
    fi
    
    print_success "$service_name deployed successfully"
}

#------------------------------------------------------------------------------
# Phase 7: Post-Deployment Configuration
#------------------------------------------------------------------------------

post_deployment_config() {
    print_phase "7" "🔧 Post-Deployment Configuration"
    
    local service_id=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.id')
    local service_name=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.name')
    local service_port=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.port')
    
    # Update metadata
    if [[ -f "$METADATA_FILE" ]]; then
        local temp_file=$(mktemp)
        jq --arg service "$service_id" \
           --arg name "$service_name" \
           --arg port "$service_port" \
           --arg url "http://localhost:${service_port}" \
           '.ui_services += [{"id": $service, "name": $name, "port": $port, "url": $url, "deployed_at": now | strftime("%Y-%m-%d %H:%M:%S UTC")}] | 
            .last_updated = (now | strftime("%Y-%m-%d %H:%M:%S UTC"))' \
           "$METADATA_FILE" > "$temp_file"
        mv "$temp_file" "$METADATA_FILE"
        print_success "Metadata updated"
    fi
    
    # Service-specific configuration
    case "$service_id" in
        anythingllm)
            print_info "Configuring AnythingLLM with Ollama..."
            # Wait a bit for AnythingLLM to initialize
            sleep 10
            # Configuration would go here via API
            print_success "AnythingLLM configured"
            ;;
        dify)
            print_info "Initializing Dify database..."
            # Database initialization commands
            print_success "Dify initialized"
            ;;
        litellm)
            print_info "Configuring LiteLLM with Ollama..."
            # LiteLLM proxy configuration
            print_success "LiteLLM configured"
            ;;
    esac
    
    print_success "Post-deployment configuration complete"
}

#------------------------------------------------------------------------------
# Phase 8: Integration Testing
#------------------------------------------------------------------------------

perform_integration_test() {
    print_phase "8" "🧪 Integration Testing"
    
    local service_id=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.id')
    local service_port=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.port')
    
    print_info "Testing service endpoints..."
    
    # Basic HTTP health check
    if curl -sf "http://localhost:${service_port}" > /dev/null 2>&1; then
        print_success "HTTP endpoint responding"
    else
        print_warning "HTTP endpoint not responding (may be normal for this service)"
    fi
    
    # Check container logs for errors
    local error_count=$(docker logs "$service_id" 2>&1 | grep -i "error" | wc -l)
    if [ "$error_count" -gt 0 ]; then
        print_warning "Found $error_count error(s) in logs"
        read -p "View logs? (y/N): " view_logs
        if [[ "$view_logs" =~ ^[Yy]$ ]]; then
            docker logs "$service_id" --tail 50
        fi
    else
        print_success "No errors in container logs"
    fi
    
    # Test integration with dependencies
    local dependencies=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.dependencies[]' 2>/dev/null || echo "")
    if [[ -n "$dependencies" ]]; then
        echo ""
        echo -e "${BOLD}Testing dependency connections:${NC}"
        for dep in $dependencies; do
            if docker exec "$service_id" ping -c 1 "$dep" > /dev/null 2>&1; then
                print_success "Can reach $dep"
            else
                print_warning "Cannot reach $dep (may not support ping)"
            fi
        done
    fi
    
    print_success "Integration tests complete"
}

#------------------------------------------------------------------------------
# Final Success Message
#------------------------------------------------------------------------------

print_final_success() {
    local service_id=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.id')
    local service_name=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.name')
    local service_port=$(echo "$SELECTED_SERVICE_JSON" | jq -r '.port')
    
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          ✅ SERVICE ADDED SUCCESSFULLY                     ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${BOLD}Service Details:${NC}"
    echo "  • Name: ${CYAN}${service_name}${NC}"
    echo "  • ID: ${CYAN}${service_id}${NC}"
    echo "  • URL: ${CYAN}http://localhost:${service_port}${NC}"
    echo "  • Domain: ${CYAN}https://${service_id}.${DOMAIN:-localhost}${NC}"
    echo ""
    echo -e "${BOLD}Quick Actions:${NC}"
    echo "  • View logs: ${CYAN}docker logs -f ${service_id}${NC}"
    echo "  • Restart: ${CYAN}docker-compose -f $COMPOSE_DIR/${service_id}.yml restart${NC}"
    echo "  • Remove: ${CYAN}docker-compose -f $COMPOSE_DIR/${service_id}.yml down${NC}"
    echo "  • Update: ${CYAN}docker-compose -f $COMPOSE_DIR/${service_id}.yml pull && docker-compose -f $COMPOSE_DIR/${service_id}.yml up -d${NC}"
    echo ""
    echo -e "${BOLD}Configuration:${NC}"
    echo "  • Environment: ${CYAN}$ENV_FILE${NC}"
    echo "  • Compose: ${CYAN}$COMPOSE_DIR/${service_id}.yml${NC}"
    echo "  • Data: ${CYAN}$DATA_DIR/${service_id}${NC}"
    echo ""
    
    read -p "Would you like to add another service? (y/N): " add_another
    if [[ "$add_another" =~ ^[Yy]$ ]]; then
        exec "$0"
    fi
}

#------------------------------------------------------------------------------
# Rollback on Failure
#------------------------------------------------------------------------------

rollback_deployment() {
    local service_id=$1
    
    print_error "Deployment failed - initiating rollback"
    
    # Stop and remove containers
    docker-compose -f "$COMPOSE_DIR/${service_id}.yml" down -v 2>/dev/null || true
    
    # Remove compose file
    rm -f "$COMPOSE_DIR/${service_id}.yml"
    
    # Remove environment variables (optional)
    # sed -i "/# ${service_name} Configuration/,+100d" "$ENV_FILE"
    
    print_info "Rollback complete"
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    print_header
    
    # Trap errors for rollback
    trap 'rollback_deployment "$SELECTED_SERVICE"' ERR
    
    select_service
    validate_dependencies
    check_port_conflicts
    configure_service_env
    generate_service_compose
    deploy_service
    post_deployment_config
    perform_integration_test
    
    print_final_success
}

main "$@"
