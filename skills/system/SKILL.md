---
name: system
description: >-
  The Ghostmind development system: how every project is built, configured, secured and deployed.
  Load first for any work on a Ghostmind project — creating an app, adding a service (web, remote MCP,
  worker, DB, tunnel), secrets or env vars, Docker/compose, deploys, servers, meta.json, routines,
  herdr, or the `run` CLI. Routes to the new-app, secrets, deploy, database and migrate skills.
---

# Ghostmind System

The system is **three pillars plus reference apps**. There is no framework to learn: plain Docker Compose, plain Bash, plain GitHub workflows. What makes a project "Ghostmind" is that it follows these conventions, and the way to build something is to **replicate a reference app** that already does it well.

| Pillar | Tool | Skill |
|---|---|---|
| **Secrets** | varlock `.env.schema` pointing into Vault (`ghostmind/` KV v2 mount) | `secrets` |
| **Deploy** | one GitHub workflow per app → Tailscale SSH → `docker compose` on the host | `deploy` |
| **Server** | hardened Hetzner host(s), reachable only over Tailscale; one per product today, possibly one big shared prod host later | `deploy` |

Creating something new → `new-app`. A Postgres DB → `database`. Converting an app still on `.env.base` / `run vault` → `migrate`.

## Rules every project follows

