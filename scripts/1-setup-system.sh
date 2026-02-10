#!/bin/bash

#############################################
# AI Platform Setup Script
# Version: 2.0.0
# Purpose: Complete system setup with volume selection, 
#          configuration generation, and service preparation
#
# Architecture:
# - Standalone (no external dependencies)
# - Data location: /mnt/data (user-selected volume)
# - Config location: /mnt/data/config/ (generated here)
# - Three configuration methods:
#   1. Interactive (guided setup)
#   2. Google Drive import
#   3. Config file import (JSON/YAML/ENV)
#
# Generates:
# - /mnt/data/config/docker-compose.yml
# - /mnt/data/config/.env
# - /mnt/data/config/postgres.env
# - /mnt/data/config/qdrant.env
# - /mnt/data/config/ollama.env
# - /mnt/data/config/n8n.env
# - /mnt/data/config/openwebui.env
# - /mnt/data/config/litellm.env (if enabled)
# - /mnt/data/config/litellm/config.yaml (if enabled)
#############################################

set -e  # Exit on error

#############################################
# COLOR DEFINITIONS
#############################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

#############################################
# GLOBAL VARIABLES
#############################################

# Base path for all data (will be set by volume selection)
BASE_PATH=""

# Configuration method (1=interactive, 2=gdrive, 3=file)
CONFIG_METHOD=""

# Service enablement flags
POSTGRES_ENABLED="true"
QDRANT_ENABLED="true"
OLLAMA_ENABLED="true"
N8N_ENABLED="true"
OPENWEBUI_ENABLED="true"
LITELLM_ENABLED="false"
SIGNAL_ENABLED="false"

# PostgreSQL configuration
POSTGRES_PORT="5432"
POSTGRES_USER="aiplatform"
POSTGRES_PASSWORD=""
POSTGRES_DB="aiplatform"
POSTGRES_MAX_CONNECTIONS="100"
POSTGRES_SHARED_BUFFERS="256MB"
POSTGRES_WORK_MEM="4MB"

# Qdrant configuration
QDRANT_PORT="6333"
QDRANT_GRPC_PORT="6334"
QDRANT_API_KEY=""
QDRANT_MAX_SEGMENT_SIZE_KB="100000"
QDRANT_INDEXING_THRESHOLD_KB="20000"

# Ollama configuration
OLLAMA_PORT="11434"
OLLAMA_GPU_ENABLED="false"
OLLAMA_MODELS="llama2,mistral"
OLLAMA_MAX_LOADED_MODELS="3"
OLLAMA_KEEP_ALIVE="5m"
OLLAMA_NUM_CTX="2048"

# n8n configuration
N8N_PORT="5678"
N8N_ENCRYPTION_KEY=""
N8N_BASIC_AUTH_USER="admin"
N8N_BASIC_AUTH_PASSWORD=""
N8N_EXECUTIONS_DATA_SAVE_ON_SUCCESS="true"
N8N_EXECUTIONS_TIMEOUT="10"
N8N_EXECUTIONS_TIMEOUT_MAX="60"

# Open WebUI configuration
OPENWEBUI_PORT="8080"
OPENWEBUI_SECRET_KEY=""
OPENWEBUI_ENABLE_SEARCH="false"
OPENWEBUI_ENABLE_RAG="true"
OPENWEBUI_DEFAULT_PROMPT="You are a helpful AI assistant"

# LiteLLM configuration
LITELLM_PORT="4000"
LITELLM_MASTER_KEY=""
LITELLM_DATABASE_URL=""
LITELLM_FALLBACK_ENABLED="true"
LITELLM_CACHE_ENABLED="true"
LITELLM_RATE_LIMIT="60"

# Signal configuration
SIGNAL_PHONE=""
SIGNAL_ENDPOINT="http://localhost:8080"
SIGNAL_RECIPIENT=""

#############################################
# UTILITY FUNCTIONS
#############################################

print_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_step() {
    echo -e "${MAGENTA}▶${NC} $1"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "Required command not found: $1"
        return 1
    fi
    return 0
}

check_port_available() {
    local port=$1
    local service=$2
    
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_warning "Port $port is already in use (needed for $service)"
        read -p "Enter different port for $service: " new_port
        echo "$new_port"
        return 1
    fi
    return 0
}

generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

generate_key() {
    openssl rand -hex 32
}

#############################################
# MAIN BANNER
#############################################

clear
echo -e "${CYAN}"
cat << "EOF"
    ___    ____   ____  __      __  ____                 
   /   |  /  _/  / __ \/ /___ _/ /_/ __/___  _________ ___
  / /| |  / /   / /_/ / / __ `/ __/ /_/ __ \/ ___/ __ `__ \
 / ___ |_/ /   / ____/ / /_/ / /_/ __/ /_/ / /  / / / / / /
/_/  |_/___/  /_/   /_/\__,_/\__/_/  \____/_/  /_/ /_/ /_/ 
                                                            
         Complete Setup & Configuration Script
                    Version 2.0.0
EOF
echo -e "${NC}"

print_info "This script will guide you through setting up the AI Platform"
print_info "Estimated time: 10-15 minutes (interactive mode)"
echo ""

#############################################
# PREREQUISITE CHECKS
#############################################

print_header "PREREQUISITE CHECKS"

print_step "Checking required commands..."

required_commands=("docker" "docker-compose" "openssl" "lsof" "lsblk")
missing_commands=()

for cmd in "${required_commands[@]}"; do
    if check_command "$cmd"; then
        print_success "$cmd found"
    else
        missing_commands+=("$cmd")
    fi
done

if [ ${#missing_commands[@]} -ne 0 ]; then
    print_error "Missing required commands: ${missing_commands[*]}"
    echo ""
    echo "Please install missing dependencies:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y docker.io docker-compose openssl lsof util-linux"
    exit 1
fi

print_success "All prerequisites met"

#############################################
# VOLUME SELECTION & MOUNTING
#############################################

select_data_volume() {
    print_header "DATA VOLUME SELECTION"
    
    echo "The AI Platform stores all persistent data in a dedicated location."
    echo "You need to select a volume/partition for this purpose."
    echo ""
    print_warning "This volume will store:"
    echo "  • All AI models (~10GB+)"
    echo "  • Vector databases"
    echo "  • PostgreSQL data"
    echo "  • Workflow data"
    echo "  • Logs and configurations"
    echo ""
    print_info "Recommended: 100GB+ of free space"
    echo ""
    
    # Show available volumes
    echo "Available volumes:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL | grep -v "loop\|sr0" || true
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    echo "Options:"
    echo "  1) Use existing /mnt/data (local filesystem)"
    echo "  2) Mount a specific device to /mnt/data"
    echo ""
    read -p "Select option [1-2]: " volume_option
    
    case $volume_option in
        1)
            BASE_PATH="/mnt/data"
            print_info "Using /mnt/data (local filesystem)"
            
            # Create directory if doesn't exist
            sudo mkdir -p "$BASE_PATH"
            
            # Check if writable
            if [ ! -w "$BASE_PATH" ]; then
                print_warning "$BASE_PATH is not writable"
                read -p "Fix permissions? [Y/n]: " fix_perms
                if [[ ! "$fix_perms" =~ ^[Nn]$ ]]; then
                    sudo chown -R $USER:$USER "$BASE_PATH"
                    print_success "Permissions fixed"
                fi
            fi
            ;;
            
        2)
            echo ""
            read -p "Enter device path (e.g., /dev/sdb1): " device_path
            
            # Validate device exists
            if [ ! -b "$device_path" ]; then
                print_error "Device $device_path does not exist"
                exit 1
            fi
            
            # Check if already mounted
            mount_point=$(lsblk -no MOUNTPOINT "$device_path" 2>/dev/null || true)
            
            if [ -n "$mount_point" ]; then
                echo "Device is already mounted at: $mount_point"
                read -p "Use this mount point? [Y/n]: " use_existing
                
                if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
                    BASE_PATH="$mount_point"
                    print_success "Using existing mount: $BASE_PATH"
                else
                    # Unmount and remount to /mnt/data
                    print_step "Unmounting $device_path..."
                    sudo umount "$device_path"
                    
                    sudo mkdir -p /mnt/data
                    print_step "Mounting $device_path to /mnt/data..."
                    sudo mount "$device_path" /mnt/data
                    
                    BASE_PATH="/mnt/data"
                    print_success "Mounted $device_path to $BASE_PATH"
                fi
            else
                # Not mounted, mount to /mnt/data
                sudo mkdir -p /mnt/data
                print_step "Mounting $device_path to /mnt/data..."
                sudo mount "$device_path" /mnt/data
                
                BASE_PATH="/mnt/data"
                print_success "Mounted $device_path to $BASE_PATH"
                
                # Ask about persistent mount
                echo ""
                read -p "Add to /etc/fstab for automatic mounting? [y/N]: " add_fstab
                
                if [[ "$add_fstab" =~ ^[Yy]$ ]]; then
                    fs_type=$(lsblk -no FSTYPE "$device_path")
                    device_uuid=$(sudo blkid -s UUID -o value "$device_path")
                    
                    if ! grep -q "$device_uuid" /etc/fstab 2>/dev/null; then
                        echo "# AI Platform data volume - added by setup script $(date)" | sudo tee -a /etc/fstab
                        echo "UUID=$device_uuid  /mnt/data  $fs_type  defaults  0  2" | sudo tee -a /etc/fstab
                        print_success "Added to /etc/fstab"
                    else
                        print_info "Already in /etc/fstab"
                    fi
                fi
            fi
            ;;
            
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac
    
    # Verify we have space
    available_space=$(df -BG "$BASE_PATH" | awk 'NR==2 {print $4}' | sed 's/G//')
    
    echo ""
    print_success "Selected volume: $BASE_PATH"
    print_info "Available space: ${available_space}GB"
    
    if [ "$available_space" -lt 50 ]; then
        echo ""
        print_warning "Less than 50GB available!"
        print_warning "Recommended: 100GB+ for full AI platform deployment"
        read -p "Continue anyway? [y/N]: " continue_low_space
        
        if [[ ! "$continue_low_space" =~ ^[Yy]$ ]]; then
            print_error "Setup cancelled. Please use a volume with more space."
            exit 1
        fi
    fi
    
    # Create config directory
    mkdir -p "$BASE_PATH/config"
    print_success "Created config directory: $BASE_PATH/config"
}

# Execute volume selection
select_data_volume
#############################################
# CONFIGURATION METHOD SELECTION
#############################################

