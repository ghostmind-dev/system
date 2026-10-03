# The image, and Compose for apps that aren't on Kubernetes

**The Dockerfile and entrypoint below serve every app**, on Kubernetes or not: one image for both environments, with varlock **inside** the container resolving secrets at start. The examples are Node; swap in the runtime of the reference app.

**The Compose sections are the exception.** Most apps run on Kubernetes in dev and prod ([kubernetes.md](kubernetes.md)) and have no compose file at all. Use Compose only when the target isn't the cluster: Cloud Run (build and run locally with Compose, deploy with the provider's CLI), a one-off container, a standalone host.

> Status: the image pattern is live in prod (portal, tags). If something here fails in practice, fix this file.

## docker/Dockerfile

```dockerfile
FROM node:22

# varlock (glibc build) + Vault plugin. Exact versions; bump together.
ARG TARGETARCH
ARG VARLOCK_VERSION=1.21.0
RUN arch=$([ "$TARGETARCH" = "amd64" ] && echo x64 || echo arm64) \
  && curl -fsSL "https://github.com/dmno-dev/varlock/releases/download/varlock%40${VARLOCK_VERSION}/varlock-linux-${arch}.tar.gz" \
     | tar -xz -C /usr/local/bin ./varlock \
  && varlock install-plugin @varlock/hashicorp-vault-plugin@2.1.1

# node_modules live one level above the source: file sync (or a Compose bind mount) of app/ can't hide them
WORKDIR /usr/app
COPY .env.schema ./
COPY app/package*.json ./
RUN npm install
ENV PATH=/usr/app/node_modules/.bin:$PATH

WORKDIR /usr/app/app
COPY app .
ARG APP_ENV=dev
RUN if [ "$APP_ENV" = "prod" ]; then npm run build; fi

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
WORKDIR /usr/app
ENTRYPOINT ["varlock", "run", "--", "/entrypoint.sh"]
```

**Every image builds on both arm64 and amd64.** Dev runs on the Mac (arm64) and prod on Hetzner (amd64). Each side builds natively (`docker compose up --build` on the machine that runs it), so there is no cross-compiling, but the same Dockerfile must work on both:
- Base images must be published for both architectures (`node`, `alpine`, `hasura/graphql-engine`, `cloudflare/cloudflared` are). Check a new one with `docker manifest inspect <image> | grep architecture`.
- Anything downloaded picks its architecture from `TARGETARCH`, as the varlock line above does. Never hardcode `x64`, `amd64` or `x86_64` in a URL.
- No `platform:` pins in compose, and no `--platform` in `FROM`: forcing amd64 on the Mac falls back to slow emulation and hides arch bugs until prod.
- Native npm/pip modules (`sharp`, `bcrypt`…) install inside the image, never copied from the Mac's `node_modules`. That's why dev mounts an anonymous `node_modules` volume over the bind mount.
- If an image is ever pushed to a registry instead of built on the host, build both: `docker buildx build --platform linux/amd64,linux/arm64 --push`.

**Match the varlock binary to the base image's C library.** The binary in `ghcr.io/dmno-dev/varlock` is built for musl (Alpine) and fails with `varlock: not found` on Debian/Ubuntu images (`node`, `hasura/graphql-engine`). On those, download the glibc release as above. On Alpine images the official one fits, with two libraries added:

```dockerfile
RUN apk add --no-cache libstdc++ libgcc
COPY --from=ghcr.io/dmno-dev/varlock:1.21.0 /usr/local/bin/varlock /usr/local/bin/varlock
RUN varlock install-plugin @varlock/hashicorp-vault-plugin@2.1.1
```

References: `/Volumes/Projects/playground/format/db/docker/Dockerfile` (glibc) and `/Volumes/Projects/playground/format/tunnel/docker/Dockerfile` (Alpine).

