[INFO] DEBUG: Script 2 starting...
[INFO] DEBUG: ENV_FILE=/mnt/data/.env
[INFO] DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[INFO] DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[INFO] Performing pre-deployment cleanup...
[INFO] Cleaning up previous deployments...
[INFO] Stopping AI platform containers using unified compose...
 Container anythingllm Stopping 
 Container flowise Stopping 
 Container litellm Stopping 
 Container signal-api Stopping 
 Container minio Stopping 
 Container grafana Stopping 
 Container n8n Stopping 
 Container tailscale Stopping 
 Container openwebui Stopping 
 Container litellm Stopped 
 Container litellm Removing 
 Container grafana Stopped 
 Container grafana Removing 
 Container litellm Removed 
 Container redis Stopping 
 Container flowise Stopped 
 Container flowise Removing 
 Container anythingllm Stopped 
 Container anythingllm Removing 
 Container grafana Removed 
 Container prometheus Stopping 
 Container signal-api Stopped 
 Container signal-api Removing 
 Container minio Stopped 
 Container minio Removing 
 Container flowise Removed 
 Container anythingllm Removed 
 Container prometheus Stopped 
 Container prometheus Removing 
 Container redis Stopped 
 Container redis Removing 
 Container signal-api Removed 
 Container minio Removed 
 Container prometheus Removed 
 Container redis Removed 
 Container tailscale Stopped 
 Container tailscale Removing 
 Container tailscale Removed 
 Container n8n Stopped 
 Container n8n Removing 
 Container n8n Removed 
 Container postgres Stopping 
 Container postgres Stopped 
 Container postgres Removing 
 Container postgres Removed 
 Container openwebui Stopped 
 Container openwebui Removing 
 Container openwebui Removed 
 Container ollama Stopping 
 Container ollama Stopped 
 Container ollama Removing 
 Container ollama Removed 
 Network ai_platform Removing 
 Network ai_platform_internal Removing 
 Network ai_platform_internal Removed 
 Network ai_platform Removed 
[SUCCESS] All containers stopped successfully
[INFO] Cleaning up orphaned containers...
Total reclaimed space: 0B
[INFO] DEBUG: Aggressive network cleanup starting...
[INFO] DEBUG: Stopping Docker daemon to clear network cache...
[INFO] DEBUG: Docker daemon stopped
[INFO] DEBUG: Force removing all ai_platform networks...
[INFO] DEBUG: Waiting for networks to be fully removed...
[INFO] DEBUG: Verifying networks are actually removed...
[INFO] DEBUG: Starting Docker daemon to refresh network cache...
[INFO] DEBUG: Waiting for Docker daemon to be ready...
[INFO] DEBUG: Network cleanup completed successfully
[INFO] Cleaning up unused volumes...
Total reclaimed space: 0B
[INFO] DEBUG: About to terminate background processes...
[INFO] DEBUG: Current PID: 3578623
[INFO] DEBUG: Terminated other 2-deploy-services processes
[INFO] DEBUG: Terminated docker-compose processes
[SUCCESS] Pre-deployment cleanup completed
[INFO] DEBUG: cleanup_previous_deployments function completed
[INFO] DEBUG: About to call load_selected_services...
[INFO] Loaded 15 selected services from Script 1
[INFO] Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[INFO] DEBUG: load_selected_services completed successfully
[INFO] DEBUG: Environment variables loaded:
[INFO]   RUNNING_UID: 1001
[INFO]   RUNNING_GID: 1001
[INFO]   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[INFO]   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[INFO]   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[INFO] DEBUG: About to verify compose file exists...
[INFO] DEBUG: Compose file verification completed
[SUCCESS] Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[INFO] DEBUG: About to generate proxy configuration...
[INFO] Generating proxy configuration for caddy...
[INFO] Generating Caddy configuration...
[SUCCESS] Proxy configuration generated for caddy
[INFO] Adding caddy service to docker-compose.yml...
[INFO] Caddy already in compose file
[SUCCESS] caddy added to compose
[INFO] DEBUG: About to create Docker networks...
[INFO] DEBUG: About to create Docker networks...
[INFO] DEBUG: Cleaning up existing networks...
[SUCCESS] Created ai_platform network
[INFO] DEBUG: Docker networks created successfully
[INFO] DEBUG: About to start service deployment loop...
[INFO] DEBUG: Deploying core infrastructure...
[INFO] DEBUG: Fixing PostgreSQL volume permissions...
[INFO] DEBUG: Fixing Redis volume permissions...
[INFO] DEBUG: Pulling postgres image...
 Image postgres:15-alpine Pulling 
 Image postgres:15-alpine Pulled 
[INFO] DEBUG: Starting postgres with explicit environment...
 Container postgres Creating 
 Container postgres Created 
 Container postgres Starting 
 Container postgres Started 
