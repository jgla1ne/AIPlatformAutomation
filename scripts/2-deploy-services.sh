#!/bin/bash
# Script 2: Parameterized Deployment
#
# NOTE: This script runs as root (required for Docker, AppArmor, system setup)
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
    echo -e "${CYAN}║            AI PLATFORM - PARAMETERIZED DEPLOYMENT           ║${NC}"
    echo -e "${CYAN}║              Baseline v1.0.0 - Multi-Stack Ready           ║${NC}"
    echo -e "${CYAN}║           AppArmor + Vector DB + OpenClaw Integration       ║${NC}"
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

# Load configuration from .env
load_configuration() {
    print_header "Loading Configuration"
    
    if [[ -f "${BASE_DIR:-/mnt/data}/config/.env" ]]; then
        source "${BASE_DIR:-/mnt/data}/config/.env"
        print_success "Configuration loaded from ${BASE_DIR}/config/.env"
    else
        print_error "Configuration file not found. Please run Script 1 first."
        exit 1
    fi
}

# Validate configuration
validate_config() {
    print_header "Validating Configuration"
    
    local required_vars=(BASE_DIR STACK_USER_UID DOCKER_NETWORK DOMAIN_NAME)
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            print_error "Required variable $var not set in .env"
            exit 1
        fi
    done
    print_success "Configuration validated"
}

# Create Docker network
create_network() {
    print_header "Creating Docker Network"
    
    docker network create "${DOCKER_NETWORK}" 2>/dev/null || true
    print_success "Docker network created: ${DOCKER_NETWORK}"
}

# AppArmor profile loading (fixed with explicit sed substitution)
load_apparmor_profiles() {
    print_header "Loading AppArmor Profiles"
    
    local profile_dir="${BASE_DIR}/apparmor"

    for profile in default openclaw tailscale; do
        local src="${profile_dir}/${profile}.profile.tmpl"
        local dst="/etc/apparmor.d/${DOCKER_NETWORK}-${profile}"

        # Check if template exists
        if [[ ! -f "$src" ]]; then
            print_error "AppArmor template not found: $src"
            continue
        fi

        # Substitute BASE_DIR into template
        sed "s|BASE_DIR_PLACEHOLDER|${BASE_DIR}|g" "${src}" > "${dst}"

        # Load into kernel
        if apparmor_parser -r "${dst}"; then
            print_success "AppArmor profile loaded: ${DOCKER_NETWORK}-${profile}"
        else
            print_warning "Failed to load AppArmor profile: ${DOCKER_NETWORK}-${profile}"
        fi
    done
}

# Vector DB configuration (global for stack)
set_vectordb_config() {
    print_header "Configuring Vector Database"
    
    case "${VECTOR_DB}" in
        qdrant)
            export VECTORDB_HOST="qdrant"
            export VECTORDB_PORT="6333"
            export VECTORDB_TYPE="qdrant"
            export VECTORDB_URL="http://qdrant:6333"
            export VECTORDB_COLLECTION="ai-platform"
            ;;
        pgvector)
            export VECTORDB_HOST="postgres"
            export VECTORDB_PORT="5432"
            export VECTORDB_TYPE="pgvector"
            export VECTORDB_URL="postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB:-aiplatform}"
            export VECTORDB_COLLECTION="ai-platform"
            ;;
        weaviate)
            export VECTORDB_HOST="weaviate"
            export VECTORDB_PORT="8080"
            export VECTORDB_TYPE="weaviate"
            export VECTORDB_URL="http://weaviate:8080"
            export VECTORDB_COLLECTION="AIPlatform"
            ;;
        chroma)
            export VECTORDB_HOST="chroma"
            export VECTORDB_PORT="8000"
            export VECTORDB_TYPE="chroma"
            export VECTORDB_URL="http://chroma:8000"
            export VECTORDB_COLLECTION="ai-platform"
            ;;
        *)
            print_warning "Unknown vector DB: ${VECTOR_DB}, defaulting to qdrant"
            set_vectordb_config qdrant
            ;;
    esac
    
    print_success "Vector DB configured: ${VECTORDB_TYPE} at ${VECTORDB_URL}"
    
    # Fix Docker Compose file to use proper variable substitution
    sed -i "s/VECTOR_DB: qdrant/VECTOR_DB: \${VECTOR_DB}/g" "$COMPOSE_FILE"
    sed -i "s/VECTOR_DB: milvus/VECTOR_DB: \${VECTOR_DB}/g" "$COMPOSE_FILE"
    sed -i "s/VECTOR_DB: chroma/VECTOR_DB: \${VECTOR_DB}/g" "$COMPOSE_FILE"
    sed -i "s/VECTOR_DB: weaviate/VECTOR_DB: \${VECTOR_DB}/g" "$COMPOSE_FILE"
}

