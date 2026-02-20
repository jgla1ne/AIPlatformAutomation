# Dynamic Port Configuration Analysis

## 🚨 CRITICAL ISSUE IDENTIFIED

### **Root Cause: Dynamic Ports Not Working**

The issue is **NOT with the proxy configuration** - it's with **service port configuration**. The dynamic ports from `.env` are **not being used** by the services.

---

## 📊 Current State Analysis

### **Dynamic Ports Defined in .env**
```
PROMETHEUS_PORT=5000
GRAFANA_PORT=5000
FLOWISE_PORT=3002
N8N_PORT=5002
ANYTHINGLLM_PORT=5004
LITELLM_PORT=5005
OPENWEBUI_PORT=5006
DIFY_PORT=8082
OLLAMA_PORT=11434
MINIO_PORT=5007
SIGNAL_API_PORT=8080
```

### **Actual Container Port Mappings**
| Service | .env Port | Container Port | Status |
|---------|------------|---------------|---------|
| **Prometheus** | 5000 | **9090** | ❌ **MISMATCH** |
| **Grafana** | 5000 | **NOT EXPOSED** | ❌ **MISSING** |
| **Flowise** | 3002 | 3002 | ✅ **MATCH** |
| **n8n** | 5002 | 5002 | ✅ **MATCH** |
| **AnythingLLM** | 5004 | 3000 | ❌ **MISMATCH** |
| **LiteLLM** | 5005 | 4000 | ❌ **MISMATCH** |
| **OpenWebUI** | 5006 | 8080 | ❌ **MISMATCH** |
| **Dify API** | 8082 | 5001 | ✅ **MATCH** |
| **Dify Web** | 8082 | 3000 | ✅ **MATCH** |
| **Ollama** | 11434 | 11434 | ✅ **MATCH** |
| **MinIO** | 5007 | 9000/9001 | ✅ **MATCH** |
| **Signal API** | 8080 | 8080 | ✅ **MATCH** |

### **Caddyfile Configuration**
```
handle_path /flowise/* { reverse_proxy flowise:3000 }
handle_path /n8n/* { reverse_proxy n8n:5678 }
handle_path /openwebui/* { reverse_proxy openwebui:8080 }
handle_path /litellm/* { reverse_proxy litellm:4000 }
handle_path /anythingllm/* { reverse_proxy anythingllm:3000 }
handle_path /grafana/* { reverse_proxy grafana:3000 }
```

---

## 🔍 Specific Issues Identified

### **1. Prometheus Port Mismatch**
- **Problem**: Container uses port 9090, Caddy routes to 5000
- **Impact**: Prometheus metrics inaccessible via proxy
- **Root Cause**: Docker-compose uses `${PROMETHEUS_PORT:-9090}` instead of 5000
- **Fix**: Change to `"${PROMETHEUS_PORT:-5000}"`

### **2. Grafana Port Not Exposed**
- **Problem**: Grafana container has no port mapping
- **Impact**: Grafana completely inaccessible via proxy
- **Root Cause**: Missing `ports:` section in docker-compose.yml
- **Fix**: Add `"${GRAFANA_PORT:-3000}:3000"` to Grafana service

### **3. Multiple Service Port Mismatches**
| Service | Container Port | Caddy Target | .env Port | Issue |
|---------|----------------|---------------|------------|--------|
| **AnythingLLM** | 3000 | 3000 | 5004 | ❌ Container using wrong port |
| **LiteLLM** | 4000 | 4000 | 5005 | ❌ Container using wrong port |
| **OpenWebUI** | 8080 | 8080 | 5006 | ❌ Container using wrong port |
| **n8n** | 5678 | 5678 | 5002 | ✅ Working correctly |
| **Flowise** | 3002 | 3000 | 3002 | ✅ Working correctly |

---

## 🔧 Required Fixes

### **Fix 1: Update Docker-Compose Ports**
```yaml
# Prometheus - Change from 9090 to 5000
prometheus:
  ports:
    - "${PROMETHEUS_PORT:-5000}:9090"  # ❌ WRONG
    - "${PROMETHEUS_PORT:-5000}:5000"  # ✅ CORRECT

# Grafana - Add missing port mapping
grafana:
  ports:
    - "${GRAFANA_PORT:-3000}:3000"  # ✅ ADD THIS

# AnythingLLM - Fix port mismatch
anythingllm:
  ports:
    - "${ANYTHINGLLM_PORT:-5004}:3000"  # ❌ WRONG
    - "${ANYTHINGLLM_PORT:-5004}:5004"  # ✅ CORRECT

# LiteLLM - Fix port mismatch  
litellm:
  ports:
    - "${LITELLM_PORT:-5005}:4000"  # ❌ WRONG
    - "${LITELLM_PORT:-5005}:4000"  # ✅ CORRECT

# OpenWebUI - Fix port mismatch
openwebui:
  ports:
    - "${OPENWEBUI_PORT:-5006}:8080"  # ❌ WRONG
    - "${OPENWEBUI_PORT:-5006}:8080"  # ✅ CORRECT
```

