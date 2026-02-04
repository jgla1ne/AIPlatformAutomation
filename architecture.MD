# AI Platform Architecture Diagram

## System Architecture Overview
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AWS EC2 Instance (Ubuntu 22.04)                     │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         Tailscale VPN Layer                            │ │
│  │              (Secure Remote Access - Port 41641 UDP)                   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                     ↓                                        │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                     NGINX Reverse Proxy (Port 8443)                    │ │
│  │                          SSL/TLS Termination                           │ │
│  │                                                                        │ │
│  │  Routes:                                                               │ │
│  │    /anythingllm  → AnythingLLM:3001                                   │ │
│  │    /clawdbot     → Clawdbot:3000                                      │ │
│  │    /dify         → Dify:80 (internal NGINX)                           │ │
│  │    /n8n          → n8n:5678                                           │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                     ↓                                        │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    Docker Network: ai-platform                         │ │
│  │                     (Internal Service Communication)                   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                     ↓                                        │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                          Service Layer                                │   │
│  │                                                                        │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │   │
│  │  │ AnythingLLM │  │  Clawdbot   │  │    Dify     │  │     n8n     │ │   │
│  │  │  Port 3001  │  │  Port 3000  │  │   Port 80   │  │  Port 5678  │ │   │
│  │  │             │  │             │  │  (internal) │  │             │ │   │
│  │  │   Vector    │  │   Agent     │  │  Workflow   │  │  Workflow   │ │   │
│  │  │  Database   │  │ Automation  │  │   Builder   │  │ Automation  │ │   │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └─────────────┘ │   │
│  │         │                │                │                          │   │
│  │         └────────────────┴────────────────┘                          │   │
│  │                          ↓                                            │   │
│  │         ┌────────────────────────────────────────┐                   │   │
│  │         │         LiteLLM Proxy Gateway          │                   │   │
│  │         │            Port 4000                    │                   │   │
│  │         │                                         │                   │   │
│  │         │  • Request routing & load balancing    │                   │   │
│  │         │  • Token counting & cost tracking      │                   │   │
│  │         │  • Retry logic & fallback handling     │                   │   │
│  │         │  • Unified API interface               │                   │   │
│  │         └──────────────┬──────────────────────────┘                   │   │
│  │                        ↓                                              │   │
│  │         ┌──────────────────────────────────────┐                     │   │
│  │         │         Ollama (Local Models)        │                     │   │
│  │         │           Port 11434                  │                     │   │
│  │         │                                       │                     │   │
│  │         │  Models: llama3.2, qwen2.5, etc.    │                     │   │
│  │         └───────────────────────────────────────┘                     │   │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                     ↓                                        │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                      Communication Services                            │ │
│  │                                                                        │ │
│  │  ┌─────────────────────┐              ┌─────────────────────┐        │ │
│  │  │    Signal API       │              │   Google Drive      │        │ │
│  │  │   Port 8080/8081    │              │   (rclone mount)    │        │ │
│  │  │                     │              │                     │        │ │
│  │  │  Phone integration  │              │  Document storage   │        │ │
│  │  └─────────────────────┘              └─────────────────────┘        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                     ↓                                        │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         Storage Layer                                  │ │
│  │                                                                        │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐   │ │
│  │  │  /home/jglaine/  │  │   /mnt/data/     │  │   Docker         │   │ │
│  │  │  ai-platform/    │  │                  │  │   Volumes        │   │ │
│  │  │                  │  │  • Scalable EBS  │  │                  │   │ │
│  │  │  • Scripts       │  │  • Large docs    │  │  • PostgreSQL    │   │ │
│  │  │  • Configs       │  │  • Media files   │  │  • Redis         │   │ │
│  │  │  • Logs          │  │  • Backups       │  │  • Weaviate      │   │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘   │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

## Data Flow Diagram
┌─────────────┐
│   User      │
│  (Tailscale)│
└──────┬──────┘
       │ HTTPS (443 → 8443)
       ↓
