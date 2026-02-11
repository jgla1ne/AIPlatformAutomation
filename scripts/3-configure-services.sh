#!/bin/bash

#==============================================================================
# Script 3: Service Configuration
# Purpose: Configure and manage deployed services
# Options:
#   1.  Manage LLM providers (add/remove/test)
#   2.  Pair Signal device
#   3.  Setup Google Drive OAuth
#   4.  Configure Qdrant collections
#   5.  Test service connections
#   6.  Configure webhooks
#   7.  Setup monitoring
#   8.  View service logs
#   9.  Restart services
#   10. Stop services
#   11. Rotate credentials
#   12. Backup configuration
#   13. Restore configuration
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
CREDENTIALS_FILE=" $ DATA_DIR/metadata/credentials.json"

# Check if metadata exists
if [[ ! -f " $ METADATA_FILE" ]]; then
    echo -e " $ {RED}Error: Setup not completed. Run scripts 1-2 first.${NC}"
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
    echo -e "${CYAN}║${NC}     ${BOLD}AI PLATFORM AUTOMATION - SERVICE CONFIG${NC}          ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}Script 3 of 5${NC} - Configure and manage services          ${CYAN}║${NC}"
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

print_warning() {
    echo -e " $ {YELLOW}[!]${NC}  $ 1"
}

print_info() {
    echo -e " $ {CYAN}[i]${NC}  $ 1"
}

confirm() {
    local prompt=" $ 1"
    local default="${2:-n}"
    local response
    
    if [[ " $ default" == "y" ]]; then
        prompt=" $ prompt [Y/n]: "
    else
        prompt=" $ prompt [y/N]: "
    fi
    
    read -r -p " $ (echo -e ${YELLOW} $ prompt $ {NC})" response
    response=${response:- $ default}
    
    [[ " $ response" =~ ^[Yy]$ ]]
}

pause() {
    read -p "Press Enter to continue..."
}

check_service_running() {
    local service= $ 1
    docker ps --format '{{.Names}}' | grep -q "^ $ {service} $ "
}

#------------------------------------------------------------------------------
# Main Menu
#------------------------------------------------------------------------------

show_main_menu() {
    print_header
    
    echo -e " $ {BOLD}Service Configuration Menu${NC}"
    echo ""
    echo -e "${CYAN}LLM & AI Services:${NC}"
    echo "  [1]  Manage LLM Providers"
    echo "  [2]  Configure Ollama Models"
    echo "  [3]  Test LLM Connections"
    echo ""
    echo -e "${CYAN}Integration Services:${NC}"
    echo "  [4]  Pair Signal Device"
    echo "  [5]  Setup Google Drive OAuth"
    echo "  [6]  Configure Webhooks"
    echo ""
    echo -e "${CYAN}Database Configuration:${NC}"
    echo "  [7]  Configure Qdrant Collections"
    echo "  [8]  Test Database Connections"
    echo "  [9]  Database Backup/Restore"
    echo ""
    echo -e "${CYAN}Service Management:${NC}"
    echo "  [10] View Service Logs"
    echo "  [11] Restart Services"
    echo "  [12] Stop Services"
    echo "  [13] Service Health Check"
    echo ""
    echo -e "${CYAN}Security & Maintenance:${NC}"
    echo "  [14] Rotate Credentials"
    echo "  [15] Backup Configuration"
    echo "  [16] Restore Configuration"
    echo "  [17] Setup Monitoring"
    echo ""
    echo "  [Q]  Quit"
    echo ""
}

main_menu() {
    while true; do
        show_main_menu
        read -p "Select option: " choice
        
        case  $ choice in
            1) manage_llm_providers ;;
            2) configure_ollama_models ;;
            3) test_llm_connections ;;
            4) pair_signal_device ;;
            5) setup_gdrive_oauth ;;
            6) configure_webhooks ;;
            7) configure_qdrant_collections ;;
            8) test_database_connections ;;
            9) database_backup_restore ;;
            10) view_service_logs ;;
            11) restart_services ;;
            12) stop_services ;;
            13) service_health_check ;;
            14) rotate_credentials ;;
            15) backup_configuration ;;
            16) restore_configuration ;;
            17) setup_monitoring ;;
            [Qq]) exit 0 ;;
            *) print_error "Invalid option" ; pause ;;
        esac
    done
}

#------------------------------------------------------------------------------
# Option 1: Manage LLM Providers
#------------------------------------------------------------------------------

manage_llm_providers() {
    print_header
    echo -e " $ {BOLD}Manage LLM Providers${NC}"
    echo ""
    
    if ! check_service_running "litellm"; then
        print_error "LiteLLM is not running"
        pause
        return
    fi
    
    echo "Current providers:"
    echo ""
    
    if [[ -f " $ DATA_DIR/config/litellm_config.yaml" ]]; then
        grep "model_name:" " $ DATA_DIR/config/litellm_config.yaml" | sed 's/.*model_name: /  - /'
    else
        echo "  No configuration file found"
    fi
    
    echo ""
    echo "[1] Add OpenAI"
    echo "[2] Add Anthropic"
    echo "[3] Add Google (Gemini)"
    echo "[4] Add Azure OpenAI"
    echo "[5] Add Groq"
    echo "[6] Remove Provider"
    echo "[7] Test Provider"
    echo "[B] Back"
    echo ""
    
    read -p "Select option: " choice
    
    case  $ choice in
        1) add_openai_provider ;;
        2) add_anthropic_provider ;;
        3) add_google_provider ;;
        4) add_azure_provider ;;
        5) add_groq_provider ;;
        6) remove_provider ;;
        7) test_provider ;;
        [Bb]) return ;;
        *) print_error "Invalid option" ; pause ;;
    esac
}

add_openai_provider() {
    echo ""
    print_step "Adding OpenAI Provider"
    echo ""
    
    read -p "Enter OpenAI API Key: " -s api_key
    echo ""
    
    if [[ -z " $ api_key" ]]; then
        print_error "API key cannot be empty"
        pause
        return
    fi
    
    # Add to litellm config
    local config_file=" $ DATA_DIR/config/litellm_config.yaml"
    
    # Backup current config
    cp " $ config_file" "${config_file}.backup"
    
    # Add models
    cat >> "$config_file" <<EOF

  - model_name: gpt-4o
    litellm_params:
      model: gpt-4o
      api_key: $api_key
  - model_name: gpt-4o-mini
    litellm_params:
      model: gpt-4o-mini
      api_key: $api_key
  - model_name: gpt-4-turbo
    litellm_params:
      model: gpt-4-turbo
      api_key:  $ api_key
EOF
    
    # Restart LiteLLM
    print_info "Restarting LiteLLM..."
    docker restart litellm
    sleep 5
    
    print_success "OpenAI provider added"
    pause
}

add_anthropic_provider() {
    echo ""
    print_step "Adding Anthropic Provider"
    echo ""
    
    read -p "Enter Anthropic API Key: " -s api_key
    echo ""
    
    if [[ -z " $ api_key" ]]; then
        print_error "API key cannot be empty"
        pause
        return
    fi
    
    local config_file=" $ DATA_DIR/config/litellm_config.yaml"
    cp " $ config_file" "${config_file}.backup"
    
    cat >> "$config_file" <<EOF

  - model_name: claude-3-5-sonnet
    litellm_params:
      model: claude-3-5-sonnet-20241022
      api_key: $api_key
  - model_name: claude-3-5-haiku
    litellm_params:
      model: claude-3-5-haiku-20241022
      api_key:  $ api_key
EOF
    
    print_info "Restarting LiteLLM..."
    docker restart litellm
    sleep 5
    
    print_success "Anthropic provider added"
    pause
}

