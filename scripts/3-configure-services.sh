#!/bin/bash
# 3-configure-services.sh - Interactive service configuration manager

SCRIPT_DIR=" $ (cd " $ (dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_ROOT="/mnt/data"
METADATA_DIR=" $ DATA_ROOT/metadata"
COMPOSE_DIR=" $ DATA_ROOT/compose"
ENV_DIR=" $ DATA_ROOT/env"
CONFIG_DIR=" $ DATA_ROOT/config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Icons
ICON_CHECK="✅"
ICON_CROSS="❌"
ICON_WARN="⚠️"
ICON_INFO="ℹ️"
ICON_GEAR="⚙️"
ICON_KEY="🔑"
ICON_ROBOT="🤖"
ICON_DB="🗄️"
ICON_SIGNAL="📱"
ICON_DRIVE="📁"
ICON_RELOAD="🔄"

log_info() { echo -e "${GREEN}[INFO]${NC}  $ 1"; }
log_warn() { echo -e " $ {YELLOW}[WARN]${NC}  $ 1"; }
log_error() { echo -e " $ {RED}[ERROR]${NC}  $ 1"; }
log_step() { echo -e " $ {CYAN}[STEP]${NC}  $ 1"; }
log_success() { echo -e " $ {GREEN}${ICON_CHECK}${NC}  $ 1"; }

show_banner() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║  ⚙️  AIPlatformAutomation - Configuration Manager v76.5   ║
╚════════════════════════════════════════════════════════════╝

    Interactive service configuration and reconfiguration tool
    
EOF
}

check_prerequisites() {
    if [ " $ EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    if [ ! -f " $ METADATA_DIR/selected_services.json" ]; then
        log_error "Services not deployed. Run ./2-deploy-services.sh first"
        exit 1
    fi
    
    # Detect real user
    if [ -n " $ {SUDO_USER:-}" ]; then
        REAL_USER=" $ SUDO_USER"
    else
        REAL_USER=" $ USER"
    fi
    
    PUID= $ (id -u " $ REAL_USER")
    PGID= $ (id -g " $ REAL_USER")
}

load_current_config() {
    log_step "Loading current configuration..."
    
    SELECTED_SERVICES=( $ (jq -r '.applications[]' " $ METADATA_DIR/selected_services.json"))
    DOMAIN= $ (jq -r '.domain' " $ METADATA_DIR/network_config.json")
    VECTORDB_TYPE= $ (jq -r '.type' " $ METADATA_DIR/vectordb_config.json" 2>/dev/null || echo "none")
    
    # Load LiteLLM config
    if [ -f " $ CONFIG_DIR/litellm_config.yaml" ]; then
        LITELLM_CONFIG_EXISTS=true
    else
        LITELLM_CONFIG_EXISTS=false
    fi
    
    # Load provider info
    PROVIDERS=( $ (jq -r '.providers[]?.name // empty' "$METADATA_DIR/llm_providers.json" 2>/dev/null))
}

# =====================================================
# MAIN MENU
# =====================================================

show_main_menu() {
    while true; do
        clear
        cat << EOF
╔════════════════════════════════════════════════════════════╗
║           🔧 CONFIGURATION MANAGEMENT MENU                 ║
╚════════════════════════════════════════════════════════════╝

${CYAN}Current Configuration:${NC}
  Domain: ${GREEN} $ DOMAIN $ {NC}
  Vector DB: ${GREEN} $ VECTORDB_TYPE $ {NC}
  LLM Providers: ${GREEN}${#PROVIDERS[@]}${NC} configured
  Services: ${GREEN}${#SELECTED_SERVICES[@]}${NC} deployed

${CYAN}Configuration Options:${NC}

  ${YELLOW}1)${NC}  ${ICON_KEY}  Manage LLM Provider API Keys
  ${YELLOW}2)${NC}  ${ICON_ROBOT} Configure LiteLLM Routing
  ${YELLOW}3)${NC}  ${ICON_DB}  Configure Vector Database
  ${YELLOW}4)${NC}  ${ICON_SIGNAL} Configure Signal Integration
  ${YELLOW}5)${NC}  ${ICON_DRIVE} Configure Google Drive Sync
  ${YELLOW}6)${NC}  ⚡  Configure Webhooks (OpenClaw/AnythingLLM/Dify)
  ${YELLOW}7)${NC}  🌐  Configure Reverse Proxy
  ${YELLOW}8)${NC}  🔍  Test Service Connections
  ${YELLOW}9)${NC}  📊  View Current Configuration
  ${YELLOW}10)${NC} ${ICON_RELOAD} Hot-Reload Services
  ${YELLOW}11)${NC} 🔐  Rotate Credentials
  ${YELLOW}12)${NC} 💾  Backup Configuration
  ${YELLOW}0)${NC}  ❌  Exit

EOF
        read -p "Select option: " choice
        
        case $choice in
            1) manage_llm_providers ;;
            2) configure_litellm_routing ;;
            3) configure_vectordb ;;
            4) configure_signal ;;
            5) configure_gdrive ;;
            6) configure_webhooks ;;
            7) configure_reverse_proxy ;;
            8) test_service_connections ;;
            9) view_current_config ;;
            10) hot_reload_services ;;
            11) rotate_credentials ;;
            12) backup_configuration ;;
            0) 
                log_info "Exiting..."
                exit 0
                ;;
            *)
                log_warn "Invalid option"
                sleep 2
                ;;
        esac
    done
}

# =====================================================
# 1. MANAGE LLM PROVIDERS
# =====================================================

manage_llm_providers() {
    while true; do
        clear
        cat << EOF
╔════════════════════════════════════════════════════════════╗
║              ${ICON_ROBOT} LLM PROVIDER MANAGEMENT                    ║
╚════════════════════════════════════════════════════════════╝

${CYAN}Currently Configured Providers:${NC}
EOF

        if [ ${#PROVIDERS[@]} -eq 0 ]; then
            echo "  ${YELLOW}None (Local Ollama only)${NC}"
        else
            for i in "${!PROVIDERS[@]}"; do
                provider="${PROVIDERS[ $ i]}"
                # Check if API key exists
                api_key= $ (jq -r ".providers[] | select(.name==\" $ provider\") | .api_key // empty" " $ METADATA_DIR/llm_providers.json")
                if [ -n " $ api_key" ]; then
                    masked_key=" $ {api_key:0:8}...${api_key: -4}"
                    status="${GREEN}${ICON_CHECK} Active${NC}"
                else
                    masked_key="Not set"
                    status="${RED}${ICON_CROSS} Missing${NC}"
                fi
                echo "  $((i+1)). $provider: $masked_key $status"
            done
        fi

        cat << EOF

${CYAN}Options:${NC}
  ${YELLOW}1)${NC} Add New Provider
  ${YELLOW}2)${NC} Update Existing Provider API Key
  ${YELLOW}3)${NC} Remove Provider
  ${YELLOW}4)${NC} Test Provider Connection
  ${YELLOW}0)${NC} Back to Main Menu

EOF
        read -p "Select option: " choice
        
        case $choice in
            1) add_llm_provider ;;
            2) update_provider_key ;;
            3) remove_provider ;;
            4) test_provider_connection ;;
            0) return ;;
            *) log_warn "Invalid option"; sleep 1 ;;
        esac
    done
}

add_llm_provider() {
    clear
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║                  ADD LLM PROVIDER                          ║
╚════════════════════════════════════════════════════════════╝

${CYAN}Available Providers:${NC}
  ${YELLOW}1)${NC} OpenAI
  ${YELLOW}2)${NC} Anthropic (Claude)
  ${YELLOW}3)${NC} Google Gemini
  ${YELLOW}4)${NC} Groq
  ${YELLOW}5)${NC} Mistral AI
  ${YELLOW}6)${NC} Cohere
  ${YELLOW}7)${NC} OpenRouter
  ${YELLOW}8)${NC} Together AI
  ${YELLOW}9)${NC} Perplexity
  ${YELLOW}0)${NC} Cancel

EOF
    read -p "Select provider: " provider_choice
    
    case  $ provider_choice in
        1) add_openai ;;
        2) add_anthropic ;;
        3) add_gemini ;;
        4) add_groq ;;
        5) add_mistral ;;
        6) add_cohere ;;
        7) add_openrouter ;;
        8) add_together ;;
        9) add_perplexity ;;
        0) return ;;
        *) log_warn "Invalid option"; sleep 1; return ;;
    esac
}

