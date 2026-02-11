#!/bin/bash

#==============================================================================
# Script 4: Add Service
# Purpose: Add user-facing applications and custom services
# Features:
#   - Template-based service creation
#   - Pre-configured application stacks
#   - Custom service builder
#   - Service dependency management
#   - Auto-networking configuration
#==============================================================================

set -euo pipefail

#------------------------------------------------------------------------------
# Color Definitions
#------------------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

#------------------------------------------------------------------------------
# Global Variables
#------------------------------------------------------------------------------
SCRIPT_DIR=" $ (cd " $ (dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="/mnt/data"
METADATA_FILE=" $ DATA_DIR/metadata/deployment_info.json"

# Check if metadata exists
if [[ ! -f " $ METADATA_FILE" ]]; then
    echo -e "${RED}Error: Setup not completed. Run scripts 1-3 first.${NC}"
    exit 1
fi

# Load metadata
DATA_DIR= $ (jq -r '.data_directory' " $ METADATA_FILE")

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}AI PLATFORM AUTOMATION - ADD SERVICE${NC}             ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}Script 4 of 5${NC} - Deploy additional applications         ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}[STEP]${NC}  $ 1"
}

print_success() {
    echo -e " $ {GREEN}[✓]${NC}  $ 1"
}

print_error() {
    echo -e " $ {RED}[✗]${NC}  $ 1"
}

print_info() {
    echo -e " $ {YELLOW}[ℹ]${NC}  $ 1"
}

print_warning() {
    echo -e " $ {YELLOW}[⚠]${NC}  $ 1"
}

confirm() {
    local prompt=" $ 1"
    read -p " $ prompt [y/N]: " response
    [[ " $ response" =~ ^[Yy]$ ]]
}

pause() {
    echo ""
    read -p "Press Enter to continue..."
}

#------------------------------------------------------------------------------
# Main Menu
#------------------------------------------------------------------------------

main_menu() {
    while true; do
        print_header
        
        echo -e "${BOLD}Application Categories:${NC}"
        echo ""
        echo "[1]  📱 Chat/Messaging Applications"
        echo "[2]  🌐 Web Applications"
        echo "[3]  🤖 AI/ML Services"
        echo "[4]  📊 Analytics & Monitoring"
        echo "[5]  💾 Data Management"
        echo "[6]  🔧 Development Tools"
        echo "[7]  🎯 Custom Service Builder"
        echo "[8]  📋 View Deployed Services"
        echo "[9]  🗑️  Remove Service"
        echo "[Q]  Quit"
        echo ""
        
        read -p "Select category: " category
        
        case  $ category in
            1) chat_applications_menu ;;
            2) web_applications_menu ;;
            3) ai_ml_services_menu ;;
            4) analytics_monitoring_menu ;;
            5) data_management_menu ;;
            6) development_tools_menu ;;
            7) custom_service_builder ;;
            8) view_deployed_services ;;
            9) remove_service ;;
            [Qq]) exit 0 ;;
            *) print_error "Invalid option" ; pause ;;
        esac
    done
}

#------------------------------------------------------------------------------
# Category 1: Chat/Messaging Applications
#------------------------------------------------------------------------------

chat_applications_menu() {
    print_header
    echo -e " $ {BOLD}Chat/Messaging Applications${NC}"
    echo ""
    echo "[1] Matrix Synapse Server"
    echo "[2] Rocket.Chat"
    echo "[3] Mattermost"
    echo "[4] Element Web (Matrix client)"
    echo "[5] Zulip"
    echo "[B] Back"
    echo ""
    
    read -p "Selection: " choice
    
    case  $ choice in
        1) deploy_matrix_synapse ;;
        2) deploy_rocketchat ;;
        3) deploy_mattermost ;;
        4) deploy_element ;;
        5) deploy_zulip ;;
        [Bb]) return ;;
        *) print_error "Invalid option" ; pause ;;
    esac
}

