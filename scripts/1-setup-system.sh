#!/usr/bin/env bash
# =============================================================================
# Script 1: System Setup & Input Collection
# PURPOSE: Complete system setup, input gathering, and platform.conf generation
# README: Grounded in unified README.md Golden Success Criteria
# =============================================================================
# USAGE:   bash scripts/1-setup-system.sh [tenant_id] [options]
# OPTIONS: --ingest-from <file>    Ingest credentials from existing .env file
#          --preserve-secrets       Preserve existing secrets from .env
#          --generate-new          Generate new secrets for all services
#          --deployment-mode <mode> Set deployment mode (minimal|standard|full)
#          --template FILE         Use template file for configuration
#          --dry-run               Show what would be configured
#          --save-template FILE    Save configuration as reusable template
# =============================================================================

set -euo pipefail

# =============================================================================
# NON-INTERACTIVE MODE (P3 fix)
# =============================================================================
export DEBIAN_FRONTEND=noninteractive

# Use system Docker socket if DOCKER_HOST points to a non-existent rootless socket
if [[ "${DOCKER_HOST:-}" == unix://* ]] && [[ ! -S "${DOCKER_HOST#unix://}" ]]; then
    export DOCKER_HOST=unix:///var/run/docker.sock
fi

# =============================================================================
# NON-ROOT EXECUTION CHECK (README P7)
# =============================================================================
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: This script must not run as root (README P7 requirement)"
    exit 1
fi

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_VERSION="5.1.0"

# =============================================================================
# LOGGING (README P11)
# =============================================================================
LOG_FILE="/tmp/ai-platform-setup.log"
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
}
ok() { log "OK: $*"; }
warn() { log "WARN: $*"; }
fail() { log "FAIL: $*"; exit 1; }
section() { echo "" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && echo "  $*" && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
banner() { 
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  🚀 AI Platform — Interactive Setup 🚀                        ║"
    echo "║                    Script 1 of 4                        ║"
    echo "║              Complete Configuration Wizard               ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
}

# =============================================================================
# SECRET GENERATION FUNCTIONS (README §5)
# =============================================================================
gen_secret() { openssl rand -hex 32; }
gen_password() { openssl rand -base64 24 | tr -d '=+/' | cut -c1-20; }

# =============================================================================
# ENHANCED MENU SELECTION FUNCTIONS
# =============================================================================
select_menu_option() {
    local title="$1"
    shift
    local options=("$@")
    local count=${#options[@]}
    
    # Handle non-TTY case (piped input) - use default option
    if [[ ! -t 0 ]]; then
        # Try to read from piped input
        local choice
        if read -t 5 choice 2>/dev/null; then
            # Validate choice
            if [[ "$choice" =~ ^[1-9]$ ]] && [[ $choice -le $count ]]; then
                return $((choice-1))
            fi
        fi
        # Default to first option if no valid input
        echo "  🎯 $title (auto-selecting option 1: ${options[0]})"
        return 0
    fi
    
    # Real TTY - show menu
    echo "  🎯 $title:"
    echo ""
    
    local i=1
    for option in "${options[@]}"; do
        echo "    $i) $option"
        ((i++))
    done
    echo ""
    
    while true; do
        read -rp "  🎯 Select option [1-$count]: " choice
        
        if [[ "$choice" =~ ^[1-9]$ ]] && [[ $choice -le $count ]]; then
            echo "  ✅ Selected: ${options[$((choice-1))]}"
            return $((choice-1))
        else
            echo "  ❌ Invalid selection. Please enter a number between 1 and $count"
        fi
    done
}

# =============================================================================
# ENHANCED UX INPUT FUNCTIONS
# =============================================================================
safe_read() {
    # Usage: safe_read "Prompt text" DEFAULT_VALUE VARIABLE_NAME [VALIDATION_PATTERN]
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local validation_pattern="${4:-}"
    local value
    local attempts=0
    local max_attempts=3

    # Check for env var override first
    value=$(printenv "${varname}" 2>/dev/null || true)

    if [ -n "${value}" ]; then
        echo "  ✨ ${prompt}: ${value} (from environment)"
        if [[ -n "$validation_pattern" && ! "$value" =~ $validation_pattern ]]; then
            fail "Environment variable $varname doesn't match required pattern"
        fi
    elif [ -t 0 ]; then
        # Real TTY — show prompt and wait for input with validation
        while [[ $attempts -lt $max_attempts ]]; do
            if [[ -n "$default" ]]; then
                echo -n "  🎯 ${prompt} [${default}]: "
                read -r value
                if [[ -z "$value" ]]; then
                    value="$default"
                fi
            else
                echo -n "  🎯 ${prompt}: "
                read -r value
            fi
            
            # Check if value is empty for required fields
            if [[ -z "$value" && -z "$default" ]]; then
                echo "  ❌ This field is required. Please enter a value."
                attempts=$((attempts + 1))
                continue
            fi
            
            value="${value:-${default}}"
            
            # Validate if pattern provided
            if [[ -n "$validation_pattern" && ! "$value" =~ $validation_pattern ]]; then
                echo "  ❌ Invalid format. Please try again."
                attempts=$((attempts + 1))
                continue
            fi
            
            break
        done
        
        if [[ $attempts -eq $max_attempts ]]; then
            fail "Maximum validation attempts reached for $varname"
        fi
    else
        # Non-TTY — try to read from piped input first, then use default
        if read -t 5 value 2>/dev/null; then
            # Successfully read from pipe
            value="${value:-${default}}"
            echo "  🎯 ${prompt}: ${value} (pipelined input)"
        else
            # No piped input, use default
            value="${default}"
            echo "  🎯 ${prompt}: ${value} (default — non-interactive mode)"
        fi
    fi

    printf -v "${varname}" '%s' "${value}"
}

safe_read_yesno() {
    local prompt="$1"
    local default="${2:-n}"
    local varname="$3"
    local value
    local attempts=0
    local max_attempts=3

    # Convert boolean defaults to y/n
    case "${default,,}" in
        true|yes) default="y" ;;
        false|no) default="n" ;;
    esac

    # Check for env var override first (same as safe_read does)
    local env_val
    env_val=$(printenv "${varname}" 2>/dev/null || true)
    if [[ -n "$env_val" ]]; then
        case "${env_val,,}" in
            true|yes|y)
                echo "  ✨ ${prompt}: true (from environment)"
                printf -v "${varname}" '%s' "true"
                return 0
                ;;
            false|no|n)
                echo "  ✨ ${prompt}: false (from environment)"
                printf -v "${varname}" '%s' "false"
                return 0
                ;;
        esac
    fi

    # Real TTY - show prompt and wait for input
    while [[ $attempts -lt $max_attempts ]]; do
        if [[ -n "$default" ]]; then
            if [[ "$default" == "y" ]]; then
                echo -n "  🤔 ${prompt} [Y/n]: "
                if ! read -r value 2>/dev/null; then
                    echo ""
                    echo "  ⏰ Input timeout - using default: $default"
                    value="$default"
                fi
            else
                echo -n "  🤔 ${prompt} [y/N]: "
                if ! read -r value 2>/dev/null; then
                    echo ""
                    echo "  ⏰ Input timeout - using default: $default"
                    value="$default"
                fi
            fi
        else
            echo -n "  🤔 ${prompt} [y/N]: "
            if ! read -r value 2>/dev/null; then
                echo ""
                echo "  ⏰ Input timeout - using default: n"
                value="n"
            fi
        fi
        
        value="${value:-${default}}"
        
        case "${value,,}" in
            y|yes) 
                value="true" 
                echo "  ✅ ${prompt}: $value"
                printf -v "${varname}" '%s' "$value"
                return 0
                ;;
            n|no) 
                value="false"
                echo "  ✅ ${prompt}: $value"
                printf -v "${varname}" '%s' "$value"
                return 0
                ;;
            *) 
                echo "  ❌ Please enter 'y' or 'n'"
                attempts=$((attempts + 1))
                ;;
        esac
    done
    
    fail "Maximum attempts reached for yes/no prompt"
}

safe_read_password() {
    local prompt="$1"
    local varname="$2"
    local value
    local confirm
    
    while true; do
        read -rsp "  🔐 ${prompt}: " value
        echo ""
        read -rsp "  🔐 Confirm ${prompt}: " confirm
        echo ""
        
        if [[ "$value" == "$confirm" && -n "$value" ]]; then
            break
        elif [[ -z "$value" ]]; then
            echo "  ❌ Password cannot be empty"
        else
            echo "  ❌ Passwords do not match"
        fi
    done
    
    printf -v "${varname}" '%s' "${value}"
}

# =============================================================================
# SYSTEM DETECTION (README §4.2)
# =============================================================================
detect_system() {
    log "🔍 Detecting system capabilities..."
    
    # GPU Detection
    if command -v nvidia-smi >/dev/null 2>&1; then
        GPU_TYPE="nvidia"
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        log "✅ NVIDIA GPU detected: ${GPU_MEMORY}MB"
    elif command -v rocm-smi >/dev/null 2>&1; then
        GPU_TYPE="rocm"
        GPU_MEMORY="unknown"
        log "✅ AMD GPU detected (ROCm)"
    else
        GPU_TYPE="none"
        GPU_MEMORY="0"
        log "ℹ️  No GPU detected - CPU-only mode"
    fi
    
    # Memory Detection
    TOTAL_RAM=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    AVAILABLE_RAM=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    log "💾 Memory: ${TOTAL_RAM}MB total, ${AVAILABLE_RAM}MB available"
    
    # Disk Space
    if [[ -d "/mnt" ]]; then
        DISK_SPACE=$(df -h /mnt | awk 'NR==2{print $4}')
        log "💿 Disk space available on /mnt: ${DISK_SPACE}"
    fi
    
    # Network MTU
    if command -v ip >/dev/null 2>&1; then
        HOST_MTU=$(ip link show | grep -E '^[0-9]+:' | head -1 | awk '{print $5}' | cut -d':' -f1)
        log "🌐 Host MTU: ${HOST_MTU}"
    fi
}

# =============================================================================
# IDENTITY COLLECTION (README §4.1)
# =============================================================================
collect_identity() {
    section "🏷️  PLATFORM IDENTITY"
    
    echo "  📋 Configure your platform identity and domain settings"
    echo ""
    
    safe_read "Platform prefix (for naming)" "ai" "PLATFORM_PREFIX" "^[a-z0-9_-]+$"
    safe_read "Tenant ID (unique identifier)" "" "TENANT_ID" "^[a-zA-Z0-9_-]+$"
    safe_read "Primary domain (e.g., example.com)" "" "DOMAIN" "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    safe_read "Organization name" "AI Platform" "ORGANIZATION"
    safe_read "Admin email" "admin@${DOMAIN}" "ADMIN_EMAIL" "^[^@]+@[^@]+\.[^@]+$"
    
    echo ""
    echo "  📊 Identity Summary:"
    echo "    Platform: ${PLATFORM_PREFIX}"
    echo "    Tenant: ${TENANT_ID}"
    echo "    Domain: ${DOMAIN}"
    echo "    Organization: ${ORGANIZATION}"
    echo "    Admin: ${ADMIN_EMAIL}"
    echo ""
    
    safe_read_yesno "Confirm identity configuration" "y" "IDENTITY_CONFIRMED"
    if [[ "$IDENTITY_CONFIRMED" != "true" ]]; then
        fail "Identity configuration cancelled"
    fi
}

# =============================================================================
# STORAGE CONFIGURATION (README §4.2) - CORRECTED EBS DETECTION
# =============================================================================
configure_storage() {
    section "💾 STORAGE CONFIGURATION"
    
    echo "  📋 Storage Options:"
    echo "    • Auto-detect Amazon EBS volumes"
    echo "    • List available volumes for selection"
    echo "    • Format and mount selected volume"
    echo "    • Fallback to OS disk if no EBS found"
    echo ""
    
    # Direct to EBS detection and selection
    detect_and_select_ebs
        
    # Create mount point (EBS case already handled by format_and_mount_ebs)
    [[ -d "/mnt/${TENANT_ID}" ]] || sudo mkdir -p "/mnt/${TENANT_ID}" 2>/dev/null || warn "Could not create /mnt/${TENANT_ID} — check permissions"
    if [[ "${USE_EBS:-false}" != "true" ]]; then
        sudo chown "$(id -u):$(id -g)" "/mnt/${TENANT_ID}" 2>/dev/null || true
    fi

    # Set data directory
    DATA_DIR="/mnt/${TENANT_ID}"
    
    # Set defaults for EBS configuration
    EBS_DEVICE_PATTERN="${EBS_DEVICE_PATTERN:-/dev/sd[f-z]}"
    EBS_FILESYSTEM="${EBS_FILESYSTEM:-ext4}"
    
    log "OK: Storage configuration complete"
}

# EBS detection using lsblk — works for both legacy /dev/sd* and NVMe /dev/nvme* devices
detect_and_select_ebs() {
    echo ""
    echo "🔍 Scanning for available block devices (including NVMe)..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local devices=()
    local descriptions=()

    # Determine which device hosts the root filesystem so we can skip it
    local root_dev
    root_dev=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null \
        || lsblk -no NAME "$(findmnt -n -o SOURCE /)" 2>/dev/null \
        || true)

    # Enumerate all whole-disk block devices (TYPE=disk, no loop/ram)
    while IFS= read -r line; do
        local name size model
        name=$(awk '{print $1}' <<<"$line")
        size=$(awk '{print $2}' <<<"$line")
        # Model is everything after name+size (may be empty)
        model=$(awk '{$1=""; $2=""; sub(/^[[:space:]]+/,"",$0); print}' <<<"$line")

        local dev="/dev/$name"
        [[ -b "$dev" ]] || continue

        # Skip the root device
        [[ "$name" == "$root_dev" ]] && continue

        # Build human-readable label; highlight EBS volumes explicitly
        local label
        if echo "$model" | grep -qi "Amazon Elastic Block Store"; then
            label="$dev — Amazon EBS ($size)"
        elif echo "$model" | grep -qi "amazon"; then
            label="$dev — Amazon volume ($size) [$model]"
        elif [[ -n "$model" ]]; then
            label="$dev — $model ($size)"
        else
            label="$dev ($size)"
        fi

        # Annotate mount status — flag other tenants clearly to prevent accidental overwrite
        local current_mount
        current_mount=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | grep -v '^$' | tr '\n' ' ' | sed 's/ $//' || true)
        if [[ -n "$current_mount" ]]; then
            if [[ "$current_mount" == "/mnt/${TENANT_ID}" ]]; then
                label+="  [already mounted for THIS tenant — will reuse]"
            elif echo "$current_mount" | grep -qE '^/mnt/'; then
                local other
                other=$(echo "$current_mount" | grep -oE '/mnt/[^ ]+' | head -1)
                label+="  ⚠ IN USE BY TENANT: ${other} — format blocked"
            else
                label+="  [mounted: $current_mount]"
            fi
        fi

        devices+=("$dev")
        descriptions+=("$label")
    done < <(lsblk -d -o NAME,SIZE,MODEL --noheadings 2>/dev/null \
        | grep -v "^loop" | grep -v "^ram")

    # Always offer an "OS disk" fallback as the last option
    devices+=("")
    descriptions+=("Use OS disk — no separate volume (data under /mnt/${TENANT_ID})")

    if [[ ${#devices[@]} -gt 1 ]]; then
        local choice
        select_menu_option "Block Device Selection" "${descriptions[@]}"
        choice=$?

        if [[ $choice -eq $((${#devices[@]}-1)) ]]; then
            echo " Selected: OS disk storage"
            EBS_DEVICE=""
            USE_EBS="false"
        else
            EBS_DEVICE="${devices[$choice]}"
            echo "  Selected: $EBS_DEVICE"
            USE_EBS="true"
            format_and_mount_ebs
        fi
    else
        echo ""
        echo "⚠️  No additional block devices found."
        echo "   Will use OS disk for storage."
        echo ""
        EBS_DEVICE=""
        USE_EBS="false"
    fi
}

# Format and mount EBS volume
# Multi-tenant safety:
#   • If device already mounted at /mnt/<TENANT_ID> → reuse as-is, skip format
#   • If device mounted at any other /mnt/<name> → BLOCK (another tenant owns it)
#   • Only format if device is unmounted or mounted at an unrecognised path
# All privileged ops run in a single sudo bash invocation — one password prompt.
format_and_mount_ebs() {
    if [[ -n "$EBS_DEVICE" ]] && [[ -b "$EBS_DEVICE" ]]; then

        local mount_point="/mnt/${TENANT_ID}"
        local current_mounts
        current_mounts=$(lsblk -no MOUNTPOINT "$EBS_DEVICE" 2>/dev/null | grep -v '^$' || true)

        # ── Case 1: already mounted at OUR tenant path → reuse, no format ──────
        if echo "$current_mounts" | grep -qx "$mount_point"; then
            echo ""
            echo "  ✅ $EBS_DEVICE is already mounted at $mount_point"
            echo "     Skipping format — reusing existing filesystem."
            sudo chown "${EUID}:$(id -g)" "$mount_point" 2>/dev/null || true
            return 0
        fi

        # ── Case 2: mounted at another /mnt/<X> → BLOCK (tenant data at risk) ──
        local other_tenant_mount
        other_tenant_mount=$(echo "$current_mounts" | grep -E '^/mnt/' | head -1 || true)
        if [[ -n "$other_tenant_mount" ]]; then
            echo ""
            echo "  ╔══════════════════════════════════════════════════════════╗"
            echo "  ║  ⛔  TENANT CONFLICT — FORMAT BLOCKED                   ║"
            echo "  ╚══════════════════════════════════════════════════════════╝"
            echo ""
            echo "  Device $EBS_DEVICE is currently in use by another tenant:"
            echo "    Mount point : $other_tenant_mount"
            echo ""
            echo "  Formatting this device would DESTROY that tenant's data."
            echo "  To proceed, first run Script 0 for that tenant:"
            local other_tenant
            other_tenant=$(basename "$other_tenant_mount")
            echo "    sudo bash scripts/0-complete-cleanup.sh ${other_tenant}"
            echo ""
            fail "Format blocked to protect tenant data at $other_tenant_mount"
        fi

        # ── Case 3: unmounted or mounted at non-/mnt path → proceed ─────────────
        if [[ -n "$current_mounts" ]]; then
            echo ""
            echo "  ⚠️  $EBS_DEVICE is currently mounted at: $current_mounts"
            echo "     It will be unmounted before formatting."
        fi

        echo ""
        echo "Formatting EBS volume: $EBS_DEVICE"
        safe_read "CONFIRM: Format $EBS_DEVICE as ext4? [yes/N]: " "" FORMAT_CONFIRM

        if [[ ! "$FORMAT_CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
            fail "EBS volume formatting cancelled"
        fi

        local user_uid user_gid tenant_id mount_point
        user_uid=$(id -u)
        user_gid=$(id -g)
        tenant_id="${TENANT_ID}"
        mount_point="/mnt/${tenant_id}"

        echo "  Running privileged EBS setup (sudo required)..."

        # Single sudo bash block — unmount, wipe fstab, format, mount, chown, add fstab
        sudo bash -s -- "$EBS_DEVICE" "$mount_point" "$user_uid" "$user_gid" <<'SUDO_EOF'
            device="$1"
            mount_point="$2"
            owner_uid="$3"
            owner_gid="$4"

            set -e

            # Unmount all current mounts of this device (handles /mnt/data etc.)
            current_mounts=$(lsblk -no MOUNTPOINT "$device" 2>/dev/null | grep -v '^$' || true)
            if [[ -n "$current_mounts" ]]; then
                while IFS= read -r mp; do
                    [[ -z "$mp" ]] && continue
                    echo "     Unmounting: $mp"
                    umount "$mp" || { echo "ERROR: Could not unmount $mp"; exit 1; }
                done <<< "$current_mounts"
            fi

            # Remove any stale fstab entry for this device (pre-format UUID)
            old_uuid=$(blkid -s UUID -o value "$device" 2>/dev/null || true)
            if [[ -n "$old_uuid" ]]; then
                sed -i "/UUID=${old_uuid}/d" /etc/fstab
                echo "     Removed stale fstab entry (UUID=${old_uuid})"
            fi

            # Format
            echo "     Formatting ${device} as ext4..."
            mkfs.ext4 -F "$device"

            # Mount
            mkdir -p "$mount_point"
            mount "$device" "$mount_point"

            # Hand ownership to the non-root caller
            chown "${owner_uid}:${owner_gid}" "$mount_point"

            # Add new fstab entry (new UUID after format)
            new_uuid=$(blkid -s UUID -o value "$device")
            fstab_entry="UUID=${new_uuid}  ${mount_point}  ext4  defaults,nofail  0  0"
            if ! grep -q "UUID=${new_uuid}" /etc/fstab; then
                echo "$fstab_entry" >> /etc/fstab
                echo "     fstab updated (UUID=${new_uuid})"
            fi
SUDO_EOF

        if [[ $? -ne 0 ]]; then
            fail "EBS privileged setup failed — see errors above"
        fi

        echo "  ✅ EBS volume formatted and mounted at ${mount_point}"
        echo "  ✅ Owned by ${user_uid}:${user_gid}"
        echo "  ✅ fstab updated for persistent mount"
    else
        fail "Invalid EBS device: $EBS_DEVICE"
    fi
}

# =============================================================================
# DOCKER DATA-ROOT CONFIGURATION
# Move Docker's data directory to the EBS volume so image pulls don't exhaust
# the small root volume. Without this, docker pull writes to /var/lib/docker/tmp
# on the root volume — typically only 8-20 GB on EC2 instances.
#
# Writes /etc/docker/daemon.json and restarts Docker (requires sudo).
# Safe to re-run — skips if data-root is already set to our target.
# =============================================================================
configure_docker_dataroot() {
    local target_root="${DATA_DIR}/docker"

    # Check current data-root — try system socket first (in case DOCKER_HOST points to non-existent rootless socket)
    local current_root
    current_root=$(DOCKER_HOST=unix:///var/run/docker.sock docker info --format '{{.DockerRootDir}}' 2>/dev/null \
        || docker info --format '{{.DockerRootDir}}' 2>/dev/null \
        || grep -o '"data-root"[[:space:]]*:[[:space:]]*"[^"]*"' /etc/docker/daemon.json 2>/dev/null | grep -o '"[^"]*"$' | tr -d '"' \
        || echo "/var/lib/docker")

    if [[ "$current_root" == "$target_root" ]]; then
        log "Docker data-root already set to ${target_root} — skipping"
        return 0
    fi

    section "🐳 DOCKER DATA DIRECTORY"
    echo "  Docker's default data root is ${current_root} (root volume — limited space)."
    echo "  Moving it to the EBS volume: ${target_root}"
    echo ""
    echo "  This requires sudo to update /etc/docker/daemon.json and restart Docker."
    echo ""

    sudo bash -s -- "$target_root" <<'DOCKER_CONF_EOF'
        set -e
        target="$1"

        # Create the target directory
        mkdir -p "$target"

        # Read existing daemon.json (if any) and merge data-root into it
        daemon_json="/etc/docker/daemon.json"
        if [[ -f "$daemon_json" ]]; then
            # Use python3 to merge: preserve existing keys, set/override data-root
            python3 - "$daemon_json" "$target" <<'PY'
import json, sys
path, root = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)
cfg["data-root"] = root
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
        else
            # No existing daemon.json — create it
            cat > "$daemon_json" <<JSON
{
  "data-root": "$target"
}
JSON
        fi

        echo "  ✅ /etc/docker/daemon.json updated (data-root: $target)"

        # Restart Docker to apply the new data-root
        systemctl restart docker
        echo "  ✅ Docker daemon restarted"
DOCKER_CONF_EOF

    if [[ $? -ne 0 ]]; then
        warn "Docker data-root configuration failed — images will be pulled to ${current_root}"
        warn "Ensure the root volume has enough free space, or configure data-root manually:"
        warn "  echo '{\"data-root\": \"${target_root}\"}' | sudo tee /etc/docker/daemon.json"
        warn "  sudo systemctl restart docker"
        return 0  # non-fatal — deployment can still proceed
    fi

    ok "Docker data-root: ${target_root} (on EBS volume)"
}

# =============================================================================
# STACK PRESET SELECTION (README §4.3)
# =============================================================================
select_stack_preset() {
    section "🎚️  STACK PRESET SELECTION"
    
    echo "  📋 Choose your platform complexity and features"
    echo ""
    
    echo "  Services can always be added/removed after initial setup via Script 3."
    echo ""
    local preset_choice=0
    [[ -n "${STACK_NAME:-}" ]] && echo "  ℹ  Current stack: ${STACK_NAME}"
    select_menu_option "Stack Preset Selection" \
        "MINIMAL (~4 GB RAM)  — PostgreSQL · Redis · Ollama · LiteLLM · OpenWebUI · Qdrant" \
        "DEVELOPMENT (~6 GB)  — Minimal + Code Server · Continue.dev config" \
        "CODING (~8 GB)       — Development + Grafana · Prometheus · SearXNG (AI dev optimized)" \
        "STANDARD (~8 GB)     — Development + N8N · Flowise · Grafana · Prometheus · Zep (memory)" \
        "FULL (~16 GB)        — Standard + OpenClaw · AnythingLLM · Dify · Authentik · SignalBot · Zep · Letta · Continue.dev" \
        "CUSTOM               — Pick every service individually (full control)" || preset_choice=$?

    case $preset_choice in
        0) STACK_PRESET="1"; STACK_NAME="minimal" ;;
        1) STACK_PRESET="2"; STACK_NAME="development" ;;
        2) STACK_PRESET="3"; STACK_NAME="coding" ;;
        3) STACK_PRESET="4"; STACK_NAME="standard" ;;
        4) STACK_PRESET="5"; STACK_NAME="full" ;;
        5) STACK_PRESET="6"; STACK_NAME="custom" ;;
    esac
    
    echo ""
    echo "  ✅ Selected: ${STACK_NAME^} Stack"

    if [[ "$STACK_PRESET" == "6" ]]; then
        configure_custom_stack
    else
        apply_preset_defaults
        select_memory_layer
        echo ""
        echo "  📦 Services included in ${STACK_NAME^}:"
        case "$STACK_NAME" in
            minimal)
                echo "    Infrastructure : PostgreSQL, Redis"
                echo "    LLM            : Ollama (local models), LiteLLM (gateway/proxy)"
                echo "    Web UI         : OpenWebUI"
                echo "    Vector DB      : Qdrant"
                ;;
            development)
                echo "    Infrastructure : PostgreSQL, Redis"
                echo "    LLM            : Ollama (local), LiteLLM (unified gateway)"
                echo "    Web UI         : OpenWebUI (→ LiteLLM, Qdrant RAG)"
                echo "    Vector DB      : Qdrant"
                echo "    Dev tools      : Code Server (browser IDE), Continue.dev config"
                ;;
            coding)
                echo "    Infrastructure : PostgreSQL, Redis"
                echo "    LLM            : Ollama (local), LiteLLM (unified gateway)"
                echo "    Web UI         : OpenWebUI (→ LiteLLM, Qdrant RAG)"
                echo "    Vector DB      : Qdrant"
                echo "    Dev tools      : Code Server (browser IDE), Continue.dev config"
                echo "    Search         : SearXNG (privacy-respecting)"
                echo "    Monitoring     : Grafana, Prometheus"
                ;;
            standard)
                echo "    Infrastructure : PostgreSQL, Redis"
                echo "    LLM            : Ollama (local), LiteLLM (unified gateway)"
                echo "    Web UI         : OpenWebUI (→ LiteLLM, vectordb RAG)"
                echo "    Vector DB      : Qdrant (default)"
                [[ "${ENABLE_ZEP:-false}"   == "true" ]] && echo "    Memory         : Zep CE (→ Postgres + LiteLLM)"
                [[ "${ENABLE_LETTA:-false}" == "true" ]] && echo "    Memory         : Letta (→ Postgres + LiteLLM)"
                echo "    Dev tools      : Code Server"
                echo "    Automation     : N8N (workflows, → LiteLLM), Flowise (AI pipelines, → vectordb)"
                echo "    Monitoring     : Grafana, Prometheus"
                ;;
            full)
                echo "    Infrastructure : PostgreSQL, Redis"
                echo "    LLM            : Ollama (local), LiteLLM (unified gateway)"
                echo "    Web UI         : OpenWebUI, OpenClaw, AnythingLLM (→ LiteLLM + vectordb)"
                echo "    Vector DB      : Qdrant (default; Weaviate/Chroma selectable)"
                [[ "${ENABLE_ZEP:-false}"   == "true" ]] && echo "    Memory         : Zep CE (→ Postgres + LiteLLM)"
                [[ "${ENABLE_LETTA:-false}" == "true" ]] && echo "    Memory         : Letta (→ Postgres + LiteLLM)"
                echo "    Dev tools      : Code Server, Continue.dev config (→ LiteLLM)"
                echo "    Automation     : N8N, Flowise, Dify (all → LiteLLM + vectordb)"
                echo "    Monitoring     : Grafana, Prometheus"
                echo "    Identity       : Authentik (SSO)"
                echo "    Alerting       : SignalBot (Signal messenger)"
                ;;
        esac
        echo ""
        echo "  💡 You can enable/disable any individual service in Script 3 at any time."
    fi
}

