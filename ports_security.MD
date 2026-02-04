# Port & Security Reference

## External Port Exposure

### AWS Security Group Configuration

| Protocol | Port  | Source      | Purpose                    | Status   |
|----------|-------|-------------|----------------------------|----------|
| TCP      | 22    | My IP       | SSH access (key-based)     | Required |
| UDP      | 41641 | 0.0.0.0/0   | Tailscale WireGuard VPN    | Required |
| TCP      | 8443  | Tailscale   | HTTPS (internal only)      | Optional |

**⚠️ CRITICAL: Only port 22 and 41641 should be open to the internet**

---

## Internal Port Mapping

### Services Exposed via NGINX (Port 8443)

| Service      | Internal Port | External Path | Direct Access        | NGINX Route           |
|--------------|---------------|---------------|----------------------|-----------------------|
| AnythingLLM  | 3001          | /anythingllm  | ❌ Not exposed       | ✅ https://HOST:8443/anythingllm |
| Clawdbot     | 3000          | /clawdbot     | ❌ Not exposed       | ✅ https://HOST:8443/clawdbot    |
| Dify         | 80            | /dify         | ❌ Not exposed       | ✅ https://HOST:8443/dify        |
| n8n          | 5678          | /n8n          | ❌ Not exposed       | ✅ https://HOST:8443/n8n         |

### Backend Services (Internal Docker Network Only)

| Service    | Port  | Protocol | Access                      | Purpose                          |
|------------|-------|----------|-----------------------------|----------------------------------|
| Ollama     | 11434 | HTTP     | Docker network only         | Local LLM inference              |
| LiteLLM    | 4000  | HTTP     | Docker network only         | Proxy gateway & routing          |
| PostgreSQL | 5432  | TCP      | Docker network only         | Dify database                    |
| Redis      | 6379  | TCP      | Docker network only         | Dify cache                       |
| Weaviate   | 8080  | HTTP     | Docker network only         | AnythingLLM vector database      |
| Signal API | 8080  | HTTP     | Docker network only         | Signal messaging primary         |
| Signal API | 8081  | HTTP     | Docker network only         | Signal messaging secondary       |
| Google     | 5572  | HTTP     | Docker network only         | rclone WebDAV                    |

---

## Dify Internal NGINX Configuration

Dify includes its own NGINX reverse proxy that handles internal routing:

### Dify Port Mapping

| Component         | Internal Port | Dify NGINX Route | Purpose                  |
|-------------------|---------------|------------------|--------------------------|
| Dify API          | 5001          | /api             | Backend API              |
| Dify Web          | 3000          | /                | Frontend interface       |
| PostgreSQL        | 5432          | N/A              | Database (direct)        |
| Redis             | 6379          | N/A              | Cache (direct)           |
| Weaviate          | 8080          | N/A              | Vector DB (direct)       |
| Sandbox           | 8194          | /sandbox         | Code execution           |

### How Dify NGINX Works
External Request → Platform NGINX:8443 → /dify → Dify NGINX:80 → Internal Services

**Example Flow:**
https://tailscale-ip:8443/dify/api/workspaces
          ↓
Platform NGINX (routes /dify/)
          ↓
Dify container port 80 (internal NGINX)
          ↓
Dify NGINX routes /api/ to dify-api:5001
          ↓
Dify API service responds

---

## Docker Network Configuration

### Network: ai-platform
- **Subnet:** 172.20.0.0/16
- **Gateway:** 172.20.0.1
- **Driver:** bridge
- **Internal:** No (allows external connectivity)

### Static IP Assignments

| Service        | IP Address    | Hostname        |
|----------------|---------------|-----------------|
| nginx          | 172.20.0.2    | nginx           |
| ollama         | 172.20.0.10   | ollama          |
| litellm        | 172.20.0.11   | litellm         |
| anythingllm    | 172.20.0.20   | anythingllm     |
| clawdbot       | 172.20.0.21   | clawdbot        |
| dify-nginx     | 172.20.0.30   | dify-nginx      |
| dify-api       | 172.20.0.31   | dify-api        |
| dify-worker    | 172.20.0.32   | dify-worker     |
| dify-db        | 172.20.0.33   | dify-db         |
| dify-redis     | 172.20.0.34   | dify-redis      |
| dify-weaviate  | 172.20.0.35   | dify-weaviate   |
| n8n            | 172.20.0.40   | n8n             |
| signal-api     | 172.20.0.50   | signal-api      |
| gdrive         | 172.20.0.60   | gdrive          |

**Service Discovery:** All services can reach each other using hostname (e.g., `http://ollama:11434`)

---

## Security Configuration

### 1. Network Layer Security (AWS)

```yaml
Security Group Rules:
  Inbound:
    - Port: 22/tcp
      Source: YOUR_IP/32
      Description: SSH access (whitelisted IP)
    
    - Port: 41641/udp
      Source: 0.0.0.0/0
      Description: Tailscale VPN (encrypted)
  
  Outbound:
    - All traffic allowed (for updates, API calls)