deploy_matrix_synapse() {
    print_header
    echo -e " $ {BOLD}Deploy Matrix Synapse Server${NC}"
    echo ""
    
    print_info "Matrix Synapse is a federated chat server"
    echo ""
    
    read -p "Server name (e.g., matrix.example.com): " server_name
    read -p "Admin email: " admin_email
    
    if ! confirm "Deploy Matrix Synapse?"; then
        return
    fi
    
    print_step "Creating Matrix configuration..."
    
    local postgres_pass= $ (jq -r '.postgres.password' " $ DATA_DIR/metadata/credentials.json")
    
    cat > " $ DATA_DIR/compose/matrix.yml" <<EOF
version: '3.8'

services:
  synapse:
    image: matrixdotorg/synapse:latest
    container_name: matrix-synapse
    restart: unless-stopped
    environment:
      - SYNAPSE_SERVER_NAME= $ {server_name}
      - SYNAPSE_REPORT_STATS=no
    volumes:
      - /mnt/data/matrix:/data
    ports:
      - "8008:8008"
      - "8448:8448"
    networks:
      - ai_platform
    depends_on:
      - postgres

networks:
  ai_platform:
    external: true
EOF
    
    # Generate homeserver config
    docker run --rm \
        -v /mnt/data/matrix:/data \
        -e SYNAPSE_SERVER_NAME="$server_name" \
        -e SYNAPSE_REPORT_STATS=no \
        matrixdotorg/synapse:latest generate
    
    # Configure database
    cat >> /mnt/data/matrix/homeserver.yaml <<EOF

database:
  name: psycopg2
  args:
    user: matrix
    password: ${postgres_pass}
    database: matrix
    host: postgres
    cp_min: 5
    cp_max: 10
EOF
    
    # Create database
    docker exec postgres psql -U ai_user -d ai_platform <<SQL
CREATE DATABASE matrix;
CREATE USER matrix WITH PASSWORD '${postgres_pass}';
GRANT ALL PRIVILEGES ON DATABASE matrix TO matrix;
SQL
    
    print_step "Deploying Matrix Synapse..."
    docker compose -f " $ DATA_DIR/compose/matrix.yml" up -d
    
    sleep 5
    
    if docker ps | grep -q "matrix-synapse"; then
        print_success "Matrix Synapse deployed successfully"
        echo ""
        print_info "Access at: http://localhost:8008"
        print_info "Admin registration: docker exec -it matrix-synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

deploy_rocketchat() {
    print_header
    echo -e " $ {BOLD}Deploy Rocket.Chat${NC}"
    echo ""
    
    if ! confirm "Deploy Rocket.Chat?"; then
        return
    fi
    
    print_step "Deploying Rocket.Chat..."
    
    cat > " $ DATA_DIR/compose/rocketchat.yml" <<'EOF'
version: '3.8'

services:
  rocketchat:
    image: rocket.chat:latest
    container_name: rocketchat
    restart: unless-stopped
    environment:
      - MONGO_URL=mongodb://mongo:27017/rocketchat
      - MONGO_OPLOG_URL=mongodb://mongo:27017/local
      - ROOT_URL=http://localhost:3000
      - PORT=3000
    volumes:
      - /mnt/data/rocketchat/uploads:/app/uploads
    ports:
      - "3100:3000"
    networks:
      - ai_platform
    depends_on:
      - mongo

  mongo:
    image: mongo:5.0
    container_name: rocketchat-mongo
    restart: unless-stopped
    command: mongod --oplogSize 128 --replSet rs0
    volumes:
      - /mnt/data/rocketchat/db:/data/db
    networks:
      - ai_platform

  mongo-init-replica:
    image: mongo:5.0
    container_name: mongo-init-replica
    command: >
      bash -c "sleep 10 && mongo mongo:27017 --eval \"rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongo:27017'}]})\""
    networks:
      - ai_platform
    depends_on:
      - mongo

networks:
  ai_platform:
    external: true
EOF
    
    docker compose -f " $ DATA_DIR/compose/rocketchat.yml" up -d
    
    sleep 10
    
    if docker ps | grep -q "rocketchat"; then
        print_success "Rocket.Chat deployed successfully"
        echo ""
        print_info "Access at: http://localhost:3100"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

deploy_mattermost() {
    print_header
    echo -e "${BOLD}Deploy Mattermost${NC}"
    echo ""
    
    if ! confirm "Deploy Mattermost?"; then
        return
    fi
    
    local postgres_pass= $ (jq -r '.postgres.password' " $ DATA_DIR/metadata/credentials.json")
    
    # Create database
    docker exec postgres psql -U ai_user -d ai_platform <<SQL
CREATE DATABASE mattermost;
CREATE USER mmuser WITH PASSWORD '${postgres_pass}';
GRANT ALL PRIVILEGES ON DATABASE mattermost TO mmuser;
SQL
    
    cat > " $ DATA_DIR/compose/mattermost.yml" <<EOF
version: '3.8'

services:
  mattermost:
    image: mattermost/mattermost-team-edition:latest
    container_name: mattermost
    restart: unless-stopped
    environment:
      - MM_SQLSETTINGS_DRIVERNAME=postgres
      - MM_SQLSETTINGS_DATASOURCE=postgres://mmuser: $ {postgres_pass}@postgres:5432/mattermost?sslmode=disable&connect_timeout=10
      - MM_SERVICESETTINGS_SITEURL=http://localhost:8065
    volumes:
      - /mnt/data/mattermost/config:/mattermost/config
      - /mnt/data/mattermost/data:/mattermost/data
      - /mnt/data/mattermost/logs:/mattermost/logs
      - /mnt/data/mattermost/plugins:/mattermost/plugins
    ports:
      - "8065:8065"
    networks:
      - ai_platform
    depends_on:
      - postgres

networks:
  ai_platform:
    external: true
EOF
    
    docker compose -f " $ DATA_DIR/compose/mattermost.yml" up -d
    
    sleep 5
    
    if docker ps | grep -q "mattermost"; then
        print_success "Mattermost deployed successfully"
        echo ""
        print_info "Access at: http://localhost:8065"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

deploy_element() {
    print_header
    echo -e " $ {BOLD}Deploy Element Web${NC}"
    echo ""
    
    read -p "Matrix homeserver URL: " homeserver_url
    
    if ! confirm "Deploy Element Web?"; then
        return
    fi
    
    mkdir -p /mnt/data/element
    
    cat > /mnt/data/element/config.json <<EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "${homeserver_url}",
            "server_name": "$(echo  $ homeserver_url | sed 's|https\?://||')"
        }
    },
    "brand": "Element",
    "integrations_ui_url": "https://scalar.vector.im/",
    "integrations_rest_url": "https://scalar.vector.im/api",
    "integrations_widgets_urls": [
        "https://scalar.vector.im/_matrix/integrations/v1",
        "https://scalar.vector.im/api",
        "https://scalar-staging.vector.im/_matrix/integrations/v1",
        "https://scalar-staging.vector.im/api",
        "https://scalar-staging.riot.im/scalar/api"
    ],
    "bug_report_endpoint_url": "https://element.io/bugreports/submit",
    "defaultCountryCode": "US",
    "showLabsSettings": true,
    "features": {
        "feature_pinning": "labs",
        "feature_custom_status": "labs",
        "feature_custom_tags": "labs",
        "feature_state_counters": "labs"
    },
    "default_federate": true,
    "default_theme": "dark",
    "roomDirectory": {
        "servers": ["matrix.org"]
    },
    "welcomeUserId": "@riot-bot:matrix.org",
    "piwik": false
}
EOF
    
    cat > " $ DATA_DIR/compose/element.yml" <<'EOF'
version: '3.8'

services:
  element:
    image: vectorim/element-web:latest
    container_name: element-web
    restart: unless-stopped
    volumes:
      - /mnt/data/element/config.json:/app/config.json
    ports:
      - "8009:80"
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF
    
    docker compose -f " $ DATA_DIR/compose/element.yml" up -d
    
    sleep 3
    
    if docker ps | grep -q "element-web"; then
        print_success "Element Web deployed successfully"
        echo ""
        print_info "Access at: http://localhost:8009"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

deploy_zulip() {
    print_header
    echo -e " $ {BOLD}Deploy Zulip${NC}"
    echo ""
    
    print_warning "Zulip requires significant resources (4GB+ RAM recommended)"
    echo ""
    
    if ! confirm "Deploy Zulip?"; then
        return
    fi
    
    read -p "Organization name: " org_name
    read -p "Admin email: " admin_email
    
    cat > " $ DATA_DIR/compose/zulip.yml" <<EOF
version: '3.8'

services:
  zulip:
    image: zulip/docker-zulip:latest
    container_name: zulip
    restart: unless-stopped
    environment:
      - SETTING_EXTERNAL_HOST=localhost:9991
      - SETTING_ZULIP_ADMINISTRATOR= $ {admin_email}
      - SECRETS_email_password=
      - SETTING_EMAIL_HOST=
      - SETTING_EMAIL_HOST_USER=${admin_email}
    volumes:
      - /mnt/data/zulip:/data
    ports:
      - "9991:80"
      - "9443:443"
    networks:
      - ai_platform
    depends_on:
      - postgres
      - redis

networks:
  ai_platform:
    external: true
EOF
    
    docker compose -f " $ DATA_DIR/compose/zulip.yml" up -d
    
    sleep 10
    
    if docker ps | grep -q "zulip"; then
        print_success "Zulip deployed successfully"
        echo ""
        print_info "Access at: http://localhost:9991"
        print_info "Complete setup in web interface"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

#------------------------------------------------------------------------------
# Category 2: Web Applications
#------------------------------------------------------------------------------

web_applications_menu() {
    print_header
    echo -e " $ {BOLD}Web Applications${NC}"
    echo ""
    echo "[1] WordPress + MySQL"
    echo "[2] Ghost Blog"
    echo "[3] Wiki.js"
    echo "[4] BookStack"
    echo "[5] Outline Knowledge Base"
    echo "[6] Nginx Proxy Manager"
    echo "[B] Back"
    echo ""
    
    read -p "Selection: " choice
    
    case  $ choice in
        1) deploy_wordpress ;;
        2) deploy_ghost ;;
        3) deploy_wikijs ;;
        4) deploy_bookstack ;;
        5) deploy_outline ;;
        6) deploy_nginx_proxy ;;
        [Bb]) return ;;
        *) print_error "Invalid option" ; pause ;;
    esac
}

