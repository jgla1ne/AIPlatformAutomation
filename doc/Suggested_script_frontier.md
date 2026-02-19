\#\!/bin/bash

# **1-setup-wizard.sh**

# **Interactive configuration wizard. Produces /opt/ai-platform/.env**

# **ALL downstream scripts source this file exclusively.**

set \-euo pipefail

RED='\\033\[0;31m'; GREEN='\\033\[0;32m'; YELLOW='\\033\[1;33m' BLUE='\\033\[0;34m'; CYAN='\\033\[0;36m'; BOLD='\\033\[1m'; NC='\\033\[0m'

log() { echo \-e "${GREEN}\[INFO\]${NC} $*"; } warn() { echo \-e "${YELLOW}\[WARN\]${NC} $*"; } err() { echo \-e "${RED}\[ERROR\]${NC} $*"; exit 1; } section() { echo \-e "\\n${BLUE}${BOLD}━━━ $* ━━━${NC}"; } ask() { echo \-e "${CYAN}$\*${NC}"; }

PLATFORM\_DIR="/opt/ai-platform" ENV\_FILE="${PLATFORM\_DIR}/.env"

# **── Root check ────────────────────────────────────────────────────────────────**

\[\[ $EUID \-ne 0 \]\] && err "Must run as root (sudo)"

# **── Dependency check ──────────────────────────────────────────────────────────**

check\_prerequisites() { section "Prerequisite Check" local missing=()

command \-v docker        &\>/dev/null || missing+=("docker")  
command \-v curl          &\>/dev/null || missing+=("curl")  
command \-v openssl       &\>/dev/null || missing+=("openssl")  
docker compose version   &\>/dev/null || missing+=("docker-compose-plugin")  
systemctl is-active \--quiet nginx    || missing+=("nginx (not running)")

if \[\[ ${\#missing\[@\]} \-gt 0 \]\]; then  
    err "Missing prerequisites: ${missing\[\*\]}\\nRun 0-install-prerequisites.sh first"  
fi  
log "All prerequisites satisfied"

}

# **── Resource detection ────────────────────────────────────────────────────────**

detect\_resources() { section "System Resource Detection"

DETECTED\_RAM\_GB=$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo)  
DETECTED\_DISK\_GB=$(df "${PLATFORM\_DIR}" \--output=avail \-BG 2\>/dev/null | tail \-1 | tr \-d 'G ')  
DETECTED\_CPUS=$(nproc)  
DETECTED\_IP=$(hostname \-I | awk '{print $1}')

\# GPU detection  
GPU\_DETECTED=false  
GPU\_NAME=""  
GPU\_VRAM\_GB=0

if command \-v nvidia-smi &\>/dev/null && nvidia-smi &\>/dev/null 2\>&1; then  
    GPU\_DETECTED=true  
    GPU\_NAME=$(nvidia-smi \--query-gpu=name \--format=csv,noheader | head \-1)  
    GPU\_VRAM\_MB=$(nvidia-smi \--query-gpu=memory.total \--format=csv,noheader,nounits | head \-1 | tr \-d ' ')  
    GPU\_VRAM\_GB=$(( GPU\_VRAM\_MB / 1024 ))  
    log "GPU: ${GPU\_NAME} (${GPU\_VRAM\_GB}GB VRAM)"  
fi

log "RAM:  ${DETECTED\_RAM\_GB}GB"  
log "Disk: ${DETECTED\_DISK\_GB}GB available"  
log "CPUs: ${DETECTED\_CPUS}"  
log "IP:   ${DETECTED\_IP}"  
log "GPU:  ${GPU\_DETECTED} ${GPU\_NAME:+(${GPU\_NAME})}"

}

# **── Secret generation ─────────────────────────────────────────────────────────**

gen\_secret() { openssl rand \-hex 32; } gen\_password() { openssl rand \-base64 24 | tr \-d '=/+' | head \-c 32; }

# **── Deployment mode ───────────────────────────────────────────────────────────**

configure\_deployment\_mode() { section "Deployment Mode" echo "" echo " 1\) Local IP only (http://${DETECTED\_IP}) \- no DNS required" echo " 2\) Custom domain ([https://yourdomain.com](https://yourdomain.com/)) \- requires DNS \+ SSL" echo " 3\) Cloudflare Tunnel ([https://yourdomain.com](https://yourdomain.com/)) \- zero port exposure" echo "" ask "Select deployment mode \[1-3\] (default: 1):" read \-r mode\_choice mode\_choice="${mode\_choice:-1}"

case "$mode\_choice" in  
    1\)  
        DEPLOYMENT\_MODE="local"  
        BASE\_DOMAIN="${DETECTED\_IP}"  
        USE\_SSL=false  
        USE\_CLOUDFLARE\_TUNNEL=false  
        log "Mode: Local IP (${DETECTED\_IP})"  
        ;;  
    2\)  
        DEPLOYMENT\_MODE="domain"  
        USE\_CLOUDFLARE\_TUNNEL=false  
        ask "Enter your domain (e.g. ai.example.com):"  
        read \-r BASE\_DOMAIN  
        \[\[ \-z "$BASE\_DOMAIN" \]\] && err "Domain cannot be empty"  
        ask "Use SSL/HTTPS? (requires certbot) \[Y/n\]:"  
        read \-r ssl\_ans  
        USE\_SSL=$(\[\[ "${ssl\_ans,,}" \!= "n" \]\] && echo true || echo false)  
        log "Mode: Domain (${BASE\_DOMAIN}, SSL=${USE\_SSL})"  
        ;;  
    3\)  
        DEPLOYMENT\_MODE="cloudflare"  
        USE\_CLOUDFLARE\_TUNNEL=true  
        USE\_SSL=true  
        ask "Enter your Cloudflare tunnel domain (e.g. ai.example.com):"  
        read \-r BASE\_DOMAIN  
        \[\[ \-z "$BASE\_DOMAIN" \]\] && err "Domain cannot be empty"  
        ask "Enter Cloudflare Tunnel token:"  
        read \-r \-s CLOUDFLARE\_TUNNEL\_TOKEN  
        echo ""  
        \[\[ \-z "$CLOUDFLARE\_TUNNEL\_TOKEN" \]\] && err "Tunnel token cannot be empty"  
        log "Mode: Cloudflare Tunnel (${BASE\_DOMAIN})"  
        ;;  
    \*)  
        err "Invalid choice: ${mode\_choice}"  
        ;;  
esac

}

# **── Service selection ─────────────────────────────────────────────────────────**

# **Each service has:**

# **\- display name**

# **\- internal name (used for env vars, container names)**

# **\- min RAM requirement**

# **\- description**

# **\- default enabled (y/n)**

declare \-A SVC\_DISPLAY=( \[ollama\]="Ollama (LLM Runtime)" \[open\_webui\]="Open WebUI (Chat Interface)" \[flowise\]="Flowise (Visual Flow Builder)" \[n8n\]="n8n (Workflow Automation)" \[langfuse\]="Langfuse (LLM Observability)" \[qdrant\]="Qdrant (Vector Database)" \[redis\]="Redis (Cache/Queue)" \[searxng\]="SearXNG (Web Search)" )

declare \-A SVC\_DESCRIPTION=( \[ollama\]="Runs local LLM models (llama, mistral, etc.)" \[open\_webui\]="ChatGPT-like interface for Ollama \+ OpenAI" \[flowise\]="Drag-and-drop LLM flow builder (LangChain)" \[n8n\]="No-code workflow automation with AI nodes" \[langfuse\]="Traces, evals and analytics for LLM apps" \[qdrant\]="High-performance vector similarity search" \[redis\]="Required by n8n queue mode and Langfuse" \[searxng\]="Privacy-respecting metasearch (used by Open WebUI RAG)" )

declare \-A SVC\_MIN\_RAM=( \[ollama\]=4 \[open\_webui\]=1 \[flowise\]=1 \[n8n\]=1 \[langfuse\]=2 \[qdrant\]=1 \[redis\]=0 \[searxng\]=0 )

declare \-A SVC\_REQUIRES=( \[open\_webui\]="ollama" \# needs at least ollama or openai \[langfuse\]="redis" \# needs redis for worker queue \[langfuse\_worker\]="langfuse" \# internal )

declare \-A SVC\_DEFAULT\_ENABLED=( \[ollama\]=true \[open\_webui\]=true \[flowise\]=true \[n8n\]=true \[langfuse\]=true \[qdrant\]=true \[redis\]=true \[searxng\]=true )

# **Ordered for display**

SERVICE\_ORDER=(ollama open\_webui flowise n8n langfuse qdrant redis searxng)

# **Final selection map \- populated by select\_services()**

declare \-A SERVICE\_ENABLED

select\_services() { section "Service Selection"

echo ""  
echo "  Available services (RAM budget: ${DETECTED\_RAM\_GB}GB):"  
echo ""  
printf "  %-4s %-30s %-8s %s\\n" "Sel" "Service" "Min RAM" "Description"  
printf "  %-4s %-30s %-8s %s\\n" "---" "-------" "-------" "-----------"

local total\_min\_ram=0  
for svc in "${SERVICE\_ORDER\[@\]}"; do  
    local min\_ram="${SVC\_MIN\_RAM\[$svc\]}"  
    local default="${SVC\_DEFAULT\_ENABLED\[$svc\]}"  
    local flag="\[Y\]"  
    \[\[ "$default" \!= "true" \]\] && flag="\[n\]"  
    \[\[ $min\_ram \-gt $DETECTED\_RAM\_GB \]\] && flag="\[\!\] LOW RAM"  
    printf "  %-4s %-30s %-8s %s\\n" \\  
        "$flag" "${SVC\_DISPLAY\[$svc\]}" "${min\_ram}GB" "${SVC\_DESCRIPTION\[$svc\]}"  
done

echo ""  
echo "  Options:"  
echo "    a) Accept all defaults (recommended)"  
echo "    c) Custom selection"  
echo "    m) Minimal (Ollama \+ Open WebUI only)"  
echo ""  
ask "Choice \[a/c/m\] (default: a):"  
read \-r sel\_choice  
sel\_choice="${sel\_choice:-a}"

case "${sel\_choice,,}" in  
    a)  
        log "Using default service selection"  
        for svc in "${SERVICE\_ORDER\[@\]}"; do  
            SERVICE\_ENABLED\[$svc\]="${SVC\_DEFAULT\_ENABLED\[$svc\]}"  
        done  
        ;;  
    m)  
        log "Minimal selection: Ollama \+ Open WebUI"  
        for svc in "${SERVICE\_ORDER\[@\]}"; do  
            SERVICE\_ENABLED\[$svc\]=false  
        done  
        SERVICE\_ENABLED\[ollama\]=true  
        SERVICE\_ENABLED\[open\_webui\]=true  
        ;;  
    c)  
        log "Custom selection:"  
        for svc in "${SERVICE\_ORDER\[@\]}"; do  
            local default="${SVC\_DEFAULT\_ENABLED\[$svc\]}"  
            local default\_label="Y/n"  
            \[\[ "$default" \!= "true" \]\] && default\_label="y/N"  
            ask "  Enable ${SVC\_DISPLAY\[$svc\]}? \[${default\_label}\]:"  
            read \-r ans  
            if \[\[ \-z "$ans" \]\]; then  
                SERVICE\_ENABLED\[$svc\]="$default"  
            else  
                SERVICE\_ENABLED\[$svc\]=$(\[\[ "${ans,,}" \== "y" \]\] && echo true || echo false)  
            fi  
            log "  ${SVC\_DISPLAY\[$svc\]}: ${SERVICE\_ENABLED\[$svc\]}"  
        done  
        ;;  
    \*)  
        err "Invalid choice"  
        ;;  
esac

\# ── Enforce dependencies ──────────────────────────────────────────────────  
\# Redis is required if n8n or langfuse are enabled  
if \[\[ "${SERVICE\_ENABLED\[n8n\]:-false}" \== "true" \]\] || \\  
   \[\[ "${SERVICE\_ENABLED\[langfuse\]:-false}" \== "true" \]\]; then  
    if \[\[ "${SERVICE\_ENABLED\[redis\]:-false}" \!= "true" \]\]; then  
        warn "Redis is required by n8n/langfuse \- enabling automatically"  
        SERVICE\_ENABLED\[redis\]=true  
    fi  
fi

\# Qdrant is recommended for langfuse but not required  
\# open-webui needs ollama OR an OpenAI key  
if \[\[ "${SERVICE\_ENABLED\[open\_webui\]:-false}" \== "true" \]\] && \\  
   \[\[ "${SERVICE\_ENABLED\[ollama\]:-false}" \!= "true" \]\]; then  
    warn "Open WebUI enabled without Ollama"  
    ask "  Enter OpenAI API key (or leave blank to add Ollama):"  
    read \-r \-s OPENAI\_API\_KEY  
    echo ""  
    if \[\[ \-z "$OPENAI\_API\_KEY" \]\]; then  
        log "Enabling Ollama automatically for Open WebUI"  
        SERVICE\_ENABLED\[ollama\]=true  
    fi  
fi

\# Show final selection  
echo ""  
log "Final service selection:"  
for svc in "${SERVICE\_ORDER\[@\]}"; do  
    local status="${SERVICE\_ENABLED\[$svc\]:-false}"  
    local icon="✓"; \[\[ "$status" \!= "true" \]\] && icon="✗"  
    log "  ${icon} ${SVC\_DISPLAY\[$svc\]}"  
done

}

# **── Per-service configuration ─────────────────────────────────────────────────**

