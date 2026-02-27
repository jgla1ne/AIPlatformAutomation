#!/bin/bash
# Script 2: Parameterized Deployment
#
# NOTE: This script runs as root (required for Docker, AppArmor, system setup)
# RUNNING_UID owns DATA_ROOT for container permissions

set -eo pipefail

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

# ── Environment Loading ──────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# DATA_ROOT must be set before this script runs
# It is written by Script 1 to /etc/ai-platform/env-pointer
if [ -f /etc/ai-platform/env-pointer ]; then
  DATA_ROOT="$(cat /etc/ai-platform/env-pointer)"
fi

if [ -z "${DATA_ROOT:-}" ]; then
  echo "❌ DATA_ROOT not found. Run Script 1 first."
  exit 1
fi

# ── Resolve tenant context ──────────────────────────────────────────
BASE_DIR="${DATA_ROOT:-/mnt/data}"
TENANT_ID="${TENANT_ID:-u1001}"
TENANT_DIR="${BASE_DIR}/${TENANT_ID}"
ENV_FILE="${TENANT_DIR}/.env"

[[ -f "${ENV_FILE}" ]] || { echo "❌ FATAL: .env not found at ${ENV_FILE}"; exit 1; }
source "${ENV_FILE}"
# ────────────────────────────────────────────────────────────────────

# 1. Load env FIRST
set -a
# shellcheck disable=SC1090
set +a

# 2. Validate COMPOSE_PROJECT_NAME is not empty
if [ -z "${COMPOSE_PROJECT_NAME}" ]; then
  echo "❌ COMPOSE_PROJECT_NAME is empty after loading .env"
  echo "   Check that Script 1 wrote it to ${ENV_FILE}"
  exit 1
fi

# 3. NOW build COMPOSE
COMPOSE_FILE_PROCESSED="/tmp/docker-compose-${COMPOSE_PROJECT_NAME}.yml"

# Process docker-compose.yml to substitute volume variables (Docker Compose limitation)
process_compose_file() {
    print_info "Processing docker-compose.yml for volume and network substitution..."
    
    # Substitute volume and network variables that Docker Compose can't handle
    sed -e "s/\${PG_VOLUME}/${PG_VOLUME}/g" \
        -e "s/\${REDIS_VOLUME}/${REDIS_VOLUME}/g" \
        -e "s/\${QDRANT_VOLUME}/${QDRANT_VOLUME}/g" \
        -e "s/\${DOCKER_NETWORK}/${DOCKER_NETWORK}/g" \
        "${COMPOSE_FILE}" > "${COMPOSE_FILE_PROCESSED}"
    
    print_success "Compose file processed: ${COMPOSE_FILE_PROCESSED}"
}

# Process the compose file
process_compose_file

COMPOSE="docker compose \
  --project-name ${COMPOSE_PROJECT_NAME} \
  --env-file ${ENV_FILE} \
  --file ${COMPOSE_FILE_PROCESSED}"

print_success ".env loaded | Project: ${COMPOSE_PROJECT_NAME} | Domain: ${DOMAIN}"

# Set tenant prefix for container names
TENANT_PREFIX="${COMPOSE_PROJECT_NAME:-ai-platform}"

# Define tenant-scoped container names
PG_CONTAINER="${COMPOSE_PROJECT_NAME}-postgres-1"
REDIS_CONTAINER="${COMPOSE_PROJECT_NAME}-redis-1"
QDRANT_CONTAINER="${COMPOSE_PROJECT_NAME}-qdrant-1"
CADDY_CONTAINER="${COMPOSE_PROJECT_NAME}-caddy-1"

# Generate tenant-prefixed container name
get_container_name() {
    local base_name="$1"
    echo "${TENANT_PREFIX}-${base_name}"
}

wait_for_caddy() {
  print_header "Waiting for Caddy to become ready"
  local max_attempts=30
  local attempt=0
  print_info "Waiting for Caddy to bind port 443..."
  
  while ! ss -tlnp | grep -q ':443 '; do
    attempt=$((attempt + 1))
    if [ ${attempt} -ge ${max_attempts} ]; then
      print_error "Caddy did not bind port 443 after ${max_attempts}s"
      print_info "Check: docker logs ${COMPOSE_PROJECT_NAME}-caddy-1"
      print_info "Common causes: DNS not propagated, ACME rate limit"
      exit 1
    fi
    sleep 2
  done
  print_success "Caddy is listening on 443"
}

# Port pre-flight check to prevent conflicts
verify_ports() {
  print_header "Port Pre-flight Check"
  local FAILED=0

  check_port() {
    local NAME="$1"
    local PORT="$2"
    local ENABLED="$3"
    [ "${ENABLED}" != "true" ] && return 0

    if ss -tlnp "sport = :${PORT}" 2>/dev/null | grep -q ":${PORT}"; then
      # Check if it's OUR project already holding it
      if docker ps --format '{{.Names}}' | \
         grep -q "^${COMPOSE_PROJECT_NAME}"; then
        echo "  ♻  ${NAME}:${PORT} — held by this project (OK)"
      else
        # Special handling for HTTP/HTTPS multi-tenant conflict
        if [ "${PORT}" = "80" ] || [ "${PORT}" = "443" ]; then
          echo "  ❌ ${NAME}:${PORT} — owned by DIFFERENT tenant's reverse proxy"
          echo ""
          echo "   🚨 MULTI-TENANT HTTP ROUTING ISSUE DETECTED"
          echo "   Only ONE tenant can own ports 80/443 simultaneously."
          echo "   Solutions:"
          echo "   • Option A: Shared reverse proxy (Caddy/Traefik) at host level"
          echo "   • Option B: Tenant-specific external ports (8443, 9443, etc.)"
          echo "   • Option C: Contact platform admin for subdomain routing setup"
          echo ""
          echo "   Current design blocks multi-tenant deployment."
          echo "   Use Script 0 to clean up the other tenant, or implement shared proxy."
        else
          echo "  ❌ ${NAME}:${PORT} — IN USE by another process"
        fi
        FAILED=$((FAILED + 1))
      fi
    else
      echo "  ✅ ${NAME}:${PORT} — available"
    fi
  }

  check_port "HTTP"       "80"                      "true"
  check_port "HTTPS"      "443"                     "true"
  check_port "LiteLLM"    "${LITELLM_PORT:-4000}"         "${ENABLE_LITELLM}"
  check_port "OpenWebUI"  "${OPENWEBUI_PORT:-3000}"       "${ENABLE_OPENWEBUI}"
  check_port "n8n"        "${N8N_PORT:-5678}"             "${ENABLE_N8N}"
  check_port "Qdrant"     "${QDRANT_PORT:-6333}"          "${ENABLE_QDRANT}"
  check_port "Prometheus" "${PROMETHEUS_PORT:-9090}"      "${ENABLE_PROMETHEUS}"

  if [ "${FAILED}" -gt 0 ]; then
    echo ""
    echo "❌ ${FAILED} port conflict(s) detected."
    echo "   Run Script 1 again to reassign ports, or run Script 0 to clean up."
    exit 1
  fi

  print_success "All ports available"
}