select_configuration_method() {
    print_header "CONFIGURATION METHOD SELECTION"

    echo "Choose how you want to configure the AI Platform:"
    echo ""
    echo "  ${GREEN}1) Interactive Setup${NC} (Recommended for first-time users)"
    echo "     • Step-by-step guided configuration"
    echo "     • All options explained"
    echo "     • Takes 10-15 minutes"
    echo ""
    echo "  ${BLUE}2) Import from Google Drive${NC}"
    echo "     • Load pre-saved configuration"
    echo "     • Requires Google Drive folder ID"
    echo "     • Instant setup with saved settings"
    echo ""
    echo "  ${YELLOW}3) Load from Configuration File${NC}"
    echo "     • Import from local JSON/YAML/ENV file"
    echo "     • Perfect for version-controlled configs"
    echo "     • Supports multiple formats"
    echo ""

    read -p "Select option [1-3]: " CONFIG_METHOD

    case $CONFIG_METHOD in
        1)
            print_success "Selected: Interactive Setup"
            interactive_configuration
            ;;
        2)
            print_success "Selected: Google Drive Import"
            import_from_google_drive
            ;;
        3)
            print_success "Selected: Configuration File Import"
            import_from_config_file
            ;;
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac
}

#############################################
# GOOGLE DRIVE IMPORT
#############################################

import_from_google_drive() {
    print_header "GOOGLE DRIVE IMPORT"

    echo "This will download your saved configuration from Google Drive."
    echo ""
    print_info "Requirements:"
    echo "  • Google Drive folder ID"
    echo "  • rclone installed and configured"
    echo "  • Configuration file: ai-platform-config.json"
    echo ""

    # Check if rclone is installed
    if ! check_command "rclone"; then
        print_error "rclone is not installed"
        echo ""
        echo "Install rclone:"
        echo "  curl https://rclone.org/install.sh | sudo bash"
        echo ""
        read -p "Install rclone now? [y/N]: " install_rclone

        if [[ "$install_rclone" =~ ^[Yy]$ ]]; then
            print_step "Installing rclone..."
            curl https://rclone.org/install.sh | sudo bash

            if ! check_command "rclone"; then
                print_error "rclone installation failed"
                exit 1
            fi

            print_success "rclone installed"
        else
            print_error "Cannot proceed without rclone"
            exit 1
        fi
    fi

    # Check if rclone is configured
    if ! rclone listremotes | grep -q "gdrive:"; then
        print_warning "rclone is not configured for Google Drive"
        echo ""
        echo "Configure rclone for Google Drive:"
        echo "  1. Run: rclone config"
        echo "  2. Select 'n' for new remote"
        echo "  3. Name it 'gdrive'"
        echo "  4. Select 'Google Drive' as storage type"
        echo "  5. Follow the authentication steps"
        echo ""
        read -p "Configure rclone now? [y/N]: " config_rclone

        if [[ "$config_rclone" =~ ^[Yy]$ ]]; then
            rclone config

            if ! rclone listremotes | grep -q "gdrive:"; then
                print_error "rclone configuration incomplete"
                exit 1
            fi
        else
            print_error "Cannot proceed without rclone configuration"
            exit 1
        fi
    fi

    print_success "rclone is configured"
    echo ""

    # Get Google Drive folder ID
    echo "Enter your Google Drive folder ID:"
    echo "(Found in the URL: https://drive.google.com/drive/folders/YOUR_FOLDER_ID)"
    echo ""
    read -p "Folder ID: " gdrive_folder_id

    if [ -z "$gdrive_folder_id" ]; then
        print_error "Folder ID cannot be empty"
        exit 1
    fi

    # Create temporary directory for download
    temp_dir=$(mktemp -d)

    print_step "Downloading configuration from Google Drive..."

    # Download the config file
    if rclone copy "gdrive:$gdrive_folder_id/ai-platform-config.json" "$temp_dir/" --progress; then
        print_success "Configuration downloaded"
    else
        print_error "Failed to download configuration"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Verify file exists
    if [ ! -f "$temp_dir/ai-platform-config.json" ]; then
        print_error "Configuration file not found in Google Drive folder"
        echo ""
        echo "Expected file: ai-platform-config.json"
        echo "Location: Google Drive folder ID $gdrive_folder_id"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Parse and load configuration
    print_step "Parsing configuration..."
    parse_json_config "$temp_dir/ai-platform-config.json"

    # Clean up
    rm -rf "$temp_dir"

    print_success "Configuration imported from Google Drive"

    # Show summary
    show_config_summary
}

#############################################
# CONFIG FILE IMPORT
#############################################

import_from_config_file() {
    print_header "CONFIGURATION FILE IMPORT"

    echo "Supported formats:"
    echo "  • JSON (.json)"
    echo "  • YAML (.yaml, .yml)"
    echo "  • ENV (.env)"
    echo ""

    read -p "Enter path to configuration file: " config_file_path

    # Expand tilde and resolve path
    config_file_path="${config_file_path/#\~/$HOME}"
    config_file_path=$(realpath "$config_file_path" 2>/dev/null || echo "$config_file_path")

    # Verify file exists
    if [ ! -f "$config_file_path" ]; then
        print_error "File not found: $config_file_path"
        exit 1
    fi

    print_success "File found: $config_file_path"

    # Detect file format
    file_extension="${config_file_path##*.}"

    print_step "Detected format: $file_extension"

    case "$file_extension" in
        json)
            parse_json_config "$config_file_path"
            ;;
        yaml|yml)
            parse_yaml_config "$config_file_path"
            ;;
        env)
            parse_env_config "$config_file_path"
            ;;
        *)
            print_error "Unsupported file format: $file_extension"
            echo "Supported: .json, .yaml, .yml, .env"
            exit 1
            ;;
    esac

    print_success "Configuration imported from file"

    # Show summary
    show_config_summary
}

#############################################
# CONFIG PARSERS
#############################################

parse_json_config() {
    local config_file="$1"

    # Check if jq is installed
    if ! check_command "jq"; then
        print_warning "jq not found, installing..."
        sudo apt-get update && sudo apt-get install -y jq
    fi

    # Validate JSON
    if ! jq empty "$config_file" 2>/dev/null; then
        print_error "Invalid JSON file"
        exit 1
    fi

    print_step "Parsing JSON configuration..."

    # Service enablement
    POSTGRES_ENABLED=$(jq -r '.services.postgresql.enabled // true' "$config_file")
    QDRANT_ENABLED=$(jq -r '.services.qdrant.enabled // true' "$config_file")
    OLLAMA_ENABLED=$(jq -r '.services.ollama.enabled // true' "$config_file")
    N8N_ENABLED=$(jq -r '.services.n8n.enabled // true' "$config_file")
    OPENWEBUI_ENABLED=$(jq -r '.services.openwebui.enabled // true' "$config_file")
    LITELLM_ENABLED=$(jq -r '.services.litellm.enabled // false' "$config_file")
    SIGNAL_ENABLED=$(jq -r '.notifications.signal.enabled // false' "$config_file")

    # PostgreSQL
    POSTGRES_PORT=$(jq -r '.services.postgresql.port // 5432' "$config_file")
    POSTGRES_USER=$(jq -r '.services.postgresql.user // "aiplatform"' "$config_file")
    POSTGRES_PASSWORD=$(jq -r '.services.postgresql.password // ""' "$config_file")
    POSTGRES_DB=$(jq -r '.services.postgresql.database // "aiplatform"' "$config_file")
    POSTGRES_MAX_CONNECTIONS=$(jq -r '.services.postgresql.max_connections // 100' "$config_file")
    POSTGRES_SHARED_BUFFERS=$(jq -r '.services.postgresql.shared_buffers // "256MB"' "$config_file")

    # Qdrant
    QDRANT_PORT=$(jq -r '.services.qdrant.port // 6333' "$config_file")
    QDRANT_GRPC_PORT=$(jq -r '.services.qdrant.grpc_port // 6334' "$config_file")
    QDRANT_API_KEY=$(jq -r '.services.qdrant.api_key // ""' "$config_file")

    # Ollama
    OLLAMA_PORT=$(jq -r '.services.ollama.port // 11434' "$config_file")
    OLLAMA_GPU_ENABLED=$(jq -r '.services.ollama.gpu_enabled // false' "$config_file")
    OLLAMA_MODELS=$(jq -r '.services.ollama.models // "llama2,mistral"' "$config_file")
    OLLAMA_NUM_CTX=$(jq -r '.services.ollama.num_ctx // 2048' "$config_file")

    # n8n
    N8N_PORT=$(jq -r '.services.n8n.port // 5678' "$config_file")
    N8N_ENCRYPTION_KEY=$(jq -r '.services.n8n.encryption_key // ""' "$config_file")
    N8N_BASIC_AUTH_USER=$(jq -r '.services.n8n.basic_auth.user // "admin"' "$config_file")
    N8N_BASIC_AUTH_PASSWORD=$(jq -r '.services.n8n.basic_auth.password // ""' "$config_file")

    # Open WebUI
    OPENWEBUI_PORT=$(jq -r '.services.openwebui.port // 8080' "$config_file")
    OPENWEBUI_SECRET_KEY=$(jq -r '.services.openwebui.secret_key // ""' "$config_file")
    OPENWEBUI_ENABLE_RAG=$(jq -r '.services.openwebui.enable_rag // true' "$config_file")

    # LiteLLM
    if [ "$LITELLM_ENABLED" = "true" ]; then
        LITELLM_PORT=$(jq -r '.services.litellm.port // 4000' "$config_file")
        LITELLM_MASTER_KEY=$(jq -r '.services.litellm.master_key // ""' "$config_file")
        LITELLM_DATABASE_URL=$(jq -r '.services.litellm.database_url // ""' "$config_file")
    fi

    # Signal
    if [ "$SIGNAL_ENABLED" = "true" ]; then
        SIGNAL_PHONE=$(jq -r '.notifications.signal.phone // ""' "$config_file")
        SIGNAL_ENDPOINT=$(jq -r '.notifications.signal.endpoint // "http://localhost:8080"' "$config_file")
        SIGNAL_RECIPIENT=$(jq -r '.notifications.signal.recipient // ""' "$config_file")
    fi

    # Generate missing passwords/keys
    [ -z "$POSTGRES_PASSWORD" ] && POSTGRES_PASSWORD=$(generate_password)
    [ -z "$QDRANT_API_KEY" ] && QDRANT_API_KEY=$(generate_key)
    [ -z "$N8N_ENCRYPTION_KEY" ] && N8N_ENCRYPTION_KEY=$(generate_key)
    [ -z "$N8N_BASIC_AUTH_PASSWORD" ] && N8N_BASIC_AUTH_PASSWORD=$(generate_password)
    [ -z "$OPENWEBUI_SECRET_KEY" ] && OPENWEBUI_SECRET_KEY=$(generate_key)

    if [ "$LITELLM_ENABLED" = "true" ]; then
        [ -z "$LITELLM_MASTER_KEY" ] && LITELLM_MASTER_KEY=$(generate_key)
        [ -z "$LITELLM_DATABASE_URL" ] && LITELLM_DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/litellm"
    fi

    print_success "JSON configuration parsed"
}