# Build vector DB environment variables
build_vectordb_env() {
    local vectordb_env=()
    
    case "${VECTOR_DB}" in
        qdrant)
            vectordb_env=(
                "-e" "VECTOR_DB=qdrant"
                "-e" "QDRANT_ENDPOINT=${VECTORDB_URL}"
                "-e" "QDRANT_API_KEY="
                "-e" "QDRANT_COLLECTION=${VECTORDB_COLLECTION}"
            )
            ;;
        pgvector)
            vectordb_env=(
                "-e" "VECTOR_DB=pgvector"
                "-e" "PGVECTOR_CONNECTION_STRING=${VECTORDB_URL}"
                "-e" "PGVECTOR_SCHEMA=ai_platform"
            )
            ;;
        weaviate)
            vectordb_env=(
                "-e" "VECTOR_DB=weaviate"
                "-e" "WEAVIATE_ENDPOINT=${VECTORDB_URL}"
                "-e" "WEAVIATE_API_KEY="
                "-e" "WEAVIATE_CLASS=${VECTORDB_COLLECTION}"
            )
            ;;
        chroma)
            vectordb_env=(
                "-e" "VECTOR_DB=chroma"
                "-e" "CHROMA_ENDPOINT=${VECTORDB_URL}"
                "-e" "CHROMA_COLLECTION=${VECTORDB_COLLECTION}"
            )
            ;;
        *)
            print_warning "Unknown vector DB: ${VECTOR_DB}, defaulting to qdrant"
            set_vectordb_config qdrant
            ;;
    esac
    
    # Set the return array
    set -- "${vectordb_env[@]}"
}

# Generic service deployment function
deploy_service() {
    local service_name=$1
    local image=$2
    local internal_port=$3
    local host_port=$4
    shift 4
    local extra_env=("$@")
    
    print_info "Deploying ${service_name}..."
    
    # Create service directories
    mkdir -p "${BASE_DIR}/data/${service_name}" "${BASE_DIR}/logs/${service_name}"
    chown -R ${STACK_USER_UID}:${STACK_USER_GID} "${BASE_DIR}/data/${service_name}"
    chown -R ${STACK_USER_UID}:${STACK_USER_GID} "${BASE_DIR}/logs/${service_name}"
    
    # Get vector DB environment variables
    build_vectordb_env
    local vectordb_env=("$@")
    
    docker run -d \
        --name "${service_name}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${STACK_USER_UID}:${STACK_USER_GID}" \
        -p "${host_port}:${internal_port}" \
        -v "${BASE_DIR}/data/${service_name}:/app/data" \
        -v "${BASE_DIR}/logs/${service_name}:/app/logs" \
        "${vectordb_env[@]}" \
        "${extra_env[@]}" \
        "${image}"
    
    print_success "${service_name} deployed on port ${host_port}"
}

# Wait for Tailscale authentication
wait_for_tailscale_auth() {
    local container_name=$1
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    print_info "Waiting for Tailscale authentication..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        if docker exec "$container_name" tailscale status 2>/dev/null | grep -q "Logged in"; then
            print_success "Tailscale authenticated"
            return 0
        fi
        
        sleep 5
        wait_time=$((wait_time + 5))
        echo -n "."
    done
    
    print_error "Tailscale authentication timed out"
    return 1
}

# Deploy OpenClaw with Tailscale sidecar
deploy_openclaw() {
    print_header "Deploying OpenClaw + Tailscale"
    
    if [ -z "${TAILSCALE_AUTH_KEY}" ]; then
        print_warning "TAILSCALE_AUTH_KEY missing - OpenClaw will run without Tailscale"
        deploy_openclaw_standalone
        return
    fi

    # Create OpenClaw directories
    mkdir -p "${BASE_DIR}/data/openclaw" "${BASE_DIR}/data/tailscale"
    chown -R ${OPENCLAW_UID}:${OPENCLAW_GID} "${BASE_DIR}/data/openclaw"
    chown -R ${OPENCLAW_UID}:${OPENCLAW_GID} "${BASE_DIR}/data/tailscale"

    # Step 1: Tailscale sidecar
    print_info "Deploying Tailscale sidecar..."
    docker run -d \
        --name "tailscale" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --cap-add NET_ADMIN \
        --cap-add SYS_MODULE \
        --security-opt "apparmor=${APPARMOR_TAILSCALE}" \
        --user "${OPENCLAW_UID}:${OPENCLAW_GID}" \
        -v "${BASE_DIR}/data/tailscale:/var/lib/tailscale" \
        -v /dev/net/tun:/dev/net/tun \
        -e "TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}" \
        -e "TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME}" \
        tailscale/tailscale:latest

    # Wait for Tailscale authentication
    wait_for_tailscale_auth "tailscale"

    # Step 2: OpenClaw in shared network namespace
    print_info "Deploying OpenClaw..."
    local vectordb_env=($(build_vectordb_env))
    
    docker run -d \
        --name "openclaw" \
        --network "container:tailscale" \
        --restart unless-stopped \
        --user "${OPENCLAW_UID}:${OPENCLAW_GID}" \
        --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=100m \
        -v "${BASE_DIR}/data/openclaw:/app/data:rw" \
        -v "${BASE_DIR}/config/openclaw:/app/config:ro" \
        ${vectordb_env[@]} \
        alpine/openclaw:latest

    print_success "OpenClaw deployed with Tailscale sidecar"
}