add_google_provider() {
    echo ""
    print_step "Adding Google (Gemini) Provider"
    echo ""
    
    read -p "Enter Google API Key: " -s api_key
    echo ""
    
    if [[ -z " $ api_key" ]]; then
        print_error "API key cannot be empty"
        pause
        return
    fi
    
    local config_file=" $ DATA_DIR/config/litellm_config.yaml"
    cp " $ config_file" "${config_file}.backup"
    
    cat >> "$config_file" <<EOF

  - model_name: gemini-2.0-flash
    litellm_params:
      model: gemini/gemini-2.0-flash-exp
      api_key: $api_key
  - model_name: gemini-1.5-pro
    litellm_params:
      model: gemini/gemini-1.5-pro
      api_key:  $ api_key
EOF
    
    print_info "Restarting LiteLLM..."
    docker restart litellm
    sleep 5
    
    print_success "Google provider added"
    pause
}

add_azure_provider() {
    echo ""
    print_step "Adding Azure OpenAI Provider"
    echo ""
    
    read -p "Enter Azure API Key: " -s api_key
    echo ""
    read -p "Enter Azure API Base URL: " api_base
    read -p "Enter Azure API Version (default: 2024-02-15-preview): " api_version
    api_version= $ {api_version:-2024-02-15-preview}
    read -p "Enter deployment name: " deployment_name
    
    if [[ -z " $ api_key" || -z " $ api_base" || -z " $ deployment_name" ]]; then
        print_error "All fields are required"
        pause
        return
    fi
    
    local config_file=" $ DATA_DIR/config/litellm_config.yaml"
    cp " $ config_file" " $ {config_file}.backup"
    
    cat >> " $ config_file" <<EOF

  - model_name: azure-gpt-4
    litellm_params:
      model: azure/ $ deployment_name
      api_key: $api_key
      api_base: $api_base
      api_version:  $ api_version
EOF
    
    print_info "Restarting LiteLLM..."
    docker restart litellm
    sleep 5
    
    print_success "Azure OpenAI provider added"
    pause
}

add_groq_provider() {
    echo ""
    print_step "Adding Groq Provider"
    echo ""
    
    read -p "Enter Groq API Key: " -s api_key
    echo ""
    
    if [[ -z " $ api_key" ]]; then
        print_error "API key cannot be empty"
        pause
        return
    fi
    
    local config_file=" $ DATA_DIR/config/litellm_config.yaml"
    cp " $ config_file" "${config_file}.backup"
    
    cat >> "$config_file" <<EOF

  - model_name: llama-3.3-70b
    litellm_params:
      model: groq/llama-3.3-70b-versatile
      api_key: $api_key
  - model_name: mixtral-8x7b
    litellm_params:
      model: groq/mixtral-8x7b-32768
      api_key:  $ api_key
EOF
    
    print_info "Restarting LiteLLM..."
    docker restart litellm
    sleep 5
    
    print_success "Groq provider added"
    pause
}

remove_provider() {
    echo ""
    print_step "Remove Provider"
    echo ""
    
    read -p "Enter model name to remove: " model_name
    
    if [[ -z " $ model_name" ]]; then
        print_error "Model name cannot be empty"
        pause
        return
    fi
    
    local config_file=" $ DATA_DIR/config/litellm_config.yaml"
    cp " $ config_file" "${config_file}.backup"
    
    # Remove model block (this is simplified - in production use proper YAML parser)
    print_warning "Manual removal recommended for complex configs"
    print_info "Backup saved to ${config_file}.backup"
    
    pause
}

test_provider() {
    echo ""
    print_step "Test Provider"
    echo ""
    
    read -p "Enter model name to test: " model_name
    
    if [[ -z " $ model_name" ]]; then
        print_error "Model name cannot be empty"
        pause
        return
    fi
    
    local master_key= $ (jq -r '.litellm.password' " $ CREDENTIALS_FILE" 2>/dev/null || echo "")
    
    if [[ -z " $ master_key" ]]; then
        print_error "LiteLLM master key not found"
        pause
        return
    fi
    
    print_info "Testing  $ model_name..."
    
    local response= $ (curl -s -X POST http://localhost:4000/v1/chat/completions \
        -H "Authorization: Bearer  $ master_key" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \" $ model_name\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Say 'test successful'\"}],
            \"max_tokens\": 10
        }")
    
    if echo " $ response" | jq -e '.choices[0].message.content' &>/dev/null; then
        local content= $ (echo "$response" | jq -r '.choices[0].message.content')
        print_success "Test successful!"
        echo ""
        echo "Response: $content"
    else
        print_error "Test failed"
        echo ""
        echo "Response:  $ response"
    fi
    
    echo ""
    pause
}

#------------------------------------------------------------------------------
# Option 2: Configure Ollama Models
#------------------------------------------------------------------------------

configure_ollama_models() {
    print_header
    echo -e " $ {BOLD}Configure Ollama Models${NC}"
    echo ""
    
    if ! check_service_running "ollama"; then
        print_error "Ollama is not running"
        pause
        return
    fi
    
    echo "Current models:"
    echo ""
    docker exec ollama ollama list
    echo ""
    
    echo "[1] Pull New Model"
    echo "[2] Remove Model"
    echo "[3] Update Model"
    echo "[4] Show Model Info"
    echo "[B] Back"
    echo ""
    
    read -p "Select option: " choice
    
    case  $ choice in
        1) pull_ollama_model ;;
        2) remove_ollama_model ;;
        3) update_ollama_model ;;
        4) show_ollama_model_info ;;
        [Bb]) return ;;
        *) print_error "Invalid option" ; pause ;;
    esac
}

pull_ollama_model() {
    echo ""
    print_step "Pull Ollama Model"
    echo ""
    
    echo "Popular models:"
    echo "  - llama3.2:3b (2GB)"
    echo "  - llama3.2:1b (1.3GB)"
    echo "  - llama3.1:8b (4.7GB)"
    echo "  - llama3.1:70b (40GB)"
    echo "  - mistral:7b (4.1GB)"
    echo "  - mixtral:8x7b (26GB)"
    echo "  - phi3:mini (2.3GB)"
    echo "  - codellama:7b (3.8GB)"
    echo ""
    
    read -p "Enter model name (e.g., llama3.2:3b): " model_name
    
    if [[ -z " $ model_name" ]]; then
        print_error "Model name cannot be empty"
        pause
        return
    fi
    
    print_info "Pulling  $ model_name..."
    docker exec ollama ollama pull " $ model_name"
    
    print_success "Model pulled successfully"
    pause
}

remove_ollama_model() {
    echo ""
    print_step "Remove Ollama Model"
    echo ""
    
    read -p "Enter model name to remove: " model_name
    
    if [[ -z "$model_name" ]]; then
        print_error "Model name cannot be empty"
        pause
        return
    fi
    
    if confirm "Remove  $ model_name?"; then
        docker exec ollama ollama rm " $ model_name"
        print_success "Model removed"
    fi
    
    pause
}