deploy_wordpress() {
    print_header
    echo -e " $ {BOLD}Deploy WordPress${NC}"
    echo ""
    
    if ! confirm "Deploy WordPress?"; then
        return
    fi
    
    local db_pass= $ (openssl rand -base64 16)
    
    cat > " $ DATA_DIR/compose/wordpress.yml" <<EOF
version: '3.8'

services:
  wordpress:
    image: wordpress:latest
    container_name: wordpress
    restart: unless-stopped
    environment:
      - WORDPRESS_DB_HOST=wordpress-mysql
      - WORDPRESS_DB_NAME=wordpress
      - WORDPRESS_DB_USER=wordpress
      - WORDPRESS_DB_PASSWORD=${db_pass}
    volumes:
      - /mnt/data/wordpress:/var/www/html
    ports:
      - "8080:80"
    networks:
      - ai_platform
    depends_on:
      - wordpress-mysql

  wordpress-mysql:
    image: mysql:8.0
    container_name: wordpress-mysql
    restart: unless-stopped
    environment:
      - MYSQL_DATABASE=wordpress
      - MYSQL_USER=wordpress
      - MYSQL_PASSWORD=${db_pass}
      - MYSQL_RANDOM_ROOT_PASSWORD=1
    volumes:
      - /mnt/data/wordpress-db:/var/lib/mysql
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF
    
    docker compose -f "$DATA_DIR/compose/wordpress.yml" up -d
    
    sleep 5
    
    if docker ps | grep -q "wordpress"; then
        print_success "WordPress deployed successfully"
        echo ""
        print_info "Access at: http://localhost:8080"
        print_info "Database password:  $ db_pass"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

deploy_ghost() {
    print_header
    echo -e " $ {BOLD}Deploy Ghost Blog${NC}"
    echo ""
    
    if ! confirm "Deploy Ghost?"; then
        return
    fi
    
    local db_pass= $ (openssl rand -base64 16)
    
    cat > " $ DATA_DIR/compose/ghost.yml" <<EOF
version: '3.8'

services:
  ghost:
    image: ghost:latest
    container_name: ghost
    restart: unless-stopped
    environment:
      - database__client=mysql
      - database__connection__host=ghost-mysql
      - database__connection__user=ghost
      - database__connection__password=${db_pass}
      - database__connection__database=ghost
      - url=http://localhost:2368
    volumes:
      - /mnt/data/ghost:/var/lib/ghost/content
    ports:
      - "2368:2368"
    networks:
      - ai_platform
    depends_on:
      - ghost-mysql

  ghost-mysql:
    image: mysql:8.0
    container_name: ghost-mysql
    restart: unless-stopped
    environment:
      - MYSQL_DATABASE=ghost
      - MYSQL_USER=ghost
      - MYSQL_PASSWORD=${db_pass}
      - MYSQL_RANDOM_ROOT_PASSWORD=1
    volumes:
      - /mnt/data/ghost-db:/var/lib/mysql
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF
    
    docker compose -f " $ DATA_DIR/compose/ghost.yml" up -d
    
    sleep 5
    
    if docker ps | grep -q "ghost"; then
        print_success "Ghost deployed successfully"
        echo ""
        print_info "Access at: http://localhost:2368"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

deploy_wikijs() {
    print_header
    echo -e " $ {BOLD}Deploy Wiki.js${NC}"
    echo ""
    
    if ! confirm "Deploy Wiki.js?"; then
        return
    fi
    
    local postgres_pass= $ (jq -r '.postgres.password' " $ DATA_DIR/metadata/credentials.json")
    
    # Create database
    docker exec postgres psql -U ai_user -d ai_platform <<SQL
CREATE DATABASE wikijs;
CREATE USER wikijs WITH PASSWORD '${postgres_pass}';
GRANT ALL PRIVILEGES ON DATABASE wikijs TO wikijs;
SQL
    
    cat > " $ DATA_DIR/compose/wikijs.yml" <<EOF
version: '3.8'

services:
  wikijs:
    image: ghcr.io/requarks/wiki:2
    container_name: wikijs
    restart: unless-stopped
    environment:
      - DB_TYPE=postgres
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=wikijs
      - DB_PASS= $ {postgres_pass}
      - DB_NAME=wikijs
    ports:
      - "3001:3000"
    networks:
      - ai_platform
    depends_on:
      - postgres

networks:
  ai_platform:
    external: true
EOF
    
    docker compose -f " $ DATA_DIR/compose/wikijs.yml" up -d
    
    sleep 5
    
    if docker ps | grep -q "wikijs"; then
        print_success "Wiki.js deployed successfully"
        echo ""
        print_info "Access at: http://localhost:3001"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

deploy_bookstack() {
    print_header
    echo -e " $ {BOLD}Deploy BookStack${NC}"
    echo ""
    
    if ! confirm "Deploy BookStack?"; then
        return
    fi
    
    local db_pass= $ (openssl rand -base64 16)
    
    cat > " $ DATA_DIR/compose/bookstack.yml" <<EOF
version: '3.8'

services:
  bookstack:
    image: lscr.io/linuxserver/bookstack:latest
    container_name: bookstack
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - APP_URL=http://localhost:6875
      - DB_HOST=bookstack-mysql
      - DB_DATABASE=bookstack
      - DB_USERNAME=bookstack
      - DB_PASSWORD=${db_pass}
    volumes:
      - /mnt/data/bookstack:/config
    ports:
      - "6875:80"
    networks:
      - ai_platform
    depends_on:
      - bookstack-mysql

  bookstack-mysql:
    image: mysql:8.0
    container_name: bookstack-mysql
    restart: unless-stopped
    environment:
      - MYSQL_DATABASE=bookstack
      - MYSQL_USER=bookstack
      - MYSQL_PASSWORD=${db_pass}
      - MYSQL_RANDOM_ROOT_PASSWORD=1
    volumes:
      - /mnt/data/bookstack-db:/var/lib/mysql
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF
    
    docker compose -f " $ DATA_DIR/compose/bookstack.yml" up -d
    
    sleep 5
    
    if docker ps | grep -q "bookstack"; then
        print_success "BookStack deployed successfully"
        echo ""
        print_info "Access at: http://localhost:6875"
        print_info "Default login: admin@admin.com / password"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

deploy_outline() {
    print_header
    echo -e " $ {BOLD}Deploy Outline Knowledge Base${NC}"
    echo ""
    
    print_warning "Outline requires S3-compatible storage"
    echo ""
    
    if ! confirm "Deploy Outline?"; then
        return
    fi
    
    read -p "S3 endpoint URL: " s3_url
    read -p "S3 access key: " s3_key
    read -sp "S3 secret key: " s3_secret
    echo ""
    read -p "S3 bucket name: " s3_bucket
    
    local postgres_pass= $ (jq -r '.postgres.password' " $ DATA_DIR/metadata/credentials.json")
    local redis_pass= $ (jq -r '.redis.password' " $ DATA_DIR/metadata/credentials.json")
    local secret_key= $ (openssl rand -hex 32)
    local utils_secret= $ (openssl rand -hex 32)
    
    # Create database
    docker exec postgres psql -U ai_user -d ai_platform <<SQL
CREATE DATABASE outline;
CREATE USER outline WITH PASSWORD '${postgres_pass}';
GRANT ALL PRIVILEGES ON DATABASE outline TO outline;
SQL
    
    cat > " $ DATA_DIR/compose/outline.yml" <<EOF
version: '3.8'

services:
  outline:
    image: outlinewiki/outline:latest
    container_name: outline
    restart: unless-stopped
    environment:
      - NODE_ENV=production
      - SECRET_KEY= $ {secret_key}
      - UTILS_SECRET=${utils_secret}
      - DATABASE_URL=postgres://outline:${postgres_pass}@postgres:5432/outline
      - REDIS_URL=redis://:${redis_pass}@redis:6379
      - URL=http://localhost:3002
      - PORT=3000
      - AWS_ACCESS_KEY_ID=${s3_key}
      - AWS_SECRET_ACCESS_KEY=${s3_secret}
      - AWS_REGION=us-east-1
      - AWS_S3_UPLOAD_BUCKET_URL=${s3_url}
      - AWS_S3_UPLOAD_BUCKET_NAME=${s3_bucket}
      - AWS_S3_FORCE_PATH_STYLE=true
      - AWS_S3_ACL=private
    ports:
      - "3002:3000"
    networks:
      - ai_platform
    depends_on:
      - postgres
      - redis

networks:
  ai_platform:
    external: true
EOF
    
    docker compose -f " $ DATA_DIR/compose/outline.yml" up -d
    
    sleep 5
    
    if docker ps | grep -q "outline"; then
        print_success "Outline deployed successfully"
        echo ""
        print_info "Access at: http://localhost:3002"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

deploy_nginx_proxy() {
    print_header
    echo -e " $ {BOLD}Deploy Nginx Proxy Manager${NC}"
    echo ""
    
    if ! confirm "Deploy Nginx Proxy Manager?"; then
        return
    fi
    
    cat > " $ DATA_DIR/compose/nginx-proxy.yml" <<'EOF'
version: '3.8'

services:
  nginx-proxy:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    volumes:
      - /mnt/data/nginx-proxy/data:/data
      - /mnt/data/nginx-proxy/letsencrypt:/etc/letsencrypt
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF
    
    docker compose -f " $ DATA_DIR/compose/nginx-proxy.yml" up -d
    
    sleep 5
    
    if docker ps | grep -q "nginx-proxy-manager"; then
        print_success "Nginx Proxy Manager deployed successfully"
        echo ""
        print_info "Access admin panel at: http://localhost:81"
        print_info "Default credentials:"
        print_info "  Email: admin@example.com"
        print_info "  Password: changeme"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

#------------------------------------------------------------------------------
# Category 3: AI/ML Services
#------------------------------------------------------------------------------

ai_ml_services_menu() {
    print_header
    echo -e "${BOLD}AI/ML Services${NC}"
    echo ""
    echo "[1] Jupyter Notebook"
    echo "[2] MLflow (ML experiment tracking)"
    echo "[3] Label Studio (data labeling)"
    echo "[4] Hugging Face Text Generation Inference"
    echo "[5] Stable Diffusion WebUI"
    echo "[6] ComfyUI"
    echo "[B] Back"
    echo ""
    
    read -p "Selection: " choice
    
    case  $ choice in
        1) deploy_jupyter ;;
        2) deploy_mlflow ;;
        3) deploy_labelstudio ;;
        4) deploy_tgi ;;
        5) deploy_stable_diffusion ;;
        6) deploy_comfyui ;;
        [Bb]) return ;;
        *) print_error "Invalid option" ; pause ;;
    esac
}

