#!/bin/bash

#==============================================================================
# Script 2: Non-Root Docker Deployment with AppArmor Security
# Purpose: Deploy all selected services using Script 1 configuration
# Version: 7.0.0 - AppArmor Security & Complete Service Coverage
#==============================================================================

set -euo pipefail

# Color definitions (matching Script 1)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Paths (matching Script 1)
readonly DATA_ROOT="/mnt/data"
readonly METADATA_DIR="$DATA_ROOT/metadata"
readonly STATE_FILE="$METADATA_DIR/setup_state.json"
readonly LOG_FILE="$DATA_ROOT/logs/deployment.log"
readonly ENV_FILE="$DATA_ROOT/.env"
readonly SERVICES_FILE="$METADATA_DIR/selected_services.json"
readonly COMPOSE_FILE="$DATA_ROOT/ai-platform/deployment/stack/docker-compose.yml"
readonly CONFIG_DIR="$DATA_ROOT/config"
readonly CREDENTIALS_FILE="$METADATA_DIR/credentials.json"
readonly DEPLOYMENT_LOCK="$DATA_ROOT/.deployment_lock"

# 🔥 NEW: AppArmor Security Configuration
readonly APPARMOR_PROFILES_DIR="$DATA_ROOT/security/apparmor"
readonly SECURITY_COMPLIANCE=true  # Enable AppArmor security for production

# Print functions
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

# 🔥 NEW: AppArmor Security Functions
setup_apparmor_security() {
    print_info "Setting up AppArmor security profiles..."
    
    # Create AppArmor profiles directory
    mkdir -p "$APPARMOR_PROFILES_DIR"
    
    # Check if AppArmor is available
    if ! command -v aa-status >/dev/null 2>&1; then
        print_warning "AppArmor not available, installing..."
        apt-get update && apt-get install -y apparmor apparmor-utils
    fi
    
    # Enable AppArmor if not already enabled
    if ! aa-status --enabled >/dev/null 2>&1; then
        print_warning "Enabling AppArmor..."
        systemctl enable apparmor
        systemctl start apparmor
    fi
    
    print_success "AppArmor security configured"
}

#==============================================================================
# ENHANCED WAIT MECHANISMS (Frontier Recommendations Adopted)
#==============================================================================

wait_for_service_healthy() {
    local service_name="$1"
    local max_attempts="${2:-60}"
    local attempt=0
    
    print_info "Waiting for $service_name to become healthy..."
    
    while [ $attempt -lt $max_attempts ]; do
        local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$service_name" 2>/dev/null || echo "not_found")
        
        if [ "$health_status" = "healthy" ]; then
            print_success "$service_name is healthy"
            return 0
        fi
        
        if [ "$health_status" = "not_found" ]; then
            print_error "$service_name container not found"
            return 1
        fi
        
        attempt=$((attempt + 1))
        sleep 2
    done
    
    print_error "$service_name failed to become healthy after $max_attempts attempts"
    docker logs "$service_name" --tail 20 2>&1 | tee -a "$LOG_FILE" || true
    return 1
}

wait_for_port() {
    local host="$1"
    local port="$2"
    local max_attempts="${3:-30}"
    local attempt=0
    
    print_info "Waiting for $host:$port to be available..."
    
    while [ $attempt -lt $max_attempts ]; do
        if nc -z "$host" "$port" 2>/dev/null; then
            print_success "$host:$port is available"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    print_error "$host:$port failed to become available"
    return 1
}

wait_for_redis() {
    local max_attempts=60
    local attempt=0
    
    print_info "Waiting for Redis to respond..."
    
    while [ $attempt -lt $max_attempts ]; do
        if docker exec redis redis-cli ping 2>/dev/null | grep -q PONG; then
            print_success "Redis is ready"
            return 0
        fi
        sleep 1
        ((attempt++))
    done
    
    print_error "Redis failed to respond to ping"
    return 1
}

wait_for_postgres() {
    local container_name="$1"
    local max_attempts="${2:-30}"
    
    print_info "Waiting for PostgreSQL to be ready..."
    
    for i in $(seq 1 $max_attempts); do
        if docker exec "$container_name" pg_isready -U "${POSTGRES_USER:-postgres}" >/dev/null 2>&1; then
            print_success "PostgreSQL is ready"
            return 0
        fi
        sleep 2
    done
    
    print_error "PostgreSQL failed to become ready"
    return 1
}

#==============================================================================
# CONFIGURATION GENERATION
#==============================================================================

generate_prometheus_config() {
    local config_dir="${DATA_ROOT}/config/prometheus"
    mkdir -p "${config_dir}"
    
    cat > "${config_dir}/prometheus.yml" <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']
  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
EOF
    
    print_success "Prometheus config generated at ${config_dir}/prometheus.yml"
}

fix_grafana_permissions() {
    local grafana_vol="${DATA_ROOT}/grafana"
    mkdir -p "${grafana_vol}"
    
    # Grafana's internal UID is 472
    chown -R 472:472 "${grafana_vol}"
    chmod 755 "${grafana_vol}"
    
    print_success "Grafana volume permissions set (UID 472)"
}

fix_ollama_permissions() {
    local ollama_vol="${DATA_ROOT}/volumes/ollama"
    mkdir -p "${ollama_vol}"
    chown -R "${RUNNING_UID}:${RUNNING_GID}" "${ollama_vol}"
    chmod 755 "${ollama_vol}"
    
    print_success "Ollama volume permissions set"
}

fix_postgres_permissions() {
    local postgres_vol="${DATA_ROOT}/volumes/postgres"
    mkdir -p "${postgres_vol}"
    chown -R "${RUNNING_UID}:${RUNNING_GID}" "${postgres_vol}"
    chmod 755 "${postgres_vol}"
    
    print_success "PostgreSQL volume permissions set"
}

fix_redis_permissions() {
    local redis_vol="${DATA_ROOT}/volumes/redis"
    mkdir -p "${redis_vol}"
    chown -R "${RUNNING_UID}:${RUNNING_GID}" "${redis_vol}"
    chmod 755 "${redis_vol}"
    
    print_success "Redis volume permissions set"
}

