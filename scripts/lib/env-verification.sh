#!/bin/bash

# Environment Verification Functions
verify_environment() {
    print_info "Verifying environment configuration..."
    
    local errors=0
    
    # Check required environment variables
    local required_vars=(
        "DATA_ROOT"
        "DOMAIN_NAME"
        "RUNNING_USER"
        "RUNNING_UID"
        "RUNNING_GID"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            print_error "Missing required environment variable: $var"
            errors=$((errors + 1))
        fi
    done
    
    # Check data directory
    if [[ ! -d "$DATA_ROOT" ]]; then
        print_error "Data directory does not exist: $DATA_ROOT"
        errors=$((errors + 1))
    fi
    
    # Check environment file
    if [[ ! -f "$ENV_FILE" ]]; then
        print_error "Environment file does not exist: $ENV_FILE"
        errors=$((errors + 1))
    fi
    
    # Check services file
    if [[ ! -f "$SERVICES_FILE" ]]; then
        print_error "Services file does not exist: $SERVICES_FILE"
        errors=$((errors + 1))
    fi
    
    if [[ $errors -gt 0 ]]; then
        print_error "Environment verification failed with $errors errors"
        return 1
    fi
    
    print_success "Environment verification passed"
    return 0
}

validate_service_dependencies() {
    local service="$1"
    local missing_deps=()
    
    case "$service" in
        "litellm")
            if [[ ! " ${SELECTED_SERVICES[*]} " =~ " postgres " ]]; then
                missing_deps+=("postgres")
            fi
            if [[ ! " ${SELECTED_SERVICES[*]} " =~ " redis " ]]; then
                missing_deps+=("redis")
            fi
            ;;
        "dify")
            if [[ ! " ${SELECTED_SERVICES[*]} " =~ " postgres " ]]; then
                missing_deps+=("postgres")
            fi
            if [[ ! " ${SELECTED_SERVICES[*]} " =~ " redis " ]]; then
                missing_deps+=("redis")
            fi
            ;;
        "n8n")
            if [[ ! " ${SELECTED_SERVICES[*]} " =~ " postgres " ]]; then
                missing_deps+=("postgres")
            fi
            ;;
    esac
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Service $service has missing dependencies: ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}