# AI Platform Automation - Patterns & Solutions Compendium

> **Complete collection of recurring patterns, solutions, and implementation guides**  
> **Version 1.0 - April 8, 2026**

---

## 🔍 **RECURRING PATTERNS CATALOG**

### **Pattern 1: Safe Variable Initialization**

**Problem**: Variables used before initialization cause script failures
**Frequency**: 50+ occurrences across all scripts
**Impact**: Critical - causes immediate script failure

#### **Implementation**
```bash
# UNIVERSAL PATTERN - Apply everywhere
VARIABLE_NAME="${VARIABLE_NAME:-default_value}"

# Examples with different types:
PORT="${PORT:-8080}"                          # Numeric
ENABLED="${ENABLED:-false}"                   # Boolean
PATH="${PATH:-/default/path}"                 # String
LIST="${LIST:-item1,item2,item3}"             # List
CONFIG_FILE="${CONFIG_FILE:-/etc/default.conf}" # File path
```

#### **Validation Checklist**
- [ ] Every variable used in prompts has default value
- [ ] Every variable used in conditions has default value
- [ ] Every variable used in file paths has default value
- [ ] No unbound variable errors in script execution

---

### **Pattern 2: Robust Input Collection**

**Problem**: User input causes script crashes or invalid states
**Frequency**: 30+ input prompts in Script 1
**Impact**: High - affects user experience and script reliability

#### **Implementation**
```bash
# Core input function
safe_read() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local pattern="$4"
    local value
    local attempts=0
    local max_attempts=3

    while [[ $attempts -lt $max_attempts ]]; do
        echo -n "  🤔 ${prompt} [${default}]: "
        read -r value
        value="${value:-${default}}"
        
        if [[ -n "$pattern" ]] && ! [[ "$value" =~ $pattern ]]; then
            echo "  ❌ Invalid format. Please match: $pattern"
            ((attempts++))
            continue
        fi
        
        printf -v "${varname}" '%s' "$value"
        echo "  ✅ ${prompt}: $value"
        return 0
    done
    
    fail "Maximum attempts reached for input: ${prompt}"
}

# Yes/No input function
safe_read_yesno() {
    local prompt="$1"
    local default="${2:-n}"
    local varname="$3"
    local value
    local attempts=0
    local max_attempts=3

    case "${default,,}" in
        true|yes) default="y" ;;
        false|no) default="n" ;;
    esac

    while [[ $attempts -lt $max_attempts ]]; do
        echo -n "  🤔 ${prompt} [${default^}/n]: "
        read -r value
        value="${value:-${default}}"
        
        case "${value,,}" in
            y|yes) 
                value="true"
                printf -v "${varname}" '%s' "$value"
                echo "  ✅ ${prompt}: $value"
                return 0
                ;;
            n|no) 
                value="false"
                printf -v "${varname}" '%s' "$value"
                echo "  ✅ ${prompt}: $value"
                return 0
                ;;
            *) 
                echo "  ❌ Please enter 'y' or 'n'"
                ((attempts++))
                ;;
        esac
    done
    
    fail "Maximum attempts reached for yes/no prompt: ${prompt}"
}

# Password input function
safe_read_password() {
    local prompt="$1"
    local varname="$2"
    local password1
    local password2
    local attempts=0
    local max_attempts=3

    while [[ $attempts -lt $max_attempts ]]; do
        echo -n "  🔒 ${prompt}: "
        read -s password1
        echo
        echo -n "  🔒 Confirm ${prompt}: "
        read -s password2
        echo
        
        if [[ "$password1" != "$password2" ]]; then
            echo "  ❌ Passwords do not match"
            ((attempts++))
            continue
        fi
        
        if [[ ${#password1} -lt 8 ]]; then
            echo "  ❌ Password must be at least 8 characters"
            ((attempts++))
            continue
        fi
        
        printf -v "${varname}" '%s' "$password1"
        echo "  ✅ ${prompt} set"
        return 0
    done
    
    fail "Maximum attempts reached for password: ${prompt}"
}
```