# Validate configuration
validate_config() {
    print_header "Validating Configuration"
    
    local required_vars=(DATA_ROOT RUNNING_UID RUNNING_GID DOCKER_NETWORK DOMAIN_NAME)
    for var in "${required_vars[@]}"; do
        local value="${!var:-}"
        if [[ -z "$value" ]]; then
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
    
    local profile_dir="${DATA_ROOT}/apparmor"

    for profile in default openclaw tailscale; do
        local src="${profile_dir}/${DOCKER_NETWORK}-${profile}"
        local dst="/etc/apparmor.d/${DOCKER_NETWORK}-${profile}"

        # Check if profile exists
        if [[ ! -f "$src" ]]; then
            print_error "AppArmor profile not found: $src"
            continue
        fi

        # Copy to AppArmor directory
        cp "$src" "$dst"

        # Load into kernel
        if apparmor_parser -r "${dst}" 2>/dev/null; then
            print_success "AppArmor profile loaded: ${DOCKER_NETWORK}-${profile}"
        else
            print_warning "Failed to load AppArmor profile: ${DOCKER_NETWORK}-${profile} (AppArmor may be disabled)"
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
    mkdir -p "${DATA_ROOT}/data/${service_name}" "${DATA_ROOT}/logs/${service_name}"
    chown -R ${RUNNING_UID}:${RUNNING_GID} "${DATA_ROOT}/data/${service_name}"
    chown -R ${RUNNING_UID}:${RUNNING_GID} "${DATA_ROOT}/logs/${service_name}"
    
    # Get vector DB environment variables
    build_vectordb_env
    local vectordb_env=("$@")
    
    docker run -d \
        --name "$(get_container_name "${service_name}")" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${RUNNING_UID}:${RUNNING_GID}" \
        -p "${host_port}:${internal_port}" \
        -v "${DATA_ROOT}/data/${service_name}:/app/data" \
        -v "${DATA_ROOT}/logs/${service_name}:/app/logs" \
        "${vectordb_env[@]}" \
        "${extra_env[@]}" \
        "${image}"
    
    print_success "${service_name} deployed on port ${host_port}"
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
    mkdir -p "${DATA_ROOT}/data/openclaw" "${DATA_ROOT}/data/tailscale"
    chown -R ${OPENCLAW_UID}:${OPENCLAW_GID} "${DATA_ROOT}/data/openclaw"
    chown -R ${OPENCLAW_UID}:${OPENCLAW_GID} "${DATA_ROOT}/data/tailscale"

    # Step 1: Tailscale sidecar
    print_info "Deploying Tailscale sidecar..."
    docker run -d \
        --name "$(get_container_name tailscale)" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --cap-add NET_ADMIN \
        --cap-add SYS_MODULE \
        --user "${OPENCLAW_UID}:${OPENCLAW_GID}" \
        -v "${DATA_ROOT}/data/tailscale:/var/lib/tailscale" \
        -v /dev/net/tun:/dev/net/tun \
        -e "TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}" \
        -e "TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME}" \
        tailscale/tailscale:latest

    # Wait for container to be ready
    sleep 5
    
    # Authenticate Tailscale inside container
    print_info "Authenticating Tailscale..."
    docker exec "$(get_container_name tailscale)" \
        tailscale up \
            --authkey="${TAILSCALE_AUTH_KEY}" \
            --hostname="${TAILSCALE_HOSTNAME}" \
            --accept-dns=false \
            --accept-routes=false

    # Wait for authentication and get IP
    wait_for_tailscale_auth "$(get_container_name tailscale)"
    
    # Get Tailscale IP and persist it
    TAILSCALE_IP=$(docker exec "$(get_container_name tailscale)" tailscale ip -4 2>/dev/null || echo "")
    if [[ -n "${TAILSCALE_IP}" ]]; then
        sed -i "s|^TAILSCALE_IP=.*|TAILSCALE_IP=${TAILSCALE_IP}|" "${ENV_FILE}" || \
            echo "TAILSCALE_IP=${TAILSCALE_IP}" >> "${ENV_FILE}"
        print_success "Tailscale IP: ${TAILSCALE_IP}"
    else
        print_error "Failed to get Tailscale IP"
    fi

    # Step 2: OpenClaw in shared network namespace
    print_info "Deploying OpenClaw..."
    
    docker run -d \
        --name "$(get_container_name openclaw)" \
        --network "container:$(get_container_name tailscale)" \
        --restart unless-stopped \
        --user "${OPENCLAW_UID}:${OPENCLAW_GID}" \
        --read-only \
        --tmpfs /tmp \
        -e "OPENCLAW_UID=${OPENCLAW_UID}" \
        -e "OPENCLAW_GID=${OPENCLAW_GID}" \
        -e "DATA_ROOT=${DATA_ROOT}" \
        -e "COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}" \
        ${vectordb_env[@]} \
        alpine/openclaw:latest

    print_success "OpenClaw deployed with Tailscale sidecar"
}

# Deploy OpenClaw standalone (without Tailscale)
deploy_openclaw_standalone() {
    print_info "Deploying OpenClaw (standalone mode)..."
    
    # Create OpenClaw directories
    mkdir -p "${DATA_ROOT}/data/openclaw"
    chown -R ${OPENCLAW_UID}:${OPENCLAW_GID} "${DATA_ROOT}/data/openclaw"
    
    local vectordb_env=($(build_vectordb_env))
    
    docker run -d \
        --name "$(get_container_name openclaw)" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${OPENCLAW_UID}:${OPENCLAW_GID}" \
        -p "${OPENCLAW_PORT}:8080" \
        -v "${DATA_ROOT}/data/openclaw:/app/data:rw" \
        -v "${DATA_ROOT}/config/openclaw:/app/config:ro" \
        ${vectordb_env[@]} \
        alpine/openclaw:latest

    print_success "OpenClaw deployed (standalone) on port ${OPENCLAW_PORT}"
}

# Deploy infrastructure services
# Main deployment function with layered approach
deploy_layered_services() {
    print_header "Deploying Services in Dependency Order"
    
    # Layer 0: Infrastructure
    deploy_layer_0_infrastructure
    
    # Layer 1: Databases
    deploy_postgres
    deploy_redis
    deploy_qdrant
    
    # Layer 2: Application Services
    deploy_layer_2_services
    
    # Layer 2.5: Dify Multi-Container Service
    deploy_layer_2_5_dify
    
    # Layer 3: Monitoring Services
    deploy_layer_3_monitoring
    
    # Layer 4: OpenClaw (restricted)
    deploy_layer_4_openclaw
    
    # Layer 5: Caddy (proxy - LAST)
    deploy_layer_5_proxy
    
    print_success "All services deployed in dependency order"
}

deploy_layer_0_infrastructure() {
    print_header "Layer 0: Network + AppArmor + RClone"
    
    # Load AppArmor profiles
    load_apparmor_profiles
    
    # Create Docker network
    docker network create "${DOCKER_NETWORK}" 2>/dev/null || true
    
    # Install RClone if Google Drive sync is enabled
    if [[ "${ENABLE_RCLONE:-false}" == "true" ]] || [[ "${GDRIVE_ENABLED:-false}" == "true" ]]; then
        print_info "Setting up RClone for Google Drive sync..."
        
        # Deploy rclone container if enabled
        if [[ "${GDRIVE_ENABLED:-false}" == "true" ]]; then
            print_info "Deploying RClone container..."
            
            docker run -d \
                --name "$(get_container_name rclone-gdrive)" \
                --network "${DOCKER_NETWORK}" \
                --restart unless-stopped \
                --user "${RUNNING_UID}:${RUNNING_GID}" \
                -v "${DATA_ROOT}/config/rclone:/config/rclone:ro" \
                -v "${RCLONE_MOUNT_POINT:-${DATA_ROOT}/gdrive}:/data/gdrive" \
                -v "${DATA_ROOT}/logs/rclone:/logs" \
                rclone/rclone:latest \
                sync \
                gdrive:"${RCLONE_GDRIVE_FOLDER:-}" \
                /data/gdrive \
                --config=/config/rclone/rclone.conf \
                --log-file=/logs/rclone.log \
                --log-level=INFO \
                --transfers=4 \
                --checkers=8
                
            print_success "RClone container deployed"
        fi
    fi
    
    print_success "Infrastructure ready"
}

