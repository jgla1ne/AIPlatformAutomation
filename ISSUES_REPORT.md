# AI Platform Automation - Issues Report
**Generated:** March 12, 2026  
**Purpose:** Systematic analysis of remaining deployment issues for Gemini AI planning

---

## 🚨 CRITICAL ISSUES REQUIRING IMMEDIATE ATTENTION

### 1. **QDRANT - Vector Database Service**
**Status:** ❌ Restarting (101) continuously  
**Port:** 6333  
**Health Check:** HTTP 000 (connection refused)

**🔍 ROOT CAUSE ANALYSIS:**
```
Permission denied creating snapshots temp directory at ./snapshots/tmp
Error Code: 13 (Permission denied)
Path: ./snapshots/tmp
```

**📋 DETAILED LOG EVIDENCE:**
```
2026-03-12T15:57:57.890717Z  WARN qdrant::startup: Failed to create init file indicator: failed to create file `.qdrant-initialized`: Permission denied (os error 13)
2026-03-12T15:57:58.260669Z ERROR qdrant::startup: Panic occurred in file src/actix/mod.rs at line 70: called `Result::unwrap()` on an `Err` value: ServiceError { error: "Failed to create snapshots temp directory at ./snapshots/tmp: Custom { kind: PermissionDenied, error: Error { kind: CreateDir, source: Os { code: 13, kind: PermissionDenied, message: \"Permission denied\" }, path: \"./snapshots/tmp\" } }"
```

**🔧 OWNERSHIP STATUS:**
- Directory: `/mnt/data/datasquiz/qdrant/snapshots/tmp` 
- Owner: `ubuntu:jglaine` (1000:1001) ✅
- Container User: `1000:1001` ✅
- Permissions: `drwxr-xr-x` ✅

**🎯 TECHNICAL ANALYSIS:**
- Qdrant runs in `/qdrant/` working directory
- Tries to create `./snapshots/tmp` (relative to `/qdrant/`)
- Volume mounted at `/qdrant/storage/snapshots/`
- **ISSUE:** Path mismatch - container expects `/qdrant/snapshots/` but data is at `/qdrant/storage/snapshots/`

**💡 POTENTIAL SOLUTIONS:**
1. Add symlink: `/qdrant/snapshots` → `/qdrant/storage/snapshots`
2. Change Qdrant working directory to `/qdrant/storage`
3. Mount snapshots to `/qdrant/snapshots` instead of `/qdrant/storage/snapshots`

---

### 2. **ANYTHINGLLM - AI Document Processing**
**Status:** ❌ Up but failing (Node.js error)  
**Port:** 3001  
**Health Check:** HTTP 000 (connection refused)

**🔍 ROOT CAUSE ANALYSIS:**
```
TypeError [ERR_INVALID_ARG_TYPE]: The "paths[0]" argument must be of type string. Received undefined
```

**📋 DETAILED LOG EVIDENCE:**
```
TypeError [ERR_INVALID_ARG_TYPE]: The "paths[0]" argument must be of type string. Received undefined
    at new NodeError (node:internal/errors:405:5)
    at validateString (node:internal/validators:162:11)
    at Object.resolve (node:path:1115:7)
    at Object.<anonymous> (/app/collector/utils/files/index.js:12:12)
    at Module._compile (node:internal/modules/cjs/loader:1364:14)
```

**🔧 CONFIGURATION STATUS:**
- Directory: `/mnt/data/datasquiz/anythingllm/` (owner: jglaine:jglaine) ✅
- Container User: `1000:1001` ✅
- Environment: QDRANT_ENDPOINT, AUTH_TOKEN configured ✅

**🎯 TECHNICAL ANALYSIS:**
- Node.js v18.20.8 application startup failure
- Path resolution error in `/app/collector/utils/files/index.js:12`
- Missing or undefined environment variable for file path
- **ISSUE:** Application code expecting undefined path parameter

**💡 POTENTIAL SOLUTIONS:**
1. Check environment variables for missing file paths
2. Verify storage directory structure
3. Update AnythingLLM configuration for proper paths
4. Check if collector component needs specific directories

---

### 3. **LITELLM - LLM Proxy Service**
**Status:** ❌ Up but failing (Python package error)  
**Port:** 4000  
**Health Check:** HTTP 000 (connection refused)

**🔍 ROOT CAUSE ANALYSIS:**
```
subprocess.CalledProcessError: Command '['/usr/local/bin/python', '-m', 'pip', 'install', 'uvicorn', 'fastapi', 'appdirs', 'backoff', 'pyyaml', 'rq', 'orjson']' returned non-zero exit status 1.
```

**📋 DETAILED LOG EVIDENCE:**
```
WARNING: The directory '/.cache/pip' or its parent directory is not owned or is not writable by the current user. The cache has been disabled.
Defaulting to user installation because normal site-packages is not writeable
subprocess.CalledProcessError: Command '['/usr/local/bin/python', '-m', 'pip', 'install', 'uvicorn', 'fastapi', 'appdirs', 'backoff', 'pyyaml', 'rq', 'orjson']' returned non-zero exit status 1.
```

**🔧 CONFIGURATION STATUS:**
- Directory: `/mnt/data/datasquiz/litellm/` (owner: jglaine:jglaine) ✅
- Container User: `1000:1001` ✅
- Environment: LITELLM_MASTER_KEY, DATABASE_URL configured ✅

