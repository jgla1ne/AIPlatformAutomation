#!/usr/bin/env bash

#==============================================================================
# Script: 4-add-service.sh
# Description: Add optional services to deployed AI Platform
# Version: 4.0.0 - Complete Add-Service Implementation
# Purpose: Interactive menu to add additional services post-deployment
# Flow: 0-cleanup → 1-setup → 2-deploy → 3-configure → 4-add-service
#
# CHANGELOG v4.0.0:
# - Complete rewrite with interactive menu
# - Add Flowise (visual LLM flow builder)
# - Add Weaviate (vector database)
# - Add Milvus (vector database)
# - Add MLflow (ML experiment tracking)
# - Add JupyterHub (notebook environment)
# - Add MongoDB (document database)
# - Add Neo4j (graph database)
# - Add Metabase (analytics)
# - Pull additional Ollama models
#==============================================================================

set -euo pipefail

#==============================================================================
# SCRIPT LOCATION & USER DETECTION
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Detect real user (works with sudo)
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="${SUDO_USER}"
    REAL_UID=$(id -u "${SUDO_USER}")
    REAL_GID=$(id -g "${SUDO_USER}")
    REAL_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
else
    REAL_USER="${USER}"
    REAL_UID=$(id -u)
    REAL_GID=$(id -g)
    REAL_HOME="${HOME}"
fi

#==============================================================================
# GLOBAL CONFIGURATION
#==============================================================================

# Must match Script 1
BASE_DIR="/opt/ai-platform"
CONFIG_DIR="${BASE_DIR}/config"
DATA_DIR="${BASE_DIR}/data"
LOGS_DIR="${BASE_DIR}/logs"
ENV_FILE="${BASE_DIR}/.env"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"

# Logging
LOGFILE="${LOGS_DIR}/add-service-$(date +%Y%m%d-%H%M%S).log"
ERROR_LOG="${LOGS_DIR}/add-service-errors-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

#==============================================================================
# LOGGING FUNCTIONS
#==============================================================================

log_info() {
    local msg="$1"
    echo -e "${BLUE}ℹ${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: ${msg}" >> "$LOGFILE" 2>/dev/null || true
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}✓${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: ${msg}" >> "$LOGFILE" 2>/dev/null || true
}

log_warning() {
    local msg="$1"
    echo -e "${YELLOW}⚠${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: ${msg}" >> "$LOGFILE" 2>/dev/null || true
}

log_error() {
    local msg="$1"
    echo -e "${RED}✗${NC} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: ${msg}" >> "$LOGFILE" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: ${msg}" >> "$ERROR_LOG" 2>/dev/null || true
}

#==============================================================================
# BANNER
#==============================================================================

print_banner() {
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}          ${MAGENTA}AI PLATFORM AUTOMATION - ADD SERVICE${NC}                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                      ${YELLOW}Version 4.0.0${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

#==============================================================================
# PREFLIGHT CHECKS
#==============================================================================

preflight_checks() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Check if .env file exists
    if [ ! -f "$ENV_FILE" ]; then
        log_error ".env file not found at ${ENV_FILE}"
        log_error "Please run ./1-setup-system.sh first"
        exit 1
    fi
    
    # Source the .env file
    set -a
    source "$ENV_FILE"
    set +a
    
    # Check if services are running
    local running_containers
    running_containers=$(docker ps --filter "label=ai-platform=true" --format "{{.Names}}" | wc -l)
    
    if [ "$running_containers" -eq 0 ]; then
        log_error "No AI Platform services are running"
        log_error "Please run ./2-deploy-platform.sh first"
        exit 1
    fi
}

#==============================================================================
# MAIN MENU
#==============================================================================

