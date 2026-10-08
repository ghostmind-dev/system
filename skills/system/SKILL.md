---
name: system
description: >-
  The Ghostmind development system: how every project is built, configured, secured and deployed.
  Load first for any work on a Ghostmind project — creating an app, adding a service (web, remote MCP,
  worker, DB, tunnel), secrets or env vars, Docker, Kubernetes (k3s, Skaffold), Compose, deploys,
  servers, meta.json, routines, herdr, or the `run` CLI. Routes to the new-app, secrets, deploy, database, migrate and comply skills.
---

# Ghostmind System

The system is **a few plain tools plus reference apps**. There is no framework to learn: Kubernetes manifests, plain Bash, varlock and GitHub workflows. What makes a project "Ghostmind" is that it follows these conventions, and the way to build something is to **replicate a reference app** that already does it well.

| Pillar | Tool | Skill |
|---|---|---|
| **Secrets** | varlock `.env.schema` pointing into Vault (`ghostmind/` KV v2 mount) | `secrets` |
| **Run** | **Kubernetes, in prod and in dev**: the k3s cluster on Hetzner, and an OrbStack cluster in dev (this Mac's, or another Mac's over Tailscale) with Skaffold and hot reload. Every Ghostmind product runs this way | `new-app` |
| **Deploy** | GitHub Actions on merge to main: build the image, log in to the cluster with the run's OIDC token, apply by digest | `deploy` |