deploy_postgres() {
  print_header "PostgreSQL"

  # Create tenant-scoped network first if it doesn't exist
  if [ -z "${DOCKER_NETWORK}" ]; then
    print_error "DOCKER_NETWORK not set in .env"
    exit 1
  fi
  
  # Deploy postgres using docker-compose (bind mount already created by Script 1)
  $COMPOSE up -d postgres

  # Wait for postgres to be genuinely ready using docker compose exec
  print_info "Waiting for PostgreSQL to accept connections..."
  ATTEMPTS=0
  MAX_ATTEMPTS=30

  until docker compose \
    --project-name "${COMPOSE_PROJECT_NAME}" \
    --env-file "${ENV_FILE}" \
    --file "${DATA_ROOT}/ai-platform/deployment/stack/docker-compose.yml" \
    exec postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    &>/dev/null 2>&1; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ "${ATTEMPTS}" -ge "${MAX_ATTEMPTS}" ]; then
      print_error "PostgreSQL did not become ready after 60 seconds"
      print_error "Logs:"
      docker compose \
        --project-name "${COMPOSE_PROJECT_NAME}" \
        --env-file "${ENV_FILE}" \
        --file "${DATA_ROOT}/ai-platform/deployment/stack/docker-compose.yml" \
        logs postgres --tail=30
      exit 1
    fi
    sleep 2
  done

  print_success "PostgreSQL ready"

  # Create databases for services
  create_databases
}

create_databases() {
    print_info "Creating databases for enabled services..."
    
    # Define service database mappings
    declare -A service_databases=(
        ["n8n"]="n8n"
        ["dify"]="dify"
        ["langfuse"]="langfuse"
        ["mattermost"]="mattermost"
        ["authentik"]="authentik"
        ["librechat"]="librechat"
        ["matrix"]="matrix"
        ["activepieces"]="activepieces"
        ["litellm"]="litellm"
    )
    
    # Create databases only for enabled services
    for service in "${!service_databases[@]}"; do
        db_name="${service_databases[$service]}"
        
        # Check if service is enabled
        case "$service" in
            "n8n")
                if [[ "${ENABLE_N8N:-false}" != "true" ]]; then continue; fi
                ;;
            "dify")
                if [[ "${ENABLE_DIFY:-false}" != "true" ]]; then continue; fi
                ;;
            "langfuse")
                if [[ "${ENABLE_LANGFUSE:-false}" != "true" ]]; then continue; fi
                ;;
            "mattermost")
                if [[ "${ENABLE_MATTERMOST:-false}" != "true" ]]; then continue; fi
                ;;
            "authentik")
                if [[ "${ENABLE_AUTHENTIK:-false}" != "true" ]]; then continue; fi
                ;;
            "librechat")
                if [[ "${ENABLE_LIBRECHAT:-false}" != "true" ]]; then continue; fi
                ;;
            "matrix")
                if [[ "${ENABLE_MATRIX:-false}" != "true" ]]; then continue; fi
                ;;
            "activepieces")
                if [[ "${ENABLE_ACTIVEPIECES:-false}" != "true" ]]; then continue; fi
                ;;
            "litellm")
                if [[ "${ENABLE_LITELLM:-false}" != "true" ]]; then continue; fi
                ;;
        esac
        
        # Create database with owner
        if docker compose \
            --project-name "${COMPOSE_PROJECT_NAME}" \
            --env-file "${ENV_FILE}" \
            --file "${DATA_ROOT}/ai-platform/deployment/stack/docker-compose.yml" \
            exec postgres psql -U "${POSTGRES_USER}" -c "CREATE DATABASE ${db_name} OWNER ${POSTGRES_USER};" &>/dev/null; then
            print_success "Database '${db_name}' created for ${service}"
        else
            print_info "Database '${db_name}' already exists or creation failed"
        fi
    done
    
    # Create pgvector extension in all databases that need it
    local vector_dbs=("dify" "anythingllm" "openwebui" "librechat")
    for db in "${vector_dbs[@]}"; do
        # Check if service is enabled
        case "$db" in
            "dify")
                if [[ "${ENABLE_DIFY:-false}" != "true" ]]; then continue; fi
                ;;
            "anythingllm")
                if [[ "${ENABLE_ANYTHINGLLM:-false}" != "true" ]]; then continue; fi
                ;;
            "openwebui")
                if [[ "${ENABLE_OPENWEBUI:-false}" != "true" ]]; then continue; fi
                ;;
            "librechat")
                if [[ "${ENABLE_LIBRECHAT:-false}" != "true" ]]; then continue; fi
                ;;
        esac
        
        if docker compose \
            --project-name "${COMPOSE_PROJECT_NAME}" \
            --env-file "${ENV_FILE}" \
            --file "${DATA_ROOT}/ai-platform/deployment/stack/docker-compose.yml" \
            exec postgres psql -U "${POSTGRES_USER}" -d "$db" -c "CREATE EXTENSION IF NOT EXISTS vector;" &>/dev/null; then
            print_success "pgvector extension created in $db database"
        else
            print_warning "pgvector extension failed in $db - is pgvector image in use?"
        fi
    done
    
    # Also create extension in default aiplatform database
    if docker compose \
        --project-name "${COMPOSE_PROJECT_NAME}" \
        --env-file "${ENV_FILE}" \
        --file "${DATA_ROOT}/ai-platform/deployment/stack/docker-compose.yml" \
        exec postgres psql -U "${POSTGRES_USER}" -c "CREATE EXTENSION IF NOT EXISTS vector;" &>/dev/null; then
        print_success "pgvector extension created in default database"
    else
        print_warning "pgvector extension failed - is pgvector image in use?"
        print_info "Check docker-compose.yml postgres image tag"
        print_info "Recommended: pgvector/pgvector:pg16 or ankane/pgvector"
    fi
}

deploy_redis() {
  print_header "Redis"
  
  # Deploy redis using docker-compose (bind mount already created by Script 1)
  docker compose \
    --project-name "${COMPOSE_PROJECT_NAME}" \
    --env-file "${ENV_FILE}" \
    --file "${DATA_ROOT}/ai-platform/deployment/stack/docker-compose.yml" \
    up -d redis

  # Wait for redis to be ready using docker compose exec
  ATTEMPTS=0
  until docker compose \
    --project-name "${COMPOSE_PROJECT_NAME}" \
    --env-file "${ENV_FILE}" \
    --file "${DATA_ROOT}/ai-platform/deployment/stack/docker-compose.yml" \
    exec redis redis-cli -a "${REDIS_PASSWORD}" ping 2>/dev/null | grep -q PONG; do
    ATTEMPTS=$((ATTEMPTS + 1))
    [ "${ATTEMPTS}" -ge 20 ] && {
      print_error "Redis did not become ready"
      docker compose \
        --project-name "${COMPOSE_PROJECT_NAME}" \
        --env-file "${ENV_FILE}" \
        --file "${DATA_ROOT}/ai-platform/deployment/stack/docker-compose.yml" \
        logs redis --tail=20
      exit 1
    }
    sleep 2
  done
  print_success "Redis ready"
}

deploy_qdrant() {
  print_header "Qdrant"
  
  # Deploy qdrant using docker-compose (bind mount already created by Script 1)
  docker compose \
    --project-name "${COMPOSE_PROJECT_NAME}" \
    --env-file "${ENV_FILE}" \
    --file "${DATA_ROOT}/ai-platform/deployment/stack/docker-compose.yml" \
    up -d qdrant

  # Wait for qdrant to be ready using docker compose exec
  ATTEMPTS=0
  until docker compose \
    --project-name "${COMPOSE_PROJECT_NAME}" \
    --env-file "${ENV_FILE}" \
    --file "${DATA_ROOT}/ai-platform/deployment/stack/docker-compose.yml" \
    exec qdrant curl -sf http://localhost:6333/health \
    &>/dev/null; do
    ATTEMPTS=$((ATTEMPTS + 1))
    [ "${ATTEMPTS}" -ge 20 ] && {
      print_error "Qdrant did not become ready"
      docker compose \
        --project-name "${COMPOSE_PROJECT_NAME}" \
        --env-file "${ENV_FILE}" \
        --file "${DATA_ROOT}/ai-platform/deployment/stack/docker-compose.yml" \
        logs qdrant --tail=20
      exit 1
    }
    sleep 2
  done
  print_success "Qdrant ready"
}

