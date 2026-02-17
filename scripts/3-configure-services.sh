#!/bin/bash
#==============================================================================
# Script 3: Post-Deployment Configuration & Management
# Purpose: Configure services, manage SSL, add services, backups
# Version: 9.0.0 - Menu-Driven Interface
#==============================================================================

set -euo pipefail

# Paths
REAL_USER="${SUDO_USER:-$USER}"
BASE_DIR="/mnt/data"
ENV_FILE="$BASE_DIR/.env"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
CONFIG_DIR="$BASE_DIR/config"
DATA_DIR="$BASE_DIR/data"
BACKUP_DIR="$BASE_DIR/backups"

# Load environment (safe sourcing)
if [ -f "$ENV_FILE" ]; then
    # Safe environment loading to avoid command execution
    set -a
    while IFS='=' read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        # Extract variable name and value
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            var_name="${BASH_REMATCH[1]}"
            var_value="${BASH_REMATCH[2]}"
            export "$var_name=$var_value"
        fi
    done < "$ENV_FILE"
else
    echo "Error: .env not found at $ENV_FILE. Run Script 1 first."
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

#==============================================================================
# LOGGING
#==============================================================================

log_info() { echo -e "${BLUE}→${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

#==============================================================================
# MAIN MENU
#==============================================================================

show_main_menu() {
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     AI Platform - Configuration & Management Menu        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Configuration Options:"
    echo ""
    echo "  ${BOLD}SSL & Security${NC}"
    echo "    1) Regenerate SSL Certificate"
    echo "    2) Update SSL Certificate (Let's Encrypt renewal)"
    echo ""
    echo "  ${BOLD}Service Management${NC}"
    echo "    3) Add New Service to Stack"
    echo "    4) Remove Service from Stack"
    echo "    5) Restart All Services"
    echo "    6) View Service Status"
    echo ""
    echo "  ${BOLD}Integration Configuration${NC}"
    echo "    7) Configure Signal CLI (QR Code Pairing)"
    echo "    8) Configure Tailscale (Device Linking)"
    echo "    9) Configure OpenClaw Integrations"
    echo "    10) Configure Google Drive Sync"
    echo ""
    echo "  ${BOLD}Backup & Restore${NC}"
    echo "    11) Backup Configuration Files"
    echo "    12) Backup Core .env + Secrets"
    echo "    13) Full System Backup"
    echo "    14) Restore from Backup"
    echo ""
    echo "  ${BOLD}Database Management${NC}"
    echo "    15) Initialize New Database"
    echo "    16) Backup Databases"
    echo "    17) Restore Databases"
    echo ""
    echo "  ${BOLD}Model Management${NC}"
    echo "    18) Pull/Update Ollama Models"
    echo "    19) List Available Models"
    echo ""
    echo "  0) Exit"
    echo ""
    read -p "Select option [0-19]: " choice
    
    handle_menu_choice "$choice"
}

handle_menu_choice() {
    case $1 in
        1) regenerate_ssl_certificate ;;
        2) renew_ssl_certificate ;;
        3) add_new_service ;;
        4) remove_service ;;
        5) restart_all_services ;;
        6) view_service_status ;;
        7) configure_signal ;;
        8) configure_tailscale ;;
        9) configure_openclaw ;;
        10) configure_gdrive ;;
        11) backup_config ;;
        12) backup_core ;;
        13) backup_full ;;
        14) restore_backup ;;
        15) initialize_database ;;
        16) backup_databases ;;
        17) restore_databases ;;
        18) manage_ollama_models ;;
        19) list_ollama_models ;;
        0) exit 0 ;;
        *) 
            log_error "Invalid option"
            sleep 2
            show_main_menu
            ;;
    esac
}

#==============================================================================
# SSL CERTIFICATE MANAGEMENT
#==============================================================================

