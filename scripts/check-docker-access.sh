#!/bin/bash
# Check if current user can access Docker without sudo

if docker ps &> /dev/null; then
    echo "✓ Docker access configured correctly"
    exit 0
else
    echo "✗ Cannot access Docker without sudo"
    echo "Please log out and back in, or run: newgrp docker"
    exit 1
fi