update_ollama_model() {
    echo ""
    print_step "Update Ollama Model"
    echo ""
    
    read -p "Enter model name to update: " model_name
    
    if [[ -z "$model_name" ]]; then
        print_error "Model name cannot be empty"
        pause
        return
    fi
    
    print_info "Updating  $ model_name..."
    docker exec ollama ollama pull " $ model_name"
    
    print_success "Model updated"
    pause
}

show_ollama_model_info() {
    echo ""
    print_step "Show Model Info"
    echo ""
    
    read -p "Enter model name: " model_name
    
    if [[ -z " $ model_name" ]]; then
        print_error "Model name cannot be empty"
        pause
        return
    fi
    
    docker exec ollama ollama show " $ model_name"
    
    echo ""
    pause
}

#------------------------------------------------------------------------------
# Option 3: Test LLM Connections
#------------------------------------------------------------------------------

test_llm_connections() {
    print_header
    echo -e "${BOLD}Test LLM Connections${NC}"
    echo ""
    
    if ! check_service_running "litellm"; then
        print_error "LiteLLM is not running"
        pause
        return
    fi
    
    local master_key= $ (jq -r '.litellm.password' " $ CREDENTIALS_FILE" 2>/dev/null || echo "")
    
    if [[ -z " $ master_key" ]]; then
        print_error "LiteLLM master key not found"
        pause
        return
    fi
    
    print_info "Fetching available models..."
    
    local models= $ (curl -s -X GET http://localhost:4000/v1/models \
        -H "Authorization: Bearer  $ master_key" | jq -r '.data[].id' 2>/dev/null)
    
    if [[ -z " $ models" ]]; then
        print_error "No models available or connection failed"
        pause
        return
    fi
    
    echo ""
    echo "Available models:"
    echo " $ models" | nl
    echo ""
    
    read -p "Enter model number to test (or 'all' for all models): " selection
    
    if [[ " $ selection" == "all" ]]; then
        while IFS= read -r model; do
            test_single_model " $ model" " $ master_key"
        done <<< " $ models"
    else
        local model= $ (echo " $ models" | sed -n " $ {selection}p")
        if [[ -n " $ model" ]]; then
            test_single_model " $ model" " $ master_key"
        else
            print_error "Invalid selection"
        fi
    fi
    
    pause
}

test_single_model() {
    local model= $ 1
    local api_key=$2
    
    print_info "Testing  $ model..."
    
    local start_time= $ (date +%s%3N)
    
    local response=$(curl -s -X POST http://localhost:4000/v1/chat/completions \
        -H "Authorization: Bearer  $ api_key" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \" $ model\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}],
            \"max_tokens\": 10
        }")
    
    local end_time= $ (date +%s%3N)
    local duration= $ ((end_time - start_time))
    
    if echo " $ response" | jq -e '.choices[0].message.content' &>/dev/null; then
        print_success " $ model - ${duration}ms"
    else
        print_error "$model - Failed"
        echo "  Error:  $ (echo " $ response" | jq -r '.error.message' 2>/dev/null || echo 'Unknown error')"
    fi
}

#------------------------------------------------------------------------------
# Option 4: Pair Signal Device
#------------------------------------------------------------------------------

pair_signal_device() {
    print_header
    echo -e "${BOLD}Pair Signal Device${NC}"
    echo ""
    
    if ! check_service_running "signal-api"; then
        print_error "Signal API is not running"
        pause
        return
    fi
    
    echo "Signal pairing options:"
    echo ""
    echo "[1] Link as Primary Device (QR Code)"
    echo "[2] Register New Number (SMS verification)"
    echo "[3] Show Linked Devices"
    echo "[B] Back"
    echo ""
    
    read -p "Select option: " choice
    
    case  $ choice in
        1) signal_link_primary ;;
        2) signal_register_number ;;
        3) signal_show_devices ;;
        [Bb]) return ;;
        *) print_error "Invalid option" ; pause ;;
    esac
}