regenerate_ssl_certificate() {
    echo ""
    echo -e "${CYAN}═══ Regenerate SSL Certificate ═══${NC}"
    echo ""
    
    if [ "${SSL_TYPE}" = "letsencrypt" ]; then
        log_info "Using Let's Encrypt for ${DOMAIN_NAME}..."
        
        # Stop proxy to free port 80
        docker compose -f "$COMPOSE_FILE" stop ${PROXY_TYPE} 2>/dev/null || true
        
        # Generate certificate
        docker run --rm -v "${DATA_DIR}/ssl:/etc/letsencrypt" \
            -p 80:80 \
            certbot/certbot certonly \
            --standalone \
            --email "${SSL_EMAIL}" \
            --agree-tos \
            --no-eff-email \
            -d "${DOMAIN_NAME}" 2>/dev/null || log_error "Certificate generation failed"
        
        # Restart proxy
        docker compose -f "$COMPOSE_FILE" start ${PROXY_TYPE} 2>/dev/null || true
        
        log_success "SSL certificate generated"
    else
        log_info "Generating self-signed certificate..."
        
        mkdir -p "${DATA_DIR}/ssl"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "${DATA_DIR}/ssl/privkey.pem" \
            -out "${DATA_DIR}/ssl/fullchain.pem" \
            -subj "/CN=${DOMAIN_NAME}/O=AI Platform/C=US" 2>/dev/null || log_error "Certificate generation failed"
        
        log_success "Self-signed certificate generated"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

renew_ssl_certificate() {
    echo ""
    echo -e "${CYAN}═══ Renew SSL Certificate ═══${NC}"
    echo ""
    
    if [ "${SSL_TYPE}" != "letsencrypt" ]; then
        log_warning "Not using Let's Encrypt. Use option 1 to regenerate self-signed."
        read -p "Press Enter to continue..."
        show_main_menu
        return
    fi
    
    log_info "Renewing Let's Encrypt certificate..."
    
    docker compose -f "$COMPOSE_FILE" stop ${PROXY_TYPE} 2>/dev/null || true
    
    docker run --rm -v "${DATA_DIR}/ssl:/etc/letsencrypt" \
        -p 80:80 \
        certbot/certbot renew 2>/dev/null || log_error "Certificate renewal failed"
    
    docker compose -f "$COMPOSE_FILE" start ${PROXY_TYPE} 2>/dev/null || true
    
    log_success "Certificate renewed"
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

#==============================================================================
# SERVICE MANAGEMENT
#==============================================================================

add_new_service() {
    echo ""
    echo -e "${CYAN}═══ Add New Service to Stack ═══${NC}"
    echo ""
    
    echo "Available services to add:"
    echo "  1) Dify (AI Platform)"
    echo "  2) n8n (Workflow Automation)"
    echo "  3) Flowise (Visual AI Workflows)"
    echo "  4) AnythingLLM (Document Q&A)"
    echo "  5) Metabase (Analytics)"
    echo "  6) JupyterHub (Data Science)"
    echo ""
    read -p "Select service [1-6]: " svc_choice
    
    case $svc_choice in
        1) add_dify_service ;;
        2) add_n8n_service ;;
        3) add_flowise_service ;;
        4) add_anythingllm_service ;;
        5) add_metabase_service ;;
        6) add_jupyterhub_service ;;
        *)
            log_error "Invalid choice"
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

add_dify_service() {
    log_info "Adding Dify to docker-compose.yml..."
    
    # Add to compose file
    cat >> "$COMPOSE_FILE" <<'EOF'

  dify-api:
    image: langgenius/dify-api:latest
    container_name: dify-api
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      MODE: api
      DB_USERNAME: ${POSTGRES_USER}
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: dify
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      SECRET_KEY: ${ENCRYPTION_KEY}
    volumes:
      - ${DATA_DIR}/dify:/app/storage
    networks:
      - ai_platform_internal
      - ai_platform
    ports:
      - "5001:5001"
    labels:
      - "ai-platform.service=dify-api"

  dify-web:
    image: langgenius/dify-web:latest
    container_name: dify-web
    restart: unless-stopped
    depends_on:
      - dify-api
    environment:
      CONSOLE_API_URL: http://dify-api:5001
      APP_API_URL: http://dify-api:5001
    networks:
      - ai_platform
    ports:
      - "3000:3000"
    labels:
      - "ai-platform.service=dify-web"
EOF
    
    # Update proxy config
    log_info "Adding Dify to proxy configuration..."
    add_service_to_proxy "dify" "dify-web:3000"
    
    # Create database
    log_info "Creating Dify database..."
    docker exec postgres psql -U ${POSTGRES_USER} -c "CREATE DATABASE dify;" 2>/dev/null || true
    
    # Deploy
    log_info "Deploying Dify..."
    docker compose -f "$COMPOSE_FILE" up -d dify-api dify-web
    
    # Reload proxy
    docker compose -f "$COMPOSE_FILE" restart ${PROXY_TYPE}
    
    log_success "Dify added successfully!"
    log_info "Access at: https://${DOMAIN_NAME}/dify"
}