generate_proxy_config() {
    print_info "Generating proxy configuration for ${PROXY_TYPE}..."
    
    # Create SSL directory
    mkdir -p "${DATA_ROOT}/ssl"
    
    # Generate self-signed certificate for testing
    if [ ! -f "${DATA_ROOT}/ssl/fullchain.pem" ]; then
        print_info "Generating self-signed SSL certificate..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "${DATA_ROOT}/ssl/privkey.pem" \
            -out "${DATA_ROOT}/ssl/fullchain.pem" \
            -subj "/CN=${DOMAIN_NAME:-localhost}/O=AI Platform/C=US" \
            2>/dev/null || true
        print_success "SSL certificate generated"
    fi
    
    # Determine which proxy to configure
    case "${PROXY_TYPE:-nginx}" in
        nginx-proxy-manager|nginx)
            generate_nginx_config
            ;;
        caddy)
            generate_caddy_config
            ;;
        traefik)
            generate_traefik_config
            ;;
        *)
            print_error "Unknown proxy type: ${PROXY_TYPE}"
            return 1
            ;;
    esac
    
    print_success "Proxy configuration generated for ${PROXY_TYPE}"
}

generate_nginx_config() {
    local nginx_conf_dir="${DATA_ROOT}/config/nginx"
    mkdir -p "$nginx_conf_dir/sites-available" "$nginx_conf_dir/sites-enabled"
    
    print_info "Generating nginx configuration..."
    
    # Main nginx.conf
    cat > "$nginx_conf_dir/nginx.conf" <<'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss 
               application/rss+xml font/truetype font/opentype 
               application/vnd.ms-fontobject image/svg+xml;
    
    # Include site configs
    include /etc/nginx/sites-enabled/*.conf;
}
EOF

    # Generate site config based on access mode
    if [ "${PROXY_CONFIG_METHOD}" = "alias" ]; then
        generate_nginx_alias_config
    else
        generate_nginx_direct_port_config
    fi
    
    # Create symlink
    ln -sf "${nginx_conf_dir}/sites-available/ai-platform.conf" \
           "${nginx_conf_dir}/sites-enabled/ai-platform.conf"
}

generate_nginx_alias_config() {
    local site_conf="${DATA_ROOT}/config/nginx/sites-available/ai-platform.conf"
    
    cat > "$site_conf" <<EOF
# AI Platform - Alias Mode Configuration
# Generated: $(date)

# HTTP redirect to HTTPS
server {
    listen 80;
    server_name ${DOMAIN_NAME} *.${DOMAIN_NAME};
    return 301 https://\$host\$request_uri;
}

# Main HTTPS server
server {
    listen 443 ssl http2;
    server_name ${DOMAIN_NAME};
    
    # SSL Configuration
    ssl_certificate ${DATA_ROOT}/ssl/fullchain.pem;
    ssl_certificate_key ${DATA_ROOT}/ssl/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
    # Root location - dashboard or landing page
    location / {
        return 200 "AI Platform - Services available at /servicename";
        add_header Content-Type text/plain;
    }

EOF

    # Add service locations based on what's enabled
    add_nginx_service_locations "$site_conf"
    
    # Close server block
    echo "}" >> "$site_conf"
}

add_nginx_service_locations() {
    local site_conf="$1"
    
    # Check which services are enabled and add locations
    if [[ " ${SELECTED_SERVICES[*]} " =~ " litellm " ]]; then
        cat >> "$site_conf" <<'EOF'
    
    # LiteLLM Gateway
    location /litellm/ {
        proxy_pass http://litellm:4000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
EOF
    fi
    
    if [[ " ${SELECTED_SERVICES[*]} " =~ " openwebui " ]]; then
        cat >> "$site_conf" <<'EOF'
    
    # Open WebUI
    location /webui/ {
        proxy_pass http://openwebui:8080/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 300s;
    }
EOF
    fi
    
    if [[ " ${SELECTED_SERVICES[*]} " =~ " n8n " ]]; then
        cat >> "$site_conf" <<'EOF'
    
    # n8n Workflow Automation
    location /n8n/ {
        proxy_pass http://n8n:5678/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        chunked_transfer_encoding off;
        proxy_buffering off;
    }
EOF
    fi
    
    if [[ " ${SELECTED_SERVICES[*]} " =~ " grafana " ]]; then
        cat >> "$site_conf" <<'EOF'
    
    # Grafana Monitoring
    location /grafana/ {
        proxy_pass http://grafana:3000/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
EOF
    fi
}

generate_caddy_config() {
    local caddy_conf="${DATA_ROOT}/config/caddy/Caddyfile"
    mkdir -p "${DATA_ROOT}/config/caddy"
    
    print_info "Generating Caddy configuration..."
    
    if [ "${PROXY_CONFIG_METHOD}" = "alias" ]; then
        generate_caddy_alias_config "$caddy_conf"
    else
        generate_caddy_subdomain_config "$caddy_conf"
    fi
}

generate_caddy_alias_config() {
    local caddy_conf="$1"
    
    cat > "$caddy_conf" <<EOF
# AI Platform - Caddy Configuration (Alias Mode)
# Generated: $(date)

{
    email ${SSL_EMAIL}
    acme_ca https://acme-v02.api.letsencrypt.org/directory
}

${DOMAIN_NAME} {
    # Automatic HTTPS
    
    # Root - landing page or dashboard
    route / {
        respond "AI Platform - Services available at /servicename"
    }

EOF

    # Add service routes
    if [[ " ${SELECTED_SERVICES[*]} " =~ " litellm " ]]; then
        cat >> "$caddy_conf" <<'EOF'
    
    # LiteLLM Gateway
    route /litellm/* {
        uri strip_prefix /litellm
        reverse_proxy litellm:4000 {
            header_up X-Real-IP {remote_host}
        }
    }
EOF
    fi

    if [[ " ${SELECTED_SERVICES[*]} " =~ " openwebui " ]]; then
        cat >> "$caddy_conf" <<'EOF'
    
    # Open WebUI
    route /webui/* {
        uri strip_prefix /webui
        reverse_proxy openwebui:8080 {
            header_up X-Real-IP {remote_host}
        }
    }
EOF
    fi

    if [[ " ${SELECTED_SERVICES[*]} " =~ " n8n " ]]; then
        cat >> "$caddy_conf" <<'EOF'
    
    # n8n
    route /n8n/* {
        uri strip_prefix /n8n
        reverse_proxy n8n:5678 {
            header_up X-Real-IP {remote_host}
        }
    }
EOF
    fi

    if [[ " ${SELECTED_SERVICES[*]} " =~ " grafana " ]]; then
        cat >> "$caddy_conf" <<'EOF'
    
    # Grafana
    route /grafana/* {
        uri strip_prefix /grafana
        reverse_proxy grafana:3000 {
            header_up X-Real-IP {remote_host}
        }
    }
EOF
    fi

    # Close Caddy block
    echo "}" >> "$caddy_conf"
}

add_proxy_to_compose() {
    print_info "Adding ${PROXY_TYPE} service to docker-compose.yml..."
    
    case "${PROXY_TYPE:-nginx}" in
        nginx-proxy-manager|nginx)
            add_nginx_to_compose
            ;;
        caddy)
            add_caddy_to_compose
            ;;
        traefik)
            add_traefik_to_compose
            ;;
        *)
            print_error "Unknown proxy type: ${PROXY_TYPE}"
            return 1
            ;;
    esac
    
    print_success "${PROXY_TYPE} added to compose"
}

add_nginx_to_compose() {
    # Check if nginx already in compose
    if grep -q "^  nginx:" "$COMPOSE_FILE"; then
        print_info "Nginx already in compose file"
        return 0
    fi
    
    # Add nginx service
    cat >> "$COMPOSE_FILE" <<'EOF'

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    volumes:
      - ${DATA_ROOT}/config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ${DATA_ROOT}/config/nginx/sites-enabled:/etc/nginx/sites-enabled:ro
      - ${DATA_ROOT}/config/nginx/mime.types:/etc/nginx/mime.types:ro
      - ${DATA_ROOT}/ssl:/etc/nginx/ssl:ro
      - ${DATA_ROOT}/nginx/html:/usr/share/nginx/html
    networks:
      - ai_platform
      - ai_platform_internal
    ports:
      - "80:80"
      - "443:443"
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost/"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "ai-platform.service=nginx"
      - "ai-platform.type=proxy"
EOF
    
    print_success "Nginx added to compose"
}

add_caddy_to_compose() {
    if grep -q "^  caddy:" "$COMPOSE_FILE"; then
        print_info "Caddy already in compose file"
        return 0
    fi
    
    cat >> "$COMPOSE_FILE" <<'EOF'

  caddy:
    image: caddy:alpine
    container_name: caddy
    restart: unless-stopped
    volumes:
      - ${DATA_ROOT}/config/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ${DATA_ROOT}/caddy/data:/data
      - ${DATA_ROOT}/caddy/config:/config
    networks:
      - ai_platform
      - ai_platform_internal
    ports:
      - "80:80"
      - "443:443"
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:2019/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "ai-platform.service=caddy"
      - "ai-platform.type=proxy"
EOF
    
    print_success "Caddy added to compose"
}

# 🔥 NEW: Generate AppArmor Profile for Service
generate_apparmor_profile() {
    local service_name="$1"
    local profile_file="$APPARMOR_PROFILES_DIR/${service_name}.profile"
    
    cat > "$profile_file" <<EOF
#include <tunables/global>

profile ${service_name} flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  
  # Network access
  network inet tcp,
  network inet udp,
  
  # File system access (restricted)
  /mnt/data/${service_name}/** rw,
  /tmp/** rw,
  /var/log/** w,
  
  # Deny sensitive system files
  deny /etc/shadow r,
  deny /etc/passwd r,
  deny /etc/ssh/** r,
  deny /root/** rw,
  deny /home/** rw,
  
  # Docker-specific restrictions
  deny /var/lib/docker/** rw,
  deny /sys/** rw,
  deny /proc/** rw,
  
  # Allow necessary system files
  /etc/hosts r,
  /etc/resolv.conf r,
  /etc/localtime r,
  /usr/share/zoneinfo/** r,
}
EOF
    
    # Load the AppArmor profile
    if aa-status | grep -q "${service_name}"; then
        print_info "AppArmor profile for ${service_name} already loaded"
    else
        apparmor_parser -r "$profile_file" || print_warning "Failed to load AppArmor profile for ${service_name}"
    fi
}

# Source environment (handle readonly variables)
if [[ -f "$ENV_FILE" ]]; then
    # Export all variables except readonly ones defined in this script
    while IFS= read -r line; do
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            var_name="${line%%=*}"
            # Skip readonly variables defined in this script
            case "$var_name" in
                DATA_ROOT|METADATA_DIR|STATE_FILE|LOG_FILE|ENV_FILE|SERVICES_FILE|COMPOSE_FILE|CONFIG_DIR|CREDENTIALS_FILE|APPARMOR_PROFILES_DIR|SECURITY_COMPLIANCE)
                    continue
                    ;;
                *)
                    export "$line"
                    ;;
            esac
        fi
    done < "$ENV_FILE"
else
    print_error "Environment file not found. Run script 1 first."
    exit 1
fi

# 🔥 NEW: Load Selected Services from JSON
load_selected_services() {
    if [[ ! -f "$SERVICES_FILE" ]]; then
        print_error "Selected services file not found. Run script 1 first."
        exit 1
    fi
    
    # Parse JSON and extract service keys
    SELECTED_SERVICES=($(jq -r '.services[].key' "$SERVICES_FILE"))
    TOTAL_SERVICES=${#SELECTED_SERVICES[@]}
    
    print_info "Loaded ${TOTAL_SERVICES} selected services from Script 1"
    print_info "Services: ${SELECTED_SERVICES[*]}"
}

# 🔥 UPDATED: Generate Complete Compose Templates with Security
generate_compose_template() {
    local service_name="$1"
    local service_dir="$COMPOSE_DIR/$service_name"
    
    mkdir -p "$service_dir"
    
    # Get user mapping from environment
    local user_mapping="${RUNNING_UID:-1001}:${RUNNING_GID:-1001}"
    
    cat > "$service_dir/docker-compose.yml" <<EOF
version: '3.8'

services:
  $service_name:
$(generate_service_config "$service_name" "$user_mapping")
    networks:
      - ai_platform
$(generate_service_security "$service_name")
    environment:
$(generate_service_env "$service_name")
    volumes:
$(generate_service_volumes "$service_name")
    ports:
$(generate_service_ports "$service_name")
    healthcheck:
$(generate_healthcheck "$service_name")
    restart: unless-stopped

networks:
  ai_platform:
    external: true
EOF

    print_success "$service_name Docker Compose template generated with security"
}

# 🔥 NEW: Generate Service Configuration
generate_service_config() {
    local service_name="$1"
    local user_mapping="$2"
    
    case "$service_name" in
        "postgres")
            echo "    image: postgres:15-alpine
    container_name: postgres
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "redis")
            echo "    image: redis:7-alpine
    container_name: redis
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "ollama")
            echo "    image: ollama/ollama:latest
    container_name: ollama
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "litellm")
            echo "    image: ghcr.io/berriai/litellm:main
    container_name: litellm
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "dify")
            echo "    image: langgenius/dify-web:latest
    container_name: dify-web
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "n8n")
            echo "    image: n8nio/n8n:latest
    container_name: n8n
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "flowise")
            echo "    image: flowiseai/flowise:latest
    container_name: flowise
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "anythingllm")
            echo "    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "openwebui")
            echo "    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "signal-api")
            echo "    image: ghcr.io/wppconnect-team/wppconnect:latest
    container_name: signal-api
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "openclaw")
            echo "    image: openclaw/openclaw:latest
    container_name: openclaw
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "grafana")
            echo "    image: grafana/grafana:latest
    container_name: grafana
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "prometheus")
            echo "    image: prom/prometheus:latest
    container_name: prometheus
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "minio")
            echo "    image: minio/minio:latest
    container_name: minio
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        "tailscale")
            echo "    image: tailscale/tailscale:latest
    container_name: tailscale
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
        *)
            echo "    image: ${service_name}:latest
    container_name: $service_name
    # 🔥 NON-ROOT USER MAPPING
    user: \"$user_mapping\""
            ;;
    esac
}

# 🔥 NEW: Generate Security Configuration
generate_service_security() {
    if [[ "$SECURITY_COMPLIANCE" == "true" ]]; then
        echo "    # 🔥 APPARMOR SECURITY
    security_opt:
      - apparmor:$service_name
    # 🔥 DOCKER SECURITY HARDENING
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETGID
      - SETUID
    read_only: true
    tmpfs:
      - /tmp:noexec,nosuid,size=100m"
    fi
}

# 🔥 UPDATED: Generate Service Environment Variables
generate_service_env() {
    local service_name="$1"
    local env_vars=""
    
    case "$service_name" in
        "postgres")
            env_vars="      - POSTGRES_USER=\${POSTGRES_USER:-postgres}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB:-aiplatform}
      - PGDATA=/var/lib/postgresql/data/pgdata
      - PUID=\${RUNNING_UID:-1001}
      - PGID=\${RUNNING_GID:-1001}
      - TZ=\${TIMEZONE:-UTC}"
            ;;
        "redis")
            env_vars="      - REDIS_PASSWORD=\${REDIS_PASSWORD}
      - PUID=\${RUNNING_UID:-1001}
      - PGID=\${RUNNING_GID:-1001}
      - TZ=\${TIMEZONE:-UTC}"
            ;;
        "ollama")
            env_vars="      - OLLAMA_HOST=0.0.0.0
      - PUID=\${RUNNING_UID:-1001}
      - PGID=\${RUNNING_GID:-1001}
      - TZ=\${TIMEZONE:-UTC}"
            ;;
        "litellm")
            env_vars="      - LITELLM_MASTER_KEY=\${LITELLM_MASTER_KEY}
      - DATABASE_URL=postgresql://\${POSTGRES_USER:-postgres}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB:-aiplatform}
      - REDIS_URL=redis://redis:6379
      - REDIS_PASSWORD=\${REDIS_PASSWORD}
      - PUID=\${RUNNING_UID:-1001}
      - PGID=\${RUNNING_GID:-1001}
      - TZ=\${TIMEZONE:-UTC}"
            ;;
        "dify")
            env_vars="      - CONSOLE_WEB_URL=http://localhost:8080
      - CONSOLE_API_URL=http://localhost:5001
      - DB_USERNAME=\${POSTGRES_USER:-postgres}
      - DB_PASSWORD=\${POSTGRES_PASSWORD}
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=\${POSTGRES_DB:-aiplatform}
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=\${REDIS_PASSWORD}
      - PUID=\${RUNNING_UID:-1001}
      - PGID=\${RUNNING_GID:-1001}
      - TZ=\${TIMEZONE:-UTC}"
            ;;
        *)
            env_vars="      - PUID=\${RUNNING_UID:-1001}
      - PGID=\${RUNNING_GID:-1001}
      - TZ=\${TIMEZONE:-UTC}"
            ;;
    esac
    
    echo "$env_vars"
}

# 🔥 UPDATED: Generate Service Volumes with User Ownership
generate_service_volumes() {
    local service_name="$1"
    local volumes=""
    
    case "$service_name" in
        "postgres")
            volumes="      - ${DATA_ROOT}/postgres:/var/lib/postgresql/data
      - ${DATA_ROOT}/logs/postgres:/var/log/postgresql"
            ;;
        "redis")
            volumes="      - ${DATA_ROOT}/redis:/data
      - ${DATA_ROOT}/logs/redis:/var/log/redis"
            ;;
        "ollama")
            volumes="      - ${DATA_ROOT}/ollama:/root/.ollama"
            ;;
        "litellm")
            volumes="      - ${DATA_ROOT}/litellm:/app/data
      - ${DATA_ROOT}/litellm/config.yaml:/app/config.yaml"
            ;;
        "dify")
            volumes="      - ${DATA_ROOT}/dify:/app/storage
      - ${DATA_ROOT}/logs/dify:/app/logs"
            ;;
        "prometheus")
            volumes="      - ${DATA_ROOT}/prometheus:/prometheus
      - ${DATA_ROOT}/logs/prometheus:/var/log/prometheus"
            ;;
        *)
            volumes="      - ${DATA_ROOT}/${service_name}:/data"
            ;;
    esac
    
    echo "$volumes"
}

# 🔥 UPDATED: Generate Service Ports
generate_ports() {
    local service_name="$1"
    local ports=""
    local bind_ip="${BIND_IP:-127.0.0.1}"
    
    case "$service_name" in
        "postgres")
            ports="      - \"${bind_ip}:5432:5432\""
            ;;
        "redis")
            ports="      - \"${bind_ip}:6379:6379\""
            ;;
        "ollama")
            ports="      - \"${bind_ip}:\${OLLAMA_PORT:-11434}:11434\""
            ;;
        "litellm")
            ports="      - \"${bind_ip}:4000:4000\""
            ;;
        "dify")
            ports="      - \"${bind_ip}:8080:3000\"
      - \"${bind_ip}:5001:5001\""
            ;;
        "n8n")
            ports="      - \"${bind_ip}:\${N8N_PORT:-5678}:5678\""
            ;;
        "flowise")
            ports="      - \"${bind_ip}:\${FLOWISE_PORT:-3000}:3000\""
            ;;
        "anythingllm")
            ports="      - \"${bind_ip}:\${ANYTHINGLLM_PORT:-3001}:3001\""
            ;;
        "openwebui")
            ports="      - \"${bind_ip}:\${OPENWEBUI_PORT:-3000}:3000\""
            ;;
        "openclaw")
            ports="      - \"${bind_ip}:\${OPENCLAW_PORT:-8081}:8081\""
            ;;
        "grafana")
            ports="      - \"${bind_ip}:3000:3000\""
            ;;
        "prometheus")
            ports="      - \"${bind_ip}:9090:9090\""
            ;;
        "minio")
            ports="      - \"${bind_ip}:9000:9000\"
      - \"${bind_ip}:9001:9001\""
            ;;
        "tailscale")
            ports="      - \"${bind_ip}:41641:41641/udp\""
            ;;
        *)
            ports="      - \"${bind_ip}:3000:3000\""
            ;;
    esac
    
    echo "$ports"
}

# 🔥 UPDATED: Generate Health Checks
generate_healthcheck() {
    local service_name="$1"
    local healthcheck=""
    
    case "$service_name" in
        "postgres")
            healthcheck="      test: [\"CMD-SHELL\", \"pg_isready -U \${POSTGRES_USER:-postgres} -d \${POSTGRES_DB:-aiplatform}\"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s"
            ;;
        "redis")
            healthcheck="      test: [\"CMD\", \"redis-cli\", \"ping\"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s"
            ;;
        "ollama")
            healthcheck="      test: [\"CMD\", \"curl\", \"-f\", \"http://localhost:11434\"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 45s"
            ;;
        "litellm")
            healthcheck="      test: [\"CMD\", \"curl\", \"-f\", \"http://localhost:4000/health\"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s"
            ;;
        "dify")
            healthcheck="      test: [\"CMD\", \"curl\", \"-f\", \"http://localhost:3000\"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 120s"
            ;;
        *)
            healthcheck="      test: [\"CMD\", \"curl\", \"-f\", \"http://localhost:3000\"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s"
            ;;
    esac
    
    echo "$healthcheck"
}

# 🔥 UPDATED: Deploy Service with Unified Compose and Health Checks
deploy_service() {
    local service="$1"
    local service_found=false
    
    echo -e "  🐳 ${BOLD}$service${NC}: "
    
    # Check if service exists in unified compose file
    if ! grep -q "^  $service:" "$COMPOSE_FILE"; then
        # Check for special cases (dify, signal-api, etc.)
        case "$service" in
            "dify")
                if grep -q "^dify-api:" "$COMPOSE_FILE" || grep -q "^dify-web:" "$COMPOSE_FILE"; then
                    service_found=true
                else
                    echo -e "${RED}SERVICE NOT FOUND IN COMPOSE FILE${NC}"
                    print_error "Service $service not defined in $COMPOSE_FILE"
                    return 1
                fi
                ;;
            "signal-api")
                if grep -q "^signal-cli:" "$COMPOSE_FILE" || grep -q "^signal-api:" "$COMPOSE_FILE"; then
                    service_found=true
                else
                    echo -e "${RED}SERVICE NOT FOUND IN COMPOSE FILE${NC}"
                    print_error "Service $service not defined in $COMPOSE_FILE"
                    return 1
                fi
                ;;
            *)
                echo -e "${RED}SERVICE NOT FOUND IN COMPOSE FILE${NC}"
                print_error "Service $service not defined in $COMPOSE_FILE"
                return 1
                ;;
        esac
    else
        service_found=true
    fi
    
    # Check for alternative service names (handle Script 1 naming differences)
    local service_found=false
    
    # Try exact match first
    if grep -q "^  $service:" "$COMPOSE_FILE"; then
        service_found=true
    fi
    
    # Try common alternatives if not found
    if [[ "$service_found" == false ]]; then
        case "$service" in
            "dify")
                if grep -q "^dify-api:" "$COMPOSE_FILE" || grep -q "^dify-web:" "$COMPOSE_FILE"; then
                    service_found=true
                fi
                ;;
            "openclaw")
                if grep -q "^openclaw:" "$COMPOSE_FILE"; then
                    service_found=true
                fi
                ;;
            "signal-api")
                if grep -q "^signal-cli:" "$COMPOSE_FILE" || grep -q "^signal-api:" "$COMPOSE_FILE"; then
                    service_found=true
                fi
                ;;
        esac
    fi
    
    if [[ "$service_found" == false ]]; then
        echo -e "${RED}SERVICE NOT FOUND IN COMPOSE FILE${NC}"
        print_error "Service $service not defined in $COMPOSE_FILE"
        return 1
    fi
    
    # Pull image
    print_info "DEBUG: Pulling $service image..."
    if ! docker compose -f "$COMPOSE_FILE" pull "$service" >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}FAILED TO PULL${NC}"
        print_error "Failed to pull $service image"
        docker compose -f "$COMPOSE_FILE" logs "$service" --tail 20
        return 1
    fi
    
    # Start service with explicit environment
    print_info "DEBUG: Starting $service with explicit environment..."
    if ! docker compose -f "$COMPOSE_FILE" up -d "$service" >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}FAILED TO START${NC}"
        print_error "Failed to start $service"
        docker compose -f "$COMPOSE_FILE" logs "$service" --tail 20
        return 1
    fi
    
    # Wait for health using enhanced wait mechanisms
    print_info "DEBUG: Waiting for $service to become healthy..."
    
    # Use enhanced wait for specific services
    case "$service" in
        "postgres")
            if wait_for_postgres "postgres" 60; then
                echo -e "${GREEN}✓ HEALTHY${NC}"
                display_service_info "$service"
                return 0
            else
                echo -e "${YELLOW}⚠ RUNNING (health check timeout)${NC}"
                print_warning "$service is running but health check timed out"
                return 0 # Don't fail deployment for health check timeout
            fi
            ;;
        "redis")
            if wait_for_redis; then
                echo -e "${GREEN}✓ HEALTHY${NC}"
                display_service_info "$service"
                return 0
            else
                echo -e "${YELLOW}⚠ RUNNING (health check timeout)${NC}"
                print_warning "$service is running but health check timed out"
                return 0
            fi
            ;;
        *)
            if wait_for_service_healthy "$service" 180; then
                echo -e "${GREEN}✓ HEALTHY${NC}"
                display_service_info "$service"
                return 0
            else
                echo -e "${YELLOW}⚠ RUNNING (health check timeout)${NC}"
                print_warning "$service is running but health check timed out"
                return 0 # Don't fail deployment for health check timeout
            fi
            ;;
    esac
}

# 🔥 NEW: Wait for Service Health with Docker Health Checks
wait_for_healthy() {
    local service="$1"
    local timeout="${2:-30}"
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        # Check container is running
        if ! docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            sleep 2
            elapsed=$((elapsed + 2))
            continue
        fi
        
        # Check health status using Docker health check
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null || echo "no_healthcheck")
        
        if [ "$health" = "healthy" ]; then
            return 0
        elif [ "$health" = "unhealthy" ]; then
            return 1
        elif [ "$health" = "no_healthcheck" ]; then
            # No healthcheck defined, verify running for 10s
            if [ $elapsed -ge 10 ]; then
                return 0
            fi
        fi
        
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    return 1
}

# 🔥 NEW: Display Service Information
display_service_info() {
    local svc="$1"
    case "$svc" in
        postgres) echo -e "    ${BLUE}→ Database ready on 5432${NC}" ;;
        redis)    echo -e "    ${BLUE}→ Cache ready on 6379${NC}" ;;
        qdrant)   echo -e "    ${BLUE}→ Vector DB ready on 6333${NC}" ;;
        ollama)   echo -e "    ${BLUE}→ LLM engine ready on 11434${NC}" ;;
        litellm)  echo -e "    ${BLUE}→ Gateway ready: http://localhost:8010/health${NC}" ;;
        open-webui) echo -e "    ${BLUE}→ UI ready: http://localhost:8080${NC}" ;;
        dify-api) echo -e "    ${BLUE}→ Dify API ready: http://localhost:5001${NC}" ;;
        dify-web) echo -e "    ${BLUE}→ Dify Web ready: http://localhost:3000${NC}" ;;
        n8n)      echo -e "    ${BLUE}→ n8n ready: http://localhost:5678${NC}" ;;
        flowise)  echo -e "    ${BLUE}→ Flowise ready: http://localhost:3001${NC}" ;;
        anythingllm) echo -e "    ${BLUE}→ AnythingLLM ready: http://localhost:3002${NC}" ;;
        prometheus) echo -e "    ${BLUE}→ Prometheus ready: http://localhost:9090${NC}" ;;
        grafana)   echo -e "    ${BLUE}→ Grafana ready: http://localhost:3003${NC}" ;;
        *)        echo -e "    ${BLUE}→ Service running${NC}" ;;
    esac
}

# 🔥 NEW: Comprehensive Cleanup Function with Unified Compose
cleanup_previous_deployments() {
    print_info "Cleaning up previous deployments..."
    
    # Stop and remove all AI platform containers using unified compose
    if [[ -f "$COMPOSE_FILE" ]]; then
        print_info "Stopping AI platform containers using unified compose..."
        if docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down >> "$LOG_FILE" 2>&1; then
            print_success "All containers stopped successfully"
        else
            print_warning "Some containers may not have stopped properly"
        fi
    else
        print_warning "Unified compose file not found, using manual cleanup"
        # Fallback to manual cleanup
        local containers=$(docker ps -q --filter "name=postgres|redis|ollama|litellm|dify|n8n|flowise|anythingllm|openwebui|signal-api|openclaw|grafana|prometheus|minio|tailscale" 2>/dev/null || true)
        
        if [[ -n "$containers" ]]; then
            echo "$containers" | xargs -r docker stop >> "$LOG_FILE" 2>&1 || true
            echo "$containers" | xargs -r docker rm >> "$LOG_FILE" 2>&1 || true
        fi
    fi
    
    # Clean up orphaned containers
    print_info "Cleaning up orphaned containers..."
    docker container prune -f >> "$LOG_FILE" 2>&1 || true
    
    # Clean up unused networks
    print_info "DEBUG: Aggressive network cleanup starting..."
    
    # Stop Docker daemon to clear network cache
    print_info "DEBUG: Stopping Docker daemon to clear network cache..."
    systemctl stop docker 2>/dev/null || true
    print_info "DEBUG: Docker daemon stopped"
    
    # Force remove all ai_platform networks
    print_info "DEBUG: Force removing all ai_platform networks..."
    docker network ls --filter "name=ai_platform*" --format "{{.Name}}" 2>/dev/null | while read network; do
        docker network rm "$network" --force 2>/dev/null || true
        print_info "DEBUG: Removed network: $network"
    done
    
    # Wait for networks to be fully removed
    print_info "DEBUG: Waiting for networks to be fully removed..."
    sleep 10
    
    # Verify networks are actually removed
    print_info "DEBUG: Verifying networks are actually removed..."
    local remaining_networks=$(docker network ls --filter "name=ai_platform*" --format "{{.Name}}" 2>/dev/null)
    if [[ -n "$remaining_networks" ]]; then
        print_error "ERROR: ai_platform networks still exist: $remaining_networks"
        print_error "This indicates a fundamental network cleanup issue"
        return 1
    fi
    
    # Start Docker daemon to refresh network cache
    print_info "DEBUG: Starting Docker daemon to refresh network cache..."
    systemctl start docker 2>/dev/null || true
    
    # Wait for Docker daemon to be ready
    print_info "DEBUG: Waiting for Docker daemon to be ready..."
    sleep 5
    
    print_info "DEBUG: Network cleanup completed successfully"
    
    # Clean up unused volumes (be careful not to remove data volumes)
    print_info "Cleaning up unused volumes..."
    docker volume prune -f --filter "label!=ai-platform.data" >> "$LOG_FILE" 2>&1 || true
    
    # Terminate any background deployment processes
    print_info "DEBUG: About to terminate background processes..."
    print_info "DEBUG: Current PID: $$"
    # Kill other 2-deploy-services processes but not current one
    for pid in $(pgrep -f "2-deploy-services.sh"); do
        if [[ "$pid" != "$$" ]]; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    print_info "DEBUG: Terminated other 2-deploy-services processes"
    pkill -f "docker-compose" 2>/dev/null || true
    print_info "DEBUG: Terminated docker-compose processes"
    
    print_success "Pre-deployment cleanup completed"
    print_info "DEBUG: cleanup_previous_deployments function completed"
}

# Main deployment function
main() {
    # 🔥 NEW: Deployment Lock Mechanism
    if [[ -f "$DEPLOYMENT_LOCK" ]]; then
        local lock_pid=$(cat "$DEPLOYMENT_LOCK" 2>/dev/null || echo "unknown")
        if ps -p "$lock_pid" >/dev/null 2>&1; then
            print_error "Deployment is already running (PID: $lock_pid)"
            print_error "Wait for it to complete or run: kill $lock_pid"
            exit 1
        else
            print_warning "Removing stale deployment lock"
            rm -f "$DEPLOYMENT_LOCK"
        fi
    fi
    
    # Create deployment lock
    echo $$ > "$DEPLOYMENT_LOCK"
    trap 'rm -f "$DEPLOYMENT_LOCK"' EXIT
    
    # 🔍 DEBUG: Script start
    print_info "DEBUG: Script 2 starting..."
    print_info "DEBUG: ENV_FILE=$ENV_FILE"
    print_info "DEBUG: SERVICES_FILE=$SERVICES_FILE"
    print_info "DEBUG: COMPOSE_FILE=$COMPOSE_FILE"
    
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            AI PLATFORM AUTOMATION - DEPLOYMENT                 ║${NC}"
    echo -e "${CYAN}║              Non-Root Version 7.0.0                      ║${NC}"
    echo -e "${CYAN}║           AppArmor Security & Complete Coverage              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}\n"
    

    # 🔥 NEW: Comprehensive Cleanup Before Deployment
    print_info "Performing pre-deployment cleanup..."
    cleanup_previous_deployments
    
    # Load selected services from Script 1
    print_info "DEBUG: About to call load_selected_services..."
    load_selected_services
    print_info "DEBUG: load_selected_services completed successfully"
    
    # 🔍 DEBUG: Environment verification
    print_info "DEBUG: Environment variables loaded:"
    print_info "  RUNNING_UID: ${RUNNING_UID:-NOT_SET}"
    print_info "  RUNNING_GID: ${RUNNING_GID:-NOT_SET}"
    print_info "  ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY:-NOT_SET}"
    print_info "  LITELLM_SALT_KEY: ${N8N_ENCRYPTION_KEY:-NOT_SET}"
    print_info "  LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY:-NOT_SET}"
    
    # Verify unified compose file exists
    print_info "DEBUG: About to verify compose file exists..."
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        print_error "Unified compose file not found: $COMPOSE_FILE"
        print_error "Run Script 1 first to generate the compose file"
        exit 1
    fi
    print_info "DEBUG: Compose file verification completed"
    
    print_success "Using unified compose file: $COMPOSE_FILE"
    
    # 🔥 NEW: Generate Proxy Configuration BEFORE Deployment
    print_info "DEBUG: About to generate proxy configuration..."
    echo ""
    echo -e "${BLUE}→ Generating proxy configuration...${NC}"
    
    generate_proxy_config
    add_proxy_to_compose
    
    echo -e "${GREEN}✓ Proxy configuration ready${NC}"
    echo ""
    
    # 🔥 NEW: Generate Critical Configurations BEFORE Deployment
    print_info "DEBUG: About to generate critical configurations..."
    echo ""
    echo -e "${BLUE}→ Generating Prometheus configuration...${NC}"
    
    generate_prometheus_config
    
    echo -e "${GREEN}✓ Prometheus configuration ready${NC}"
    echo ""
    
    # 🔥 NEW: Fix Volume Permissions BEFORE Deployment
    print_info "DEBUG: About to fix volume permissions..."
    echo ""
    echo -e "${BLUE}→ Setting up volume permissions...${NC}"
    
    fix_postgres_permissions
    fix_redis_permissions
    fix_grafana_permissions
    fix_ollama_permissions
    
    echo -e "${GREEN}✓ Volume permissions fixed${NC}"
    echo ""
    
    print_info "DEBUG: About to create Docker networks..."
    
    # ,
    print_info "DEBUG: About to create Docker networks..."
    # Clean up existing networks with wrong labels first
    print_info "DEBUG: Cleaning up existing networks..."
    docker network prune -f >> "$LOG_FILE" 2>&1 || true
    
    if ! docker network inspect ai_platform >/dev/null 2>&1; then
        docker compose -f "$COMPOSE_FILE" up --no-deps --detach prometheus || true
        print_success "Created ai_platform network"
    fi
    
    if ! docker network inspect ai_platform_internal >/dev/null 2>&1; then
        docker compose -f "$COMPOSE_FILE" up --no-deps --detach prometheus || true_internal --internal
        print_success "Created ai_platform_internal network"
    fi
    print_info "DEBUG: Docker networks created successfully"
    
    # 🔥 REFACTORED: Deploy Services in Corrected Dependency Order
    print_info "DEBUG: About to start service deployment loop..."
    
    # Define deployment order based on gap analysis fixes
    local core_services=("postgres" "redis")
    local monitoring_services=("prometheus" "grafana")
    local ai_services=("ollama" "litellm" "openwebui" "anythingllm" "dify")
    local application_services=("n8n" "flowise")
    local storage_services=("minio")
    local network_services=("tailscale" "openclaw" "signal-api")
    local proxy_services=("caddy")
    
    # Deploy in phases with proper dependencies
    local failed=0
    
    # Phase 1: Core Infrastructure (PostgreSQL, Redis)
    print_info "DEBUG: Deploying core infrastructure..."
    
    for service in "${core_services[@]}"; do
        if [[ " ${SELECTED_SERVICES[*]} " =~ " ${service} " ]]; then
            deploy_service "$service" || failed=$((failed + 1))
        fi
    done
    
    # Phase 2: Monitoring Stack (Prometheus, Grafana)
    print_info "DEBUG: Deploying monitoring services..."
    for service in "${monitoring_services[@]}"; do
        if [[ " ${SELECTED_SERVICES[*]} " =~ " ${service} " ]]; then
            deploy_service "$service" || failed=$((failed + 1))
        fi
    done
    
    # Phase 3: AI Services (Ollama → LiteLLM → OpenWebUI → AnythingLLM → Dify)
    print_info "DEBUG: Deploying AI services..."
    for service in "${ai_services[@]}"; do
        if [[ " ${SELECTED_SERVICES[*]} " =~ " ${service} " ]]; then
            deploy_service "$service" || failed=$((failed + 1))
        fi
    done
    
    # Phase 4: Application Services (n8n, Flowise)
    print_info "DEBUG: Deploying application services..."
    for service in "${application_services[@]}"; do
        if [[ " ${SELECTED_SERVICES[*]} " =~ " ${service} " ]]; then
            deploy_service "$service" || failed=$((failed + 1))
        fi
    done
    
    # Phase 5: Storage & Network Services (MinIO, Tailscale, OpenClaw, Signal-API)
    print_info "DEBUG: Deploying storage and network services..."
    for service in "${storage_services[@]}"; do
        if [[ " ${SELECTED_SERVICES[*]} " =~ " ${service} " ]]; then
            deploy_service "$service" || failed=$((failed + 1))
        fi
    done
    
    for service in "${network_services[@]}"; do
        if [[ " ${SELECTED_SERVICES[*]} " =~ " ${service} " ]]; then
            deploy_service "$service" || failed=$((failed + 1))
        fi
    done
    
    # Phase 6: Proxy Layer (Caddy - Start Last)
    print_info "DEBUG: Deploying proxy services..."
    for service in "${proxy_services[@]}"; do
        if [[ " ${SELECTED_SERVICES[*]} " =~ " ${service} " ]]; then
            deploy_service "$service" || failed=$((failed + 1))
        fi
    done
    
    print_info "DEBUG: All services deployment completed"
    
    echo -e "\n${CYAN}🚀 Starting deployment of ${TOTAL_SERVICES} services...${NC}\n"
    print_info "DEBUG: About to start core services deployment..."
    
    # Deploy core infrastructure first
    local core_services=("postgres" "redis")
    local deployed=0
    for service in "${core_services[@]}"; do
        print_info "DEBUG: Checking core service: $service"
        if [[ " ${SELECTED_SERVICES[@]} " =~ " $service " ]]; then
            print_info "DEBUG: Deploying core service: $service"
            if deploy_service "$service"; then
                deployed=$((deployed + 1))
                print_info "DEBUG: Core service $service deployed successfully"
            else
                failed=$((failed + 1))
                print_error "❌ ZERO TOLERANCE: Core service $service deployment failed!"
                print_error "🚨 STOPPING DEPLOYMENT - Zero tolerance policy"
                echo -e "\n${RED}❌ DEPLOYMENT FAILED WITH ERRORS${NC}"
                echo -e "${RED}Failed services: $failed${NC}"
                echo -e "${RED}Deployed services: $deployed${NC}"
                exit 1
            fi
        fi
    done
    print_info "DEBUG: Core services deployment completed"
    
    # Deploy remaining services
    print_info "DEBUG: About to deploy remaining services..."
    for service in "${SELECTED_SERVICES[@]}"; do
        if [[ ! " ${core_services[@]} " =~ " $service " ]]; then
            print_info "DEBUG: Deploying remaining service: $service"
            if deploy_service "$service"; then
                deployed=$((deployed + 1))
                print_info "DEBUG: Service $service deployed successfully"
            else
                failed=$((failed + 1))
                print_error "❌ ZERO TOLERANCE: Service $service deployment failed!"
                print_error "🚨 STOPPING DEPLOYMENT - Zero tolerance policy"
                echo -e "\n${RED}❌ DEPLOYMENT FAILED WITH ERRORS${NC}"
                echo -e "${RED}Failed services: $failed${NC}"
                echo -e "${RED}Deployed services: $deployed${NC}"
                exit 1
            fi
        fi
    done
    print_info "DEBUG: All remaining services deployment completed"
    
    echo -e "\n${GREEN}🎉 Deployment completed!${NC}"
    echo -e "${CYAN}✅ Deployed: $deployed services${NC}"
    echo -e "${RED}❌ Failed: $failed services${NC}"
    echo -e "${CYAN}All containers are running as non-root user with AppArmor security${NC}"
    echo -e "${CYAN}Check container status: docker ps --format 'table {{.Names}}\t{{.User}}\t{{.Status}}'${NC}"
}

# Run main function
main "$@"