add_openai() {
    echo
    log_step "Configuring OpenAI..."
    read -sp "Enter OpenAI API Key: " api_key
    echo
    
    if [ -z " $ api_key" ]; then
        log_warn "API key cannot be empty"
        sleep 2
        return
    fi
    
    # Test the key
    log_info "Testing API key..."
    response=$(curl -s -w "%{http_code}" -o /tmp/openai_test.json \
        -H "Authorization: Bearer  $ api_key" \
        https://api.openai.com/v1/models)
    
    if [ " $ response" = "200" ]; then
        log_success "API key valid!"
        
        # Save to metadata
        save_provider_to_metadata "openai" " $ api_key" "https://api.openai.com/v1"
        
        # Add to LiteLLM config
        add_to_litellm_config "openai" " $ api_key"
        
        log_success "OpenAI configured successfully"
    else
        log_error "Invalid API key or connection failed (HTTP  $ response)"
        cat /tmp/openai_test.json
    fi
    
    read -p "Press Enter to continue..."
}

add_anthropic() {
    echo
    log_step "Configuring Anthropic (Claude)..."
    read -sp "Enter Anthropic API Key: " api_key
    echo
    
    if [ -z " $ api_key" ]; then
        log_warn "API key cannot be empty"
        sleep 2
        return
    fi
    
    log_info "Testing API key..."
    response=$(curl -s -w "%{http_code}" -o /tmp/anthropic_test.json \
        -H "x-api-key:  $ api_key" \
        -H "anthropic-version: 2023-06-01" \
        https://api.anthropic.com/v1/messages \
        -d '{"model":"claude-3-haiku-20240307","messages":[{"role":"user","content":"test"}],"max_tokens":10}')
    
    if [ " $ response" = "200" ]; then
        log_success "API key valid!"
        save_provider_to_metadata "anthropic" " $ api_key" "https://api.anthropic.com/v1"
        add_to_litellm_config "anthropic" " $ api_key"
        log_success "Anthropic configured successfully"
    else
        log_error "Invalid API key or connection failed (HTTP  $ response)"
    fi
    
    read -p "Press Enter to continue..."
}

add_gemini() {
    echo
    log_step "Configuring Google Gemini..."
    read -sp "Enter Google Gemini API Key: " api_key
    echo
    
    if [ -z " $ api_key" ]; then
        log_warn "API key cannot be empty"
        sleep 2
        return
    fi
    
    log_info "Testing API key..."
    response= $ (curl -s -w "%{http_code}" -o /tmp/gemini_test.json \
        "https://generativelanguage.googleapis.com/v1beta/models?key= $ api_key")
    
    if [ " $ response" = "200" ]; then
        log_success "API key valid!"
        save_provider_to_metadata "gemini" " $ api_key" "https://generativelanguage.googleapis.com/v1beta"
        add_to_litellm_config "gemini" "$api_key"
        log_success "Gemini configured successfully"
    else
        log_error "Invalid API key or connection failed (HTTP  $ response)"
    fi
    
    read -p "Press Enter to continue..."
}

add_groq() {
    echo
    log_step "Configuring Groq..."
    read -sp "Enter Groq API Key: " api_key
    echo
    
    if [ -z " $ api_key" ]; then
        log_warn "API key cannot be empty"
        sleep 2
        return
    fi
    
    save_provider_to_metadata "groq" " $ api_key" "https://api.groq.com/openai/v1"
    add_to_litellm_config "groq" " $ api_key"
    log_success "Groq configured successfully"
    
    read -p "Press Enter to continue..."
}

add_mistral() {
    echo
    log_step "Configuring Mistral AI..."
    read -sp "Enter Mistral API Key: " api_key
    echo
    
    if [ -z " $ api_key" ]; then
        log_warn "API key cannot be empty"
        sleep 2
        return
    fi
    
    save_provider_to_metadata "mistral" " $ api_key" "https://api.mistral.ai/v1"
    add_to_litellm_config "mistral" " $ api_key"
    log_success "Mistral AI configured successfully"
    
    read -p "Press Enter to continue..."
}

add_cohere() {
    echo
    log_step "Configuring Cohere..."
    read -sp "Enter Cohere API Key: " api_key
    echo
    
    if [ -z " $ api_key" ]; then
        log_warn "API key cannot be empty"
        sleep 2
        return
    fi
    
    save_provider_to_metadata "cohere" " $ api_key" "https://api.cohere.ai/v1"
    add_to_litellm_config "cohere" " $ api_key"
    log_success "Cohere configured successfully"
    
    read -p "Press Enter to continue..."
}

add_openrouter() {
    echo
    log_step "Configuring OpenRouter..."
    read -sp "Enter OpenRouter API Key: " api_key
    echo
    
    if [ -z " $ api_key" ]; then
        log_warn "API key cannot be empty"
        sleep 2
        return
    fi
    
    save_provider_to_metadata "openrouter" " $ api_key" "https://openrouter.ai/api/v1"
    add_to_litellm_config "openrouter" " $ api_key"
    log_success "OpenRouter configured successfully"
    
    read -p "Press Enter to continue..."
}

add_together() {
    echo
    log_step "Configuring Together AI..."
    read -sp "Enter Together AI API Key: " api_key
    echo
    
    if [ -z " $ api_key" ]; then
        log_warn "API key cannot be empty"
        sleep 2
        return
    fi
    
    save_provider_to_metadata "together" " $ api_key" "https://api.together.xyz/v1"
    add_to_litellm_config "together" " $ api_key"
    log_success "Together AI configured successfully"
    
    read -p "Press Enter to continue..."
}

add_perplexity() {
    echo
    log_step "Configuring Perplexity..."
    read -sp "Enter Perplexity API Key: " api_key
    echo
    
    if [ -z " $ api_key" ]; then
        log_warn "API key cannot be empty"
        sleep 2
        return
    fi
    
    save_provider_to_metadata "perplexity" " $ api_key" "https://api.perplexity.ai"
    add_to_litellm_config "perplexity" " $ api_key"
    log_success "Perplexity configured successfully"
    
    read -p "Press Enter to continue..."
}

save_provider_to_metadata() {
    local provider_name= $ 1
    local api_key= $ 2
    local base_url= $ 3
    
    # Update or add provider in llm_providers.json
    jq --arg name " $ provider_name" \
       --arg key " $ api_key" \
       --arg url "$base_url" \
       '.providers += [{"name": $name, "api_key": $key, "base_url":  $ url}] | 
        .providers |= unique_by(.name)' \
       " $ METADATA_DIR/llm_providers.json" > /tmp/llm_providers.json.tmp
    
    mv /tmp/llm_providers.json.tmp " $ METADATA_DIR/llm_providers.json"
    
    # Reload PROVIDERS array
    PROVIDERS=( $ (jq -r '.providers[]?.name // empty' " $ METADATA_DIR/llm_providers.json"))
}

add_to_litellm_config() {
    local provider= $ 1
    local api_key=$2
    
    # This will be called after saving to metadata
    # We'll regenerate the full LiteLLM config
    regenerate_litellm_config
}

update_provider_key() {
    if [ ${#PROVIDERS[@]} -eq 0 ]; then
        log_warn "No providers configured"
        sleep 2
        return
    fi
    
    clear
    echo "Select provider to update:"
    echo
    for i in "${!PROVIDERS[@]}"; do
        echo "  $((i+1)). ${PROVIDERS[ $ i]}"
    done
    echo "  0. Cancel"
    echo
    read -p "Select provider: " choice
    
    if [ " $ choice" = "0" ]; then
        return
    fi
    
    if [ " $ choice" -lt 1 ] || [ " $ choice" -gt "${#PROVIDERS[@]}" ]; then
        log_warn "Invalid selection"
        sleep 2
        return
    fi
    
    provider_name="${PROVIDERS[$((choice-1))]}"
    
    echo
    read -sp "Enter new API key for  $ provider_name: " new_api_key
    echo
    
    if [ -z " $ new_api_key" ]; then
        log_warn "API key cannot be empty"
        sleep 2
        return
    fi
    
    # Update in metadata
    jq --arg name " $ provider_name" \
       --arg key " $ new_api_key" \
       '(.providers[] | select(.name == $name) | .api_key) =  $ key' \
       " $ METADATA_DIR/llm_providers.json" > /tmp/llm_providers.json.tmp
    
    mv /tmp/llm_providers.json.tmp "$METADATA_DIR/llm_providers.json"
    
    regenerate_litellm_config
    
    log_success "API key updated for $provider_name"
    read -p "Press Enter to continue..."
}

remove_provider() {
    if [ ${#PROVIDERS[@]} -eq 0 ]; then
        log_warn "No providers configured"
        sleep 2
        return
    fi
    
    clear
    echo "Select provider to remove:"
    echo
    for i in "${!PROVIDERS[@]}"; do
        echo "  $((i+1)). ${PROVIDERS[ $ i]}"
    done
    echo "  0. Cancel"
    echo
    read -p "Select provider: " choice
    
    if [ " $ choice" = "0" ]; then
        return
    fi
    
    if [ " $ choice" -lt 1 ] || [ " $ choice" -gt "${#PROVIDERS[@]}" ]; then
        log_warn "Invalid selection"
        sleep 2
        return
    fi
    
    provider_name="${PROVIDERS[$((choice-1))]}"
    
    read -p "Are you sure you want to remove  $ provider_name? (yes/no): " confirm
    
    if [ " $ confirm" = "yes" ]; then
        # Remove from metadata
        jq --arg name "$provider_name" \
           '.providers = [.providers[] | select(.name !=  $ name)]' \
           " $ METADATA_DIR/llm_providers.json" > /tmp/llm_providers.json.tmp
        
        mv /tmp/llm_providers.json.tmp "$METADATA_DIR/llm_providers.json"
        
        regenerate_litellm_config
        
        log_success "Provider  $ provider_name removed"
        
        # Reload PROVIDERS array
        PROVIDERS=( $ (jq -r '.providers[]?.name // empty' "$METADATA_DIR/llm_providers.json"))
    else
        log_info "Cancelled"
    fi
    
    read -p "Press Enter to continue..."
}

test_provider_connection() {
    if [ ${#PROVIDERS[@]} -eq 0 ]; then
        log_warn "No providers configured"
        sleep 2
        return
    fi
    
    clear
    echo "Testing provider connections..."
    echo
    
    for provider in "${PROVIDERS[@]}"; do
        api_key= $ (jq -r ".providers[] | select(.name==\" $ provider\") | .api_key" "$METADATA_DIR/llm_providers.json")
        
        echo -n "Testing $provider... "
        
        case  $ provider in
            openai)
                response= $ (curl -s -w "%{http_code}" -o /dev/null \
                    -H "Authorization: Bearer  $ api_key" \
                    https://api.openai.com/v1/models)
                ;;
            anthropic)
                response= $ (curl -s -w "%{http_code}" -o /dev/null \
                    -H "x-api-key:  $ api_key" \
                    -H "anthropic-version: 2023-06-01" \
                    https://api.anthropic.com/v1/messages \
                    -d '{"model":"claude-3-haiku-20240307","messages":[{"role":"user","content":"test"}],"max_tokens":10}')
                ;;
            gemini)
                response= $ (curl -s -w "%{http_code}" -o /dev/null \
                    "https://generativelanguage.googleapis.com/v1beta/models?key= $ api_key")
                ;;
            *)
                response="000"
                ;;
        esac
        
        if [ " $ response" = "200" ]; then
            echo -e "${GREEN}${ICON_CHECK} OK${NC}"
        else
            echo -e "${RED}${ICON_CROSS} FAILED (HTTP  $ response) $ {NC}"
        fi
    done
    
    echo
    read -p "Press Enter to continue..."
}

# =====================================================
# 2. CONFIGURE LITELLM ROUTING
# =====================================================

configure_litellm_routing() {
    clear
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║            ${ICON_ROBOT} LITELLM ROUTING CONFIGURATION                ║
╚════════════════════════════════════════════════════════════╝

${CYAN}Current Routing Strategy:${NC}
   $ (jq -r '.strategy' " $ METADATA_DIR/litellm_routing.json")

${CYAN}Available Strategies:${NC}
  ${YELLOW}1)${NC} Simple Passthrough (no routing)
  ${YELLOW}2)${NC} Round Robin (distribute evenly)
  ${YELLOW}3)${NC} Fallback Chain (primary → backup)
  ${YELLOW}4)${NC} Cost-Based Routing (cheapest first)
  ${YELLOW}5)${NC} Latency-Based Routing (fastest first)
  ${YELLOW}6)${NC} Custom Model Mapping
  ${YELLOW}0)${NC} Back to Main Menu