**Compose stays in the toolbox** for targets that aren't the cluster: Cloud Run (build and run locally with Compose, deploy with the provider's CLI), a one-off container, a script project. It is the exception: no product under `/Volumes/Projects/ghostmind` holds a compose file any more (Vault's own server, outside the cluster, is the one Compose host). Start from Kubernetes, and reach for Compose only when the target can't be the cluster.

Creating something new → `new-app`. A Postgres DB → `database`. Converting an app still on `.env.base` / `run vault` → `migrate`. Checking a project against these rules and fixing drift → `comply`.

## Rules every project follows

1. **Every process that needs config starts through varlock.** Dev scripts and one-off commands: `varlock run -- <cmd>`. Every container has `varlock run --` as its entrypoint, so in prod only the pod talks to Vault, logging in with its own service-account token. A variable that is not declared in `.env.schema` does not exist.
2. **Nothing secret lives in the repo or on disk.** One `.env.schema` per app is committed and holds only defaults and *pointers* (`vaultSecret(...)`), with `if(forEnv(prod), …)` for what differs per environment. Values live in Vault.
3. **Two environments: `dev` and `prod`**, selected by `APP_ENV`. Never name one `local`: varlock always loads a file called `.env.local` whatever the environment, so its pointers would leak into prod.
4. **Logic lives in `scripts/*.sh`; a routine is a one-liner that calls it.** Plain Bash, readable by anyone, with no `run custom` and no `jsr:@ghostmind/run` imports. `run routine` has no shell, so `bash -c "cd app && …"` breaks: anything with `cd`, `&&`, pipes or quotes goes in a script.
5. **Hot reload in dev is required.** `skaffold dev` copies each edited source file into the running container (`sync: infer`) and the dev server reloads it. (Compose apps: a bind mount of the source.)
   **Prod changes only through a merge to main.** GitHub Actions is the only thing that deploys. No `kubectl apply`, `edit` or `exec` against prod to change an app; read-only checks are fine.
6. **AI-operable by default.** A product ships a way for Claude to operate it: a remote **MCP** (the app's actions as tools) and a **Claude plugin** whose skill teaches the app's concepts and traps. Much of the work around an app goes faster through an AI than by hand. When planning a product, ask what the user will want to do with it through Claude; skip the MCP and plugin only when the answer is honestly nothing (a static site, a pure internal worker).
7. **Ask before changing shared infrastructure**: a `ghostmind/global/*` key another project reads, a tailnet node's tags, Vault auth methods, roles or policies, the prod cluster (namespaces, RBAC, nodes), the shared RDS. Add alongside rather than rename; remove only what nothing reads.
8. **Pick the network by where the two ends run.**
   - **Inside a project: Service names**, `<project>-<app>:<port>`, the same in dev and prod.
   - **Between projects and to Vault: an address stored in Vault or the schema** (for example `DB_USERS_ENDPOINT`, `VAULT_ADDR=http://10.0.0.7:8200`), never a hardcoded cluster name, so an app can move without code changes.
   - **Between Hetzner servers: the Hetzner private network (10.0.0.x), never Tailscale.** It is free, built in and one less thing to fail.
   - **Across providers** (Hetzner ↔ Google Cloud, the M1 Mac…): Tailscale is allowed for running prod traffic, as a deliberate link. The node is tagged (tagged nodes don't expire), the ACL allows only that path, and the link is monitored. For a managed service with no persistent host (Cloud Run), use public HTTPS with auth instead.
   - **Shared users:** local users in dev (`state.users.svc.cluster.local:5090`) and the same Service on 5080 in prod, both through `DB_USERS_ENDPOINT` in Vault. Dev can't read the prod value.
   - **Dev and deploy** (the Mac, CI reaching the cluster API, SSH, debugging) use Tailscale.
   Inside the cluster: NetworkPolicies (default deny), no Istio, no Ingress for now (Gateway API if one tunnel ever fronts the whole cluster).
   Addresses: `/Volumes/Projects/home/networking.md`.
9. **Expose only what must be public.** A Cloudflare tunnel exists only if an endpoint is public, and it sends each hostname straight to its app's Service. There is no Traefik.
10. **Apps stay portable.** The image plus `.env.schema` is the app. No app depends on a Kubernetes feature to work, so it can run under Compose, on Cloud Run or on another cluster unchanged.

## Project shape

```
<project>/                       one git repo = one product
  meta.json                      type project: name, tags, groups, routines, herdr workspace
  CLAUDE.md  README.md  .gitignore
  .github/workflows/             _deploy-k8s.yaml (reusable) + deploy.yaml (one job per app)
  <app>/                         one folder per service (ui, mcp, api, worker, db, tunnel, mac, cli…)
    .env.schema                  committed; pointers only, both environments
    app/                         source
    docker/  Dockerfile  entrypoint.sh
    k8s/     <app>.yaml  <app>.dev.yaml      prod and dev manifests
    skaffold.yaml                dev on the current kube context (names no cluster)
    .dockerignore                node_modules, .next, dist
    scripts/                     the app's own verbs: migrate.sh, create-db.sh…
    meta.json                    routines dev, dev_keep, delete (skaffold) + herdr tab for this app
  k8s/                           the project's scripts: dev-setup.sh (pre-deploy hook shared by the apps), remove.sh, prod-init.sh (one-time prod setup, `deploy` skill)
  shared/                        only when several backends share TypeScript; the apps then build from the root
  plugin/                        the product's Claude plugin: .mcp.json + skills (see new-app → blocks.md)
```

**The root holds only `README.md`, `CLAUDE.md`, `meta.json`, `.gitignore`, `.github/`, `k8s/` (the project's dev scripts), `shared/` with a root `.dockerignore` when backends share code, and, when the product ships a Claude plugin, `plugin/` and `.claude-plugin/marketplace.json`.** Every app, including non-web ones (a Swift app, a CLI), lives in its own service folder. Nothing app-specific (`package.json`, `src/`, `test/`) stays at the root.

`docker/compose.*.yaml` exists only when the app isn't on Kubernetes. One project = one namespace, named after the project, in dev and prod. Apps reach each other by Service name (`<project>-<app>:<port>`), the same name the container had under Compose.

## Building blocks and their reference apps

Replicate the reference; do not invent a new pattern when one exists. When a newer project does a block better, update this table so the reference moves to it.

| Block | Use when | Reference |
|---|---|---|
| **Kubernetes app, dev and prod** | The default for a new app | `/Volumes/Projects/ghostmind/portal` (`portal/` = ui, `tunnel/`): `k8s/<app>.yaml` + `<app>.dev.yaml`, `skaffold.yaml` per app with hot reload, no Compose. Details: `new-app` → kubernetes.md |
| **Prod deploy to the cluster** | Every app on k3s | `/Volumes/Projects/ghostmind/portal/.github/workflows/` (`_deploy-k8s.yaml`, `deploy.yaml`); also `tags` (five apps) |
| **Skaffold dev with hot reload** | Dev for every Kubernetes app | `/Volumes/Projects/ghostmind/portal/portal/skaffold.yaml` (`sync: infer`), `/Volumes/Projects/ghostmind/tags/k8s/dev-setup.sh` (namespace, volume, dev-session Vault token) and `k8s/remove.sh` |
| **Vault login by service account** | A pod that reads secrets | `/Volumes/Projects/ghostmind/tags/city/k8s/city.yaml` + `.env.schema`; `portal/tunnel` |
| **Tunnel without Traefik** | Something must be public | `/Volumes/Projects/ghostmind/portal/tunnel`, `/Volumes/Projects/ghostmind/tags/tunnel` |
| Cluster and node setup | Adding a node or a project to the cluster | `/Volumes/Projects/ghostmind/start/host/k3s/` and `host/scripts/server-bootstrap.sh` |
| Remote MCP + Google OAuth (the product's auth server) | Most products | `/Volumes/Projects/ghostmind/format/mcp` (Google-proxy OAuth with enforced PKCE, allow-listed redirects, signed state: `app/src/auth/oauth.ts`) for the OAuth; `/Volumes/Projects/ghostmind/potion/mcp` (`app/src/main.ts`) for the transport: **stateless on the cluster**, MCP SDK v2, no sessions (`new-app` → blocks.md) |
| **Claude plugin for the product** (MCP + skill) | Almost every product: how the user operates it through Claude | `/Volumes/Projects/ghostmind/potion/plugin` (`.mcp.json` → the remote MCP, `skills/potion`, `skills/potion-blocks`); smaller: `/Volumes/Projects/ghostmind/tags/plugin` |
| Web app, simple | Default: signs in through the MCP server's OAuth, so web, MCP and native share one auth system | `/Volumes/Projects/ghostmind/format/ui` (static React + TanStack, Vite) |
| Web app, full-stack | Needs server rendering or its own API routes | `/Volumes/Projects/ghostmind/potion/ui` (Next.js + next-auth Google) |
| Native app signing in to the product | Mac/iOS app with user accounts | `/Volumes/Projects/ghostmind/format/mac/app/Sources/Format/Account.swift` (RFC 8252 loopback + PKCE, tokens in the Keychain) |
| Bring-your-own OpenRouter | Users pay for their own AI | `/Volumes/Projects/ghostmind/format` (OpenRouter PKCE, key AES-GCM in an `ai_connections` table no user role can read); same pattern as `potion/agent/ai-connection.ts` |
| Terraform | Cloud resources (GCS bucket + service account) | `/Volumes/Projects/ghostmind/tags/bucket` (Terraform in a container through varlock) |
| Database | The product has state | `/Volumes/Projects/ghostmind/tags/db` (Hasura on the cluster, migrations applied in the container); `/Volumes/Projects/ghostmind/format/db` for `create-db.sh` |
| Worker / internal service | Background jobs, no public endpoint | `/Volumes/Projects/ghostmind/potion/worker` (a Deployment and Service with no tunnel route) |
| Compose + Cloud Run (not on the cluster) | A managed target, a script project | `/Volumes/Projects/playground/inference` (bash + gcloud, varlock on the host) |
| Shared service, always on in dev | A service other products call | `/Volumes/Projects/ghostmind/users` (`start` routine, its own dev database) |
| Stateful app on a volume, tailnet only | An internal tool | `/Volumes/Projects/ghostmind/admin` (SQLite on a volume, Tailscale Serve) |
| Compose on a standalone host | An app that can't go on the cluster | `deploy` → compose-host.md. No product uses it today: tags and users did before moving to the cluster (their git history) |
| iOS / Expo | Mobile | `/Volumes/Projects/ghostmind/tags/native` (varlock, signing and creds scripts); older: `potion/native` |
| Raycast extension | Mac launcher tools | `/Volumes/Projects/labo/projects` |
| Swift macOS app | Native Mac | `/Volumes/Projects/ghostmind/format/mac` (`scripts/dev.sh`: watch, rebuild, re-sign, relaunch) |
| Python CLI/package | Tooling | `/Volumes/Projects/labo/theme` |

`portal` is the reference for how an app is packaged and run; `format` and `tags` are references for app code (auth, web, native, db). Every project in the table runs on Kubernetes in dev and prod, with no Traefik and no compose file, so manifests, Skaffold files and workflows can be copied from any of them; `portal` and `tags` are the cleanest. What is still legacy: potion's `bucket` (`.env.base`, `run` scripts) and leftover `.env.base` / `.env.template` files in `potion/chrome` and `potion/native`; several entrypoints (portal's tunnel, tags, format, users) still loop in prod, a Compose habit (`new-app` → docker.md). **Don't copy `potion/mcp`'s OAuth**: it doesn't enforce PKCE, accepts any redirect URI and leaves `state` unsigned; take format's instead. Its stateless transport (`app/src/main.ts`) is the reference for every MCP on the cluster.

## Naming

| Thing | Pattern | Example |
|---|---|---|
| Service (and container) | `<project>-<app>` | `portal-ui` |
| Namespace | `<project>` | `portal` |
| Image | `ghcr.io/ghostmind-app/<project>-<app>` | `ghcr.io/ghostmind-app/portal-ui` |
| Vault role and policy | `<project>-<app>` (at `auth/k8s`) | `portal-tunnel` |
| Vault, app secrets | `ghostmind/project/<project>/<app>` (+ `/dev`, `/prod`) | `ghostmind/project/potion/mcp/prod` |
| Vault, shared secrets | `ghostmind/global/<provider>`; look it up live (`secrets` skill) | `ghostmind/global/openrouter` |
| Database | `<project>_<app>_<env>` | `potion_db_prod` |
| Routines | `dev` (`skaffold dev`), then verbs (`migrate`, `create_db`); no `prod` routine | |
| Public host | `<app>.ghostmind.app` (dev) / `<app>.ghostmind.dev` (prod); see Domains | `format.ghostmind.app` / `format.ghostmind.dev` |

## Domains

Both domains are in the Cloudflare account. **`ghostmind.app` is dev; `ghostmind.dev` is prod.**

- **An app is one host per environment**: `<app>.ghostmind.app` and `<app>.ghostmind.dev`. Most apps never get their own domain. A product that has one (potion.run, tags.city) uses it for prod instead of `ghostmind.dev`.
- **One level deep only**: `<app>.ghostmind.dev`, never `mcp.<app>.ghostmind.dev`. Cloudflare's free Universal SSL covers one level of subdomain.
- **The bare `ghostmind.dev` belongs to portal**; apps only take subdomains.
- **Services are paths on that host, not subdomains.** The tunnel's ingress routes by `path:`, most specific first:

  | Path | Service |
  |---|---|
  | `/mcp` | the MCP server |
  | `/.well-known/oauth-*`, `/oauth/*` | the MCP server (it is the OAuth server; see `new-app` → blocks.md) |
  | `/api` | the API |
  | everything else | the web UI |

  Each service serves its routes **under its own prefix** (the API at `/api/v1/...`; the tunnel doesn't strip prefixes), so URLs it builds for itself (OAuth issuer, redirect URIs, links) are the real public ones. `PUBLIC_URL` is `https://<app>.ghostmind.app` / `https://<app>.ghostmind.dev`.

Projects on separate subdomains (`mcp.tags.city`, `format-mcp.ghostmind.app`, potion's `mcp.potion.run`) predate this rule; they move to paths when they're next reworked.

## Ports

Every port a project uses **on the Mac** must be unique across all projects, so any two can run side by side: Skaffold's `localPort` forwards, tool ports such as the Hasura console, and a Compose `ports:` where one exists. Inside the cluster a port only has to be unique within its project, but keep one number per app everywhere (container, Service, forward) so addresses read the same in dev and prod.

**Pick from the registry below**, and add the new project's row in the same change. Then confirm nothing is listening: `lsof -iTCP -sTCP:LISTEN -nP | grep :<port>`.

| Project | Ports |
|---|---|
| portal | ui 5096 |
| tags | city 5085 · db 5086 · mcp 3085 · native 3086 |
| format | db 5075 · ui 5076 · mcp 3075 · Hasura console 9705 / api 9703 |
| users | state 5090 (dev forward; the Service is 5080 in prod, consumers hardcode it) · Hasura console 9727 / 9728 |
| potion | ui 5001 · mcp 3020 · chrome 3025 · worker 3030 · api 3040 · native 3055 · db 5080 · Hasura console 9693 / 9695 |
| noice | ui 5065 |
| admin | dashboard 5095 |
| magneto | api 3035 · db 5035 · ui 5036 |
| together (playground) | api 3045 · db 5045 · ui 5046 · web 3060 |
| vault | 8200 |

For a new project, pick unused numbers in the usual ranges: 5000–5999 for web and db, 3000–3999 for APIs and MCPs, 9700–9799 for tool ports.

## meta.json and `run`

`run` operates projects on the Mac, and every folder's `meta.json` is what it reads. Its own skill (the `run` plugin, shipped from the `run` repo) holds the detail; load it for anything beyond this summary.

- `run projects`: the dashboard. Every folder whose `meta.json` has `type: "project"`, with its herdr workspace, git branch and uncommitted changes; workspaces are opened and closed from it, alone or by tag or group. This is where most of the work happens. To ask what exists or what is running, use `run projects --json` (add `--panes` for what each pane runs) rather than reading folders.
  - **Opening a project** builds its workspace and asks which of its panes' routines to start: all, a hand-picked few, or one **profile**.
  - **Saved views** filter the table (by tag, group, folder, organization, machine, status, git state); they live in `~/.config/run/projects.json`.
  - **Other machines**: projects on a Mac saved in herdr (`herdr machine add`) appear in the same table and are opened there over SSH.
- `run routine <name>`: runs a `routines` entry. It splits on spaces **without a shell**, so pipes, quotes and redirects belong inside a script.
- `run herdr init|attach|terminate <workspace>`: builds the herdr workspace from the `herdr` blocks. `init --start` also runs the routine each pane names; `--profile <name>` or `--only <tab/pane,...>` narrows which.
- `run herdr colors [on|off]`: shows or hides each project's colour mark in herdr's sidebar. Fetch the schema before editing a `herdr` block: `https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json`.

A meta.json carries `id` (12-char random), `name`, `type` (`project` at the root, `app` per service), `description`, `tags`, `groups`, `routines`, `herdr`. `tags` describe a project; `groups` name sets of projects worked on together. In the `herdr` block, a workspace may carry a `color` (its mark in herdr's sidebar), and a pane may name the `routine` it usually runs and the `profiles` it is part of. A profile is a set of routines started together for one way of working on a project (`web`, `mobile`), tagged pane by pane across the project's apps.

**Removed in run 0.9.0, they no longer exist:** `run custom`, `run vault kv`, `run docker`, `run terraform`, `run tmux`, `run meta`, `run action`, `run misc`, and the meta.json keys `compose`, `docker`, `terraform`, `custom`, `tmux`, `template`, `global`. A project still calling one is converted with the `migrate` skill: its scripts become `scripts/*.sh`.

**Still present but on its way out:** `--cible`/`--env` env loading with `.env.base`/`.env.local`, and the `secrets` key. New work never uses them.

## Environment

- No devcontainers: everything runs on the Mac host (projects under `/Volumes/Projects`).
- **OrbStack** replaces Docker Desktop: Docker plus a local Kubernetes cluster, and the cluster uses locally built images with no push. **A dev machine is a pair**, a kube context and a Docker context for the same OrbStack, switched together (`kubectl config use-context X && docker context use X`): an image exists only on the daemon that built it. Contexts are per Mac and **no file in a repo names a cluster** (no `kubeContext` in `skaffold.yaml`): `skaffold dev` uses the current context. Another Mac's OrbStack over Tailscale needs its Docker context on an SSH-forwarded unix socket, not `ssh://` (Skaffold cannot dial it): `new-app` → kubernetes.md → Dev machines. `ghostmind` is the prod context (read-only use): scripts that touch prod always pass `--context ghostmind`, never the current context.
- After an OrbStack restart, builds can fail with `proxy.orb.internal … i/o timeout`: `orb stop && orb start`. OrbStack has 10 GB of RAM.
- Compose paths (when an app has them) are **relative to the compose file**; `SRC`/`LOCALHOST_SRC` are legacy.
- `VAULT_ADDR` and `VAULT_TOKEN` are exported in the shell. There is no `~/.vault-token`, so schemas pass the token explicitly.
- Tools on the host: `varlock` (brew `dmno-dev/tap/varlock`), `vault`, `docker`, `kubectl`, `skaffold`, `gh`, `tailscale`, `herdr`.
- GitHub orgs: product repos live in **`ghostmind-app`** (older remotes still say `ghostmind-dev` and redirect); system tooling (this plugin, `run`, `play`) is in `ghostmind-dev`. Hosts, Tailscale and private addresses: `/Volumes/Projects/home/networking.md`.
- The Tailscale CLI isn't on the Mac's PATH: `/Applications/Tailscale.app/Contents/MacOS/Tailscale`.
- The Mac's shell is zsh: `for path in …` overwrites `$PATH`; an unquoted glob like `--include=*.ts` fails with "no matches found"; `timeout` doesn't exist. Put loops and anything glob-heavy in a `bash` script.