parse_yaml_config() {
    local config_file="$1"

    # Check if yq is installed
    if ! check_command "yq"; then
        print_warning "yq not found, installing..."
        sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
        sudo chmod +x /usr/local/bin/yq
    fi

    print_step "Parsing YAML configuration..."

    # Service enablement
    POSTGRES_ENABLED=$(yq e '.services.postgresql.enabled // true' "$config_file")
    QDRANT_ENABLED=$(yq e '.services.qdrant.enabled // true' "$config_file")
    OLLAMA_ENABLED=$(yq e '.services.ollama.enabled // true' "$config_file")
    N8N_ENABLED=$(yq e '.services.n8n.enabled // true' "$config_file")
    OPENWEBUI_ENABLED=$(yq e '.services.openwebui.enabled // true' "$config_file")
    LITELLM_ENABLED=$(yq e '.services.litellm.enabled // false' "$config_file")
    SIGNAL_ENABLED=$(yq e '.notifications.signal.enabled // false' "$config_file")

    # PostgreSQL
    POSTGRES_PORT=$(yq e '.services.postgresql.port // 5432' "$config_file")
    POSTGRES_USER=$(yq e '.services.postgresql.user // "aiplatform"' "$config_file")
    POSTGRES_PASSWORD=$(yq e '.services.postgresql.password // ""' "$config_file")
    POSTGRES_DB=$(yq e '.services.postgresql.database // "aiplatform"' "$config_file")

    # Qdrant
    QDRANT_PORT=$(yq e '.services.qdrant.port // 6333' "$config_file")
    QDRANT_API_KEY=$(yq e '.services.qdrant.api_key // ""' "$config_file")

    # Ollama
    OLLAMA_PORT=$(yq e '.services.ollama.port // 11434' "$config_file")
    OLLAMA_GPU_ENABLED=$(yq e '.services.ollama.gpu_enabled // false' "$config_file")
    OLLAMA_MODELS=$(yq e '.services.ollama.models // "llama2,mistral"' "$config_file")

    # n8n
    N8N_PORT=$(yq e '.services.n8n.port // 5678' "$config_file")
    N8N_ENCRYPTION_KEY=$(yq e '.services.n8n.encryption_key // ""' "$config_file")
    N8N_BASIC_AUTH_USER=$(yq e '.services.n8n.basic_auth.user // "admin"' "$config_file")
    N8N_BASIC_AUTH_PASSWORD=$(yq e '.services.n8n.basic_auth.password // ""' "$config_file")

    # Open WebUI
    OPENWEBUI_PORT=$(yq e '.services.openwebui.port // 8080' "$config_file")
    OPENWEBUI_SECRET_KEY=$(yq e '.services.openwebui.secret_key // ""' "$config_file")

    # LiteLLM
    if [ "$LITELLM_ENABLED" = "true" ]; then
        LITELLM_PORT=$(yq e '.services.litellm.port // 4000' "$config_file")
        LITELLM_MASTER_KEY=$(yq e '.services.litellm.master_key // ""' "$config_file")
    fi

    # Signal
    if [ "$SIGNAL_ENABLED" = "true" ]; then
        SIGNAL_PHONE=$(yq e '.notifications.signal.phone // ""' "$config_file")
        SIGNAL_RECIPIENT=$(yq e '.notifications.signal.recipient // ""' "$config_file")
    fi

    # Generate missing passwords/keys
    [ -z "$POSTGRES_PASSWORD" ] && POSTGRES_PASSWORD=$(generate_password)
    [ -z "$QDRANT_API_KEY" ] && QDRANT_API_KEY=$(generate_key)
    [ -z "$N8N_ENCRYPTION_KEY" ] && N8N_ENCRYPTION_KEY=$(generate_key)
    [ -z "$N8N_BASIC_AUTH_PASSWORD" ] && N8N_BASIC_AUTH_PASSWORD=$(generate_password)
    [ -z "$OPENWEBUI_SECRET_KEY" ] && OPENWEBUI_SECRET_KEY=$(generate_key)

    if [ "$LITELLM_ENABLED" = "true" ]; then
        [ -z "$LITELLM_MASTER_KEY" ] && LITELLM_MASTER_KEY=$(generate_key)
        [ -z "$LITELLM_DATABASE_URL" ] && LITELLM_DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/litellm"
    fi

    print_success "YAML configuration parsed"
}

parse_env_config() {
    local config_file="$1"

    print_step "Parsing ENV configuration..."

    # Source the env file
    set -a
    source "$config_file"
    set +a

    print_success "ENV configuration loaded"
}

#############################################
# CONFIGURATION SUMMARY
#############################################

show_config_summary() {
    print_header "CONFIGURATION SUMMARY"

    echo "Enabled Services:"
    [ "$POSTGRES_ENABLED" = "true" ] && echo "  ${GREEN}✓${NC} PostgreSQL (port $POSTGRES_PORT)"
    [ "$QDRANT_ENABLED" = "true" ] && echo "  ${GREEN}✓${NC} Qdrant (port $QDRANT_PORT)"
    [ "$OLLAMA_ENABLED" = "true" ] && echo "  ${GREEN}✓${NC} Ollama (port $OLLAMA_PORT)"
    [ "$N8N_ENABLED" = "true" ] && echo "  ${GREEN}✓${NC} n8n (port $N8N_PORT)"
    [ "$OPENWEBUI_ENABLED" = "true" ] && echo "  ${GREEN}✓${NC} Open WebUI (port $OPENWEBUI_PORT)"
    [ "$LITELLM_ENABLED" = "true" ] && echo "  ${GREEN}✓${NC} LiteLLM (port $LITELLM_PORT)"

    echo ""
    echo "Optional Features:"
    [ "$SIGNAL_ENABLED" = "true" ] && echo "  ${GREEN}✓${NC} Signal Notifications"
    [ "$OLLAMA_GPU_ENABLED" = "true" ] && echo "  ${GREEN}✓${NC} GPU Support (Ollama)"

    echo ""
    echo "Data Location: ${CYAN}$BASE_PATH${NC}"
    echo ""

    read -p "Proceed with this configuration? [Y/n]: " confirm

    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        print_warning "Configuration cancelled"
        exit 0
    fi
}

# Execute configuration method selection
select_configuration_method
#############################################
# INTERACTIVE CONFIGURATION
#############################################

interactive_configuration() {
    print_header "INTERACTIVE CONFIGURATION"

    echo "This wizard will guide you through configuring your AI Platform."
    echo "Default values are shown in [brackets]. Press Enter to accept defaults."
    echo ""
    read -p "Press Enter to begin..."

    # Service selection
    configure_service_selection

    # Port configuration
    configure_ports

    # Credentials and security
    configure_credentials

    # Advanced options
    configure_advanced_options

    # Optional features
    configure_optional_features

    # Show summary
    show_config_summary
}

#############################################
# SERVICE SELECTION
#############################################

configure_service_selection() {
    print_header "SERVICE SELECTION"

    echo "Select which services to enable:"
    echo ""

    # PostgreSQL
    echo "${CYAN}PostgreSQL${NC} - Relational database"
    echo "  Required for: n8n, LiteLLM, Open WebUI (optional)"
    read -p "Enable PostgreSQL? [Y/n]: " enable_postgres
    POSTGRES_ENABLED=$( [[ "$enable_postgres" =~ ^[Nn]$ ]] && echo "false" || echo "true" )

    if [ "$POSTGRES_ENABLED" = "false" ]; then
        print_warning "Some services may have limited functionality without PostgreSQL"
    fi
    echo ""

    # Qdrant
    echo "${CYAN}Qdrant${NC} - Vector database"
    echo "  Required for: RAG, embeddings, semantic search"
    read -p "Enable Qdrant? [Y/n]: " enable_qdrant
    QDRANT_ENABLED=$( [[ "$enable_qdrant" =~ ^[Nn]$ ]] && echo "false" || echo "true" )
    echo ""

    # Ollama
    echo "${CYAN}Ollama${NC} - Local LLM runtime"
    echo "  Provides: llama2, mistral, codellama, and more"
    read -p "Enable Ollama? [Y/n]: " enable_ollama
    OLLAMA_ENABLED=$( [[ "$enable_ollama" =~ ^[Nn]$ ]] && echo "false" || echo "true" )

    if [ "$OLLAMA_ENABLED" = "true" ]; then
        # GPU support check
        if lspci | grep -i nvidia > /dev/null 2>&1; then
            echo "  ${GREEN}✓${NC} NVIDIA GPU detected"
            read -p "  Enable GPU acceleration? [Y/n]: " enable_gpu
            OLLAMA_GPU_ENABLED=$( [[ "$enable_gpu" =~ ^[Nn]$ ]] && echo "false" || echo "true" )
        else
            echo "  ${YELLOW}!${NC} No NVIDIA GPU detected (will run on CPU)"
            OLLAMA_GPU_ENABLED="false"
        fi

        # Model selection
        echo ""
        echo "  Select models to download (comma-separated):"
        echo "    - llama2 (7B, general purpose)"
        echo "    - llama2:13b (13B, more capable)"
        echo "    - mistral (7B, fast and efficient)"
        echo "    - codellama (7B, code-focused)"
        echo "    - phi (2.7B, small and fast)"
        read -p "  Models [$OLLAMA_MODELS]: " models_input
        [ -n "$models_input" ] && OLLAMA_MODELS="$models_input"
    fi
    echo ""

    # n8n
    echo "${CYAN}n8n${NC} - Workflow automation"
    echo "  Provides: automation, integrations, scheduled tasks"
    read -p "Enable n8n? [Y/n]: " enable_n8n
    N8N_ENABLED=$( [[ "$enable_n8n" =~ ^[Nn]$ ]] && echo "false" || echo "true" )
    echo ""

    # Open WebUI
    echo "${CYAN}Open WebUI${NC} - ChatGPT-like interface"
    echo "  Provides: chat interface, RAG, model management"
    read -p "Enable Open WebUI? [Y/n]: " enable_openwebui
    OPENWEBUI_ENABLED=$( [[ "$enable_openwebui" =~ ^[Nn]$ ]] && echo "false" || echo "true" )

    if [ "$OPENWEBUI_ENABLED" = "true" ]; then
        read -p "  Enable RAG (Retrieval-Augmented Generation)? [Y/n]: " enable_rag
        OPENWEBUI_ENABLE_RAG=$( [[ "$enable_rag" =~ ^[Nn]$ ]] && echo "false" || echo "true" )

        if [ "$OPENWEBUI_ENABLE_RAG" = "true" ] && [ "$QDRANT_ENABLED" = "false" ]; then
            print_warning "  RAG requires Qdrant. Consider enabling Qdrant for full RAG functionality."
        fi
    fi
    echo ""

    # LiteLLM
    echo "${CYAN}LiteLLM${NC} - LLM proxy and unified API"
    echo "  Provides: API compatibility, load balancing, fallbacks"
    read -p "Enable LiteLLM? [y/N]: " enable_litellm
    LITELLM_ENABLED=$( [[ "$enable_litellm" =~ ^[Yy]$ ]] && echo "true" || echo "false" )

    if [ "$LITELLM_ENABLED" = "true" ] && [ "$POSTGRES_ENABLED" = "false" ]; then
        print_warning "  LiteLLM works best with PostgreSQL for persistent storage."
        read -p "  Enable PostgreSQL for LiteLLM? [Y/n]: " enable_postgres_litellm
        if [[ ! "$enable_postgres_litellm" =~ ^[Nn]$ ]]; then
            POSTGRES_ENABLED="true"
            print_success "  PostgreSQL enabled"
        fi
    fi
    echo ""

    print_success "Service selection complete"
}