configure\_ollama() { \[\[ "${SERVICE\_ENABLED\[ollama\]:-false}" \!= "true" \]\] && return

section "Ollama Configuration"

OLLAMA\_USE\_GPU=false  
if \[\[ "$GPU\_DETECTED" \== "true" \]\]; then  
    ask "Use GPU for Ollama? \[Y/n\]:"  
    read \-r gpu\_ans  
    \[\[ "${gpu\_ans,,}" \!= "n" \]\] && OLLAMA\_USE\_GPU=true  
    log "GPU mode: ${OLLAMA\_USE\_GPU}"  
fi

OLLAMA\_NUM\_PARALLEL=1  
OLLAMA\_MAX\_LOADED\_MODELS=1  
if \[\[ $DETECTED\_RAM\_GB \-ge 32 \]\]; then  
    OLLAMA\_NUM\_PARALLEL=4  
    OLLAMA\_MAX\_LOADED\_MODELS=3  
elif \[\[ $DETECTED\_RAM\_GB \-ge 16 \]\]; then  
    OLLAMA\_NUM\_PARALLEL=2  
    OLLAMA\_MAX\_LOADED\_MODELS=2  
fi  
log "Parallel requests: ${OLLAMA\_NUM\_PARALLEL}, Max loaded models: ${OLLAMA\_MAX\_LOADED\_MODELS}"

ask "Pull a default model after deployment? (e.g. llama3.2:3b) \[leave blank to skip\]:"  
read \-r OLLAMA\_DEFAULT\_MODEL  
log "Auto-pull model: ${OLLAMA\_DEFAULT\_MODEL:-none}"

}

configure\_open\_webui() { \[\[ "${SERVICE\_ENABLED\[open\_webui\]:-false}" \!= "true" \]\] && return section "Open WebUI Configuration"

OPEN\_WEBUI\_ENABLE\_RAG=false  
if \[\[ "${SERVICE\_ENABLED\[searxng\]:-false}" \== "true" \]\]; then  
    OPEN\_WEBUI\_ENABLE\_RAG=true  
    log "RAG web search: enabled (via SearXNG)"  
fi

OPEN\_WEBUI\_ENABLE\_AUTH=true  
ask "Enable authentication for Open WebUI? \[Y/n\]:"  
read \-r auth\_ans  
\[\[ "${auth\_ans,,}" \== "n" \]\] && OPEN\_WEBUI\_ENABLE\_AUTH=false  
log "Authentication: ${OPEN\_WEBUI\_ENABLE\_AUTH}"

}

configure\_n8n() { \[\[ "${SERVICE\_ENABLED\[n8n\]:-false}" \!= "true" \]\] && return section "n8n Configuration"

N8N\_BASIC\_AUTH\_ENABLED=true  
ask "Enable n8n basic auth? \[Y/n\]:"  
read \-r auth\_ans  
if \[\[ "${auth\_ans,,}" \== "n" \]\]; then  
    N8N\_BASIC\_AUTH\_ENABLED=false  
else  
    ask "  n8n username \[admin\]:"  
    read \-r N8N\_BASIC\_AUTH\_USER  
    N8N\_BASIC\_AUTH\_USER="${N8N\_BASIC\_AUTH\_USER:-admin}"  
    ask "  n8n password \[generated\]:"  
    read \-r \-s N8N\_BASIC\_AUTH\_PASSWORD  
    echo ""  
    N8N\_BASIC\_AUTH\_PASSWORD="${N8N\_BASIC\_AUTH\_PASSWORD:-$(gen\_password)}"  
fi  
log "n8n auth: ${N8N\_BASIC\_AUTH\_ENABLED}"

}

configure\_flowise() { \[\[ "${SERVICE\_ENABLED\[flowise\]:-false}" \!= "true" \]\] && return section "Flowise Configuration"

FLOWISE\_AUTH\_ENABLED=false  
ask "Enable Flowise username/password? \[y/N\]:"  
read \-r auth\_ans  
if \[\[ "${auth\_ans,,}" \== "y" \]\]; then  
    FLOWISE\_AUTH\_ENABLED=true  
    ask "  Flowise username \[admin\]:"  
    read \-r FLOWISE\_USERNAME  
    FLOWISE\_USERNAME="${FLOWISE\_USERNAME:-admin}"  
    ask "  Flowise password \[generated\]:"  
    read \-r \-s FLOWISE\_PASSWORD  
    echo ""  
    FLOWISE\_PASSWORD="${FLOWISE\_PASSWORD:-$(gen\_password)}"  
fi

}

configure\_langfuse() { \[\[ "${SERVICE\_ENABLED\[langfuse\]:-false}" \!= "true" \]\] && return section "Langfuse Configuration" log "Langfuse uses PostgreSQL (deployed internally)" LANGFUSE\_DB\_PASSWORD=$(gen\_password) LANGFUSE\_SECRET\_KEY=$(gen\_secret) LANGFUSE\_SALT=$(gen\_secret) log "Database credentials: generated" }

configure\_ports() { section "Port Configuration" log "Default ports:"

declare \-gA DEFAULT\_PORTS=(  
    \[ollama\]=11434  
    \[open\_webui\]=3000  
    \[flowise\]=3001  
    \[n8n\]=5678  
    \[langfuse\]=8080  
    \[qdrant\]=6333  
    \[qdrant\_grpc\]=6334  
    \[redis\]=6379  
    \[searxng\]=8081  
)

echo ""  
ask "Customize ports? \[y/N\]:"  
read \-r port\_ans

declare \-gA FINAL\_PORTS  
if \[\[ "${port\_ans,,}" \== "y" \]\]; then  
    for svc in "${\!DEFAULT\_PORTS\[@\]}"; do  
        ask "  ${svc} port \[${DEFAULT\_PORTS\[$svc\]}\]:"  
        read \-r p  
        FINAL\_PORTS\[$svc\]="${p:-${DEFAULT\_PORTS\[$svc\]}}"  
    done  
else  
    for svc in "${\!DEFAULT\_PORTS\[@\]}"; do  
        FINAL\_PORTS\[$svc\]="${DEFAULT\_PORTS\[$svc\]}"  
    done  
fi

\# Log only enabled service ports  
for svc in "${SERVICE\_ORDER\[@\]}"; do  
    \[\[ "${SERVICE\_ENABLED\[$svc\]:-false}" \== "true" \]\] && \\  
        log "  ${svc}: ${FINAL\_PORTS\[$svc\]:-N/A}"  
done

}

# **── Write .env ────────────────────────────────────────────────────────────────**

write\_env\_file() { section "Writing Configuration"

mkdir \-p "${PLATFORM\_DIR}/configs" "${PLATFORM\_DIR}/secrets"  
chmod 700 "${PLATFORM\_DIR}/secrets"

cat \> "${ENV\_FILE}" \<\< EOF

# **\============================================================**

# **AI Platform Configuration**

# **Generated: $(date \-u \+"%Y-%m-%dT%H:%M:%SZ")**

# **DO NOT COMMIT TO VERSION CONTROL**

# **\============================================================**

# **── Platform ─────────────────────────────────────────────────────────────────**

PLATFORM\_DIR=${PLATFORM\_DIR} DEPLOYMENT\_MODE=${DEPLOYMENT\_MODE} BASE\_DOMAIN=${BASE\_DOMAIN} USE\_SSL=${USE\_SSL} USE\_CLOUDFLARE\_TUNNEL=${USE\_CLOUDFLARE\_TUNNEL:-false} $(\[ \-n "${CLOUDFLARE\_TUNNEL\_TOKEN:-}" \] && echo "CLOUDFLARE\_TUNNEL\_TOKEN=${CLOUDFLARE\_TUNNEL\_TOKEN}") SERVER\_IP=${DETECTED\_IP}

# **── System Resources ─────────────────────────────────────────────────────────**

DETECTED\_RAM\_GB=${DETECTED\_RAM\_GB} DETECTED\_DISK\_GB=${DETECTED\_DISK\_GB} DETECTED\_CPUS=${DETECTED\_CPUS} GPU\_DETECTED=${GPU\_DETECTED} GPU\_NAME=${GPU\_NAME:-none} GPU\_VRAM\_GB=${GPU\_VRAM\_GB:-0}

# **── Service Enablement Flags ─────────────────────────────────────────────────**

# **These flags drive ALL downstream scripts (2, 3, 4\)**

SERVICE\_OLLAMA\_ENABLED=${SERVICE\_ENABLED\[ollama\]:-false} SERVICE\_OPEN\_WEBUI\_ENABLED=${SERVICE\_ENABLED\[open\_webui\]:-false} SERVICE\_FLOWISE\_ENABLED=${SERVICE\_ENABLED\[flowise\]:-false} SERVICE\_N8N\_ENABLED=${SERVICE\_ENABLED\[n8n\]:-false} SERVICE\_LANGFUSE\_ENABLED=${SERVICE\_ENABLED\[langfuse\]:-false} SERVICE\_QDRANT\_ENABLED=${SERVICE\_ENABLED\[qdrant\]:-false} SERVICE\_REDIS\_ENABLED=${SERVICE\_ENABLED\[redis\]:-false} SERVICE\_SEARXNG\_ENABLED=${SERVICE\_ENABLED\[searxng\]:-false}

# **── Port Assignments ─────────────────────────────────────────────────────────**

PORT\_OLLAMA=${FINAL\_PORTS\[ollama\]:-11434} PORT\_OPEN\_WEBUI=${FINAL\_PORTS\[open\_webui\]:-3000} PORT\_FLOWISE=${FINAL\_PORTS\[flowise\]:-3001} PORT\_N8N=${FINAL\_PORTS\[n8n\]:-5678} PORT\_LANGFUSE=${FINAL\_PORTS\[langfuse\]:-8080} PORT\_QDRANT=${FINAL\_PORTS\[qdrant\]:-6333} PORT\_QDRANT\_GRPC=${FINAL\_PORTS\[qdrant\_grpc\]:-6334} PORT\_REDIS=${FINAL\_PORTS\[redis\]:-6379} PORT\_SEARXNG=${FINAL\_PORTS\[searxng\]:-8081}

# **── Ollama ───────────────────────────────────────────────────────────────────**

OLLAMA\_USE\_GPU=${OLLAMA\_USE\_GPU:-false} OLLAMA\_NUM\_PARALLEL=${OLLAMA\_NUM\_PARALLEL:-1} OLLAMA\_MAX\_LOADED\_MODELS=${OLLAMA\_MAX\_LOADED\_MODELS:-1} OLLAMA\_DEFAULT\_MODEL=${OLLAMA\_DEFAULT\_MODEL:-} OLLAMA\_IMAGE=ollama/ollama:latest

# **── Open WebUI ───────────────────────────────────────────────────────────────**

OPEN\_WEBUI\_ENABLE\_AUTH=${OPEN\_WEBUI\_ENABLE\_AUTH:-true} OPEN\_WEBUI\_ENABLE\_RAG=${OPEN\_WEBUI\_ENABLE\_RAG:-false} OPEN\_WEBUI\_SECRET\_KEY=$(gen\_secret) OPEN\_WEBUI\_IMAGE=ghcr.io/open-webui/open-webui:main OPENAI\_API\_KEY=${OPENAI\_API\_KEY:-}

# **── Flowise ──────────────────────────────────────────────────────────────────**

FLOWISE\_AUTH\_ENABLED=${FLOWISE\_AUTH\_ENABLED:-false} FLOWISE\_USERNAME=${FLOWISE\_USERNAME:-admin} FLOWISE\_PASSWORD=${FLOWISE\_PASSWORD:-$(gen\_password)} FLOWISE\_SECRET\_KEY=$(gen\_secret) FLOWISE\_IMAGE=flowiseai/flowise:latest

# **── n8n ──────────────────────────────────────────────────────────────────────**

N8N\_BASIC\_AUTH\_ENABLED=${N8N\_BASIC\_AUTH\_ENABLED:-false} N8N\_BASIC\_AUTH\_USER=${N8N\_BASIC\_AUTH\_USER:-admin} N8N\_BASIC\_AUTH\_PASSWORD=${N8N\_BASIC\_AUTH\_PASSWORD:-$(gen\_password)} N8N\_ENCRYPTION\_KEY=$(gen\_secret) N8N\_IMAGE=n8nio/n8n:latest

# **── Langfuse ─────────────────────────────────────────────────────────────────**

LANGFUSE\_SECRET\_KEY=${LANGFUSE\_SECRET\_KEY:-$(gen\_secret)} LANGFUSE\_SALT=${LANGFUSE\_SALT:-$(gen\_secret)} LANGFUSE\_DB\_PASSWORD=${LANGFUSE\_DB\_PASSWORD:-$(gen\_password)} LANGFUSE\_DB\_USER=langfuse LANGFUSE\_DB\_NAME=langfuse LANGFUSE\_IMAGE=langfuse/langfuse:latest POSTGRES\_IMAGE=postgres:15-alpine

# **── Qdrant ───────────────────────────────────────────────────────────────────**

QDRANT\_IMAGE=qdrant/qdrant:latest

# **── Redis ────────────────────────────────────────────────────────────────────**

REDIS\_IMAGE=redis:7-alpine

# **── SearXNG ──────────────────────────────────────────────────────────────────**

SEARXNG\_SECRET\_KEY=$(gen\_secret) SEARXNG\_IMAGE=searxng/searxng:latest

# **── Docker Images (common) ───────────────────────────────────────────────────**

NGINX\_IMAGE=nginx:alpine EOF

chmod 600 "${ENV\_FILE}"  
log "Configuration written to: ${ENV\_FILE}"

}

# **── Summary ───────────────────────────────────────────────────────────────────**

show\_summary() { section "Configuration Summary" echo "" log "Platform directory : ${PLATFORM\_DIR}" log "Deployment mode : ${DEPLOYMENT\_MODE}" log "Base domain/IP : ${BASE\_DOMAIN}" log "SSL : ${USE\_SSL}" echo "" log "Selected services:" for svc in "${SERVICE\_ORDER\[@\]}"; do local enabled="${SERVICE\_ENABLED\[$svc\]:-false}" local icon="✓"; \[\[ "$enabled" \!= "true" \]\] && icon="✗" printf " %s %s\\n" "$icon" "${SVC\_DISPLAY\[$svc\]}" done echo "" log "Config file: ${ENV\_FILE}" echo "" log "Next step: sudo bash 2-deploy-services.sh" }

# **── Main ──────────────────────────────────────────────────────────────────────**

main() { clear echo \-e "${BOLD}${BLUE}" echo " ╔═══════════════════════════════════════╗" echo " ║ AI Platform Setup Wizard ║" echo " ╚═══════════════════════════════════════╝" echo \-e "${NC}"

check\_prerequisites  
detect\_resources  
configure\_deployment\_mode  
select\_services  
configure\_ollama  
configure\_open\_webui  
configure\_n8n  
configure\_flowise  
configure\_langfuse  
configure\_ports  
write\_env\_file  
show\_summary

}

main "$@"

\#\!/bin/bash

