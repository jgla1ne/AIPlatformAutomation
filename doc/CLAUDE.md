Let me read every file completely before writing anything.There is exactly one root cause, and one cascading mistake. Here is the complete picture.

---

## The Actual Root Cause: `schema.prisma` mount that doesn't exist

**File:** `scripts/3-configure-services.sh`, line 615

```yaml
      - ${CONFIG_DIR}/litellm/schema.prisma:/app/schema.prisma:ro
```

`schema.prisma` is never written to the host by any script. `generate_litellm_config` only writes `config.yaml`. `prepare_directories` only creates the `CONFIG_DIR/litellm` directory.

When Docker tries to bind-mount a source path that **does not exist as a file**, it creates a **directory** at that path. So Docker creates `/mnt/data/datasquiz/configs/litellm/schema.prisma/` as a directory, then mounts that directory over `/app/schema.prisma` inside the container — replacing the real Prisma schema file (which exists correctly inside the image) with an empty directory. Prisma tries to read its schema, gets a directory handle instead, and **hangs indefinitely**. This is why the logs show "Prisma schema loaded from schema.prisma" followed by silence — it's stuck trying to parse a directory as YAML.

## The Cascading Mistake: `initialize_litellm_database` in Script 2

Windsurf added a call to `initialize_litellm_database()` in Script 2 (lines 151–158) that runs `docker compose run --rm litellm` to pre-migrate the database. This creates a second litellm container that hits **the same broken schema.prisma mount**, fails, and because Script 2 does `if initialize_litellm_database ...; then ... else return 1; fi`, **Script 2 exits entirely** — meaning no caddy, no monitoring, no web services ever deploy.

The function also has hardcoded `ds-admin` as the postgres user throughout (lines 1123, 1147), violating the zero-hardcoded-values principle.

---

## The Two Changes for Windsurf

### Change 1 — Script 3: Remove the `schema.prisma` mount

**File:** `scripts/3-configure-services.sh`

```bash
# FIND and DELETE this single line (line 615):
      - ${CONFIG_DIR}/litellm/schema.prisma:/app/schema.prisma:ro
```

The `schema.prisma` file belongs inside the image where LiteLLM ships it. We must not mount over it. LiteLLM's built-in startup sequence handles Prisma migration automatically when it has a valid `DATABASE_URL` and an empty database — no external intervention needed.

The litellm volumes block should read exactly:
```yaml
    volumes:
      - ${CONFIG_DIR}/litellm/config.yaml:/litellm-config.yaml:ro
      - ${DATA_DIR}/litellm:/root/.cache
```

### Change 2 — Script 2: Remove the `initialize_litellm_database` call

**File:** `scripts/2-deploy-services.sh`

```bash
# FIND and DELETE these lines (151–158):
        # Initialize LiteLLM database (Mission Control)
        log_info "Initializing LiteLLM database..."
        if initialize_litellm_database "$TENANT"; then
            log_success "LiteLLM database initialized successfully"
        else
            log_error "LiteLLM database initialization failed"
            return 1
        fi
```

The Step 5 block should go directly from the `--force` block to `deploy_service litellm`:

```bash
        # --force only: wipe Prisma cache and reset litellm database (clean slate)
        if [[ "$FORCE_REDEPLOY" == "true" ]]; then
            # ... existing --force block unchanged ...
        fi

        deploy_service litellm
        wait_for_healthy litellm 180
```

LiteLLM runs Prisma migration automatically on startup. The database was already provisioned by `provision_databases`. There is nothing to pre-initialise.

---

## Deploy After These Two Changes

```bash
sudo bash scripts/0-complete-cleanup.sh datasquiz
sudo bash scripts/1-setup-system.sh datasquiz
sudo bash scripts/2-deploy-services.sh datasquiz --force
```

With the schema.prisma mount gone, LiteLLM starts with its own intact schema file, Prisma migrates the clean database in ~3 seconds, the proxy becomes healthy, and n8n, flowise, anythingllm, and codeserver all unblock.