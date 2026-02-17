[1;33m[WARNING][0m Removing stale deployment lock
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[1;33m[WARNING][0m Some containers may not have stopped properly
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Aggressive network cleanup starting...
[0;36m[INFO][0m DEBUG: Stopping Docker daemon to clear network cache...
[0;36m[INFO][0m DEBUG: Docker daemon stopped
[0;36m[INFO][0m DEBUG: Force removing all ai_platform networks...
[0;36m[INFO][0m DEBUG: Removed network: ai_platform
[0;36m[INFO][0m DEBUG: Removed network: ai_platform_internal
[0;36m[INFO][0m DEBUG: Waiting for networks to be fully removed...
[0;36m[INFO][0m DEBUG: Verifying networks are actually removed...
[0;31m[ERROR][0m ERROR: ai_platform networks still exist: ai_platform
ai_platform_internal
[0;31m[ERROR][0m This indicates a fundamental network cleanup issue
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[1;33m[WARNING][0m Some containers may not have stopped properly
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Aggressive network cleanup starting...
[0;36m[INFO][0m DEBUG: Stopping Docker daemon to clear network cache...
[0;36m[INFO][0m DEBUG: Docker daemon stopped
[0;36m[INFO][0m DEBUG: Force removing all ai_platform networks...
[0;36m[INFO][0m DEBUG: Removed network: ai_platform
[0;36m[INFO][0m DEBUG: Removed network: ai_platform_internal
[0;36m[INFO][0m DEBUG: Waiting for networks to be fully removed...
[0;36m[INFO][0m DEBUG: Verifying networks are actually removed...
[0;36m[INFO][0m DEBUG: Starting Docker daemon to refresh network cache...
[1;33m[WARNING][0m WARNING: ai_platform networks still exist: ai_platform
ai_platform_internal
[1;33m[WARNING][0m Force removing remaining networks...
[0;31m[ERROR][0m ERROR: Failed to remove ai_platform networks: ai_platform
ai_platform_internal
[0;31m[ERROR][0m This indicates a fundamental network cleanup issue
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[1;33m[WARNING][0m Some containers may not have stopped properly
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Aggressive network cleanup starting...
[0;36m[INFO][0m DEBUG: Stopping Docker daemon to clear network cache...
[0;36m[INFO][0m DEBUG: Docker daemon stopped
[0;36m[INFO][0m DEBUG: Force removing all ai_platform networks...
[0;36m[INFO][0m DEBUG: Waiting for networks to be fully removed...
[0;36m[INFO][0m DEBUG: Verifying networks are actually removed...
[0;36m[INFO][0m DEBUG: Starting Docker daemon to refresh network cache...
[0;32m[SUCCESS][0m All ai_platform networks successfully removed
[0;36m[INFO][0m DEBUG: Waiting for Docker daemon to be ready...
[0;36m[INFO][0m DEBUG: Network cleanup completed successfully
[0;36m[INFO][0m Cleaning up unused volumes...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: About to terminate background processes...
[0;36m[INFO][0m DEBUG: Current PID: 4151325
[0;36m[INFO][0m DEBUG: Terminated other 2-deploy-services processes
[0;36m[INFO][0m DEBUG: Terminated docker-compose processes
[0;32m[SUCCESS][0m Pre-deployment cleanup completed
[0;36m[INFO][0m DEBUG: cleanup_previous_deployments function completed
[0;36m[INFO][0m DEBUG: About to call load_selected_services...
[0;36m[INFO][0m Loaded 15 selected services from Script 1
[0;36m[INFO][0m Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[0;36m[INFO][0m DEBUG: load_selected_services completed successfully
[0;36m[INFO][0m DEBUG: Environment variables loaded:
[0;36m[INFO][0m   RUNNING_UID: 1001
[0;36m[INFO][0m   RUNNING_GID: 1001
[0;36m[INFO][0m   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[0;36m[INFO][0m DEBUG: About to verify compose file exists...
[0;36m[INFO][0m DEBUG: Compose file verification completed
[0;32m[SUCCESS][0m Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: About to generate proxy configuration...
[0;36m[INFO][0m Generating proxy configuration for caddy...
[0;36m[INFO][0m Generating Caddy configuration...
[0;32m[SUCCESS][0m Proxy configuration generated for caddy
[0;36m[INFO][0m Adding caddy service to docker-compose.yml...
[0;36m[INFO][0m Caddy already in compose file
[0;32m[SUCCESS][0m caddy added to compose
[0;36m[INFO][0m DEBUG: About to generate critical configurations...
[0;32m[SUCCESS][0m Prometheus config generated at /mnt/data/config/prometheus/prometheus.yml
[0;36m[INFO][0m DEBUG: About to fix volume permissions...
[0;32m[SUCCESS][0m PostgreSQL volume permissions set
[0;32m[SUCCESS][0m Redis volume permissions set
[0;32m[SUCCESS][0m Grafana volume permissions set (UID 472)
[0;32m[SUCCESS][0m Ollama volume permissions set
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: Cleaning up existing networks...
[0;32m[SUCCESS][0m Created ai_platform network
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[1;33m[WARNING][0m Some containers may not have stopped properly
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Aggressive network cleanup starting...
[0;36m[INFO][0m DEBUG: Stopping Docker daemon to clear network cache...
[0;36m[INFO][0m DEBUG: Docker daemon stopped
[0;36m[INFO][0m DEBUG: Force removing all ai_platform networks...
[0;36m[INFO][0m DEBUG: Waiting for networks to be fully removed...
[0;36m[INFO][0m DEBUG: Verifying networks are actually removed...
[0;36m[INFO][0m DEBUG: Starting Docker daemon to refresh network cache...
[0;32m[SUCCESS][0m All ai_platform networks successfully removed
[0;36m[INFO][0m DEBUG: Waiting for Docker daemon to be ready...
[0;36m[INFO][0m DEBUG: Network cleanup completed successfully
[0;36m[INFO][0m Cleaning up unused volumes...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: About to terminate background processes...
[0;36m[INFO][0m DEBUG: Current PID: 4152308
[0;36m[INFO][0m DEBUG: Terminated other 2-deploy-services processes
[0;36m[INFO][0m DEBUG: Terminated docker-compose processes
[0;32m[SUCCESS][0m Pre-deployment cleanup completed
[0;36m[INFO][0m DEBUG: cleanup_previous_deployments function completed
[0;36m[INFO][0m DEBUG: About to call load_selected_services...
[0;36m[INFO][0m Loaded 15 selected services from Script 1
[0;36m[INFO][0m Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[0;36m[INFO][0m DEBUG: load_selected_services completed successfully
[0;36m[INFO][0m DEBUG: Environment variables loaded:
[0;36m[INFO][0m   RUNNING_UID: 1001
[0;36m[INFO][0m   RUNNING_GID: 1001
[0;36m[INFO][0m   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[0;36m[INFO][0m DEBUG: About to verify compose file exists...
[0;36m[INFO][0m DEBUG: Compose file verification completed
[0;32m[SUCCESS][0m Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: About to generate proxy configuration...
[0;36m[INFO][0m Generating proxy configuration for caddy...
[0;36m[INFO][0m Generating Caddy configuration...
[0;32m[SUCCESS][0m Proxy configuration generated for caddy
[0;36m[INFO][0m Adding caddy service to docker-compose.yml...
[0;36m[INFO][0m Caddy already in compose file
[0;32m[SUCCESS][0m caddy added to compose
[0;36m[INFO][0m DEBUG: About to generate critical configurations...
[0;32m[SUCCESS][0m Prometheus config generated at /mnt/data/config/prometheus/prometheus.yml
[0;36m[INFO][0m DEBUG: About to fix volume permissions...
[0;32m[SUCCESS][0m PostgreSQL volume permissions set
[0;32m[SUCCESS][0m Redis volume permissions set
[0;32m[SUCCESS][0m Grafana volume permissions set (UID 472)
[0;32m[SUCCESS][0m Ollama volume permissions set
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: Cleaning up existing networks...
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[1;33m[WARNING][0m Some containers may not have stopped properly
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Aggressive network cleanup starting...
[0;36m[INFO][0m DEBUG: Stopping Docker daemon to clear network cache...
[0;36m[INFO][0m DEBUG: Docker daemon stopped
[0;36m[INFO][0m DEBUG: Force removing all ai_platform networks...
[0;36m[INFO][0m DEBUG: Waiting for networks to be fully removed...
[0;36m[INFO][0m DEBUG: Verifying networks are actually removed...
[0;36m[INFO][0m DEBUG: Starting Docker daemon to refresh network cache...
[0;32m[SUCCESS][0m All ai_platform networks successfully removed
[0;36m[INFO][0m DEBUG: Waiting for Docker daemon to be ready...
[0;36m[INFO][0m DEBUG: Network cleanup completed successfully
[0;36m[INFO][0m Cleaning up unused volumes...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: About to terminate background processes...
[0;36m[INFO][0m DEBUG: Current PID: 4153217
[0;36m[INFO][0m DEBUG: Terminated other 2-deploy-services processes
[0;36m[INFO][0m DEBUG: Terminated docker-compose processes
[0;32m[SUCCESS][0m Pre-deployment cleanup completed
[0;36m[INFO][0m DEBUG: cleanup_previous_deployments function completed
[0;36m[INFO][0m DEBUG: About to call load_selected_services...
[0;36m[INFO][0m Loaded 15 selected services from Script 1
[0;36m[INFO][0m Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[0;36m[INFO][0m DEBUG: load_selected_services completed successfully
[0;36m[INFO][0m DEBUG: Environment variables loaded:
[0;36m[INFO][0m   RUNNING_UID: 1001
[0;36m[INFO][0m   RUNNING_GID: 1001
[0;36m[INFO][0m   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[0;36m[INFO][0m DEBUG: About to verify compose file exists...
[0;36m[INFO][0m DEBUG: Compose file verification completed
[0;32m[SUCCESS][0m Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: About to generate proxy configuration...
[0;36m[INFO][0m Generating proxy configuration for caddy...
[0;36m[INFO][0m Generating Caddy configuration...
[0;32m[SUCCESS][0m Proxy configuration generated for caddy
[0;36m[INFO][0m Adding caddy service to docker-compose.yml...
[0;36m[INFO][0m Caddy already in compose file
[0;32m[SUCCESS][0m caddy added to compose
[0;36m[INFO][0m DEBUG: About to generate critical configurations...
[0;32m[SUCCESS][0m Prometheus config generated at /mnt/data/config/prometheus/prometheus.yml
[0;36m[INFO][0m DEBUG: About to fix volume permissions...
[0;32m[SUCCESS][0m PostgreSQL volume permissions set
[0;32m[SUCCESS][0m Redis volume permissions set
[0;32m[SUCCESS][0m Grafana volume permissions set (UID 472)
[0;32m[SUCCESS][0m Ollama volume permissions set
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: Cleaning up existing networks...
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[1;33m[WARNING][0m Some containers may not have stopped properly
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Cleaning up networks...
[0;36m[INFO][0m Cleaning up unused volumes...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: About to terminate background processes...
[0;36m[INFO][0m DEBUG: Current PID: 4154478
[0;36m[INFO][0m DEBUG: Terminated other 2-deploy-services processes
[0;36m[INFO][0m DEBUG: Terminated docker-compose processes
[0;32m[SUCCESS][0m Pre-deployment cleanup completed
[0;36m[INFO][0m DEBUG: cleanup_previous_deployments function completed
[0;36m[INFO][0m DEBUG: About to call load_selected_services...
[0;36m[INFO][0m Loaded 15 selected services from Script 1
[0;36m[INFO][0m Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[0;36m[INFO][0m DEBUG: load_selected_services completed successfully
[0;36m[INFO][0m DEBUG: Environment variables loaded:
[0;36m[INFO][0m   RUNNING_UID: 1001
[0;36m[INFO][0m   RUNNING_GID: 1001
[0;36m[INFO][0m   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[0;36m[INFO][0m DEBUG: About to verify compose file exists...
[0;36m[INFO][0m DEBUG: Compose file verification completed
[0;32m[SUCCESS][0m Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: About to generate proxy configuration...
[0;36m[INFO][0m Generating proxy configuration for caddy...
[0;36m[INFO][0m Generating Caddy configuration...
[0;32m[SUCCESS][0m Proxy configuration generated for caddy
[0;36m[INFO][0m Adding caddy service to docker-compose.yml...
[0;36m[INFO][0m Caddy already in compose file
[0;32m[SUCCESS][0m caddy added to compose
[0;36m[INFO][0m DEBUG: About to generate critical configurations...
[0;32m[SUCCESS][0m Prometheus config generated at /mnt/data/config/prometheus/prometheus.yml
[0;36m[INFO][0m DEBUG: About to fix volume permissions...
[0;32m[SUCCESS][0m PostgreSQL volume permissions set
[0;32m[SUCCESS][0m Redis volume permissions set
[0;32m[SUCCESS][0m Grafana volume permissions set (UID 472)
[0;32m[SUCCESS][0m Ollama volume permissions set
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: Cleaning up existing networks...
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[1;33m[WARNING][0m Some containers may not have stopped properly
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Cleaning up networks...
[0;36m[INFO][0m Cleaning up unused volumes...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: About to terminate background processes...
[0;36m[INFO][0m DEBUG: Current PID: 4154932
[0;36m[INFO][0m DEBUG: Terminated other 2-deploy-services processes
[0;36m[INFO][0m DEBUG: Terminated docker-compose processes
[0;32m[SUCCESS][0m Pre-deployment cleanup completed
[0;36m[INFO][0m DEBUG: cleanup_previous_deployments function completed
[0;36m[INFO][0m DEBUG: About to call load_selected_services...
[0;36m[INFO][0m Loaded 15 selected services from Script 1
[0;36m[INFO][0m Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[0;36m[INFO][0m DEBUG: load_selected_services completed successfully
[0;36m[INFO][0m DEBUG: Environment variables loaded:
[0;36m[INFO][0m   RUNNING_UID: 1001
[0;36m[INFO][0m   RUNNING_GID: 1001
[0;36m[INFO][0m   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[0;36m[INFO][0m DEBUG: About to verify compose file exists...
[0;36m[INFO][0m DEBUG: Compose file verification completed
[0;32m[SUCCESS][0m Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: About to generate proxy configuration...
[0;36m[INFO][0m Generating proxy configuration for caddy...
[0;36m[INFO][0m Generating Caddy configuration...
[0;32m[SUCCESS][0m Proxy configuration generated for caddy
[0;36m[INFO][0m Adding caddy service to docker-compose.yml...
[0;36m[INFO][0m Caddy already in compose file
[0;32m[SUCCESS][0m caddy added to compose
[0;36m[INFO][0m DEBUG: About to generate critical configurations...
[0;32m[SUCCESS][0m Prometheus config generated at /mnt/data/config/prometheus/prometheus.yml
[0;36m[INFO][0m DEBUG: About to fix volume permissions...
[0;32m[SUCCESS][0m PostgreSQL volume permissions set
[0;32m[SUCCESS][0m Redis volume permissions set
[0;32m[SUCCESS][0m Grafana volume permissions set (UID 472)
[0;32m[SUCCESS][0m Ollama volume permissions set
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: Cleaning up existing networks...
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[1;33m[WARNING][0m Some containers may not have stopped properly
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Cleaning up networks...
[0;36m[INFO][0m Cleaning up unused volumes...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: About to terminate background processes...
[0;36m[INFO][0m DEBUG: Current PID: 4155387
[0;36m[INFO][0m DEBUG: Terminated other 2-deploy-services processes
[0;36m[INFO][0m DEBUG: Terminated docker-compose processes
[0;32m[SUCCESS][0m Pre-deployment cleanup completed
[0;36m[INFO][0m DEBUG: cleanup_previous_deployments function completed
[0;36m[INFO][0m DEBUG: About to call load_selected_services...
[0;36m[INFO][0m Loaded 15 selected services from Script 1
[0;36m[INFO][0m Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[0;36m[INFO][0m DEBUG: load_selected_services completed successfully
[0;36m[INFO][0m DEBUG: Environment variables loaded:
[0;36m[INFO][0m   RUNNING_UID: 1001
[0;36m[INFO][0m   RUNNING_GID: 1001
[0;36m[INFO][0m   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[0;36m[INFO][0m DEBUG: About to verify compose file exists...
[0;36m[INFO][0m DEBUG: Compose file verification completed
[0;32m[SUCCESS][0m Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: About to generate proxy configuration...
[0;36m[INFO][0m Generating proxy configuration for caddy...
[0;36m[INFO][0m Generating Caddy configuration...
[0;32m[SUCCESS][0m Proxy configuration generated for caddy
[0;36m[INFO][0m Adding caddy service to docker-compose.yml...
[0;36m[INFO][0m Caddy already in compose file
[0;32m[SUCCESS][0m caddy added to compose
[0;36m[INFO][0m DEBUG: About to generate critical configurations...
[0;32m[SUCCESS][0m Prometheus config generated at /mnt/data/config/prometheus/prometheus.yml
[0;36m[INFO][0m DEBUG: About to fix volume permissions...
[0;32m[SUCCESS][0m PostgreSQL volume permissions set
[0;32m[SUCCESS][0m Redis volume permissions set
[0;32m[SUCCESS][0m Grafana volume permissions set (UID 472)
[0;32m[SUCCESS][0m Ollama volume permissions set
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: Cleaning up existing networks...
[0;32m[SUCCESS][0m Created ai_platform network
[0;32m[SUCCESS][0m Created ai_platform_internal network
[0;36m[INFO][0m DEBUG: Docker networks created successfully
[0;36m[INFO][0m DEBUG: About to start service deployment loop...
[0;36m[INFO][0m DEBUG: Deploying core infrastructure...
[0;36m[INFO][0m DEBUG: Pulling postgres image...
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:39Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull postgres image
[0;36m[INFO][0m DEBUG: Pulling redis image...
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull redis image
[0;36m[INFO][0m DEBUG: Deploying monitoring services...
[0;36m[INFO][0m DEBUG: Pulling prometheus image...
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull prometheus image
[0;36m[INFO][0m DEBUG: Pulling grafana image...
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull grafana image
[0;36m[INFO][0m DEBUG: Deploying AI services...
[0;36m[INFO][0m DEBUG: Pulling ollama image...
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:40Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull ollama image
[0;36m[INFO][0m DEBUG: Pulling litellm image...
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull litellm image
[0;36m[INFO][0m DEBUG: Pulling openwebui image...
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull openwebui image
[0;36m[INFO][0m DEBUG: Pulling anythingllm image...
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull anythingllm image
[0;31m[ERROR][0m Service dify not defined in /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: Deploying application services...
[0;36m[INFO][0m DEBUG: Pulling n8n image...
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:41Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull n8n image
[0;36m[INFO][0m DEBUG: Pulling flowise image...
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull flowise image
[0;36m[INFO][0m DEBUG: Deploying storage and network services...
[0;36m[INFO][0m DEBUG: Pulling minio image...
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull minio image
[0;36m[INFO][0m DEBUG: Pulling tailscale image...
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull tailscale image
[0;36m[INFO][0m DEBUG: Pulling openclaw image...
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:42Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull openclaw image
[0;36m[INFO][0m DEBUG: Pulling signal-api image...
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull signal-api image
[0;36m[INFO][0m DEBUG: Deploying proxy services...
[0;36m[INFO][0m DEBUG: All services deployment completed
[0;36m[INFO][0m DEBUG: About to start core services deployment...
[0;36m[INFO][0m DEBUG: Checking core service: postgres
[0;36m[INFO][0m DEBUG: Deploying core service: postgres
[0;36m[INFO][0m DEBUG: Pulling postgres image...
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T09:20:43Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull postgres image
[0;31m[ERROR][0m ❌ ZERO TOLERANCE: Core service postgres deployment failed!
[0;31m[ERROR][0m 🚨 STOPPING DEPLOYMENT - Zero tolerance policy
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[1;33m[WARNING][0m Some containers may not have stopped properly
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Cleaning up networks...
[0;36m[INFO][0m Cleaning up unused volumes...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: About to terminate background processes...
[0;36m[INFO][0m DEBUG: Current PID: 4178673
[0;36m[INFO][0m DEBUG: Terminated other 2-deploy-services processes
[0;36m[INFO][0m DEBUG: Terminated docker-compose processes
[0;32m[SUCCESS][0m Pre-deployment cleanup completed
[0;36m[INFO][0m DEBUG: cleanup_previous_deployments function completed
[0;36m[INFO][0m DEBUG: About to call load_selected_services...
[0;36m[INFO][0m Loaded 15 selected services from Script 1
[0;36m[INFO][0m Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[0;36m[INFO][0m DEBUG: load_selected_services completed successfully
[0;36m[INFO][0m DEBUG: Environment variables loaded:
[0;36m[INFO][0m   RUNNING_UID: 1001
[0;36m[INFO][0m   RUNNING_GID: 1001
[0;36m[INFO][0m   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[0;36m[INFO][0m DEBUG: About to verify compose file exists...
[0;36m[INFO][0m DEBUG: Compose file verification completed
[0;32m[SUCCESS][0m Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: About to generate proxy configuration...
[0;36m[INFO][0m Generating proxy configuration for caddy...
[0;36m[INFO][0m Generating Caddy configuration...
[0;32m[SUCCESS][0m Proxy configuration generated for caddy
[0;36m[INFO][0m Adding caddy service to docker-compose.yml...
[0;36m[INFO][0m Caddy already in compose file
[0;32m[SUCCESS][0m caddy added to compose
[0;36m[INFO][0m DEBUG: About to generate critical configurations...
[0;32m[SUCCESS][0m Prometheus config generated at /mnt/data/config/prometheus/prometheus.yml
[0;36m[INFO][0m DEBUG: About to fix volume permissions...
[0;32m[SUCCESS][0m PostgreSQL volume permissions set
[0;32m[SUCCESS][0m Redis volume permissions set
[0;32m[SUCCESS][0m Grafana volume permissions set (UID 472)
[0;32m[SUCCESS][0m Ollama volume permissions set
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: Cleaning up existing networks...
[0;32m[SUCCESS][0m Created ai_platform network
[0;32m[SUCCESS][0m Created ai_platform_internal network
[0;36m[INFO][0m DEBUG: Docker networks created successfully
[0;36m[INFO][0m DEBUG: About to start service deployment loop...
[0;36m[INFO][0m DEBUG: Deploying core infrastructure...
[0;36m[INFO][0m DEBUG: Pulling postgres image...
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull postgres image
[0;36m[INFO][0m DEBUG: Pulling redis image...
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:00Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull redis image
[0;36m[INFO][0m DEBUG: Deploying monitoring services...
[0;36m[INFO][0m DEBUG: Pulling prometheus image...
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull prometheus image
[0;36m[INFO][0m DEBUG: Pulling grafana image...
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull grafana image
[0;36m[INFO][0m DEBUG: Deploying AI services...
[0;36m[INFO][0m DEBUG: Pulling ollama image...
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull ollama image
[0;36m[INFO][0m DEBUG: Pulling litellm image...
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull litellm image
[0;36m[INFO][0m DEBUG: Pulling openwebui image...
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull openwebui image
[0;36m[INFO][0m DEBUG: Pulling anythingllm image...
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull anythingllm image
[0;31m[ERROR][0m Service dify not defined in /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: Deploying application services...
[0;36m[INFO][0m DEBUG: Pulling n8n image...
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull n8n image
[0;36m[INFO][0m DEBUG: Pulling flowise image...
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull flowise image
[0;36m[INFO][0m DEBUG: Deploying storage and network services...
[0;36m[INFO][0m DEBUG: Pulling minio image...
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull minio image
[0;36m[INFO][0m DEBUG: Pulling tailscale image...
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull tailscale image
[0;36m[INFO][0m DEBUG: Pulling openclaw image...
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull openclaw image
[0;36m[INFO][0m DEBUG: Pulling signal-api image...
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull signal-api image
[0;36m[INFO][0m DEBUG: Deploying proxy services...
[0;36m[INFO][0m DEBUG: All services deployment completed
[0;36m[INFO][0m DEBUG: About to start core services deployment...
[0;36m[INFO][0m DEBUG: Checking core service: postgres
[0;36m[INFO][0m DEBUG: Deploying core service: postgres
[0;36m[INFO][0m DEBUG: Pulling postgres image...
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:43:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull postgres image
[0;31m[ERROR][0m ❌ ZERO TOLERANCE: Core service postgres deployment failed!
[0;31m[ERROR][0m 🚨 STOPPING DEPLOYMENT - Zero tolerance policy
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[1;33m[WARNING][0m Some containers may not have stopped properly
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Cleaning up networks...
[0;36m[INFO][0m Cleaning up unused volumes...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: About to terminate background processes...
[0;36m[INFO][0m DEBUG: Current PID: 4179931
[0;36m[INFO][0m DEBUG: Terminated other 2-deploy-services processes
[0;36m[INFO][0m DEBUG: Terminated docker-compose processes
[0;32m[SUCCESS][0m Pre-deployment cleanup completed
[0;36m[INFO][0m DEBUG: cleanup_previous_deployments function completed
[0;36m[INFO][0m DEBUG: About to call load_selected_services...
[0;36m[INFO][0m Loaded 15 selected services from Script 1
[0;36m[INFO][0m Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[0;36m[INFO][0m DEBUG: load_selected_services completed successfully
[0;36m[INFO][0m DEBUG: Environment variables loaded:
[0;36m[INFO][0m   RUNNING_UID: 1001
[0;36m[INFO][0m   RUNNING_GID: 1001
[0;36m[INFO][0m   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[0;36m[INFO][0m DEBUG: About to verify compose file exists...
[0;36m[INFO][0m DEBUG: Compose file verification completed
[0;32m[SUCCESS][0m Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: About to generate proxy configuration...
[0;36m[INFO][0m Generating proxy configuration for caddy...
[0;36m[INFO][0m Generating Caddy configuration...
[0;32m[SUCCESS][0m Proxy configuration generated for caddy
[0;36m[INFO][0m Adding caddy service to docker-compose.yml...
[0;36m[INFO][0m Caddy already in compose file
[0;32m[SUCCESS][0m caddy added to compose
[0;36m[INFO][0m DEBUG: About to generate critical configurations...
[0;32m[SUCCESS][0m Prometheus config generated at /mnt/data/config/prometheus/prometheus.yml
[0;36m[INFO][0m DEBUG: About to fix volume permissions...
[0;32m[SUCCESS][0m PostgreSQL volume permissions set
[0;32m[SUCCESS][0m Redis volume permissions set
[0;32m[SUCCESS][0m Grafana volume permissions set (UID 472)
[0;32m[SUCCESS][0m Ollama volume permissions set
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: Cleaning up existing networks...
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[1;33m[WARNING][0m Some containers may not have stopped properly
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Cleaning up networks...
[0;36m[INFO][0m Cleaning up unused volumes...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: About to terminate background processes...
[0;36m[INFO][0m DEBUG: Current PID: 4180323
[0;36m[INFO][0m DEBUG: Terminated other 2-deploy-services processes
[0;36m[INFO][0m DEBUG: Terminated docker-compose processes
[0;32m[SUCCESS][0m Pre-deployment cleanup completed
[0;36m[INFO][0m DEBUG: cleanup_previous_deployments function completed
[0;36m[INFO][0m DEBUG: About to call load_selected_services...
[0;36m[INFO][0m Loaded 15 selected services from Script 1
[0;36m[INFO][0m Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[0;36m[INFO][0m DEBUG: load_selected_services completed successfully
[0;36m[INFO][0m DEBUG: Environment variables loaded:
[0;36m[INFO][0m   RUNNING_UID: 1001
[0;36m[INFO][0m   RUNNING_GID: 1001
[0;36m[INFO][0m   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[0;36m[INFO][0m DEBUG: About to verify compose file exists...
[0;36m[INFO][0m DEBUG: Compose file verification completed
[0;32m[SUCCESS][0m Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: About to generate proxy configuration...
[0;36m[INFO][0m Generating proxy configuration for caddy...
[0;36m[INFO][0m Generating Caddy configuration...
[0;32m[SUCCESS][0m Proxy configuration generated for caddy
[0;36m[INFO][0m Adding caddy service to docker-compose.yml...
[0;36m[INFO][0m Caddy already in compose file
[0;32m[SUCCESS][0m caddy added to compose
[0;36m[INFO][0m DEBUG: About to generate critical configurations...
[0;32m[SUCCESS][0m Prometheus config generated at /mnt/data/config/prometheus/prometheus.yml
[0;36m[INFO][0m DEBUG: About to fix volume permissions...
[0;32m[SUCCESS][0m PostgreSQL volume permissions set
[0;32m[SUCCESS][0m Redis volume permissions set
[0;32m[SUCCESS][0m Grafana volume permissions set (UID 472)
[0;32m[SUCCESS][0m Ollama volume permissions set
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: Cleaning up existing networks...
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[1;33m[WARNING][0m Some containers may not have stopped properly
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Cleaning up networks...
[0;36m[INFO][0m Cleaning up unused volumes...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: About to terminate background processes...
[0;36m[INFO][0m DEBUG: Current PID: 4180765
[0;36m[INFO][0m DEBUG: Terminated other 2-deploy-services processes
[0;36m[INFO][0m DEBUG: Terminated docker-compose processes
[0;32m[SUCCESS][0m Pre-deployment cleanup completed
[0;36m[INFO][0m DEBUG: cleanup_previous_deployments function completed
[0;36m[INFO][0m DEBUG: About to call load_selected_services...
[0;36m[INFO][0m Loaded 15 selected services from Script 1
[0;36m[INFO][0m Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[0;36m[INFO][0m DEBUG: load_selected_services completed successfully
[0;36m[INFO][0m DEBUG: Environment variables loaded:
[0;36m[INFO][0m   RUNNING_UID: 1001
[0;36m[INFO][0m   RUNNING_GID: 1001
[0;36m[INFO][0m   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[0;36m[INFO][0m DEBUG: About to verify compose file exists...
[0;36m[INFO][0m DEBUG: Compose file verification completed
[0;32m[SUCCESS][0m Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: About to generate proxy configuration...
[0;36m[INFO][0m Generating proxy configuration for caddy...
[0;36m[INFO][0m Generating Caddy configuration...
[0;32m[SUCCESS][0m Proxy configuration generated for caddy
[0;36m[INFO][0m Adding caddy service to docker-compose.yml...
[0;36m[INFO][0m Caddy already in compose file
[0;32m[SUCCESS][0m caddy added to compose
[0;36m[INFO][0m DEBUG: About to generate critical configurations...
[0;32m[SUCCESS][0m Prometheus config generated at /mnt/data/config/prometheus/prometheus.yml
[0;36m[INFO][0m DEBUG: About to fix volume permissions...
[0;32m[SUCCESS][0m PostgreSQL volume permissions set
[0;32m[SUCCESS][0m Redis volume permissions set
[0;32m[SUCCESS][0m Grafana volume permissions set (UID 472)
[0;32m[SUCCESS][0m Ollama volume permissions set
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: Cleaning up existing networks...
[0;32m[SUCCESS][0m Created ai_platform network
[0;32m[SUCCESS][0m Created ai_platform_internal network
[0;36m[INFO][0m DEBUG: Docker networks created successfully
[0;36m[INFO][0m DEBUG: About to start service deployment loop...
[0;36m[INFO][0m DEBUG: Deploying core infrastructure...
[0;36m[INFO][0m DEBUG: Pulling postgres image...
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull postgres image
[0;36m[INFO][0m DEBUG: Pulling redis image...
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:01Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull redis image
[0;36m[INFO][0m DEBUG: Deploying monitoring services...
[0;36m[INFO][0m DEBUG: Pulling prometheus image...
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull prometheus image
[0;36m[INFO][0m DEBUG: Pulling grafana image...
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull grafana image
[0;36m[INFO][0m DEBUG: Deploying AI services...
[0;36m[INFO][0m DEBUG: Pulling ollama image...
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:02Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull ollama image
[0;36m[INFO][0m DEBUG: Pulling litellm image...
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull litellm image
[0;36m[INFO][0m DEBUG: Pulling openwebui image...
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull openwebui image
[0;36m[INFO][0m DEBUG: Pulling anythingllm image...
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull anythingllm image
[0;31m[ERROR][0m Service dify not defined in /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: Deploying application services...
[0;36m[INFO][0m DEBUG: Pulling n8n image...
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull n8n image
[0;36m[INFO][0m DEBUG: Pulling flowise image...
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:03Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull flowise image
[0;36m[INFO][0m DEBUG: Deploying storage and network services...
[0;36m[INFO][0m DEBUG: Pulling minio image...
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull minio image
[0;36m[INFO][0m DEBUG: Pulling tailscale image...
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull tailscale image
[0;36m[INFO][0m DEBUG: Pulling openclaw image...
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull openclaw image
[0;36m[INFO][0m DEBUG: Pulling signal-api image...
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:04Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull signal-api image
[0;36m[INFO][0m DEBUG: Deploying proxy services...
[0;36m[INFO][0m DEBUG: All services deployment completed
[0;36m[INFO][0m DEBUG: About to start core services deployment...
[0;36m[INFO][0m DEBUG: Checking core service: postgres
[0;36m[INFO][0m DEBUG: Deploying core service: postgres
[0;36m[INFO][0m DEBUG: Pulling postgres image...
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
time="2026-02-17T10:45:05Z" level=warning msg="The \"DATA_ROOT\" variable is not set. Defaulting to a blank string."
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull postgres image
[0;31m[ERROR][0m ❌ ZERO TOLERANCE: Core service postgres deployment failed!
[0;31m[ERROR][0m 🚨 STOPPING DEPLOYMENT - Zero tolerance policy
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[1;33m[WARNING][0m Some containers may not have stopped properly
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Cleaning up networks...
[0;36m[INFO][0m Cleaning up unused volumes...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: About to terminate background processes...
[0;36m[INFO][0m DEBUG: Current PID: 4182939
[0;36m[INFO][0m DEBUG: Terminated other 2-deploy-services processes
[0;36m[INFO][0m DEBUG: Terminated docker-compose processes
[0;32m[SUCCESS][0m Pre-deployment cleanup completed
[0;36m[INFO][0m DEBUG: cleanup_previous_deployments function completed
[0;36m[INFO][0m DEBUG: About to call load_selected_services...
[0;36m[INFO][0m Loaded 15 selected services from Script 1
[0;36m[INFO][0m Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[0;36m[INFO][0m DEBUG: load_selected_services completed successfully
[0;36m[INFO][0m DEBUG: Environment variables loaded:
[0;36m[INFO][0m   RUNNING_UID: 1001
[0;36m[INFO][0m   RUNNING_GID: 1001
[0;36m[INFO][0m   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[0;36m[INFO][0m DEBUG: About to verify compose file exists...
[0;36m[INFO][0m DEBUG: Compose file verification completed
[0;32m[SUCCESS][0m Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: About to generate proxy configuration...
[0;36m[INFO][0m Generating proxy configuration for caddy...
[0;36m[INFO][0m Generating Caddy configuration...
[0;32m[SUCCESS][0m Proxy configuration generated for caddy
[0;36m[INFO][0m Adding caddy service to docker-compose.yml...
[0;36m[INFO][0m Caddy already in compose file
[0;32m[SUCCESS][0m caddy added to compose
[0;36m[INFO][0m DEBUG: About to generate critical configurations...
[0;32m[SUCCESS][0m Prometheus config generated at /mnt/data/config/prometheus/prometheus.yml
[0;36m[INFO][0m DEBUG: About to fix volume permissions...
[0;32m[SUCCESS][0m PostgreSQL volume permissions set
[0;32m[SUCCESS][0m Redis volume permissions set
[0;32m[SUCCESS][0m Grafana volume permissions set (UID 472)
[0;32m[SUCCESS][0m Ollama volume permissions set
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: Cleaning up existing networks...
[0;32m[SUCCESS][0m Created ai_platform network
[0;32m[SUCCESS][0m Created ai_platform_internal network
[0;36m[INFO][0m DEBUG: Docker networks created successfully
[0;36m[INFO][0m DEBUG: About to start service deployment loop...
[0;36m[INFO][0m DEBUG: Deploying core infrastructure...
[0;36m[INFO][0m DEBUG: Pulling postgres image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull postgres image
[0;36m[INFO][0m DEBUG: Pulling redis image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull redis image
[0;36m[INFO][0m DEBUG: Deploying monitoring services...
[0;36m[INFO][0m DEBUG: Pulling prometheus image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull prometheus image
[0;36m[INFO][0m DEBUG: Pulling grafana image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull grafana image
[0;36m[INFO][0m DEBUG: Deploying AI services...
[0;36m[INFO][0m DEBUG: Pulling ollama image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull ollama image
[0;36m[INFO][0m DEBUG: Pulling litellm image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull litellm image
[0;36m[INFO][0m DEBUG: Pulling openwebui image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull openwebui image
[0;36m[INFO][0m DEBUG: Pulling anythingllm image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull anythingllm image
[0;31m[ERROR][0m Service dify not defined in /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: Deploying application services...
[0;36m[INFO][0m DEBUG: Pulling n8n image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull n8n image
[0;36m[INFO][0m DEBUG: Pulling flowise image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull flowise image
[0;36m[INFO][0m DEBUG: Deploying storage and network services...
[0;36m[INFO][0m DEBUG: Pulling minio image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull minio image
[0;36m[INFO][0m DEBUG: Pulling tailscale image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull tailscale image
[0;36m[INFO][0m DEBUG: Pulling openclaw image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull openclaw image
[0;36m[INFO][0m DEBUG: Pulling signal-api image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull signal-api image
[0;36m[INFO][0m DEBUG: Deploying proxy services...
[0;36m[INFO][0m DEBUG: All services deployment completed
[0;36m[INFO][0m DEBUG: About to start core services deployment...
[0;36m[INFO][0m DEBUG: Checking core service: postgres
[0;36m[INFO][0m DEBUG: Deploying core service: postgres
[0;36m[INFO][0m DEBUG: Pulling postgres image...
validating /mnt/data/ai-platform/deployment/stack/docker-compose.yml: volumes must be a mapping
[0;31m[ERROR][0m Failed to pull postgres image
[0;31m[ERROR][0m ❌ ZERO TOLERANCE: Core service postgres deployment failed!
[0;31m[ERROR][0m 🚨 STOPPING DEPLOYMENT - Zero tolerance policy
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
[0;32m[SUCCESS][0m All containers stopped successfully
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Cleaning up networks...
[0;36m[INFO][0m Cleaning up unused volumes...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: About to terminate background processes...
[0;36m[INFO][0m DEBUG: Current PID: 4184314
[0;36m[INFO][0m DEBUG: Terminated other 2-deploy-services processes
[0;36m[INFO][0m DEBUG: Terminated docker-compose processes
[0;32m[SUCCESS][0m Pre-deployment cleanup completed
[0;36m[INFO][0m DEBUG: cleanup_previous_deployments function completed
[0;36m[INFO][0m DEBUG: About to call load_selected_services...
[0;36m[INFO][0m Loaded 15 selected services from Script 1
[0;36m[INFO][0m Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[0;36m[INFO][0m DEBUG: load_selected_services completed successfully
[0;36m[INFO][0m DEBUG: Environment variables loaded:
[0;36m[INFO][0m   RUNNING_UID: 1001
[0;36m[INFO][0m   RUNNING_GID: 1001
[0;36m[INFO][0m   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[0;36m[INFO][0m DEBUG: About to verify compose file exists...
[0;36m[INFO][0m DEBUG: Compose file verification completed
[0;32m[SUCCESS][0m Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: About to generate proxy configuration...
[0;36m[INFO][0m Generating proxy configuration for caddy...
[0;36m[INFO][0m Generating Caddy configuration...
[0;32m[SUCCESS][0m Proxy configuration generated for caddy
[0;36m[INFO][0m Adding caddy service to docker-compose.yml...
[0;36m[INFO][0m Caddy already in compose file
[0;32m[SUCCESS][0m caddy added to compose
[0;36m[INFO][0m DEBUG: About to generate critical configurations...
[0;32m[SUCCESS][0m Prometheus config generated at /mnt/data/config/prometheus/prometheus.yml
[0;36m[INFO][0m DEBUG: About to fix volume permissions...
[0;32m[SUCCESS][0m PostgreSQL volume permissions set
[0;32m[SUCCESS][0m Redis volume permissions set
[0;32m[SUCCESS][0m Grafana volume permissions set (UID 472)
[0;32m[SUCCESS][0m Ollama volume permissions set
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: Cleaning up existing networks...
[0;32m[SUCCESS][0m Created ai_platform network
[0;36m[INFO][0m DEBUG: Docker networks created successfully
[0;36m[INFO][0m DEBUG: About to start service deployment loop...
[0;36m[INFO][0m DEBUG: Deploying core infrastructure...
[0;36m[INFO][0m DEBUG: Pulling postgres image...
 Image postgres:15-alpine Pulling 
 Image postgres:15-alpine Pulled 
[0;36m[INFO][0m DEBUG: Starting postgres with explicit environment...
 Container postgres Creating 
 Container postgres Created 
 Container postgres Starting 
 Container postgres Started 
[0;36m[INFO][0m DEBUG: Waiting for postgres to become healthy...
[0;36m[INFO][0m Waiting for PostgreSQL to be ready (max 60s)...
[0;32m[SUCCESS][0m PostgreSQL is ready
[0;36m[INFO][0m DEBUG: Pulling redis image...
 Image redis:7-alpine Pulling 
 Image redis:7-alpine Pulled 
[0;36m[INFO][0m DEBUG: Starting redis with explicit environment...
 Container redis Creating 
 Container redis Created 
 Container redis Starting 
 Container redis Started 
[0;36m[INFO][0m DEBUG: Waiting for redis to become healthy...
[0;36m[INFO][0m Waiting for Redis to be ready (max 30s)...
[0;31m[ERROR][0m Redis failed to become ready after 30 seconds
[1;33m[WARNING][0m redis is running but health check timed out
[0;36m[INFO][0m DEBUG: Deploying monitoring services...
[0;36m[INFO][0m DEBUG: Pulling prometheus image...
 Image prom/prometheus:latest Pulling 
 Image prom/prometheus:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting prometheus with explicit environment...
 Container prometheus Starting 
 Container prometheus Started 
[0;36m[INFO][0m DEBUG: Waiting for prometheus to become healthy...
[0;36m[INFO][0m Waiting for prometheus to be healthy (max 180s)...
[0;31m[ERROR][0m prometheus failed to become healthy after 180 seconds
panic: Unable to create mmap-ed active query log

goroutine 1 [running]:
github.com/prometheus/prometheus/promql.NewActiveQueryTracker({0x7ffde4d1aed8, 0xb}, 0x14, 0xc00007a6c0)
	/app/promql/query_logger.go:145 +0x345
main.main()
	/app/cmd/prometheus/main.go:894 +0x8953
time=2026-02-17T10:53:36.524Z level=INFO source=main.go:1589 msg="updated GOGC" old=100 new=75
time=2026-02-17T10:53:36.524Z level=INFO source=main.go:704 msg="Leaving GOMAXPROCS=2: CPU quota undefined" component=automaxprocs
time=2026-02-17T10:53:36.525Z level=INFO source=memlimit.go:198 msg="GOMEMLIMIT is updated" component=automemlimit package=github.com/KimMachineGun/automemlimit/memlimit GOMEMLIMIT=7380773683 previous=9223372036854775807
time=2026-02-17T10:53:36.525Z level=INFO source=main.go:803 msg="Starting Prometheus Server" mode=server version="(version=3.9.1, branch=HEAD, revision=9ec59baffb547e24f1468a53eb82901e58feabd8)"
time=2026-02-17T10:53:36.525Z level=INFO source=main.go:808 msg="operational information" build_context="(go=go1.25.5, platform=linux/amd64, user=root@61c3a9212c9e, date=20260107-16:08:09, tags=netgo,builtinassets)" host_details="(Linux 6.14.0-1018-aws #18~24.04.1-Ubuntu SMP Mon Nov 24 19:46:27 UTC 2025 x86_64 d102b58813ef (none))" fd_limits="(soft=524287, hard=524288)" vm_limits="(soft=unlimited, hard=unlimited)"
time=2026-02-17T10:53:36.527Z level=ERROR source=query_logger.go:113 msg="Error opening query log file" component=activeQueryTracker file=/prometheus/queries.active err="open /prometheus/queries.active: permission denied"
panic: Unable to create mmap-ed active query log

goroutine 1 [running]:
github.com/prometheus/prometheus/promql.NewActiveQueryTracker({0x7fff27bcbed8, 0xb}, 0x14, 0xc00046cb80)
	/app/promql/query_logger.go:145 +0x345
main.main()
	/app/cmd/prometheus/main.go:894 +0x8953
[1;33m[WARNING][0m prometheus is running but health check timed out
[0;36m[INFO][0m DEBUG: Pulling grafana image...
 Image grafana/grafana:latest Pulling 
 Image grafana/grafana:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting grafana with explicit environment...
 Network ai_platform Creating 
 Network ai_platform Created 
 Container grafana Creating 
 Container grafana Created 
 Container grafana Starting 
 Container grafana Started 
[0;36m[INFO][0m DEBUG: Waiting for grafana to become healthy...
[0;36m[INFO][0m Waiting for grafana to be healthy (max 180s)...
[0;31m[ERROR][0m grafana failed to become healthy after 180 seconds
You may have issues with file permissions, more information here: http://docs.grafana.org/installation/docker/#migrate-to-v51-or-later
mkdir: can't create directory '/var/lib/grafana/plugins': Permission denied
GF_PATHS_DATA='/var/lib/grafana' is not writable.
You may have issues with file permissions, more information here: http://docs.grafana.org/installation/docker/#migrate-to-v51-or-later
mkdir: can't create directory '/var/lib/grafana/plugins': Permission denied
GF_PATHS_DATA='/var/lib/grafana' is not writable.
You may have issues with file permissions, more information here: http://docs.grafana.org/installation/docker/#migrate-to-v51-or-later
mkdir: can't create directory '/var/lib/grafana/plugins': Permission denied
GF_PATHS_DATA='/var/lib/grafana' is not writable.
You may have issues with file permissions, more information here: http://docs.grafana.org/installation/docker/#migrate-to-v51-or-later
mkdir: can't create directory '/var/lib/grafana/plugins': Permission denied
GF_PATHS_DATA='/var/lib/grafana' is not writable.
You may have issues with file permissions, more information here: http://docs.grafana.org/installation/docker/#migrate-to-v51-or-later
mkdir: can't create directory '/var/lib/grafana/plugins': Permission denied
GF_PATHS_DATA='/var/lib/grafana' is not writable.
You may have issues with file permissions, more information here: http://docs.grafana.org/installation/docker/#migrate-to-v51-or-later
mkdir: can't create directory '/var/lib/grafana/plugins': Permission denied
GF_PATHS_DATA='/var/lib/grafana' is not writable.
You may have issues with file permissions, more information here: http://docs.grafana.org/installation/docker/#migrate-to-v51-or-later
mkdir: can't create directory '/var/lib/grafana/plugins': Permission denied
[1;33m[WARNING][0m grafana is running but health check timed out
[0;36m[INFO][0m DEBUG: Deploying AI services...
[0;36m[INFO][0m DEBUG: Pulling ollama image...
 Image ollama/ollama:latest Pulling 
 Image ollama/ollama:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting ollama with explicit environment...
 Container ollama Creating 
 Container ollama Created 
 Container ollama Starting 
 Container ollama Started 
[0;36m[INFO][0m DEBUG: Waiting for ollama to become healthy...
[0;36m[INFO][0m Waiting for ollama to be healthy (max 180s)...
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
 Container prometheus Stopping 
 Container postgres Stopping 
 Container ollama Stopping 
 Container redis Stopping 
 Container grafana Stopping 
 Container ollama Stopped 
 Container ollama Removing 
 Container prometheus Stopped 
 Container prometheus Removing 
 Container grafana Stopped 
 Container grafana Removing 
 Container prometheus Removed 
 Container grafana Removed 
 Container ollama Removed 
 Container redis Stopped 
 Container redis Removing 
 Container redis Removed 
 Container postgres Stopped 
 Container postgres Removing 
 Container postgres Removed 
 Network ai_platform Removing 
 Network ai_platform_internal Removing 
 Network ai_platform Removed 
 Network ai_platform_internal Removed 
[0;32m[SUCCESS][0m All containers stopped successfully
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Cleaning up networks...
[0;36m[INFO][0m Cleaning up unused volumes...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: About to terminate background processes...
[0;36m[INFO][0m DEBUG: Current PID: 9545
[0;36m[INFO][0m DEBUG: Terminated other 2-deploy-services processes
[0;36m[INFO][0m DEBUG: Terminated docker-compose processes
[0;32m[SUCCESS][0m Pre-deployment cleanup completed
[0;36m[INFO][0m DEBUG: cleanup_previous_deployments function completed
[0;36m[INFO][0m DEBUG: About to call load_selected_services...
[0;36m[INFO][0m Loaded 15 selected services from Script 1
[0;36m[INFO][0m Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[0;36m[INFO][0m DEBUG: load_selected_services completed successfully
[0;36m[INFO][0m DEBUG: Environment variables loaded:
[0;36m[INFO][0m   RUNNING_UID: 1001
[0;36m[INFO][0m   RUNNING_GID: 1001
[0;36m[INFO][0m   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[0;36m[INFO][0m DEBUG: About to verify compose file exists...
[0;36m[INFO][0m DEBUG: Compose file verification completed
[0;32m[SUCCESS][0m Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: About to generate proxy configuration...
[0;36m[INFO][0m Generating proxy configuration for caddy...
[0;36m[INFO][0m Generating Caddy configuration...
[0;32m[SUCCESS][0m Proxy configuration generated for caddy
[0;36m[INFO][0m Adding caddy service to docker-compose.yml...
[0;36m[INFO][0m Caddy already in compose file
[0;32m[SUCCESS][0m caddy added to compose
[0;36m[INFO][0m DEBUG: About to generate critical configurations...
[0;32m[SUCCESS][0m Prometheus config generated at /mnt/data/config/prometheus/prometheus.yml
[0;36m[INFO][0m DEBUG: About to fix volume permissions...
[0;32m[SUCCESS][0m PostgreSQL volume permissions set
[0;32m[SUCCESS][0m Redis volume permissions set
[0;36m[INFO][0m Setting up Grafana permissions (UID 472)...
[0;32m[SUCCESS][0m Grafana volume permissions set (UID 472)
[0;32m[SUCCESS][0m Ollama volume permissions set
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: Cleaning up existing networks...
[0;32m[SUCCESS][0m Created ai_platform network
[0;36m[INFO][0m DEBUG: Docker networks created successfully
[0;36m[INFO][0m DEBUG: About to start service deployment loop...
[0;36m[INFO][0m DEBUG: Deploying core infrastructure...
[0;36m[INFO][0m DEBUG: Pulling postgres image...
 Image postgres:15-alpine Pulling 
 Image postgres:15-alpine Pulled 
[0;36m[INFO][0m DEBUG: Starting postgres with explicit environment...
 Container postgres Creating 
 Container postgres Created 
 Container postgres Starting 
 Container postgres Started 
[0;36m[INFO][0m DEBUG: Waiting for postgres to become healthy...
[0;36m[INFO][0m Waiting for PostgreSQL to be ready (max 60s)...
[0;32m[SUCCESS][0m PostgreSQL is ready
[0;36m[INFO][0m DEBUG: Pulling redis image...
 Image redis:7-alpine Pulling 
 Image redis:7-alpine Pulled 
[0;36m[INFO][0m DEBUG: Starting redis with explicit environment...
 Container redis Creating 
 Container redis Created 
 Container redis Starting 
 Container redis Started 
[0;36m[INFO][0m DEBUG: Waiting for redis to become healthy...
[0;36m[INFO][0m Waiting for Redis to be ready (max 30s)...
[0;31m[ERROR][0m Redis failed to become ready after 30 seconds
[1;33m[WARNING][0m redis is running but health check timed out
[0;36m[INFO][0m DEBUG: Deploying monitoring services...
[0;36m[INFO][0m DEBUG: Pulling prometheus image...
 Image prom/prometheus:latest Pulling 
 Image prom/prometheus:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting prometheus with explicit environment...
 Container prometheus Starting 
 Container prometheus Started 
[0;36m[INFO][0m DEBUG: Waiting for prometheus to become healthy...
[0;36m[INFO][0m Waiting for prometheus to be healthy (max 180s)...
[0;31m[ERROR][0m prometheus failed to become healthy after 180 seconds
panic: Unable to create mmap-ed active query log

goroutine 1 [running]:
github.com/prometheus/prometheus/promql.NewActiveQueryTracker({0x7ffe3a485ed8, 0xb}, 0x14, 0xc00061eb50)
	/app/promql/query_logger.go:145 +0x345
main.main()
	/app/cmd/prometheus/main.go:894 +0x8953
time=2026-02-17T11:04:20.128Z level=INFO source=main.go:1589 msg="updated GOGC" old=100 new=75
time=2026-02-17T11:04:20.129Z level=INFO source=main.go:704 msg="Leaving GOMAXPROCS=2: CPU quota undefined" component=automaxprocs
time=2026-02-17T11:04:20.129Z level=INFO source=memlimit.go:198 msg="GOMEMLIMIT is updated" component=automemlimit package=github.com/KimMachineGun/automemlimit/memlimit GOMEMLIMIT=7380773683 previous=9223372036854775807
time=2026-02-17T11:04:20.129Z level=INFO source=main.go:803 msg="Starting Prometheus Server" mode=server version="(version=3.9.1, branch=HEAD, revision=9ec59baffb547e24f1468a53eb82901e58feabd8)"
time=2026-02-17T11:04:20.130Z level=INFO source=main.go:808 msg="operational information" build_context="(go=go1.25.5, platform=linux/amd64, user=root@61c3a9212c9e, date=20260107-16:08:09, tags=netgo,builtinassets)" host_details="(Linux 6.14.0-1018-aws #18~24.04.1-Ubuntu SMP Mon Nov 24 19:46:27 UTC 2025 x86_64 4e891db7dce5 (none))" fd_limits="(soft=524287, hard=524288)" vm_limits="(soft=unlimited, hard=unlimited)"
time=2026-02-17T11:04:20.132Z level=ERROR source=query_logger.go:113 msg="Error opening query log file" component=activeQueryTracker file=/prometheus/queries.active err="open /prometheus/queries.active: permission denied"
panic: Unable to create mmap-ed active query log

goroutine 1 [running]:
github.com/prometheus/prometheus/promql.NewActiveQueryTracker({0x7fff15364ed8, 0xb}, 0x14, 0xc0002b8c90)
	/app/promql/query_logger.go:145 +0x345
main.main()
	/app/cmd/prometheus/main.go:894 +0x8953
[1;33m[WARNING][0m prometheus is running but health check timed out
[0;36m[INFO][0m DEBUG: Pulling grafana image...
 Image grafana/grafana:latest Pulling 
 Image grafana/grafana:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting grafana with explicit environment...
 Network ai_platform Creating 
 Network ai_platform Created 
 Container grafana Creating 
 Container grafana Created 
 Container grafana Starting 
 Container grafana Started 
[0;36m[INFO][0m DEBUG: Waiting for grafana to become healthy...
[0;36m[INFO][0m Waiting for grafana to be healthy (max 180s)...
[0;32m[SUCCESS][0m grafana is healthy
[0;36m[INFO][0m DEBUG: Deploying AI services...
[0;36m[INFO][0m DEBUG: Pulling ollama image...
 Image ollama/ollama:latest Pulling 
 Image ollama/ollama:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting ollama with explicit environment...
 Container ollama Creating 
 Container ollama Created 
 Container ollama Starting 
 Container ollama Started 
[0;36m[INFO][0m DEBUG: Waiting for ollama to become healthy...
[0;36m[INFO][0m Waiting for ollama to be healthy (max 180s)...
[0;31m[ERROR][0m ollama failed to become healthy after 180 seconds
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
[1;33m[WARNING][0m ollama is running but health check timed out
[0;36m[INFO][0m DEBUG: Pulling litellm image...
 Image ghcr.io/berriai/litellm:main-latest Pulling 
 Image ghcr.io/berriai/litellm:main-latest Pulled 
[0;36m[INFO][0m DEBUG: Starting litellm with explicit environment...
 Container postgres Running 
 Container redis Running 
 Container litellm Creating 
 Container litellm Created 
 Container redis Waiting 
 Container postgres Waiting 
 Container redis Healthy 
 Container postgres Healthy 
 Container litellm Starting 
 Container litellm Started 
[0;36m[INFO][0m DEBUG: Waiting for litellm to become healthy...
[0;36m[INFO][0m Waiting for litellm to be healthy (max 180s)...
[0;31m[ERROR][0m litellm failed to become healthy after 180 seconds
           ~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.13/site-packages/click/core.py", line 783, in invoke
    return __callback(*args, **kwargs)
  File "/usr/lib/python3.13/site-packages/litellm/proxy/proxy_cli.py", line 670, in run_server
    _config = asyncio.run(proxy_config.get_config(config_file_path=config))
  File "/usr/lib/python3.13/asyncio/runners.py", line 195, in run
    return runner.run(main)
           ~~~~~~~~~~^^^^^^
  File "/usr/lib/python3.13/asyncio/runners.py", line 118, in run
    return self._loop.run_until_complete(task)
           ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^
  File "/usr/lib/python3.13/asyncio/base_events.py", line 725, in run_until_complete
    return future.result()
           ~~~~~~~~~~~~~^^
  File "/usr/lib/python3.13/site-packages/litellm/proxy/proxy_server.py", line 2318, in get_config
    config = await self._get_config_from_file(config_file_path=config_file_path)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.13/site-packages/litellm/proxy/proxy_server.py", line 2068, in _get_config_from_file
    raise Exception(f"Config file not found: {file_path}")
Exception: Config file not found: /app/config/config.yaml
[1;33m[WARNING][0m litellm is running but health check timed out
[0;36m[INFO][0m DEBUG: Pulling openwebui image...
 Image ghcr.io/open-webui/open-webui:main Pulling 
 Image ghcr.io/open-webui/open-webui:main Pulled 
[0;36m[INFO][0m DEBUG: Starting openwebui with explicit environment...
 Container openwebui Creating 
 Container openwebui Created 
 Container ollama Starting 
 Container ollama Started 
 Container openwebui Starting 
 Container openwebui Started 
[0;36m[INFO][0m DEBUG: Waiting for openwebui to become healthy...
[0;36m[INFO][0m Waiting for openwebui to be healthy (max 180s)...
[0;31m[ERROR][0m openwebui failed to become healthy after 180 seconds
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 196, in reraise
    raise value.with_traceback(tb)
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 3321, in execute_sql
    cursor = self.cursor()
             ^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 3311, in cursor
    self.connect()
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 3262, in connect
    with __exception_wrapper__:
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 3088, in __exit__
    reraise(new_type, new_type(exc_value, *exc_args), traceback)
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 196, in reraise
    raise value.with_traceback(tb)
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 3263, in connect
    self._state.set_connection(self._connect())
                               ^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 3604, in _connect
    conn = sqlite3.connect(self.database, timeout=self._timeout,
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
peewee.OperationalError: unable to open database file
[1;33m[WARNING][0m openwebui is running but health check timed out
[0;36m[INFO][0m DEBUG: Pulling anythingllm image...
 Image mintplexlabs/anythingllm:latest Pulling 
 Image mintplexlabs/anythingllm:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting anythingllm with explicit environment...
 Container anythingllm Creating 
 Container anythingllm Created 
 Container anythingllm Starting 
 Container anythingllm Started 
[0;36m[INFO][0m DEBUG: Waiting for anythingllm to become healthy...
[0;36m[INFO][0m Waiting for anythingllm to be healthy (max 180s)...
[0;31m[ERROR][0m anythingllm failed to become healthy after 180 seconds
/usr/local/bin/docker-entrypoint.sh: line 20: cd: /app/server/: Permission denied
/usr/local/bin/docker-entrypoint.sh: line 20: cd: /app/server/: Permission denied
/usr/local/bin/docker-entrypoint.sh: line 20: cd: /app/server/: Permission denied
/usr/local/bin/docker-entrypoint.sh: line 20: cd: /app/server/: Permission denied
/usr/local/bin/docker-entrypoint.sh: line 20: cd: /app/server/: Permission denied
/usr/local/bin/docker-entrypoint.sh: line 20: cd: /app/server/: Permission denied
/usr/local/bin/docker-entrypoint.sh: line 20: cd: /app/server/: Permission denied
/usr/local/bin/docker-entrypoint.sh: line 20: cd: /app/server/: Permission denied
/usr/local/bin/docker-entrypoint.sh: line 20: cd: /app/server/: Permission denied
/usr/local/bin/docker-entrypoint.sh: line 20: cd: /app/server/: Permission denied
/usr/local/bin/docker-entrypoint.sh: line 20: cd: /app/server/: Permission denied
/usr/local/bin/docker-entrypoint.sh: line 20: cd: /app/server/: Permission denied
[1;33m[WARNING][0m anythingllm is running but health check timed out
[0;31m[ERROR][0m Service dify not defined in /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: Deploying application services...
[0;36m[INFO][0m DEBUG: Pulling n8n image...
 Image n8nio/n8n:latest Pulling 
 b36411a2fa43 Already exists 
 46dae4e9ce13 Already exists 
 4fc13c49d310 Already exists 
 0032134270b3 Already exists 
 038e4c626c22 Already exists 
 f5fe3c7d87bb Already exists 
 461c8cb85958 Already exists 
 4f4fb700ef54 Already exists 
 4f4fb700ef54 Already exists 
 9c8d6c8473e6 Pulling fs layer 
 b2efb9726ee5 Pulling fs layer 
 de3dac043c86 Pulling fs layer 
 9c8d6c8473e6 Downloading [>                                                  ]  534.4kB/168.6MB
 de3dac043c86 Downloading [>                                                  ]  11.64kB/1.142MB
 b2efb9726ee5 Downloading [==================================================>]     311B/311B
 b2efb9726ee5 Verifying Checksum 
 b2efb9726ee5 Download complete 
 de3dac043c86 Verifying Checksum 
 de3dac043c86 Download complete 
 9c8d6c8473e6 Downloading [==>                                                ]  7.489MB/168.6MB
 9c8d6c8473e6 Downloading [====>                                              ]  16.55MB/168.6MB
 9c8d6c8473e6 Downloading [=======>                                           ]  25.13MB/168.6MB
 9c8d6c8473e6 Downloading [==========>                                        ]  34.21MB/168.6MB
 9c8d6c8473e6 Downloading [=============>                                     ]  44.39MB/168.6MB
 9c8d6c8473e6 Downloading [================>                                  ]  55.08MB/168.6MB
 9c8d6c8473e6 Downloading [===================>                               ]   64.7MB/168.6MB
 9c8d6c8473e6 Downloading [=====================>                             ]  72.71MB/168.6MB
 9c8d6c8473e6 Downloading [========================>                          ]  81.25MB/168.6MB
 9c8d6c8473e6 Downloading [==========================>                        ]  89.24MB/168.6MB
 9c8d6c8473e6 Downloading [=============================>                     ]  98.33MB/168.6MB
 9c8d6c8473e6 Downloading [===============================>                   ]  106.9MB/168.6MB
 9c8d6c8473e6 Downloading [==================================>                ]    116MB/168.6MB
 9c8d6c8473e6 Downloading [===================================>               ]  121.4MB/168.6MB
 9c8d6c8473e6 Downloading [======================================>            ]  130.4MB/168.6MB
 9c8d6c8473e6 Downloading [=========================================>         ]    139MB/168.6MB
 9c8d6c8473e6 Downloading [===========================================>       ]  148.1MB/168.6MB
 9c8d6c8473e6 Downloading [=============================================>     ]  154.5MB/168.6MB
 9c8d6c8473e6 Downloading [================================================>  ]  162.6MB/168.6MB
 9c8d6c8473e6 Verifying Checksum 
 9c8d6c8473e6 Download complete 
 9c8d6c8473e6 Extracting [>                                                  ]  557.1kB/168.6MB
 9c8d6c8473e6 Extracting [>                                                  ]  1.114MB/168.6MB
 9c8d6c8473e6 Extracting [>                                                  ]  1.671MB/168.6MB
 9c8d6c8473e6 Extracting [>                                                  ]  2.228MB/168.6MB
 9c8d6c8473e6 Extracting [>                                                  ]  2.785MB/168.6MB
 9c8d6c8473e6 Extracting [=>                                                 ]  4.456MB/168.6MB
 9c8d6c8473e6 Extracting [=>                                                 ]  5.014MB/168.6MB
 9c8d6c8473e6 Extracting [=>                                                 ]  5.571MB/168.6MB
 9c8d6c8473e6 Extracting [=>                                                 ]  6.128MB/168.6MB
 9c8d6c8473e6 Extracting [=>                                                 ]  6.685MB/168.6MB
 9c8d6c8473e6 Extracting [==>                                                ]  7.242MB/168.6MB
 9c8d6c8473e6 Extracting [==>                                                ]  7.799MB/168.6MB
 9c8d6c8473e6 Extracting [==>                                                ]  8.356MB/168.6MB
 9c8d6c8473e6 Extracting [==>                                                ]  8.913MB/168.6MB
 9c8d6c8473e6 Extracting [==>                                                ]   9.47MB/168.6MB
 9c8d6c8473e6 Extracting [==>                                                ]  10.03MB/168.6MB
 9c8d6c8473e6 Extracting [===>                                               ]  10.58MB/168.6MB
 9c8d6c8473e6 Extracting [===>                                               ]   11.7MB/168.6MB
 9c8d6c8473e6 Extracting [===>                                               ]  12.26MB/168.6MB
 9c8d6c8473e6 Extracting [===>                                               ]  12.81MB/168.6MB
 9c8d6c8473e6 Extracting [===>                                               ]  13.37MB/168.6MB
 9c8d6c8473e6 Extracting [====>                                              ]  13.93MB/168.6MB
 9c8d6c8473e6 Extracting [====>                                              ]  14.48MB/168.6MB
 9c8d6c8473e6 Extracting [====>                                              ]  15.04MB/168.6MB
 9c8d6c8473e6 Extracting [====>                                              ]  16.15MB/168.6MB
 9c8d6c8473e6 Extracting [=====>                                             ]  17.27MB/168.6MB
 9c8d6c8473e6 Extracting [=====>                                             ]  17.83MB/168.6MB
 9c8d6c8473e6 Extracting [=====>                                             ]  18.38MB/168.6MB
 9c8d6c8473e6 Extracting [=====>                                             ]   19.5MB/168.6MB
 9c8d6c8473e6 Extracting [=====>                                             ]  20.05MB/168.6MB
 9c8d6c8473e6 Extracting [======>                                            ]  20.61MB/168.6MB
 9c8d6c8473e6 Extracting [======>                                            ]  21.17MB/168.6MB
 9c8d6c8473e6 Extracting [======>                                            ]  21.73MB/168.6MB
 9c8d6c8473e6 Extracting [======>                                            ]  22.28MB/168.6MB
 9c8d6c8473e6 Extracting [======>                                            ]  22.84MB/168.6MB
 9c8d6c8473e6 Extracting [======>                                            ]   23.4MB/168.6MB
 9c8d6c8473e6 Extracting [=======>                                           ]  23.95MB/168.6MB
 9c8d6c8473e6 Extracting [=======>                                           ]  24.51MB/168.6MB
 9c8d6c8473e6 Extracting [=======>                                           ]  25.07MB/168.6MB
 9c8d6c8473e6 Extracting [=======>                                           ]  25.62MB/168.6MB
 9c8d6c8473e6 Extracting [=======>                                           ]  26.18MB/168.6MB
 9c8d6c8473e6 Extracting [=======>                                           ]  26.74MB/168.6MB
 9c8d6c8473e6 Extracting [========>                                          ]   27.3MB/168.6MB
 9c8d6c8473e6 Extracting [========>                                          ]  27.85MB/168.6MB
 9c8d6c8473e6 Extracting [========>                                          ]  28.41MB/168.6MB
 9c8d6c8473e6 Extracting [========>                                          ]  28.97MB/168.6MB
 9c8d6c8473e6 Extracting [=========>                                         ]   31.2MB/168.6MB
 9c8d6c8473e6 Extracting [=========>                                         ]  31.75MB/168.6MB
 9c8d6c8473e6 Extracting [=========>                                         ]  32.31MB/168.6MB
 9c8d6c8473e6 Extracting [=========>                                         ]  32.87MB/168.6MB
 9c8d6c8473e6 Extracting [=========>                                         ]  33.42MB/168.6MB
 9c8d6c8473e6 Extracting [==========>                                        ]  33.98MB/168.6MB
 9c8d6c8473e6 Extracting [==========>                                        ]  34.54MB/168.6MB
 9c8d6c8473e6 Extracting [==========>                                        ]  35.09MB/168.6MB
 9c8d6c8473e6 Extracting [==========>                                        ]  35.65MB/168.6MB
 9c8d6c8473e6 Extracting [==========>                                        ]  36.21MB/168.6MB
 9c8d6c8473e6 Extracting [==========>                                        ]  36.77MB/168.6MB
 9c8d6c8473e6 Extracting [===========>                                       ]  37.32MB/168.6MB
 9c8d6c8473e6 Extracting [===========>                                       ]  37.88MB/168.6MB
 9c8d6c8473e6 Extracting [===========>                                       ]  38.44MB/168.6MB
 9c8d6c8473e6 Extracting [===========>                                       ]  38.99MB/168.6MB
 9c8d6c8473e6 Extracting [===========>                                       ]  39.55MB/168.6MB
 9c8d6c8473e6 Extracting [============>                                      ]  40.67MB/168.6MB
 9c8d6c8473e6 Extracting [============>                                      ]  41.22MB/168.6MB
 9c8d6c8473e6 Extracting [============>                                      ]  41.78MB/168.6MB
 9c8d6c8473e6 Extracting [============>                                      ]  42.34MB/168.6MB
 9c8d6c8473e6 Extracting [============>                                      ]  42.89MB/168.6MB
 9c8d6c8473e6 Extracting [============>                                      ]  43.45MB/168.6MB
 9c8d6c8473e6 Extracting [=============>                                     ]  44.01MB/168.6MB
 9c8d6c8473e6 Extracting [=============>                                     ]  46.24MB/168.6MB
 9c8d6c8473e6 Extracting [=============>                                     ]  46.79MB/168.6MB
 9c8d6c8473e6 Extracting [==============>                                    ]  47.35MB/168.6MB
 9c8d6c8473e6 Extracting [==============>                                    ]  47.91MB/168.6MB
 9c8d6c8473e6 Extracting [==============>                                    ]  48.46MB/168.6MB
 9c8d6c8473e6 Extracting [==============>                                    ]  49.02MB/168.6MB
 9c8d6c8473e6 Extracting [==============>                                    ]  49.58MB/168.6MB
 9c8d6c8473e6 Extracting [==============>                                    ]  50.14MB/168.6MB
 9c8d6c8473e6 Extracting [===============>                                   ]  50.69MB/168.6MB
 9c8d6c8473e6 Extracting [===============>                                   ]  51.25MB/168.6MB
 9c8d6c8473e6 Extracting [===============>                                   ]  53.48MB/168.6MB
 9c8d6c8473e6 Extracting [================>                                  ]  54.03MB/168.6MB
 9c8d6c8473e6 Extracting [================>                                  ]  54.59MB/168.6MB
 9c8d6c8473e6 Extracting [================>                                  ]  55.71MB/168.6MB
 9c8d6c8473e6 Extracting [================>                                  ]  56.26MB/168.6MB
 9c8d6c8473e6 Extracting [=================>                                 ]  57.38MB/168.6MB
 9c8d6c8473e6 Extracting [=================>                                 ]  57.93MB/168.6MB
 9c8d6c8473e6 Extracting [=================>                                 ]  59.05MB/168.6MB
 9c8d6c8473e6 Extracting [=================>                                 ]   59.6MB/168.6MB
 9c8d6c8473e6 Extracting [=================>                                 ]  60.16MB/168.6MB
 9c8d6c8473e6 Extracting [==================>                                ]  60.72MB/168.6MB
 9c8d6c8473e6 Extracting [==================>                                ]  61.28MB/168.6MB
 9c8d6c8473e6 Extracting [==================>                                ]  61.83MB/168.6MB
 9c8d6c8473e6 Extracting [==================>                                ]  62.39MB/168.6MB
 9c8d6c8473e6 Extracting [==================>                                ]  62.95MB/168.6MB
 9c8d6c8473e6 Extracting [==================>                                ]   63.5MB/168.6MB
 9c8d6c8473e6 Extracting [==================>                                ]  64.06MB/168.6MB
 9c8d6c8473e6 Extracting [===================>                               ]  64.62MB/168.6MB
 9c8d6c8473e6 Extracting [===================>                               ]  65.18MB/168.6MB
 9c8d6c8473e6 Extracting [===================>                               ]  65.73MB/168.6MB
 9c8d6c8473e6 Extracting [===================>                               ]  66.29MB/168.6MB
 9c8d6c8473e6 Extracting [===================>                               ]  66.85MB/168.6MB
 9c8d6c8473e6 Extracting [===================>                               ]   67.4MB/168.6MB
 9c8d6c8473e6 Extracting [====================>                              ]  67.96MB/168.6MB
 9c8d6c8473e6 Extracting [====================>                              ]  69.07MB/168.6MB
 9c8d6c8473e6 Extracting [====================>                              ]  69.63MB/168.6MB
 9c8d6c8473e6 Extracting [====================>                              ]  70.75MB/168.6MB
 9c8d6c8473e6 Extracting [=====================>                             ]   71.3MB/168.6MB
 9c8d6c8473e6 Extracting [=====================>                             ]  72.42MB/168.6MB
 9c8d6c8473e6 Extracting [======================>                            ]  75.76MB/168.6MB
 9c8d6c8473e6 Extracting [=======================>                           ]  77.99MB/168.6MB
 9c8d6c8473e6 Extracting [=======================>                           ]  78.54MB/168.6MB
 9c8d6c8473e6 Extracting [=======================>                           ]   79.1MB/168.6MB
 9c8d6c8473e6 Extracting [=======================>                           ]  79.66MB/168.6MB
 9c8d6c8473e6 Extracting [=======================>                           ]  80.22MB/168.6MB
 9c8d6c8473e6 Extracting [=======================>                           ]  80.77MB/168.6MB
 9c8d6c8473e6 Extracting [========================>                          ]  81.33MB/168.6MB
 9c8d6c8473e6 Extracting [========================>                          ]  82.44MB/168.6MB
 9c8d6c8473e6 Extracting [========================>                          ]     83MB/168.6MB
 9c8d6c8473e6 Extracting [========================>                          ]  83.56MB/168.6MB
 9c8d6c8473e6 Extracting [========================>                          ]  84.12MB/168.6MB
 9c8d6c8473e6 Extracting [=========================>                         ]  84.67MB/168.6MB
 9c8d6c8473e6 Extracting [=========================>                         ]  85.23MB/168.6MB
 9c8d6c8473e6 Extracting [=========================>                         ]  85.79MB/168.6MB
 9c8d6c8473e6 Extracting [=========================>                         ]  86.34MB/168.6MB
 9c8d6c8473e6 Extracting [=========================>                         ]   86.9MB/168.6MB
 9c8d6c8473e6 Extracting [=========================>                         ]  87.46MB/168.6MB
 9c8d6c8473e6 Extracting [==========================>                        ]  88.57MB/168.6MB
 9c8d6c8473e6 Extracting [===========================>                       ]  91.36MB/168.6MB
 9c8d6c8473e6 Extracting [===========================>                       ]  93.03MB/168.6MB
 9c8d6c8473e6 Extracting [============================>                      ]  95.26MB/168.6MB
 9c8d6c8473e6 Extracting [============================>                      ]  96.93MB/168.6MB
 9c8d6c8473e6 Extracting [=============================>                     ]  99.16MB/168.6MB
 9c8d6c8473e6 Extracting [==============================>                    ]  101.4MB/168.6MB
 9c8d6c8473e6 Extracting [==============================>                    ]  101.9MB/168.6MB
 9c8d6c8473e6 Extracting [==============================>                    ]  102.5MB/168.6MB
 9c8d6c8473e6 Extracting [==============================>                    ]  103.1MB/168.6MB
 9c8d6c8473e6 Extracting [==============================>                    ]  103.6MB/168.6MB
 9c8d6c8473e6 Extracting [==============================>                    ]  104.2MB/168.6MB
 9c8d6c8473e6 Extracting [===============================>                   ]  104.7MB/168.6MB
 9c8d6c8473e6 Extracting [===============================>                   ]  105.3MB/168.6MB
 9c8d6c8473e6 Extracting [===============================>                   ]  105.8MB/168.6MB
 9c8d6c8473e6 Extracting [===============================>                   ]  106.4MB/168.6MB
 9c8d6c8473e6 Extracting [===============================>                   ]    107MB/168.6MB
 9c8d6c8473e6 Extracting [===============================>                   ]  107.5MB/168.6MB
 9c8d6c8473e6 Extracting [================================>                  ]  108.1MB/168.6MB
 9c8d6c8473e6 Extracting [================================>                  ]  108.6MB/168.6MB
 9c8d6c8473e6 Extracting [================================>                  ]  109.7MB/168.6MB
 9c8d6c8473e6 Extracting [================================>                  ]  110.3MB/168.6MB
 9c8d6c8473e6 Extracting [================================>                  ]  110.9MB/168.6MB
 9c8d6c8473e6 Extracting [=================================>                 ]  111.4MB/168.6MB
 9c8d6c8473e6 Extracting [=================================>                 ]    112MB/168.6MB
 9c8d6c8473e6 Extracting [=================================>                 ]  112.5MB/168.6MB
 9c8d6c8473e6 Extracting [=================================>                 ]  113.1MB/168.6MB
 9c8d6c8473e6 Extracting [=================================>                 ]  114.2MB/168.6MB
 9c8d6c8473e6 Extracting [==================================>                ]  114.8MB/168.6MB
 9c8d6c8473e6 Extracting [==================================>                ]  115.3MB/168.6MB
 9c8d6c8473e6 Extracting [==================================>                ]    117MB/168.6MB
 9c8d6c8473e6 Extracting [===================================>               ]  118.7MB/168.6MB
 9c8d6c8473e6 Extracting [===================================>               ]  119.2MB/168.6MB
 9c8d6c8473e6 Extracting [===================================>               ]  120.9MB/168.6MB
 9c8d6c8473e6 Extracting [====================================>              ]  121.4MB/168.6MB
 9c8d6c8473e6 Extracting [=====================================>             ]  126.5MB/168.6MB
 9c8d6c8473e6 Extracting [======================================>            ]  128.7MB/168.6MB
 9c8d6c8473e6 Extracting [======================================>            ]  129.8MB/168.6MB
 9c8d6c8473e6 Extracting [======================================>            ]  131.5MB/168.6MB
 9c8d6c8473e6 Extracting [=======================================>           ]  133.1MB/168.6MB
 9c8d6c8473e6 Extracting [========================================>          ]  135.4MB/168.6MB
 9c8d6c8473e6 Extracting [========================================>          ]    137MB/168.6MB
 9c8d6c8473e6 Extracting [========================================>          ]  137.6MB/168.6MB
 9c8d6c8473e6 Extracting [=========================================>         ]  139.3MB/168.6MB
 9c8d6c8473e6 Extracting [=========================================>         ]  140.4MB/168.6MB
 9c8d6c8473e6 Extracting [=========================================>         ]  141.5MB/168.6MB
 9c8d6c8473e6 Extracting [==========================================>        ]    142MB/168.6MB
 9c8d6c8473e6 Extracting [==========================================>        ]  142.6MB/168.6MB
 9c8d6c8473e6 Extracting [==========================================>        ]  143.2MB/168.6MB
 9c8d6c8473e6 Extracting [==========================================>        ]  143.7MB/168.6MB
 9c8d6c8473e6 Extracting [===========================================>       ]  147.6MB/168.6MB
 9c8d6c8473e6 Extracting [============================================>      ]  148.7MB/168.6MB
 9c8d6c8473e6 Extracting [============================================>      ]  149.3MB/168.6MB
 9c8d6c8473e6 Extracting [=============================================>     ]  152.1MB/168.6MB
 9c8d6c8473e6 Extracting [=============================================>     ]  153.2MB/168.6MB
 9c8d6c8473e6 Extracting [=============================================>     ]  153.7MB/168.6MB
 9c8d6c8473e6 Extracting [=============================================>     ]  154.3MB/168.6MB
 9c8d6c8473e6 Extracting [==============================================>    ]  156.5MB/168.6MB
 9c8d6c8473e6 Extracting [===============================================>   ]  158.8MB/168.6MB
 9c8d6c8473e6 Extracting [===============================================>   ]  159.3MB/168.6MB
 9c8d6c8473e6 Extracting [===============================================>   ]  159.9MB/168.6MB
 9c8d6c8473e6 Extracting [===============================================>   ]  160.4MB/168.6MB
 9c8d6c8473e6 Extracting [===============================================>   ]    161MB/168.6MB
 9c8d6c8473e6 Extracting [================================================>  ]  162.1MB/168.6MB
 9c8d6c8473e6 Extracting [================================================>  ]  162.7MB/168.6MB
 9c8d6c8473e6 Extracting [================================================>  ]  164.9MB/168.6MB
 9c8d6c8473e6 Extracting [=================================================> ]  166.6MB/168.6MB
 9c8d6c8473e6 Extracting [=================================================> ]  167.1MB/168.6MB
 9c8d6c8473e6 Extracting [=================================================> ]  167.7MB/168.6MB
 9c8d6c8473e6 Extracting [=================================================> ]  168.2MB/168.6MB
 9c8d6c8473e6 Extracting [==================================================>]  168.6MB/168.6MB
 9c8d6c8473e6 Pull complete 
 b2efb9726ee5 Extracting [==================================================>]     311B/311B
 b2efb9726ee5 Extracting [==================================================>]     311B/311B
 b2efb9726ee5 Pull complete 
 de3dac043c86 Extracting [=>                                                 ]  32.77kB/1.142MB
 de3dac043c86 Extracting [==================================================>]  1.142MB/1.142MB
 de3dac043c86 Extracting [==================================================>]  1.142MB/1.142MB
 de3dac043c86 Pull complete 
 Image n8nio/n8n:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting n8n with explicit environment...
 Container postgres Running 
 Container n8n Creating 
 Container n8n Created 
 Container postgres Waiting 
 Container postgres Healthy 
 Container n8n Starting 
 Container n8n Started 
[0;36m[INFO][0m DEBUG: Waiting for n8n to become healthy...
[0;36m[INFO][0m Waiting for n8n to be healthy (max 180s)...
[0;31m[ERROR][0m n8n failed to become healthy after 180 seconds
    at CommandRegistry.execute (/usr/local/lib/node_modules/n8n/src/command-registry.ts:46:3)
    at /usr/local/lib/node_modules/n8n/bin/n8n:63:2
Error: EACCES: permission denied, mkdir '/.n8n'
    at mkdirSync (node:fs:1377:26)
    at InstanceSettings.loadOrCreate (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/n8n-core@file+packages+core_@opentelemetry+api@1.9.0_@opentelemetry+exporter-trace-otlp_4dbefa9881a7c57a9e05a20ce4387c10/node_modules/n8n-core/src/instance-settings/instance-settings.ts:223:12)
    at new InstanceSettings (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/n8n-core@file+packages+core_@opentelemetry+api@1.9.0_@opentelemetry+exporter-trace-otlp_4dbefa9881a7c57a9e05a20ce4387c10/node_modules/n8n-core/src/instance-settings/instance-settings.ts:70:24)
    at ContainerClass.get (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/@n8n+di@file+packages+@n8n+di/node_modules/@n8n/di/src/di.ts:104:16)
    at CommunityPackagesModule.loadDir (/usr/local/lib/node_modules/n8n/src/modules/community-packages/community-packages.module.ts:41:30)
    at ModuleRegistry.loadModules (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/@n8n+backend-common@file+packages+@n8n+backend-common/node_modules/@n8n/backend-common/src/modules/module-registry.ts:105:20)
    at CommandRegistry.execute (/usr/local/lib/node_modules/n8n/src/command-registry.ts:46:3)
    at /usr/local/lib/node_modules/n8n/bin/n8n:63:2
Error: EACCES: permission denied, mkdir '/.n8n'
    at mkdirSync (node:fs:1377:26)
    at InstanceSettings.loadOrCreate (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/n8n-core@file+packages+core_@opentelemetry+api@1.9.0_@opentelemetry+exporter-trace-otlp_4dbefa9881a7c57a9e05a20ce4387c10/node_modules/n8n-core/src/instance-settings/instance-settings.ts:223:12)
    at new InstanceSettings (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/n8n-core@file+packages+core_@opentelemetry+api@1.9.0_@opentelemetry+exporter-trace-otlp_4dbefa9881a7c57a9e05a20ce4387c10/node_modules/n8n-core/src/instance-settings/instance-settings.ts:70:24)
    at ContainerClass.get (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/@n8n+di@file+packages+@n8n+di/node_modules/@n8n/di/src/di.ts:104:16)
    at CommunityPackagesModule.loadDir (/usr/local/lib/node_modules/n8n/src/modules/community-packages/community-packages.module.ts:41:30)
    at ModuleRegistry.loadModules (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/@n8n+backend-common@file+packages+@n8n+backend-common/node_modules/@n8n/backend-common/src/modules/module-registry.ts:105:20)
    at CommandRegistry.execute (/usr/local/lib/node_modules/n8n/src/command-registry.ts:46:3)
    at /usr/local/lib/node_modules/n8n/bin/n8n:63:2
[1;33m[WARNING][0m n8n is running but health check timed out
[0;36m[INFO][0m DEBUG: Pulling flowise image...
 Image flowiseai/flowise:latest Pulling 
 Image flowiseai/flowise:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting flowise with explicit environment...
 Container postgres Running 
 Container flowise Creating 
 Container flowise Created 
 Container postgres Waiting 
 Container postgres Healthy 
 Container flowise Starting 
 Container flowise Started 
[0;36m[INFO][0m DEBUG: Waiting for flowise to become healthy...
[0;36m[INFO][0m Waiting for flowise to be healthy (max 180s)...
[0;31m[ERROR][0m flowise failed to become healthy after 180 seconds
          ^

SystemError [ERR_SYSTEM_ERROR]: A system error occurred: uv_os_get_passwd returned ENOENT (no such file or directory)
    at userInfo (node:os:311:11)
    at Config._shell (/usr/local/lib/node_modules/flowise/node_modules/@oclif/core/lib/config/config.js:587:67)
    at Config.load (/usr/local/lib/node_modules/flowise/node_modules/@oclif/core/lib/config/config.js:309:27)
    at async Config.load (/usr/local/lib/node_modules/flowise/node_modules/@oclif/core/lib/config/config.js:167:9)
    at async Object.run (/usr/local/lib/node_modules/flowise/node_modules/@oclif/core/lib/main.js:61:20) {
  code: 'ERR_SYSTEM_ERROR',
  info: {
    errno: -2,
    code: 'ENOENT',
    message: 'no such file or directory',
    syscall: 'uv_os_get_passwd'
  },
  errno: [Getter/Setter],
  syscall: [Getter/Setter]
}

Node.js v20.20.0
[1;33m[WARNING][0m flowise is running but health check timed out
[0;36m[INFO][0m DEBUG: Deploying storage and network services...
[0;36m[INFO][0m DEBUG: Pulling minio image...
 Image minio/minio:latest Pulling 
 Image minio/minio:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting minio with explicit environment...
 Container minio Creating 
 Container minio Created 
 Container minio Starting 
 Container minio Started 
[0;36m[INFO][0m DEBUG: Waiting for minio to become healthy...
[0;36m[INFO][0m Waiting for minio to be healthy (max 180s)...
[0;31m[ERROR][0m minio failed to become healthy after 180 seconds
Error: unable to rename (/data/.minio.sys/tmp -> /data/.minio.sys/tmp-old/aa557647-e677-49ec-91ca-414dbc9654ae) file access denied, drive may be faulty, please investigate (*fmt.wrapError)
       7: internal/logger/logger.go:271:logger.LogIf()
       6: cmd/logging.go:160:cmd.storageLogIf()
       5: cmd/prepare-storage.go:89:cmd.bgFormatErasureCleanupTmp()
       4: cmd/xl-storage.go:272:cmd.newXLStorage()
       3: cmd/object-api-common.go:63:cmd.newStorageAPI()
       2: cmd/format-erasure.go:568:cmd.initStorageDisksWithErrors.func1()
       1: github.com/minio/pkg/v3@v3.1.3/sync/errgroup/errgroup.go:123:errgroup.(*Group).Go.func1()

API: SYSTEM.storage
Time: 11:29:48 UTC 02/17/2026
Error: unable to create (/data/.minio.sys/tmp) file access denied, drive may be faulty, please investigate (*fmt.wrapError)
       7: internal/logger/logger.go:271:logger.LogIf()
       6: cmd/logging.go:160:cmd.storageLogIf()
       5: cmd/prepare-storage.go:96:cmd.bgFormatErasureCleanupTmp()
       4: cmd/xl-storage.go:272:cmd.newXLStorage()
       3: cmd/object-api-common.go:63:cmd.newStorageAPI()
       2: cmd/format-erasure.go:568:cmd.initStorageDisksWithErrors.func1()
       1: github.com/minio/pkg/v3@v3.1.3/sync/errgroup/errgroup.go:123:errgroup.(*Group).Go.func1()
FATAL Unable to initialize backend: file access denied
[1;33m[WARNING][0m minio is running but health check timed out
[0;36m[INFO][0m DEBUG: Pulling tailscale image...
 Image tailscale/tailscale:latest Pulling 
 Image tailscale/tailscale:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting tailscale with explicit environment...
 Container tailscale Creating 
 Container tailscale Created 
 Container tailscale Starting 
 Container tailscale Started 
[0;36m[INFO][0m DEBUG: Waiting for tailscale to become healthy...
[0;36m[INFO][0m Waiting for tailscale to be healthy (max 180s)...
[0;31m[ERROR][0m tailscale failed to become healthy after 180 seconds
2026/02/17 11:33:07 trying bootstrapDNS("derp7.tailscale.com", "167.179.89.145") for "log.tailscale.com" ...
2026/02/17 11:33:07 bootstrapDNS("derp7.tailscale.com", "167.179.89.145") for "log.tailscale.com" error: Get "https://derp7.tailscale.com/bootstrap-dns?q=log.tailscale.com": dial tcp 167.179.89.145:443: connect: network is unreachable
2026/02/17 11:33:07 trying bootstrapDNS("derp6.tailscale.com", "2400:6180:100:d0::982:d001") for "log.tailscale.com" ...
2026/02/17 11:33:07 bootstrapDNS("derp6.tailscale.com", "2400:6180:100:d0::982:d001") for "log.tailscale.com" error: Get "https://derp6.tailscale.com/bootstrap-dns?q=log.tailscale.com": dial tcp [2400:6180:100:d0::982:d001]:443: connect: network is unreachable
2026/02/17 11:33:07 logtail: upload: log upload of 4765 bytes compressed failed: Post "https://log.tailscale.com/c/tailnode.log.tailscale.io/0883c20cba509d67745c0dfad407765ae4f7456e1510da3b4a1df0de81bc7a5c": failed to resolve "log.tailscale.com": no DNS fallback candidates remain for "log.tailscale.com"
2026/02/17 11:33:10 health(warnable=warming-up): ok
2026/02/17 11:33:16 [RATELIMIT] format("control: LoginInteractive -> regen=true") (9 dropped)
2026/02/17 11:33:16 control: LoginInteractive -> regen=true
2026/02/17 11:33:16 [RATELIMIT] format("control: doLogin(regen=%v, hasUrl=%v)") (9 dropped)
2026/02/17 11:33:16 control: doLogin(regen=true, hasUrl=false)
2026/02/17 11:33:16 [RATELIMIT] format("control: trying bootstrapDNS(%q, %q) for %q ...") (163 dropped)
2026/02/17 11:33:16 control: trying bootstrapDNS("derp4c.tailscale.com", "134.122.77.138") for "controlplane.tailscale.com" ...
2026/02/17 11:33:16 [RATELIMIT] format("control: bootstrapDNS(%q, %q) for %q error: %v") (163 dropped)
2026/02/17 11:33:16 control: bootstrapDNS("derp4c.tailscale.com", "134.122.77.138") for "controlplane.tailscale.com" error: Get "https://derp4c.tailscale.com/bootstrap-dns?q=controlplane.tailscale.com": dial tcp 134.122.77.138:443: connect: network is unreachable
2026/02/17 11:33:16 control: trying bootstrapDNS("derp12b.tailscale.com", "2001:19f0:5c01:48a:5400:3ff:fe8d:cb5f") for "controlplane.tailscale.com" ...
2026/02/17 11:33:16 [RATELIMIT] format("control: trying bootstrapDNS(%q, %q) for %q ...")
2026/02/17 11:33:16 control: bootstrapDNS("derp12b.tailscale.com", "2001:19f0:5c01:48a:5400:3ff:fe8d:cb5f") for "controlplane.tailscale.com" error: Get "https://derp12b.tailscale.com/bootstrap-dns?q=controlplane.tailscale.com": dial tcp [2001:19f0:5c01:48a:5400:3ff:fe8d:cb5f]:443: connect: network is unreachable
2026/02/17 11:33:16 [RATELIMIT] format("control: bootstrapDNS(%q, %q) for %q error: %v")
2026/02/17 11:33:16 [RATELIMIT] format("Received error: %v") (9 dropped)
2026/02/17 11:33:16 Received error: fetch control key: Get "https://controlplane.tailscale.com/key?v=131": failed to resolve "controlplane.tailscale.com": no DNS fallback candidates remain for "controlplane.tailscale.com"
[1;33m[WARNING][0m tailscale is running but health check timed out
[0;36m[INFO][0m DEBUG: Pulling openclaw image...
 Image openclaw/openclaw:latest Pulling 
 Image openclaw/openclaw:latest Error pull access denied for openclaw/openclaw, repository does not exist or may require 'docker login': denied: requested access to the resource is denied
Error response from daemon: pull access denied for openclaw/openclaw, repository does not exist or may require 'docker login': denied: requested access to the resource is denied
[0;31m[ERROR][0m Failed to pull openclaw image
[0;36m[INFO][0m DEBUG: Pulling signal-api image...
 Image bbernhard/signal-cli-rest-api:latest Pulling 
 Image bbernhard/signal-cli-rest-api:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting signal-api with explicit environment...
 Container signal-api Creating 
 Container signal-api Created 
 Container signal-api Starting 
 Container signal-api Started 
[0;36m[INFO][0m DEBUG: Waiting for signal-api to become healthy...
[0;36m[INFO][0m Waiting for signal-api to be healthy (max 180s)...
[0;31m[ERROR][0m signal-api failed to become healthy after 180 seconds
+ [ -z /home/.local/share/signal-cli ]
+ usermod -u 1000 signal-api
usermod: no changes
+ groupmod -o -g 1000 signal-api
groupmod: Permission denied.
groupmod: cannot lock /etc/group; try again later.
+ set -e
+ [ -z /home/.local/share/signal-cli ]
+ usermod -u 1000 signal-api
usermod: no changes
+ groupmod -o -g 1000 signal-api
groupmod: Permission denied.
groupmod: cannot lock /etc/group; try again later.
+ set -e
+ [ -z /home/.local/share/signal-cli ]
+ usermod -u 1000 signal-api
usermod: no changes
+ groupmod -o -g 1000 signal-api
groupmod: Permission denied.
groupmod: cannot lock /etc/group; try again later.
[1;33m[WARNING][0m signal-api is running but health check timed out
[0;36m[INFO][0m DEBUG: Deploying proxy services...
[0;36m[INFO][0m DEBUG: All services deployment completed
[0;36m[INFO][0m DEBUG: About to start core services deployment...
[0;36m[INFO][0m DEBUG: Checking core service: postgres
[0;36m[INFO][0m DEBUG: Deploying core service: postgres
[0;36m[INFO][0m DEBUG: Pulling postgres image...
 Image postgres:15-alpine Pulling 
 Image postgres:15-alpine Pulled 
[0;36m[INFO][0m DEBUG: Starting postgres with explicit environment...
 Container postgres Running 
[0;36m[INFO][0m DEBUG: Waiting for postgres to become healthy...
[0;36m[INFO][0m Waiting for PostgreSQL to be ready (max 60s)...
[0;32m[SUCCESS][0m PostgreSQL is ready
[0;36m[INFO][0m DEBUG: Core service postgres deployed successfully
[0;36m[INFO][0m DEBUG: Checking core service: redis
[0;36m[INFO][0m DEBUG: Deploying core service: redis
[0;36m[INFO][0m DEBUG: Pulling redis image...
 Image redis:7-alpine Pulling 
 Image redis:7-alpine Pulled 
[0;36m[INFO][0m DEBUG: Starting redis with explicit environment...
 Container redis Running 
[0;36m[INFO][0m DEBUG: Waiting for redis to become healthy...
[0;36m[INFO][0m Waiting for Redis to be ready (max 30s)...
[0;31m[ERROR][0m Redis failed to become ready after 30 seconds
[1;33m[WARNING][0m redis is running but health check timed out
[0;36m[INFO][0m DEBUG: Core service redis deployed successfully
[0;36m[INFO][0m DEBUG: Core services deployment completed
[0;36m[INFO][0m DEBUG: About to deploy remaining services...
[0;36m[INFO][0m DEBUG: Deploying remaining service: prometheus
[0;36m[INFO][0m DEBUG: Pulling prometheus image...
 Image prom/prometheus:latest Pulling 
 Image prom/prometheus:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting prometheus with explicit environment...
 Container prometheus Starting 
 Container prometheus Started 
[0;36m[INFO][0m DEBUG: Waiting for prometheus to become healthy...
[0;36m[INFO][0m Waiting for prometheus to be healthy (max 180s)...
[0;31m[ERROR][0m prometheus failed to become healthy after 180 seconds
panic: Unable to create mmap-ed active query log

goroutine 1 [running]:
github.com/prometheus/prometheus/promql.NewActiveQueryTracker({0x7ffccdc5fed8, 0xb}, 0x14, 0xc0001ee040)
	/app/promql/query_logger.go:145 +0x345
main.main()
	/app/cmd/prometheus/main.go:894 +0x8953
time=2026-02-17T11:39:40.265Z level=INFO source=main.go:1589 msg="updated GOGC" old=100 new=75
time=2026-02-17T11:39:40.268Z level=INFO source=main.go:704 msg="Leaving GOMAXPROCS=2: CPU quota undefined" component=automaxprocs
time=2026-02-17T11:39:40.268Z level=INFO source=memlimit.go:198 msg="GOMEMLIMIT is updated" component=automemlimit package=github.com/KimMachineGun/automemlimit/memlimit GOMEMLIMIT=7380773683 previous=9223372036854775807
time=2026-02-17T11:39:40.268Z level=INFO source=main.go:803 msg="Starting Prometheus Server" mode=server version="(version=3.9.1, branch=HEAD, revision=9ec59baffb547e24f1468a53eb82901e58feabd8)"
time=2026-02-17T11:39:40.268Z level=INFO source=main.go:808 msg="operational information" build_context="(go=go1.25.5, platform=linux/amd64, user=root@61c3a9212c9e, date=20260107-16:08:09, tags=netgo,builtinassets)" host_details="(Linux 6.14.0-1018-aws #18~24.04.1-Ubuntu SMP Mon Nov 24 19:46:27 UTC 2025 x86_64 4e891db7dce5 (none))" fd_limits="(soft=524287, hard=524288)" vm_limits="(soft=unlimited, hard=unlimited)"
time=2026-02-17T11:39:40.270Z level=ERROR source=query_logger.go:113 msg="Error opening query log file" component=activeQueryTracker file=/prometheus/queries.active err="open /prometheus/queries.active: permission denied"
panic: Unable to create mmap-ed active query log

goroutine 1 [running]:
github.com/prometheus/prometheus/promql.NewActiveQueryTracker({0x7fffd6c54ed8, 0xb}, 0x14, 0xc00024c050)
	/app/promql/query_logger.go:145 +0x345
main.main()
	/app/cmd/prometheus/main.go:894 +0x8953
[1;33m[WARNING][0m prometheus is running but health check timed out
[0;36m[INFO][0m DEBUG: Service prometheus deployed successfully
[0;36m[INFO][0m DEBUG: Deploying remaining service: flowise
[0;36m[INFO][0m DEBUG: Pulling flowise image...
 Image flowiseai/flowise:latest Pulling 
 Image flowiseai/flowise:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting flowise with explicit environment...
 Container postgres Running 
 Container postgres Waiting 
 Container postgres Healthy 
 Container flowise Starting 
 Container flowise Started 
[0;36m[INFO][0m DEBUG: Waiting for flowise to become healthy...
[0;36m[INFO][0m Waiting for flowise to be healthy (max 180s)...
[0;31m[ERROR][0m flowise failed to become healthy after 180 seconds
          ^

SystemError [ERR_SYSTEM_ERROR]: A system error occurred: uv_os_get_passwd returned ENOENT (no such file or directory)
    at userInfo (node:os:311:11)
    at Config._shell (/usr/local/lib/node_modules/flowise/node_modules/@oclif/core/lib/config/config.js:587:67)
    at Config.load (/usr/local/lib/node_modules/flowise/node_modules/@oclif/core/lib/config/config.js:309:27)
    at async Config.load (/usr/local/lib/node_modules/flowise/node_modules/@oclif/core/lib/config/config.js:167:9)
    at async Object.run (/usr/local/lib/node_modules/flowise/node_modules/@oclif/core/lib/main.js:61:20) {
  code: 'ERR_SYSTEM_ERROR',
  info: {
    errno: -2,
    code: 'ENOENT',
    message: 'no such file or directory',
    syscall: 'uv_os_get_passwd'
  },
  errno: [Getter/Setter],
  syscall: [Getter/Setter]
}

Node.js v20.20.0
[1;33m[WARNING][0m flowise is running but health check timed out
[0;36m[INFO][0m DEBUG: Service flowise deployed successfully
[0;36m[INFO][0m DEBUG: Deploying remaining service: grafana
[0;36m[INFO][0m DEBUG: Pulling grafana image...
 Image grafana/grafana:latest Pulling 
 Image grafana/grafana:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting grafana with explicit environment...
 Container grafana Running 
[0;36m[INFO][0m DEBUG: Waiting for grafana to become healthy...
[0;36m[INFO][0m Waiting for grafana to be healthy (max 180s)...
[0;32m[SUCCESS][0m grafana is healthy
[0;36m[INFO][0m DEBUG: Service grafana deployed successfully
[0;36m[INFO][0m DEBUG: Deploying remaining service: n8n
[0;36m[INFO][0m DEBUG: Pulling n8n image...
 Image n8nio/n8n:latest Pulling 
 Image n8nio/n8n:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting n8n with explicit environment...
 Container postgres Running 
 Container n8n Running 
 Container postgres Waiting 
 Container postgres Healthy 
[0;36m[INFO][0m DEBUG: Waiting for n8n to become healthy...
[0;36m[INFO][0m Waiting for n8n to be healthy (max 180s)...
[0;31m[ERROR][0m n8n failed to become healthy after 180 seconds
    at CommandRegistry.execute (/usr/local/lib/node_modules/n8n/src/command-registry.ts:46:3)
    at /usr/local/lib/node_modules/n8n/bin/n8n:63:2
Error: EACCES: permission denied, mkdir '/.n8n'
    at mkdirSync (node:fs:1377:26)
    at InstanceSettings.loadOrCreate (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/n8n-core@file+packages+core_@opentelemetry+api@1.9.0_@opentelemetry+exporter-trace-otlp_4dbefa9881a7c57a9e05a20ce4387c10/node_modules/n8n-core/src/instance-settings/instance-settings.ts:223:12)
    at new InstanceSettings (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/n8n-core@file+packages+core_@opentelemetry+api@1.9.0_@opentelemetry+exporter-trace-otlp_4dbefa9881a7c57a9e05a20ce4387c10/node_modules/n8n-core/src/instance-settings/instance-settings.ts:70:24)
    at ContainerClass.get (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/@n8n+di@file+packages+@n8n+di/node_modules/@n8n/di/src/di.ts:104:16)
    at CommunityPackagesModule.loadDir (/usr/local/lib/node_modules/n8n/src/modules/community-packages/community-packages.module.ts:41:30)
    at ModuleRegistry.loadModules (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/@n8n+backend-common@file+packages+@n8n+backend-common/node_modules/@n8n/backend-common/src/modules/module-registry.ts:105:20)
    at CommandRegistry.execute (/usr/local/lib/node_modules/n8n/src/command-registry.ts:46:3)
    at /usr/local/lib/node_modules/n8n/bin/n8n:63:2
Error: EACCES: permission denied, mkdir '/.n8n'
    at mkdirSync (node:fs:1377:26)
    at InstanceSettings.loadOrCreate (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/n8n-core@file+packages+core_@opentelemetry+api@1.9.0_@opentelemetry+exporter-trace-otlp_4dbefa9881a7c57a9e05a20ce4387c10/node_modules/n8n-core/src/instance-settings/instance-settings.ts:223:12)
    at new InstanceSettings (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/n8n-core@file+packages+core_@opentelemetry+api@1.9.0_@opentelemetry+exporter-trace-otlp_4dbefa9881a7c57a9e05a20ce4387c10/node_modules/n8n-core/src/instance-settings/instance-settings.ts:70:24)
    at ContainerClass.get (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/@n8n+di@file+packages+@n8n+di/node_modules/@n8n/di/src/di.ts:104:16)
    at CommunityPackagesModule.loadDir (/usr/local/lib/node_modules/n8n/src/modules/community-packages/community-packages.module.ts:41:30)
    at ModuleRegistry.loadModules (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/@n8n+backend-common@file+packages+@n8n+backend-common/node_modules/@n8n/backend-common/src/modules/module-registry.ts:105:20)
    at CommandRegistry.execute (/usr/local/lib/node_modules/n8n/src/command-registry.ts:46:3)
    at /usr/local/lib/node_modules/n8n/bin/n8n:63:2
[1;33m[WARNING][0m n8n is running but health check timed out
[0;36m[INFO][0m DEBUG: Service n8n deployed successfully
[0;36m[INFO][0m DEBUG: Deploying remaining service: ollama
[0;36m[INFO][0m DEBUG: Pulling ollama image...
 Image ollama/ollama:latest Pulling 
 Image ollama/ollama:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting ollama with explicit environment...
 Container ollama Starting 
 Container ollama Started 
[0;36m[INFO][0m DEBUG: Waiting for ollama to become healthy...
[0;36m[INFO][0m Waiting for ollama to be healthy (max 180s)...
[0;31m[ERROR][0m ollama failed to become healthy after 180 seconds
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
[1;33m[WARNING][0m ollama is running but health check timed out
[0;36m[INFO][0m DEBUG: Service ollama deployed successfully
[0;36m[INFO][0m DEBUG: Deploying remaining service: openclaw
[0;36m[INFO][0m DEBUG: Pulling openclaw image...
 Image openclaw/openclaw:latest Pulling 
 Image openclaw/openclaw:latest Error pull access denied for openclaw/openclaw, repository does not exist or may require 'docker login': denied: requested access to the resource is denied
Error response from daemon: pull access denied for openclaw/openclaw, repository does not exist or may require 'docker login': denied: requested access to the resource is denied
[0;31m[ERROR][0m Failed to pull openclaw image
[0;31m[ERROR][0m ❌ ZERO TOLERANCE: Service openclaw deployment failed!
[0;31m[ERROR][0m 🚨 STOPPING DEPLOYMENT - Zero tolerance policy
[0;36m[INFO][0m DEBUG: Script 2 starting...
[0;36m[INFO][0m DEBUG: ENV_FILE=/mnt/data/.env
[0;36m[INFO][0m DEBUG: SERVICES_FILE=/mnt/data/metadata/selected_services.json
[0;36m[INFO][0m DEBUG: COMPOSE_FILE=/mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m Performing pre-deployment cleanup...
[0;36m[INFO][0m Cleaning up previous deployments...
[0;36m[INFO][0m Stopping AI platform containers using unified compose...
 Container signal-api Stopping 
 Container prometheus Stopping 
 Container anythingllm Stopping 
 Container minio Stopping 
 Container tailscale Stopping 
 Container flowise Stopping 
 Container openwebui Stopping 
 Container grafana Stopping 
 Container litellm Stopping 
 Container n8n Stopping 
 Container anythingllm Stopped 
 Container anythingllm Removing 
 Container signal-api Stopped 
 Container signal-api Removing 
 Container anythingllm Removed 
 Container prometheus Stopped 
 Container prometheus Removing 
 Container flowise Stopped 
 Container flowise Removing 
 Container signal-api Removed 
 Container minio Stopped 
 Container minio Removing 
 Container minio Removed 
 Container prometheus Removed 
 Container flowise Removed 
 Container tailscale Stopped 
 Container tailscale Removing 
 Container tailscale Removed 
 Container n8n Stopped 
 Container n8n Removing 
 Container grafana Stopped 
 Container grafana Removing 
 Container grafana Removed 
 Container n8n Removed 
 Container openwebui Stopped 
 Container openwebui Removing 
 Container openwebui Removed 
 Container ollama Stopping 
 Container ollama Stopped 
 Container ollama Removing 
 Container ollama Removed 
 Container litellm Stopped 
 Container litellm Removing 
 Container litellm Removed 
 Container postgres Stopping 
 Container redis Stopping 
 Container redis Stopped 
 Container redis Removing 
 Container redis Removed 
 Container postgres Stopped 
 Container postgres Removing 
 Container postgres Removed 
 Network ai_platform_internal Removing 
 Network ai_platform Removing 
 Network ai_platform Removed 
 Network ai_platform_internal Removed 
[0;32m[SUCCESS][0m All containers stopped successfully
[0;36m[INFO][0m Cleaning up orphaned containers...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: Cleaning up networks...
[0;36m[INFO][0m Cleaning up unused volumes...
Total reclaimed space: 0B
[0;36m[INFO][0m DEBUG: About to terminate background processes...
[0;36m[INFO][0m DEBUG: Current PID: 189867
[0;36m[INFO][0m DEBUG: Terminated other 2-deploy-services processes
[0;36m[INFO][0m DEBUG: Terminated docker-compose processes
[0;32m[SUCCESS][0m Pre-deployment cleanup completed
[0;36m[INFO][0m DEBUG: cleanup_previous_deployments function completed
[0;36m[INFO][0m DEBUG: About to call load_selected_services...
[0;36m[INFO][0m Loaded 15 selected services from Script 1
[0;36m[INFO][0m Services: prometheus flowise grafana n8n ollama openclaw dify anythingllm litellm redis postgres tailscale openwebui signal-api minio
[0;36m[INFO][0m DEBUG: load_selected_services completed successfully
[0;36m[INFO][0m DEBUG: Environment variables loaded:
[0;36m[INFO][0m   RUNNING_UID: 1001
[0;36m[INFO][0m   RUNNING_GID: 1001
[0;36m[INFO][0m   ENCRYPTION_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_SALT_KEY: mc0kzQLxm0ytCWT63nz2izOhE3fgXxtFNStX1pdRvazLABBKL3DafvdZbqklPY
[0;36m[INFO][0m   LITELLM_MASTER_KEY: t5WWkxxjSOUWD8GNIxevUuJmVg5KhmrN
[0;36m[INFO][0m DEBUG: About to verify compose file exists...
[0;36m[INFO][0m DEBUG: Compose file verification completed
[0;32m[SUCCESS][0m Using unified compose file: /mnt/data/ai-platform/deployment/stack/docker-compose.yml
[0;36m[INFO][0m DEBUG: About to generate proxy configuration...
[0;36m[INFO][0m Generating proxy configuration for caddy...
[0;36m[INFO][0m Generating Caddy configuration...
[0;32m[SUCCESS][0m Proxy configuration generated for caddy
[0;36m[INFO][0m Adding caddy service to docker-compose.yml...
[0;36m[INFO][0m Caddy already in compose file
[0;32m[SUCCESS][0m caddy added to compose
[0;36m[INFO][0m DEBUG: About to generate critical configurations...
[0;32m[SUCCESS][0m Prometheus config generated at /mnt/data/config/prometheus/prometheus.yml
[0;36m[INFO][0m DEBUG: About to fix volume permissions...
[0;32m[SUCCESS][0m PostgreSQL volume permissions set
[0;32m[SUCCESS][0m Redis volume permissions set
[0;36m[INFO][0m Setting up Grafana permissions (UID 472)...
[0;32m[SUCCESS][0m Grafana volume permissions set (UID 472)
[0;32m[SUCCESS][0m Ollama volume permissions set
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: About to create Docker networks...
[0;36m[INFO][0m DEBUG: Cleaning up existing networks...
[0;32m[SUCCESS][0m Created ai_platform network
[0;36m[INFO][0m DEBUG: Docker networks created successfully
[0;36m[INFO][0m DEBUG: About to start service deployment loop...
[0;36m[INFO][0m DEBUG: Deploying core infrastructure...
[0;36m[INFO][0m DEBUG: Pulling postgres image...
 Image postgres:15-alpine Pulling 
 Image postgres:15-alpine Pulled 
[0;36m[INFO][0m DEBUG: Starting postgres with explicit environment...
 Container postgres Creating 
 Container postgres Created 
 Container postgres Starting 
 Container postgres Started 
[0;36m[INFO][0m DEBUG: Waiting for postgres to become healthy...
[0;36m[INFO][0m Waiting for PostgreSQL to be ready (max 60s)...
[0;32m[SUCCESS][0m PostgreSQL is ready
[0;36m[INFO][0m DEBUG: Pulling redis image...
 Image redis:7-alpine Pulling 
 Image redis:7-alpine Pulled 
[0;36m[INFO][0m DEBUG: Starting redis with explicit environment...
 Container redis Creating 
 Container redis Created 
 Container redis Starting 
 Container redis Started 
[0;36m[INFO][0m DEBUG: Waiting for redis to become healthy...
[0;36m[INFO][0m Waiting for Redis to be ready (max 30s)...
[0;31m[ERROR][0m Redis failed to become ready after 30 seconds
[1;33m[WARNING][0m redis is running but health check timed out
[0;36m[INFO][0m DEBUG: Deploying monitoring services...
[0;36m[INFO][0m DEBUG: Pulling prometheus image...
 Image prom/prometheus:latest Pulling 
 Image prom/prometheus:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting prometheus with explicit environment...
 Container prometheus Starting 
 Container prometheus Started 
[0;36m[INFO][0m DEBUG: Waiting for prometheus to become healthy...
[0;36m[INFO][0m Waiting for prometheus to be healthy (max 180s)...
[0;31m[ERROR][0m prometheus failed to become healthy after 180 seconds
panic: Unable to create mmap-ed active query log

goroutine 1 [running]:
github.com/prometheus/prometheus/promql.NewActiveQueryTracker({0x7ffd2a728ed8, 0xb}, 0x14, 0xc000241090)
	/app/promql/query_logger.go:145 +0x345
main.main()
	/app/cmd/prometheus/main.go:894 +0x8953
time=2026-02-17T11:56:30.134Z level=INFO source=main.go:1589 msg="updated GOGC" old=100 new=75
time=2026-02-17T11:56:30.135Z level=INFO source=main.go:704 msg="Leaving GOMAXPROCS=2: CPU quota undefined" component=automaxprocs
time=2026-02-17T11:56:30.135Z level=INFO source=memlimit.go:198 msg="GOMEMLIMIT is updated" component=automemlimit package=github.com/KimMachineGun/automemlimit/memlimit GOMEMLIMIT=7380773683 previous=9223372036854775807
time=2026-02-17T11:56:30.135Z level=INFO source=main.go:803 msg="Starting Prometheus Server" mode=server version="(version=3.9.1, branch=HEAD, revision=9ec59baffb547e24f1468a53eb82901e58feabd8)"
time=2026-02-17T11:56:30.135Z level=INFO source=main.go:808 msg="operational information" build_context="(go=go1.25.5, platform=linux/amd64, user=root@61c3a9212c9e, date=20260107-16:08:09, tags=netgo,builtinassets)" host_details="(Linux 6.14.0-1018-aws #18~24.04.1-Ubuntu SMP Mon Nov 24 19:46:27 UTC 2025 x86_64 2e513e370b6d (none))" fd_limits="(soft=524287, hard=524288)" vm_limits="(soft=unlimited, hard=unlimited)"
time=2026-02-17T11:56:30.137Z level=ERROR source=query_logger.go:113 msg="Error opening query log file" component=activeQueryTracker file=/prometheus/queries.active err="open /prometheus/queries.active: permission denied"
panic: Unable to create mmap-ed active query log

goroutine 1 [running]:
github.com/prometheus/prometheus/promql.NewActiveQueryTracker({0x7fffc6829ed8, 0xb}, 0x14, 0xc0006629d0)
	/app/promql/query_logger.go:145 +0x345
main.main()
	/app/cmd/prometheus/main.go:894 +0x8953
[1;33m[WARNING][0m prometheus is running but health check timed out
[0;36m[INFO][0m DEBUG: Pulling grafana image...
 Image grafana/grafana:latest Pulling 
 Image grafana/grafana:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting grafana with explicit environment...
 Network ai_platform Creating 
 Network ai_platform Created 
 Container grafana Creating 
 Container grafana Created 
 Container grafana Starting 
 Container grafana Started 
[0;36m[INFO][0m DEBUG: Waiting for grafana to become healthy...
[0;36m[INFO][0m Waiting for grafana to be healthy (max 180s)...
[0;32m[SUCCESS][0m grafana is healthy
[0;36m[INFO][0m DEBUG: Deploying AI services...
[0;36m[INFO][0m DEBUG: Pulling ollama image...
 Image ollama/ollama:latest Pulling 
 Image ollama/ollama:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting ollama with explicit environment...
 Container ollama Creating 
 Container ollama Created 
 Container ollama Starting 
 Container ollama Started 
[0;36m[INFO][0m DEBUG: Waiting for ollama to become healthy...
[0;36m[INFO][0m Waiting for ollama to be healthy (max 180s)...
[0;31m[ERROR][0m ollama failed to become healthy after 180 seconds
Couldn't find '/ollama_data/.ollama/id_ed25519'. Generating new private key.
Your new public key is: 

ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOR4mtYwN6eT2LnNNCDAgp1dYZsYE2hIduZVAMEWNIfK

time=2026-02-17T11:57:40.022Z level=INFO source=routes.go:1663 msg="server config" env="map[CUDA_VISIBLE_DEVICES: GGML_VK_VISIBLE_DEVICES: GPU_DEVICE_ORDINAL: HIP_VISIBLE_DEVICES: HSA_OVERRIDE_GFX_VERSION: HTTPS_PROXY: HTTP_PROXY: NO_PROXY: OLLAMA_CONTEXT_LENGTH:0 OLLAMA_DEBUG:INFO OLLAMA_EDITOR: OLLAMA_FLASH_ATTENTION:false OLLAMA_GPU_OVERHEAD:0 OLLAMA_HOST:http://0.0.0.0:11434 OLLAMA_KEEP_ALIVE:5m0s OLLAMA_KV_CACHE_TYPE: OLLAMA_LLM_LIBRARY: OLLAMA_LOAD_TIMEOUT:5m0s OLLAMA_MAX_LOADED_MODELS:0 OLLAMA_MAX_QUEUE:512 OLLAMA_MODELS:/ollama_data/.ollama/models OLLAMA_MULTIUSER_CACHE:false OLLAMA_NEW_ENGINE:false OLLAMA_NOHISTORY:false OLLAMA_NOPRUNE:false OLLAMA_NO_CLOUD:false OLLAMA_NUM_PARALLEL:1 OLLAMA_ORIGINS:[* http://localhost https://localhost http://localhost:* https://localhost:* http://127.0.0.1 https://127.0.0.1 http://127.0.0.1:* https://127.0.0.1:* http://0.0.0.0 https://0.0.0.0 http://0.0.0.0:* https://0.0.0.0:* app://* file://* tauri://* vscode-webview://* vscode-file://*] OLLAMA_REMOTES:[ollama.com] OLLAMA_SCHED_SPREAD:false OLLAMA_VULKAN:false ROCR_VISIBLE_DEVICES: http_proxy: https_proxy: no_proxy:]"
time=2026-02-17T11:57:40.025Z level=INFO source=routes.go:1665 msg="Ollama cloud disabled: false"
time=2026-02-17T11:57:40.027Z level=INFO source=images.go:473 msg="total blobs: 0"
time=2026-02-17T11:57:40.027Z level=INFO source=images.go:480 msg="total unused blobs removed: 0"
time=2026-02-17T11:57:40.028Z level=INFO source=routes.go:1718 msg="Listening on [::]:11434 (version 0.16.2)"
time=2026-02-17T11:57:40.035Z level=INFO source=runner.go:67 msg="discovering available GPUs..."
time=2026-02-17T11:57:40.036Z level=INFO source=runner.go:106 msg="experimental Vulkan support disabled.  To enable, set OLLAMA_VULKAN=1"
time=2026-02-17T11:57:40.053Z level=INFO source=server.go:431 msg="starting runner" cmd="/usr/bin/ollama runner --ollama-engine --port 35327"
time=2026-02-17T11:57:40.188Z level=INFO source=server.go:431 msg="starting runner" cmd="/usr/bin/ollama runner --ollama-engine --port 44993"
time=2026-02-17T11:57:40.244Z level=INFO source=types.go:60 msg="inference compute" id=cpu library=cpu compute="" name=cpu description=cpu libdirs=ollama driver="" pci_id="" type="" total="7.6 GiB" available="7.6 GiB"
time=2026-02-17T11:57:40.244Z level=INFO source=routes.go:1768 msg="vram-based default context" total_vram="0 B" default_num_ctx=4096
[1;33m[WARNING][0m ollama is running but health check timed out
[0;36m[INFO][0m DEBUG: Pulling litellm image...
 Image ghcr.io/berriai/litellm:main-latest Pulling 
 Image ghcr.io/berriai/litellm:main-latest Pulled 
[0;36m[INFO][0m DEBUG: Starting litellm with explicit environment...
 Container postgres Running 
 Container redis Running 
 Container litellm Creating 
 Container litellm Created 
 Container postgres Waiting 
 Container redis Waiting 
 Container redis Healthy 
 Container postgres Healthy 
 Container litellm Starting 
 Container litellm Started 
[0;36m[INFO][0m DEBUG: Waiting for litellm to become healthy...
[0;36m[INFO][0m Waiting for litellm to be healthy (max 180s)...
[0;31m[ERROR][0m litellm failed to become healthy after 180 seconds
           ~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.13/site-packages/click/core.py", line 783, in invoke
    return __callback(*args, **kwargs)
  File "/usr/lib/python3.13/site-packages/litellm/proxy/proxy_cli.py", line 670, in run_server
    _config = asyncio.run(proxy_config.get_config(config_file_path=config))
  File "/usr/lib/python3.13/asyncio/runners.py", line 195, in run
    return runner.run(main)
           ~~~~~~~~~~^^^^^^
  File "/usr/lib/python3.13/asyncio/runners.py", line 118, in run
    return self._loop.run_until_complete(task)
           ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^
  File "/usr/lib/python3.13/asyncio/base_events.py", line 725, in run_until_complete
    return future.result()
           ~~~~~~~~~~~~~^^
  File "/usr/lib/python3.13/site-packages/litellm/proxy/proxy_server.py", line 2318, in get_config
    config = await self._get_config_from_file(config_file_path=config_file_path)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.13/site-packages/litellm/proxy/proxy_server.py", line 2068, in _get_config_from_file
    raise Exception(f"Config file not found: {file_path}")
Exception: Config file not found: /app/config/config.yaml
[1;33m[WARNING][0m litellm is running but health check timed out
[0;36m[INFO][0m DEBUG: Pulling openwebui image...
 Image ghcr.io/open-webui/open-webui:main Pulling 
 Image ghcr.io/open-webui/open-webui:main Pulled 
[0;36m[INFO][0m DEBUG: Starting openwebui with explicit environment...
 Container ollama Running 
 Container openwebui Creating 
 Container openwebui Created 
 Container openwebui Starting 
 Container openwebui Started 
[0;36m[INFO][0m DEBUG: Waiting for openwebui to become healthy...
[0;36m[INFO][0m Waiting for openwebui to be healthy (max 180s)...
[0;31m[ERROR][0m openwebui failed to become healthy after 180 seconds
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 196, in reraise
    raise value.with_traceback(tb)
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 3321, in execute_sql
    cursor = self.cursor()
             ^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 3311, in cursor
    self.connect()
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 3262, in connect
    with __exception_wrapper__:
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 3088, in __exit__
    reraise(new_type, new_type(exc_value, *exc_args), traceback)
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 196, in reraise
    raise value.with_traceback(tb)
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 3263, in connect
    self._state.set_connection(self._connect())
                               ^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/peewee.py", line 3604, in _connect
    conn = sqlite3.connect(self.database, timeout=self._timeout,
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
peewee.OperationalError: unable to open database file
[1;33m[WARNING][0m openwebui is running but health check timed out
[0;36m[INFO][0m DEBUG: Pulling anythingllm image...
 Image mintplexlabs/anythingllm:latest Pulling 
 Image mintplexlabs/anythingllm:latest Pulled 
[0;36m[INFO][0m DEBUG: Starting anythingllm with explicit environment...
 Container anythingllm Creating 
 Container anythingllm Created 
 Container anythingllm Starting 
 Container anythingllm Started 
[0;36m[INFO][0m DEBUG: Waiting for anythingllm to become healthy...
[0;36m[INFO][0m Waiting for anythingllm to be healthy (max 180s)...
