#!/bin/bash

set -euo pipefail

# ============================================================================
# AI Platform - Add Service Script v9.0
# Dynamically add new Docker services to the platform
# ============================================================================

readonly SCRIPT_VERSION="9.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="${PROJECT_ROOT}/logs/add-service-$(date +%Y%m%d-%H%M%S).log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

success() { echo -e "${GREEN}✓ $*${NC}" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}✗ $*${NC}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}" | tee -a "$LOG_FILE"; }
info() { echo -e "${BLUE}ℹ $*${NC}" | tee -a "$LOG_FILE"; }
prompt() { echo -e "${CYAN}❯ $*${NC}"; }

# ============================================================================
# Setup Logging
# ============================================================================

setup_logging() {
    mkdir -p "${PROJECT_ROOT}/logs"
    echo "Add service started at $(date)" > "$LOG_FILE"
    info "Log file: $LOG_FILE"
}

# ============================================================================
# Display Banner
# ============================================================================

display_banner() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║       AI Platform - Add Service v${SCRIPT_VERSION}                   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

# ============================================================================
# Load Environment
# ============================================================================

load_environment() {
    info "Loading environment configuration..."
    
    if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
        error "Environment file not found: ${PROJECT_ROOT}/.env"
        exit 1
    fi
    
    set -a
    source "${PROJECT_ROOT}/.env"
    set +a
    
    success "Environment loaded"
}

# ============================================================================
# Service Templates
# ============================================================================

get_service_template() {
    local service_type="$1"
    
    case $service_type in
        "basic")
            echo "basic_service_template"
            ;;
        "ai-model")
            echo "ai_model_template"
            ;;
        "web-ui")
            echo "web_ui_template"
            ;;
        "database")
            echo "database_template"
            ;;
        "custom")
            echo "custom_template"
            ;;
        *)
            echo "basic_service_template"
            ;;
    esac
}

# ============================================================================
# Template: Basic Service
# ============================================================================

basic_service_template() {
    local service_name="$1"
    local image="$2"
    local port="$3"
    local env_vars="$4"
    
    cat << EOF
version: '3.8'

services:
  ${service_name}:
    image: ${image}
    container_name: ${service_name}
    restart: unless-stopped
    ports:
      - "${port}:${port}"
    networks:
      - ai-platform
    volumes:
      - ${PROJECT_ROOT}/data/${service_name}:/data
      - ${PROJECT_ROOT}/data/gdrive/sync:/gdrive:ro
    environment:
${env_vars}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${port}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai-platform:
    external: true
EOF
}

# ============================================================================
# Template: AI Model Service
# ============================================================================

ai_model_template() {
    local service_name="$1"
    local image="$2"
    local port="$3"
    local gpu_enabled="$4"
    local env_vars="$5"
    
    local gpu_config=""
    if [[ $gpu_enabled == "true" ]]; then
        gpu_config="    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]"
    fi
    
    cat << EOF
version: '3.8'

services:
  ${service_name}:
    image: ${image}
    container_name: ${service_name}
    restart: unless-stopped
    ports:
      - "${port}:${port}"
    networks:
      - ai-platform
    volumes:
      - ${PROJECT_ROOT}/data/${service_name}:/data
      - ${PROJECT_ROOT}/data/${service_name}/models:/models
      - ${PROJECT_ROOT}/data/gdrive/sync:/gdrive:ro
    environment:
${env_vars}
${gpu_config}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${port}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

networks:
  ai-platform:
    external: true
EOF
}

# ============================================================================
# Template: Web UI Service
# ============================================================================