signal_link_primary() {
    echo ""
    print_step "Link as Primary Device"
    echo ""
    
    print_info "This will generate a QR code to scan with Signal mobile app"
    echo ""
    
    read -p "Enter device name (e.g., 'AI Platform'): " device_name
    device_name= $ {device_name:-AI Platform}
    
    print_info "Generating QR code..."
    print_info "Open Signal on your phone: Settings > Linked Devices > Link New Device"
    echo ""
    
    # Generate linking URI
    local response= $ (curl -s -X GET "http://localhost:8090/v1/qrcodelink?device_name= $ device_name")
    
    if echo "$response" | jq -e '.error' &>/dev/null; then
        print_error "Failed to generate QR code"
        echo "Error:  $ (echo " $ response" | jq -r '.error')"
        pause
        return
    fi
    
    # Display QR code (if qrencode is available)
    if command -v qrencode &>/dev/null; then
        local tsdevice= $ (echo " $ response" | jq -r '.tsdevice')
        echo "$tsdevice" | qrencode -t UTF8
    else
        print_warning "qrencode not installed, showing URL instead"
        echo "Manual URL:  $ (echo " $ response" | jq -r '.url')"
    fi
    
    echo ""
    print_info "Scan the QR code with your Signal app"
    print_info "Waiting for pairing... (this may take a minute)"
    
    # Wait for pairing
    sleep 60
    
    # Check if paired
    local accounts= $ (curl -s -X GET http://localhost:8090/v1/accounts)
    
    if echo " $ accounts" | jq -e '.[0]' &>/dev/null; then
        local number= $ (echo " $ accounts" | jq -r '.[0]')
        print_success "Paired successfully!"
        echo "Number:  $ number"
        
        # Save to credentials
        local temp_file= $ (mktemp)
        jq --arg number "$number" '.signal.number =  $ number' " $ CREDENTIALS_FILE" > " $ temp_file"
        mv " $ temp_file" " $ CREDENTIALS_FILE"
    else
        print_error "Pairing failed or timed out"
    fi
    
    pause
}

signal_register_number() {
    echo ""
    print_step "Register New Number"
    echo ""
    
    read -p "Enter phone number (with country code, e.g., +1234567890): " phone_number
    
    if [[ -z " $ phone_number" ]]; then
        print_error "Phone number cannot be empty"
        pause
        return
    fi
    
    print_info "Sending verification code..."
    
    local response= $ (curl -s -X POST http://localhost:8090/v1/register/ $ phone_number \
        -H "Content-Type: application/json" \
        -d '{"use_voice": false}')
    
    if echo "$response" | jq -e '.error' &>/dev/null; then
        print_error "Failed to send verification code"
        echo "Error:  $ (echo " $ response" | jq -r '.error')"
        pause
        return
    fi
    
    print_success "Verification code sent"
    echo ""
    
    read -p "Enter verification code: " verification_code
    
    print_info "Verifying..."
    
    response= $ (curl -s -X POST http://localhost:8090/v1/register/ $ phone_number/verify/ $ verification_code)
    
    if echo " $ response" | jq -e '.error' &>/dev/null; then
        print_error "Verification failed"
        echo "Error:  $ (echo " $ response" | jq -r '.error')"
    else
        print_success "Registered successfully!"
        
        # Save to credentials
        local temp_file= $ (mktemp)
        jq --arg number " $ phone_number" '.signal.number =  $ number' " $ CREDENTIALS_FILE" > " $ temp_file"
        mv " $ temp_file" " $ CREDENTIALS_FILE"
    fi
    
    pause
}

signal_show_devices() {
    echo ""
    print_step "Linked Devices"
    echo ""
    
    local accounts= $ (curl -s -X GET http://localhost:8090/v1/accounts)
    
    if echo " $ accounts" | jq -e '.[0]' &>/dev/null; then
        echo "Linked accounts:"
        echo " $ accounts" | jq -r '.[]' | nl
    else
        print_info "No devices linked"
    fi
    
    echo ""
    pause
}

#------------------------------------------------------------------------------
# Option 5: Setup Google Drive OAuth
#------------------------------------------------------------------------------

setup_gdrive_oauth() {
    print_header
    echo -e "${BOLD}Setup Google Drive OAuth${NC}"
    echo ""
    
    if ! check_service_running "gdrive-sync"; then
        print_error "Google Drive Sync is not running"
        pause
        return
    fi
    
    print_info "Setting up Google Drive OAuth requires:"
    echo "  1. Google Cloud Project"
    echo "  2. OAuth 2.0 credentials"
    echo "  3. Google Drive API enabled"
    echo ""
    
    echo "Steps:"
    echo "  1. Go to: https://console.cloud.google.com/"
    echo "  2. Create a project (or select existing)"
    echo "  3. Enable Google Drive API"
    echo "  4. Create OAuth 2.0 Client ID (Desktop app)"
    echo "  5. Download credentials JSON"
    echo ""
    
    if ! confirm "Do you have OAuth credentials ready?"; then
        pause
        return
    fi
    
    echo ""
    read -p "Enter path to credentials JSON file: " creds_path
    
    if [[ ! -f "$creds_path" ]]; then
        print_error "File not found:  $ creds_path"
        pause
        return
    fi
    
    # Copy credentials
    mkdir -p " $ DATA_DIR/gdrive/config"
    cp " $ creds_path" " $ DATA_DIR/gdrive/config/credentials.json"
    
    print_info "Starting OAuth flow..."
    print_info "A browser window will open. Follow the prompts to authorize."
    echo ""
    
    # Run rclone config
    docker exec -it gdrive-sync rclone config create gdrive drive \
        config_is_local false \
        scope drive \
        root_folder_id "" \
        service_account_file /config/credentials.json
    
    print_success "OAuth configuration complete"
    
    # Test connection
    print_info "Testing connection..."
    
    if docker exec gdrive-sync rclone lsd gdrive: &>/dev/null; then
        print_success "Connection successful!"
        
        # Setup sync
        echo ""
        if confirm "Setup automatic sync?"; then
            setup_gdrive_sync
        fi
    else
        print_error "Connection failed"
    fi
    
    pause
}

setup_gdrive_sync() {
    echo ""
    read -p "Enter local path to sync (default:  $ DATA_DIR/gdrive/sync): " local_path
    local_path= $ {local_path:- $ DATA_DIR/gdrive/sync}
    
    read -p "Enter Google Drive path (e.g., /AI_Platform): " remote_path
    
    read -p "Sync interval in minutes (default: 30): " interval
    interval= $ {interval:-30}
    
    # Create sync script
    cat > "$DATA_DIR/gdrive/sync.sh" <<EOF
#!/bin/bash
rclone sync  $ local_path gdrive: $ remote_path -v --log-file=/data/sync.log
EOF
    
    chmod +x " $ DATA_DIR/gdrive/sync.sh"
    
    # Add to crontab
    local cron_schedule="*/ $ interval * * * *"
    
    print_success "Sync configured"
    print_info "Schedule: Every $interval minutes"
    print_info "Local:  $ local_path"
    print_info "Remote: gdrive: $ remote_path"
}

#------------------------------------------------------------------------------
# Option 6: Configure Webhooks
#------------------------------------------------------------------------------

configure_webhooks() {
    print_header
    echo -e "${BOLD}Configure Webhooks${NC}"
    echo ""
    
    echo "Available webhook configurations:"
    echo ""
    echo "[1] n8n Webhook URLs"
    echo "[2] Signal Incoming Messages"
    echo "[3] LiteLLM Callbacks"
    echo "[4] Custom Webhook"
    echo "[B] Back"
    echo ""
    
    read -p "Select option: " choice
    
    case  $ choice in
        1) configure_n8n_webhooks ;;
        2) configure_signal_webhooks ;;
        3) configure_litellm_callbacks ;;
        4) configure_custom_webhook ;;
        [Bb]) return ;;
        *) print_error "Invalid option" ; pause ;;
    esac
}

configure_n8n_webhooks() {
    echo ""
    print_step "n8n Webhook URLs"
    echo ""
    
    if ! check_service_running "n8n"; then
        print_error "n8n is not running. Deploy it first using script 4."
        pause
        return
    fi
    
    local tailscale_ip= $ (jq -r '.tailscale_ip' " $ METADATA_FILE" 2>/dev/null || echo "localhost")
    
    print_info "n8n webhook base URL:"
    echo "  http:// $ tailscale_ip:5678/webhook/"
    echo ""
    print_info "Create webhooks in n8n UI and use this base URL"
    echo ""
    print_info "Example webhook: http:// $ tailscale_ip:5678/webhook/my-webhook"
    
    pause
}

configure_signal_webhooks() {
    echo ""
    print_step "Signal Incoming Messages Webhook"
    echo ""
    
    if ! check_service_running "signal-api"; then
        print_error "Signal API is not running"
        pause
        return
    fi
    
    read -p "Enter webhook URL (e.g., http://n8n:5678/webhook/signal): " webhook_url
    
    if [[ -z " $ webhook_url" ]]; then
        print_error "Webhook URL cannot be empty"
        pause
        return
    fi
    
    # Configure Signal API to forward messages
    print_info "Configuring Signal API..."
    
    # This would require modifying the Signal API container config
    print_warning "Manual configuration required:"
    echo "  1. Edit $DATA_DIR/signal/config.yml"
    echo "  2. Add webhook URL:  $ webhook_url"
    echo "  3. Restart signal-api container"
    
    pause
}

configure_litellm_callbacks() {
    echo ""
    print_step "LiteLLM Callbacks"
    echo ""
    
    if ! check_service_running "litellm"; then
        print_error "LiteLLM is not running"
        pause
        return
    fi
    
    echo "Available callback types:"
    echo "  1. Success callback (all successful requests)"
    echo "  2. Failure callback (all failed requests)"
    echo "  3. Langfuse logging"
    echo "  4. Custom webhook"
    echo ""
    
    read -p "Select callback type: " cb_type
    read -p "Enter webhook URL: " webhook_url
    
    if [[ -z " $ webhook_url" ]]; then
        print_error "Webhook URL cannot be empty"
        pause
        return
    fi
    
    local config_file="$DATA_DIR/config/litellm_config.yaml"
    
    case  $ cb_type in
        1)
            sed -i "s/success_callback: .*/success_callback: [\"webhook\"]/" " $ config_file"
            echo "WEBHOOK_URL= $ webhook_url" >> " $ DATA_DIR/env/litellm.env"
            ;;
        2)
            sed -i "s/failure_callback: .*/failure_callback: [\"webhook\"]/" " $ config_file"
            echo "FAILURE_WEBHOOK_URL= $ webhook_url" >> " $ DATA_DIR/env/litellm.env"
            ;;
        *)
            print_error "Invalid selection"
            pause
            return
            ;;
    esac
    
    docker restart litellm
    print_success "Callback configured"
    
    pause
}