1. **Every process that needs config starts through varlock.** Dev scripts, compose in dev, one-off commands: `varlock run -- <cmd>`. Every container has `varlock run --` as its entrypoint, so in prod only the container talks to Vault. A variable that is not declared in `.env.schema` does not exist.
2. **Nothing secret lives in the repo or on disk.** `.env.schema`, `.env.dev` and `.env.prod` are committed and hold only defaults and *pointers* (`vaultSecret(...)`). Values live in Vault.
3. **Two environments: `dev` and `prod`**, selected by `APP_ENV`. Never name one `local`: varlock always loads a file called `.env.local` whatever the environment, so its pointers would leak into prod.
4. **Logic lives in `scripts/*.sh`; a routine is a one-liner that calls it.** Plain Bash, readable by anyone, with no `run custom` and no `jsr:@ghostmind/run` imports.
5. **Hot reload in dev.** `compose.dev.yaml` bind-mounts the app source; the dev server watches it.
6. **AI-operable by default.** A product ships a way for Claude to operate it: a remote **MCP** (the app's actions as tools) and a **Claude plugin** whose skill teaches the app's concepts and traps. Much of the work around an app goes faster through an AI than by hand. When planning a product, ask what the user will want to do with it through Claude; skip the MCP and plugin only when the answer is honestly nothing (a static site, a pure internal worker).
7. **Expose only what must be public.** Internal services stay on Tailscale. A Cloudflare tunnel exists only if an endpoint is public, and Traefik only when one public host carries several services (see Domains).

## Project shape

```
<project>/                       one git repo = one product
  meta.json                      transitional: name, routines, herdr workspace
  CLAUDE.md  README.md  .gitignore
  .github/workflows/<app>.yaml   one per deployable app
  <app>/                         one folder per service (ui, mcp, api, worker, db, tunnel, traefik, mac, cli…)
    .env.schema  .env.dev  .env.prod     committed; pointers only
    app/                         source
    docker/  Dockerfile  entrypoint.sh  compose.dev.yaml  compose.prod.yaml
    scripts/ dev.sh  prod.sh  (+ migrate.sh, create-db.sh…)
    meta.json                    routines + herdr tab for this app
  plugin/                        the product's Claude plugin: .mcp.json + skills (see new-app → blocks.md)
```

**The root holds only `README.md`, `CLAUDE.md`, `meta.json`, `.gitignore`, `.github/` and, when the product ships a Claude plugin, `.claude-plugin/marketplace.json`.** Every app, including non-web ones (a Swift app, a CLI), lives in its own service folder. Nothing app-specific (`package.json`, `src/`, `test/`) stays at the root.

All apps of a project share one compose network (`docker compose -p <project>`), so they reach each other by container name (`<project>-<app>:<port>`).

## Building blocks and their reference apps

Replicate the reference; do not invent a new pattern when one exists. When a newer project does a block better, update this table so the reference moves to it.

| Block | Use when | Reference |
|---|---|---|
| Remote MCP + Google OAuth (the product's auth server) | Most products | `/Volumes/Projects/playground/format/mcp` (Express + MCP SDK; Google-proxy OAuth with enforced PKCE, allow-listed redirects, signed state: `app/src/auth/oauth.ts`) |
| **Claude plugin for the product** (MCP + skill) | Almost every product: how the user operates it through Claude | `/Volumes/Projects/ghostmind/potion/plugin` (`.mcp.json` → the remote MCP, `skills/potion`, `skills/potion-blocks`); smaller: `/Volumes/Projects/ghostmind/tags/plugin` |
| Web app, simple | Default: signs in through the MCP server's OAuth, so web, MCP and native share one auth system | `/Volumes/Projects/playground/format/ui` (static React + TanStack, Vite) |
| Web app, full-stack | Needs server rendering or its own API routes | `/Volumes/Projects/ghostmind/potion/ui` (Next.js + next-auth Google) |
| Native app signing in to the product | Mac/iOS app with user accounts | `/Volumes/Projects/playground/format/mac/app/Sources/Format/Account.swift` (RFC 8252 loopback + PKCE, tokens in the Keychain) |
| Bring-your-own OpenRouter | Users pay for their own AI | `/Volumes/Projects/playground/format` (OpenRouter PKCE, key AES-GCM in an `ai_connections` table no user role can read); same pattern as `potion/agent/ai-connection.ts` |
| Database | The product has state | `/Volumes/Projects/playground/format/db` (Hasura on the shared RDS, varlock-native); older: `potion/db` |
| Worker / internal service | Background jobs, no public endpoint | `/Volumes/Projects/ghostmind/potion/worker` |
| Tunnel | Something must be public | `/Volumes/Projects/playground/format/tunnel` (varlock-native); older: `potion/tunnel` |
| Traefik | Several public hostnames behind one tunnel | `/Volumes/Projects/playground/format/traefik`; older: `potion/traefik` |
| Secrets via varlock (host-side scripts) | Script/CLI projects, Cloud Run | `/Volumes/Projects/playground/inference/.env.schema` |
| iOS / Expo | Mobile | `/Volumes/Projects/ghostmind/potion/native` |
| Raycast extension | Mac launcher tools | `/Volumes/Projects/labo/projects` |
| Swift macOS app | Native Mac | `/Volumes/Projects/playground/format/mac` (`scripts/dev.sh`: watch, rebuild, re-sign, relaunch) |
| Python CLI/package | Tooling | `/Volumes/Projects/labo/theme` |

`format` is the first project built on this system; prefer it where it has the block. The potion references predate varlock: copy their **app code and structure**, and take secrets, compose and deploy from the `secrets` and `new-app` skills instead. They also use the old environment name: `compose.local.yaml`, `ingress.local.yaml` and `.env.local` become `compose.dev.yaml`, `ingress.dev.yaml` and `.env.dev`. **Don't copy `potion/mcp`'s OAuth**: it doesn't enforce PKCE, accepts any redirect URI and leaves `state` unsigned; take format's instead.

## Naming

| Thing | Pattern | Example |
|---|---|---|
| Container | `<project>-<app>` | `potion-mcp` |
| Vault, app secrets | `ghostmind/project/<project>/<app>` (+ `/dev`, `/prod`) | `ghostmind/project/potion/mcp/prod` |
| Vault, shared secrets | `ghostmind/global/<provider>`; look it up live (`secrets` skill) | `ghostmind/global/openrouter` |
| Database | `<project>_<app>_<env>` | `potion_db_prod` |
| Routines | `dev`, `prod`, then verbs (`migrate`, `create_db`) | |
| Public host | `<app>.ghostmind.app` (dev) / `<app>.ghostmind.dev` (prod); see Domains | `format.ghostmind.app` / `format.ghostmind.dev` |

## Domains

Both domains are in the Cloudflare account. **`ghostmind.app` is dev; `ghostmind.dev` is prod.**

- **An app is one host per environment**: `<app>.ghostmind.app` and `<app>.ghostmind.dev`. Most apps never get their own domain. A product that has one (potion.run, tags.city) uses it for prod instead of `ghostmind.dev`.
- **One level deep only**: `<app>.ghostmind.dev`, never `mcp.<app>.ghostmind.dev`. Cloudflare's free Universal SSL covers one level of subdomain.
- **The bare `ghostmind.dev` belongs to portal**; apps only take subdomains.
- **Services are paths on that host, not subdomains.** Traefik routes by path prefix:

  | Path | Service |
  |---|---|
  | `/mcp` | the MCP server |
  | `/.well-known/oauth-*`, `/oauth/*` | the MCP server (it is the OAuth server; see `new-app` → blocks.md) |
  | `/api` | the API |
  | everything else | the web UI |

  Each service serves its routes **under its own prefix** (the API at `/api/v1/...`, not `/v1/...` behind a strip-prefix), so URLs it builds for itself (OAuth issuer, redirect URIs, links) are the real public ones. `PUBLIC_URL` is `https://<app>.ghostmind.app` / `https://<app>.ghostmind.dev`.

Projects on separate subdomains (`format-mcp.ghostmind.app`, potion's `mcp.potion.run`) predate this rule; they move to paths when they're next reworked.

## Ports

Every port a project publishes on the host must be unique across **all** projects, so any two can run side by side. That includes secondary ports: the Hasura console (`--console-port`, `--api-port`), debuggers, anything in a compose `ports:`.

- **Traefik publishes no host port.** The tunnel reaches it on the compose network (`http://<project>-traefik:80`).
- **Pick from the registry below**, and add the new project's row in the same change. Then confirm nothing is listening: `lsof -iTCP -sTCP:LISTEN -nP | grep :<port>`.

| Project | Ports |
|---|---|
| format | db 5075 · ui 5076 · mcp 3075 · Hasura console 9705 / api 9703 |
| potion (legacy) | ui 5001 · mcp 3020 · chrome 3025 · worker 3030 · api 3040 · native 3055 · db 5080 · Hasura console 9693 / 9695 · traefik 80 / 8080 |
| tags (legacy) | city 5001 · mcp 3020 · native 3055 · db 5080 · Hasura console 9697 / 9698 · traefik 80 / 8080 |
| users (legacy) | db 5080 |
| portal (legacy) | portal 8089 · traefik 80 / 8080 |
| noice (legacy) | ui 5001 · traefik 80 / 8080 |
| vault | 8200 |

Legacy rows collide with each other: renumber them when the project is migrated. For a new project, pick unused numbers in the usual ranges: 5000–5999 for web and db, 3000–3999 for APIs and MCPs, 9700–9799 for tool ports.

## meta.json and `run` (transitional)

`run` and `meta.json` are being retired. Until then only two parts are live:

- `run herdr init|attach|terminate <workspace>`: builds the herdr workspace from the `herdr` block. Fetch the schema before editing it: `https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json`.
- `run routine <name>`: runs a `routines` entry. It splits on spaces **without a shell**, so pipes, quotes and redirects belong inside a script.

A new meta.json carries only `id` (12-char random), `name`, `type` (`project` at the root, `app` per service), `description`, `tags`, `routines`, `herdr`.

**Deprecated. They still work for existing projects, but new work never uses them:** `run custom`, `run vault kv`, `--cible`/`--env` env loading, `.env.base`/`.env.local`, `run docker`, `run terraform`, `run tmux`, `run meta`, `run action`, and the meta.json keys `compose`, `docker`, `terraform`, `custom`, `secrets`, `tmux`, `template`, `global`. Leave existing projects on them until they are migrated with the `migrate` skill.

## Environment

- No devcontainers: everything runs on the Mac host (projects under `/Volumes/Projects`). Compose paths are **relative to the compose file**; `SRC`/`LOCALHOST_SRC` are legacy.
- `VAULT_ADDR` and `VAULT_TOKEN` are exported in the shell. There is no `~/.vault-token`, so schemas pass the token explicitly.
- Tools on the host: `varlock` (brew `dmno-dev/tap/varlock`), `vault`, `docker`, `gh`, `tailscale`, `herdr`.
- GitHub org: `ghostmind-dev`. Hosts on Tailscale: see `/Volumes/Projects/home/networking.md`.