web_ui_template() {
    local service_name="$1"
    local image="$2"
    local port="$3"
    local url_path="$4"
    local env_vars="$5"
    
    cat << EOF
version: '3.8'

services:
  ${service_name}:
    image: ${image}
    container_name: ${service_name}
    restart: unless-stopped
    ports:
      - "${port}:${port}"
    networks:
      - ai-platform
    volumes:
      - ${PROJECT_ROOT}/data/${service_name}:/data
      - ${PROJECT_ROOT}/data/gdrive/sync:/gdrive:ro
    environment:
${env_vars}
      - PUBLIC_PATH=/${url_path}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${service_name}.rule=PathPrefix(\`/${url_path}\`)"
      - "traefik.http.services.${service_name}.loadbalancer.server.port=${port}"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${port}/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  ai-platform:
    external: true
EOF
}

# ============================================================================
# Template: Database Service
# ============================================================================

database_template() {
    local service_name="$1"
    local image="$2"
    local port="$3"
    local db_user="$4"
    local db_password="$5"
    local db_name="$6"
    
    cat << EOF
version: '3.8'

services:
  ${service_name}:
    image: ${image}
    container_name: ${service_name}
    restart: unless-stopped
    ports:
      - "${port}:${port}"
    networks:
      - ai-platform
    volumes:
      - ${PROJECT_ROOT}/data/${service_name}:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=${db_user}
      - POSTGRES_PASSWORD=${db_password}
      - POSTGRES_DB=${db_name}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${db_user}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

networks:
  ai-platform:
    external: true
EOF
}

# ============================================================================
# Template: Custom Service (User-provided compose)
# ============================================================================

custom_template() {
    local compose_file="$1"
    
    if [[ ! -f $compose_file ]]; then
        error "Compose file not found: $compose_file"
        return 1
    fi
    
    cat "$compose_file"
}

# ============================================================================
# Collect Service Information
# ============================================================================

collect_service_info() {
    echo "" | tee -a "$LOG_FILE"
    info "=== Service Information Collection ==="
    echo "" | tee -a "$LOG_FILE"
    
    # Service name
    prompt "Enter service name (lowercase, no spaces, e.g., 'myservice'):"
    read -r SERVICE_NAME
    
    if [[ ! $SERVICE_NAME =~ ^[a-z0-9-]+$ ]]; then
        error "Invalid service name. Use lowercase letters, numbers, and hyphens only."
        return 1
    fi
    
    # Check if service already exists
    if [[ -d "${PROJECT_ROOT}/stacks/${SERVICE_NAME}" ]]; then
        error "Service '${SERVICE_NAME}' already exists!"
        prompt "Overwrite existing service? [y/N]:"
        read -r overwrite
        if [[ ! $overwrite =~ ^[Yy]$ ]]; then
            info "Cancelled"
            return 1
        fi
        warn "Existing service will be overwritten"
    fi
    
    # Service type
    echo "" | tee -a "$LOG_FILE"
    info "Select service type:"
    echo "  1) Basic service (generic Docker container)"
    echo "  2) AI Model service (with optional GPU support)"
    echo "  3) Web UI service (with reverse proxy integration)"
    echo "  4) Database service (PostgreSQL/MySQL/etc.)"
    echo "  5) Custom (provide your own docker-compose.yml)"
    echo ""
    
    prompt "Select type [1-5]:"
    read -r service_type_choice
    
    case $service_type_choice in
        1) SERVICE_TYPE="basic" ;;
        2) SERVICE_TYPE="ai-model" ;;
        3) SERVICE_TYPE="web-ui" ;;
        4) SERVICE_TYPE="database" ;;
        5) SERVICE_TYPE="custom" ;;
        *)
            error "Invalid choice"
            return 1
            ;;
    esac
    
    info "Selected type: $SERVICE_TYPE"
    
    # Collect type-specific information
    case $SERVICE_TYPE in
        "basic")
            collect_basic_info
            ;;
        "ai-model")
            collect_ai_model_info
            ;;
        "web-ui")
            collect_web_ui_info
            ;;
        "database")
            collect_database_info
            ;;
        "custom")
            collect_custom_info
            ;;
    esac
}

# ============================================================================
# Collect Basic Service Info
# ============================================================================

collect_basic_info() {
    echo "" | tee -a "$LOG_FILE"
    
    prompt "Enter Docker image (e.g., 'nginx:latest'):"
    read -r DOCKER_IMAGE
    
    prompt "Enter exposed port (e.g., '8080'):"
    read -r SERVICE_PORT
    
    # Environment variables
    echo "" | tee -a "$LOG_FILE"
    info "Add environment variables (leave empty to finish):"
    ENV_VARS=""
    
    while true; do
        prompt "Variable name (or press Enter to finish):"
        read -r var_name
        
        if [[ -z $var_name ]]; then
            break
        fi
        
        prompt "Variable value:"
        read -r var_value
        
        ENV_VARS="${ENV_VARS}      - ${var_name}=${var_value}\n"
    done
}

# ============================================================================
# Collect AI Model Service Info
# ============================================================================

collect_ai_model_info() {
    echo "" | tee -a "$LOG_FILE"
    
    prompt "Enter Docker image (e.g., 'ollama/ollama:latest'):"
    read -r DOCKER_IMAGE
    
    prompt "Enter exposed port (e.g., '11434'):"
    read -r SERVICE_PORT
    
    prompt "Enable GPU support? [y/N]:"
    read -r gpu_choice
    
    if [[ $gpu_choice =~ ^[Yy]$ ]]; then
        GPU_ENABLED="true"
    else
        GPU_ENABLED="false"
    fi
    
    # Environment variables
    echo "" | tee -a "$LOG_FILE"
    info "Add environment variables (leave empty to finish):"
    ENV_VARS=""
    
    while true; do
        prompt "Variable name (or press Enter to finish):"
        read -r var_name
        
        if [[ -z $var_name ]]; then
            break
        fi
        
        prompt "Variable value:"
        read -r var_value
        
        ENV_VARS="${ENV_VARS}      - ${var_name}=${var_value}\n"
    done
}

# ============================================================================
# Collect Web UI Service Info
# ============================================================================

collect_web_ui_info() {
    echo "" | tee -a "$LOG_FILE"
    
    prompt "Enter Docker image (e.g., 'myapp/ui:latest'):"
    read -r DOCKER_IMAGE
    
    prompt "Enter exposed port (e.g., '3000'):"
    read -r SERVICE_PORT
    
    prompt "Enter URL path for reverse proxy (e.g., 'myapp'):"
    read -r URL_PATH
    
    # Environment variables
    echo "" | tee -a "$LOG_FILE"
    info "Add environment variables (leave empty to finish):"
    ENV_VARS=""
    
    while true; do
        prompt "Variable name (or press Enter to finish):"
        read -r var_name
        
        if [[ -z $var_name ]]; then
            break
        fi
        
        prompt "Variable value:"
        read -r var_value
        
        ENV_VARS="${ENV_VARS}      - ${var_name}=${var_value}\n"
    done
}

# ============================================================================
# Collect Database Service Info
# ============================================================================

collect_database_info() {
    echo "" | tee -a "$LOG_FILE"
    
    info "Select database type:"
    echo "  1) PostgreSQL"
    echo "  2) MySQL"
    echo "  3) MongoDB"
    echo "  4) Redis"
    echo "  5) Other"
    echo ""
    
    prompt "Select [1-5]:"
    read -r db_choice
    
    case $db_choice in
        1)
            DOCKER_IMAGE="postgres:16-alpine"
            SERVICE_PORT="5432"
            ;;
        2)
            DOCKER_IMAGE="mysql:8.0"
            SERVICE_PORT="3306"
            ;;
        3)
            DOCKER_IMAGE="mongo:7"
            SERVICE_PORT="27017"
            ;;
        4)
            DOCKER_IMAGE="redis:7-alpine"
            SERVICE_PORT="6379"
            ;;
        5)
            prompt "Enter Docker image:"
            read -r DOCKER_IMAGE
            prompt "Enter port:"
            read -r SERVICE_PORT
            ;;
    esac
    
    # Database credentials
    prompt "Enter database username [default: admin]:"
    read -r DB_USER
    DB_USER="${DB_USER:-admin}"
    
    prompt "Enter database password:"
    read -rs DB_PASSWORD
    echo ""
    
    if [[ -z $DB_PASSWORD ]]; then
        DB_PASSWORD=$(openssl rand -base64 32)
        info "Generated random password: $DB_PASSWORD"
    fi
    
    prompt "Enter database name [default: ${SERVICE_NAME}_db]:"
    read -r DB_NAME
    DB_NAME="${DB_NAME:-${SERVICE_NAME}_db}"
}

# ============================================================================
# Collect Custom Service Info
# ============================================================================

collect_custom_info() {
    echo "" | tee -a "$LOG_FILE"
    
    prompt "Enter path to your docker-compose.yml file:"
    read -r COMPOSE_FILE_PATH
    
    if [[ ! -f $COMPOSE_FILE_PATH ]]; then
        error "File not found: $COMPOSE_FILE_PATH"
        return 1
    fi
    
    info "Using custom compose file: $COMPOSE_FILE_PATH"
}

# ============================================================================
# Generate Docker Compose File
# ============================================================================

generate_compose_file() {
    local stack_dir="${PROJECT_ROOT}/stacks/${SERVICE_NAME}"
    mkdir -p "$stack_dir"
    
    local compose_file="${stack_dir}/docker-compose.yml"
    
    info "Generating docker-compose.yml for ${SERVICE_NAME}..."
    
    case $SERVICE_TYPE in
        "basic")
            basic_service_template "$SERVICE_NAME" "$DOCKER_IMAGE" "$SERVICE_PORT" "$ENV_VARS" > "$compose_file"
            ;;
        "ai-model")
            ai_model_template "$SERVICE_NAME" "$DOCKER_IMAGE" "$SERVICE_PORT" "$GPU_ENABLED" "$ENV_VARS" > "$compose_file"
            ;;
        "web-ui")
            web_ui_template "$SERVICE_NAME" "$DOCKER_IMAGE" "$SERVICE_PORT" "$URL_PATH" "$ENV_VARS" > "$compose_file"
            ;;
        "database")
            database_template "$SERVICE_NAME" "$DOCKER_IMAGE" "$SERVICE_PORT" "$DB_USER" "$DB_PASSWORD" "$DB_NAME" > "$compose_file"
            ;;
        "custom")
            custom_template "$COMPOSE_FILE_PATH" > "$compose_file"
            ;;
    esac
    
    success "Generated: $compose_file"
    
    # Show the generated file
    echo "" | tee -a "$LOG_FILE"
    info "Generated docker-compose.yml:"
    echo "────────────────────────────────────────" | tee -a "$LOG_FILE"
    cat "$compose_file" | tee -a "$LOG_FILE"
    echo "────────────────────────────────────────" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# ============================================================================
# Create Data Directories
# ============================================================================

create_data_directories() {
    info "Creating data directories..."
    
    local data_dir="${PROJECT_ROOT}/data/${SERVICE_NAME}"
    mkdir -p "$data_dir"
    
    # Additional directories for specific types
    case $SERVICE_TYPE in
        "ai-model")
            mkdir -p "${data_dir}/models"
            success "Created models directory"
            ;;
        "database")
            chmod 700 "$data_dir"
            success "Set secure permissions on database directory"
            ;;
    esac
    
    success "Data directories created: $data_dir"
}

# ============================================================================
# Update NGINX Configuration
# ============================================================================

update_nginx_config() {
    if [[ $SERVICE_TYPE != "web-ui" ]]; then
        return 0
    fi
    
    info "Updating NGINX configuration for reverse proxy..."
    
    local nginx_config="${PROJECT_ROOT}/stacks/nginx/conf.d/${SERVICE_NAME}.conf"
    
    cat > "$nginx_config" << EOF
# ${SERVICE_NAME} reverse proxy configuration
location /${URL_PATH}/ {
    proxy_pass http://${SERVICE_NAME}:${SERVICE_PORT}/;
    proxy_http_version 1.1;
    
    # WebSocket support
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    
    # Standard proxy headers
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    
    # Timeouts
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    
    # Buffer settings
    proxy_buffering off;
    proxy_request_buffering off;
}
EOF
    
    success "NGINX configuration created: $nginx_config"
    
    # Reload NGINX
    if docker ps --filter "name=nginx" --filter "status=running" --format '{{.Names}}' | grep -q "nginx"; then
        info "Reloading NGINX..."
        docker exec nginx nginx -s reload 2>&1 | tee -a "$LOG_FILE"
        success "NGINX reloaded"
    else
        warn "NGINX not running. Configuration will be applied on next start."
    fi
}

# ============================================================================
# Update Environment File
# ============================================================================

update_env_file() {
    info "Updating .env file..."
    
    local env_file="${PROJECT_ROOT}/.env"
    
    # Add service-specific variables
    {
        echo ""
        echo "# ${SERVICE_NAME} configuration"
        echo "${SERVICE_NAME^^}_PORT=${SERVICE_PORT}"
        
        if [[ $SERVICE_TYPE == "database" ]]; then
            echo "${SERVICE_NAME^^}_USER=${DB_USER}"
            echo "${SERVICE_NAME^^}_PASSWORD=${DB_PASSWORD}"
            echo "${SERVICE_NAME^^}_NAME=${DB_NAME}"
        fi
        
        if [[ $SERVICE_TYPE == "web-ui" ]]; then
            echo "${SERVICE_NAME^^}_URL_PATH=${URL_PATH}"
        fi
    } >> "$env_file"
    
    success "Environment file updated"
}

# ============================================================================
# Deploy Service
# ============================================================================

deploy_service() {
    echo "" | tee -a "$LOG_FILE"
    prompt "Deploy the service now? [Y/n]:"
    read -r deploy_choice
    
    if [[ $deploy_choice =~ ^[Nn]$ ]]; then
        info "Skipping deployment. Deploy later with:"
        echo "  cd ${PROJECT_ROOT}/stacks/${SERVICE_NAME}"
        echo "  docker compose up -d"
        return 0
    fi
    
    info "Deploying ${SERVICE_NAME}..."
    
    cd "${PROJECT_ROOT}/stacks/${SERVICE_NAME}"
    
    if docker compose up -d 2>&1 | tee -a "$LOG_FILE"; then
        success "Service deployed successfully"
        
        # Wait for container to start
        sleep 5
        
        # Check status
        if docker ps --filter "name=${SERVICE_NAME}" --filter "status=running" --format '{{.Names}}' | grep -q "${SERVICE_NAME}"; then
            success "Service ${SERVICE_NAME} is running"
            
            # Show access information
            echo "" | tee -a "$LOG_FILE"
            info "Service access information:"
            echo "  • Container: ${SERVICE_NAME}" | tee -a "$LOG_FILE"
            echo "  • Port: ${SERVICE_PORT}" | tee -a "$LOG_FILE"
            
            if [[ $SERVICE_TYPE == "web-ui" ]]; then
                local tailscale_ip
                tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "localhost")
                echo "  • URL: https://${tailscale_ip}:8443/${URL_PATH}" | tee -a "$LOG_FILE"
            fi
            
            if [[ $SERVICE_TYPE == "database" ]]; then
                echo "  • Username: ${DB_USER}" | tee -a "$LOG_FILE"
                echo "  • Password: ${DB_PASSWORD}" | tee -a "$LOG_FILE"
                echo "  • Database: ${DB_NAME}" | tee -a "$LOG_FILE"
            fi
            
        else
            error "Service failed to start. Check logs:"
            echo "  docker logs ${SERVICE_NAME}"
        fi
    else
        error "Deployment failed"
        return 1
    fi
}

# ============================================================================
# Create Systemd Service
# ============================================================================

create_systemd_service() {
    echo "" | tee -a "$LOG_FILE"
    prompt "Create systemd service for auto-start on boot? [Y/n]:"
    read -r systemd_choice
    
    if [[ $systemd_choice =~ ^[Nn]$ ]]; then
        info "Skipping systemd service creation"
        return 0
    fi
    
    info "Creating systemd service..."
    
    local service_file="/etc/systemd/system/aiplatform-${SERVICE_NAME}.service"
    
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=AI Platform - ${SERVICE_NAME}
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${PROJECT_ROOT}/stacks/${SERVICE_NAME}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable "aiplatform-${SERVICE_NAME}.service" 2>&1 | tee -a "$LOG_FILE"
    
    success "Systemd service created and enabled"
    
    info "Service management commands:"
    echo "  • Start:   sudo systemctl start aiplatform-${SERVICE_NAME}" | tee -a "$LOG_FILE"
    echo "  • Stop:    sudo systemctl stop aiplatform-${SERVICE_NAME}" | tee -a "$LOG_FILE"
    echo "  • Status:  sudo systemctl status aiplatform-${SERVICE_NAME}" | tee -a "$LOG_FILE"
    echo "  • Disable: sudo systemctl disable aiplatform-${SERVICE_NAME}" | tee -a "$LOG_FILE"
}

# ============================================================================
# Generate Configuration Template
# ============================================================================

generate_config_template() {
    local config_dir="${PROJECT_ROOT}/data/${SERVICE_NAME}/config"
    mkdir -p "$config_dir"
    
    local config_file="${config_dir}/README.md"
    
    cat > "$config_file" << EOF
# ${SERVICE_NAME} Configuration

## Service Information
- **Type**: ${SERVICE_TYPE}
- **Image**: ${DOCKER_IMAGE}
- **Port**: ${SERVICE_PORT}
- **Data Directory**: ${PROJECT_ROOT}/data/${SERVICE_NAME}

## Access Information
EOF
    
    if [[ $SERVICE_TYPE == "web-ui" ]]; then
        cat >> "$config_file" << EOF

### Web Interface
- **URL Path**: /${URL_PATH}
- **Tailscale URL**: https://\$(tailscale ip -4):8443/${URL_PATH}
EOF
    fi
    
    if [[ $SERVICE_TYPE == "database" ]]; then
        cat >> "$config_file" << EOF

### Database Credentials
- **Username**: ${DB_USER}
- **Password**: ${DB_PASSWORD}
- **Database**: ${DB_NAME}
- **Connection String**: 
  \`\`\`
  postgresql://${DB_USER}:${DB_PASSWORD}@${SERVICE_NAME}:${SERVICE_PORT}/${DB_NAME}
  \`\`\`
EOF
    fi
    
    cat >> "$config_file" << EOF

## Integration with Other Services
This service has access to:
- Google Drive sync: \`/gdrive\` (read-only)
- AI Platform network: Can communicate with other services

## Docker Commands
\`\`\`bash
# View logs
docker logs ${SERVICE_NAME} -f

# Restart service
docker restart ${SERVICE_NAME}

# Update service
cd ${PROJECT_ROOT}/stacks/${SERVICE_NAME}
docker compose pull
docker compose up -d

# Remove service
docker compose down
docker volume rm ${SERVICE_NAME}_data  # if applicable
\`\`\`

## Notes
- Created on: $(date)
- Log file: ${LOG_FILE}
EOF
    
    success "Configuration documentation created: $config_file"
}

# ============================================================================
# Display Summary
# ============================================================================

display_summary() {
    echo "" | tee -a "$LOG_FILE"
    echo "╔════════════════════════════════════════════════════════════╗" | tee -a "$LOG_FILE"
    echo "║                Service Addition Complete                   ║" | tee -a "$LOG_FILE"
    echo "╚════════════════════════════════════════════════════════════╝" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    success "Service '${SERVICE_NAME}' has been added to the platform!"
    echo "" | tee -a "$LOG_FILE"
    
    info "Service Details:" | tee -a "$LOG_FILE"
    echo "  • Name: ${SERVICE_NAME}" | tee -a "$LOG_FILE"
    echo "  • Type: ${SERVICE_TYPE}" | tee -a "$LOG_FILE"
    echo "  • Image: ${DOCKER_IMAGE}" | tee -a "$LOG_FILE"
    echo "  • Port: ${SERVICE_PORT}" | tee -a "$LOG_FILE"
    
    if [[ $SERVICE_TYPE == "web-ui" ]]; then
        local tailscale_ip
        tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "localhost")
        echo "  • URL: https://${tailscale_ip}:8443/${URL_PATH}" | tee -a "$LOG_FILE"
    fi
    
    echo "" | tee -a "$LOG_FILE"
    
    info "Files Created:" | tee -a "$LOG_FILE"
    echo "  • Docker Compose: ${PROJECT_ROOT}/stacks/${SERVICE_NAME}/docker-compose.yml" | tee -a "$LOG_FILE"
    echo "  • Data Directory: ${PROJECT_ROOT}/data/${SERVICE_NAME}" | tee -a "$LOG_FILE"
    echo "  • Config Documentation: ${PROJECT_ROOT}/data/${SERVICE_NAME}/config/README.md" | tee -a "$LOG_FILE"
    
    if [[ $SERVICE_TYPE == "web-ui" ]]; then
        echo "  • NGINX Config: ${PROJECT_ROOT}/stacks/nginx/conf.d/${SERVICE_NAME}.conf" | tee -a "$LOG_FILE"
    fi
    
    echo "" | tee -a "$LOG_FILE"
    
    info "Next Steps:" | tee -a "$LOG_FILE"
    echo "  1. Check service logs: docker logs ${SERVICE_NAME} -f" | tee -a "$LOG_FILE"
    echo "  2. Configure service-specific settings in: ${PROJECT_ROOT}/data/${SERVICE_NAME}/config" | tee -a "$LOG_FILE"
    
    if [[ $SERVICE_TYPE == "web-ui" ]]; then
        echo "  3. Access web interface at: /${URL_PATH}" | tee -a "$LOG_FILE"
    fi
    
    echo "" | tee -a "$LOG_FILE"
    info "Log file saved to: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# ============================================================================
# Cleanup on Error
# ============================================================================

cleanup_on_error() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        error "Script failed with exit code: $exit_code"
        
        prompt "Do you want to remove partially created files? [y/N]:"
        read -r cleanup_choice
        
        if [[ $cleanup_choice =~ ^[Yy]$ ]]; then
            warn "Cleaning up..."
            
            # Stop and remove container if running
            if docker ps -a --filter "name=${SERVICE_NAME}" --format '{{.Names}}' | grep -q "${SERVICE_NAME}"; then
                docker stop "${SERVICE_NAME}" 2>/dev/null
                docker rm "${SERVICE_NAME}" 2>/dev/null
            fi
            
            # Remove stack directory
            if [[ -d "${PROJECT_ROOT}/stacks/${SERVICE_NAME}" ]]; then
                rm -rf "${PROJECT_ROOT}/stacks/${SERVICE_NAME}"
            fi
            
            # Remove NGINX config
            if [[ -f "${PROJECT_ROOT}/stacks/nginx/conf.d/${SERVICE_NAME}.conf" ]]; then
                rm -f "${PROJECT_ROOT}/stacks/nginx/conf.d/${SERVICE_NAME}.conf"
            fi
            
            # Remove systemd service
            if [[ -f "/etc/systemd/system/aiplatform-${SERVICE_NAME}.service" ]]; then
                sudo systemctl disable "aiplatform-${SERVICE_NAME}.service" 2>/dev/null
                sudo rm -f "/etc/systemd/system/aiplatform-${SERVICE_NAME}.service"
                sudo systemctl daemon-reload
            fi
            
            success "Cleanup complete"
        fi
    fi
}

trap cleanup_on_error EXIT

# ============================================================================
# Main Execution
# ============================================================================

main() {
    setup_logging
    display_banner
    load_environment
    
    # Collect information
    if ! collect_service_info; then
        error "Failed to collect service information"
        exit 1
    fi
    
    # Generate compose file
    generate_compose_file
    
    # Create data directories
    create_data_directories
    
    # Update NGINX if web-ui
    if [[ $SERVICE_TYPE == "web-ui" ]]; then
        update_nginx_config
    fi
    
    # Update environment file
    update_env_file
    
    # Generate config template
    generate_config_template
    
    # Deploy service
    deploy_service
    
    # Create systemd service
    create_systemd_service
    
    # Display summary
    display_summary
}

main "$@"
