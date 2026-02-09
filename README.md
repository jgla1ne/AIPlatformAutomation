# AIPlatformAutomation

## 1. Purpose

AIPlatformAutomation provides a **fully automated, modular, self-hosted AI platform** designed to:

- Run **on-prem or in private cloud**
- Embed **private data locally**
- Share those embeddings across **multiple AI services**
- Combine **local LLMs** and **external LLM providers**
- Enforce **strict network separation**
- Be **reproducible, auditable, and extensible**

The platform is driven entirely by scripts and configuration files, not manual steps.

---

## 2. Core Objectives

This project aims to deliver:

- A **single AI platform**, not isolated tools  
- A **shared private vector memory** usable by all services  
- Deterministic setup and deployment  
- Minimal trust surface  
- Clear operational boundaries  
- Incremental extensibility without redeployment  

---

## 3. Key Outcomes

After full execution, the platform provides:

- On-prem vector embeddings of private data  
- Multiple AI applications using the same embedded data  
- Centralized LLM routing  
- Optional augmentation via external LLMs  
- Secure public access for selected services  
- Private administrative access via Tailscale  
- Modular service lifecycle management  

---

## 4. Architectural Principles

1. **Separation of Concerns**  
   Cleanup, configuration, deployment, wiring, and extension are isolated.

2. **Network Segmentation**  
   Public access, private service traffic, and admin access are separated.

3. **Data Gravity**  
   Private data and embeddings remain local.

4. **Explicit Configuration**  
   All decisions are collected once and reused.

5. **Service Composability**  
   Each service is independently dockerized and replaceable.

---

## 5. Network Architecture

### 5.1 Public Access Layer

- Bound to **Public IP**
- Ports: **80 / 443**
- Terminates TLS
- Exposes **only selected web interfaces**
- Implemented via reverse proxy (Caddy / Nginx)

No internal APIs, databases, or LLM endpoints are publicly reachable.

---

### 5.2 Private AI Network

- Docker internal bridge network
- No inbound public access
- All service-to-service communication occurs here

Includes:
- LiteLLM
- Ollama (internal LLMs)
- Vector database (Qdrant / Chroma)
- OpenClaw
- AI applications (Dify, Flowise, OpenWebUI, etc.)

This is where **private embeddings live and are consumed**.

---

### 5.3 Tailscale Overlay Network

- Uses **Tailscale IPs (100.x.x.x)**
- Never exposed publicly
- Used for:
  - Administration
  - Debugging
  - Internal APIs
  - Secure remote access

Tailscale **does not replace** the public proxy.  
It is a **separate trust domain**.

---

## 6. Core Platform Components

### 6.1 LiteLLM

- Central routing layer for all LLM requests
- Supports:
  - Local models (via Ollama)
  - External providers (OpenAI, OpenRouter, Google Gemini, etc.)
- Routing strategies:
  - Round-robin
  - Weighted
  - Custom

All AI services interact with LLMs **only through LiteLLM**.

---

### 6.2 Ollama (Internal LLMs)

- Hosts local models
- Used for:
  - Inference
  - Embeddings
- Models are selectable during setup
- Models are pulled during deployment

---

### 6.3 Vector Database

- Qdrant or Chroma
- Stores embeddings of private data
- Shared across all AI services
- Never exposed publicly

---

### 6.4 OpenClaw

- Embedding and access coordination layer
- Connects:
  - LiteLLM
  - Vector DB
  - AI services
- Generates credentials and runtime configuration
- Enforces consistent access patterns to private data

---

## 7. AI Applications Layer

Multiple AI services can be enabled concurrently, including:

- Dify
- Flowise
- OpenWebUI
- ComfyUI
- AnythingLLM
- Custom services added later

All services:
- Use the same vector DB
- Route LLM calls through LiteLLM
- Never embed data independently

---

## 8. Optional Services

- Monitoring:
  - Grafana
  - Prometheus
  - ELK
- Administration:
  - Portainer
- Communication:
  - Signal integration
- Data sync:
  - Google Drive (OAuth or Project-based)

Optional services are selected during configuration and integrated consistently.

---

## 9. Script Lifecycle

### Script 0 — Complete Cleanup  
`0-complete-cleanup.sh`

Purpose:
- Reset the host to a known clean state

Removes:
- Docker (containers, images, volumes, networks)
- `/mnt/data`
- Configuration directories
- Residual system packages

Preserves:
- `/scripts`

Ensures:
- No state leakage between deployments

---

### Script 1 — System Setup  
`1-setup-system.sh`

Purpose:
- Collect **all configuration and intent**

Responsibilities:
- Prepare and mount `/mnt/data`
- Create required directory structure
- Ensure correct permissions
- Collect:
  - Core services
  - AI services
  - Vector DB choice
  - Internal LLM models
  - External LLM providers and API keys
  - Proxy configuration and SSL email
  - Custom ports (validated)
  - Tailscale auth and API keys
  - Signal configuration
  - GDrive configuration
  - Monitoring stack
- Write:
  - `.env`
  - `credentials.txt`
  - Metadata files

**No services are installed or started here**

---

### Script 2 — Deploy Services  
`2-deploy-services.sh`

Purpose:
- Materialize the configuration

Actions:
- Load `.env`
- Pull Docker images
- Assemble per-service compose fragments
- Build unified Docker Compose stack
- Deploy services incrementally
- Perform health checks with timeouts
- Produce deployment summary

---

### Script 3 — Configure Services  
`3-configure-services.sh`

Purpose:
- Wire services together

Actions:
- Configure:
  - LiteLLM routing
  - OpenClaw ↔ Vector DB
  - Tailscale
  - Signal
  - GDrive
- Generate runtime configuration files
- Validate inter-service communication
- Update service summary

---

### Script 4 — Add Service  
`4-add-service.sh`

Purpose:
- Extend the platform post-deployment

Actions:
- Add a new dockerized service
- Inject it into the existing stack
- Update compose and configuration
- No teardown required

---

## 10. Security & Data Model

- Private data:
  - Embedded locally
  - Never leaves the platform
- External LLMs:
  - Optional
  - Routed and controlled
- Secrets:
  - Generated dynamically
  - Stored locally
- Public access:
  - Limited and explicit
- Internal APIs:
  - Private only

---

## 11. Intended Usage Flow

```bash
sudo ./scripts/0-complete-cleanup.sh
sudo ./scripts/1-setup-system.sh
sudo ./scripts/2-deploy-services.sh
sudo ./scripts/3-configure-services.sh
sudo ./scripts/4-add-service.sh
