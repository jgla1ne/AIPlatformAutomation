This document defines how Windsurf should repair and stabilize the stack while preserving the repository’s principles.

Core constraints from the project philosophy:

Pure bash automation

Zero external orchestration frameworks

Deterministic deployment

Minimal dependencies

Auditable scripts

Simple pipeline stages

The solution therefore focuses on execution correctness, not architectural expansion.

1. Root Cause Model (Based on the Analysis Document)

The comprehensive analysis identifies several systemic failure categories.

A. Race Conditions

Containers start before dependencies exist.

Typical example:

API starts before Postgres ready
Frontend starts before API ready

This is one of the most common deployment failures in automated pipelines.
Misconfiguration and sequencing issues are known to cause a large share of deployment problems, often resolved through validation and deterministic execution order.

B. DNS / Domain Resolution Timing

Scripts assume DNS already propagated.

Reality:

User configures domain
DNS may take minutes/hours
Script fails immediately
C. Docker Network Timing

Common failure pattern:

container attach network before creation
D. Interactive Input Regression

Recent regressions include:

0 = All services broken
domain prompt split into multiple steps
IP detection inconsistent

These break the deterministic UX promised by the README.

E. Service Health Not Verified

Scripts assume success after:

docker compose up -d

But containers may be:

crashing
restarting
misconfigured
2. Correct Deployment Model

The platform must follow a strict stage contract architecture.

Stage 0  Clean environment
Stage 1  Host preparation
Stage 2  Infrastructure deployment
Stage 3  Application deployment
Stage 4  Configuration
Stage 5  Validation

Each stage must:

verify prerequisites
execute
verify results
exit on failure
3. Deterministic Service Dependency Graph

The stack must follow a strict dependency order.

Docker Engine
   ↓
Docker Network
   ↓
Volumes
   ↓
Databases
   ↓
Infrastructure Services
   ↓
Application Services
   ↓
Reverse Proxy
   ↓
TLS

Concrete order:

postgres
redis
vector database
api services
worker services
frontend
proxy
4. Mandatory Wait Mechanisms

The biggest missing component is dependency readiness verification.

Every service must wait for its dependency.

Example pattern:

wait_for_port() {
  host=$1
  port=$2

  for i in {1..30}; do
      nc -z $host $port && return 0
      sleep 2
  done

  echo "Timeout waiting for $host:$port"
  exit 1
}

Example usage:

wait_for_port localhost 5432
wait_for_port localhost 6379
5. DNS Validation Model

Domain verification must follow this flow:

user inputs domain
resolve public server IP
resolve domain IP
compare

Example:

PUBLIC_IP=$(curl -s https://api.ipify.org)
DNS_IP=$(dig +short $DOMAIN | tail -n1)

If mismatch:

DNS not yet propagated
wait or abort
6. Deterministic Docker Network Creation

Must be idempotent.

Replace:

docker network create ai-platform

With:

docker network inspect ai-platform >/dev/null 2>&1 \
|| docker network create ai-platform
7. Service Startup Model

Instead of:

docker compose up -d

Use staged startup:

start database
wait ready

start cache
wait ready

start backend
wait ready

start frontend
8. Health Validation Layer

Every service must expose a health endpoint.

Example:

/health
/status
/ping

Validation script:

curl -f http://localhost:3000/health

If failure:

exit deployment
9. Interactive Interface Fixes

The CLI must restore the original behavior.

Correct UX:

Select services to deploy

0) All services
1) n8n
2) openwebui
3) ollama
4) langflow

Handler:

case "$choice" in
0) deploy_all ;;
1) deploy_n8n ;;
...
esac
10. Environment Consistency

All scripts must load the same environment file.

Pattern:

/opt/ai-platform/.env

Load:

set -a
source /opt/ai-platform/.env
set +a
11. Logging Strategy

Without adding frameworks.

Simple logging:

/var/log/aiplatform

Example:

setup.log
deploy.log
config.log

Wrapper:

exec > >(tee -a deploy.log)
exec 2>&1
12. Failure Diagnostics

If container fails:

docker compose logs

Expose automatically.

Example:

docker compose up -d || {
   docker compose logs
   exit 1
}
13. Security Considerations

Automation scripts deploying AI tools must account for the rapidly expanding attack surface around APIs and automation services. Recent threat briefings highlight exploitation of AI workflow platforms and API misconfigurations in production environments.

Therefore minimal protections should be included:

firewall ports
docker secrets
.env isolation

But without adding orchestration frameworks.

14. Minimal Observability

To remain aligned with the project philosophy:

docker ps
docker logs
curl health endpoints

No observability stack.

15. Validation Script

Final validation step.

scripts/validate.sh

Checks:

containers running
ports open
API responding
frontend responding
TLS valid

Example:

curl -I https://domain
16. Recovery Strategy

If deployment partially fails:

docker compose down
docker compose up -d

Or restart failing containers:

docker restart container
17. Windsurf Implementation Plan

Windsurf should implement fixes in this order:

Phase 1 — Script correctness

restore interactive menus

fix environment loading

restore domain prompt

Phase 2 — determinism

add wait functions

add DNS validation

enforce service ordering

Phase 3 — robustness

add health checks

add logging

add failure diagnostics

Phase 4 — validation

final deployment verification

18. Expected Result

After fixes the stack should achieve:

deterministic installation
reproducible deployments
no race conditions
clear diagnostics
single-command deployment

Final UX:

git clone repo
cd AIPlatformAutomation
sudo ./scripts/1-setup-system.sh
sudo ./scripts/2-deploy-services.sh
sudo ./scripts/3-configure-services.sh

Output:

✔ Docker installed
✔ Network created
✔ Services deployed
✔ Configuration applied
✔ Platform available