[INFO] DEBUG: Waiting for postgres to become healthy...
[INFO] DEBUG: Pulling redis image...
 Image redis:7-alpine Pulling 
 Image redis:7-alpine Pulled 
[INFO] DEBUG: Starting redis with explicit environment...
 Container redis Creating 
 Container redis Created 
 Container redis Starting 
 Container redis Started 
[INFO] DEBUG: Waiting for redis to become healthy...
[WARNING] redis is running but health check timed out
[INFO] DEBUG: Deploying monitoring services...
[INFO] DEBUG: Pulling prometheus image...
 Image prom/prometheus:latest Pulling 
 Image prom/prometheus:latest Pulled 
[INFO] DEBUG: Starting prometheus with explicit environment...
 Container prometheus Starting 
 Container prometheus Started 
[INFO] DEBUG: Waiting for prometheus to become healthy...
[WARNING] prometheus is running but health check timed out
[INFO] DEBUG: Pulling grafana image...
 Image grafana/grafana:latest Pulling 
 Image grafana/grafana:latest Pulled 
[INFO] DEBUG: Starting grafana with explicit environment...
 Network ai_platform Creating 
 Network ai_platform Created 
 Container grafana Creating 
 Container grafana Created 
 Container prometheus Starting 
 Container prometheus Started 
 Container prometheus Waiting 
 Container prometheus Error dependency prometheus failed to start
dependency failed to start: container prometheus is unhealthy
[ERROR] Failed to start grafana
[INFO] DEBUG: Deploying AI services...
[INFO] DEBUG: Pulling ollama image...
 Image ollama/ollama:latest Pulling 
 Image ollama/ollama:latest Pulled 
[INFO] DEBUG: Starting ollama with explicit environment...
 Container ollama Creating 
 Container ollama Created 
 Container ollama Starting 
 Container ollama Started 
[INFO] DEBUG: Waiting for ollama to become healthy...
[WARNING] ollama is running but health check timed out
[INFO] DEBUG: Pulling litellm image...
 Image ghcr.io/berriai/litellm:main-latest Pulling 
 Image ghcr.io/berriai/litellm:main-latest Pulled 
[INFO] DEBUG: Starting litellm with explicit environment...
 Container postgres Running 
 Container litellm Creating 
 Container litellm Created 
 Container redis Starting 
 Container redis Started 
 Container redis Waiting 
 Container postgres Waiting 
 Container redis Error dependency redis failed to start
 Container postgres Healthy 
dependency failed to start: container redis is unhealthy
[ERROR] Failed to start litellm
[INFO] DEBUG: Pulling openwebui image...
 Image ghcr.io/open-webui/open-webui:main Pulling 
 Image ghcr.io/open-webui/open-webui:main Pulled 
[INFO] DEBUG: Starting openwebui with explicit environment...
 Container openwebui Creating 
 Container openwebui Created 
 Container ollama Starting 
 Container ollama Started 
 Container openwebui Starting 
 Container openwebui Started 
[INFO] DEBUG: Waiting for openwebui to become healthy...
[WARNING] openwebui is running but health check timed out
[INFO] DEBUG: Pulling anythingllm image...
 Image mintplexlabs/anythingllm:latest Pulling 
 Image mintplexlabs/anythingllm:latest Pulled 
[INFO] DEBUG: Starting anythingllm with explicit environment...
 Container anythingllm Creating 
 Container anythingllm Created 
 Container anythingllm Starting 
 Container anythingllm Started 
[INFO] DEBUG: Waiting for anythingllm to become healthy...
[WARNING] anythingllm is running but health check timed out
[ERROR] Service dify not defined in /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[INFO] DEBUG: Pulling openclaw image...
 Image openclaw/openclaw:latest Pulling 
 Image openclaw/openclaw:latest Error pull access denied for openclaw/openclaw, repository does not exist or may require 'docker login': denied: requested access to the resource is denied
Error response from daemon: pull access denied for openclaw/openclaw, repository does not exist or may require 'docker login': denied: requested access to the resource is denied
[ERROR] Failed to pull openclaw image
[INFO] DEBUG: Deploying communication services...
[INFO] DEBUG: Pulling n8n image...
 Image n8nio/n8n:latest Pulling 
 Image n8nio/n8n:latest Pulled 
[INFO] DEBUG: Starting n8n with explicit environment...
 Container postgres Running 
 Container n8n Creating 
 Container n8n Created 
 Container postgres Waiting 
 Container postgres Healthy 
 Container n8n Starting 
 Container n8n Started 
[INFO] DEBUG: Waiting for n8n to become healthy...
[WARNING] n8n is running but health check timed out
[INFO] DEBUG: Pulling signal-api image...
 Image bbernhard/signal-cli-rest-api:latest Pulling 
 Image bbernhard/signal-cli-rest-api:latest Pulled 