Build context is the **service folder** (`..` from `docker/`). When the app imports shared code from the repo root (potion's `shared/`), make the context the repo root and copy that folder too, as `potion/mcp` does.

## docker/entrypoint.sh

See the prod branch under compose.prod.yaml below: in prod, the entrypoint loops instead of `exec`.

## Compose only: docker/compose.dev.yaml

On Kubernetes, hot reload comes from Skaffold's file sync instead of this bind mount ([kubernetes.md](kubernetes.md)).

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
      - /usr/app/app/node_modules      # empty: hides the Mac's node_modules (the image's are in /usr/app)
      # - /usr/app/app/.next           # Next.js: hide the host's build cache too
```

Node resolves modules by walking up from the source, so the image's `/usr/app/node_modules` serves the bind-mounted code, and the empty anonymous volume hides whatever macOS-built modules sit in `app/`. Don't put the image's modules *in* the anonymous volume (the older pattern): compose reuses anonymous volumes across `up --build`, so new dependencies silently never arrive.

The dev server takes its port from the schema: `"dev": "next dev --port $PORT"`, not a number in `package.json`.

To test a container by hand, run it on the project network (`docker run --network <project>_default …`); on the default bridge it can't reach Vault.

## Compose only: docker/compose.prod.yaml

For a standalone host (`deploy` → compose-host.md).

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
    # called by another server in prod? bind the private address, never Tailscale:
    #   - "${PRIVATE_IP:?}:5080:5080"
    # also reached from the Mac (a prod Hasura)? add "${TAILSCALE_IP:?}:5080:5080". Never 0.0.0.0.
    environment:
      APP_ENV: prod
      VAULT_ADDR: http://vault.tail0e3587.ts.net:8200
    secrets: [vault_role_id, vault_secret_id]
secrets:
  vault_role_id:   { file: /run/ghostmind/<project>/<app>/role_id }     # host RAM, written per deploy
  vault_secret_id: { file: /run/ghostmind/<project>/<app>/secret_id }   # single-use, deleted after start
```

Prod authenticates with a **single-use AppRole login** that the deploy workflow drops into host RAM. It is mounted into the container as compose secrets (`/run/secrets/*`, never in env). The schema reads them into `VAULT_ROLE_ID` / `VAULT_SECRET_ID` with `if(forEnv(prod), exec("cat /run/secrets/…"))` (see the `secrets` skill). The `deploy` skill covers the whole flow.

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

## Compose only: scripts/

```bash
# scripts/dev.sh
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose -p <project> -f docker/compose.dev.yaml up --build

# scripts/prod.sh
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose -p <project> -f docker/compose.prod.yaml up --build -d --force-recreate
```

When `compose.prod.yaml` binds the private or Tailscale address, `prod.sh` exports them first (reference: `/Volumes/Projects/ghostmind/users/state/scripts/prod.sh`):

```bash
export PRIVATE_IP=$(ip -4 -o addr show | awk '$4 ~ /^10\.0\.0\./ {sub(/\/.*/, "", $4); print $4; exit}')
[ -n "$PRIVATE_IP" ] || { echo "no 10.0.0.x private address on this host" >&2; exit 1; }
export TAILSCALE_IP=$(tailscale ip -4)        # only if the Mac reaches this port
```

`-p <project>` puts every app of the project on one network. `--force-recreate` matters in prod: without it an unchanged image isn't restarted, and the deploy's "restarted since the deploy began" check fails. The project name also prefixes named volumes (`<project>_tunnel-creds`); when migrating, keep `-p` identical to the legacy project name so volumes carry over. `dev.sh` is called through `varlock run --include-internal --`, so `${PORT}` and `${VAULT_*}` are set when compose interpolates. **`--include-internal` is required whenever a child needs `VAULT_TOKEN`**: the token is an internal item, and without the flag varlock hands the child an empty one, so the dev container can't reach Vault and scripts calling the `vault` CLI get permission denied. Routines that don't pass the token on (host-only builds, the traefik dev script) can drop the flag. `prod.sh` runs **without** varlock: `compose.prod.yaml` is literal and only the container talks to Vault, so the server and CI never hold app secrets.

## meta.json

On Kubernetes the routine is `"dev": "skaffold dev"` and there is no `prod` routine (prod deploys through CI only). The Compose form:

```json
{
  "id": "<12 random chars>",
  "name": "<app>",
  "type": "app",
  "routines": {
    "dev": "varlock run --include-internal -- bash scripts/dev.sh",
    "prod": "bash scripts/prod.sh"
  },
  "herdr": { "workspaces": [ { "label": "<project>", "tabs": [ {
    "label": "<app>", "prefix": false, "layout": "compact",
    "compact": { "type": "vertical", "panes": [
      { "name": "dev", "description": "dev server with hot reload (run routine dev), long-running" },
      { "name": "execution-shell", "description": "ad-hoc commands" }
    ] } } ] } ] }
}
```

`"prefix": false` keeps tab names to one word. Without it, `run herdr` prefixes a sub-app's tabs with the app name, so `mcp` becomes `mcp-mcp`.

## .gitignore (project root)

```gitignore
node_modules/
dist/
.DS_Store
# varlock: only the committed .env.schema exists (older apps: also .env.dev / .env.prod).
# A .env.local must never exist (varlock always loads it, whatever the environment).
.env
.env.local
.env.*.local
```

Never ignore `.env.schema` (or `.env.dev` / `.env.prod` where an app still has them): they are the committed pointer files. Legacy `.gitignore`s ignore `.env.*` or `.env.prod`, which silently drops them from git; replace those lines.
