# AI Platform Automation - Comprehensive Diagnostic Report
# Generated: 2026-03-13 21:07 UTC
# Status: CRITICAL - Multiple service failures preventing deployment

## EXECUTIVE SUMMARY
- Main domain: ai.datasquiz.net (HTTP 000 - Caddy not responding)
- 1/17 services working (Grafana: HTTP 302)
- 16/17 services failing (All showing HTTP 502)
- Core infrastructure (PostgreSQL, Redis) appears healthy
- Authentik Redis authentication fixed but web server not listening
- N8N permissions fixed but still starting up

## CURRENT DEPLOYMENT STATE

### HTTP Status Check (2026-03-13 21:07 UTC)
```
grafana: HTTP 302 ✅ Working
n8n: HTTP 502 ❌
openwebui: HTTP 502 ❌
auth: HTTP 502 ❌
litellm: HTTP 502 ❌
flowise: HTTP 502 ❌
anythingllm: HTTP 502 ❌
```

## CRITICAL ISSUES IDENTIFIED

### 1. AUTHENTIK - BOOTING BUT NOT LISTENING
**Problem**: Authentik boots successfully but web server never starts listening on port 9000

**Port Check Result**:
```
Checking if port 9000 is open...
bash: connect: Connection refused
Port 9000 CLOSED
```

**Environment Variables**:
```
AUTHENTIK_REDIS__DB=0
AUTHENTIK_REDIS__HOST=redis
AUTHENTIK_REDIS__PORT=6379
AUTHENTIK_REDIS__PASSWORD=Ewkxl1FSKz8bt150llxJrDPrUs3Qqnap
AUTHENTIK_POSTGRESQL__HOST=postgres
AUTHENTIK_POSTGRESQL__PORT=5432
AUTHENTIK_POSTGRESQL__NAME=authentik
AUTHENTIK_POSTGRESQL__USER=authentik
AUTHENTIK_POSTGRESQL__PASSWORD=<correct_password>
```

### 2. N8N - PERMISSIONS FIXED BUT STILL STARTING
**Problem**: N8N was failing with EACCES permission errors, now fixed but still initializing

**Recent Logs**:
```
n8n            | 2025-03-13T14:26:18.389Z | info: [initializeDatabase] Initializing n8n database
n8n            | 2025-03-13T14:26:18.393Z | info: [initializeDatabase] Connecting to database with settings: {"type": "postgresdb", "host": "postgres", "port": 5433, "database": "n8n", "user": "ds-admin", "password": "****", "ssl": false, "connectionTimeout": 60000}
```

**Port Configuration Issue**:
```
N8N is configured to use port 5433 for PostgreSQL but PostgreSQL is on 5432
```

## APPENDIX - DETAILED LOGS


### 1. DOCKER CONTAINER STATUS
NAMES                        STATUS                             PORTS
ai-datasquiz-openwebui-1     Up 4 seconds (health: starting)    8080/tcp
ai-datasquiz-openclaw-1      Up 7 hours                         
ai-datasquiz-anythingllm-1   Up 13 seconds (health: starting)   
ai-datasquiz-flowise-1       Up 5 seconds                       
ai-datasquiz-litellm-1       Up 5 seconds                       4000/tcp
ai-datasquiz-authentik-1     Up 54 seconds (health: starting)   
ai-datasquiz-n8n-1           Up 23 seconds                      5678/tcp
ai-datasquiz-ollama-1        Up 7 hours                         0.0.0.0:11434->11434/tcp, [::]:11434->11434/tcp
ai-datasquiz-rclone-1        Up 7 hours                         
ai-datasquiz-tailscale-1     Up 7 hours                         
ai-datasquiz-prometheus-1    Up 7 hours                         9090/tcp
ai-datasquiz-caddy-1         Up 7 hours                         0.0.0.0:80->80/tcp, [::]:80->80/tcp, 0.0.0.0:443->443/tcp, [::]:443->443/tcp, 0.0.0.0:443->443/udp, [::]:443->443/udp, 2019/tcp
ai-datasquiz-redis-1         Up 7 hours (healthy)               6379/tcp
ai-datasquiz-qdrant-1        Up 7 hours                         0.0.0.0:6333->6333/tcp, [::]:6333->6333/tcp, 6334/tcp
ai-datasquiz-signal-1        Up 7 hours (healthy)               0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp
ai-datasquiz-grafana-1       Up 7 hours                         3000/tcp
ai-datasquiz-postgres-1      Up 7 hours (healthy)               5432/tcp


### 2. AUTHENTIK FULL LOGS (last 50 lines)
    ldap_check_connection
    ldap_sync

[pgactivity]
    pgactivity

[pglock]
    pglock

[recovery]
    create_admin_group
    create_recovery_key

[rest_framework]
    generateschema

[scim]
    scim_sync

[sessions]
    clearsessions

[staticfiles]
    collectstatic
    findstatic
    runserver
{"event": "Loaded config", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436530.1344676, "file": "/authentik/lib/default.yml"}
{"event": "Loaded environment variables", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436530.1435227, "count": 10}
{"event": "Starting authentik bootstrap", "level": "info", "logger": "authentik.lib.config", "timestamp": 1773436543.5293949}
{"event": "PostgreSQL connection successful", "level": "info", "logger": "authentik.lib.config", "timestamp": 1773436543.8442845}
{"event": "Redis Connection successful", "level": "info", "logger": "authentik.lib.config", "timestamp": 1773436543.8635316}
{"event": "Finished authentik bootstrap", "level": "info", "logger": "authentik.lib.config", "timestamp": 1773436543.863717}
{"event": "Booting authentik", "level": "info", "logger": "authentik.lib.config", "timestamp": 1773436572.235975, "version": "2025.2.4"}
{"event": "Enabled authentik enterprise", "level": "info", "logger": "authentik.lib.config", "timestamp": 1773436572.2528872}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.2628999, "path": "authentik.enterprise.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.26823, "path": "authentik.sources.oauth.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.2745771, "path": "authentik.stages.authenticator_webauthn.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.288292, "path": "authentik.outposts.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.2939095, "path": "authentik.admin.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.3064332, "path": "authentik.enterprise.providers.microsoft_entra.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.313048, "path": "authentik.enterprise.providers.google_workspace.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.328607, "path": "authentik.stages.authenticator_totp.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.3547142, "path": "authentik.sources.ldap.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.372106, "path": "authentik.sources.kerberos.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.3800602, "path": "authentik.blueprints.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.3901842, "path": "authentik.sources.plex.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.40194, "path": "authentik.providers.scim.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.4032285, "path": "authentik.enterprise.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.4073968, "path": "authentik.events.settings"}
{"event": "Loaded app settings", "level": "debug", "logger": "authentik.lib.config", "timestamp": 1773436572.4346967, "path": "authentik.crypto.settings"}


### 3. N8N FULL LOGS (last 50 lines)
    at CommandRegistry.execute (/usr/local/lib/node_modules/n8n/src/command-registry.ts:82:4)
    at /usr/local/lib/node_modules/n8n/bin/n8n:63:2