# Deploy OpenClaw standalone (without Tailscale)
deploy_openclaw_standalone() {
    print_info "Deploying OpenClaw (standalone mode)..."
    
    # Create OpenClaw directories
    mkdir -p "${BASE_DIR}/data/openclaw"
    chown -R ${OPENCLAW_UID}:${OPENCLAW_GID} "${BASE_DIR}/data/openclaw"
    
    local vectordb_env=($(build_vectordb_env))
    
    docker run -d \
        --name "openclaw" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${OPENCLAW_UID}:${OPENCLAW_GID}" \
        -p "${OPENCLAW_PORT}:8080" \
        -v "${BASE_DIR}/data/openclaw:/app/data:rw" \
        -v "${BASE_DIR}/config/openclaw:/app/config:ro" \
        ${vectordb_env[@]} \
        alpine/openclaw:latest

    print_success "OpenClaw deployed (standalone) on port ${OPENCLAW_PORT}"
}

# Deploy infrastructure services
deploy_infrastructure() {
    print_header "Deploying Infrastructure Services"
    
    # PostgreSQL (if using pgvector or as general database)
    deploy_service "postgres" "postgres:15" "5432" "5432" \
        "-e POSTGRES_DB=${POSTGRES_DB:-aiplatform}" \
        "-e POSTGRES_USER=${POSTGRES_USER:-postgres}" \
        "-e POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-password}"
    
    # Redis (for caching)
    deploy_service "redis" "redis:7-alpine" "6379" "6379"
    
    # Vector Database
    case "${VECTOR_DB}" in
        qdrant)
            deploy_service "qdrant" "qdrant/qdrant:latest" "6333" "6333"
            ;;
        weaviate)
            deploy_service "weaviate" "semitechnologies/weaviate:latest" "8080" "8080"
            ;;
        chroma)
            deploy_service "chroma" "chromadb/chroma:latest" "8000" "8000"
            ;;
        # pgvector uses postgres, already deployed
    esac
    
    # Ollama (for LLM services)
    deploy_service "ollama" "ollama/ollama:latest" "11434" "11434"
}

# Deploy AI services
deploy_ai_services() {
    print_header "Deploying AI Services"
    
    # n8n
    deploy_service "n8n" "n8nio/n8n:latest" "5678" "${N8N_PORT}" \
        "-e N8N_BASIC_AUTH_ACTIVE=true" \
        "-e N8N_BASIC_AUTH_USER=admin" \
        "-e N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD:-password}"
    
    # AnythingLLM
    deploy_service "anythingllm" "mintplexlabs/anythingllm:latest" "3001" "${ANYTHINGLLM_PORT}" \
        "-e STORAGE_DIR=/app/server/storage" \
        "-e JWT_SECRET=${JWT_SECRET:-your-secret-key}" \
        "-e LLM_PROVIDER=ollama" \
        "-e OLLAMA_BASE_PATH=http://ollama:11434" \
        "-e EMBEDDING_ENGINE=ollama" \
        "-e EMBEDDING_BASE_PATH=http://ollama:11434"
    
    # LiteLLM
    deploy_service "litellm" "ghcr.io/berriai/litellm:main-latest" "4000" "${LITELLM_PORT}" \
        "-e LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY:-your-master-key}" \
        "-e LITELLM_SALT_KEY=${LITELLM_SALT_KEY:-your-salt-key}"
    
    # OpenWebUI
    deploy_service "openwebui" "ghcr.io/open-webui/open-webui:main" "8080" "${OPENWEBUI_PORT}" \
        "-e OLLAMA_BASE_URL=http://ollama:11434" \
        "-e WEBUI_AUTH=true" \
        "-e WEBUI_SECRET_KEY=${JWT_SECRET:-your-secret-key}"
    
    # MinIO (S3-compatible storage)
    deploy_service "minio" "minio/minio:latest" "9000" "${MINIO_S3_PORT}" \
        "-e MINIO_ROOT_USER=${MINIO_ROOT_USER:-minioadmin}" \
        "-e MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-minioadmin}"
    
    # Deploy MinIO console separately
    deploy_service "minio-console" "minio/minio:latest" "9001" "${MINIO_CONSOLE_PORT}" \
        "-e MINIO_ROOT_USER=${MINIO_ROOT_USER:-minioadmin}" \
        "-e MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-minioadmin}"
}

