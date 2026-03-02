Perfect ✅ — this is exactly the kind of architectural drift that happens when README evolution loses deployment truth.

You’re absolutely right:

- ❌ **OpenClaw is NOT behind the reverse proxy**
- ✅ It is exposed via **Tailscale private IP**
- ✅ It operates on its own network path
- ✅ It should not be visually grouped under proxy-routed services

You also want stronger emphasis on:

- 🐳 Fully dockerized compose generation
- 🔐 Non-root tenant-specific UID execution
- 🧠 Interconnected LLM architecture (LiteLLM as entrypoint, vector DB integration, internal ↔ external routing)
- 🧩 Intentional stack orchestration, not “just services running”

Below is a **corrected README**, keeping the **exact same structure and layout**, but:

- ✅ Fixing OpenClaw placement
- ✅ Reinforcing docker-compose generation model
- ✅ Emphasizing non-root security
- ✅ Clarifying LiteLLM central routing role
- ✅ Clarifying vector DB integration chain
- ✅ Reinforcing the "interconnected AI system" objective

---

# ✅ RECONSTRUCTED README (STRUCTURE PRESERVED)

---

# **AI Platform Automation**

A comprehensive, modular AI platform deployment system with dynamic service orchestration.

This platform does not deploy independent containers.  
It deploys an **interconnected AI runtime stack**.

---

## **🏗 Architecture Overview**

This platform uses a fully dockerized, dynamically generated `docker-compose` architecture.

No static compose file exists in the repository.

Each tenant deployment generates:

- A custom `docker-compose.yml`
- A dedicated Docker network
- A non-root runtime configuration
- Reverse proxy configuration (if selected)
- A centralized `.env` file
- Inter-service wiring

---

### **Core Components**

* **Script 0:** Complete tenant cleanup (containers, volumes, networks)  
* **Script 1:** Interactive configuration (hardware detection, ports, services, credentials, proxy selection)  
* **Script 2:** Dynamic `docker-compose.yml` generation + network creation  
* **Script 3:** Post-deployment stack interconnection & LLM configuration  
* **Script 4:** Add new services without modifying core scripts  

---

## **🎯 Architectural Goals**

✅ Multi-tenant isolation  
✅ Fully dockerized compose-based infrastructure  
✅ Non-root container execution (tenant UID/GID)  
✅ Centralized LLM routing via LiteLLM  
✅ Internal ↔ External model abstraction  
✅ Vector database integration for RAG  
✅ Service auto-integration at configuration stage  

This is not a container launcher.  
It is an **AI infrastructure orchestration system**.

---

# **🚀 Quick Start**

```bash
# 1. Cleanup
sudo bash scripts/0-complete-cleanup.sh

# 2. Configure tenant
sudo bash scripts/1-setup-system.sh

# 3. (Optional) Add Tailscale auth key
nano /mnt/data/u1001/.env
# TAILSCALE_AUTH_KEY=tskey-auth-xxxxx

# 4. Deploy stack
sudo bash scripts/2-deploy-services.sh

# 5. Interconnect services
sudo bash scripts/3-configure-services.sh

# 6. Extend later
sudo bash scripts/4-add-service.sh <service>
```

---

# **📋 Available Services**

Only selected services are deployed and interconnected.

| Service | Role | Exposure |
|----------|------|----------|
| Ollama | Local LLM runtime | Internal |
| LiteLLM | Central LLM gateway & router | Internal + Proxy |
| PostgreSQL | Structured storage | Internal |
| Redis | Cache / queue | Internal |
| Qdrant | Vector database | Internal |
| Open WebUI | Chat UI | Reverse Proxy |
| AnythingLLM | RAG UI | Reverse Proxy |
| Dify | AI App Builder | Reverse Proxy |
| Flowise | Visual AI workflows | Reverse Proxy |
| n8n | Automation | Reverse Proxy |
| OpenClaw | AI Browser Agent | **Tailscale only** |
| Prometheus | Metrics collector | Internal |
| Grafana | Monitoring dashboard | Reverse Proxy |
| MinIO | Object storage | Reverse Proxy |
| Signal API | Messaging bridge | Internal |
| Tailscale | Private network overlay | External VPN |

---

# **🌐 Network Architecture**

### Reverse Proxy Network (Optional)

```
Internet
   │
   ▼
Reverse Proxy (Caddy / Nginx / Traefik)
   │
   ├── Open WebUI
   ├── AnythingLLM
   ├── Dify
   ├── Flowise
   ├── n8n
   ├── Grafana
   └── MinIO
```

---

### Core Internal Docker Network (Tenant Scoped)

```
Tenant Docker Network
   ├── Ollama
   ├── LiteLLM
   ├── Qdrant
   ├── PostgreSQL
   ├── Redis
   └── Prometheus
```

All AI services communicate internally through this network.

---

### Tailscale Network (Separate Path)

```
Tailscale VPN
   │
   └── OpenClaw (Dedicated Tailscale IP)
```

OpenClaw is NOT exposed through reverse proxy.  
It is accessed exclusively via private Tailscale IP for secure automation control.

---

# **🔧 Configuration Model**

All configuration is centralized:

```
/mnt/data/<tenant>/.env
```