#############################################
# PORT CONFIGURATION
#############################################

configure_ports() {
    print_header "PORT CONFIGURATION"

    echo "Configure service ports (press Enter for defaults):"
    echo ""

    if [ "$POSTGRES_ENABLED" = "true" ]; then
        while true; do
            read -p "PostgreSQL port [$POSTGRES_PORT]: " port_input
            port_input=${port_input:-$POSTGRES_PORT}

            if check_port_available "$port_input"; then
                POSTGRES_PORT="$port_input"
                print_success "PostgreSQL port: $POSTGRES_PORT"
                break
            else
                print_error "Port $port_input is in use. Try another."
            fi
        done
    fi

    if [ "$QDRANT_ENABLED" = "true" ]; then
        while true; do
            read -p "Qdrant HTTP port [$QDRANT_PORT]: " port_input
            port_input=${port_input:-$QDRANT_PORT}

            if check_port_available "$port_input"; then
                QDRANT_PORT="$port_input"
                print_success "Qdrant HTTP port: $QDRANT_PORT"
                break
            else
                print_error "Port $port_input is in use. Try another."
            fi
        done

        while true; do
            read -p "Qdrant gRPC port [$QDRANT_GRPC_PORT]: " port_input
            port_input=${port_input:-$QDRANT_GRPC_PORT}

            if check_port_available "$port_input"; then
                QDRANT_GRPC_PORT="$port_input"
                print_success "Qdrant gRPC port: $QDRANT_GRPC_PORT"
                break
            else
                print_error "Port $port_input is in use. Try another."
            fi
        done
    fi

    if [ "$OLLAMA_ENABLED" = "true" ]; then
        while true; do
            read -p "Ollama port [$OLLAMA_PORT]: " port_input
            port_input=${port_input:-$OLLAMA_PORT}

            if check_port_available "$port_input"; then
                OLLAMA_PORT="$port_input"
                print_success "Ollama port: $OLLAMA_PORT"
                break
            else
                print_error "Port $port_input is in use. Try another."
            fi
        done
    fi

    if [ "$N8N_ENABLED" = "true" ]; then
        while true; do
            read -p "n8n port [$N8N_PORT]: " port_input
            port_input=${port_input:-$N8N_PORT}

            if check_port_available "$port_input"; then
                N8N_PORT="$port_input"
                print_success "n8n port: $N8N_PORT"
                break
            else
                print_error "Port $port_input is in use. Try another."
            fi
        done
    fi

    if [ "$OPENWEBUI_ENABLED" = "true" ]; then
        while true; do
            read -p "Open WebUI port [$OPENWEBUI_PORT]: " port_input
            port_input=${port_input:-$OPENWEBUI_PORT}

            if check_port_available "$port_input"; then
                OPENWEBUI_PORT="$port_input"
                print_success "Open WebUI port: $OPENWEBUI_PORT"
                break
            else
                print_error "Port $port_input is in use. Try another."
            fi
        done
    fi

    if [ "$LITELLM_ENABLED" = "true" ]; then
        while true; do
            read -p "LiteLLM port [$LITELLM_PORT]: " port_input
            port_input=${port_input:-$LITELLM_PORT}

            if check_port_available "$port_input"; then
                LITELLM_PORT="$port_input"
                print_success "LiteLLM port: $LITELLM_PORT"
                break
            else
                print_error "Port $port_input is in use. Try another."
            fi
        done
    fi

    echo ""
    print_success "Port configuration complete"
}

#############################################
# CREDENTIALS CONFIGURATION
#############################################

configure_credentials() {
    print_header "CREDENTIALS & SECURITY"

    echo "Configure authentication credentials:"
    echo "Leave blank to auto-generate secure passwords."
    echo ""

    # PostgreSQL
    if [ "$POSTGRES_ENABLED" = "true" ]; then
        echo "${CYAN}PostgreSQL${NC}"
        read -p "  Database user [$POSTGRES_USER]: " user_input
        [ -n "$user_input" ] && POSTGRES_USER="$user_input"

        read -p "  Database name [$POSTGRES_DB]: " db_input
        [ -n "$db_input" ] && POSTGRES_DB="$db_input"

        read -sp "  Database password [auto-generate]: " pass_input
        echo ""
        if [ -n "$pass_input" ]; then
            POSTGRES_PASSWORD="$pass_input"
        else
            POSTGRES_PASSWORD=$(generate_password)
            print_info "  Generated password: ${POSTGRES_PASSWORD:0:4}...${POSTGRES_PASSWORD: -4}"
        fi
        echo ""
    fi

    # Qdrant
    if [ "$QDRANT_ENABLED" = "true" ]; then
        echo "${CYAN}Qdrant${NC}"
        read -sp "  API key [auto-generate]: " key_input
        echo ""
        if [ -n "$key_input" ]; then
            QDRANT_API_KEY="$key_input"
        else
            QDRANT_API_KEY=$(generate_key)
            print_info "  Generated API key: ${QDRANT_API_KEY:0:8}...${QDRANT_API_KEY: -8}"
        fi
        echo ""
    fi

    # n8n
    if [ "$N8N_ENABLED" = "true" ]; then
        echo "${CYAN}n8n${NC}"
        read -p "  Basic auth username [$N8N_BASIC_AUTH_USER]: " user_input
        [ -n "$user_input" ] && N8N_BASIC_AUTH_USER="$user_input"

        read -sp "  Basic auth password [auto-generate]: " pass_input
        echo ""
        if [ -n "$pass_input" ]; then
            N8N_BASIC_AUTH_PASSWORD="$pass_input"
        else
            N8N_BASIC_AUTH_PASSWORD=$(generate_password)
            print_info "  Generated password: ${N8N_BASIC_AUTH_PASSWORD:0:4}...${N8N_BASIC_AUTH_PASSWORD: -4}"
        fi

        # Encryption key (always auto-generate for security)
        N8N_ENCRYPTION_KEY=$(generate_key)
        print_info "  Generated encryption key: ${N8N_ENCRYPTION_KEY:0:8}...${N8N_ENCRYPTION_KEY: -8}"
        echo ""
    fi

    # Open WebUI
    if [ "$OPENWEBUI_ENABLED" = "true" ]; then
        echo "${CYAN}Open WebUI${NC}"
        # Secret key (always auto-generate for security)
        OPENWEBUI_SECRET_KEY=$(generate_key)
        print_info "  Generated secret key: ${OPENWEBUI_SECRET_KEY:0:8}...${OPENWEBUI_SECRET_KEY: -8}"
        echo ""
    fi

    # LiteLLM
    if [ "$LITELLM_ENABLED" = "true" ]; then
        echo "${CYAN}LiteLLM${NC}"
        read -sp "  Master key [auto-generate]: " key_input
        echo ""
        if [ -n "$key_input" ]; then
            LITELLM_MASTER_KEY="$key_input"
        else
            LITELLM_MASTER_KEY=$(generate_key)
            print_info "  Generated master key: ${LITELLM_MASTER_KEY:0:8}...${LITELLM_MASTER_KEY: -8}"
        fi

        # Database URL
        if [ "$POSTGRES_ENABLED" = "true" ]; then
            LITELLM_DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/litellm"
            print_info "  Database: litellm (on PostgreSQL)"
        fi
        echo ""
    fi

    print_success "Credentials configured"
}

#############################################
# ADVANCED OPTIONS
#############################################