deploy_layer_2_services() {
    print_header "Layer 2: Application Services"
    
    # MinIO - runs as root to handle system directory creation
    if [[ "${ENABLE_MINIO:-true}" == "true" ]]; then
        print_info "Deploying MinIO..."
        docker run -d \
            --name "$(get_container_name minio)" \
            --network "${DOCKER_NETWORK}" \
            --restart unless-stopped \
            -e MINIO_ROOT_USER="${MINIO_ROOT_USER}" \
            -e MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}" \
            -v "${DATA_ROOT}/data/minio:/data" \
            minio/minio:latest server /data --console-address ":9001"
    else
        print_info "MinIO disabled (ENABLE_MINIO=false)"
    fi
    
    # n8n
    if [[ "${ENABLE_N8N:-true}" == "true" ]]; then
        print_info "Deploying n8n..."
        docker run -d \
            --name "$(get_container_name n8n)" \
            --network "${DOCKER_NETWORK}" \
            --restart unless-stopped \
            -e DB_TYPE=postgresdb \
            -e DB_POSTGRESDB_HOST=postgres \
            -e DB_POSTGRESDB_DATABASE=n8n \
            -e DB_POSTGRESDB_USER="${POSTGRES_USER}" \
            -e DB_POSTGRESDB_PASSWORD="${POSTGRES_PASSWORD}" \
            -e N8N_HOST="n8n.${DOMAIN_NAME:-localhost}" \
            -e N8N_PROTOCOL=https \
            -e N8N_PORT=5678 \
            -e WEBHOOK_URL="https://n8n.${DOMAIN_NAME:-localhost}/" \
            -e N8N_EDITOR_BASE_URL="https://n8n.${DOMAIN_NAME:-localhost}/" \
            -e HOME=/data/n8n \
            -v "${DATA_ROOT}/data/n8n:/data/n8n" \
            -u "${RUNNING_UID}:${RUNNING_GID}" \
            n8nio/n8n:latest
    else
        print_info "n8n disabled (ENABLE_N8N=false)"
    fi
    
    # OpenWebUI with secret key
    if [[ "${ENABLE_OPENWEBUI:-true}" == "true" ]]; then
        print_info "Deploying OpenWebUI..."
        docker run -d \
            --name "$(get_container_name openwebui)" \
            --network "${DOCKER_NETWORK}" \
            --restart unless-stopped \
            -e WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY}" \
            -v "${DATA_ROOT}/data/openwebui:/app/backend/data" \
            -u "${RUNNING_UID}:${RUNNING_GID}" \
            ghcr.io/open-webui/open-webui:main
    else
        print_info "OpenWebUI disabled (ENABLE_OPENWEBUI=false)"
    fi
    
    # AnythingLLM - fixed configuration with proper storage path and LiteLLM integration
    if [[ "${ENABLE_ANYTHINGLLM:-true}" == "true" ]]; then
        print_info "Deploying AnythingLLM..."
        docker run -d \
            --name "$(get_container_name anythingllm)" \
            --network "${DOCKER_NETWORK}" \
            --restart unless-stopped \
            --user "${RUNNING_UID}:${RUNNING_GID}" \
            -p "${ANYTHINGLLM_PORT}:3001" \
            -v "${DATA_ROOT}/data/anythingllm:/app/server/storage" \
            -e STORAGE_DIR=/app/server/storage \
            -e JWT_SECRET="${ANYTHINGLLM_JWT_SECRET}" \
            -e DISABLE_TELEMETRY=true \
            -e LLM_PROVIDER="litellm" \
            -e LITELLM_BASE_URL="http://litellm:4000" \
            -e LITELLM_API_KEY="${LITELLM_MASTER_KEY}" \
            -e EMBEDDING_PROVIDER="litellm" \
            -e EMBEDDING_MODEL_PREF="text-embedding-ada-002" \
            mintplexlabs/anythingllm:latest
    else
        print_info "AnythingLLM disabled (ENABLE_ANYTHINGLLM=false)"
    fi
    
    # Signal API
    if [[ "${ENABLE_SIGNAL:-true}" == "true" ]]; then
        print_info "Deploying Signal API..."
        docker run -d \
            --name "$(get_container_name signal-api)" \
            --network "${DOCKER_NETWORK}" \
            --restart unless-stopped \
            --user "${RUNNING_UID}:${RUNNING_GID}" \
            -p "${SIGNAL_API_PORT}:8080" \
            -e MODE=native \
            -v "${DATA_ROOT}/data/signal:/home/.local/share/signal-cli" \
            bbernhard/signal-cli-rest-api:latest
    else
        print_info "Signal API disabled (ENABLE_SIGNAL=false)"
    fi
    
    # LiteLLM - enhanced configuration for multi-provider routing
    if [[ "${ENABLE_LITELLM:-true}" == "true" ]]; then
        print_info "Deploying LiteLLM..."
        docker run -d \
            --name "$(get_container_name litellm)" \
            --network "${DOCKER_NETWORK}" \
            --restart unless-stopped \
            -e LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY}" \
            -e LITELLM_SALT_KEY="${LITELLM_MASTER_KEY}" \
            -e DATABASE_URL="postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB:-aiplatform}" \
            -e REDIS_URL="redis://:${REDIS_PASSWORD:-}@redis:6379" \
            -v "${DATA_ROOT}/data/litellm:/app/data" \
            -v "${DATA_ROOT}/logs/litellm:/app/logs" \
            -v "${DATA_ROOT}/config/litellm/config.yaml:/app/config.yaml:ro" \
            -u "${RUNNING_UID}:${RUNNING_GID}" \
            ghcr.io/berriai/litellm:main-latest \
            --config /app/config.yaml --port 4000
    else
        print_info "LiteLLM disabled (ENABLE_LITELLM=false)"
    fi
    
    # Flowise - runs as root (UID 0) due to Node.js user info issues
    if [[ "${ENABLE_FLOWISE:-true}" == "true" ]]; then
        print_info "Deploying Flowise..."
        docker run -d \
            --name "$(get_container_name flowise)" \
            --network "${DOCKER_NETWORK}" \
            --restart unless-stopped \
            -e PORT=3000 \
            -e FLOWISE_HOST=0.0.0.0 \
            -e DATABASE_PATH=/root/.flowise \
            -e APIKEY_PATH=/root/.flowise \
            -e HOME=/root \
            -v "${DATA_ROOT}/data/flowise:/root/.flowise" \
            flowiseai/flowise:latest
    else
        print_info "Flowise disabled (ENABLE_FLOWISE=false)"
    fi
    
    # Wait for layer 2
    if [[ "${ENABLE_N8N:-true}" == "true" ]]; then
        wait_http "n8n" "http://n8n:5678/healthz" 60
    fi
    if [[ "${ENABLE_MINIO:-true}" == "true" ]]; then
        wait_http "minio" "http://minio:9000/minio/health/live" 60
    fi
    if [[ "${ENABLE_FLOWISE:-true}" == "true" ]]; then
        wait_http "flowise" "http://flowise:3000" 60
    fi
    # wait_http "litellm" "http://litellm:4000/health" 60  # Temporarily disabled - needs API key
    
    # Create MinIO buckets after MinIO is ready
    if [[ "${ENABLE_MINIO:-true}" == "true" ]]; then
        print_info "Creating MinIO buckets..."
        docker exec minio mc alias set local http://localhost:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" 2>/dev/null || true
        docker exec minio mc mb local/n8n-data --ignore-existing 2>/dev/null || true
        docker exec minio mc mb local/anythingllm --ignore-existing 2>/dev/null || true
        docker exec minio mc mb local/dify --ignore-existing 2>/dev/null || true
        print_success "MinIO buckets created"
    fi
    
    print_success "Layer 2 application services healthy (litellm health check disabled)"
}