deploy_jupyter() {
    print_header
    echo -e " $ {BOLD}Deploy Jupyter Notebook${NC}"
    echo ""
    
    local gpu_available= $ (jq -r '.gpu_available' " $ METADATA_FILE")
    
    if [[ "$gpu_available" == "true" ]]; then
        echo "GPU support: ${GREEN}Available${NC}"
        if ! confirm "Deploy with GPU support?"; then
            gpu_available="false"
        fi
    fi
    
    local token= $ (openssl rand -hex 16)
    
    if [[ " $ gpu_available" == "true" ]]; then
        cat > " $ DATA_DIR/compose/jupyter.yml" <<EOF
version: '3.8'

services:
  jupyter:
    image: jupyter/tensorflow-notebook:latest
    container_name: jupyter
    restart: unless-stopped
    environment:
      - JUPYTER_ENABLE_LAB=yes
      - JUPYTER_TOKEN= $ {token}
    volumes:
      - /mnt/data/jupyter:/home/jovyan/work
    ports:
      - "8888:8888"
    networks:
      - ai_platform
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

networks:
  ai_platform:
    external: true
EOF
    else
        cat > " $ DATA_DIR/compose/jupyter.yml" <<EOF
version: '3.8'

services:
  jupyter:
    image: jupyter/scipy-notebook:latest
    container_name: jupyter
    restart: unless-stopped
    environment:
      - JUPYTER_ENABLE_LAB=yes
      - JUPYTER_TOKEN= $ {token}
    volumes:
      - /mnt/data/jupyter:/home/jovyan/work
    ports:
      - "8888:8888"
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF
    fi
    
    docker compose -f "$DATA_DIR/compose/jupyter.yml" up -d
    
    sleep 5
    
    if docker ps | grep -q "jupyter"; then
        print_success "Jupyter deployed successfully"
        echo ""
        print_info "Access at: http://localhost:8888"
        print_info "Token:  $ token"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

deploy_mlflow() {
    print_header
    echo -e " $ {BOLD}Deploy MLflow${NC}"
    echo ""
    
    if ! confirm "Deploy MLflow?"; then
        return
    fi
    
    local postgres_pass= $ (jq -r '.postgres.password' " $ DATA_DIR/metadata/credentials.json")
    
    # Create database
    docker exec postgres psql -U ai_user -d ai_platform <<SQL
CREATE DATABASE mlflow;
CREATE USER mlflow WITH PASSWORD '${postgres_pass}';
GRANT ALL PRIVILEGES ON DATABASE mlflow TO mlflow;
SQL
    
    cat > " $ DATA_DIR/compose/mlflow.yml" <<EOF
version: '3.8'

services:
  mlflow:
    image: ghcr.io/mlflow/mlflow:latest
    container_name: mlflow
    restart: unless-stopped
    command: >
      mlflow server
      --backend-store-uri postgresql://mlflow: $ {postgres_pass}@postgres:5432/mlflow
      --default-artifact-root /mlflow/artifacts
      --host 0.0.0.0
      --port 5000
    volumes:
      - /mnt/data/mlflow:/mlflow
    ports:
      - "5000:5000"
    networks:
      - ai_platform
    depends_on:
      - postgres

networks:
  ai_platform:
    external: true
EOF
    
    docker compose -f " $ DATA_DIR/compose/mlflow.yml" up -d
    
    sleep 5
    
    if docker ps | grep -q "mlflow"; then
        print_success "MLflow deployed successfully"
        echo ""
        print_info "Access at: http://localhost:5000"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

deploy_labelstudio() {
    print_header
    echo -e " $ {BOLD}Deploy Label Studio${NC}"
    echo ""
    
    if ! confirm "Deploy Label Studio?"; then
        return
    fi
    
    local postgres_pass= $ (jq -r '.postgres.password' " $ DATA_DIR/metadata/credentials.json")
    
    # Create database
    docker exec postgres psql -U ai_user -d ai_platform <<SQL
CREATE DATABASE labelstudio;
CREATE USER labelstudio WITH PASSWORD '${postgres_pass}';
GRANT ALL PRIVILEGES ON DATABASE labelstudio TO labelstudio;
SQL
    
    cat > " $ DATA_DIR/compose/labelstudio.yml" <<EOF
version: '3.8'

services:
  labelstudio:
    image: heartexlabs/label-studio:latest
    container_name: labelstudio
    restart: unless-stopped
    environment:
      - DJANGO_DB=default
      - POSTGRE_NAME=labelstudio
      - POSTGRE_USER=labelstudio
      - POSTGRE_PASSWORD= $ {postgres_pass}
      - POSTGRE_PORT=5432
      - POSTGRE_HOST=postgres
    volumes:
      - /mnt/data/labelstudio:/label-studio/data
    ports:
      - "8090:8080"
    networks:
      - ai_platform
    depends_on:
      - postgres

networks:
  ai_platform:
    external: true
EOF
    
    docker compose -f " $ DATA_DIR/compose/labelstudio.yml" up -d
    
    sleep 5
    
    if docker ps | grep -q "labelstudio"; then
        print_success "Label Studio deployed successfully"
        echo ""
        print_info "Access at: http://localhost:8090"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

deploy_tgi() {
    print_header
    echo -e " $ {BOLD}Deploy Hugging Face Text Generation Inference${NC}"
    echo ""
    
    local gpu_available= $ (jq -r '.gpu_available' " $ METADATA_FILE")
    
    if [[ " $ gpu_available" != "true" ]]; then
        print_warning "GPU not available. TGI performance will be limited."
        if ! confirm "Continue anyway?"; then
            return
        fi
    fi
    
    read -p "Model ID (e.g., mistralai/Mistral-7B-v0.1): " model_id
    
    cat > " $ DATA_DIR/compose/tgi.yml" <<EOF
version: '3.8'

services:
  tgi:
    image: ghcr.io/huggingface/text-generation-inference:latest
    container_name: tgi
    restart: unless-stopped
    command: --model-id ${model_id}
    volumes:
      - /mnt/data/tgi:/data
    ports:
      - "8081:80"
    networks:
      - ai_platform
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

networks:
  ai_platform:
    external: true
EOF
    
    docker compose -f " $ DATA_DIR/compose/tgi.yml" up -d
    
    print_info "Downloading model... This may take a while."
    sleep 10
    
    if docker ps | grep -q "tgi"; then
        print_success "TGI deployed successfully"
        echo ""
        print_info "Access at: http://localhost:8081"
    else
        print_error "Deployment failed"
    fi
    
    pause
}

deploy_stable_diffusion() {
    print_header
    echo -e " $ {BOLD}Deploy Stable Diffusion WebUI${NC}"
    echo ""
    
    local gpu_available= $ (jq -r '.gpu_available' " $ METADATA_FILE")
    
    if [[ " $ gpu_available" != "true" ]]; then
        print_error "GPU required for Stable Diffusion"
        pause
        return
    fi
    
    if ! confirm "Deploy Stable Diffusion WebUI?"; then
        return
    fi
    
    cat > " $ DATA_DIR/compose/stable-diffusion.yml" <<'EOF'
version: '3.8'

services:
  stable-diffusion:
    image: ghcr.io/AUTOMATIC1111/stable-diffusion-webui:latest
    container_name: stable-diffusion-webui
    restart: unless-stopped
    command: --listen --port 7860
    volumes:
      - /mnt/data/stable-diffusion:/data
 ports:
      - "7860:7860"
    networks:
      - ai_platform
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/stable-diffusion.yml" up -d

    sleep 10

    if docker ps | grep -q "stable-diffusion-webui"; then
        print_success "Stable Diffusion WebUI deployed successfully"
        echo ""
        print_info "Access at: http://localhost:7860"
        print_info "First launch will download models (may take time)"
    else
        print_error "Deployment failed"
    fi

    pause
}

deploy_comfyui() {
    print_header
    echo -e "${BOLD}Deploy ComfyUI${NC}"
    echo ""

    local gpu_available=$(jq -r '.gpu_available' "$METADATA_FILE")

    if [[ "$gpu_available" != "true" ]]; then
        print_error "GPU required for ComfyUI"
        pause
        return
    fi

    if ! confirm "Deploy ComfyUI?"; then
        return
    fi

    cat > "$DATA_DIR/compose/comfyui.yml" <<'EOF'
version: '3.8'

services:
  comfyui:
    image: yanwk/comfyui-boot:latest
    container_name: comfyui
    restart: unless-stopped
    volumes:
      - /mnt/data/comfyui:/root
    ports:
      - "8188:8188"
    networks:
      - ai_platform
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/comfyui.yml" up -d

    sleep 5

    if docker ps | grep -q "comfyui"; then
        print_success "ComfyUI deployed successfully"
        echo ""
        print_info "Access at: http://localhost:8188"
    else
        print_error "Deployment failed"
    fi

    pause
}

#------------------------------------------------------------------------------
# Category 4: Analytics & Monitoring
#------------------------------------------------------------------------------

analytics_monitoring_menu() {
    print_header
    echo -e "${BOLD}Analytics & Monitoring${NC}"
    echo ""
    echo "[1] Grafana + Prometheus"
    echo "[2] Metabase"
    echo "[3] Redash"
    echo "[4] Uptime Kuma"
    echo "[5] Netdata"
    echo "[B] Back"
    echo ""

    read -p "Selection: " choice

    case $choice in
        1) deploy_grafana_prometheus ;;
        2) deploy_metabase ;;
        3) deploy_redash ;;
        4) deploy_uptime_kuma ;;
        5) deploy_netdata ;;
        [Bb]) return ;;
        *) print_error "Invalid option" ; pause ;;
    esac
}

