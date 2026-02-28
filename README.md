# AI Platform Automation

🚀 **Multi-Tenant AI Platform Infrastructure with Zero-Trust Security**

## 📋 Overview

This project provides a comprehensive, production-ready AI platform automation system that deploys a modular AI stack with vector databases, authentication, and secure networking. Built for AWS with EBS storage, Docker Compose orchestration, and multi-tenant isolation.

## 🏗️ Architecture Overview

### Core Principles

1. **Multi-Tenant Isolation**: Each tenant runs with dedicated UID/GID, storage, and network namespaces
2. **Zero-Trust Security**: All services run as non-root users with AppArmor hardening
3. **Modular AI Stack**: Pluggable AI services with shared vector databases
4. **Secure Networking**: Tailscale VPN + OpenClaw for internal/external access
5. **Infrastructure as Code**: Complete automation with state management and rollback

### Key Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    AI Platform Architecture                    │
├─────────────────────────────────────────────────────────────────┤
│  Public Internet                                             │
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │
│  │    Caddy    │    │  Traefik    │    │ Nginx Proxy │      │
│  │  (Reverse   │    │  (Reverse   │    │   Manager   │      │
│  │   Proxy)    │    │   Proxy)    │    │             │      │
│  └─────────────┘    └─────────────┘    └─────────────┘      │
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              AI Services Layer                             ││
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐        ││
│  │  │ Open WebUI  │ │ AnythingLLM │ │    Dify     │        ││
│  │  │   (Chat)    │ │ (Workspace) │ │ (Platform)  │        ││
│  │  └─────────────┘ └─────────────┘ └─────────────┘        ││
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐        ││
│  │  │    n8n      │ │   Flowise   │ │   Ollama    │        ││
│  │  │ (Workflows) │ │ (AI Flows)  │ │ (LLM Host)  │        ││
│  │  └─────────────┘ └─────────────┘ └─────────────┘        ││
│  └─────────────────────────────────────────────────────────────┘│
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │            Vector Database Layer                            ││
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐        ││
│  │  │   Qdrant    │ │   Chroma    │ │  Weaviate   │        ││
│  │  │ (Vector DB) │ │ (Vector DB) │ │ (Vector DB) │        ││
│  │  └─────────────┘ └─────────────┘ └─────────────┘        ││
│  └─────────────────────────────────────────────────────────────┘│
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │            Infrastructure Layer                             ││
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐        ││
│  │  │ PostgreSQL  │ │    Redis    │ │    MinIO    │        ││
│  │  │ (Metadata)  │ │  (Cache)    │ │  (Storage)  │        ││
│  │  └─────────────┘ └─────────────┘ └─────────────┘        ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              Security & Networking                         ││
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐        ││
│  │  │  Tailscale  │ │  OpenClaw   │ │  AppArmor   │        ││
│  │  │    (VPN)    │ │  (Security) │ │(Hardening) │        ││
│  │  └─────────────┘ └─────────────┘ └─────────────┘        ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Network Topology                           │
├─────────────────────────────────────────────────────────────────┤
│                                                             │
│  Public Internet                                             │
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────┐    HTTPS (443/80)                         │
│  │   Domain    │ ◄─────────────────────────────────────────── │
│  │  (DNS)     │                                            │
│  └─────────────┘                                            │
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────┐    ┌─────────────┐                         │
│  │    Caddy    │    │  Traefik    │                         │
│  │  (Public)   │    │  (Public)   │                         │
│  └─────────────┘    └─────────────┘                         │
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              Docker Network                                ││
│  │  aiplatform_default (Tenant Isolated)                    ││
│  └─────────────────────────────────────────────────────────────┘│
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              AI Services                                  ││
│  │  Open WebUI, AnythingLLM, Dify, n8n, Flowise, Ollama     ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              Tailscale Network                            ││
│  │  100.x.x.x/24 (Private VPN)                            ││
│  └─────────────────────────────────────────────────────────────┘│
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────┐    ┌─────────────┐                         │
│  │  OpenClaw   │    │  Internal   │                         │
│  │ (Security)  │    │  Services   │                         │
│  └─────────────┘    └─────────────┘                         │
└─────────────────────────────────────────────────────────────────┘
```

## 📁 Directory Structure

```
AIPlatformAutomation/
├── scripts/                          # Core automation scripts
│   ├── 0-reset-tenant.sh             # Reset tenant configuration
│   ├── 1-setup-system.sh             # Main setup and configuration
│   ├── 2-deploy-services.sh         # Deploy AI services stack
│   ├── 3-configure-services.sh       # Post-deployment configuration
│   ├── 4-add-service.sh             # Add new services dynamically
│   └── docker-compose.yml           # Service definitions
├── doc/                             # Documentation
│   └── analysis.md                  # Technical analysis document
├── templates/                        # Configuration templates
│   ├── apparmor/                    # AppArmor profiles
│   ├── nginx/                       # Nginx configurations
│   └── systemd/                     # Service definitions
├── tests/                           # Test suites
└── README.md                        # This file
```

### Configuration Locations

| Component | Location | Purpose |
|-----------|----------|---------|
| **Tenant Data** | `/mnt/data/{tenant}/` | All tenant-specific data |
| **Environment** | `/mnt/data/{tenant}/.env` | Service configuration |
| **AppArmor** | `/mnt/data/{tenant}/apparmor/` | Security profiles |
| **Logs** | `/mnt/data/{tenant}/logs/` | Service logs |
| **Configs** | `/mnt/data/{tenant}/config/` | Service configs |
| **Docker Volumes** | `/var/lib/docker/volumes/` | Persistent storage |
| **State Files** | `/mnt/data/metadata/` | Setup state and metadata |

## 🔧 Core Scripts

### 1. `0-reset-tenant.sh` - Tenant Reset
**Purpose**: Clean slate reset for tenant configuration
- Removes tenant directories and configurations
- Cleans Docker volumes and containers
- Resets system state
- Preserves EBS volumes (data safe)

### 2. `1-setup-system.sh` - System Setup
**Purpose**: Complete system initialization and configuration
- **Tenant Detection**: Multi-tenant user identification via SUDO_UID/GID
- **EBS Volume Selection**: fdisk-based volume scanning and mounting
- **Service Selection**: Interactive AI service selection
- **Port Management**: Dynamic port allocation and conflict resolution
- **Domain Configuration**: SSL certificate setup and proxy configuration
- **Environment Generation**: Complete .env file creation
- **Security Setup**: AppArmor profiles and user permissions

### 3. `2-deploy-services.sh` - Service Deployment
**Purpose**: Deploy and configure the AI services stack
- **Volume Processing**: Dynamic volume substitution in docker-compose
- **Service Orchestration**: Ordered deployment with health checks
- **Database Setup**: PostgreSQL, Redis, and vector DB initialization
- **Network Configuration**: Docker network setup and isolation
- **Tailscale Integration**: VPN setup and IP persistence
- **Health Monitoring**: Service startup validation

### 4. `3-configure-services.sh` - Post-Configuration
**Purpose**: Fine-tune and manage deployed services
- **Tailscale Configuration**: VPN settings and authentication
- **rclone Setup**: Cloud storage synchronization
- **Vector DB Collections**: Initialize AI service collections
- **Service Management**: Start/stop/restart operations
- **Monitoring Setup**: Prometheus and Grafana configuration

### 5. `4-add-service.sh` - Dynamic Service Addition
**Purpose**: Add new AI services to existing deployment
- **Service Templates**: Modular service definitions
- **Port Allocation**: Automatic port assignment
- **Configuration Generation**: Service-specific setup
- **Integration**: Connect to existing vector databases

## 🤖 AI Stack Components

### AI Applications
- **Open WebUI**: Chat interface for LLMs
- **AnythingLLM**: AI workspace and document management
- **Dify**: AI application development platform
- **n8n**: Workflow automation
- **Flowise**: AI flow builder
- **Ollama**: Local LLM hosting
- **LiteLLM**: LLM gateway and load balancing

### Vector Databases
- **Qdrant**: High-performance vector similarity search
- **Chroma**: Open-source embedding database
- **Weaviate**: Knowledge graph-based vector database

### Infrastructure Services
- **PostgreSQL**: Metadata and configuration storage
- **Redis**: Caching and session management
- **MinIO**: S3-compatible object storage
- **Prometheus**: Monitoring and metrics
- **Grafana**: Visualization and dashboards

### Security & Networking
- **Tailscale**: Zero-trust VPN networking
- **OpenClaw**: Container security and access control
- **AppArmor**: Mandatory access control
- **Caddy/Traefik/Nginx**: Reverse proxy with SSL

## 🔐 Security Architecture

### Multi-Tenant Isolation
- **User Mapping**: Each tenant runs as dedicated UID/GID
- **Storage Isolation**: Separate EBS volumes and directories
- **Network Isolation**: Tenant-specific Docker networks
- **Process Isolation**: Non-root containers with AppArmor

### Zero-Trust Security
- **Tailscale VPN**: Secure internal communication
- **OpenClaw**: Container security hardening
- **AppArmor Profiles**: Restrictive security policies
- **Secret Management**: Encrypted credential storage

### Access Control
```
┌─────────────────────────────────────────────────────────────────┐
│                    Access Control Model                        │
├─────────────────────────────────────────────────────────────────┤
│                                                             │
│  Public Access                                               │
│  ┌─────────────┐    HTTPS + Domain Auth                      │
│  │   Caddy    │ ◄─────────────────────────────────────────── │
│  │  (Proxy)    │                                            │
│  └─────────────┘                                            │
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────┐    Internal Network Only                    │
│  │ AI Services │ ◄─────────────────────────────────────────── │
│  │             │                                            │
│  └─────────────┘                                            │
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────┐    Tailscale VPN Only                       │
│  │ OpenClaw   │ ◄─────────────────────────────────────────── │
│  │ (Security)  │                                            │
│  └─────────────┘                                            │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Deployment Workflow

