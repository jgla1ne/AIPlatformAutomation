#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# SCRIPT 1 — SYSTEM SETUP & CONFIGURATION (NO REGRESSIONS)
###############################################################################

LOG_DIR="$HOME/logs"
CONFIG_DIR="$HOME/config"
mkdir -p "$LOG_DIR" "$CONFIG_DIR"

LOG="$LOG_DIR/step1-setup.log"
exec > >(tee -a "$LOG") 2>&1

echo "================================================="
echo " STEP 1 — SYSTEM SETUP"
echo "================================================="

###############################################################################
# SERVICE DEFINITIONS (grounded in original README + earlier script)
###############################################################################

ALL_CORE_SERVICES=(
  ollama
  litellm
  anythingllm
)

ALL_AI_SERVICES=(
  dify
  comfyui
  openwebui
  flowise
  openclaw
)

ALL_OPT_SERVICES=(
  grafana
  prometheus
  elk
  portainer
)

ALL_SERVICES=(
  "${ALL_CORE_SERVICES[@]}"
  "${ALL_AI_SERVICES[@]}"
  "${ALL_OPT_SERVICES[@]}"
)

###############################################################################
# DEFAULT PORT REGISTRY (NO 10000 REGRESSION)
###############################################################################

declare -A DEFAULT_PORTS=(
  [ollama]=11434
  [litellm]=5000
  [anythingllm]=3001
  [dify]=3000
  [comfyui]=8188
  [openwebui]=7860
  [flowise]=8081
  [openclaw]=8080
  [grafana]=5601
  [prometheus]=9090
  [elk]=5601
  [portainer]=9000
)

###############################################################################
# STATE REGISTRIES (FULLY INITIALISED)
###############################################################################

declare -A SERVICES_SELECTED
declare -A SERVICE_PORT

for svc in "${ALL_SERVICES[@]}"; do
  SERVICES_SELECTED["$svc"]=false
  SERVICE_PORT["$svc"]="${DEFAULT_PORTS[$svc]}"
done

###############################################################################
# UTILS
###############################################################################

port_free() {
  ! ss -lnt | awk '{print $4}' | grep -q ":$1\$"
}

prompt_port() {
  local svc="$1"
  local default="${DEFAULT_PORTS[$svc]}"
  local port

  while true; do
    read -rp "Port for $svc [$default]: " port
    port="${port:-$default}"

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
      echo "❌ Invalid port number"
      continue
    fi

    if ! port_free "$port"; then
      echo "❌ Port $port already in use"
      continue
    fi

    SERVICE_PORT["$svc"]="$port"
    break
  done
}

select_services() {
  local label="$1"
  shift
  local services=("$@")

  echo
  echo "Select $label services:"
  echo "  0) ALL"
  local i=1
  for svc in "${services[@]}"; do
    echo "  $i) $svc"
    ((i++))
  done

  read -rp "Selection (comma-separated): " selection

  if [[ "$selection" == "0" ]]; then
    for svc in "${services[@]}"; do
      SERVICES_SELECTED["$svc"]=true
    done
    return
  fi

  IFS=',' read -ra picks <<< "$selection"
  for pick in "${picks[@]}"; do
    idx=$((pick - 1))
    if [[ "$idx" -ge 0 && "$idx" -lt "${#services[@]}" ]]; then
      SERVICES_SELECTED["${services[$idx]}"]=true
    fi
  done
}

###############################################################################
# DOMAIN + IP VALIDATION (SINGLE PROMPT — NO REGRESSION)
###############################################################################

read -rp "Enter domain or subdomain (e.g., ai.example.com): " DOMAIN
DOMAIN="$(echo "$DOMAIN" | xargs)"

if [[ -z "$DOMAIN" ]]; then
  echo "❌ Domain cannot be empty"
  exit 1
fi

PUBLIC_IP="$(curl -fsSL https://api.ipify.org || true)"
DOMAIN_IP="$(getent ahosts "$DOMAIN" | awk '{print $1}' | head -n1 || true)"

echo "Detected public IP : ${PUBLIC_IP:-unknown}"
echo "Resolved domain IP : ${DOMAIN_IP:-unresolved}"

if [[ -n "$DOMAIN_IP" && -n "$PUBLIC_IP" && "$DOMAIN_IP" != "$PUBLIC_IP" ]]; then
  echo "⚠ WARNING: Domain does not resolve to this host"
fi

###############################################################################
# SERVICE SELECTION (0 = ALL RESTORED)
###############################################################################

select_services "CORE" "${ALL_CORE_SERVICES[@]}"
select_services "AI"   "${ALL_AI_SERVICES[@]}"
select_services "OPTIONAL" "${ALL_OPT_SERVICES[@]}"

###############################################################################
# PORT CONFIGURATION
###############################################################################

echo
echo "Configuring ports…"

for svc in "${ALL_SERVICES[@]}"; do
  if [[ "${SERVICES_SELECTED[$svc]}" == "true" ]]; then
    prompt_port "$svc"
  fi
done

###############################################################################
# WRITE ENV + OPENCLAW CONFIG (NO SILENT SKIPS)
###############################################################################

ENV_FILE="$CONFIG_DIR/.env"
OPENCLAW_FILE="$CONFIG_DIR/openclaw_config.json"

echo "Writing $ENV_FILE"
{
  echo "DOMAIN=$DOMAIN"
  echo "PUBLIC_IP=$PUBLIC_IP"
  for svc in "${ALL_SERVICES[@]}"; do
    if [[ "${SERVICES_SELECTED[$svc]}" == "true" ]]; then
      echo "$(echo "$svc" | tr '[:lower:]' '[:upper:]')_PORT=${SERVICE_PORT[$svc]}"
    fi
  done
} > "$ENV_FILE"

echo "Writing $OPENCLAW_FILE"
cat > "$OPENCLAW_FILE" <<EOF
{
  "domain": "$DOMAIN",
  "services": {
$(for svc in "${ALL_SERVICES[@]}"; do
    if [[ "${SERVICES_SELECTED[$svc]}" == "true" ]]; then
      echo "    \"$svc\": { \"port\": ${SERVICE_PORT[$svc]} },"
    fi
done | sed '$ s/,$//')
  }
}
EOF

echo "✅ Script 1 completed successfully"