# **2-deploy-services.sh**

# **Reads .env service flags → generates compose for ONLY enabled services**

# **→ deploys in correct dependency order → health checks before exit**

set \-euo pipefail

RED='\\033\[0;31m'; GREEN='\\033\[0;32m'; YELLOW='\\033\[1;33m'; BLUE='\\033\[0;34m'; NC='\\033\[0m' log() { echo \-e "${GREEN}\[$(date '+%H:%M:%S')\] $*${NC}"; } warn() { echo \-e "${YELLOW}\[$(date '+%H:%M:%S')\] WARN: $*${NC}"; } err() { echo \-e "${RED}\[$(date '+%H:%M:%S')\] ERROR: $*${NC}"; exit 1; } section() { echo \-e "\\n${BLUE}━━━ $* ━━━${NC}"; }

PLATFORM\_DIR="/opt/ai-platform" ENV\_FILE="${PLATFORM\_DIR}/.env" COMPOSE\_FILE="${PLATFORM\_DIR}/docker-compose.yml"

# **── Load & validate env ───────────────────────────────────────────────────────**

load\_env() { \[\[ \-f "$ENV\_FILE" \]\] || err "No config found at ${ENV\_FILE}. Run script 1 first." set \-a; source "$ENV\_FILE"; set \+a log "Loaded config from: ${ENV\_FILE}"

\# Validate critical vars exist  
\[\[ \-n "${DEPLOYMENT\_MODE:-}" \]\] || err "DEPLOYMENT\_MODE missing from .env"  
\[\[ \-n "${SERVER\_IP:-}"        \]\] || err "SERVER\_IP missing from .env"

}

# **── Health check helpers ──────────────────────────────────────────────────────**

# **All health checks use container-internal checks via docker exec**

# **This avoids the chicken-and-egg problem of checking via host ports**

# **before nginx is configured**

MAX\_WAIT=180 \# seconds total per service POLL=5 \# seconds between polls

wait\_for\_container\_healthy() { local name="$1" local start elapsed status

log "  Waiting for ${name}..."  
start=$(date \+%s)

while true; do  
    elapsed=$(( $(date \+%s) \- start ))  
    \[\[ $elapsed \-ge $MAX\_WAIT \]\] && {  
        warn "  TIMEOUT: ${name} not healthy after ${MAX\_WAIT}s"  
        docker logs \--tail=30 "$name" 2\>/dev/null | sed 's/^/    /'  
        return 1  
    }

    \# Check container exists at all  
    if \! docker inspect "$name" &\>/dev/null; then  
        log "    ${name}: container not yet created (${elapsed}s)..."  
        sleep "$POLL"; continue  
    fi

    status=$(docker inspect \--format='{{.State.Status}}' "$name" 2\>/dev/null || echo "unknown")  
    health=$(docker inspect \--format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \\  
                "$name" 2\>/dev/null || echo "none")

    case "$status" in  
        running)  
            case "$health" in  
                healthy)  
                    log "  ✓ ${name}: healthy (${elapsed}s)"  
                    return 0 ;;  
                none)  
                    \# No healthcheck defined \- running is good enough  
                    log "  ✓ ${name}: running, no healthcheck (${elapsed}s)"  
                    return 0 ;;  
                starting)  
                    log "    ${name}: starting... (${elapsed}s)"  
                    sleep "$POLL" ;;  
                unhealthy)  
                    warn "  ✗ ${name}: UNHEALTHY"  
                    docker logs \--tail=30 "$name" 2\>/dev/null | sed 's/^/    /'  
                    return 1 ;;  
                \*)  
                    log "    ${name}: health=${health} (${elapsed}s)"  
                    sleep "$POLL" ;;  
            esac ;;  
        exited|dead)  
            warn "  ✗ ${name}: ${status}"  
            docker logs \--tail=30 "$name" 2\>/dev/null | sed 's/^/    /'  
            return 1 ;;  
        \*)  
            log "    ${name}: status=${status} (${elapsed}s)"  
            sleep "$POLL" ;;  
    esac  
done

}

# **Wait for all containers in a tier, report but don't fail hard**

wait\_for\_tier() { local tier="$1"; shift local containers=("$@") local failed=0

section "Health Checks: ${tier}"  
for c in "${containers\[@\]}"; do  
    wait\_for\_container\_healthy "$c" || failed=$((failed \+ 1))  
done

if \[\[ $failed \-gt 0 \]\]; then  
    warn "${failed} container(s) in '${tier}' not healthy \- deployment may be partial"  
else  
    log "Tier '${tier}': all containers healthy"  
fi  
return $failed

}

# **── SearXNG config ────────────────────────────────────────────────────────────**

generate\_searxng\_config() { \[\[ "${SERVICE\_SEARXNG\_ENABLED:-false}" \!= "true" \]\] && return

local dir="${PLATFORM\_DIR}/configs/searxng"  
mkdir \-p "$dir"

\# Generate secret if not present  
local secret="${SEARXNG\_SECRET\_KEY:-$(openssl rand \-hex 32)}"

cat \> "${dir}/settings.yml" \<\< EOF

general: debug: false instance\_name: "AI Platform Search" enable\_metrics: false

search: safe\_search: 0 autocomplete: "" formats: \[html, json\]

server: port: 8080 bind\_address: "0.0.0.0" secret\_key: "${secret}" limiter: false image\_proxy: false http\_protocol\_version: "1.0" method: "GET"

engines:

* name: google engine: google shortcut: g  
* name: duckduckgo engine: duckduckgo shortcut: d

ui: static\_use\_hash: true infinite\_scroll: false default\_locale: "" results\_on\_new\_tab: false

enabled\_plugins:

* Hash\_plugin

* Search\_on\_category\_select

* Tracker\_URL\_remover EOF

   log "SearXNG config generated"

}

# **── Compose file generation ───────────────────────────────────────────────────**

# **Only enabled services are written into the compose file.**

# **This is the critical change \- no phantom upstreams.**