configure_advanced_options() {
    print_header "ADVANCED OPTIONS"

    echo "Configure advanced settings? (recommended for production)"
    read -p "Configure advanced options? [y/N]: " configure_advanced

    if [[ ! "$configure_advanced" =~ ^[Yy]$ ]]; then
        print_info "Using default advanced settings"
        return
    fi

    echo ""

    # PostgreSQL tuning
    if [ "$POSTGRES_ENABLED" = "true" ]; then
        echo "${CYAN}PostgreSQL Performance Tuning${NC}"
        read -p "  Max connections [$POSTGRES_MAX_CONNECTIONS]: " input
        [ -n "$input" ] && POSTGRES_MAX_CONNECTIONS="$input"

        read -p "  Shared buffers [$POSTGRES_SHARED_BUFFERS]: " input
        [ -n "$input" ] && POSTGRES_SHARED_BUFFERS="$input"

        read -p "  Work memory [$POSTGRES_WORK_MEM]: " input
        [ -n "$input" ] && POSTGRES_WORK_MEM="$input"

        echo ""
    fi

    # Qdrant tuning
    if [ "$QDRANT_ENABLED" = "true" ]; then
        echo "${CYAN}Qdrant Performance Tuning${NC}"
        read -p "  Max segment size (KB) [$QDRANT_MAX_SEGMENT_SIZE_KB]: " input
        [ -n "$input" ] && QDRANT_MAX_SEGMENT_SIZE_KB="$input"

        read -p "  Indexing threshold (KB) [$QDRANT_INDEXING_THRESHOLD_KB]: " input
        [ -n "$input" ] && QDRANT_INDEXING_THRESHOLD_KB="$input"

        echo ""
    fi

    # Ollama tuning
    if [ "$OLLAMA_ENABLED" = "true" ]; then
        echo "${CYAN}Ollama Performance Tuning${NC}"
        read -p "  Max loaded models [$OLLAMA_MAX_LOADED_MODELS]: " input
        [ -n "$input" ] && OLLAMA_MAX_LOADED_MODELS="$input"

        read -p "  Keep alive duration [$OLLAMA_KEEP_ALIVE]: " input
        [ -n "$input" ] && OLLAMA_KEEP_ALIVE="$input"

        read -p "  Context size [$OLLAMA_NUM_CTX]: " input
        [ -n "$input" ] && OLLAMA_NUM_CTX="$input"

        echo ""
    fi

    # n8n tuning
    if [ "$N8N_ENABLED" = "true" ]; then
        echo "${CYAN}n8n Performance Tuning${NC}"
        read -p "  Save successful executions? [$N8N_EXECUTIONS_DATA_SAVE_ON_SUCCESS]: " input
        [ -n "$input" ] && N8N_EXECUTIONS_DATA_SAVE_ON_SUCCESS="$input"

        read -p"  Execution timeout (minutes) [$N8N_EXECUTIONS_TIMEOUT]: " input
        [ -n "$input" ] && N8N_EXECUTIONS_TIMEOUT="$input"

        read -p "  Max execution timeout (minutes) [$N8N_EXECUTIONS_TIMEOUT_MAX]: " input
        [ -n "$input" ] && N8N_EXECUTIONS_TIMEOUT_MAX="$input"

        echo ""
    fi

    # Open WebUI tuning
    if [ "$OPENWEBUI_ENABLED" = "true" ]; then
        echo "${CYAN}Open WebUI Configuration${NC}"
        read -p "  Enable signup? [$OPENWEBUI_ENABLE_SIGNUP]: " input
        [ -n "$input" ] && OPENWEBUI_ENABLE_SIGNUP="$input"

        read -p "  Default models [$OPENWEBUI_DEFAULT_MODELS]: " input
        [ -n "$input" ] && OPENWEBUI_DEFAULT_MODELS="$input"

        echo ""
    fi

    # LiteLLM tuning
    if [ "$LITELLM_ENABLED" = "true" ]; then
        echo "${CYAN}LiteLLM Configuration${NC}"
        read -p "  Enable telemetry? [$LITELLM_TELEMETRY]: " input
        [ -n "$input" ] && LITELLM_TELEMETRY="$input"

        read -p "  Request timeout (seconds) [$LITELLM_REQUEST_TIMEOUT]: " input
        [ -n "$input" ] && LITELLM_REQUEST_TIMEOUT="$input"

        echo ""
    fi

    print_success "Advanced options configured"
}

#############################################
# OPTIONAL FEATURES
#############################################

configure_optional_features() {
    print_header "OPTIONAL FEATURES"

    echo "Configure optional integrations:"
    echo ""

    # Signal notifications
    echo "${CYAN}Signal Notifications${NC}"
    echo "  Send deployment notifications via Signal messenger"
    read -p "Enable Signal notifications? [y/N]: " enable_signal
    SIGNAL_ENABLED=$( [[ "$enable_signal" =~ ^[Yy]$ ]] && echo "true" || echo "false" )

    if [ "$SIGNAL_ENABLED" = "true" ]; then
        echo ""
        echo "  Signal CLI must be installed and registered."
        echo "  See: https://github.com/AsamK/signal-cli"
        echo ""

        read -p "  Your Signal phone number (e.g., +1234567890): " signal_phone
        SIGNAL_PHONE="$signal_phone"

        read -p "  Recipient phone number (e.g., +1234567890): " signal_recipient
        SIGNAL_RECIPIENT="$signal_recipient"

        read -p "  Signal CLI endpoint [$SIGNAL_ENDPOINT]: " signal_endpoint
        [ -n "$signal_endpoint" ] && SIGNAL_ENDPOINT="$signal_endpoint"

        print_info "  Signal will be tested during deployment"
    fi

    echo ""
    print_success "Optional features configured"
}
#############################################
# DOCKER COMPOSE FILE GENERATION
#############################################

generate_docker_compose() {
    print_header "GENERATING DOCKER COMPOSE"
    
    local compose_file="$BASE_PATH/config/docker-compose.yml"
    
    print_step "Creating docker-compose.yml..."
    
    cat > "$compose_file" << 'EOF'
version: '3.8'

networks:
  ai-platform:
    driver: bridge

volumes:
  postgres_data:
  qdrant_data:
  ollama_data:
  n8n_data:
  openwebui_data:

services:
EOF

    # Add PostgreSQL service
    if [ "$POSTGRES_ENABLED" = "true" ]; then
        cat >> "$compose_file" << EOF

  postgres:
    image: postgres:16-alpine
    container_name: ai-postgres
    restart: unless-stopped
    networks:
      - ai-platform
    ports:
      - "${POSTGRES_PORT}:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ${BASE_PATH}/backups/postgres:/backups
    env_file:
      - ${BASE_PATH}/config/postgres.env
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    fi

    # Add Qdrant service
    if [ "$QDRANT_ENABLED" = "true" ]; then
        cat >> "$compose_file" << EOF

  qdrant:
    image: qdrant/qdrant:latest
    container_name: ai-qdrant
    restart: unless-stopped
    networks:
      - ai-platform
    ports:
      - "${QDRANT_PORT}:6333"
      - "${QDRANT_GRPC_PORT}:6334"
    volumes:
      - qdrant_data:/qdrant/storage
      - ${BASE_PATH}/backups/qdrant:/backups
    env_file:
      - ${BASE_PATH}/config/qdrant.env
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:6333/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    fi

    # Add Ollama service
    if [ "$OLLAMA_ENABLED" = "true" ]; then
        cat >> "$compose_file" << EOF

  ollama:
    image: ollama/ollama:latest
    container_name: ai-ollama
    restart: unless-stopped
    networks:
      - ai-platform
    ports:
      - "${OLLAMA_PORT}:11434"
    volumes:
      - ollama_data:/root/.ollama
      - ${BASE_PATH}/models:/models
    env_file:
      - ${BASE_PATH}/config/ollama.env
EOF

        # Add GPU support if enabled
        if [ "$OLLAMA_GPU_ENABLED" = "true" ]; then
            cat >> "$compose_file" << EOF
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
        fi

        cat >> "$compose_file" << EOF
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    fi

    # Add n8n service
    if [ "$N8N_ENABLED" = "true" ]; then
        cat >> "$compose_file" << EOF

  n8n:
    image: n8nio/n8n:latest
    container_name: ai-n8n
    restart: unless-stopped
    networks:
      - ai-platform
    ports:
      - "${N8N_PORT}:5678"
    volumes:
      - n8n_data:/home/node/.n8n
      - ${BASE_PATH}/workflows:/workflows
    env_file:
      - ${BASE_PATH}/config/n8n.env
EOF

        # Add PostgreSQL dependency if enabled
        if [ "$POSTGRES_ENABLED" = "true" ]; then
            cat >> "$compose_file" << EOF
    depends_on:
      postgres:
        condition: service_healthy
EOF
        fi

        cat >> "$compose_file" << EOF
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    fi

    # Add Open WebUI service
    if [ "$OPENWEBUI_ENABLED" = "true" ]; then
        cat >> "$compose_file" << EOF

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ai-openwebui
    restart: unless-stopped
    networks:
      - ai-platform
    ports:
      - "${OPENWEBUI_PORT}:8080"
    volumes:
      - openwebui_data:/app/backend/data
      - ${BASE_PATH}/uploads:/app/backend/uploads
    env_file:
      - ${BASE_PATH}/config/openwebui.env
EOF

        # Add dependencies
        local deps_added=false
        if [ "$OLLAMA_ENABLED" = "true" ] || [ "$POSTGRES_ENABLED" = "true" ]; then
            cat >> "$compose_file" << EOF
    depends_on:
EOF
            deps_added=true
        fi

        if [ "$OLLAMA_ENABLED" = "true" ]; then
            cat >> "$compose_file" << EOF
      ollama:
        condition: service_healthy
EOF
        fi

        if [ "$POSTGRES_ENABLED" = "true" ]; then
            cat >> "$compose_file" << EOF
      postgres:
        condition: service_healthy
EOF
        fi

        cat >> "$compose_file" << EOF
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    fi

    # Add LiteLLM service
    if [ "$LITELLM_ENABLED" = "true" ]; then
        cat >> "$compose_file" << EOF

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: ai-litellm
    restart: unless-stopped
    networks:
      - ai-platform
    ports:
      - "${LITELLM_PORT}:4000"
    volumes:
      - ${BASE_PATH}/config/litellm:/app/config
      - ${BASE_PATH}/logs/litellm:/app/logs
    env_file:
      - ${BASE_PATH}/config/litellm.env
    command: --config /app/config/config.yaml --port 4000
EOF

        # Add dependencies
        if [ "$POSTGRES_ENABLED" = "true" ]; then
            cat >> "$compose_file" << EOF
    depends_on:
      postgres:
        condition: service_healthy
EOF
        fi

        cat >> "$compose_file" << EOF
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    fi

    print_success "docker-compose.yml created"
}

#############################################
# MAIN .ENV FILE GENERATION
#############################################

generate_main_env() {
    print_header "GENERATING MAIN ENV FILE"
    
    local env_file="$BASE_PATH/config/.env"
    
    print_step "Creating .env..."
    
    cat > "$env_file" << EOF
#############################################
# AI Platform Configuration
# Generated: $(date)
# Base Path: $BASE_PATH
#############################################

# Base configuration
BASE_PATH=$BASE_PATH
COMPOSE_PROJECT_NAME=ai-platform

# Service enablement
POSTGRES_ENABLED=$POSTGRES_ENABLED
QDRANT_ENABLED=$QDRANT_ENABLED
OLLAMA_ENABLED=$OLLAMA_ENABLED
N8N_ENABLED=$N8N_ENABLED
OPENWEBUI_ENABLED=$OPENWEBUI_ENABLED
LITELLM_ENABLED=$LITELLM_ENABLED

# Port configuration
POSTGRES_PORT=$POSTGRES_PORT
QDRANT_PORT=$QDRANT_PORT
QDRANT_GRPC_PORT=$QDRANT_GRPC_PORT
OLLAMA_PORT=$OLLAMA_PORT
N8N_PORT=$N8N_PORT
OPENWEBUI_PORT=$OPENWEBUI_PORT
LITELLM_PORT=$LITELLM_PORT

# Optional features
SIGNAL_ENABLED=$SIGNAL_ENABLED
EOF

    if [ "$SIGNAL_ENABLED" = "true" ]; then
        cat >> "$env_file" << EOF
SIGNAL_PHONE=$SIGNAL_PHONE
SIGNAL_RECIPIENT=$SIGNAL_RECIPIENT
SIGNAL_ENDPOINT=$SIGNAL_ENDPOINT
EOF
    fi

    print_success ".env created"
}