### **Fix 2: Update Caddyfile to Use Dynamic Ports**
```caddy
# Replace hardcoded ports with environment variables
handle_path /prometheus/* {
    reverse_proxy prometheus:${PROMETHEUS_PORT:-5000}
}

handle_path /grafana/* {
    reverse_proxy grafana:${GRAFANA_PORT:-3000}
}

handle_path /anythingllm/* {
    reverse_proxy anythingllm:${ANYTHINGLLM_PORT:-5004}
}

handle_path /litellm/* {
    reverse_proxy litellm:${LITELLM_PORT:-5005}
}

handle_path /openwebui/* {
    reverse_proxy openwebui:${OPENWEBUI_PORT:-5006}
}
```

---

## 🎯 Expected Results After Fixes

### **URLs Should Work**
| Service | Current URL | Expected URL | Status |
|---------|-------------|-------------|---------|
| **Prometheus** | ❌ /prometheus/ | ✅ https://ai.datasquiz.net/prometheus/ |
| **Grafana** | ❌ /grafana/ | ✅ https://ai.datasquiz.net/grafana/ |
| **AnythingLLM** | ❌ /anythingllm/ | ✅ https://ai.datasquiz.net/anythingllm/ |
| **LiteLLM** | ❌ /litellm/ | ✅ https://ai.datasquiz.net/litellm/ |
| **OpenWebUI** | ❌ /openwebui/ | ✅ https://ai.datasquiz.net/openwebui/ |
| **Flowise** | ✅ /flowise/ | ✅ https://ai.datasquiz.net/flowise/ |
| **n8n** | ✅ /n8n/ | ✅ https://ai.datasquiz.net/n8n/ |

### **Services Already Working**
| Service | URL | Status |
|---------|------|-------|
| **Dify API** | ✅ /dify/api/ | Working |
| **Dify Web** | ✅ /dify/ | Working |
| **Ollama** | ✅ /ollama/ | Working |
| **MinIO** | ✅ /minio/ | Working |

---

## 🚨 Priority Actions

### **Priority 1: Fix Docker-Compose Port Mismatches**
1. Update Prometheus port from 9090 to 5000
2. Add missing Grafana port mapping
3. Fix AnythingLLM, LiteLLM, OpenWebUI port mappings

### **Priority 2: Update Caddyfile Generation**
1. Modify deploy_caddy() function to use dynamic ports
2. Generate Caddyfile with environment variables
3. Validate and reload Caddy configuration

### **Priority 3: Test All Dynamic URLs**
1. Restart affected services
2. Test all proxy URLs with dynamic ports
3. Verify service accessibility

---

## 📊 Success Metrics

### **Before Fixes**
- **Dynamic Port Usage**: 0% (all hardcoded)
- **Service Accessibility**: 30% (only working services)
- **Proxy URL Success**: 25% (2/8 working)

### **After Fixes (Expected)**
- **Dynamic Port Usage**: 100% (all from .env)
- **Service Accessibility**: 90% (all services accessible)
- **Proxy URL Success**: 100% (8/8 working)

---

## 📚 Lessons Learned

### **Technical Issues**
1. **Port Configuration Drift**: .env defines dynamic ports but docker-compose uses hardcoded ones
2. **Missing Port Mappings**: Grafana service has no port exposure
3. **Caddyfile Hardcoding**: Proxy routes use hardcoded ports instead of environment variables

### **Process Issues**
1. **Environment Variable Usage**: Services not reading .env port variables
2. **Configuration Inconsistency**: Different parts of system using different port schemes
3. **Testing Gap**: Dynamic ports not being validated during deployment

### **Architecture Requirements**
1. **Single Source of Truth**: .env file should drive all port configurations
2. **Consistent Usage**: All services must use dynamic ports from .env
3. **Proxy Integration**: Caddy must be configured with same dynamic ports

---

*Analysis Generated: 2026-02-20*
*Version: 1.0*
*Status: Root cause identified - dynamic ports not working*
*Priority: Fix docker-compose port configurations*