generate\_compose() { section "Generating docker-compose.yml"

local ollama\_gpu\_section=""  
if \[\[ "${SERVICE\_OLLAMA\_ENABLED:-false}" \== "true" \]\] && \\  
   \[\[ "${OLLAMA\_USE\_GPU:-false}" \== "true" \]\] && \\  
   \[\[ "${GPU\_DETECTED:-false}" \== "true" \]\]; then  
    ollama\_gpu\_section="  
deploy:  
  resources:  
    reservations:  
      devices:  
        \- driver: nvidia  
          count: all  
          capabilities: \[gpu\]"  
fi

\# Build depends\_on blocks dynamically based on what's enabled  
local webui\_depends=""  
if \[\[ "${SERVICE\_OLLAMA\_ENABLED:-false}" \== "true" \]\]; then  
    webui\_depends="  
depends\_on:  
  ollama:  
    condition: service\_healthy"  
fi

local langfuse\_depends=""  
if \[\[ "${SERVICE\_REDIS\_ENABLED:-false}" \== "true" \]\]; then  
    langfuse\_depends="  
  redis:  
    condition: service\_healthy"  
fi

local n8n\_depends=""  
if \[\[ "${SERVICE\_REDIS\_ENABLED:-false}" \== "true" \]\]; then  
    n8n\_depends="  
depends\_on:  
  redis:  
    condition: service\_healthy"  
fi

\# ── Write header ──────────────────────────────────────────────────────────  
cat \> "$COMPOSE\_FILE" \<\< 'HEADER'

# **AI Platform docker-compose.yml**

# **Generated by 2-deploy-services.sh \- do not edit manually**

networks: ai-platform: external: true

volumes: HEADER

\# ── Write volumes for enabled services only ───────────────────────────────  
\[\[ "${SERVICE\_OLLAMA\_ENABLED:-false}"    \== "true" \]\] && echo "  ollama-data:"       \>\> "$COMPOSE\_FILE"  
\[\[ "${SERVICE\_OPEN\_WEBUI\_ENABLED:-false}" \== "true" \]\] && echo "  open-webui-data:"  \>\> "$COMPOSE\_FILE"  
\[\[ "${SERVICE\_FLOWISE\_ENABLED:-false}"   \== "true" \]\] && echo "  flowise-data:"      \>\> "$COMPOSE\_FILE"  
\[\[ "${SERVICE\_N8N\_ENABLED:-false}"       \== "true" \]\] && echo "  n8n-data:"          \>\> "$COMPOSE\_FILE"  
\[\[ "${SERVICE\_LANGFUSE\_ENABLED:-false}"  \== "true" \]\] && echo "  langfuse-db-data:"  \>\> "$COMPOSE\_FILE"  
\[\[ "${SERVICE\_QDRANT\_ENABLED:-false}"    \== "true" \]\] && echo "  qdrant-data:"       \>\> "$COMPOSE\_FILE"  
\[\[ "${SERVICE\_REDIS\_ENABLED:-false}"     \== "true" \]\] && echo "  redis-data:"        \>\> "$COMPOSE\_FILE"

echo "" \>\> "$COMPOSE\_FILE"  
echo "services:" \>\> "$COMPOSE\_FILE"

\# ── TIER 1: Pure infrastructure (no inter-service deps) ───────────────────

\# Redis  
if \[\[ "${SERVICE\_REDIS\_ENABLED:-false}" \== "true" \]\]; then  
    cat \>\> "$COMPOSE\_FILE" \<\< EOF

redis: image: ${REDIS\_IMAGE:-redis:7-alpine} container\_name: redis restart: unless-stopped networks: \[ai-platform\] ports: \- "127.0.0.1:${PORT\_REDIS:-6379}:6379" volumes: \- redis-data:/data command: redis-server \--save 60 1 \--loglevel warning \--requirepass "" healthcheck: test: \["CMD", "redis-cli", "ping"\] interval: 10s timeout: 5s retries: 10 start\_period: 10s logging: driver: json-file options: {max-size: "10m", max-file: "3"} EOF fi

\# Qdrant  
if \[\[ "${SERVICE\_QDRANT\_ENABLED:-false}" \== "true" \]\]; then  
    cat \>\> "$COMPOSE\_FILE" \<\< EOF

qdrant: image: ${QDRANT\_IMAGE:-qdrant/qdrant:latest} container\_name: qdrant restart: unless-stopped networks: \[ai-platform\] ports: \- "127.0.0.1:${PORT\_QDRANT:-6333}:6333" \- "127.0.0.1:${PORT\_QDRANT\_GRPC:-6334}:6334" volumes: \- qdrant-data:/qdrant/storage healthcheck: test: \["CMD-SHELL", "curl \-sf [http://localhost:6333/healthz](http://localhost:6333/healthz) || exit 1"\] interval: 15s timeout: 10s retries: 10 start\_period: 20s logging: driver: json-file options: {max-size: "10m", max-file: "3"} EOF fi

\# Ollama  
if \[\[ "${SERVICE\_OLLAMA\_ENABLED:-false}" \== "true" \]\]; then  
    cat \>\> "$COMPOSE\_FILE" \<\< EOF

ollama: image: ${OLLAMA\_IMAGE:-ollama/ollama:latest} container\_name: ollama restart: unless-stopped networks: \[ai-platform\] ports: \- "127.0.0.1:${PORT\_OLLAMA:-11434}:11434" volumes: \- ollama-data:/root/.ollama environment: OLLAMA\_NUM\_PARALLEL: "${OLLAMA\_NUM\_PARALLEL:-1}" OLLAMA\_MAX\_LOADED\_MODELS: "${OLLAMA\_MAX\_LOADED\_MODELS:-1}" healthcheck: test: \["CMD-SHELL", "curl \-sf [http://localhost:11434/api/tags](http://localhost:11434/api/tags) || exit 1"\] interval: 15s timeout: 10s retries: 20 start\_period: 30s${ollama\_gpu\_section} logging: driver: json-file options: {max-size: "20m", max-file: "3"} EOF fi

\# Langfuse PostgreSQL (internal only, no port on host)  
if \[\[ "${SERVICE\_LANGFUSE\_ENABLED:-false}" \== "true" \]\]; then  
    cat \>\> "$COMPOSE\_FILE" \<\< EOF

langfuse-db: image: ${POSTGRES\_IMAGE:-postgres:15-alpine} container\_name: langfuse-db restart: unless-stopped networks: \[ai-platform\] volumes: \- langfuse-db-data:/var/lib/postgresql/data environment: POSTGRES\_USER: "${LANGFUSE\_DB\_USER:-langfuse}" POSTGRES\_PASSWORD: "${LANGFUSE\_DB\_PASSWORD}" POSTGRES\_DB: "${LANGFUSE\_DB\_NAME:-langfuse}" PGDATA: /var/lib/postgresql/data/pgdata healthcheck: test: \["CMD-SHELL", "pg\_isready \-U ${LANGFUSE\_DB\_USER:-langfuse} \-d ${LANGFUSE\_DB\_NAME:-langfuse}"\] interval: 10s timeout: 5s retries: 15 start\_period: 20s logging: driver: json-file options: {max-size: "10m", max-file: "3"} EOF fi

\# ── TIER 2: Services with tier-1 dependencies ─────────────────────────────

\# SearXNG  
if \[\[ "${SERVICE\_SEARXNG\_ENABLED:-false}" \== "true" \]\]; then  
    cat \>\> "$COMPOSE\_FILE" \<\< EOF

searxng: image: ${SEARXNG\_IMAGE:-searxng/searxng:latest} container\_name: searxng restart: unless-stopped networks: \[ai-platform\] ports: \- "127.0.0.1:${PORT\_SEARXNG:-8081}:8080" volumes: \- ${PLATFORM\_DIR}/configs/searxng:/etc/searxng:ro environment: SEARXNG\_BASE\_URL: "[http://localhost:${PORT\_SEARXNG:-8081}](http://localhost:${port_searxng:-8081%7D/)" healthcheck: test: \["CMD-SHELL", "wget \-qO- [http://localhost:8080/healthz](http://localhost:8080/healthz) || curl \-sf [http://localhost:8080/](http://localhost:8080/) || exit 1"\] interval: 15s timeout: 10s retries: 10 start\_period: 30s logging: driver: json-file options: {max-size: "10m", max-file: "3"} EOF fi

\# Flowise  
if \[\[ "${SERVICE\_FLOWISE\_ENABLED:-false}" \== "true" \]\]; then  
    local flowise\_auth\_env=""  
    if \[\[ "${FLOWISE\_AUTH\_ENABLED:-false}" \== "true" \]\]; then  
        flowise\_auth\_env="  
  FLOWISE\_USERNAME: \\"\\${FLOWISE\_USERNAME:-admin}\\"  
  FLOWISE\_PASSWORD: \\"\\${FLOWISE\_PASSWORD}\\""  
    fi

    cat \>\> "$COMPOSE\_FILE" \<\< EOF

flowise: image: ${FLOWISE\_IMAGE:-flowiseai/flowise:latest} container\_name: flowise restart: unless-stopped networks: \[ai-platform\] ports: \- "127.0.0.1:${PORT\_FLOWISE:-3001}:3000" volumes: \- flowise-data:/root/.flowise environment: PORT: "3000" FLOWISE\_SECRETKEY\_OVERWRITE: "${FLOWISE\_SECRET\_KEY}"${flowise\_auth\_env} healthcheck: test: \["CMD-SHELL", "curl \-sf [http://localhost:3000/](http://localhost:3000/) || exit 1"\] interval: 15s timeout: 10s retries: 15 start\_period: 45s logging: driver: json-file options: {max-size: "10m", max-file: "3"} EOF fi

\# n8n  
if \[\[ "${SERVICE\_N8N\_ENABLED:-false}" \== "true" \]\]; then  
    local n8n\_webhook\_url="http://${SERVER\_IP}:${PORT\_N8N:-5678}"  
    \[\[ "$DEPLOYMENT\_MODE" \!= "local" \]\] && \\  
        n8n\_webhook\_url="http${USE\_SSL:+s}://n8n.${BASE\_DOMAIN}"

    local n8n\_auth\_env=""  
    if \[\[ "${N8N\_BASIC\_AUTH\_ENABLED:-false}" \== "true" \]\]; then  
        n8n\_auth\_env="  
  N8N\_BASIC\_AUTH\_ACTIVE: \\"true\\"  
  N8N\_BASIC\_AUTH\_USER: \\"\\${N8N\_BASIC\_AUTH\_USER:-admin}\\"  
  N8N\_BASIC\_AUTH\_PASSWORD: \\"\\${N8N\_BASIC\_AUTH\_PASSWORD}\\""  
    fi

    cat \>\> "$COMPOSE\_FILE" \<\< EOF

n8n: image: ${N8N\_IMAGE:-n8nio/n8n:latest} container\_name: n8n restart: unless-stopped networks: \[ai-platform\]${n8n\_depends} ports: \- "127.0.0.1:${PORT\_N8N:-5678}:5678" volumes: \- n8n-data:/home/node/.n8n environment: N8N\_HOST: "0.0.0.0" N8N\_PORT: "5678" N8N\_PROTOCOL: "http" WEBHOOK\_URL: "${n8n\_webhook\_url}/" N8N\_ENCRYPTION\_KEY: "${N8N\_ENCRYPTION\_KEY}" EXECUTIONS\_PROCESS: "main" N8N\_LOG\_LEVEL: "warn"${n8n\_auth\_env} healthcheck: test: \["CMD-SHELL", "wget \-qO- [http://localhost:5678/healthz](http://localhost:5678/healthz) || exit 1"\] interval: 15s timeout: 10s retries: 15 start\_period: 45s logging: driver: json-file options: {max-size: "20m", max-file: "3"} EOF fi

\# Langfuse web \+ worker (both need db, worker needs redis)  
if \[\[ "${SERVICE\_LANGFUSE\_ENABLED:-false}" \== "true" \]\]; then  
    local langfuse\_nextauth\_url="http://${SERVER\_IP}:${PORT\_LANGFUSE:-8080}"  
    \[\[ "$DEPLOYMENT\_MODE" \!= "local" \]\] && \\  
        langfuse\_nextauth\_url="http${USE\_SSL:+s}://langfuse.${BASE\_DOMAIN}"

    cat \>\> "$COMPOSE\_FILE" \<\< EOF

langfuse-web: image: ${LANGFUSE\_IMAGE:-langfuse/langfuse:latest} container\_name: langfuse-web restart: unless-stopped networks: \[ai-platform\] ports: \- "127.0.0.1:${PORT\_LANGFUSE:-8080}:3000" depends\_on: langfuse-db: condition: service\_healthy${langfuse\_depends} environment: DATABASE\_URL: "postgresql://${LANGFUSE\_DB\_USER:-langfuse}:${LANGFUSE\_DB\_PASSWORD}@langfuse-db:5432/${LANGFUSE\_DB\_NAME:-langfuse}" NEXTAUTH\_URL: "${langfuse\_nextauth\_url}" NEXTAUTH\_SECRET: "${LANGFUSE\_SECRET\_KEY}" SALT: "${LANGFUSE\_SALT}" LANGFUSE\_ENABLE\_EXPERIMENTAL\_FEATURES: "false" TELEMETRY\_ENABLED: "false" NEXT\_PUBLIC\_SIGN\_UP\_DISABLED: "false" $(\[ "${SERVICE\_REDIS\_ENABLED:-false}" \== "true" \] && echo 'REDIS\_HOST: "redis"') $(\[ "${SERVICE\_REDIS\_ENABLED:-false}" \== "true" \] && echo 'REDIS\_PORT: "6379"') healthcheck: test: \["CMD-SHELL", "curl \-sf [http://localhost:3000/api/public/health](http://localhost:3000/api/public/health) || exit 1"\] interval: 20s timeout: 10s retries: 20 start\_period: 90s logging: driver: json-file options: {max-size: "20m", max-file: "3"}

langfuse-worker: image: ${LANGFUSE\_IMAGE:-langfuse/langfuse:latest} container\_name: langfuse-worker restart: unless-stopped networks: \[ai-platform\] command: \["node", "dist/src/server/worker/index.js"\] depends\_on: langfuse-db: condition: service\_healthy langfuse-web: condition: service\_healthy${langfuse\_depends} environment: DATABASE\_URL: "postgresql://${LANGFUSE\_DB\_USER:-langfuse}:${LANGFUSE\_DB\_PASSWORD}@langfuse-db:5432/${LANGFUSE\_DB\_NAME:-langfuse}" LANGFUSE\_SECRET\_KEY: "${LANGFUSE\_SECRET\_KEY}" SALT: "${LANGFUSE\_SALT}" $(\[ "${SERVICE\_REDIS\_ENABLED:-false}" \== "true" \] && echo 'REDIS\_HOST: "redis"') $(\[ "${SERVICE\_REDIS\_ENABLED:-false}" \== "true" \] && echo 'REDIS\_PORT: "6379"') healthcheck: test: \["CMD-SHELL", "curl \-sf [http://localhost:3030/api/health](http://localhost:3030/api/health) || exit 1"\] interval: 20s timeout: 10s retries: 10 start\_period: 60s logging: driver: json-file options: {max-size: "10m", max-file: "3"} EOF fi

\# ── TIER 3: Frontends (depend on everything above) ────────────────────────

\# Open WebUI  
if \[\[ "${SERVICE\_OPEN\_WEBUI\_ENABLED:-false}" \== "true" \]\]; then  
    local rag\_env=""  
    if \[\[ "${OPEN\_WEBUI\_ENABLE\_RAG:-false}" \== "true" \]\] && \\  
       \[\[ "${SERVICE\_SEARXNG\_ENABLED:-false}" \== "true" \]\]; then  
        rag\_env="  
  ENABLE\_RAG\_WEB\_SEARCH: \\"true\\"  
  RAG\_WEB\_SEARCH\_ENGINE: \\"searxng\\"  
  SEARXNG\_QUERY\_URL: \\"http://searxng:8080/search?q=\<query\>\&format=json\\""  
    fi

    local ollama\_url="http://ollama:11434"  
    local openai\_env=""  
    if \[\[ \-n "${OPENAI\_API\_KEY:-}" \]\]; then  
        openai\_env="  
  OPENAI\_API\_KEY: \\"\\${OPENAI\_API\_KEY}\\""  
    fi  
    if \[\[ "${SERVICE\_OLLAMA\_ENABLED:-false}" \!= "true" \]\]; then  
        ollama\_url=""  
    fi

    local auth\_env="WEBUI\_AUTH: \\"${OPEN\_WEBUI\_ENABLE\_AUTH:-true}\\""

    cat \>\> "$COMPOSE\_FILE" \<\< EOF

open-webui: image: ${OPEN\_WEBUI\_IMAGE:-ghcr.io/open-webui/open-webui:main} container\_name: open-webui restart: unless-stopped networks: \[ai-platform\]${webui\_depends} ports: \- "127.0.0.1:${PORT\_OPEN\_WEBUI:-3000}:8080" volumes: \- open-webui-data:/app/backend/data environment: ${ollama\_url:+OLLAMA\_BASE\_URL: "[http://ollama:11434"}](http://ollama:11434%22%7D/) WEBUI\_SECRET\_KEY: "${OPEN\_WEBUI\_SECRET\_KEY}" ${auth\_env} PORT: "8080"${rag\_env}${openai\_env} healthcheck: test: \["CMD-SHELL", "curl \-sf [http://localhost:8080/](http://localhost:8080/) || exit 1"\] interval: 20s timeout: 10s retries: 15 start\_period: 60s logging: driver: json-file options: {max-size: "20m", max-file: "3"} EOF fi

log "docker-compose.yml generated: ${COMPOSE\_FILE}"

}

# **── Ordered deployment ────────────────────────────────────────────────────────**