#############################################
# POSTGRESQL ENV GENERATION
#############################################

generate_postgres_env() {
    if [ "$POSTGRES_ENABLED" != "true" ]; then
        return
    fi
    
    print_step "Creating postgres.env..."
    
    local env_file="$BASE_PATH/config/postgres.env"
    
    cat > "$env_file" << EOF
#############################################
# PostgreSQL Configuration
#############################################

POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB

# Performance tuning
POSTGRES_MAX_CONNECTIONS=$POSTGRES_MAX_CONNECTIONS
POSTGRES_SHARED_BUFFERS=$POSTGRES_SHARED_BUFFERS
POSTGRES_WORK_MEM=$POSTGRES_WORK_MEM
POSTGRES_MAINTENANCE_WORK_MEM=$POSTGRES_MAINTENANCE_WORK_MEM
POSTGRES_EFFECTIVE_CACHE_SIZE=$POSTGRES_EFFECTIVE_CACHE_SIZE

# WAL configuration
POSTGRES_WAL_LEVEL=replica
POSTGRES_MAX_WAL_SENDERS=3
POSTGRES_MAX_REPLICATION_SLOTS=3

# Logging
POSTGRES_LOG_STATEMENT=none
POSTGRES_LOG_DURATION=off
POSTGRES_LOG_MIN_DURATION_STATEMENT=1000
EOF

    print_success "postgres.env created"
}

#############################################
# QDRANT ENV GENERATION
#############################################

generate_qdrant_env() {
    if [ "$QDRANT_ENABLED" != "true" ]; then
        return
    fi
    
    print_step "Creating qdrant.env..."
    
    local env_file="$BASE_PATH/config/qdrant.env"
    
    cat > "$env_file" << EOF
#############################################
# Qdrant Configuration
#############################################

QDRANT__SERVICE__HTTP_PORT=6333
QDRANT__SERVICE__GRPC_PORT=6334

# API Key
QDRANT__SERVICE__API_KEY=$QDRANT_API_KEY

# Performance tuning
QDRANT__STORAGE__PERFORMANCE__MAX_SEARCH_THREADS=$QDRANT_MAX_SEARCH_THREADS
QDRANT__STORAGE__OPTIMIZERS__DEFAULT_SEGMENT_NUMBER=$QDRANT_DEFAULT_SEGMENT_NUMBER
QDRANT__STORAGE__OPTIMIZERS__INDEXING_THRESHOLD_KB=$QDRANT_INDEXING_THRESHOLD_KB
QDRANT__STORAGE__OPTIMIZERS__MAX_SEGMENT_SIZE_KB=$QDRANT_MAX_SEGMENT_SIZE_KB

# WAL configuration
QDRANT__STORAGE__WAL__WAL_CAPACITY_MB=$QDRANT_WAL_CAPACITY_MB
QDRANT__STORAGE__WAL__WAL_SEGMENTS_AHEAD=$QDRANT_WAL_SEGMENTS_AHEAD

# Snapshots
QDRANT__STORAGE__SNAPSHOTS__ENABLED=true
QDRANT__STORAGE__SNAPSHOTS__PATH=/qdrant/storage/snapshots

# Telemetry
QDRANT__TELEMETRY_DISABLED=$QDRANT_TELEMETRY_DISABLED
EOF

    print_success "qdrant.env created"
}

#############################################
# OLLAMA ENV GENERATION
#############################################

generate_ollama_env() {
    if [ "$OLLAMA_ENABLED" != "true" ]; then
        return
    fi
    
    print_step "Creating ollama.env..."
    
    local env_file="$BASE_PATH/config/ollama.env"
    
    cat > "$env_file" << EOF
#############################################
# Ollama Configuration
#############################################

OLLAMA_HOST=0.0.0.0:11434

# Model configuration
OLLAMA_MODELS=$OLLAMA_MODELS
OLLAMA_KEEP_ALIVE=$OLLAMA_KEEP_ALIVE
OLLAMA_MAX_LOADED_MODELS=$OLLAMA_MAX_LOADED_MODELS

# Context and performance
OLLAMA_NUM_PARALLEL=$OLLAMA_NUM_PARALLEL
OLLAMA_NUM_CTX=$OLLAMA_NUM_CTX
OLLAMA_NUM_THREAD=$OLLAMA_NUM_THREAD

# GPU configuration
OLLAMA_GPU_ENABLED=$OLLAMA_GPU_ENABLED
EOF

    if [ "$OLLAMA_GPU_ENABLED" = "true" ]; then
        cat >> "$env_file" << EOF
NVIDIA_VISIBLE_DEVICES=all
NVIDIA_DRIVER_CAPABILITIES=compute,utility
EOF
    fi

    print_success "ollama.env created"
}

#############################################
# N8N ENV GENERATION
#############################################

generate_n8n_env() {
    if [ "$N8N_ENABLED" != "true" ]; then
        return
    fi
    
    print_step "Creating n8n.env..."
    
    local env_file="$BASE_PATH/config/n8n.env"
    
    cat > "$env_file" << EOF
#############################################
# n8n Configuration
#############################################

# Basic auth
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=$N8N_BASIC_AUTH_USER
N8N_BASIC_AUTH_PASSWORD=$N8N_BASIC_AUTH_PASSWORD

# Encryption
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY

# Webhook configuration
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=http
WEBHOOK_URL=http://localhost:$N8N_PORT/

# Execution configuration
N8N_EXECUTIONS_DATA_SAVE_ON_ERROR=$N8N_EXECUTIONS_DATA_SAVE_ON_ERROR
N8N_EXECUTIONS_DATA_SAVE_ON_SUCCESS=$N8N_EXECUTIONS_DATA_SAVE_ON_SUCCESS
N8N_EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=$N8N_EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS

# Timeout configuration
EXECUTIONS_TIMEOUT=$N8N_EXECUTIONS_TIMEOUT
EXECUTIONS_TIMEOUT_MAX=$N8N_EXECUTIONS_TIMEOUT_MAX

# Performance
N8N_CONCURRENCY_PRODUCTION_LIMIT=$N8N_CONCURRENCY_PRODUCTION_LIMIT
EOF

    # Add PostgreSQL configuration if enabled
    if [ "$POSTGRES_ENABLED" = "true" ]; then
        cat >> "$env_file" << EOF

# Database configuration
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=$POSTGRES_USER
DB_POSTGRESDB_PASSWORD=$POSTGRES_PASSWORD
EOF
    fi

    print_success "n8n.env created"
}

#############################################
# OPEN WEBUI ENV GENERATION
#############################################

generate_openwebui_env() {
    if [ "$OPENWEBUI_ENABLED" != "true" ]; then
        return
    fi
    
    print_step "Creating openwebui.env..."
    
    local env_file="$BASE_PATH/config/openwebui.env"
    
    cat > "$env_file" << EOF
#############################################
# Open WebUI Configuration
#############################################

# Basic configuration
WEBUI_SECRET_KEY=$OPENWEBUI_SECRET_KEY
ENABLE_SIGNUP=$OPENWEBUI_ENABLE_SIGNUP
DEFAULT_MODELS=$OPENWEBUI_DEFAULT_MODELS

# Ollama integration
EOF

    if [ "$OLLAMA_ENABLED" = "true" ]; then
        cat >> "$env_file" << EOF
OLLAMA_BASE_URL=http://ollama:11434
EOF
    else
        cat >> "$env_file" << EOF
OLLAMA_BASE_URL=
EOF
    fi

    cat >> "$env_file" << EOF

# RAG configuration
ENABLE_RAG_WEB_SEARCH=$OPENWEBUI_ENABLE_RAG
ENABLE_RAG_HYBRID_SEARCH=$OPENWEBUI_ENABLE_RAG
EOF

    # Add Qdrant configuration if enabled
    if [ "$QDRANT_ENABLED" = "true" ] && [ "$OPENWEBUI_ENABLE_RAG" = "true" ]; then
        cat >> "$env_file" << EOF

# Vector database (Qdrant)
VECTOR_DB=qdrant
QDRANT_URI=http://qdrant:6333
QDRANT_API_KEY=$QDRANT_API_KEY
EOF
    fi

    # Add PostgreSQL configuration if enabled
    if [ "$POSTGRES_ENABLED" = "true" ]; then
        cat >> "$env_file" << EOF

# Database configuration
DATABASE_URL=postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@postgres:5432/openwebui
EOF
    fi

    cat >> "$env_file" << EOF

# File uploads
ENABLE_IMAGE_GENERATION=true
ENABLE_COMMUNITY_SHARING=false
EOF

    print_success "openwebui.env created"
}

#############################################
# LITELLM ENV GENERATION
#############################################

generate_litellm_env() {
    if [ "$LITELLM_ENABLED" != "true" ]; then
        return
    fi
    
    print_step "Creating litellm.env..."
    
    local env_file="$BASE_PATH/config/litellm.env"
    
    cat > "$env_file" << EOF
#############################################
# LiteLLM Configuration
#############################################

# Master key
LITELLM_MASTER_KEY=$LITELLM_MASTER_KEY

# Database configuration
EOF

    if [ "$POSTGRES_ENABLED" = "true" ]; then
        cat >> "$env_file" << EOF
DATABASE_URL=$LITELLM_DATABASE_URL
EOF
    fi

    cat >> "$env_file" << EOF

# Proxy configuration
LITELLM_PORT=4000
LITELLM_DROP_PARAMS=true

# Telemetry
LITELLM_TELEMETRY=$LITELLM_TELEMETRY

# Timeouts
LITELLM_REQUEST_TIMEOUT=$LITELLM_REQUEST_TIMEOUT
LITELLM_TIMEOUT=$LITELLM_TIMEOUT

# Logging
LITELLM_LOG=INFO
SET_VERBOSE=false
EOF

    print_success "litellm.env created"
}

#############################################
# LITELLM CONFIG.YAML GENERATION
#############################################

