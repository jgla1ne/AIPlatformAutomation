#!/bin/bash

set -euo pipefail

# ============================================================================
# AI Platform - Service Configuration Script v9.0
# Configure Signal, Google Drive, Ollama models, and service settings
# ============================================================================

readonly SCRIPT_VERSION="9.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="${PROJECT_ROOT}/logs/configure-$(date +%Y%m%d-%H%M%S).log"

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
    echo "Service configuration started at $(date)" > "$LOG_FILE"
    info "Log file: $LOG_FILE"
}

# ============================================================================
# Display Banner
# ============================================================================

display_banner() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║    AI Platform - Service Configuration v${SCRIPT_VERSION}            ║"
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
# Configuration Menu
# ============================================================================

show_menu() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              Service Configuration Menu                    ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  1) Configure Signal API (link phone number)"
    echo "  2) Configure Google Drive sync"
    echo "  3) Download Ollama models"
    echo "  4) Configure LiteLLM settings"
    echo "  5) Configure Clawdbot"
    echo "  6) Configure AnythingLLM"
    echo "  7) Setup system daemons (auto-start on boot)"
    echo "  8) View service status"
    echo "  9) Run all configurations (recommended)"
    echo "  0) Exit"
    echo ""
}

# ============================================================================
# Signal API Configuration
# ============================================================================

configure_signal() {
    info "=== Signal API Configuration ==="
    echo "" | tee -a "$LOG_FILE"
    
    # Check if Signal container is running
    if ! docker ps --filter "name=signal-api" --filter "status=running" --format '{{.Names}}' | grep -q "signal-api"; then
        error "Signal API container is not running"
        error "Please run ./2-deploy-services.sh first"
        return 1
    fi
    
    info "Signal API can be linked in two ways:"
    echo "  1. Link as primary device (recommended for new setup)"
    echo "  2. Link as secondary device (if you have Signal on phone)"
    echo ""
    
    prompt "Choose linking method [1/2]:"
    read -r link_method
    
    case $link_method in
        1)
            configure_signal_primary
            ;;
        2)
            configure_signal_secondary
            ;;
        *)
            error "Invalid choice"
            return 1
            ;;
    esac
}

configure_signal_primary() {
    info "Linking Signal as PRIMARY device..."
    echo "" | tee -a "$LOG_FILE"
    
    prompt "Enter your phone number (with country code, e.g., +1234567890):"
    read -r phone_number
    
    if [[ ! $phone_number =~ ^\+[0-9]{10,15}$ ]]; then
        error "Invalid phone number format. Must start with + and country code"
        return 1
    fi
    
    info "Registering phone number: $phone_number"
    
    # Register the number
    if docker exec signal-api curl -X POST \
        -H "Content-Type: application/json" \
        -d "{\"number\":\"$phone_number\",\"use_voice\":false}" \
        http://localhost:8080/v1/register/$phone_number 2>&1 | tee -a "$LOG_FILE"; then
        
        success "Verification code sent to $phone_number"
        echo ""
        prompt "Enter the verification code you received:"
        read -r verification_code
        
        # Verify the code
        if docker exec signal-api curl -X POST \
            -H "Content-Type: application/json" \
            -d "{\"number\":\"$phone_number\",\"code\":\"$verification_code\"}" \
            http://localhost:8080/v1/register/$phone_number/verify 2>&1 | tee -a "$LOG_FILE"; then
            
            success "Signal successfully linked as primary device!"
            
            # Update Clawdbot config
            update_clawdbot_signal_number "$phone_number"
            
        else
            error "Failed to verify code"
            return 1
        fi
    else
        error "Failed to register phone number"
        return 1
    fi
}