deploy_grafana_prometheus() {
    print_header
    echo -e "${BOLD}Deploy Grafana + Prometheus${NC}"
    echo ""

    if ! confirm "Deploy monitoring stack?"; then
        return
    fi

    # Create Prometheus config
    mkdir -p /mnt/data/prometheus

    cat > /mnt/data/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
EOF

    cat > "$DATA_DIR/compose/monitoring.yml" <<'EOF'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    volumes:
      - /mnt/data/prometheus:/etc/prometheus
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"
    networks:
      - ai_platform

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana-data:/var/lib/grafana
    ports:
      - "3000:3000"
    networks:
      - ai_platform
    depends_on:
      - prometheus

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    ports:
      - "9100:9100"
    networks:
      - ai_platform

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    privileged: true
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    ports:
      - "8082:8080"
    networks:
      - ai_platform

volumes:
  prometheus-data:
  grafana-data:

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/monitoring.yml" up -d

    sleep 5

    if docker ps | grep -q "grafana"; then
        print_success "Monitoring stack deployed successfully"
        echo ""
        print_info "Grafana: http://localhost:3000 (admin/admin)"
        print_info "Prometheus: http://localhost:9090"
        print_info "Node Exporter: http://localhost:9100"
        print_info "cAdvisor: http://localhost:8082"
    else
        print_error "Deployment failed"
    fi

    pause
}

deploy_metabase() {
    print_header
    echo -e "${BOLD}Deploy Metabase${NC}"
    echo ""

    if ! confirm "Deploy Metabase?"; then
        return
    fi

    cat > "$DATA_DIR/compose/metabase.yml" <<'EOF'
version: '3.8'

services:
  metabase:
    image: metabase/metabase:latest
    container_name: metabase
    restart: unless-stopped
    environment:
      - MB_DB_FILE=/metabase-data/metabase.db
    volumes:
      - /mnt/data/metabase:/metabase-data
    ports:
      - "3003:3000"
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/metabase.yml" up -d

    sleep 5

    if docker ps | grep -q "metabase"; then
        print_success "Metabase deployed successfully"
        echo ""
        print_info "Access at: http://localhost:3003"
    else
        print_error "Deployment failed"
    fi

    pause
}

