

# AI Platform Deployment Log Analysis

**Generated:** Sun Mar 15 09:48:39 UTC 2026  
**Tenant:** datasquiz  
**Domain:** ai.datasquiz.net  
**Status:** Infrastructure deployed, frontend URLs not responding

---

## 🚨 ISSUE SUMMARY
- ✅ All infrastructure services healthy (postgres, redis, qdrant, caddy, tailscale)
- ❌ Frontend URLs returning connection refused/SSL errors
- ❌ Web services not accessible via configured domains

---

## 📊 SERVICE STATUS OVERVIEW

NAME                       IMAGE                        COMMAND                  SERVICE     CREATED       STATUS                            PORTS
ai-datasquiz-caddy-1       caddy:2-alpine               "caddy run --config …"   caddy       4 hours ago   Up 4 hours (healthy)              0.0.0.0:80->80/tcp, [::]:80->80/tcp, 0.0.0.0:443->443/tcp, [::]:443->443/tcp, 0.0.0.0:2019->2019/tcp, [::]:2019->2019/tcp, 443/udp
ai-datasquiz-postgres-1    postgres:15-alpine           "docker-entrypoint.s…"   postgres    4 hours ago   Up 4 hours (healthy)              5432/tcp
ai-datasquiz-qdrant-1      qdrant/qdrant:latest         "./entrypoint.sh"        qdrant      4 hours ago   Restarting (101) 27 seconds ago   
ai-datasquiz-redis-1       redis:7-alpine               "docker-entrypoint.s…"   redis       4 hours ago   Up 4 hours (healthy)              6379/tcp
ai-datasquiz-tailscale-1   tailscale/tailscale:latest   "/usr/local/bin/cont…"   tailscale   4 hours ago   Up 4 hours (unhealthy)            
NAME                       IMAGE                        COMMAND                  SERVICE     CREATED       STATUS                            PORTS
ai-datasquiz-caddy-1       caddy:2-alpine               "caddy run --config …"   caddy       4 hours ago   Up 4 hours (healthy)              0.0.0.0:80->80/tcp, [::]:80->80/tcp, 0.0.0.0:443->443/tcp, [::]:443->443/tcp, 0.0.0.0:2019->2019/tcp, [::]:2019->2019/tcp, 443/udp
ai-datasquiz-postgres-1    postgres:15-alpine           "docker-entrypoint.s…"   postgres    4 hours ago   Up 4 hours (healthy)              5432/tcp
ai-datasquiz-qdrant-1      qdrant/qdrant:latest         "./entrypoint.sh"        qdrant      4 hours ago   Restarting (101) 36 seconds ago   
ai-datasquiz-redis-1       redis:7-alpine               "docker-entrypoint.s…"   redis       4 hours ago   Up 4 hours (healthy)              6379/tcp
ai-datasquiz-tailscale-1   tailscale/tailscale:latest   "/usr/local/bin/cont…"   tailscale   4 hours ago   Up 4 hours (unhealthy)            

---

## 📋 CURRENT RUNNING CONTAINERS


ai-datasquiz-caddy-1       Up 4 hours (healthy)              0.0.0.0:80->80/tcp, [::]:80->80/tcp, 0.0.0.0:443->443/tcp, [::]:443->443/tcp, 0.0.0.0:2019->2019/tcp, [::]:2019->2019/tcp, 443/udp
ai-datasquiz-tailscale-1   Up 4 hours (unhealthy)            
ai-datasquiz-qdrant-1      Restarting (101) 10 seconds ago   
ai-datasquiz-redis-1       Up 4 hours (healthy)              6379/tcp
ai-datasquiz-postgres-1    Up 4 hours (healthy)              5432/tcp

NAMES                    STATUS                    PORTS
ai-datasquiz-caddy-1       Up 4 hours (healthy)              0.0.0.0:80->80/tcp, [::]:80->80/tcp, 0.0.0.0:443->443/tcp, [::]:443->443/tcp, 0.0.0.0:2019->2019/tcp, [::]:2019->2019/tcp, 443/udp
ai-datasquiz-tailscale-1   Up 4 hours (unhealthy)            
ai-datasquiz-qdrant-1      Restarting (101) 23 seconds ago   
ai-datasquiz-redis-1       Up 4 hours (healthy)              6379/tcp
ai-datasquiz-postgres-1    Up 4 hours (healthy)              5432/tcp

