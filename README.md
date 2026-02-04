# ?? AI Platform - Enterprise Agent Automation System

**Version:** 5.0 Final  
**Status:** Production-Ready  
**Target:** AWS EC2 g5.xlarge (NVIDIA A10G GPU)  
**OS:** Ubuntu 22.04 LTS  

---

## ?? Table of Contents

- [Overview](#-overview)
- [Features](#-features)
- [Architecture](#-architecture)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Directory Structure](#-directory-structure)
- [Configuration](#-configuration)
- [Usage](#-usage)
- [Troubleshooting](#-troubleshooting)
- [Maintenance](#-maintenance)
- [Security](#-security)
- [Cost Optimization](#-cost-optimization)
- [FAQ](#-faq)

---

## ?? Overview

Enterprise-grade AI agent automation platform combining:
- **Local GPU inference** (Ollama) for fast, free responses
- **Cloud AI** (OpenAI/Anthropic) for complex reasoning
- **Vector database** (AnythingLLM) for document knowledge base
- **Workflow automation** (Dify) for multi-step processes
- **Multi-channel messaging** (Signal) for user interaction

**Key Differentiator:** Intelligent routing saves 90% on AI costs while maintaining sub-2s response times.

---

## ? Features

### Core Capabilities
- ? **Hybrid AI Routing**: Local GPU for 80% of queries, cloud for complex tasks
- ? **Vector RAG**: Search 10,000+ documents in <2 seconds
- ? **Workflow Engine**: Dify's visual builder with 50+ node types
- ? **E2E Encryption**: Signal protocol for secure messaging
- ? **GPU Acceleration**: NVIDIA A10G for llama3.2, qwen2.5 models
- ? **Scalable Storage**: 500GB ? 16TB expansion in minutes
- ? **Zero Public Ports**: Tailscale VPN mesh network only
- ? **Idempotent Deployment**: Run scripts multiple times safely

### Supported AI Models
- **Local (GPU)**: llama3.2:3b, qwen2.5:3b, nomic-embed-text
- **Cloud (API)**: GPT-4, GPT-3.5-turbo, Claude-3-Sonnet, Claude-3-Opus

### Integrations
- **Messaging**: Signal (E2E encrypted)
- **Vector DB**: Weaviate, LanceDB
- **Databases**: PostgreSQL, Redis
- **AI Providers**: OpenAI, Anthropic, Ollama

---

## ??? Architecture
+-------------------------------------------------+
¦           AWS EC2 g5.xlarge Instance            ¦
¦         Ubuntu 22.04 + NVIDIA A10G GPU          ¦
+-------------------------------------------------+
                   ¦
        +---------------------+
        ¦  Tailscale VPN      ¦
        ¦  (100.x.x.x only)   ¦
        +---------------------+
                   ¦
        +---------------------+
        ¦  Gateway NGINX      ¦
        ¦  (Port 8443 HTTPS)  ¦
        +---------------------+
                   ¦
    +--------------+-----------------------------+
    ¦              ¦              ¦              ¦
    ?              ?              ?              ?
+--------+   +----------+   +---------+   +----------+
¦  Dify  ¦   ¦AnythingLLM¦  ¦ClawdBot ¦   ¦Signal API¦
¦ (4343) ¦   ¦  (3001)   ¦  ¦ (18789) ¦   ¦  (8080)  ¦
+--------+   +-----------+  +---------+   +----------+
    ¦              ¦             ¦              ¦
    +-------------------------------------------+
                   ¦
        +---------------------+
        ¦   LiteLLM Router    ¦
        ¦     (Port 4000)     ¦
        +---------------------+
                   ¦
         +------------------+
         ¦                  ¦
         ?                  ?
    +---------+      +------------+
    ¦ Ollama  ¦      ¦ OpenAI API ¦
    ¦ (11434) ¦      ¦  (Cloud)   ¦
    ¦ GPU A10G¦      ¦ GPT-4      ¦
    +---------+      +------------+
         ¦
         ?
+--------------------------------+
¦  /mnt/data (500GB EBS Volume)  ¦
¦  +-- ollama/         (15GB)    ¦
¦  +-- anythingllm/    (20GB)    ¦
¦  +-- dify/           (10GB)    ¦
¦  +-- signal/         (500MB)   ¦
+--------------------------------+

### Port Mapping

| Service | Internal Port | External Port | Protocol | Access |
|---------|---------------|---------------|----------|--------|
| Gateway NGINX | 8443 | 8443 | HTTPS | Tailscale only |
| Dify API | 5001 | - | HTTP | Internal only |
| AnythingLLM | 3001 | - | HTTP | Internal only |
| ClawdBot | 18789 | - | HTTP | Internal only |
| Signal API | 8080 | - | HTTP | Internal only |
| LiteLLM | 4000 | - | HTTP | Internal only |
| Ollama | 11434 | - | HTTP | Internal only |
| PostgreSQL | 5432 | - | TCP | Internal only |
| Redis | 6379 | - | TCP | Internal only |

**Security:** Only ONE port (8443) exposed via Tailscale VPN. All other services are internal-only.

---

## ?? Prerequisites

### Hardware Requirements
- **Instance Type**: AWS EC2 g5.xlarge (or equivalent)
  - 4 vCPUs (AMD EPYC)
  - 16GB RAM
  - NVIDIA A10G GPU (24GB VRAM)
  - 30GB root volume + 500GB EBS volume

### Software Requirements
- Ubuntu 22.04 LTS (fresh install)
- Tailscale account (free tier)
- Phone number for Signal registration
- OpenAI API key (optional, for complex queries)

### AWS Setup
```bash
# 1. Launch g5.xlarge instance (Ubuntu 22.04)
# 2. Attach 500GB gp3 EBS volume
# 3. Mount EBS at /mnt/data (scripts will format)
# 4. Security group: Allow SSH (port 22) only

###Tailscale Setup
# On EC2 instance
###curl -fsSL https://tailscale.com/install.sh | sh
###sudo tailscale up

# On your local machine
# Install Tailscale and connect to same account
# Note the EC2 Tailscale IP (100.x.x.x)

Installation (25 minutes total)
# 1. Clone repository
cd ~
git clone https://github.com/YOUR_USERNAME/ai-platform-installer.git
cd ai-platform-installer/scripts

# 2. System setup (10 minutes)
#    - Installs Docker, NVIDIA drivers, CUDA toolkit
#    - Creates service users and directories
#    - Configures EBS volume at /mnt/data
./1-setup-system.sh

# 3. Deploy services (12 minutes)
#    - Downloads AI models (llama3.2, qwen2.5)
#    - Starts all Docker containers
#    - Configures internal networking
./2-deploy-services.sh

# 4. Link Signal device (2 minutes, interactive)
#    - Generates QR code for Signal pairing
#    - OR registers new phone number
./3-link-signal-device.sh

# 5. Deploy ClawdBot (1 minute)
#    - Starts Signal messaging bot
#    - Connects to AnythingLLM
./4-deploy-clawdbot.sh

# 6. Configure services (2 minutes)
#    - Tests all connections
#    - Configures API keys
#    - Verifies end-to-end flow
./5-configure-services.sh

?? Directory Structure

ai-platform-installer/
+-- README.md                    # This file
+-- .env                         # Main configuration (generated by setup script)
+-- .secrets                     # API keys, passwords (generated, gitignored)
+-- .gitignore                   # Excludes secrets, stacks/, logs/
¦
+-- scripts/                     # All executable scripts
¦   +-- 0-complete-cleanup.sh    # ?? Removes everything, back to fresh Ubuntu
¦   +-- 1-setup-system.sh        # System preparation (Docker, NVIDIA, users)
¦   +-- 2-deploy-services.sh     # Deploy all containers
¦   +-- 3-link-signal-device.sh  # Interactive Signal pairing
¦   +-- 4-deploy-clawdbot.sh     # ClawdBot deployment
¦   +-- 5-configure-services.sh  # Post-deployment configuration
¦
+-- stacks/                      # Generated during deployment (gitignored)
¦   +-- ollama/
¦   ¦   +-- docker-compose.yml
¦   +-- litellm/
¦   ¦   +-- docker-compose.yml
¦   ¦   +-- config.yaml
¦   +-- signal/
¦   ¦   +-- docker-compose.yml
¦   +-- dify/
¦   ¦   +-- docker-compose.yml
¦   ¦   +-- .env
¦   +-- anythingllm/
¦   ¦   +-- docker-compose.yml
¦   +-- clawdbot/
¦       +-- docker-compose.yml
¦       +-- clawdbot.py
¦
+-- logs/                        # Generated during runtime (gitignored)
    +-- setup.log
    +-- deploy.log
    +-- <service>.log

## ¿ Repository Structure

This repository is **path-agnostic** and works regardless of folder name:

```bash
# Works with any name:
~/AIPlatformAutomation/
~/ai-platform/
~/my-ai-stack/
/opt/ai-platform/

# Scripts auto-detect location
cd ~/AIPlatformAutomation/scripts
./1-setup-system.sh  # ¿ Automatically finds parent directory

What to commit to Git:

? README.md, scripts/*.sh
? .env, .secrets (contain API keys)
? stacks/ (generated during deployment)
? logs/ (runtime logs)