#### **Usage Examples**
```bash
# String input with validation
safe_read "Tenant ID" "demo" "TENANT_ID" "^[a-z0-9-]+$"

# Yes/No input
safe_read_yesno "Enable PostgreSQL" "true" "ENABLE_POSTGRES"

# Password input
safe_read_password "PostgreSQL password" "POSTGRES_PASSWORD"

# Port input with numeric validation
safe_read "Redis port" "6379" "REDIS_PORT" "^[0-9]+$"
```

---

### **Pattern 3: Consistent Error Handling**

**Problem**: Scripts fail silently or with unclear messages
**Frequency**: Every function needs this
**Impact**: High - affects debugging and user experience

#### **Implementation**
```bash
# Logging functions
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
    echo "$msg" >> "${LOG_FILE:-/tmp/ai-platform.log}"
}

ok() { 
    log "OK: $*" 
}

warn() { 
    log "WARN: $*" 
}

fail() { 
    log "FAIL: $*" 
    echo "💥 ERROR: $*" >&2
    exit 1
}

# Debug logging
debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG: $*"
    fi
}

# Success confirmation
confirm() {
    local message="$1"
    log "SUCCESS: $message"
    echo "✅ $message"
}
```

#### **Error Handling Patterns**
```bash
# Function with error handling
do_something() {
    debug "Starting do_something"
    
    if ! command_that_might_fail; then
        fail "Command failed: command_that_might_fail"
    fi
    
    confirm "do_something completed successfully"
}

# Resource cleanup
cleanup_on_exit() {
    local exit_code=$?
    debug "Cleaning up with exit code: $exit_code"
    
    # Cleanup operations here
    rm -f /tmp/temp_file
    
    if [[ $exit_code -ne 0 ]]; then
        warn "Script failed with exit code: $exit_code"
    fi
    
    exit $exit_code
}

trap cleanup_on_exit EXIT
```

---

### **Pattern 4: Tenant-Isolated Directory Structure**

**Problem**: Inconsistent paths cause deployment failures
**Frequency**: All file operations
**Impact**: Critical - causes data loss and security issues

#### **Implementation**
```bash
# Base directory structure
initialize_directories() {
    local tenant_id="$1"
    
    # Base directory (always under /mnt)
    BASE_DIR="/mnt/${tenant_id}"
    CONFIG_DIR="${BASE_DIR}/config"
    DATA_DIR="${BASE_DIR}/data"
    LOG_DIR="${BASE_DIR}/logs"
    BACKUP_DIR="${BASE_DIR}/backups"
    TEMPLATES_DIR="${BASE_DIR}/templates"
    
    # Create directories with proper permissions
    mkdir -p "${BASE_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${LOG_DIR}" "${BACKUP_DIR}" "${TEMPLATES_DIR}"
    
    # Set permissions (600 for secure files, 755 for directories)
    chmod 755 "${BASE_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${LOG_DIR}" "${BACKUP_DIR}" "${TEMPLATES_DIR}"
    
    # Create subdirectories
    mkdir -p "${CONFIG_DIR}/nginx" "${CONFIG_DIR}/caddy" "${CONFIG_DIR}/litellm"
    mkdir -p "${DATA_DIR}/postgres" "${DATA_DIR}/redis" "${DATA_DIR}/qdrant"
    mkdir -p "${LOG_DIR}/services" "${LOG_DIR}/deployments"
    
    ok "Directory structure created for tenant: ${tenant_id}"
}
```

#### **Path Usage Patterns**
```bash
# ALWAYS use tenant-isolated paths
CONFIG_FILE="${CONFIG_DIR}/platform.conf"
COMPOSE_FILE="${CONFIG_DIR}/docker-compose.yml"
LITELLM_CONFIG="${CONFIG_DIR}/litellm/config.yaml"
POSTGRES_DATA="${DATA_DIR}/postgres"
SERVICE_LOG="${LOG_DIR}/services/${service_name}.log"

# NEVER use hardcoded paths like /tmp or /etc
# WRONG: /tmp/platform.conf
# RIGHT: ${CONFIG_DIR}/platform.conf
```

---

### **Pattern 5: Service Enablement Control**

**Problem**: Services deployed regardless of user choice
**Frequency**: 25+ services
**Impact**: High - wastes resources and violates user preferences