┌──────────────────────┐
│   NGINX Proxy        │
│   SSL Termination    │
└──────┬───────────────┘
       │
       ├─→ /anythingllm ─→ AnythingLLM (3001) ─┐
       │                                        │
       ├─→ /clawdbot ────→ Clawdbot (3000) ────┤
       │                                        │
       ├─→ /dify ────────→ Dify (80) ──────────┤
       │                                        │
       └─→ /n8n ─────────→ n8n (5678) ─────────┤
                                                │
                                                ↓
                                    ┌───────────────────┐
                                    │  LiteLLM Gateway  │
                                    │   (Port 4000)     │
                                    └─────────┬─────────┘
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    │                         │                         │
                    ↓                         ↓                         ↓
          ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
          │  Simple Queries  │    │ Complex Queries  │    │  External APIs   │
          │   (Ollama)       │    │   (Claude/GPT)   │    │   (Fallback)     │
          │  llama3.2:3b     │    │   Via Tailscale  │    │                  │
          └──────────────────┘    └──────────────────┘    └──────────────────┘

## Network Architecture
┌─────────────────────────────────────────────────────────────────┐
│                    Docker Network: ai-platform                   │
│                      Subnet: 172.20.0.0/16                       │
│                                                                  │
│  Service IP Assignments:                                         │
│  ├─ nginx:          172.20.0.2                                  │
│  ├─ ollama:         172.20.0.10                                 │
│  ├─ litellm:        172.20.0.11                                 │
│  ├─ anythingllm:    172.20.0.20                                 │
│  ├─ clawdbot:       172.20.0.21                                 │
│  ├─ dify:           172.20.0.30                                 │
│  ├─ n8n:            172.20.0.40                                 │
│  ├─ signal-api:     172.20.0.50                                 │
│  └─ gdrive:         172.20.0.60                                 │
│                                                                  │
│  All services can communicate via service name (DNS)             │
│  Example: http://ollama:11434                                   │
└─────────────────────────────────────────────────────────────────┘

## Storage Architecture
EC2 Instance Storage Layout
───────────────────────────
/home/jglaine/ai-platform/          (Main Application)
├── scripts/                        (Deployment scripts)
├── stacks/                         (Docker compose files)
│   ├── anythingllm/
│   ├── clawdbot/
│   ├── dify/
│   ├── litellm/
│   ├── n8n/
│   ├── nginx/
│   ├── ollama/
│   ├── signal-api/
│   └── gdrive/
├── data/                          (Service data)
│   ├── anythingllm/
│   │   └── storage/ → /mnt/data/anythingllm/storage
│   ├── ollama/models/
│   ├── postgresql/
│   ├── redis/
│   └── gdrive/
│       └── sync/ → /mnt/data/gdrive/
└── logs/                          (Deployment logs)
/mnt/data/                         (Scalable EBS Volume)
├── anythingllm/
│   └── storage/                   (Vector DB, documents)
├── gdrive/                        (Google Drive sync)
├── backups/                       (Automated backups)
└── media/                         (Large media files)
Docker Volumes
──────────────
├── postgres_data                  (PostgreSQL database)
├── redis_data                     (Redis cache)
├── weaviate_data                  (Vector database)
└── ollama_models                  (AI models)