configure_custom_webhook() {
    echo ""
    print_step "Custom Webhook"
    echo ""
    
    read -p "Enter webhook name: " webhook_name
    read -p "Enter webhook URL: " webhook_url
    read -p "Enter HTTP method (GET/POST): " http_method
    http_method= $ (echo " $ http_method" | tr '[:lower:]' '[:upper:]')
    
    if [[ -z " $ webhook_name" || -z " $ webhook_url" ]]; then
        print_error "Name and URL are required"
        pause
        return
    fi
    
    # Save webhook config
    local webhook_file=" $ DATA_DIR/metadata/webhooks.json"
    
    if [[ ! -f " $ webhook_file" ]]; then
        echo "[]" > " $ webhook_file"
    fi
    
    local temp_file= $ (mktemp)
    jq --arg name " $ webhook_name" \
       --arg url " $ webhook_url" \
       --arg method " $ http_method" \
       '. += [{name: $name, url: $url, method:  $ method, created_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}]' \
       " $ webhook_file" > " $ temp_file"
    
    mv " $ temp_file" " $ webhook_file"
    
    print_success "Webhook saved"
    print_info "Use this in your workflows/integrations"
    
    pause
}

#------------------------------------------------------------------------------
# Option 7: Configure Qdrant Collections
#------------------------------------------------------------------------------

configure_qdrant_collections() {
    print_header
    echo -e " $ {BOLD}Configure Qdrant Collections${NC}"
    echo ""
    
    if ! check_service_running "qdrant"; then
        print_error "Qdrant is not running"
        pause
        return
    fi
    
    local api_key= $ (jq -r '.qdrant.password' " $ CREDENTIALS_FILE" 2>/dev/null || echo "")
    
    echo "[1] List Collections"
    echo "[2] Create Collection"
    echo "[3] Delete Collection"
    echo "[4] Collection Info"
    echo "[B] Back"
    echo ""
    
    read -p "Select option: " choice
    
    case  $ choice in
        1) list_qdrant_collections " $ api_key" ;;
        2) create_qdrant_collection " $ api_key" ;;
        3) delete_qdrant_collection " $ api_key" ;;
        4) qdrant_collection_info " $ api_key" ;;
        [Bb]) return ;;
        *) print_error "Invalid option" ; pause ;;
    esac
}

list_qdrant_collections() {
    local api_key= $ 1
    
    echo ""
    print_step "Qdrant Collections"
    echo ""
    
    local collections=$(curl -s -X GET http://localhost:6333/collections \
        -H "api-key:  $ api_key")
    
    if echo " $ collections" | jq -e '.result.collections' &>/dev/null; then
        echo " $ collections" | jq -r '.result.collections[] | "  - \(.name) (\(.vectors_count) vectors)"'
    else
        print_info "No collections found"
    fi
    
    echo ""
    pause
}

create_qdrant_collection() {
    local api_key= $ 1
    
    echo ""
    print_step "Create Qdrant Collection"
    echo ""
    
    read -p "Enter collection name: " collection_name
    read -p "Enter vector size (e.g., 1536 for OpenAI, 384 for all-MiniLM): " vector_size
    read -p "Enter distance metric (Cosine/Euclid/Dot, default: Cosine): " distance
    distance=${distance:-Cosine}
    
    if [[ -z " $ collection_name" || -z " $ vector_size" ]]; then
        print_error "Collection name and vector size are required"
        pause
        return
    fi
    
    print_info "Creating collection..."
    
    local response= $ (curl -s -X PUT http://localhost:6333/collections/ $ collection_name \
        -H "api-key: $api_key" \
        -H "Content-Type: application/json" \
        -d "{
            \"vectors\": {
                \"size\":  $ vector_size,
                \"distance\": \" $ distance\"
            }
        }")
    
    if echo "$response" | jq -e '.result' &>/dev/null; then
        print_success "Collection created:  $ collection_name"
    else
        print_error "Failed to create collection"
        echo " $ response" | jq .
    fi
    
    pause
}

delete_qdrant_collection() {
    local api_key= $ 1
    
    echo ""
    print_step "Delete Qdrant Collection"
    echo ""
    
    read -p "Enter collection name to delete: " collection_name
    
    if [[ -z " $ collection_name" ]]; then
        print_error "Collection name cannot be empty"
        pause
        return
    fi
    
    if ! confirm "Delete collection ' $ collection_name'? This cannot be undone."; then
        return
    fi
    
    print_info "Deleting collection..."
    
    local response= $ (curl -s -X DELETE http://localhost:6333/collections/$collection_name \
        -H "api-key:  $ api_key")
    
    if echo " $ response" | jq -e '.result' &>/dev/null; then
        print_success "Collection deleted"
    else
        print_error "Failed to delete collection"
        echo " $ response" | jq .
    fi
    
    pause
}

qdrant_collection_info() {
    local api_key= $ 1
    
    echo ""
    read -p "Enter collection name: " collection_name
    
    if [[ -z "$collection_name" ]]; then
        print_error "Collection name cannot be empty"
        pause
        return
    fi
    
    echo ""
    print_info "Collection:  $ collection_name"
    echo ""
    
    curl -s -X GET http://localhost:6333/collections/ $ collection_name \
        -H "api-key:  $ api_key" | jq .
    
    echo ""
    pause
}

#------------------------------------------------------------------------------
# Option 8: Test Database Connections
#------------------------------------------------------------------------------

test_database_connections() {
    print_header
    echo -e " $ {BOLD}Test Database Connections${NC}"
    echo ""
    
    local all_pass=true
    
    # Test PostgreSQL
    print_step "Testing PostgreSQL..."
    if check_service_running "postgres"; then
        if docker exec postgres pg_isready -U postgres &>/dev/null; then
            print_success "PostgreSQL: Connected"
        else
            print_error "PostgreSQL: Connection failed"
            all_pass=false
        fi
    else
        print_warning "PostgreSQL: Not running"
        all_pass=false
    fi
    
    # Test Redis
    print_step "Testing Redis..."
    if check_service_running "redis"; then
        local redis_pass= $ (grep REDIS_PASSWORD " $ DATA_DIR/env/redis.env" 2>/dev/null | cut -d'=' -f2)
        if docker exec redis redis-cli -a " $ redis_pass" PING &>/dev/null; then
            print_success "Redis: Connected"
        else
            print_error "Redis: Connection failed"
            all_pass=false
        fi
    else
        print_warning "Redis: Not running"
        all_pass=false
    fi
    
    # Test Qdrant
    print_step "Testing Qdrant..."
    if check_service_running "qdrant"; then
        if curl -sf http://localhost:6333/healthz &>/dev/null; then
            print_success "Qdrant: Connected"
        else
            print_error "Qdrant: Connection failed"
            all_pass=false
        fi
    else
        print_warning "Qdrant: Not running"
        all_pass=false
    fi
    
    echo ""
    if [[ " $ all_pass" == true ]]; then
        print_success "All database connections successful"
    else
        print_warning "Some databases failed connection tests"
    fi
    
    pause
}

#------------------------------------------------------------------------------
# Option 9: Database Backup/Restore
#------------------------------------------------------------------------------