#### **Implementation**
```bash
# Service enablement flags
initialize_service_flags() {
    # Infrastructure
    ENABLE_POSTGRES="${ENABLE_POSTGRES:-false}"
    ENABLE_REDIS="${ENABLE_REDIS:-false}"
    
    # LLM Services
    ENABLE_OLLAMA="${ENABLE_OLLAMA:-false}"
    ENABLE_LITELLM="${ENABLE_LITELLM:-false}"
    
    # Web UIs
    ENABLE_OPENWEBUI="${ENABLE_OPENWEBUI:-false}"
    ENABLE_LIBRECHAT="${ENABLE_LIBRECHAT:-false}"
    
    # Vector Databases
    ENABLE_QDRANT="${ENABLE_QDRANT:-false}"
    ENABLE_WEAVIATE="${ENABLE_WEAVIATE:-false}"
    
    # Automation
    ENABLE_N8N="${ENABLE_N8N:-false}"
    ENABLE_FLOWISE="${ENABLE_FLOWISE:-false}"
}

# Service deployment template
deploy_service() {
    local service_name="$1"
    local enable_flag="$2"
    local deploy_function="$3"
    
    if [[ "${enable_flag}" == "true" ]]; then
        log "Deploying service: ${service_name}"
        if ${deploy_function}; then
            ok "Service deployed: ${service_name}"
        else
            fail "Service deployment failed: ${service_name}"
        fi
    else
        log "Skipping disabled service: ${service_name}"
    fi
}
```

#### **Usage Examples**
```bash
# In deployment script
deploy_service "PostgreSQL" "${ENABLE_POSTGRES}" "deploy_postgres"
deploy_service "Redis" "${ENABLE_REDIS}" "deploy_redis"
deploy_service "Ollama" "${ENABLE_OLLAMA}" "deploy_ollama"
deploy_service "LiteLLM" "${ENABLE_LITELLM}" "deploy_litellm"
```

---

## 🔧 **SOLUTIONS COMPENDIUM**

### **Solution 1: EBS Volume Detection and Mounting**

**Problem**: Need to detect and mount EBS volumes dynamically
**Solution**: Use fdisk and grep to identify EBS volumes

#### **Implementation**
```bash
detect_ebs_volumes() {
    log "Detecting EBS volumes..."
    
    # Get list of EBS volumes
    local ebs_volumes
    ebs_volumes=$(fdisk -l | grep "Amazon Elastic Block Store" | awk '{print $2}' | tr -d ':')
    
    if [[ -z "$ebs_volumes" ]]; then
        warn "No EBS volumes detected"
        return 1
    fi
    
    echo "Available EBS volumes:"
    local i=1
    for volume in $ebs_volumes; do
        echo "  $i) $volume"
        ((i++))
    done
    
    # User selection
    local selection
    safe_read "Select EBS volume (1-$((i-1)))" "1" "selection" "^[0-9]+$"
    
    # Get selected volume
    local selected_volume
    selected_volume=$(echo "$ebs_volumes" | sed -n "${selection}p")
    
    if [[ -z "$selected_volume" ]]; then
        fail "Invalid EBS volume selection"
    fi
    
    SELECTED_EBS_VOLUME="$selected_volume"
    ok "Selected EBS volume: $selected_volume"
}

mount_ebs_volume() {
    local device="$1"
    local mount_point="$2"
    
    # Check if device exists
    if [[ ! -b "$device" ]]; then
        fail "EBS device not found: $device"
    fi
    
    # Check if already mounted
    if mountpoint -q "$mount_point"; then
        warn "EBS volume already mounted at: $mount_point"
        return 0
    fi
    
    # Create mount point
    mkdir -p "$mount_point"
    
    # Format if needed
    if ! blkid "$device" >/dev/null 2>&1; then
        log "Formatting EBS volume: $device"
        mkfs.ext4 -F "$device" || fail "Failed to format EBS volume"
    fi
    
    # Mount the volume
    log "Mounting EBS volume: $device -> $mount_point"
    mount "$device" "$mount_point" || fail "Failed to mount EBS volume"
    
    # Add to fstab for persistence
    if ! grep -q "$device" /etc/fstab; then
        local uuid
        uuid=$(blkid -s UUID -o value "$device")
        echo "UUID=$uuid  $mount_point  ext4  defaults,nofail  0  2" >> /etc/fstab
        ok "Added EBS volume to fstab"
    fi
    
    ok "EBS volume mounted successfully"
}
```

