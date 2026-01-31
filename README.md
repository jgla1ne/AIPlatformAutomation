Complete deployment guide for GPU-accelerated AI platform on AWS EC2 g5.xlarge.

## Architecture Overview
Signal Messages → Signal REST API (8080) → ClawDBot (18789) → AnythingLLM (3001)
                                                                     ↓
Dify Workflows → Signal REST API (8080) → Signal Network     LiteLLM (4000)
                                                                     ↓
All HTTPS traffic → Gateway NGINX (8443) ← Tailscale         Ollama (11434) → NVIDIA GPU

## Prerequisites

1. **AWS EC2 Instance**
   - Type: g5.xlarge (NVIDIA A10G GPU)
   - OS: Ubuntu 22.04 LTS
   - EBS: 500GB+ gp3 volume
   - Security Group: Only Tailscale access needed

2. **Tailscale**
   - Installed and connected
   - Note your Tailscale IP

3. **Phone Number**
   - For Signal registration
   - Must NOT be currently registered on Signal
   - International format: +1234567890

4. **Smartphone**
   - Signal app installed
   - Able to scan QR codes

## Installation Steps

### Step 1: System Preparation

```bash
# SSH into your EC2 instance as user: jglaine
ssh jglaine@<ec2-ip>

# Download installer package
cd ~
git clone <this-repo-url> ai-platform-installer
# OR manually create using the files above

cd ai-platform-installer
Step 2: System Setup (30-45 minutes)
