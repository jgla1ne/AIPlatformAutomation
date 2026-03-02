# AI Platform Service Status Table

**Generated:** March 2, 2026  
**Purpose:** Comprehensive service status with URLs, listening status, access methods, and health response handling

---

## 🌐 Service URLs Summary

| Service | External HTTPS URL | Local Port | Internal URL | Tailscale URL | Status |
|----------|-------------------|-------------|-------------|---------------|--------|
| n8n | https://n8n.${DOMAIN} | 5678 | http://localhost:5678 | http://${TAILSCALE_IP:-N/A}:5678 | 🟢 |
| Flowise | https://flowise.${DOMAIN} | 3000 | http://localhost:3000 | http://${TAILSCALE_IP:-N/A}:3000 | 🟢 |
| OpenWebUI | https://chat.${DOMAIN} | 8080 | http://localhost:8080 | http://${TAILSCALE_IP:-N/A}:8080 | 🟢 |
| AnythingLLM | https://anythingllm.${DOMAIN} | 3001 | http://localhost:3001 | http://${TAILSCALE_IP:-N/A}:3001 | 🟢 |
| LiteLLM | https://litellm.${DOMAIN} | 4000 | http://localhost:4000 | http://${TAILSCALE_IP:-N/A}:4000 | 🟡 |
| Grafana | https://grafana.${DOMAIN} | 3002 | http://localhost:3002 | http://${TAILSCALE_IP:-N/A}:3002 | 🟢 |
| Ollama | N/A (API only) | 11434 | http://localhost:11434 | N/A | 🟡 |
| Qdrant | N/A (API only) | 6333 | http://localhost:6333 | N/A | 🟡 |
| Authentik | https://auth.${DOMAIN} | 9000 | http://localhost:9000 | http://${TAILSCALE_IP:-N/A}:9000 | 🟢 |
| MinIO | https://minio.${DOMAIN} | 9000 | http://localhost:9000 | http://${TAILSCALE_IP:-N/A}:9000 | 🟢 |
| Prometheus | https://prometheus.${DOMAIN} | 9090 | http://localhost:9090 | N/A | 🟢 |
| Signal API | N/A (API only) | 8080 | http://localhost:8080 | N/A | 🟢 |
| OpenClaw | https://openclaw.${DOMAIN} | ${OPENCLAW_PORT} | http://localhost:${OPENCLAW_PORT} | http://${TAILSCALE_IP:-N/A}:${OPENCLAW_PORT} | 🔴 |
| Caddy | https://${DOMAIN} | 80/443 | N/A | N/A | 🟢 |
| PostgreSQL | N/A (internal) | 5432 | N/A | N/A | 🟢 |
| Redis | N/A (internal) | 6379 | N/A | N/A | 🟢 |

---

## 📊 Listening Status Details

### **Internal Services (Docker Network)**
- **PostgreSQL**: Listening on port 5432 (internal only)
- **Redis**: Listening on port 6379 (internal only)
- **Caddy**: Listening on ports 80, 443 (external) + 2019 (admin)

### **External Services (Internet-Facing)**
- **n8n**: Port 5678 (external via Caddy)
- **Flowise**: Port 3000 (external via Caddy)
- **OpenWebUI**: Port 8080 (external via Caddy)
- **AnythingLLM**: Port 3001 (external via Caddy)
- **LiteLLM**: Port 4000 (external via Caddy)
- **Grafana**: Port 3002 (external via Caddy)
- **Authentik**: Port 9000 (external via Caddy)
- **MinIO**: Port 9000 (external via Caddy)
- **Prometheus**: Port 9090 (external via Caddy)

### **API-Only Services**
- **Ollama**: Port 11434 (API endpoint, no web UI)
- **Qdrant**: Port 6333 (API endpoint, no web UI)
- **Signal API**: Port 8080 (API endpoint, no web UI)

---

## 🔒 Access Methods

### **External Access (Public Internet)**
```bash
# Access via HTTPS with valid SSL certificates
curl -k https://n8n.${DOMAIN}/healthz
curl -k https://flowise.${DOMAIN}/api/v1/ping
curl -k https://chat.${DOMAIN}/health
curl -k https://anythingllm.${DOMAIN}/api/ping
curl -k https://litellm.${DOMAIN}/health
curl -k https://grafana.${DOMAIN}/api/health
```