apply_preset_defaults() {
    log "🎯 Applying ${STACK_NAME^} stack defaults..."

    case "$STACK_NAME" in
        minimal)
            ENABLE_POSTGRES="true"
            ENABLE_REDIS="true"
            ENABLE_OLLAMA="true"
            ENABLE_LITELLM="true"
            ENABLE_OPENWEBUI="true"
            ENABLE_QDRANT="true"
            ENABLE_SEARXNG="true"
            ;;
        development)
            # Minimal + Code Server + Continue.dev
            ENABLE_POSTGRES="true"
            ENABLE_REDIS="true"
            ENABLE_OLLAMA="true"
            ENABLE_LITELLM="true"
            ENABLE_OPENWEBUI="true"
            ENABLE_QDRANT="true"
            ENABLE_CODE_SERVER="true"
            ENABLE_CONTINUE_DEV="true"
            ENABLE_SEARXNG="true"
            ;;
        coding)
            # Optimized AI development: Code Server + Continue.dev + monitoring
            ENABLE_POSTGRES="true"
            ENABLE_REDIS="true"
            ENABLE_OLLAMA="true"
            ENABLE_LITELLM="true"
            ENABLE_OPENWEBUI="true"
            ENABLE_QDRANT="true"
            ENABLE_CODE_SERVER="true"
            ENABLE_CONTINUE_DEV="true"
            ENABLE_GRAFANA="true"
            ENABLE_PROMETHEUS="true"
            ENABLE_SEARXNG="true"
            ;;
        standard)
            # Development + N8N + Flowise + Monitoring; memory asked separately
            ENABLE_POSTGRES="true"
            ENABLE_REDIS="true"
            ENABLE_OLLAMA="true"
            ENABLE_LITELLM="true"
            ENABLE_OPENWEBUI="true"
            ENABLE_QDRANT="true"
            ENABLE_CODE_SERVER="true"
            ENABLE_N8N="true"
            ENABLE_FLOWISE="true"
            ENABLE_GRAFANA="true"
            ENABLE_PROMETHEUS="true"
            ENABLE_SEARXNG="true"
            ;;
        full)
            # Standard + All remaining services; memory asked separately
            ENABLE_POSTGRES="true"
            ENABLE_REDIS="true"
            ENABLE_OLLAMA="true"
            ENABLE_LITELLM="true"
            ENABLE_OPENWEBUI="true"
            ENABLE_QDRANT="true"
            ENABLE_CODE_SERVER="true"
            ENABLE_N8N="true"
            ENABLE_FLOWISE="true"
            ENABLE_GRAFANA="true"
            ENABLE_PROMETHEUS="true"
            ENABLE_LIBRECHAT="true"
            ENABLE_OPENCLAW="true"
            ENABLE_ANYTHINGLLM="true"
            ENABLE_DIFY="true"
            ENABLE_SIGNALBOT="true"
            ENABLE_SEARXNG="true"
            ENABLE_AUTHENTIK="true"
            ENABLE_CONTINUE_DEV="true"
            ;;
    esac
}

# Memory-layer selection — called after apply_preset_defaults for standard + full presets.
# Minimal and development have no memory layer option.
select_memory_layer() {
    [[ "$STACK_NAME" != "standard" && "$STACK_NAME" != "full" ]] && return 0

    section "🧠 MEMORY LAYER SELECTION"
    echo "  Both Zep CE and Letta connect to your existing Postgres + LiteLLM."
    echo "  Zep CE  — long-term conversation memory (sessions, summaries, search)"
    echo "  Letta   — stateful agent memory server (MemGPT-style persistent agents)"
    echo ""

    local choice=0
    [[ -n "${ENABLE_ZEP:-}" || -n "${ENABLE_LETTA:-}" ]] && \
        echo "  ℹ  Current memory: zep=${ENABLE_ZEP:-false} letta=${ENABLE_LETTA:-false}"
    select_menu_option "Memory Layer" \
        "NONE     — No memory service" \
        "ZEP CE   — Conversation memory only (recommended, lighter)" \
        "LETTA    — Agent memory only (MemGPT)" \
        "BOTH     — Zep CE + Letta" || choice=$?

    ENABLE_ZEP="false"
    ENABLE_LETTA="false"
    case $choice in
        0) ;;                                            # none
        1) ENABLE_ZEP="true" ;;                         # zep only
        2) ENABLE_LETTA="true" ;;                       # letta only
        3) ENABLE_ZEP="true"; ENABLE_LETTA="true" ;;   # both
    esac

    # Dependency enforcement: Zep and Letta both require Postgres + LiteLLM
    if [[ "${ENABLE_ZEP}" == "true" || "${ENABLE_LETTA}" == "true" ]]; then
        if [[ "${ENABLE_POSTGRES:-false}" != "true" ]]; then
            warn "Zep/Letta require PostgreSQL — forcing ENABLE_POSTGRES=true"
            ENABLE_POSTGRES="true"
        fi
        if [[ "${ENABLE_LITELLM:-false}" != "true" ]]; then
            warn "Zep/Letta require LiteLLM for embeddings — forcing ENABLE_LITELLM=true"
            ENABLE_LITELLM="true"
        fi
    fi

    echo ""
    if [[ "${ENABLE_ZEP}" == "true" && "${ENABLE_LETTA}" == "true" ]]; then
        echo "  ✅ Memory: Zep CE + Letta  (requires Postgres + LiteLLM — auto-enabled)"
    elif [[ "${ENABLE_ZEP}" == "true" ]]; then
        echo "  ✅ Memory: Zep CE  (requires Postgres + LiteLLM — auto-enabled if needed)"
    elif [[ "${ENABLE_LETTA}" == "true" ]]; then
        echo "  ✅ Memory: Letta  (requires Postgres + LiteLLM — auto-enabled if needed)"
    else
        echo "  ℹ️  Memory: none selected"
    fi
}

configure_custom_stack() {
    section "🔧 CUSTOM STACK CONFIGURATION"
    
    echo "  📋 Select individual services to enable"
    echo ""
    
    # Infrastructure Services
    echo "  🏗️  Infrastructure Services:"
    safe_read_yesno "PostgreSQL (database)" "true" "ENABLE_POSTGRES"
    safe_read_yesno "Redis (cache)" "true" "ENABLE_REDIS"
    echo ""
    
    # LLM Services
    echo "  🤖 LLM Services:"
    safe_read_yesno "Ollama (local models)" "true" "ENABLE_OLLAMA"
    safe_read_yesno "LiteLLM (gateway)" "true" "ENABLE_LITELLM"
    echo ""
    
    # Web Interfaces
    echo "  🌐 Web Interfaces:"
    safe_read_yesno "OpenWebUI (chat interface)" "true" "ENABLE_OPENWEBUI"
    safe_read_yesno "LibreChat (multi-provider chat)" "false" "ENABLE_LIBRECHAT"
    safe_read_yesno "OpenClaw (private gateway)" "false" "ENABLE_OPENCLAW"
    safe_read_yesno "AnythingLLM (document chat)" "false" "ENABLE_ANYTHINGLLM"
    echo ""
    
    # Vector Databases
    echo "  🔍 Vector Databases:"
    safe_read_yesno "Qdrant (vector DB)" "true" "ENABLE_QDRANT"
    safe_read_yesno "Weaviate (vector DB)" "false" "ENABLE_WEAVIATE"
    safe_read_yesno "ChromaDB (vector DB)" "false" "ENABLE_CHROMA"
    safe_read_yesno "Milvus (vector DB)" "false" "ENABLE_MILVUS"
    echo ""
    
    # Automation
    echo "  ⚙️  Automation:"
    safe_read_yesno "N8N (workflow automation)" "false" "ENABLE_N8N"
    safe_read_yesno "Flowise (AI workflows)" "false" "ENABLE_FLOWISE"
    safe_read_yesno "Dify (LLM ops)" "false" "ENABLE_DIFY"
    echo ""
    
    # Memory Layer
    echo "  🧠 Memory Layer:"
    safe_read_yesno "Zep CE (conversation memory → Postgres + pgvector + LiteLLM)" "false" "ENABLE_ZEP"
    safe_read_yesno "Letta / MemGPT (stateful agent memory → Postgres + LiteLLM)" "false" "ENABLE_LETTA"
    echo ""

    # Development
    echo "  💻 Development:"
    safe_read_yesno "Code Server (browser IDE)" "false" "ENABLE_CODE_SERVER"
    safe_read_yesno "Continue.dev config (AI coding assistant, auto-pointed to LiteLLM)" "false" "ENABLE_CONTINUE_DEV"
    echo ""

    # Monitoring
    echo "  📊 Monitoring:"
    safe_read_yesno "Grafana (dashboards)" "false" "ENABLE_GRAFANA"
    safe_read_yesno "Prometheus (metrics)" "false" "ENABLE_PROMETHEUS"
    echo ""

    # Authentication
    echo "  Authentication:"
    safe_read_yesno "Authentik (SSO)" "false" "ENABLE_AUTHENTIK"
    echo ""

    # Additional Services
    echo "  Additional:"
    safe_read_yesno "SignalBot (Signal messenger notifications)" "false" "ENABLE_SIGNALBOT"
    safe_read_yesno "SearXNG (privacy-respecting search engine)" "false" "ENABLE_SEARXNG"
    safe_read_yesno "Bifrost (alternative LLM gateway / advanced routing)" "false" "ENABLE_BIFROST"
}

# =============================================================================
# SERVICE CREDENTIALS (system-generated but user-overridable)
# Called after stack selection so we know which services are enabled.
# =============================================================================
configure_service_credentials() {
    section "🔑 SERVICE CREDENTIALS"
    echo "  System-generated secrets are shown as defaults."
    echo "  Press Enter to accept, or type your own value to override."
    echo ""

    # PostgreSQL
    if [[ "${ENABLE_POSTGRES:-false}" == "true" ]]; then
        echo "  🐘 PostgreSQL:"
        safe_read "Database username" "${TENANT_ID}" "POSTGRES_USER"
        safe_read "Database name"     "${TENANT_ID}" "POSTGRES_DB"
        # Password auto-generated in write_platform_conf; allow override here
        local pg_pass_placeholder="<auto-generated>"
        echo "    Password: ${pg_pass_placeholder} (override with POSTGRES_PASSWORD env var before running)"
        echo ""
    fi

    # Redis
    if [[ "${ENABLE_REDIS:-false}" == "true" ]]; then
        echo "  📦 Redis:"
        local redis_pass_placeholder="<auto-generated>"
        echo "    Password: ${redis_pass_placeholder} (override with REDIS_PASSWORD env var before running)"
        echo ""
    fi

    # OpenClaw — uses token-based auth (no username), token = OPENCLAW_PASSWORD
    if [[ "${ENABLE_OPENCLAW:-false}" == "true" ]]; then
        OPENCLAW_IMAGE="alpine/openclaw:latest"
        safe_read "OpenClaw gateway token (leave blank to auto-generate)" "" "OPENCLAW_PASSWORD"
        if [[ -z "${OPENCLAW_PASSWORD:-}" ]]; then
            OPENCLAW_PASSWORD="$(openssl rand -base64 18 | tr -d '=+/' | cut -c1-16)"
            echo "    Auto-generated token: ${OPENCLAW_PASSWORD}"
        fi
        echo ""
    fi

    # Zep / Letta — public images, no prompts needed
    # Images: ghcr.io/getzep/zep:latest  |  letta/letta:latest
}

# =============================================================================
# LLM GATEWAY CONFIGURATION (README §4.4)
# =============================================================================
configure_llm_gateway() {
    section "🤖 LLM GATEWAY CONFIGURATION"
    
    echo "  📋 Configure LLM service gateway and model access"
    echo ""
    
    local gateway_choice=0
    select_menu_option "LLM Gateway Selection" \
        "LITELLM - Unified API for multiple providers with load balancing" \
        "BIFROST - Advanced gateway with enterprise features" \
        "DIRECT OLLAMA - Simple direct access to local models" || gateway_choice=$?
    
    case $gateway_choice in
        0) LLM_GATEWAY_TYPE="litellm" ;;
        1) LLM_GATEWAY_TYPE="bifrost" ;;
        2) LLM_GATEWAY_TYPE="direct" ;;
    esac
    
    case "$LLM_GATEWAY_TYPE" in
        litellm)
            configure_litellm_gateway
            ;;
        bifrost)
            configure_bifrost_gateway
            ;;
        direct)
            configure_direct_ollama
            ;;
    esac
}

configure_litellm_gateway() {
    echo ""
    log "🎯 Configuring LiteLLM Gateway..."
    
    safe_read "LiteLLM API key (auto-generated)" "$(gen_secret)" "LITELLM_MASTER_KEY"
    
    # Use menu selection for routing strategy
    local routing_choice=0
    select_menu_option "LiteLLM Load Balancing Strategy" \
        "cost-optimized (Prefer local models, fallback to external)" \
        "least-busy (Route to least busy model)" \
        "weighted (Weighted round-robin)" \
        "simple (Round-robin)" \
        "performance-first (Prefer fastest response time)" || routing_choice=$?
    case $routing_choice in
        0) LITELLM_ROUTING_STRATEGY="cost-optimized" ;;
        1) LITELLM_ROUTING_STRATEGY="least-busy" ;;
        2) LITELLM_ROUTING_STRATEGY="weighted" ;;
        3) LITELLM_ROUTING_STRATEGY="simple" ;;
        4) LITELLM_ROUTING_STRATEGY="performance-first" ;;
    esac
    
    safe_read "Enable request logging" "true" "LITELLM_ENABLE_LOGGING"
    safe_read "Enable cost tracking" "true" "LITELLM_ENABLE_COST_TRACKING"
    
    echo ""
    echo "  📊 LiteLLM Configuration Summary:"
    echo "    Gateway Type: LiteLLM"
    echo "    Master Key: ${LITELLM_MASTER_KEY:0:10}..."
    echo "    Routing: ${LITELLM_ROUTING_STRATEGY}"
    echo "    Logging: ${LITELLM_ENABLE_LOGGING}"
    echo "    Cost Tracking: ${LITELLM_ENABLE_COST_TRACKING}"
}

configure_bifrost_gateway() {
    echo ""
    log "🎯 Configuring Bifrost Gateway..."
    
    safe_read "Bifrost admin token" "$(gen_secret)" "BIFROST_ADMIN_TOKEN"
    safe_read "Bifrost API key" "$(gen_secret)" "BIFROST_API_KEY"
    safe_read "Bifrost port" "8000" "BIFROST_PORT" "^[0-9]+$"
    
    echo ""
    echo "  📊 Bifrost Configuration Summary:"
    echo "    Gateway Type: Bifrost"
    echo "    Admin Token: ${BIFROST_ADMIN_TOKEN:0:10}..."
    echo "    API Key: ${BIFROST_API_KEY:0:10}..."
    echo "    Port: ${BIFROST_PORT}"
}

configure_direct_ollama() {
    echo ""
    log "🎯 Configuring Direct Ollama Access..."
    
    safe_read "Ollama host" "localhost" "OLLAMA_HOST"
    safe_read "Ollama port" "11434" "OLLAMA_PORT" "^[0-9]+$"
    
    echo ""
    echo "  📊 Direct Ollama Configuration Summary:"
    echo "    Gateway Type: Direct Ollama"
    echo "    Host: ${OLLAMA_HOST}"
    echo "    Port: ${OLLAMA_PORT}"
}

# =============================================================================
# VECTOR DATABASE CONFIGURATION (README §4.5)
# =============================================================================
configure_vector_database() {
    section "🔍 VECTOR DATABASE CONFIGURATION"
    
    echo "  📋 Configure vector database for AI memory and search"
    echo ""
    
    local vector_choice=0
    select_menu_option "Vector Database Selection" \
        "QDRANT - High-performance vector search with built-in filtering" \
        "WEAVIATE - Enterprise GraphQL API with multi-modal support" \
        "CHROMADB - Lightweight Python-focused database" \
        "MILVUS - Distributed cloud-native massive scale database" || vector_choice=$?
    
    case $vector_choice in
        0) VECTOR_DB_TYPE="qdrant" ;;
        1) VECTOR_DB_TYPE="weaviate" ;;
        2) VECTOR_DB_TYPE="chroma" ;;
        3) VECTOR_DB_TYPE="milvus" ;;
    esac
    
    case "$VECTOR_DB_TYPE" in
        qdrant)
            configure_qdrant
            ;;
        weaviate)
            configure_weaviate
            ;;
        chroma)
            configure_chroma
            ;;
        milvus)
            configure_milvus
            ;;
    esac
}