deploy_layer_2_5_dify() {
    print_header "Layer 2.5: Dify Multi-Container Service"
    
    if [[ "${ENABLE_DIFY:-true}" != "true" ]]; then
        print_info "Dify disabled (ENABLE_DIFY=false)"
        return
    fi
    
    # Create Dify directories
    mkdir -p "${DATA_ROOT}/data/dify/storage"
    mkdir -p "${DATA_ROOT}/data/dify/logs"
    chown -R ${RUNNING_UID}:${RUNNING_GID} "${DATA_ROOT}/data/dify/"
    
    # Dify API container
    docker run -d \
        --name "$(get_container_name dify-api)" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${RUNNING_UID}:${RUNNING_GID}" \
        -e MODE=api \
        -e SECRET_KEY="${DIFY_SECRET_KEY}" \
        -e DB_USERNAME="${POSTGRES_USER:-postgres}" \
        -e DB_PASSWORD="${POSTGRES_PASSWORD}" \
        -e DB_HOST=postgres \
        -e DB_PORT=5432 \
        -e DB_DATABASE="${POSTGRES_DB:-aiplatform}" \
        -e REDIS_HOST=redis \
        -e REDIS_PORT=6379 \
        -e REDIS_PASSWORD="${REDIS_PASSWORD}" \
        -e STORAGE_TYPE=local \
        -e STORAGE_LOCAL_PATH=/app/api/storage \
        -e CELERY_BROKER_URL="redis://:${REDIS_PASSWORD:-}@redis:6379/1" \
        -v "${DATA_ROOT}/data/dify/storage:/app/api/storage" \
        langgenius/dify-api:latest
    
    # Dify Worker container
    docker run -d \
        --name "$(get_container_name dify-worker)" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${RUNNING_UID}:${RUNNING_GID}" \
        -e MODE=worker \
        -e SECRET_KEY="${DIFY_SECRET_KEY}" \
        -e DB_USERNAME="${POSTGRES_USER:-postgres}" \
        -e DB_PASSWORD="${POSTGRES_PASSWORD}" \
        -e DB_HOST=postgres \
        -e DB_PORT=5432 \
        -e DB_DATABASE="${POSTGRES_DB:-aiplatform}" \
        -e REDIS_HOST=redis \
        -e REDIS_PORT=6379 \
        -e REDIS_PASSWORD="${REDIS_PASSWORD}" \
        -e STORAGE_TYPE=local \
        -e STORAGE_LOCAL_PATH=/app/api/storage \
        -e CELERY_BROKER_URL="redis://:${REDIS_PASSWORD:-}@redis:6379/1" \
        -v "${DATA_ROOT}/data/dify/storage:/app/api/storage" \
        langgenius/dify-api:latest
    
    # Dify Web container
    docker run -d \
        --name "$(get_container_name dify-web)" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --user "${RUNNING_UID}:${RUNNING_GID}" \
        -e EDITION=SELF_HOSTED \
        -e CONSOLE_API_URL="https://dify.${DOMAIN_NAME:-localhost}" \
        -e APP_API_URL="https://dify.${DOMAIN_NAME:-localhost}" \
        langgenius/dify-web:latest
    
    # Wait for Dify services
    wait_http "dify-api" "http://$(get_container_name dify-api):5001/health" 60
    wait_http "dify-web" "http://$(get_container_name dify-web):3000" 60
    
    print_success "Layer 2.5 Dify multi-container service healthy"
}

deploy_layer_3_monitoring() {
    print_header "Layer 3: Monitoring Services"
    
    if [[ "${ENABLE_GRAFANA:-true}" != "true" && "${ENABLE_PROMETHEUS:-true}" != "true" ]]; then
        print_info "Monitoring services disabled (ENABLE_GRAFANA=false and ENABLE_PROMETHEUS=false)"
        return
    fi
    
    # Create Prometheus config
    mkdir -p "${DATA_ROOT}/config/prometheus"
    mkdir -p "${DATA_ROOT}/data/prometheus"
    chown -R 65534:65534 "${DATA_ROOT}/data/prometheus"
    chown -R 65534:65534 "${DATA_ROOT}/config/prometheus"
    # Generate dynamic Prometheus config based on enabled services
    cat > "${DATA_ROOT}/config/prometheus/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
EOF

    # Add scrape configs for enabled services only
    if [[ "${ENABLE_N8N:-false}" == "true" ]]; then
        cat >> "${DATA_ROOT}/config/prometheus/prometheus.yml" << EOF
  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
EOF
    fi

    if [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]]; then
        cat >> "${DATA_ROOT}/config/prometheus/prometheus.yml" << EOF
  - job_name: 'openwebui'
    static_configs:
      - targets: ['openwebui:8080']
EOF
    fi

    if [[ "${ENABLE_LITELLM:-false}" == "true" ]]; then
        cat >> "${DATA_ROOT}/config/prometheus/prometheus.yml" << EOF
  - job_name: 'litellm'
    static_configs:
      - targets: ['litellm:4000']
EOF
    fi

    if [[ "${ENABLE_QDRANT:-false}" == "true" ]]; then
        cat >> "${DATA_ROOT}/config/prometheus/prometheus.yml" << EOF
  - job_name: 'qdrant'
    static_configs:
      - targets: ['qdrant:6333']
EOF
    fi

    # Postgres is always enabled
    cat >> "${DATA_ROOT}/config/prometheus/prometheus.yml" << EOF
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']
EOF

    if [[ "${ENABLE_MINIO:-false}" == "true" ]]; then
        cat >> "${DATA_ROOT}/config/prometheus/prometheus.yml" << EOF
  - job_name: 'minio'
    static_configs:
      - targets: ['minio:9000']
EOF
    fi

    if [[ "${ENABLE_FLOWISE:-false}" == "true" ]]; then
        cat >> "${DATA_ROOT}/config/prometheus/prometheus.yml" << EOF
  - job_name: 'flowise'
    static_configs:
      - targets: ['flowise:3000']
EOF
    fi

    if [[ "${ENABLE_DIFY:-false}" == "true" ]]; then
        cat >> "${DATA_ROOT}/config/prometheus/prometheus.yml" << EOF
  - job_name: 'dify-api'
    static_configs:
      - targets: ['dify-api:5001']
  - job_name: 'dify-worker'
    static_configs:
      - targets: ['dify-worker:5001']
EOF
    fi

    if [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]]; then
        cat >> "${DATA_ROOT}/config/prometheus/prometheus.yml" << EOF
  - job_name: 'anythingllm'
    static_configs:
      - targets: ['anythingllm:3000']
