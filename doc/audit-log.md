════════════════════════════════════════════════════════════════════╗
║            AI PLATFORM AUTOMATION - DEPLOYMENT                 ║
║              Non-Root Version 7.0.0                      ║
║           AppArmor Security & Complete Coverage              ║
╚════════════════════════════════════════════════════════════════════╝

[INFO] Performing pre-deployment cleanup...
[INFO] Cleaning up previous deployments...
[INFO] Stopping AI platform containers using unified compose...
[SUCCESS] All containers stopped successfully
[INFO] Cleaning up orphaned containers...
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
[INFO] DEBUG: About to terminate background processes...
[INFO] DEBUG: Current PID: 3951208
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

→ Generating proxy configuration...
[INFO] Generating proxy configuration for caddy...
[INFO] Generating Caddy configuration...
[SUCCESS] Proxy configuration generated for caddy
[INFO] Adding caddy service to docker-compose.yml...
[INFO] Caddy already in compose file
[SUCCESS] caddy added to compose
✓ Proxy configuration ready

[INFO] DEBUG: About to create Docker networks...
[INFO] DEBUG: About to create Docker networks...
[INFO] DEBUG: Cleaning up existing networks...
[+] up 1/2
 ✔ Network ai_platform_internal Created                                                                                                                                                                                                         0.1s
[+] up 2/2er prometheus         Creating                                                       
 ✔ Network ai_platform_internal Created                                                                                                                                                                                                         0.1s
[+] up 2/2er prometheus         Created                                                        
 ✔ Network ai_platform_internal Created                                                                                                                                                                                                         0.1s
[+] up 2/2er prometheus         Created                                                        
 ✔ Network ai_platform_internal Created                                                                                                                                                                                                         0.1s
[+] up 2/2er prometheus         Created                                                        
 ✔ Network ai_platform_internal Created                                                                                                                                                                                                         0.1s
 ✔ Container prometheus         Created                                                                                                                                                                                                         0.1s
[SUCCESS] Created ai_platform network
[INFO] DEBUG: Docker networks created successfully
[INFO] DEBUG: About to start service deployment loop...
[INFO] DEBUG: Deploying core infrastructure...
[INFO] DEBUG: Fixing PostgreSQL volume permissions...
[INFO] DEBUG: Fixing Redis volume permissions...
  🐳 postgres: 
[INFO] DEBUG: Pulling postgres image...
[INFO] DEBUG: Starting postgres with explicit environment...
[INFO] DEBUG: Waiting for postgres to become healthy...
[INFO] Waiting for PostgreSQL to be ready...
[SUCCESS] PostgreSQL is ready
✓ HEALTHY
    → Database ready on 5432
  🐳 redis: 
[INFO] DEBUG: Pulling redis image...
[INFO] DEBUG: Starting redis with explicit environment...
[INFO] DEBUG: Waiting for redis to become healthy...
[INFO] Waiting for localhost:6379 to be available...
[ERROR] localhost:6379 failed to become available
⚠ RUNNING (health check timeout)
[WARNING] redis is running but health check timed out
[INFO] DEBUG: Deploying monitoring services...
  🐳 prometheus: 
[INFO] DEBUG: Pulling prometheus image...
[INFO] DEBUG: Starting prometheus with explicit environment...
[INFO] DEBUG: Waiting for prometheus to become healthy...
[INFO] Waiting for prometheus to become healthy...
[ERROR] prometheus failed to become healthy after 180 attempts
time=2026-02-17T07:27:03.832Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:27:04.302Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:27:04.784Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:27:05.467Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:27:06.680Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:27:08.639Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:27:12.185Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:27:18.848Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:27:31.940Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:27:57.925Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:28:49.399Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:29:49.670Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:30:49.947Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:31:50.244Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:32:50.538Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:33:50.823Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
time=2026-02-17T07:34:51.137Z level=ERROR source=main.go:654 msg="Error loading config (--config.file=/etc/prometheus/prometheus.yml)" file=/etc/prometheus/prometheus.yml err="open /etc/prometheus/prometheus.yml: no such file or directory"
⚠ RUNNING (health check timeout)
[WARNING] prometheus is running but health check timed out
  🐳 grafana: 
[INFO] DEBUG: Pulling grafana image...
[INFO] DEBUG: Starting grafana with explicit environment...
[INFO] DEBUG: Waiting for grafana to become healthy...
[INFO] Waiting for grafana to become healthy...
[ERROR] grafana failed to become healthy after 180 attempts
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
⚠ RUNNING (health check timeout)
[WARNING] grafana is running but health check timed out
[INFO] DEBUG: Deploying AI services...
  🐳 ollama: 
[INFO] DEBUG: Pulling ollama image...
[INFO] DEBUG: Starting ollama with explicit environment...
[INFO] DEBUG: Waiting for ollama to become healthy...
[INFO] Waiting for ollama to become healthy...
[ERROR] ollama failed to become healthy after 180 attempts
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
⚠ RUNNING (health check timeout)
[WARNING] ollama is running but health check timed out
  🐳 litellm: 
[INFO] DEBUG: Pulling litellm image...
[INFO] DEBUG: Starting litellm with explicit environment...
FAILED TO START
[ERROR] Failed to start litellm
  🐳 openwebui: 
[INFO] DEBUG: Pulling openwebui image...
[INFO] DEBUG: Starting openwebui with explicit environment...
[INFO] DEBUG: Waiting for openwebui to become healthy...
[INFO] Waiting for openwebui to become healthy...
[ERROR] openwebui failed to become healthy after 180 attempts
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
⚠ RUNNING (health check timeout)
[WARNING] openwebui is running but health check timed out
  🐳 anythingllm: 
[INFO] DEBUG: Pulling anythingllm image...
[INFO] DEBUG: Starting anythingllm with explicit environment...
[INFO] DEBUG: Waiting for anythingllm to become healthy...
[INFO] Waiting for anythingllm to become healthy..