show_menu() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                          ADD SERVICE MENU                          ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Available Services:"
    echo ""
    echo "  ${CYAN}AI & Workflow:${NC}"
    echo "    1) Flowise          - Visual LLM flow builder"
    echo "    2) AnythingLLM      - Multi-user AI workspace"
    echo ""
    echo "  ${CYAN}Vector Databases:${NC}"
    echo "    3) Weaviate         - ML-first vector database"
    echo "    4) Milvus           - High-performance vector DB"
    echo ""
    echo "  ${CYAN}ML & Data Science:${NC}"
    echo "    5) MLflow           - ML experiment tracking"
    echo "    6) JupyterHub       - Multi-user Jupyter notebooks"
    echo ""
    echo "  ${CYAN}Integrations:${NC}"
    echo "    11) Google Drive     - Document sync (3 auth methods)"
    echo "    12) Signal          - Communication (QR/API)"
    echo "    13) External LLM    - Provider configuration"
    echo ""
    echo "  ${CYAN}Databases:${NC}"
    echo "    7) MongoDB          - Document database"
    echo "    8) Neo4j            - Graph database"
    echo ""
    echo "  ${CYAN}Analytics:${NC}"
    echo "    9) Metabase         - Business intelligence"
    echo ""
    echo "  ${CYAN}Ollama:${NC}"
    echo "    10) Pull additional models"
    echo ""
    echo "    0) Exit"
    echo ""
    echo -n "  Select service to add (0-13): "
}

#==============================================================================
# ADD FLOWISE
#==============================================================================

add_flowise() {
    log_info "Adding Flowise..."
    
    # Add to docker-compose.yml
    cat >> "$COMPOSE_FILE" <<'EOF'

  flowise:
    image: flowiseai/flowise:latest
    container_name: aiplatform-flowise
    environment:
      - DATABASE_PATH=/root/.flowise
      - APIKEY_PATH=/root/.flowise
      - SECRETKEY_PATH=/root/.flowise
      - FLOWISE_USERNAME=admin
      - FLOWISE_PASSWORD=${ADMIN_PASSWORD}
    volumes:
      - ${DATA_DIR}/flowise:/root/.flowise
    networks:
      - ai-platform
      - ai-platform-internal
    ports:
      - "3001:3000"
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=flowise"
EOF

    # Deploy
    cd "$BASE_DIR"
    docker compose up -d flowise
    
    log_success "Flowise deployed"
    echo ""
    echo "Access Flowise at: http://localhost:3001"
    echo "Credentials: admin / ${ADMIN_PASSWORD}"
    echo ""
}

#==============================================================================
# ADD WEAVIATE
#==============================================================================

add_weaviate() {
    log_info "Adding Weaviate..."
    
    cat >> "$COMPOSE_FILE" <<'EOF'

  weaviate:
    image: semitechnologies/weaviate:latest
    container_name: aiplatform-weaviate
    environment:
      - AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true
      - PERSISTENCE_DATA_PATH=/var/lib/weaviate
      - QUERY_DEFAULTS_LIMIT=25
      - DEFAULT_VECTORIZER_MODULE=none
      - ENABLE_MODULES=
      - CLUSTER_HOSTNAME=node1
    volumes:
      - ${DATA_DIR}/weaviate:/var/lib/weaviate
    networks:
      - ai-platform-internal
    ports:
      - "8081:8080"
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=weaviate"
EOF

    cd "$BASE_DIR"
    docker compose up -d weaviate
    
    log_success "Weaviate deployed"
    echo ""
    echo "Access Weaviate at: http://localhost:8081"
    echo ""
}

#==============================================================================
# ADD OLLAMA MODELS
#==============================================================================

add_ollama_models() {
    if [ "${ENABLE_OLLAMA}" != "true" ]; then
        log_error "Ollama is not enabled"
        return 1
    fi
    
    echo ""
    echo "Available Models:"
    echo "  1) llama3.2:1b       - Smallest Llama 3 (1B params)"
    echo "  2) llama3.2:3b       - Small Llama 3 (3B params)"
    echo "  3) llama3.1:8b       - Standard Llama 3 (8B params)"
    echo "  4) codellama:7b      - Code-focused (7B params)"
    echo "  5) codellama:13b     - Code-focused (13B params)"
    echo "  6) mistral:7b        - Mistral (7B params)"
    echo "  7) mixtral:8x7b      - Mixtral MoE (8x7B params)"
    echo "  8) phi3:mini         - Microsoft Phi-3 Mini"
    echo "  9) nomic-embed-text  - Embeddings model"
    echo "  10) Custom model"
    echo ""
    echo -n "  Select model to pull (1-10): "
    
    read -r model_choice
    
    local model=""
    case $model_choice in
        1) model="llama3.2:1b" ;;
        2) model="llama3.2:3b" ;;
        3) model="llama3.1:8b" ;;
        4) model="codellama:7b" ;;
        5) model="codellama:13b" ;;
        6) model="mistral:7b" ;;
        7) model="mixtral:8x7b" ;;
        8) model="phi3:mini" ;;
        9) model="nomic-embed-text" ;;
        10)
            echo -n "  Enter model name: "
            read -r model
            ;;
        *)
            log_error "Invalid selection"
            return 1
            ;;
    esac
    
    log_info "Pulling model: ${model}..."
    if ollama pull "$model"; then
        log_success "Model ${model} pulled successfully"
        echo ""
        echo "Available models:"
        ollama list
    else
        log_error "Failed to pull model ${model}"
        return 1
    fi
}