deploy_redash() {
    print_header
    echo -e "${BOLD}Deploy Redash${NC}"
    echo ""

    if ! confirm "Deploy Redash?"; then
        return
    fi

    local postgres_pass=$(jq -r '.postgres.password' "$DATA_DIR/metadata/credentials.json")
    local redis_pass=$(jq -r '.redis.password' "$DATA_DIR/metadata/credentials.json")
    local cookie_secret=$(openssl rand -base64 32)
    local secret_key=$(openssl rand -base64 32)

    # Create database
    docker exec postgres psql -U ai_user -d ai_platform <<SQL
CREATE DATABASE redash;
CREATE USER redash WITH PASSWORD '${postgres_pass}';
GRANT ALL PRIVILEGES ON DATABASE redash TO redash;
SQL

    cat > "$DATA_DIR/compose/redash.yml" <<EOF
version: '3.8'

services:
  redash:
    image: redash/redash:latest
    container_name: redash
    restart: unless-stopped
    command: server
    environment:
      - PYTHONUNBUFFERED=0
      - REDASH_LOG_LEVEL=INFO
      - REDASH_REDIS_URL=redis://:${redis_pass}@redis:6379/0
      - REDASH_DATABASE_URL=postgresql://redash:${postgres_pass}@postgres:5432/redash
      - REDASH_COOKIE_SECRET=${cookie_secret}
      - REDASH_SECRET_KEY=${secret_key}
      - REDASH_WEB_WORKERS=4
    ports:
      - "5001:5000"
    networks:
      - ai_platform
    depends_on:
      - postgres
      - redis

  redash-scheduler:
    image: redash/redash:latest
    container_name: redash-scheduler
    restart: unless-stopped
    command: scheduler
    environment:
      - REDASH_REDIS_URL=redis://:${redis_pass}@redis:6379/0
      - REDASH_DATABASE_URL=postgresql://redash:${postgres_pass}@postgres:5432/redash
      - QUEUES=celery
      - WORKERS_COUNT=1
    networks:
      - ai_platform
    depends_on:
      - postgres
      - redis

  redash-worker:
    image: redash/redash:latest
    container_name: redash-worker
    restart: unless-stopped
    command: worker
    environment:
      - PYTHONUNBUFFERED=0
      - REDASH_LOG_LEVEL=INFO
      - REDASH_REDIS_URL=redis://:${redis_pass}@redis:6379/0
      - REDASH_DATABASE_URL=postgresql://redash:${postgres_pass}@postgres:5432/redash
      - QUEUES=queries,scheduled_queries,celery
      - WORKERS_COUNT=2
    networks:
      - ai_platform
    depends_on:
      - postgres
      - redis

networks:
  ai_platform:
    external: true
EOF

    # Initialize database
    docker compose -f "$DATA_DIR/compose/redash.yml" run --rm redash create_db

    docker compose -f "$DATA_DIR/compose/redash.yml" up -d

    sleep 5

    if docker ps | grep -q "redash"; then
        print_success "Redash deployed successfully"
        echo ""
        print_info "Access at: http://localhost:5001"
    else
        print_error "Deployment failed"
    fi

    pause
}

deploy_uptime_kuma() {
    print_header
    echo -e "${BOLD}Deploy Uptime Kuma${NC}"
    echo ""

    if ! confirm "Deploy Uptime Kuma?"; then
        return
    fi

    cat > "$DATA_DIR/compose/uptime-kuma.yml" <<'EOF'
version: '3.8'

services:
  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    restart: unless-stopped
    volumes:
      - /mnt/data/uptime-kuma:/app/data
    ports:
      - "3005:3001"
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/uptime-kuma.yml" up -d

    sleep 5

    if docker ps | grep -q "uptime-kuma"; then
        print_success "Uptime Kuma deployed successfully"
        echo ""
        print_info "Access at: http://localhost:3005"
    else
        print_error "Deployment failed"
    fi

    pause
}

deploy_netdata() {
    print_header
    echo -e "${BOLD}Deploy Netdata${NC}"
    echo ""

    if ! confirm "Deploy Netdata?"; then
        return
    fi

    cat > "$DATA_DIR/compose/netdata.yml" <<'EOF'
version: '3.8'

services:
  netdata:
    image: netdata/netdata:latest
    container_name: netdata
    restart: unless-stopped
    cap_add:
      - SYS_PTRACE
    security_opt:
      - apparmor:unconfined
    volumes:
      - /etc/passwd:/host/etc/passwd:ro
      - /etc/group:/host/etc/group:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports:
      - "19999:19999"
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/netdata.yml" up -d

    sleep 5

    if docker ps | grep -q "netdata"; then
        print_success "Netdata deployed successfully"
        echo ""
        print_info "Access at: http://localhost:19999"
    else
        print_error "Deployment failed"
    fi

    pause
}

#------------------------------------------------------------------------------
# Category 5: Data Management
#------------------------------------------------------------------------------

data_management_menu() {
    print_header
    echo -e "${BOLD}Data Management${NC}"
    echo ""
    echo "[1] pgAdmin (PostgreSQL GUI)"
    echo "[2] Redis Commander"
    echo "[3] MinIO (S3-compatible storage)"
    echo "[4] FileBrowser"
    echo "[5] Nextcloud"
    echo "[B] Back"
    echo ""

    read -p "Selection: " choice

    case $choice in
        1) deploy_pgadmin ;;
        2) deploy_redis_commander ;;
        3) deploy_minio ;;
        4) deploy_filebrowser ;;
        5) deploy_nextcloud ;;
        [Bb]) return ;;
        *) print_error "Invalid option" ; pause ;;
    esac
}

deploy_pgadmin() {
    print_header
    echo -e "${BOLD}Deploy pgAdmin${NC}"
    echo ""

    read -p "Admin email: " admin_email
    read -sp "Admin password: " admin_pass
    echo ""

    if ! confirm "Deploy pgAdmin?"; then
        return
    fi

    cat > "$DATA_DIR/compose/pgadmin.yml" <<EOF
version: '3.8'

services:
  pgadmin:
    image: dpage/pgadmin4:latest
    container_name: pgadmin
    restart: unless-stopped
    environment:
      - PGADMIN_DEFAULT_EMAIL=${admin_email}
      - PGADMIN_DEFAULT_PASSWORD=${admin_pass}
      - PGADMIN_CONFIG_SERVER_MODE=False
    volumes:
      - /mnt/data/pgadmin:/var/lib/pgadmin
    ports:
      - "5050:80"
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/pgadmin.yml" up -d

    sleep 5

    if docker ps | grep -q "pgadmin"; then
        print_success "pgAdmin deployed successfully"
        echo ""
        print_info "Access at: http://localhost:5050"
        print_info "Login with: $admin_email"
    else
        print_error "Deployment failed"
    fi

    pause
}

deploy_redis_commander() {
    print_header
    echo -e "${BOLD}Deploy Redis Commander${NC}"
    echo ""

    if ! confirm "Deploy Redis Commander?"; then
        return
    fi

    local redis_pass=$(jq -r '.redis.password' "$DATA_DIR/metadata/credentials.json")

    cat > "$DATA_DIR/compose/redis-commander.yml" <<EOF
version: '3.8'

services:
  redis-commander:
    image: rediscommander/redis-commander:latest
    container_name: redis-commander
    restart: unless-stopped
    environment:
      - REDIS_HOSTS=local:redis:6379:0:${redis_pass}
    ports:
      - "8081:8081"
    networks:
      - ai_platform
    depends_on:
      - redis

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/redis-commander.yml" up -d

    sleep 3

    if docker ps | grep -q "redis-commander"; then
        print_success "Redis Commander deployed successfully"
        echo ""
        print_info "Access at: http://localhost:8081"
    else
        print_error "Deployment failed"
    fi

    pause
}