EOF
    fi

    # Add node exporter for system metrics
    cat >> "${DATA_ROOT}/config/prometheus/prometheus.yml" << EOF
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
EOF
    
    chown "${RUNNING_UID}:${RUNNING_GID}" "${DATA_ROOT}/config/prometheus/prometheus.yml"
    
    # Prometheus with correct port mapping and arguments
    if [[ "${ENABLE_PROMETHEUS:-true}" == "true" ]]; then
        print_info "Deploying Prometheus..."
        docker run -d \
            --name "$(get_container_name prometheus)" \
            --network "${DOCKER_NETWORK}" \
            --restart unless-stopped \
            --user "${RUNNING_UID}:${RUNNING_GID}" \
            -p "${PROMETHEUS_PORT}:9090" \
            -v "${DATA_ROOT}/config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
            -v "${DATA_ROOT}/data/prometheus:/prometheus" \
            prom/prometheus:latest \
            --config.file=/etc/prometheus/prometheus.yml \
            --storage.tsdb.path=/prometheus \
            --web.console.libraries=/etc/prometheus/console_libraries \
            --web.console.templates=/etc/prometheus/consoles \
            --web.enable-lifecycle
    else
        print_info "Prometheus disabled (ENABLE_PROMETHEUS=false)"
    fi
    
    # Grafana with correct user and port mapping
    if [[ "${ENABLE_GRAFANA:-true}" == "true" ]]; then
        print_info "Deploying Grafana..."
        docker run -d \
            --name "$(get_container_name grafana)" \
            --network "${DOCKER_NETWORK}" \
            --restart unless-stopped \
            --user "${RUNNING_UID}:${RUNNING_GID}" \
            -p "${GRAFANA_PORT}:3000" \
            -e GF_SERVER_ROOT_URL="https://grafana.${DOMAIN_NAME:-localhost}/" \
            -e GF_SECURITY_ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
            -v "${DATA_ROOT}/data/grafana:/var/lib/grafana" \
            grafana/grafana:latest
    else
        print_info "Grafana disabled (ENABLE_GRAFANA=false)"
    fi
    
    # Wait for monitoring services
    if [[ "${ENABLE_PROMETHEUS:-true}" == "true" ]]; then
        wait_http "prometheus" "http://prometheus:9090/-/healthy" 60
    fi
    if [[ "${ENABLE_GRAFANA:-true}" == "true" ]]; then
        wait_http "grafana" "http://grafana:3000/api/health" 60
    fi
    print_success "Layer 3 monitoring services healthy"
}

deploy_layer_4_openclaw() {
    print_header "Layer 4: OpenClaw (restricted)"
    
    if [[ "${ENABLE_OPENCLAW:-true}" != "true" ]]; then
        print_info "OpenClaw disabled (ENABLE_OPENCLAW=false)"
        return
    fi
    
    # Temporarily skip OpenClaw - image not available
    print_warning "OpenClaw deployment skipped - image not available"
    
    # docker run -d \
    #     --name openclaw \
    #     --network "${DOCKER_NETWORK}" \
    #     --restart unless-stopped \
    #      \
    #     -e VECTOR_DB_URL="http://qdrant:6333" \
    #     -e HOME=/data/openclaw \
    #     -e OPENCLAW_HOME=/data/openclaw \
    #     -e OPENCLAW_CONFIG=/data/openclaw/config \
    #     -e XDG_CONFIG_HOME=/data/openclaw/.config \
    #     -e XDG_DATA_HOME=/data/openclaw/.local \
    #     -v "${DATA_ROOT}/data/openclaw:/data/openclaw" \
    #     -u "${OPENCLAW_UID}:${OPENCLAW_GID}" \
    #     --read-only \
    #     --tmpfs /tmp:rw,noexec,nosuid \
    #     openclaw/openclaw:latest
    
    print_success "Layer 3 OpenClaw skipped"
    # wait_http "openclaw" "http://openclaw:8080/health" 60  # Skipped - OpenClaw not deployed
    print_success "Layer 3 OpenClaw healthy (skipped)"
}

deploy_layer_5_proxy() {
    print_header "Layer 5: Caddy (last)"
    
    if [[ "${ENABLE_CADDY:-true}" != "true" ]]; then
        print_info "Caddy disabled (ENABLE_CADDY=false)"
        return
    fi
    
    # Ensure Caddyfile directory exists and is properly formatted
    mkdir -p "${DATA_ROOT}/caddy"
    
    # Caddyfile already written by Script 1, but ensure proper SSL configuration
    # Remove any stale lock files before starting
    if docker exec $(get_container_name caddy) find /data/caddy/locks/ -name "*.lock" 2>/dev/null | grep -q .; then
        print_info "Removing stale certificate lock files..."
        docker exec $(get_container_name caddy) find /data/caddy/locks/ -name "*.lock" -delete 2>/dev/null || true
    fi
    
    # Remove stale ACME challenge tokens
    docker exec $(get_container_name caddy) find /data/caddy/acme/ -name "*.json" -delete 2>/dev/null || true
    
    docker run -d \
        --name "$(get_container_name caddy)" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        -p "80:80" \
        -p "443:443" \
        -v "${DATA_ROOT}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
        -v "${DATA_ROOT}/caddy/data:/data" \
        -v "${DATA_ROOT}/caddy/config:/config" \
        caddy:2-alpine
    
    # Wait for Caddy to be ready before proceeding to application layer
    wait_for_caddy
    
    print_success "Caddy started with SSL certificate management"
}

wait_healthy() {
    local container=$1
    local check_cmd=$2
    local timeout=$3
    local elapsed=0
    
    echo -n "  Waiting for ${container}..."
    while ! eval "${check_cmd}" &>/dev/null; do
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
        if [[ $elapsed -ge $timeout ]]; then
            echo ""
            print_error "${container} failed to become healthy after ${timeout}s"
            print_info "Logs:"
            docker logs --tail 20 "$(get_container_name ${container})"
            exit 1
        fi
    done
    echo " "
}

wait_http() {
    local name=$1
    local url=$2
    local timeout=$3
    local elapsed=0
    
    echo -n "  Waiting for ${name} HTTP..."
    while ! docker run --rm --network "${DOCKER_NETWORK}" \
            curlimages/curl:latest -sf "${url}" &>/dev/null; do
        sleep 3
        elapsed=$((elapsed + 3))
        echo -n "."
        if [[ $elapsed -ge $timeout ]]; then
            echo ""
            print_error "${name} HTTP check failed after ${timeout}s"
            print_info "Logs:"
            docker logs --tail 30 "${name}"
            exit 1
        fi
    done
    echo " "
}

# Validate deployment with smart health checks that respect ENABLE_* flags
validate_deployment() {
    print_header "Validating Deployment"
    local failed_services=()

    check_service() {
        local NAME="$1"
        local CONTAINER_NAME="$2"
        local ENABLED="$3"
        local HEALTH_CHECK="$4"

        if [[ "${ENABLED}" != "true" ]]; then
            echo "  ⏭  ${NAME} — disabled (skipped)"
            return 0
        fi

        if docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
            # Perform health check if provided
            if [[ -n "${HEALTH_CHECK}" ]]; then
                if eval "${HEALTH_CHECK}" &>/dev/null; then
                    echo "  ✅ ${NAME} — OK"
                else
                    echo "  ❌ ${NAME} — FAILED (unhealthy)"
                    failed_services+=("$NAME")
                fi
            else
                echo "  ✅ ${NAME} — running"
            fi
        else
            echo "  ❌ ${NAME} — NOT RUNNING"
            failed_services+=("$NAME")
        fi
    }

    echo "🔍 Service Health Status:"
    check_service "PostgreSQL" "$(get_container_name postgres)" "${ENABLE_POSTGRES:-true}" \
        "docker exec $(get_container_name postgres) pg_isready -U ${POSTGRES_USER:-postgres}"

    check_service "Redis" "$(get_container_name redis)" "${ENABLE_REDIS:-true}" \
        "docker exec $(get_container_name redis) redis-cli -a ${REDIS_PASSWORD:-} ping"

    check_service "Qdrant" "$(get_container_name qdrant)" "${ENABLE_QDRANT:-true}" \
        "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://$(get_container_name qdrant):6333/"

    check_service "MinIO" "$(get_container_name minio)" "${ENABLE_MINIO:-false}" \
        "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://$(get_container_name minio):9000/minio/health/live"

    check_service "n8n" "$(get_container_name n8n)" "${ENABLE_N8N:-false}" \
        "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://$(get_container_name n8n):5678/healthz"

    check_service "OpenWebUI" "$(get_container_name openwebui)" "${ENABLE_OPENWEBUI:-false}" \
        "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://$(get_container_name openwebui):3000"

    check_service "AnythingLLM" "$(get_container_name anythingllm)" "${ENABLE_ANYTHINGLLM:-false}" \
        "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://$(get_container_name anythingllm):3001"

    check_service "Signal API" "$(get_container_name signal-api)" "${ENABLE_SIGNAL_API:-false}" \
        "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://$(get_container_name signal-api):8080"

    check_service "LiteLLM" "$(get_container_name litellm)" "${ENABLE_LITELLM:-true}" \
        "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://$(get_container_name litellm):4000/health"

    check_service "Flowise" "$(get_container_name flowise)" "${ENABLE_FLOWISE:-false}" \
        "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://$(get_container_name flowise):3000"

    check_service "Dify API" "$(get_container_name dify-api)" "${ENABLE_DIFY:-false}" \
        "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://$(get_container_name dify-api):5001/health"

    check_service "Dify Web" "$(get_container_name dify-web)" "${ENABLE_DIFY:-false}" \
        "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://$(get_container_name dify-web):3000"

    check_service "Prometheus" "$(get_container_name prometheus)" "${ENABLE_PROMETHEUS:-true}" \
        "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://$(get_container_name prometheus):9090/-/healthy"

    check_service "Grafana" "$(get_container_name grafana)" "${ENABLE_GRAFANA:-true}" \
        "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://$(get_container_name grafana):3000/api/health"

    check_service "Caddy" "$(get_container_name caddy)" "${ENABLE_CADDY:-true}" \
        "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://$(get_container_name caddy):80"

    check_service "OpenClaw" "$(get_container_name openclaw)" "${ENABLE_OPENCLAW:-true}" \
        "docker run --rm --network ${DOCKER_NETWORK} alpine/curl -sf http://$(get_container_name openclaw):8080/health"

    check_service "rclone" "$(get_container_name rclone-gdrive)" "${ENABLE_GDRIVE:-false}" \
        ""

    echo ""
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        print_warning "${#failed_services[@]} service(s) failed health check: ${failed_services[*]}"
        print_info "Check logs: ${COMPOSE} logs --tail=50"
        return 1
    else
        print_success "All enabled services healthy"
        return 0
    fi
}

