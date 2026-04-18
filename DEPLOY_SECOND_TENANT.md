# Deploying Second Tenant - Practical Workaround

## 🚨 Current Situation
- **Tenant 1**: `datasquiz` deployed on `ai.dataquiz.net` using ports 80/443
- **Tenant 2**: Wants to deploy coding stack but faces port conflicts

## 🛠️ Immediate Solutions

### Option 1: Use Different Proxy Ports (Recommended)
```bash
# Deploy second tenant with different Caddy ports
./scripts/1-setup-system.sh tenant2 \
  --base-domain tenant2.example.com \
  --caddy-http-port 8080 \
  --caddy-https-port 8443
```

**Advantages**:
- ✅ No port conflicts with first tenant
- ✅ Independent TLS certificates
- ✅ Full proxy functionality
- ✅ Isolated deployment

### Option 2: Disable Caddy (IP-based Access)
```bash
# Deploy second tenant without reverse proxy
./scripts/1-setup-system.sh tenant2 \
  --base-domain tenant2.example.com \
  --disable-caddy \
  --direct-ip-access
```

**Advantages**:
- ✅ No port conflicts
- ✅ Direct IP access to services
- ✅ Simpler deployment
- ❌ No domain-based access (IP only)

### Option 3: Use Subdomain with Different Ports
```bash
# Deploy with subdomain and port range
./scripts/1-setup-system.sh tenant2 \
  --base-domain ai.tenant2.example.com \
  --port-range-start 3100 \
  --caddy-http-port 8080 \
  --caddy-https-port 8443
```

**Advantages**:
- ✅ No conflicts with first tenant
- ✅ Domain-based access
- ✅ Organized port allocation

## 🎯 Step-by-Step Deployment (Option 1)

### 1. Configure Second Tenant
```bash
echo "=== Configuring Second Tenant ==="
echo "Tenant ID: tenant2"
echo "Domain: tenant2.example.com"
echo "Caddy HTTP Port: 8080"
echo "Caddy HTTPS Port: 8443"
echo "Port Range: 3100-3199"
```

### 2. Run Script 1
```bash
./scripts/1-setup-system.sh tenant2 \
  --base-domain tenant2.example.com \
  --caddy-http-port 8080 \
  --caddy-https-port 8443
```

### 3. Verify Configuration
```bash
echo "=== Verifying Configuration ==="
grep "CADDY_HTTP_PORT" /mnt/tenant2/config/platform.conf
grep "TENANT_ID" /mnt/tenant2/config/platform.conf
```

### 4. Deploy Services
```bash
./scripts/2-deploy-services.sh tenant2
```

### 5. Verify Deployment
```bash
echo "=== Verifying Deployment ==="
docker ps | grep tenant2
curl -I http://tenant2.example.com:8080
```

## 🔍 Port Allocation Table

| Tenant | Domain | Caddy HTTP | Caddy HTTPS | Port Range | Status |
|--------|---------|-------------|--------------|------------|--------|
| datasquiz | ai.dataquiz.net | 80 | 443 | 3000-3099 | ✅ Deployed |
| tenant2 | tenant2.example.com | 8080 | 8443 | 3100-3199 | 🔄 Ready to deploy |

## ⚠️ Important Notes

### Service Access URLs
After deployment, second tenant services will be accessible at:
- **OpenWebUI**: http://tenant2.example.com:8080 → http://127.0.0.1:3000
- **LiteLLM**: http://tenant2.example.com:8080/api → http://127.0.0.1:4000
- **Code Server**: http://tenant2.example.com:8080/code → http://127.0.0.1:8080

### TLS Certificates
- **First Tenant**: Certificate for `ai.dataquiz.net`
- **Second Tenant**: Certificate for `tenant2.example.com`
- **No Conflicts**: Separate certificates, separate Caddy instances

### Inter-Tenant Communication
Services are isolated by design. To enable communication:
1. **Shared Services**: Deploy monitoring, logging in shared namespace
2. **API Gateway**: Implement tenant-to-tenant service discovery
3. **VPN**: Set up private network between tenants

## 🚀 Deployment Commands

### Quick Deploy (Option 1)
```bash
# One-liner for second tenant
./scripts/1-setup-system.sh tenant2 --base-domain tenant2.example.com --caddy-http-port 8080 --caddy-https-port 8443 && ./scripts/2-deploy-services.sh tenant2
```

### Verify Both Tenants
```bash
echo "=== Both Tenants Status ==="
echo "Tenant 1 (datasquiz):"
curl -s http://ai.dataquiz.net | head -1
echo "Tenant 2 (tenant2):"
curl -s http://tenant2.example.com:8080 | head -1
echo ""
echo "Port Usage:"
ss -tlnp | grep ":80\|:443\|:8080\|:8443"
```

This approach allows immediate deployment of the second tenant while maintaining complete isolation from the first tenant.