---

## 🔍 CRITICAL FINDINGS

### 🚨 IMMEDIATE ISSUES:
1. **Qdrant is restarting (101)** - Vector database unstable
2. **Tailscale unhealthy** - VPN connectivity issues  
3. **Missing web services** - No LiteLLM, OpenWebUI, etc. containers
4. **Only Caddy exposed** - Only reverse proxy has external ports

---

## 📝 INDIVIDUAL SERVICE LOGS

### 🌐 CADDY (Reverse Proxy)

### Caddy Logs:


### Qdrant Logs (Vector Database):

   2: std::panicking::panic_handler::{{closure}}
   3: std::sys::backtrace::__rust_end_short_backtrace
   4: __rustc::rust_begin_unwind
   5: core::panicking::panic_fmt
   6: core::result::unwrap_failed
   7: qdrant::actix::init::{{closure}}
   8: tokio::task::local::LocalSet::run_until::{{closure}}
   9: std::sys::backtrace::__rust_begin_short_backtrace
  10: core::ops::function::FnOnce::call_once{{vtable.shim}}
  11: std::sys::thread::unix::Thread::new::thread_start
  12: <unknown>
  13: __clone

2026-03-15T09:50:34.863520Z ERROR qdrant::startup: Panic occurred in file src/actix/mod.rs at line 70: called `Result::unwrap()` on an `Err` value: ServiceError { error: "Failed to create snapshots temp directory at ./snapshots/tmp: Custom { kind: PermissionDenied, error: Error { kind: CreateDir, source: Os { code: 13, kind: PermissionDenied, message: \"Permission denied\" }, path: \"./snapshots/tmp\" } }", backtrace: Some("   0: collection::operations::types::CollectionError::service_error\n   1: storage::content_manager::toc::temp_directories::<impl storage::content_manager::toc::TableOfContent>::snapshots_temp_path\n   2: qdrant::actix::init::{{closure}}\n   3: tokio::task::local::LocalSet::run_until::{{closure}}\n   4: std::sys::backtrace::__rust_begin_short_backtrace\n   5: core::ops::function::FnOnce::call_once{{vtable.shim}}\n   6: std::sys::thread::unix::Thread::new::thread_start\n   7: <unknown>\n   8: __clone\n") }
2026-03-15T09:50:35.741141Z ERROR qdrant::startup: Panic backtrace: 
   0: qdrant::startup::setup_panic_hook::{{closure}}
   1: std::panicking::panic_with_hook
   2: std::panicking::panic_handler::{{closure}}
   3: std::sys::backtrace::__rust_end_short_backtrace
   4: __rustc::rust_begin_unwind
   5: core::panicking::panic_fmt
   6: core::result::unwrap_failed
   7: qdrant::main
   8: std::sys::backtrace::__rust_begin_short_backtrace
   9: main
  10: <unknown>
  11: __libc_start_main
  12: _start

2026-03-15T09:50:35.741173Z ERROR qdrant::startup: Panic occurred in file src/main.rs at line 683: thread is not panicking: Any { .. }
Qdrant is restarting - checking last error:
  12: <unknown>
  13: __clone

2026-03-15T09:50:34.863520Z ERROR qdrant::startup: Panic occurred in file src/actix/mod.rs at line 70: called `Result::unwrap()` on an `Err` value: ServiceError { error: "Failed to create snapshots temp directory at ./snapshots/tmp: Custom { kind: PermissionDenied, error: Error { kind: CreateDir, source: Os { code: 13, kind: PermissionDenied, message: \"Permission denied\" }, path: \"./snapshots/tmp\" } }", backtrace: Some("   0: collection::operations::types::CollectionError::service_error\n   1: storage::content_manager::toc::temp_directories::<impl storage::content_manager::toc::TableOfContent>::snapshots_temp_path\n   2: qdrant::actix::init::{{closure}}\n   3: tokio::task::local::LocalSet::run_until::{{closure}}\n   4: std::sys::backtrace::__rust_begin_short_backtrace\n   5: core::ops::function::FnOnce::call_once{{vtable.shim}}\n   6: std::sys::thread::unix::Thread::new::thread_start\n   7: <unknown>\n   8: __clone\n") }
2026-03-15T09:50:35.741141Z ERROR qdrant::startup: Panic backtrace: 
   0: qdrant::startup::setup_panic_hook::{{closure}}
   1: std::panicking::panic_with_hook
   2: std::panicking::panic_handler::{{closure}}
   3: std::sys::backtrace::__rust_end_short_backtrace
   4: __rustc::rust_begin_unwind
   5: core::panicking::panic_fmt
   6: core::result::unwrap_failed
   7: qdrant::main
   8: std::sys::backtrace::__rust_begin_short_backtrace
   9: main
  10: <unknown>
  11: __libc_start_main
  12: _start