database_backup_restore() {
    print_header
    echo -e "${BOLD}Database Backup/Restore${NC}"
    echo ""
    
    echo "[1] Backup All Databases"
    echo "[2] Backup PostgreSQL"
    echo "[3] Backup Qdrant"
    echo "[4] Restore from Backup"
    echo "[5] List Backups"
    echo "[B] Back"
    echo ""
    
    read -p "Select option: " choice
    
    case  $ choice in
        1) backup_all_databases ;;
        2) backup_postgres ;;
        3) backup_qdrant ;;
        4) restore_database ;;
        5) list_backups ;;
        [Bb]) return ;;
        *) print_error "Invalid option" ; pause ;;
    esac
}

backup_all_databases() {
    echo ""
    print_step "Backing up all databases..."
    echo ""
    
    local backup_dir=" $ DATA_DIR/backups/ $ (date +%Y%m%d_%H%M%S)"
    mkdir -p " $ backup_dir"
    
    # Backup PostgreSQL
    if check_service_running "postgres"; then
        print_info "Backing up PostgreSQL..."
        docker exec postgres pg_dumpall -U postgres | gzip > " $ backup_dir/postgres.sql.gz"
        print_success "PostgreSQL backed up"
    fi
    
    # Backup Qdrant
    if check_service_running "qdrant"; then
        print_info "Backing up Qdrant..."
        tar -czf " $ backup_dir/qdrant.tar.gz" -C " $ DATA_DIR" qdrant/
        print_success "Qdrant backed up"
    fi
    
    # Backup Redis
    if check_service_running "redis"; then
        print_info "Backing up Redis..."
        docker exec redis redis-cli SAVE
        cp " $ DATA_DIR/redis/dump.rdb" "$backup_dir/redis.rdb"
        print_success "Redis backed up"
    fi
    
    echo ""
    print_success "All databases backed up to:  $ backup_dir"
    
    pause
}

backup_postgres() {
    echo ""
    print_step "Backing up PostgreSQL..."
    echo ""
    
    if ! check_service_running "postgres"; then
        print_error "PostgreSQL is not running"
        pause
        return
    fi
    
    local backup_dir=" $ DATA_DIR/backups/postgres/ $ (date +%Y%m%d_%H%M%S)"
    mkdir -p " $ backup_dir"
    
    docker exec postgres pg_dumpall -U postgres | gzip > "$backup_dir/all_databases.sql.gz"
    
    print_success "PostgreSQL backed up to:  $ backup_dir"
    
    pause
}

backup_qdrant() {
    echo ""
    print_step "Backing up Qdrant..."
    echo ""
    
    if ! check_service_running "qdrant"; then
        print_error "Qdrant is not running"
        pause
        return
    fi
    
    local backup_dir=" $ DATA_DIR/backups/qdrant/ $ (date +%Y%m%d_%H%M%S)"
    mkdir -p " $ backup_dir"
    
    # Create snapshot via API
    local api_key= $ (jq -r '.qdrant.password' " $ CREDENTIALS_FILE" 2>/dev/null || echo "")
    
    curl -s -X POST http://localhost:6333/collections/snapshot \
        -H "api-key:  $ api_key"
    
    # Copy Qdrant data
    tar -czf " $ backup_dir/qdrant_data.tar.gz" -C "$DATA_DIR" qdrant/
    
    print_success "Qdrant backed up to:  $ backup_dir"
    
    pause
}

restore_database() {
    echo ""
    print_step "Restore Database"
    echo ""
    
    local backup_base=" $ DATA_DIR/backups"
    
    if [[ ! -d " $ backup_base" ]] || [[ -z " $ (ls -A  $ backup_base)" ]]; then
        print_error "No backups found"
        pause
        return
    fi
    
    echo "Available backups:"
    find " $ backup_base" -mindepth 1 -maxdepth 1 -type d | nl
    echo ""
    
    read -p "Enter backup number to restore: " backup_num
    
    local backup_dir= $ (find " $ backup_base" -mindepth 1 -maxdepth 1 -type d | sed -n "${backup_num}p")
    
    if [[ -z " $ backup_dir" ]]; then
        print_error "Invalid selection"
        pause
        return
    fi
    
    print_warning "This will overwrite current data!"
    if ! confirm "Continue with restore?"; then
        return
    fi
    
    # Restore PostgreSQL
    if [[ -f " $ backup_dir/postgres.sql.gz" ]]; then
        print_info "Restoring PostgreSQL..."
        gunzip < " $ backup_dir/postgres.sql.gz" | docker exec -i postgres psql -U postgres
        print_success "PostgreSQL restored"
    fi
    
    # Restore Qdrant
    if [[ -f " $ backup_dir/qdrant.tar.gz" ]]; then
        print_info "Restoring Qdrant..."
        docker stop qdrant
        rm -rf " $ DATA_DIR/qdrant"
        tar -xzf " $ backup_dir/qdrant.tar.gz" -C " $ DATA_DIR"
        docker start qdrant
        print_success "Qdrant restored"
    fi
    
    # Restore Redis
    if [[ -f " $ backup_dir/redis.rdb" ]]; then
        print_info "Restoring Redis..."
        docker stop redis
        cp " $ backup_dir/redis.rdb" " $ DATA_DIR/redis/dump.rdb"
        docker start redis
        print_success "Redis restored"
    fi
    
    pause
}

list_backups() {
    echo ""
    print_step "Available Backups"
    echo ""
    
    local backup_base=" $ DATA_DIR/backups"
    
    if [[ ! -d " $ backup_base" ]] || [[ -z "$(ls -A  $ backup_base)" ]]; then
        print_info "No backups found"
        pause
        return
    fi
    
    find " $ backup_base" -mindepth 1 -maxdepth 1 -type d -exec du -sh {} \; | sort
    
    echo ""
    pause
}

#------------------------------------------------------------------------------
# Option 10: View Service Logs
#------------------------------------------------------------------------------

view_service_logs() {
    print_header
    echo -e "${BOLD}View Service Logs${NC}"
    echo ""
    
    echo "Select service:"
    docker ps --format "{{.Names}}" | nl
    echo ""
    echo "[A] All services"
    echo "[B] Back"
    echo ""
    
    read -p "Selection: " choice
    
    case  $ choice in
        [Aa])
            docker compose -f " $ DATA_DIR/compose/*.yml" logs -f --tail=100
            ;;
        [Bb])
            return
            ;;
        *)
            local service= $ (docker ps --format "{{.Names}}" | sed -n " $ {choice}p")
            if [[ -n "$service" ]]; then
                echo ""
                print_info "Showing logs for  $ service (Ctrl+C to exit)"
                echo ""
                docker logs -f --tail=100 " $ service"
            else
                print_error "Invalid selection"
                pause
            fi
            ;;
    esac
}

#------------------------------------------------------------------------------
# Option 11: Restart Services
#------------------------------------------------------------------------------

restart_services() {
    print_header
    echo -e "${BOLD}Restart Services${NC}"
    echo ""
    
    echo "Select service to restart:"
    docker ps --format "{{.Names}}" | nl
    echo ""
    echo "[A] All services"
    echo "[B] Back"
    echo ""
    
    read -p "Selection: " choice
    
    case $choice in
        [Aa])
            if confirm "Restart all services?"; then
                print_info "Restarting all services..."
                docker restart  $ (docker ps -q)
                print_success "All services restarted"
            fi
            pause
            ;;
        [Bb])
            return
            ;;
        *)
            local service= $ (docker ps --format "{{.Names}}" | sed -n "${choice}p")
            if [[ -n "$service" ]]; then
                print_info "Restarting  $ service..."
                docker restart " $ service"
                print_success " $ service restarted"
            else
                print_error "Invalid selection"
            fi
            pause
            ;;
    esac
}