EACCES: permission denied, open '/home/node/.n8n/crash.journal'
TypeError: Cannot read properties of undefined (reading 'error')
    at Start.exitWithCrash (/usr/local/lib/node_modules/n8n/src/commands/base-command.ts:205:22)
    at Start.catch (/usr/local/lib/node_modules/n8n/src/commands/start.ts:381:14)
    at CommandRegistry.execute (/usr/local/lib/node_modules/n8n/src/command-registry.ts:86:25)
    at /usr/local/lib/node_modules/n8n/bin/n8n:63:2
Error: EACCES: permission denied, open '/home/node/.n8n/crash.journal'
    at open (node:internal/fs/promises:637:25)
    at touchFile (/usr/local/lib/node_modules/n8n/src/crash-journal.ts:15:14)
    at Object.init (/usr/local/lib/node_modules/n8n/src/crash-journal.ts:32:2)
    at Start.initCrashJournal (/usr/local/lib/node_modules/n8n/src/commands/base-command.ts:193:3)
    at Start.init (/usr/local/lib/node_modules/n8n/src/commands/start.ts:190:3)
    at CommandRegistry.execute (/usr/local/lib/node_modules/n8n/src/command-registry.ts:82:4)
    at /usr/local/lib/node_modules/n8n/bin/n8n:63:2
EACCES: permission denied, open '/home/node/.n8n/crash.journal'
TypeError: Cannot read properties of undefined (reading 'error')
    at Start.exitWithCrash (/usr/local/lib/node_modules/n8n/src/commands/base-command.ts:205:22)
    at Start.catch (/usr/local/lib/node_modules/n8n/src/commands/start.ts:381:14)
    at CommandRegistry.execute (/usr/local/lib/node_modules/n8n/src/command-registry.ts:86:25)
    at /usr/local/lib/node_modules/n8n/bin/n8n:63:2
Error: EACCES: permission denied, open '/home/node/.n8n/crash.journal'
    at open (node:internal/fs/promises:637:25)
    at touchFile (/usr/local/lib/node_modules/n8n/src/crash-journal.ts:15:14)
    at Object.init (/usr/local/lib/node_modules/n8n/src/crash-journal.ts:32:2)
    at Start.initCrashJournal (/usr/local/lib/node_modules/n8n/src/commands/base-command.ts:193:3)
    at Start.init (/usr/local/lib/node_modules/n8n/src/commands/start.ts:190:3)
    at CommandRegistry.execute (/usr/local/lib/node_modules/n8n/src/command-registry.ts:82:4)
    at /usr/local/lib/node_modules/n8n/bin/n8n:63:2
EACCES: permission denied, open '/home/node/.n8n/crash.journal'
TypeError: Cannot read properties of undefined (reading 'error')
    at Start.exitWithCrash (/usr/local/lib/node_modules/n8n/src/commands/base-command.ts:205:22)
    at Start.catch (/usr/local/lib/node_modules/n8n/src/commands/start.ts:381:14)
    at CommandRegistry.execute (/usr/local/lib/node_modules/n8n/src/command-registry.ts:86:25)
    at /usr/local/lib/node_modules/n8n/bin/n8n:63:2
Error: EACCES: permission denied, open '/home/node/.n8n/crash.journal'
    at open (node:internal/fs/promises:637:25)
    at touchFile (/usr/local/lib/node_modules/n8n/src/crash-journal.ts:15:14)
    at Object.init (/usr/local/lib/node_modules/n8n/src/crash-journal.ts:32:2)
    at Start.initCrashJournal (/usr/local/lib/node_modules/n8n/src/commands/base-command.ts:193:3)
    at Start.init (/usr/local/lib/node_modules/n8n/src/commands/start.ts:190:3)
    at CommandRegistry.execute (/usr/local/lib/node_modules/n8n/src/command-registry.ts:82:4)
    at /usr/local/lib/node_modules/n8n/bin/n8n:63:2
EACCES: permission denied, open '/home/node/.n8n/crash.journal'
TypeError: Cannot read properties of undefined (reading 'error')
    at Start.exitWithCrash (/usr/local/lib/node_modules/n8n/src/commands/base-command.ts:205:22)
    at Start.catch (/usr/local/lib/node_modules/n8n/src/commands/start.ts:381:14)
    at CommandRegistry.execute (/usr/local/lib/node_modules/n8n/src/command-registry.ts:86:25)
    at /usr/local/lib/node_modules/n8n/bin/n8n:63:2


