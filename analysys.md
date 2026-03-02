Service Status Audit
Copy table


#
Service
Reported Status
Root Cause
Severity



1
Caddy
✅ Healthy
—
—


2
PostgreSQL
✅ Healthy
—
—


3
Redis
✅ Healthy
—
—


4
Ollama
✅ Healthy
—
—


5
Open WebUI
⚠️ Slow start
Normal first-boot behaviour
Low


6
n8n
✅ Healthy
—
—


7
Flowise
✅ Healthy
—
—


8
LiteLLM
❌ Unhealthy
3 bugs (see below)
High


9
Qdrant
✅ Healthy
—
—


10
AnythingLLM
❌ Restarting
2 bugs (see below)
High


11
Grafana
✅ Healthy
—
—


12
Prometheus
✅ Healthy
—
—


13
Authentik
⚠️ Starting
DB not pre-created + image tag
Medium


14
Signal API
❌ Failed
Requires manual registration — by design
Info


15
Dify
❌ Failed
4 bugs (see below)
High



Detailed Bug Analysis & Windsurf Fix Instructions

🔴 BUG 1 — PostgreSQL: Databases Never Created
File: scripts/2-deploy-services.sh → write_init_scripts()
Problem: The SQL uses CREATE DATABASE IF NOT EXISTS which is not valid PostgreSQL syntax. It is MySQL syntax. PostgreSQL will error on every line, meaning n8n, flowise, litellm, authentik, and dify databases never exist. Every service that needs its own database fails.
Fix for Windsurf: Replace write_init_scripts() in 2-deploy-services.sh:
write_init_scripts() {
    local init_dir="${DATA_ROOT}/compose/init-scripts"
    mkdir -p "${init_dir}"

    cat > "${init_dir}/01-create-databases.sql" << 'EOF'
SELECT 'CREATE DATABASE n8n' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n')\gexec
SELECT 'CREATE DATABASE flowise' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'flowise')\gexec
SELECT 'CREATE DATABASE litellm' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'litellm')\gexec
SELECT 'CREATE DATABASE authentik' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'authentik')\gexec
SELECT 'CREATE DATABASE dify' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'dify')\gexec
EOF
}

🔴 BUG 2 — LiteLLM: Three Compounding Failures
File: scripts/2-deploy-services.sh → append_litellm()
Problem 1 — Wrong health endpoint: /health/liveliness returns 401 without a key header. Docker marks it unhealthy immediately.
Problem 2 — Config written with absolute host path, not compose-relative: The volume mount uses ${litellm_config_dir}/config.yaml (absolute path on host). This works on first deploy but breaks on any machine where DATA_ROOT differs from what Docker expects, and breaks 4-add-service.sh entirely since it duplicates the function without the mkdir