configure_signal_secondary() {
    info "Linking Signal as SECONDARY device..."
    echo "" | tee -a "$LOG_FILE"
    
    prompt "Enter a device name (e.g., 'AI-Platform'):"
    read -r device_name
    
    device_name="${device_name:-AI-Platform}"
    
    info "Generating QR code for linking..."
    echo "" | tee -a "$LOG_FILE"
    
    # Generate linking URI
    local link_response
    link_response=$(docker exec signal-api curl -X GET \
        "http://localhost:8080/v1/qrcodelink?device_name=${device_name}" 2>&1)
    
    echo "$link_response" | tee -a "$LOG_FILE"
    
    echo "" | tee -a "$LOG_FILE"
    success "QR Code displayed above"
    echo "" | tee -a "$LOG_FILE"
    info "Steps to complete linking:"
    echo "  1. Open Signal app on your phone"
    echo "  2. Go to Settings → Linked Devices"
    echo "  3. Tap '+' or 'Link New Device'"
    echo "  4. Scan the QR code shown above"
    echo "" | tee -a "$LOG_FILE"
    
    prompt "Press Enter after scanning the QR code..."
    read -r
    
    # Wait a bit for linking to complete
    sleep 3
    
    # Check if any account is registered
    if docker exec signal-api curl -X GET http://localhost:8080/v1/accounts 2>&1 | grep -q "number"; then
        success "Signal successfully linked as secondary device!"
        
        # Extract the phone number
        local phone_number
        phone_number=$(docker exec signal-api curl -s http://localhost:8080/v1/accounts | grep -oP '"\+[0-9]+"' | tr -d '"' | head -1)
        
        if [[ -n $phone_number ]]; then
            info "Linked phone number: $phone_number"
            update_clawdbot_signal_number "$phone_number"
        fi
    else
        error "Linking may have failed. Check Signal app."
        return 1
    fi
}

update_clawdbot_signal_number() {
    local phone_number="$1"
    
    info "Updating Clawdbot configuration with Signal number..."
    
    local config_file="${PROJECT_ROOT}/data/clawdbot/config.json"
    
    if [[ -f $config_file ]]; then
        # Update the config file
        local temp_file="${config_file}.tmp"
        jq ".signalNumber = \"$phone_number\"" "$config_file" > "$temp_file" && mv "$temp_file" "$config_file"
        
        success "Clawdbot config updated"
        
        # Restart Clawdbot to apply changes
        info "Restarting Clawdbot..."
        docker restart clawdbot 2>&1 | tee -a "$LOG_FILE"
        sleep 3
        success "Clawdbot restarted"
    else
        warn "Clawdbot config file not found"
    fi
}

# ============================================================================
# Google Drive Configuration
# ============================================================================

configure_gdrive() {
    info "=== Google Drive Configuration ==="
    echo "" | tee -a "$LOG_FILE"
    
    # Check if gdrive-sync container is running
    if ! docker ps --filter "name=gdrive-sync" --filter "status=running" --format '{{.Names}}' | grep -q "gdrive-sync"; then
        error "Google Drive sync container is not running"
        error "Please run ./2-deploy-services.sh first"
        return 1
    fi
    
    info "This will configure rclone to sync with Google Drive"
    echo "" | tee -a "$LOG_FILE"
    
    prompt "Have you already configured rclone? [y/N]:"
    read -r has_config
    
    if [[ $has_config =~ ^[Yy]$ ]]; then
        configure_gdrive_existing
    else
        configure_gdrive_new
    fi
}

configure_gdrive_new() {
    info "Starting interactive rclone configuration..."
    echo "" | tee -a "$LOG_FILE"
    
    warn "IMPORTANT: When asked 'Auto config?', answer 'N' (No)"
    warn "You will need to authorize via a web browser"
    echo "" | tee -a "$LOG_FILE"
    
    prompt "Press Enter to start rclone config..."
    read -r
    
    # Run rclone config in the container
    docker exec -it gdrive-sync rclone config
    
    echo "" | tee -a "$LOG_FILE"
    success "Rclone configuration complete"
    
    # Get the remote name
    prompt "Enter the remote name you just configured (e.g., 'gdrive'):"
    read -r remote_name
    
    # Update .env file
    update_env_var "GDRIVE_REMOTE_NAME" "$remote_name"
    
    # Test the configuration
    test_gdrive_sync "$remote_name"
}

configure_gdrive_existing() {
    info "Using existing rclone configuration..."
    
    prompt "Enter your rclone config file path:"
    read -r config_path
    
    if [[ ! -f $config_path ]]; then
        error "Config file not found: $config_path"
        return 1
    fi
    
    # Copy config to the container volume
    cp "$config_path" "${PROJECT_ROOT}/data/gdrive/config/rclone.conf"
    success "Config file copied"
    
    # List remotes
    info "Available remotes:"
    docker exec gdrive-sync rclone listremotes
    
    prompt "Enter the remote name to use (e.g., 'gdrive'):"
    read -r remote_name
    
    # Update .env file
    update_env_var "GDRIVE_REMOTE_NAME" "$remote_name"
    
    # Test the configuration
    test_gdrive_sync "$remote_name"
}

test_gdrive_sync() {
    local remote_name="$1"
    
    info "Testing Google Drive connection..."
    
    if docker exec gdrive-sync rclone lsd "${remote_name}:" 2>&1 | tee -a "$LOG_FILE"; then
        success "Google Drive connection successful!"
        
        # Ask for sync path
        prompt "Enter the folder path to sync (leave empty for root):"
        read -r sync_path
        
        update_env_var "GDRIVE_REMOTE_PATH" "$sync_path"
        
        # Start initial sync
        info "Starting initial sync (this may take a while)..."
        docker exec gdrive-sync rclone sync "${remote_name}:${sync_path}" /data -v 2>&1 | tee -a "$LOG_FILE"
        
        success "Initial sync complete!"
        
        # Restart container with new settings
        info "Restarting gdrive-sync with new configuration..."
        cd "${PROJECT_ROOT}/stacks/gdrive"
        docker compose restart 2>&1 | tee -a "$LOG_FILE"
        
        success "Google Drive sync configured and running"
        
        # Show synced files
        echo "" | tee -a "$LOG_FILE"
        info "Synced files location: ${PROJECT_ROOT}/data/gdrive/sync"
        info "Files are accessible to all services for ingestion"
        
    else
        error "Failed to connect to Google Drive"
        error "Please check your configuration"
        return 1
    fi
}

# ============================================================================
# Ollama Model Configuration
# ============================================================================

configure_ollama() {
    info "=== Ollama Model Configuration ==="
    echo "" | tee -a "$LOG_FILE"
    
    # Check if Ollama container is running
    if ! docker ps --filter "name=ollama" --filter "status=running" --format '{{.Names}}' | grep -q "ollama"; then
        error "Ollama container is not running"
        error "Please run ./2-deploy-services.sh first"
        return 1
    fi
    
    info "Recommended models for the AI platform:"
    echo "  1. qwen2.5:latest (7B) - Main LLM model"
    echo "  2. nomic-embed-text:latest - Text embeddings"
    echo "  3. llama3.2:latest (3B) - Lightweight alternative"
    echo "  4. mistral:latest (7B) - Another good option"
    echo "" | tee -a "$LOG_FILE"
    
    prompt "Select models to download:"
    echo "  1) Download recommended (qwen2.5 + nomic-embed-text)"
    echo "  2) Download all models"
    echo "  3) Custom model selection"
    echo "  4) List available models"
    echo ""
    
    read -r choice
    
    case $choice in
        1)
            download_model "qwen2.5:latest"
            download_model "nomic-embed-text:latest"
            ;;
        2)
            download_model "qwen2.5:latest"
            download_model "nomic-embed-text:latest"
            download_model "llama3.2:latest"
            download_model "mistral:latest"
            ;;
        3)
            prompt "Enter model name (e.g., 'llama3.2:latest'):"
            read -r model_name
            download_model "$model_name"
            ;;
        4)
            info "Searching Ollama library..."
            docker exec ollama ollama list
            ;;
        *)
            error "Invalid choice"
            return 1
            ;;
    esac
    
    # List downloaded models
    echo "" | tee -a "$LOG_FILE"
    info "Currently downloaded models:"
    docker exec ollama ollama list | tee -a "$LOG_FILE"
}

