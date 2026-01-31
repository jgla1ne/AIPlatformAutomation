#!/bin/bash
set -euo pipefail

SECRETS_FILE=~/ai-platform-installer/.secrets

if [[ -f "$SECRETS_FILE" ]]; then
    echo "Secrets file already exists. Loading..."
    source "$SECRETS_FILE"
    exit 0
fi

echo "Generating secrets..."

# Get Tailscale IP
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "NOT_SET")

# Get user info
PLATFORM_USER=$(whoami)
PLATFORM_UID=$(id -u)
PLATFORM_GID=$(id -g)

# Generate random secrets
POSTGRES_PASSWORD=$(openssl rand -hex 32)
REDIS_PASSWORD=$(openssl rand -hex 32)
DIFY_SECRET_KEY=$(openssl rand -hex 32)
DIFY_INIT_PASSWORD=$(openssl rand -base64 12)
LITELLM_MASTER_KEY="sk-$(openssl rand -hex 24)"
ANYTHINGLLM_JWT_SECRET=$(openssl rand -hex 32)
ANYTHINGLLM_API_KEY="sk-$(openssl rand -hex 24)"

cat > "$SECRETS_FILE" <<EOF
# AI Platform Secrets
# Generated: $(date)
# DO NOT COMMIT THIS FILE

# User information
export PLATFORM_USER="$PLATFORM_USER"
export PLATFORM_UID="$PLATFORM_UID"
export PLATFORM_GID="$PLATFORM_GID"

# Network
export TAILSCALE_IP="$TAILSCALE_IP"

# Database passwords
export POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
export REDIS_PASSWORD="$REDIS_PASSWORD"

# Dify
export DIFY_SECRET_KEY="$DIFY_SECRET_KEY"
export DIFY_INIT_PASSWORD="$DIFY_INIT_PASSWORD"

# LiteLLM
export LITELLM_MASTER_KEY="$LITELLM_MASTER_KEY"

# AnythingLLM
export ANYTHINGLLM_JWT_SECRET="$ANYTHINGLLM_JWT_SECRET"
export ANYTHINGLLM_API_KEY="$ANYTHINGLLM_API_KEY"

# Signal (to be set during registration)
export SIGNAL_PHONE_NUMBER=""
EOF

chmod 600 "$SECRETS_FILE"

echo "✅ Secrets generated and saved to $SECRETS_FILE"
echo ""
echo "IMPORTANT: Save these credentials securely!"
echo "Dify Admin Password: $DIFY_INIT_PASSWORD"
echo "LiteLLM API Key: $LITELLM_MASTER_KEY"
echo "AnythingLLM API Key: $ANYTHINGLLM_API_KEY"
SECRETS_EOF

chmod +x ~/ai-platform-installer/scripts/generate-secrets.sh