### Phase 1: System Setup
```bash
# 1. Reset existing configuration (optional)
sudo ./0-reset-tenant.sh

# 2. Run system setup
sudo ./1-setup-system.sh
```

### Phase 2: Service Deployment
```bash
# 3. Deploy AI services
sudo ./2-deploy-services.sh
```

### Phase 3: Configuration
```bash
# 4. Configure services
sudo ./3-configure-services.sh
```

### Phase 4: Service Management
```bash
# 5. Add new services (optional)
sudo ./4-add-service.sh
```

## 📊 Service Interconnections

### Vector Database Integration
```
AI Services → Vector DBs → Storage
     ↓            ↓           ↓
Open WebUI → Qdrant → EBS Volume
AnythingLLM → Chroma → EBS Volume
Dify → Weaviate → EBS Volume
```

### Authentication Flow
```
User → Domain → Proxy → Tailscale → OpenClaw → Service
  ↓        ↓        ↓         ↓          ↓         ↓
HTTPS   SSL Cert  Auth     VPN      Security  Container
```

### Data Flow
```
User Input → AI Service → Vector DB → EBS Storage
     ↓           ↓           ↓           ↓
  Query    Processing   Search    Persistence
```

## 🔧 Configuration Management

### Environment Variables
- **Tenant Configuration**: UID/GID, user names, paths
- **Service Configuration**: Ports, URLs, credentials
- **Database Configuration**: Connection strings, passwords
- **Network Configuration**: Domains, IPs, certificates