## Security Layers
┌────────────────────────────────────────────────────────────┐
│                    Security Architecture                    │
│                                                             │
│  Layer 1: Network (AWS Security Groups)                    │
│  ├─ Tailscale:      41641/udp  (WireGuard VPN)            │
│  ├─ SSH:            22/tcp      (Key-based only)          │
│  └─ All other:      BLOCKED                               │
│                                                             │
│  Layer 2: Tailscale VPN                                    │
│  ├─ End-to-end encryption (WireGuard protocol)            │
│  ├─ MagicDNS for service discovery                        │
│  ├─ ACLs for access control                               │
│  └─ No public IP exposure                                 │
│                                                             │
│  Layer 3: NGINX Reverse Proxy                              │
│  ├─ SSL/TLS termination (Let's Encrypt)                   │
│  ├─ Path-based routing                                    │
│  ├─ Rate limiting                                         │
│  └─ Security headers                                      │
│                                                             │
│  Layer 4: Docker Network Isolation                         │
│  ├─ Internal network (172.20.0.0/16)                      │
│  ├─ No external port exposure                             │
│  └─ Service-to-service authentication                     │
│                                                             │
│  Layer 5: Application Security                             │
│  ├─ API key authentication                                │
│  ├─ JWT tokens                                            │
│  ├─ User-specific credentials                             │
│  └─ Database encryption at rest                           │
└────────────────────────────────────────────────────────────┘

## Component Integration Map
                ┌─────────────────────┐
                │   User Interface    │
                │   (Web Browser)     │
                └──────────┬──────────┘
                           │
                ┌──────────▼──────────┐
                │   Service Entry     │
                ├─────────────────────┤
                │  • AnythingLLM      │◄─────┐
                │  • Clawdbot         │      │
                │  • Dify             │      │
                │  • n8n              │      │
                └──────────┬──────────┘      │
                           │                  │
                ┌──────────▼──────────┐      │
                │   LiteLLM Proxy     │      │
                │   (Smart Router)    │      │
                └──────────┬──────────┘      │
                           │                  │
            ┌──────────────┼──────────────┐  │
            │              │              │  │
 ┌──────────▼────────┐  ┌─▼────────┐  ┌──▼──────────┐
 │  Local Models     │  │ External │  │  Clawdbot   │
 │  (Ollama)         │  │ APIs     │  │  Actions    │
 │                   │  │          │  │             │
 │ • llama3.2        │  │ • Claude │  │ • System    │
 │ • qwen2.5         │  │ • GPT-4  │  │ • Files     │
 │ • deepseek        │  │          │  │ • Workflows │
 └───────────────────┘  └──────────┘  └──────┬──────┘
                                              │
                           ┌──────────────────┘
                           │
                ┌──────────▼──────────┐
                │  Data Sources       │
                ├─────────────────────┤
                │ • Vector DB         │
                │ • Google Drive      │
                │ • Signal Messages   │
                │ • Local Files       │
                └─────────────────────┘

## Deployment Flow
Step 1: System Setup
┌─────────────────────────────────────┐
│  1-system-setup.sh                  │
│  ├─ Install dependencies            │
│  ├─ Configure Docker                │
│  ├─ Create networks                 │
│  ├─ Setup directories               │
│  └─ Generate .env file              │
└─────────────────────────────────────┘
              ↓
Step 2: Deploy Services
┌─────────────────────────────────────┐
│  2-deploy-services.sh               │
│  ├─ Deploy Ollama                   │
│  ├─ Deploy LiteLLM                  │
│  ├─ Deploy AnythingLLM              │
│  ├─ Deploy Clawdbot                 │
│  ├─ Deploy Dify                     │
│  ├─ Deploy n8n                      │
│  ├─ Deploy Signal API               │
│  ├─ Deploy Google Drive             │
│  └─ Configure NGINX & Tailscale     │
└─────────────────────────────────────┘
              ↓
Step 3: Configure Services
┌─────────────────────────────────────┐
│  3-configure-services.sh            │
│  ├─ Link Signal phone               │
│  ├─ Setup Google Drive sync         │
│  ├─ Download Ollama models          │
│  ├─ Configure LiteLLM routing       │
│  ├─ Setup Clawdbot integrations     │
│  └─ Create systemd daemons          │
└─────────────────────────────────────┘
              ↓
Step 4: Add Services (Optional)
┌─────────────────────────────────────┐
│  4-add-service.sh                   │
│  ├─ Choose service template         │
│  ├─ Generate docker-compose.yml     │
│  ├─ Configure NGINX routing         │
│  ├─ Deploy new service              │
│  └─ Create systemd daemon           │
└─────────────────────────────────────┘