deploy_minio() {
    print_header
    echo -e "${BOLD}Deploy MinIO${NC}"
    echo ""

    read -p "Root user: " root_user
    read -sp "Root password (min 8 chars): " root_pass
    echo ""

    if ! confirm "Deploy MinIO?"; then
        return
    fi

    cat > "$DATA_DIR/compose/minio.yml" <<EOF
version: '3.8'

services:
  minio:
    image: minio/minio:latest
    container_name: minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      - MINIO_ROOT_USER=${root_user}
      - MINIO_ROOT_PASSWORD=${root_pass}
    volumes:
      - /mnt/data/minio:/data
    ports:
      - "9000:9000"
      - "9001:9001"
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/minio.yml" up -d

    sleep 5

    if docker ps | grep -q "minio"; then
        print_success "MinIO deployed successfully"
        echo ""
        print_info "API: http://localhost:9000"
        print_info "Console: http://localhost:9001"
    else
        print_error "Deployment failed"
    fi

    pause
}

deploy_filebrowser() {
    print_header
    echo -e "${BOLD}Deploy FileBrowser${NC}"
    echo ""

    if ! confirm "Deploy FileBrowser?"; then
        return
    fi

    cat > "$DATA_DIR/compose/filebrowser.yml" <<'EOF'
version: '3.8'

services:
  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: filebrowser
    restart: unless-stopped
    volumes:
      - /mnt/data:/srv
      - /mnt/data/filebrowser/database.db:/database.db
      - /mnt/data/filebrowser/settings.json:/config/settings.json
    ports:
      - "8083:80"
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF

    mkdir -p /mnt/data/filebrowser

    docker compose -f "$DATA_DIR/compose/filebrowser.yml" up -d

    sleep 3

    if docker ps | grep -q "filebrowser"; then
        print_success "FileBrowser deployed successfully"
        echo ""
        print_info "Access at: http://localhost:8083"
        print_info "Default credentials: admin/admin"
    else
        print_error "Deployment failed"
    fi

    pause
}

deploy_nextcloud() {
    print_header
    echo -e "${BOLD}Deploy Nextcloud${NC}"
    echo ""

    if ! confirm "Deploy Nextcloud?"; then
        return
    fi

    local db_pass=$(openssl rand -base64 16)

    cat > "$DATA_DIR/compose/nextcloud.yml" <<EOF
version: '3.8'

services:
  nextcloud:
    image: nextcloud:latest
    container_name: nextcloud
    restart: unless-stopped
    environment:
      - POSTGRES_HOST=nextcloud-db
      - POSTGRES_DB=nextcloud
      - POSTGRES_USER=nextcloud
      - POSTGRES_PASSWORD=${db_pass}
    volumes:
      - /mnt/data/nextcloud:/var/www/html
    ports:
      - "8084:80"
    networks:
      - ai_platform
    depends_on:
      - nextcloud-db

  nextcloud-db:
    image: postgres:15
    container_name: nextcloud-db
    restart: unless-stopped
    environment:
      - POSTGRES_DB=nextcloud
      - POSTGRES_USER=nextcloud
      - POSTGRES_PASSWORD=${db_pass}
    volumes:
      - /mnt/data/nextcloud-db:/var/lib/postgresql/data
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/nextcloud.yml" up -d

    sleep 10

    if docker ps | grep -q "nextcloud"; then
        print_success "Nextcloud deployed successfully"
        echo ""
        print_info "Access at: http://localhost:8084"
        print_info "Complete setup in web interface"
    else
        print_error "Deployment failed"
    fi

    pause
}

#------------------------------------------------------------------------------
# Category 6: Development Tools
#------------------------------------------------------------------------------

development_tools_menu() {
    print_header
    echo -e "${BOLD}Development Tools${NC}"
    echo ""
    echo "[1] Code-Server (VS Code in browser)"
    echo "[2] GitLab"
    echo "[3] Gitea"
    echo "[4] Jenkins"
    echo "[5] Portainer"
    echo "[B] Back"
    echo ""

    read -p "Selection: " choice

    case $choice in
        1) deploy_code_server ;;
        2) deploy_gitlab ;;
        3) deploy_gitea ;;
        4) deploy_jenkins ;;
        5) deploy_portainer ;;
        [Bb]) return ;;
        *) print_error "Invalid option" ; pause ;;
    esac
}

deploy_code_server() {
    print_header
    echo -e "${BOLD}Deploy Code-Server${NC}"
    echo ""

    read -sp "Set password: " code_pass
    echo ""

    if ! confirm "Deploy Code-Server?"; then
        return
    fi

    cat > "$DATA_DIR/compose/code-server.yml" <<EOF
version: '3.8'

services:
  code-server:
    image: codercom/code-server:latest
    container_name: code-server
    restart: unless-stopped
    environment:
      - PASSWORD=${code_pass}
    volumes:
      - /mnt/data/code-server:/home/coder/project
    ports:
      - "8085:8080"
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/code-server.yml" up -d

    sleep 5

    if docker ps | grep -q "code-server"; then
        print_success "Code-Server deployed successfully"
        echo ""
        print_info "Access at: http://localhost:8085"
    else
        print_error "Deployment failed"
    fi

    pause
}

deploy_gitlab() {
    print_header
    echo -e "${BOLD}Deploy GitLab${NC}"
    echo ""

    print_warning "GitLab requires at least 4GB RAM"
    echo ""

    if ! confirm "Deploy GitLab?"; then
        return
    fi

    read -p "External URL (e.g., http://gitlab.local): " gitlab_url

    cat > "$DATA_DIR/compose/gitlab.yml" <<EOF
version: '3.8'

services:
  gitlab:
    image: gitlab/gitlab-ce:latest
    container_name: gitlab
    restart: unless-stopped
    hostname: 'gitlab.local'
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url '${gitlab_url}'
        gitlab_rails['gitlab_shell_ssh_port'] = 2224
    volumes:
      - /mnt/data/gitlab/config:/etc/gitlab
      - /mnt/data/gitlab/logs:/var/log/gitlab
      - /mnt/data/gitlab/data:/var/opt/gitlab
    ports:
      - "8086:80"
      - "8443:443"
      - "2224:22"
    networks:
      - ai_platform
    shm_size: '256m'

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/gitlab.yml" up -d

    print_info "GitLab is starting... This may take 2-3 minutes."
    sleep 10

    if docker ps | grep -q "gitlab"; then
        print_success "GitLab deployed successfully"
        echo ""
        print_info "Access at: http://localhost:8086"
        print_info "Get root password: docker exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password"
    else
        print_error "Deployment failed"
    fi

    pause
}

deploy_gitea() {
    print_header
    echo -e "${BOLD}Deploy Gitea${NC}"
    echo ""

    if ! confirm "Deploy Gitea?"; then
        return
    fi

    local postgres_pass=$(jq -r '.postgres.password' "$DATA_DIR/metadata/credentials.json")

    # Create database
    docker exec postgres psql -U ai_user -d ai_platform <<SQL
CREATE DATABASE gitea;
CREATE USER gitea WITH PASSWORD '${postgres_pass}';
GRANT ALL PRIVILEGES ON DATABASE gitea TO gitea;
SQL

    cat > "$DATA_DIR/compose/gitea.yml" <<EOF
version: '3.8'

services:
  gitea:
    image: gitea/gitea:latest
    container_name: gitea
    restart: unless-stopped
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=postgres:5432
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=gitea
      - GITEA__database__PASSWD=${postgres_pass}
    volumes:
      - /mnt/data/gitea:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "3006:3000"
      - "2223:22"
    networks:
      - ai_platform
    depends_on:
      - postgres

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/gitea.yml" up -d

    sleep 5

    if docker ps | grep -q "gitea"; then
        print_success "Gitea deployed successfully"
        echo ""
        print_info "Access at: http://localhost:3006"
    else
        print_error "Deployment failed"
    fi

    pause
}