EOF
    read -p "Select routing strategy: " choice
    
    case  $ choice in
        1) set_routing_strategy "simple" ;;
        2) set_routing_strategy "round_robin" ;;
        3) set_routing_strategy "fallback" ;;
        4) set_routing_strategy "cost" ;;
        5) set_routing_strategy "latency" ;;
        6) configure_model_mapping ;;
        0) return ;;
        *) log_warn "Invalid option"; sleep 1 ;;
    esac
}

set_routing_strategy() {
    local strategy= $ 1
    
    # Update metadata
    jq --arg strat "$strategy" '.strategy =  $ strat' \
       " $ METADATA_DIR/litellm_routing.json" > /tmp/litellm_routing.json.tmp
    
    mv /tmp/litellm_routing.json.tmp "$METADATA_DIR/litellm_routing.json"
    
    # Regenerate LiteLLM config
    regenerate_litellm_config
    
    log_success "Routing strategy set to: $strategy"
    read -p "Press Enter to continue..."
}

configure_model_mapping() {
    clear
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║              CUSTOM MODEL MAPPING                          ║
╚════════════════════════════════════════════════════════════╝

${CYAN}Current Mappings:${NC}
EOF

    if [ -f " $ METADATA_DIR/litellm_routing.json" ]; then
        jq -r '.model_mappings // {} | to_entries[] | "  \(.key) → \(.value)"' \
           " $ METADATA_DIR/litellm_routing.json"
    fi

    cat << EOF

${CYAN}Options:${NC}
  ${YELLOW}1)${NC} Add Model Mapping
  ${YELLOW}2)${NC} Remove Model Mapping
  ${YELLOW}0)${NC} Back

EOF
    read -p "Select option: " choice
    
    case  $ choice in
        1) add_model_mapping ;;
        2) remove_model_mapping ;;
        0) return ;;
    esac
}

add_model_mapping() {
    echo
    read -p "Enter virtual model name (e.g., 'gpt-4-fast'): " virtual_model
    read -p "Enter actual model name (e.g., 'gpt-4-turbo'): " actual_model
    read -p "Enter provider (e.g., 'openai'): " provider
    
    # Add to metadata
    jq --arg virt " $ virtual_model" \
       --arg actual " $ actual_model" \
       --arg prov " $ provider" \
       '.model_mappings[$virt] = {"model": $actual, "provider":  $ prov}' \
       " $ METADATA_DIR/litellm_routing.json" > /tmp/litellm_routing.json.tmp
    
    mv /tmp/litellm_routing.json.tmp " $ METADATA_DIR/litellm_routing.json"
    
    regenerate_litellm_config
    
    log_success "Model mapping added"
    read -p "Press Enter to continue..."
}

remove_model_mapping() {
    echo
    read -p "Enter virtual model name to remove: " virtual_model
    
    jq --arg virt " $ virtual_model" \
       'del(.model_mappings[ $ virt])' \
       " $ METADATA_DIR/litellm_routing.json" > /tmp/litellm_routing.json.tmp
    
    mv /tmp/litellm_routing.json.tmp " $ METADATA_DIR/litellm_routing.json"
    
    regenerate_litellm_config
    
    log_success "Model mapping removed"
    read -p "Press Enter to continue..."
}

regenerate_litellm_config() {
    log_info "Regenerating LiteLLM configuration..."
    
    # Load metadata
    ROUTING_STRATEGY= $ (jq -r '.strategy' " $ METADATA_DIR/litellm_routing.json")
    
    # Start config
    cat > " $ CONFIG_DIR/litellm_config.yaml" << 'EOLITELLM'
model_list:
EOLITELLM

    # Add Ollama models
    if [ -f " $ METADATA_DIR/selected_services.json" ]; then
        OLLAMA_MODELS= $ (jq -r '.ollama_models[]? // empty' "$METADATA_DIR/selected_services.json" 2>/dev/null)
        
        for model in  $ OLLAMA_MODELS; do
            cat >> " $ CONFIG_DIR/litellm_config.yaml" << EOMODEL
  - model_name:  $ model
    litellm_params:
      model: ollama/ $ model
      api_base: http://ollama:11434
EOMODEL
        done
    fi
    
    # Add cloud providers
    if [ -f " $ METADATA_DIR/llm_providers.json" ]; then
        while IFS= read -r provider_json; do
            provider_name= $ (echo " $ provider_json" | jq -r '.name')
            api_key= $ (echo " $ provider_json" | jq -r '.api_key')
            base_url= $ (echo "$provider_json" | jq -r '.base_url // empty')
            
            case  $ provider_name in
                openai)
                    cat >> " $ CONFIG_DIR/litellm_config.yaml" << EOMODEL

  - model_name: gpt-4
    litellm_params:
      model: openai/gpt-4
      api_key: $api_key
      
  - model_name: gpt-4-turbo
    litellm_params:
      model: openai/gpt-4-turbo-preview
      api_key: $api_key
      
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: openai/gpt-3.5-turbo
      api_key:  $ api_key
EOMODEL
                    ;;
                    
                anthropic)
                    cat >> " $ CONFIG_DIR/litellm_config.yaml" << EOMODEL

  - model_name: claude-3-opus
    litellm_params:
      model: anthropic/claude-3-opus-20240229
      api_key: $api_key
      
  - model_name: claude-3-sonnet
    litellm_params:
      model: anthropic/claude-3-sonnet-20240229
      api_key: $api_key
      
  - model_name: claude-3-haiku
    litellm_params:
      model: anthropic/claude-3-haiku-20240307
      api_key:  $ api_key
EOMODEL
                    ;;
                    
                gemini)
                    cat >> " $ CONFIG_DIR/litellm_config.yaml" << EOMODEL

  - model_name: gemini-pro
    litellm_params:
      model: gemini/gemini-pro
      api_key: $api_key
      
  - model_name: gemini-pro-vision
    litellm_params:
      model: gemini/gemini-pro-vision
      api_key:  $ api_key
EOMODEL
                    ;;
                    
                groq)
                    cat >> " $ CONFIG_DIR/litellm_config.yaml" << EOMODEL

  - model_name: llama3-70b
    litellm_params:
      model: groq/llama3-70b-8192
      api_key: $api_key
      api_base: $base_url
      
  - model_name: mixtral-8x7b
    litellm_params:
      model: groq/mixtral-8x7b-32768
      api_key: $api_key
      api_base:  $ base_url
EOMODEL
                    ;;
            esac
            
        done < <(jq -c '.providers[]' " $ METADATA_DIR/llm_providers.json" 2>/dev/null)
    fi
    
    # Add routing configuration
    cat >> "$CONFIG_DIR/litellm_config.yaml" << EOLITELLM

# Routing configuration
router_settings:
  routing_strategy: $ROUTING_STRATEGY
  num_retries: 3
  timeout: 30
  fallback_models: []
  context_window_fallback_dict: {}

# General settings
general_settings:
  master_key: ${LITELLM_MASTER_KEY:- $ (cat " $ ENV_DIR/litellm.env" 2>/dev/null | grep LITELLM_MASTER_KEY | cut -d= -f2)}
  database_url: postgresql://aiplatform: $ (cat " $ ENV_DIR/postgres.env" 2>/dev/null | grep POSTGRES_PASSWORD | cut -d= -f2)@postgres:5432/aiplatform
  
litellm_settings:
  telemetry: false
  drop_params: true
  set_verbose: false
EOLITELLM

    log_success "LiteLLM configuration regenerated"
}

# =====================================================
# 3. CONFIGURE VECTOR DATABASE
# =====================================================