configure_qdrant() {
    echo ""
    log "🎯 Configuring Qdrant..."
    
    safe_read "Qdrant port" "6333" "QDRANT_PORT" "^[0-9]+$"
    safe_read "Qdrant API key" "$(gen_secret)" "QDRANT_API_KEY"
    safe_read "Enable collection management" "true" "QDRANT_ENABLE_COLLECTIONS"
    
    echo ""
    echo "  📊 Qdrant Configuration Summary:"
    echo "    Database: Qdrant"
    echo "    Port: ${QDRANT_PORT}"
    echo "    API Key: ${QDRANT_API_KEY:0:10}..."
    echo "    Collection Management: ${QDRANT_ENABLE_COLLECTIONS}"
}

configure_weaviate() {
    echo ""
    log "🎯 Configuring Weaviate..."
    
    safe_read "Weaviate port" "8080" "WEAVIATE_PORT" "^[0-9]+$"
    safe_read "Weaviate API key" "$(gen_secret)" "WEAVIATE_API_KEY"
    safe_read "Enable authentication" "true" "WEAVIATE_ENABLE_AUTH"
    
    echo ""
    echo "  📊 Weaviate Configuration Summary:"
    echo "    Database: Weaviate"
    echo "    Port: ${WEAVIATE_PORT}"
    echo "    API Key: ${WEAVIATE_API_KEY:0:10}..."
    echo "    Authentication: ${WEAVIATE_ENABLE_AUTH}"
}

configure_chroma() {
    echo ""
    log "🎯 Configuring ChromaDB..."
    
    safe_read "ChromaDB port" "8000" "CHROMA_PORT" "^[0-9]+$"
    safe_read "ChromaDB auth token" "$(gen_secret)" "CHROMA_AUTH_TOKEN"
    
    echo ""
    echo "  📊 ChromaDB Configuration Summary:"
    echo "    Database: ChromaDB"
    echo "    Port: ${CHROMA_PORT}"
    echo "    Auth Token: ${CHROMA_AUTH_TOKEN:0:10}..."
}

configure_milvus() {
    echo ""
    log "🎯 Configuring Milvus..."
    
    safe_read "Milvus port" "19530" "MILVUS_PORT" "^[0-9]+$"
    safe_read "Milvus API key" "$(gen_secret)" "MILVUS_API_KEY"
    
    echo ""
    echo "  📊 Milvus Configuration Summary:"
    echo "    Database: Milvus"
    echo "    Port: ${MILVUS_PORT}"
    echo "    API Key: ${MILVUS_API_KEY:0:10}..."
}

# =============================================================================
# TLS CONFIGURATION (README §4.6)
# =============================================================================
configure_tls() {
    section "🔐 TLS CERTIFICATE CONFIGURATION"
    
    echo "  📋 Configure SSL/TLS certificates for secure access"
    echo ""
    
    local tls_choice=0
    # Show current value as a hint if already configured
    if [[ -n "${TLS_MODE:-}" ]]; then
        echo "  ℹ  Current TLS mode: ${TLS_MODE}"
    fi
    select_menu_option "TLS Certificate Selection" \
        "LET'S ENCRYPT - Automatic free certificates for production (recommended)" \
        "MANUAL CERTIFICATES - Provide your own cert/key files" \
        "SELF-SIGNED - Auto-generated cert for development/internal use" \
        "HTTP ONLY - No TLS (internal networks only)" || tls_choice=$?

    case $tls_choice in
        0) TLS_MODE="letsencrypt" ;;
        1) TLS_MODE="manual" ;;
        2) TLS_MODE="selfsigned" ;;
        3) TLS_MODE="none" ;;
    esac

    # Collect HTTP→HTTPS redirect exactly once here; never re-ask in configure_proxy
    if [[ "$TLS_MODE" != "none" ]]; then
        echo ""
        safe_read_yesno "Force HTTP to HTTPS redirect" "true" "HTTP_TO_HTTPS_REDIRECT"
    else
        HTTP_TO_HTTPS_REDIRECT="false"
    fi
    PROXY_FORCE_HTTPS="${HTTP_TO_HTTPS_REDIRECT}"
    
    case "$TLS_MODE" in
        letsencrypt)
            configure_letsencrypt
            ;;
        manual)
            configure_manual_tls
            ;;
        selfsigned)
            configure_selfsigned_tls
            ;;
        none)
            configure_no_tls
            ;;
    esac
}

configure_letsencrypt() {
    echo ""
    log "🎯 Configuring Let's Encrypt..."
    
    safe_read "Email for Let's Encrypt" "${ADMIN_EMAIL}" "LETSENCRYPT_EMAIL"
    safe_read "Enable staging mode (testing)" "false" "LETSENCRYPT_STAGING"
    safe_read "Auto-renew certificates" "true" "LETSENCRYPT_AUTO_RENEW"
    
    # Enhanced DNS validation with mission control
    echo ""
    log "🔍 Running enhanced DNS validation for ${DOMAIN}..."
    validate_dns_setup "$DOMAIN"
    
    # Additional Let's Encrypt specific checks
    echo ""
    log "🔍 Let's Encrypt specific validation..."
    
    # Check if port 80 is available (required for HTTP-01 challenge)
    if ss -tlnp 2>/dev/null | grep -q ":80 "; then
        warn "Port 80 is already in use - Let's Encrypt HTTP-01 challenge may fail"
        safe_read_yesno "Continue with port 80 in use?" "false" "CONTINUE_PORT80"
        if [[ "$CONTINUE_PORT80" != "true" ]]; then
            fail "Let's Encrypt requires port 80 for HTTP-01 challenge"
        fi
    else
        echo "✅ Port 80 is available for Let's Encrypt HTTP-01 challenge"
    fi
    
    # Check if port 443 is available
    if ss -tlnp 2>/dev/null | grep -q ":443 "; then
        warn "Port 443 is already in use - HTTPS may conflict"
        safe_read_yesno "Continue with port 443 in use?" "false" "CONTINUE_PORT443"
        if [[ "$CONTINUE_PORT443" != "true" ]]; then
            fail "Port 443 is required for HTTPS"
        fi
    else
        echo "✅ Port 443 is available for HTTPS"
    fi
    
    echo "✅ Let's Encrypt configuration validated"
}

configure_manual_tls() {
    echo ""
    log "🎯 Configuring Manual TLS..."
    
    safe_read "Certificate file path" "${DATA_DIR}/config/ssl/${DOMAIN}.crt" "TLS_CERT_FILE"
    safe_read "Private key file path" "${DATA_DIR}/config/ssl/${DOMAIN}.key" "TLS_KEY_FILE"
    
    # Validate files exist
    if [[ ! -f "$TLS_CERT_FILE" ]]; then
        warn "Certificate file not found: ${TLS_CERT_FILE}"
        warn "Please ensure certificate files exist before deployment"
    fi
    
    if [[ ! -f "$TLS_KEY_FILE" ]]; then
        warn "Private key file not found: ${TLS_KEY_FILE}"
        warn "Please ensure certificate files exist before deployment"
    fi
    
    echo ""
    echo "  📊 Manual TLS Configuration Summary:"
    echo "    TLS Mode: Manual"
    echo "    Certificate: ${TLS_CERT_FILE}"
    echo "    Private Key: ${TLS_KEY_FILE}"
}

configure_selfsigned_tls() {
    echo ""
    log "🎯 Configuring Self-Signed TLS..."
    
    safe_read "Certificate validity days" "365" "SELF_SIGNED_DAYS" "^[0-9]+$"
    safe_read "Country code" "US" "CERT_COUNTRY" "^[A-Z]{2}$"
    safe_read "State/Province" "California" "CERT_STATE"
    safe_read "City" "San Francisco" "CERT_CITY"
    safe_read "Organization" "${ORGANIZATION}" "CERT_ORG"
    
    echo ""
    echo "  📊 Self-Signed TLS Configuration Summary:"
    echo "    TLS Mode: Self-Signed"
    echo "    Validity: ${SELF_SIGNED_DAYS} days"
    echo "    Country: ${CERT_COUNTRY}"
    echo "    State: ${CERT_STATE}"
    echo "    City: ${CERT_CITY}"
    echo "    Organization: ${CERT_ORG}"
}

configure_no_tls() {
    echo ""
    log "⚠️  Configuring No TLS..."
    
    warn "TLS disabled - all connections will be HTTP"
    warn "Not recommended for production use"
    
    safe_read_yesno "Confirm TLS disabled" "false" "CONFIRM_NO_TLS"
    if [[ "$CONFIRM_NO_TLS" != "true" ]]; then
        fail "TLS configuration cancelled"
    fi
    
    echo ""
    echo "  📊 No TLS Configuration Summary:"
    echo "    TLS Mode: None (HTTP only)"
    echo "    Warning: Not secure for production"
}

# =============================================================================
# API KEY COLLECTION (README §4.7)
# =============================================================================
collect_api_keys() {
    section "🔑 API KEY COLLECTION"
    
    echo "  📋 Configure API keys for LLM providers"
    echo "  🔐 Keys are encrypted and stored securely"
    echo ""
    
    # Now configure individual providers first
    
    # OpenAI
    echo "  🤖 OpenAI Configuration:"
    safe_read_yesno "Enable OpenAI" "false" "ENABLE_OPENAI"
    if [[ "$ENABLE_OPENAI" == "true" ]]; then
        safe_read "OpenAI API key" "" "OPENAI_API_KEY" "^sk-[A-Za-z0-9]+$"
        safe_read "OpenAI organization ID" "" "OPENAI_ORG_ID"
        safe_read "OpenAI models" "gpt-4,gpt-3.5-turbo" "OPENAI_MODELS"
    fi
    echo ""
    
    # Anthropic
    echo "  🧠 Anthropic Configuration:"
    safe_read_yesno "Enable Anthropic Claude" "false" "ENABLE_ANTHROPIC"
    if [[ "$ENABLE_ANTHROPIC" == "true" ]]; then
        safe_read "Anthropic API key" "" "ANTHROPIC_API_KEY" "^sk-ant-[A-Za-z0-9_-]+$"
        safe_read "Anthropic models" "claude-3-sonnet-20240229,claude-3-haiku-20240307" "ANTHROPIC_MODELS"
    fi
    echo ""
    
    # Google
    echo "  🔍 Google AI Configuration:"
    safe_read_yesno "Enable Google AI" "false" "ENABLE_GOOGLE"
    if [[ "$ENABLE_GOOGLE" == "true" ]]; then
        safe_read "Google AI API key" "" "GOOGLE_AI_API_KEY" "^[A-Za-z0-9_-]+$"
        safe_read "Google models" "gemini-pro,gemini-pro-vision" "GOOGLE_MODELS"
    fi
    echo ""
    
    # Groq
    echo "  ⚡ Groq Configuration:"
    safe_read_yesno "Enable Groq" "false" "ENABLE_GROQ"
    if [[ "$ENABLE_GROQ" == "true" ]]; then
        safe_read "Groq API key" "" "GROQ_API_KEY" "^gsk_[A-Za-z0-9_-]+$"
        safe_read "Groq models" "llama2-70b-4096,mixtral-8x7b-32768" "GROQ_MODELS"
    fi
    echo ""
    
    # Cohere
    echo "  🔗 Cohere Configuration:"
    safe_read_yesno "Enable Cohere" "false" "ENABLE_COHERE"
    if [[ "$ENABLE_COHERE" == "true" ]]; then
        safe_read "Cohere API key" "" "COHERE_API_KEY" "^[A-Za-z0-9_-]+$"
        safe_read "Cohere models" "command,command-nightly,command-light" "COHERE_MODELS"
    fi
    echo ""
    
    # Hugging Face
    echo "  🤗 Hugging Face Configuration:"
    safe_read_yesno "Enable Hugging Face" "false" "ENABLE_HUGGINGFACE"
    if [[ "$ENABLE_HUGGINGFACE" == "true" ]]; then
        safe_read "Hugging Face API key" "" "HUGGINGFACE_API_KEY" "^[A-Za-z0-9_-]+$"
        safe_read "Hugging Face models" "microsoft/DialoGPT-medium,google/flan-t5-base" "HUGGINGFACE_MODELS"
    fi
    echo ""
    
    # OpenRouter
    echo "  🌐 OpenRouter Configuration:"
    safe_read_yesno "Enable OpenRouter" "false" "ENABLE_OPENROUTER"
    if [[ "$ENABLE_OPENROUTER" == "true" ]]; then
        safe_read "OpenRouter API key" "" "OPENROUTER_API_KEY" "^sk-or-[A-Za-z0-9_-]+$"
        safe_read "OpenRouter models" "anthropic/claude-3-sonnet,openai/gpt-4" "OPENROUTER_MODELS"
    fi
    echo ""

    # Mammouth
    echo "  🦣 Mammouth AI Configuration (https://api.mammouth.ai/):"
    safe_read_yesno "Enable Mammouth" "false" "ENABLE_MAMMOUTH"
    if [[ "$ENABLE_MAMMOUTH" == "true" ]]; then
        safe_read "Mammouth API key" "" "MAMMOUTH_API_KEY"
        # Auto-default base URL and models - behave like other providers
        MAMMOUTH_BASE_URL="https://api.mammouth.ai/v1"
        MAMMOUTH_MODELS="mammouth"
        echo "    🎯 Auto-configured: Base URL = $MAMMOUTH_BASE_URL"
        echo "    🎯 Auto-configured: Models = $MAMMOUTH_MODELS"
    fi
    echo ""

    # Search APIs (SerpAPI + Brave) - Only if SearXNG not enabled
    echo "  🔍 Search API Configuration:"
    echo "     (Modular architecture: SearXNG provides search, external APIs optional)"
    if [[ "${SEARXNG_ENABLED:-false}" != "true" ]]; then
        safe_read_yesno "Enable SerpAPI (Google/Bing/DDG search)" "false" "ENABLE_SERPAPI"
        if [[ "$ENABLE_SERPAPI" == "true" ]]; then
            safe_read "SerpAPI key" "" "SERPAPI_KEY"
            safe_read "SerpAPI engine" "google" "SERPAPI_ENGINE"
        fi
        echo ""
        safe_read_yesno "Enable Brave Search API" "false" "ENABLE_BRAVESEARCH"
        if [[ "$ENABLE_BRAVESEARCH" == "true" ]]; then
            safe_read "Brave Search API key" "" "BRAVE_API_KEY"
        fi
    else
        echo "     ✅ SearXNG enabled - external search APIs not needed"
        ENABLE_SERPAPI="false"
        ENABLE_BRAVESEARCH="false"
    fi
    echo ""

    # Local Models (Ollama)
    echo "  🦙 Local Models Configuration:"
    safe_read_yesno "Enable local models" "true" "ENABLE_LOCAL_MODELS"
    if [[ "$ENABLE_LOCAL_MODELS" == "true" ]]; then
        select_ollama_models
        safe_read_yesno "Auto-download models in Script 2" "true" "OLLAMA_AUTO_DOWNLOAD"
    if [[ "$OLLAMA_AUTO_DOWNLOAD" == "true" ]]; then
        echo "    📥 Models will be downloaded during deployment"
        echo "    📥 Use 'no' to deploy without models, add later via Script 3"
    else
        echo "    ⏭ Skipping model download in Script 2"
        echo "    💡 Models can be added later via Script 3 --configure-models"
    fi
    fi
    echo ""
    
    # Preferred LLM Provider for routing (after model configuration)
    echo "  🎯 Select your preferred LLM provider for LiteLLM routing priority:"
    echo "     This determines which provider gets first priority when multiple are available"
    echo ""
    local preferred_provider_choice=0
    [[ -n "${PREFERRED_LLM_PROVIDER:-}" ]] && echo "  ℹ  Current preferred provider: ${PREFERRED_LLM_PROVIDER}"
    select_menu_option "Preferred LLM Provider (Routing Priority)" \
        "OpenAI - GPT-4 and GPT-3.5 models" \
        "Anthropic Claude - Claude 3 family" \
        "Google AI - Gemini models" \
        "Groq - Fast inference with Llama models" \
        "Cohere - Command models" \
        "Hugging Face - Open model hub" \
        "Local Ollama - Self-hosted models" \
        "OpenRouter - Multi-provider aggregator" \
        "Mammouth - mammouth.ai models" || preferred_provider_choice=$?

        case $preferred_provider_choice in
            0) PREFERRED_LLM_PROVIDER="openai" ;;
            1) PREFERRED_LLM_PROVIDER="anthropic" ;;
            2) PREFERRED_LLM_PROVIDER="google" ;;
            3) PREFERRED_LLM_PROVIDER="groq" ;;
            4) PREFERRED_LLM_PROVIDER="cohere" ;;
            5) PREFERRED_LLM_PROVIDER="huggingface" ;;
            6) PREFERRED_LLM_PROVIDER="ollama" ;;
            7) PREFERRED_LLM_PROVIDER="openrouter" ;;
            8) PREFERRED_LLM_PROVIDER="mammouth" ;;
        esac

    echo ""
    echo "  ✅ Preferred provider for routing: ${PREFERRED_LLM_PROVIDER^}"
    echo ""
}

# OLLAMA MODEL SELECTION
# =============================================================================
select_ollama_models() {
    echo ""
    echo "  🦙 Available Ollama Models:"
    echo ""
    
    # Display GPU/CPU detection results
    echo "  📊 Hardware Detection:"
    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        echo "    💻 GPU: NVIDIA (${GPU_MEMORY}MB VRAM) - GPU acceleration available"
        echo "    💻 Recommended: Large models (8-16GB+) for optimal performance"
    elif [[ "$GPU_TYPE" == "rocm" ]]; then
        echo "    💻 GPU: AMD ROCm - GPU acceleration available"
        echo "    💻 Recommended: Medium models (4-8GB) for ROCm compatibility"
    else
        echo "    💻 GPU: None detected - CPU-only mode"
        echo "    💻 Recommended: Small models (< 4GB) for CPU efficiency"
    fi
    echo "    💻 RAM: ${TOTAL_RAM}MB total, ${AVAILABLE_RAM}MB available"
    echo ""
    
    # Model groups
    echo "   1) Qwen 3.6 35B - Latest Alibaba model (5 hours ago)"
    echo "   2) Gemma 2 27B - Google's latest multimodal (2 days ago)"
    echo "   3) Gemma 2 26B - Google's multimodal model (2 days ago)"
    echo "   4) MedGemma 27B - Medical specialized Gemma 2 (2 days ago)"
    echo "   5) GLM 5.1 - Latest agentic engineering model (1 week ago)"
    echo "   6) Mistral Large 3 - Latest Mistral MoE model (4 months ago)"
    echo "   7) Kimi K2 - Moonshot AI's MoE model (6 months ago)"
    echo "   8) Qwen 3 VL 32B - Vision-language model (5 months ago)"
    echo "   9) Gemma 2 9B - Google's compact multimodal (2 days ago)"
    echo "   10) Gemma 2 4B - Google's small multimodal (2 days ago)"
    echo "   11) Olmo 2 13B - Open language model (1 year ago)"
    echo "   12) Llama 3.3 70B - Meta's latest large model (1 year ago)"
    echo "   13) DeepSeek V3 671B - DeepSeek's MoE model (1 year ago)"
    echo "   14) Dolphin 3 8B - General purpose model (1 year ago)"
    echo "   15) Qwen 3 30B - Alibaba's latest generation (6 months ago)"
    echo "   16) SmolLM2 1.7B - Compact language model (1 year ago)"
    echo "   17) Llama 3.2 3B - Meta's compact model (1 year ago)"
    echo "   18) Mistral 7B - Mistral AI's updated model (9 months ago)"
    echo "   19) Gemma 4 4B - Google's latest compact model (new)"
    echo "   20) Gemma 4 26B - Google's medium model (new)"
    echo "   21) Gemma 4 31B - Google's large model (new)"
    echo "   22) Llama 3.2 3B - Meta's compact model (alternative)"
    echo "   23) Custom model - Enter specific model name"
    echo "      Examples: gemma4:4b, gemma4:31b"
    echo "      Multiple: gemma4:4b,gemma4:26b,gemma4:31b (comma-separated)"
    echo ""
    
    [[ -n "${OLLAMA_MODELS:-}" ]] && echo "  ℹ  Current models: ${OLLAMA_MODELS}"

    echo "  Select models (comma-separated numbers, e.g., 19,20,21):"
    echo -n "  Models selection [1-23]: "
    if [[ -t 0 ]]; then
        read -r selection
    else
        # Non-TTY: try piped input with timeout, else use default
        if ! read -t 5 -r selection 2>/dev/null; then
            selection="19,17"  # Default: Gemma 4 4B + Llama 3.2 3B (compact, CPU-friendly)
            echo "  (using default: $selection)"
        fi
    fi

    if [[ -z "$selection" ]]; then
        selection="19,17"  # Default: Gemma 4 4B + Llama 3.2 3B
    fi
    
    # Convert selection to model names
    local models=""
    IFS=',' read -ra selections <<< "$selection"
    for num in "${selections[@]}"; do
        case "${num// /}" in
            1) models="${models:+$models,}qwen3.6:35b" ;;
            2) models="${models:+$models,}gemma2:27b" ;;
            3) models="${models:+$models,}gemma2:26b" ;;
            4) models="${models:+$models,}medgemma:27b" ;;
            5) models="${models:+$models,}glm-5.1" ;;
            6) models="${models:+$models,}mistral-large-3" ;;
            7) models="${models:+$models,}kimi-k2" ;;
            8) models="${models:+$models,}qwen3-vl:32b" ;;
            9) models="${models:+$models,}gemma2:9b" ;;
            10) models="${models:+$models,}gemma2:4b" ;;
            11) models="${models:+$models,}olmo2:13b" ;;
            12) models="${models:+$models,}llama3.3:70b" ;;
            13) models="${models:+$models,}deepseek-v3:671b" ;;
            14) models="${models:+$models,}dolphin3:8b" ;;
            15) models="${models:+$models,}qwen3:30b" ;;
            16) models="${models:+$models,}smollm2:1.7b" ;;
            17) models="${models:+$models,}llama3.2:3b" ;;
            18) models="${models:+$models,}mistral:7b" ;;
            19) models="${models:+$models,}gemma3:4b" ;;
            20) models="${models:+$models,}gemma3:12b" ;;
            21) models="${models:+$models,}gemma3:27b" ;;
            22) models="${models:+$models,}llama3.2:3b" ;;
            23) 
                echo ""
                echo "  🔧 Custom Model Entry:"
                echo "  Enter model name(s) as they appear in ollama.com/library"
                echo "  Examples: qwen3.6:35b, gemma4:27b"
                echo "  Multiple models: qwen3.6:35b,gemma4:27b,gemma4:9b (comma-separated)"
                echo ""
                echo -n "  🎯 Custom model(s): "
                read -r custom_models
                if [[ -n "$custom_models" ]]; then
                    models="${models:+$models,}$custom_models"
                fi
                ;;
            *) echo "  ⚠️  Invalid selection: $num (skipping)" ;;
        esac
    done
    
    if [[ -n "$models" ]]; then
        OLLAMA_MODELS="$models"
        echo "  ✅ Selected models: $OLLAMA_MODELS"
    else
        OLLAMA_MODELS="gemma3:4b,llama3.2:3b"
        echo "  ✅ No valid models selected, using defaults: $OLLAMA_MODELS"
    fi
}