### **Tailscale VPN Access (Private Network)**
```bash
# Access when Tailscale is enabled and authenticated
curl -k http://${TAILSCALE_IP}:5678  # n8n
curl -k http://${TAILSCALE_IP}:3000  # Flowise
curl -k http://${TAILSCALE_IP}:8080  # OpenWebUI
curl -k http://${TAILSCALE_IP}:3001  # AnythingLLM
curl -k http://${TAILSCALE_IP}:4000  # LiteLLM
curl -k http://${TAILSCALE_IP}:3002  # Grafana
```

### **Local Internal Access (Development/Debugging)**
```bash
# Direct access on the host machine
curl -k http://localhost:5678/healthz     # n8n
curl -k http://localhost:3000/api/v1/ping   # Flowise
curl -k http://localhost:8080/health       # OpenWebUI
curl -k http://localhost:3001/api/ping      # AnythingLLM
curl -k http://localhost:4000/health        # LiteLLM
curl -k http://localhost:3002/api/health     # Grafana
curl -k http://localhost:11434/api/tags     # Ollama API
curl -k http://localhost:6333/health        # Qdrant API
curl -k http://localhost:8080              # Signal API
```

---

## 🏥 Health Response Handling

### **Expected HTTP Status Codes**
| Status Code | Meaning | Service Examples |
|-------------|---------|------------------|
| 200 | OK | n8n, Flowise, OpenWebUI, AnythingLLM, Grafana |
| 301 | Redirect | Caddy (HTTP→HTTPS) |
| 302 | Found | Authentik login redirects |
| 400 | Bad Request | Invalid API calls |
| 401 | Unauthorized | Missing/invalid API keys |
| 403 | Forbidden | Permission denied |
| 404 | Not Found | Invalid endpoints |
| 500 | Server Error | Service internal failures |
| 502 | Bad Gateway | Upstream service unavailable |
| 503 | Service Unavailable | Service starting/maintenance |

### **Expected Health Endpoints**
| Service | Health Check Endpoint | Expected Response |
|---------|-------------------|------------------|
| n8n | `/healthz` | `{"status": "ok"}` |
| Flowise | `/api/v1/ping` | `{"status": "ok"}` |
| OpenWebUI | `/health` | `{"status": "healthy"}` |
| AnythingLLM | `/api/ping` | `{"status": "ok"}` |
| LiteLLM | `/health` | `{"status": "ok"}` |
| Grafana | `/api/health` | `{"status": "ok"}` |
| Ollama | `/api/tags` | JSON model list |
| Qdrant | `/health` | `{"status": "ok"}` |
| Caddy | N/A (admin interface) | Valid config page |
| PostgreSQL | N/A (internal) | Connection acceptance |
| Redis | N/A (internal) | PING response |

### **Body Response Examples**
```json
// Successful health check response
{
  "status": "ok",
  "timestamp": "2026-03-02T12:00:00Z",
  "version": "1.0.0",
  "uptime": "2h 15m 30s"
}

// Service with additional info
{
  "status": "ok",
  "version": "1.0.0",
  "services": {
    "database": "connected",
    "cache": "connected",
    "api": "healthy"
  }
}

// Error response
{
  "error": "Service temporarily unavailable",
  "code": "503",
  "message": "Service is starting up"
}
```

---

## 🔍 Service Dependencies

### **Service Startup Order**
1. **Infrastructure First**: PostgreSQL, Redis, Caddy
2. **Vector DB**: Qdrant (if enabled)
3. **Core Services**: LiteLLM, n8n
4. **User Interfaces**: OpenWebUI, Flowise, AnythingLLM, Grafana
5. **AI Runtime**: Ollama (if enabled)
6. **Monitoring**: Prometheus
7. **Security**: Authentik, Tailscale, OpenClaw

### **Network Flow**
```
Internet Request → Caddy (80/443) → Docker Network → Service
                                    ↓
                                 Internal Request → Service (if needed) → Docker Network → Caddy → Internet Response
```

---

## 📱 Quick Reference Commands