configure_vectordb() {
    clear
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║          ${ICON_DB} VECTOR DATABASE CONFIGURATION                  ║
╚════════════════════════════════════════════════════════════╝

${CYAN}Current Vector DB:${NC} ${GREEN} $ VECTORDB_TYPE $ {NC}

${CYAN}Options:${NC}
  ${YELLOW}1)${NC} Test Connection
  ${YELLOW}2)${NC} View Collections/Indexes
  ${YELLOW}3)${NC} Update API Key (if applicable)
  ${YELLOW}4)${NC} Backup Database
  ${YELLOW}5)${NC} Switch Vector DB (requires redeployment)
  ${YELLOW}0)${NC} Back to Main Menu

EOF
    read -p "Select option: " choice
    
    case $choice in
        1) test_vectordb_connection ;;
        2) view_vectordb_collections ;;
        3) update_vectordb_api_key ;;
        4) backup_vectordb ;;
        5) switch_vectordb ;;
        0) return ;;
        *) log_warn "Invalid option"; sleep 1 ;;
    esac
}

test_vectordb_connection() {
    log_info "Testing $VECTORDB_TYPE connection..."
    
    case  $ VECTORDB_TYPE in
        qdrant)
            response= $ (curl -s -w "%{http_code}" -o /tmp/qdrant_test.json \
                http://localhost:6333/collections)
            
            if [ "$response" = "200" ]; then
                log_success "Qdrant is responding"
                echo "Collections:"
                jq -r '.result.collections[]?.name // "No collections"' /tmp/qdrant_test.json | sed 's/^/  • /'
            else
                log_error "Qdrant not responding (HTTP  $ response)"
            fi
            ;;
            
        milvus)
            # Milvus requires specific client, just check if port is open
            if nc -z localhost 19530 2>/dev/null; then
                log_success "Milvus port 19530 is open"
            else
                log_error "Cannot connect to Milvus on port 19530"
            fi
            ;;
            
        chromadb)
            response= $ (curl -s -w "%{http_code}" -o /tmp/chroma_test.json \
                http://localhost:8000/api/v1/heartbeat)
            
            if [ "$response" = "200" ]; then
                log_success "ChromaDB is responding"
            else
                log_error "ChromaDB not responding (HTTP  $ response)"
            fi
            ;;
            
        weaviate)
            response= $ (curl -s -w "%{http_code}" -o /tmp/weaviate_test.json \
                http://localhost:8080/v1/.well-known/ready)
            
            if [ "$response" = "200" ]; then
                log_success "Weaviate is responding"
            else
                log_error "Weaviate not responding (HTTP $response)"
            fi
            ;;
    esac
    
    read -p "Press Enter to continue..."
}

view_vectordb_collections() {
    case $VECTORDB_TYPE in
        qdrant)
            curl -s http://localhost:6333/collections | jq -r '.result.collections[]?.name' | sed 's/^/  • /'
            ;;
        chromadb)
            curl -s http://localhost:8000/api/v1/collections | jq
            ;;
        *)
            log_warn "Collection listing not implemented for  $ VECTORDB_TYPE"
            ;;
    esac
    
    read -p "Press Enter to continue..."
}

update_vectordb_api_key() {
    if [ " $ VECTORDB_TYPE" = "qdrant" ]; then
        echo
        read -sp "Enter new Qdrant API key: " new_key
        echo
        
        # Update in vectordb_config.json
        jq --arg key "$new_key" '.api_key =  $ key' \
           " $ METADATA_DIR/vectordb_config.json" > /tmp/vectordb_config.json.tmp
        
        mv /tmp/vectordb_config.json.tmp " $ METADATA_DIR/vectordb_config.json"
        
        # Update env file
        sed -i "s/QDRANT_API_KEY=.*/QDRANT_API_KEY= $ new_key/" "$ENV_DIR/qdrant.env"
        
        log_success "API key updated. Restart Qdrant for changes to take effect."
        log_info "Run: docker compose -f  $ COMPOSE_DIR/qdrant.yml restart"
    else
        log_warn " $ VECTORDB_TYPE does not use API keys"
    fi
    
    read -p "Press Enter to continue..."
}

backup_vectordb() {
    log_info "Backing up  $ VECTORDB_TYPE data..."
    
    BACKUP_DIR=" $ DATA_ROOT/backups/vectordb_ $ (date +%Y%m%d_%H%M%S)"
    mkdir -p " $ BACKUP_DIR"
    
    case  $ VECTORDB_TYPE in
        qdrant)
            tar -czf " $ BACKUP_DIR/qdrant_data.tar.gz" -C " $ DATA_ROOT/data" qdrant
            ;;
        milvus)
            tar -czf " $ BACKUP_DIR/milvus_data.tar.gz" -C " $ DATA_ROOT/data" milvus
            ;;
        chromadb)
            tar -czf " $ BACKUP_DIR/chromadb_data.tar.gz" -C " $ DATA_ROOT/data" chromadb
            ;;
        weaviate)
            tar -czf " $ BACKUP_DIR/weaviate_data.tar.gz" -C "$DATA_ROOT/data" weaviate
            ;;
    esac
    
    log_success "Backup saved to: $BACKUP_DIR"
    read -p "Press Enter to continue..."
}

switch_vectordb() {
    log_warn "Switching vector databases requires:"
    echo "  1. Backing up current data"
    echo "  2. Stopping current vector DB container"
    echo "  3. Deploying new vector DB"
    echo "  4. Updating dependent services (AnythingLLM, Dify, Flowise)"
    echo
    log_warn "This is a complex operation. Recommended: Re-run setup from scratch."
    read -p "Press Enter to continue..."
}

# =====================================================
# 4. CONFIGURE SIGNAL
# =====================================================

configure_signal() {
    clear
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║          ${ICON_SIGNAL} SIGNAL INTEGRATION CONFIGURATION              ║
╚════════════════════════════════════════════════════════════╝

${CYAN}Current Status:${NC}
EOF

    SIGNAL_ENABLED= $ (jq -r '.enabled' " $ METADATA_DIR/signal_config.json" 2>/dev/null || echo "false")
    
    if [ " $ SIGNAL_ENABLED" = "true" ]; then
        PHONE= $ (jq -r '.phone_number' "$METADATA_DIR/signal_config.json")
        echo -e "  ${GREEN}${ICON_CHECK} Enabled${NC} (Phone: $PHONE)"
    else
        echo -e "  ${RED}${ICON_CROSS} Disabled${NC}"
    fi

    cat << EOF

${CYAN}Options:${NC}
  ${YELLOW}1)${NC} Enable/Reconfigure Signal
  ${YELLOW}2)${NC} Test Signal Connection
  ${YELLOW}3)${NC} View QR Code for Pairing
  ${YELLOW}4)${NC} Send Test Message
  ${YELLOW}5)${NC} Configure Webhook URL
  ${YELLOW}6)${NC} Disable Signal
  ${YELLOW}0)${NC} Back to Main Menu

EOF
    read -p "Select option: " choice
    
    case  $ choice in
        1) configure_signal_setup ;;
        2) test_signal_connection ;;
        3) show_signal_qr ;;
        4) send_signal_test_message ;;
        5) configure_signal_webhook ;;
        6) disable_signal ;;
        0) return ;;
        *) log_warn "Invalid option"; sleep 1 ;;
    esac
}

