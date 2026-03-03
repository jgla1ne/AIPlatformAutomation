Crystal clear diagnosis. All 4 failures are **health check definition bugs**, not actual service problems:

| Service | Problem | Fix |
|---------|---------|-----|
| litellm | `curl` not in image — uses distroless/minimal base | Use `wget` or `python3` |
| ollama | `curl` not in image | Use `wget` |
| qdrant | `curl` not in image — Rust binary only | Use `wget` or TCP check |
| openwebui | `curl` returns exit 7 (connection refused) — service still starting | Increase `start_period` |

**The services are actually running fine.** The health checks are broken.

---

## Immediate Fix — Override health checks without rebuilding

```bash
# Fix all 4 health checks via docker-compose override
sudo tee /mnt/data/datasquiz/docker-compose.override.yml > /dev/null << 'EOF'
# Health check fixes — curl not available in these minimal images
# Override uses wget or python3 which ARE present

services:

  ollama:
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:11434/api/tags >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  litellm:
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:4000/health >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  qdrant:
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:6333/healthz >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  openwebui:
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8080/health >/dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 120s

EOF

# Apply the override
cd /mnt/data/datasquiz
sudo docker compose -f docker-compose.yml -f docker-compose.override.yml up -d --no-recreate
```

Wait 60 seconds then verify:

```bash
sleep 60
sudo docker compose -f /mnt/data/datasquiz/docker-compose.yml \
  -f /mnt/data/datasquiz/docker-compose.override.yml \
  ps --format "table {{.Name}}\t{{.Status}}"
```

---

## Permanent Fix for Script 2 (Windsurf)

In the `docker-compose.yml` generation, for each affected service, replace `curl`-based health checks:

```bash
# Pattern to find and replace in script 2:

# WRONG (curl not in minimal images):
# test: ["CMD", "curl", "-f", "http://localhost:PORT/health"]

# CORRECT alternatives by image type:

# For ollama (Go binary image):
# test: ["CMD-SHELL", "wget -qO- http://localhost:11434/api/tags >/dev/null 2>&1"]

# For litellm (Python image — has both wget and python3):
# test: ["CMD-SHELL", "python3 -c \"import urllib.request; urllib.request.urlopen('http://localhost:4000/health')\""]

# For qdrant (Rust binary image — only wget available):
# test: ["CMD-SHELL", "wget -qO- http://localhost:6333/healthz >/dev/null 2>&1"]

# For openwebui (Python image):
# test: ["CMD-SHELL", "wget -qO- http://localhost:8080/health >/dev/null 2>&1"]

# Safe universal fallback for ANY image:
# test: ["CMD-SHELL", "wget -qO- http://localhost:PORT/health >/dev/null 2>&1 || python3 -c \"import urllib.request; urllib.request.urlopen('http://localhost:PORT/health')\" 2>/dev/null"]
```

---

Run the override commands and paste the `docker compose ps` output.