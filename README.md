# AI Platform Automation - Complete Deployment Guide
**Version 76.3.0** | Last Updated: 2026-02-09

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Installation Scripts](#installation-scripts)
   - [Script 0: Complete Cleanup](#script-0-complete-cleanup)
   - [Script 1: System Setup](#script-1-system-setup)
   - [Script 2: Deploy Services](#script-2-deploy-services)
   - [Script 3: Configure Services](#script-3-configure-services)
   - [Script 4: Verify Deployment](#script-4-verify-deployment)
5. [Network Configuration](#network-configuration)
6. [Service Access](#service-access)
7. [Troubleshooting](#troubleshooting)
8. [Maintenance](#maintenance)
9. [Security Considerations](#security-considerations)
10. [Changelog](#changelog)

---

## 🎯 Overview

This project provides a **fully automated deployment** of a complete AI platform stack on Ubuntu 24.04 LTS, featuring:

- **Tailscale VPN** (isolated IP: `100.x.x.x:8443`)
- **Open WebUI** with Ollama backend
- **n8n** workflow automation
- **Flowise** AI orchestration
- **Dify** AI application platform
- **Portainer** container management
- **Nginx** reverse proxy with SSL
- **PostgreSQL** databases for each service
- **Automated SSL certificate** generation and renewal

### Key Objectives

✅ **One-command deployment** for complete AI infrastructure
✅ **Isolated Tailscale access** on dedicated IP with port 8443
✅ **Production-ready** with SSL, security hardening, and monitoring
✅ **Modular architecture** with independent service deployment
✅ **Automatic recovery** and health checking
✅ **Clean separation** between public and VPN-only services

---

## 🏗️ Architecture

### Network Layout

```
Internet
    │
    ├─→ Tailscale VPN (100.x.x.x:8443) ──→ Nginx Gateway
    │                                         │
    │                                         ├─→ Open WebUI (3000)
    │                                         ├─→ n8n (5678)
    │                                         ├─→ Flowise (3001)
    │                                         ├─→ Dify (3002/5001)
    │                                         └─→ Portainer (9443)
    │
    └─→ Local Network (eth0)
            │
            └─→ Direct Container Access (localhost only)
```

### Technology Stack

| Component | Version | Purpose | Port |
|-----------|---------|---------|------|
| **Ubuntu** | 24.04 LTS | Base OS | - |
| **Docker** | Latest | Container runtime | - |
| **Tailscale** | Latest | VPN access | 8443 |
| **Nginx** | Latest | Reverse proxy | 80/443 |
| **Open WebUI** | Latest | AI chat interface | 3000 |
| **Ollama** | Latest | LLM backend | 11434 |
| **n8n** | Latest | Workflow automation | 5678 |
| **Flowise** | Latest | AI orchestration | 3001 |
| **Dify** | Latest | AI app platform | 3002/5001 |
| **Portainer** | CE Latest | Container mgmt | 9443 |
| **PostgreSQL** | 16 | Database (per service) | 5432+ |

---

## 📦 Prerequisites

### System Requirements

- **OS**: Ubuntu 24.04 LTS (fresh installation recommended)
- **CPU**: 4+ cores (8+ recommended for AI workloads)
- **RAM**: 16 GB minimum (32 GB+ recommended)
- **Storage**: 100 GB+ SSD (NVMe preferred for AI models)
- **Network**: Static IP or stable DHCP reservation
- **User**: Non-root user with sudo privileges

### Required Accounts

1. **Tailscale Account** (free tier sufficient)
   - Sign up at https://tailscale.com
   - Generate an auth key at https://login.tailscale.com/admin/settings/keys
   - Use reusable key for automation

2. **Domain Name** (optional but recommended)
   - For proper SSL certificates
   - DNS A record pointing to Tailscale IP

### Pre-Installation Checklist

- [ ] Fresh Ubuntu 24.04 LTS installation
- [ ] Non-root user with sudo access created
- [ ] System updated (`sudo apt update && sudo apt upgrade -y`)
- [ ] Tailscale auth key ready
- [ ] Domain name configured (if using SSL)
- [ ] Firewall rules planned
- [ ] Backup strategy defined

---

## 🚀 Installation Scripts

### Script 0: Complete Cleanup

**Purpose**: Nuclear option to completely remove all AI platform components and reset the system to a clean state.

**File**: `scripts/0-complete-cleanup.sh`

#### What It Does

1. **Stops all containers** and removes Docker networks
2. **Removes all Docker volumes** (including databases)
3. **Purges Tailscale** completely (requires re-authentication)
4. **Deletes all configuration files** and service directories
5. **Removes Docker engine** and associated packages
6. **Cleans system packages** and orphaned dependencies
7. **Resets firewall rules** to default state

#### Expected Outcome

- System returned to pre-installation state
- All data destroyed (databases, configurations, logs)
- Ready for fresh installation

#### Usage

```bash
# WARNING: This is destructive and irreversible
chmod +x scripts/0-complete-cleanup.sh
sudo ./scripts/0-complete-cleanup.sh

# After cleanup, reboot is recommended
sudo reboot
```

⚠️ **WARNING**: This script will permanently delete:
- All AI models downloaded by Ollama
- All workflow data in n8n
- All Flowise configurations and flows
- All Dify applications and datasets
- All PostgreSQL databases and users
- All SSL certificates
- All container images

---

### Script 1: System Setup

**Purpose**: Prepare the Ubuntu system with all required dependencies and configure the base environment.

**File**: `scripts/1-setup-system.sh`

**Status**: ✅ Working and tested

#### What It Does

1. **System Preparation**
   - Updates package lists and upgrades existing packages
   - Installs essential utilities (curl, git, jq, htop, etc.)
   - Configures system locale and timezone

2. **Docker Installation**
   - Adds Docker's official GPG key and repository
   - Installs Docker Engine and Docker Compose
   - Configures Docker daemon with optimal settings
   - Adds current user to docker group

3. **Tailscale Installation**
   - Adds Tailscale repository and GPG key
   - Installs Tailscale VPN client
   - Configures Tailscale with authentication
   - Sets up IP routing and advertises subnet

4. **Network Configuration**
   - Enables IP forwarding
   - Configures UFW firewall rules
   - Sets up NAT and routing tables
   - Ensures Tailscale IP isolation

5. **Directory Structure**
   - Creates `/opt/ai-platform` base directory
   - Sets up subdirectories for each service
   - Configures proper permissions

#### Expected Outcome

- Docker installed and running
- Tailscale connected with dedicated IP (100.x.x.x)
- Firewall configured for Tailscale traffic on port 8443
- Base directory structure created
- System ready for service deployment

#### Usage

```bash
chmod +x scripts/1-setup-system.sh
sudo ./scripts/1-setup-system.sh

# Verify Docker
docker --version
docker compose version

# Verify Tailscale
tailscale status
tailscale ip -4  # Note this IP for access

# Verify network
sudo ufw status
ip route | grep tailscale
```

#### Configuration Variables

Edit these at the top of the script before running:

```bash
TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"  # Your reusable auth key
TIMEZONE="America/New_York"            # Your timezone
```

---

### Script 2: Deploy Services

**Purpose**: Deploy all Docker containers with proper networking, volumes, and dependencies.

**File**: `scripts/2-deploy-services.sh`

**Status**: ⚠️ Recently updated - requires testing

#### What It Does

1. **PostgreSQL Databases**
   - Deploys independent PostgreSQL 16 containers for:
     - n8n workflow data
     - Flowise configurations
     - Dify application data
   - Creates databases and dedicated users
   - Sets up persistent volumes
   - Configures health checks

2. **Ollama Backend**
   - Deploys Ollama container for LLM inference
   - Configures GPU support (if available)
   - Sets up model storage volume
   - Exposes API on port 11434

3. **Open WebUI**
   - Deploys Open WebUI container
   - Connects to Ollama backend
   - Configures authentication
   - Sets up data persistence

4. **n8n Workflow Automation**
   - Deploys n8n container
   - Connects to PostgreSQL database
   - Configures webhook URL
   - Sets up workflow persistence

5. **Flowise AI Orchestration**
   - Deploys Flowise container
   - Connects to PostgreSQL database
   - Configures API keys and credentials
   - Sets up flow storage

6. **Dify AI Platform**
   - Deploys Dify API and Web containers
   - Connects to PostgreSQL and Redis
   - Configures S3 storage (MinIO)
   - Sets up worker processes

7. **Portainer Management**
   - Deploys Portainer CE container
   - Connects to Docker socket
   - Configures admin access
   - Sets up SSL on port 9443

8. **Docker Networks**
   - Creates `ai-platform-network` bridge network
   - Connects all services to shared network
   - Configures inter-service communication

#### Expected Outcome

- All containers running and healthy
- PostgreSQL databases initialized and accessible
- Services connected to shared network
- Volumes created and mounted
- Health checks passing

#### Usage

```bash
chmod +x scripts/2-deploy-services.sh
sudo ./scripts/2-deploy-services.sh

# Verify deployment
docker ps -a
docker network ls
docker volume ls

# Check specific service
docker logs open-webui
docker logs n8n
docker logs flowise
docker logs dify-api
```

#### Service Dependencies

```
PostgreSQL (n8n-db, flowise-db, dify-db)
    ↓
Ollama → Open WebUI
    ↓
n8n (requires n8n-db)
    ↓
Flowise (requires flowise-db)
    ↓
Dify (requires dify-db, redis, minio)
    ↓
Portainer (independent)
```

---

### Script 3: Configure Services

**Purpose**: Configure Nginx reverse proxy, SSL certificates, and service-specific settings.

**File**: `scripts/3-configure-services.sh`

**Status**: ⚠️ Recently updated - requires testing

#### What It Does

1. **Nginx Installation**
   - Installs Nginx web server
   - Configures upstream definitions for each service
   - Sets up reverse proxy rules
   - Enables gzip compression and caching

2. **SSL Certificate Generation**
   - Generates self-signed certificates (development)
   - Or configures Let's Encrypt (production)
   - Sets up automatic renewal
   - Configures strong cipher suites

3. **Tailscale-Specific Configuration**
   - Binds Nginx to Tailscale IP (100.x.x.x:8443)
   - Configures HTTPS on port 8443
   - Sets up WebSocket support for real-time services
   - Enables proper headers for proxied requests

4. **Service Routes**
   - `/webui` → Open WebUI (port 3000)
   - `/n8n` → n8n (port 5678)
   - `/flowise` → Flowise (port 3001)
   - `/dify` → Dify Web (port 3002)
   - `/portainer` → Portainer (port 9443)

5. **Security Headers**
   - Implements HSTS
   - Configures CSP (Content Security Policy)
   - Sets X-Frame-Options
   - Enables XSS protection

6. **Service-Specific Configurations**
   - Open WebUI: Ollama connection and authentication
   - n8n: Webhook base URL and execution settings
   - Flowise: Database connection and API settings
   - Dify: Environment variables and worker configuration
   - Portainer: Admin password setup

#### Expected Outcome

- Nginx running and bound to Tailscale IP:8443
- All services accessible through reverse proxy
- SSL certificates active (self-signed or Let's Encrypt)
- Security headers configured
- WebSocket connections working

#### Usage

```bash
chmod +x scripts/3-configure-services.sh
sudo ./scripts/3-configure-services.sh

# Verify Nginx
sudo nginx -t
sudo systemctl status nginx

# Check certificate
openssl s_client -connect $(tailscale ip -4):8443 -servername yourdomain.com

# Test service access
curl -k https://$(tailscale ip -4):8443/webui
```

#### Configuration Variables

```bash
DOMAIN="your-tailscale-hostname.ts.net"
TAILSCALE_IP=$(tailscale ip -4)
SSL_PORT=8443
USE_LETSENCRYPT=false  # Set to true for production
```

---

### Script 4: Verify Deployment

**Purpose**: Comprehensive health check and validation of all deployed services.

**File**: `scripts/4-verify-deployment.sh`

**Status**: ⚠️ Recently updated - requires testing

#### What It Does

1. **Container Health Checks**
   - Verifies all containers are running
   - Checks container health status
   - Validates restart policies
   - Reports resource usage (CPU, memory)

2. **Network Validation**
   - Confirms Tailscale connectivity
   - Tests Docker network connectivity
   - Validates port bindings
   - Checks firewall rules

3. **Database Connectivity**
   - Tests PostgreSQL connections for each service
   - Verifies database creation
   - Checks user permissions
   - Validates schema initialization

4. **Service Endpoint Tests**
   - HTTP/HTTPS request to each service
   - Validates response codes (200, 302, etc.)
   - Tests WebSocket connections
   - Checks API endpoints

5. **SSL Certificate Validation**
   - Verifies certificate validity
   - Checks expiration dates
   - Validates certificate chain
   - Tests cipher strength

6. **Integration Tests**
   - Open WebUI → Ollama connection
   - n8n → Database connection
   - Flowise → Database connection
   - Dify → Database and Redis connection

7. **Performance Baseline**
   - Measures response times
   - Checks resource availability
   - Validates disk space
   - Reports system load

#### Expected Outcome

- All containers reported as healthy
- All services accessible via Tailscale IP:8443
- Database connections successful
- SSL certificates valid
- Integration tests passing
- Detailed report generated

#### Usage

```bash
chmod +x scripts/4-verify-deployment.sh
sudo ./scripts/4-verify-deployment.sh

# Output includes:
# ✅ Container Status
# ✅ Network Connectivity
# ✅ Database Health
# ✅ Service Endpoints
# ✅ SSL Validation
# ✅ Integration Tests
# ✅ Performance Metrics
```

#### Sample Output

```
========================================
AI Platform Deployment Verification
========================================

[✓] Docker Service: Running
[✓] Tailscale Service: Running (100.64.x.x)
[✓] Nginx Service: Running (8443)

Container Status:
[✓] ollama: healthy (uptime: 2h)
[✓] open-webui: healthy (uptime: 2h)
[✓] n8n: healthy (uptime: 2h)
[✓] flowise: healthy (uptime: 2h)
[✓] dify-api: healthy (uptime: 2h)
[✓] dify-web: healthy (uptime: 2h)
[✓] portainer: healthy (uptime: 2h)

Database Connectivity:
[✓] n8n-db: Connected
[✓] flowise-db: Connected
[✓] dify-db: Connected

Service Endpoints:
[✓] https://100.64.x.x:8443/webui (200 OK)
[✓] https://100.64.x.x:8443/n8n (200 OK)
[✓] https://100.64.x.x:8443/flowise (200 OK)
[✓] https://100.64.x.x:8443/dify (200 OK)
[✓] https://100.64.x.x:8443/portainer (200 OK)

SSL Certificate:
[✓] Valid until: 2025-12-31
[✓] Subject: CN=yourdomain.ts.net
[✓] Issuer: Self-signed / Let's Encrypt

Integration Tests:
[✓] Open WebUI → Ollama: Connected
[✓] n8n → PostgreSQL: Connected
[✓] Flowise → PostgreSQL: Connected
[✓] Dify → PostgreSQL: Connected
[✓] Dify → Redis: Connected

Performance:
[✓] CPU Load: 15%
[✓] Memory Usage: 8.2/16 GB
[✓] Disk Space: 45/100 GB used

========================================
✅ All checks passed! Deployment verified.
========================================
```

---

## 🌐 Network Configuration

### Tailscale VPN Access

The entire AI platform is accessible **only through Tailscale VPN** on a dedicated IP and port:

```
Tailscale IP: 100.x.x.x (assigned by Tailscale)
HTTPS Port: 8443
SSL: Enabled (self-signed or Let's Encrypt)
```

#### Access Pattern

```
Client Device (Tailscale)
    ↓
https://100.x.x.x:8443
    ↓
Nginx Reverse Proxy
    ↓
Service Routing:
    /webui    → Open WebUI
    /n8n      → n8n
    /flowise  → Flowise
    /dify     → Dify
    /portainer→ Portainer
```

### Firewall Rules

```bash
# Only Tailscale traffic allowed on 8443
sudo ufw status

Status: active
To                         Action      From
--                         ------      ----
8443/tcp                   ALLOW       100.64.0.0/10  # Tailscale only
22/tcp                     ALLOW       Anywhere       # SSH
41641/udp                  ALLOW       Anywhere       # Tailscale
```

### DNS Configuration (Optional)

For custom domain support:

1. Create DNS A record:
   ```
   ai-platform.yourdomain.com → 100.x.x.x
   ```

2. Update Nginx configuration:
   ```nginx
   server_name ai-platform.yourdomain.com;
   ```

3. Use Let's Encrypt for production SSL:
   ```bash
   # In script 3, set:
   USE_LETSENCRYPT=true
   DOMAIN="ai-platform.yourdomain.com"
   ```

---

## 🔐 Service Access

### Initial Access URLs

After deployment, access services at:

| Service | URL | Default Port |
|---------|-----|--------------|
| **Open WebUI** | `https://100.x.x.x:8443/webui` | 3000 |
| **n8n** | `https://100.x.x.x:8443/n8n` | 5678 |
| **Flowise** | `https://100.x.x.x:8443/flowise` | 3001 |
| **Dify** | `https://100.x.x.x:8443/dify` | 3002 |
| **Portainer** | `https://100.x.x.x:8443/portainer` | 9443 |

*Replace `100.x.x.x` with your actual Tailscale IP*

### First-Time Setup

#### Open WebUI
1. Navigate to `/webui`
2. Create admin account
3. Configure Ollama connection (should auto-detect)
4. Download AI models from library

#### n8n
1. Navigate to `/n8n`
2. Create owner account (first user)
3. Set up credentials for integrations
4. Import or create workflows

#### Flowise
1. Navigate to `/flowise`
2. No authentication by default
3. Create first chatflow
4. Configure API keys in settings

#### Dify
1. Navigate to `/dify`
2. Create admin account
3. Set up API keys
4. Create first application

#### Portainer
1. Navigate to `/portainer`
2. Set admin password
3. Connect to local Docker environment
4. Review container status

---

## 🛠️ Troubleshooting

### Common Issues

#### 1. Cannot Access Services

**Symptom**: Browser shows "Connection refused" or timeout

**Solutions**:
```bash
# Verify Tailscale connection
tailscale status
tailscale ping 100.x.x.x

# Check Nginx is listening on Tailscale IP
sudo netstat -tlnp | grep 8443

# Verify firewall rules
sudo ufw status | grep 8443

# Check Nginx logs
sudo tail -f /var/log/nginx/error.log
```

#### 2. Containers Not Starting

**Symptom**: `docker ps` shows containers as "Exited" or "Restarting"

**Solutions**:
```bash
# Check specific container logs
docker logs <container-name>

# Verify disk space
df -h

# Check Docker daemon
sudo systemctl status docker

# Restart specific service
docker restart <container-name>
```

#### 3. Database Connection Errors

**Symptom**: Services show "Cannot connect to database"

**Solutions**:
```bash
# Check PostgreSQL containers
docker ps | grep postgres

# Test database connection
docker exec -it n8n-db psql -U n8n -d n8n -c "SELECT 1;"

# Verify environment variables
docker inspect n8n | grep -i postgres

# Restart database and dependent service
docker restart n8n-db && sleep 5 && docker restart n8n
```

#### 4. SSL Certificate Errors

**Symptom**: Browser shows "Your connection is not private"

**Solutions**:
```bash
# For self-signed certificates (development)
# Accept the browser warning and continue

# For Let's Encrypt (production)
sudo certbot renew --dry-run

# Check certificate validity
openssl s_client -connect 100.x.x.x:8443 -servername yourdomain.com

# Regenerate self-signed certificate
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/nginx-selfsigned.key \
  -out /etc/ssl/certs/nginx-selfsigned.crt
```

#### 5. Ollama Model Download Fails

**Symptom**: Models won't download or inference is slow

**Solutions**:
```bash
# Check Ollama container
docker logs ollama

# Verify disk space for models
docker exec ollama df -h

# Manually pull model
docker exec ollama ollama pull llama2

# Check GPU availability (if using NVIDIA)
docker exec ollama nvidia-smi
```

### Log Locations

```bash
# Application logs
docker logs <container-name>

# Nginx logs
/var/log/nginx/access.log
/var/log/nginx/error.log

# Tailscale logs
sudo journalctl -u tailscaled

# System logs
sudo journalctl -xe
```

### Emergency Recovery

```bash
# Stop all services
docker stop $(docker ps -q)

# Restart Docker daemon
sudo systemctl restart docker

# Restart Tailscale
sudo systemctl restart tailscaled

# Restart Nginx
sudo systemctl restart nginx

# Full system reboot
sudo reboot
```

---

## 🔄 Maintenance

### Regular Tasks

#### Daily
- Monitor disk space: `df -h`
- Check container status: `docker ps`
- Review logs for errors: `docker logs <service>`

#### Weekly
- Update Docker images: `docker compose pull && docker compose up -d`
- Backup databases (see Backup section)
- Review Nginx access logs
- Check Tailscale connectivity

#### Monthly
- System updates: `sudo apt update && sudo apt upgrade -y`
- SSL certificate renewal (if using Let's Encrypt)
- Clean unused Docker resources: `docker system prune -a`
- Review and rotate logs

### Backup Strategy

#### Database Backups

```bash
# Backup n8n database
docker exec n8n-db pg_dump -U n8n n8n > n8n_backup_$(date +%Y%m%d).sql

# Backup Flowise database
docker exec flowise-db pg_dump -U flowise flowise > flowise_backup_$(date +%Y%m%d).sql

# Backup Dify database
docker exec dify-db pg_dump -U dify dify > dify_backup_$(date +%Y%m%d).sql
```

#### Volume Backups

```bash
# Backup all Docker volumes
docker run --rm -v ai-platform-data:/data -v $(pwd):/backup \
  ubuntu tar czf /backup/volumes_backup_$(date +%Y%m%d).tar.gz /data
```

#### Configuration Backups

```bash
# Backup Nginx config
sudo tar czf nginx_config_$(date +%Y%m%d).tar.gz /etc/nginx/

# Backup service configs
sudo tar czf ai-platform_config_$(date +%Y%m%d).tar.gz /opt/ai-platform/
```

### Update Procedure

```bash
# 1. Backup everything first
./scripts/backup-all.sh

# 2. Pull latest images
cd /opt/ai-platform
docker compose pull

# 3. Recreate containers with new images
docker compose up -d

# 4. Verify deployment
./scripts/4-verify-deployment.sh

# 5. Check logs for errors
docker compose logs -f
```

### Performance Optimization

#### Docker
```bash
# Clean up unused resources weekly
docker system prune -a -f --volumes

# Optimize Docker daemon
sudo nano /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
sudo systemctl restart docker
```

#### PostgreSQL
```bash
# Vacuum databases monthly
docker exec n8n-db psql -U n8n -d n8n -c "VACUUM ANALYZE;"
docker exec flowise-db psql -U flowise -d flowise -c "VACUUM ANALYZE;"
docker exec dify-db psql -U dify -d dify -c "VACUUM ANALYZE;"
```

---

## 🔒 Security Considerations

### Network Security

1. **Tailscale VPN Only**
   - All services accessible only through Tailscale
   - No public internet exposure
   - Port 8443 restricted to Tailscale subnet (100.64.0.0/10)

2. **Firewall Configuration**
   ```bash
   # UFW rules are strict
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow from 100.64.0.0/10 to any port 8443
   ```

3. **SSL/TLS**
   - All traffic encrypted with TLS 1.2+
   - Strong cipher suites enforced
   - HSTS enabled

### Application Security

1. **Authentication**
   - All services require authentication
   - Strong password policies recommended
   - Consider implementing 2FA where supported

2. **API Keys**
   - Store API keys in environment variables
   - Rotate keys regularly
   - Use service-specific keys with minimal permissions

3. **Database Security**
   - PostgreSQL accessible only within Docker network
   - Unique passwords per database
   - Regular backups with encryption

### Container Security

1. **Image Sources**
   - Use official images only
   - Regularly update to latest versions
   - Scan for vulnerabilities: `docker scan <image>`

2. **Resource Limits**
   ```yaml
   # In docker-compose.yml
   deploy:
     resources:
       limits:
         cpus: '2'
         memory: 4G
   ```

3. **Non-Root Execution**
   - Most containers run as non-root users
   - Docker socket access restricted to Portainer only

### Monitoring

```bash
# Monitor failed login attempts
sudo journalctl -u ssh | grep "Failed password"

# Monitor Docker events
docker events --filter 'type=container'

# Monitor Tailscale connections
sudo tailscale status
```

### Security Checklist

- [ ] Tailscale auth key is reusable but expires
- [ ] Strong passwords set for all services
- [ ] SSL certificates valid and auto-renewing
- [ ] Firewall rules tested and verified
- [ ] Database backups encrypted at rest
- [ ] SSH key authentication enabled (password auth disabled)
- [ ] Regular security updates scheduled
- [ ] Log monitoring and alerting configured

---

## 📝 Changelog

### Version 76.3.0 (Current)

**Major Updates:**
- Migrated from monolithic docker-compose to modular script-based deployment
- Enhanced Tailscale integration with dedicated IP isolation
- Improved error handling and logging across all scripts
- Added comprehensive health checks and verification
- Implemented proper service dependencies and startup order

**Script Evolution:**
- **Script 0**: Complete cleanup and reset functionality
- **Script 1**: System setup with Docker and Tailscale (✅ tested)
- **Script 2**: Modular service deployment (⚠️ updated, testing needed)
- **Script 3**: Nginx configuration and SSL setup (⚠️ updated, testing needed)
- **Script 4**: Comprehensive deployment verification (⚠️ updated, testing needed)

**Service Updates:**
- Open WebUI: Latest version with improved Ollama integration
- n8n: PostgreSQL backend for better scalability
- Flowise: Enhanced database persistence
- Dify: Complete API and Web deployment with Redis and MinIO
- Portainer: CE edition with proper SSL on port 9443

**Network Improvements:**
- Tailscale bound to port 8443 exclusively
- Improved firewall rules for Tailscale subnet
- Enhanced Nginx reverse proxy configuration
- WebSocket support for all services

**Security Enhancements:**
- Self-signed SSL certificates with strong ciphers
- Optional Let's Encrypt integration
- Improved header security (HSTS, CSP, X-Frame-Options)
- Database isolation within Docker network

**Documentation:**
- Complete README restructure matching current implementation
- Added detailed script descriptions and expected outcomes
- Enhanced troubleshooting section
- Added maintenance and backup procedures

### Previous Versions

For detailed changelog history before version control, see:
- [Detailed Changelog](changelog/detailed_changelog.csv)
- [Summary Changelog](changelog/summary_changelog.csv)

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Test your changes thoroughly
4. Commit with clear messages (`git commit -m 'Add amazing feature'`)
5. Push to your branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

---

## 📄 License

This project is provided as-is for educational and personal use. Please review individual service licenses:

- Docker: Apache 2.0
- Tailscale: BSD 3-Clause
- Open WebUI: MIT
- Ollama: MIT
- n8n: Sustainable Use License
- Flowise: Apache 2.0
- Dify: Apache 2.0
- Portainer: Zlib License

---

## 📧 Support

For issues, questions, or contributions:

- **GitHub Issues**: [Create an issue](https://github.com/jgla1ne/AIPlatformAutomation/issues)
- **Discussions**: [GitHub Discussions](https://github.com/jgla1ne/AIPlatformAutomation/discussions)

---

## 🙏 Acknowledgments

- Tailscale team for excellent VPN solution
- Docker community for containerization platform
- Open source maintainers of all integrated services
- Ubuntu LTS for stable foundation

---

**Last Updated**: 2026-02-09
**Version**: 76.3.0
**Maintainer**: jgla1ne
**Repository**: https://github.com/jgla1ne/AIPlatformAutomation