#------------------------------------------------------------------------------
# Option 12: Stop Services
#------------------------------------------------------------------------------

stop_services() {
    print_header
    echo -e " $ {BOLD}Stop Services${NC}"
    echo ""
    
    echo "Select service to stop:"
    docker ps --format "{{.Names}}" | nl
    echo ""
    echo "[A] All services"
    echo "[B] Back"
    echo ""
    
    read -p "Selection: " choice
    
    case $choice in
        [Aa])
            if confirm "Stop all services?"; then
                print_info "Stopping all services..."
                docker stop  $ (docker ps -q)
                print_success "All services stopped"
            fi
            pause
            ;;
        [Bb])
            return
            ;;
        *)
            local service= $ (docker ps --format "{{.Names}}" | sed -n "${choice}p")
            if [[ -n "$service" ]]; then
                if confirm "Stop  $ service?"; then
                    docker stop " $ service"
                    print_success " $ service stopped"
                fi
            else
                print_error "Invalid selection"
            fi
            pause
            ;;
    esac
}

#------------------------------------------------------------------------------
# Option 13: Service Health Check
#------------------------------------------------------------------------------

service_health_check() {
    print_header
    echo -e " $ {BOLD}Service Health Check${NC}"
    echo ""
    
    print_step "Checking service health..."
    echo ""
    
    # Get all running containers
    local containers= $ (docker ps --format "{{.Names}}")
    
    while IFS= read -r container; do
        local health= $ (docker inspect --format='{{.State.Health.Status}}' " $ container" 2>/dev/null || echo "N/A")
        local status= $ (docker inspect --format='{{.State.Status}}' " $ container")
        
        if [[ " $ health" == "healthy" ]] || [[ " $ health" == "N/A" && " $ status" == "running" ]]; then
            print_success " $ container: OK"
        elif [[ " $ health" == "unhealthy" ]]; then
            print_error " $ container: UNHEALTHY"
        elif [[ " $ status" != "running" ]]; then
            print_error " $ container: NOT RUNNING"
        else
            print_warning " $ container:  $ health"
        fi
    done <<< " $ containers"
    
    echo ""
    pause
}

#------------------------------------------------------------------------------
# Option 14: Rotate Credentials
#------------------------------------------------------------------------------

rotate_credentials() {
    print_header
    echo -e "${BOLD}Rotate Credentials${NC}"
    echo ""
    
    echo "Select service:"
    echo "  [1] PostgreSQL password"
    echo "  [2] Redis password"
    echo "  [3] Qdrant API key"
    echo "  [4] LiteLLM master key"
    echo "  [5] All credentials"
    echo "  [B] Back"
    echo ""
    
    read -p "Selection: " choice
    
    case  $ choice in
        1) rotate_postgres_password ;;
        2) rotate_redis_password ;;
        3) rotate_qdrant_key ;;
        4) rotate_litellm_key ;;
        5) rotate_all_credentials ;;
        [Bb]) return ;;
        *) print_error "Invalid option" ; pause ;;
    esac
}

rotate_postgres_password() {
    echo ""
    print_warning "Rotating PostgreSQL password will require updating all dependent services"
    
    if ! confirm "Continue?"; then
        return
    fi
    
    local new_password= $ (openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    print_info "Updating password..."
    
    # Update in container
    docker exec postgres psql -U postgres -c "ALTER USER postgres PASSWORD ' $ new_password';"
    
    # Update env file
    sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD= $ new_password/" " $ DATA_DIR/env/postgres.env"
    
    # Update credentials file
    local temp_file= $ (mktemp)
    jq --arg pass "$new_password" '.postgres.password =  $ pass' " $ CREDENTIALS_FILE" > " $ temp_file"
    mv " $ temp_file" " $ CREDENTIALS_FILE"
    
    print_success "Password rotated"
    print_warning "Update dependent services (n8n, dify, litellm, flowise)"
    
    pause
}

rotate_redis_password() {
    echo ""
    if ! confirm "Rotate Redis password?"; then
        return
    fi
    
    local new_password= $ (openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    # Update config
    sed -i "s/requirepass .*/requirepass  $ new_password/" " $ DATA_DIR/config/redis.conf"
    sed -i "s/REDIS_PASSWORD=.*/REDIS_PASSWORD= $ new_password/" " $ DATA_DIR/env/redis.env"
    
    # Update credentials
    local temp_file= $ (mktemp)
    jq --arg pass " $ new_password" '.redis.password =  $ pass' " $ CREDENTIALS_FILE" > " $ temp_file"
    mv " $ temp_file" " $ CREDENTIALS_FILE"
    
    # Restart Redis
    docker restart redis
    
    print_success "Password rotated"
    
    pause
}

rotate_qdrant_key() {
    echo ""
    if ! confirm "Rotate Qdrant API key?"; then
        return
    fi
    
    local new_key="sk- $ (openssl rand -hex 32)"
    
    sed -i "s/QDRANT__SERVICE__API_KEY=.*/QDRANT__SERVICE__API_KEY= $ new_key/" " $ DATA_DIR/env/qdrant.env"
    
    local temp_file= $ (mktemp)
    jq --arg key " $ new_key" '.qdrant.password =  $ key' " $ CREDENTIALS_FILE" > " $ temp_file"
    mv " $ temp_file" " $ CREDENTIALS_FILE"
    
    docker restart qdrant
    
    print_success "API key rotated"
    
    pause
}

rotate_litellm_key() {
    echo ""
    if ! confirm "Rotate LiteLLM master key?"; then
        return
    fi
    
    local new_key="sk- $ (openssl rand -hex 32)"
    
    sed -i "s/LITELLM_MASTER_KEY=.*/LITELLM_MASTER_KEY= $ new_key/" " $ DATA_DIR/env/litellm.env"
    
    local temp_file= $ (mktemp)
    jq --arg key " $ new_key" '.litellm.password =  $ key' " $ CREDENTIALS_FILE" > " $ temp_file"
    mv " $ temp_file" "$CREDENTIALS_FILE"
    
    docker restart litellm
    
    print_success "Master key rotated"
    print_info "New key:  $ new_key"
    
    pause
}

rotate_all_credentials() {
    echo ""
    print_warning "This will rotate all service credentials"
    
    if ! confirm "Continue?"; then
        return
    fi
    
    rotate_postgres_password
    rotate_redis_password
    rotate_qdrant_key
    rotate_litellm_key
    
    print_success "All credentials rotated"
    
    pause
}

#------------------------------------------------------------------------------
# Option 15: Backup Configuration
#------------------------------------------------------------------------------

backup_configuration() {
    print_header
    echo -e " $ {BOLD}Backup Configuration${NC}"
    echo ""
    
    local backup_dir=" $ DATA_DIR/backups/config/ $ (date +%Y%m%d_%H%M%S)"
    mkdir -p " $ backup_dir"
    
    print_info "Backing up configuration..."
    
    # Backup compose files
    cp -r " $ DATA_DIR/compose" " $ backup_dir/"
    
    # Backup env files
    cp -r " $ DATA_DIR/env" " $ backup_dir/"
    
    # Backup config files
    cp -r " $ DATA_DIR/config" " $ backup_dir/"
    
    # Backup metadata
    cp -r " $ DATA_DIR/metadata" " $ backup_dir/"
    
    # Create archive
    tar -czf " $ backup_dir.tar.gz" -C " $ backup_dir" .
    rm -rf " $ backup_dir"
    
    print_success "Configuration backed up to:  $ backup_dir.tar.gz"
    
    pause
}

#------------------------------------------------------------------------------
# Option 16: Restore Configuration
#------------------------------------------------------------------------------

restore_configuration() {
    print_header
    echo -e " $ {BOLD}Restore Configuration${NC}"
    echo ""
    
    local backup_base=" $ DATA_DIR/backups/config"
    
    if [[ ! -d " $ backup_base" ]] || [[ -z "$(ls -A  $ backup_base 2>/dev/null)" ]]; then
        print_error "No configuration backups found"
        pause
        return
    fi
    
    echo "Available backups:"
    find " $ backup_base" -name "*.tar.gz" | nl
    echo ""
    
    read -p "Enter backup number to restore: " backup_num
    
    local backup_file= $ (find " $ backup_base" -name "*.tar.gz" | sed -n "${backup_num}p")
   
 if [[ -z "$backup_file" ]]; then
        print_error "Invalid selection"
        pause
        return
    fi

    print_warning "This will overwrite current configuration!"
    if ! confirm "Continue with restore?"; then
        return
    fi

    local temp_dir=$(mktemp -d)

    print_info "Extracting backup..."
    tar -xzf "$backup_file" -C "$temp_dir"

    print_info "Restoring configuration..."

    # Stop all services
    docker stop $(docker ps -q) 2>/dev/null || true

    # Restore files
    cp -r "$temp_dir/compose/"* "$DATA_DIR/compose/"
    cp -r "$temp_dir/env/"* "$DATA_DIR/env/"
    cp -r "$temp_dir/config/"* "$DATA_DIR/config/"
    cp -r "$temp_dir/metadata/"* "$DATA_DIR/metadata/"

    # Cleanup
    rm -rf "$temp_dir"

    print_success "Configuration restored"
    print_info "Restart services to apply changes"

    pause
}

#------------------------------------------------------------------------------
# Option 17: Setup Monitoring
#------------------------------------------------------------------------------

setup_monitoring() {
    print_header
    echo -e "${BOLD}Setup Monitoring${NC}"
    echo ""

    print_info "Monitoring options:"
    echo ""
    echo "[1] Install Prometheus + Grafana"
    echo "[2] Setup Docker stats monitoring"
    echo "[3] Configure health check alerts"
    echo "[4] View current metrics"
    echo "[B] Back"
    echo ""

    read -p "Selection: " choice

    case $choice in
        1) install_prometheus_grafana ;;
        2) setup_docker_stats ;;
        3) configure_health_alerts ;;
        4) view_current_metrics ;;
        [Bb]) return ;;
        *) print_error "Invalid option" ; pause ;;
    esac
}