---

### **Solution 2: Port Health Checks and Conflict Detection**

**Problem**: Need to ensure ports are available and services are healthy
**Solution**: Comprehensive port validation and health checks

#### **Implementation**
```bash
check_port_availability() {
    local port="$1"
    local service="$2"
    
    # Check if port is in use
    if netstat -tuln | grep -q ":${port} "; then
        local pid=$(lsof -ti:${port} 2>/dev/null)
        fail "Port ${port} already in use by PID ${pid} (service: ${service})"
    fi
    
    # Check if port is in privileged range
    if [[ $port -lt 1024 ]]; then
        warn "Port ${port} is in privileged range - may require root"
    fi
    
    ok "Port ${port} is available for ${service}"
}

check_service_health() {
    local service_name="$1"
    local health_url="$2"
    local timeout="${3:-30}"
    
    log "Checking health of ${service_name}..."
    
    local count=0
    while [[ $count -lt $timeout ]]; do
        if curl -sf "$health_url" >/dev/null 2>&1; then
            ok "${service_name} is healthy"
            return 0
        fi
        
        sleep 1
        ((count++))
    done
    
    fail "${service_name} health check failed after ${timeout}s"
}

validate_all_ports() {
    log "Validating all service ports..."
    
    # Define port mappings
    declare -A port_mappings=(
        ["POSTGRES"]="${POSTGRES_PORT:-5432}"
        ["REDIS"]="${REDIS_PORT:-6379}"
        ["OLLAMA"]="${OLLAMA_PORT:-11434}"
        ["LITELLM"]="${LITELLM_PORT:-4000}"
        ["OPENWEBUI"]="${OPENWEBUI_PORT:-3000}"
        ["QDRANT"]="${QDRANT_PORT:-6333}"
        ["N8N"]="${N8N_PORT:-5678}"
        ["GRAFANA"]="${GRAFANA_PORT:-3001}"
    )
    
    # Check each port
    for service in "${!port_mappings[@]}"; do
        local port="${port_mappings[$service]}"
        local enable_var="ENABLE_${service}"
        
        if [[ "${!enable_var}" == "true" ]]; then
            check_port_availability "$port" "$service"
        fi
    done
    
    ok "All ports validated successfully"
}
```

---

### **Solution 3: DNS Validation and TLS Configuration**

**Problem**: Need to validate domains and configure TLS certificates
**Solution**: Comprehensive DNS validation and TLS setup

#### **Implementation**
```bash
validate_domain() {
    local domain="$1"
    
    # Check domain format
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        fail "Invalid domain format: $domain"
    fi
    
    # Check DNS resolution
    if ! nslookup "$domain" >/dev/null 2>&1; then
        fail "Domain does not resolve: $domain"
    fi
    
    # Get public IP
    local public_ip
    public_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null)
    
    if [[ -z "$public_ip" ]]; then
        warn "Could not determine public IP"
    else
        # Check if domain resolves to this IP
        local domain_ip
        domain_ip=$(nslookup "$domain" | grep -A1 "Name:" | tail -1 | awk '{print $2}')
        
        if [[ "$domain_ip" != "$public_ip" ]]; then
            warn "Domain resolves to ${domain_ip}, but public IP is ${public_ip}"
        fi
    fi
    
    ok "Domain validation passed: $domain"
}

configure_tls() {
    local domain="$1"
    local email="$2"
    local tls_mode="$3"
    
    case "$tls_mode" in
        "letsencrypt")
            configure_letsencrypt "$domain" "$email"
            ;;
        "manual")
            configure_manual_tls "$domain"
            ;;
        "self-signed")
            configure_self_signed_tls "$domain"
            ;;
        "none")
            warn "TLS disabled - HTTP only"
            ;;
        *)
            fail "Invalid TLS mode: $tls_mode"
            ;;
    esac
}

configure_letsencrypt() {
    local domain="$1"
    local email="$2"
    
    log "Configuring Let's Encrypt for $domain"
    
    # Install certbot if not present
    if ! command -v certbot >/dev/null 2>&1; then
        apt-get update
        apt-get install -y certbot python3-certbot-nginx
    fi
    
    # Obtain certificate
    certbot --nginx -d "$domain" --email "$email" --agree-tos --non-interactive || \
    fail "Failed to obtain Let's Encrypt certificate"
    
    # Setup auto-renewal
    echo "0 12 * * * /usr/bin/certbot renew --quiet" | crontab -
    
    ok "Let's Encrypt configured for $domain"
}
```