deploy_jenkins() {
    print_header
    echo -e "${BOLD}Deploy Jenkins${NC}"
    echo ""

    if ! confirm "Deploy Jenkins?"; then
        return
    fi

    cat > "$DATA_DIR/compose/jenkins.yml" <<'EOF'
version: '3.8'

services:
  jenkins:
    image: jenkins/jenkins:lts
    container_name: jenkins
    restart: unless-stopped
    privileged: true
    user: root
    volumes:
      - /mnt/data/jenkins:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - "8087:8080"
      - "50000:50000"
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/jenkins.yml" up -d

    sleep 10

    if docker ps | grep -q "jenkins"; then
        print_success "Jenkins deployed successfully"
        echo ""
        print_info "Access at: http://localhost:8087"
        print_info "Get initial password: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
    else
        print_error "Deployment failed"
    fi

    pause
}

deploy_portainer() {
    print_header
    echo -e "${BOLD}Deploy Portainer${NC}"
    echo ""

    if ! confirm "Deploy Portainer?"; then
        return
    fi

    cat > "$DATA_DIR/compose/portainer.yml" <<'EOF'
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /mnt/data/portainer:/data
    ports:
      - "9000:9000"
      - "9443:9443"
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF

    docker compose -f "$DATA_DIR/compose/portainer.yml" up -d

    sleep 5

    if docker ps | grep -q "portainer"; then
        print_success "Portainer deployed successfully"
        echo ""
        print_info "Access at: https://localhost:9443"
    else
        print_error "Deployment failed"
    fi

    pause
}

#------------------------------------------------------------------------------
# Option 7: Custom Service Builder
#------------------------------------------------------------------------------

custom_service_builder() {
    print_header
    echo -e "${BOLD}Custom Service Builder${NC}"
    echo ""

    read -p "Service name: " service_name
    read -p "Docker image: " docker_image
    read -p "Container name: " container_name
    read -p "Port mapping (e.g., 8080:80): " port_mapping

    echo ""
    echo "Volumes (one per line, empty line to finish):"
    local volumes=()
    while true; do
        read -p "Volume: " vol
        [[ -z "$vol" ]] && break
        volumes+=("$vol")
    done

    echo ""
    echo "Environment variables (KEY=VALUE, one per line, empty line to finish):"
    local env_vars=()
    while true; do
        read -p "Env var: " env
        [[ -z "$env" ]] && break
        env_vars+=("$env")
    done

    echo ""
    if ! confirm "Create service?"; then
        return
    fi

    # Generate compose file
    cat > "$DATA_DIR/compose/${service_name}.yml" <<EOF
version: '3.8'

services:
  ${service_name}:
    image: ${docker_image}
    container_name: ${container_name}
    restart: unless-stopped
EOF

    if [[ ${#env_vars[@]} -gt 0 ]]; then
        echo "    environment:" >> "$DATA_DIR/compose/${service_name}.yml"
        for env in "${env_vars[@]}"; do
            echo "      - ${env}" >> "$DATA_DIR/compose/${service_name}.yml"
        done
    fi

    if [[ ${#volumes[@]} -gt 0 ]]; then
        echo "    volumes:" >> "$DATA_DIR/compose/${service_name}.yml"
        for vol in "${volumes[@]}"; do
            echo "      - ${vol}" >> "$DATA_DIR/compose/${service_name}.yml"
        done
    fi

    cat >> "$DATA_DIR/compose/${service_name}.yml" <<EOF
    ports:
      - "${port_mapping}"
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF

    print_step "Deploying ${service_name}..."
    docker compose -f "$DATA_DIR/compose/${service_name}.yml" up -d

    sleep 3

    if docker ps | grep -q "${container_name}"; then
        print_success "${service_name} deployed successfully"
    else
        print_error "Deployment failed"
    fi

    pause
}

#------------------------------------------------------------------------------
# Option 8: View Deployed Services
#------------------------------------------------------------------------------

view_deployed_services() {
    print_header
    echo -e "${BOLD}Deployed Services${NC}"
    echo ""

    if [[ ! -d "$DATA_DIR/compose" ]]; then
        print_info "No services deployed"
        pause
        return
    fi

    local compose_files=("$DATA_DIR/compose"/*.yml)

    if [[ ${#compose_files[@]} -eq 0 ]]; then
        print_info "No services deployed"
        pause
        return
    fi

    echo -e "${BOLD}Service${NC}\t\t${BOLD}Status${NC}\t\t${BOLD}Ports${NC}"
    echo "--------------------------------------------------------"

    for file in "${compose_files[@]}"; do
        local service_name=$(basename "$file" .yml)
        local containers=$(docker compose -f "$file" ps --format json 2>/dev/null | jq -r '.Name' 2>/dev/null)

        if [[ -n "$containers" ]]; then
            while IFS= read -r container; do
                local status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
                local ports=$(docker port "$container" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')

                if [[ "$status" == "running" ]]; then
                    echo -e "${service_name}\t${GREEN}${status}${NC}\t\t${ports}"
                else
                    echo -e "${service_name}\t${RED}${status}${NC}\t\t${ports}"
                fi
            done <<< "$containers"
        fi
    done

    echo ""
    pause
}

#------------------------------------------------------------------------------
# Option 9: Remove Service
#------------------------------------------------------------------------------

remove_service() {
    print_header
    echo -e "${BOLD}Remove Service${NC}"
    echo ""

    if [[ ! -d "$DATA_DIR/compose" ]]; then
        print_info "No services deployed"
        pause
        return
    fi

    local compose_files=("$DATA_DIR/compose"/*.yml)

    if [[ ${#compose_files[@]} -eq 0 ]]; then
        print_info "No services deployed"
        pause
        return
    fi

    echo "Available services:"
    echo ""

    local i=1
    for file in "${compose_files[@]}"; do
        echo "[$i] $(basename "$file" .yml)"
        ((i++))
    done

    echo ""
    read -p "Select service to remove (number): " selection

    local selected_file="${compose_files[$((selection-1))]}"

    if [[ ! -f "$selected_file" ]]; then
        print_error "Invalid selection"
        pause
        return
    fi

    local service_name=$(basename "$selected_file" .yml)

    print_warning "This will remove: $service_name"

    if confirm "Also delete data volumes?"; then
        local delete_volumes=true
    else
        local delete_volumes=false
    fi

    if ! confirm "Proceed with removal?"; then
        return
    fi

    print_step "Stopping service..."
    docker compose -f "$selected_file" down

    if [[ "$delete_volumes" == true ]]; then
        print_step "Removing volumes..."
        docker compose -f "$selected_file" down -v

        # Remove data directories
        rm -rf "/mnt/data/${service_name}"
        rm -rf "/mnt/data/${service_name}-"*
    fi

    # Remove compose file
    rm -f "$selected_file"

    print_success "Service removed successfully"

    pause
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    # Check root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi

    # Check prerequisites
    if [[ ! -f "$METADATA_FILE" ]]; then
        print_error "System not initialized. Run scripts 1-3 first."
        exit 1
    fi

    # Start main menu loop
    main_menu
}

# Run main function
main "$@"