Generated during Script 1.

The system automatically:

- Detects GPU availability
- Enables NVIDIA runtime if present
- Allocates conflict-free ports
- Generates secure secrets
- Creates tenant-scoped Docker networks
- Assigns containers to tenant UID/GID
- Prevents root execution
- Generates reverse proxy config (if enabled)

No credentials are hardcoded.

---

# **🧠 Interconnected LLM Architecture**

This is the core design principle.

---

### 🔹 Ollama

- Provides local model inference
- Runs inside internal Docker network
- Not directly exposed externally

---

### 🔹 LiteLLM (Central Entry Point)

LiteLLM acts as:

✅ Unified LLM API gateway  
✅ Routing layer  
✅ Local → Cloud fallback manager  
✅ Authentication layer  

All AI apps connect to LiteLLM, not directly to Ollama.

Flow:

```
AI App (AnythingLLM / Dify / Flowise / OpenWebUI)
          │
          ▼
        LiteLLM
          │
          ├── Ollama (local models)
          └── External APIs (OpenAI, Anthropic, etc.)
```

This allows:

- Transparent model switching
- Centralized API key management
- Rate limiting
- Future multi-model routing

---

### 🔹 Vector Database Integration

AnythingLLM uses:

```
AnythingLLM
    │
    ├── LiteLLM (for inference)
    └── Qdrant (for embeddings)
```

Qdrant runs internally and is not exposed externally.

Script 3 ensures:

- Collections created
- Endpoints configured
- Embeddings pipeline functional

---

# **📊 Monitoring & Observability**

```
Containers → Prometheus → Grafana
```

- Prometheus scrapes container metrics
- Grafana auto-configured
- Reverse proxy metrics optionally collected
- Healthchecks embedded in compose definitions

All monitoring containers run as non-root.

---

# **🔐 Security Architecture**

### Non-Root Execution

All containers run as:

```
user: "${TENANT_UID}:${TENANT_GID}"
```

No root containers allowed.

---

### Tenant Isolation

Each tenant has:

```
/mnt/data/uXXXX/
    ├── .env
    ├── docker-compose.yml
    ├── logs/
    ├── volumes/
```

Each tenant:

- Has its own Docker network
- Has isolated volumes
- Has independent lifecycle
- Cannot access other tenant containers

---

### Secrets Management

- Generated at setup
- Stored in `.env`
- Not embedded in compose templates
- Not committed to repository

---

# **🚦 Production Deployment**

For production:

1. Configure DNS
2. Open 80/443 if reverse proxy enabled
3. Configure firewall rules
4. Enable backups:
   - PostgreSQL
   - Qdrant
   - MinIO
5. Verify Tailscale connectivity
6. Test LiteLLM routing fallback

---

# **✅ SUCCESS CRITERIA BY PHASE**

---

## Phase 0 — Cleanup

✅ No orphan containers  
✅ No orphan networks  
✅ Volumes reset (optional preserve)  
✅ Comple docker prune of all images
✅ complete rm -rf of tenant data (including root data which should never be)
---

## Phase 1 — Setup

✅ GPU detection complete  
✅ Ports conflict-free  
✅ `.env` clean and deterministic  
✅ Docker group permissions applied  
✅ No containers running  
✅ Complete sumary of service stack configured and url to expect
---

## Phase 2 — Deployment

✅ Dynamic docker prune of the tenant to reload a clean stack and avoid port conflict
✅ Dynamic docker-compose generated  
✅ Tenant network created  
✅ All services running  
✅ restart: unless-stopped enabled  
✅ Health checks passing  
✅ Reverse proxy routing valid  
✅ OpenClaw reachable via Tailscale  
✅ Complete summary of service stack stood up, summary of url by health

---

## Phase 3 — Configuration

✅ Ollama models pulled  
✅ LiteLLM routing configured  
✅ Local → external fallback tested  
✅ Qdrant collections created  
✅ AnythingLLM connected to LiteLLM + Qdrant  
✅ Dify using LiteLLM gateway  
✅ Services auto-start on reboot  
✅ Services status, sservice reload, redeploy

---

## Phase 4 — Extensibility

✅ Services appended dynamically  
✅ Reverse proxy auto-updated  
✅ Monitoring auto-integrated  
✅ No modification to core architecture  

---

# **🧠 Technology Stack Summary**

| Layer | Technology | Role |
|-------|------------|------|
| LLM Runtime | Ollama | Local inference |
| LLM Gateway | LiteLLM | Central routing |
| Vector DB | Qdrant | Embeddings |
| Database | PostgreSQL | Structured storage |
| Cache | Redis | Performance |
| Monitoring | Prometheus | Metrics |
| Visualization | Grafana | Dashboards |
| Object Storage | MinIO | S3 storage |
| Reverse Proxy | Caddy / Nginx / Traefik | HTTPS |
| VPN | Tailscale | Secure access |
| RAG UI | AnythingLLM | Document interface |
| AI Builder | Dify | App builder |
| Agent | OpenClaw | Browser automation |

---

# **📌 Status**

**Status:** Production-Grade Modular AI Stack  
**Last Updated:** 2026-03-01  
**Maintainer:** Jean-Gabriel Laine  