### **Check All Service Status**
```bash
# Docker container status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Service health checks
for service in n8n flowise openwebui anythingllm litellm grafana; do
    echo "Checking $service..."
    curl -k https://$service.${DOMAIN}/health || echo "FAILED"
done

# Detailed service info
docker compose -f /mnt/data/${TENANT_ID}/docker-compose.yml ps
```

### **Access Specific Service**
```bash
# n8n workflow access
curl -k -X POST "https://n8n.${DOMAIN}/api/v1/workflows" \
  -H "Authorization: Bearer ${N8N_API_KEY}" \
  -H "Content-Type: application/json"

# Ollama model management
curl -X POST http://localhost:11434/api/pull \
  -H "Content-Type: application/json" \
  -d '{"name": "llama3.2:1b"}'

# Qdrant vector operations
curl -X GET http://localhost:6333/collections \
  -H "API-Key: ${QDRANT_API_KEY}"

# Flowise AI workflow
curl -X POST https://flowise.${DOMAIN}/api/v1/predictions \
  -H "Authorization: Bearer ${FLOWISE_PASSWORD}" \
  -H "Content-Type: application/json" \
  -d '{"question": "What is AI?"}'
```

---

## 🚨 Troubleshooting

### **Common Issues & Solutions**

| Issue | Symptoms | Solution |
|--------|-------------|----------|
| Service not accessible | DNS not propagated | Wait 5-10 minutes for DNS, check `dig +short ${DOMAIN}` |
| SSL certificate errors | Port 80/443 blocked | Open EC2 security group, ensure inbound rules allow HTTP/HTTPS |
| Service unhealthy | Database migrations | Wait for initialization, check logs: `docker logs ${service}` |
| API 401 errors | Invalid credentials | Check .env file, regenerate keys: `sudo bash scripts/1-setup-system.sh` |
| Connection refused | Service not started | Check service order: `docker ps -a`, ensure dependencies running |
| Memory issues | OOM kills | Add swap: `sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile` |
| Disk space issues | Volume full | Clean up: `docker system prune -af --volumes` |

### **Health Check Script**
```bash
#!/bin/bash
# Comprehensive health check script
DOMAIN="your-domain.com"
TAILSCALE_IP="100.x.x.x"  # From .env or tailscale ip -4

services=("n8n" "flowise" "openwebui" "anythingllm" "litellm" "grafana")

echo "🔍 Checking service health..."
for service in "${services[@]}"; do
    echo -n "Testing $service... "
    
    # External HTTPS check
    if curl -k -s --max-time 10 "https://$service.$DOMAIN/health" >/dev/null 2>&1; then
        echo "✅ External OK"
    else
        echo "❌ External FAILED"
    fi
    
    # Local check
    if curl -s --max-time 10 "http://localhost:$port/health" >/dev/null 2>&1; then
        echo "✅ Local OK"
    else
        echo "❌ Local FAILED"
    fi
    
    # Tailscale check (if available)
    if [ -n "$TAILSCALE_IP" ]; then
        if curl -s --max-time 10 "http://$TAILSCALE_IP:$port/health" >/dev/null 2>&1; then
            echo "✅ Tailscale OK"
        else
            echo "❌ Tailscale FAILED"
        fi
    else
        echo "➖ Tailscale N/A"
    fi
done
```

---

**Status Legend:**
- 🟢 **Healthy**: Service responding correctly on all access methods
- 🟡 **Starting**: Service initializing (normal for first deployment)
- 🔴 **Unhealthy**: Service failing (requires investigation)
- 🔴 **Disabled**: Service not enabled in configuration

---

## 📋 Usage Notes

### **For Development**
- Use local URLs (http://localhost:port) for faster access during development
- Check service logs: `docker logs -f service-name`
- Restart individual services: `docker restart service-name`

### **For Production**
- Always use HTTPS URLs for security
- Monitor SSL certificate expiry
- Use Tailscale for secure administrative access
- Set up monitoring alerts for service health

### **Security Considerations**
- Change default passwords before first production use
- Use API keys instead of passwords where possible
- Enable firewalls to restrict access to necessary ports only
- Regularly update services and dependencies
- Monitor Docker logs for unusual activity