[INFO] DEBUG: Starting signal-api with explicit environment...
 Container signal-api Creating 
 Container signal-api Created 
 Container signal-api Starting 
 Container signal-api Started 
[INFO] DEBUG: Waiting for signal-api to become healthy...
[WARNING] signal-api is running but health check timed out
[INFO] DEBUG: Deploying storage services...
[INFO] DEBUG: Pulling minio image...
 Image minio/minio:latest Pulling 
 Image minio/minio:latest Pulled 
[INFO] DEBUG: Starting minio with explicit environment...
 Container minio Creating 
 Container minio Created 
 Container minio Starting 
 Container minio Started 
[INFO] DEBUG: Waiting for minio to become healthy...
[WARNING] minio is running but health check timed out
[INFO] DEBUG: Deploying network services...
[INFO] DEBUG: Pulling tailscale image...
 Image tailscale/tailscale:latest Pulling 
 Image tailscale/tailscale:latest Pulled 
[INFO] DEBUG: Starting tailscale with explicit environment...
 Container tailscale Creating 
 Container tailscale Created 
 Container tailscale Starting 
 Container tailscale Started 
[INFO] DEBUG: Waiting for tailscale to become healthy...
^C
jglaine@ip-172-31-2-211:~/AIPlatformAutomation/scripts$ tail -f /mnt/data/logs/deployment.log 
 Image ghcr.io/open-webui/open-webui:main Pulling 
 Image ghcr.io/open-webui/open-webui:main Pulled 
[INFO] DEBUG: Starting openwebui with explicit environment...
 Container openwebui Creating 
 Container openwebui Created 
 Container ollama Starting 
 Container ollama Started 
 Container openwebui Starting 
 Container openwebui Started 
[INFO] DEBUG: Waiting for openwebui to become healthy...
[WARNING] openwebui is running but health check timed out
[INFO] DEBUG: Pulling anythingllm image...
 Image mintplexlabs/anythingllm:latest Pulling 
 Image mintplexlabs/anythingllm:latest Pulled 
[INFO] DEBUG: Starting anythingllm with explicit environment...
 Container anythingllm Creating 
 Container anythingllm Created 
 Container anythingllm Starting 
 Container anythingllm Started 
[INFO] DEBUG: Waiting for anythingllm to become healthy...
[WARNING] anythingllm is running but health check timed out
[ERROR] Service dify not defined in /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[INFO] DEBUG: Pulling openclaw image...
 Image openclaw/openclaw:latest Pulling 
 Image openclaw/openclaw:latest Error pull access denied for openclaw/openclaw, repository does not exist or may require 'docker login': denied: requested access to the resource is denied
Error response from daemon: pull access denied for openclaw/openclaw, repository does not exist or may require 'docker login': denied: requested access to the resource is denied
[ERROR] Failed to pull openclaw image
[INFO] DEBUG: Deploying communication services...
[INFO] DEBUG: Pulling n8n image...
 Image n8nio/n8n:latest Pulling 
 Image n8nio/n8n:latest Pulled 
[INFO] DEBUG: Starting n8n with explicit environment...
 Container postgres Running 
 Container n8n Creating 
 Container n8n Created 
 Container postgres Waiting 
 Container postgres Healthy 
 Container n8n Starting 
 Container n8n Started 
[INFO] DEBUG: Waiting for n8n to become healthy...
[WARNING] n8n is running but health check timed out
[INFO] DEBUG: Pulling signal-api image...
 Image bbernhard/signal-cli-rest-api:latest Pulling 
 Image bbernhard/signal-cli-rest-api:latest Pulled 
[INFO] DEBUG: Starting signal-api with explicit environment...
 Container signal-api Creating 
 Container signal-api Created 
 Container signal-api Starting 
 Container signal-api Started 
[INFO] DEBUG: Waiting for signal-api to become healthy...
[WARNING] signal-api is running but health check timed out
[INFO] DEBUG: Deploying storage services...
[INFO] DEBUG: Pulling minio image...
 Image minio/minio:latest Pulling 
 Image minio/minio:latest Pulled 
[INFO] DEBUG: Starting minio with explicit environment...
 Container minio Creating 
 Container minio Created 
 Container minio Starting 
 Container minio Started 
[INFO] DEBUG: Waiting for minio to become healthy...
[WARNING] minio is running but health check timed out
[INFO] DEBUG: Deploying network services...
[INFO] DEBUG: Pulling tailscale image...
 Image tailscale/tailscale:latest Pulling 
 Image tailscale/tailscale:latest Pulled 
[INFO] DEBUG: Starting tailscale with explicit environment...
 Container tailscale Creating 
 Container tailscale Created 
 Container tailscale Starting 
 Container tailscale Started 
[INFO] DEBUG: Waiting for tailscale to become healthy...
