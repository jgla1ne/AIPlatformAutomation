## Two Problems, Two Fixes

The report is clear. Both issues are simple configuration errors.

---

## Problem 1: Caddyfile — Two Invalid Directives

### Invalid directive 1: `header_read_timeout`
This is NOT a Caddy v2 `reverse_proxy` subdirective. It doesn't exist. Remove it.

### Invalid directive 2: `tls internal` + `auto_https off` together
`auto_https off` disables ACME/Let's Encrypt globally, then `tls internal` creates self-signed certs. Combined with real DNS pointing to a real IP, this means no valid TLS ever. Pick one approach.

---

## The Complete Fixed Caddyfile

```caddy
{
    admin 0.0.0.0:2019
    email {$ADMIN_EMAIL}
    # Remove auto_https off — let Caddy handle ACME automatically
}

# HTTP → HTTPS redirect for all hosts
http:// {
    redir https://{host}{uri} permanent
}

litellm.{$DOMAIN} {
    reverse_proxy litellm:4000 {
        header_up Host {http.reverse_proxy.upstream.hostport}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto https
    }
}

chat.{$DOMAIN} {
    reverse_proxy open-webui:8080 {
        header_up Host {http.reverse_proxy.upstream.hostport}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto https
        # WebSocket support — correct Caddy v2 syntax:
        header_up Upgrade {http.request.header.Upgrade}
        header_up Connection {http.request.header.Connection}
        # header_read_timeout DOES NOT EXIST — removed
        transport http {
            read_timeout 86400s
            write_timeout 86400s
        }
    }
}

grafana.{$DOMAIN} {
    reverse_proxy grafana:3000 {
        header_up Host {http.reverse_proxy.upstream.hostport}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-Proto https
    }
}

n8n.{$DOMAIN} {
    reverse_proxy n8n:5678 {
        header_up Host {http.reverse_proxy.upstream.hostport}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-Proto https
    }
}

flowise.{$DOMAIN} {
    reverse_proxy flowise:3000 {
        header_up Host {http.reverse_proxy.upstream.hostport}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-Proto https
    }
}

dify.{$DOMAIN} {
    reverse_proxy dify-nginx:80 {
        header_up Host {http.reverse_proxy.upstream.hostport}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-Proto https
    }
}
```

**Key changes:**
- Removed `auto_https off` → Caddy now gets real Let's Encrypt certs automatically
- Removed `tls internal` from all blocks → no more self-signed
- Removed `header_read_timeout 86400` → replaced with valid `transport http { read_timeout 86400s }`
- `{http.request.remote_host}` → correct placeholder is `{http.request.remote.host}`

---

## Problem 2: Caddy Service Missing Ports 80/443 in docker-compose.yml

The report shows the Caddy service exists but ports 80/443 are not bound. Fix:

```yaml
  caddy:
    image: caddy:2-alpine
    container_name: ai-platform-caddy
    restart: unless-stopped
    ports:
      - "80:80"       # ← MUST be present for ACME HTTP-01 challenge
      - "443:443"     # ← MUST be present for HTTPS
      - "2019:2019"   # Caddy admin API (optional, internal only)
    volumes:
      - ${CONFIG_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    environment:
      DOMAIN: ${DOMAIN}
      ADMIN_EMAIL: ${ADMIN_EMAIL}
    networks:
      - ai_network

volumes:
  caddy_data:     # ← Must be a named volume, not tmpfs — persists TLS certs
  caddy_config:
```

**Critical:** `caddy_data` must be a persistent named volume. If it's missing or tmpfs, Caddy re-requests certificates on every restart and will hit Let's Encrypt rate limits within hours.

---

## LiteLLM: Still `health: starting` at 38 Seconds

The report shows LiteLLM logs:
```
"LiteLLM: Proxy initialized with Config"
"Set models: llama3.2, nomic-embed-text"
"Thank you for using LiteLLM!"
```

**The proxy IS running.** The health check is still hitting the wrong endpoint. Confirm this is `/health/liveliness` not `/health` in docker-compose.yml:

```yaml
healthcheck:
  test: ["CMD", "python3", "-c",
    "import urllib.request; urllib.request.urlopen('http://localhost:4000/health/liveliness')"]
  interval: 30s
  timeout: 15s
  retries: 10
  start_period: 120s
```

---

## Instructions for Windsurf

```
MAKE EXACTLY THESE CHANGES — nothing else:

1. Replace /mnt/data/datasquiz/configs/caddy/Caddyfile with the 
   fixed version above.
   Changes: remove header_read_timeout, remove auto_https off,
   remove tls internal, fix remote.host placeholders, add 
   transport http block for websocket timeout.

2. In docker-compose.yml, ensure caddy service has:
     ports:
       - "80:80"
       - "443:443"
   And caddy_data is a named volume (not tmpfs).

3. Validate before restarting:
   docker run --rm \
     -v /mnt/data/datasquiz/configs/caddy/Caddyfile:/etc/caddy/Caddyfile:ro \
     caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile

   Output must say: "Valid configuration"
   If it shows any error — DO NOT restart Caddy — fix the error first.

4. Only after validation passes:
   docker compose up -d caddy

5. Confirm:
   docker compose logs caddy --tail 20
   # Should show: "serving initial configuration"
   # Should show: certificate obtained for each domain

DO NOT touch postgres, redis, ollama, grafana, prometheus, 
open-webui, rclone, or tailscale.
```