deploy\_services() { section "Deploying Services"

\# Ensure network exists  
if \! docker network ls \--format '{{.Name}}' | grep \-q '^ai-platform$'; then  
    docker network create \\  
        \--driver bridge \\  
        \--subnet 172.20.0.0/16 \\  
        ai-platform  
    log "Created docker network: ai-platform"  
fi

\# ── Tier 1: stateful infrastructure ──────────────────────────────────────  
local tier1=()  
\[\[ "${SERVICE\_REDIS\_ENABLED:-false}"  \== "true" \]\] && tier1+=(redis)  
\[\[ "${SERVICE\_QDRANT\_ENABLED:-false}" \== "true" \]\] && tier1+=(qdrant)  
\[\[ "${SERVICE\_OLLAMA\_ENABLED:-false}" \== "true" \]\] && tier1+=(ollama)  
\[\[ "${SERVICE\_LANGFUSE\_ENABLED:-false}" \== "true" \]\] && tier1+=(langfuse-db)

if \[\[ ${\#tier1\[@\]} \-gt 0 \]\]; then  
    log "Starting tier 1: ${tier1\[\*\]}"  
    docker compose \-f "$COMPOSE\_FILE" up \-d "${tier1\[@\]}"  
    wait\_for\_tier "Infrastructure" "${tier1\[@\]}" || true  
fi

\# ── Tier 2: application services ─────────────────────────────────────────  
local tier2=()  
\[\[ "${SERVICE\_SEARXNG\_ENABLED:-false}" \== "true" \]\] && tier2+=(searxng)  
\[\[ "${SERVICE\_FLOWISE\_ENABLED:-false}" \== "true" \]\] && tier2+=(flowise)  
\[\[ "${SERVICE\_N8N\_ENABLED:-false}"     \== "true" \]\] && tier2+=(n8n)

if \[\[ ${\#tier2\[@\]} \-gt 0 \]\]; then  
    log "Starting tier 2: ${tier2\[\*\]}"  
    docker compose \-f "$COMPOSE\_FILE" up \-d "${tier2\[@\]}"  
    wait\_for\_tier "Application Services" "${tier2\[@\]}" || true  
fi

\# ── Tier 3: DB-backed services ────────────────────────────────────────────  
local tier3=()  
\[\[ "${SERVICE\_LANGFUSE\_ENABLED:-false}" \== "true" \]\] && tier3+=(langfuse-web langfuse-worker)

if \[\[ ${\#tier3\[@\]} \-gt 0 \]\]; then  
    log "Starting tier 3: ${tier3\[\*\]}"  
    docker compose \-f "$COMPOSE\_FILE" up \-d "${tier3\[@\]}"  
    wait\_for\_tier "Langfuse" "${tier3\[@\]}" || true  
fi

\# ── Tier 4: frontends ─────────────────────────────────────────────────────  
local tier4=()  
\[\[ "${SERVICE\_OPEN\_WEBUI\_ENABLED:-false}" \== "true" \]\] && tier4+=(open-webui)

if \[\[ ${\#tier4\[@\]} \-gt 0 \]\]; then  
    log "Starting tier 4: ${tier4\[\*\]}"  
    docker compose \-f "$COMPOSE\_FILE" up \-d "${tier4\[@\]}"  
    wait\_for\_tier "Frontend" "${tier4\[@\]}" || true  
fi

}

# **── Status report ─────────────────────────────────────────────────────────────**

deployment\_report() { section "Deployment Report"

docker compose \-f "$COMPOSE\_FILE" ps \--format \\  
    "table {{.Name}}\\t{{.Status}}\\t{{.Ports}}" 2\>/dev/null || \\  
docker compose \-f "$COMPOSE\_FILE" ps

}

# **── Main ──────────────────────────────────────────────────────────────────────**

main() { log "=== SERVICE DEPLOYMENT \===" \[\[ $EUID \-ne 0 \]\] && err "Must run as root"

load\_env  
generate\_searxng\_config  
generate\_compose  
deploy\_services  
deployment\_report

log ""  
log "=== DEPLOYMENT COMPLETE \==="  
log "Next: sudo bash 3-configure-services.sh"

}

main "$@"

\#\!/bin/bash

# **3-configure-services.sh**

# **Reads /opt/ai-platform/.env produced by script 1**

# **Configures nginx for ONLY the services that are enabled AND running**

# **Handles all three deployment modes: local / domain / cloudflare**

set \-euo pipefail

RED='\\033\[0;31m' GREEN='\\033\[0;32m' YELLOW='\\033\[1;33m' BLUE='\\033\[0;34m' CYAN='\\033\[0;36m' BOLD='\\033\[1m' NC='\\033\[0m'

log() { echo \-e "${GREEN}\[$(date '+%H:%M:%S')\] INFO${NC} $*"; } warn() { echo \-e "${YELLOW}\[$(date '+%H:%M:%S')\] WARN${NC} $*"; } err() { echo \-e "${RED}\[$(date '+%H:%M:%S')\] ERROR${NC} $*"; exit 1; } section() { echo \-e "\\n${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\\n $*\\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; } ok() { echo \-e "${GREEN}\[$(date '+%H:%M:%S')\] ✓${NC} $*"; } skip() { echo \-e "${CYAN}\[$(date '+%H:%M:%S')\] ○${NC} $* (skipped \- not enabled/running)"; }

PLATFORM\_DIR="/opt/ai-platform" ENV\_FILE="${PLATFORM\_DIR}/.env" COMPOSE\_FILE="${PLATFORM\_DIR}/docker-compose.yml" NGINX\_CONF="/etc/nginx/conf.d/ai-platform.conf" NGINX\_CONF\_BACKUP="/etc/nginx/conf.d/ai-platform.conf.bak"

# **─────────────────────────────────────────────────────────────────────────────**

# **0\. Guards**

# **─────────────────────────────────────────────────────────────────────────────**

\[\[ $EUID \-ne 0 \]\] && err "Must run as root (sudo bash 3-configure-services.sh)" \[\[ \-f "$ENV\_FILE" \]\] || err "Config file not found: ${ENV\_FILE}\\nRun script 1 first." \[\[ \-f "$COMPOSE\_FILE" \]\] || err "Compose file not found: ${COMPOSE\_FILE}\\nRun script 2 first."

# **─────────────────────────────────────────────────────────────────────────────**

# **1\. Load environment**

# **─────────────────────────────────────────────────────────────────────────────**

load\_env() { section "Loading Configuration" set \-a \# shellcheck source=/dev/null source "$ENV\_FILE" set \+a

\# Normalise booleans \- treat any non-"true" value as false  
\_bool() { \[\[ "${1:-false}" \== "true" \]\] && echo true || echo false; }

SERVICE\_OLLAMA\_ENABLED=$(   \_bool "${SERVICE\_OLLAMA\_ENABLED:-false}")  
SERVICE\_OPEN\_WEBUI\_ENABLED=$(\_bool "${SERVICE\_OPEN\_WEBUI\_ENABLED:-false}")  
SERVICE\_FLOWISE\_ENABLED=$(  \_bool "${SERVICE\_FLOWISE\_ENABLED:-false}")  
SERVICE\_N8N\_ENABLED=$(      \_bool "${SERVICE\_N8N\_ENABLED:-false}")  
SERVICE\_LANGFUSE\_ENABLED=$( \_bool "${SERVICE\_LANGFUSE\_ENABLED:-false}")  
SERVICE\_QDRANT\_ENABLED=$(   \_bool "${SERVICE\_QDRANT\_ENABLED:-false}")  
SERVICE\_REDIS\_ENABLED=$(    \_bool "${SERVICE\_REDIS\_ENABLED:-false}")  
SERVICE\_SEARXNG\_ENABLED=$(  \_bool "${SERVICE\_SEARXNG\_ENABLED:-false}")

log "Deployment mode : ${DEPLOYMENT\_MODE:-local}"  
log "Base domain     : ${BASE\_DOMAIN:-${SERVER\_IP}}"  
log "SSL enabled     : ${USE\_SSL:-false}"  
log "Cloudflare      : ${USE\_CLOUDFLARE\_TUNNEL:-false}"

}

# **─────────────────────────────────────────────────────────────────────────────**

# **2\. Service readiness helpers**

# **─────────────────────────────────────────────────────────────────────────────**

# **Returns 0 if container exists and is in running state**

container\_running() { local name="$1" local state state=$(docker inspect \--format='{{.State.Status}}' "$name" 2\>/dev/null) || return 1 \[\[ "$state" \== "running" \]\] }

# **Returns 0 if a TCP port on 127.0.0.1 accepts connections**

port\_open() { local port="$1" timeout 2 bash \-c "\>/dev/tcp/127.0.0.1/${port}" 2\>/dev/null }

# **Waits up to $3 seconds for a port to open, checking every 5s**

wait\_for\_port() { local label="$1" local port="$2" local max\_wait="${3:-120}" local elapsed=0

while \[\[ $elapsed \-lt $max\_wait \]\]; do  
    if port\_open "$port"; then  
        ok "${label} responding on port ${port}"  
        return 0  
    fi  
    log "  Waiting for ${label} on port ${port} (${elapsed}s / ${max\_wait}s)"  
    sleep 5  
    elapsed=$((elapsed \+ 5))  
done  
warn "${label}: port ${port} not reachable after ${max\_wait}s"  
return 1

}

# **Master readiness check \- builds the ACTIVE\_SERVICES array used throughout**

check\_service\_readiness() { section "Service Readiness Check"

\# Map: env\_key → container\_name, host\_port, display\_name  
\# Format: "container\_name:host\_port:display\_name"  
declare \-gA SVC\_META=(  
    \[ollama\]="ollama:${PORT\_OLLAMA:-11434}:Ollama"  
    \[open\_webui\]="open-webui:${PORT\_OPEN\_WEBUI:-3000}:Open WebUI"  
    \[flowise\]="flowise:${PORT\_FLOWISE:-3001}:Flowise"  
    \[n8n\]="n8n:${PORT\_N8N:-5678}:n8n"  
    \[langfuse\]="langfuse-web:${PORT\_LANGFUSE:-8080}:Langfuse"  
    \[qdrant\]="qdrant:${PORT\_QDRANT:-6333}:Qdrant"  
    \[redis\]="redis:${PORT\_REDIS:-6379}:Redis"  
    \[searxng\]="searxng:${PORT\_SEARXNG:-8081}:SearXNG"  
)

\# ACTIVE\_SERVICES \= services that are enabled in .env AND container is running  
declare \-gA ACTIVE\_SERVICES=()

for svc\_key in "${\!SVC\_META\[@\]}"; do  
    local flag\_var="SERVICE\_${svc\_key^^}\_ENABLED"  
    \# open\_webui \-\> OPEN\_WEBUI  
    flag\_var="${flag\_var/OPEN/OPEN}"  
    local enabled="${\!flag\_var:-false}"  
    IFS=':' read \-r container port label \<\<\< "${SVC\_META\[$svc\_key\]}"

    if \[\[ "$enabled" \!= "true" \]\]; then  
        skip "$label"  
        continue  
    fi

    if \! container\_running "$container"; then  
        warn "${label}: enabled but container '${container}' is not running"  
        warn "       Try: docker compose \-f ${COMPOSE\_FILE} up \-d ${container}"  
        continue  
    fi

    \# Give running containers a short grace period then check port  
    if wait\_for\_port "$label" "$port" 30; then  
        ACTIVE\_SERVICES\[$svc\_key\]="${SVC\_META\[$svc\_key\]}"  
        ok "${label}: active at 127.0.0.1:${port}"  
    else  
        warn "${label}: container running but port ${port} not responding"  
        warn "       Adding to nginx anyway \- may become available later"  
        ACTIVE\_SERVICES\[$svc\_key\]="${SVC\_META\[$svc\_key\]}"  
    fi  
done

if \[\[ ${\#ACTIVE\_SERVICES\[@\]} \-eq 0 \]\]; then  
    err "No services are running. Run script 2 first."  
fi

log ""  
log "Active services: ${\#ACTIVE\_SERVICES\[@\]}"  
for k in "${\!ACTIVE\_SERVICES\[@\]}"; do  
    IFS=':' read \-r \_ \_ label \<\<\< "${ACTIVE\_SERVICES\[$k\]}"  
    log "  ✓ ${label}"  
done

}

# **─────────────────────────────────────────────────────────────────────────────**

# **3\. Nginx shared map block (written once to a separate file)**

# **─────────────────────────────────────────────────────────────────────────────**

write\_nginx\_map\_conf() { local map\_file="/etc/nginx/conf.d/ai-platform-map.conf"

cat \> "$map\_file" \<\< 'EOF'

# **AI Platform \- shared map \- generated by 3-configure-services.sh**

map $http\_upgrade $connection\_upgrade { default upgrade; '' close; } EOF log "Nginx map block written: ${map\_file}" }

# **─────────────────────────────────────────────────────────────────────────────**

# **4\. Nginx config generators**

# **Each function appends one server block to the config file.**

# **They are ONLY called when the service is in ACTIVE\_SERVICES.**

# **─────────────────────────────────────────────────────────────────────────────**

# **── Helper: build the proxy\_pass block (shared between all services) ──────────**

\_proxy\_params() { local upstream="$1" cat \<\< EOF proxy\_pass ${upstream}; proxy\_http\_version 1.1; proxy\_set\_header Upgrade $http\_upgrade; proxy\_set\_header Connection $connection\_upgrade; proxy\_set\_header Host $host; proxy\_set\_header X-Real-IP $remote\_addr; proxy\_set\_header X-Forwarded-For $proxy\_add\_x\_forwarded\_for; proxy\_set\_header X-Forwarded-Proto $scheme; proxy\_read\_timeout 300s; proxy\_buffering off; EOF }

# **── Helper: derive listen directives based on deployment mode ─────────────────**

\_listen\_directives() { local port="$1" \# host port local ssl="${2:-false}" local cert="$3" local key="$4"

if \[\[ "$ssl" \== "true" \]\] && \[\[ \-f "$cert" \]\] && \[\[ \-f "$key" \]\]; then  
    cat \<\< EOF  
listen ${port} ssl;  
listen \[::\]:${port} ssl;  
ssl\_certificate     ${cert};  
ssl\_certificate\_key ${key};  
ssl\_protocols       TLSv1.2 TLSv1.3;  
ssl\_ciphers         HIGH:\!aNULL:\!MD5;

EOF else cat \<\< EOF listen ${port}; listen \[::\]:${port}; EOF fi }

# **── LOCAL MODE: port-based server blocks, no hostname needed ──────────────────**

write\_nginx\_local() { section "Writing Nginx Config (local / port-based)"

local conf="$NGINX\_CONF"  
: \> "$conf"   \# truncate

cat \>\> "$conf" \<\< EOF

# **AI Platform \- local port-based config**

# **Generated: $(date \-u \+"%Y-%m-%dT%H:%M:%SZ")**

# **Mode: local**

EOF

\# Ollama  
if \[\[ \-v ACTIVE\_SERVICES\[ollama\] \]\]; then  
    cat \>\> "$conf" \<\< EOF

server { listen 127.0.0.1:${PORT\_OLLAMA:-11434}; server\_name \_; location / { $(\_proxy\_params "[http://127.0.0.1:${PORT\_OLLAMA:-11434}](http://127.0.0.1:${port_ollama:-11434%7D/)") } } EOF ok "Nginx block: Ollama" fi

\# Open WebUI  
if \[\[ \-v ACTIVE\_SERVICES\[open\_webui\] \]\]; then  
    cat \>\> "$conf" \<\< EOF

server { $(\_listen\_directives "${PORT\_OPEN\_WEBUI:-3000}" false) server\_name \_; client\_max\_body\_size 100M;

location / {

$(\_proxy\_params "[http://127.0.0.1:${PORT\_OPEN\_WEBUI:-3000}](http://127.0.0.1:${port_open_webui:-3000%7D/)") } } EOF ok "Nginx block: Open WebUI" fi

\# Flowise  
if \[\[ \-v ACTIVE\_SERVICES\[flowise\] \]\]; then  
    cat \>\> "$conf" \<\< EOF

server { $(\_listen\_directives "${PORT\_FLOWISE:-3001}" false) server\_name \_; client\_max\_body\_size 50M;

location / {

$(\_proxy\_params "[http://127.0.0.1:${PORT\_FLOWISE:-3001}](http://127.0.0.1:${port_flowise:-3001%7D/)") } } EOF ok "Nginx block: Flowise" fi

\# n8n  
if \[\[ \-v ACTIVE\_SERVICES\[n8n\] \]\]; then  
    cat \>\> "$conf" \<\< EOF

server { $(\_listen\_directives "${PORT\_N8N:-5678}" false) server\_name \_;

location / {

$(\_proxy\_params "[http://127.0.0.1:${PORT\_N8N:-5678}](http://127.0.0.1:${port_n8n:-5678%7D/)") }

location /webhook {

$(\_proxy\_params "[http://127.0.0.1:${PORT\_N8N:-5678}/webhook](http://127.0.0.1:${port_n8n:-5678%7D/webhook)") } } EOF ok "Nginx block: n8n" fi

\# Langfuse  
if \[\[ \-v ACTIVE\_SERVICES\[langfuse\] \]\]; then  
    cat \>\> "$conf" \<\< EOF

server { $(\_listen\_directives "${PORT\_LANGFUSE:-8080}" false) server\_name \_; client\_max\_body\_size 20M;

location / {

$(\_proxy\_params "[http://127.0.0.1:${PORT\_LANGFUSE:-8080}](http://127.0.0.1:${port_langfuse:-8080%7D/)") } } EOF ok "Nginx block: Langfuse" fi

\# Qdrant  
if \[\[ \-v ACTIVE\_SERVICES\[qdrant\] \]\]; then  
    cat \>\> "$conf" \<\< EOF

server { $(\_listen\_directives "${PORT\_QDRANT:-6333}" false) server\_name \_;

location / {

$(\_proxy\_params "[http://127.0.0.1:${PORT\_QDRANT:-6333}](http://127.0.0.1:${port_qdrant:-6333%7D/)") } } EOF ok "Nginx block: Qdrant" fi

\# SearXNG  
if \[\[ \-v ACTIVE\_SERVICES\[searxng\] \]\]; then  
    cat \>\> "$conf" \<\< EOF

server { $(\_listen\_directives "${PORT\_SEARXNG:-8081}" false) server\_name \_;

location / {

$(\_proxy\_params "[http://127.0.0.1:${PORT\_SEARXNG:-8081}](http://127.0.0.1:${port_searxng:-8081%7D/)") } } EOF ok "Nginx block: SearXNG" fi }

# **── DOMAIN MODE: subdomain-based server blocks ────────────────────────────────**

write\_nginx\_domain() { section "Writing Nginx Config (domain / subdomain-based)"

local ssl="${USE\_SSL:-false}"  
local domain="${BASE\_DOMAIN}"  
local conf="$NGINX\_CONF"  
: \> "$conf"

\# Cert paths (certbot convention)  
local cert="/etc/letsencrypt/live/${domain}/fullchain.pem"  
local key="/etc/letsencrypt/live/${domain}/privkey.pem"

\# If SSL requested but certs missing, warn and fall back to HTTP  
if \[\[ "$ssl" \== "true" \]\] && { \[\[ \! \-f "$cert" \]\] || \[\[ \! \-f "$key" \]\]; }; then  
    warn "SSL certificates not found at ${cert}"  
    warn "Falling back to HTTP. Run certbot then re-run this script."  
    ssl=false  
fi

cat \>\> "$conf" \<\< EOF

# **AI Platform \- domain/subdomain config**

# **Generated: $(date \-u \+"%Y-%m-%dT%H:%M:%SZ")**

# **Mode: domain Base: ${domain} SSL: ${ssl}**

EOF

\# Helper: one server block per subdomain  
\_domain\_server\_block() {  
    local subdomain="$1"  
    local upstream\_port="$2"  
    local extra\_location="${3:-}"  
    local client\_max="${4:-10M}"

    local fqdn="${subdomain}.${domain}"

    cat \>\> "$conf" \<\< EOF

# **── ${fqdn} ────────────────────────────────────────────────────────────────**

EOF

   \# HTTP → HTTPS redirect if SSL  
    if \[\[ "$ssl" \== "true" \]\]; then  
        cat \>\> "$conf" \<\< EOF

server { listen 80; listen \[::\]:80; server\_name ${fqdn}; return 301 https://$host$request\_uri; } EOF fi

   cat \>\> "$conf" \<\< EOF

server { $(\_listen\_directives "$(\[ "$ssl" \== "true" \] && echo 443 || echo 80)" "$ssl" "$cert" "$key") server\_name ${fqdn}; client\_max\_body\_size ${client\_max};

location / {

$(\_proxy\_params "[http://127.0.0.1:${upstream\_port}](http://127.0.0.1:$%7Bupstream_port%7D/)") } ${extra\_location} } EOF }

\[\[ \-v ACTIVE\_SERVICES\[ollama\] \]\]    && \_domain\_server\_block "ollama"    "${PORT\_OLLAMA:-11434}"  
\[\[ \-v ACTIVE\_SERVICES\[open\_webui\] \]\] && \_domain\_server\_block "chat"     "${PORT\_OPEN\_WEBUI:-3000}" "" "100M"  
\[\[ \-v ACTIVE\_SERVICES\[flowise\] \]\]   && \_domain\_server\_block "flowise"   "${PORT\_FLOWISE:-3001}"   "" "50M"  
\[\[ \-v ACTIVE\_SERVICES\[n8n\] \]\]       && \_domain\_server\_block "n8n"       "${PORT\_N8N:-5678}"       \\

" location /webhook { $(\_proxy\_params "[http://127.0.0.1:${PORT\_N8N:-5678}/webhook](http://127.0.0.1:${port_n8n:-5678%7D/webhook)") }" \[\[ \-v ACTIVE\_SERVICES\[langfuse\] \]\] && \_domain\_server\_block "langfuse" "${PORT\_LANGFUSE:-8080}" "" "20M" \[\[ \-v ACTIVE\_SERVICES\[qdrant\] \]\] && \_domain\_server\_block "qdrant" "${PORT\_QDRANT:-6333}" \[\[ \-v ACTIVE\_SERVICES\[searxng\] \]\] && \_domain\_server\_block "search" "${PORT\_SEARXNG:-8081}"

ok "Domain nginx config written for ${domain}"

}

# **── CLOUDFLARE TUNNEL MODE: localhost-only, no public ports ───────────────────**

write\_nginx\_cloudflare() { section "Writing Nginx Config (Cloudflare Tunnel mode)"

\# In tunnel mode nginx only needs to proxy from localhost ports  
\# The cloudflared daemon handles external TLS and routing  
\# We write the same as local mode but also deploy cloudflared container

write\_nginx\_local

configure\_cloudflare\_tunnel

}

configure\_cloudflare\_tunnel() { section "Configuring Cloudflare Tunnel"

local domain="${BASE\_DOMAIN}"  
local token="${CLOUDFLARE\_TUNNEL\_TOKEN:-}"

if \[\[ \-z "$token" \]\]; then  
    err "CLOUDFLARE\_TUNNEL\_TOKEN is not set in ${ENV\_FILE}"  
fi

\# Build ingress rules only for active services  
local ingress\_rules=""

\_cf\_ingress() {  
    local subdomain="$1"  
    local port="$2"  
    ingress\_rules+="  \- hostname: ${subdomain}.${domain}\\n"  
    ingress\_rules+="    service: http://localhost:${port}\\n"  
}

\[\[ \-v ACTIVE\_SERVICES\[open\_webui\] \]\] && \_cf\_ingress "chat"    "${PORT\_OPEN\_WEBUI:-3000}"  
\[\[ \-v ACTIVE\_SERVICES\[flowise\] \]\]    && \_cf\_ingress "flowise" "${PORT\_FLOWISE:-3001}"  
\[\[ \-v ACTIVE\_SERVICES\[n8n\] \]\]        && \_cf\_ingress "n8n"     "${PORT\_N8N:-5678}"  
\[\[ \-v ACTIVE\_SERVICES\[langfuse\] \]\]   && \_cf\_ingress "langfuse" "${PORT\_LANGFUSE:-8080}"  
\[\[ \-v ACTIVE\_SERVICES\[qdrant\] \]\]     && \_cf\_ingress "qdrant"  "${PORT\_QDRANT:-6333}"  
\[\[ \-v ACTIVE\_SERVICES\[searxng\] \]\]    && \_cf\_ingress "search"  "${PORT\_SEARXNG:-8081}"  
\[\[ \-v ACTIVE\_SERVICES\[ollama\] \]\]     && \_cf\_ingress "ollama"  "${PORT\_OLLAMA:-11434}"

\# Catch-all must be last  
ingress\_rules+="  \- service: http\_status:404\\n"

local cf\_config\_dir="${PLATFORM\_DIR}/configs/cloudflared"  
mkdir \-p "$cf\_config\_dir"

cat \> "${cf\_config\_dir}/config.yml" \<\< EOF

# **Cloudflare Tunnel config \- generated by 3-configure-services.sh**

tunnel: ai-platform credentials-file: /etc/cloudflared/creds.json

ingress: $(printf '%b' "$ingress\_rules") EOF

log "Cloudflare tunnel config written: ${cf\_config\_dir}/config.yml"

\# Check if cloudflared container is already running  
if container\_running "cloudflared"; then  
    log "Restarting cloudflared container"  
    docker restart cloudflared  
else  
    log "Starting cloudflared container"  
    docker run \-d \\  
        \--name cloudflared \\  
        \--network ai-platform \\  
        \--restart unless-stopped \\  
        \-v "${cf\_config\_dir}:/etc/cloudflared:ro" \\  
        cloudflare/cloudflared:latest \\  
        tunnel \--no-autoupdate run \--token "${token}" \\  
        2\>&1 | tail \-5  
fi

ok "Cloudflare tunnel configured"

}

# **─────────────────────────────────────────────────────────────────────────────**

# **5\. Apply nginx config**

# **─────────────────────────────────────────────────────────────────────────────**

apply\_nginx() { section "Applying Nginx Configuration"

\# Back up existing config if present  
if \[\[ \-f "$NGINX\_CONF" \]\]; then  
    cp "$NGINX\_CONF" "$NGINX\_CONF\_BACKUP"  
    log "Backup: ${NGINX\_CONF\_BACKUP}"  
fi

\# Test  
if \! nginx \-t 2\>&1; then  
    err "Nginx config test FAILED. Restoring backup."  
    \[\[ \-f "$NGINX\_CONF\_BACKUP" \]\] && cp "$NGINX\_CONF\_BACKUP" "$NGINX\_CONF"  
    nginx \-t   \# show error in context  
    exit 1  
fi

ok "Nginx config test passed"  
systemctl reload nginx  
ok "Nginx reloaded"

}

# **─────────────────────────────────────────────────────────────────────────────**

# **6\. Post-deploy: Ollama model pull**

# **─────────────────────────────────────────────────────────────────────────────**

configure\_ollama\_models() { \[\[ "${SERVICE\_OLLAMA\_ENABLED:-false}" \!= "true" \]\] && return \[\[ \-v ACTIVE\_SERVICES\[ollama\] \]\] || return

section "Ollama Model Configuration"

\# Count currently available models  
local model\_count  
model\_count=$(docker exec ollama ollama list 2\>/dev/null | tail \-n \+2 | wc \-l || echo "0")

log "Models currently available: ${model\_count}"

\# Auto-pull model specified in .env during wizard  
if \[\[ \-n "${OLLAMA\_DEFAULT\_MODEL:-}" \]\]; then  
    log "Auto-pulling model from wizard config: ${OLLAMA\_DEFAULT\_MODEL}"  
    if docker exec ollama ollama pull "${OLLAMA\_DEFAULT\_MODEL}"; then  
        ok "Model pulled: ${OLLAMA\_DEFAULT\_MODEL}"  
    else  
        warn "Model pull failed for ${OLLAMA\_DEFAULT\_MODEL}"  
        warn "Retry manually: docker exec ollama ollama pull ${OLLAMA\_DEFAULT\_MODEL}"  
    fi  
    return  
fi

if \[\[ $model\_count \-gt 0 \]\]; then  
    log "Models already present \- skipping auto-pull"  
    docker exec ollama ollama list  
    return  
fi

\# No model configured and none present \- advise user  
warn "No models are installed in Ollama."  
warn "Pull a model with:"  
warn "  docker exec ollama ollama pull llama3.2:3b"  
warn "  docker exec ollama ollama pull nomic-embed-text"

}

# **─────────────────────────────────────────────────────────────────────────────**

# **7\. Post-deploy: SSL provisioning (domain mode)**

# **─────────────────────────────────────────────────────────────────────────────**

provision\_ssl() { \[\[ "${USE\_SSL:-false}" \!= "true" \]\] && return \[\[ "${DEPLOYMENT\_MODE:-local}" \!= "domain" \]\] && return

section "SSL Certificate Provisioning"

local domain="${BASE\_DOMAIN}"

if \! command \-v certbot &\>/dev/null; then  
    warn "certbot not found. Install with: apt install certbot python3-certbot-nginx"  
    warn "Then run: certbot \--nginx \-d ${domain} \-d chat.${domain} ..."  
    return  
fi

\# Build \-d arguments for every active subdomain  
local certbot\_domains="-d ${domain}"  
local \-A subdomain\_map=(  
    \[open\_webui\]="chat"  
    \[flowise\]="flowise"  
    \[n8n\]="n8n"  
    \[langfuse\]="langfuse"  
    \[qdrant\]="qdrant"  
    \[searxng\]="search"  
    \[ollama\]="ollama"  
)

for svc in "${\!subdomain\_map\[@\]}"; do  
    \[\[ \-v ACTIVE\_SERVICES\[$svc\] \]\] && \\  
        certbot\_domains+=" \-d ${subdomain\_map\[$svc\]}.${domain}"  
done

log "Requesting certificate for: ${certbot\_domains}"

if certbot \--nginx ${certbot\_domains} \\  
    \--non-interactive \\  
    \--agree-tos \\  
    \--email "${CERTBOT\_EMAIL:-admin@${domain}}" \\  
    \--redirect; then  
    ok "SSL certificates issued"  
else  
    warn "certbot failed. You may need to:"  
    warn "  1\. Ensure DNS A records point to this server"  
    warn "  2\. Ensure port 80 is open"  
    warn "  3\. Run certbot manually"  
fi

}

# **─────────────────────────────────────────────────────────────────────────────**

# **8\. Cross-service configuration**

# **Injects runtime connection details between services**

# **─────────────────────────────────────────────────────────────────────────────**

configure\_cross\_service() { section "Cross-Service Configuration"

\# Open WebUI → SearXNG  
if \[\[ \-v ACTIVE\_SERVICES\[open\_webui\] \]\] && \[\[ \-v ACTIVE\_SERVICES\[searxng\] \]\]; then  
    log "Open WebUI: SearXNG RAG already configured via compose env"  
    ok "Open WebUI ↔ SearXNG: connected"  
fi

\# Open WebUI → Ollama  
if \[\[ \-v ACTIVE\_SERVICES\[open\_webui\] \]\] && \[\[ \-v ACTIVE\_SERVICES\[ollama\] \]\]; then  
    ok "Open WebUI ↔ Ollama: connected (via docker network)"  
fi

\# Flowise → Ollama  
if \[\[ \-v ACTIVE\_SERVICES\[flowise\] \]\] && \[\[ \-v ACTIVE\_SERVICES\[ollama\] \]\]; then  
    log "Flowise → Ollama endpoint: http://ollama:${PORT\_OLLAMA:-11434}"  
    ok "Flowise ↔ Ollama: connection details logged"  
fi

\# n8n → Ollama  
if \[\[ \-v ACTIVE\_SERVICES\[n8n\] \]\] && \[\[ \-v ACTIVE\_SERVICES\[ollama\] \]\]; then  
    log "n8n → Ollama endpoint: http://ollama:${PORT\_OLLAMA:-11434}"  
    ok "n8n ↔ Ollama: connection details logged"  
fi

\# Langfuse → verify DB migration completed  
if \[\[ \-v ACTIVE\_SERVICES\[langfuse\] \]\]; then  
    log "Checking Langfuse DB migration status..."  
    local max=12  
    local attempt=0  
    while \[\[ $attempt \-lt $max \]\]; do  
        if docker exec langfuse-web \\  
            curl \-sf http://localhost:3000/api/public/health \\  
                \-o /dev/null 2\>/dev/null; then  
            ok "Langfuse API health check passed"  
            break  
        fi  
        attempt=$((attempt \+ 1))  
        log "  Waiting for Langfuse health endpoint (${attempt}/${max})"  
        sleep 10  
    done  
    \[\[ $attempt \-ge $max \]\] && \\  
        warn "Langfuse health endpoint not responding yet \- migrations may still be running"  
fi

}

# **─────────────────────────────────────────────────────────────────────────────**

# **9\. Firewall rules (ufw \- only if active)**

# **─────────────────────────────────────────────────────────────────────────────**

configure\_firewall() { section "Firewall Configuration"

if \! command \-v ufw &\>/dev/null || \! ufw status | grep \-q "Status: active"; then  
    log "ufw not active \- skipping firewall config"  
    return  
fi

local mode="${DEPLOYMENT\_MODE:-local}"

\# Always allow SSH  
ufw allow ssh &\>/dev/null || true

\# Allow nginx HTTP/HTTPS  
ufw allow 'Nginx Full' &\>/dev/null || true

if \[\[ "$mode" \== "local" \]\]; then  
    \# Allow individual service ports for local access  
    local ports=(  
        "${PORT\_OPEN\_WEBUI:-3000}"  
        "${PORT\_FLOWISE:-3001}"  
        "${PORT\_N8N:-5678}"  
        "${PORT\_LANGFUSE:-8080}"  
        "${PORT\_QDRANT:-6333}"  
        "${PORT\_SEARXNG:-8081}"  
    )

    for port in "${ports\[@\]}"; do  
        ufw allow "$port/tcp" &\>/dev/null || true  
    done  
    ok "ufw: opened local service ports"

elif \[\[ "$mode" \== "cloudflare" \]\]; then  
    \# Cloudflare tunnel \- only allow SSH \+ outbound  
    \# All service ports should be on 127.0.0.1 only  
    ok "ufw: Cloudflare tunnel mode \- no additional ports opened"  
fi

log "Firewall status:"  
ufw status numbered 2\>/dev/null | head \-20 || true

}

# **─────────────────────────────────────────────────────────────────────────────**

# **10\. Write service connection manifest**

# **Machine-readable file consumed by script 4 when adding new services**

# **─────────────────────────────────────────────────────────────────────────────**

write\_service\_manifest() { local manifest="${PLATFORM\_DIR}/service-manifest.env"

cat \> "$manifest" \<\< EOF

# **AI Platform Service Manifest**

# **Generated: $(date \-u \+"%Y-%m-%dT%H:%M:%SZ")**

# **Used by script 4 (add-service) and monitoring**

MANIFEST\_GENERATED=$(date \-u \+"%Y-%m-%dT%H:%M:%SZ") DEPLOYMENT\_MODE=${DEPLOYMENT\_MODE:-local} BASE\_DOMAIN=${BASE\_DOMAIN:-${SERVER\_IP:-localhost}} USE\_SSL=${USE\_SSL:-false}

# **Active services at time of last configure run**

$(for k in "${\!ACTIVE\_SERVICES\[@\]}"; do IFS=':' read \-r container port label \<\<\< "${ACTIVE\_SERVICES\[$k\]}" echo "ACTIVE\_${k^^}=true" echo "ACTIVE\_${k^^}*PORT=${port}" echo "ACTIVE*${k^^}\_CONTAINER=${container}" done) EOF

chmod 600 "$manifest"  
ok "Service manifest written: ${manifest}"

}

# **─────────────────────────────────────────────────────────────────────────────**

# **11\. Final access report**

# **─────────────────────────────────────────────────────────────────────────────**

access\_report() { section "Access URLs"

local mode="${DEPLOYMENT\_MODE:-local}"  
local ip="${SERVER\_IP:-$(hostname \-I | awk '{print $1}')}"  
local domain="${BASE\_DOMAIN:-$ip}"  
local proto="http"  
\[\[ "${USE\_SSL:-false}" \== "true" \]\] && proto="https"

echo ""  
echo \-e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"  
echo \-e "${BOLD}║             AI PLATFORM \- READY                                 ║${NC}"  
echo \-e "${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"

\_report\_line() {  
    local label="$1"  
    local url="$2"  
    printf "${BOLD}║${NC}  %-16s  ${CYAN}%-44s${NC}  ${BOLD}║${NC}\\n" "$label" "$url"  
}

if \[\[ "$mode" \== "local" \]\]; then  
    \[\[ \-v ACTIVE\_SERVICES\[open\_webui\] \]\] && \_report\_line "Open WebUI"  "http://${ip}:${PORT\_OPEN\_WEBUI:-3000}"  
    \[\[ \-v ACTIVE\_SERVICES\[flowise\] \]\]    && \_report\_line "Flowise"     "http://${ip}:${PORT\_FLOWISE:-3001}"  
    \[\[ \-v ACTIVE\_SERVICES\[n8n\] \]\]        && \_report\_line "n8n"         "http://${ip}:${PORT\_N8N:-5678}"  
    \[\[ \-v ACTIVE\_SERVICES\[langfuse\] \]\]   && \_report\_line "Langfuse"    "http://${ip}:${PORT\_LANGFUSE:-8080}"  
    \[\[ \-v ACTIVE\_SERVICES\[qdrant\] \]\]     && \_report\_line "Qdrant"      "http://${ip}:${PORT\_QDRANT:-6333}"  
    \[\[ \-v ACTIVE\_SERVICES\[searxng\] \]\]    && \_report\_line "SearXNG"     "http://${ip}:${PORT\_SEARXNG:-8081}"  
    \[\[ \-v ACTIVE\_SERVICES\[ollama\] \]\]     && \_report\_line "Ollama API"  "http://${ip}:${PORT\_OLLAMA:-11434}"  
else  
    \[\[ \-v ACTIVE\_SERVICES\[open\_webui\] \]\] && \_report\_line "Open WebUI"  "${proto}://chat.${domain}"  
    \[\[ \-v ACTIVE\_SERVICES\[flowise\] \]\]    && \_report\_line "Flowise"     "${proto}://flowise.${domain}"  
    \[\[ \-v ACTIVE\_SERVICES\[n8n\] \]\]        && \_report\_line "n8n"         "${proto}://n8n.${domain}"  
    \[\[ \-v ACTIVE\_SERVICES\[langfuse\] \]\]   && \_report\_line "Langfuse"    "${proto}://langfuse.${domain}"  
    \[\[ \-v ACTIVE\_SERVICES\[qdrant\] \]\]     && \_report\_line "Qdrant"      "${proto}://qdrant.${domain}"  
    \[\[ \-v ACTIVE\_SERVICES\[searxng\] \]\]    && \_report\_line "SearXNG"     "${proto}://search.${domain}"  
    \[\[ \-v ACTIVE\_SERVICES\[ollama\] \]\]     && \_report\_line "Ollama API"  "${proto}://ollama.${domain}"  
fi

echo \-e "${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"

\# Credentials summary  
if \[\[ "${N8N\_BASIC\_AUTH\_ENABLED:-false}" \== "true" \]\]; then  
    \_report\_line "n8n user"     "${N8N\_BASIC\_AUTH\_USER:-admin}"  
    \_report\_line "n8n pass"     "${N8N\_BASIC\_AUTH\_PASSWORD:-(see .env)}"  
fi  
if \[\[ "${FLOWISE\_AUTH\_ENABLED:-false}" \== "true" \]\]; then  
    \_report\_line "Flowise user" "${FLOWISE\_USERNAME:-admin}"  
    \_report\_line "Flowise pass" "${FLOWISE\_PASSWORD:-(see .env)}"  
fi

echo \-e "${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"  
printf "${BOLD}║${NC}  %-64s  ${BOLD}║${NC}\\n" "Credentials file: ${ENV\_FILE}"  
echo \-e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"  
echo ""

log "To add a new service later: sudo bash 4-add-service.sh"  
log "To check status:           docker compose \-f ${COMPOSE\_FILE} ps"

}

# **─────────────────────────────────────────────────────────────────────────────**

# **MAIN**

# **─────────────────────────────────────────────────────────────────────────────**

main() { section "AI Platform \- Service Configuration" log "Script 3 of 5"

load\_env  
check\_service\_readiness

write\_nginx\_map\_conf

case "${DEPLOYMENT\_MODE:-local}" in  
    local)      write\_nginx\_local      ;;  
    domain)     write\_nginx\_domain     ;;  
    cloudflare) write\_nginx\_cloudflare ;;  
    \*)          err "Unknown DEPLOYMENT\_MODE: ${DEPLOYMENT\_MODE}" ;;  
esac

apply\_nginx  
provision\_ssl  
configure\_ollama\_models  
configure\_cross\_service  
configure\_firewall  
write\_service\_manifest  
access\_report

ok "=== Configuration complete \==="

}

main "$@"

\#\!/bin/bash

# **4-add-service.sh**

# **Adds a single new service to an existing deployment.**

# **Reads .env \+ service-manifest.env, updates docker-compose,**

# **starts only the new container, then updates nginx.**

# **Does NOT touch running services.**

set \-euo pipefail

RED='\\033\[0;31m' GREEN='\\033\[0;32m' YELLOW='\\033\[1;33m' BLUE='\\033\[0;34m' CYAN='\\033\[0;36m' BOLD='\\033\[1m' NC='\\033\[0m'

log() { echo \-e "${GREEN}\[ $ (date '+%H:%M:%S')\] INFO $ {NC} $ \*"; } warn() { echo \-e " $ {YELLOW}\[ $ (date '+%H:%M:%S')\] WARN $ {NC} $ \*"; } err() { echo \-e " $ {RED}\[ $ (date '+%H:%M:%S')\] ERROR $ {NC} $ \*"; exit 1; } section() { echo \-e "\\n $ {BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\\n $ \*\\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ $ {NC}"; } ok() { echo \-e "${GREEN}\[ $ (date '+%H:%M:%S')\] ✓ $ {NC} $ \*"; }

PLATFORM\_DIR="/opt/ai-platform" ENV\_FILE=" $ {PLATFORM\_DIR}/.env" MANIFEST\_FILE="${PLATFORM\_DIR}/service-manifest.env" COMPOSE\_FILE="${PLATFORM\_DIR}/docker-compose.yml" NGINX\_CONF="/etc/nginx/conf.d/ai-platform.conf"

# **─────────────────────────────────────────────────────────────────────────────**

# **0\. Guards**

# **─────────────────────────────────────────────────────────────────────────────**

\[\[ $ EUID \-ne 0 \]\] && err "Must run as root" \[\[ \-f " $ ENV\_FILE" \]\] || err "Run script 1 first: ${ENV\_FILE} missing" \[\[ \-f "$MANIFEST\_FILE" \]\] || err "Run script 3 first: ${MANIFEST\_FILE} missing" \[\[ \-f "$COMPOSE\_FILE" \]\] || err "Run script 2 first: ${COMPOSE\_FILE} missing"

# **─────────────────────────────────────────────────────────────────────────────**

# **1\. Load both env files**

# **─────────────────────────────────────────────────────────────────────────────**

load\_env() { set \-a source " $ ENV\_FILE" source " $ MANIFEST\_FILE" set \+a log "Configuration loaded" log "Current deployment mode: ${DEPLOYMENT\_MODE:-local}" }

# **─────────────────────────────────────────────────────────────────────────────**

# **2\. Catalogue: what services exist vs what is currently active**

# **─────────────────────────────────────────────────────────────────────────────**

# **All known services with metadata**

# **Format: "display\_name:container\_name:host\_port:internal\_port:description"**

declare \-A ALL\_SERVICES=( \[ollama\]="Ollama:ollama:${PORT\_OLLAMA:-11434}:11434:Local LLM runtime" \[open\_webui\]="Open WebUI:open-webui:${PORT\_OPEN\_WEBUI:-3000}:8080:Chat interface" \[flowise\]="Flowise:flowise:${PORT\_FLOWISE:-3001}:3000:Visual flow builder" \[n8n\]="n8n:n8n:${PORT\_N8N:-5678}:5678:Workflow automation" \[langfuse\]="Langfuse:langfuse-web:${PORT\_LANGFUSE:-8080}:3000:LLM observability" \[qdrant\]="Qdrant:qdrant:${PORT\_QDRANT:-6333}:6333:Vector database" \[redis\]="Redis:redis:${PORT\_REDIS:-6379}:6379:Cache and queue" \[searxng\]="SearXNG:searxng:${PORT\_SEARXNG:-8081}:8080:Web search" )

container\_running() { local name=" $ 1" local state state= $ (docker inspect \--format='{{.State.Status}}' " $ name" 2\>/dev/null) || return 1 \[\[ " $ state" \== "running" \]\] }

enabled\_in\_env() { local svc=" $ 1" local flag\_var="SERVICE\_ $ {svc^^}\_ENABLED" \[\[ "${\!flag\_var:-false}" \== "true" \]\] }

# **Build list of services that are addable (not currently active)**

find\_addable\_services() { declare \-gA ADDABLE=()

for svc in "${\!ALL\_SERVICES\[@\]}"; do  
    IFS=':' read \-r display container port \_ desc \<\<\< "${ALL\_SERVICES\[ $ svc\]}"

    \# Skip if already enabled AND running  
    if enabled\_in\_env " $ svc" && container\_running " $ container"; then  
        continue  
    fi

    ADDABLE\[ $ svc\]="${ALL\_SERVICES\[$svc\]}"  
done

}

# **─────────────────────────────────────────────────────────────────────────────**

# **3\. Interactive service picker**

# **─────────────────────────────────────────────────────────────────────────────**

pick\_service() { section "Add New Service"

find\_addable\_services

if \[\[ ${\#ADDABLE\[@\]} \-eq 0 \]\]; then  
    log "All services are already running. Nothing to add."  
    exit 0  
fi

echo ""  
echo "  Services available to add:"  
echo ""  
printf "  %-4s %-15s %-10s %s\\n" "Num" "Service" "Port" "Description"  
printf "  %-4s %-15s %-10s %s\\n" "---" "-------" "----" "-----------"

\# Build ordered index for display  
local \-a svc\_index=()  
local i=1  
for svc in "${\!ADDABLE\[@\]}"; do  
    IFS=':' read \-r display \_ port \_ desc \<\<\< "${ADDABLE\[ $ svc\]}"  
    printf "  %-4s %-15s %-10s %s\\n" "\[ $ i\]" " $ display" " $ port" " $ desc"  
    svc\_index+=(" $ svc")  
    i= $ ((i \+ 1))  
done

echo ""  
echo "  \[q\] Quit"  
echo ""  
read \-rp "  Select service number: " choice

\[\[ " $ choice" \== "q" \]\] && exit 0  
\[\[ " $ choice" \=\~ ^\[0-9\]+ $  \]\] || err "Invalid selection"  
\[\[ " $ choice" \-ge 1 \]\] && \[\[ " $ choice" \-le ${\#svc\_index\[@\]} \]\] || err "Number out of range"

TARGET\_SVC="${svc\_index\[ $ ((choice \- 1))\]}"  
IFS=':' read \-r TARGET\_DISPLAY TARGET\_CONTAINER TARGET\_HOST\_PORT \\  
    TARGET\_INTERNAL\_PORT TARGET\_DESC \<\<\< " $ {ADDABLE\[$TARGET\_SVC\]}"

log "Selected: ${TARGET\_DISPLAY} (${TARGET\_SVC})"

}

# **─────────────────────────────────────────────────────────────────────────────**

# **4\. Pre-flight: check dependencies for the selected service**

# **─────────────────────────────────────────────────────────────────────────────**

check\_dependencies() { section "Dependency Check: ${TARGET\_DISPLAY}"

local deps\_ok=true

case " $ TARGET\_SVC" in  
    open\_webui)  
        if \! container\_running "ollama"; then  
            warn "Open WebUI works best with Ollama running"  
            warn "Add Ollama first or provide OPENAI\_API\_KEY"  
        fi  
        ;;  
    n8n)  
        if \! container\_running "redis"; then  
            warn "n8n queue mode requires Redis"  
            warn "Adding Redis first is recommended"  
            read \-rp "  Add Redis automatically? \[Y/n\]: " ans  
            if \[\[ " $ {ans,,}" \!= "n" \]\]; then  
                TARGET\_SVC="redis"  
                IFS=':' read \-r TARGET\_DISPLAY TARGET\_CONTAINER \\  
                    TARGET\_HOST\_PORT TARGET\_INTERNAL\_PORT TARGET\_DESC \\  
                    \<\<\< "${ALL\_SERVICES\[redis\]}"  
                log "Switched target to Redis \- re-run to add n8n"  
            fi  
        fi  
        ;;  
    langfuse)  
        if \! container\_running "redis"; then  
            warn "Langfuse worker requires Redis \- enabling Redis too"  
            deps\_ok=false  
        fi  
        if \! docker ps \-a \--format '{{.Names}}' | grep \-q "^langfuse-db $ "; then  
            log "Langfuse DB will be created alongside langfuse-web"  
        fi  
        ;;  
esac

if \[\[ " $ deps\_ok" \== "false" \]\]; then  
    err "Dependency check failed. Add required services first."  
fi

ok "Dependencies satisfied"

}

# **─────────────────────────────────────────────────────────────────────────────**

# **5\. Update .env to enable the new service**

# **─────────────────────────────────────────────────────────────────────────────**

update\_env\_file() { section "Updating .env"

local flag\_var="SERVICE\_${TARGET\_SVC^^}\_ENABLED"  
\# Handle open\_webui key  
flag\_var="${flag\_var/OPEN\_WEBUI/OPEN\_WEBUI}"

if grep \-q "^${flag\_var}=" " $ ENV\_FILE"; then  
    \# Update existing line  
    sed \-i "s|^ $ {flag\_var}=.\*|${flag\_var}=true|" " $ ENV\_FILE"  
else  
    \# Append  
    echo " $ {flag\_var}=true" \>\> " $ ENV\_FILE"  
fi

\# Reload  
set \-a; source " $ ENV\_FILE"; set \+a

ok ".env updated: ${flag\_var}=true"

}

# **─────────────────────────────────────────────────────────────────────────────**

# **6\. Append service stanza to docker-compose.yml**

# **Uses compose's own merging by generating a standalone fragment,**

# **then delegates to compose which reads volumes from the existing file**

# **─────────────────────────────────────────────────────────────────────────────**

append\_to\_compose() { section "Updating docker-compose.yml"

\# Back up compose file first  
cp " $ COMPOSE\_FILE" " $ {COMPOSE\_FILE}.bak.$(date \+%s)"  
log "Compose backup created"

\# Check if service stanza already exists in compose  
if grep \-q "^  ${TARGET\_CONTAINER}:" " $ COMPOSE\_FILE" 2\>/dev/null; then  
    log "Service stanza already exists in compose \- will just start it"  
    return  
fi

\# Add volume entry if needed (before services: block)  
\_ensure\_volume() {  
    local vol=" $ 1"  
    if \! grep \-q "^  ${vol}:" "$COMPOSE\_FILE"; then  
        \# Insert after 'volumes:' line  
        sed \-i "/^volumes:/a\\\\  ${vol}:" "$COMPOSE\_FILE"  
        log "Volume added: ${vol}"  
    fi  
}

\# Generate and append the service stanza  
case " $ TARGET\_SVC" in  
    redis)  
        \_ensure\_volume "redis-data"  
        cat \>\> " $ COMPOSE\_FILE" \<\< EOF

redis: image: ${REDIS\_IMAGE:-redis:7-alpine} container\_name: redis restart: unless-stopped networks: \[ai-platform\] ports: \- "127.0.0.1:${PORT\_REDIS:-6379}:6379" volumes: \- redis-data:/data command: redis-server \--save 60 1 \--loglevel warning healthcheck: test: \["CMD", "redis-cli", "ping"\] interval: 10s timeout: 5s retries: 10 start\_period: 10s EOF ;;

   qdrant)  
        \_ensure\_volume "qdrant-data"  
        cat \>\> " $ COMPOSE\_FILE" \<\< EOF

qdrant: image: \\ $ {QDRANT\_IMAGE:-qdrant/qdrant:latest} container\_name: qdrant restart: unless-stopped networks: \[ai-platform\] ports: \- "127.0.0.1:${PORT\_QDRANT:-6333}:6333" \- "127.0.0.1:${PORT\_QDRANT\_GRPC:-6334}:6334" volumes: \- qdrant-data:/qdrant/storage healthcheck: test: \["CMD-SHELL", "curl \-sf [http://localhost:6333/healthz](http://localhost:6333/healthz) || exit 1"\] interval: 15s timeout: 10s retries: 10 start\_period: 20s EOF ;;

   ollama)  
        \_ensure\_volume "ollama-data"  
        local gpu\_section=""  
        if \[\[ "${OLLAMA\_USE\_GPU:-false}" \== "true" \]\] && \\  
           \[\[ "${GPU\_DETECTED:-false}" \== "true" \]\]; then  
            gpu\_section="  
deploy:  
  resources:  
    reservations:  
      devices:  
        \- driver: nvidia  
          count: all  
          capabilities: \[gpu\]"  
        fi  
        cat \>\> " $ COMPOSE\_FILE" \<\< EOF

ollama: image: \\ $ {OLLAMA\_IMAGE:-ollama/ollama:latest} container\_name: ollama restart: unless-stopped networks: \[ai-platform\] ports: \- "127.0.0.1:${PORT\_OLLAMA:-11434}:11434" volumes: \- ollama-data:/root/.ollama environment: OLLAMA\_NUM\_PARALLEL: "${OLLAMA\_NUM\_PARALLEL:-1}" OLLAMA\_MAX\_LOADED\_MODELS: "${OLLAMA\_MAX\_LOADED\_MODELS:-1}" healthcheck: test: \["CMD-SHELL", "curl \-sf [http://localhost:11434/api/tags](http://localhost:11434/api/tags) || exit 1"\] interval: 15s timeout: 10s retries: 20 start\_period: 30s${gpu\_section} EOF ;;

   open\_webui)  
        \_ensure\_volume "open-webui-data"  
        local rag\_env=""  
        if container\_running "searxng"; then  
            rag\_env="  
  ENABLE\_RAG\_WEB\_SEARCH: \\"true\\"  
  RAG\_WEB\_SEARCH\_ENGINE: \\"searxng\\"  
  SEARXNG\_QUERY\_URL: \\"http://searxng:8080/search?q=\<query\>\&format=json\\""  
        fi  
        local ollama\_url\_env=""  
        if container\_running "ollama"; then  
            ollama\_url\_env="  
  OLLAMA\_BASE\_URL: \\"http://ollama:11434\\""  
        fi  
        local depends=""  
        if container\_running "ollama"; then  
            depends="  
depends\_on:  
  ollama:  
    condition: service\_healthy"  
        fi

        cat \>\> " $ COMPOSE\_FILE" \<\< EOF

open-webui: image: \\ $ {OPEN\_WEBUI\_IMAGE:-ghcr.io/open-webui/open-webui:main} container\_name: open-webui restart: unless-stopped networks: \[ai-platform\]${depends} ports: \- "127.0.0.1:${PORT\_OPEN\_WEBUI:-3000}:8080" volumes: \- open-webui-data:/app/backend/data environment: WEBUI\_SECRET\_KEY: "${OPEN\_WEBUI\_SECRET\_KEY}" WEBUI\_AUTH: "${OPEN\_WEBUI\_ENABLE\_AUTH:-true}" PORT: "8080"${ollama\_url\_env}${rag\_env} healthcheck: test: \["CMD-SHELL", "curl \-sf [http://localhost:8080/](http://localhost:8080/) || exit 1"\] interval: 20s timeout: 10s retries: 15 start\_period: 60s EOF ;;

   flowise)  
        \_ensure\_volume "flowise-data"  
        local flowise\_auth=""  
        if \[\[ "${FLOWISE\_AUTH\_ENABLED:-false}" \== "true" \]\]; then  
            flowise\_auth="  
  FLOWISE\_USERNAME: \\"\\${FLOWISE\_USERNAME:-admin}\\"  
  FLOWISE\_PASSWORD: \\"\\${FLOWISE\_PASSWORD}\\""  
        fi  
        cat \>\> " $ COMPOSE\_FILE" \<\< EOF

flowise: image: \\ $ {FLOWISE\_IMAGE:-flowiseai/flowise:latest} container\_name: flowise restart: unless-stopped networks: \[ai-platform\] ports: \- "127.0.0.1:${PORT\_FLOWISE:-3001}:3000" volumes: \- flowise-data:/root/.flowise environment: PORT: "3000" FLOWISE\_SECRETKEY\_OVERWRITE: "${FLOWISE\_SECRET\_KEY}"${flowise\_auth} healthcheck: test: \["CMD-SHELL", "curl \-sf [http://localhost:3000/](http://localhost:3000/) || exit 1"\] interval: 15s timeout: 10s retries: 15 start\_period: 45s EOF ;;

   n8n)  
        \_ensure\_volume "n8n-data"  
        local n8n\_webhook="http://${SERVER\_IP}:${PORT\_N8N:-5678}"  
        \[\[ "${DEPLOYMENT\_MODE:-local}" \!= "local" \]\] && \\  
            n8n\_webhook="http${USE\_SSL:+s}://n8n.${BASE\_DOMAIN}"

        local n8n\_auth=""  
        if \[\[ "${N8N\_BASIC\_AUTH\_ENABLED:-false}" \== "true" \]\]; then  
            n8n\_auth="  
  N8N\_BASIC\_AUTH\_ACTIVE: \\"true\\"  
  N8N\_BASIC\_AUTH\_USER: \\"\\${N8N\_BASIC\_AUTH\_USER:-admin}\\"  
  N8N\_BASIC\_AUTH\_PASSWORD: \\"\\${N8N\_BASIC\_AUTH\_PASSWORD}\\""  
        fi

        local n8n\_depends=""  
        if container\_running "redis"; then  
            n8n\_depends="  
depends\_on:  
  redis:  
    condition: service\_healthy"  
        fi

        cat \>\> " $ COMPOSE\_FILE" \<\< EOF

n8n: image: \\ $ {N8N\_IMAGE:-n8nio/n8n:latest} container\_name: n8n restart: unless-stopped networks: \[ai-platform\]${n8n\_depends} ports: \- "127.0.0.1:${PORT\_N8N:-5678}:5678" volumes: \- n8n-data:/home/node/.n8n environment: N8N\_HOST: "0.0.0.0" N8N\_PORT: "5678" N8N\_PROTOCOL: "http" WEBHOOK\_URL: "${n8n\_webhook}/" N8N\_ENCRYPTION\_KEY: "${N8N\_ENCRYPTION\_KEY}" EXECUTIONS\_PROCESS: "main" N8N\_LOG\_LEVEL: "warn"${n8n\_auth} healthcheck: test: \["CMD-SHELL", "wget \-qO- [http://localhost:5678/healthz](http://localhost:5678/healthz) || exit 1"\] interval: 15s timeout: 10s retries: 15 start\_period: 45s EOF ;;

   langfuse)  
        \_ensure\_volume "langfuse-db-data"  
        local lf\_url="http://${SERVER\_IP}:${PORT\_LANGFUSE:-8080}"  
        \[\[ "${DEPLOYMENT\_MODE:-local}" \!= "local" \]\] && \\  
            lf\_url="http${USE\_SSL:+s}://langfuse.${BASE\_DOMAIN}"

        local redis\_env=""  
        if container\_running "redis"; then  
            redis\_env="  
  REDIS\_HOST: \\"redis\\"  
  REDIS\_PORT: \\"6379\\""  
        fi

        cat \>\> " $ COMPOSE\_FILE" \<\< EOF

langfuse-db: image: \\ $ {POSTGRES\_IMAGE:-postgres:15-alpine} container\_name: langfuse-db restart: unless-stopped networks: \[ai-platform\] volumes: \- langfuse-db-data:/var/lib/postgresql/data environment: POSTGRES\_USER: "${LANGFUSE\_DB\_USER:-langfuse}" POSTGRES\_PASSWORD: "${LANGFUSE\_DB\_PASSWORD}" POSTGRES\_DB: "${LANGFUSE\_DB\_NAME:-langfuse}" PGDATA: /var/lib/postgresql/data/pgdata healthcheck: test: \["CMD-SHELL", "pg\_isready \-U ${LANGFUSE\_DB\_USER:-langfuse}"\] interval: 10s timeout: 5s retries: 15 start\_period: 20s

langfuse-web: image: ${LANGFUSE\_IMAGE:-langfuse/langfuse:latest} container\_name: langfuse-web restart: unless-stopped networks: \[ai-platform\] ports: \- "127.0.0.1:${PORT\_LANGFUSE:-8080}:3000" depends\_on: langfuse-db: condition: service\_healthy environment: DATABASE\_URL: "postgresql://${LANGFUSE\_DB\_USER:-langfuse}:${LANGF