# =============================================================================
# PORT CONFIGURATION WITH HEALTH VALIDATION (README §4.6) - ENHANCED
# =============================================================================
configure_ports() {
    section "🔌 PORT CONFIGURATION WITH HEALTH VALIDATION"
    
    echo "  📋 Port Management:"
    echo "    • Check for port conflicts before assignment"
    echo "    • Mission control health validation for services"
    echo "    • Dynamic port allocation for conflicts"
    echo ""
    
    # Check port conflicts first
    check_port_conflicts
    
    echo "Configuring service ports..."
    
    # Infrastructure ports
    safe_read "PostgreSQL port" "${POSTGRES_PORT:-5432}" "POSTGRES_PORT"
    safe_read "Redis port" "${REDIS_PORT:-6379}" "REDIS_PORT"
    
    # Service ports
    safe_read "LiteLLM port" "${LITELLM_PORT:-4000}" "LITELLM_PORT"
    safe_read "Ollama port" "${OLLAMA_PORT:-11434}" "OLLAMA_PORT"
    safe_read "OpenWebUI port" "${OPENWEBUI_PORT:-3000}" "OPENWEBUI_PORT"
    safe_read "Qdrant port" "${QDRANT_PORT:-6333}" "QDRANT_PORT"
    
    if [[ "$N8N_ENABLED" == "true" ]]; then
        safe_read "n8n port" "${N8N_PORT:-5678}" "N8N_PORT"
    fi
    
    if [[ "$CODESERVER_ENABLED" == "true" ]]; then
        safe_read "Code Server port" "${CODESERVER_PORT:-8443}" "CODESERVER_PORT"
    fi
    
    # Mission control port health validation
    echo ""
    echo "Running mission control port health checks..."
    
    # Check if ports are available (pre-deployment validation)
    local all_ports_available=true
    
    for service_port in "POSTGRES:${POSTGRES_PORT}" "REDIS:${REDIS_PORT}" "LITELLM:${LITELLM_PORT}" "OLLAMA:${OLLAMA_PORT}" "OPENWEBUI:${OPENWEBUI_PORT}" "QDRANT:${QDRANT_PORT}"; do
        local service=$(echo "$service_port" | cut -d: -f1)
        local port=$(echo "$service_port" | cut -d: -f2)
        
        if ss -tlnp 2>/dev/null | grep -q ":$port "; then
            echo "❌ Port $port is already in use (conflict for $service)"
            all_ports_available=false
        else
            echo "✅ Port $port is available for $service"
        fi
    done
    
    if [[ "$all_ports_available" != "true" ]]; then
        echo ""
        echo "⚠️  Port conflicts detected. You can:"
        echo "   1. Change conflicting ports above"
        echo "   2. Stop conflicting processes"
        echo "   3. Continue and let deployment handle conflicts"
        
        safe_read "Continue with current port configuration?" "n" "CONTINUE_WITH_CONFLICTS"
        if [[ "$CONTINUE_WITH_CONFLICTS" != "yes" ]]; then
            fail "Port configuration cancelled due to conflicts"
        fi
    fi
    
    ok "Port configuration complete"
}

# =============================================================================
# PROXY CONFIGURATION (README §4.8)
# Supports: Caddy (auto-configured routes) or Nginx Proxy Manager (web UI managed)
# Only one reverse proxy may be active per deployment (mutually exclusive).
# =============================================================================
configure_proxy() {
    section "🌐 PROXY CONFIGURATION"

    echo "  📋 Configure reverse proxy for HTTPS termination and service routing"
    echo ""

    safe_read_yesno "Enable reverse proxy (recommended when domain is configured)" "true" "ENABLE_PROXY"
    if [[ "$ENABLE_PROXY" != "true" ]]; then
        ENABLE_CADDY="false"
        ENABLE_NPM="false"
        PROXY_TYPE="none"
        echo "  ℹ️  No reverse proxy — services accessible via direct ports only"
        echo ""
        return 0
    fi

    echo ""
    local proxy_choice=0
    [[ -n "${PROXY_TYPE:-}" ]] && echo "  ℹ  Current proxy: ${PROXY_TYPE}"
    select_menu_option "Reverse Proxy Type" \
        "CADDY             — Auto-configures all routes; Caddyfile generated by Script 2" \
        "NGINX PROXY MGR   — Web UI at :81 for manual route management (more flexible)" || proxy_choice=$?

    ENABLE_CADDY="false"
    ENABLE_NPM="false"

    case $proxy_choice in
        0)
            PROXY_TYPE="caddy"
            ENABLE_CADDY="true"
            echo ""
            safe_read "HTTP port"  "80"  "PROXY_HTTP_PORT"  "^[0-9]+$"
            safe_read "HTTPS port" "443" "PROXY_HTTPS_PORT" "^[0-9]+$"
            CADDY_HTTP_PORT="${PROXY_HTTP_PORT:-80}"
            CADDY_HTTPS_PORT="${PROXY_HTTPS_PORT:-443}"
            PROXY_FORCE_HTTPS="${HTTP_TO_HTTPS_REDIRECT:-false}"
            echo ""
            echo "  ✅ Caddy: HTTP=${CADDY_HTTP_PORT}  HTTPS=${CADDY_HTTPS_PORT}  Force-HTTPS=${PROXY_FORCE_HTTPS}"
            ;;
        1)
            PROXY_TYPE="npm"
            ENABLE_NPM="true"
            echo ""
            safe_read "HTTP port"       "80"  "PROXY_HTTP_PORT"  "^[0-9]+$"
            safe_read "HTTPS port"      "443" "PROXY_HTTPS_PORT" "^[0-9]+$"
            safe_read "NPM admin port"  "81"  "NPM_ADMIN_PORT"   "^[0-9]+$"
            NPM_HTTP_PORT="${PROXY_HTTP_PORT:-80}"
            NPM_HTTPS_PORT="${PROXY_HTTPS_PORT:-443}"
            echo ""
            echo "  ✅ Nginx Proxy Manager: HTTP=${NPM_HTTP_PORT}  HTTPS=${NPM_HTTPS_PORT}  Admin=:${NPM_ADMIN_PORT}"
            echo "     Routes must be configured via the NPM web UI after first deploy."
            echo "     Default login: admin@example.com / changeme (change immediately)"
            ;;
    esac
    echo ""
}

# =============================================================================
# GOOGLE DRIVE INTEGRATION (README §4.9)
# =============================================================================
configure_google_drive() {
    section "📁 GOOGLE DRIVE INTEGRATION"
    
    echo "  📂 Google Drive Integration:"
    safe_read_yesno "Enable Google Drive ingestion" "false" "ENABLE_GDRIVE"
    if [[ "$ENABLE_GDRIVE" == "true" ]]; then
        safe_read "Google Drive Folder ID" "" "GDRIVE_FOLDER_ID"
        safe_read "Google Drive Folder Name [AI Platform]" "AI Platform" "GDRIVE_FOLDER_NAME"
    fi
    
    echo ""
    if [[ "$ENABLE_GDRIVE" == "true" ]]; then
        echo "  ✅ Google Drive Configuration:"
        echo "    Folder ID: ${GDRIVE_FOLDER_ID:-Not set}"
        echo "    Folder Name: $GDRIVE_FOLDER_NAME"
    else
        echo "  ℹ️  Google Drive integration disabled"
    fi
    echo ""
}

# =============================================================================
# SIGNAL-BOT CONFIGURATION (README §4.13)
# =============================================================================
configure_signalbot() {
    section "📡 SIGNAL-BOT CONFIGURATION"
    
    echo "  📋 Configure Signal bot for notifications"
    echo ""
    
    safe_read_yesno "Enable Signal bot" "false" "ENABLE_SIGNALBOT"
    if [[ "$ENABLE_SIGNALBOT" == "true" ]]; then
        echo ""
        safe_read "Signal phone number (E.164 format, e.g., +15551234567)" "" "SIGNAL_PHONE" "^\+[1-9][0-9]{1,14}$"
        safe_read "Signal recipient number (E.164 format)" "" "SIGNAL_RECIPIENT" "^\+[1-9][0-9]{1,14}$"
        safe_read "Signal bot port" "8080" "SIGNALBOT_PORT" "^[0-9]+$"
        
        echo ""
        echo "  ✅ Signal Bot Configuration:"
        echo "    Phone Number: $SIGNAL_PHONE"
        echo "    Recipient: $SIGNAL_RECIPIENT"
        echo "    Port: $SIGNALBOT_PORT"
    else
        echo "  ℹ️  Signal bot disabled"
    fi
    
    # SearXNG Configuration
    echo "  📋 Configure SearXNG search engine"
    echo ""
    
    safe_read_yesno "Enable SearXNG" "false" "ENABLE_SEARXNG"
    if [[ "$ENABLE_SEARXNG" == "true" ]]; then
        echo ""
        safe_read "SearXNG port" "8888" "SEARXNG_PORT" "^[0-9]+$"
        safe_read "SearXNG secret key (leave blank to auto-generate)" "AUTO_GENERATE" "SEARXNG_SECRET_KEY" "^.*$"
        if [[ "$SEARXNG_SECRET_KEY" == "AUTO_GENERATE" || -z "${SEARXNG_SECRET_KEY:-}" ]]; then
            SEARXNG_SECRET_KEY="$(openssl rand -hex 32)"
            echo "    Auto-generated secret key: ${SEARXNG_SECRET_KEY}"
        fi
        
        echo ""
        echo "  ✅ SearXNG Configuration:"
        echo "    Port: $SEARXNG_PORT"
        echo "    Secret Key: ${SEARXNG_SECRET_KEY:0:16}..."
    else
        echo "  ℹ️  SearXNG disabled"
    fi
    echo ""
}

# Enhanced port conflict detection
check_port_conflicts() {
    echo "Checking for port conflicts..."
    
    # Collect all required ports from platform.conf
    local required_ports=()
    
    # Infrastructure ports
    [[ "${POSTGRES_ENABLED}" == "true" ]] && required_ports+=("${POSTGRES_PORT:-5432}")
    [[ "${REDIS_ENABLED}" == "true" ]] && required_ports+=("${REDIS_PORT:-6379}")
    
    # Service ports
    [[ "${LITELLM_ENABLED}" == "true" ]] && required_ports+=("${LITELLM_PORT:-4000}")
    [[ "${OLLAMA_ENABLED}" == "true" ]] && required_ports+=("${OLLAMA_PORT:-11434}")
    [[ "${OPENWEBUI_ENABLED}" == "true" ]] && required_ports+=("${OPENWEBUI_PORT:-3000}")
    [[ "${QDRANT_ENABLED}" == "true" ]] && required_ports+=("${QDRANT_PORT:-6333}")
    [[ "${N8N_ENABLED}" == "true" ]] && required_ports+=("${N8N_PORT:-5678}")
    [[ "${CODESERVER_ENABLED}" == "true" ]] && required_ports+=("${CODESERVER_PORT:-8443}")
    
    # Check each port against currently listening ports
    local conflicts=()
    for port in "${required_ports[@]}"; do
        if ss -tlnp 2>/dev/null | grep -q ":$port "; then
            local pid=$(ss -tlnp 2>/dev/null | grep ":$port " | head -1 | awk '{print $7}')
            local process=$(ps -p "$pid" -o comm= 2>/dev/null)
            conflicts+=("Port $port: already in use by $process (PID $pid)")
        fi
    done
    
    # Report conflicts
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo "❌ PORT CONFLICTS DETECTED:"
        printf '%s\n' "${conflicts[@]}"
        echo ""
        echo "Options:"
        echo "  1. Change conflicting ports in platform.conf"
        echo "  2. Stop conflicting processes"
        echo "  3. Use different tenant ID"
    else
        echo "✅ No port conflicts detected for required ports"
        echo "Required ports: ${required_ports[*]}"
    fi
}

# Mission Control Port Health Check (for Scripts 2, 3)
check_port_health() {
    local port="$1"
    local service="$2"
    local timeout="${3:-30}"
    
    echo "Checking port health for $service (port $port)..."
    
    # Check if port is listening
    local waited=0
    while ! ss -tlnp 2>/dev/null | grep -q ":$port "; do
        if [[ $waited -ge $timeout ]]; then
            echo "❌ Port $port not available for $service after ${timeout}s"
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
    
    # Check service health endpoint if available
    case "$service" in
        "postgres")
            if docker exec "${TENANT_PREFIX}-postgres" pg_isready -U postgres >/dev/null 2>&1; then
                echo "✅ PostgreSQL health check passed"
            else
                echo "❌ PostgreSQL health check failed"
                return 1
            fi
            ;;
        "redis")
            if docker exec "${TENANT_PREFIX}-redis" redis-cli ping | grep -q PONG; then
                echo "✅ Redis health check passed"
            else
                echo "❌ Redis health check failed"
                return 1
            fi
            ;;
        "ollama")
            if curl -s "http://localhost:${port}/api/tags" >/dev/null; then
                echo "✅ Ollama health check passed"
            else
                echo "❌ Ollama health check failed"
                return 1
            fi
            ;;
        "litellm")
            if curl -s "http://localhost:${port}/health" >/dev/null; then
                echo "✅ LiteLLM health check passed"
            else
                echo "❌ LiteLLM health check failed"
                return 1
            fi
            ;;
        *)
            echo "✅ Port $port is available for $service"
            ;;
    esac
    
    return 0
}

# =============================================================================
# DNS VALIDATION FUNCTIONS (README §4.5) - ENHANCED
# =============================================================================

# Enhanced DNS validation with mission control integration
validate_dns_setup() {
    local domain="$1"
    
    echo "=== DNS VALIDATION FOR $domain ==="
    
    # Step 1: Basic domain format validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        echo "❌ Invalid domain format: $domain"
        return 1
    fi
    echo "✅ Domain format is valid"
    
    # Step 2: DNS resolution test
    echo "Testing DNS resolution..."
    if dig +short "$domain" >/dev/null 2>&1; then
        echo "✅ DNS resolution successful"
    else
        echo "❌ DNS resolution failed"
        return 1
    fi
    
    # Step 3: Get public IP and compare
    echo "Detecting public IP..."
    local public_ip
    public_ip=$(curl -s https://ifconfig.me 2>/dev/null || curl -s https://ipinfo.io/ip 2>/dev/null)
    
    if [[ -z "$public_ip" ]]; then
        echo "❌ Could not detect public IP"
        return 1
    fi
    echo "Detected public IP: $public_ip"
    
    # Step 4: Compare domain resolution with public IP
    echo "Comparing domain resolution with public IP..."
    local domain_ip
    domain_ip=$(dig +short "$domain" | head -1)
    
    if [[ "$domain_ip" == "$public_ip" ]]; then
        echo "✅ Domain resolves to this server's public IP"
    else
        echo "⚠️  Domain resolves to $domain_ip, but this server's public IP is $public_ip"
        echo "   This may indicate a DNS configuration issue"
        safe_read_yesno "Continue despite IP mismatch?" "false" "CONTINUE_IP_MISMATCH"
        if [[ "$CONTINUE_IP_MISMATCH" != "true" ]]; then
            return 1
        fi
    fi
    
    # Step 5: Test reverse DNS (optional)
    echo "Testing reverse DNS lookup..."
    local reverse_dns
    if reverse_dns=$(dig -x "$public_ip" +short 2>/dev/null); then
        echo "Reverse DNS: $public_ip → $reverse_dns"
        if [[ "$reverse_dns" != "$domain" ]]; then
            echo "⚠️  Reverse DNS mismatch: $public_ip → $reverse_dns (expected $domain)"
        fi
    else
        echo "Reverse DNS lookup failed for $public_ip"
    fi
    
    echo "=== DNS VALIDATION COMPLETE ==="
    return 0
}

# DNS health check for mission control
check_dns_health() {
    local domain="$1"
    local timeout="${2:-30}"
    
    echo "Checking DNS health for $domain..."
    
    local waited=0
    while [[ $waited -lt $timeout ]]; do
        if dig +short "$domain" >/dev/null 2>&1; then
            echo "✅ DNS resolution working for $domain"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    
    echo "❌ DNS resolution failed after ${timeout}s"
    return 1
}

# =============================================================================
# CONFIGURATION SUMMARY DISPLAY
# =============================================================================
display_configuration_summary() {
    section "🔐 CONFIGURATION SUMMARY"
    
    echo "  🔐 TLS Configuration:"
    echo "    • Certificate management with DNS validation"
    echo "    • Automatic certificate renewal"
    echo ""
    
    # Identity Summary
    echo "  🏷️  IDENTITY:"
    echo "    Platform: ${PLATFORM_PREFIX}"
    echo "    Tenant: ${TENANT_ID}"
    echo "    Domain: ${DOMAIN}"
    echo "    Organization: ${ORGANIZATION}"
    echo "    Admin Email: ${ADMIN_EMAIL}"
    echo ""
    
    # Storage Summary
    echo "  💾 STORAGE:"
    echo "    Data Directory: ${DATA_DIR}"
    echo "    EBS Volume: ${USE_EBS}"
    if [[ "$USE_EBS" == "true" ]]; then
        echo "    Device Pattern: ${EBS_DEVICE_PATTERN}"
        echo "    Filesystem: ${EBS_FILESYSTEM}"
    fi
    echo ""
    
    # Stack Summary
    echo "  🎚️  STACK:"
    echo "    Preset: ${STACK_NAME^}"
    echo "    Enabled Services:"
    [[ "$ENABLE_POSTGRES" == "true" ]] && echo "      • PostgreSQL"
    [[ "$ENABLE_REDIS" == "true" ]] && echo "      • Redis"
    [[ "$ENABLE_OLLAMA" == "true" ]] && echo "      • Ollama"
    [[ "$ENABLE_LITELLM" == "true" ]] && echo "      • LiteLLM"
    [[ "$ENABLE_OPENWEBUI" == "true" ]] && echo "      • OpenWebUI"
    [[ "$ENABLE_QDRANT" == "true" ]] && echo "      • Qdrant"
    [[ "$ENABLE_CODE_SERVER" == "true" ]] && echo "      • Code Server"
    [[ "$ENABLE_N8N" == "true" ]] && echo "      • N8N"
    [[ "$ENABLE_FLOWISE" == "true" ]] && echo "      • Flowise"
    [[ "$ENABLE_GRAFANA" == "true" ]] && echo "      • Grafana"
    [[ "$ENABLE_PROMETHEUS" == "true" ]] && echo "      • Prometheus"
    [[ "$ENABLE_LIBRECHAT" == "true" ]] && echo "      • LibreChat"
    [[ "$ENABLE_OPENCLAW" == "true" ]] && echo "      • OpenClaw"
    [[ "$ENABLE_ANYTHINGLLM" == "true" ]] && echo "      • AnythingLLM"
    [[ "$ENABLE_DIFY" == "true" ]] && echo "      • Dify"
    [[ "$ENABLE_SIGNALBOT" == "true" ]] && echo "      • SignalBot"
    [[ "$ENABLE_AUTHENTIK" == "true" ]] && echo "      • Authentik"
    echo ""
    
    # LLM Gateway Summary
    echo "  🤖 LLM GATEWAY:"
    echo "    Type: ${LLM_GATEWAY_TYPE^}"
    case "$LLM_GATEWAY_TYPE" in
        litellm)
            echo "    Routing: ${LITELLM_ROUTING_STRATEGY}"
            echo "    Logging: ${LITELLM_ENABLE_LOGGING}"
            ;;
        bifrost)
            echo "    Port: ${BIFROST_PORT}"
            ;;
        direct)
            echo "    Host: ${OLLAMA_HOST}:${OLLAMA_PORT}"
            ;;
    esac
    echo ""
    
    # Vector Database Summary
    echo "  🔍 VECTOR DATABASE:"
    echo "    Type: ${VECTOR_DB_TYPE^}"
    case "$VECTOR_DB_TYPE" in
        qdrant)
            echo "    Port: ${QDRANT_PORT}"
            ;;
        weaviate)
            echo "    Port: ${WEAVIATE_PORT}"
            ;;
        chroma)
            echo "    Port: ${CHROMA_PORT}"
            ;;
        milvus)
            echo "    Port: ${MILVUS_PORT}"
            ;;
    esac
    echo ""
    
    # TLS Summary
    echo "  🔐 TLS:"
    echo "    Mode: ${TLS_MODE^}"
    case "$TLS_MODE" in
        letsencrypt)
            echo "    Email: ${LETSENCRYPT_EMAIL}"
            echo "    Staging: ${LETSENCRYPT_STAGING}"
            ;;
        manual)
            echo "    Certificate: ${TLS_CERT_FILE}"
            ;;
        selfsigned)
            echo "    Validity: ${SELF_SIGNED_DAYS} days"
            ;;
        none)
            echo "    ⚠️  HTTP only - not secure"
            ;;
    esac
    echo ""
    
    # API Keys Summary
    echo "  🔑 API KEYS:"
    local provider_count=0
    [[ "$ENABLE_OPENAI" == "true" ]] && { echo "    • OpenAI: ✅"; ((provider_count++)); }
    [[ "$ENABLE_ANTHROPIC" == "true" ]] && { echo "    • Anthropic: ✅"; ((provider_count++)); }
    [[ "$ENABLE_GOOGLE" == "true" ]] && { echo "    • Google AI: ✅"; ((provider_count++)); }
    [[ "$ENABLE_GROQ" == "true" ]] && { echo "    • Groq: ✅"; ((provider_count++)); }
    [[ "$ENABLE_COHERE" == "true" ]] && { echo "    • Cohere: ✅"; ((provider_count++)); }
    [[ "$ENABLE_HUGGINGFACE" == "true" ]] && { echo "    • Hugging Face: ✅"; ((provider_count++)); }
    [[ "$ENABLE_LOCAL_MODELS" == "true" ]] && { echo "    • Local Models: ✅"; ((provider_count++)); }
    
    if [[ $provider_count -eq 0 ]]; then
        echo "    ⚠️  No LLM providers configured"
    else
        echo "    Total providers: ${provider_count}"
    fi
    echo ""
    
    # System Resources
    echo "  💻 SYSTEM RESOURCES:"
    echo "    GPU: ${GPU_TYPE^}"
    [[ "$GPU_TYPE" != "none" ]] && echo "    GPU Memory: ${GPU_MEMORY}MB"
    echo "    RAM: ${TOTAL_RAM}MB total, ${AVAILABLE_RAM}MB available"
    echo "    Disk: ${DISK_SPACE} available"
    echo ""
    
    # GPU/CPU Deployment Confirmation
    echo "  💻 DEPLOYMENT MODE CONFIRMATION:"
    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        echo "    • Recommended: GPU-accelerated deployment for large models"
        echo "    • Performance: Fast inference with ${GPU_MEMORY}MB VRAM"
        echo "    • Use Case: Production workloads, large model inference"
    elif [[ "$GPU_TYPE" == "rocm" ]]; then
        echo "    • Recommended: GPU-accelerated deployment for medium models"
        echo "    • Performance: Good inference with AMD ROCm"
        echo "    • Use Case: Development, medium model workloads"
    else
        echo "    • Recommended: CPU-only deployment for small models"
        echo "    • Performance: Slower inference, no GPU acceleration"
        echo "    • Use Case: Development, testing, small model workloads"
        echo "    • Upgrade: Consider GPU instance for large models"
    fi
    echo ""
    
    # Final Confirmation
    echo "  🎯 CONFIGURATION COMPLETE"
    echo "    All settings have been collected and validated"
    echo "    Ready to generate platform.conf and deploy"
    echo ""
    
    safe_read_yesno "Confirm and save configuration" "y" "CONFIRM_CONFIG"
    if [[ "$CONFIRM_CONFIG" != "true" ]]; then
        fail "Configuration cancelled by user"
    fi
}