### State Management
- **Setup State**: Phase completion tracking
- **Service State**: Health and status monitoring
- **Configuration State**: Version control and rollback

## 📈 Monitoring & Observability

### Metrics Collection
- **Prometheus**: System and service metrics
- **Grafana**: Visualization and dashboards
- **Service Logs**: Centralized logging

### Health Checks
- **Service Health**: Container status and response times
- **Database Health**: Connection and query performance
- **Network Health**: VPN and proxy status

## 🛠️ Troubleshooting

### Common Issues
1. **Port Conflicts**: Dynamic port allocation resolves
2. **Volume Mounts**: EBS volume selection and permissions
3. **Network Issues**: Tailscale and proxy configuration
4. **Service Failures**: Health checks and log analysis

### Debug Commands
```bash
# Check service status
docker compose ps

# View service logs
docker compose logs [service]

# Check network connectivity
docker network ls

# Verify volumes
docker volume ls
```

## 🔄 Maintenance

### Updates
- **Service Updates**: Rolling updates with zero downtime
- **Security Updates**: Automated patch management
- **Configuration Updates**: Controlled rollouts

### Backups
- **Data Backups**: EBS snapshots and database dumps
- **Configuration Backups**: Git version control
- **State Backups**: Setup state restoration

## 📝 Development

### Adding New Services
1. Create service template in `templates/`
2. Add to service selection in `1-setup-system.sh`
3. Update `docker-compose.yml`
4. Test deployment

### Customization
- **Templates**: Modify service configurations
- **Scripts**: Add custom automation
- **Security**: Update AppArmor profiles

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📞 Support

For support and questions:
- Create an issue in the repository
- Check the documentation in `doc/`
- Review the troubleshooting section

---

**Built with ❤️ for production AI deployments**