configure_signal_setup() {
    log_step "Setting up Signal integration..."
    
    # Check if signal-api container is running
    if ! docker ps | grep -q signal-api; then
        log_error "Signal-API container not running"
        log_info "Deploy Signal-API first: ./4-add-service.sh"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo
    read -p "Enter phone number (with country code, e.g., +1234567890): " phone_number
    
    if [ -z " $ phone_number" ]; then
        log_warn "Phone number cannot be empty"
        sleep 2
        return
    fi
    
    log_info "Registering phone number with Signal..."
    
    # Register with Signal
    response= $ (curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"number\":\" $ phone_number\",\"use_voice\":false}" \
        http://localhost:8090/v1/register/ $ phone_number)
    
    if echo " $ response" | jq -e '.error' >/dev/null 2>&1; then
        log_error "Registration failed:  $ (echo " $ response" | jq -r '.error')"
        read -p "Press Enter to continue..."
        return
    fi
    
    log_success "Registration initiated. Check your phone for verification code."
    echo
    read -p "Enter 6-digit verification code: " verify_code
    
    # Verify code
    response= $ (curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"number\":\" $ phone_number\",\"code\":\" $ verify_code\"}" \
        http://localhost:8090/v1/register/ $ phone_number/verify/ $ verify_code)
    
    if echo " $ response" | jq -e '.error' >/dev/null 2>&1; then
        log_error "Verification failed:  $ (echo " $ response" | jq -r '.error')"
        read -p "Press Enter to continue..."
        return
    fi
    
    log_success "Signal account verified!"
    
    # Save to metadata
    jq --arg phone "$phone_number" \
       --arg webhook "http://localhost:8090/v1/send" \
       '.enabled = true | .phone_number = $phone | .webhook_url =  $ webhook' \
       " $ METADATA_DIR/signal_config.json" > /tmp/signal_config.json.tmp
    
    mv /tmp/signal_config.json.tmp " $ METADATA_DIR/signal_config.json"
    
    log_success "Signal configuration saved"
    read -p "Press Enter to continue..."
}

test_signal_connection() {
    if ! docker ps | grep -q signal-api; then
        log_error "Signal-API container not running"
        read -p "Press Enter to continue..."
        return
    fi
    
    log_info "Testing Signal-API connection..."
    
    response= $ (curl -s http://localhost:8090/v1/health)
    
    if echo " $ response" | jq -e '.status' >/dev/null 2>&1; then
        log_success "Signal-API is healthy"
        echo " $ response" | jq
    else
        log_error "Signal-API not responding correctly"
    fi
    
    read -p "Press Enter to continue..."
}

show_signal_qr() {
    PHONE= $ (jq -r '.phone_number' " $ METADATA_DIR/signal_config.json" 2>/dev/null)
    
    if [ -z " $ PHONE" ] || [ " $ PHONE" = "null" ]; then
        log_warn "Phone number not configured"
        read -p "Press Enter to continue..."
        return
    fi
    
    log_info "Generating QR code for linking..."
    
    # Get QR code from signal-api
    curl -s "http://localhost:8090/v1/qrcodelink?device_name=OpenClaw" > /tmp/signal_qr.png
    
    if [ -f /tmp/signal_qr.png ]; then
        log_success "QR code saved to /tmp/signal_qr.png"
        log_info "Scan this with Signal app on your phone to link"
        
        # Try to display with qrencode if available
        if command -v qrencode &>/dev/null; then
            qrencode -t ANSIUTF8 < /tmp/signal_qr.png
        fi
    else
        log_error "Failed to generate QR code"
    fi
    
    read -p "Press Enter to continue..."
}

send_signal_test_message() {
    PHONE= $ (jq -r '.phone_number' " $ METADATA_DIR/signal_config.json" 2>/dev/null)
    
    if [ -z " $ PHONE" ] || [ " $ PHONE" = "null" ]; then
        log_warn "Phone number not configured"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo
    read -p "Enter recipient phone number (or press Enter to send to self): " recipient
    
    if [ -z " $ recipient" ]; then
        recipient=" $ PHONE"
    fi
    
    read -p "Enter test message: " message
    
    if [ -z " $ message" ]; then
        message="Test message from AIPlatformAutomation"
    fi
    
    log_info "Sending message..."
    
    response= $ (curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"message\":\" $ message\",\"number\":\" $ PHONE\",\"recipients\":[\" $ recipient\"]}" \
        http://localhost:8090/v2/send)
    
    if echo " $ response" | jq -e '.error' >/dev/null 2>&1; then
        log_error "Failed to send:  $ (echo " $ response" | jq -r '.error')"
    else
        log_success "Message sent!"
    fi
    
    read -p "Press Enter to continue..."
}

configure_signal_webhook() {
    echo
    read -p "Enter webhook URL for incoming messages (e.g., http://openclaw-ui:3000/webhook): " webhook_url
    
    if [ -z " $ webhook_url" ]; then
        log_warn "Webhook URL cannot be empty"
        sleep 2
        return
    fi
    
    jq --arg url " $ webhook_url" '.webhook_url =  $ url' \
       " $ METADATA_DIR/signal_config.json" > /tmp/signal_config.json.tmp
    
    mv /tmp/signal_config.json.tmp " $ METADATA_DIR/signal_config.json"
    
    log_success "Webhook URL updated"
    read -p "Press Enter to continue..."
}

disable_signal() {
    read -p "Are you sure you want to disable Signal? (yes/no): " confirm
    
    if [ " $ confirm" = "yes" ]; then
        jq '.enabled = false' \
           " $ METADATA_DIR/signal_config.json" > /tmp/signal_config.json.tmp
        
        mv /tmp/signal_config.json.tmp " $ METADATA_DIR/signal_config.json"
        
        log_success "Signal disabled"
    else
        log_info "Cancelled"
    fi
    
    read -p "Press Enter to continue..."
}

# =====================================================
# 5. CONFIGURE GOOGLE DRIVE
# =====================================================

configure_gdrive() {
    clear
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║        ${ICON_DRIVE} GOOGLE DRIVE SYNC CONFIGURATION              ║
╚════════════════════════════════════════════════════════════╝

${CYAN}Current Status:${NC}
EOF

    GDRIVE_ENABLED= $ (jq -r '.enabled' " $ METADATA_DIR/gdrive_config.json" 2>/dev/null || echo "false")
    
    if [ "$GDRIVE_ENABLED" = "true" ]; then
        echo -e "  ${GREEN}${ICON_CHECK} Enabled${NC}"
    else
        echo -e "  ${RED}${ICON_CROSS} Disabled${NC}"
    fi

    cat << EOF

${CYAN}Options:${NC}
  ${YELLOW}1)${NC} Configure Google Drive OAuth
  ${YELLOW}2)${NC} Set Sync Folders
  ${YELLOW}3)${NC} Set Sync Interval
  ${YELLOW}4)${NC} Test Connection
  ${YELLOW}5)${NC} Manual Sync Now
  ${YELLOW}6)${NC} View Sync Status
  ${YELLOW}7)${NC} Disable Google Drive Sync
  ${YELLOW}0)${NC} Back to Main Menu

EOF
    read -p "Select option: " choice
    
    case  $ choice in
        1) configure_gdrive_oauth ;;
        2) configure_gdrive_folders ;;
        3) configure_gdrive_interval ;;
        4) test_gdrive_connection ;;
        5) manual_gdrive_sync ;;
        6) view_gdrive_status ;;
        7) disable_gdrive ;;
        0) return ;;
        *) log_warn "Invalid option"; sleep 1 ;;
    esac
}

configure_gdrive_oauth() {
    log_step "Configuring Google Drive OAuth..."
    
    cat << 'EOF'

To configure Google Drive access:
1. Go to https://console.cloud.google.com/
2. Create a new project (or select existing)
3. Enable Google Drive API
4. Create OAuth 2.0 credentials
5. Download the credentials JSON file

EOF
    
    read -p "Enter path to OAuth credentials JSON file: " creds_path
    
    if [ ! -f " $ creds_path" ]; then
        log_error "File not found:  $ creds_path"
        sleep 2
        return
    fi
    
    # Copy credentials
    mkdir -p " $ CONFIG_DIR/rclone"
    cp " $ creds_path" " $ CONFIG_DIR/rclone/client_secret.json"
    
    log_info "Starting OAuth flow..."
    log_info "A browser window will open for authorization"
    
    # Run rclone config for OAuth
    docker run --rm -it \
        -v " $ CONFIG_DIR/rclone:/config/rclone" \
        rclone/rclone:latest \
        config create gdrive drive \
        config_is_local false \
        --drive-client-id " $ (jq -r '.installed.client_id' " $ CONFIG_DIR/rclone/client_secret.json")" \
        --drive-client-secret " $ (jq -r '.installed.client_secret' "$CONFIG_DIR/rclone/client_secret.json")"
    
    if [  $ ? -eq 0 ]; then
        log_success "Google Drive configured successfully"
        
        # Update metadata
        jq '.enabled = true' \
           " $ METADATA_DIR/gdrive_config.json" > /tmp/gdrive_config.json.tmp
        
        mv /tmp/gdrive_config.json.tmp " $ METADATA_DIR/gdrive_config.json"
    else
        log_error "OAuth configuration failed"
    fi
    
    read -p "Press Enter to continue..."
}

configure_gdrive_folders() {
    echo
    read -p "Enter Google Drive folder path to sync FROM (e.g., /AI_Platform): " remote_path
    read -p "Enter local path to sync TO (default: /mnt/data/data/gdrive-sync): " local_path
    
    if [ -z " $ local_path" ]; then
        local_path="/mnt/data/data/gdrive-sync"
    fi
    
    # Update metadata
    jq --arg remote " $ remote_path" \
       --arg local " $ local_path" \
       '.remote_path = $remote | .local_path =  $ local' \
       " $ METADATA_DIR/gdrive_config.json" > /tmp/gdrive_config.json.tmp
    
    mv /tmp/gdrive_config.json.tmp " $ METADATA_DIR/gdrive_config.json"
    
    log_success "Sync folders configured"
    read -p "Press Enter to continue..."
}

configure_gdrive_interval() {
    echo
    echo "Sync intervals:"
    echo "  300  = 5 minutes"
    echo "  900  = 15 minutes"
    echo "  1800 = 30 minutes"
    echo "  3600 = 1 hour"
    echo
    read -p "Enter sync interval in seconds (default: 1800): " interval
    
    if [ -z " $ interval" ]; then
        interval=1800
    fi
    
    # Update metadata
    jq --arg int " $ interval" '.sync_interval = ( $ int | tonumber)' \
       " $ METADATA_DIR/gdrive_config.json" > /tmp/gdrive_config.json.tmp
    
    mv /tmp/gdrive_config.json.tmp " $ METADATA_DIR/gdrive_config.json"
    
    # Update env file
    sed -i "s/SYNC_INTERVAL=.*/SYNC_INTERVAL= $ interval/" " $ ENV_DIR/gdrive-sync.env"
    
    log_success "Sync interval set to  $ interval seconds"
    read -p "Press Enter to continue..."
}

test_gdrive_connection() {
    log_info "Testing Google Drive connection..."
    
    if [ ! -f " $ CONFIG_DIR/rclone/rclone.conf" ]; then
        log_error "rclone not configured. Run option 1 first."
        read -p "Press Enter to continue..."
        return
    fi
    
    # List remote files
    docker run --rm \
        -v "$CONFIG_DIR/rclone:/config/rclone" \
        rclone/rclone:latest \
        lsd gdrive:
    
    if [  $ ? -eq 0 ]; then
        log_success "Successfully connected to Google Drive"
    else
        log_error "Connection failed"
    fi
    
    read -p "Press Enter to continue..."
}

manual_gdrive_sync() {
    REMOTE_PATH= $ (jq -r '.remote_path' " $ METADATA_DIR/gdrive_config.json")
    LOCAL_PATH= $ (jq -r '.local_path' " $ METADATA_DIR/gdrive_config.json")
    
    log_info "Starting manual sync..."
    log_info "Remote: gdrive: $ REMOTE_PATH"
    log_info "Local:  $ LOCAL_PATH"
    
    docker run --rm \
        -v " $ CONFIG_DIR/rclone:/config/rclone" \
        -v " $ LOCAL_PATH:/data" \
        rclone/rclone:latest \
        sync "gdrive: $ REMOTE_PATH" /data -v
    
    if [  $ ? -eq 0 ]; then
        log_success "Sync completed"
    else
        log_error "Sync failed"
    fi
    
    read -p "Press Enter to continue..."
}