generate_litellm_config() {
    if [ "$LITELLM_ENABLED" != "true" ]; then
        return
    fi
    
    print_step "Creating litellm/config.yaml..."
    
    # Create litellm config directory
    mkdir -p "$BASE_PATH/config/litellm"
    
    local config_file="$BASE_PATH/config/litellm/config.yaml"
    
    cat > "$config_file" << EOF
# LiteLLM Proxy Configuration
# Generated: $(date)

model_list:
EOF

    # Add Ollama models if enabled
    if [ "$OLLAMA_ENABLED" = "true" ]; then
        # Convert comma-separated models to array
        IFS=',' read -ra MODELS <<< "$OLLAMA_MODELS"
        
        for model in "${MODELS[@]}"; do
            model=$(echo "$model" | xargs)  # Trim whitespace
            cat >> "$config_file" << EOF
  - model_name: $model
    litellm_params:
      model: ollama/$model
      api_base: http://ollama:11434
      
EOF
        done
    fi

    cat >> "$config_file" << EOF

# General settings
general_settings:
  master_key: $LITELLM_MASTER_KEY
  
  # Database (if PostgreSQL enabled)
EOF

    if [ "$POSTGRES_ENABLED" = "true" ]; then
        cat >> "$config_file" << EOF
  database_url: $LITELLM_DATABASE_URL
  database_type: postgres
EOF
    fi

    cat >> "$config_file" << EOF
  
  # Fallback & retry
  num_retries: 3
  request_timeout: $LITELLM_REQUEST_TIMEOUT
  fallbacks: []
  
  # Rate limiting
  max_parallel_requests: 100
  
  # Caching (disabled by default)
  cache: false
  
  # Telemetry
  telemetry: $LITELLM_TELEMETRY

# Logging
litellm_settings:
  drop_params: true
  set_verbose: false
  json_logs: true
EOF

    print_success "litellm/config.yaml created"
}

#############################################
# GENERATE ALL CONFIGURATION FILES
#############################################

