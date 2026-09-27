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
6. **Expose only what must be public.** Internal services stay on Tailscale. A Cloudflare tunnel exists only if an endpoint is public, and Traefik only if several public hostnames share that tunnel.

## Project shape

```
<project>/                       one git repo = one product
  meta.json                      transitional: name, routines, herdr workspace
  CLAUDE.md  Readme.md  .gitignore
  .github/workflows/<app>.yaml   one per deployable app
  <app>/                         one folder per service (ui, mcp, api, worker, db, tunnel, traefik…)
    .env.schema  .env.dev  .env.prod     committed; pointers only
    app/                         source
    docker/  Dockerfile  entrypoint.sh  compose.dev.yaml  compose.prod.yaml
    scripts/ dev.sh  prod.sh  (+ migrate.sh, create-db.sh…)
    meta.json                    routines + herdr tab for this app
```

All apps of a project share one compose network (`docker compose -p <project>`), so they reach each other by container name (`<project>-<app>:<port>`).

## Building blocks and their reference apps

Replicate the reference; do not invent a new pattern when one exists. When a newer project does a block better, update this table so the reference moves to it.

| Block | Use when | Reference |
|---|---|---|
| Web app + Google login | Most products | `/Volumes/Projects/ghostmind/potion/ui` (Next.js + next-auth Google) |
| Remote MCP + Google OAuth | Most products, usually alongside the web app | `/Volumes/Projects/ghostmind/potion/mcp` (Express + MCP SDK, `app/src/auth/google.ts`, `oauth-routes.ts`) |
| Database | The product has state | `/Volumes/Projects/ghostmind/potion/db` (Hasura on the shared RDS) |
| Worker / internal service | Background jobs, no public endpoint | `/Volumes/Projects/ghostmind/potion/worker` |
| Tunnel | Something must be public | `/Volumes/Projects/ghostmind/potion/tunnel` |
| Traefik | Several public hostnames behind one tunnel | `/Volumes/Projects/ghostmind/potion/traefik` |
| Secrets via varlock (host-side scripts) | Script/CLI projects, Cloud Run | `/Volumes/Projects/playground/inference/.env.schema` |
| iOS / Expo | Mobile | `/Volumes/Projects/ghostmind/potion/native` |
| Raycast extension | Mac launcher tools | `/Volumes/Projects/labo/projects` |
| Swift macOS app | Native Mac | `/Volumes/Projects/playground/format` |
| Python CLI/package | Tooling | `/Volumes/Projects/labo/theme` |

The reference apps predate varlock: copy their **app code and structure**, and take secrets, compose and deploy from the `secrets` and `new-app` skills instead.

## Naming

| Thing | Pattern | Example |
|---|---|---|
| Container | `<project>-<app>` | `potion-mcp` |
| Vault, app secrets | `ghostmind/project/<project>/<app>` (+ `/dev`, `/prod`) | `ghostmind/project/potion/mcp/prod` |
| Vault, shared secrets | `ghostmind/global/<provider>`; look it up live (`secrets` skill) | `ghostmind/global/openrouter` |
| Database | `<project>_<app>_<env>` | `potion_db_prod` |
| Routines | `dev`, `prod`, then verbs (`migrate`, `create_db`) | |
| Dev domain / prod domain | `<app>.ghostmind.app` / the product domain | `mcp.ghostmind.app` / `mcp.potion.run` |

Local ports must be unique across **all** projects so two projects can run at once. Before picking one, check what is taken: `grep -rhoE '^PORT=[0-9]+' /Volumes/Projects/*/*/*/.env.schema /Volumes/Projects/*/*/*/.env.base 2>/dev/null | sort -u`.

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
