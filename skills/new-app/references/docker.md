# Service folder: Docker, compose, scripts

One Dockerfile serves both environments. varlock runs **inside** the container and resolves secrets at start, so secrets never pass through compose, `docker inspect` or disk. The examples below are Node; swap in the runtime of the reference app.

> Status: this container-side varlock pattern is the target design. Its first full run is the portal pilot. If something here fails in practice, fix this file.

## docker/Dockerfile

```dockerfile
FROM node:22

# varlock binary + Vault plugin baked in (exact versions; bump together)
COPY --from=ghcr.io/dmno-dev/varlock:1.21.0 /usr/local/bin/varlock /usr/local/bin/varlock
RUN varlock install-plugin @varlock/hashicorp-vault-plugin@2.1.1

WORKDIR /usr/app
COPY .env.schema .env.dev .env.prod ./

WORKDIR /usr/app/app
COPY app/package*.json ./
RUN npm install

ARG APP_ENV=dev
COPY app .
RUN if [ "$APP_ENV" = "prod" ]; then npm run build; fi

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
WORKDIR /usr/app
ENTRYPOINT ["varlock", "run", "--", "/entrypoint.sh"]
```

Build context is the **service folder** (`..` from `docker/`). When the app imports shared code from the repo root (potion's `shared/`), make the context the repo root and copy that folder too, as `potion/mcp` does.

## docker/entrypoint.sh

See the prod branch under compose.prod.yaml below: in prod, the entrypoint loops instead of `exec`.

## docker/compose.dev.yaml

```yaml
services:
  <app>:
    container_name: <project>-<app>
    build:
      context: ..
      dockerfile: docker/Dockerfile
      args: { APP_ENV: dev }
    ports: ["${PORT}:${PORT}"]
    environment:
      APP_ENV: dev
      VAULT_ADDR: ${VAULT_ADDR}
      VAULT_TOKEN: ${VAULT_TOKEN}      # dev only: your own token, on your own machine
    volumes:
      - ../app:/usr/app/app            # hot reload
      - /usr/app/app/node_modules      # keep the image's node_modules
```

## docker/compose.prod.yaml

```yaml
services:
  <app>:
    container_name: <project>-<app>
    build:
      context: ..
      dockerfile: docker/Dockerfile
      args: { APP_ENV: prod }
    restart: unless-stopped
    ports: ["127.0.0.1:5001:5001"]      # literal: prod compose never needs varlock on the host
    environment:
      APP_ENV: prod
      VAULT_ADDR: http://vault.tail0e3587.ts.net:8200
    secrets: [vault_role_id, vault_secret_id]
secrets:
  vault_role_id:   { file: /run/ghostmind/<project>/<app>/role_id }     # host RAM, written per deploy
  vault_secret_id: { file: /run/ghostmind/<project>/<app>/secret_id }   # single-use, deleted after start
```

Prod authenticates with a **single-use AppRole login** that the deploy workflow drops into host RAM. It is mounted into the container as compose secrets (`/run/secrets/*`, never in env). `.env.prod` reads them into `VAULT_ROLE_ID` / `VAULT_SECRET_ID` (see the `secrets` skill). The `deploy` skill covers the whole flow.

**varlock must stay PID 1 and supervise the app**, because the login cannot be reused. If the app crashes, it restarts inside the container, and the secrets resolved at start are still in varlock's memory. In prod the entrypoint loops:

```sh
# entrypoint.sh, prod branch
cd /usr/app/app
if [ "$APP_ENV" = "prod" ]; then
  while true; do npm run start || echo "app exited ($?), restarting"; sleep 2; done
else
  exec npm run dev
fi
```

Internal-only services (workers) drop `ports:` entirely.

## scripts/

```bash
# scripts/dev.sh
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose -p <project> -f docker/compose.dev.yaml up --build

# scripts/prod.sh
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose -p <project> -f docker/compose.prod.yaml up --build -d
```

`-p <project>` puts every app of the project on one network. `dev.sh` is called through `varlock run --`, so `${PORT}` and `${VAULT_*}` are set when compose interpolates. `prod.sh` runs **without** varlock: `compose.prod.yaml` is literal and only the container talks to Vault, so the server and CI never hold app secrets.

## meta.json

```json
{
  "id": "<12 random chars>",
  "name": "<app>",
  "type": "app",
  "routines": {
    "dev": "varlock run -- bash scripts/dev.sh",
    "prod": "bash scripts/prod.sh"
  },
  "herdr": { "workspaces": [ { "label": "<project>", "tabs": [ {
    "label": "<app>", "layout": "compact",
    "compact": { "type": "vertical", "panes": [
      { "name": "dev", "description": "dev server with hot reload (run routine dev), long-running" },
      { "name": "execution-shell", "description": "ad-hoc commands" }
    ] } } ] } ] }
}
```