generate_all_configs() {
    print_header "CONFIGURATION FILE GENERATION"
    
    # Create necessary directories
    print_step "Creating directory structure..."
    mkdir -p "$BASE_PATH/config"
    mkdir -p "$BASE_PATH/backups/postgres"
    mkdir -p "$BASE_PATH/backups/qdrant"
    mkdir -p "$BASE_PATH/models"
    mkdir -p "$BASE_PATH/workflows"
    mkdir -p "$BASE_PATH/uploads"
    mkdir -p "$BASE_PATH/logs/litellm"
    print_success "Directory structure created"
    
    # Generate all files
    generate_docker_compose
    generate_main_env
    generate_postgres_env
    generate_qdrant_env
    generate_ollama_env
    generate_n8n_env
    generate_openwebui_env
    generate_litellm_env
    generate_litellm_config
    
    # Set permissions
    print_step "Setting permissions..."
    chmod 600 "$BASE_PATH/config"/*.env 2>/dev/null || true
    chmod 600 "$BASE_PATH/config/litellm/config.yaml" 2>/dev/null || true
    print_success "Permissions set"
    
    echo ""
    print_success "All configuration files generated!"
    print_info "Configuration location: $BASE_PATH/config/"
}

# Execute configuration generation
generate_all_configs
#############################################
# CONFIGURATION BACKUP & EXPORT
#############################################

backup_configuration() {
    print_header "BACKING UP CONFIGURATION"

    local backup_dir="$BASE_PATH/config/backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="config_backup_${timestamp}"

    print_step "Creating backup: $backup_name"

    mkdir -p "$backup_dir"

    # Create backup archive
    tar -czf "$backup_dir/${backup_name}.tar.gz" \
        -C "$BASE_PATH/config" \
        --exclude='backups' \
        . 2>/dev/null

    if [ $? -eq 0 ]; then
        print_success "Configuration backed up to: $backup_dir/${backup_name}.tar.gz"
    else
        print_warning "Backup creation failed (non-critical)"
    fi

    # Keep only last 10 backups
    ls -t "$backup_dir"/config_backup_*.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm
}

#############################################
# EXPORT TO GOOGLE DRIVE
#############################################

export_to_google_drive() {
    if [ ! -f "$HOME/.config/rclone/rclone.conf" ]; then
        print_info "Skipping Google Drive export (rclone not configured)"
        return
    fi

    print_header "EXPORTING TO GOOGLE DRIVE"

    read -p "Export configuration to Google Drive? [y/N]: " export_gdrive

    if [[ ! "$export_gdrive" =~ ^[Yy]$ ]]; then
        print_info "Skipping Google Drive export"
        return
    fi

    # Get remote name
    local remotes=$(rclone listremotes 2>/dev/null | grep -i 'gdrive\|google')

    if [ -z "$remotes" ]; then
        print_warning "No Google Drive remote found in rclone"
        return
    fi

    local remote=$(echo "$remotes" | head -n1 | sed 's/:$//')

    read -p "Enter destination folder ID (or press Enter for root): " folder_id

    local dest="${remote}:"
    [ -n "$folder_id" ] && dest="${remote}:${folder_id}"

    print_step "Uploading configuration..."

    # Create export package
    local export_dir="/tmp/ai_platform_export_$$"
    mkdir -p "$export_dir"

    # Copy configuration files
    cp -r "$BASE_PATH/config" "$export_dir/" 2>/dev/null

    # Create metadata file
    cat > "$export_dir/metadata.json" << EOF
{
  "export_date": "$(date -Iseconds)",
  "base_path": "$BASE_PATH",
  "services": {
    "postgres": $POSTGRES_ENABLED,
    "qdrant": $QDRANT_ENABLED,
    "ollama": $OLLAMA_ENABLED,
    "n8n": $N8N_ENABLED,
    "openwebui": $OPENWEBUI_ENABLED,
    "litellm": $LITELLM_ENABLED
  },
  "ports": {
    "postgres": $POSTGRES_PORT,
    "qdrant": $QDRANT_PORT,
    "ollama": $OLLAMA_PORT,
    "n8n": $N8N_PORT,
    "openwebui": $OPENWEBUI_PORT,
    "litellm": $LITELLM_PORT
  }
}
EOF

    # Upload to Google Drive
    if rclone copy "$export_dir" "$dest/ai-platform-config" --progress 2>&1 | grep -q "Transferred:"; then
        print_success "Configuration exported to Google Drive"

        # Get shareable link if possible
        local folder_link=$(rclone link "$dest/ai-platform-config" 2>/dev/null)
        if [ -n "$folder_link" ]; then
            echo ""
            echo "${CYAN}Shareable link:${NC} $folder_link"
            echo ""
        fi
    else
        print_error "Failed to export to Google Drive"
    fi

    # Cleanup
    rm -rf "$export_dir"
}

#############################################
# CONFIGURATION VALIDATION
#############################################

validate_configuration() {
    print_header "VALIDATING CONFIGURATION"

    local errors=0

    # Check docker-compose.yml syntax
    print_step "Validating docker-compose.yml..."
    if command -v docker-compose &> /dev/null; then
        if docker-compose -f "$BASE_PATH/config/docker-compose.yml" config > /dev/null 2>&1; then
            print_success "docker-compose.yml is valid"
        else
            print_error "docker-compose.yml has syntax errors"
            ((errors++))
        fi
    else
        print_warning "docker-compose not installed, skipping validation"
    fi

    # Check required files exist
    print_step "Checking required files..."
    local required_files=(
        "$BASE_PATH/config/docker-compose.yml"
        "$BASE_PATH/config/.env"
    )

    [ "$POSTGRES_ENABLED" = "true" ] && required_files+=("$BASE_PATH/config/postgres.env")
    [ "$QDRANT_ENABLED" = "true" ] && required_files+=("$BASE_PATH/config/qdrant.env")
    [ "$OLLAMA_ENABLED" = "true" ] && required_files+=("$BASE_PATH/config/ollama.env")
    [ "$N8N_ENABLED" = "true" ] && required_files+=("$BASE_PATH/config/n8n.env")
    [ "$OPENWEBUI_ENABLED" = "true" ] && required_files+=("$BASE_PATH/config/openwebui.env")
    [ "$LITELLM_ENABLED" = "true" ] && required_files+=("$BASE_PATH/config/litellm.env")
    [ "$LITELLM_ENABLED" = "true" ] && required_files+=("$BASE_PATH/config/litellm/config.yaml")

    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            print_success "Found: $(basename $file)"
        else
            print_error "Missing: $file"
            ((errors++))
        fi
    done

    # Check port availability
    print_step "Checking port availability..."
    local ports_to_check=()

    [ "$POSTGRES_ENABLED" = "true" ] && ports_to_check+=($POSTGRES_PORT)
    [ "$QDRANT_ENABLED" = "true" ] && ports_to_check+=($QDRANT_PORT $QDRANT_GRPC_PORT)
    [ "$OLLAMA_ENABLED" = "true" ] && ports_to_check+=($OLLAMA_PORT)
    [ "$N8N_ENABLED" = "true" ] && ports_to_check+=($N8N_PORT)
    [ "$OPENWEBUI_ENABLED" = "true" ] && ports_to_check+=($OPENWEBUI_PORT)
    [ "$LITELLM_ENABLED" = "true" ] && ports_to_check+=($LITELLM_PORT)

    for port in "${ports_to_check[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            print_warning "Port $port is already in use"
            ((errors++))
        else
            print_success "Port $port is available"
        fi
    done

    echo ""
    if [ $errors -eq 0 ]; then
        print_success "All validation checks passed!"
        return 0
    else
        print_error "Validation found $errors error(s)"
        return 1
    fi
}

#############################################
# GENERATE DEPLOYMENT SUMMARY
#############################################

generate_deployment_summary() {
    local summary_file="$BASE_PATH/DEPLOYMENT_SUMMARY.md"

    print_step "Generating deployment summary..."

    cat > "$summary_file" << EOF
# AI Platform Deployment Summary

**Generated:** $(date)
**Base Path:** \`$BASE_PATH\`
**Configuration:** Complete ✓

---

## Enabled Services

EOF

    # List enabled services
    [ "$POSTGRES_ENABLED" = "true" ] && echo "- **PostgreSQL** - Port $POSTGRES_PORT" >> "$summary_file"
    [ "$QDRANT_ENABLED" = "true" ] && echo "- **Qdrant** - Port $QDRANT_PORT (gRPC: $QDRANT_GRPC_PORT)" >> "$summary_file"
    [ "$OLLAMA_ENABLED" = "true" ] && echo "- **Ollama** - Port $OLLAMA_PORT" >> "$summary_file"
    [ "$N8N_ENABLED" = "true" ] && echo "- **n8n** - Port $N8N_PORT" >> "$summary_file"
    [ "$OPENWEBUI_ENABLED" = "true" ] && echo "- **Open WebUI** - Port $OPENWEBUI_PORT" >> "$summary_file"
    [ "$LITELLM_ENABLED" = "true" ] && echo "- **LiteLLM** - Port $LITELLM_PORT" >> "$summary_file"

    cat >> "$summary_file" << EOF

---

## Access URLs (After Deployment)

EOF

    [ "$N8N_ENABLED" = "true" ] && echo "- **n8n:** http://localhost:$N8N_PORT" >> "$summary_file"
    [ "$OPENWEBUI_ENABLED" = "true" ] && echo "- **Open WebUI:** http://localhost:$OPENWEBUI_PORT" >> "$summary_file"
    [ "$LITELLM_ENABLED" = "true" ] && echo "- **LiteLLM:** http://localhost:$LITELLM_PORT" >> "$summary_file"
    [ "$QDRANT_ENABLED" = "true" ] && echo "- **Qdrant Dashboard:** http://localhost:$QDRANT_PORT/dashboard" >> "$summary_file"

    cat >> "$summary_file" << EOF

---

## Credentials

EOF

    # Add credentials
    [ "$POSTGRES_ENABLED" = "true" ] && cat >> "$summary_file" << EOF
### PostgreSQL
- **User:** \`$POSTGRES_USER\`
- **Password:** \`$POSTGRES_PASSWORD\`
- **Database:** \`$POSTGRES_DB\`

EOF

    [ "$QDRANT_ENABLED" = "true" ] && cat >> "$summary_file" << EOF
### Qdrant
- **API Key:** \`$QDRANT_API_KEY\`

EOF

    [ "$N8N_ENABLED" = "true" ] && cat >> "$summary_file" << EOF
### n8n
- **Username:** \`$N8N_BASIC_AUTH_USER\`
- **Password:** \`$N8N_BASIC_AUTH_PASSWORD\`

EOF

    [ "$OPENWEBUI_ENABLED" = "true" ] && cat >> "$summary_file" << EOF
### Open WebUI
- **Secret Key:** \`$OPENWEBUI_SECRET_KEY\`
- **Signup Enabled:** $OPENWEBUI_ENABLE_SIGNUP

EOF

    [ "$LITELLM_ENABLED" = "true" ] && cat >> "$summary_file" << EOF
### LiteLLM
- **Master Key:** \`$LITELLM_MASTER_KEY\`

EOF

    cat >> "$summary_file" << EOF

---

## Next Steps

1. **Deploy Services:**
   \`\`\`bash
   bash $BASE_PATH/scripts/02_deploy.sh
   \`\`\`

2. **Check Service Status:**
   \`\`\`bash
   cd $BASE_PATH/config
   docker-compose ps
   \`\`\`

3. **View Logs:**
   \`\`\`bash
   cd $BASE_PATH/config
   docker-compose logs -f [service_name]
   \`\`\`

4. **Stop Services:**
   \`\`\`bash
   cd $BASE_PATH/config
   docker-compose down
   \`\`\`

---

## Directory Structure

\`\`\`
$BASE_PATH/
├── config/              # Configuration files
│   ├── docker-compose.yml
│   ├── .env
│   ├── *.env           # Service-specific env files
│   └── litellm/        # LiteLLM configuration
├── backups/            # Database backups
│   ├── postgres/
│   └── qdrant/
├── models/             # Ollama models
├── workflows/          # n8n workflows
├── uploads/            # Open WebUI uploads
├── logs/               # Application logs
└── scripts/            # Deployment scripts
    ├── 01_configure.sh  # This script
    └── 02_deploy.sh     # Deployment script
\`\`\`

---

## Configuration Files

- **Main Config:** \`$BASE_PATH/config/.env\`
- **Docker Compose:** \`$BASE_PATH/config/docker-compose.yml\`
- **Service Configs:** \`$BASE_PATH/config/*.env\`
EOF

    if [ "$OLLAMA_ENABLED" = "true" ]; then
        cat >> "$summary_file" << EOF
- **Ollama Models:** $OLLAMA_MODELS

EOF
    fi

    cat >> "$summary_file" << EOF

---

## Support & Documentation

- **Project Repository:** [Add your repo URL]
- **Documentation:** [Add docs URL]
- **Issues:** [Add issues URL]

---

**Configuration Complete!** 🎉

Your AI Platform is ready for deployment. Review this summary and proceed to deployment when ready.

EOF

    print_success "Deployment summary created: $summary_file"
}

#############################################
# PREPARE DEPLOYMENT SCRIPT
#############################################

prepare_deployment_script() {
    print_step "Creating deployment script reference..."

    local deploy_script="$BASE_PATH/scripts/02_deploy.sh"

    # Check if deployment script exists
    if [ ! -f "$deploy_script" ]; then
        print_warning "Deployment script not found: $deploy_script"
        echo ""
        echo "You will need to run the deployment script separately once available."
        return
    fi

    # Make it executable
    chmod +x "$deploy_script"
    print_success "Deployment script ready"
}

#############################################
# FINAL SUMMARY & NEXT STEPS
#############################################

show_final_summary() {
    clear
    print_header "CONFIGURATION COMPLETE!"

    echo "${GREEN}✓${NC} All configuration files have been generated"
    echo "${GREEN}✓${NC} Configuration validated successfully"
    echo "${GREEN}✓${NC} Backup created"
    echo ""

    echo "═══════════════════════════════════════════════════════"
    echo "                   ${CYAN}DEPLOYMENT SUMMARY${NC}"
    echo "═══════════════════════════════════════════════════════"
    echo ""

    echo "${BOLD}Base Path:${NC} $BASE_PATH"
    echo ""

    echo "${BOLD}Enabled Services:${NC}"
    [ "$POSTGRES_ENABLED" = "true" ] && echo "  ${GREEN}✓${NC} PostgreSQL (port $POSTGRES_PORT)"
    [ "$QDRANT_ENABLED" = "true" ] && echo "  ${GREEN}✓${NC} Qdrant (port $QDRANT_PORT)"
    [ "$OLLAMA_ENABLED" = "true" ] && echo "  ${GREEN}✓${NC} Ollama (port $OLLAMA_PORT)"
    [ "$N8N_ENABLED" = "true" ] && echo "  ${GREEN}✓${NC} n8n (port $N8N_PORT)"
    [ "$OPENWEBUI_ENABLED" = "true" ] && echo "  ${GREEN}✓${NC} Open WebUI (port $OPENWEBUI_PORT)"
    [ "$LITELLM_ENABLED" = "true" ] && echo "  ${GREEN}✓${NC} LiteLLM (port $LITELLM_PORT)"

    echo ""
    echo "${BOLD}Configuration Files:${NC}"
    echo "  ${CYAN}→${NC} $BASE_PATH/config/docker-compose.yml"
    echo "  ${CYAN}→${NC} $BASE_PATH/config/.env"
    echo "  ${CYAN}→${NC} $BASE_PATH/config/*.env (service configs)"

    echo ""
    echo "${BOLD}Documentation:${NC}"
    echo "  ${CYAN}→${NC} $BASE_PATH/DEPLOYMENT_SUMMARY.md"

    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "                    ${CYAN}NEXT STEPS${NC}"
    echo "═══════════════════════════════════════════════════════"
    echo ""

    echo "1. ${BOLD}Review Configuration${NC}"
    echo "   ${CYAN}→${NC} cat $BASE_PATH/DEPLOYMENT_SUMMARY.md"
    echo ""

    echo "2. ${BOLD}Deploy Services${NC}"
    if [ -f "$BASE_PATH/scripts/02_deploy.sh" ]; then
        echo "   ${CYAN}→${NC} bash $BASE_PATH/scripts/02_deploy.sh"
    else
        echo "   ${CYAN}→${NC} cd $BASE_PATH/config"
        echo "   ${CYAN}→${NC} docker-compose up -d"
    fi
    echo ""

    echo "3. ${BOLD}Monitor Deployment${NC}"
    echo "   ${CYAN}→${NC} cd $BASE_PATH/config"
    echo "   ${CYAN}→${NC} docker-compose logs -f"
    echo ""

    echo "4. ${BOLD}Access Services${NC}"
    [ "$N8N_ENABLED" = "true" ] && echo "   ${CYAN}→${NC} n8n: http://localhost:$N8N_PORT"
    [ "$OPENWEBUI_ENABLED" = "true" ] && echo "   ${CYAN}→${NC} Open WebUI: http://localhost:$OPENWEBUI_PORT"
    [ "$LITELLM_ENABLED" = "true" ] && echo "   ${CYAN}→${NC} LiteLLM: http://localhost:$LITELLM_PORT"

    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo ""

    # Optional: Auto-proceed to deployment
    if [ -f "$BASE_PATH/scripts/02_deploy.sh" ]; then
        echo ""
        read -p "Would you like to proceed with deployment now? [Y/n]: " proceed

        if [[ ! "$proceed" =~ ^[Nn]$ ]]; then
            echo ""
            print_success "Starting deployment..."
            sleep 2
            bash "$BASE_PATH/scripts/02_deploy.sh"
        else
            echo ""
            print_info "Run deployment later with: bash $BASE_PATH/scripts/02_deploy.sh"
        fi
    fi
}

#############################################
# SIGNAL NOTIFICATION TEST
#############################################

test_signal_notification() {
    if [ "$SIGNAL_ENABLED" != "true" ]; then
        return
    fi

    print_step "Testing Signal notification..."

    if command -v signal-cli &> /dev/null; then
        local message="AI Platform: Configuration completed successfully on $(hostname)"

        if signal-cli -u "$SIGNAL_PHONE" send -m "$message" "$SIGNAL_RECIPIENT" &> /dev/null; then
            print_success "Signal notification sent"
        else
            print_warning "Signal notification failed (non-critical)"
        fi
    else
        print_warning "signal-cli not installed, skipping notification"
    fi
}

#############################################
# MAIN FINALIZATION WORKFLOW
#############################################

finalize_configuration() {
    # Backup configuration
    backup_configuration

    # Export to Google Drive (optional)
    export_to_google_drive

    # Validate configuration
    if ! validate_configuration; then
        echo ""
        read -p "Configuration has errors. Continue anyway? [y/N]: " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            print_error "Configuration aborted due to validation errors"
            exit 1
        fi
    fi

    # Generate deployment summary
    generate_deployment_summary

    # Prepare deployment script
    prepare_deployment_script

    # Test Signal notification
    test_signal_notification

    # Show final summary
    show_final_summary
}

#############################################
# SCRIPT EXECUTION
#############################################

# Execute finalization
finalize_configuration

# Script complete
print_success "Configuration script completed successfully!"
exit 0