view_gdrive_status() {
    if ! docker ps | grep -q gdrive-sync; then
        log_warn "GDrive sync container not running"
        read -p "Press Enter to continue..."
        return
    fi
    
    log_info "GDrive sync container logs (last 50 lines):"
    echo
    docker logs --tail 50 gdrive-sync
    
    read -p "Press Enter to continue..."
}

disable_gdrive() {
    read -p "Are you sure you want to disable Google Drive sync? (yes/no): " confirm
    
    if [ " $ confirm" = "yes" ]; then
        jq '.enabled = false' \
           " $ METADATA_DIR/gdrive_config.json" > /tmp/gdrive_config.json.tmp
        
        mv /tmp/gdrive_config.json.tmp " $ METADATA_DIR/gdrive_config.json"
        
        # Stop container
        if docker ps | grep -q gdrive-sync; then
            docker compose -f "$COMPOSE_DIR/gdrive-sync.yml" down
        fi
        
        log_success "Google Drive sync disabled"
    else
        log_info "Cancelled"
    fi
    
    read -p "Press Enter to continue..."
}

# =====================================================
# 6. CONFIGURE WEBHOOKS
# =====================================================

configure_webhooks() {
    clear
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║            ⚡ WEBHOOK CONFIGURATION                        ║
╚════════════════════════════════════════════════════════════╝

${CYAN}Webhook Integrations:${NC}

  ${YELLOW}1)${NC} OpenClaw → Signal Webhook
  ${YELLOW}2)${NC} AnythingLLM → Signal Webhook
  ${YELLOW}3)${NC} Dify → Signal Webhook
  ${YELLOW}4)${NC} n8n → LiteLLM Webhook
  ${YELLOW}5)${NC} Test Webhook Endpoint
  ${YELLOW}0)${NC} Back to Main Menu

EOF
    read -p "Select option: " choice
    
    case  $ choice in
        1) configure_openclaw_webhook ;;
        2) configure_anythingllm_webhook ;;
        3) configure_dify_webhook ;;
        4) configure_n8n_webhook ;;
        5) test_webhook ;;
        0) return ;;
        *) log_warn "Invalid option"; sleep 1 ;;
    esac
}

configure_openclaw_webhook() {
    SIGNAL_WEBHOOK= $ (jq -r '.webhook_url' "$METADATA_DIR/signal_config.json" 2>/dev/null)
    
    echo
    echo "Current Signal webhook:  $ SIGNAL_WEBHOOK"
    read -p "Update OpenClaw to use this webhook? (yes/no): " confirm
    
    if [ " $ confirm" = "yes" ]; then
        # Update OpenClaw env
        sed -i "s|SIGNAL_API_URL=.*|SIGNAL_API_URL= $ SIGNAL_WEBHOOK|" " $ ENV_DIR/openclaw-ui.env"
        
        log_success "OpenClaw webhook updated"
        log_warn "Restart OpenClaw for changes to take effect:"
        log_info "docker compose -f  $ COMPOSE_DIR/openclaw-ui.yml restart"
    fi
    
    read -p "Press Enter to continue..."
}

configure_anythingllm_webhook() {
    log_info "Configuring AnythingLLM Signal webhook..."
    
    SIGNAL_WEBHOOK= $ (jq -r '.webhook_url' " $ METADATA_DIR/signal_config.json" 2>/dev/null)
    
    cat << EOF

To configure AnythingLLM webhook:
1. Access AnythingLLM at http:// $ DOMAIN:3001
2. Go to Settings → Integrations
3. Add Signal webhook:  $ SIGNAL_WEBHOOK
4. Configure message routing

EOF
    
    read -p "Press Enter to continue..."
}

configure_dify_webhook() {
    log_info "Configuring Dify Signal webhook..."
    
    SIGNAL_WEBHOOK= $ (jq -r '.webhook_url' " $ METADATA_DIR/signal_config.json" 2>/dev/null)
    
    cat << EOF

To configure Dify webhook:
1. Access Dify at http:// $ DOMAIN:3002
2. Go to your app → Settings → Integrations
3. Add HTTP webhook:  $ SIGNAL_WEBHOOK
4. Set up trigger conditions

EOF
    
    read -p "Press Enter to continue..."
}

configure_n8n_webhook() {
    LITELLM_URL="http://litellm:4000"
    LITELLM_KEY= $ (cat " $ ENV_DIR/litellm.env" | grep LITELLM_MASTER_KEY | cut -d= -f2)
    
    cat << EOF

To configure n8n LiteLLM webhook:
1. Access n8n at http://$DOMAIN:5678
2. Create a new workflow
3. Add HTTP Request node:
   - URL: $LITELLM_URL/chat/completions
   - Method: POST
   - Authentication: Bearer Token
   - Token: $LITELLM_KEY
4. Configure request body for OpenAI-compatible format

EOF

    read -p "Press Enter to continue..."
}

test_webhook() {
    echo
    read -p "Enter webhook URL to test: " webhook_url

    if [ -z "$webhook_url" ]; then
        log_warn "URL cannot be empty"
        sleep 2
        return
    fi

    log_info "Sending test POST request..."

    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d '{"test":"message","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
        "$webhook_url")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)

    echo
    echo "HTTP Status: $http_code"
    echo "Response Body:"
    echo "$body" | jq 2>/dev/null || echo "$body"

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        log_success "Webhook test successful"
    else
        log_error "Webhook test failed"
    fi

    read -p "Press Enter to continue..."
}

# =====================================================
# 7. CONFIGURE REVERSE PROXY
# =====================================================

configure_reverse_proxy() {
    PROXY_TYPE=$(jq -r '.proxy_type' "$METADATA_DIR/network_config.json")

    clear
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║          🌐 REVERSE PROXY CONFIGURATION                    ║
╚════════════════════════════════════════════════════════════╝

${CYAN}Current Proxy:${NC} $PROXY_TYPE

${CYAN}Options:${NC}
  ${YELLOW}1)${NC} View Current Configuration
  ${YELLOW}2)${NC} Add SSL Certificate
  ${YELLOW}3)${NC} Update Domain
  ${YELLOW}4)${NC} Add/Remove Service Route
  ${YELLOW}5)${NC} Test Proxy Configuration
  ${YELLOW}6)${NC} View Proxy Logs
  ${YELLOW}0)${NC} Back to Main Menu

EOF
    read -p "Select option: " choice

    case $choice in
        1) view_proxy_config ;;
        2) add_ssl_certificate ;;
        3) update_domain ;;
        4) manage_service_routes ;;
        5) test_proxy_config ;;
        6) view_proxy_logs ;;
        0) return ;;
        *) log_warn "Invalid option"; sleep 1 ;;
    esac
}

view_proxy_config() {
    case $PROXY_TYPE in
        swag)
            log_info "SWAG Configuration:"
            echo
            cat "$CONFIG_DIR/swag/nginx/site-confs/default.conf" 2>/dev/null || log_warn "Config file not found"
            ;;
        nginx-proxy-manager)
            log_info "Access NPM web interface at: http://$DOMAIN:81"
            log_info "Default credentials:"
            echo "  Email: admin@example.com"
            echo "  Password: changeme"
            ;;
    esac

    read -p "Press Enter to continue..."
}

add_ssl_certificate() {
    echo
    read -p "Enter domain for SSL certificate: " ssl_domain
    read -p "Enter email for Let's Encrypt: " ssl_email

    if [ -z "$ssl_domain" ] || [ -z "$ssl_email" ]; then
        log_warn "Domain and email are required"
        sleep 2
        return
    fi

    case $PROXY_TYPE in
        swag)
            log_info "Configuring Let's Encrypt with SWAG..."

            # Update SWAG env
            sed -i "s/URL=.*/URL=$ssl_domain/" "$ENV_DIR/swag.env"
            sed -i "s/EMAIL=.*/EMAIL=$ssl_email/" "$ENV_DIR/swag.env"

            # Restart SWAG
            docker compose -f "$COMPOSE_DIR/swag.yml" restart

            log_success "SSL certificate requested. Check SWAG logs for status."
            ;;

        nginx-proxy-manager)
            log_info "To add SSL in NPM:"
            echo "  1. Access NPM at http://$DOMAIN:81"
            echo "  2. Go to SSL Certificates"
            echo "  3. Add Let's Encrypt certificate"
            echo "  4. Domain: $ssl_domain"
            echo "  5. Email: $ssl_email"
            ;;
    esac

    read -p "Press Enter to continue..."
}

update_domain() {
    echo
    read -p "Enter new domain: " new_domain

    if [ -z "$new_domain" ]; then
        log_warn "Domain cannot be empty"
        sleep 2
        return
    fi

    # Update metadata
    jq --arg domain "$new_domain" '.domain = $domain' \
       "$METADATA_DIR/network_config.json" > /tmp/network_config.json.tmp

    mv /tmp/network_config.json.tmp "$METADATA_DIR/network_config.json"

    # Update proxy env
    case $PROXY_TYPE in
        swag)
            sed -i "s/URL=.*/URL=$new_domain/" "$ENV_DIR/swag.env"
            docker compose -f "$COMPOSE_DIR/swag.yml" restart
            ;;
        nginx-proxy-manager)
            log_info "Update domain in NPM web interface"
            ;;
    esac

    DOMAIN="$new_domain"
    log_success "Domain updated to: $new_domain"

    read -p "Press Enter to continue..."
}