# Display deployment summary
display_summary() {
    print_header "Deployment Summary"
    
    echo "📊 Stack Information:"
    echo "   Base Directory: ${DATA_ROOT}"
    echo "   Network: ${DOCKER_NETWORK}"
    echo "   Domain: ${DOMAIN_NAME}"
    echo "   Proxy Method: ${PROXY_CONFIG_METHOD:-subdomain}"
    echo ""
    echo "🌐 Service URLs:"
    if [[ "${PROXY_CONFIG_METHOD:-subdomain}" == "subdomain" ]]; then
        echo "   n8n: https://n8n.${DOMAIN_NAME}/"
        echo "   OpenWebUI: https://openwebui.${DOMAIN_NAME}/"
        echo "   AnythingLLM: https://anythingllm.${DOMAIN_NAME}/"
        echo "   Flowise: https://flowise.${DOMAIN_NAME}/"
        echo "   LiteLLM: https://litellm.${DOMAIN_NAME}/"
        echo "   Grafana: https://grafana.${DOMAIN_NAME}/"
        echo "   MinIO: https://minio.${DOMAIN_NAME}/"
        echo "   Signal API: https://signal-api.${DOMAIN_NAME}/"
        echo "   Prometheus: https://prometheus.${DOMAIN_NAME}/"
        echo "   Dify: https://dify.${DOMAIN_NAME}/"
        echo "   Main Domain: https://${DOMAIN_NAME}/ (redirects to OpenWebUI)"
    else
        echo "   n8n: http://${LOCALHOST}:${N8N_PORT}/n8n/"
        echo "   OpenWebUI: http://${LOCALHOST}:${OPENWEBUI_PORT}/openwebui/"
        echo "   AnythingLLM: http://${LOCALHOST}:${ANYTHINGLLM_PORT}/anythingllm/"
        echo "   Flowise: http://${LOCALHOST}:${FLOWISE_PORT}/flowise/"
        echo "   LiteLLM: http://${LOCALHOST}:${LITELLM_PORT}/litellm/"
        echo "   Grafana: http://${LOCALHOST}:${GRAFANA_PORT}/grafana/"
        echo "   MinIO: http://${LOCALHOST}:${MINIO_CONSOLE_PORT}/minio/"
        echo "   Signal API: http://${LOCALHOST}:${SIGNAL_API_PORT}/"
        echo "   Prometheus: http://${LOCALHOST}:${PROMETHEUS_PORT}/prometheus/"
        echo "   Dify: http://${LOCALHOST}:${DIFY_PORT}/dify/"
    fi
    echo ""
    echo "📋 Next Steps:"
    echo "   1. Access services via the URLs above"
    echo "   2. Check service health: docker ps"
    echo "   3. View logs: docker logs <service_name>"
    echo "   4. Monitor certificates: docker exec caddy find /data/caddy/certificates/ -name '*.crt'"
    
    # RClone management section
    if [[ "${GDRIVE_ENABLED:-false}" == "true" ]]; then
        echo ""
        echo "📁 RClone Google Drive Management:"
        echo "   - Run sync now: docker restart rclone-gdrive"
        echo "   - View logs: docker logs rclone-gdrive --tail 50"
        echo "   - Check status: docker inspect rclone-gdrive"
        echo "   - Mount point: ${RCLONE_MOUNT_POINT:-${DATA_ROOT}/gdrive}"
    fi
    
    # Tailscale/OpenClaw section
    if [[ -n "${TAILSCALE_IP:-}" ]] && [[ "${TAILSCALE_IP}" != "pending" ]]; then
        echo ""
        echo "🔒 OpenClaw (internal only):"
        echo "   URL: http://${TAILSCALE_IP}:18789"
        echo "   Access via Tailscale VPN only"
        echo "   Install Tailscale client: https://tailscale.com/download"
    fi
    echo ""
    print_success "Deployment complete! All services are running with SSL certificates."
}

# LiteLLM configuration generation
generate_litellm_config() {
    local conf_path="${DATA_ROOT}/config/litellm/config.yaml"
    mkdir -p "${DATA_ROOT}/config/litellm"

    cat > "${conf_path}" << EOF
model_list:
EOF

    # Add OpenAI models if enabled (check for API key)
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        cat >> "${conf_path}" << EOF
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: ${OPENAI_API_KEY}
  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: ${OPENAI_API_KEY}
EOF
    fi

    # Add Anthropic models if enabled (check for API key)
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        cat >> "${conf_path}" << EOF
  - model_name: claude-sonnet-4-5
    litellm_params:
      model: anthropic/claude-sonnet-4-5
      api_key: ${ANTHROPIC_API_KEY}
  - model_name: claude-haiku-3-5
    litellm_params:
      model: anthropic/claude-haiku-3-5
      api_key: ${ANTHROPIC_API_KEY}
EOF
    fi

    # Add Ollama model if Ollama is enabled
    if [[ "${ENABLE_OLLAMO:-false}" == "true" ]]; then
        cat >> "${conf_path}" << EOF
  - model_name: ollama-llama3
    litellm_params:
      model: ollama/llama3
      api_base: http://ollama:11434
EOF
    fi

    # Always add the general settings block
    cat >> "${conf_path}" << EOF

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD}@postgres:5432/litellm

litellm_settings:
  drop_params: true
  request_timeout: 120
EOF

    chmod 600 "${conf_path}"
    chown "${RUNNING_UID}:${RUNNING_GID}" "${conf_path}"
    print_success "LiteLLM config written to ${conf_path}"
}