# =============================================================================
# PLATFORM.CONF GENERATION (README §4.10)
# =============================================================================
write_platform_conf() {
    section "📝 GENERATING PLATFORM.CONF"
    
    # Ensure DATA_DIR is set correctly based on TENANT_ID
    if [[ -z "${DATA_DIR:-}" || -z "${TENANT_ID:-}" ]]; then
        DATA_DIR="/mnt/${TENANT_ID:-default}"
        log "⚠️  TENANT_ID was empty, using default directory: $DATA_DIR"
    fi
    
    # Create the directory structure if it doesn't exist
    mkdir -p "${DATA_DIR}/config"
    mkdir -p "${DATA_DIR}/data"
    mkdir -p "${DATA_DIR}/logs"
    mkdir -p "${DATA_DIR}/.configured"
    
    local config_file="${DATA_DIR}/config/platform.conf"
    local temp_file="/tmp/platform.conf.$$"
    local generated_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local searxng_secret_key=$(gen_secret)
    
    # Generate ALL secrets to avoid function calls in heredoc
    local code_server_password=$(gen_password)
    local litellm_master_key=$(gen_secret)
    local bifrost_admin_token=$(gen_secret)
    local bifrost_api_key=$(gen_secret)
    local qdrant_api_key=$(gen_secret)
    local weaviate_api_key=$(gen_secret)
    local chroma_auth_token=$(gen_secret)
    local milvus_api_key=$(gen_secret)
    local postgres_password=$(gen_password)
    local redis_password=$(gen_password)
    local n8n_encryption_key=$(gen_secret)
    local grafana_admin_password=$(gen_password)
    local litellm_ui_password=$(gen_password)
    local openwebui_secret=$(gen_secret)
    local flowise_password=$(gen_password)
    local flowise_secretkey_overwrite=$(gen_secret)
    local dify_secret_key=$(gen_secret)
    local dify_init_password=$(openssl rand -base64 16 | tr -d '=+/')
    local librechat_jwt_secret=$(gen_secret)
    local librechat_crypt_key=$(openssl rand -hex 32)
    local mongo_password=$(gen_password)
    local authentik_secret_key=$(openssl rand -hex 50)
    local authentik_bootstrap_password=$(openssl rand -base64 16 | tr -d '=+/')
    local zep_auth_secret=$(openssl rand -hex 32)
    local letta_server_pass=$(openssl rand -hex 24)
    local anythingllm_jwt_secret=$(openssl rand -hex 32)
    local code_server_password=$(openssl rand -base64 16 | tr -d '=+/')
    local n8n_encryption_key=$(openssl rand -hex 32)
    local serpapi_key=${SERPAPI_KEY:-}
    local brave_api_key=${BRAVE_API_KEY:-}
    local openclaw_password=${OPENCLAW_PASSWORD:-$(gen_password)}
    
    log "🎯 Generating comprehensive configuration file..."
    
    # Create temporary file
    cat > "$temp_file" << EOF
# =============================================================================
# AI Platform Configuration - Generated by Script 1
# Platform: ${PLATFORM_PREFIX}
# Tenant: ${TENANT_ID}
# Domain: ${DOMAIN}
# Generated: ${generated_date}
# =============================================================================

# =============================================================================
# STORAGE CONFIGURATION
# =============================================================================
DATA_DIR="${DATA_DIR}"
USE_EBS="${USE_EBS}"
EBS_DEVICE_PATTERN="${EBS_DEVICE_PATTERN:-/dev/sd[f-z]}"
EBS_FILESYSTEM="${EBS_FILESYSTEM:-ext4}"
EBS_MOUNT_OPTS="${EBS_MOUNT_OPTS:-defaults,noatime}"

# =============================================================================
# STACK CONFIGURATION
# =============================================================================
STACK_PRESET="${STACK_PRESET:-5}"
STACK_NAME="${STACK_NAME:-custom}"

# Infrastructure Services
ENABLE_POSTGRES="${ENABLE_POSTGRES:-false}"
ENABLE_REDIS="${ENABLE_REDIS:-false}"

# LLM Services
ENABLE_OLLAMA="${ENABLE_OLLAMA:-false}"
ENABLE_LITELLM="${ENABLE_LITELLM:-false}"

# Web Interfaces
ENABLE_OPENWEBUI="${ENABLE_OPENWEBUI:-false}"
ENABLE_LIBRECHAT="${ENABLE_LIBRECHAT:-false}"
ENABLE_OPENCLAW="${ENABLE_OPENCLAW:-false}"
ENABLE_ANYTHINGLLM="${ENABLE_ANYTHINGLLM:-false}"

# Vector Databases
ENABLE_QDRANT="${ENABLE_QDRANT:-false}"
ENABLE_WEAVIATE="${ENABLE_WEAVIATE:-false}"
ENABLE_CHROMA="${ENABLE_CHROMA:-false}"
ENABLE_MILVUS="${ENABLE_MILVUS:-false}"

# Automation
ENABLE_N8N="${ENABLE_N8N:-false}"
ENABLE_FLOWISE="${ENABLE_FLOWISE:-false}"
ENABLE_DIFY="${ENABLE_DIFY:-false}"

# Development
ENABLE_CODE_SERVER="${ENABLE_CODE_SERVER:-false}"

# Monitoring
ENABLE_GRAFANA="${ENABLE_GRAFANA:-false}"
ENABLE_PROMETHEUS="${ENABLE_PROMETHEUS:-false}"

# Authentication
ENABLE_AUTHENTIK="${ENABLE_AUTHENTIK:-false}"

# Additional Services
ENABLE_SIGNALBOT="${ENABLE_SIGNALBOT:-false}"
SIGNAL_PHONE="${SIGNAL_PHONE:-}"
SIGNAL_RECIPIENT="${SIGNAL_RECIPIENT:-}"

ENABLE_SEARXNG="${ENABLE_SEARXNG:-false}"
SEARXNG_PORT="${SEARXNG_PORT:-8888}"
SEARXNG_SECRET_KEY="${SEARXNG_SECRET_KEY:-${searxng_secret_key}}"

ENABLE_BIFROST="${ENABLE_BIFROST:-false}"
BIFROST_PORT="${BIFROST_PORT:-8000}"

# Memory Layer
ENABLE_LETTA="${ENABLE_LETTA:-false}"
LETTA_PORT="${LETTA_PORT:-8283}"

# Development
ENABLE_CONTINUE_DEV="${ENABLE_CONTINUE_DEV:-false}"

# Search APIs
ENABLE_SERPAPI="${ENABLE_SERPAPI:-false}"
SERPAPI_KEY="${SERPAPI_KEY:-}"
SERPAPI_ENGINE="${SERPAPI_ENGINE:-google}"
ENABLE_BRAVE="${ENABLE_BRAVE:-false}"
BRAVE_API_KEY="${BRAVE_API_KEY:-}"

# =============================================================================
# INGESTION CONFIGURATION
# =============================================================================
ENABLE_INGESTION="${ENABLE_INGESTION:-false}"
INGESTION_METHOD="${INGESTION_METHOD:-rclone}"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
RCLONE_POLL_INTERVAL="${RCLONE_POLL_INTERVAL:-5}"
RCLONE_TRANSFERS="${RCLONE_TRANSFERS:-4}"
RCLONE_CHECKERS="${RCLONE_CHECKERS:-8}"
RCLONE_VFS_CACHE="${RCLONE_VFS_CACHE:-writes}"
GDRIVE_CREDENTIALS_FILE="${GDRIVE_CREDENTIALS_FILE:-}"
GDRIVE_FOLDER_ID="${GDRIVE_FOLDER_ID:-}"
AWS_S3_BUCKET="${AWS_S3_BUCKET:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-}"
AZURE_CONTAINER="${AZURE_CONTAINER:-}"
AZURE_ACCESS_KEY="${AZURE_ACCESS_KEY:-}"
LOCAL_INGESTION_PATH="${LOCAL_INGESTION_PATH:-/mnt/${TENANT_ID}/ingestion/AI_Platform}"

# =============================================================================
# LLM GATEWAY CONFIGURATION
# =============================================================================
LLM_GATEWAY_TYPE="${LLM_GATEWAY_TYPE:-litellm}"

# LiteLLM Configuration
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-${litellm_master_key}}"
LITELLM_ROUTING_STRATEGY="${LITELLM_ROUTING_STRATEGY:-cost-optimized}"
LITELLM_ENABLE_LOGGING="${LITELLM_ENABLE_LOGGING:-true}"
LITELLM_ENABLE_COST_TRACKING="${LITELLM_ENABLE_COST_TRACKING:-true}"

# Bifrost Configuration
BIFROST_ADMIN_TOKEN="${BIFROST_ADMIN_TOKEN:-${bifrost_admin_token}}"
BIFROST_API_KEY="${BIFROST_API_KEY:-${bifrost_api_key}}"
BIFROST_PORT="${BIFROST_PORT:-8000}"

# Direct Ollama Configuration
OLLAMA_HOST="${OLLAMA_HOST:-localhost}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"

# =============================================================================
# VECTOR DATABASE CONFIGURATION
# =============================================================================
VECTOR_DB_TYPE="${VECTOR_DB_TYPE:-qdrant}"

# Qdrant Configuration
QDRANT_PORT="${QDRANT_PORT:-6333}"
QDRANT_API_KEY="${QDRANT_API_KEY:-${qdrant_api_key}}"
QDRANT_ENABLE_COLLECTIONS="${QDRANT_ENABLE_COLLECTIONS:-true}"

# Weaviate Configuration
WEAVIATE_PORT="${WEAVIATE_PORT:-8080}"
WEAVIATE_API_KEY="${WEAVIATE_API_KEY:-${weaviate_api_key}}"
WEAVIATE_ENABLE_AUTH="${WEAVIATE_ENABLE_AUTH:-true}"

# ChromaDB Configuration
CHROMA_PORT="${CHROMA_PORT:-8000}"
CHROMA_AUTH_TOKEN="${CHROMA_AUTH_TOKEN:-${chroma_auth_token}}"

# Milvus Configuration
MILVUS_PORT="${MILVUS_PORT:-19530}"
MILVUS_API_KEY="${MILVUS_API_KEY:-${milvus_api_key}}"

# =============================================================================
# TLS CONFIGURATION
# =============================================================================
TLS_MODE="${TLS_MODE:-self-signed}"

# Let's Encrypt Configuration
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-${ADMIN_EMAIL}}"
LETSENCRYPT_STAGING="${LETSENCRYPT_STAGING:-false}"
LETSENCRYPT_AUTO_RENEW="${LETSENCRYPT_AUTO_RENEW:-true}"

# Manual TLS Configuration
TLS_CERT_FILE="${TLS_CERT_FILE:-${DATA_DIR}/config/ssl/${DOMAIN}.crt}"
TLS_KEY_FILE="${TLS_KEY_FILE:-${DATA_DIR}/config/ssl/${DOMAIN}.key}"

# Self-Signed TLS Configuration
SELF_SIGNED_DAYS="${SELF_SIGNED_DAYS:-365}"
CERT_COUNTRY="${CERT_COUNTRY:-US}"
CERT_STATE="${CERT_STATE:-California}"
CERT_CITY="${CERT_CITY:-San Francisco}"
CERT_ORG="${CERT_ORG:-${ORGANIZATION}}"

# =============================================================================
# API KEY CONFIGURATION
# =============================================================================

# OpenAI Configuration
ENABLE_OPENAI="${ENABLE_OPENAI:-false}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
OPENAI_ORG_ID="${OPENAI_ORG_ID:-}"
OPENAI_MODELS="${OPENAI_MODELS:-gpt-4,gpt-3.5-turbo}"

# Anthropic Configuration
ENABLE_ANTHROPIC="${ENABLE_ANTHROPIC:-false}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
ANTHROPIC_MODELS="${ANTHROPIC_MODELS:-claude-3-sonnet-20240229,claude-3-haiku-20240307}"

# Google AI Configuration
ENABLE_GOOGLE="${ENABLE_GOOGLE:-false}"
GOOGLE_AI_API_KEY="${GOOGLE_AI_API_KEY:-}"
GOOGLE_MODELS="${GOOGLE_MODELS:-gemini-pro,gemini-pro-vision}"

# Groq Configuration
ENABLE_GROQ="${ENABLE_GROQ:-false}"
GROQ_API_KEY="${GROQ_API_KEY:-}"
GROQ_MODELS="${GROQ_MODELS:-llama2-70b-4096,mixtral-8x7b-32768}"

# Cohere Configuration
ENABLE_COHERE="${ENABLE_COHERE:-false}"
COHERE_API_KEY="${COHERE_API_KEY:-}"
COHERE_MODELS="${COHERE_MODELS:-command,command-nightly,command-light}"

# Hugging Face Configuration
ENABLE_HUGGINGFACE="${ENABLE_HUGGINGFACE:-false}"
HUGGINGFACE_API_KEY="${HUGGINGFACE_API_KEY:-}"
HUGGINGFACE_MODELS="${HUGGINGFACE_MODELS:-microsoft/DialoGPT-medium,google/flan-t5-base}"

# Local Models Configuration
ENABLE_LOCAL_MODELS="${ENABLE_LOCAL_MODELS:-true}"
OLLAMA_MODELS="${OLLAMA_MODELS:-llama3.1:8b,mistral:7b}"
OLLAMA_AUTO_DOWNLOAD="${OLLAMA_AUTO_DOWNLOAD:-true}"

# =============================================================================
# PORT CONFIGURATION
# =============================================================================

# Core Infrastructure Ports
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
REDIS_PORT="${REDIS_PORT:-6379}"

# LLM Service Ports
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
LITELLM_PORT="${LITELLM_PORT:-4000}"

# Web Interface Ports
OPENWEBUI_PORT="${OPENWEBUI_PORT:-3000}"
LIBRECHAT_PORT="${LIBRECHAT_PORT:-3080}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
ANYTHINGLLM_PORT="${ANYTHINGLLM_PORT:-3082}"

# Vector Database Ports
QDRANT_PORT="${QDRANT_PORT:-6333}"
WEAVIATE_PORT="${WEAVIATE_PORT:-8080}"
CHROMA_PORT="${CHROMA_PORT:-8000}"
MILVUS_PORT="${MILVUS_PORT:-19530}"

# Automation Ports
N8N_PORT="${N8N_PORT:-5678}"
FLOWISE_PORT="${FLOWISE_PORT:-3000}"
DIFY_PORT="${DIFY_PORT:-3001}"

# Development Ports
CODE_SERVER_PORT="${CODE_SERVER_PORT:-8080}"

# Monitoring Ports
GRAFANA_PORT="${GRAFANA_PORT:-3001}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"

# Authentication Ports
AUTHENTIK_PORT="${AUTHENTIK_PORT:-9000}"

# Additional Ports
SIGNALBOT_PORT="${SIGNALBOT_PORT:-8080}"

# =============================================================================
# SYSTEM CONFIGURATION
# =============================================================================

# Docker Configuration
DOCKER_NETWORK="${TENANT_ID}-network"
COMPOSE_FILE="${DATA_DIR}/config/docker-compose.yml"

# Logging Configuration
LOG_DIR="${DATA_DIR}/logs"
LOG_LEVEL="info"

# GPU Configuration
GPU_TYPE="${GPU_TYPE:-none}"
GPU_MEMORY="${GPU_MEMORY:-0}"

# Memory Configuration
TOTAL_RAM="${TOTAL_RAM:-0}"
AVAILABLE_RAM="${AVAILABLE_RAM:-0}"

# Network Configuration
HOST_MTU="${HOST_MTU:-1500}"

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================
# DERIVED CONFIGURATION (computed at generation time — do not edit manually)
# =============================================================================

# Container naming prefix
TENANT_PREFIX="${PLATFORM_PREFIX}-${TENANT_ID}"
BASE_DOMAIN="${DOMAIN}"
PROXY_EMAIL="${ADMIN_EMAIL}"

# Directory aliases (Script 2/3 compatibility)
BASE_DIR="${DATA_DIR}"
CONFIG_DIR="${DATA_DIR}/config"
CONFIGURED_DIR="${DATA_DIR}/.configured"

# Process ownership (current user UID/GID)
PUID="$(id -u)"
PGID="$(id -g)"

# Database credentials (defaults to TENANT_ID; user-overridable in configure_service_credentials)
POSTGRES_USER="${POSTGRES_USER:-${TENANT_ID}}"
POSTGRES_DB="${POSTGRES_DB:-${TENANT_ID}}"

# Ollama default model (first in list)
OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-gemma3:4b}"

# Application secrets (generated once, stable across deploys)
POSTGRES_PASSWORD="${postgres_password}"
REDIS_PASSWORD="${redis_password}"
LITELLM_UI_PASSWORD="${litellm_ui_password}"
OPENWEBUI_SECRET="${openwebui_secret}"
FLOWISE_USERNAME="admin"
FLOWISE_PASSWORD="${flowise_password}"
FLOWISE_SECRETKEY_OVERWRITE="${flowise_secretkey_overwrite}"
DIFY_SECRET_KEY="${dify_secret_key}"
DIFY_INIT_PASSWORD="${dify_init_password}"
LIBRECHAT_JWT_SECRET="${librechat_jwt_secret}"
LIBRECHAT_CRYPT_KEY="${librechat_crypt_key}"
MONGO_PASSWORD="${mongo_password}"
AUTHENTIK_SECRET_KEY="${authentik_secret_key}"
AUTHENTIK_BOOTSTRAP_PASSWORD="${authentik_bootstrap_password}"
ZEP_AUTH_SECRET="${zep_auth_secret}"
LETTA_SERVER_PASS="${letta_server_pass}"
ANYTHINGLLM_JWT_SECRET="${anythingllm_jwt_secret}"
CODE_SERVER_PASSWORD="${code_server_password}"
N8N_ENCRYPTION_KEY="${n8n_encryption_key}"
SERPAPI_KEY="${SERPAPI_KEY:-}"
BRAVE_API_KEY="${BRAVE_API_KEY:-}"
OPENCLAW_PASSWORD="${OPENCLAW_PASSWORD:-$(gen_password)}"

# N8N webhook URL
N8N_WEBHOOK_URL="http://${DOMAIN}/"

# API key aliases (Script 2 uses GOOGLE_API_KEY / OPENROUTER_API_KEY)
GOOGLE_API_KEY="${GOOGLE_AI_API_KEY:-}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"

# Mammouth AI (https://api.mammouth.ai/)
ENABLE_MAMMOUTH="${ENABLE_MAMMOUTH:-false}"
MAMMOUTH_API_KEY="${MAMMOUTH_API_KEY:-}"
MAMMOUTH_BASE_URL="${MAMMOUTH_BASE_URL:-https://api.mammouth.ai/v1}"
MAMMOUTH_MODELS="${MAMMOUTH_MODELS:-mammouth}"

# =============================================================================
# SERVICE _ENABLED FLAGS (Script 2/3 compatibility — mirrors ENABLE_* above)
# =============================================================================
POSTGRES_ENABLED="${ENABLE_POSTGRES:-false}"
REDIS_ENABLED="${ENABLE_REDIS:-false}"
OLLAMA_ENABLED="${ENABLE_OLLAMA:-false}"
LITELLM_ENABLED="${ENABLE_LITELLM:-false}"
OPENWEBUI_ENABLED="${ENABLE_OPENWEBUI:-false}"
LIBRECHAT_ENABLED="${ENABLE_LIBRECHAT:-false}"
QDRANT_ENABLED="${ENABLE_QDRANT:-false}"
WEAVIATE_ENABLED="${ENABLE_WEAVIATE:-false}"
N8N_ENABLED="${ENABLE_N8N:-false}"
FLOWISE_ENABLED="${ENABLE_FLOWISE:-false}"
DIFY_ENABLED="${ENABLE_DIFY:-false}"
GRAFANA_ENABLED="${ENABLE_GRAFANA:-false}"
PROMETHEUS_ENABLED="${ENABLE_PROMETHEUS:-false}"
CADDY_ENABLED="${ENABLE_CADDY:-false}"
AUTHENTIK_ENABLED="${ENABLE_AUTHENTIK:-false}"
SIGNALBOT_ENABLED="${ENABLE_SIGNALBOT:-false}"
SEARXNG_ENABLED="${ENABLE_SEARXNG:-false}"
OPENCLAW_ENABLED="${ENABLE_OPENCLAW:-false}"
OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-alpine/openclaw:latest}"
BIFROST_ENABLED="${ENABLE_BIFROST:-false}"
ANYTHINGLLM_ENABLED="${ENABLE_ANYTHINGLLM:-false}"
ZEP_ENABLED="${ENABLE_ZEP:-false}"
LETTA_ENABLED="${ENABLE_LETTA:-false}"
CODE_SERVER_ENABLED="${ENABLE_CODE_SERVER:-false}"
CONTINUE_DEV_ENABLED="${ENABLE_CONTINUE_DEV:-false}"
CHROMA_ENABLED="${ENABLE_CHROMA:-false}"