---

### **Solution 4: Template System Implementation**

**Problem**: Need to save and reuse configurations
**Solution**: Template generation and loading system

#### **Implementation**
```bash
save_template() {
    local template_file="$1"
    local tenant_id="$2"
    
    # Create templates directory if not exists
    mkdir -p "$(dirname "$template_file")"
    
    # Export all configuration variables
    {
        echo "# AI Platform Configuration Template"
        echo "# Generated: $(date)"
        echo "# Tenant: $tenant_id"
        echo ""
        
        # Export all variables matching pattern
        env | grep -E "^(TENANT_|ENABLE_|PORT_|API_KEY|PASSWORD|URL|DOMAIN)" | sort
        
        echo ""
        echo "# End of template"
    } > "$template_file"
    
    # Set secure permissions
    chmod 600 "$template_file"
    
    ok "Template saved: $template_file"
}

load_template() {
    local template_file="$1"
    
    if [[ ! -f "$template_file" ]]; then
        fail "Template file not found: $template_file"
    fi
    
    # Source the template
    source "$template_file" || fail "Failed to load template"
    
    ok "Template loaded: $template_file"
}

validate_template() {
    local template_file="$1"
    
    # Check required variables
    local required_vars=("TENANT_ID" "DOMAIN" "ADMIN_EMAIL")
    
    source "$template_file"
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            fail "Required variable missing in template: $var"
        fi
    done
    
    ok "Template validation passed: $template_file"
}
```

---

## 📋 **IMPLEMENTATION CHECKLISTS**

### **Script Implementation Checklist**

#### **Pre-Implementation**
- [ ] Read and understand the pattern
- [ ] Identify all use cases in current script
- [ ] Plan integration points
- [ ] Consider edge cases

#### **Implementation**
- [ ] Apply pattern exactly as specified
- [ ] Use same variable names and conventions
- [ ] Add proper error handling
- [ ] Include logging statements

#### **Post-Implementation**
- [ ] Test with various inputs
- [ ] Test error conditions
- [ ] Verify integration works
- [ ] Update documentation

### **Code Review Checklist**

#### **Variable Handling**
- [ ] All variables initialized with defaults
- [ ] No unbound variable errors
- [ ] Consistent naming conventions
- [ ] Proper scoping

#### **Input Validation**
- [ ] All user inputs validated
- [ ] Proper error messages
- [ ] Retry logic implemented
- [ ] TTY/non-TTY handling

#### **Error Handling**
- [ ] Consistent logging format
- [ ] Proper exit codes
- [ ] Cleanup on exit
- [ ] Resource management

#### **Security**
- [ ] No hardcoded secrets
- [ ] Proper file permissions
- [ ] Input sanitization
- [ ] Tenant isolation

---

## 🎯 **BEST PRACTICES SUMMARY**

### **Coding Standards**
1. **Always use `${VAR:-default}`** for variable initialization
2. **Always validate user input** with appropriate functions
3. **Always log operations** with consistent formatting
4. **Always handle errors** gracefully with proper cleanup
5. **Always use tenant-isolated paths** under `/mnt/${TENANT_ID}/`

### **Design Principles**
1. **Simple over complex** - Choose the simplest solution that works
2. **Explicit over implicit** - Make behavior obvious and documented
3. **Consistent over clever** - Use established patterns consistently
4. **Testable over fast** - Write code that can be easily tested

### **Security Practices**
1. **Zero hardcoded secrets** - All secrets from user input or secure generation
2. **Principle of least privilege** - Minimum permissions required
3. **Tenant isolation** - Complete separation of tenant data
4. **Secure defaults** - Default to the most secure option

---

*Document Version: 1.0 | Created: April 8, 2026 | Status: Complete Reference*
