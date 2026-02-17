# AI Platform - Proxy & Configuration Refactoring Plan

**Date:** February 17, 2026  
**Status:** Scripts 0-1 functional, Script 2 deploys but services not accessible  
**Goal:** Fix proxy configuration generation + enhance Script 3 for post-deployment tasks

---

## PROBLEM ANALYSIS

### Current State

**Script 1 (Functional):**
- ✅ Collects proxy choice (nginx/caddy)
- ✅ Saves proxy type (direct-port/alias)
- ✅ Stores in .env: `PROXY_TYPE=nginx` and `ACCESS_MODE=alias`
- ❌ Does NOT generate proxy config files

**Script 2 (Partial):**
- ✅ Deploys services
- ✅ Services are running
- ❌ No proxy configuration generated
- ❌ URLs not accessible (https://domain.com/servicename → 404)

**Script 3 (Minimal):**
- Currently ~100 lines of stubs
- Needs comprehensive post-deployment configuration

---

## PART 1: PROXY CONFIGURATION FIX

### Architecture Decision

**Where to generate proxy config:** Script 2 (during deployment)

**Why:**
- Proxy must be deployed WITH proper configuration
- Can't deploy proxy first then configure it (chicken-egg problem)
- Script 2 knows which services were deployed

**Implementation Strategy:**
```
Script 1: Collects proxy settings → Saves to .env
           ↓
Script 2: Reads .env → Generates proxy config → Deploys proxy + services
           ↓
Script 3: Post-deployment tasks (SSL renewal, service additions)
```

---

## REFACTORING PLAN - SCRIPT 2

### Phase 1: Add Proxy Config Generation Functions

**Location:** Add after line ~60 (before deployment phases start)

```bash
#==============================================================================
# PROXY CONFIGURATION GENERATION
#==============================================================================

generate_proxy_config() {
    log_info "Generating proxy configuration..."
    
    # Determine which proxy to configure
    case "${PROXY_TYPE:-nginx}" in
        nginx)
            generate_nginx_config
            ;;
        caddy)
            generate_caddy_config
            ;;
        traefik)
            generate_traefik_config
            ;;
        *)
            log_error "Unknown proxy type: ${PROXY_TYPE}"
            return 1
            ;;
    esac
    
    log_success "Proxy configuration generated"
}

generate_nginx_config() {
    local nginx_conf_dir="${CONFIG_DIR}/nginx"
    mkdir -p "$nginx_conf_dir/sites-available" "$nginx_conf_dir/sites-enabled"
    
    log_info "Generating nginx configuration..."
    
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
    if [ "${ACCESS_MODE}" = "alias" ]; then
        generate_nginx_alias_config
    else
        generate_nginx_direct_port_config
    fi
    
    # Create symlink
    ln -sf "$nginx_conf_dir/sites-available/ai-platform.conf" \
           "$nginx_conf_dir/sites-enabled/ai-platform.conf"
}

generate_nginx_alias_config() {
    local site_conf="${CONFIG_DIR}/nginx/sites-available/ai-platform.conf"
    
    cat > "$site_conf" <<EOF
# AI Platform - Alias Mode Configuration
# Generated: $(date)

# HTTP redirect to HTTPS
server {
    listen 80;
    server_name ${BASE_DOMAIN} *.${BASE_DOMAIN};
    return 301 https://\$host\$request_uri;
}

# Main HTTPS server
server {
    listen 443 ssl http2;
    server_name ${BASE_DOMAIN};
    
    # SSL Configuration
    ssl_certificate ${SSL_DIR}/fullchain.pem;
    ssl_certificate_key ${SSL_DIR}/privkey.pem;
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
        root /usr/share/nginx/html;
        index index.html;
    }

EOF

    # Add service locations based on what's enabled
    add_nginx_service_locations "$site_conf"
    
    # Close server block
    echo "}" >> "$site_conf"
}

add_nginx_service_locations() {
    local site_conf="$1"
    
    # LiteLLM
    if [ "${ENABLE_LITELLM}" = "true" ]; then
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
    
    # Open WebUI
    if [ "${ENABLE_OPENWEBUI}" = "true" ]; then
        cat >> "$site_conf" <<'EOF'
    
    # Open WebUI
    location /webui/ {
        proxy_pass http://open-webui:8080/;
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
    
    # Dify
    if [ "${ENABLE_DIFY}" = "true" ]; then
        cat >> "$site_conf" <<'EOF'
    
    # Dify Platform
    location /dify/ {
        proxy_pass http://dify-web:3000/;
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
    
    # n8n
    if [ "${ENABLE_N8N}" = "true" ]; then
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
    
    # Flowise
    if [ "${ENABLE_FLOWISE}" = "true" ]; then
        cat >> "$site_conf" <<'EOF'
    
    # Flowise
    location /flowise/ {
        proxy_pass http://flowise:3000/;
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
    
    # Grafana
    if [ "${ENABLE_MONITORING}" = "true" ]; then
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
    
    # AnythingLLM
    if [ "${ENABLE_ANYTHINGLLM}" = "true" ]; then
        cat >> "$site_conf" <<'EOF'
    
    # AnythingLLM
    location /anythingllm/ {
        proxy_pass http://anythingllm:3001/;
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
}

generate_caddy_config() {
    local caddy_conf="${CONFIG_DIR}/caddy/Caddyfile"
    mkdir -p "${CONFIG_DIR}/caddy"
    
    log_info "Generating Caddy configuration..."
    
    if [ "${ACCESS_MODE}" = "alias" ]; then
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
    email ${LETSENCRYPT_EMAIL}
    acme_ca https://acme-v02.api.letsencrypt.org/directory
}

${BASE_DOMAIN} {
    # Automatic HTTPS
    
    # Root - landing page or dashboard
    route / {
        respond "AI Platform - Services available at /servicename"
    }

EOF

    # Add service routes
    [ "${ENABLE_LITELLM}" = "true" ] && cat >> "$caddy_conf" <<'EOF'
    
    # LiteLLM Gateway
    route /litellm/* {
        uri strip_prefix /litellm
        reverse_proxy litellm:4000 {
            header_up X-Real-IP {remote_host}
        }
    }
EOF

    [ "${ENABLE_OPENWEBUI}" = "true" ] && cat >> "$caddy_conf" <<'EOF'
    
    # Open WebUI
    route /webui/* {
        uri strip_prefix /webui
        reverse_proxy open-webui:8080 {
            header_up X-Real-IP {remote_host}
        }
    }
EOF

    [ "${ENABLE_DIFY}" = "true" ] && cat >> "$caddy_conf" <<'EOF'
    
    # Dify
    route /dify/* {
        uri strip_prefix /dify
        reverse_proxy dify-web:3000 {
            header_up X-Real-IP {remote_host}
        }
    }
EOF

    [ "${ENABLE_N8N}" = "true" ] && cat >> "$caddy_conf" <<'EOF'
    
    # n8n
    route /n8n/* {
        uri strip_prefix /n8n
        reverse_proxy n8n:5678 {
            header_up X-Real-IP {remote_host}
        }
    }
EOF

    [ "${ENABLE_FLOWISE}" = "true" ] && cat >> "$caddy_conf" <<'EOF'
    
    # Flowise
    route /flowise/* {
        uri strip_prefix /flowise
        reverse_proxy flowise:3000 {
            header_up X-Real-IP {remote_host}
        }
    }
EOF

    [ "${ENABLE_MONITORING}" = "true" ] && cat >> "$caddy_conf" <<'EOF'
    
    # Grafana
    route /grafana/* {
        uri strip_prefix /grafana
        reverse_proxy grafana:3000 {
            header_up X-Real-IP {remote_host}
        }
    }
EOF

    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && cat >> "$caddy_conf" <<'EOF'
    
    # AnythingLLM
    route /anythingllm/* {
        uri strip_prefix /anythingllm
        reverse_proxy anythingllm:3001 {
            header_up X-Real-IP {remote_host}
        }
    }
EOF

    # Close Caddy block
    echo "}" >> "$caddy_conf"
}

#==============================================================================
# PROXY SERVICE ADDITION TO COMPOSE
#==============================================================================

add_proxy_to_compose() {
    log_info "Adding proxy service to docker-compose.yml..."
    
    case "${PROXY_TYPE:-nginx}" in
        nginx)
            add_nginx_to_compose
            ;;
        caddy)
            add_caddy_to_compose
            ;;
    esac
}

add_nginx_to_compose() {
    # Check if nginx already in compose
    if grep -q "^  nginx:" "$COMPOSE_FILE"; then
        log_info "Nginx already in compose file"
        return 0
    fi
    
    # Add nginx service
    cat >> "$COMPOSE_FILE" <<'EOF'

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    volumes:
      - ${CONFIG_DIR}/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ${CONFIG_DIR}/nginx/sites-enabled:/etc/nginx/sites-enabled:ro
      - ${SSL_DIR}:/etc/nginx/ssl:ro
      - ${DATA_DIR}/nginx/html:/usr/share/nginx/html
    networks:
      - ai-platform
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      - litellm
      - open-webui
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost/"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "ai-platform.service=nginx"
      - "ai-platform.type=proxy"
EOF
    
    log_success "Nginx added to compose"
}

add_caddy_to_compose() {
    if grep -q "^  caddy:" "$COMPOSE_FILE"; then
        log_info "Caddy already in compose file"
        return 0
    fi
    
    cat >> "$COMPOSE_FILE" <<'EOF'

  caddy:
    image: caddy:alpine
    container_name: caddy
    restart: unless-stopped
    volumes:
      - ${CONFIG_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ${DATA_DIR}/caddy/data:/data
      - ${DATA_DIR}/caddy/config:/config
    networks:
      - ai-platform
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      - litellm
      - open-webui
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:2019/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "ai-platform.service=caddy"
      - "ai-platform.type=proxy"
EOF
    
    log_success "Caddy added to compose"
}
```

### Phase 2: Modify Deployment Sequence

**Location:** Main execution (lines ~120-200)

**BEFORE deployment phases, add:**

```bash
# --- Generate Proxy Configuration BEFORE Deployment ---
echo ""
echo -e "${BLUE}→ Generating proxy configuration...${NC}"

generate_proxy_config
add_proxy_to_compose

echo -e "${GREEN}✓ Proxy configuration ready${NC}"
echo ""
```

**Complete Modified Deployment Flow:**

```bash
# PHASE 0: VALIDATION
print_phase "🔍 PHASE 0/13: DOCKER-COMPOSE VALIDATION" "18s"
SVC_COUNT=$(grep -c "image:" "$COMPOSE_FILE")
echo -e "  Parsing $SVC_COUNT services → docker-compose.yml ${GREEN}✓${NC}"

# PHASE 0.5: PROXY CONFIGURATION (NEW)
print_phase "🔧 PHASE 0.5/13: PROXY CONFIGURATION GENERATION" "10s"
generate_proxy_config
add_proxy_to_compose
echo -e "  Proxy type: ${PROXY_TYPE} | Access mode: ${ACCESS_MODE} ${GREEN}✓${NC}"

# PHASE 1: CONFIRMATION
print_phase "🔢 PHASE 1/13: DEPLOYMENT ORDER CONFIRMATION" "12s"
# ... existing code ...

# Continue with normal deployment phases...
```

---

## PART 2: SCRIPT 3 REFACTORING

### New Architecture - Menu-Driven Configuration

```bash
#!/bin/bash
#==============================================================================
# Script 3: Post-Deployment Configuration & Management
# Purpose: Configure services, manage SSL, add services, backups
#==============================================================================

set -euo pipefail

# Paths
REAL_USER="${SUDO_USER:-$USER}"
BASE_DIR="/home/$REAL_USER/ai-platform"
ENV_FILE="$BASE_DIR/.env"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
CONFIG_DIR="$BASE_DIR/config"
DATA_DIR="$BASE_DIR/data"
BACKUP_DIR="$BASE_DIR/backups"

# Load environment
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env not found. Run Script 1 first."
    exit 1
fi

source "$ENV_FILE"

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
    
    if [ "${USE_LETSENCRYPT}" = "true" ]; then
        log_info "Using Let's Encrypt for ${BASE_DOMAIN}..."
        
        # Stop proxy to free port 80
        docker compose -f "$COMPOSE_FILE" stop ${PROXY_TYPE}
        
        # Generate certificate
        docker run --rm -v "${SSL_DIR}:/etc/letsencrypt" \
            -p 80:80 \
            certbot/certbot certonly \
            --standalone \
            --email "${LETSENCRYPT_EMAIL}" \
            --agree-tos \
            --no-eff-email \
            -d "${BASE_DOMAIN}"
        
        # Restart proxy
        docker compose -f "$COMPOSE_FILE" start ${PROXY_TYPE}
        
        log_success "SSL certificate generated"
    else
        log_info "Generating self-signed certificate..."
        
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "${SSL_DIR}/privkey.pem" \
            -out "${SSL_DIR}/fullchain.pem" \
            -subj "/CN=${BASE_DOMAIN}/O=AI Platform/C=US"
        
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
    
    if [ "${USE_LETSENCRYPT}" != "true" ]; then
        log_warning "Not using Let's Encrypt. Use option 1 to regenerate self-signed."
        read -p "Press Enter to continue..."
        show_main_menu
        return
    fi
    
    log_info "Renewing Let's Encrypt certificate..."
    
    docker compose -f "$COMPOSE_FILE" stop ${PROXY_TYPE}
    
    docker run --rm -v "${SSL_DIR}:/etc/letsencrypt" \
        -p 80:80 \
        certbot/certbot renew
    
    docker compose -f "$COMPOSE_FILE" start ${PROXY_TYPE}
    
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
      DB_PASSWORD: ${DB_PASSWORD}
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
      - ai-platform-internal
      - ai-platform
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
      - ai-platform
    ports:
      - "3000:3000"
    labels:
      - "ai-platform.service=dify-web"
EOF
    
    # Update .env
    sed -i 's/ENABLE_DIFY=false/ENABLE_DIFY=true/' "$ENV_FILE"
    
    # Add to proxy config
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
    log_info "Access at: https://${BASE_DOMAIN}/dify"
}

add_service_to_proxy() {
    local service_name=$1
    local upstream=$2
    
    case "${PROXY_TYPE}" in
        nginx)
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
    enabled: ${ENABLE_LITELLM}
    url: http://litellm:4000
    api_key: \${LITELLM_MASTER_KEY}
    
  ollama:
    enabled: ${ENABLE_OLLAMA}
    url: http://ollama:11434
    
  qdrant:
    enabled: ${ENABLE_QDRANT}
    url: http://qdrant:6333
    
  signal:
    enabled: true
    url: http://signal-cli:8080
    phone: \${SIGNAL_PHONE_NUMBER}
    
  n8n:
    enabled: ${ENABLE_N8N}
    url: http://n8n:5678
    webhook_base: https://${BASE_DOMAIN}/n8n
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
```

---

## IMPLEMENTATION CHECKLIST

### Phase 1: Script 2 Proxy Fix (2-3 hours)

**File:** `scripts/2-deploy-services.sh`

- [ ] Add proxy configuration functions (lines ~60-500)
- [ ] Add `generate_proxy_config()` function
- [ ] Add `generate_nginx_config()` function
- [ ] Add `generate_caddy_config()` function
- [ ] Add `add_nginx_service_locations()` function
- [ ] Add `add_proxy_to_compose()` function
- [ ] Insert proxy generation before deployment (line ~120)
- [ ] Test: Deploy and verify URLs accessible

### Phase 2: Script 3 Rewrite (4-5 hours)

**File:** `scripts/3-configure-services.sh`

- [ ] Replace entire file with menu-driven version
- [ ] Implement SSL certificate management
- [ ] Implement service addition functions
- [ ] Implement Signal CLI configuration
- [ ] Implement Tailscale configuration
- [ ] Implement OpenClaw configuration
- [ ] Implement Google Drive configuration
- [ ] Implement backup functions
- [ ] Implement model management
- [ ] Test each menu option

### Phase 3: Testing (1-2 hours)

- [ ] Clean deployment test (Scripts 0→1→2)
- [ ] Verify all URLs accessible
- [ ] Test Script 3 menu navigation
- [ ] Test adding new service via Script 3
- [ ] Test backup functions
- [ ] Verify SSL regeneration works

---

## TESTING PROTOCOL

### Test 1: Clean Deployment
```bash
sudo ./0-complete-cleanup.sh
sudo ./1-setup-system.sh
# Select: nginx, alias mode, enable monitoring
sudo ./2-deploy-services.sh
```

**Verify:**
- [ ] Services deploy successfully
- [ ] https://domain.com/webui loads Open WebUI
- [ ] https://domain.com/litellm/health returns 200
- [ ] https://domain.com/grafana loads Grafana

### Test 2: Script 3 Configuration
```bash
sudo ./3-configure-services.sh
# Test option 3: Add New Service (Dify)
```

**Verify:**
- [ ] Dify added to compose
- [ ] Dify added to proxy config
- [ ] https://domain.com/dify loads Dify

### Test 3: Backup/Restore
```bash
sudo ./3-configure-services.sh
# Test option 11: Backup Configuration
```

**Verify:**
- [ ] Backup file created in backups/
- [ ] Can extract and view contents

---

## SUMMARY

**Changes:**
1. **Script 2:** Add proxy config generation BEFORE deployment (minimal intrusion)
2. **Script 3:** Complete rewrite with menu-driven interface (modular functions)

**Benefits:**
- Services accessible via configured URLs
- Script 3 becomes comprehensive management tool
- Maintains 5-script architecture
- Modular, easy to extend

**Estimated Time:** 7-10 hours total implementation

**Priority Order:**
1. Fix Script 2 proxy generation (CRITICAL)
2. Test URL accessibility
3. Implement Script 3 menu
4. Add service management functions
5. Add backup functions