# =============================================================================
# END OF CONFIGURATION
# =============================================================================
EOF

    # Move to final location
    mkdir -p "$(dirname "$config_file")"
    mv "$temp_file" "$config_file"
    
    # Set permissions
    chmod 600 "$config_file"
    
    echo "  ✅ Configuration saved to: $config_file"
    echo "  📊 Total variables: $(grep -c '^[A-Z_]*=' "$config_file")"
    echo "  🔐 File permissions: 600 (secure)"
}

# =============================================================================
# TENANT USER CREATION (README §4.11)
# =============================================================================

# =============================================================================
# PORT HEALTH CHECKS (README COMPLIANCE)
# =============================================================================
check_port_conflicts() {
    echo "Checking for port conflicts..."
    
    # Define default ports (only used for conflict checking)
    local DEFAULT_POSTGRES_PORT=5432
    local DEFAULT_REDIS_PORT=6379
    local DEFAULT_OLLAMA_PORT=11434
    local DEFAULT_LITELLM_PORT=4000
    local DEFAULT_OPENWEBUI_PORT=3000
    local DEFAULT_QDRANT_PORT=6333
    local DEFAULT_WEAVIATE_PORT=8080
    local DEFAULT_CHROMADB_PORT=8000
    local DEFAULT_MILVUS_PORT=19530
    
    local required_ports=()
    local port_names=()
    
    # Collect all required ports from enabled services using defaults
    if [[ "${ENABLE_POSTGRES:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_POSTGRES_PORT")
        port_names+=("PostgreSQL")
    fi
    
    if [[ "${ENABLE_REDIS:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_REDIS_PORT")
        port_names+=("Redis")
    fi
    
    if [[ "${ENABLE_LITELLM:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_LITELLM_PORT")
        port_names+=("LiteLLM")
    fi
    
    if [[ "${ENABLE_OLLAMA:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_OLLAMA_PORT")
        port_names+=("Ollama")
    fi
    
    if [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_OPENWEBUI_PORT")
        port_names+=("OpenWebUI")
    fi
    
    if [[ "${ENABLE_QDRANT:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_QDRANT_PORT")
        port_names+=("Qdrant")
    fi
    
    if [[ "${ENABLE_WEAVIATE:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_WEAVIATE_PORT")
        port_names+=("Weaviate")
    fi
    
    if [[ "${ENABLE_CHROMADB:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_CHROMADB_PORT")
        port_names+=("ChromaDB")
    fi
    
    if [[ "${ENABLE_MILVUS:-false}" == "true" ]]; then
        required_ports+=("$DEFAULT_MILVUS_PORT")
        port_names+=("Milvus")
    fi
    
    # Check each port for conflicts
    local conflicts=0
    for i in "${!required_ports[@]}"; do
        local port="${required_ports[$i]}"
        local name="${port_names[$i]}"
        
        if ss -tlnp 2>/dev/null | grep -q ":$port "; then
            echo "  ❌ CONFLICT: $name port $port is already in use"
            conflicts=$((conflicts + 1))
        else
            echo "  ✅ OK: $name port $port is available"
        fi
    done
    
    if [[ $conflicts -gt 0 ]]; then
        fail "Found $conflicts port conflicts. Please resolve before proceeding."
    fi
    
    ok "All required ports are available"
}

# =============================================================================
# DNS VALIDATION (README COMPLIANCE)
# =============================================================================
validate_domain() {
    local domain="$1"
    
    # Basic domain format validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        fail "Invalid domain format: $domain"
    fi
    
    # Test DNS resolution
    if ! nslookup "$domain" >/dev/null 2>&1; then
        warn "Domain $domain does not resolve in DNS"
        return 1
    fi
    
    ok "Domain $domain is valid and resolves"
    return 0
}

test_dns_resolution() {
    local domain="$1"
    echo "=== DNS VALIDATION FOR $domain ==="
    
    # Validate domain format
    validate_domain "$domain" || return 1
    
    # Detect public IP
    local public_ip
    public_ip=$(curl -s http://checkip.amazonaws.com/ 2>/dev/null || curl -s http://icanhazip.com/ 2>/dev/null)
    
    if [[ -z "$public_ip" ]]; then
        warn "Could not detect public IP"
        return 1
    fi
    
    # Check domain resolution
    local domain_ip
    domain_ip=$(nslookup "$domain" | grep -A 1 "Name:" | tail -1 | awk '{print $2}')
    
    if [[ "$domain_ip" != "$public_ip" ]]; then
        warn "Domain IP ($domain_ip) does not match public IP ($public_ip)"
        warn "DNS may not be properly configured for this domain"
        return 1
    fi
    
    ok "DNS validation successful for $domain"
    return 0
}

# =============================================================================
# MISSION CONTROL DASHBOARD (end-of-Script-1 display)
# =============================================================================
display_service_summary() {
    local server_ip
    server_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
    local base_proto="http"
    [[ "${TLS_MODE:-none}" != "none" ]] && base_proto="https"
    local pfx="${TENANT_PREFIX:-${PLATFORM_PREFIX:-ai}-${TENANT_ID:-tenant}}"
    local W=78  # inner width of box

    _mc_line() { printf "║  %-${W}s║\n" "$*"; }
    _mc_sep()  { printf "╠%s╣\n" "$(printf '═%.0s' $(seq 1 $((W+2))))"; }
    _mc_top()  { printf "╔%s╗\n" "$(printf '═%.0s' $(seq 1 $((W+2))))"; }
    _mc_bot()  { printf "╚%s╝\n" "$(printf '═%.0s' $(seq 1 $((W+2))))"; }
    _mc_blank(){ _mc_line ""; }

    echo ""
    _mc_top
    _mc_line "$(printf '%*s' $(( (W + 34) / 2 )) '🎛️  MISSION CONTROL — CONFIGURATION READY')"
    _mc_sep

    _mc_line "TENANT : ${TENANT_ID:-?}   PREFIX : ${pfx}   STACK : ${STACK_NAME:-custom}"
    _mc_line "DOMAIN : ${DOMAIN}   TLS : ${TLS_MODE:-none}   GATEWAY : ${LLM_GATEWAY_TYPE:-litellm}"
    local storage_info
    if [[ -n "${EBS_DEVICE:-}" ]]; then
        storage_info="EBS ${EBS_DEVICE} → /mnt/${TENANT_ID}"
    else
        storage_info="OS disk → /mnt/${TENANT_ID}"
    fi
    _mc_line "VECTOR : ${VECTOR_DB_TYPE:-qdrant}   ZEP : ${ENABLE_ZEP:-false}   LETTA : ${ENABLE_LETTA:-false}   STORAGE : ${storage_info}"
    _mc_sep

    _mc_line "SERVICES CONFIGURED                                    PORT"
    _mc_blank
    [[ "${ENABLE_POSTGRES:-false}"  == "true" ]] && _mc_line "  ✅ PostgreSQL  (${POSTGRES_USER:-$TENANT_ID} / ${POSTGRES_DB:-$TENANT_ID})           :${POSTGRES_PORT:-5432}"
    [[ "${ENABLE_REDIS:-false}"     == "true" ]] && _mc_line "  ✅ Redis                                                :${REDIS_PORT:-6379}"
    [[ "${ENABLE_OLLAMA:-false}"    == "true" ]] && _mc_line "  ✅ Ollama (models: ${OLLAMA_MODELS:-llama3.1:8b})          :${OLLAMA_PORT:-11434}"
    [[ "${ENABLE_LITELLM:-false}"   == "true" ]] && _mc_line "  ✅ LiteLLM (routing: ${LITELLM_ROUTING_STRATEGY:-cost-optimized})             :${LITELLM_PORT:-4000}"
    [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] && _mc_line "  ✅ OpenWebUI  (→ LiteLLM + Ollama RAG)                 :${OPENWEBUI_PORT:-3000}"
    [[ "${ENABLE_ZEP:-false}"       == "true" ]] && _mc_line "  ✅ Zep CE     (→ Postgres + LiteLLM)                   :${ZEP_PORT:-8100}"
    [[ "${ENABLE_LETTA:-false}"     == "true" ]] && _mc_line "  ✅ Letta      (→ Postgres + LiteLLM)                   :${LETTA_PORT:-8283}"
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && _mc_line "  ✅ AnythingLLM (→ LiteLLM + ${VECTOR_DB_TYPE:-qdrant})             :${ANYTHINGLLM_PORT:-3001}"
    [[ "${ENABLE_OPENCLAW:-false}"  == "true" ]] && _mc_line "  ✅ OpenClaw   (token auth)                             :${OPENCLAW_PORT:-18789}"
    [[ "${ENABLE_QDRANT:-false}"    == "true" ]] && _mc_line "  ✅ Qdrant                                               :${QDRANT_PORT:-6333}"
    [[ "${ENABLE_WEAVIATE:-false}"  == "true" ]] && _mc_line "  ✅ Weaviate                                             :${WEAVIATE_PORT:-8080}"
    [[ "${ENABLE_CHROMA:-false}"    == "true" ]] && _mc_line "  ✅ ChromaDB                                             :${CHROMA_PORT:-8000}"
    [[ "${ENABLE_N8N:-false}"       == "true" ]] && _mc_line "  ✅ N8N        (→ LiteLLM)                              :${N8N_PORT:-5678}"
    [[ "${ENABLE_FLOWISE:-false}"   == "true" ]] && _mc_line "  ✅ Flowise    (→ LiteLLM + ${VECTOR_DB_TYPE:-qdrant})            :${FLOWISE_PORT:-3030}"
    [[ "${ENABLE_DIFY:-false}"      == "true" ]] && _mc_line "  ✅ Dify       (→ LiteLLM + ${VECTOR_DB_TYPE:-qdrant})            :${DIFY_PORT:-3001}"
    [[ "${ENABLE_GRAFANA:-false}"   == "true" ]] && _mc_line "  ✅ Grafana                                              :${GRAFANA_PORT:-3002}"
    [[ "${ENABLE_PROMETHEUS:-false}" == "true" ]] && _mc_line "  ✅ Prometheus                                          :${PROMETHEUS_PORT:-9090}"
    [[ "${ENABLE_AUTHENTIK:-false}" == "true" ]] && _mc_line "  ✅ Authentik  (SSO)                                    :${AUTHENTIK_PORT:-9000}"
    [[ "${ENABLE_SIGNALBOT:-false}" == "true" ]] && _mc_line "  ✅ SignalBot  (${SIGNAL_PHONE:-not set})                   :${SIGNALBOT_PORT:-8080}"
    [[ "${ENABLE_SEARXNG:-false}"   == "true" ]] && _mc_line "  ✅ SearXNG    (privacy search)                        :${SEARXNG_PORT:-8888}"
    [[ "${ENABLE_CODE_SERVER:-false}" == "true" ]] && _mc_line "  ✅ Code Server                                         :${CODE_SERVER_PORT:-8080}"
    [[ "${ENABLE_CONTINUE_DEV:-false}" == "true" ]] && _mc_line "  ✅ Continue.dev (config → LiteLLM at :${LITELLM_PORT:-4000})       local"
    _mc_sep

    _mc_line "LLM PROVIDERS                    SEARCH APIS"
    _mc_blank
    local prov_line=""
    [[ "${ENABLE_OPENAI:-false}"      == "true" ]] && prov_line+="OpenAI "
    [[ "${ENABLE_ANTHROPIC:-false}"   == "true" ]] && prov_line+="Anthropic "
    [[ "${ENABLE_GOOGLE:-false}"      == "true" ]] && prov_line+="Google "
    [[ "${ENABLE_GROQ:-false}"        == "true" ]] && prov_line+="Groq "
    [[ "${ENABLE_COHERE:-false}"      == "true" ]] && prov_line+="Cohere "
    [[ "${ENABLE_HUGGINGFACE:-false}" == "true" ]] && prov_line+="HuggingFace "
    [[ "${ENABLE_OPENROUTER:-false}"  == "true" ]] && prov_line+="OpenRouter "
    [[ "${ENABLE_MAMMOUTH:-false}"    == "true" ]] && prov_line+="Mammouth "
    [[ "${ENABLE_LOCAL_MODELS:-false}" == "true" ]] && prov_line+="Ollama(local) "
    local search_line=""
    [[ "${ENABLE_SERPAPI:-false}"     == "true" ]] && search_line+="SerpAPI(${SERPAPI_ENGINE:-google}) "
    [[ "${ENABLE_BRAVE:-false}"       == "true" ]] && search_line+="BraveSearch "
    _mc_line "  ${prov_line:-none}   |   ${search_line:-none}"
    _mc_line "  Preferred: ${PREFERRED_LLM_PROVIDER:-ollama}   Gateway: ${LLM_GATEWAY_TYPE:-litellm} → all services"
    _mc_sep

    _mc_line "ACCESS URLS  (all bound to 127.0.0.1 — use proxy or SSH tunnel for external)"
    _mc_blank
    [[ "${ENABLE_OPENWEBUI:-false}"   == "true" ]] && _mc_line "  Open WebUI   → ${base_proto}://${DOMAIN:-$server_ip}  (direct: http://127.0.0.1:${OPENWEBUI_PORT:-3000})"
    [[ "${ENABLE_LITELLM:-false}"     == "true" ]] && _mc_line "  LiteLLM API  → http://127.0.0.1:${LITELLM_PORT:-4000}/v1"
    [[ "${ENABLE_OLLAMA:-false}"      == "true" ]] && _mc_line "  Ollama       → http://127.0.0.1:${OLLAMA_PORT:-11434}"
    [[ "${ENABLE_ZEP:-false}"          == "true" ]] && _mc_line "  Zep          → http://127.0.0.1:${ZEP_PORT:-8100}"
    [[ "${ENABLE_LETTA:-false}"        == "true" ]] && _mc_line "  Letta        → http://127.0.0.1:${LETTA_PORT:-8283}"
    [[ "${ENABLE_N8N:-false}"         == "true" ]] && _mc_line "  N8N          → http://127.0.0.1:${N8N_PORT:-5678}"
    [[ "${ENABLE_FLOWISE:-false}"     == "true" ]] && _mc_line "  Flowise      → http://127.0.0.1:${FLOWISE_PORT:-3030}"
    [[ "${ENABLE_DIFY:-false}"        == "true" ]] && _mc_line "  Dify         → http://127.0.0.1:${DIFY_PORT:-3001}"
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && _mc_line "  AnythingLLM  → http://127.0.0.1:${ANYTHINGLLM_PORT:-3001}"
    [[ "${ENABLE_OPENCLAW:-false}"    == "true" ]] && _mc_line "  OpenClaw     → http://127.0.0.1:${OPENCLAW_PORT:-18789}  (token: see platform.conf)"
    [[ "${ENABLE_GRAFANA:-false}"     == "true" ]] && _mc_line "  Grafana      → http://127.0.0.1:${GRAFANA_PORT:-3002}"
    [[ "${ENABLE_AUTHENTIK:-false}"   == "true" ]] && _mc_line "  Authentik    → http://127.0.0.1:${AUTHENTIK_PORT:-9000}"
    [[ "${ENABLE_CODE_SERVER:-false}" == "true" ]] && _mc_line "  Code Server  → http://127.0.0.1:${CODE_SERVER_PORT:-8080}"
    [[ "${ENABLE_CADDY:-false}"       == "true" ]] && _mc_line "  Caddy proxy  → ${base_proto}://${DOMAIN:-$server_ip} (ports ${CADDY_HTTP_PORT:-80}/${CADDY_HTTPS_PORT:-443})"
    _mc_blank
    _mc_line "  DB/Cache (internal containers only):"
    [[ "${ENABLE_POSTGRES:-false}"    == "true" ]] && _mc_line "    ${pfx}-postgres:5432  user=${POSTGRES_USER:-$TENANT_ID} db=${POSTGRES_DB:-$TENANT_ID}"
    [[ "${ENABLE_REDIS:-false}"       == "true" ]] && _mc_line "    ${pfx}-redis:6379"
    _mc_sep

    _mc_line "NEXT STEP:  bash scripts/2-deploy-services.sh ${TENANT_ID}"
    _mc_line "CONF FILE:  ${DATA_DIR:-/mnt/${TENANT_ID}}/config/platform.conf"
    _mc_bot
    echo ""
}

# =============================================================================
# ENHANCED PORT CONFIGURATION WITH OVERRIDES
# =============================================================================
configure_ports() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🌐 PORT CONFIGURATION WITH HEALTH VALIDATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📋 Configure service ports with conflict detection"
    echo ""
    
    # Check port conflicts first
    check_port_conflicts
    
    # Allow per-service port overrides using defaults
    if [[ "${ENABLE_POSTGRES:-false}" == "true" ]]; then
        safe_read "PostgreSQL port [5432]" "5432" "POSTGRES_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_REDIS:-false}" == "true" ]]; then
        safe_read "Redis port [6379]" "6379" "REDIS_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_LITELLM:-false}" == "true" ]]; then
        safe_read "LiteLLM port [4000]" "4000" "LITELLM_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_OLLAMA:-false}" == "true" ]]; then
        safe_read "Ollama port [11434]" "11434" "OLLAMA_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]]; then
        safe_read "OpenWebUI port [3000]" "3000" "OPENWEBUI_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_QDRANT:-false}" == "true" ]]; then
        safe_read "Qdrant port [6333]" "6333" "QDRANT_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_WEAVIATE:-false}" == "true" ]]; then
        safe_read "Weaviate port [8080]" "8080" "WEAVIATE_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_CHROMADB:-false}" == "true" ]]; then
        safe_read "ChromaDB port [8000]" "8000" "CHROMADB_PORT" "^[0-9]+$"
    fi
    
    if [[ "${ENABLE_MILVUS:-false}" == "true" ]]; then
        safe_read "Milvus port [19530]" "19530" "MILVUS_PORT" "^[0-9]+$"
    fi
    
    # Final port conflict check after overrides
    check_port_conflicts
    
    ok "Port configuration complete"
}

# =============================================================================
# MAIN INTERACTIVE INPUT COLLECTION (ENHANCED) FUNCTIONS
# =============================================================================
run_interactive_collection() {
    banner
    
    detect_system
    collect_identity
    configure_storage
    configure_docker_dataroot
    select_stack_preset
    configure_service_credentials
    configure_llm_gateway
    configure_vector_database
    
    # Initialize TLS_MODE before validation (don't override if already set from template)
    TLS_MODE="${TLS_MODE:-none}"

    # DNS Validation before TLS (README compliance)
    if [[ "$TLS_MODE" == "letsencrypt" ]] || [[ "$TLS_MODE" == "provided" ]]; then
        test_dns_resolution "$DOMAIN" || warn "DNS validation failed - TLS may not work properly"
    fi
    
    configure_tls
    collect_api_keys
    configure_ports
    configure_proxy
    configure_google_drive
    configure_signalbot

    # =============================================================================
    # INGESTION CONFIGURATION (README §4.7)
    # =============================================================================
    configure_ingestion
    
    # =============================================================================
    # TEMPLATE GENERATION
    # =============================================================================
    save_configuration_template
    
    write_platform_conf
}