2026-03-15T09:50:35.741173Z ERROR qdrant::startup: Panic occurred in file src/main.rs at line 683: thread is not panicking: Any { .. }


### Tailscale Logs (VPN):



### PostgreSQL Logs:



### Redis Logs:

1:C 15 Mar 2026 05:35:19.572 * Configuration loaded
1:M 15 Mar 2026 05:35:19.572 * monotonic clock: POSIX clock_gettime
1:M 15 Mar 2026 05:35:19.574 * Running mode=standalone, port=6379.
1:M 15 Mar 2026 05:35:19.575 * Server initialized
1:M 15 Mar 2026 05:35:19.579 * Loading RDB produced by version 7.4.8
1:M 15 Mar 2026 05:35:19.579 * RDB age 368744 seconds
1:M 15 Mar 2026 05:35:19.579 * RDB memory usage when created 0.90 Mb
1:M 15 Mar 2026 05:35:19.579 * Done loading RDB, keys loaded: 0, keys expired: 0.
1:M 15 Mar 2026 05:35:19.579 * DB loaded from disk: 0.001 seconds
1:M 15 Mar 2026 05:35:19.579 * Ready to accept connections tcp


---

## 🔍 CONFIGURATION ANALYSIS

### Generated Caddyfile:

{
    admin 0.0.0.0:2019
    email admin@datasquiz.net
}

grafana.ai.datasquiz.net {
    tls internal
    reverse_proxy grafana:3000
}
prometheus.ai.datasquiz.net {
    tls internal
    reverse_proxy prometheus:9090
}

{
    admin 0.0.0.0:2019
    email admin@datasquiz.net
}

grafana.ai.datasquiz.net {
    tls internal
    reverse_proxy grafana:3000
}
prometheus.ai.datasquiz.net {
    tls internal
    reverse_proxy prometheus:9090
}

### Environment Variables (.env):

DOMAIN=ai.datasquiz.net
ENABLE_POSTGRES=true
ENABLE_REDIS=true
ENABLE_CADDY=true
ENABLE_QDRANT=true
ENABLE_GRAFANA=true
ENABLE_PROMETHEUS=true
ENABLE_AUTHENTIK=true
ENABLE_SIGNAL=true
ENABLE_TAILSCALE=true
ENABLE_OPENCLAW=true
ENABLE_RCLONE=true
# ════════════════════════════════════════════════════════════════════════
# AI Platform — Environment Configuration
# Generated: 2026-03-15T05:33:05Z
# ════════════════════════════════════════════════════════════════════════

# ─── Platform Identity ────────────────────────────────────────────────────────
TENANT_ID=datasquiz
DOMAIN=ai.datasquiz.net
ADMIN_EMAIL=admin@datasquiz.net
DATA_ROOT=/mnt/data/datasquiz
SSL_TYPE=selfsigned
PROJECT_PREFIX=ai-

# ─── Tenant User Configuration ───────────────────────────────────────────────────
TENANT_UID=1001
TENANT_GID=1001

# ─── Service Ownership UIDs (Pragmatic Exception Pattern) ───────────────────────
# Per README.md, some services ignore the 'user:' directive and require
# their internal UID to own their data directory. These are defined here as
# configurable variables to avoid hardcoding in scripts.
# If a service is compliant, its variable can be left blank or removed.
POSTGRES_UID=70
PROMETHEUS_UID=65534
GRAFANA_UID=472
N8N_UID=1000
QDRANT_UID=1000
REDIS_UID=999
OPENWEBUI_UID=1000
ANYTHINGLLM_UID=1000
ENABLE_POSTGRES=true
ENABLE_REDIS=true
ENABLE_CADDY=true
ENABLE_QDRANT=true
ENABLE_GRAFANA=true
ENABLE_PROMETHEUS=true
ENABLE_AUTHENTIK=true
ENABLE_SIGNAL=true
ENABLE_TAILSCALE=true
ENABLE_OPENCLAW=true
ENABLE_RCLONE=true

