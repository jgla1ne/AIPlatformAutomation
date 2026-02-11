#!/bin/bash
# 0-complete-cleanup.sh - Complete platform reset

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_ROOT="/mnt/data"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_banner() {
    cat << 'EOF'
╔════════════════════════════════════════════════════╗
║  🧹 AIPlatformAutomation - Complete Cleanup v76.5  ║
╚════════════════════════════════════════════════════╝
EOF
}

show_cleanup_summary() {
    log_info "Analyzing current installation..."
    
    RUNNING_CONTAINERS=$(docker ps -q | wc -l)
    COMPOSE_FILES=$(find "$DATA_ROOT/compose" -name "*.yml" 2>/dev/null | wc -l)
    TOTAL_SIZE=$(du -sh "$DATA_ROOT" 2>/dev/null | awk '{print $1}')
    
    # Check for Signal registration
    if [ -f "$DATA_ROOT/data/signal-api/.storage/data/accounts.json" ]; then
        SIGNAL_REGISTERED=true
        SIGNAL_NUMBER=$(jq -r '.[0].number' "$DATA_ROOT/data/signal-api/.storage/data/accounts.json" 2>/dev/null)
    else
        SIGNAL_REGISTERED=false
    fi
    
    # Check for GDrive auth
    if [ -f "$DATA_ROOT/config/rclone/rclone.conf" ]; then
        GDRIVE_CONFIGURED=true
    else
        GDRIVE_CONFIGURED=false
    fi
    
    cat << EOF

📊 Current Installation Summary:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🐳 Running containers: $RUNNING_CONTAINERS
  📦 Service definitions: $COMPOSE_FILES
  💾 Total disk usage: $TOTAL_SIZE
  📱 Signal registered: $([ "$SIGNAL_REGISTERED" = true ] && echo "✅ Yes ($SIGNAL_NUMBER)" || echo "❌ No")
  📁 GDrive configured: $([ "$GDRIVE_CONFIGURED" = true ] && echo "✅ Yes" || echo "❌ No")
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

prompt_cleanup_mode() {
    cat << 'EOF'
🚨 CLEANUP MODE SELECTION

  1) 🗑️  Full cleanup (delete everything)
  2) 💾 Preserve user data (/mnt/data/data)
  3) 📱 Preserve Signal registration
  4) 🔄 Preserve configs (Signal + GDrive + LiteLLM)
  5) 🔙 Backup then cleanup
  6) ❌ Cancel

EOF
    
    while true; do
        read -p "Enter selection [1-6]: " choice
        case $choice in
            1) CLEANUP_MODE="full"; break ;;
            2) CLEANUP_MODE="preserve-data"; break ;;
            3) CLEANUP_MODE="preserve-signal"; break ;;
            4) CLEANUP_MODE="preserve-configs"; break ;;
            5) 
                backup_before_cleanup
                CLEANUP_MODE="full"
                break
                ;;
            6) log_info "Cleanup cancelled"; exit 0 ;;
            *) log_error "Invalid choice" ;;
        esac
    done
}

backup_before_cleanup() {
    BACKUP_DIR="$DATA_ROOT/backups/$(date +%Y%m%d_%H%M%S)"
    log_info "Creating backup in $BACKUP_DIR..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup critical configs
    [ -d "$DATA_ROOT/data/signal-api" ] && cp -r "$DATA_ROOT/data/signal-api" "$BACKUP_DIR/"
    [ -f "$DATA_ROOT/config/litellm_config.yaml" ] && cp "$DATA_ROOT/config/litellm_config.yaml" "$BACKUP_DIR/"
    [ -f "$DATA_ROOT/config/rclone/rclone.conf" ] && cp "$DATA_ROOT/config/rclone/rclone.conf" "$BACKUP_DIR/"
    [ -d "$DATA_ROOT/metadata" ] && cp -r "$DATA_ROOT/metadata" "$BACKUP_DIR/"
    
    # Export environment variables
    if [ -d "$DATA_ROOT/env" ]; then
        cp -r "$DATA_ROOT/env" "$BACKUP_DIR/"
    fi
    
    log_info "✅ Backup completed: $BACKUP_DIR"
}

stop_all_containers() {
    log_info "🛑 Stopping all containers..."
    
    if [ -d "$DATA_ROOT/compose" ]; then
        # Stop in reverse dependency order
        for compose_file in \
            "$DATA_ROOT/compose/openclaw-ui.yml" \
            "$DATA_ROOT/compose/dify-web.yml" \
            "$DATA_ROOT/compose/dify-worker.yml" \
            "$DATA_ROOT/compose/dify-api.yml" \
            "$DATA_ROOT/compose/anythingllm.yml" \
            "$DATA_ROOT/compose/openwebui.yml" \
            "$DATA_ROOT/compose/flowise.yml" \
            "$DATA_ROOT/compose/n8n.yml" \
            "$DATA_ROOT/compose/litellm.yml" \
            "$DATA_ROOT/compose/signal-api.yml" \
            "$DATA_ROOT/compose/ollama.yml" \
            "$DATA_ROOT/compose/qdrant.yml" \
            "$DATA_ROOT/compose/milvus.yml" \
            "$DATA_ROOT/compose/chromadb.yml" \
            "$DATA_ROOT/compose/redis.yml" \
            "$DATA_ROOT/compose/postgres.yml" \
            "$DATA_ROOT/compose/swag.yml" \
            "$DATA_ROOT/compose/monitoring-stack.yml"; do
            
            if [ -f "$compose_file" ]; then
                SERVICE_NAME=$(basename "$compose_file" .yml)
                log_info "Stopping $SERVICE_NAME..."
                docker compose -f "$compose_file" down -v 2>/dev/null || true
            fi
        done
    fi
    
    # Force cleanup any remaining
    docker ps -aq | xargs -r docker rm -f 2>/dev/null || true
}