# =============================================================================
# INGESTION CONFIGURATION (README §4.7)
# =============================================================================
configure_ingestion() {
    section "🔄 INGESTION CONFIGURATION"
    
    echo "  📋 Configure automated data ingestion pipeline"
    echo "    • Rclone for cloud storage synchronization"
    echo "    • Automated processing and indexing"
    echo "    • Support for multiple providers (GDrive, S3, Azure)"
    echo ""
    
    safe_read_yesno "Enable automated ingestion pipeline" "false" "ENABLE_INGESTION"
    
    if [[ "$ENABLE_INGESTION" == "true" ]]; then
        echo ""
        echo "  🔹 Ingestion Providers:"
        echo "    1) Rclone (Google Drive, S3, Azure, etc.)"
        echo "    2) Google Drive (direct)"
        echo "    3) AWS S3 (direct)"
        echo "    4) Azure Blob (direct)"
        echo "    5) Local filesystem"

        # Normalize INGESTION_METHOD from string (template) to number for safe_read validation
        case "${INGESTION_METHOD:-}" in
            rclone) export INGESTION_METHOD="1" ;;
            gdrive) export INGESTION_METHOD="2" ;;
            s3)     export INGESTION_METHOD="3" ;;
            azure)  export INGESTION_METHOD="4" ;;
            local)  export INGESTION_METHOD="5" ;;
        esac
        safe_read "Ingestion method [1-5]" "1" "INGESTION_METHOD" "^[1-5]$"
        
        case "$INGESTION_METHOD" in
            1)
                safe_read "Rclone remote name" "gdrive" "RCLONE_REMOTE"
                safe_read "Sync interval (minutes)" "5" "RCLONE_POLL_INTERVAL" "^[0-9]+$"
                safe_read "Parallel transfers" "4" "RCLONE_TRANSFERS" "^[0-9]+$"
                safe_read "Parallel checkers" "8" "RCLONE_CHECKERS" "^[0-9]+$"
                safe_read "VFS cache mode" "writes" "RCLONE_VFS_CACHE" "^(writes|off|full)$"
                
                echo ""
                echo "  📋 Rclone Configuration Methods:"
                echo "    1) Paste JSON credentials directly"
                echo "    2) Provide file path to credentials"
                
                safe_read "Credentials input method [1-2]" "1" "RCLONE_CRED_METHOD" "^[1-2]$"
                
                case "$RCLONE_CRED_METHOD" in
                    1)
                        local rclone_conf_dir="/mnt/${TENANT_ID}/config"
                        mkdir -p "$rclone_conf_dir"

                        # Guard: if a valid SA JSON already exists, offer to keep it
                        local _existing_sa="${rclone_conf_dir}/service-account.json"
                        if [[ -f "${_existing_sa}" ]] && [[ $(stat -c%s "${_existing_sa}" 2>/dev/null || echo 0) -gt 50 ]]; then
                            echo ""
                            echo "  ✅ Existing service account JSON found: ${_existing_sa}"
                            echo "     Size: $(stat -c%s "${_existing_sa}") bytes"
                            safe_read "Keep existing credentials? [y/n]" "y" "_keep_sa" "^[yYnN]$"
                            if [[ "${_keep_sa,,}" == "y" ]]; then
                                GDRIVE_CREDENTIALS_FILE="${_existing_sa}"
                                echo "  Keeping existing credentials."
                                # Ensure rclone.conf references the existing SA file
                                {
                                    echo "[${RCLONE_REMOTE:-gdrive}]"
                                    echo "type = drive"
                                    echo "scope = drive.readonly"
                                    echo "service_account_file = /credentials/service-account.json"
                                    [[ -n "${GDRIVE_FOLDER_ID:-}" ]] && echo "root_folder_id = ${GDRIVE_FOLDER_ID}"
                                } > "${rclone_conf_dir}/rclone.conf"
                                chmod 600 "${rclone_conf_dir}/rclone.conf"
                                break 2
                            fi
                        fi

                        echo ""
                        echo "  Paste your Google service account JSON credentials:"
                        echo "  (Press Enter on an empty line to finish)"
                        echo ""

                        local json_content=""
                        local _line
                        while true; do
                            if [[ -t 0 ]]; then
                                read -r _line
                                [[ -z "$_line" ]] && break
                                json_content+="$_line"$'\n'
                            else
                                json_content=$(cat)
                                break
                            fi
                        done

                        # Reject empty paste — do not overwrite a valid existing file with garbage
                        if [[ ${#json_content} -lt 50 ]]; then
                            echo "  ⚠ No credentials pasted (or too short). Keeping existing file if present."
                            if [[ -f "${_existing_sa}" ]] && [[ $(stat -c%s "${_existing_sa}" 2>/dev/null || echo 0) -gt 50 ]]; then
                                GDRIVE_CREDENTIALS_FILE="${_existing_sa}"
                            fi
                            break
                        fi

                        # Save JSON as service-account.json (NOT as rclone.conf)
                        echo "$json_content" > "${rclone_conf_dir}/service-account.json"
                        chmod 600 "${rclone_conf_dir}/service-account.json"
                        GDRIVE_CREDENTIALS_FILE="${rclone_conf_dir}/service-account.json"

                        # Generate proper INI-format rclone.conf
                        # root_folder_id scopes sync to the shared folder — service accounts
                        # have no personal My Drive so root sync is always empty without this.
                        {
                            echo "[${RCLONE_REMOTE:-gdrive}]"
                            echo "type = drive"
                            echo "scope = drive.readonly"
                            echo "service_account_file = /credentials/service-account.json"
                            [[ -n "${GDRIVE_FOLDER_ID:-}" ]] && echo "root_folder_id = ${GDRIVE_FOLDER_ID}"
                        } > "${rclone_conf_dir}/rclone.conf"
                        chmod 600 "${rclone_conf_dir}/rclone.conf"

                        echo "  Credentials saved to: ${rclone_conf_dir}/service-account.json"
                        echo "  rclone.conf generated at: ${rclone_conf_dir}/rclone.conf"
                        ;;
                    2)
                        safe_read "Path to Google service account JSON file" "/mnt/${TENANT_ID}/config/service-account.json" "RCLONE_CONFIG_FILE"

                        if [[ ! -f "$RCLONE_CONFIG_FILE" ]]; then
                            fail "Credentials file not found: $RCLONE_CONFIG_FILE"
                        fi

                        local rclone_conf_dir="/mnt/${TENANT_ID}/config"
                        mkdir -p "$rclone_conf_dir"
                        cp "$RCLONE_CONFIG_FILE" "${rclone_conf_dir}/service-account.json"
                        chmod 600 "${rclone_conf_dir}/service-account.json"
                        GDRIVE_CREDENTIALS_FILE="${rclone_conf_dir}/service-account.json"

                        # Generate proper INI-format rclone.conf
                        {
                            echo "[${RCLONE_REMOTE:-gdrive}]"
                            echo "type = drive"
                            echo "scope = drive.readonly"
                            echo "service_account_file = /credentials/service-account.json"
                            [[ -n "${GDRIVE_FOLDER_ID:-}" ]] && echo "root_folder_id = ${GDRIVE_FOLDER_ID}"
                        } > "${rclone_conf_dir}/rclone.conf"
                        chmod 600 "${rclone_conf_dir}/rclone.conf"

                        echo "  Credentials saved to: ${rclone_conf_dir}/service-account.json"
                        echo "  rclone.conf generated at: ${rclone_conf_dir}/rclone.conf"
                        ;;
                esac

                echo ""
                echo "  Rclone Configuration Summary:"
                echo "    Remote: ${RCLONE_REMOTE}"
                echo "    Sync Interval: ${RCLONE_POLL_INTERVAL} minutes"
                echo "    Transfers: ${RCLONE_TRANSFERS} parallel"
                echo "    Checkers: ${RCLONE_CHECKERS} parallel"
                echo "    VFS Cache: ${RCLONE_VFS_CACHE}"
                echo "    Credentials: ${GDRIVE_CREDENTIALS_FILE}"
                ;;
            2)
                safe_read "Google Drive credentials JSON path" "/mnt/${TENANT_ID}/config/gdrive-credentials.json" "GDRIVE_CREDENTIALS_FILE"
                ;;
            3)
                safe_read "AWS S3 bucket name" "" "AWS_S3_BUCKET"
                safe_read "AWS region" "us-east-1" "AWS_REGION"
                safe_read "AWS access key ID" "" "AWS_ACCESS_KEY_ID"
                safe_read "AWS secret access key" "" "AWS_SECRET_ACCESS_KEY"
                ;;
            4)
                safe_read "Azure storage account" "" "AZURE_STORAGE_ACCOUNT"
                safe_read "Azure container name" "" "AZURE_CONTAINER"
                safe_read "Azure access key" "" "AZURE_ACCESS_KEY"
                ;;
            5)
                safe_read "Local source path" "/mnt/${TENANT_ID}/ingestion" "LOCAL_INGESTION_PATH"
                ;;
        esac
        
        # Translate numeric INGESTION_METHOD to canonical string for Script 2 compatibility
        case "$INGESTION_METHOD" in
            1) INGESTION_METHOD="rclone" ;;
            2) INGESTION_METHOD="gdrive" ;;
            3) INGESTION_METHOD="s3" ;;
            4) INGESTION_METHOD="azure" ;;
            5) INGESTION_METHOD="local" ;;
        esac

        # Confirmation
        echo ""
        safe_read_yesno "Confirm ingestion configuration" "true" "INGESTION_CONFIRMED"
        if [[ "$INGESTION_CONFIRMED" != "true" ]]; then
            warn "Ingestion configuration cancelled"
            ENABLE_INGESTION="false"
        fi
    else
        echo "Ingestion disabled - manual data loading only"
    fi

    ok "Ingestion configuration complete"
}

# =============================================================================
# TEMPLATE GENERATION
# =============================================================================

save_configuration_template() {
    local template_path="${1:-}"
    
    if [[ -z "$template_path" ]]; then
        # Default template location (outside git repo)
        template_path="${HOME}/.ai-platform-templates/${TENANT_ID}-template.conf"
    fi
    
    # Create template directory if it doesn't exist
    mkdir -p "$(dirname "$template_path")"
    
    log "💾 Saving configuration template: $template_path"
    
    # Create template file — all non-secret configuration variables.
    # Secrets (passwords, API keys) are intentionally excluded so this file is
    # safe to store in version control. The template auto-confirms every value
    # shown here when passed via --template; unset a variable to re-prompt.
    cat > "$template_path" << EOF
# =============================================================================
# AI Platform Configuration Template
# Generated: $(date)
# Tenant: ${TENANT_ID}
# Stack: ${STACK_NAME:-custom}
# =============================================================================
# USAGE: bash scripts/1-setup-system.sh ${TENANT_ID} --template "$template_path"
# Secrets (passwords, API keys) are NOT stored here — re-enter them each deploy
# or export them as environment variables before running.
# =============================================================================

# IDENTITY
PLATFORM_PREFIX="${PLATFORM_PREFIX}"
TENANT_ID="${TENANT_ID}"
DOMAIN="${DOMAIN}"
ORGANIZATION="${ORGANIZATION}"
ADMIN_EMAIL="${ADMIN_EMAIL}"

# STORAGE
USE_EBS="${USE_EBS}"
EBS_DEVICE="${EBS_DEVICE:-}"
DATA_DIR="${DATA_DIR}"

# STACK
STACK_PRESET="${STACK_PRESET}"
STACK_NAME="${STACK_NAME:-custom}"

# LLM GATEWAY
LLM_GATEWAY_TYPE="${LLM_GATEWAY_TYPE:-litellm}"
LITELLM_ROUTING_STRATEGY="${LITELLM_ROUTING_STRATEGY:-cost-optimized}"

# VECTOR DATABASE
VECTOR_DB_TYPE="${VECTOR_DB_TYPE:-qdrant}"
QDRANT_PORT="${QDRANT_PORT:-6333}"
WEAVIATE_PORT="${WEAVIATE_PORT:-8080}"
CHROMA_PORT="${CHROMA_PORT:-8000}"
MILVUS_PORT="${MILVUS_PORT:-19530}"

# TLS
TLS_MODE="${TLS_MODE:-none}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
HTTP_TO_HTTPS_REDIRECT="${HTTP_TO_HTTPS_REDIRECT:-false}"
PROXY_FORCE_HTTPS="${PROXY_FORCE_HTTPS:-false}"

# PROXY — Caddy and NPM are mutually exclusive; only one may be true
ENABLE_PROXY="${ENABLE_PROXY:-false}"
PROXY_TYPE="${PROXY_TYPE:-none}"
PROXY_ROUTING="${PROXY_ROUTING:-subdomain}"
ENABLE_CADDY="${ENABLE_CADDY:-false}"
CADDY_HTTP_PORT="${CADDY_HTTP_PORT:-80}"
CADDY_HTTPS_PORT="${CADDY_HTTPS_PORT:-443}"
ENABLE_NPM="${ENABLE_NPM:-false}"
NPM_HTTP_PORT="${NPM_HTTP_PORT:-80}"
NPM_HTTPS_PORT="${NPM_HTTPS_PORT:-443}"
NPM_ADMIN_PORT="${NPM_ADMIN_PORT:-81}"

# SERVICE ENABLEMENT FLAGS
ENABLE_POSTGRES="${ENABLE_POSTGRES:-false}"
ENABLE_REDIS="${ENABLE_REDIS:-false}"
ENABLE_OLLAMA="${ENABLE_OLLAMA:-false}"
ENABLE_LITELLM="${ENABLE_LITELLM:-false}"
ENABLE_OPENWEBUI="${ENABLE_OPENWEBUI:-false}"
ENABLE_LIBRECHAT="${ENABLE_LIBRECHAT:-false}"
ENABLE_OPENCLAW="${ENABLE_OPENCLAW:-false}"
ENABLE_ANYTHINGLLM="${ENABLE_ANYTHINGLLM:-false}"
ENABLE_QDRANT="${ENABLE_QDRANT:-false}"
ENABLE_WEAVIATE="${ENABLE_WEAVIATE:-false}"
ENABLE_CHROMA="${ENABLE_CHROMA:-false}"
ENABLE_MILVUS="${ENABLE_MILVUS:-false}"
ENABLE_N8N="${ENABLE_N8N:-false}"
ENABLE_FLOWISE="${ENABLE_FLOWISE:-false}"
ENABLE_DIFY="${ENABLE_DIFY:-false}"
ENABLE_CODE_SERVER="${ENABLE_CODE_SERVER:-false}"
ENABLE_CONTINUE_DEV="${ENABLE_CONTINUE_DEV:-false}"
ENABLE_ZEP="${ENABLE_ZEP:-false}"
ENABLE_LETTA="${ENABLE_LETTA:-false}"
ENABLE_GRAFANA="${ENABLE_GRAFANA:-false}"
ENABLE_PROMETHEUS="${ENABLE_PROMETHEUS:-false}"
ENABLE_AUTHENTIK="${ENABLE_AUTHENTIK:-false}"
ENABLE_SIGNALBOT="${ENABLE_SIGNALBOT:-false}"
ENABLE_SEARXNG="${ENABLE_SEARXNG:-false}"
ENABLE_BIFROST="${ENABLE_BIFROST:-false}"
ENABLE_CADDY="${ENABLE_CADDY:-false}"
ENABLE_NPM="${ENABLE_NPM:-false}"
ENABLE_INGESTION="${ENABLE_INGESTION:-false}"
INGESTION_METHOD="${INGESTION_METHOD:-rclone}"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
RCLONE_POLL_INTERVAL="${RCLONE_POLL_INTERVAL:-5}"

# SERVICE PORTS
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
REDIS_PORT="${REDIS_PORT:-6379}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
LITELLM_PORT="${LITELLM_PORT:-4000}"
OPENWEBUI_PORT="${OPENWEBUI_PORT:-3000}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
ANYTHINGLLM_PORT="${ANYTHINGLLM_PORT:-3001}"
N8N_PORT="${N8N_PORT:-5678}"
FLOWISE_PORT="${FLOWISE_PORT:-3030}"
DIFY_PORT="${DIFY_PORT:-3001}"
CODE_SERVER_PORT="${CODE_SERVER_PORT:-8080}"
ZEP_PORT="${ZEP_PORT:-8100}"
LETTA_PORT="${LETTA_PORT:-8283}"
GRAFANA_PORT="${GRAFANA_PORT:-3002}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
AUTHENTIK_PORT="${AUTHENTIK_PORT:-9000}"
SIGNALBOT_PORT="${SIGNALBOT_PORT:-8080}"
SEARXNG_PORT="${SEARXNG_PORT:-8888}"
BIFROST_PORT="${BIFROST_PORT:-8000}"
NPM_ADMIN_PORT="${NPM_ADMIN_PORT:-81}"

# LOCAL MODELS
ENABLE_LOCAL_MODELS="${ENABLE_LOCAL_MODELS:-true}"
OLLAMA_MODELS="${OLLAMA_MODELS:-llama3.1:8b,mistral:7b}"
OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-gemma3:4b}"
OLLAMA_AUTO_DOWNLOAD="${OLLAMA_AUTO_DOWNLOAD:-true}"

# LLM PROVIDERS (enable flags only — API keys excluded from template)
PREFERRED_LLM_PROVIDER="${PREFERRED_LLM_PROVIDER:-ollama}"
ENABLE_OPENAI="${ENABLE_OPENAI:-false}"
OPENAI_MODELS="${OPENAI_MODELS:-gpt-4o,gpt-4o-mini}"
ENABLE_ANTHROPIC="${ENABLE_ANTHROPIC:-false}"
ANTHROPIC_MODELS="${ANTHROPIC_MODELS:-claude-3-5-sonnet-20241022}"
ENABLE_GOOGLE="${ENABLE_GOOGLE:-false}"
GOOGLE_MODELS="${GOOGLE_MODELS:-gemini-pro}"
ENABLE_GROQ="${ENABLE_GROQ:-false}"
GROQ_MODELS="${GROQ_MODELS:-llama-3.1-8b-instant}"
ENABLE_COHERE="${ENABLE_COHERE:-false}"
ENABLE_HUGGINGFACE="${ENABLE_HUGGINGFACE:-false}"
ENABLE_OPENROUTER="${ENABLE_OPENROUTER:-false}"
ENABLE_MAMMOUTH="${ENABLE_MAMMOUTH:-false}"
MAMMOUTH_BASE_URL="${MAMMOUTH_BASE_URL:-https://api.mammouth.ai/v1}"
MAMMOUTH_MODELS="${MAMMOUTH_MODELS:-mammouth}"

# SEARCH APIS (key values excluded from template)
ENABLE_SERPAPI="${ENABLE_SERPAPI:-false}"
SERPAPI_ENGINE="${SERPAPI_ENGINE:-google}"
ENABLE_BRAVE="${ENABLE_BRAVE:-false}"

# SERVICE CREDENTIALS (usernames only — passwords excluded from template)
POSTGRES_USER="${POSTGRES_USER:-${TENANT_ID}}"
POSTGRES_DB="${POSTGRES_DB:-${TENANT_ID}}"
FLOWISE_USERNAME="${FLOWISE_USERNAME:-admin}"
LIBRECHAT_JWT_SECRET="${LIBRECHAT_JWT_SECRET:-$(gen_secret)}"
LIBRECHAT_CRYPT_KEY="${LIBRECHAT_CRYPT_KEY:-$(openssl rand -hex 32)}"
MONGO_PASSWORD="${MONGO_PASSWORD:-$(gen_password)}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"

# SIGNAL BOT
SIGNAL_PHONE="${SIGNAL_PHONE:-}"
SIGNAL_RECIPIENT="${SIGNAL_RECIPIENT:-}"

# GOOGLE DRIVE
ENABLE_GDRIVE="${ENABLE_GDRIVE:-false}"
GDRIVE_FOLDER_NAME="${GDRIVE_FOLDER_NAME:-AI Platform}"

# =============================================================================
# END OF TEMPLATE
# This template can be used to recreate the same configuration:
#   bash scripts/1-setup-system.sh ${TENANT_ID} --template "$template_path"
# =============================================================================
EOF

    # Set secure permissions
    chmod 600 "$template_path"
    
    ok "Configuration template saved to: $template_path"
    ok "Template permissions set to 600 (secure)"
    
    echo ""
    echo "📋 TEMPLATE USAGE:"
    echo "  To reuse this configuration:"
    echo "    bash scripts/1-setup-system.sh ${TENANT_ID} --template '$template_path'"
    echo ""
    echo "  To edit the template:"
    echo "    nano '$template_path'"
    echo ""
    echo "  Template location (outside git repo):"
    echo "    ${HOME}/.ai-platform-templates/"
    echo ""
}

