\# 🤖 AIPlatformAutomation

\*\*Enterprise-grade AI platform deployment automation for self-hosted infrastructure\*\*

\[\!\[License: MIT\](https://img.shields.io/badge/License-MIT-yellow.svg)\](https://opensource.org/licenses/MIT)  
\[\!\[Shell Script\](https://img.shields.io/badge/Shell\_Script-121011?logo=gnu-bash\&logoColor=white)\](https://www.gnu.org/software/bash/)  
\[\!\[Docker\](https://img.shields.io/badge/Docker-2496ED?logo=docker\&logoColor=white)\](https://www.docker.com/)

\---

\#\# 📑 Table of Contents

\- \[Overview\](\#overview)  
\- \[Architecture\](\#architecture)  
  \- \[Network Architecture\](\#network-architecture)  
  \- \[Service Architecture\](\#service-architecture)  
\- \[Features\](\#features)  
\- \[Prerequisites\](\#prerequisites)  
\- \[Installation\](\#installation)  
  \- \[Quick Start\](\#quick-start)  
  \- \[Step-by-Step Guide\](\#step-by-step-guide)  
\- \[Scripts Documentation\](\#scripts-documentation)  
  \- \[Script 0: Complete Cleanup\](\#script-0-complete-cleanup)  
  \- \[Script 1: Setup System\](\#script-1-setup-system)  
  \- \[Script 2: Deploy Services\](\#script-2-deploy-services)  
  \- \[Script 3: Configure Services\](\#script-3-configure-services)  
  \- \[Script 4: Add Service\](\#script-4-add-service)  
\- \[Service Stack\](\#service-stack)  
  \- \[Core Infrastructure\](\#core-infrastructure)  
  \- \[Vector Databases\](\#vector-databases)  
  \- \[LLM Layer\](\#llm-layer)  
  \- \[AI Applications\](\#ai-applications)  
  \- \[Workflow Tools\](\#workflow-tools)  
  \- \[Communication Layer\](\#communication-layer)  
  \- \[Reverse Proxy\](\#reverse-proxy)  
\- \[Configuration\](\#configuration)  
  \- \[Directory Structure\](\#directory-structure)  
  \- \[Network Configuration\](\#network-configuration)  
  \- \[LiteLLM Configuration\](\#litellm-configuration)  
  \- \[Signal Configuration\](\#signal-configuration)  
  \- \[Google Drive Configuration\](\#google-drive-configuration)  
\- \[Usage Examples\](\#usage-examples)  
\- \[Troubleshooting\](\#troubleshooting)  
\- \[Advanced Topics\](\#advanced-topics)  
\- \[Contributing\](\#contributing)  
\- \[License\](\#license)

\---

\#\# Overview

\*\*AIPlatformAutomation\*\* provides a complete, production-ready automation framework for deploying a self-hosted AI platform with intelligent routing, vector databases, and communication integrations.

\#\#\# Key Capabilities

\- 🔒 \*\*Privacy-First\*\*: Complete data sovereignty with self-hosted infrastructure  
\- 🎨 \*\*Modular Design\*\*: Choose from 10+ AI services based on your needs  
\- 🔄 \*\*Production-Ready\*\*: Battle-tested deployment with health checks and monitoring  
\- 🚀 \*\*Zero-to-Hero\*\*: Bare metal to operational AI platform in \<30 minutes  
\- 🔌 \*\*Integration-Native\*\*: Pre-configured LiteLLM routing, Signal messaging, RAG pipelines

\#\#\# Why This Project?

Traditional AI deployments require extensive DevOps knowledge and manual configuration across dozens of services. This project provides:

1\. \*\*Unified Deployment\*\*: Single command deployment of interconnected AI services  
2\. \*\*Intelligent Routing\*\*: LiteLLM-based cost and latency optimization across 100+ LLM providers  
3\. \*\*RAG-Ready\*\*: Pre-configured vector databases with document ingestion pipelines  
4\. \*\*Communication Integration\*\*: Signal API and OpenClaw for message routing  
5\. \*\*Production Patterns\*\*: Proper secret management, health checks, and rollback capabilities

\---

\#\# Architecture

\#\#\# Network Architecture

┌─────────────────────────────────────────────────────────────────┐ │ Public Internet │ └────────────────────────────┬────────────────────────────────────┘ │ │ HTTPS (443) / HTTP (80) │ ┌─────────▼─────────┐ │ Reverse Proxy │ │ (SWAG / NPM) │ │ │ │ • SSL Termination│ │ • Domain Routing │ │ • Rate Limiting │ └─────────┬─────────┘ │ ┌───────────────────┼───────────────────┐ │ │ │ Public Routes Internal Routes Admin Routes (80/443) (Tailscale Only) (Tailscale Only) │ │ │ │ │ │ │ │ │ ┌────────▼────────┐ ┌──────▼──────┐ ┌───────▼────────┐ │ Marketing │ │ Tailscale │ │ Admin Panel │ │ Landing Page │ │ 100.x.x.x │ │ │ │ │ │ │ │ Port: 18789 │ │ Public Demo │ │ VPN Access │ │ │ └─────────────────┘ └──────┬──────┘ │ • LiteLLM UI │ │ │ • Metrics │ │ │ • Logs │ │ └────────────────┘ │ ┌──────────────┼──────────────┐ │ │ │ ┌───────▼──────┐ ┌────▼─────┐ ┌─────▼──────┐ │ AI UIs │ │ Workflow │ │ Comms │ │ │ │ Tools │ │ Layer │ │ • OpenWebUI │ │ │ │ │ │ • AnythingLLM│ │ • n8n │ │ • Signal │ │ • Dify │ │ • Flowise│ │ • OpenClaw │ │ • ComfyUI │ │ │ │ │ └──────┬───────┘ └────┬─────┘ └─────┬──────┘ │ │ │ └──────────────┼──────────────┘ │ ┌───────▼────────┐ │ LiteLLM │ │ Routing Layer │ │ │ │ • Cost Track │ │ • Fallbacks │ │ • Caching │ └───────┬────────┘ │ ┌─────────────────┼─────────────────┐ │ │ │ ┌───────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐ │ Ollama │ │ OpenAI │ │ Anthropic │ │ (Local) │ │ (API) │ │ (API) │ │ │ │ │ │ │ │ Port: 11434 │ │ External │ │ External │ └──────────────┘ └─────────────┘ └─────────────┘ │ ┌─────────────────┼─────────────────┐ │ │ │ ┌───────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐ │ Vector DB │ │ Postgres │ │ Redis │ │ (Qdrant/etc) │ │ │ │ │ │ │ │ Port: 5432 │ │ Port: 6379 │ │ Port: 6333 │ │ │ │ │ └──────────────┘ └─────────────┘ └─────────────┘

\*\*Network Segmentation\*\*:

1\. \*\*Public Layer (Ports 80/443)\*\*:  
   \- Accessible from internet  
   \- Routes through selected reverse proxy (SWAG or Nginx Proxy Manager)  
   \- SSL/TLS termination  
   \- Optional: Public-facing demo or landing page

2\. \*\*Tailscale Private Network (100.x.x.x)\*\*:  
   \- All AI services accessible via Tailscale VPN  
   \- Admin panel on port \*\*18789\*\* (Tailscale IP only)  
   \- Direct service access bypassing proxy  
   \- Secure inter-service communication

3\. \*\*Admin Services (Tailscale Only)\*\*:  
   \- LiteLLM Admin UI: \`http://\<tailscale-ip\>:18789\`  
   \- Prometheus: \`http://\<tailscale-ip\>:9090\`  
   \- Grafana: \`http://\<tailscale-ip\>:3005\`

\*\*Access Patterns\*\*:

Public User → [https://yourdomain.com](https://yourdomain.com) → Proxy (80/443) → Service

Admin/Team → Tailscale → [http://100.x.x.x:18789](http://100.x.x.x:18789) → LiteLLM UI Admin/Team → Tailscale → [http://100.x.x.x:8080](http://100.x.x.x:8080) → Open WebUI Admin/Team → Tailscale → [http://100.x.x.x:3001](http://100.x.x.x:3001) → AnythingLLM

\---

\#\#\# Service Architecture

┌─────────────────────────────────────────────────────────────────┐ │ Application Layer │ │ │ │ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ │ │ │ OpenWebUI │ │ AnythingLLM │ │ Dify │ │ │ │ │ │ │ │ │ │ │ │ Chat UI │ │ Doc Chat │ │ LLM Apps │ │ │ └──────┬───────┘ └──────┬───────┘ └──────┬───────┘ │ │ │ │ │ │ └─────────┼─────────────────┼─────────────────┼───────────────────┘ │ │ │ │ │ │ ┌─────────▼─────────────────▼─────────────────▼───────────────────┐ │ Routing Layer │ │ │ │ ┌───────────────────────────────────────────────────────────┐ │ │ │ LiteLLM │ │ │ │ │ │ │ │ • Unified API (OpenAI-compatible) │ │ │ │ • Cost tracking & budgets │ │ │ │ • Intelligent routing (cost/latency/load) │ │ │ │ • Fallback chains │ │ │ │ • Response caching (Redis) │ │ │ │ • Prometheus metrics │ │ │ └───────────────────────────────────────────────────────────┘ │ │ │ └───────────────────────────────┬───────────────────────────────────┘ │ ┌───────────────────────┼───────────────────────┐ │ │ │ ┌───────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐ │ Ollama │ │ API │ │ API │ │ (Local) │ │ Providers │ │ Providers │ │ │ │ │ │ │ │ • llama3.2 │ │ • OpenAI │ │ • Anthropic │ │ • mistral │ │ • Groq │ │ • Google │ │ • codellama │ │ • Together │ │ • Cohere │ └──────────────┘ └─────────────┘ └─────────────┘

\*\*Data Flow\*\*:  
1\. User sends message to UI (OpenWebUI, AnythingLLM, Dify)  
2\. UI calls LiteLLM unified API endpoint  
3\. LiteLLM routes to optimal provider based on strategy  
4\. Response cached in Redis for identical queries  
5\. Metrics sent to Prometheus  
6\. Result returned to user

\---

\#\# Features

\#\#\# 🎨 Interactive User Experience

All scripts feature a rich terminal UI with:

\*\*Color-Coded Output\*\*:  
\- 🟢 \*\*Green\*\*: Success messages and completions  
\- 🟡 \*\*Yellow\*\*: Warnings and important notes  
\- 🔴 \*\*Red\*\*: Errors and failures  
\- 🔵 \*\*Blue\*\*: Informational messages  
\- 🟣 \*\*Magenta\*\*: Step indicators

\*\*Icons & Formatting\*\*:

✅ Service deployed successfully ❌ Configuration failed ⚠️ Warning: Port conflict detected ℹ️ Info: Using default configuration ⚙️ Configuring service... 🔑 API key required 🤖 LLM provider added 📱 Signal paired successfully

\*\*Progress Indicators\*\*:

\[████████████████░░░░\] 80% Deploying services...

\*\*Interactive Menus\*\*:

╔════════════════════════════════════════════════════════════╗ ║ 🤖 AIPlatformAutomation v76.5 ║ ╚════════════════════════════════════════════════════════════╝

Select services to deploy:

☐ 1\) Open WebUI \- Modern ChatGPT-like interface ☑ 2\) AnythingLLM \- Document-based AI chat (SELECTED) ☐ 3\) Dify \- LLM application development platform ☑ 4\) n8n \- Workflow automation (SELECTED) ☐ 5\) Flowise \- Visual LangChain builder

\[Space\] Toggle \[Enter\] Confirm \[Q\] Quit

\---

\#\#\# 🔧 System Management

\*\*Hardware Detection\*\*:  
\- Automatic GPU detection (NVIDIA)  
\- EBS volume discovery and mounting  
\- CPU core and RAM detection  
\- Network interface enumeration

\*\*Dependency Installation\*\*:  
\- Docker Engine  
\- Docker Compose v2  
\- NVIDIA Container Toolkit (if GPU present)  
\- Ollama (optional, for local LLMs)  
\- Tailscale (optional, for private networking)

\*\*Service Selection\*\*:  
\- Multi-select interface with dependency checking  
\- Real-time validation (e.g., Dify requires Vector DB)  
\- Port conflict detection  
\- Resource requirement warnings

\---

\#\#\# 🤖 LLM Provider Management

\*\*Supported Providers\*\* (100+):  
\- \*\*Local\*\*: Ollama, LM Studio  
\- \*\*API\*\*: OpenAI, Anthropic, Google, Groq, Mistral, Cohere, Together AI  
\- \*\*Self-hosted\*\*: vLLM, text-generation-webui, LocalAI

\*\*Configuration Options\*\*:  
\- Add/remove providers  
\- Update API keys  
\- Test connectivity  
\- Set model aliases  
\- Configure rate limits  
\- Set budget caps

\*\*LiteLLM Routing Strategies\*\*:  
1\. \*\*Simple Shuffle\*\*: Random selection  
2\. \*\*Cost-Based\*\*: Choose cheapest model first  
3\. \*\*Latency-Based\*\*: Choose fastest model based on history  
4\. \*\*Usage-Based\*\*: Load balance across models  
5\. \*\*Custom\*\*: Define your own logic

\---

\#\#\# 🗄️ Vector Database Integration

\*\*Supported Databases\*\*:  
\- \*\*Qdrant\*\* (Recommended): REST \+ gRPC, web dashboard  
\- \*\*Milvus\*\*: High performance, distributed support  
\- \*\*ChromaDB\*\*: Simple, Python-native  
\- \*\*Weaviate\*\*: GraphQL API, semantic search

\*\*Features\*\*:  
\- Automatic collection creation  
\- Connection testing  
\- Performance monitoring  
\- Backup/restore capabilities

\---

\#\#\# 📱 Communication Integration

\*\*Signal API\*\*:  
\- QR code pairing workflow  
\- Send/receive messages  
\- Group support  
\- Attachment handling  
\- Webhook mode

\*\*OpenClaw UI\*\*:  
\- Multi-channel message orchestration  
\- LLM integration  
\- Routing rules  
\- Message history

\*\*Webhook Configuration\*\*:  
\- OpenClaw → Signal routing  
\- AnythingLLM → Signal notifications  
\- Dify → Signal alerts  
\- n8n → LiteLLM calls

\---

\#\#\# 📁 Google Drive Integration

\*\*Features\*\*:  
\- OAuth 2.0 authentication  
\- Automated document sync  
\- Configurable sync intervals  
\- Selective folder sync  
\- Format support: PDF, DOCX, TXT, MD, CSV

\*\*Workflow\*\*:  
1\. User uploads document to Google Drive  
2\. rclone syncs to local \`/mnt/data/documents\`  
3\. Document processor chunks and embeds  
4\. Vectors stored in selected Vector DB  
5\. Available for RAG queries in AnythingLLM/Dify

\---

\#\# Prerequisites

\#\#\# System Requirements

| Component | Minimum | Recommended |  
|-----------|---------|-------------|  
| \*\*OS\*\* | Ubuntu 22.04 LTS | Ubuntu 22.04+ LTS |  
| \*\*CPU\*\* | 4 cores (x86\_64) | 8+ cores |  
| \*\*RAM\*\* | 16 GB | 32+ GB |  
| \*\*Storage\*\* | 100 GB | 500+ GB SSD/NVMe |  
| \*\*GPU\*\* | None (CPU inference) | NVIDIA (8GB+ VRAM) |  
| \*\*Network\*\* | 10 Mbps | 100+ Mbps |

\#\#\# Software Requirements

\*\*Required\*\*:  
\- \`bash\` 4.0+  
\- \`sudo\` privileges  
\- Internet connectivity

\*\*Auto-Installed\*\*:  
\- Docker Engine 24.0+  
\- Docker Compose v2.20+  
\- NVIDIA drivers \+ Container Toolkit (if GPU detected)  
\- Ollama (optional)  
\- Tailscale (optional)

\#\#\# Account Requirements (Optional)

\*\*For API LLM Providers\*\*:  
\- OpenAI API key (\[platform.openai.com\](https://platform.openai.com))  
\- Anthropic API key (\[console.anthropic.com\](https://console.anthropic.com))  
\- Google AI API key (\[makersuite.google.com\](https://makersuite.google.com))  
\- Groq API key (\[console.groq.com\](https://console.groq.com))

\*\*For Google Drive Sync\*\*:  
\- Google Cloud project with Drive API enabled  
\- OAuth 2.0 credentials (Client ID \+ Secret)

\*\*For Public Access\*\*:  
\- Domain name (for SSL certificates)  
\- DNS configured to point to your server

\---

\#\# Installation

\#\#\# Quick Start

\`\`\`bash  
\# Clone repository  
git clone https://github.com/jgla1ne/AIPlatformAutomation.git  
cd AIPlatformAutomation

\# Make scripts executable  
chmod \+x scripts/\*.sh

\# Run interactive setup  
sudo ./scripts/1-setup-system.sh

\# Deploy selected services  
sudo ./scripts/2-deploy-services.sh

\# Configure services (optional)  
sudo ./scripts/3-configure-services.sh

**Total time**: 15-30 minutes depending on internet speed and service selection.

---

### **Step-by-Step Guide**

#### **Step 1: System Preparation**

\# Update system packages  
sudo apt update && sudo apt upgrade \-y

\# Clone repository  
git clone https://github.com/jgla1ne/AIPlatformAutomation.git  
cd AIPlatformAutomation

\# Make scripts executable  
chmod \+x scripts/\*.sh

#### **Step 2: Run System Setup**

sudo ./scripts/1-setup-system.sh

**What This Does**:

**Hardware Detection**:

 ╔════════════════════════════════════════════════════════════╗  
║          🖥️  HARDWARE DETECTION                            ║  
╚════════════════════════════════════════════════════════════╝

✅ GPU Detected: NVIDIA RTX 4090 (24GB VRAM)  
✅ EBS Volume: /dev/nvme1n1 (500GB)  
ℹ️  CPU: 16 cores  
ℹ️  RAM: 64GB

1. 

**Storage Configuration**:

 ╔════════════════════════════════════════════════════════════╗  
║          💾 STORAGE CONFIGURATION                          ║  
╚════════════════════════════════════════════════════════════╝

Detected EBS volume: /dev/nvme1n1 (500GB)

Options:  
  1\) Format and mount as /mnt/data  
  2\) Mount existing filesystem  
  3\) Skip (use root filesystem)

Select option \[1-3\]: 

2. 

**Service Selection**:

 ╔════════════════════════════════════════════════════════════╗  
║          📦 SERVICE SELECTION                              ║  
╚════════════════════════════════════════════════════════════╝

Select services to deploy (Space to toggle, Enter to confirm):

AI Interfaces:  
  ☑ 1\) Open WebUI \- ChatGPT-like interface for Ollama/LiteLLM  
  ☑ 2\) AnythingLLM \- Document-based AI chat with RAG  
  ☐ 3\) Dify \- LLM application development platform  
  ☐ 4\) ComfyUI \- Advanced image generation (GPU required)

Workflow Tools:  
  ☑ 5\) n8n \- Workflow automation  
  ☐ 6\) Flowise \- Visual LangChain builder

Communication:  
  ☑ 7\) Signal API \- Signal messaging integration  
  ☑ 8\) OpenClaw UI \- Message orchestration hub

Infrastructure:  
  ☑ 9\) PostgreSQL \- Relational database  
  ☑ 10\) Redis \- Cache and message queue  
  ☑ 11\) Qdrant \- Vector database

LLM:  
  ☑ 12\) Ollama \- Local LLM runtime  
  ☑ 13\) LiteLLM \- Universal LLM routing layer

Proxy:  
  ☐ 14\) SWAG \- Secure Web Application Gateway  
  ☑ 15\) Nginx Proxy Manager \- Visual reverse proxy (RECOMMENDED)

Monitoring:  
  ☐ 16\) Prometheus \+ Grafana \- Metrics and dashboards

\[Selected: 11 services\]  \[D\]ependency Check  \[C\]ontinue  \[Q\]uit

3. 

**Vector Database Selection**:

 ╔════════════════════════════════════════════════════════════╗  
║          🗄️  VECTOR DATABASE SELECTION                     ║  
╚════════════════════════════════════════════════════════════╝

Choose vector database for AnythingLLM:

  1\) Qdrant (Recommended)  
     \- REST \+ gRPC API  
     \- Web dashboard  
     \- Production-ready

  2\) Milvus  
     \- High performance  
     \- Distributed support  
     \- Complex setup

  3\) ChromaDB  
     \- Simple setup  
     \- Python-native  
     \- Good for development

  4\) Weaviate  
     \- GraphQL API  
     \- Semantic search  
     \- Modular architecture

Select \[1-4\]: 

4. 

**LLM Provider Configuration**:

 ╔════════════════════════════════════════════════════════════╗  
║          🤖 LLM PROVIDER CONFIGURATION                     ║  
╚════════════════════════════════════════════════════════════╝

Configure LLM providers for LiteLLM routing:

✅ Local Provider:  
   • Ollama (will be deployed)  
   • Models: llama3.2, mistral, codellama

Add API providers? (recommended for fallback)

  1\) OpenAI (GPT-4, GPT-3.5)  
  2\) Anthropic (Claude 3\)  
  3\) Google (Gemini)  
  4\) Groq (Fast Llama inference)  
  5\) All of the above  
  6\) Skip API providers

Select \[1-6\]: 1

Enter OpenAI API key (sk-...): 

5. 

**LiteLLM Routing Strategy**:

 ╔════════════════════════════════════════════════════════════╗  
║          🔄 LITELLM ROUTING CONFIGURATION                  ║  
╚════════════════════════════════════════════════════════════╝

Select routing strategy:

  1\) simple-shuffle  
     Random selection from available models

  2\) cost-based-routing (Recommended)  
     Choose cheapest model first, fallback on expensive

  3\) latency-based-routing  
     Choose fastest model based on historical latency

  4\) usage-based-routing  
     Load balance across all models

Select \[1-4\]: 2

Configure fallback chain:  
  Primary: llama3.2 (Ollama \- local)  
  Fallback 1: gpt-3.5-turbo (OpenAI \- $0.0005/1K tokens)  
  Fallback 2: gpt-4 (OpenAI \- $0.03/1K tokens)

Confirm? (yes/no): yes

6. 

**Signal API Configuration**:

 ╔════════════════════════════════════════════════════════════╗  
║          📱 SIGNAL API CONFIGURATION                       ║  
╚════════════════════════════════════════════════════════════╝

Set up Signal messaging integration:

  1\) Configure now (recommended)  
  2\) Configure later via Script 3

Select \[1-2\]: 1

Enter your phone number (with country code, e.g., \+1234567890): \+15551234567

ℹ️  Signal API will be deployed  
ℹ️  QR code for pairing will be shown after deployment  
ℹ️  Keep your phone ready\!

7. 

**Google Drive Configuration**:

 ╔════════════════════════════════════════════════════════════╗  
║          📁 GOOGLE DRIVE INTEGRATION                       ║  
╚════════════════════════════════════════════════════════════╝

Set up automatic document sync from Google Drive:

  1\) Configure now  
  2\) Configure later via Script 3  
  3\) Skip Google Drive integration

Select \[1-3\]: 1

Google Drive OAuth Setup:

1\. Go to: https://console.cloud.google.com  
2\. Create project or select existing  
3\. Enable "Google Drive API"  
4\. Create OAuth 2.0 credentials (Desktop app)  
5\. Enter credentials below:

Client ID: \<paste-here\>  
Client Secret: \<paste-here\>

ℹ️  OAuth authorization will be completed after deployment

8. 

**Network Configuration**:

 ╔════════════════════════════════════════════════════════════╗  
║          🌐 NETWORK CONFIGURATION                          ║  
╚════════════════════════════════════════════════════════════╝

Tailscale setup (recommended for secure access):

  1\) Install and configure Tailscale  
  2\) Skip Tailscale (use local network only)

Select \[1-2\]: 1

Installing Tailscale...

Run this command to authenticate:  
  sudo tailscale up

Your Tailscale IP will be used for admin access.

9. 

**Configuration Summary**:

 ╔════════════════════════════════════════════════════════════╗  
║          ✅ SETUP COMPLETE                                 ║  
╚════════════════════════════════════════════════════════════╝

Configuration Summary:

📦 Services Selected: 11  
   • Open WebUI, AnythingLLM, n8n  
   • Signal API, OpenClaw UI  
   • PostgreSQL, Redis, Qdrant  
   • Ollama, LiteLLM  
   • Nginx Proxy Manager

🤖 LLM Providers: 2  
   • Ollama (local)  
   • OpenAI (API)

🔄 Routing Strategy: cost-based-routing

📱 Signal: Configured (+15551234567)

📁 Google Drive: Configured

🌐 Network: Tailscale (100.x.x.x)

💾 Data Directory: /mnt/data

Metadata saved to: /mnt/data/metadata/

Next step: Run ./scripts/2-deploy-services.sh

10. 

---

#### **Step 3: Deploy Services**

sudo ./scripts/2-deploy-services.sh

**What This Does**:

**Pre-Deployment Checks**:

 ╔════════════════════════════════════════════════════════════╗  
║          🔍 PRE-DEPLOYMENT VALIDATION                      ║  
╚════════════════════════════════════════════════════════════╝

✅ Docker is running  
✅ Docker Compose v2.20.0 installed  
✅ Configuration metadata found  
✅ /mnt/data mounted (450GB free)  
✅ No port conflicts detected

Services to deploy: 11  
Estimated deployment time: 15-20 minutes

Continue? (yes/no): yes

1. 

**Infrastructure Deployment**:

 ╔════════════════════════════════════════════════════════════╗  
║          🏗️  DEPLOYING INFRASTRUCTURE                      ║  
╚════════════════════════════════════════════════════════════╝

\[1/11\] Deploying PostgreSQL...  
       ✅ Compose file generated  
       ✅ Container started  
       ✅ Health check passed  
       ℹ️  Port: 5432

\[2/11\] Deploying Redis...  
       ✅ Compose file generated  
       ✅ Container started  
       ✅ Health check passed  
       ℹ️  Port: 6379

\[3/11\] Deploying Qdrant...  
       ✅ Compose file generated  
       ✅ Container started  
       ✅ Health check passed  
       ℹ️  Ports: 6333 (HTTP), 6334 (gRPC)  
       ℹ️  Dashboard: http://localhost:6333/dashboard

2. 

**LLM Layer Deployment**:

 \[4/11\] Deploying Ollama...  
       ✅ Compose file generated  
       ✅ GPU support enabled (NVIDIA)  
       ✅ Container started  
       ⏳ Pulling models (this may take 5-10 minutes)...  
          \[██████████░░░░░░░░░░\] 50% llama3.2:latest  
       ✅ Model llama3.2:latest ready  
       ✅ Model mistral:latest ready  
       ℹ️  Port: 11434

\[5/11\] Deploying LiteLLM...  
       ✅ Compose file generated  
       ✅ Configuration file generated  
          • Providers: Ollama, OpenAI  
          • Routing: cost-based-routing  
          • Caching: Redis  
       ✅ Container started  
       ✅ Health check passed  
       ℹ️  API Port: 4000  
       ℹ️  Admin UI: http://100.x.x.x:18789 (Tailscale only)

3. 

**AI Applications Deployment**:

 \[6/11\] Deploying Open WebUI...  
       ✅ Compose file generated  
       ✅ Linked to LiteLLM  
       ✅ Container started  
       ℹ️  Port: 8080  
       ℹ️  Access: http://100.x.x.x:8080

\[7/11\] Deploying AnythingLLM...  
       ✅ Compose file generated  
       ✅ Vector DB configured (Qdrant)  
       ✅ Container started  
       ℹ️  Port: 3001  
       ℹ️  Access: http://100.x.x.x:3001

\[8/11\] Deploying n8n...  
       ✅ Compose file generated  
       ✅ PostgreSQL linked  
       ✅ LiteLLM webhook configured  
       ✅ Container started  
       ℹ️  Port: 5678  
       ℹ️  Access: http://100.x.x.x:5678

4. 

**Communication Layer Deployment**:

 \[9/11\] Deploying Signal API...  
       ✅ Compose file generated  
       ✅ Container started  
         
       📱 SIGNAL PAIRING REQUIRED  
         
       Scan this QR code with Signal app on your phone:  
       (Settings → Linked Devices → Link New Device)  
         
       ████ ▄▄▄▄▄ █▀█ █▄▀▄▀▄█ ▄▄▄▄▄ ████  
       ████ █   █ █▀▀▀█ ▀ ▀▀█ █   █ ████  
       ████ █▄▄▄█ █▀ █▀▀ ▄ ▀█ █▄▄▄█ ████  
       ████▄▄▄▄▄▄▄█▄▀ █▄▀ ▀ █▄▄▄▄▄▄▄████  
       ████▄▀▄▀ ▄▄ ▄▀▄▄▀█▀▄  ▄▀▀█▀▄████  
       ████▀ ▄▄▀▄▄▀█▀ █ ▀▀█▀▀█▀▀█ ▀████  
       ...  
         
       ⏳ Waiting for pairing... (timeout: 5 minutes)  
         
       ✅ Device paired successfully\!  
       ℹ️  Phone: \+15551234567  
       ℹ️  Webhook URL: http://signal-api:8090/v2/receive

\[10/11\] Deploying OpenClaw UI...  
        ✅ Compose file generated  
        ✅ Signal webhook configured  
        ✅ Container started  
        ℹ️  Port: 3000  
        ℹ️  Access: http://100.x.x.x:3000

5. 

**Reverse Proxy Deployment**:

 \[11/11\] Deploying Nginx Proxy Manager...  
        ✅ Compose file generated  
        ✅ Container started  
        ℹ️  Ports: 80 (HTTP), 443 (HTTPS), 81 (Admin)  
        ℹ️  Admin Panel: http://100.x.x.x:81  
          
        📝 Default Credentials:  
           Email: admin@example.com  
           Password: changeme  
          
        ⚠️  IMPORTANT: Change password after first login\!

6. 

**Post-Deployment Configuration**:

 ╔════════════════════════════════════════════════════════════╗  
║          ⚙️  POST-DEPLOYMENT CONFIGURATION                 ║  
╚════════════════════════════════════════════════════════════╝

Running health checks...  
✅ PostgreSQL: Healthy  
✅ Redis: Healthy  
✅ Qdrant: Healthy  
✅ Ollama: Healthy (2 models loaded)  
✅ LiteLLM: Healthy  
✅ Open WebUI: Healthy  
✅ AnythingLLM: Healthy  
✅ n8n: Healthy  
✅ Signal API: Healthy (paired)  
✅ OpenClaw UI: Healthy  
✅ Nginx Proxy Manager: Healthy

Configuring Google Drive sync...  
⏳ Opening OAuth authorization URL...

Please authorize in your browser, then return here.

✅ Google Drive authorized  
✅ Sync configured (interval: 1 hour)  
✅ Initial sync complete (0 documents found)

7. 

**Deployment Summary**:

 ╔════════════════════════════════════════════════════════════╗  
║          🎉 DEPLOYMENT COMPLETE                            ║  
╚════════════════════════════════════════════════════════════╝

All services deployed successfully\!

📊 Service Access (via Tailscale IP: 100.x.x.x):

AI Interfaces:  
  • Open WebUI:    http://100.x.x.x:8080  
  • AnythingLLM:   http://100.x.x.x:3001

Workflow Tools:  
  • n8n:           http://100.x.x.x:5678

Communication:  
  • OpenClaw UI:   http://100.x.x.x:3000

Admin Panels:  
  • LiteLLM UI:    http://100.x.x.x:18789  
  • Nginx PM:      http://100.x.x.x:81  
  • Qdrant:        http://100.x.x.x:6333/dashboard

🔐 Generated Credentials saved to:  
   /mnt/data/metadata/credentials.json

📝 Next Steps:

1\. Access Nginx Proxy Manager (http://100.x.x.x:81)  
   \- Login with default credentials  
   \- Change password  
   \- Add SSL certificates  
   \- Configure domain routing

2\. Access Open WebUI (http://100.x.x.x:8080)  
   \- Create your first user account  
   \- Start chatting with Ollama/LiteLLM

3\. Access AnythingLLM (http://100.x.x.x:3001)  
   \- Create workspace  
   \- Upload documents  
   \- Start document-based Q\&A

4\. Configure webhooks (optional):  
   Run: sudo ./scripts/3-configure-services.sh

5\. Add more services (optional):  
   Run: sudo ./scripts/4-add-service.sh

📚 Documentation: /mnt/data/metadata/deployment\_info.json

Enjoy your AI platform\! 🚀

8. 

---

#### **Step 4: Configure Services (Optional)**

sudo ./scripts/3-configure-services.sh

**Main Menu**:

╔════════════════════════════════════════════════════════════╗  
║  ⚙️  AIPlatformAutomation \- Configuration Manager v76.5   ║  
╚════════════════════════════════════════════════════════════╝

    Interactive service configuration and reconfiguration tool

Current Status:  
  • Services Running: 11/11  
  • LLM Providers: 2 (Ollama, OpenAI)  
  • Routing Strategy: cost-based-routing  
  • Signal: Paired (+15551234567)  
  • Google Drive: Synced (last: 5 min ago)

╔════════════════════════════════════════════════════════════╗  
║                      MAIN MENU                             ║  
╚════════════════════════════════════════════════════════════╝

  🤖  1\) Manage LLM Providers  
  🔄  2\) Reconfigure LiteLLM Routing  
  🗄️   3\) Manage Vector Databases  
  📱  4\) Configure Signal API  
  📁  5\) Configure Google Drive Sync  
  🔗  6\) Configure Webhooks  
  🌐  7\) Configure Reverse Proxy  
  🔍  8\) Test Service Connections  
  📊  9\) View Current Configuration  
  🔄  10\) Hot-Reload Services  
  🔐  11\) Rotate Credentials  
  💾  12\) Backup Configuration  
  ❌  13\) Remove Service  
  🚪  0\) Exit

Select option \[0-13\]: 

**(Detailed submenu interactions follow same pattern as Step 2 \- interactive, color-coded, icon-rich)**

---

#### **Step 5: Add More Services (Optional)**

sudo ./scripts/4-add-service.sh

**Service Catalog**:

╔════════════════════════════════════════════════════════════╗  
║          ➕ ADD SERVICE                                     ║  
╚════════════════════════════════════════════════════════════╝

Available services not yet deployed:

  1\) 🎨 Dify  
     LLM application development platform  
     Dependencies: PostgreSQL ✅, Redis ✅, Vector DB ✅  
     Port: 3002

  2\) 🌊 Flowise  
     Drag-and-drop LangChain builder  
     Dependencies: PostgreSQL ✅  
     Port: 3003

  3\) 🖼️  ComfyUI  
     Advanced image generation with Stable Diffusion  
     Dependencies: None  
     Port: 8188  
     ⚠️  GPU recommended (or very slow)

  4\) 📊 Monitoring Stack (Prometheus \+ Grafana)  
     Service metrics and dashboards  
     Dependencies: None  
     Ports: 9090 (Prometheus), 3005 (Grafana)

  0\) Back to main menu

Select service to add \[0-4\]: 1

╔════════════════════════════════════════════════════════════╗  
║          🎨 DEPLOYING DIFY                                 ║  
╚════════════════════════════════════════════════════════════╝

Pre-deployment checks:  
  ✅ Dependencies satisfied  
  ✅ No port conflicts  
  ✅ Sufficient disk space

Generating configuration...  
  ✅ dify-api.yml created  
  ✅ dify-worker.yml created  
  ✅ dify-web.yml created  
  ✅ dify.env created

Deploying services...  
  \[1/3\] Deploying dify-api...       ✅  
  \[2/3\] Deploying dify-worker...    ✅  
  \[3/3\] Deploying dify-web...       ✅

Running health checks...  
  ✅ dify-api: Healthy  
  ✅ dify-worker: Healthy  
  ✅ dify-web: Healthy

Configuring integrations...  
  ✅ Vector DB (Qdrant) connected  
  ✅ LiteLLM endpoint configured  
  ✅ PostgreSQL schema initialized

╔════════════════════════════════════════════════════════════╗  
║          ✅ DIFY DEPLOYED SUCCESSFULLY                     ║  
╚════════════════════════════════════════════════════════════╝

Access Information:  
  • Web UI:  http://100.x.x.x:3002  
  • API:     http://100.x.x.x:5001

First-Time Setup:  
  1\. Open http://100.x.x.x:3002  
  2\. Create admin account  
  3\. Configure LLM providers (already pre-filled with LiteLLM)  
  4\. Create your first app\!

Documentation:  
  • Official Docs: https://docs.dify.ai  
  • Local Info: /mnt/data/metadata/dify\_info.json

Press Enter to continue...

---

## **Scripts Documentation**

### **Script 0: Complete Cleanup**

**File**: `scripts/0-complete-cleanup.sh`

**Purpose**: Remove all deployed services, data, and configuration (factory reset)

**⚠️ DANGER**: This script will **permanently delete** all data, containers, images, and configuration.

**Usage**:

sudo ./scripts/0-complete-cleanup.sh

**What It Does**:

**Confirmation Prompt**:

 ╔════════════════════════════════════════════════════════════╗  
║          ⚠️  COMPLETE CLEANUP \- DANGER ZONE                ║  
╚════════════════════════════════════════════════════════════╝

This will PERMANENTLY DELETE:  
  • All deployed containers  
  • All Docker images  
  • All data in /mnt/data  
  • All configuration files  
  • All metadata

This action CANNOT be undone\!

Type 'DELETE EVERYTHING' to confirm: 

1.   
2. **Stops all containers**

3. **Removes containers and images**

4. **Deletes `/mnt/data` directory**

5. **Unmounts EBS volume**

6. **Removes Docker networks**

7. **Optionally uninstalls Docker**

**Safety Features**:

* Requires explicit confirmation phrase  
* Creates backup before deletion (optional)  
* Asks before uninstalling Docker  
* Provides restore instructions if backup created

**Exit Codes**:

* `0`: Success  
* `1`: User canceled  
* `2`: Insufficient privileges

---

### **Script 1: Setup System**

**File**: `scripts/1-setup-system.sh`

**Purpose**: Initial system configuration and service planning

**Usage**:

sudo ./scripts/1-setup-system.sh \[options\]

**Options**:

* `--non-interactive`: Skip all prompts (use defaults)  
* `--config-file <path>`: Load configuration from JSON  
* `--skip-hardware-check`: Skip hardware detection  
* `--help`: Show help message

**Interactive Flow**:

1. **Banner Display**

2. **Hardware Detection**:

   * GPU detection (NVIDIA only currently)  
   * EBS volume discovery  
   * CPU/RAM detection  
   * Network interfaces  
3. **EBS Configuration**:

   * Format and mount options  
   * Filesystem selection (ext4 recommended)  
   * Mount point: `/mnt/data`  
4. **Docker Installation**:

   * Detect existing installation  
   * Install Docker Engine if missing  
   * Install Docker Compose v2  
   * Install NVIDIA Container Toolkit (if GPU present)  
   * Configure user permissions  
5. **Ollama Installation** (optional):

   * Install from official script  
   * Configure GPU support  
   * Select initial models to download  
6. **Tailscale Installation** (optional):

   * Install from official repository  
   * Guide user through authentication  
   * Detect Tailscale IP  
7. **Service Selection**:

   * Multi-select menu  
   * Dependency validation  
   * Resource requirement warnings  
8. **Vector DB Selection** (if AnythingLLM/Dify selected)

9. **LLM Provider Configuration**:

   * Local: Ollama (if installed)  
   * API: OpenAI, Anthropic, Google, Groq, etc.  
   * API key input and validation  
10. **LiteLLM Routing Configuration**:

    * Strategy selection  
    * Fallback chain definition  
    * Cost/latency preferences  
    * Caching options  
11. **Signal API Configuration** (if selected):

    * Phone number input  
    * Pairing mode selection  
12. **Google Drive Configuration** (if selected):

    * OAuth credentials input  
    * Sync preferences  
13. **Network Configuration**:

    * Reverse proxy selection  
    * Domain configuration (optional)  
    * Tailscale vs local access  
14. **Save Configuration**:

    * Metadata files created in `/mnt/data/metadata/`  
    * Summary display

**Output Files**:

* `/mnt/data/metadata/system_info.json`  
* `/mnt/data/metadata/selected_services.json`  
* `/mnt/data/metadata/network_config.json`  
* `/mnt/data/metadata/vectordb_config.json`  
* `/mnt/data/metadata/llm_providers.json`  
* `/mnt/data/metadata/litellm_routing.json`  
* `/mnt/data/metadata/signal_config.json`  
* `/mnt/data/metadata/gdrive_config.json`

**Re-runnable**: ✅ Yes \- Can be run multiple times to reconfigure

**Exit Codes**:

* `0`: Success  
* `1`: User canceled  
* `2`: Insufficient privileges  
* `3`: Hardware requirements not met  
* `4`: Dependency installation failed

---

### **Script 2: Deploy Services**

**File**: `scripts/2-deploy-services.sh`

**Purpose**: Generate configurations and deploy all selected services

**Usage**:

sudo ./scripts/2-deploy-services.sh \[options\]

**Options**:

* `--skip-health-checks`: Don't wait for health checks  
* `--parallel`: Deploy services in parallel (faster but less readable output)  
* `--service <name>`: Deploy only specific service  
* `--help`: Show help message

**Deployment Order** (optimized for dependencies):

1. **Infrastructure**:

   * PostgreSQL  
   * Redis  
   * Vector Database (Qdrant/Milvus/ChromaDB/Weaviate)  
2. **LLM Core**:

   * Ollama (with model downloads)  
   * LiteLLM  
3. **AI Applications**:

   * Open WebUI  
   * AnythingLLM  
   * Dify (api, worker, web)  
   * n8n  
   * Flowise  
   * ComfyUI  
4. **Communication**:

   * Signal API (with QR pairing)  
   * OpenClaw UI  
   * Google Drive Sync  
5. **Networking**:

   * Reverse Proxy (SWAG or Nginx Proxy Manager)  
6. **Monitoring** (if selected):

   * Prometheus  
   * Grafana

**Key Functions**:

#### **`generate_compose_file()`**

Creates Docker Compose file for each service with:

* Volume mounts  
* Environment variables  
* Network configuration  
* Health checks  
* Restart policies  
* GPU support (if applicable)

#### **`generate_env_file()`**

Creates environment file with:

* Auto-generated credentials  
* Service URLs  
* API keys  
* Feature flags

#### **`deploy_service()`**

Deploys a single service:

1. Generate compose \+ env files  
2. Pull images  
3. Start containers  
4. Wait for health check  
5. Run post-deploy configuration

#### **`configure_litellm()`**

Generates `litellm_config.yaml` with:

* Model list from all configured providers  
* Routing strategy  
* Fallback chains  
* Caching configuration  
* Budget/rate limits  
* Prometheus integration

#### **`pair_signal()`**

Initiates Signal pairing:

1. Start Signal API container  
2. Display QR code  
3. Wait for device pairing  
4. Save device credentials  
5. Test message sending

#### **`authorize_gdrive()`**

Completes Google Drive OAuth:

1. Start rclone config  
2. Open browser for authorization  
3. Save refresh token  
4. Test connection  
5. Start initial sync

**Output Files**:

* `/mnt/data/compose/*.yml` \- Docker Compose files  
* `/mnt/data/env/*.env` \- Environment files  
* `/mnt/data/config/litellm_config.yaml`  
* `/mnt/data/config/rclone/rclone.conf`  
* `/mnt/data/metadata/deployment_info.json`  
* `/mnt/data/metadata/credentials.json` (encrypted)

**Re-runnable**: ⚠️ Partial

* Safe to rerun, but will stop existing containers  
* Use `--service <name>` to redeploy specific service  
* Data volumes are preserved

**Exit Codes**:

* `0`: Success (all services deployed)  
* `1`: Partial success (some services failed)  
* `2`: Insufficient privileges  
* `3`: Configuration not found (run Script 1 first)  
* `4`: Deployment failed (critical service)

---

### **Script 3: Configure Services**

**File**: `scripts/3-configure-services.sh`

**Purpose**: Interactive reconfiguration of deployed services

**Usage**:

sudo ./scripts/3-configure-services.sh

**Main Menu Options**:

#### **1\) Manage LLM Providers**

╔════════════════════════════════════════════════════════════╗  
║          🤖 MANAGE LLM PROVIDERS                           ║  
╚════════════════════════════════════════════════════════════╝

Current Providers:  
  ✅ ollama (Ollama \- Local)  
     Models: llama3.2, mistral, codellama  
     Status: Healthy  
       
  ✅ openai (OpenAI \- API)  
     Models: gpt-4, gpt-3.5-turbo  
     Status: Healthy  
     Last used: 2 minutes ago

Options:  
  1\) Add New Provider  
  2\) Remove Provider  
  3\) Update API Key  
  4\) Test Provider Connection  
  5\) Manage Model Aliases  
  6\) View Usage Stats  
  0\) Back to Main Menu

Select \[0-6\]: 1

Available Providers:  
  1\) Anthropic (Claude models)  
  2\) Google (Gemini models)  
  3\) Groq (Fast Llama inference)  
  4\) Mistral AI  
  5\) Cohere  
  6\) Together AI  
  7\) Hugging Face  
  8\) Custom OpenAI-compatible endpoint

Select provider \[1-8\]: 1

Enter Anthropic API key (sk-ant-...): \*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*

Testing connection...  
✅ Connected to Anthropic API  
✅ Available models:  
   • claude-3-opus-20240229  
   • claude-3-sonnet-20240229  
   • claude-3-haiku-20240307

Add to LiteLLM config? (yes/no): yes

Updating LiteLLM configuration...  
✅ Provider added to litellm\_config.yaml  
✅ LiteLLM reloaded (hot-reload, no downtime)

New provider available\! Test it:  
  curl \-X POST http://localhost:4000/v1/chat/completions \\  
    \-H "Authorization: Bearer $LITELLM\_KEY" \\  
    \-d '{"model":"claude-3-opus","messages":\[...\]}'

#### **2\) Reconfigure LiteLLM Routing**

╔════════════════════════════════════════════════════════════╗  
║          🔄 RECONFIGURE LITELLM ROUTING                    ║  
╚════════════════════════════════════════════════════════════╝

Current Strategy: cost-based-routing

Available Strategies:  
  1\) simple-shuffle  
     Random selection from available models  
       
  2\) cost-based-routing (CURRENT)  
     Optimize for cost (cheapest first)  
       
  3\) latency-based-routing  
     Optimize for speed (fastest first)  
       
  4\) usage-based-routing  
     Load balance across all models  
       
  5\) custom  
     Define your own routing logic

Select new strategy \[1-5\]: 3

Latency-based routing configuration:

Primary models (fastest):  
  • llama3.2 (Ollama) \- avg latency: 45ms  
  • gpt-3.5-turbo (OpenAI) \- avg latency: 320ms  
  • claude-3-haiku (Anthropic) \- avg latency: 280ms

Fallback models:  
  • gpt-4 (OpenAI) \- avg latency: 980ms  
  • claude-3-opus (Anthropic) \- avg latency: 1200ms

Enable automatic latency tracking? (yes/no): yes

Latency tracking settings:  
  • Sample rate: Every request  
  • Window size: Last 100 requests  
  • Re-evaluation: Every 5 minutes

Apply changes? (yes/no): yes

✅ Routing strategy updated  
✅ LiteLLM configuration reloaded  
✅ New strategy active

Test the new routing:  
  \# Fast query (will use llama3.2)  
  curl \-X POST http://localhost:4000/v1/chat/completions \\  
    \-H "Authorization: Bearer $LITELLM\_KEY" \\  
    \-d '{"model":"auto","messages":\[{"role":"user","content":"Hi"}\]}'

#### **4\) Configure Signal API**

╔════════════════════════════════════════════════════════════╗  
║          📱 CONFIGURE SIGNAL API                           ║  
╚════════════════════════════════════════════════════════════╝

Current Status:  
  ✅ Paired  
  📱 Phone: \+15551234567  
  🔗 Webhook: http://signal-api:8090/v2/receive  
  📊 Messages sent today: 47  
  📊 Messages received today: 12

Options:  
  1\) Pair New Device  
  2\) Test Message Sending  
  3\) Test Message Receiving (webhook)  
  4\) View Message History  
  5\) Update Phone Number  
  6\) Reset Pairing  
  0\) Back to Main Menu

Select \[0-6\]: 2

Test message sending:

Recipient number (with country code): \+15559876543

Message to send: Hello from AI Platform\! This is a test message.

Sending message...  
✅ Message sent successfully  
📱 Message ID: abc-123-def-456  
⏰ Delivered at: 2024-01-15 14:23:45 UTC

Send another test message? (yes/no): no

#### **6\) Configure Webhooks**

╔════════════════════════════════════════════════════════════╗  
║          🔗 CONFIGURE WEBHOOKS                             ║  
╚════════════════════════════════════════════════════════════╝

Webhook Integrations:

1\) OpenClaw → Signal  
   Status: ✅ Configured  
   URL: http://signal-api:8090/v2/send  
   Last triggered: 5 minutes ago

2\) AnythingLLM → Signal  
   Status: ⚠️  Not configured  
   Configure now? (yes/no): yes  
     
   \[Instructions displayed for manual configuration in AnythingLLM UI\]

3\) Dify → Signal  
   Status: ⚠️  Not configured

4\) n8n → LiteLLM  
   Status: ✅ Configured  
   URL: http://litellm:4000/v1/chat/completions  
     
5\) Custom Webhook  
   Test any webhook endpoint  
     
Select \[1-5\] or 0 to go back: 5

Custom Webhook Testing:

Enter webhook URL: http://myservice:8080/webhook

Request method:  
  1\) POST  
  2\) GET  
  3\) PUT  
    
Select \[1-3\]: 1

Request body (JSON):  
{  
  "message": "test from AI platform",  
  "timestamp": "2024-01-15T14:25:00Z"  
}

Headers (optional, one per line, format: Key: Value):  
Content-Type: application/json  
Authorization: Bearer abc123

Send test request? (yes/no): yes

Sending...  
✅ Request sent  
📊 Response status: 200 OK  
📄 Response body:  
{  
  "status": "received",  
  "id": "test-123"  
}

#### **8\) Test Service Connections**

╔════════════════════════════════════════════════════════════╗  
║          🔍 TEST SERVICE CONNECTIONS                       ║  
╚════════════════════════════════════════════════════════════╝

Running comprehensive health checks...

Infrastructure:  
  ✅ PostgreSQL     | 5432  | Healthy | 12 connections | Latency: 2ms  
  ✅ Redis          | 6379  | Healthy | Cache hit: 87% | Latency: 1ms  
  ✅ Qdrant         | 6333  | Healthy | Collections: 3 | Vectors: 1.2M

LLM Layer:  
  ✅ Ollama         | 11434 | Healthy | Models: 3      | GPU: 45% util  
  ✅ LiteLLM        | 4000  | Healthy | Providers: 3   | Cache: 92% hit

AI Applications:  
  ✅ Open WebUI     | 8080  | Healthy | Users: 5       | Uptime: 3d 4h  
  ✅ AnythingLLM    | 3001  | Healthy | Workspaces: 2  | Docs: 145  
  ✅ n8n            | 5678  | Healthy | Workflows: 8   | Active: 3

Communication:  
  ✅ Signal API     | 8090  | Healthy | Paired: Yes    | Queue: 0  
  ✅ OpenClaw UI    | 3000  | Healthy | Channels: 4    | Messages: 47

Networking:  
  ✅ Nginx PM       | 81    | Healthy | Proxies: 6     | SSL: 3 certs

Integration Tests:  
  ⏳ Testing LiteLLM → Ollama...           ✅ OK (38ms)  
  ⏳ Testing LiteLLM → OpenAI...           ✅ OK (287ms)  
  ⏳ Testing AnythingLLM → Qdrant...       ✅ OK (12ms)  
  ⏳ Testing n8n → LiteLLM...              ✅ OK (156ms)  
  ⏳ Testing OpenClaw → Signal...          ✅ OK (98ms)

Overall Status: ✅ ALL SYSTEMS OPERATIONAL

Press Enter to continue...

#### **11\) Rotate Credentials**

╔════════════════════════════════════════════════════════════╗  
║          🔐 ROTATE CREDENTIALS                             ║  
╚════════════════════════════════════════════════════════════╝

⚠️  This will generate new credentials and restart services.

Select credentials to rotate:

  ☐ 1\) PostgreSQL password  
  ☐ 2\) Redis password  
  ☐ 3\) Qdrant API key  
  ☐ 4\) LiteLLM master key  
  ☐ 5\) All of the above

\[Space\] Toggle  \[Enter\] Confirm  \[Q\] Cancel

Selections: 4, 5

Confirm rotation? This will cause brief  
Confirm rotation? This will cause brief downtime (yes/no): yes

Rotating credentials...

  \[1/4\] Generating new PostgreSQL password...    ✅  
  \[2/4\] Generating new Redis password...         ✅  
  \[3/4\] Generating new Qdrant API key...         ✅  
  \[4/4\] Generating new LiteLLM master key...     ✅

Updating configuration files...  
  ✅ Updated /mnt/data/env/postgres.env  
  ✅ Updated /mnt/data/env/redis.env  
  ✅ Updated /mnt/data/env/qdrant.env  
  ✅ Updated /mnt/data/env/litellm.env  
  ✅ Updated /mnt/data/config/litellm\_config.yaml

Restarting affected services...  
  ⏳ Stopping postgres...              ✅  
  ⏳ Stopping redis...                 ✅  
  ⏳ Stopping qdrant...                ✅  
  ⏳ Stopping litellm...               ✅  
  ⏳ Starting postgres...              ✅  
  ⏳ Starting redis...                 ✅  
  ⏳ Starting qdrant...                ✅  
  ⏳ Starting litellm...               ✅

Updating dependent services...  
  ⏳ Restarting anythingllm...         ✅  
  ⏳ Restarting dify-api...            ✅  
  ⏳ Restarting n8n...                 ✅  
  ⏳ Restarting openwebui...           ✅

Running health checks...  
  ✅ All services healthy

Backing up old credentials...  
  ✅ Saved to /mnt/data/metadata/credentials\_backup\_20240115\_142730.json

🔐 New LiteLLM Master Key:  
   sk-1234567890abcdef1234567890abcdef

⚠️  IMPORTANT: Update this key in all client applications\!

Services that need manual key update:  
  • Open WebUI: Settings → LiteLLM API Key  
  • AnythingLLM: Settings → LLM Provider → API Key  
  • n8n workflows using LiteLLM  
  • Any custom scripts or applications

Updated credentials saved to:  
  /mnt/data/metadata/credentials.json

Press Enter to continue...

#### **12\) Backup Configuration**

╔════════════════════════════════════════════════════════════╗  
║          💾 BACKUP CONFIGURATION                           ║  
╚════════════════════════════════════════════════════════════╝

Backup Options:

  1\) Full Backup (configurations \+ metadata)  
     \~2 MB | Includes all service configs, credentials, metadata  
       
  2\) Data Backup (configurations \+ databases)  
     \~500 MB | Includes PostgreSQL, Redis, Vector DB data  
       
  3\) Complete Backup (everything)  
     \~2 GB | Includes configs, data, and Docker images  
       
  4\) Restore from Backup

Select \[1-4\]: 1

Full Configuration Backup:

Backup location: /mnt/data/backups/

Creating backup...  
  ⏳ Collecting metadata files...              ✅ (15 files)  
  ⏳ Collecting compose files...               ✅ (11 files)  
  ⏳ Collecting env files...                   ✅ (11 files)  
  ⏳ Collecting config files...                ✅ (8 files)  
  ⏳ Exporting credentials (encrypted)...      ✅  
  ⏳ Generating backup manifest...             ✅  
  ⏳ Creating tarball...                       ✅

Backup created successfully\!

📦 Backup Details:  
   File: /mnt/data/backups/aiplatform\_config\_20240115\_142800.tar.gz  
   Size: 1.8 MB  
   Checksum: sha256:abc123def456...  
     
✅ Backup manifest:  
   • System info  
   • Selected services  
   • Network configuration  
   • LLM providers (3)  
   • Vector DB config  
   • Signal config  
   • Google Drive config  
   • All environment files  
   • All compose files  
   • LiteLLM routing config  
   • Credentials (encrypted with server key)

📝 To restore this backup:  
   sudo ./scripts/3-configure-services.sh  
   → Select "12) Backup Configuration"  
   → Select "4) Restore from Backup"  
   → Provide backup file path

Press Enter to continue...

**Key Features**:

* Hot-reload (most changes don't require service restart)  
* Validation before applying changes  
* Automatic backups before destructive operations  
* Rollback capability  
* Real-time health monitoring

**Re-runnable**: ✅ Yes \- Designed for repeated use

**Exit Codes**:

* `0`: Success  
* `1`: User canceled  
* `2`: Insufficient privileges  
* `3`: Services not deployed (run Script 2 first)

---

### **Script 4: Add Service**

**File**: `scripts/4-add-service.sh`

**Purpose**: Add additional services after initial deployment

**Usage**:

sudo ./scripts/4-add-service.sh \[--service \<name\>\]

**Service Catalog**:

╔════════════════════════════════════════════════════════════╗  
║          ➕ ADD SERVICE TO EXISTING DEPLOYMENT             ║  
╚════════════════════════════════════════════════════════════╝

Currently Deployed Services:  
  ✅ PostgreSQL  
  ✅ Redis  
  ✅ Qdrant  
  ✅ Ollama  
  ✅ LiteLLM  
  ✅ Open WebUI  
  ✅ AnythingLLM  
  ✅ n8n  
  ✅ Signal API  
  ✅ OpenClaw UI  
  ✅ Nginx Proxy Manager

Available Services to Add:

╔════════════════════════════════════════════════════════════╗  
║  🎨 AI APPLICATIONS                                        ║  
╚════════════════════════════════════════════════════════════╝

  1\) Dify  
     📝 Description: LLM application development platform  
        Build LLM apps with visual workflow editor  
          
     🔧 Dependencies:   
        ✅ PostgreSQL (already deployed)  
        ✅ Redis (already deployed)  
        ✅ Vector DB (already deployed)  
          
     🌐 Ports: 3002 (web), 5001 (api), 5002 (worker)  
     💾 Storage: \~2 GB  
     🎯 Use Case: RAG apps, chatbots, AI workflow automation  
     📚 Docs: https://docs.dify.ai

  2\) Flowise  
     📝 Description: Drag-and-drop LangChain builder  
        Visual tool for creating LangChain flows  
          
     🔧 Dependencies:  
        ✅ PostgreSQL (already deployed)  
          
     🌐 Port: 3003  
     💾 Storage: \~500 MB  
     🎯 Use Case: Prototyping AI workflows, LangChain experimentation  
     📚 Docs: https://docs.flowiseai.com

  3\) ComfyUI  
     📝 Description: Advanced Stable Diffusion workflow designer  
        Node-based interface for image generation  
          
     🔧 Dependencies: None  
     ⚠️  Requires: GPU with 8GB+ VRAM (or very slow on CPU)  
          
     🌐 Port: 8188  
     💾 Storage: \~15 GB (base models)  
     🎯 Use Case: Advanced image generation, custom workflows  
     📚 Docs: https://github.com/comfyanonymous/ComfyUI

╔════════════════════════════════════════════════════════════╗  
║  🔄 WORKFLOW TOOLS                                         ║  
╚════════════════════════════════════════════════════════════╝

  4\) Flowise (see above)

╔════════════════════════════════════════════════════════════╗  
║  🗄️  VECTOR DATABASES                                      ║  
╚════════════════════════════════════════════════════════════╝

  5\) Add Secondary Vector DB  
     📝 Description: Add another vector database for comparison  
        Current: Qdrant  
        Options: Milvus, ChromaDB, Weaviate  
          
     🔧 Dependencies: None  
     🌐 Port: Varies by DB  
     💾 Storage: \~1 GB  
     🎯 Use Case: A/B testing, migration, multi-tenant

╔════════════════════════════════════════════════════════════╗  
║  📊 MONITORING & OBSERVABILITY                             ║  
╚════════════════════════════════════════════════════════════╝

  6\) Prometheus \+ Grafana  
     📝 Description: Metrics collection and visualization  
        Monitor all services with dashboards  
          
     🔧 Dependencies: None  
          
     🌐 Ports: 9090 (Prometheus), 3005 (Grafana)  
     💾 Storage: \~5 GB (metrics retention: 30 days)  
     🎯 Use Case: Performance monitoring, alerting, capacity planning  
     📚 Docs: https://prometheus.io, https://grafana.com

  7\) Grafana Loki  
     📝 Description: Log aggregation system  
        Centralized logging from all containers  
          
     🔧 Dependencies:  
        ⚠️  Prometheus (not deployed \- add with option 6\)  
          
     🌐 Port: 3100  
     💾 Storage: \~10 GB (log retention: 7 days)  
     🎯 Use Case: Debugging, audit trails, log analysis

╔════════════════════════════════════════════════════════════╗  
║  🌐 REVERSE PROXY                                          ║  
╚════════════════════════════════════════════════════════════╝

  8\) Switch Reverse Proxy  
     📝 Current: Nginx Proxy Manager  
        Switch to: SWAG (Secure Web Application Gateway)  
          
     ⚠️  This will reconfigure all proxy routes  
     🌐 Port: 80, 443, 81 (admin)

  0\) Back to Main Menu

Select service to add \[0-8\]: 1

**Deployment Flow for Selected Service**:

╔════════════════════════════════════════════════════════════╗  
║          🎨 ADDING DIFY                                    ║  
╚════════════════════════════════════════════════════════════╝

Pre-deployment Checks:  
  ✅ Checking dependencies...  
     ✅ PostgreSQL: Running (port 5432\)  
     ✅ Redis: Running (port 6379\)  
     ✅ Qdrant: Running (port 6333\)  
       
  ✅ Checking port availability...  
     ✅ Port 3002: Available  
     ✅ Port 5001: Available  
     ✅ Port 5002: Available  
       
  ✅ Checking disk space...  
     ✅ Available: 450 GB (required: 2 GB)  
       
  ✅ Checking network connectivity...  
     ✅ Can reach Docker Hub  
     ✅ Can reach package repositories

All checks passed\! Proceeding with deployment...

Generating Configuration Files:  
  ⏳ Creating dify-api.yml...                 ✅  
  ⏳ Creating dify-worker.yml...              ✅  
  ⏳ Creating dify-web.yml...                 ✅  
  ⏳ Creating dify.env...                     ✅  
     • Generated SECRET\_KEY  
     • Set POSTGRES\_HOST=postgres:5432  
     • Set REDIS\_HOST=redis:6379  
     • Set QDRANT\_HOST=qdrant:6333  
     • Set LITELLM\_API\_BASE=http://litellm:4000

Pulling Docker Images:  
  ⏳ Pulling langgenius/dify-api:latest...    \[=====\>    \] 45%

*(Progress bars and animations for image pulls)*

Pulling Docker Images:  
  ✅ Pulled langgenius/dify-api:latest        (1.2 GB)  
  ✅ Pulled langgenius/dify-worker:latest     (1.1 GB)  
  ✅ Pulled langgenius/dify-web:latest        (156 MB)

Starting Services:  
  \[1/3\] Starting dify-api...  
        Container: dify-api  
        Status: Created → Running  
        Health check: ████████░░ 80% (waiting for /health)  
        ✅ Healthy (took 12s)  
          
  \[2/3\] Starting dify-worker...  
        Container: dify-worker  
        Status: Created → Running  
        ✅ Started (no health check)  
          
  \[3/3\] Starting dify-web...  
        Container: dify-web  
        Status: Created → Running  
        Health check: ██████████ 100%  
        ✅ Healthy (took 5s)

Running Post-Deployment Configuration:  
  ⏳ Initializing PostgreSQL schema...        ✅  
     • Created tables: 42  
     • Created indexes: 18  
     • Inserted seed data  
       
  ⏳ Connecting to Qdrant...                  ✅  
     • Created collection: dify\_embeddings  
     • Dimension: 1536  
     • Distance: Cosine  
       
  ⏳ Connecting to LiteLLM...                 ✅  
     • Endpoint: http://litellm:4000  
     • API key configured  
     • Available models: 5  
       
  ⏳ Configuring Redis cache...               ✅  
     • Namespace: dify:  
     • TTL: 3600s

Integration Tests:  
  ⏳ Testing Dify API → PostgreSQL...         ✅ (8ms)  
  ⏳ Testing Dify API → Redis...              ✅ (2ms)  
  ⏳ Testing Dify API → Qdrant...             ✅ (15ms)  
  ⏳ Testing Dify API → LiteLLM...            ✅ (234ms)  
  ⏳ Testing Dify Web → Dify API...           ✅ (45ms)

╔════════════════════════════════════════════════════════════╗  
║          ✅ DIFY DEPLOYED SUCCESSFULLY                     ║  
╚════════════════════════════════════════════════════════════╝

Access Information:

  📍 Web Interface:  
     • Tailscale: http://100.x.x.x:3002  
     • Local: http://localhost:3002  
       
  📍 API Endpoint:  
     • URL: http://100.x.x.x:5001  
     • Docs: http://100.x.x.x:5001/api/docs  
       
  🔐 Admin Setup Required:  
     1\. Open http://100.x.x.x:3002  
     2\. Click "Create Account"  
     3\. Enter your admin email and password  
     4\. Verify email (if SMTP configured)

Configuration Details:

  📁 Files Created:  
     • /mnt/data/compose/dify-api.yml  
     • /mnt/data/compose/dify-worker.yml  
     • /mnt/data/compose/dify-web.yml  
     • /mnt/data/env/dify.env  
     • /mnt/data/metadata/dify\_info.json  
       
  🗄️  Database:  
     • PostgreSQL database: dify  
     • Tables: 42  
     • Migrations: Up to date  
       
  🔗 Integrations:  
     • Vector DB: Qdrant (collection: dify\_embeddings)  
     • LLM Provider: LiteLLM (5 models available)  
     • Cache: Redis (namespace: dify:)  
       
  💾 Storage:  
     • Data directory: /mnt/data/dify  
     • Uploads: /mnt/data/dify/uploads  
     • Logs: /mnt/data/dify/logs

Next Steps:

  1️⃣  Complete Admin Setup:  
     • Access http://100.x.x.x:3002  
     • Create your admin account  
       
  2️⃣  Configure LLM Provider (already pre-configured):  
     • Provider: LiteLLM  
     • Endpoint: http://litellm:4000  
     • Models: Available from LiteLLM routing  
       
  3️⃣  Create Your First App:  
     • Click "Create App"  
     • Choose template (Chat, Agent, Workflow)  
     • Configure prompts and tools  
       
  4️⃣  Optional: Configure in Reverse Proxy:  
     • Add proxy host in Nginx PM  
     • Domain: dify.yourdomain.com → 100.x.x.x:3002  
     • Enable SSL  
       
  5️⃣  Optional: Configure Signal Notifications:  
     • Run: sudo ./scripts/3-configure-services.sh  
     • Select "6) Configure Webhooks"  
     • Configure Dify → Signal

Useful Commands:

  \# View logs  
  docker logs \-f dify-api  
  docker logs \-f dify-worker  
  docker logs \-f dify-web  
    
  \# Restart services  
  docker restart dify-api dify-worker dify-web  
    
  \# Check status  
  docker ps | grep dify  
    
  \# Access PostgreSQL  
  docker exec \-it postgres psql \-U postgres \-d dify

Documentation:

  📚 Official Docs: https://docs.dify.ai  
  📚 API Reference: http://100.x.x.x:5001/api/docs  
  📚 Local Info: /mnt/data/metadata/dify\_info.json  
  📚 GitHub: https://github.com/langgenius/dify

Updated Metadata:  
  ✅ Added to /mnt/data/metadata/selected\_services.json  
  ✅ Added to /mnt/data/metadata/deployment\_info.json

Press Enter to continue...

**Features**:

* Dependency resolution  
* Port conflict detection  
* Pre-deployment validation  
* Automatic integration with existing services  
* Post-deployment testing  
* Detailed setup instructions

**Re-runnable**: ⚠️ Partial

* Can add different services  
* Redeploying same service will stop and recreate  
* Data volumes preserved

**Exit Codes**:

* `0`: Success  
* `1`: User canceled  
* `2`: Insufficient privileges  
* `3`: Dependencies not met  
* `4`: Port conflict  
* `5`: Deployment failed

---

### **Script 5: Manage Services**

**File**: `scripts/5-manage-services.sh` (if exists, or integrated into script 3\)

**Purpose**: Day-to-day service management operations

**Usage**:

sudo ./scripts/5-manage-services.sh

**Main Menu**:

╔════════════════════════════════════════════════════════════╗  
║          ⚙️  SERVICE MANAGEMENT                            ║  
╚════════════════════════════════════════════════════════════╝

Service Status Overview:

  Infrastructure:  
    🟢 postgres           Running   (uptime: 3d 5h)  
    🟢 redis              Running   (uptime: 3d 5h)  
    🟢 qdrant             Running   (uptime: 3d 5h)  
      
  LLM Layer:  
    🟢 ollama             Running   (uptime: 3d 5h)  
    🟢 litellm            Running   (uptime: 2d 18h)  
      
  Applications:  
    🟢 openwebui          Running   (uptime: 3d 4h)  
    🟢 anythingllm        Running   (uptime: 3d 4h)  
    🟢 dify-api           Running   (uptime: 1h 23m)  
    🟢 dify-worker        Running   (uptime: 1h 23m)  
    🟢 dify-web           Running   (uptime: 1h 23m)  
    🟢 n8n                Running   (uptime: 3d 4h)  
      
  Communication:  
    🟢 signal-api         Running   (uptime: 3d 4h)  
    🟢 openclaw           Running   (uptime: 3d 4h)  
      
  Networking:  
    🟢 nginx-pm           Running   (uptime: 3d 5h)

System Resources:  
  💻 CPU: 24% (8 cores)  
  🧠 RAM: 45% (28.8 GB / 64 GB)  
  💾 Disk: 22% (110 GB / 500 GB)  
  🌐 Network: ↓ 2.3 MB/s  ↑ 450 KB/s

Options:

  1\) Start Service  
  2\) Stop Service  
  3\) Restart Service  
  4\) View Logs  
  5\) Service Details  
  6\) Resource Usage (by service)  
  7\) Update Service (pull new image)  
  8\) Scale Service  
  9\) Remove Service  
  10\) Restart All Services  
  11\) Stop All Services  
  0\) Exit

Select \[0-11\]: 4

**View Logs Submenu**:

╔════════════════════════════════════════════════════════════╗  
║          📋 VIEW SERVICE LOGS                              ║  
╚════════════════════════════════════════════════════════════╝

Select service:  
  1\) postgres  
  2\) redis  
  3\) qdrant  
  4\) ollama  
  5\) litellm  
  6\) openwebui  
  7\) anythingllm  
  8\) dify-api  
  9\) dify-worker  
  10\) dify-web  
  11\) n8n  
  12\) signal-api  
  13\) openclaw  
  14\) nginx-pm  
    
  0\) Back

Select service \[0-14\]: 8

Log options:  
  1\) Tail (live, last 50 lines)  
  2\) Last 100 lines  
  3\) Last 500 lines  
  4\) Full logs  
  5\) Search logs  
  6\) Export logs to file

Select \[1-6\]: 1

Showing live logs for dify-api (Ctrl+C to exit):  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

2024-01-15 14:30:12 INFO     uvicorn.error \- Started server process \[1\]  
2024-01-15 14:30:12 INFO     uvicorn.error \- Waiting for application startup.  
2024-01-15 14:30:13 INFO     app.initialize \- Connecting to PostgreSQL...  
2024-01-15 14:30:13 INFO     app.initialize \- PostgreSQL connected  
2024-01-15 14:30:13 INFO     app.initialize \- Connecting to Redis...  
2024-01-15 14:30:13 INFO     app.initialize \- Redis connected  
2024-01-15 14:30:13 INFO     app.initialize \- Connecting to Qdrant...  
2024-01-15 14:30:14 INFO     app.initialize \- Qdrant connected  
2024-01-15 14:30:14 INFO     uvicorn.error \- Application startup complete.  
2024-01-15 14:30:45 INFO     api.chat \- POST /v1/chat-messages  
2024-01-15 14:30:45 INFO     llm.litellm \- Calling model: gpt-3.5-turbo  
2024-01-15 14:30:46 INFO     llm.litellm \- Response received (tokens: 45\)  
2024-01-15 14:31:02 INFO     api.documents \- POST /v1/documents/upload  
2024-01-15 14:31:02 INFO     vectordb.qdrant \- Indexing document chunks (12 chunks)  
2024-01-15 14:31:03 INFO     vectordb.qdrant \- Indexed successfully  
...

\[Following logs in real-time \- Press Ctrl+C to stop\]

**Resource Usage Submenu**:

╔════════════════════════════════════════════════════════════╗  
║          📊 RESOURCE USAGE BY SERVICE                      ║  
╚════════════════════════════════════════════════════════════╝

Service          CPU %    RAM (MB)   Disk R/W (MB/s)   Network (KB/s)  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  
postgres         3.2%     512        0.5 / 0.3         12 / 8  
redis            1.1%     128        0.1 / 0.1         45 / 32  
qdrant           8.4%     2048       2.3 / 1.1         123 / 89  
ollama           15.2%    4096       0.0 / 0.0         234 / 156  
litellm          5.3%     256        0.0 / 0.0         89 / 67  
openwebui        2.1%     512        0.2 / 0.1         34 / 28  
anythingllm      4.5%     1024       0.8 / 0.4         67 / 45  
dify-api         3.2%     768        0.3 / 0.2         45 / 34  
dify-worker      1.8%     512        0.1 / 0.1         12 / 8  
dify-web         0.9%     256        0.0 / 0.0         23 / 18  
n8n              2.3%     512        0.2 / 0.1         28 / 23  
signal-api       1.5%     256        0.0 / 0.0         18 / 12  
openclaw         1.2%     384        0.0 / 0.0         15 / 10  
nginx-pm         0.8%     128        0.0 / 0.0         34 / 28  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  
TOTAL            51.5%    11392      4.5 / 2.5         779 / 558

GPU Usage (NVIDIA RTX 4090):  
  📊 Utilization: 45%  
  🧠 Memory: 8.2 GB / 24 GB (34%)  
  🌡️  Temperature: 62°C  
    
  Primary Consumer: ollama (llama3.2 model loaded)

Top 5 by CPU:  
  1\. ollama      (15.2%)  
  2\. qdrant      (8.4%)  
  3\. litellm     (5.3%)  
  4\. anythingllm (4.5%)  
  5\. dify-api    (3.2%)

Top 5 by RAM:  
  1\. ollama      (4096 MB)  
  2\. qdrant      (2048 MB)  
  3\. anythingllm (1024 MB)  
  4\. dify-api    (768 MB)  
  5\. openwebui   (512 MB)

Options:  
  1\) Refresh (live monitoring)  
  2\) Export to CSV  
  3\) View historical data (Prometheus)  
  4\) Back to main menu

Select \[1-4\]: 

**Update Service Submenu**:

╔════════════════════════════════════════════════════════════╗  
║          🔄 UPDATE SERVICE                                 ║  
╚════════════════════════════════════════════════════════════╝

Select service to update:  
  1\) openwebui (current: v0.1.124, available: v0.1.125)  🆕  
  2\) anythingllm (current: latest, available: latest)  
  3\) dify-api (current: 0.5.2, available: 0.5.3)  🆕  
  4\) n8n (current: 1.20.0, available: 1.21.0)  🆕  
  5\) All services with updates available  
    
  0\) Back

Select \[0-5\]: 1

Updating openwebui...

Current version: v0.1.124  
New version: v0.1.125

Changelog:  
  • Fixed authentication bug  
  • Added support for function calling  
  • Improved mobile UI  
  • Performance improvements

Backup current container? (yes/no): yes

Creating backup...  
  ✅ Container state saved to /mnt/data/backups/openwebui\_20240115\_143000.tar

Pulling new image...  
  ⏳ Pulling ghcr.io/open-webui/open-webui:v0.1.125...  
     \[████████████████████\] 100% (234 MB)  
  ✅ Image pulled

Stopping current container...  
  ✅ openwebui stopped

Starting new container...  
  ✅ openwebui started  
  ✅ Health check passed

Running post-update migrations...  
  ✅ Database schema updated  
  ✅ Static files regenerated

Testing...  
  ✅ HTTP endpoint responsive  
  ✅ Authentication working  
  ✅ LiteLLM connection OK

╔════════════════════════════════════════════════════════════╗  
║          ✅ UPDATE COMPLETED                               ║  
╚════════════════════════════════════════════════════════════╝

Open WebUI updated: v0.1.124 → v0.1.125

Access: http://100.x.x.x:8080

Rollback available (if issues):  
  docker stop openwebui  
  docker load \< /mnt/data/backups/openwebui\_20240115\_143000.tar  
  docker start openwebui

Press Enter to continue...

---

## **Service Stack**

### **Core Infrastructure**

#### **PostgreSQL**

* **Purpose**: Relational database for Dify, n8n, Flowise  
* **Version**: 16-alpine  
* **Port**: 5432 (internal only)  
* **Storage**: `/mnt/data/postgres`  
* **Credentials**: Auto-generated, stored in `/mnt/data/metadata/credentials.json`  
* **Backups**: Daily automatic backups to `/mnt/data/backups/postgres/`

**Access**:  
 docker exec \-it postgres psql \-U postgres

* 

#### **Redis**

* **Purpose**: Cache, session store, message queue  
* **Version**: 7-alpine  
* **Port**: 6379 (internal only)  
* **Storage**: `/mnt/data/redis`  
* **Use Cases**:  
  * LiteLLM response caching  
  * Dify session management  
  * n8n queue management

**Access**:  
docker exec \-it redis redis-cli  
AUTH \<password\>

* 

---

### **Vector Databases**

#### **Qdrant (Recommended)**

* **Purpose**: Vector similarity search for RAG  
* **Version**: latest  
* **Ports**:  
  * 6333 (HTTP API)  
  * 6334 (gRPC)  
* **Storage**: `/mnt/data/qdrant`  
* **Dashboard**: [http://100.x.x.x:6333/dashboard](http://100.x.x.x:6333/dashboard)  
* **Features**:  
  * Full-text search  
  * Filtering  
  * Multi-vector support  
  * Quantization for efficiency  
* **Usage**:  
  * AnythingLLM document embeddings  
  * Dify knowledge base  
  * Custom RAG applications

#### **Alternative: Milvus**

* **Purpose**: High-performance vector DB  
* **Ports**: 19530 (gRPC), 9091 (HTTP)  
* **Best For**: Large-scale deployments (\>10M vectors)

#### **Alternative: ChromaDB**

* **Purpose**: Simple vector DB  
* **Port**: 8000  
* **Best For**: Development, small datasets

#### **Alternative: Weaviate**

* **Purpose**: Semantic search engine  
* **Port**: 8080  
* **Best For**: Complex queries, hybrid search

---

### **LLM Layer**

#### **Ollama**

* **Purpose**: Run LLMs locally  
* **Version**: latest  
* **Port**: 11434  
* **Storage**: `/mnt/data/ollama`  
* **GPU**: Automatically detected and configured  
* **Pre-installed Models**:  
  * `llama3.2:latest` (7B)  
  * `mistral:latest` (7B)  
  * `codellama:latest` (7B)

**Management**:  
\# List models  
docker exec ollama ollama list

\# Pull new model  
docker exec ollama ollama pull llama3.2:70b

\# Remove model  
docker exec ollama ollama rm mistral

* 

#### **LiteLLM**

* **Purpose**: Universal LLM proxy with routing  
* **Version**: main-latest  
* **Ports**:  
  * 4000 (API)  
  * 18789 (Admin UI, Tailscale only)  
* **Configuration**: `/mnt/data/config/litellm_config.yaml`  
* **Features**:  
  * OpenAI-compatible API  
  * 100+ provider support  
  * Cost tracking  
  * Response caching (Redis)  
  * Fallback chains  
  * Load balancing  
  * Budget caps  
  * Prometheus metrics  
* **Admin UI**: [http://100.x.x.x:18789](http://100.x.x.x:18789)  
  * Model analytics  
  * Cost dashboard  
  * Request logs  
  * Provider health

**API Usage**:  
curl \-X POST http://localhost:4000/v1/chat/completions \\  
  \-H "Authorization: Bearer $LITELLM\_MASTER\_KEY" \\  
  \-H "Content-Type: application/json" \\  
  \-d '{  
    "model": "gpt-3.5-turbo",  
    "messages": \[{"role": "user", "content": "Hello\!"}\]  
  }'

* 

---

### **AI Applications**

#### **Open WebUI**

* **Purpose**: ChatGPT-like interface for local/API LLMs  
* **Version**: main  
* **Port**: 8080  
* **Storage**: `/mnt/data/openwebui`  
* **Features**:  
  1. Multi-user support  
  2. Model switching  
  3. Conversation history  
  4. Document uploads (RAG)  
  5. Admin panel  
  6. Dark/light themes  
  7. Mobile-responsive  
* **Integration**: Pre-configured with LiteLLM  
* **First-Time Setup**:  
  1. Open [http://100.x.x.x:8080](http://100.x.x.x:8080)  
  2. Create admin account (first user \= admin)  
  3. Start chatting\!

#### **AnythingLLM**

* **Purpose**: Document-based AI chat with RAG  
* **Version**: latest  
* **Port**: 3001  
* **Storage**: `/mnt/data/anythingllm`  
* **Features**:  
  1. Multi-workspace support  
  2. Document upload (PDF, DOCX, TXT, MD, CSV)  
  3. Web scraping  
  4. YouTube transcript import  
  5. Citation tracking  
  6. Custom embeddings  
  7. Agent mode  
* **Integration**:  
  1. LLM Provider: LiteLLM (pre-configured)  
  2. Vector DB: Qdrant (pre-configured)  
  3. Embedding Model: text-embedding-ada-002 (via LiteLLM)  
* **First-Time Setup**:  
  1. Open [http://100.x.x.x:3001](http://100.x.x.x:3001)  
  2. Create workspace  
  3. Upload documents  
  4. Start asking questions\!

#### **Dify (Optional)**

* **Purpose**: LLM application development platform  
* **Version**: 0.5.x  
* **Ports**:  
  * 3002 (web UI)  
  * 5001 (API)  
* **Storage**: `/mnt/data/dify`  
* **Components**:  
  * `dify-api`: Backend API  
  * `dify-worker`: Background jobs  
  * `dify-web`: Frontend UI  
* **Features**:  
  * Visual workflow builder  
  * RAG pipeline designer  
  * Agent builder  
  * API endpoint generation  
  * Prompt engineering tools  
  * Multi-tenant support  
* **Use Cases**:  
  * Customer support chatbots  
  * Content generation tools  
  * Document Q\&A systems  
  * API-based LLM apps

#### **ComfyUI (Optional, GPU Recommended)**

* **Purpose**: Advanced Stable Diffusion workflow designer  
* **Version**: latest  
* **Port**: 8188  
* **Storage**: \`/mnt/data/comfy Human: continue

\- \*\*Storage\*\*: \`/mnt/data/comfyui\`  
\- \*\*Requirements\*\*:   
  \- GPU with 8GB+ VRAM (NVIDIA)  
  \- \~15 GB disk space for models  
\- \*\*Features\*\*:  
  \- Node-based workflow editor  
  \- Custom model loading  
  \- ControlNet support  
  \- Img2Img, Inpainting  
  \- Video generation  
  \- Batch processing  
\- \*\*Pre-installed Models\*\*:  
  \- Stable Diffusion 1.5  
  \- SDXL (if GPU supports)  
\- \*\*Access\*\*: http://100.x.x.x:8188

\---

\#\#\# Workflow Tools

\#\#\#\# \*\*n8n\*\*  
\- \*\*Purpose\*\*: Workflow automation and integration  
\- \*\*Version\*\*: latest  
\- \*\*Port\*\*: 5678  
\- \*\*Storage\*\*: \`/mnt/data/n8n\`  
\- \*\*Database\*\*: PostgreSQL (shared)  
\- \*\*Features\*\*:  
  \- 400+ integrations  
  \- Visual workflow editor  
  \- Webhooks  
  \- Cron scheduling  
  \- API endpoints  
  \- Error handling  
  \- Execution history  
\- \*\*Pre-configured Nodes\*\*:  
  \- HTTP Request (for LiteLLM)  
  \- PostgreSQL  
  \- Redis  
  \- Webhook triggers  
\- \*\*Example Workflows\*\*:  
  1\. \*\*Email → LLM → Summary\*\*:  
     \- Trigger: Email received  
     \- LLM: Summarize content (via LiteLLM)  
     \- Action: Send to Signal  
       
  2\. \*\*Document Processing Pipeline\*\*:  
     \- Trigger: File uploaded to Google Drive  
     \- Process: Extract text, chunk, embed  
     \- Store: Upload to Qdrant  
     \- Notify: Send confirmation via Signal  
       
  3\. \*\*AI Agent with RAG\*\*:  
     \- Trigger: Webhook  
     \- Query: Search Qdrant for relevant docs  
     \- LLM: Generate response with context  
     \- Return: JSON response  
\- \*\*Access\*\*: http://100.x.x.x:5678  
\- \*\*First-Time Setup\*\*:  
  1\. Open URL  
  2\. Create owner account  
  3\. Import starter workflows (optional)

\#\#\#\# \*\*Flowise\*\* (Optional)  
\- \*\*Purpose\*\*: Drag-and-drop LangChain builder  
\- \*\*Version\*\*: latest  
\- \*\*Port\*\*: 3003  
\- \*\*Storage\*\*: \`/mnt/data/flowise\`  
\- \*\*Database\*\*: PostgreSQL (shared)  
\- \*\*Features\*\*:  
  \- Visual LangChain flow builder  
  \- 100+ nodes (agents, chains, tools)  
  \- API endpoint generation  
  \- Chatbot embedding  
  \- Prompt templates  
  \- Memory management  
\- \*\*Use Cases\*\*:  
  \- Prototyping RAG apps  
  \- Building conversational agents  
  \- Testing LangChain components

\---

\#\#\# Communication Layer

\#\#\#\# \*\*Signal API\*\*  
\- \*\*Purpose\*\*: Send/receive Signal messages programmatically  
\- \*\*Version\*\*: bbernhard/signal-cli-rest-api:latest  
\- \*\*Port\*\*: 8090  
\- \*\*Storage\*\*: \`/mnt/data/signal\`  
\- \*\*Modes\*\*:  
  \- \*\*JSON-RPC\*\* (default): Full Signal protocol support  
  \- \*\*Native\*\*: Lighter, limited features  
\- \*\*Features\*\*:  
  \- Send text messages  
  \- Send attachments  
  \- Receive messages (webhook)  
  \- Group messaging  
  \- Contact management  
  \- Message reactions  
\- \*\*Setup Process\*\* (via Script 3):  
  1\. Register phone number  
  2\. Verify SMS code  
  3\. Set profile name  
  4\. Configure webhooks (optional)  
\- \*\*API Examples\*\*:  
  \`\`\`bash  
  \# Send message  
  curl \-X POST http://localhost:8090/v2/send \\  
    \-H "Content-Type: application/json" \\  
    \-d '{  
      "message": "Hello from AI Platform\!",  
      "number": "+1234567890",  
      "recipients": \["+0987654321"\]  
    }'  
    
  \# Send with attachment  
  curl \-X POST http://localhost:8090/v2/send \\  
    \-F 'message=Check this out' \\  
    \-F 'number=+1234567890' \\  
    \-F 'recipients=+0987654321' \\  
    \-F 'attachment=@report.pdf'

* **Webhook Configuration**:  
  * URL: [http://n8n:5678/webhook/signal-incoming](http://n8n:5678/webhook/signal-incoming)  
  * Use in n8n workflows to respond to messages

#### **OpenClaw UI**

* **Purpose**: Web-based Signal messenger interface  
* **Version**: latest (from docker-compose-signal-ui.yaml)  
* **Port**: 3000  
* **Storage**: Shared with Signal API  
* **Features**:  
  * Web UI for Signal  
  * Contact list  
  * Conversation threads  
  * Send/receive messages  
  * File attachments  
  * Multi-device support  
* **Access**: [http://100.x.x.x:3000](http://100.x.x.x:3000)  
* **Integration**: Automatically connects to Signal API container

#### **Google Drive Sync (Optional)**

* **Purpose**: Automatic Google Drive file synchronization  
* **Version**: ghcr.io/astrada/google-drive-ocamlfuse:latest  
* **Storage**: `/mnt/data/gdrive`  
* **Mount Point**: `/mnt/data/gdrive/mount` (accessible to other containers)  
* **Setup Process** (via Script 3):  
  * OAuth authentication (browser)  
  * Select folders to sync  
  * Configure sync frequency  
* **Use Cases**:  
  * Auto-sync documents to AnythingLLM/Dify  
  * Backup AI outputs to Drive  
  * Shared knowledge base  
* **Integration with n8n**:  
  * Watch folder for new files  
  * Trigger RAG indexing workflow  
  * Notify via Signal when processed

---

### **Reverse Proxy**

#### **Nginx Proxy Manager (Default)**

* **Purpose**: Easy SSL and domain routing  
* **Version**: jc21/nginx-proxy-manager:latest  
* **Ports**:  
  * 80 (HTTP, auto-redirect to HTTPS)  
  * 443 (HTTPS)  
  * 81 (Admin UI)  
* **Storage**: `/mnt/data/nginx-pm`  
* **Features**:  
  * Web-based configuration  
  * Automatic Let's Encrypt SSL  
  * Access lists (IP whitelisting)  
  * Custom SSL certificates  
  * WebSocket support  
  * HTTP/2 and HTTP/3  
* **Default Credentials**:  
  * Email: `admin@example.com`  
  * Password: `changeme`  
  * ⚠️ **MUST CHANGE** on first login  
* **Admin UI**: [http://100.x.x.x:81](http://100.x.x.x:81)

**Common Proxy Hosts**:  
Domain                    → Target  
────────────────────────────────────────────  
chat.yourdomain.com       → 100.x.x.x:8080  (Open WebUI)  
docs.yourdomain.com       → 100.x.x.x:3001  (AnythingLLM)  
dify.yourdomain.com       → 100.x.x.x:3002  (Dify)  
workflows.yourdomain.com  → 100.x.x.x:5678  (n8n)  
signal.yourdomain.com     → 100.x.x.x:3000  (OpenClaw)  
proxy.yourdomain.com      → 100.x.x.x:81    (Nginx PM Admin)

*   
* **Access List Example**:  
  * Create list: "Tailscale Only"  
  * Allow: 100.64.0.0/10  
  * Apply to admin interfaces for security

#### **SWAG (Alternative)**

* **Purpose**: Secure Web Application Gateway  
* **Version**: linuxserver/swag:latest  
* **Ports**: 80, 443, 81  
* **Features**:  
  * File-based configuration  
  * Built-in Fail2ban  
  * GeoIP blocking  
  * Pre-configured security headers  
* **Best For**: Advanced users preferring config files

---

## **Configuration**

### **Directory Structure**

/mnt/data/  
├── compose/                    \# Docker Compose files  
│   ├── postgres.yml  
│   ├── redis.yml  
│   ├── qdrant.yml  
│   ├── ollama.yml  
│   ├── litellm.yml  
│   ├── openwebui.yml  
│   ├── anythingllm.yml  
│   ├── dify-api.yml  
│   ├── dify-worker.yml  
│   ├── dify-web.yml  
│   ├── n8n.yml  
│   ├── signal-api.yml  
│   ├── openclaw.yml  
│   ├── nginx-pm.yml  
│   └── gdrive-sync.yml  
│  
├── env/                        \# Environment files  
│   ├── postgres.env  
│   ├── redis.env  
│   ├── qdrant.env  
│   ├── ollama.env  
│   ├── litellm.env  
│   ├── openwebui.env  
│   ├── anythingllm.env  
│   ├── dify.env  
│   ├── n8n.env  
│   ├── signal.env  
│   └── nginx-pm.env  
│  
├── config/                     \# Application configs  
│   ├── litellm\_config.yaml     \# LiteLLM routing  
│   ├── nginx-pm/               \# Nginx PM configs  
│   ├── n8n/                    \# n8n workflows  
│   └── signal/                 \# Signal API configs  
│  
├── metadata/                   \# Deployment metadata  
│   ├── deployment\_info.json    \# Deployment details  
│   ├── selected\_services.json  \# Installed services  
│   ├── credentials.json        \# Generated credentials  
│   ├── network\_config.json     \# Network settings  
│   ├── tailscale\_info.json     \# Tailscale details  
│   └── llm\_providers.json      \# LLM provider configs  
│  
├── backups/                    \# Backups  
│   ├── postgres/               \# Database backups  
│   │   └── daily/  
│   ├── configs/                \# Config backups  
│   └── containers/             \# Container snapshots  
│  
├── logs/                       \# Centralized logs (if Loki enabled)  
│   ├── nginx-pm/  
│   ├── litellm/  
│   └── application/  
│  
└── \[service-name\]/             \# Service-specific data  
    ├── postgres/               \# PostgreSQL data  
    ├── redis/                  \# Redis data  
    ├── qdrant/                 \# Qdrant data  
    ├── ollama/                 \# Ollama models  
    ├── openwebui/              \# Open WebUI data  
    ├── anythingllm/            \# AnythingLLM data  
    ├── dify/                   \# Dify data  
    ├── n8n/                    \# n8n data  
    ├── signal/                 \# Signal data  
    ├── comfyui/                \# ComfyUI models  
    ├── flowise/                \# Flowise data  
    ├── nginx-pm/               \# Nginx PM data  
    └── gdrive/                 \# Google Drive sync  
        └── mount/              \# Mounted Drive folder

---

### **Network Configuration**

#### **Docker Networks**

networks:  
  ai-platform-network:  
    name: ai-platform-network  
    driver: bridge  
    ipam:  
      config:  
        \- subnet: 172.28.0.0/16  
          gateway: 172.28.0.1

**All services** connect to `ai-platform-network` for inter-container communication.

**Service Discovery**:

* Services reference each other by container name  
* Example: `http://litellm:4000` (from any container)  
* No need for IP addresses

#### **Port Mapping Strategy**

**Two-Tier Access Model**:

1. **Public/Proxy Access** (Ports 80/443):

   * Traffic flows through Nginx Proxy Manager  
   * SSL termination  
   * Domain-based routing  
   * Access lists for security  
   * **Services**: Open WebUI, AnythingLLM, Dify, n8n, OpenClaw

Internet/LAN → Nginx PM (80/443) → Backend Service

2.   
3. **Tailscale Direct Access** (Custom Ports):

   * Direct access via Tailscale IP  
   * No proxy overhead  
   * Admin interfaces  
   * **Services**: LiteLLM Admin (18789), Nginx PM Admin (81), Qdrant Dashboard (6333)

Tailscale Client → 100.x.x.x:PORT → Service

4. 

#### **Network Diagram**

┌─────────────────────────────────────────────────────────────────┐  
│                      PUBLIC INTERNET                            │  
│                            ↓↓↓                                  │  
└─────────────────────────────────────────────────────────────────┘  
                              ↓  
                         \[Firewall\]  
                         Ports: 80, 443  
                              ↓  
┌─────────────────────────────────────────────────────────────────┐  
│                   NGINX PROXY MANAGER                           │  
│                    (Port 80, 443, 81\)                           │  
│  ┌──────────────────────────────────────────────────────────┐  │  
│  │  Domain Routing:                                         │  │  
│  │  • chat.domain.com      → openwebui:8080                │  │  
│  │  • docs.domain.com      → anythingllm:3001              │  │  
│  │  • dify.domain.com      → dify-web:3002                 │  │  
│  │  • workflows.domain.com → n8n:5678                      │  │  
│  │  • signal.domain.com    → openclaw:3000                 │  │  
│  └──────────────────────────────────────────────────────────┘  │  
└─────────────────────────────────────────────────────────────────┘  
          ↓           ↓           ↓           ↓           ↓  
   ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  
   │OpenWebUI │ │AnythingLLM│ │Dify Web │ │   n8n    │ │OpenClaw │  
   │  :8080   │ │  :3001   │ │  :3002  │ │  :5678   │ │  :3000   │  
   └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘  
          ↓           ↓           ↓           ↓           ↓  
   ┌──────────────────────────────────────────────────────────────┐  
   │          AI PLATFORM NETWORK (172.28.0.0/16)                │  
   │                                                              │  
   │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │  
   │  │PostgreSQL│  │  Redis   │  │  Qdrant  │  │  Ollama  │   │  
   │  │  :5432   │  │  :6379   │  │  :6333   │  │ :11434   │   │  
   │  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │  
   │                                                              │  
   │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │  
   │  │ LiteLLM  │  │Dify API  │  │Dify Wrkr │  │Signal API│   │  
   │  │  :4000   │  │  :5001   │  │  :5002   │  │  :8090   │   │  
   │  │ :18789   │  └──────────┘  └──────────┘  └──────────┘   │  
   │  └──────────┘                                               │  
   └──────────────────────────────────────────────────────────────┘  
                              ↑  
                              │  
┌─────────────────────────────────────────────────────────────────┐  
│                      TAILSCALE NETWORK                          │  
│                    (100.x.x.x/32 per device)                    │  
│                                                                 │  
│  Direct Access (no proxy):                                      │  
│  • 100.x.x.x:18789  → LiteLLM Admin UI                         │  
│  • 100.x.x.x:81     → Nginx PM Admin                           │  
│  • 100.x.x.x:6333   → Qdrant Dashboard                         │  
│  • 100.x.x.x:8080   → Open WebUI (direct)                      │  
│  • 100.x.x.x:3001   → AnythingLLM (direct)                     │  
│  • 100.x.x.x:5678   → n8n (direct)                             │  
│                                                                 │  
│  ┌────────────┐  ┌────────────┐  ┌────────────┐               │  
│  │   Laptop   │  │   Phone    │  │   Tablet   │               │  
│  │100.x.x.2   │  │100.x.x.3   │  │100.x.x.4   │               │  
│  └────────────┘  └────────────┘  └────────────┘               │  
└─────────────────────────────────────────────────────────────────┘

**Key Points**:

* Ports 80/443 \= Public-facing (via proxy with SSL)  
* Tailscale IPs \= Admin access, direct connections  
* All services communicate internally via Docker network  
* No public exposure of admin interfaces (18789, 81, 6333\)

---

### **LiteLLM Configuration**

**Configuration File**: `/mnt/data/config/litellm_config.yaml`

**Example Configuration**:

model\_list:  
  \# Local Ollama Models  
  \- model\_name: llama3.2  
    litellm\_params:  
      model: ollama/llama3.2  
      api\_base: http://ollama:11434  
        
  \- model\_name: mistral  
    litellm\_params:  
      model: ollama/mistral  
      api\_base: http://ollama:11434  
        
  \- model\_name: codellama  
    litellm\_params:  
      model: ollama/codellama  
      api\_base: http://ollama:11434

  \# OpenAI Models (if API key configured)  
  \- model\_name: gpt-3.5-turbo  
    litellm\_params:  
      model: gpt-3.5-turbo  
      api\_key: os.environ/OPENAI\_API\_KEY  
        
  \- model\_name: gpt-4  
    litellm\_params:  
      model: gpt-4  
      api\_key: os.environ/OPENAI\_API\_KEY

  \# Anthropic Models (if API key configured)  
  \- model\_name: claude-3-sonnet  
    litellm\_params:  
      model: claude-3-sonnet-20240229  
      api\_key: os.environ/ANTHROPIC\_API\_KEY

  \# Google Gemini (if API key configured)  
  \- model\_name: gemini-pro  
    litellm\_params:  
      model: gemini/gemini-pro  
      api\_key: os.environ/GEMINI\_API\_KEY

\# Router Settings  
router\_settings:  
  routing\_strategy: usage-based-routing  \# Options: simple-shuffle, least-busy, usage-based-routing, latency-based-routing  
  num\_retries: 3  
  timeout: 600  
  allowed\_fails: 3  
  cooldown\_time: 60

\# Caching (Redis)  
cache:  
  type: redis  
  host: redis  
  port: 6379  
  password: os.environ/REDIS\_PASSWORD  
    
  \# Cache TTL (seconds)  
  ttl: 3600  
    
  \# Cache completion responses  
  supported\_call\_types:  
    \- completion  
    \- embedding

\# Budget Management  
general\_settings:  
  master\_key: os.environ/LITELLM\_MASTER\_KEY  
  database\_url: postgresql://postgres:${POSTGRES\_PASSWORD}@postgres:5432/litellm  
    
  \# Max budget per user (optional)  
  \# max\_budget: 100  
    
  \# Max budget per key (optional)  
  \# max\_budget\_per\_key: 10

\# Logging  
litellm\_settings:  
  drop\_params: true  
  set\_verbose: false  
  json\_logs: true  
    
\# Success/Failure Callbacks  
callbacks:  
  \- prometheus  \# Metrics for monitoring

\# Guardrails (optional)  
\# guardrails:  
\#   \- prompt\_injection\_detection  
\#   \- pii\_masking

**Routing Strategies Explained**:

1. **simple-shuffle**: Random model selection

   * Use: Load testing, no preference  
2. **least-busy**: Route to model with fewest active requests

   * Use: Balanced load distribution  
3. **usage-based-routing** (Recommended): Track success rates, prefer healthy models

   * Use: Production, automatic failover  
4. **latency-based-routing**: Route to fastest responding model

   * Use: Latency-sensitive applications

**Cost Tracking**:

* View in LiteLLM Admin UI: [http://100.x.x.x:18789](http://100.x.x.x:18789)  
* Per-user budgets  
* Per-API-key budgets  
* Cost per model/provider

---

### **Signal Configuration**

**Setup via Script 3** → Option 2

**Configuration Files**:

* `/mnt/data/env/signal.env`  
* `/mnt/data/signal/data/` (account data)

**Webhook Configuration**:

\# Set webhook URL (e.g., for n8n)  
curl \-X POST http://localhost:8090/v1/configuration/webhook \\  
  \-H "Content-Type: application/json" \\  
  \-d '{  
    "url": "http://n8n:5678/webhook/signal-incoming"  
  }'

**n8n Webhook Node**:

1\. Add "Webhook" node  
2\. Webhook Name: signal-incoming  
3\. HTTP Method: POST  
4\. Path: /webhook/signal-incoming

Incoming data structure:  
{  
  "envelope": {  
    "source": "+1234567890",  
    "sourceNumber": "+1234567890",  
    "sourceName": "John Doe",  
    "sourceUuid": "abc-123-def",  
    "timestamp": 1705334400000,  
    "dataMessage": {  
      "timestamp": 1705334400000,  
      "message": "Hello AI\!",  
      "expiresInSeconds": 0,  
      "viewOnce": false  
    }  
  },  
  "account": "+0987654321"  
}

**Example n8n Workflow** (AI-powered Signal bot):

\[Webhook\] → \[Function: Extract Message\] → \[HTTP: Query LiteLLM\] → \[Function: Format Response\] → \[HTTP: Send Signal Reply\]

---

### **Google Drive Configuration**

**Setup via Script 3** → Option 3

**OAuth Flow**:

1. Script generates auth URL  
2. Open URL in browser  
3. Authorize Google Drive access  
4. Copy auth code  
5. Paste into script  
6. Connection established

**Mounted Folder**:

* Local path: `/mnt/data/gdrive/mount/`  
* Accessible from containers: `gdrive-sync:/gdrive:ro`

**Sync Configuration**:

\# /mnt/data/config/gdrive-sync.conf  
sync\_interval: 300  \# 5 minutes  
folders:  
  \- My Drive/AI Documents  
  \- My Drive/Knowledge Base  
  \- My Drive/Work Files

**Integration with AnythingLLM**:

\# n8n workflow  
1\. Watch folder: /gdrive/AI Documents  
2\. On new file → Upload to AnythingLLM workspace  
3\. Trigger embedding generation  
4\. Send Signal notification: "Document \[name\] indexed"

---

## **Usage Examples**

### **Example 1: RAG Document Q\&A**

**Tools**: AnythingLLM, Qdrant, LiteLLM

1. **Upload Documents** (AnythingLLM):

   * Open [http://100.x.x.x:3001](http://100.x.x.x:3001)  
   * Create workspace: "Company Docs"  
   * Upload PDFs/DOCX files  
   * Wait for embedding (watch progress)  
2. **Configure LLM**:

   * Settings → LLM Provider: LiteLLM  
   * Model: gpt-3.5-turbo (or llama3.2 for local)  
   * Embedding Model: text-embedding-ada-002  
3. **Ask Questions**:

   * Type: "What are our vacation policies?"  
   * AnythingLLM:  
     * Searches Qdrant for relevant chunks  
     * Sends chunks \+ question to LiteLLM  
     * Returns answer with citations

### **Example 2: Automated Document Processing**

**Tools**: n8n, Google Drive, AnythingLLM, Signal

**Workflow**:

\[Google Drive Trigger: New File\]   
  ↓  
\[Move File to /gdrive/mount/\]  
  ↓  
\[HTTP Request: Upload to AnythingLLM API\]  
  ↓  
\[Wait for Embedding Complete\]  
  ↓  
\[HTTP Request: Send Signal notification\]  
  Message: "✅ Processed: {{fileName}}"

**Setup**:

1. Create n8n workflow ([http://100.x.x.x:5678](http://100.x.x.x:5678))  
2. Add Google Drive node (authenticate)  
3. Configure AnythingLLM API call  
4. Add Signal API node  
5. Activate workflow

### **Example 3: Multi-Model Comparison**

**Tools**: LiteLLM, Open WebUI

1. **Configure LiteLLM Models** (Script 3):

   * Add OpenAI (gpt-3.5-turbo, gpt-4)  
   * Add Anthropic (claude-3-sonnet)  
   * Add Local (llama3.2, mistral)  
2. **Open WebUI**:

   * Open [http://100.x.x.x:8080](http://100.x.x.x:8080)  
   * Select model dropdown  
   * All LiteLLM models appear  
   * Switch between models mid-conversation  
3. **Compare Responses**:

   * Ask same question to different models  
   * Compare speed, quality, cost  
   * View costs in LiteLLM Admin ([http://100.x.x.x:18789](http://100.x.x.x:18789))

### **Example 4: Signal-based AI Assistant**

**Tools**: Signal API, n8n, LiteLLM

**n8n Workflow**:

\[Webhook: Signal Incoming\]  
  ↓  
\[Function: Parse message\]  
  const message \= $json.envelope.dataMessage.message;  
  const sender \=  $ json.envelope.source;  
  return { message, sender };  
  ↓  
\[HTTP: Query LiteLLM\]  
  POST http://litellm:4000/v1/chat/completions  
  Body:  
  {  
    "model": "gpt-3.5-turbo",  
    "messages": \[  
      {"role": "system", "content": "You are a helpful assistant"},  
      {"role": "user", "content": "{{ $ node\['Function'\].json.message}}"}  
    \]  
  }  
  ↓  
\[Function: Extract AI response\]  
  const aiResponse \= $json.choices\[0\].message.content;  
  const sender \=  $ node\['Function'\].json.sender;  
  return { aiResponse, sender };  
  ↓  
\[HTTP: Send Signal Reply\]  
  POST http://signal-api:8090/v2/send  
  Body:  
  {  
    "message": "{{ $ json.aiResponse}}",  
    "number": "+YOUR\_NUMBER",  
    "recipients": \["{{$json.sender}}"\]  
  }

**Result**: Text your Signal number, get AI-powered responses\!

### **Example 5: Automated Reporting**

**Tools**: n8n, PostgreSQL, LiteLLM, Signal

**Workflow** (Daily at 9 AM):

\[Cron: 0 9 \* \* \*\]  
  ↓  
\[Postgres: Query metrics\]  
  SELECT   
    service\_name,  
    COUNT(\*) as requests,  
    AVG(response\_time) as avg\_time  
  FROM service\_logs  
  WHERE date \= CURRENT\_DATE \- 1  
  GROUP BY service\_name;  
  ↓  
\[Function: Format data\]  
  ↓  
\[HTTP: Generate report with LiteLLM\]  
  Prompt: "Create an executive summary of these metrics:  
  {{ $ json}}"  
  ↓  
\[HTTP: Send via Signal\]  
  Message: "📊 Daily Report\\n\\n{{ $ json.choices\[0\].message.content}}"

---

## **Troubleshooting**

### **Service Won't Start**

**Symptoms**: Container exits immediately

**Diagnosis**:

\# Check logs  
docker logs \<container-name\>

\# Check if port is in use  
sudo netstat \-tulpn | grep :\<port\>

\# Check environment variables  
docker exec \<container-name\> env

**Common Causes**:

**Port Conflict**:

 \# Find what's using the port  
sudo lsof \-i :\<port\>

\# Change port in compose file  
\# Edit /mnt/data/compose/\<service\>.yml  
ports:  
  \- "NEW\_PORT:INTERNAL\_PORT"

1. 

**Missing Environment Variable**:

 \# Check .env file  
cat /mnt/data/env/\<service\>.env

\# Ensure all required vars are set  
\# Re-run Script 3 to regenerate

2. 

**Permission Issues**:

 \# Fix data directory permissions  
sudo chown \-R 1000:1000 /mnt/data/\<service\>

3. 

### **Can't Access Service**

**Symptoms**: Connection refused, timeout

**Diagnosis**:

\# Check if service is running  
docker ps | grep \<service\>

\# Check if port is exposed  
docker port \<container-name\>

\# Test from host  
curl http://localhost:\<port\>

\# Test from another container  
docker exec \<another-container\> curl http://\<service-name\>:\<port\>

**Common Causes**:

**Firewall Blocking**:

 \# Check UFW status  
sudo ufw status

\# Allow port  
sudo ufw allow \<port\>/tcp

1. 

**Wrong Network**:

 \# Check container network  
docker inspect \<container\> | grep NetworkMode

\# Should be: ai-platform-network  
\# If not, fix in compose file:  
networks:  
  \- ai-platform-network

2. 

**Service Not Healthy**:

 \# Check health status  
docker inspect \<container\> | grep \-A 10 Health

\# View health check logs  
docker inspect \<container\> | jq '.\[0\].State.Health'

3. 

### **LiteLLM Not Routing**

**Symptoms**: "Model not found" errors

**Diagnosis**:

\# Check LiteLLM logs  
docker logs litellm

\# Test LiteLLM directly  
curl http://localhost:4000/v1/models \\  
  \-H "Authorization: Bearer $LITELLM\_MASTER\_KEY"

**Common Causes**:

**Invalid Config**:

 \# Validate YAML syntax  
yamllint /mnt/data/config/litellm\_config.yaml

\# Check for typos in model names  
cat /mnt/data/config/litellm\_config.yaml | grep model\_name

1. 

**Provider API Key Missing**:

 \# Check environment variables  
docker exec litellm env | grep API\_KEY

\# Add missing keys via Script 3  
sudo ./scripts/3-configure-services.sh  
→ Option 1: Add/Update LLM Provider

2. 

**Ollama Model Not Pulled**:

 \# List Ollama models  
docker exec ollama ollama list

\# Pull missing model  
docker exec ollama ollama pull llama3.2

3. 

### **Vector DB Connection Failed**

**Symptoms**: AnythingLLM/Dify can't connect to Qdrant

**Diagnosis**:

\# Check Qdrant status  
curl http://localhost:6333/health

\# Check from application container  
docker exec anythingllm curl http://qdrant:6333/health

**Common Causes**:

**Qdrant Not Running**:

 docker ps | grep qdrant  
\# If not running:  
docker start qdrant

1. 

**Wrong API Key**:

 \# Check Qdrant API key  
cat /mnt/data/env/qdrant.env | grep API\_KEY

\# Check application config  
cat /mnt/data/env/anythingllm.env | grep QDRANT

\# Keys should match\!

2. 

**Collection Not Created**:

 \# List collections  
curl http://localhost:6333/collections

\# Create missing collection (example for AnythingLLM)  
curl \-X PUT http://localhost:6333/collections/anythingllm \\  
  \-H "Content-Type: application/json" \\  
  \-d '{  
    "vectors": {  
      "size": 1536,  
      "distance": "Cosine"  
    }  
  }'

3. 

### **Signal API Not Pairing**

**Symptoms**: Can't register phone number

**Diagnosis**:

\# Check Signal API logs  
docker logs signal-api

\# Check if number is already registered  
docker exec signal-api signal-cli \-u \+YOUR\_NUMBER listDevices

**Common Causes**:

1. **Invalid Phone Format**:

   * Must include country code: \+1234567890  
   * No spaces or dashes

**Number Already Registered**:

 \# Unregister first  
docker exec signal-api signal-cli \-u \+YOUR\_NUMBER unregister

\# Then re-run Script 3 setup

2.   
3. **SMS Not Received**:

   * Check phone signal  
   * Try voice verification (option in script)  
   * Some carriers block automated SMS

### **Nginx Proxy Not Working**

**Symptoms**: 502 Bad Gateway, SSL errors

**Diagnosis**:

\# Check Nginx PM logs  
docker logs nginx-pm

\# Check if backend is reachable  
docker exec nginx-pm curl http://\<backend-service\>:\<port\>

**Common Causes**:

**Backend Service Down**:

 docker ps | grep \<backend-service\>  
\# Restart if needed  
docker restart \<backend-service\>

1.   
2. **SSL Certificate Issues**:

   * Check Nginx PM Admin UI ([http://100.x.x.x:81](http://100.x.x.x:81))  
   * Go to SSL Certificates  
   * Renew or reissue certificate  
3. **Wrong Proxy Configuration**:

   * In Nginx PM UI: Hosts → Proxy Hosts  
   * Verify:  
     * Domain name matches  
     * Forward host/port correct  
     * WebSocket support enabled (for n8n, Open WebUI)

### **High Resource Usage**

**Symptoms**: Slow performance, high CPU/RAM

**Diagnosis**:

\# Check resource usage  
docker stats

\# Find top consumer  
docker stats \--no-stream | sort \-k 3 \-h

**Common Causes**:

**Ollama Using GPU Incorrectly**:

 \# Check GPU status  
nvidia-smi

\# If not using GPU:  
\# Edit /mnt/data/compose/ollama.yml  
deploy:  
  resources:  
    reservations:  
      devices:  
        \- driver: nvidia  
          count: 1  
          capabilities: \[gpu\]

1. 

**Too Many Models Loaded**:

 \# Check Ollama loaded models  
docker exec ollama ollama list

\# Unload unused models  
docker exec ollama ollama rm \<model-name\>

2. 

**Database Not Optimized**:

 \# PostgreSQL: Vacuum and analyze  
docker exec postgres psql \-U postgres \-c "VACUUM ANALYZE;"

\# Qdrant: Optimize collection  
curl \-X POST http://localhost:6333/collections/anythingllm/index

3. 

---

## **Advanced Topics**

### **Custom LiteLLM Routing**

**Scenario**: Route cheap models for simple tasks, expensive for complex

\# /mnt/data/config/litellm\_config.yaml

model\_list:  
  \# Budget model group  
  \- model\_name: cheap-chat  
    litellm\_params:  
      model: ollama/llama3.2  
      api\_base: http://ollama:11434  
      rpm: 100  \# Requests per minute  
        
  \# Premium model group  
  \- model\_name: premium-chat  
    litellm\_params:  
      model: gpt-4  
      api\_key: os.environ/OPENAI\_API\_KEY  
      rpm: 10

router\_settings:  
  routing\_strategy: usage-based-routing  
    
  \# Fallback chain  
  fallbacks:  
    \- from\_model: premium-chat  
      to\_model: cheap-chat  \# Fallback to cheap if premium fails

\# Use in application:  
\# \- Simple queries: model="cheap-chat"  
\# \- Complex queries: model="premium-chat"

### **Multi-Tenant Setup**

**Scenario**: Isolate data per customer

**Approach 1: Database-Level**:

\# Deploy separate PostgreSQL per tenant  
\# /mnt/data/compose/postgres-tenant1.yml  
services:  
  postgres-tenant1:  
    image: postgres:16-alpine  
    environment:  
      POSTGRES\_DB: tenant1  
      POSTGRES\_PASSWORD: ${TENANT1\_PASSWORD}  
    volumes:  
      \- /mnt/data/postgres-tenant1:/var/lib/postgresql/data

**Approach 2: Application-Level** (Dify/AnythingLLM):

* Create separate workspaces per tenant  
* Use API keys to isolate access  
* Configure quotas per workspace

**Approach 3: Vector DB Collections**:

\# Create tenant-specific Qdrant collections  
curl \-X PUT http://localhost:6333/collections/tenant1 \\  
  \-H "Content-Type: application/json" \\  
  \-d '{"vectors": {"size": 1536, "distance": "Cosine"}}'

curl \-X PUT http://localhost:6333/collections/tenant2 \\  
  \-H "Content-Type: application/json" \\  
  \-d '{"vectors": {"size": 1536, "distance": "Cosine"}}'

### **Horizontal Scaling**

**Scenario**: Scale services across multiple servers

**Ollama Scaling** (Multiple GPU Servers):

\# Server 1: /mnt/data/config/litellm\_config.yaml  
model\_list:  
  \- model\_name: llama3.2  
    litellm\_params:  
      model: ollama/llama3.2  
      api\_base: http://server1-tailscale-ip:11434  
        
  \- model\_name: llama3.2  
    litellm\_params:  
      model: ollama/llama3.2  
      api\_base: http://server2-tailscale-ip:11434

\# LiteLLM will load balance between both

**Database Scaling** (PostgreSQL Replication):

1. Primary: Read/Write (Server 1\)  
2. Replica: Read-only (Server 2\)  
3. Update application configs to use replica for reads

### **Monitoring with Prometheus \+ Grafana**

**Deploy Stack** (Script 4):

sudo ./scripts/4-add-service.sh  
→ Select: Prometheus \+ Grafana

**Grafana Dashboards**:

1. LiteLLM Dashboard:

   * Requests per model  
   * Cost tracking  
   * Latency percentiles  
   * Error rates  
2. Docker Metrics:

   * CPU/RAM per container  
   * Network I/O  
   * Disk usage  
3. Qdrant Dashboard:

   * Query latency  
   * Vector count  
   * Index status

**Alerts**:

\# /mnt/data/config/prometheus/alerts.yml  
groups:  
  \- name: ai-platform  
    rules:  
      \- alert: HighErrorRate  
        expr: rate(litellm\_errors\[5m\]) \> 0.05  
        annotations:  
          summary: "High error rate in LiteLLM"  
            
      \- alert: HighMemoryUsage  
        expr: container\_memory\_usage\_bytes / container\_spec\_memory\_limit\_bytes \> 0.9  
        annotations:  
          summary: "Container {{ $labels.name }} using \>90% memory"

### **Backup Strategy**

**Automated Backups** (via cron):

\# /etc/cron.d/ai-platform-backup  
0 2 \* \* \* root /usr/local/bin/backup-ai-platform.sh

**Backup Script** (generated by Script 3):

\#\!/bin/bash  
\# /usr/local/bin/backup-ai-platform.sh

BACKUP\_DIR="/mnt/data/backups"  
DATE= $ (date \+%Y%m%d\_%H%M%S)

\# Backup PostgreSQL  
docker exec postgres pg\_dumpall \-U postgres | gzip \> " $ BACKUP\_DIR/postgres/postgres\_ $ DATE.sql.gz"

\# Backup Redis  
docker exec redis redis-cli \--rdb " $ BACKUP\_DIR/redis/dump\_ $ DATE.rdb"

\# Backup Qdrant snapshots  
curl \-X POST http://localhost:6333/collections/anythingllm/snapshots  
curl http://localhost:6333/collections/anythingllm/snapshots \-o " $ BACKUP\_DIR/qdrant/anythingllm\_ $ DATE.snapshot"

\# Backup configs  
tar \-czf " $ BACKUP\_DIR/configs/configs\_ $ DATE.tar.gz" /mnt/data/config/ /mnt/data/env/

\# Rotate old backups (keep 30 days)  
find " $ BACKUP\_DIR" \-type f \-mtime \+30 \-delete

\# Upload to cloud (optional)  
\# rclone copy "$BACKUP\_DIR" remote:ai-platform-backups

### **Disaster Recovery**

**Full System Restore**:

\# 1\. Fresh server with same OS  
\# 2\. Install Docker, Tailscale  
\# 3\. Restore data directory  
sudo rsync \-avz backup-server:/mnt/data/ /mnt/data/

\# 4\. Run deployment script  
sudo ./scripts/2-deploy-services.sh

\# 5\. Restore databases  
gunzip \< /mnt/data/backups/postgres/postgres\_LATEST.sql.gz | \\  
  docker exec \-i postgres psql \-U postgres

\# 6\. Restart all services  
docker restart $(docker ps \-aq)

---

## **Contributing**

We welcome contributions\! Areas of interest:

* Additional service integrations  
* Improved error handling  
* Performance optimizations  
* Documentation improvements  
* Bug fixes

**How to Contribute**:

1. Fork repository  
2. Create feature branch  
3. Test changes thoroughly  
4. Submit pull request with description

**Coding Standards**:

* Follow existing bash script conventions  
* Add comments for complex logic  
* Update documentation for new features  
* Test on fresh Ubuntu 24.04 installation

---

## **License**

MIT License \- See LICENSE file for details

REFERENCES

Codebase : 

\* The repository \[https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation\](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation)  

\* high level objectives here : \[https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/README.md\](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/README.md)  

\* The previous (superseeded) high level objectives : \[https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/3176f2f3da7ee9ccb2908380387df3e38923a8d4/README.md\](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/3176f2f3da7ee9ccb2908380387df3e38923a8d4/README.md)  

\* script 0 : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/0-complete-cleanup.sh  

\* script 1: https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh  

\* script 2 : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh  

\* script 3 : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh  

\* script 4 : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh  

    

\* This was a good start ui wise : \[https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/7df4b977d0d66f7dcdd0b099a38fb4011402d280/scripts/1-setup-system.sh\](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/7df4b977d0d66f7dcdd0b099a38fb4011402d280/scripts/1-setup-system.sh)  

\* This was the iteration with more bugs : \[https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/0af338937926c8d052d9a413b79409376e8c7dfa/scripts/1-setup-system.sh\](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/0af338937926c8d052d9a413b79409376e8c7dfa/scripts/1-setup-system.sh)  

\* This was a good attempt to incorporate all mandatory variables from services : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/069b5f51f047319120a1a97080116bbe4a1d322b/scripts/1-setup-system.sh