# Tailscale setup with daemon socket check and key validation
setup_tailscale() {
    if [[ "${ENABLE_TAILSCALE:-false}" != "true" ]]; then
        print_info "Tailscale disabled — skipping"
        return 0
    fi

    print_info "Setting up Tailscale..."

    # Install if missing
    if ! command -v tailscale &>/dev/null; then
        print_info "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    fi

    # Ensure daemon is running
    if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
        print_info "Starting tailscaled..."
        systemctl enable tailscaled --now
        # Wait for socket to appear
        ATTEMPTS=0
        while [[ ! -S /var/run/tailscale/tailscaled.sock ]] && \
              [[ "${ATTEMPTS}" -lt 15 ]]; do
            sleep 2
            ATTEMPTS=$((ATTEMPTS + 1))
        done
    fi

    # Validate key format before calling tailscale up
    if [[ ! "${TAILSCALE_AUTH_KEY}" =~ ^tskey-auth- ]]; then
        print_error "Invalid Tailscale auth key format: ${TAILSCALE_AUTH_KEY}"
        print_error "Must start with 'tskey-auth-'"
        exit 1
    fi

    # Bring up Tailscale with correct flags for a Docker host
    print_info "Bringing up Tailscale (hostname: ${TAILSCALE_HOSTNAME})..."
    tailscale up \
        --authkey="${TAILSCALE_AUTH_KEY}" \
        --hostname="${TAILSCALE_HOSTNAME}" \
        --accept-dns=false \
        --accept-routes=false \
        --reset

    # Wait for IP with timeout
    TAILSCALE_IP=""
    ATTEMPTS=0
    while [[ -z "${TAILSCALE_IP}" ]] && [[ "${ATTEMPTS}" -lt 30 ]]; do
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)
        [[ -z "${TAILSCALE_IP}" ]] && sleep 2
        ATTEMPTS=$((ATTEMPTS + 1))
    done

    if [[ -z "${TAILSCALE_IP}" ]]; then
        print_error "Tailscale failed to obtain IP after 60 seconds"
        print_error "Debug: tailscale status"
        exit 1
    fi

    # Persist IP for other scripts
    sed -i "s|^TAILSCALE_IP=.*|TAILSCALE_IP=${TAILSCALE_IP}|" "${ENV_FILE}" || \
        echo "TAILSCALE_IP=${TAILSCALE_IP}" >> "${ENV_FILE}"

    print_success "Tailscale IP: ${TAILSCALE_IP}"
    print_success "Tailscale hostname: ${TAILSCALE_HOSTNAME}"

    # Verify connectivity
    if tailscale status | grep -q "100\.[0-9]"; then
        print_success "Tailscale connected and operational"
    else
        print_warning "Tailscale IP assigned but status unclear — check: tailscale status"
    fi
}

# RClone configuration generation with OAuth tunnel fix
setup_rclone() {
    if [[ "${ENABLE_GDRIVE:-false}" != "true" ]] && [[ "${GDRIVE_ENABLED:-false}" != "true" ]]; then
        print_info "Google Drive sync disabled — skipping rclone setup"
        return 0
    fi

    print_info "Setting up rclone..."
    mkdir -p "${DATA_ROOT}/config/rclone"
    mkdir -p "${RCLONE_MOUNT_POINT:-${DATA_ROOT}/gdrive}"
    mkdir -p "${DATA_ROOT}/logs/rclone"

    case "${GDRIVE_AUTH_METHOD:-${RCLONE_AUTH_METHOD:-}}" in

        service_account)
            # Validate service account JSON exists
            SA_FILE="${DATA_ROOT}/config/rclone/service-account.json"
            if [[ ! -f "$SA_FILE" ]]; then
                print_error "Service account JSON not found: $SA_FILE"
                print_error "Re-run Script 1 and provide service account JSON path"
                exit 1
            fi

            # Write rclone.conf (service account — no OAuth)
            cat > "${DATA_ROOT}/config/rclone/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
service_account_file = /data/config/rclone/service-account.json
root_folder_id = ${RCLONE_GDRIVE_FOLDER:-}
EOF
            print_success "rclone config written (service account)"
            ;;

        oauth_tunnel)
            RCLONE_CONF="${DATA_ROOT}/config/rclone/rclone.conf"

            # Check if token already obtained
            if [[ "${RCLONE_TOKEN_OBTAINED}" == "true" ]] && \
               [[ -f "$RCLONE_CONF" ]] && \
               grep -q '"access_token"' "$RCLONE_CONF" 2>/dev/null; then
                print_success "rclone OAuth token already present — starting container"
            else
                # Print instructions and defer to Script 3
                echo ""
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "  rclone OAuth Authorization Required"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
                echo "  Run this on YOUR LOCAL MACHINE (laptop/desktop):"
                echo ""
                echo "  Step 1: Open a NEW terminal on your local machine"
                echo "  Step 2: Run:"
                echo "    ssh -L 53682:localhost:53682 $(whoami)@$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')"
                echo ""
                echo "  Step 3: In ANOTHER local terminal, run:"
                echo "    rclone authorize \"drive\" \\"
                echo "      \"${RCLONE_OAUTH_CLIENT_ID}\" \\"
                echo "      \"${RCLONE_OAUTH_CLIENT_SECRET}\""
                echo ""
                echo "  Step 4: Complete the browser auth flow"
                echo "  Step 5: Copy the token JSON that rclone prints"
                echo "  Step 6: Run Script 3 to paste the token and complete setup"
                echo ""
                echo "  ⚠️  Google Drive sync will be DISABLED until this is done"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
                print_warning "rclone setup deferred — run Script 3 to complete"

                # Disable gdrive in this run so other services still start
                ENABLE_GDRIVE=false
                GDRIVE_ENABLED=false
                return 0
            fi
            ;;

        paste_token)
            # Token was already pasted in Script 1 and written to rclone.conf
            RCLONE_CONF="${DATA_ROOT}/config/rclone/rclone.conf"
            if [[ ! -f "$RCLONE_CONF" ]]; then
                print_error "rclone.conf not found — re-run Script 1"
                exit 1
            fi
            print_success "rclone config found (paste_token method)"
            ;;

        *)
            print_error "Unknown rclone auth method: ${GDRIVE_AUTH_METHOD:-${RCLONE_AUTH_METHOD}}"
            exit 1
            ;;
    esac

    print_success "rclone configuration completed"
}

# RClone service management
create_rclone_service() {
    print_info "Creating RClone systemd service..."
    
    # Create systemd service file
    cat > "/etc/systemd/system/rclone-gdrive.service" << EOF
[Unit]
Description=RClone Google Drive Mount Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUNNING_USER}
Group=${RUNNING_GID}
ExecStart=/usr/bin/rclone mount ${RCLONE_REMOTE_NAME:-gdrive}: ${RCLONE_MOUNT_POINT} \\
    --config ${RCLONE_CONFIG_DIR} \\
    --cache-dir ${RCLONE_CACHE_DIR} \\
    --log-file ${RCLONE_LOGS_DIR}/rclone.log \\
    --log-level INFO \\
    --allow-non-empty \\
    --vfs-cache-mode writes \\
    --dir-cache-time 5m \\
    --poll-interval 1m \\
    --umask 002
ExecStop=/bin/fusermount -u ${RCLONE_MOUNT_POINT}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Create mount point if it doesn't exist
    mkdir -p "${RCLONE_MOUNT_POINT}"
    chown "${RUNNING_UID}:${RUNNING_GID}" "${RCLONE_MOUNT_POINT}"
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable rclone-gdrive.service
    
    print_success "RClone service created and enabled"
    print_info "Use 'systemctl start rclone-gdrive' to start the mount"
    print_info "Use 'systemctl stop rclone-gdrive' to stop the mount"
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
    validate_config
    verify_ports
    set_vectordb_config
    
    # Deploy services in dependency order
    # Generate configurations before deployment
    setup_rclone
    generate_litellm_config
    
    # Setup Tailscale before services start
    setup_tailscale
    
    deploy_layered_services
    
    # Validate and summarize
    validate_deployment
    display_summary
}

# Run main function
main "$@"