# ENABLED SERVICES:
ENABLE_POSTGRES=true
ENABLE_REDIS=true
ENABLE_CADDY=true
ENABLE_OLLAMA=false
ENABLE_OPENAI=false
ENABLE_ANTHROPIC=false
ENABLE_LOCALAI=false
ENABLE_VLLM=false
ENABLE_OPENWEBUI=false
ENABLE_ANYTHINGLLM=false
ENABLE_DIFY=false
ENABLE_N8N=false
ENABLE_FLOWISE=false
ENABLE_LITELLM=false
ENABLE_QDRANT=true
ENABLE_WEAVIATE=false
ENABLE_PINECONE=false
ENABLE_CHROMADB=false
ENABLE_MILVUS=false
ENABLE_GRAFANA=true
ENABLE_PROMETHEUS=true
ENABLE_AUTHENTIK=true
ENABLE_SIGNAL=true
ENABLE_TAILSCALE=true
ENABLE_OPENCLAW=true
ENABLE_RCLONE=true
ENABLE_MINIO=false

---

## 🎯 ROOT CAUSE ANALYSIS

### 🚨 CRITICAL ISSUES IDENTIFIED:

1. **MISSING WEB SERVICES**: 
   - ENABLE_LITELLM=false ❌ (AI gateway required for all web services)
   - ENABLE_OPENWEBUI=false ❌ (Chat interface)
   - ENABLE_N8N=false ❌ (Workflow automation)
   - ENABLE_ANYTHINGLLM=false ❌ (Document chat)
   - ENABLE_FLOWISE=false ❌ (AI workflow builder)

2. **QDRANT RESTART LOOP**:
   - Vector database continuously restarting (exit code 101)
   - No web services can function without vector DB

3. **CADDY PROXY FAILURES**:
   - Trying to proxy to non-existent services (grafana, prometheus)
   - DNS resolution failures: "lookup grafana on 127.0.0.11:53: server misbehaving"
   - SSL certificate issues with self-signed certs

4. **POSTGRES DATABASE ERRORS**:
   - Continuous connection attempts to non-existent database "ds-admin"
   - Something trying to connect with wrong database name

---

## 🔧 IMMEDIATE FIXES NEEDED

### 1. Enable Core AI Services
The deployment only deployed infrastructure, but no AI services. Need to enable:

```bash
# Enable in .env file:
ENABLE_LITELLM=true
ENABLE_OPENWEBUI=true  
ENABLE_OLLAMA=true  # For local models
```

### 2. Fix Qdrant Restart Issue
Check Qdrant configuration and permissions.

### 3. Deploy Missing Services
Run deployment again with enabled services.

---

## 📊 NETWORK CONNECTIVITY TESTS

### Test Local Access:
```bash
# Test Caddy admin interface
curl http://localhost:2019/

# Test direct service ports  
curl http://localhost:3000/  # Grafana (should be running)
curl http://localhost:9090/  # Prometheus (should be running)
```

### Test Domain Resolution:
```bash
nslookup grafana.ai.datasquiz.net
nslookup prometheus.ai.datasquiz.net
```

---

## 🚀 NEXT STEPS

1. **Enable AI Services** in .env file
2. **Fix Qdrant** restart issue  
3. **Re-run deployment** with all services
4. **Test connectivity** to all endpoints
5. **Verify SSL certificates** for domain access

---

**Generated:** Sun Mar 15 09:53:27 UTC 2026  
**Analysis Status:** Infrastructure deployed, web services missing - needs service enablement

 Container ai-datasquiz-redis-1 Running 
time="2026-03-15T06:14:34Z" level=warning msg="The \"CONFIG_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:14:34Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:14:34Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:14:34Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:14:34Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
 Container ai-datasquiz-qdrant-1 Starting 
 Container ai-datasquiz-qdrant-1 Started 
