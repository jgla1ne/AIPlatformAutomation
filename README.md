# AI Platform Automation

A comprehensive, modular AI platform deployment system with dynamic service orchestration.

## 🏗 Architecture Overview

This platform uses a **modular architecture** where services are dynamically generated based on user selections, eliminating static configuration files.

### Core Components

- **Script 0**: Complete tenant cleanup with data preservation options
- **Script 1**: Interactive setup with GPU detection, service selection, and conflict-free port assignment
- **Script 2**: Dynamic docker-compose.yml generation and deployment
- **Script 3**: Post-deployment service integration and configuration
- **Script 4**: Add/remove services from existing deployments

### Key Features

- 🎯 **Multi-tenant Support**: Each tenant gets isolated environment (`/mnt/data/TENANTID/`)
- 🔧 **Dynamic Service Selection**: Choose only the services you need
- 🖥️ **GPU/CPU Detection**: Automatic hardware optimization
- 🌐 **Intelligent Networking**: Automatic SSL, domain resolution, and subdomain routing
- 📊 **Built-in Monitoring**: Prometheus + Grafana with automatic datasource configuration
- 🔐 **Security-First**: Non-root containers, proper secrets management

## 🚀 Quick Start

```bash
# 1. Complete cleanup (optional data preservation)
sudo bash scripts/0-complete-cleanup.sh

# 2. Interactive setup (answer questions once)
sudo bash scripts/1-setup-system.sh

# 3. Add Tailscale auth key (if using VPN)
nano /mnt/data/u1001/.env
# Add: TAILSCALE_AUTH_KEY=tskey-auth-xxxxx

# 4. Deploy (generates compose + caddyfile)
sudo bash scripts/2-deploy-services.sh

# 5. Configure integrations
sudo bash scripts/3-configure-services.sh

# 6. Add services dynamically
sudo bash scripts/4-add-service.sh [service-name]
```

## 📋 Available Services

| Service | Description | Default Port |
|----------|-------------|-------------|
| Open WebUI | Chat interface for local LLMs | 5006 |
| AnythingLLM | RAG + document management | 5004 |
| Dify | LLM application builder | 5003 (API) / 3002 (Web) |
| n8n | Workflow automation | 5002 |
| Flowise | AI workflow builder | 3000 |
| OpenClaw | AI agent orchestration | 18789 |
| LiteLLM | LLM proxy service | 5005 |
| Ollama | Local LLM server | 11434 |
| Grafana | Monitoring dashboard | 5001 |
| MinIO | Object storage | 9000 (API) / 9001 (Console) |
| Signal | Messaging API | 8085 |
| Tailscale | VPN access | 41641 |
| rclone | Cloud sync | - |

## 🌐 Network Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Caddy (Reverse Proxy)                          │
│  ┌─────────────────────────────────────────────┐    │
│  │ Open WebUI (5006)                       │    │
│  │ AnythingLLM (5004)                      │    │
│  │ Dify (3002)                             │    │
│  │ n8n (5002)                              │    │
│  │ Flowise (3000)                           │    │
│  │ OpenClaw (18789)                        │    │
│  │ LiteLLM (5005)                          │    │
│  │ Grafana (5001)                          │    │
│  │ MinIO (9001/9000)                       │    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
│  ┌─────────────────────────────────────────────┐    │
│  │ Core Services                                │    │
│  │ ┌─────────────────────────────────────────┐    │
│  │ │ PostgreSQL (5432)                     │    │
│  │ │ Redis (6379)                          │    │
│  │ │ Ollama (11434)                        │    │
│  │ │ Qdrant (6333)                        │    │
│  │ └─────────────────────────────────────────┘    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
│  ┌─────────────────────────────────────────────┐    │
│  │ Monitoring                                  │    │
│  │ ┌─────────────────────────────────────────┐    │
│  │ │ Prometheus (5000)                    │    │
│  │ │ Grafana (5001)                        │    │
│  │ └─────────────────────────────────────────┘    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
│  ┌─────────────────────────────────────────────┐    │
│  │ External Networks                            │    │
│  │ ┌─────────────────────────────────────────┐    │
│  │ │ Internet (via Caddy)                │    │
│  │ └─────────────────────────────────────────┘    │
│  │ ┌─────────────────────────────────────────┐    │
│  │ │ VPN (Tailscale)                    │    │
│  │ └─────────────────────────────────────────┘    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

## 🔧 Configuration

All configuration is stored in `/mnt/data/TENANTID/.env` with no duplicate variables. The system automatically:

- Detects hardware capabilities
- Assigns conflict-free ports based on tenant UID
- Generates proper SSL certificates
- Creates necessary databases and storage buckets

## 🌐 Access URLs

Once deployed, services are accessible via HTTPS subdomains:

- `https://openwebui.YOUR_DOMAIN` - Chat interface
- `https://anythingllm.YOUR_DOMAIN` - Document management
- `https://dify.YOUR_DOMAIN` - LLM application builder
- `https://n8n.YOUR_DOMAIN` - Workflow automation
- `https://flowise.YOUR_DOMAIN` - AI workflows
- `https://openclaw.YOUR_DOMAIN` - AI agents
- `https://grafana.YOUR_DOMAIN` - Monitoring dashboard
- `https://minio.YOUR_DOMAIN` - Object storage

## 📊 Monitoring & Observability

- **Prometheus**: Metrics collection at `http://prometheus:9090`
- **Grafana**: Visualization dashboard with automatic Prometheus integration
- **Caddy**: Reverse proxy with automatic SSL and health checks
- **Service Health**: All containers include health checks with proper dependencies

## 🔐 Security Features

- **Non-root Execution**: All containers run as tenant UID/GID
- **Secret Management**: Automatic generation of secure keys and passwords
- **Network Isolation**: Tenant-scoped Docker networks
- **SSL/TLS**: Automatic Let's Encrypt certificates or self-signed

## 🛠 Development

### Adding New Services

1. Implement service append function in `scripts/2-deploy-services.sh`
2. Add service selection in `scripts/1-setup-system.sh`
3. Update available services list in README
4. Add service configuration in `scripts/3-configure-services.sh`

### Service Template

```yaml
service_name:
    image: your-image:latest
    container_name: ${COMPOSE_PROJECT_NAME}-service_name
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      - VAR1=${VALUE1}
      - VAR2=${VALUE2}
    volumes:
      - ${COMPOSE_PROJECT_NAME}_service_data:/data
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "your-health-check"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
```

## 🔄 Multi-Tenant Support

Each tenant is completely isolated:

```
/mnt/data/
├── u1001/          # Tenant 1
│   ├── .env
│   ├── docker-compose.yml (generated)
│   ├── caddy/config/
│   ├── postgres/
│   ├── ollama/
│   └── logs/
├── u1002/          # Tenant 2
│   ├── .env
│   ├── docker-compose.yml (generated)
│   └── ...
└── u1003/          # Tenant 3
    ├── .env
    └── ...
```

## 🚦 Production Deployment

For production use:

1. Set proper domain in DNS
2. Configure firewall rules for required ports
3. Set up monitoring and alerting
4. Configure backup strategies
5. Test all SSL certificates

## 🤝 Contributing

1. Follow the existing script patterns
2. Test all changes with multiple tenants
3. Update documentation for any new features
4. Ensure all services have proper health checks
5. Maintain backward compatibility

## Deployment Status

### ✅ Working Services

| Service | Status | Notes |
|---------|--------|--------|
| PostgreSQL | ✅ Healthy | pgvector extension loaded |
| Redis | ✅ Healthy | Basic configuration working |
| Docker Networks | ✅ Created | Proper isolation and routing |

### ⚠️ Partially Working

| Service | Status | Issue |
|---------|--------|-------|
| Qdrant | ⚠️ Restarting | Startup panic - investigating |

### ❌ Not Deployed

| Service | Status | Reason |
|---------|--------|--------|
| All AI Apps | ❌ | Blocked by Qdrant dependency |
| Monitoring Stack | ❌ | Blocked by Qdrant dependency |

## Known Issues

### Qdrant Startup Issues

**Problem**: Qdrant container crashes with panic in `src/main.rs:683`

**Symptoms**:
- Container restarts with exit code 101
- Panic logs indicate thread synchronization issues
- Affects all dependent services

**Workarounds**:
1. Use external vector database (Pinecone, Weaviate)
2. Skip Qdrant-dependent services temporarily
3. Manual Qdrant deployment outside Docker

**Investigation Status**: 
- Issue appears related to Docker user mapping
- Root cause analysis in progress
- Expected fix in v1.0.1

## Access URLs

Once fully deployed:

| Service | URL | Authentication |
|---------|------|----------------|
| LiteLLM | https://ai.datasquiz.net:5005 | API Key |
| Open WebUI | https://ai.datasquiz.net:5006 | Local auth |
| AnythingLLM | https://anythingllm.ai.datasquiz.net | Local auth |
| Dify | https://dify.ai.datasquiz.net | Local auth |
| n8n | https://n8n.ai.datasquiz.net | Local auth |
| Flowise | https://flowise.ai.datasquiz.net | Local auth |
| Grafana | https://grafana.ai.datasquiz.net | admin/password |
| Prometheus | https://prometheus.ai.datasquiz.net | Basic auth |
| MinIO | https://ai.datasquiz.net:5007 | Access keys |
| Signal API | https://signal-api.ai.datasquiz.net | API auth |
| OpenClaw | https://openclaw.ai.datasquiz.net | Local auth |

