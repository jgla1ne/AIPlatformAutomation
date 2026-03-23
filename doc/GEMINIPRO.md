This is a fantastic and highly detailed diagnostic report. It perfectly isolates the exact reasons your deployment is failing. Caddy is crashing due to invalid syntax, and even if it didn't crash, it wouldn't be accessible because it's missing from the `docker-compose.yml` port bindings.

Here is the exact prompt you should paste into **Windsurf** to fix all of these issues in one shot with minimal code churn. 

***

### 🤖 Prompt for Windsurf:

"Windsurf, based on the recent HTTPS diagnostics report, the deployment is failing because Caddy is crashing due to invalid directives, and it is missing from the `docker-compose.yml`. Please apply the following targeted fixes to the scripts. Do not rewrite everything, just patch the specific generation blocks:

#### 1. Fix the Caddyfile Generation (in `3-configure-services.sh`)
Locate where the `Caddyfile` is being generated and make these **exact** changes:
*   **Remove** `auto_https off` from the global block.
*   **Remove** `tls internal` from ALL service blocks (this forces self-signed certs and breaks external access).
*   **Remove** `header_read_timeout 86400` from the OpenWebUI block (this is an invalid Caddy v2 directive causing the fatal crash).

**Update the Caddyfile generation block to look like this:**
```bash
cat << EOF > /mnt/data/${TENANT_ID}/configs/caddy/Caddyfile
{
    admin 0.0.0.0:2019
    email ${ADMIN_EMAIL}
    servers {
        trusted_proxies static private_ranges
    }
}

https://litellm.${DOMAIN} {
    reverse_proxy litellm:4000 {
        header_up Host {http.reverse_proxy.upstream.hostport}
        header_up X-Real-IP {http.request.remote_host}
        header_up X-Forwarded-For {http.request.remote_addr}
        header_up X-Forwarded-Proto https
    }
}

https://chat.${DOMAIN} {
    reverse_proxy open-webui:8080 {
        header_up Host {http.reverse_proxy.upstream.hostport}
        header_up X-Real-IP {http.request.remote_host}
        header_up X-Forwarded-For {http.request.remote_addr}
        header_up X-Forwarded-Proto https
        header_up Upgrade {http.request.header.Upgrade}
        header_up Connection {http.request.header.Connection}
    }
}
EOF
```

#### 2. Add Caddy to Docker Compose (in `2-deploy-services.sh`)
The report shows the Caddy service is missing or lacks port mappings. Find the `docker-compose.yml` generation block in `2-deploy-services.sh` and ensure the Caddy service is defined exactly like this with ports 80 and 443 exposed:

```yaml
  caddy:
    image: caddy:2-alpine
    container_name: ai-${TENANT_ID}-caddy-1
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /mnt/data/${TENANT_ID}/configs/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - /mnt/data/${TENANT_ID}/caddy_data:/data
      - /mnt/data/${TENANT_ID}/caddy_config:/config
    networks:
      - default
    depends_on:
      - litellm
      - open-webui
```

#### 3. Fix LiteLLM Port Binding (in `2-deploy-services.sh`)
The report notes LiteLLM is not responding to `localhost:4000`. This usually happens if LiteLLM binds to `127.0.0.1` inside its container instead of `0.0.0.0`. 
Find the LiteLLM `command` or entrypoint in `docker-compose.yml` (or docker run command) and ensure it explicitly includes `--host 0.0.0.0` and `--port 4000`:

```yaml
    # Inside litellm service in docker-compose.yml
    command: ["--config", "/app/config.yaml", "--port", "4000", "--host", "0.0.0.0"]
```

Please apply these precise fixes to `2-deploy-services.sh` and `3-configure-services.sh`. Do not touch other functional services like Postgres or Ollama."