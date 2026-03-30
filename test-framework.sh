#!/bin/bash
set -euo pipefail

# Simplified framework validation
framework_test() {
    echo "Starting validation..."
    
    # Binary checks
    for bin in curl jq; do
        if ! command -v "$bin" >/dev/null 2>&1; then
            echo "Missing: $bin"
            exit 1
        fi
    done
    echo "Binary checks OK"
    
    # Docker check
    if ! docker info >/dev/null 2>&1; then
        echo "Docker failed"
        exit 1
    fi
    echo "Docker OK"
    
    # Docker compose check
    if ! docker compose version >/dev/null 2>&1; then
        echo "Docker compose failed"
        exit 1
    fi
    echo "Docker compose OK"
    
    # EBS mount check
    if [[ ! -d /mnt ]]; then
        echo "EBS mount failed"
        exit 1
    fi
    echo "EBS mount OK"
    
    # Disk space check
    local free_gb
    free_gb=$(df /mnt | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $free_gb -lt 10 ]]; then
        echo "Insufficient disk space: ${free_gb}GB"
        exit 1
    fi
    echo "Disk space OK: ${free_gb}GB"
    
    echo "Validation complete"
}

framework_test
