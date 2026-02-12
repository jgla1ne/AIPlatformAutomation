#!/bin/bash

set -euo pipefail

# Interactive cleanup before running any script
interactive_cleanup() {
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║              🧹 INTERACTIVE CLEANUP WORKFLOW                    ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "This will run a complete cleanup before executing the target script."
    echo ""
    read -p "Run cleanup first? [Y/n]: " response
    response=${response:-Y}
    
    if [[ "$response" =~ ^[Yy] ]]; then
        echo "Running complete cleanup..."
        sudo bash scripts/0-complete-cleanup.sh
        echo ""
        echo "✅ Cleanup completed!"
        echo ""
    fi
}

# Main execution
main() {
    local script_to_run="$1"
    
    if [[ -z "$script_to_run" ]]; then
        echo "Usage: $0 <script_to_run>"
        echo "Example: $0 scripts/1-setup-system.sh"
        exit 1
    fi
    
    # Run interactive cleanup
    interactive_cleanup
    
    # Run the target script
    echo "🚀 Running: $script_to_run"
    echo ""
    sudo bash "$script_to_run"
}

main "$@"