download_model() {
    local model_name="$1"
    
    info "Downloading model: $model_name"
    info "This may take several minutes depending on model size..."
    echo "" | tee -a "$LOG_FILE"
    
    if docker exec ollama ollama pull "$model_name" 2>&1 | tee -a "$LOG_FILE"; then
        success "Model $model_name downloaded successfully"
    else
        error "Failed to download model $model_name"
        return 1
    fi
}

# ============================================================================
# LiteLLM Configuration
# ============================================================================

configure_litellm() {
    info "=== LiteLLM Configuration ==="
    echo "" | tee -a "$LOG_FILE"
    
    # List available Ollama models
    info "Available Ollama models:"
    docker exec ollama ollama list | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    prompt "Enter the default model to use (e.g., 'qwen2.5:latest'):"
    read -r default_model
    
    if [[ -z $default_model ]]; then
        default_model="qwen2.5:latest"
        info "Using default: $default_model"
    fi
    
    # Update LiteLLM config
    local config_file="${PROJECT_ROOT}/data/litellm/config.yaml"
    
    cat > "$config_file" << EOF
model_list:
  - model_name: ${default_model}
    litellm_params:
      model: ollama/${default_model}
      api_base: http://ollama:11434

  - model_name: nomic-embed-text
    litellm_params:
      model: ollama/nomic-embed-text:latest
      api_base: http://ollama:11434

litellm_settings:
  drop_params: true
  success_callback: []
  failure_callback: []
  
general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: "sqlite:////app/data/litellm.db"
  
router_settings:
  routing_strategy: "simple-shuffle"
  redis_host: null
  
environment_variables:
  OLLAMA_API_BASE: "http://ollama:11434"
EOF
    
    success "LiteLLM configuration updated"
    
    # Restart LiteLLM
    info "Restarting LiteLLM..."
    docker restart litellm 2>&1 | tee -a "$LOG_FILE"
    sleep 5
    
    success "LiteLLM restarted with new configuration"
    
    # Test LiteLLM
    echo "" | tee -a "$LOG_FILE"
    info "Testing LiteLLM API..."
    
    if docker exec litellm curl -s http://localhost:4000/health | grep -q "healthy"; then
        success "LiteLLM is healthy and responding"
    else
        warn "LiteLLM may not be responding yet (still initializing)"
    fi
}

