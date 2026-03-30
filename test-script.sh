#!/bin/bash
set -euo pipefail

echo "Testing basic script execution..."
echo "Tenant ID: $1"
echo "Dry run: $2"
echo "Non-interactive: $3"

# Test framework validation
echo "Testing Docker access..."
if docker info >/dev/null 2>&1; then
    echo "Docker OK"
else
    echo "Docker failed"
fi

echo "Test complete"