# Deploy Caddy reverse proxy
deploy_caddy() {
    print_header "Deploying Caddy Reverse Proxy"
    
    # Create Caddyfile
    mkdir -p "${BASE_DIR}/caddy"
    cat > "${BASE_DIR}/caddy/Caddyfile" << EOF
{
    admin off
    auto_https off
}

:80 {
    # N8N (with websockets)
    handle_path /n8n/* {
        reverse_proxy n8n:5678 {
            header_up Upgrade {http.request.header.Upgrade}
            header_up Connection {http.request.header.Connection}
        }
    }

    # OpenWebUI (with websockets)
    handle_path /openwebui/* {
        reverse_proxy openwebui:8080 {
            header_up Upgrade {http.request.header.Upgrade}
            header_up Connection {http.request.header.Connection}
        }
    }

    # AnythingLLM (with websockets)
    handle_path /anythingllm/* {
        reverse_proxy anythingllm:3001 {
            header_up Upgrade {http.request.header.Upgrade}
            header_up Connection {http.request.header.Connection}
        }
    }

    # LiteLLM
    handle_path /litellm/* {
        reverse_proxy litellm:4000
    }

    # OpenClaw (if standalone)
    handle_path /openclaw/* {
        reverse_proxy openclaw:8080
    }

    # MinIO Console
    handle_path /minio/* {
        reverse_proxy minio-console:9001
    }

    # Health check
    handle /health {
        respond "OK" 200
    }

    # Fallback
    respond "AI Platform - use /servicename to access services" 200
}
EOF

    # Deploy Caddy
    docker run -d \
        --name "caddy" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${STACK_USER_UID}:${STACK_USER_GID}" \
        -p "80:80" \
        -p "443:443" \
        -v "${BASE_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
        -v "${BASE_DIR}/ssl:/etc/ssl:ro" \
        caddy:2-alpine

    print_success "Caddy deployed with reverse proxy configuration"
}

# Validate deployment
validate_deployment() {
    print_header "Validating Deployment"
    
    local services=(postgres redis qdrant ollama n8n anythingllm litellm openwebui minio caddy)
    local failed_services=()
    
    for service in "${services[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${service}$"; then
            print_success "${service} is running"
        else
            print_warning "${service} is not running"
            failed_services+=("$service")
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        print_warning "Some services failed to start: ${failed_services[*]}"
        print_info "Check logs with: docker logs <service_name>"
    else
        print_success "All services deployed successfully!"
    fi
}

# Display deployment summary
display_summary() {
    print_header "Deployment Summary"
    
    echo "📊 Stack Information:"
    echo "   Base Directory: ${BASE_DIR}"
    echo "   Network: ${DOCKER_NETWORK}"
    echo "   Domain: ${DOMAIN_NAME}"
    echo ""
    echo "🔧 Service URLs:"
    echo "   n8n: http://${LOCALHOST}:${N8N_PORT}/n8n/"
    echo "   AnythingLLM: http://${LOCALHOST}:${ANYTHINGLLM_PORT}/anythingllm/"
    echo "   LiteLLM: http://${LOCALHOST}:${LITELLM_PORT}/litellm/"
    echo "   OpenWebUI: http://${LOCALHOST}:${OPENWEBUI_PORT}/openwebui/"
    echo "   MinIO: http://${LOCALHOST}:${MINIO_CONSOLE_PORT}/minio/"
    echo "   Health Check: http://${LOCALHOST}/health"
    echo ""
    echo "📋 Next Steps:"
    echo "   1. Configure services with: bash 3-configure-services.sh"
    echo "   2. Add more services with: bash 4-add-service.sh"
    echo ""
    print_success "Deployment complete!"
}

# Main function
main() {
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    print_banner
    
    # Execute deployment phases
    load_configuration
    validate_config
    create_network
    load_apparmor_profiles
    set_vectordb_config
    
    # Deploy services
    deploy_infrastructure
    deploy_ai_services
    deploy_openclaw
    deploy_caddy
    
    # Validate and summarize
    validate_deployment
    display_summary
}

# Run main function
main "$@"