# ============================================================================
# Clawdbot Configuration
# ============================================================================

configure_clawdbot() {
    info "=== Clawdbot Configuration ==="
    echo "" | tee -a "$LOG_FILE"
    
    local config_file="${PROJECT_ROOT}/data/clawdbot/config.json"
    
    # Load existing config
    if [[ -f $config_file ]]; then
        local current_config
        current_config=$(cat "$config_file")
        info "Current configuration:"
        echo "$current_config" | jq '.' | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
    fi
    
    prompt "Enter admin phone numbers (comma-separated, e.g., +1234567890,+0987654321):"
    read -r admin_numbers
    
    # Convert to JSON array
    local admin_array="[]"
    if [[ -n $admin_numbers ]]; then
        admin_array=$(echo "$admin_numbers" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";""))')
    fi
    
    prompt "Enter LiteLLM model name [qwen2.5:latest]:"
    read -r model_name
    model_name="${model_name:-qwen2.5:latest}"
    
    prompt "Enter max tokens [2048]:"
    read -r max_tokens
    max_tokens="${max_tokens:-2048}"
    
    prompt "Enter temperature (0.0-1.0) [0.7]:"
    read -r temperature
    temperature="${temperature:-0.7}"
    
    # Create updated config
    cat > "$config_file" << EOF
{
  "signalNumber": "${CLAWDBOT_SIGNAL_NUMBER}",
  "adminNumbers": ${admin_array},
  "liteLLMEndpoint": "http://litellm:4000",
  "liteLLMAPIKey": "${LITELLM_MASTER_KEY}",
  "modelName": "${model_name}",
  "maxTokens": ${max_tokens},
  "temperature": ${temperature},
  "systemPrompt": "You are a helpful AI assistant accessible via Signal messaging.",
  "features": {
    "imageGeneration": false,
    "webSearch": false,
    "fileAccess": true
  }
}
EOF
    
    success "Clawdbot configuration updated"
    
    # Restart Clawdbot
    info "Restarting Clawdbot..."
    docker restart clawdbot 2>&1 | tee -a "$LOG_FILE"
    sleep 3
    
    success "Clawdbot restarted with new configuration"
}

# ============================================================================
# AnythingLLM Configuration
# ============================================================================

configure_anythingllm() {
    info "=== AnythingLLM Configuration ==="
    echo "" | tee -a "$LOG_FILE"
    
    info "AnythingLLM is configured to use:"
    echo "  • LLM Provider: Ollama"
    echo "  • Ollama Base URL: http://ollama:11434"
    echo "  • Embedding Provider: Ollama"
    echo "  • Embedding Model: nomic-embed-text:latest"
    echo "  • Vector Database: LanceDB (built-in)"
    echo "" | tee -a "$LOG_FILE"
    
    info "Additional configuration via web UI:"
    local tailscale_ip
    tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "localhost")
    
    echo "  1. Access: https://${tailscale_ip}:8443/anythingllm" | tee -a "$LOG_FILE"
    echo "  2. Create admin account on first visit" | tee -a "$LOG_FILE"
    echo "  3. Go to Settings → LLM to verify Ollama connection" | tee -a "$LOG_FILE"
    echo "  4. Go to Settings → Embedder to verify embedding model" | tee -a "$LOG_FILE"
    echo "  5. Create workspaces and upload documents" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    info "Documents from Google Drive are available at:"
    echo "  /app/collector/hotdir/gdrive" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    success "AnythingLLM is ready for use"
}