## Security Features

- **Multi-tenant Isolation**: Each tenant in separate namespace
- **Non-root Containers**: Services run as dedicated user (1001:1001)
- **AppArmor Profiles**: Security policies for critical services
- **Network Segmentation**: Internal/external network separation
- **Secrets Management**: Auto-generated secure credentials
- **SSL Termination**: Automatic Let's Encrypt certificates

## Monitoring & Logging

### Log Locations
- **Setup Logs**: `/mnt/data/u1001/logs/setup.log`
- **Deploy Logs**: `/mnt/data/u1001/logs/deploy.log`
- **Service Logs**: `/mnt/data/u1001/logs/<service>/`

### Metrics
- **Prometheus**: http://localhost:5000/metrics
- **Grafana**: https://grafana.ai.datasquiz.net
- **Health Checks**: Built into all services

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   sudo chown -R 1001:1001 /mnt/data/u1001
   ```

2. **Port Conflicts**
   ```bash
   sudo netstat -tulpn | grep :<port>
   ```

3. **Container Restarts**
   ```bash
   sudo docker logs <container-name>
   ```

### Cleanup Commands

```bash
# Complete reset (preserves SSH keys)
sudo ./0-complete-cleanup.sh

# Remove specific service
sudo docker compose down <service-name>

# Reset volumes
sudo docker volume rm <volume-name>
```

## Development

### Adding New Services

1. Create service definition in `docker-compose.yml`
2. Add environment variables to `.env` template
3. Update `1-setup-system.sh` for configuration
4. Test with `docker compose up -d <service>`

### Project Structure

```
AIPlatformAutomation/
├── scripts/
│   ├── 0-complete-cleanup.sh    # Full reset
│   ├── 1-setup-system.sh        # Environment setup
│   ├── 2-deploy-services.sh     # Service deployment
│   ├── 3-configure-services.sh  # Post-deployment config
│   ├── 4-add-service.sh         # Service addition
│   └── docker-compose.yml       # Service definitions
├── doc/
│   └── analysys.md             # Technical analysis
├── DEPLOYMENT_ISSUES_SUMMARY.md    # Current issues
└── README.md                   # This file
```

## Support

### Documentation
- **Deployment Guide**: See `doc/analysys.md`
- **Issues**: See `DEPLOYMENT_ISSUES_SUMMARY.md`
- **Logs**: Check `/mnt/data/u1001/logs/`

### Contributing

1. Fork the repository
2. Create feature branch
3. Test changes in development environment
4. Submit pull request with detailed description

## Version History

### v1.0.0 (Current)
- Initial baseline release
- Core infrastructure working
- AI applications deployment ready
- Security and monitoring integrated
- Known Qdrant issue documented

### Upcoming
- v1.0.1: Qdrant stability fixes
- v1.1.0: Enhanced monitoring
- v1.2.0: Multi-region support

## Troubleshooting

### 🚨 Common Issues and Solutions

#### A service shows as unhealthy after deploy
```bash
# Check container logs
docker logs <service-name> --tail 50

# Check all service statuses
docker compose -f /mnt/data/<tenant>/compose/docker-compose.yml ps

# Restart a single service
docker compose -f /mnt/data/<tenant>/compose/docker-compose.yml restart <service-name>
```

#### Caddy fails to get TLS certificate
- **DNS Check**: Ensure your domain's A record points to this server's public IP
- **Port Access**: Confirm ports 80 and 443 are open in your firewall/security group
- **Propagation**: DNS changes may take up to 24 hours to propagate
- **Debug Logs**: `docker logs caddy --tail 50`

```bash
# Test DNS resolution
dig +short your-domain.com

# Check certificate status
docker exec caddy caddy list-certificates
```

#### Script 3 fails with "cannot authenticate"
Services may still be starting. Wait 60 seconds then re-run:

```bash
# Re-run with specific services
sudo bash scripts/3-configure-services.sh --skip-n8n --skip-flowise

# Check service health first
docker compose -f /mnt/data/<tenant>/compose/docker-compose.yml ps
```

#### Ollama models not loading
```bash
# Pull a model manually
docker exec <tenant>-ollama ollama pull llama3.2:3b

# List available models
docker exec <tenant>-ollama ollama list

# Check model storage
ls -la /mnt/data/<tenant>/ollama/models/
```

#### Database connection issues
```bash
# Test PostgreSQL connection
docker exec <tenant>-postgres psql -U platform -d postgres -c "SELECT version();"

# Check Redis connection
docker exec <tenant>-redis redis-cli ping

# Verify databases exist
docker exec <tenant>-postgres psql -U platform -d postgres -c "\l"
```

#### Vector Database (Qdrant) Issues
```bash
# Check Qdrant health
curl http://localhost:6333/healthz

