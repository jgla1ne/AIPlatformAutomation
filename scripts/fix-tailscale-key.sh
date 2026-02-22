#!/bin/bash
# Script to fix Tailscale auth key

echo "Fixing Tailscale auth key..."
echo ""

# Read new auth key
echo -n "Enter Tailscale auth key (starts with tskey-auth-): "
read -r NEW_AUTH_KEY

# Validate format
if [[ ! "$NEW_AUTH_KEY" =~ ^tskey-auth- ]]; then
    echo "Error: Auth key must start with 'tskey-auth-'"
    exit 1
fi

# Update .env file
sed -i "s/TAILSCALE_AUTH_KEY=.*/TAILSCALE_AUTH_KEY=${NEW_AUTH_KEY}/" /mnt/data/.env

echo "✅ Tailscale auth key updated in /mnt/data/.env"
echo ""
echo "Updated key: ${NEW_AUTH_KEY}"
echo ""
echo "You can now run: sudo ./2-deploy-services.sh"
