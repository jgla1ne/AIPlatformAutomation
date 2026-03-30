#!/bin/bash
set -euo pipefail

echo "Starting deployment test..."
echo "Tenant: $1"
echo "Dry run: $2"

# Test basic functions
echo "Testing Docker access..."
if docker info >/dev/null 2>&1; then
    echo "✓ Docker accessible"
else
    echo "✗ Docker not accessible"
    exit 1
fi

echo "Test completed successfully"