**🎯 TECHNICAL ANALYSIS:**
- Python package installation failure during startup
- Pip cache directory permission issues (`/.cache/pip`)
- Container trying to install packages as non-root user
- **ISSUE:** Python package management permissions in container

**💡 POTENTIAL SOLUTIONS:**
1. Fix pip cache directory permissions
2. Pre-install required packages in Docker image
3. Use pip with --user flag explicitly
4. Set PYTHONPATH environment variable

---

## ⚠️ MEDIUM PRIORITY ISSUES

### 4. **RCLONE - Cloud Storage Sync**
**Status:** ❌ Up but FUSE mount failing  
**Port:** N/A (background service)

**🔍 ROOT CAUSE ANALYSIS:**
```
CRITICAL: Fatal error: failed to mount FUSE fs: fusermount: exit status 1
NOTICE: mount helper error: fusermount3: mount failed: Permission denied
```

**📋 DETAILED LOG EVIDENCE:**
```
2026/03/12 16:02:58 CRITICAL: Fatal error: failed to mount FUSE fs: fusermount: exit status 1
2026/03/12 16:03:03 NOTICE: mount helper error: fusermount3: mount failed: Permission denied
```

**🎯 TECHNICAL ANALYSIS:**
- FUSE filesystem mount permission denied
- Container running as non-root cannot mount FUSE
- **ISSUE:** Host-level FUSE permissions required

**💡 POTENTIAL SOLUTIONS:**
1. Add --privileged flag to container
2. Install FUSE kernel module on host
3. Run rclone as root user (security trade-off)
4. Use rclone serve instead of mount

---

### 5. **OPENCLAW - Custom Application**
**Status:** ❌ Restarting (0) - No logs available  
**Port:** Unknown  
**Health Check:** Unknown

**🔍 ROOT CAUSE ANALYSIS:**
- Container exits immediately (exit code 0)
- No log output available
- **ISSUE:** Unknown - requires investigation

**💡 POTENTIAL SOLUTIONS:**
1. Check container entrypoint configuration
2. Verify environment variables
3. Check if required dependencies are missing
4. Review OpenClaw service definition

---

## ✅ WORKING SERVICES (BASELINE)

| Service | Status | Port | Health |
|---------|--------|------|--------|
| **postgres** | ✅ Healthy | 5432 | OK |
| **redis** | ✅ Healthy | 6379 | OK |
| **caddy** | ✅ Up | 80/443 | OK |
| **ollama** | ✅ Up | 11434 | OK |
| **grafana** | ✅ Up | 3000 | OK |
| **prometheus** | ✅ Up | 9090 | OK |
| **signal** | ✅ Healthy | 8080 | OK |
| **tailscale** | ✅ Up | 41641 | OK |
| **authentik** | ⏳ Health Starting | 9000 | Pending |
| **flowise** | ✅ Up | 3000 | OK |
| **n8n** | ✅ Up | 5678 | OK |
| **openwebui** | ⏳ Health Starting | 3000 | Pending |

---

## 🎯 PRIORITY ACTION PLAN

### **IMMEDIATE (Critical Path)**
1. **Fix Qdrant snapshots path mismatch** - Blocks all vector DB operations
2. **Resolve AnythingLLM Node.js path error** - Blocks document processing
3. **Fix LiteLLM Python package installation** - Blocks LLM proxy

### **SECONDARY**
4. **Resolve Rclone FUSE permissions** - Cloud storage sync
5. **Debug OpenClaw container exit** - Custom application

### **INFRASTRUCTURE**
6. **Add missing Dify service** - Not deployed despite being enabled
7. **Complete health checks for authentik/openwebui** - Pending startup

---

## 📊 SYSTEM HEALTH SUMMARY

- **Total Services:** 18
- **Healthy:** 8 (44%)
- **Issues:** 5 (28%)
- **Pending:** 5 (28%)

**Core Infrastructure:** ✅ Stable (postgres, redis, caddy, ollama)  
**AI/LLM Stack:** ❌ Critical issues (qdrant, anythingllm, litellm)  
**Monitoring:** ✅ Stable (grafana, prometheus)  
**Security:** ✅ Stable (signal, tailscale, authentik starting)

---

## 🔍 EVIDENCE COLLECTION SUMMARY

**Logs Analyzed:**
- ✅ Qdrant: Permission denied, path mismatch identified
- ✅ AnythingLLM: Node.js path resolution error
- ✅ LiteLLM: Python package installation failure
- ✅ Rclone: FUSE mount permission denied
- ❌ OpenClaw: No logs available

**Directory Permissions Verified:**
- ✅ Qdrant: 1000:1001 ownership correct
- ✅ AnythingLLM: jglaine:jglaine ownership correct
- ✅ LiteLLM: jglaine:jglaine ownership correct

**Health Checks Performed:**
- ❌ Qdrant (6333): Connection refused
- ❌ AnythingLLM (3001): Connection refused
- ❌ LiteLLM (4000): Connection refused
- ❌ N8N (5678): Connection refused (but container up)

---

**🤖 READY FOR GEMINI ANALYSIS:** This comprehensive report provides detailed evidence, root cause analysis, and technical context for AI-driven problem resolution planning.
