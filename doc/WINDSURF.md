# WINDSURF.md - Script 1 Refactoring Plan
# Generated: 2026-03-31T23:15:00Z
# Based on: Analysis of working commit c38d365 vs current broken implementation

## 📋 CRITICAL FINDING

**Working Script 1 (commit c38d365)** used a **simple, direct `read` approach** that worked perfectly in both interactive and non-interactive environments.

**Current Script 1** has been over-engineered with TTY detection, timeouts, and complex buffering that breaks the input mechanism.

---

## 🔍 ROOT CAUSE ANALYSIS

### What Worked in c38d365
```bash
prompt_default() {
    local var="$1"
    local question="$2"
    local default="$3"
    echo ""
    read -r -p "  $question [$default]: " input
    eval "$var='${input:-$default}'"
}
```

**Key Principles:**
- **Simple `read -r -p`**: No TTY detection, no timeouts
- **Direct variable assignment**: Uses `eval` to set variables by name
- **Clean prompt format**: `  Question [default]: `
- **Immediate fallback**: `${input:-$default}` handles empty input

### What's Broken Now
- **Complex TTY detection**: `[[ -t 0 ]]` checks interfere with input
- **Timeout mechanisms**: `-t 30` adds complexity and breaks flow
- **Printf vs echo**: Buffering differences
- **Multiple function layers**: `prompt_input` → complex logic → variable setting

---

## 🎯 REFACTORING PLAN

### Step 1: Restore Simple Prompt Functions

**Replace the entire prompt system with the working c38d365 version:**

```bash
# =============================================================================
# INTERACTIVE PROMPT FUNCTIONS (RESTORED from c38d365)
# =============================================================================

prompt_default() {
    local var="$1"
    local question="$2"
    local default="$3"
    echo ""
    read -r -p "  $question [$default]: " input
    eval "$var='${input:-$default}'"
}

prompt_required() {
    local var="$1"
    local question="$2"
    local value=""
    while [[ -z "$value" ]]; do
        echo ""
        read -r -p "  $question (required): " value
        if [[ -z "$value" ]]; then
            echo "  ⚠  This field is required."
        fi
    done
    eval "$var='$value'"
}

prompt_secret() {
    local var="$1"
    local question="$2"
    local value=""
    while [[ -z "$value" ]]; do
        echo ""
        read -r -s -p "  $question (required, hidden): " value
        echo ""
        if [[ -z "$value" ]]; then
            echo "  ⚠  This field is required."
        fi
    done
    eval "$var='$value'"
}

prompt_yesno() {
    local var="$1"
    local question="$2"
    local default="${3:-y}"
    local answer=""
    echo ""
    read -r -p "  $question [y/n] (default: $default): " answer
    answer="${answer:-$default}"
    case "$answer" in
        [Yy]*) eval "$var=true" ;;
        *)     eval "$var=false" ;;
    esac
}
```

### Step 2: Remove All Complex Logic

**Delete these functions/variables:**
- `prompt_input()` function (entirely)
- `_DEFAULT_POSTGRES_PASS`, `_DEFAULT_N8N_KEY`, `_DEFAULT_WEBUI_KEY` variables
- TTY detection `[[ -t 0 ]]` checks
- Timeout `-t 30` parameters
- Non-interactive fallback logic
- Environment variable override logic

### Step 3: Restore Working Collection Pattern

**Adopt the c38d365 collection structure:**