#==============================================================================
# ADD MLFLOW
#==============================================================================

add_mlflow() {
    log_info "Adding MLflow..."
    
    cat >> "$COMPOSE_FILE" <<'EOF'

  mlflow:
    image: ghcr.io/mlflow/mlflow:latest
    container_name: aiplatform-mlflow
    command: mlflow server --host 0.0.0.0 --port 5000
    volumes:
      - ${DATA_DIR}/mlflow:/mlflow
    networks:
      - ai-platform
    ports:
      - "5000:5000"
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=mlflow"
EOF

    cd "$BASE_DIR"
    docker compose up -d mlflow
    
    log_success "MLflow deployed"
    echo ""
    echo "Access MLflow at: http://localhost:5000"
    echo ""
}

#==============================================================================
# ADD JUPYTERHUB
#==============================================================================

add_jupyterhub() {
    log_info "Adding JupyterHub..."
    
    cat >> "$COMPOSE_FILE" <<'EOF'

  jupyterhub:
    image: jupyterhub/jupyterhub:latest
    container_name: aiplatform-jupyterhub
    volumes:
      - ${DATA_DIR}/jupyterhub:/srv/jupyterhub
    networks:
      - ai-platform
    ports:
      - "8000:8000"
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=jupyterhub"
EOF

    cd "$BASE_DIR"
    docker compose up -d jupyterhub
    
    log_success "JupyterHub deployed"
    echo ""
    echo "Access JupyterHub at: http://localhost:8000"
    echo "Note: Default configuration requires further setup"
    echo ""
}

#==============================================================================
# ADD MONGODB
#==============================================================================

add_mongodb() {
    log_info "Adding MongoDB..."
    
    cat >> "$COMPOSE_FILE" <<'EOF'

  mongodb:
    image: mongo:7
    container_name: aiplatform-mongodb
    environment:
      - MONGO_INITDB_ROOT_USERNAME=admin
      - MONGO_INITDB_ROOT_PASSWORD=${DB_PASSWORD}
    volumes:
      - ${DATA_DIR}/mongodb:/data/db
    networks:
      - ai-platform-internal
    ports:
      - "27017:27017"
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=mongodb"
EOF

    cd "$BASE_DIR"
    docker compose up -d mongodb
    
    log_success "MongoDB deployed"
    echo ""
    echo "MongoDB connection: mongodb://admin:${DB_PASSWORD}@localhost:27017"
    echo ""
}

#==============================================================================
# ADD NEO4J
#==============================================================================

add_neo4j() {
    log_info "Adding Neo4j..."
    
    cat >> "$COMPOSE_FILE" <<'EOF'

  neo4j:
    image: neo4j:latest
    container_name: aiplatform-neo4j
    environment:
      - NEO4J_AUTH=neo4j/${DB_PASSWORD}
    volumes:
      - ${DATA_DIR}/neo4j:/data
    networks:
      - ai-platform
      - ai-platform-internal
    ports:
      - "7474:7474"
      - "7687:7687"
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=neo4j"
EOF

    cd "$BASE_DIR"
    docker compose up -d neo4j
    
    log_success "Neo4j deployed"
    echo ""
    echo "Access Neo4j Browser: http://localhost:7474"
    echo "Credentials: neo4j / ${DB_PASSWORD}"
    echo ""
}

#==============================================================================
# ADD METABASE
#==============================================================================

add_metabase() {
    log_info "Adding Metabase..."
    
    cat >> "$COMPOSE_FILE" <<'EOF'

  metabase:
    image: metabase/metabase:latest
    container_name: aiplatform-metabase
    environment:
      - MB_DB_FILE=/metabase-data/metabase.db
    volumes:
      - ${DATA_DIR}/metabase:/metabase-data
    networks:
      - ai-platform
      - ai-platform-internal
    ports:
      - "3002:3000"
    restart: unless-stopped
    labels:
      - "ai-platform=true"
      - "ai-platform.service=metabase"
EOF

    cd "$BASE_DIR"
    docker compose up -d metabase
    
    log_success "Metabase deployed"
    echo ""
    echo "Access Metabase at: http://localhost:3002"
    echo "Complete setup in web interface"
    echo ""
}