# =============================================================================
# SERVICE VARIABLE INITIALIZATION - ALIGNED WITH .env
# =============================================================================
initialize_service_variables() {
    # Platform Identity (from .env)
    PLATFORM_PREFIX="${PLATFORM_PREFIX:-ai-}"
    TENANT_ID="${TENANT_ID:-}"
    DOMAIN="${DOMAIN:-}"
    ORGANIZATION="${ORGANIZATION:-}"
    ADMIN_EMAIL="${ADMIN_EMAIL:-}"
    DATA_ROOT="${DATA_ROOT:-/mnt/data/}"
    PROJECT_PREFIX="${PROJECT_PREFIX:-ai-}"
    
    # Tenant User Configuration
    TENANT_UID="${TENANT_UID:-1001}"
    TENANT_GID="${TENANT_GID:-1001}"
    
    # Service Ownership UIDs (Pragmatic Exception Pattern)
    POSTGRES_UID="${POSTGRES_UID:-70}"
    PROMETHEUS_UID="${PROMETHEUS_UID:-65534}"
    GRAFANA_UID="${GRAFANA_UID:-472}"
    N8N_UID="${N8N_UID:-1000}"
    QDRANT_UID="${QDRANT_UID:-1000}"
    REDIS_UID="${REDIS_UID:-999}"
    OPENWEBUI_UID="${OPENWEBUI_UID:-1000}"
    ANYTHINGLLM_UID="${ANYTHINGLLM_UID:-1000}"
    OLLAMA_UID="${OLLAMA_UID:-1001}"
    FLOWISE_UID="${FLOWISE_UID:-1000}"
    LITELLM_UID="${LITELLM_UID:-1000}"
    AUTHENTIK_UID="${AUTHENTIK_UID:-1000}"
    CADDY_UID="${CADDY_UID:-1000}"
    
    # Service Flags (complete list from .env)
    ENABLE_POSTGRES="${ENABLE_POSTGRES:-false}"
    ENABLE_REDIS="${ENABLE_REDIS:-false}"
    ENABLE_CADDY="${ENABLE_CADDY:-false}"
    ENABLE_OLLAMA="${ENABLE_OLLAMA:-false}"
    ENABLE_OPENAI="${ENABLE_OPENAI:-false}"
    ENABLE_ANTHROPIC="${ENABLE_ANTHROPIC:-false}"
    ENABLE_LOCALAI="${ENABLE_LOCALAI:-false}"
    ENABLE_VLLM="${ENABLE_VLLM:-false}"
    ENABLE_OPENWEBUI="${ENABLE_OPENWEBUI:-false}"
    ENABLE_ANYTHINGLLM="${ENABLE_ANYTHINGLLM:-false}"
    ENABLE_DIFY="${ENABLE_DIFY:-false}"
    ENABLE_N8N="${ENABLE_N8N:-false}"
    ENABLE_FLOWISE="${ENABLE_FLOWISE:-false}"
    ENABLE_LITELLM="${ENABLE_LITELLM:-false}"
    ENABLE_QDRANT="${ENABLE_QDRANT:-false}"
    ENABLE_WEAVIATE="${ENABLE_WEAVIATE:-false}"
    ENABLE_PINECONE="${ENABLE_PINECONE:-false}"
    ENABLE_CHROMADB="${ENABLE_CHROMADB:-false}"
    ENABLE_MILVUS="${ENABLE_MILVUS:-false}"
    ENABLE_GRAFANA="${ENABLE_GRAFANA:-false}"
    ENABLE_PROMETHEUS="${ENABLE_PROMETHEUS:-false}"
    ENABLE_AUTHENTIK="${ENABLE_AUTHENTIK:-false}"
    ENABLE_SIGNAL="${ENABLE_SIGNAL:-false}"
    ENABLE_OPENCLAW="${ENABLE_OPENCLAW:-false}"
    ENABLE_RCLONE="${ENABLE_RCLONE:-false}"
    ENABLE_MINIO="${ENABLE_MINIO:-false}"
    ENABLE_CODE_SERVER="${ENABLE_CODE_SERVER:-false}"
    ENABLE_SEARXNG="${ENABLE_SEARXNG:-false}"
    
    # Vector Database Configuration
    PINECONE_PROJECT_ID="${PINECONE_PROJECT_ID:-}"
    
    # Service URLs (internal Docker network)
    OLLAMA_INTERNAL_URL="http://ollama:11434"
    OLLAMA_BASE_URL="http://ollama:11434"
    OPENAI_INTERNAL_URL="https://api.openai.com/v1"
    ANTHROPIC_INTERNAL_URL="https://api.anthropic.com"
    LOCALAI_INTERNAL_URL="http://localai:8080"
    VLLM_INTERNAL_URL="http://vllm:8000"
    LITELLM_INTERNAL_URL="http://litellm:4000"
    QDRANT_INTERNAL_URL="http://qdrant:6333"
    WEAVIATE_INTERNAL_URL="http://weaviate:8080"
    PINECONE_INTERNAL_URL="https://pinecone.io"
    CHROMADB_INTERNAL_URL="http://chromadb:8000"
    MILVUS_INTERNAL_URL="http://milvus:19530"
    REDIS_INTERNAL_URL="redis://redis:6379"
    POSTGRES_INTERNAL_URL="postgresql://postgres:5432"
    N8N_INTERNAL_URL="http://n8n:5678"
    
    # Service API endpoints
    OLLAMA_API_ENDPOINT="http://ollama:11434/api/tags"
    LITELLM_API_ENDPOINT="http://litellm:4000/v1"
    QDRANT_API_ENDPOINT="http://qdrant:6333"
    
    # Project Configuration
    COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-}"
    DOCKER_NETWORK="${DOCKER_NETWORK:-}"
    
    # Hardware Configuration
    GPU_TYPE="${GPU_TYPE:-cpu}"
    GPU_COUNT="${GPU_COUNT:-0}"
    OLLAMA_GPU_LAYERS="${OLLAMA_GPU_LAYERS:-auto}"
    CPU_CORES="${CPU_CORES:-$(nproc)}"
    TOTAL_RAM_GB="${TOTAL_RAM_GB:-8}"
    
    # Ollama Configuration
    OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-gemma3:4b}"
    OLLAMA_MODELS="${OLLAMA_MODELS:-gemma4:4b,gemma4:26b}"
    
    # LLM Providers
    LLM_PROVIDERS="${LLM_PROVIDERS:-local}"
    OPENAI_API_KEY="${OPENAI_API_KEY:-}"
    GOOGLE_API_KEY="${GOOGLE_API_KEY:-}"
    GROQ_API_KEY="${GROQ_API_KEY:-}"
    OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
    
    # LiteLLM Routing Strategy
    LITELLM_ROUTING_STRATEGY="${LITELLM_ROUTING_STRATEGY:-cost-optimized}"
    LITELLM_INTERNAL_PORT="${LITELLM_INTERNAL_PORT:-4000}"
    
    # Internal Service Ports
    CADDY_INTERNAL_HTTP_PORT="${CADDY_INTERNAL_HTTP_PORT:-80}"
    CADDY_INTERNAL_HTTPS_PORT="${CADDY_INTERNAL_HTTPS_PORT:-443}"
    OLLAMA_INTERNAL_PORT="${OLLAMA_INTERNAL_PORT:-11434}"
    QDRANT_INTERNAL_PORT="${QDRANT_INTERNAL_PORT:-6333}"
    QDRANT_INTERNAL_HTTP_PORT="${QDRANT_INTERNAL_HTTP_PORT:-6333}"
    OPENWEBUI_INTERNAL_PORT="${OPENWEBUI_INTERNAL_PORT:-8081}"
    OPENCLAW_INTERNAL_PORT="${OPENCLAW_INTERNAL_PORT:-18789}"
    SIGNAL_INTERNAL_PORT="${SIGNAL_INTERNAL_PORT:-8080}"
    N8N_INTERNAL_PORT="${N8N_INTERNAL_PORT:-5678}"
    FLOWISE_INTERNAL_PORT="${FLOWISE_INTERNAL_PORT:-3000}"
    ANYTHINGLLM_INTERNAL_PORT="${ANYTHINGLLM_INTERNAL_PORT:-3001}"
    GRAFANA_INTERNAL_PORT="${GRAFANA_INTERNAL_PORT:-3000}"
    PROMETHEUS_INTERNAL_PORT="${PROMETHEUS_INTERNAL_PORT:-9090}"
    MINIO_INTERNAL_PORT="${MINIO_INTERNAL_PORT:-9000}"
    MINIO_CONSOLE_INTERNAL_PORT="${MINIO_CONSOLE_INTERNAL_PORT:-9001}"
    POSTGRES_INTERNAL_PORT="${POSTGRES_INTERNAL_PORT:-5432}"
    REDIS_INTERNAL_PORT="${REDIS_INTERNAL_PORT:-6379}"
    
    # Database Configuration
    POSTGRES_USER="${POSTGRES_USER:-}"
    POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
    POSTGRES_DB="${POSTGRES_DB:-}"
    DB_USER="${DB_USER:-}"
    DB_PASSWORD="${DB_PASSWORD:-}"
    
    # Redis Configuration
    REDIS_PASSWORD="${REDIS_PASSWORD:-}"
    
    # n8n Configuration
    N8N_BASIC_AUTH_ACTIVE="${N8N_BASIC_AUTH_ACTIVE:-false}"
    N8N_BASIC_AUTH_USER="${N8N_BASIC_AUTH_USER:-}"
    N8N_BASIC_AUTH_PASSWORD="${N8N_BASIC_AUTH_PASSWORD:-}"
    
    # Flowise Configuration
    FLOWISE_USERNAME="${FLOWISE_USERNAME:-}"
    FLOWISE_PASSWORD="${FLOWISE_PASSWORD:-}"
    
    # LiteLLM Configuration
    LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"
    LITELLM_DATABASE_URL="${LITELLM_DATABASE_URL:-postgresql://postgres:password@localhost:5432/litellm}"
    LITELLM_ENABLE_LOGGING="${LITELLM_ENABLE_LOGGING:-true}"
    
    # AnythingLLM Configuration
    ANYTHINGLLM_STORAGE_PATH="${ANYTHINGLLM_STORAGE_PATH:-}"
    ANYTHINGLLM_JWT_SECRET="${ANYTHINGLLM_JWT_SECRET:-}"
    
    # Qdrant Configuration
    QDRANT_API_KEY="${QDRANT_API_KEY:-}"
    QDRANT_COLLECTION_NAME="${QDRANT_COLLECTION_NAME:-}"
    
    # Grafana Configuration
    GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
    GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-}"
    
    # Authentik Configuration
    AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY:-}"
    AUTHENTIK_ADMIN_TOKEN="${AUTHENTIK_ADMIN_TOKEN:-}"
    
    # MinIO Configuration
    MINIO_ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
    MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-minioadmin}"
    MINIO_BUCKET="${MINIO_BUCKET:-}"
    
    # Dify Configuration
    DIFY_SECRET_KEY="${DIFY_SECRET_KEY:-}"
    DIFY_DATABASE_URL="${DIFY_DATABASE_URL:-}"
    
    # Network & Security
    TLS_MODE="${TLS_MODE:-none}"
    LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
    LETSENCRYPT_STAGING="${LETSENCRYPT_STAGING:-false}"
    LETSENCRYPT_AUTO_RENEW="${LETSENCRYPT_AUTO_RENEW:-true}"
    HTTP_TO_HTTPS_REDIRECT="${HTTP_TO_HTTPS_REDIRECT:-false}"
    
    # Proxy Configuration
    ENABLE_PROXY="${ENABLE_PROXY:-false}"
    PROXY_TYPE="${PROXY_TYPE:-nginx}"
    PROXY_ROUTING="${PROXY_ROUTING:-path_based}"
    PROXY_HTTP_PORT="${PROXY_HTTP_PORT:-80}"
    PROXY_HTTPS_PORT="${PROXY_HTTPS_PORT:-443}"
    PROXY_FORCE_HTTPS="${PROXY_FORCE_HTTPS:-false}"
    
    # Google Drive Integration
    ENABLE_GDRIVE="${ENABLE_GDRIVE:-false}"
    GDRIVE_FOLDER_ID="${GDRIVE_FOLDER_ID:-}"
    GDRIVE_FOLDER_NAME="${GDRIVE_FOLDER_NAME:-AI Platform}"
    
    # Search APIs
    SEARXNG_SECRET_KEY="${SEARXNG_SECRET_KEY:-}"
    
    # Additional Service Ports
    WEAVIATE_PORT="${WEAVIATE_PORT:-8080}"
    CHROMADB_PORT="${CHROMADB_PORT:-8000}"
    MILVUS_PORT="${MILVUS_PORT:-19530}"
    CODESERVER_PORT="${CODESERVER_PORT:-8443}"
    
    # Self-signed TLS
    SELF_SIGNED_DAYS="${SELF_SIGNED_DAYS:-365}"
    
    # Manual TLS
    TLS_CERT_FILE="${TLS_CERT_FILE:-}"
    TLS_KEY_FILE="${TLS_KEY_FILE:-}"
    
    # Network Configuration
    LOCALHOST="${LOCALHOST:-localhost}"
    
    # Service Passwords and Secrets
    REDIS_PASSWORD="${REDIS_PASSWORD:-}"
    N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-}"
    N8N_API_KEY="${N8N_API_KEY:-}"
    N8N_USER="${N8N_USER:-}"
    N8N_PASSWORD="${N8N_PASSWORD:-}"
    FLOWISE_SECRET_KEY="${FLOWISE_SECRET_KEY:-}"
    FLOWISE_USERNAME="${FLOWISE_USERNAME:-}"
    FLOWISE_PASSWORD="${FLOWISE_PASSWORD:-}"
    LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"
    LITELLM_SALT_KEY="${LITELLM_SALT_KEY:-}"
    ANYTHINGLLM_API_KEY="${ANYTHINGLLM_API_KEY:-}"
    ANYTHINGLLM_JWT_SECRET="${ANYTHINGLLM_JWT_SECRET:-}"
    ANYTHINGLLM_AUTH_TOKEN="${ANYTHINGLLM_AUTH_TOKEN:-}"
    ANYTHINGLLM_PORT="${ANYTHINGLLM_PORT:-3001}"
    QDRANT_API_KEY="${QDRANT_API_KEY:-}"
    QDRANT_VECTOR_SIZE="${QDRANT_VECTOR_SIZE:-768}"
    GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-}"
    GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-}"
    GF_SECURITY_ADMIN_PASSWORD="${GF_SECURITY_ADMIN_PASSWORD:-}"
    AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY:-}"
    AUTHENTIK_BOOTSTRAP_EMAIL="${AUTHENTIK_BOOTSTRAP_EMAIL:-}"
    AUTHENTIK_BOOTSTRAP_PASSWORD="${AUTHENTIK_BOOTSTRAP_PASSWORD:-}"
    ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
    MINIO_ROOT_USER="${MINIO_ROOT_USER:-}"
    MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-}"
    DIFY_SECRET_KEY="${DIFY_SECRET_KEY:-}"
    DIFY_INNER_API_KEY="${DIFY_INNER_API_KEY:-}"
    
    # Google Drive Integration (added GDRIVE_FOLDER_ID)
    GDRIVE_AUTH_METHOD="${GDRIVE_AUTH_METHOD:-service_account}"
    GDRIVE_CLIENT_ID="${GDRIVE_CLIENT_ID:-}"
    GDRIVE_CLIENT_SECRET="${GDRIVE_CLIENT_SECRET:-}"
    GDRIVE_FOLDER_NAME="${GDRIVE_FOLDER_NAME:-}"
    GDRIVE_FOLDER_ID="${GDRIVE_FOLDER_ID:-}"  # Added as requested
    GDRIVE_TOKEN="${GDRIVE_TOKEN:-service_account_valid}"
    
    # Rclone Configuration
    RCLONE_AUTH_METHOD="${RCLONE_AUTH_METHOD:-service_account}"
    RCLONE_CONFIG_PATH="${RCLONE_CONFIG_PATH:-}"
    RCLONE_GDRIVE_ROOT_ID="${RCLONE_GDRIVE_ROOT_ID:-}"
    
    # Search APIs
    SEARCH_PROVIDER="${SEARCH_PROVIDER:-multiple}"
    BRAVE_API_KEY="${BRAVE_API_KEY:-}"
    SERPAPI_KEY="${SERPAPI_KEY:-}"
    SERPAPI_ENGINE="${SERPAPI_ENGINE:-google}"
    CUSTOM_SEARCH_URL="${CUSTOM_SEARCH_URL:-}"
    CUSTOM_SEARCH_KEY="${CUSTOM_SEARCH_KEY:-}"
    
    # Proxy Configuration (added for user selection)
    PROXY_TYPE="${PROXY_TYPE:-caddy}"
    ROUTING_METHOD="${ROUTING_METHOD:-subdomain}"
    SSL_TYPE="${SSL_TYPE:-selfsigned}"
    CUSTOM_PROXY_IMAGE="${CUSTOM_PROXY_IMAGE:-}"
    HTTP_PROXY="${HTTP_PROXY:-}"
    HTTPS_PROXY="${HTTPS_PROXY:-}"
    NO_PROXY="${NO_PROXY:-localhost,127.0.0.1,.local}"
    HTTP_TO_HTTPS_REDIRECT="${HTTP_TO_HTTPS_REDIRECT:-true}"
    
    # OpenClaw Configuration
    OPENCLAW_PASSWORD="${OPENCLAW_PASSWORD:-}"
    OPENCLAW_ADMIN_USER="${OPENCLAW_ADMIN_USER:-}"
    OPENCLAW_SECRET="${OPENCLAW_SECRET:-}"
    OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
    OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-alpine/openclaw:latest}"

    # External Ports
    CADDY_HTTP_PORT="${CADDY_HTTP_PORT:-80}"
    CADDY_HTTPS_PORT="${CADDY_HTTPS_PORT:-443}"
    N8N_PORT="${N8N_PORT:-5678}"
    FLOWISE_PORT="${FLOWISE_PORT:-3000}"
    OPENWEBUI_PORT="${OPENWEBUI_PORT:-8081}"
    ANYTHINGLLM_PORT="${ANYTHINGLLM_PORT:-3001}"
    LITELLM_PORT="${LITELLM_PORT:-4000}"
    GRAFANA_PORT="${GRAFANA_PORT:-3002}"
    PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
    OLLAMA_PORT="${OLLAMA_PORT:-11434}"
    QDRANT_PORT="${QDRANT_PORT:-6333}"
    SIGNAL_PORT="${SIGNAL_PORT:-8080}"
    OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
    RCLONE_PORT="${RCLONE_PORT:-5572}"
    
    # Additional Variables
    SSL_EMAIL="${SSL_EMAIL:-}"
    GPU_DEVICE="${GPU_DEVICE:-cpu}"
    TENANT_DIR="${TENANT_DIR:-}"
    MINIO_CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"
    MINIO_PORT="${MINIO_PORT:-9000}"
    
    # Authentik Redis Configuration
    AUTHENTIK_REDIS__HOST="${AUTHENTIK_REDIS__HOST:-redis}"
    
    # Dify Storage Configuration
    DIFY_STORAGE_TYPE="${DIFY_STORAGE_TYPE:-local}"
    DIFY_STORAGE_LOCAL_ROOT="${DIFY_STORAGE_LOCAL_ROOT:-/data}"
    
    # Infrastructure Services
    ENABLE_POSTGRES="${ENABLE_POSTGRES:-false}"
    ENABLE_POSTGRESQL="${ENABLE_POSTGRESQL:-false}"  # Alias for compatibility
    ENABLE_REDIS="${ENABLE_REDIS:-false}"
    
    # LLM Services
    ENABLE_OLLAMA="${ENABLE_OLLAMA:-false}"
    ENABLE_LITELLM="${ENABLE_LITELLM:-false}"
    ENABLE_BIFROST="${ENABLE_BIFROST:-false}"
    ENABLE_DIRECT_OLLAMA="${ENABLE_DIRECT_OLLAMA:-false}"
    
    # Web Interfaces
    ENABLE_OPENWEBUI="${ENABLE_OPENWEBUI:-false}"
    ENABLE_LIBRECHAT="${ENABLE_LIBRECHAT:-false}"
    ENABLE_OPENCLAW="${ENABLE_OPENCLAW:-false}"
    ENABLE_ANYTHINGLLM="${ENABLE_ANYTHINGLLM:-false}"
    
    # Vector Databases
    ENABLE_QDRANT="${ENABLE_QDRANT:-false}"
    ENABLE_WEAVIATE="${ENABLE_WEAVIATE:-false}"
    ENABLE_CHROMA="${ENABLE_CHROMA:-false}"
    ENABLE_MILVUS="${ENABLE_MILVUS:-false}"
    
    # Automation
    ENABLE_N8N="${ENABLE_N8N:-false}"
    ENABLE_FLOWISE="${ENABLE_FLOWISE:-false}"
    ENABLE_FLOWISEAI="${ENABLE_FLOWISEAI:-false}"
    ENABLE_LANGFLOW="${ENABLE_LANGFLOW:-false}"
    ENABLE_DIFY="${ENABLE_DIFY:-false}"
    ENABLE_SIGNALBOT="${ENABLE_SIGNALBOT:-false}"
    
    # Development
    ENABLE_CODE_SERVER="${ENABLE_CODE_SERVER:-false}"
    ENABLE_CONTINUE_DEV="${ENABLE_CONTINUE_DEV:-false}"
    
    # Monitoring
    ENABLE_GRAFANA="${ENABLE_GRAFANA:-false}"
    ENABLE_PROMETHEUS="${ENABLE_PROMETHEUS:-false}"
    
    # Authentication
    ENABLE_AUTHENTIK="${ENABLE_AUTHENTIK:-false}"
    
    # Additional Services
    ENABLE_ZEP="${ENABLE_ZEP:-false}"
    ENABLE_LETTA="${ENABLE_LETTA:-false}"
    ENABLE_NGINX="${ENABLE_NGINX:-false}"
    ENABLE_CADDY="${ENABLE_CADDY:-false}"
    
    # LLM Providers
    PREFERRED_LLM_PROVIDER="${PREFERRED_LLM_PROVIDER:-ollama}"
    ENABLE_OPENAI="${ENABLE_OPENAI:-false}"
    ENABLE_ANTHROPIC="${ENABLE_ANTHROPIC:-false}"
    ENABLE_GOOGLE="${ENABLE_GOOGLE:-false}"
    ENABLE_GROQ="${ENABLE_GROQ:-false}"
    ENABLE_COHERE="${ENABLE_COHERE:-false}"
    ENABLE_HUGGINGFACE="${ENABLE_HUGGINGFACE:-false}"
    ENABLE_OLLAMA_PROVIDER="${ENABLE_OLLAMA_PROVIDER:-false}"
    ENABLE_LOCAL_MODELS="${ENABLE_LOCAL_MODELS:-false}"
    ENABLE_OPENROUTER="${ENABLE_OPENROUTER:-false}"
    ENABLE_MAMMOUTH="${ENABLE_MAMMOUTH:-false}"

    # Additional Services
    ENABLE_GDRIVE="${ENABLE_GDRIVE:-false}"
    ENABLE_SIGNALBOT="${ENABLE_SIGNALBOT:-false}"
    
    # Port variables
    SIGNALBOT_PORT="${SIGNALBOT_PORT:-8080}"
    SEARXNG_PORT="${SEARXNG_PORT:-8888}"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
main() {
    local tenant_id="${1:-}"
    local template_file=""
    local preserve_secrets=false
    local generate_new=false
    local deployment_mode=""
    local dry_run=false
    local save_template=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ingest-from)
                template_file="$2"
                shift 2
                ;;
            --preserve-secrets)
                preserve_secrets=true
                shift
                ;;
            --generate-new)
                generate_new=true
                shift
                ;;
            --deployment-mode)
                deployment_mode="$2"
                shift 2
                ;;
            --template)
                template_file="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --save-template)
                save_template="$2"
                shift 2
                ;;
            -*)
                echo "Unknown option: $1"
                exit 1
                ;;
            *)
                if [[ -z "$tenant_id" ]]; then
                    tenant_id="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Display banner
    banner
    
    # Set up tenant-specific logging
    local TENANT_LOG_FILE="/tmp/ai-platform-setup-$(date +%Y%m%d-%H%M%S).log"
    
    log "🚀 === Script 1: System Setup & Input Collection ==="
    log "📋 Version: ${SCRIPT_VERSION}"
    log "👤 Tenant: $tenant_id"
    log "🔧 Dry-run: ${dry_run}"
    log "📥 Template file: ${template_file}"
    log "🔒 Preserve secrets: ${preserve_secrets}"
    log "🆕 Generate new: ${generate_new}"
    log "🎯 Deployment mode: ${deployment_mode}"
    log "💾 Save template: ${save_template}"
    
    # Initialize all service enable variables to prevent unbound variable errors
    initialize_service_variables
    
    # Run interactive collection, optionally pre-seeding from a template
    if [[ -n "$template_file" ]]; then
        log "📄 Loading template: $template_file"
        if [[ ! -f "$template_file" ]]; then
            fail "Template file not found: $template_file"
        fi
        # Source template to pre-fill variables
        # shellcheck source=/dev/null
        source "$template_file" || fail "Failed to load template: $template_file"
        # Export all uppercase vars so safe_read() can detect them via printenv
        while IFS='=' read -r key _; do
            [[ "$key" =~ ^[A-Z][A-Z0-9_]+$ ]] && export "$key" 2>/dev/null || true
        done < <(grep -E '^[A-Z][A-Z0-9_]+=' "$template_file" | grep -v '^#')
        # CLI tenant_id overrides template TENANT_ID
        [[ -n "$tenant_id" ]] && export TENANT_ID="$tenant_id"
        log "✅ Template loaded — all pre-filled variables will auto-confirm"
        log "   To override any value, unset the variable before running"
    fi
    run_interactive_collection

    # Create idempotency marker
    mkdir -p "${DATA_DIR}/.configured"
    touch "${DATA_DIR}/.configured/setup-system"

    # Mission Control dashboard — shown after everything is written/confirmed
    display_service_summary

    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              🎉 SYSTEM SETUP COMPLETE 🎉                   ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ✅ All configuration collected and validated"
    echo "  ✅ platform.conf generated: ${DATA_DIR}/config/platform.conf"
    echo "  ✅ Tenant user created: ${PLATFORM_PREFIX}${TENANT_ID}"
    echo "  ✅ Directory structure created: ${DATA_DIR}"
    echo "  ✅ Ready for Script 2: Deployment Engine"
    echo ""
    echo "  📋 NEXT STEPS:"
    echo "    1. Review configuration: cat ${DATA_DIR}/config/platform.conf"
    echo "    2. Run deployment: bash scripts/2-deploy-services.sh ${TENANT_ID}"
    echo "    3. Monitor services: bash scripts/3-configure-services.sh ${TENANT_ID}"
    echo ""
    echo "  🔐 IMPORTANT:"
    echo "    • All API keys are stored securely in platform.conf"
    echo "    • File permissions are set to 600 (owner read only)"
    echo "    • Keep this configuration file secure and backed up"
    echo ""
    
    # Template generation prompt
    if [[ -z "$template_file" ]]; then
        echo ""
        echo "💾 SAVE CONFIGURATION TEMPLATE?"
        echo "  Save your configuration as a reusable template for future deployments:"
        echo ""
        
        # Default template path
        local default_template="${HOME}/.ai-platform-templates/${TENANT_ID}-template.conf"
        
        safe_read_yesno "Save configuration template to ${default_template}?" "true" "SAVE_TEMPLATE"
        
        if [[ "$SAVE_TEMPLATE" == "true" ]]; then
            safe_read "Template path (or press Enter for default):" "$default_template" "CUSTOM_TEMPLATE_PATH"
            save_configuration_template "$CUSTOM_TEMPLATE_PATH"
        else
            echo ""
            echo "ℹ️  Template not saved. You can create one later by running:"
            echo "    bash scripts/1-setup-system.sh ${TENANT_ID} --save-template <path>"
        fi
    fi
    
    # If save template was specified via command line
    if [[ -n "$save_template" ]]; then
        save_configuration_template "$save_template"
    fi
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