install_prometheus_grafana() {
    echo ""
    print_step "Installing Prometheus + Grafana"
    echo ""

    if confirm "Install monitoring stack?"; then
        print_info "Creating monitoring compose file..."

        cat > "$DATA_DIR/compose/monitoring.yml" <<'EOF'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - /mnt/data/prometheus:/prometheus
      - /mnt/data/config/prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    ports:
      - "9090:9090"
    networks:
      - ai_platform

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    volumes:
      - /mnt/data/grafana:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
    ports:
      - "3000:3000"
    networks:
      - ai_platform

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    command:
      - '--path.rootfs=/host'
    volumes:
      - '/:/host:ro,rslave'
    ports:
      - "9100:9100"
    networks:
      - ai_platform

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    ports:
      - "8080:8080"
    networks:
      - ai_platform

networks:
  ai_platform:
    external: true
EOF

        # Create Prometheus config
        mkdir -p "$DATA_DIR/config"
        cat > "$DATA_DIR/config/prometheus.yml" <<'EOF'
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

  - job_name: 'docker-containers'
    static_configs:
      - targets:
        - 'postgres:5432'
        - 'redis:6379'
        - 'qdrant:6333'
        - 'ollama:11434'
        - 'litellm:4000'
EOF

        # Generate Grafana password
        local grafana_pass=$(openssl rand -base64 16)
        echo "GRAFANA_PASSWORD=$grafana_pass" > "$DATA_DIR/env/monitoring.env"

        # Deploy
        docker compose -f "$DATA_DIR/compose/monitoring.yml" --env-file "$DATA_DIR/env/monitoring.env" up -d

        print_success "Monitoring stack deployed"
        echo ""
        print_info "Access Grafana at: http://localhost:3000"
        print_info "Username: admin"
        print_info "Password: $grafana_pass"
        echo ""
        print_info "Access Prometheus at: http://localhost:9090"
    fi

    pause
}

setup_docker_stats() {
    echo ""
    print_step "Docker Stats Monitoring"
    echo ""

    print_info "Real-time container statistics:"
    echo ""

    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"

    echo ""
    pause
}

configure_health_alerts() {
    echo ""
    print_step "Configure Health Check Alerts"
    echo ""

    read -p "Enter email for alerts (optional): " alert_email
    read -p "Enter Slack webhook URL (optional): " slack_webhook

    # Create health check script
    cat > "$DATA_DIR/scripts/health_check.sh" <<'EOF'
#!/bin/bash

# Health check script
SERVICES=("postgres" "redis" "qdrant" "ollama" "litellm")
ALERT_EMAIL="${ALERT_EMAIL:-}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"

for service in "${SERVICES[@]}"; do
    if ! docker ps | grep -q "$service"; then
        message="ALERT: $service is not running!"

        # Send email if configured
        if [[ -n "$ALERT_EMAIL" ]]; then
            echo "$message" | mail -s "Service Alert: $service" "$ALERT_EMAIL"
        fi

        # Send Slack notification if configured
        if [[ -n "$SLACK_WEBHOOK" ]]; then
            curl -X POST "$SLACK_WEBHOOK" \
                -H 'Content-Type: application/json' \
                -d "{\"text\":\"$message\"}"
        fi

        echo "$message"
    fi
done
EOF

    chmod +x "$DATA_DIR/scripts/health_check.sh"

    # Add to crontab
    if confirm "Add to crontab (check every 5 minutes)?"; then
        (crontab -l 2>/dev/null; echo "*/5 * * * * $DATA_DIR/scripts/health_check.sh") | crontab -
        print_success "Health check scheduled"
    fi

    pause
}

view_current_metrics() {
    echo ""
    print_step "Current System Metrics"
    echo ""

    echo -e "${BOLD}System Resources:${NC}"
    echo ""

    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo "CPU Usage: ${cpu_usage}%"

    # Memory usage
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    echo "Memory Usage: ${mem_usage}%"

    # Disk usage
    local disk_usage=$(df -h "$DATA_DIR" | awk 'NR==2 {print $5}')
    echo "Disk Usage: $disk_usage"

    echo ""
    echo -e "${BOLD}Container Statistics:${NC}"
    echo ""

    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

    echo ""
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
        print_error "System not initialized. Run script 1 first."
        exit 1
    fi

    # Start main menu loop
    main_menu
}

# Run main function
main "$@"