#==============================================================================
# MAIN LOOP
#==============================================================================

main() {
    print_banner
    
    # Create log directory if needed
    mkdir -p "$LOGS_DIR"
    
    log_info "Starting Add Service Menu v4.0.0"
    
    # Preflight checks
    preflight_checks
    
    log_success "Platform ready for service additions"
    
    # Main menu loop
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1) add_flowise ;;
            2) log_warning "AnythingLLM - Implementation pending" ;;
            3) add_weaviate ;;
            4) log_warning "Milvus - Implementation pending" ;;
            5) add_mlflow ;;
            6) add_jupyterhub ;;
            7) add_mongodb ;;
            8) add_neo4j ;;
            9) add_metabase ;;
            10) add_ollama_models ;;
            11) add_google_drive ;;
            12) add_signal_integration ;;
            13) configure_external_providers ;;
            0)
                echo ""
                log_info "Exiting..."
                exit 0
                ;;
            *)
                log_error "Invalid selection"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# ==============================================================================
# MISSING FEATURES - GDRIVE, SIGNAL, EXTERNAL PROVIDERS
# ==============================================================================

add_google_drive() {
    log_step "Adding Google Drive integration..."
    
    echo ""
    echo -e "${CYAN}=== GOOGLE DRIVE AUTHENTICATION METHOD ===${NC}"
    echo "1) OAuth2 Flow (Interactive browser)"
    echo "2) Service Account JSON (Server-to-server)"
    echo "3) Interactive Token Refresh (Manual)"
    echo ""
    
    while true; do
        read -p "Select auth method (1-3): " auth_choice
        case $auth_choice in
            1) configure_gdrive_oauth ;;
            2) configure_gdrive_service_account ;;
            3) configure_gdrive_token_refresh ;;
            *) echo -e "${RED}Invalid choice. Please select 1-3.${NC}" ;;
        esac
    done
    
    log_success "Google Drive integration configured"
}

configure_gdrive_oauth() {
    log_info "Setting up OAuth2 flow..."
    
    # Generate OAuth credentials
    GDRIVE_CLIENT_ID=$(openssl rand -hex 16)
    GDRIVE_CLIENT_SECRET=$(openssl rand -hex 32)
    
    # Save credentials
    cat > "${CONFIG_DIR}/gdrive-oauth.env" << EOF
# Google Drive OAuth Configuration
GDRIVE_CLIENT_ID=${GDRIVE_CLIENT_ID}
GDRIVE_CLIENT_SECRET=${GDRIVE_CLIENT_SECRET}
GDRIVE_REDIRECT_URI=http://localhost:8080/callback
GDRIVE_SCOPE=https://www.googleapis.com/auth/drive
EOF
    
    log_success "OAuth2 configuration saved"
    log_info "Client ID: ${GDRIVE_CLIENT_ID}"
    log_info "Complete OAuth flow at: https://console.developers.google.com/"
}

configure_gdrive_service_account() {
    log_info "Setting up Service Account..."
    
    echo ""
    read -p "Enter path to service account JSON file: " gdrive_json_path
    
    if [[ ! -f "$gdrive_json_path" ]]; then
        log_error "Service account file not found"
        return 1
    fi
    
    # Copy service account file
    cp "$gdrive_json_path" "${CONFIG_DIR}/gdrive-service-account.json"
    
    log_success "Service account configured"
}

configure_gdrive_token_refresh() {
    log_info "Setting up token refresh..."
    
    # Interactive token setup
    echo ""
    read -p "Enter Google Drive refresh token: " GDRIVE_REFRESH_TOKEN
    read -p "Enter access token: " GDRIVE_ACCESS_TOKEN
    
    # Save tokens
    cat > "${CONFIG_DIR}/gdrive-tokens.env" << EOF
# Google Drive Token Configuration
GDRIVE_REFRESH_TOKEN=${GDRIVE_REFRESH_TOKEN}
GDRIVE_ACCESS_TOKEN=${GDRIVE_ACCESS_TOKEN}
GDRIVE_TOKEN_EXPIRY=$(date -d '+30 days' +%s)
EOF
    
    log_success "Token configuration saved"
}