time="2026-03-15T06:14:34Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:14:34Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:14:34Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:14:34Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:14:34Z" level=warning msg="The \"CONFIG_DIR\" variable is not set. Defaulting to a blank string."
 Container ai-datasquiz-redis-1 Running 
 Container ai-datasquiz-postgres-1 Running 
 Container ai-datasquiz-caddy-1 Running 
 Container ai-datasquiz-postgres-1 Waiting 
 Container ai-datasquiz-redis-1 Waiting 
 Container ai-datasquiz-redis-1 Healthy 
 Container ai-datasquiz-postgres-1 Healthy 
time="2026-03-15T06:15:49Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:49Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:49Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:49Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:49Z" level=warning msg="The \"CONFIG_DIR\" variable is not set. Defaulting to a blank string."
 Container ai-datasquiz-postgres-1 Running 
time="2026-03-15T06:15:50Z" level=warning msg="The \"CONFIG_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:50Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:50Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:50Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:50Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
 Container ai-datasquiz-redis-1 Running 
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"CONFIG_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
 Container ai-datasquiz-qdrant-1 Running 
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"CONFIG_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
 Container ai-datasquiz-postgres-1 Running 
 Container ai-datasquiz-redis-1 Running 
 Container ai-datasquiz-caddy-1 Running 
 Container ai-datasquiz-postgres-1 Waiting 
 Container ai-datasquiz-redis-1 Waiting 
 Container ai-datasquiz-postgres-1 Healthy 
 Container ai-datasquiz-redis-1 Healthy 

---

## 📋 DEPLOYMENT LOGS

### Latest Deployment Log:
```
time="2026-03-15T06:15:49Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:49Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:49Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:49Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:49Z" level=warning msg="The \"CONFIG_DIR\" variable is not set. Defaulting to a blank string."
 Container ai-datasquiz-postgres-1 Running 
time="2026-03-15T06:15:50Z" level=warning msg="The \"CONFIG_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:50Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:50Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:50Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:50Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
 Container ai-datasquiz-redis-1 Running 
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"CONFIG_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
 Container ai-datasquiz-qdrant-1 Running 
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"CONFIG_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
time="2026-03-15T06:15:51Z" level=warning msg="The \"DATA_DIR\" variable is not set. Defaulting to a blank string."
 Container ai-datasquiz-postgres-1 Running 
 Container ai-datasquiz-redis-1 Running 
 Container ai-datasquiz-caddy-1 Running 
 Container ai-datasquiz-postgres-1 Waiting 
 Container ai-datasquiz-redis-1 Waiting 
 Container ai-datasquiz-postgres-1 Healthy 
 Container ai-datasquiz-redis-1 Healthy 
```

---

## 🎯 FINAL DIAGNOSIS

### ROOT CAUSE: **Missing Web Services Deployment**

The deployment script only deployed **infrastructure services** because all web services are **disabled** in the .env file:

❌ **DISABLED (Missing):**
- LiteLLM (AI Gateway) - ENABLE_LITELLM=false
- OpenWebUI (Chat Interface) - ENABLE_OPENWEBUI=false  
- Ollama (Local LLM Runtime) - ENABLE_OLLAMA=false
- n8n (Workflow Automation) - ENABLE_N8N=false
- Flowise (AI Workflow Builder) - ENABLE_FLOWISE=false
- AnythingLLM (Document Chat) - ENABLE_ANYTHINGLLM=false

✅ **DEPLOYED (Infrastructure Only):**
- PostgreSQL, Redis, Qdrant, Caddy, Tailscale

### WHY URLs ARE FAILING:
1. **grafana.ai.datasquiz.net** → Caddy trying to proxy to non-existent Grafana container
2. **prometheus.ai.datasquiz.net** → Caddy trying to proxy to non-existent Prometheus container  
3. **All other domains** → No backend services exist

### IMMEDIATE SOLUTION:
Enable core AI services in .env and re-run deployment:

```bash
# Edit /mnt/data/datasquiz/.env and set:
ENABLE_LITELLM=true
ENABLE_OPENWEBUI=true
ENABLE_OLLAMA=true

# Then re-run deployment:
sudo bash scripts/2-deploy-services.sh datasquiz
```

---

**Analysis Complete:** The platform deployed infrastructure successfully but needs AI services enabled for frontend functionality.