manage_service_routes() {
    log_info "Service route management depends on your proxy type"

    case $PROXY_TYPE in
        swag)
            echo
            echo "SWAG routes are configured in:"
            echo "  $CONFIG_DIR/swag/nginx/site-confs/"
            echo
            echo "Example route for OpenWebUI:"
            cat << 'ROUTE'
location /openwebui/ {
    proxy_pass http://open-webui:8080/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
ROUTE
            ;;

        nginx-proxy-manager)
            echo
            echo "Add routes in NPM web interface:"
            echo "  1. Go to Proxy Hosts"
            echo "  2. Add Proxy Host"
            echo "  3. Configure domain, forward hostname/IP, port"
            ;;
    esac

    read -p "Press Enter to continue..."
}

test_proxy_config() {
    log_info "Testing proxy configuration..."

    case $PROXY_TYPE in
        swag)
            docker exec swag nginx -t
            ;;
        nginx-proxy-manager)
            docker exec nginx-proxy-manager nginx -t
            ;;
    esac

    if [ $? -eq 0 ]; then
        log_success "Proxy configuration is valid"
    else
        log_error "Proxy configuration has errors"
    fi

    read -p "Press Enter to continue..."
}

view_proxy_logs() {
    case $PROXY_TYPE in
        swag)
            docker logs --tail 100 -f swag
            ;;
        nginx-proxy-manager)
            docker logs --tail 100 -f nginx-proxy-manager
            ;;
    esac
}

# =====================================================
# 8. TEST SERVICE CONNECTIONS
# =====================================================

test_service_connections() {
    clear
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║          🔍 SERVICE CONNECTION TESTS                       ║
╚════════════════════════════════════════════════════════════╝

Testing all deployed services...

EOF

    # Test PostgreSQL
    if docker ps | grep -q postgres; then
        echo -n "PostgreSQL... "
        if docker exec postgres pg_isready -U aiplatform >/dev/null 2>&1; then
            echo -e "${GREEN}${ICON_CHECK}${NC}"
        else
            echo -e "${RED}${ICON_CROSS}${NC}"
        fi
    fi

    # Test Redis
    if docker ps | grep -q redis; then
        echo -n "Redis... "
        if docker exec redis redis-cli ping | grep -q PONG; then
            echo -e "${GREEN}${ICON_CHECK}${NC}"
        else
            echo -e "${RED}${ICON_CROSS}${NC}"
        fi
    fi

    # Test Vector DB
    if [ "$VECTORDB_TYPE" != "none" ]; then
        echo -n "Vector DB ($VECTORDB_TYPE)... "
        case $VECTORDB_TYPE in
            qdrant)
                response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:6333/health)
                ;;
            milvus)
                response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:9091/healthz)
                ;;
            chromadb)
                response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:8000/api/v1/heartbeat)
                ;;
            weaviate)
                response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:8080/v1/.well-known/ready)
                ;;
        esac

        if [ "$response" = "200" ]; then
            echo -e "${GREEN}${ICON_CHECK}${NC}"
        else
            echo -e "${RED}${ICON_CROSS}${NC}"
        fi
    fi

    # Test Ollama
    if docker ps | grep -q ollama; then
        echo -n "Ollama... "
        response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:11434)
        if [ "$response" = "200" ]; then
            echo -e "${GREEN}${ICON_CHECK}${NC}"
        else
            echo -e "${RED}${ICON_CROSS}${NC}"
        fi
    fi

    # Test LiteLLM
    if docker ps | grep -q litellm; then
        echo -n "LiteLLM... "
        response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:4000/health)
        if [ "$response" = "200" ]; then
            echo -e "${GREEN}${ICON_CHECK}${NC}"
        else
            echo -e "${RED}${ICON_CROSS}${NC}"
        fi
    fi

    # Test each selected service
    for service in "${SELECTED_SERVICES[@]}"; do
        case $service in
            open-webui)
                echo -n "Open WebUI... "
                response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:8080)
                ;;
            anythingllm)
                echo -n "AnythingLLM... "
                response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:3001)
                ;;
            dify)
                echo -n "Dify... "
                response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:3002/health)
                ;;
            n8n)
                echo -n "n8n... "
                response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:5678/healthz)
                ;;
            flowise)
                echo -n "Flowise... "
                response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:3003/health)
                ;;
            comfyui)
                echo -n "ComfyUI... "
                response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:8188)
                ;;
            openclaw-ui)
                echo -n "OpenClaw UI... "
                response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:3000)
                ;;
            signal-api)
                echo -n "Signal API... "
                response=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:8090/v1/health)
                ;;
        esac

        if [ "$response" = "200" ]; then
            echo -e "${GREEN}${ICON_CHECK}${NC}"
        else
            echo -e "${RED}${ICON_CROSS}${NC}"
        fi
    done

    echo
    read -p "Press Enter to continue..."
}

# =====================================================
# 9. VIEW CURRENT CONFIGURATION
# =====================================================

view_current_config() {
    clear
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║          📊 CURRENT SYSTEM CONFIGURATION                   ║
╚════════════════════════════════════════════════════════════╝

${CYAN}Network Configuration:${NC}
  Domain: $DOMAIN
  Proxy: $PROXY_TYPE

${CYAN}Infrastructure:${NC}
  Vector DB: $VECTORDB_TYPE

${CYAN}LLM Providers:${NC}
EOF

    if [ ${#PROVIDERS[@]} -eq 0 ]; then
        echo "  • Local only (Ollama)"
    else
        for provider in "${PROVIDERS[@]}"; do
            echo "  • $provider"
        done
    fi

    cat << EOF

${CYAN}LiteLLM Routing:${NC}
  Strategy: $(jq -r '.strategy' "$METADATA_DIR/litellm_routing.json")

${CYAN}Integrations:${NC}
EOF

    SIGNAL_ENABLED=$(jq -r '.enabled' "$METADATA_DIR/signal_config.json" 2>/dev/null || echo "false")
    if [ "$SIGNAL_ENABLED" = "true" ]; then
        echo -e "  Signal: ${GREEN}${ICON_CHECK} Enabled${NC} ($(jq -r '.phone_number' "$METADATA_DIR/signal_config.json"))"
    else
        echo -e "  Signal: ${RED}${ICON_CROSS} Disabled${NC}"
    fi

    GDRIVE_ENABLED=$(jq -r '.enabled' "$METADATA_DIR/gdrive_config.json" 2>/dev/null || echo "false")
    if [ "$GDRIVE_ENABLED" = "true" ]; then
        echo -e "  Google Drive: ${GREEN}${ICON_CHECK} Enabled${NC}"
    else
        echo -e "  Google Drive: ${RED}${ICON_CROSS} Disabled${NC}"
    fi

    cat << EOF

${CYAN}Deployed Services (${#SELECTED_SERVICES[@]}):${NC}
EOF

    for service in "${SELECTED_SERVICES[@]}"; do
        if docker ps | grep -q "$service"; then
            echo -e "  • $service ${GREEN}${ICON_CHECK} Running${NC}"
        else
            echo -e "  • $service ${RED}${ICON_CROSS} Stopped${NC}"
        fi
    done

    echo
    read -p "Press Enter to continue..."
}

# =====================================================
# 10. HOT-RELOAD SERVICES
# =====================================================

hot_reload_services() {
    clear
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║          ${ICON_RELOAD} HOT-RELOAD SERVICES                            ║
╚════════════════════════════════════════════════════════════╝

Select service to reload:

EOF

    services_with_reload=("litellm" "open-webui" "anythingllm" "n8n" "flowise")

    for i in "${!services_with_reload[@]}"; do
        echo "  $((i+1)). ${services_with_reload[$i]}"
    done
    echo "  0. Cancel"
    echo

    read -p "Select service: " choice

    if [ "$choice" = "0" ]; then
        return
    fi

    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#services_with_reload[@]}" ]; then
        log_warn "Invalid selection"
        sleep 2
        return
    fi

    service_name="${services_with_reload[$((choice-1))]}"

    log_info "Reloading $service_name..."

    case $service_name in
        litellm)
            # Regenerate config and restart
            regenerate_litellm_config
            docker compose -f "$COMPOSE_DIR/litellm.yml" restart
            ;;
        *)
            docker compose -f "$COMPOSE_DIR/${service_name}.yml" restart
            ;;
    esac

    if [ $? -eq 0 ]; then
        log_success "$service_name reloaded successfully"
    else
        log_error "Failed to reload $service_name"
    fi

    read -p "Press Enter to continue..."
}

# =====================================================
# 11. ROTATE CREDENTIALS
# =====================================================

rotate_credentials() {
    clear
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║          🔐 CREDENTIAL ROTATION                            ║
╚════════════════════════════════════════════════════════════╝

${YELLOW}Warning:${NC} Rotating credentials requires restarting services

Select credentials to rotate:

  ${YELLOW}1)${NC} PostgreSQL passwords
  ${YELLOW}2)${NC} Redis password
  ${YELLOW}3)${NC} LiteLLM master key
  ${YELLOW}4)${NC} Vector DB API key
  ${YELLOW}5)${NC} All credentials (full rotation)
  ${YELLOW}0)${NC} Cancel

EOF
    read -p "Select option: " choice

    case $choice in
        1) rotate_postgres_password ;;
        2) rotate_redis_password ;;
        3) rotate_litellm_key ;;
        4) rotate_vectordb_key ;;
        5) rotate_all_credentials ;;
        0) return ;;
        *) log_warn "Invalid option"; sleep 1 ;;
    esac
}