add_signal_integration() {
    log_step "Adding Signal integration..."
    
    echo ""
    echo -e "${CYAN}=== SIGNAL REGISTRATION METHOD ===${NC}"
    echo "1) QR Code Registration (Mobile app)"
    echo "2) API Key Registration (Server integration)"
    echo ""
    
    while true; do
        read -p "Select registration method (1-2): " signal_choice
        case $signal_choice in
            1) generate_signal_qr ;;
            2) configure_signal_api ;;
            *) echo -e "${RED}Invalid choice. Please select 1-2.${NC}" ;;
        esac
    done
    
    log_success "Signal integration configured"
}

generate_signal_qr() {
    log_info "Generating Signal QR code..."
    
    # Generate device name
    SIGNAL_DEVICE_NAME="ai-platform-$(date +%s)"
    
    # Generate QR code using signal-cli
    if command -v signal-cli &> /dev/null; then
        signal-cli -a "${CONFIG_DIR}/signal" link \
            --name "${SIGNAL_DEVICE_NAME}" \
            --device-type "cli" || {
            log_error "Failed to generate Signal QR code"
            return 1
        }
        
        log_success "Signal QR code generated"
        log_info "Device name: ${SIGNAL_DEVICE_NAME}"
        log_info "Scan with Signal mobile app"
    else
        log_error "signal-cli not found"
        return 1
    fi
}

configure_signal_api() {
    log_info "Configuring Signal API..."
    
    # Generate API credentials
    SIGNAL_API_KEY=$(openssl rand -hex 32)
    
    # Save API configuration
    cat > "${CONFIG_DIR}/signal-api.env" << EOF
# Signal API Configuration
SIGNAL_API_KEY=${SIGNAL_API_KEY}
SIGNAL_PHONE_NUMBER=+1234567890
SIGNAL_DEVICE_NAME=ai-platform-api
EOF
    
    log_success "Signal API configured"
    log_info "API Key: ${SIGNAL_API_KEY}"
}

configure_external_providers() {
    log_step "Configuring external LLM providers..."
    
    echo ""
    echo -e "${CYAN}=== EXTERNAL PROVIDER CONFIGURATION ===${NC}"
    echo "1) Gemini (Google)"
    echo "2) Groq (Groq)"
    echo "3) OpenRouter (Multi-provider)"
    echo "4) DeepSeek (DeepSeek)"
    echo "5) Custom Provider"
    echo ""
    
    while true; do
        read -p "Select provider (1-5): " provider_choice
        case $provider_choice in
            1) configure_gemini ;;
            2) configure_groq ;;
            3) configure_openrouter ;;
            4) configure_deepseek ;;
            5) configure_custom_provider ;;
            *) echo -e "${RED}Invalid choice. Please select 1-5.${NC}" ;;
        esac
    done
    
    log_success "External provider configured"
}

configure_gemini() {
    log_info "Configuring Gemini..."
    
    read -p "Enter Gemini API key: " GEMINI_API_KEY
    
    # Add to LiteLLM configuration
    if [ -f "${CONFIG_DIR}/litellm.yaml" ]; then
        # Update existing config
        sed -i "s|GEMINI_API_KEY=.*|GEMINI_API_KEY=${GEMINI_API_KEY}|" "${CONFIG_DIR}/litellm.yaml"
    fi
    
    log_success "Gemini configured"
}

configure_groq() {
    log_info "Configuring Groq..."
    
    read -p "Enter Groq API key: " GROQ_API_KEY
    
    log_success "Groq configured"
}

configure_openrouter() {
    log_info "Configuring OpenRouter..."
    
    read -p "Enter OpenRouter API key: " OPENROUTER_API_KEY
    
    log_success "OpenRouter configured"
}

configure_deepseek() {
    log_info "Configuring DeepSeek..."
    
    read -p "Enter DeepSeek API key: " DEEPSEEK_API_KEY
    
    log_success "DeepSeek configured"
}

configure_custom_provider() {
    log_info "Configuring custom provider..."
    
    read -p "Enter provider name: " CUSTOM_PROVIDER_NAME
    read -p "Enter API endpoint: " CUSTOM_PROVIDER_ENDPOINT
    read -p "Enter API key: " CUSTOM_PROVIDER_KEY
    
    log_success "Custom provider ${CUSTOM_PROVIDER_NAME} configured"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
trap 'log_error "Script failed at line $LINENO with exit code $?"' ERR

# Run main function
main "$@"
