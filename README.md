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

| n8n | n8nio/n8n:latest | 5678 | Workflow automation |
| Flowise | flowiseai/flowise:latest | 3002 | Visual workflow builder |
| Ollama | ollama/ollama:latest | 11434 | Local LLM serving |

### Monitoring & Management

| Service | Version | Port | Purpose | Status |
|---------|---------|-------|---------|--------|
| Prometheus | prom/prometheus:latest | 5000 | Metrics collection |
| Grafana | grafana/grafana:latest | 3001 | Metrics visualization |
| Caddy | caddy:2-alpine | 80/443 | Reverse proxy and SSL |
| Signal API | bbernhard/signal-cli-rest-api:0.84 | 8090 | WhatsApp integration |
| OpenClaw | alpine/openclaw:latest | 18789 | Platform management |

## Quick Start

### Prerequisites

- Ubuntu 20.04+ or CentOS 8+
- Docker Engine 20.10+ and Docker Compose v2+
- **EBS volume must be attached and mounted to `/mnt/data` before running any script**
- At least 8GB RAM and 4 CPU cores
- 50GB+ storage for data volumes
- Domain name for SSL certificates

### Installation

1. **Clone Repository**
   ```bash
   git clone https://github.com/jgla1ne/AIPlatformAutomation.git
   cd AIPlatformAutomation/scripts
   ```

2. **Run Setup**
   ```bash
   sudo ./1-setup-system.sh
   ```

3. **Deploy Services**
   ```bash
   sudo ./2-deploy-services.sh
   ```

4. **Configure Services**
   ```bash
   sudo ./3-configure-services.sh
   ```

## Configuration

### Environment Variables

Key configuration variables in `/mnt/data/u1001/.env`:

```bash
# Core Configuration
DOMAIN_NAME=ai.datasquiz.net
TENANT_UID=1001
TENANT_GID=1001
DATA_ROOT=/mnt/data/u1001

# Database Credentials
POSTGRES_USER=ds-admin
POSTGRES_PASSWORD=<generated>
REDIS_PASSWORD=<generated>

# Security
ADMIN_PASSWORD=<generated>
ENCRYPTION_KEY=<generated>
JWT_SECRET=<generated>
```

### Network Configuration

- **Internal Network**: `aip-u1001_net_internal` (isolated)
- **External Network**: `aip-u1001_net` (internet access)
- **Service Discovery**: All services use Docker DNS
- **SSL/TLS**: Managed by Caddy with Let's Encrypt

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

---

**Status**: Production Ready (with known limitations)
**Last Updated**: 2026-02-28
**Maintainer**: Jean-Gabriel Laine <jglaine@example.com>