### 4. CADDY LOGS (last 50 lines)
{"level":"error","ts":1773428740.0871718,"logger":"http.log.error","msg":"dial tcp 172.18.0.14:4000: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"33524","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"litellm.ai.datasquiz.net","uri":"/.env.production","headers":{"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.100 Safari/537.36 OPR/62.0.3331.99"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"],"Connection":["close"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"litellm.ai.datasquiz.net","ech":false}},"duration":0.001340052,"status":502,"err_id":"fsxk8w66x","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773428740.1003654,"logger":"http.log.error","msg":"dial tcp 172.18.0.14:4000: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"33532","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"litellm.ai.datasquiz.net","uri":"/.env.bak","headers":{"User-Agent":["Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.0.1 Safari/605.1.15"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"],"Connection":["close"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"litellm.ai.datasquiz.net","ech":false}},"duration":0.00128196,"status":502,"err_id":"3k4tswefx","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773428740.106308,"logger":"http.log.error","msg":"dial tcp 172.18.0.14:4000: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"33538","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"litellm.ai.datasquiz.net","uri":"/.env.prod","headers":{"User-Agent":["Mozilla/5.0 (Linux; Android 9; VOG-L29) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/76.0.3809.111 Mobile Safari/537.36"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"],"Connection":["close"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"litellm.ai.datasquiz.net","ech":false}},"duration":0.001220132,"status":502,"err_id":"wmt1xnmw0","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773428740.119324,"logger":"http.log.error","msg":"dial tcp 172.18.0.14:4000: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"33546","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"litellm.ai.datasquiz.net","uri":"/crm/.env","headers":{"User-Agent":["Mozilla/5.0 (iPad; CPU OS 11_0 like Mac OS X) AppleWebKit/604.1.38 (KHTML, like Gecko) Version/11.0 Mobile/15A5362a Safari/604.1"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"],"Connection":["close"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"litellm.ai.datasquiz.net","ech":false}},"duration":0.001215619,"status":502,"err_id":"9r4rgh9bv","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773428740.1559153,"logger":"http.log.error","msg":"dial tcp 172.18.0.14:4000: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"33558","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"litellm.ai.datasquiz.net","uri":"/wp-config","headers":{"User-Agent":["Mozilla/5.0 (X11; FreeBSD amd64) AppleWebKit/537.4 (KHTML like Gecko) Chrome/22.0.1229.79 Safari/537.4"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"],"Connection":["close"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"litellm.ai.datasquiz.net","ech":false}},"duration":0.003144542,"status":502,"err_id":"kcg70w7m7","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773428740.1654403,"logger":"http.log.error","msg":"dial tcp 172.18.0.14:4000: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"33562","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"litellm.ai.datasquiz.net","uri":"/config.env","headers":{"Connection":["close"],"User-Agent":["Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/52.0.2743.116 Safari/537.36"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"litellm.ai.datasquiz.net","ech":false}},"duration":0.007335674,"status":502,"err_id":"n9ic74me5","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773428740.1740992,"logger":"http.log.error","msg":"dial tcp 172.18.0.14:4000: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"33576","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"litellm.ai.datasquiz.net","uri":"/awstats/.env","headers":{"Connection":["close"],"User-Agent":["Mozilla/5.0 (X11; U; Linux armv7l like Android; en-us) AppleWebKit/531.2+ (KHTML, like Gecko) Version/5.0 Safari/533.2+ Kindle/3.0+"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"litellm.ai.datasquiz.net","ech":false}},"duration":0.009179958,"status":502,"err_id":"wiy24tmay","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773428740.1771436,"logger":"http.log.error","msg":"dial tcp 172.18.0.14:4000: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"33588","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"litellm.ai.datasquiz.net","uri":"/awsconfig.js","headers":{"Accept-Encoding":["gzip"],"Connection":["close"],"User-Agent":["Mozilla/5.0 (Linux; Android 9; CLT-L29) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/76.0.3809.111 Mobile Safari/537.36"],"Accept-Charset":["utf-8"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"litellm.ai.datasquiz.net","ech":false}},"duration":0.006069118,"status":502,"err_id":"n7wenj051","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773429288.354693,"logger":"http.log.error","msg":"dial tcp 172.18.0.18:5678: connect: connection refused","request":{"remote_ip":"185.242.177.51","remote_port":"54582","client_ip":"185.242.177.51","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/","headers":{"Accept":["*/*"],"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:147.0) Gecko/20100101 Firefox/147.0"],"Accept-Encoding":["gzip, compress, deflate, br"],"Connection":["keep-alive"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.001518082,"status":502,"err_id":"jectwjirb","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773429289.864663,"logger":"http.log.error","msg":"dial tcp 172.18.0.18:5678: connect: connection refused","request":{"remote_ip":"185.242.177.53","remote_port":"54634","client_ip":"185.242.177.53","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/","headers":{"Connection":["close"],"Accept":["*/*"],"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:147.0) Gecko/20100101 Firefox/147.0"],"Accept-Encoding":["gzip, compress, deflate, br"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.001136401,"status":502,"err_id":"5jzwqwaip","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773429376.225893,"logger":"http.log.error","msg":"dial tcp 172.18.0.17:9000: connect: connection refused","request":{"remote_ip":"34.124.224.42","remote_port":"39682","client_ip":"34.124.224.42","proto":"HTTP/1.1","method":"GET","host":"auth.ai.datasquiz.net","uri":"/","headers":{"Accept":["*/*"],"Connection":["keep-alive"],"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0 Safari/537.36"],"Accept-Encoding":["gzip, deflate"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"auth.ai.datasquiz.net","ech":false}},"duration":0.001373151,"status":502,"err_id":"098s1kxh1","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773430212.0401661,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"185.242.177.19","remote_port":"39068","client_ip":"185.242.177.19","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/","headers":{"Connection":["keep-alive"],"User-Agent":["python-requests/2.32.5"],"Accept-Encoding":["gzip, deflate"],"Accept":["*/*"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.001131271,"status":502,"err_id":"705pijn5n","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773430212.1077378,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"185.242.177.19","remote_port":"59672","client_ip":"185.242.177.19","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/","headers":{"Accept-Encoding":["gzip, deflate"],"Accept":["*/*"],"Connection":["keep-alive"],"User-Agent":["python-requests/2.32.5"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.001023306,"status":502,"err_id":"i0wdmm0zp","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773430710.46633,"logger":"http.log.error","msg":"dial tcp 172.18.0.17:3001: connect: connection refused","request":{"remote_ip":"143.198.232.249","remote_port":"47772","client_ip":"143.198.232.249","proto":"HTTP/1.1","method":"GET","host":"anythingllm.ai.datasquiz.net","uri":"/","headers":{"Sec-Ch-Ua-Platform":["\"Linux\""],"Sec-Fetch-Mode":["navigate"],"Sec-Fetch-User":["?1"],"Sec-Ch-Ua-Mobile":["?0"],"Upgrade-Insecure-Requests":["1"],"User-Agent":["Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"],"Sec-Gpc":["1"],"Accept-Language":["en-US,en;q=0.5"],"Sec-Ch-Ua":["\"Chromium\";v=\"142\", \"Not:A-Brand\";v=\"24\", \"Brave\";v=\"142\""],"Accept":["text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8"],"Sec-Fetch-Site":["none"],"Sec-Fetch-Dest":["document"],"Accept-Encoding":["gzip, deflate"],"Connection":["keep-alive"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"anythingllm.ai.datasquiz.net","ech":false}},"duration":0.001306312,"status":502,"err_id":"yjvquxgz8","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773430714.1723487,"logger":"http.log.error","msg":"dial tcp 172.18.0.17:3001: connect: connection refused","request":{"remote_ip":"143.198.232.249","remote_port":"47878","client_ip":"143.198.232.249","proto":"HTTP/1.1","method":"GET","host":"anythingllm.ai.datasquiz.net","uri":"/favicon.ico","headers":{"Accept":["text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8"],"Accept-Encoding":["gzip, deflate"],"Sec-Ch-Ua":["\"Chromium\";v=\"142\", \"Not:A-Brand\";v=\"24\", \"Brave\";v=\"142\""],"Accept-Language":["en-US,en;q=0.5"],"Sec-Fetch-Site":["none"],"Sec-Fetch-Mode":["navigate"],"Sec-Fetch-Dest":["document"],"Sec-Ch-Ua-Mobile":["?0"],"Connection":["keep-alive"],"Referer":["https://anythingllm.ai.datasquiz.net/"],"Sec-Gpc":["1"],"Sec-Fetch-User":["?1"],"Sec-Ch-Ua-Platform":["\"Linux\""],"User-Agent":["Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"],"Upgrade-Insecure-Requests":["1"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"anythingllm.ai.datasquiz.net","ech":false}},"duration":0.014776688,"status":502,"err_id":"kcep4tbuv","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773430751.1244164,"logger":"http.log.error","msg":"dial tcp: lookup flowise on 127.0.0.11:53: server misbehaving","request":{"remote_ip":"34.124.224.42","remote_port":"38042","client_ip":"34.124.224.42","proto":"HTTP/1.1","method":"GET","host":"flowise.ai.datasquiz.net","uri":"/","headers":{"Accept-Encoding":["gzip, deflate"],"Accept":["*/*"],"Connection":["keep-alive"],"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0 Safari/537.36"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"flowise.ai.datasquiz.net","ech":false}},"duration":0.006349505,"status":502,"err_id":"0jnf0p9fg","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773431185.030593,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"34.124.224.42","remote_port":"59312","client_ip":"34.124.224.42","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/","headers":{"Connection":["keep-alive"],"User-Agent":["Mozilla/5.0 (Linux; Android 12) Chrome/111.0 Mobile Safari/537.36"],"Accept-Encoding":["gzip, deflate"],"Accept":["*/*"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.009052805,"status":502,"err_id":"ei7rw1wf4","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773431705.479429,"logger":"http.log.error","msg":"dial tcp: lookup dify on 127.0.0.11:53: server misbehaving","request":{"remote_ip":"35.187.233.145","remote_port":"50698","client_ip":"35.187.233.145","proto":"HTTP/1.1","method":"GET","host":"dify.ai.datasquiz.net","uri":"/","headers":{"Accept-Encoding":["gzip, deflate"],"Accept":["*/*"],"Connection":["keep-alive"],"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0 Safari/537.36"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"dify.ai.datasquiz.net","ech":false}},"duration":0.023775214,"status":502,"err_id":"b5x0w86h7","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432006.7602036,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"38734","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/aws.env","headers":{"Connection":["close"],"User-Agent":["Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3068.0 Safari/537.36"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.003990648,"status":502,"err_id":"45t4jymnh","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432006.7661426,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"38726","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/.aws/credentials","headers":{"Connection":["close"],"User-Agent":["Mozilla/5.0 (Linux; Android 7.0; Lenovo K33a42) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.101 Mobile Safari/537.36"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.010784456,"status":502,"err_id":"3fhjfyixw","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432006.77197,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"38768","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/.env","headers":{"User-Agent":["Mozilla/5.0 (Linux; Android 9; SAMSUNG SM-N950F Build/PPR1.180610.011) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/9.4 Chrome/67.0.3396.87 Mobile Safari/537.36"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"],"Connection":["close"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.004960194,"status":502,"err_id":"1x8ip50py","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432006.772723,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"38740","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/wp-config","headers":{"Connection":["close"],"User-Agent":["Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3683.103 Safari/537.36 OPR/60.0.3255.109"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.010331747,"status":502,"err_id":"f3r4299x7","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432006.7739604,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"38762","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/.env.live","headers":{"Accept-Encoding":["gzip"],"Connection":["close"],"User-Agent":["Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.92 Safari/537.36"],"Accept-Charset":["utf-8"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.002949044,"status":502,"err_id":"r6s8cdxjd","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432006.7740288,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"38752","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/.env.prod","headers":{"Accept-Encoding":["gzip"],"Connection":["close"],"User-Agent":["Mozilla/5.0 (Linux; Android 9; ONEPLUS A5010) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/76.0.3809.89 Mobile Safari/537.36"],"Accept-Charset":["utf-8"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.000834009,"status":502,"err_id":"u1vv702ce","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432006.774093,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"38782","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/config.env","headers":{"Accept-Encoding":["gzip"],"Connection":["close"],"User-Agent":["Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/11.1.2 Safari/605.1.15"],"Accept-Charset":["utf-8"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.001239897,"status":502,"err_id":"vfqr1sffs","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432006.7815442,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"38796","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/.env.bak","headers":{"Connection":["close"],"User-Agent":["Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.142 Safari/537.36"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.001014951,"status":502,"err_id":"xc0phdpws","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432006.7820015,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"38804","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/crm/.env","headers":{"Connection":["close"],"User-Agent":["Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/76.0.3809.87 Safari/537.36"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.000529559,"status":502,"err_id":"u4riggv4w","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432006.799767,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"38812","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/awstats/.env","headers":{"Accept-Encoding":["gzip"],"Connection":["close"],"User-Agent":["SonyEricssonW810i/R4EA Browser/NetFront/3.3 Profile/MIDP-2.0 Configuration/CLDC-1.1 UP.Link/6.3.0.0.0"],"Accept-Charset":["utf-8"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.001240598,"status":502,"err_id":"9zyjztski","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432006.8105736,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"38826","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/.env.production","headers":{"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.146 Safari/537.36"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"],"Connection":["close"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.001471937,"status":502,"err_id":"ickev0dkg","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432006.8306923,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:5678: connect: connection refused","request":{"remote_ip":"45.148.10.238","remote_port":"38842","client_ip":"45.148.10.238","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/awsconfig.js","headers":{"User-Agent":["Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.142 Safari/537.36"],"Accept-Charset":["utf-8"],"Accept-Encoding":["gzip"],"Connection":["close"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.001414229,"status":502,"err_id":"jpyp663f0","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432254.1288235,"logger":"http.log.error","msg":"dial tcp: lookup flowise on 127.0.0.11:53: server misbehaving","request":{"remote_ip":"147.182.171.41","remote_port":"46308","client_ip":"147.182.171.41","proto":"HTTP/1.1","method":"GET","host":"flowise.ai.datasquiz.net","uri":"/","headers":{"Sec-Fetch-User":["?1"],"User-Agent":["Mozilla/5.0 (X11; Linux x86_64; rv:142.0) Gecko/20100101 Firefox/142.0"],"Accept":["text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"],"Sec-Fetch-Mode":["navigate"],"Connection":["keep-alive"],"Upgrade-Insecure-Requests":["1"],"Sec-Fetch-Dest":["document"],"Priority":["u=0, i"],"Accept-Language":["en-US,en;q=0.5"],"Accept-Encoding":["gzip, deflate"],"Sec-Fetch-Site":["none"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"flowise.ai.datasquiz.net","ech":false}},"duration":0.018061245,"status":502,"err_id":"vw5jdkjnt","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432260.0287697,"logger":"http.log.error","msg":"dial tcp: lookup flowise on 127.0.0.11:53: server misbehaving","request":{"remote_ip":"147.182.171.41","remote_port":"46420","client_ip":"147.182.171.41","proto":"HTTP/1.1","method":"GET","host":"flowise.ai.datasquiz.net","uri":"/favicon.ico","headers":{"Accept":["text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"],"Connection":["keep-alive"],"Sec-Fetch-Dest":["document"],"User-Agent":["Mozilla/5.0 (X11; Linux x86_64; rv:142.0) Gecko/20100101 Firefox/142.0"],"Sec-Fetch-Site":["none"],"Accept-Encoding":["gzip, deflate"],"Upgrade-Insecure-Requests":["1"],"Sec-Fetch-User":["?1"],"Priority":["u=0, i"],"Accept-Language":["en-US,en;q=0.5"],"Sec-Fetch-Mode":["navigate"],"Referer":["https://flowise.ai.datasquiz.net/"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"","server_name":"flowise.ai.datasquiz.net","ech":false}},"duration":0.00488005,"status":502,"err_id":"bnzyydas5","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432285.7231207,"logger":"http.log.error","msg":"dial tcp 172.18.0.17:3001: connect: connection refused","request":{"remote_ip":"74.7.241.178","remote_port":"41030","client_ip":"74.7.241.178","proto":"HTTP/2.0","method":"GET","host":"anythingllm.ai.datasquiz.net","uri":"/robots.txt","headers":{"Accept":["*/*"],"From":["oai-searchbot(at)openai.com"],"User-Agent":["Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36; compatible; OAI-SearchBot/1.3; robots.txt; +https://openai.com/searchbot"],"Accept-Encoding":["gzip, br, deflate"],"X-Openai-Host-Hash":["886348265"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"h2","server_name":"anythingllm.ai.datasquiz.net","ech":false}},"duration":0.008554162,"status":502,"err_id":"6fyd54hnv","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432286.0600908,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:9000: connect: connection refused","request":{"remote_ip":"74.7.241.155","remote_port":"38952","client_ip":"74.7.241.155","proto":"HTTP/2.0","method":"GET","host":"auth.ai.datasquiz.net","uri":"/robots.txt","headers":{"X-Openai-Host-Hash":["925000245"],"Accept":["*/*"],"From":["oai-searchbot(at)openai.com"],"User-Agent":["Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36; compatible; OAI-SearchBot/1.3; robots.txt; +https://openai.com/searchbot"],"Accept-Encoding":["gzip, br, deflate"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"h2","server_name":"auth.ai.datasquiz.net","ech":false}},"duration":0.001311125,"status":502,"err_id":"ng79v8nx7","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432321.734761,"logger":"http.log.error","msg":"dial tcp 172.18.0.18:3000: connect: connection refused","request":{"remote_ip":"74.7.241.186","remote_port":"41088","client_ip":"74.7.241.186","proto":"HTTP/2.0","method":"GET","host":"flowise.ai.datasquiz.net","uri":"/robots.txt","headers":{"From":["oai-searchbot(at)openai.com"],"User-Agent":["Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36; compatible; OAI-SearchBot/1.3; robots.txt; +https://openai.com/searchbot"],"Accept-Encoding":["gzip, br, deflate"],"X-Openai-Host-Hash":["114826740"],"Accept":["*/*"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"h2","server_name":"flowise.ai.datasquiz.net","ech":false}},"duration":0.004358208,"status":502,"err_id":"v1avri2p9","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432351.5398133,"logger":"http.log.error","msg":"dial tcp 172.18.0.14:4000: connect: connection refused","request":{"remote_ip":"74.7.228.46","remote_port":"41890","client_ip":"74.7.228.46","proto":"HTTP/2.0","method":"GET","host":"litellm.ai.datasquiz.net","uri":"/robots.txt","headers":{"User-Agent":["Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36; compatible; OAI-SearchBot/1.3; robots.txt; +https://openai.com/searchbot"],"Accept-Encoding":["gzip, br, deflate"],"X-Openai-Host-Hash":["376706454"],"Accept":["*/*"],"From":["oai-searchbot(at)openai.com"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"h2","server_name":"litellm.ai.datasquiz.net","ech":false}},"duration":0.00456175,"status":502,"err_id":"gd76i6krm","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432385.7587366,"logger":"http.log.error","msg":"dial tcp 172.18.0.13:5678: connect: connection refused","request":{"remote_ip":"74.7.230.13","remote_port":"55646","client_ip":"74.7.230.13","proto":"HTTP/2.0","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/robots.txt","headers":{"X-Openai-Host-Hash":["46533229"],"Accept":["*/*"],"From":["oai-searchbot(at)openai.com"],"User-Agent":["Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36; compatible; OAI-SearchBot/1.3; robots.txt; +https://openai.com/searchbot"],"Accept-Encoding":["gzip, br, deflate"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"h2","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.004087826,"status":502,"err_id":"jzyyt54pq","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432385.8769975,"logger":"http.log.error","msg":"dial tcp 172.18.0.17:8081: connect: connection refused","request":{"remote_ip":"74.7.175.133","remote_port":"48422","client_ip":"74.7.175.133","proto":"HTTP/2.0","method":"GET","host":"openwebui.ai.datasquiz.net","uri":"/robots.txt","headers":{"Accept":["*/*"],"From":["oai-searchbot(at)openai.com"],"User-Agent":["Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36; compatible; OAI-SearchBot/1.3; robots.txt; +https://openai.com/searchbot"],"Accept-Encoding":["gzip, br, deflate"],"X-Openai-Host-Hash":["848725342"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"h2","server_name":"openwebui.ai.datasquiz.net","ech":false}},"duration":0.002179227,"status":502,"err_id":"ggdfvxiwr","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432488.8321278,"logger":"http.log.error","msg":"dial tcp: lookup dify on 127.0.0.11:53: server misbehaving","request":{"remote_ip":"34.124.224.42","remote_port":"54392","client_ip":"34.124.224.42","proto":"HTTP/1.1","method":"GET","host":"dify.ai.datasquiz.net","uri":"/","headers":{"User-Agent":["Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"],"Accept-Encoding":["gzip, deflate"],"Accept":["*/*"],"Connection":["keep-alive"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"dify.ai.datasquiz.net","ech":false}},"duration":0.013509459,"status":502,"err_id":"7fy7r6thw","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432712.6494384,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:9000: connect: connection refused","request":{"remote_ip":"45.92.86.113","remote_port":"43297","client_ip":"45.92.86.113","proto":"HTTP/1.1","method":"GET","host":"auth.ai.datasquiz.net","uri":"/","headers":{"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.61 Safari/537.36"],"Accept":["*/*"],"Accept-Encoding":["gzip, deflate"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"auth.ai.datasquiz.net","ech":false}},"duration":0.001312962,"status":502,"err_id":"xhrp5ujcf","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432713.9119618,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:9000: connect: connection refused","request":{"remote_ip":"155.94.203.9","remote_port":"41847","client_ip":"155.94.203.9","proto":"HTTP/1.1","method":"GET","host":"auth.ai.datasquiz.net","uri":"/","headers":{"Accept-Encoding":["gzip, deflate"],"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.61 Safari/537.36"],"Accept":["*/*"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"auth.ai.datasquiz.net","ech":false}},"duration":0.001242298,"status":502,"err_id":"f5cuj336z","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773432714.3297014,"logger":"http.log.error","msg":"dial tcp 172.18.0.15:9000: connect: connection refused","request":{"remote_ip":"155.94.203.9","remote_port":"41847","client_ip":"155.94.203.9","proto":"HTTP/1.1","method":"GET","host":"auth.ai.datasquiz.net","uri":"/","headers":{"Accept":["*/*"],"Accept-Encoding":["gzip, deflate"],"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.61 Safari/537.36"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"auth.ai.datasquiz.net","ech":false}},"duration":0.000779098,"status":502,"err_id":"iumd85knz","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773433287.5973368,"logger":"http.log.error","msg":"dial tcp 172.18.0.17:8081: connect: connection refused","request":{"remote_ip":"34.124.224.42","remote_port":"49704","client_ip":"34.124.224.42","proto":"HTTP/1.1","method":"GET","host":"openwebui.ai.datasquiz.net","uri":"/","headers":{"User-Agent":["Mozilla/5.0 (X11; Linux x86_64) Firefox/117.0"],"Accept-Encoding":["gzip, deflate"],"Accept":["*/*"],"Connection":["keep-alive"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"openwebui.ai.datasquiz.net","ech":false}},"duration":0.001258012,"status":502,"err_id":"9n7vxn1wu","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773433400.569205,"logger":"http.log.error","msg":"dial tcp: lookup dify on 127.0.0.11:53: server misbehaving","request":{"remote_ip":"45.92.87.180","remote_port":"39111","client_ip":"45.92.87.180","proto":"HTTP/1.1","method":"GET","host":"dify.ai.datasquiz.net","uri":"/","headers":{"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.61 Safari/537.36"],"Accept":["*/*"],"Accept-Encoding":["gzip, deflate"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"dify.ai.datasquiz.net","ech":false}},"duration":0.00729755,"status":502,"err_id":"3t0z921k6","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773433402.5131345,"logger":"http.log.error","msg":"dial tcp: lookup dify on 127.0.0.11:53: server misbehaving","request":{"remote_ip":"45.92.86.181","remote_port":"33817","client_ip":"45.92.86.181","proto":"HTTP/1.1","method":"GET","host":"dify.ai.datasquiz.net","uri":"/","headers":{"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.61 Safari/537.36"],"Accept":["*/*"],"Accept-Encoding":["gzip, deflate"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"dify.ai.datasquiz.net","ech":false}},"duration":0.00427221,"status":502,"err_id":"6btg9ethg","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773434093.824015,"logger":"http.log.error","msg":"dial tcp 172.18.0.13:4000: connect: connection refused","request":{"remote_ip":"45.92.86.185","remote_port":"45273","client_ip":"45.92.86.185","proto":"HTTP/1.1","method":"GET","host":"litellm.ai.datasquiz.net","uri":"/","headers":{"Accept-Encoding":["gzip, deflate"],"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.61 Safari/537.36"],"Accept":["*/*"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"litellm.ai.datasquiz.net","ech":false}},"duration":0.004843124,"status":502,"err_id":"a8ft8xm3s","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773434410.1453383,"logger":"http.log.error","msg":"dial tcp 172.18.0.17:5678: connect: connection refused","request":{"remote_ip":"45.92.86.33","remote_port":"32961","client_ip":"45.92.86.33","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/","headers":{"Accept-Encoding":["gzip, deflate"],"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.61 Safari/537.36"],"Accept":["*/*"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.001338498,"status":502,"err_id":"0ni0jpwp0","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773436000.852574,"logger":"http.log.error","msg":"dial tcp 172.18.0.14:9000: connect: connection refused","request":{"remote_ip":"54.252.80.129","remote_port":"39050","client_ip":"54.252.80.129","proto":"HTTP/2.0","method":"GET","host":"auth.ai.datasquiz.net","uri":"/","headers":{"Accept":["*/*"],"User-Agent":["curl/8.5.0"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"h2","server_name":"auth.ai.datasquiz.net","ech":false}},"duration":0.016327138,"status":502,"err_id":"8vp3ej0ks","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773436037.1621473,"logger":"http.log.error","msg":"dial tcp 172.18.0.12:5678: connect: connection refused","request":{"remote_ip":"46.193.162.90","remote_port":"58756","client_ip":"46.193.162.90","proto":"HTTP/1.1","method":"GET","host":"n8n.ai.datasquiz.net","uri":"/.env","headers":{"Accept":["*/*"],"Accept-Encoding":["gzip, deflate, zstd"],"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"n8n.ai.datasquiz.net","ech":false}},"duration":0.003386259,"status":502,"err_id":"n4bnna5ez","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}
{"level":"error","ts":1773436124.7140388,"logger":"http.log.error","msg":"dial tcp 172.18.0.18:3000: connect: connection refused","request":{"remote_ip":"46.193.162.90","remote_port":"60317","client_ip":"46.193.162.90","proto":"HTTP/1.1","method":"GET","host":"flowise.ai.datasquiz.net","uri":"/.env","headers":{"User-Agent":["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"],"Accept":["*/*"],"Accept-Encoding":["gzip, deflate, zstd"]},"tls":{"resumed":false,"version":772,"cipher_suite":4865,"proto":"http/1.1","server_name":"flowise.ai.datasquiz.net","ech":false}},"duration":0.00509398,"status":502,"err_id":"8zc66ttus","err_trace":"reverseproxy.statusError (reverseproxy.go:1525)"}


### 5. POSTGRESQL LOGS (last 30 lines)
2026-03-13 19:26:53.754 UTC [7447] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 19:43:53.668 UTC [7856] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 19:45:05.305 UTC [7882] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 19:46:15.249 UTC [7916] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 19:50:30.541 UTC [8015] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 19:51:18.451 UTC [8035] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 19:51:42.115 UTC [8039] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 19:52:26.360 UTC [8060] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 19:54:24.291 UTC [8108] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:02:09.993 UTC [8291] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:08:19.123 UTC [8433] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:09:07.058 UTC [8456] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:13:30.771 UTC [8567] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:14:40.102 UTC [8594] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:17:42.270 UTC [8666] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:19:16.606 UTC [8704] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:20:03.925 UTC [8726] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:22:00.042 UTC [8775] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:24:44.565 UTC [8835] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:29:41.449 UTC [8954] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:32:06.803 UTC [9013] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:32:29.763 UTC [9017] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:36:26.526 UTC [9113] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:39:36.618 UTC [9194] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 20:58:26.470 UTC [9641] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 21:05:29.090 UTC [9801] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 21:07:50.548 UTC [9854] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 21:09:42.105 UTC [9898] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 21:10:42.114 UTC [9921] LOG:  could not receive data from client: Connection reset by peer
2026-03-13 21:12:31.920 UTC [9959] LOG:  could not receive data from client: Connection reset by peer


### 6. REDIS LOGS (last 30 lines)
1:M 13 Mar 2026 21:15:28.808 . 0 clients connected (0 replicas), 1047496 bytes in use
1:M 13 Mar 2026 21:15:31.022 - Accepted 127.0.0.1:45842
1:M 13 Mar 2026 21:15:31.026 - Client closed connection id=5711 addr=127.0.0.1:45842 laddr=127.0.0.1:6379 fd=10 name= age=0 idle=0 flags=N db=0 sub=0 psub=0 ssub=0 multi=-1 watch=0 qbuf=0 qbuf-free=20474 argv-mem=0 multi-mem=0 rbs=16384 rbp=7 obl=0 oll=0 omem=0 tot-mem=37760 events=r cmd=ping user=default redir=-1 resp=2 lib-name= lib-ver=
1:M 13 Mar 2026 21:15:34.115 . 0 clients connected (0 replicas), 1047496 bytes in use
1:M 13 Mar 2026 21:15:36.321 - Accepted 127.0.0.1:45848
1:M 13 Mar 2026 21:15:36.323 - Client closed connection id=5712 addr=127.0.0.1:45848 laddr=127.0.0.1:6379 fd=10 name= age=0 idle=0 flags=N db=0 sub=0 psub=0 ssub=0 multi=-1 watch=0 qbuf=0 qbuf-free=20474 argv-mem=0 multi-mem=0 rbs=16384 rbp=16384 obl=0 oll=0 omem=0 tot-mem=37760 events=r cmd=ping user=default redir=-1 resp=2 lib-name= lib-ver=
1:M 13 Mar 2026 21:15:39.528 . 0 clients connected (0 replicas), 1047496 bytes in use
1:M 13 Mar 2026 21:15:42.382 - Accepted 127.0.0.1:55508
1:M 13 Mar 2026 21:15:42.386 - Client closed connection id=5713 addr=127.0.0.1:55508 laddr=127.0.0.1:6379 fd=10 name= age=0 idle=0 flags=N db=0 sub=0 psub=0 ssub=0 multi=-1 watch=0 qbuf=0 qbuf-free=20474 argv-mem=0 multi-mem=0 rbs=16384 rbp=16384 obl=0 oll=0 omem=0 tot-mem=37760 events=r cmd=ping user=default redir=-1 resp=2 lib-name= lib-ver=
1:M 13 Mar 2026 21:15:43.858 - Accepted 172.18.0.14:54074
1:M 13 Mar 2026 21:15:43.865 - Client closed connection id=5714 addr=172.18.0.14:54074 laddr=172.18.0.9:6379 fd=10 name= age=0 idle=0 flags=N db=0 sub=0 psub=0 ssub=0 multi=-1 watch=0 qbuf=0 qbuf-free=20474 argv-mem=0 multi-mem=0 rbs=16384 rbp=16384 obl=0 oll=0 omem=0 tot-mem=37760 events=r cmd=ping user=default redir=-1 resp=2 lib-name=redis-py lib-ver=5.0.7
1:M 13 Mar 2026 21:15:44.777 . 0 clients connected (0 replicas), 1047496 bytes in use
1:M 13 Mar 2026 21:15:47.696 - Accepted 127.0.0.1:55516
1:M 13 Mar 2026 21:15:47.699 - Client closed connection id=5715 addr=127.0.0.1:55516 laddr=127.0.0.1:6379 fd=10 name= age=0 idle=0 flags=N db=0 sub=0 psub=0 ssub=0 multi=-1 watch=0 qbuf=0 qbuf-free=20474 argv-mem=0 multi-mem=0 rbs=16384 rbp=7 obl=0 oll=0 omem=0 tot-mem=37760 events=r cmd=ping user=default redir=-1 resp=2 lib-name= lib-ver=
1:M 13 Mar 2026 21:15:50.153 . 0 clients connected (0 replicas), 1047496 bytes in use
1:M 13 Mar 2026 21:15:53.241 - Accepted 127.0.0.1:53324
1:M 13 Mar 2026 21:15:53.248 - Client closed connection id=5716 addr=127.0.0.1:53324 laddr=127.0.0.1:6379 fd=10 name= age=0 idle=0 flags=N db=0 sub=0 psub=0 ssub=0 multi=-1 watch=0 qbuf=0 qbuf-free=20474 argv-mem=0 multi-mem=0 rbs=16384 rbp=16384 obl=0 oll=0 omem=0 tot-mem=37760 events=r cmd=ping user=default redir=-1 resp=2 lib-name= lib-ver=
1:M 13 Mar 2026 21:15:55.466 . 0 clients connected (0 replicas), 1047496 bytes in use
1:M 13 Mar 2026 21:15:59.494 - Accepted 127.0.0.1:53336
1:M 13 Mar 2026 21:15:59.494 - Client closed connection id=5717 addr=127.0.0.1:53336 laddr=127.0.0.1:6379 fd=10 name= age=0 idle=0 flags=N db=0 sub=0 psub=0 ssub=0 multi=-1 watch=0 qbuf=0 qbuf-free=20474 argv-mem=0 multi-mem=0 rbs=16384 rbp=16384 obl=0 oll=0 omem=0 tot-mem=37760 events=r cmd=ping user=default redir=-1 resp=2 lib-name= lib-ver=
1:M 13 Mar 2026 21:16:01.014 . 0 clients connected (0 replicas), 1047496 bytes in use
1:M 13 Mar 2026 21:16:04.754 - Accepted 127.0.0.1:50836
1:M 13 Mar 2026 21:16:04.757 - Client closed connection id=5718 addr=127.0.0.1:50836 laddr=127.0.0.1:6379 fd=10 name= age=0 idle=0 flags=N db=0 sub=0 psub=0 ssub=0 multi=-1 watch=0 qbuf=0 qbuf-free=20474 argv-mem=0 multi-mem=0 rbs=16384 rbp=16384 obl=0 oll=0 omem=0 tot-mem=37760 events=r cmd=ping user=default redir=-1 resp=2 lib-name= lib-ver=
1:M 13 Mar 2026 21:16:06.207 . 0 clients connected (0 replicas), 1047496 bytes in use
1:M 13 Mar 2026 21:16:09.960 - Accepted 127.0.0.1:41258
1:M 13 Mar 2026 21:16:09.961 - Client closed connection id=5719 addr=127.0.0.1:41258 laddr=127.0.0.1:6379 fd=10 name= age=0 idle=0 flags=N db=0 sub=0 psub=0 ssub=0 multi=-1 watch=0 qbuf=0 qbuf-free=20474 argv-mem=0 multi-mem=0 rbs=16384 rbp=16384 obl=0 oll=0 omem=0 tot-mem=37760 events=r cmd=ping user=default redir=-1 resp=2 lib-name= lib-ver=
1:M 13 Mar 2026 21:16:11.312 . 0 clients connected (0 replicas), 1047496 bytes in use
1:M 13 Mar 2026 21:16:15.226 - Accepted 127.0.0.1:41264
1:M 13 Mar 2026 21:16:15.227 - Client closed connection id=5720 addr=127.0.0.1:41264 laddr=127.0.0.1:6379 fd=10 name= age=0 idle=0 flags=N db=0 sub=0 psub=0 ssub=0 multi=-1 watch=0 qbuf=0 qbuf-free=20474 argv-mem=0 multi-mem=0 rbs=16384 rbp=16384 obl=0 oll=0 omem=0 tot-mem=37760 events=r cmd=ping user=default redir=-1 resp=2 lib-name= lib-ver=
1:M 13 Mar 2026 21:16:16.443 . 0 clients connected (0 replicas), 1047496 bytes in use


### 7. DOCKER COMPOSE FILE (authentik section)

```yaml
  authentik:
    image: ghcr.io/goauthentik/server:latest
    restart: unless-stopped
    user: "${AUTHENTIK_UID:-1000}:${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      - 'AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}'
      # TRIPLE-CHECK this entire block for typos and variable names.
      - 'AUTHENTIK_POSTGRESQL__HOST=postgres'
      - 'AUTHENTIK_POSTGRESQL__PORT=5432'
      - 'AUTHENTIK_POSTGRESQL__NAME=${AUTHENTIK_DB_NAME}'
      - 'AUTHENTIK_POSTGRESQL__USER=${AUTHENTIK_DB_USER}'
      - 'AUTHENTIK_POSTGRESQL__PASSWORD=${AUTHENTIK_DB_PASS}'
      - 'AUTHENTIK_REDIS__HOST=redis'
      - 'AUTHENTIK_REDIS__PORT=6379'
      - 'AUTHENTIK_REDIS__DB=0'
      - 'AUTHENTIK_REDIS__PASSWORD=Ewkxl1FSKz8bt150llxJrDPrUs3Qqnap'
      # Add any other required Authentik variables here
    volumes:
      - ./authentik:/media
      - ./authentik:/templates
    depends_on:
      postgres:
        condition: service_healthy

  tailscale:
    image: tailscale/tailscale:latest
    container_name: ai-datasquiz-tailscale-1
    hostname: ai-datasquiz
    environment:
      - TS_AUTHKEY=tskey-auth-kmrpeLFThF11CNTRL-KFzGnfMPQVJeKqirm3nWVJeV2jq78FbrM
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_USERSPACE=true
      - TS_ACCEPT_DNS=false
      - TS_ACCEPT_ROUTES=true
    volumes:
      - ./tailscale:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - net_admin
      - sys_module
    devices:
      - /dev/net/tun
    restart: unless-stopped
    command: sh -c "tailscaled --tun=userspace-networking --socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1055 & tailscale up --hostname=ai-datasquiz --authkey=tskey-auth-kmrpeLFThF11CNTRL-KFzGnfMPQVJeKqirm3nWVJeV2jq78FbrM && wait"


```


### 8. CADDYFILE CONFIGURATION

```nginx
{
    email admin@datasquiz.net
    # acme_dns google_cloud_dns ... # Placeholder for future DNS challenge
}

ai.datasquiz.net {
    tls internal {
        on_demand
    }
    respond "AI Platform v3.2.0 is active. Welcome." 200
}

grafana.ai.datasquiz.net {
    reverse_proxy grafana:3000
}

prometheus.ai.datasquiz.net {
    reverse_proxy prometheus:9090
}

auth.ai.datasquiz.net {
    reverse_proxy authentik:9000
}

openwebui.ai.datasquiz.net {
    reverse_proxy openwebui:8081
}

n8n.ai.datasquiz.net {
    reverse_proxy n8n:5678
}

flowise.ai.datasquiz.net {
    reverse_proxy flowise:3000
}

anythingllm.ai.datasquiz.net {
    reverse_proxy anythingllm:3001
}

litellm.ai.datasquiz.net {
    reverse_proxy litellm:4000
}

dify.ai.datasquiz.net {
    reverse_proxy dify:3001
}


```


### 9. ENVIRONMENT VARIABLES (non-sensitive)

```bash
TENANT_ID=datasquiz
DOMAIN=ai.datasquiz.net
TENANT_UID=1001
TENANT_GID=1001
ENABLE_POSTGRES=true
ENABLE_REDIS=true
ENABLE_CADDY=true
ENABLE_OLLAMA=true
ENABLE_OPENAI=false
ENABLE_ANTHROPIC=false
ENABLE_GROQ=false
ENABLE_OPENROUTER=false
ENABLE_GEMINI=false
ENABLE_LOCALAI=false
ENABLE_VLLM=false
ENABLE_OPENWEBUI=true
ENABLE_ANYTHINGLLM=true
ENABLE_DIFY=true
ENABLE_N8N=true
ENABLE_FLOWISE=true
ENABLE_LITELLM=true
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
ENABLE_GPU=false
TENANT_DIR=/mnt/data/datasquiz

```


### 10. SERVICE HEALTH CHECKS
starting

authentik: starting


n8n: No health check


grafana: No health check
starting

openwebui: starting


flowise: No health check
starting

anythingllm: starting


litellm: No health check


### 11. NETWORK ALIASES

ai-datasquiz-openwebui-1: [ai-datasquiz-openwebui-1 openwebui]

ai-datasquiz-openclaw-1: [ai-datasquiz-openclaw-1 openclaw]

ai-datasquiz-anythingllm-1: [ai-datasquiz-anythingllm-1 anythingllm]

ai-datasquiz-flowise-1: [ai-datasquiz-flowise-1 flowise]

ai-datasquiz-litellm-1: [ai-datasquiz-litellm-1 litellm]

ai-datasquiz-authentik-1: [ai-datasquiz-authentik-1 authentik]

ai-datasquiz-n8n-1: [ai-datasquiz-n8n-1 n8n]

ai-datasquiz-ollama-1: [ai-datasquiz-ollama-1 ollama]

ai-datasquiz-rclone-1: [ai-datasquiz-rclone-1 rclone]

ai-datasquiz-tailscale-1: [ai-datasquiz-tailscale-1 tailscale]


### 12. DNS RESOLUTION TESTS

Testing authentik:
Server:		127.0.0.11
Address:	127.0.0.11:53

** server can't find authentik.ap-southeast-2.compute.internal: NXDOMAIN

** server can't find authentik.ap-southeast-2.compute.internal: NXDOMAIN

DNS lookup failed

Testing n8n:
Server:		127.0.0.11
Address:	127.0.0.11:53

** server can't find n8n.ap-southeast-2.compute.internal: NXDOMAIN

** server can't find n8n.ap-southeast-2.compute.internal: NXDOMAIN

DNS lookup failed

Testing grafana:
Server:		127.0.0.11
Address:	127.0.0.11:53

** server can't find grafana.ap-southeast-2.compute.internal: NXDOMAIN

** server can't find grafana.ap-southeast-2.compute.internal: NXDOMAIN

DNS lookup failed

Testing postgres:
Server:		127.0.0.11
Address:	127.0.0.11:53

** server can't find postgres.ap-southeast-2.compute.internal: NXDOMAIN

** server can't find postgres.ap-southeast-2.compute.internal: NXDOMAIN

DNS lookup failed

Testing redis:
Server:		127.0.0.11
Address:	127.0.0.11:53

** server can't find redis.ap-southeast-2.compute.internal: NXDOMAIN

** server can't find redis.ap-southeast-2.compute.internal: NXDOMAIN

DNS lookup failed


### 13. SYSTEM RESOURCE STATUS

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme1n1     98G  3.2G   90G   4% /mnt
               total        used        free      shared  buff/cache   available
Mem:           7.6Gi       7.0Gi       201Mi       5.4Mi       813Mi       690Mi
Swap:          8.0Gi       4.6Gi       3.4Gi
CONTAINER                                                          CPU %     MEM USAGE / LIMIT
ed4543741817db2eeadbf83e1c827d82382779e8f9d1210fbc455b6435453748   19.31%    57.23MiB / 7.635GiB
39c5aaf54c900053f0447968984735483ff2d492242471ce936a84c48c799c95   0.00%     3.113MiB / 7.635GiB
e7a8d4dfa3ff1ac44eebf56aa52df5c70b8b21886680c894c541ac3540a50f59   19.99%    291.1MiB / 7.635GiB
8269a738281d3c022f2aa8812a92ece7d604f6d7b8c40ae6b26a239f0017ae33   23.47%    89MiB / 7.635GiB
826a9967ba82971d56d114c052ce1357c33b128a0e6f9b00796333d911d48d37   10.66%    118.1MiB / 7.635GiB
23a49b4be80006afd86285979fae9131174e583ccc0d2c7db7143d27f57fcff8   10.20%    215.3MiB / 7.635GiB
a1ade09540d90019739074f5aa2883680560157f23e35dcae05f6539f91e5676   0.00%     8.477MiB / 7.635GiB
8f23d7230d2b06823c4d7e16bdcaa4a56df4371a1046a4bb2f62742b2e52507c   0.02%     15.04MiB / 7.635GiB
bf13179a6d8325215726e3dcd84e9017aa5a22d35579656079bb8f4f352abb06   0.01%     9.023MiB / 7.635GiB
0a03b11d640e192b157206c2d9a2163cf5e72ad6d80b7307e73f238a9d90dd62   0.01%     23.31MiB / 7.635GiB
7dd7b0ddcc39dae0306f6d3d473bf37e23efc1ac4ac5390ff6c9c3dd38c4b3e4   0.00%     17.09MiB / 7.635GiB
6c51d00d313845e4197a77b0daaaf69c4e694778278ed000863a4f264b715e6a   0.59%     2.109MiB / 7.635GiB
257415c091c98b6080d56e3f064095872acacb94d109ec49e9cb661d1c0d6db2   0.02%     3.109MiB / 7.635GiB
06e272253f077649a781ba00cf8ee332d791079db906822ce67f658bb498aedd   0.00%     6.758MiB / 7.635GiB
72e6b9253b9359fbf0be3c3a619cd7154e1da9db9984ca29a55de1d8ae510a2a   0.31%     90.47MiB / 7.635GiB
f1aca310ea5f4cf22d2b968a8bc683073dc497cb65cc876762832c0df62e447b   0.00%     7.051MiB / 7.635GiB
3801807f3a4a966869ae72e945b1e87873052e8d2ac06c607d156093128722af   15.71%    25.55MiB / 7.635GiB

```