```bash
collect_configuration() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         AI Platform — Configuration Collector            ║"
    echo "║                    Script 1 of 4                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  System detected:"
    echo "  • Architecture: $PLATFORM_ARCH"
    echo "  • GPU Type    : $GPU_TYPE"
    echo "  • Total RAM   : ${TOTAL_RAM_GB}GB"
    echo "  • Free on /mnt: ${MNT_DISK_GB}GB"
    echo ""
    echo "  You will be prompted for all configuration values."
    echo "  Press ENTER to accept defaults shown in [brackets]."
    echo ""

    # ── SECTION: Tenant Configuration ─────────────────────────────────────
    section "1. Tenant Configuration"
    
    prompt_required TENANT_ID \
        "Tenant identifier (used for all container/directory names)"
    
    prompt_default BASE_DOMAIN \
        "Base domain (e.g., example.com or 'local' for localhost)" \
        "local"

    # ── SECTION: Stack Preset ───────────────────────────────────────────────
    section "2. Stack Preset"
    
    echo "  Available presets:"
    echo "    minimal  - Core LLM platform (postgres, redis, litellm, ollama, openwebui, qdrant, caddy)"
    echo "    standard - Full automation (minimal + librechat, openclaw, n8n, flowise)"
    echo "    full     - Everything (standard + dify, authentik, signalbot, bifrost)"
    echo "    custom   - Choose services individually"
    
    local preset
    while true; do
        prompt_default preset "Select preset" "minimal"
        preset=$(echo "${preset}" | xargs | tr '[:upper:]' '[:lower:]')
        case "${preset}" in
            minimal|standard|full|custom) break ;;
            *) echo "    Invalid preset. Choose: minimal, standard, full, or custom" ;;
        esac
    done
    STACK_PRESET="${preset}"
    
    # ── SECTION: Service Flags (if custom) ───────────────────────────────────
    if [[ "${STACK_PRESET}" == "custom" ]]; then
        section "3. Service Selection"
        
        prompt_yesno POSTGRES_ENABLED "Enable PostgreSQL" "y"
        prompt_yesno REDIS_ENABLED "Enable Redis" "y"
        prompt_yesno LITELLM_ENABLED "Enable LiteLLM" "y"
        prompt_yesno OLLAMA_ENABLED "Enable Ollama" "y"
        prompt_yesno OPENWEBUI_ENABLED "Enable OpenWebUI" "y"
        prompt_yesno N8N_ENABLED "Enable N8N" "y"
        prompt_yesno FLOWISE_ENABLED "Enable Flowise" "y"
        prompt_yesno QDRANT_ENABLED "Enable Qdrant" "y"
    else
        # Set flags based on preset (existing logic)
        configure_services_by_preset "${STACK_PRESET}"
    fi

    # ── SECTION: API Keys (optional) ─────────────────────────────────────────
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        section "4. LLM Provider API Keys (optional)"
        echo "  Press ENTER to skip any provider"
        
        prompt_default OPENAI_API_KEY "OpenAI API Key" ""
        prompt_default ANTHROPIC_API_KEY "Anthropic API Key" ""
        prompt_default GOOGLE_API_KEY "Google API Key" ""
        prompt_default GROQ_API_KEY "Groq API Key" ""
        prompt_default OPENROUTER_API_KEY "OpenRouter API Key" ""
    fi

    # ── SECTION: Port Overrides (optional) ─────────────────────────────────
    section "5. Port Configuration (optional)"
    echo "  Press ENTER to accept defaults"
    
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        prompt_default POSTGRES_PORT "PostgreSQL port" "5432"
    fi
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        prompt_default REDIS_PORT "Redis port" "6379"
    fi
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        prompt_default LITELLM_PORT "LiteLLM port" "4000"
    fi
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        prompt_default OLLAMA_PORT "Ollama port" "11434"
        prompt_default OLLAMA_DEFAULT_MODEL "Default Ollama model" "llama3.2"
    fi
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        prompt_default OPENWEBUI_PORT "OpenWebUI port" "3000"
    fi
    if [[ "${N8N_ENABLED}" == "true" ]]; then
        prompt_default N8N_PORT "N8N port" "5678"
    fi
    if [[ "${FLOWISE_ENABLED}" == "true" ]]; then
        prompt_default FLOWISE_PORT "Flowise port" "3001"
    fi
}
```

### Step 4: Generate Secrets in write_platform_conf()

**Keep the existing secret generation logic but remove the pre-generated defaults:**

```bash
# In write_platform_conf():
if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
    postgres_password="$(gen_password)"
fi

if [[ "${N8N_ENABLED}" == "true" ]]; then
    n8n_encryption_key="$(gen_secret)"
fi

if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
    openwebui_secret="$(gen_secret)"
fi
```

---

## 🎯 EXECUTION STRATEGY

### Phase 1: Immediate Rollback (High Priority)
1. **Replace all prompt functions** with the c38d365 versions
2. **Remove complex TTY detection** and timeout logic
3. **Test basic input collection** with simple tenant ID prompt

### Phase 2: Restore Structure (Medium Priority)
1. **Reimplement collect_configuration()** with section-based approach
2. **Add preset selection logic** (minimal/standard/full/custom)
3. **Restore service flag collection** for custom preset

### Phase 3: Validate Integration (Low Priority)
1. **Ensure platform.conf generation** works with new variables
2. **Test directory creation** and package installation
3. **Verify compatibility** with Scripts 2 and 3

---

## 🔧 WHY THIS WILL WORK

### The c38d365 Approach Was Bulletproof Because:
1. **No TTY Detection**: Simple `read` works in both interactive and piped environments
2. **No Timeouts**: Natural flow without artificial interruptions
3. **Direct Variable Setting**: `eval` bypasses complex variable scoping issues
4. **Clean Prompts**: Consistent format that users expect
5. **Immediate Fallback**: `${input:-$default}` handles empty input naturally

### Why Current Approach Fails:
1. **Over-Engineering**: TTY detection adds complexity that breaks input
2. **Buffering Issues**: `printf` vs `echo` timing problems
3. **Variable Scoping**: Complex function layers interfere with variable setting
4. **Timeout Interference**: Artificial timeouts interrupt natural user flow

---

## 📋 TESTING CHECKLIST

### Basic Input Test
```bash
# This should work without hanging:
echo -e "\ntestuser\nlocal\nminimal\n" | bash scripts/1-setup-system.sh
```

### Interactive Test
```bash
# This should work in real terminal:
bash scripts/1-setup-system.sh
```

### Non-Interactive Test
```bash
# This should use all defaults:
TENANT_ID=test bash scripts/1-setup-system.sh
```

---

## 🚀 IMPLEMENTATION ORDER

1. **Replace prompt functions** (30 minutes)
2. **Remove complex logic** (15 minutes)  
3. **Test basic input** (15 minutes)
4. **Restore collection structure** (45 minutes)
5. **Full integration test** (30 minutes)

**Total estimated time: 2.25 hours**

---

**FINAL RECOMMENDATION**: Revert to the simple, proven c38d365 input mechanism. The current over-engineered solution is fundamentally broken and cannot be fixed with incremental changes.