cleanup_docker_resources() {
    log_info "🐳 Cleaning Docker resources..."
    
    # Remove networks (except default bridge)
    docker network ls --format '{{.Name}}' | grep -v -E '^(bridge|host|none)$' | xargs -r docker network rm 2>/dev/null || true
    
    # Remove volumes
    docker volume ls -q | xargs -r docker volume rm 2>/dev/null || true
    
    # Prune system
    docker system prune -af --volumes 2>/dev/null || true
}

cleanup_filesystem() {
    local mode=$1
    log_info "📂 Cleaning filesystem (mode: $mode)..."
    
    case $mode in
        "full")
            log_warn "Removing ALL platform files..."
            rm -rf "$DATA_ROOT"/*
            ;;
            
        "preserve-data")
            log_warn "Preserving user data directory..."
            find "$DATA_ROOT" -mindepth 1 -maxdepth 1 ! -name 'data' -exec rm -rf {} + 2>/dev/null || true
            ;;
            
        "preserve-signal")
            log_warn "Preserving Signal registration..."
            TEMP_SIGNAL="/tmp/signal-backup-$$"
            [ -d "$DATA_ROOT/data/signal-api" ] && mv "$DATA_ROOT/data/signal-api" "$TEMP_SIGNAL"
            
            rm -rf "$DATA_ROOT"/*
            
            mkdir -p "$DATA_ROOT/data"
            [ -d "$TEMP_SIGNAL" ] && mv "$TEMP_SIGNAL" "$DATA_ROOT/data/signal-api"
            ;;
            
        "preserve-configs")
            log_warn "Preserving Signal, GDrive, and LiteLLM configs..."
            TEMP_DIR="/tmp/config-backup-$$"
            mkdir -p "$TEMP_DIR"
            
            [ -d "$DATA_ROOT/data/signal-api" ] && cp -r "$DATA_ROOT/data/signal-api" "$TEMP_DIR/"
            [ -f "$DATA_ROOT/config/litellm_config.yaml" ] && cp "$DATA_ROOT/config/litellm_config.yaml" "$TEMP_DIR/"
            [ -f "$DATA_ROOT/config/rclone/rclone.conf" ] && cp "$DATA_ROOT/config/rclone/rclone.conf" "$TEMP_DIR/"
            
            rm -rf "$DATA_ROOT"/*
            
            mkdir -p "$DATA_ROOT/data" "$DATA_ROOT/config/rclone"
            [ -d "$TEMP_DIR/signal-api" ] && mv "$TEMP_DIR/signal-api" "$DATA_ROOT/data/"
            [ -f "$TEMP_DIR/litellm_config.yaml" ] && mv "$TEMP_DIR/litellm_config.yaml" "$DATA_ROOT/config/"
            [ -f "$TEMP_DIR/rclone.conf" ] && mv "$TEMP_DIR/rclone.conf" "$DATA_ROOT/config/rclone/"
            
            rm -rf "$TEMP_DIR"
            ;;
    esac
}

unregister_signal() {
    if [ "$CLEANUP_MODE" = "full" ] && [ -f "$DATA_ROOT/data/signal-api/.storage/data/accounts.json" ]; then
        log_info "📱 Unregistering Signal device..."
        
        # This would require signal-cli to be running
        # For now, just inform the user
        log_warn "⚠️  Signal device registration data will be deleted"
        log_warn "   You'll need to re-pair with Signal on next setup"
    fi
}

show_cleanup_report() {
    cat << 'EOF'

╔════════════════════════════════════════════════════╗
║     ✅ CLEANUP COMPLETED SUCCESSFULLY              ║
╚════════════════════════════════════════════════════╝

📊 Cleanup Summary:
  ✓ Docker containers stopped and removed
  ✓ Docker networks cleaned
  ✓ Docker volumes removed
  ✓ Platform files cleaned

EOF

    if [ "$CLEANUP_MODE" != "full" ]; then
        cat << EOF
💾 Preserved Items:
EOF
        [ -d "$DATA_ROOT/data" ] && echo "  • User data directory"
        [ -d "$DATA_ROOT/data/signal-api" ] && echo "  • Signal registration"
        [ -f "$DATA_ROOT/config/litellm_config.yaml" ] && echo "  • LiteLLM routing config"
        [ -f "$DATA_ROOT/config/rclone/rclone.conf" ] && echo "  • GDrive authentication"
    fi
    
    cat << 'EOF'

🚀 Next Steps:
  • Run ./1-setup-system.sh to reinstall the platform
  • Your system is now in a clean state

EOF
}

main() {
    show_banner
    
    # Must run as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    show_cleanup_summary
    prompt_cleanup_mode
    
    # Final confirmation
    log_warn "⚠️  This will stop all services and remove files based on mode: $CLEANUP_MODE"
    read -p "Are you ABSOLUTELY sure? (type 'yes' to confirm): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
    
    unregister_signal
    stop_all_containers
    cleanup_docker_resources
    cleanup_filesystem "$CLEANUP_MODE"
    show_cleanup_report
}

main "$@"