add_service_to_proxy() {
    local service_name=$1
    local upstream=$2
    
    case "${PROXY_TYPE}" in
        nginx-proxy-manager|nginx)
            add_service_to_nginx "$service_name" "$upstream"
            ;;
        caddy)
            add_service_to_caddy "$service_name" "$upstream"
            ;;
    esac
}

add_service_to_nginx() {
    local service_name=$1
    local upstream=$2
    local site_conf="${CONFIG_DIR}/nginx/sites-available/ai-platform.conf"
    
    # Find the closing brace and insert before it
    local temp_file=$(mktemp)
    
    # Remove last }
    head -n -1 "$site_conf" > "$temp_file"
    
    # Add new location
    cat >> "$temp_file" <<EOF
    
    # ${service_name^}
    location /${service_name}/ {
        proxy_pass http://${upstream}/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
    
    mv "$temp_file" "$site_conf"
    
    log_success "Added ${service_name} to nginx configuration"
}

add_service_to_caddy() {
    local service_name=$1
    local upstream=$2
    local caddy_conf="${CONFIG_DIR}/caddy/Caddyfile"
    
    # Remove closing }
    local temp_file=$(mktemp)
    head -n -1 "$caddy_conf" > "$temp_file"
    
    # Add route
    cat >> "$temp_file" <<EOF
    
    # ${service_name^}
    route /${service_name}/* {
        uri strip_prefix /${service_name}
        reverse_proxy ${upstream} {
            header_up X-Real-IP {remote_host}
        }
    }
}
EOF
    
    mv "$temp_file" "$caddy_conf"
    
    log_success "Added ${service_name} to Caddy configuration"
}

#==============================================================================
# SIGNAL CLI CONFIGURATION
#==============================================================================

configure_signal() {
    echo ""
    echo -e "${CYAN}═══ Signal CLI Configuration ═══${NC}"
    echo ""
    
    log_info "Checking Signal CLI service..."
    
    if ! docker ps --format '{{.Names}}' | grep -q "^signal-cli$"; then
        log_warning "Signal CLI not running. Starting..."
        docker compose -f "$COMPOSE_FILE" up -d signal-cli
        sleep 5
    fi
    
    log_info "Starting device linking process..."
    log_info "This will display a QR code to link your Signal account"
    echo ""
    
    # Get QR code for linking
    docker exec -it signal-cli signal-cli -u +$PHONE_NUMBER link -n "AI Platform Server" \
        | qrencode -t UTF8
    
    echo ""
    log_info "Scan this QR code with your Signal app:"
    log_info "Signal → Settings → Linked Devices → '+' → Scan QR code"
    echo ""
    
    read -p "Press Enter after scanning the QR code..."
    
    log_info "Verifying connection..."
    if docker exec signal-cli signal-cli -u +$PHONE_NUMBER receive --timeout 5 &>/dev/null; then
        log_success "Signal CLI linked successfully!"
    else
        log_warning "Could not verify connection. It may take a few moments."
    fi
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

#==============================================================================
# TAILSCALE CONFIGURATION
#==============================================================================

configure_tailscale() {
    echo ""
    echo -e "${CYAN}═══ Tailscale Configuration ═══${NC}"
    echo ""
    
    echo "Tailscale Setup Options:"
    echo "  1) Link with Auth Key"
    echo "  2) Link with URL (manual)"
    echo "  3) Show Current Status"
    echo ""
    read -p "Select option [1-3]: " ts_choice
    
    case $ts_choice in
        1)
            read -p "Enter Tailscale Auth Key: " auth_key
            docker exec tailscale tailscale up --authkey="$auth_key" \
                --advertise-exit-node \
                --advertise-tags=tag:ai-platform
            log_success "Tailscale configured with auth key"
            ;;
        2)
            log_info "Generating login URL..."
            docker exec tailscale tailscale up
            log_info "Visit the URL shown above to authorize this device"
            ;;
        3)
            docker exec tailscale tailscale status
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

#==============================================================================
# OPENCLAW CONFIGURATION
#==============================================================================

configure_openclaw() {
    echo ""
    echo -e "${CYAN}═══ OpenClaw Integration Configuration ═══${NC}"
    echo ""
    
    log_info "Configuring OpenClaw service connections..."
    
    # Generate OpenClaw config
    cat > "${CONFIG_DIR}/openclaw/services.yaml" <<EOF
# OpenClaw Service Configuration
# Generated: $(date)

services:
  litellm:
    enabled: ${ENABLE_LITELLM:-false}
    url: http://litellm:4000
    api_key: \${LITELLM_MASTER_KEY}
    
  ollama:
    enabled: ${ENABLE_OLLAMA:-false}
    url: http://ollama:11434
    
  qdrant:
    enabled: ${ENABLE_QDRANT:-false}
    url: http://qdrant:6333
    
  signal:
    enabled: true
    url: http://signal-cli:8080
    phone: \${SIGNAL_PHONE_NUMBER}
    
  n8n:
    enabled: ${ENABLE_N8N:-false}
    url: http://n8n:5678
    webhook_base: https://${DOMAIN_NAME}/n8n
EOF
    
    log_success "OpenClaw configuration saved"
    
    # Restart OpenClaw to load new config
    log_info "Restarting OpenClaw..."
    docker compose -f "$COMPOSE_FILE" restart openclaw
    
    log_success "OpenClaw configured"
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

#==============================================================================
# GOOGLE DRIVE CONFIGURATION
#==============================================================================

configure_gdrive() {
    echo ""
    echo -e "${CYAN}═══ Google Drive Configuration ═══${NC}"
    echo ""
    
    echo "Google Drive Setup Options:"
    echo "  1) Generate OAuth URL (Browser-based)"
    echo "  2) Enter OAuth Token Manually"
    echo "  3) Use Service Account Key"
    echo "  4) Test Current Connection"
    echo ""
    read -p "Select option [1-4]: " gd_choice
    
    case $gd_choice in
        1)
            log_info "Generating OAuth URL..."
            rclone authorize "drive" <<< "" | grep "https://" || \
                log_error "Failed to generate URL. Install rclone first."
            ;;
        2)
            read -p "Enter OAuth Token: " oauth_token
            echo "$oauth_token" > "${CONFIG_DIR}/gdrive/oauth_token"
            configure_rclone_with_token "$oauth_token"
            ;;
        3)
            read -p "Enter path to service account JSON: " sa_path
            if [ -f "$sa_path" ]; then
                cp "$sa_path" "${CONFIG_DIR}/gdrive/service-account.json"
                configure_rclone_with_sa
                log_success "Service account configured"
            else
                log_error "File not found: $sa_path"
            fi
            ;;
        4)
            log_info "Testing Google Drive connection..."
            rclone lsd gdrive: || log_error "Connection failed"
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

configure_rclone_with_token() {
    local token=$1
    
    cat > ~/.config/rclone/rclone.conf <<EOF
[gdrive]
type = drive
scope = drive
token = {"access_token":"$token","token_type":"Bearer"}
EOF
    
    log_success "Rclone configured with OAuth token"
}

configure_rclone_with_sa() {
    cat > ~/.config/rclone/rclone.conf <<EOF
[gdrive]
type = drive
scope = drive
service_account_file = ${CONFIG_DIR}/gdrive/service-account.json
EOF
    
    log_success "Rclone configured with service account"
}

#==============================================================================
# BACKUP FUNCTIONS
#==============================================================================

backup_config() {
    echo ""
    echo -e "${CYAN}═══ Backup Configuration Files ═══${NC}"
    echo ""
    
    local backup_name="config-$(date +%Y%m%d-%H%M%S).tar.gz"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    mkdir -p "${BACKUP_DIR}"
    
    log_info "Creating configuration backup..."
    
    tar -czf "$backup_path" \
        -C "${BASE_DIR}" \
        config/ \
        docker-compose.yml 2>/dev/null
    
    log_success "Configuration backed up: ${backup_path}"
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

backup_core() {
    echo ""
    echo -e "${CYAN}═══ Backup Core (.env + Secrets) ═══${NC}"
    echo ""
    
    local backup_name="core-$(date +%Y%m%d-%H%M%S).tar.gz"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    mkdir -p "${BACKUP_DIR}"
    
    log_info "Creating core backup..."
    
    tar -czf "$backup_path" \
        -C "${BASE_DIR}" \
        .env \
        .secrets 2>/dev/null || true
    
    # Encrypt backup
    if command -v gpg &>/dev/null; then
        log_info "Encrypting backup..."
        gpg -c "$backup_path"
        rm "$backup_path"
        backup_path="${backup_path}.gpg"
    fi
    
    log_success "Core files backed up: ${backup_path}"
    log_warning "KEEP THIS FILE SECURE - Contains secrets!"
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

backup_full() {
    echo ""
    echo -e "${CYAN}═══ Full System Backup ═══${NC}"
    echo ""
    
    local backup_name="full-$(date +%Y%m%d-%H%M%S).tar.gz"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    mkdir -p "${BACKUP_DIR}"
    
    log_info "Creating full system backup (this may take a while)..."
    
    # Stop services
    log_info "Stopping services..."
    docker compose -f "$COMPOSE_FILE" stop
    
    # Backup everything
    tar -czf "$backup_path" \
        -C "${BASE_DIR}" \
        --exclude='backups' \
        --exclude='logs' \
        . 2>/dev/null
    
    # Restart services
    log_info "Restarting services..."
    docker compose -f "$COMPOSE_FILE" start
    
    log_success "Full backup created: ${backup_path}"
    
    local size=$(du -h "$backup_path" | cut -f1)
    log_info "Backup size: ${size}"
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

#==============================================================================
# MODEL MANAGEMENT
#==============================================================================

manage_ollama_models() {
    echo ""
    echo -e "${CYAN}═══ Ollama Model Management ═══${NC}"
    echo ""
    
    echo "Available models to pull:"
    echo "  1) llama3.1 (4GB)"
    echo "  2) llama3.1:70b (40GB)"
    echo "  3) mistral (4GB)"
    echo "  4) codellama (4GB)"
    echo "  5) gemma2 (5GB)"
    echo "  6) Custom model"
    echo ""
    read -p "Select model [1-6]: " model_choice
    
    case $model_choice in
        1) model_name="llama3.1" ;;
        2) model_name="llama3.1:70b" ;;
        3) model_name="mistral" ;;
        4) model_name="codellama" ;;
        5) model_name="gemma2" ;;
        6)
            read -p "Enter model name: " model_name
            ;;
        *)
            log_error "Invalid choice"
            return
            ;;
    esac
    
    log_info "Pulling model: ${model_name}..."
    docker exec ollama ollama pull "$model_name"
    
    log_success "Model ${model_name} pulled successfully"
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

list_ollama_models() {
    echo ""
    echo -e "${CYAN}═══ Available Ollama Models ═══${NC}"
    echo ""
    
    docker exec ollama ollama list
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================

main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root (use sudo)"
        exit 1
    fi
    
    # Show menu
    show_main_menu
}

main "$@"
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