# ============================================================================
# System Daemon Setup
# ============================================================================

setup_system_daemons() {
    info "=== Setting up System Daemons ==="
    echo "" | tee -a "$LOG_FILE"
    
    info "This will create systemd services to auto-start Docker Compose stacks on boot"
    echo "" | tee -a "$LOG_FILE"
    
    # Create systemd service template
    local service_template='[Unit]
Description=AI Platform - %i Stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=PROJECT_ROOT/stacks/%i
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target'
    
    # Replace PROJECT_ROOT placeholder
    service_template="${service_template//PROJECT_ROOT/$PROJECT_ROOT}"
    
    # List of stacks
    local stacks=("ollama" "litellm" "anythingllm" "clawdbot" "dify" "n8n" "signal" "gdrive" "nginx")
    
    for stack in "${stacks[@]}"; do
        local service_file="/etc/systemd/system/aiplatform-${stack}.service"
        
        info "Creating service: aiplatform-${stack}.service"
        
        echo "$service_template" | sed "s/%i/${stack}/g" | sudo tee "$service_file" > /dev/null
        
        # Enable the service
        sudo systemctl daemon-reload
        sudo systemctl enable "aiplatform-${stack}.service" 2>&1 | tee -a "$LOG_FILE"
        
        success "Service aiplatform-${stack} enabled"
    done
    
    echo "" | tee -a "$LOG_FILE"
    success "All services configured to start on boot"
    
    info "Service management commands:"
    echo "  • Start all:   sudo systemctl start aiplatform-*" | tee -a "$LOG_FILE"
    echo "  • Stop all:    sudo systemctl stop aiplatform-*" | tee -a "$LOG_FILE"
    echo "  • Status:      sudo systemctl status aiplatform-*" | tee -a "$LOG_FILE"
    echo "  • Disable:     sudo systemctl disable aiplatform-*" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# ============================================================================
# View Service Status
# ============================================================================

view_status() {
    info "=== Service Status ==="
    echo "" | tee -a "$LOG_FILE"
    
    # Docker containers
    info "Docker Containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | tee -a "$LOG_FILE"
    
    echo "" | tee -a "$LOG_FILE"
    
    # Systemd services
    if systemctl list-units --all | grep -q "aiplatform-"; then
        info "Systemd Services:"
        sudo systemctl status aiplatform-* --no-pager | grep -E "(●|Active:)" | tee -a "$LOG_FILE"
    else
        warn "No systemd services configured yet"
    fi
    
    echo "" | tee -a "$LOG_FILE"
    
    # Disk usage
    info "Disk Usage:"
    du -sh "${PROJECT_ROOT}/data"/* 2>/dev/null | sort -h | tee -a "$LOG_FILE"
    
    echo "" | tee -a "$LOG_FILE"
    
    # Tailscale status
    if command -v tailscale &> /dev/null; then
        info "Tailscale Status:"
        tailscale status --self | tee -a "$LOG_FILE"
    fi
}

# ============================================================================
# Run All Configurations
# ============================================================================

run_all_configurations() {
    info "=== Running All Configurations ==="
    echo "" | tee -a "$LOG_FILE"
    
    warn "This will run all configuration steps interactively"
    prompt "Continue? [y/N]:"
    read -r confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        info "Cancelled"
        return 0
    fi
    
    echo "" | tee -a "$LOG_FILE"
    
    # 1. Signal
    info "Step 1/7: Signal API Configuration"
    configure_signal
    
    echo "" | tee -a "$LOG_FILE"
    
    # 2. Google Drive
    info "Step 2/7: Google Drive Configuration"
    configure_gdrive
    
    echo "" | tee -a "$LOG_FILE"
    
    # 3. Ollama models
    info "Step 3/7: Ollama Model Download"
    configure_ollama
    
    echo "" | tee -a "$LOG_FILE"
    
    # 4. LiteLLM
    info "Step 4/7: LiteLLM Configuration"
    configure_litellm
    
    echo "" | tee -a "$LOG_FILE"
    
    # 5. Clawdbot
    info "Step 5/7: Clawdbot Configuration"
    configure_clawdbot
    
    echo "" | tee -a "$LOG_FILE"
    
    # 6. AnythingLLM
    info "Step 6/7: AnythingLLM Configuration"
    configure_anythingllm
    
    echo "" | tee -a "$LOG_FILE"
    
    # 7. System daemons
    info "Step 7/7: System Daemon Setup"
    setup_system_daemons
    
    echo "" | tee -a "$LOG_FILE"
    success "All configurations complete!"
}

# ============================================================================
# Update Environment Variable
# ============================================================================

update_env_var() {
    local key="$1"
    local value="$2"
    local env_file="${PROJECT_ROOT}/.env"
    
    if grep -q "^${key}=" "$env_file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
    else
        echo "${key}=${value}" >> "$env_file"
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    setup_logging
    display_banner
    load_environment
    
    if [[ $# -eq 0 ]]; then
        # Interactive mode
        while true; do
            show_menu
            prompt "Select an option [0-9]:"
            read -r choice
            
            case $choice in
                1) configure_signal ;;
                2) configure_gdrive ;;
                3) configure_ollama ;;
                4) configure_litellm ;;
                5) configure_clawdbot ;;
                6) configure_anythingllm ;;
                7) setup_system_daemons ;;
                8) view_status ;;
                9) run_all_configurations ;;
                0) 
                    info "Exiting..."
                    exit 0
                    ;;
                *)
                    error "Invalid option"
                    ;;
            esac
            
            echo ""
            prompt "Press Enter to continue..."
            read -r
        done
    else
        # Command-line mode
        case $1 in
            signal) configure_signal ;;
            gdrive) configure_gdrive ;;
            ollama) configure_ollama ;;
            litellm) configure_litellm ;;
            clawdbot) configure_clawdbot ;;
            anythingllm) configure_anythingllm ;;
            daemons) setup_system_daemons ;;
            status) view_status ;;
            all) run_all_configurations ;;
            *)
                error "Unknown command: $1"
                echo "Usage: $0 [signal|gdrive|ollama|litellm|clawdbot|anythingllm|daemons|status|all]"
                exit 1
                ;;
        esac
    fi
}

main "$@"