rotate_postgres_password() {
    log_warn "Rotating PostgreSQL password..."

    NEW_PASSWORD=$(openssl rand -base64 32)

    # Update env file
    sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$NEW_PASSWORD/" "$ENV_DIR/postgres.env"

    # Update password in PostgreSQL
    docker exec postgres psql -U aiplatform -c "ALTER USER aiplatform WITH PASSWORD '$NEW_PASSWORD';"

    # Update all services that use PostgreSQL
    for env_file in "$ENV_DIR"/*.env; do
        if grep -q "DATABASE_URL" "$env_file"; then
            sed -i "s|postgresql://aiplatform:[^@]*@|postgresql://aiplatform:$NEW_PASSWORD@|g" "$env_file"
        fi
    done

    log_success "PostgreSQL password rotated"
    log_warn "Restart all services that use PostgreSQL"

    read -p "Press Enter to continue..."
}

rotate_redis_password() {
    log_warn "Rotating Redis password..."

    NEW_PASSWORD=$(openssl rand -base64 32)

    # Update env file
    sed -i "s/REDIS_PASSWORD=.*/REDIS_PASSWORD=$NEW_PASSWORD/" "$ENV_DIR/redis.env"

    # Restart Redis
    docker compose -f "$COMPOSE_DIR/redis.yml" restart

    # Update all services that use Redis
    for env_file in "$ENV_DIR"/*.env; do
        if grep -q "REDIS_PASSWORD" "$env_file"; then
            sed -i "s/REDIS_PASSWORD=.*/REDIS_PASSWORD=$NEW_PASSWORD/" "$env_file"
        fi
    done

    log_success "Redis password rotated"
    log_warn "Restart all services that use Redis"

    read -p "Press Enter to continue..."
}

rotate_litellm_key() {
    log_warn "Rotating LiteLLM master key..."

    NEW_KEY=$(openssl rand -hex 32)

    # Update env file
    sed -i "s/LITELLM_MASTER_KEY=.*/LITELLM_MASTER_KEY=$NEW_KEY/" "$ENV_DIR/litellm.env"

    # Restart LiteLLM
    docker compose -f "$COMPOSE_DIR/litellm.yml" restart

    log_success "LiteLLM master key rotated"
    log_info "New key: $NEW_KEY"
    log_warn "Update this key in all services that use LiteLLM"

    read -p "Press Enter to continue..."
}

rotate_vectordb_key() {
    if [ "$VECTORDB_TYPE" = "qdrant" ]; then
        log_warn "Rotating Qdrant API key..."

        NEW_KEY=$(openssl rand -hex 32)

        # Update env file
        sed -i "s/QDRANT_API_KEY=.*/QDRANT_API_KEY=$NEW_KEY/" "$ENV_DIR/qdrant.env"

        # Update metadata
        jq --arg key "$NEW_KEY" '.api_key = $key' \
           "$METADATA_DIR/vectordb_config.json" > /tmp/vectordb_config.json.tmp

        mv /tmp/vectordb_config.json.tmp "$METADATA_DIR/vectordb_config.json"

        # Restart Qdrant
        docker compose -f "$COMPOSE_DIR/qdrant.yml" restart

        log_success "Qdrant API key rotated"
        log_warn "Update this key in all services that use Qdrant"
    else
        log_warn "$VECTORDB_TYPE does not use API keys"
    fi

    read -p "Press Enter to continue..."
}

rotate_all_credentials() {
    read -p "Are you sure you want to rotate ALL credentials? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        log_info "Cancelled"
        sleep 1
        return
    fi

    log_warn "Starting full credential rotation..."

    rotate_postgres_password
    rotate_redis_password
    rotate_litellm_key
    rotate_vectordb_key

    log_success "All credentials rotated"
    log_warn "IMPORTANT: Restart all services for changes to take effect"
    log_info "Run: docker compose down && ./2-deploy-services.sh"

    read -p "Press Enter to continue..."
}

# =====================================================
# 12. BACKUP CONFIGURATION
# =====================================================

backup_configuration() {
    BACKUP_NAME="config_backup_$(date +%Y%m%d_%H%M%S)"
    BACKUP_PATH="$DATA_ROOT/backups/$BACKUP_NAME"

    log_info "Creating configuration backup..."

    mkdir -p "$BACKUP_PATH"

    # Backup metadata
    cp -r "$METADATA_DIR" "$BACKUP_PATH/"

    # Backup compose files
    cp -r "$COMPOSE_DIR" "$BACKUP_PATH/"

    # Backup env files
    cp -r "$ENV_DIR" "$BACKUP_PATH/"

    # Backup config files
    cp -r "$CONFIG_DIR" "$BACKUP_PATH/"

    # Create archive
    tar -czf "$DATA_ROOT/backups/${BACKUP_NAME}.tar.gz" -C "$DATA_ROOT/backups" "$BACKUP_NAME"
    rm -rf "$BACKUP_PATH"

    log_success "Backup created: $DATA_ROOT/backups/${BACKUP_NAME}.tar.gz"

    # Show backup size
    BACKUP_SIZE=$(du -h "$DATA_ROOT/backups/${BACKUP_NAME}.tar.gz" | cut -f1)
    log_info "Backup size: $BACKUP_SIZE"

    read -p "Press Enter to continue..."
}

# =====================================================
# HELPER FUNCTIONS
# =====================================================

regenerate_litellm_config() {
    log_info "Regenerating LiteLLM configuration..."

    ROUTING_STRATEGY=$(jq -r '.strategy' "$METADATA_DIR/litellm_routing.json")

    cat > "$CONFIG_DIR/litellm_config.yaml" << 'LITELLM_HEADER'
model_list:
LITELLM_HEADER

    # Add local Ollama models
    OLLAMA_MODELS=($(jq -r '.models[]' "$METADATA_DIR/selected_services.json" 2>/dev/null))
    for model in "${OLLAMA_MODELS[@]}"; do
        cat >> "$CONFIG_DIR/litellm_config.yaml" << OLLAMA_MODEL
  - model_name: ollama/$model
    litellm_params:
      model: ollama/$model
      api_base: http://ollama:11434
OLLAMA_MODEL
    done

    # Add cloud providers
    PROVIDERS=($(jq -r '.providers[]?.name // empty' "$METADATA_DIR/llm_providers.json"))
    for provider in "${PROVIDERS[@]}"; do
        API_KEY=$(jq -r ".providers[] | select(.name==\"$provider\") | .api_key" "$METADATA_DIR/llm_providers.json")
        BASE_URL=$(jq -r ".providers[] | select(.name==\"$provider\") | .base_url" "$METADATA_DIR/llm_providers.json")

        case $provider in
            openai)
                cat >> "$CONFIG_DIR/litellm_config.yaml" << OPENAI_CONFIG
  - model_name: gpt-4
    litellm_params:
      model: openai/gpt-4
      api_key: $API_KEY
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: openai/gpt-3.5-turbo
      api_key: $API_KEY
OPENAI_CONFIG
                ;;

            anthropic)
                cat >> "$CONFIG_DIR/litellm_config.yaml" << ANTHROPIC_CONFIG
  - model_name: claude-3-opus
    litellm_params:
      model: anthropic/claude-3-opus-20240229
      api_key: $API_KEY
  - model_name: claude-3-sonnet
    litellm_params:
      model: anthropic/claude-3-sonnet-20240229
      api_key: $API_KEY
  - model_name: claude-3-haiku
    litellm_params:
      model: anthropic/claude-3-haiku-20240307
      api_key: $API_KEY
ANTHROPIC_CONFIG
                ;;

            gemini)
                cat >> "$CONFIG_DIR/litellm_config.yaml" << GEMINI_CONFIG
  - model_name: gemini-pro
    litellm_params:
      model: gemini/gemini-pro
      api_key: $API_KEY
GEMINI_CONFIG
                ;;

            groq)
                cat >> "$CONFIG_DIR/litellm_config.yaml" << GROQ_CONFIG
  - model_name: mixtral-8x7b
    litellm_params:
      model: groq/mixtral-8x7b-32768
      api_key: $API_KEY
  - model_name: llama2-70b
    litellm_params:
      model: groq/llama2-70b-4096
      api_key: $API_KEY
GROQ_CONFIG
                ;;
        esac
    done

    # Add routing configuration
    cat >> "$CONFIG_DIR/litellm_config.yaml" << ROUTING_CONFIG

router_settings:
  routing_strategy: $ROUTING_STRATEGY
  num_retries: 3
  timeout: 60
  fallbacks: true

litellm_settings:
  drop_params: true
  set_verbose: true
ROUTING_CONFIG

    log_success "LiteLLM configuration regenerated"
}

configure_model_mapping() {
    clear
    echo "Custom model mapping configuration"
    echo
    echo "Example: Map 'my-gpt4' to 'openai/gpt-4'"
    echo
    read -p "Enter alias name: " alias_name
    read -p "Enter actual model (e.g., openai/gpt-4): " actual_model

    if [ -z "$alias_name" ] || [ -z "$actual_model" ]; then
        log_warn "Both fields are required"
        sleep 2
        return
    fi

    # This would need to be added to litellm_config.yaml
    log_info "Adding model mapping to configuration..."

    cat >> "$CONFIG_DIR/litellm_config.yaml" << MODEL_MAP
  - model_name: $alias_name
    litellm_params:
      model: $actual_model
MODEL_MAP

    log_success "Model mapping added: $alias_name → $actual_model"

    # Reload LiteLLM
    docker compose -f "$COMPOSE_DIR/litellm.yml" restart

    read -p "Press Enter to continue..."
}

# =====================================================
# MAIN EXECUTION
# =====================================================

main() {
    show_banner
    check_prerequisites
    load_current_config
    show_main_menu
}

main "$@"