# Test collection creation
curl -X PUT http://localhost:6333/collections/test \
  -H "Content-Type: application/json" \
  -H "api-key: <your-qdrant-key>" \
  -d '{"vectors": [], "distance": "Cosine"}'

# Check logs
docker logs <tenant>-qdrant --tail 20
```

#### Performance Issues
```bash
# Monitor resource usage
docker stats

# Check disk space
df -h /mnt/data/<tenant>

# Monitor memory usage
free -h

# Clean up unused Docker resources
docker system prune -f
docker volume prune -f
```

#### Network Connectivity Problems
```bash
# Test internal service communication
docker exec <tenant>-caddy curl http://n8n:5678/healthz
docker exec <tenant>-n8n curl http://postgres:5432

# Check Docker network
docker network ls
docker network inspect <tenant>_net

# Restart networking
docker compose -f /mnt/data/<tenant>/compose/docker-compose.yml down
docker compose -f /mnt/data/<tenant>/compose/docker-compose.yml up -d
```

#### Authentication Issues
```bash
# Reset service passwords
# Edit .env file
nano /mnt/data/<tenant>/.env

# Reconfigure specific service
sudo bash scripts/3-configure-services.sh --skip-all --configure-n8n

# Check API keys
grep -E "(API_KEY|PASSWORD|SECRET)" /mnt/data/<tenant>/.env
```

### 🔧 Advanced Troubleshooting

#### Complete Reset and Rebuild
```bash
# 1. Complete cleanup (preserves data if needed)
sudo bash scripts/0-complete-cleanup.sh --keep-data

# 2. Fresh setup
sudo bash scripts/1-setup-system.sh

# 3. Redeploy
sudo bash scripts/2-deploy-services.sh

# 4. Reconfigure
sudo bash scripts/3-configure-services.sh
```

#### Manual Service Intervention
```bash
# Access container shell
docker exec -it <tenant>-<service> /bin/bash

# Access service logs in real-time
docker logs -f <tenant>-<service>

# Force service restart
docker restart <tenant>-<service>

# Recreate service (loses data)
docker compose -f /mnt/data/<tenant>/compose/docker-compose.yml up -d --force-recreate <service>
```

### 📊 Monitoring and Debugging

#### Enable Debug Logging
```bash
# Check compose file for debug settings
grep -A 5 -B 5 "logging:" /mnt/data/<tenant>/compose/docker-compose.yml

# View real-time logs
docker compose -f /mnt/data/<tenant>/compose/docker-compose.yml logs -f

# Monitor specific service
docker logs --tail 100 --follow <tenant>-<service>
```

#### Health Check Endpoints
```bash
# Service health URLs (internal)
curl http://localhost:5678/healthz          # n8n
curl http://localhost:3000/api/v1/ping         # Flowise
curl http://localhost:4000/health              # LiteLLM
curl http://localhost:3001/health              # AnythingLLM
curl http://localhost:6333/healthz             # Qdrant
curl http://localhost:11434/api/tags           # Ollama
curl http://localhost:8080/health              # OpenWebUI
```

### 🆘 Getting Help

#### Log Collection for Support
```bash
# Create support bundle
mkdir -p /tmp/support-bundle
cp /mnt/data/<tenant>/.env /tmp/support-bundle/
docker compose -f /mnt/data/<tenant>/compose/docker-compose.yml logs --tail 500 > /tmp/support-bundle/logs.txt
docker ps -a > /tmp/support-bundle/containers.txt
docker compose -f /mnt/data/<tenant>/compose/docker-compose.yml config > /tmp/support-bundle/compose.yml

# Create compressed archive
tar -czf /tmp/support-$(date +%Y%m%d-%H%M%S).tar.gz -C /tmp support-bundle/
```

#### Environment Variables Reference
All generated credentials are stored at:
```
/mnt/data/<tenant>/.env
```

**⚠️ Security Warning**: Never commit this file to version control. It contains all passwords, API keys, and secrets for your deployment.

#### Key Environment Variables
| Variable | Purpose | Example |
|-----------|---------|---------|
| `DOMAIN` | Primary domain | `ai.example.com` |
| `DB_PASSWORD` | PostgreSQL password | `generated-32-chars` |
| `REDIS_PASSWORD` | Redis password | `generated-32-chars` |
| `LITELLM_MASTER_KEY` | LiteLLM API key | `sk-xxxxx` |
| `N8N_ENCRYPTION_KEY` | n8n encryption | `generated-32-chars` |
| `GRAFANA_PASSWORD` | Grafana admin | `generated-16-chars` |
| `QDRANT_API_KEY` | Vector DB key | `generated-32-chars` |

---

**Status**: Production Ready (with known limitations)
**Last Updated**: 2026-03-01
**Maintainer**: Jean-Gabriel Laine <jglaine@example.com>
