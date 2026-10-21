---
name: system
description: >-
  The Ghostmind development system: how every project is built, configured, secured and deployed.
  Load first for any work on a Ghostmind project — creating an app, adding a service (web, remote MCP,
  worker, DB, tunnel), secrets or env vars, Docker, Kubernetes (k3s, Skaffold), Compose, deploys,
  servers, meta.json, routines, herdr, or the `run` CLI. Routes to the kickoff, new-app, secrets, deploy, database, migrate and comply skills.
---

# Ghostmind System

The system is **a few plain tools plus reference apps**. There is no framework to learn: Kubernetes manifests, plain Bash, varlock and GitHub workflows. What makes a project "Ghostmind" is that it follows these conventions, and the way to build something is to **replicate a reference app** that already does it well.

| Pillar | Tool | Skill |
|---|---|---|
| **Secrets** | varlock `.env.schema` pointing into Vault (`ghostmind/` KV v2 mount) | `secrets` |
| **Run** | **Kubernetes, in prod and in dev**: the k3s cluster on Hetzner, and the dev cluster in dev (the one that runs the shared dev services; nothing names it) with Skaffold and hot reload. Every Ghostmind product runs this way | `new-app` |
| **Deploy** | GitHub Actions on merge to main: build the image, log in to the cluster with the run's OIDC token, apply by digest | `deploy` |

**Compose stays in the toolbox** for targets that aren't the cluster: Cloud Run (build and run locally with Compose, deploy with the provider's CLI), a one-off container, a script project. It is the exception: no product holds a compose file any more (the Compose hosts are Vault's own server and the house's Zigbee bridge on a Raspberry Pi, both outside the cluster). Start from Kubernetes, and reach for Compose only when the target can't be the cluster.

Creating something new → `new-app`; setting up only its folder and herdr workspace and moving the work to a Claude session there → `kickoff`. A Postgres DB → `database`. Converting an app still on `.env.base` / `run vault` → `migrate`. Checking a project against these rules and fixing drift → `comply`. When a piece of work is done, the user asks for a debrief (`/system:debrief`, or in their own words: "update the system with what you learned"): what it taught goes back into these skills and into the `toolkits` skills.

## Rules every project follows

1. **Every process that needs config starts through varlock.** Dev scripts and one-off commands: `varlock run -- <cmd>`. Every container has `varlock run --` as its entrypoint, so in prod only the pod talks to Vault, logging in with its own service-account token. A variable that is not declared in `.env.schema` does not exist.
2. **Nothing secret lives in the repo or on disk.** One `.env.schema` per app is committed and holds only defaults and *pointers* (`vaultSecret(...)`), with `if(forEnv(prod), …)` for what differs per environment. Values live in Vault.
3. **Two environments: `dev` and `prod`**, selected by `APP_ENV`. Never name one `local`: varlock always loads a file called `.env.local` whatever the environment, so its pointers would leak into prod.
4. **Logic lives in `scripts/*.sh`; a routine is a one-liner that calls it.** Plain Bash, readable by anyone, with no `run custom` and no `jsr:@ghostmind/run` imports. `run routine` has no shell, so `bash -c "cd app && …"` breaks: anything with `cd`, `&&`, pipes or quotes goes in a script.
5. **Hot reload in dev is required.** `skaffold dev` copies each edited source file into the running container (`sync: infer`) and the dev server reloads it. (Compose apps: a bind mount of the source.)
   **Prod changes only through a merge to main.** GitHub Actions is the only thing that deploys. No `kubectl apply`, `edit` or `exec` against prod to change an app; read-only checks are fine.
6. **AI-operable by default.** A product ships a way for Claude to operate it: a remote **MCP** (the app's actions as tools) and a **Claude plugin** whose skill teaches the app's concepts and traps. Much of the work around an app goes faster through an AI than by hand. When planning a product, ask what the user will want to do with it through Claude; skip the MCP and plugin only when the answer is honestly nothing (a static site, a pure internal worker).
7. **Ask before changing shared infrastructure**: a `ghostmind/global/*` key another project reads, a tailnet node's tags, Vault auth methods, roles or policies, the prod cluster (namespaces, RBAC, nodes), the shared Postgres server (the `db` project). Add alongside rather than rename; remove only what nothing reads.
8. **Pick the network by where the two ends run.**
   - **Inside a project: Service names**, `<project>-<app>:<port>`, the same in dev and prod.
   - **Between projects and to Vault: an address stored in Vault or the schema** (for example `DB_USERS_ENDPOINT`, `VAULT_ADDR=http://10.0.0.7:8200`), never a hardcoded cluster name, so an app can move without code changes.
   - **Between Hetzner servers: the Hetzner private network (10.0.0.x), never Tailscale.** It is free, built in and one less thing to fail.
   - **Across providers** (Hetzner ↔ Google Cloud, a machine at home…): Tailscale is allowed for running prod traffic, as a deliberate link. The node is tagged (tagged nodes don't expire), the ACL allows only that path, and the link is monitored. For a managed service with no persistent host (Cloud Run), use public HTTPS with auth instead.
   - **Shared users:** local users in dev (`state.users.svc.cluster.local:5090`) and the same Service on 5080 in prod, both through `DB_USERS_ENDPOINT` in Vault. Dev can't read the prod value.
   - **Billing:** the same way, through `BILLING_ENDPOINT` in Vault (`ghostmind/global/billing`, and `…/billing/prod`). A product never calls Stripe.
   - **Dev and deploy** (the Mac, CI reaching the cluster API, SSH, debugging) use Tailscale.
   Inside the cluster: NetworkPolicies (default deny), no Istio, no Ingress for now (Gateway API if one tunnel ever fronts the whole cluster).
   Addresses: `/Volumes/Projects/home/networking.md`.
9. **Expose only what must be public.** A Cloudflare tunnel exists only if an endpoint is public, and it sends each hostname straight to its app's Service. There is no Traefik. A product that has a public endpoint has its `tunnel/` app from the start, in dev (`<app>.ghostmind.app`) and in prod (`<app>.ghostmind.dev`): the tunnel is part of the product's structure, not a step of its first deploy. The one exception is an app the user wants **dev only** (a test page for a library, never released): it has `"dev-only"` in its `meta.json` `tags`, no prod manifest, no prod tunnel and no deploy job, and `comply` accepts that. Reference: `/Volumes/Projects/colors` (`ui/`, `tunnel/`).
10. **Apps stay portable.** The image plus `.env.schema` is the app. No app depends on a Kubernetes feature to work, so it can run under Compose, on Cloud Run or on another cluster unchanged.
11. **Every publish asks which version first.** A script that ships a versioned thing to people (an iOS build, a Chrome extension zip, a Mac release: the `mobile_publish`, `extension_build` and `release` routines) asks, before it builds, which release this is: patch, minor, major, keep the current version or a version typed in full, each choice shown with the version it gives; Enter takes the patch. An answer it does not know stops before anything is built. A routine that only sends again a build already on disk (`mobile_submit`) asks nothing. An npm package is the same: a `publish` routine asks, then tests, builds and runs `npm publish`; a version is never picked for the user in a hurry. References: `/Volumes/Projects/colors/lib/scripts/publish.sh` (npm), `/Volumes/Projects/tags/native/scripts/publish.sh` (iOS), `/Volumes/Projects/tags/chrome/scripts/extension-build.sh` (extension), `/Volumes/Projects/format/mac/scripts/release.sh` (Mac).
12. **A project's folder is shared with other sessions.** Another Claude session, and the `skaffold dev` panes, may be working in the same folder right now. Before changing a repo that is not this session's own project: list the sessions (`ListAgents`) and tell the one that owns it which files you will change (`SendMessage`). Then work in a copy of your own, `git worktree add .claude/worktrees/<topic> -b <topic> origin/main` (inside the repo: `/Volumes/Projects` holds one folder per project and nothing else, and `run projects` lists a second copy as another project), bring the change back as a pull request, and remove the worktree when it is merged.
    - **Commit by naming the files**: `git commit -m … -- <paths>`. Never `git commit -a` or `git add -A` there: an uncommitted file in that tree is somebody's work in progress, and `-a` shipped another session's version bump to prod inside an unrelated commit (potion, 2026-10-13).
    - **No `git stash`, `git checkout <branch>` or `git switch` in the shared folder**: a running `skaffold dev` builds from it (`new-app` → kubernetes.md, Dev machines, says what breaks).
    - **A build that ships is made from the committed branch, in a worktree of its own.** A TestFlight build, an extension zip or a Mac release is built from the working tree, so another session's uncommitted files ship inside it. Build it from a worktree of the branch (`git worktree add .claude/worktrees/ios-publish HEAD`, then `npm install` in it and the routine there), commit the version bump the script writes to the shared branch by naming the file, and remove the worktree.
    - **Run a routine as its `meta.json` writes it**, with answers piped in when it asks (`printf 'p\n' | run routine mobile_publish`); never retype its command around it. tags' `publish.sh` starts varlock itself, and wrapped in a second `APP_ENV=prod varlock run --` it stopped before building with `vaultSecret(): No Vault authentication found` on every secret.
    - **Stop only your own processes, by their id.** `pkill -f scripts/publish.sh` matches every project's publish on the machine: it killed a second session's iOS build mid-archive (relay, 2026-10-13). One publish of an app at a time: say you are starting one.
    - To try a branch on dev, fast-forward the shared folder's own branch to it (`git merge --ff-only origin/<topic>`) when its tree is clean; that is the project's normal flow and switches nothing.
13. **A process that keeps running runs where the person sees it, and outlives the session.** A dev routine (`dev`, `dev_keep`, `skaffold dev`), a dev server, a watcher, a forward or a tail is never a background task of the Claude session: there it is invisible, it dies with the session, and the session sits idle waiting on it. It runs in its herdr pane, started by the routine that pane names (from `run projects`, or `run herdr init <workspace> --start --only <tab/pane>`; the `herdr` skill drives a pane). When its pane already runs it, use it as it is and read its output there. The person sees the output, keeps it alive when the work is done, and goes on with something else while the session works. A one-shot command (a test, a typecheck, a migration, a build, a check) runs directly. **Deploys are the exception**: they run the way the `deploy` skill says, never left running in a pane. Seen: a session started block's `ui` and `mcp` `skaffold dev` as its own background tasks and left them running for five hours, outside the panes where every other project's routines run (2026-10-18).

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
    scripts/                     the app's own verbs: migrate.sh, console.sh…
    meta.json                    routines dev, dev_keep, delete (skaffold) + herdr tab for this app
  k8s/                           the project's scripts: dev-setup.sh (pre-deploy hook shared by the apps), remove.sh, prod-init.sh (one-time prod setup, `deploy` skill)
  shared/                        only when several backends share TypeScript; the apps then build from the root
  plugin/                        the product's Claude plugin: .mcp.json + skills (see new-app → blocks.md)
```

**The root holds only `README.md`, `CLAUDE.md`, `meta.json`, `.gitignore`, `.github/`, `k8s/` (the project's dev scripts), `shared/` with a root `.dockerignore` when backends share code, and, when the product ships a Claude plugin, `plugin/` and `.claude-plugin/marketplace.json`.** Every app, including non-web ones (a Swift app, a CLI), lives in its own service folder. Nothing app-specific (`package.json`, `src/`, `test/`) stays at the root.

`docker/compose.*.yaml` exists only when the app isn't on Kubernetes. One project = one namespace, named after the project, in dev and prod. Apps reach each other by Service name (`<project>-<app>:<port>`), the same name the container had under Compose.

## The core of every product

Every product starts from the same seven parts. A new product gets all of them unless the user says otherwise; what varies from one product to the next is what the app does, not how it is assembled.

| Part | What it is | Reference |
|---|---|---|
| **Google sign-in** | One login for web, MCP and native, backed by the shared users database (`DB_USERS_ENDPOINT`), so a person is the same user in every product | `/Volumes/Projects/format/mcp` (`app/src/auth/oauth.ts`) |
| **UI** | The web app, signing in through the MCP server's OAuth | `/Volumes/Projects/format/ui` |
| **Database** | The product's own state: Hasura on the cluster | `/Volumes/Projects/tags/db` |
| **Colours** | Each app owns its colours: no theme package is shared at run time (decided 2026-10-17, after `@ghostmind-dev/colors` was tried in six apps and removed). A new interface starts with its own theme system, reproduced from Potion's before the first screen: one token file, role variables, a before-paint script, light and dark. `new-app` → blocks.md → *Colours* | `/Volumes/Projects/potion/ui/app/src/theme` (web), `/Volumes/Projects/potion/native/app/theme` (iOS) |
| **MCP** | The app's actions as tools, stateless on the cluster | `/Volumes/Projects/potion/mcp` (transport) |
| **Skills** | The Claude plugin that teaches the app's concepts and points at the MCP | `/Volumes/Projects/potion/plugin` |
| **OpenRouter, the user's own** | Every AI feature runs on the key the user connects. We don't pay for inference, and a user who wants a heavier experience pays for their own. The models offered are read live from OpenRouter's model list, never kept in code, and a model the person chose that stops working is never swapped silently: the product says so and they choose another (`new-app` → references/openrouter.md) | `/Volumes/Projects/format` (`ai_connections`) |

A product works without an OpenRouter key: AI features stay off until the user connects one. Anything public adds a tunnel, with its dev and its prod side together; a native app (iOS, Mac) is added on top of the core and signs in to the same OAuth server.

## Workspaces (strongly encouraged)

Give a product **workspaces** from its first migration: isolated containers inside an account, with everything the person makes belonging to one of them. It is not one of the six parts, because a few products have nothing to put in one, but for any product that holds a person's data it is the default, and leaving it out is a decision to say out loud. References: `/Volumes/Projects/potion` (`workspaces` table, `shared/server/workspace-resolver.ts`, the `workspace` header in `plugin/.mcp.json`) and `/Volumes/Projects/tags`.

Why it is worth doing before anyone asks:

- **People end up with more than one context**: home and work, one client each, one place each (a house, an office). Without workspaces they open a second account.
- **Sharing and teams attach to a workspace**, not to a person. A product whose rows belong to a user has nowhere to put a second member.
- **Adding it later touches everything**: a column and a backfill on every table, a parameter on every query, tool and screen. Adding it first costs one table and one column.

What it takes:

- **A `workspaces` table** (`id`, `user_id`, `name`, `is_default`) and a **`workspace_id` on every table a person's data lives in**, with the foreign key cascading. Rows are filtered by workspace, not only by user. Nothing crosses from one workspace to another.
- **One default workspace, created with the account**, so a person who never thinks about workspaces never sees the idea.
- **The workspace can be set from every surface**, always: a switcher in the web UI, a `workspace` header (the workspace's name) for the MCP so a project's `.mcp.json` can pin one, a parameter in the API, a flag in a command line. A surface that can't choose is a surface stuck in the default.
- **One resolver, shared by every backend**: the workspace named by the caller, else the default, else create the default. Two backends resolving differently is how potion's iOS server came to refuse what its MCP accepted.
- **MCP tools for it**: list, create, read and set the default. **Renaming and deleting a workspace stay web-only**, on purpose: a delete takes everything inside with it, and a rename breaks every `.mcp.json` pinned to the old name.

When the product shows a single workspace at first, still put `workspace_id` in the schema: the interface can grow later, the tables cannot cheaply.

Skip it when there is honestly nothing to contain: a static site, an internal worker, a shared service, a prototype. Say so in the project's `CLAUDE.md`, with the reason.

## Building blocks and their reference apps

Replicate the reference; do not invent a new pattern when one exists. When a newer project does a block better, update this table so the reference moves to it. **A reference can be behind the rules.** When a reference and `comply`'s `scripts/check.sh` disagree, the check is right: copy the reference's code and fix what the check reports.

| Block | Use when | Reference |
|---|---|---|
| **Kubernetes app, dev and prod** | The default for a new app | `/Volumes/Projects/portal` (`portal/` = ui, `tunnel/`): `k8s/<app>.yaml` + `<app>.dev.yaml`, `skaffold.yaml` per app with hot reload, no Compose. Details: `new-app` → kubernetes.md |
| **Prod deploy to the cluster** | Every app on k3s | `/Volumes/Projects/portal/.github/workflows/` (`_deploy-k8s.yaml`, `deploy.yaml`); also `tags` (five apps) |
| **Skaffold dev with hot reload** | Dev for every Kubernetes app | `/Volumes/Projects/portal/portal/skaffold.yaml` (`sync: infer`), `/Volumes/Projects/tags/k8s/dev-setup.sh` (namespace, volume, dev-session Vault token) and `k8s/remove.sh` |
| **Vault login by service account** | A pod that reads secrets | `/Volumes/Projects/tags/city/k8s/city.yaml` + `.env.schema`; `portal/tunnel` |
| **Tunnel without Traefik** | Something must be public | `/Volumes/Projects/portal/tunnel`, `/Volumes/Projects/tags/tunnel` |
| Cluster and node setup | Adding a node or a project to the cluster | `/Volumes/Projects/ghostmind/start/host/k3s/` and `host/scripts/server-bootstrap.sh` |
| Remote MCP + Google OAuth (the product's auth server) | Most products | `/Volumes/Projects/format/mcp` (Google-proxy OAuth with enforced PKCE, allow-listed redirects, signed state: `app/src/auth/oauth.ts`) for the OAuth; `/Volumes/Projects/potion/mcp` (`app/src/main.ts`) for the transport: **stateless on the cluster**, MCP SDK v2, no sessions (`new-app` → blocks.md) |
| **Claude plugin for the product** (MCP + skill) | Almost every product: how the user operates it through Claude | `/Volumes/Projects/potion/plugin` (`.mcp.json` → the remote MCP, `skills/potion`, `skills/potion-blocks`); smaller: `/Volumes/Projects/tags/plugin` |
| Web app, simple | Default: signs in through the MCP server's OAuth, so web, MCP and native share one auth system | `/Volumes/Projects/format/ui` (static React + TanStack, Vite) |
| Web app, full-stack | Needs server rendering or its own API routes | `/Volumes/Projects/potion/ui` (Next.js + next-auth Google) |
| Native app signing in to the product | Mac/iOS app with user accounts | `/Volumes/Projects/format/mac/app/Sources/Format/Account.swift` (RFC 8252 loopback + PKCE, tokens in the Keychain) |
| Bring-your-own OpenRouter | Users pay for their own AI | `/Volumes/Projects/potion` (`agent/ai-connection.ts`: PKCE, key AES-GCM in `ai_connections`; `shared/server/ai-models.ts`: models read live, a gone model refused). Guide: `new-app` → references/openrouter.md |
| **An assistant in the app** | A chat that understands the product and acts in it with the person's yes | `/Volumes/Projects/relay` (`api/app/src/assistant/`: `@ghostmind-dev/agento` on the person's key, Jev as decider, the product's own MCP as its tools, `/chat` as a page). `new-app` → blocks.md → *An assistant in the app* |
| **Payments** (billing) | The product sells a plan | `/Volumes/Projects/billing` (its README: the contract); the product's side: `/Volumes/Projects/tags/shared/server/billing.ts`. One Stripe account, one webhook and one customer per person for every product; the product holds a billing token and no Stripe key. `new-app` → blocks.md → *Payments: billing* |
| OpenTofu (not Terraform) | Cloud resources (GCS bucket + service account) | `/Volumes/Projects/format/bucket` (OpenTofu, the open-source Terraform, in a container through varlock; the files go in on stdin, so it works when the Docker engine is another machine; the service account's key goes from Terraform's outputs straight into Vault, never to a file). Don't copy `tags/bucket`: it runs HashiCorp's Terraform and writes the key to `infra/service-account-key.json` (`check.sh` fails it) |
| Database | The product has state | `/Volumes/Projects/tags/db` (Hasura on the cluster, migrations applied in the container) |
| **Reaching things in a person's home** (relay) | The product makes something for a place (a sound, a picture) that should reach a speaker, a light or a screen there from anywhere | `/Volumes/Projects/relay` (its README, "Playing a stream"): relay reaches the home and is given what the product makes (an address); the product does not call relay. Reference: noice, whose stream relay plays. `new-app` → blocks.md → *Things at home: relay* |
| Worker / internal service | Background jobs, no public endpoint | `/Volumes/Projects/potion/worker` (a Deployment and Service with no tunnel route) |
| Compose + Cloud Run (not on the cluster) | A managed target, a script project | `/Volumes/Projects/inference` (bash + gcloud, varlock on the host) |
| Shared service, always on in dev | A service other products call | `/Volumes/Projects/users` (`start` routine, its own dev database) |
| Stateful app on a volume, tailnet only | An internal tool | `/Volumes/Projects/ghostmind/admin` (SQLite on a volume, Tailscale Serve) |
| Compose on a standalone host | An app that can't go on the cluster | `deploy` → compose-host.md. No product uses it today: tags and users did before moving to the cluster (their git history) |
| Compose on a small device, deployed over SSH | A single-purpose box that must stay light (a Raspberry Pi with a radio): the host has only git and Docker, no agent, no CI runner | `/Volumes/Projects/bridge` (`scripts/deploy.sh`: edited on the Mac, `run routine deploy` pushes, then the host pulls and restarts only the service whose files changed. It first brings back what the app rewrote on the host, here Zigbee2MQTT's `configuration.yaml`, so the two sides never diverge) |
| iOS app | Mobile | `/Volumes/Projects/relay/native` (no server of its own, signs in through the product's OAuth); `/Volumes/Projects/noice/native` (the same, plus Google Cast, an html block in the app, its own Metro port, and `scripts/apple.mjs` that registers the bundle ids); `/Volumes/Projects/tags/native` (with a companion server; signing and creds scripts); `/Volumes/Projects/format/native` for a **widget** (a WidgetKit extension in `app/targets/widget`, built by `@bacons/apple-targets` at each prebuild: Home and Lock Screen widgets and the iOS 18 control, opening the app at a deep link); older: `potion/native`. `new-app` → non-web.md → *A mobile app* |
| Raycast extension | Mac launcher tools | `/Volumes/Projects/labo/projects` |
| Swift macOS app | Native Mac | `/Volumes/Projects/format/mac` (`scripts/dev.sh`: watch, rebuild, re-sign, relaunch) |
| Mac app around a program we already have | Native Mac | `/Volumes/Projects/relay/mac` (contains the product's command-line program; trial and package builds; released to `downloads.ghostmind.dev`). `new-app` → non-web.md → *A Mac app* |
| Python CLI/package | Tooling | `/Volumes/Projects/theme` |
| **Html written by a model, shown in an app** | A note's chart, a dashboard, the box under the mouse on a map, a card: any place an AI writes the markup | `@ghostmind-dev/block` on npm (source: `/Volumes/Projects/block/lib`): the sandboxed frame, libraries, sized slots, the app's own functions lent to the block, on a web page and in a web view. Every product uses it; the app's side of it: `potion/ui/app/src/lib/potion-block.ts` (many functions, a feed, permissions), `tags/shared/pure/layout-frame.ts` (one function, web and iOS from one file), `relay/api/app/src/ui/frame.js` (a page with no build). Never write another iframe for this (`new-app` → blocks.md). **A product where a person makes layouts** takes block as the model (`/Volumes/Projects/block`: a room, data fields through `<app>.self()`, the live draft and the chat) and Potion as the integration example (`new-app` → blocks.md, *Letting a person make layouts*) |
| **An AI chat in a product** | Asking about the person's data, making a new thing, making a layout | An observation, not a rule: contexts that need different reach (the person's data, the product's tools, or, for a layout, only the draft and made-up data). Kept apart by what the model is handed (`new-app` → blocks.md, *An AI chat in an app*) |

`portal` is the reference for how an app is packaged and run; `format` and `tags` are references for app code (auth, web, native, db). Every project in the table runs on Kubernetes in dev and prod, with no Traefik and no compose file, so manifests, Skaffold files and workflows can be copied from any of them; `portal` and `tags` are the cleanest. What is still legacy: potion's `bucket` (`.env.base`, `run` scripts) and leftover `.env.base` / `.env.template` files in `potion/chrome` and `potion/native`; several entrypoints (portal's tunnel, tags, format, users) still loop in prod, a Compose habit (`new-app` → docker.md). **Don't copy how `format`, `billing` and `potion` choose the cluster**: they pin `kubeContext: m1` in `skaffold.yaml` or run Skaffold through a `scripts/skaffold.sh` that names `m1` and sets `DOCKER_HOST=ssh://m1`, which the check fails (no file names a cluster). Copy `tags/scripts/skaffold.sh`, which derives the Docker context from the kube context. **Don't copy `potion/mcp`'s OAuth**: it doesn't enforce PKCE, accepts any redirect URI and leaves `state` unsigned; take format's instead. Its stateless transport (`app/src/main.ts`) is the reference for every MCP on the cluster.

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
| Routines | `dev` (`skaffold dev`), then verbs (`migrate`, `console`); no `prod` routine | |
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

**An iOS app's Metro is one of these ports.** Two apps in dev on the same 8081 load each other's code (noice's app ran relay's on 2026-10-13). Each takes its own, written in the registry (`new-app` → non-web.md → *A mobile app*).

**Pick from the registry below**, and add the new project's row in the same change. Then confirm nothing is listening: `lsof -iTCP -sTCP:LISTEN -nP | grep :<port>`.

| Project | Ports |
|---|---|
| portal | ui 5096 |
| tags | city 5085 · db 5086 · mcp 3085 · native 3086 · Hasura console 9725 / api 9723 · atlas 5087 / 5088, its console 9755 / api 9753 · iOS: Metro 8085 |
| format | db 5075 · ui 5076 · mcp 3075 · Hasura console 9705 / api 9703 · iOS: Metro 8086, pretend backend 5077 |
| users | state 5090 (dev forward; the Service is 5080 in prod, consumers hardcode it) · Hasura console 9727 / 9728 |
| potion | ui 5001 · mcp 3020 · chrome 3025 (its extension's hot reload 8082) · worker 3030 · api 3040 · native 3055 · db 5080 · Hasura console 9693 / 9695 · iOS: Metro 8081 |
| noice | ui 5065 · db 5066 · engine 5068 · Hasura console 9735 / api 9733 · iOS: Metro 8083, pretend backend 5069 |
| relay | api 5055 · db 5056 · mcp 3065 · Hasura console 9745 / api 9743 · iOS: Metro 8084 |
| db | postgres 5432 |
| admin | dashboard 5095 |
| magneto | api 3035 · db 5035 · ui 5036 |
| together (playground) | api 3045 · db 5045 · ui 5046 · web 3060 |
| block | demo 5105 · ui 5106 (the one dev host: it sends /mcp, /oauth and /api to the mcp) · db 5107 · mcp 3105 · Hasura console 9775 / api 9773 |
| colors | ui 5125 (dev only) |
| billing | api 3095 · mcp 3096 (prod forward 3097) · db 5115 · Hasura console 9765 / api 9763 |
| vault | 8200 |

For a new project, pick unused numbers in the usual ranges: 5000–5999 for web and db, 3000–3999 for APIs and MCPs, 9700–9799 for tool ports, 8081–8099 for an iOS app's Metro. `comply`'s check compares every project's Metro port and reports two that are the same.

## meta.json and `run`

`run` operates projects on the Mac, and every folder's `meta.json` is what it reads. Its own skill (the `run` plugin, shipped from the `run` repo) holds the detail; load it for anything beyond this summary.

- `run projects`: the dashboard. Every folder whose `meta.json` has `type: "project"`, with its herdr workspace, git branch and uncommitted changes; workspaces are opened and closed from it, alone or by tag or group. This is where most of the work happens. To ask what exists or what is running, use `run projects --json` (add `--panes` for what each pane runs) rather than reading folders.
  - **Opening a project** builds its workspace and asks which of its panes' routines to start: all, a hand-picked few, or one **profile**.
  - **Saved views** filter the table (by tag, group, folder, organization, machine, status, git state); they live in `~/.config/run/projects.json`.
  - **Other machines**: projects on a Mac saved in herdr (`herdr machine add`) appear in the same table and are opened there over SSH. Save only real workstations: the dashboard runs `run projects --json` on each saved machine about every 10 seconds, which on a Raspberry Pi 3 is 7 seconds of full CPU per poll. A small host is worked on from a local clone and deployed over SSH instead (the `bridge` reference).
- `run routine <name>`: runs a `routines` entry. It splits on spaces **without a shell**, so pipes, quotes and redirects belong inside a script.
- `run herdr init|attach|terminate <workspace>`: builds the herdr workspace from the `herdr` blocks. `init --start` also runs the routine each pane names; `--profile <name>` or `--only <tab/pane,...>` narrows which.
- `run herdr colors [on|off]`: shows or hides each project's colour mark in herdr's sidebar. Fetch the schema before editing a `herdr` block: `https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json`.

A meta.json carries `id` (12-char random), `name`, `type` (`project` at the root, `app` per service), `description`, `tags`, `groups`, `routines`, `herdr`. `tags` describe a project; `groups` name sets of projects worked on together. In the `herdr` block, a workspace may carry a `color` (its mark in herdr's sidebar), and a pane may name the `routine` it usually runs and the `profiles` it is part of. A profile is a set of routines started together for one way of working on a project (`web`, `mobile`), tagged pane by pane across the project's apps. **The root `meta.json` has a `claude` tab, first, whose pane names no routine and no profile: the person starts Claude there by hand.** Claude is never a routine: `run routine` starts it without a terminal, so it falls into `--print` mode and stops at once with `Error: Input must be provided either through stdin or as a prompt argument when using --print` (admin, 2026-10-20).

**Removed in run 0.9.0, they no longer exist:** `run custom`, `run vault kv`, `run docker`, `run terraform`, `run tmux`, `run meta`, `run action`, `run misc`, and the meta.json keys `compose`, `docker`, `terraform`, `custom`, `tmux`, `template`, `global`. A project still calling one is converted with the `migrate` skill: its scripts become `scripts/*.sh`.

**Still present but on its way out:** `--cible`/`--env` env loading with `.env.base`/`.env.local`, and the `secrets` key. New work never uses them.

## Environment

- No devcontainers: everything runs on the Mac host (projects under `/Volumes/Projects`).
- **This text may be older than the repo.** The plugin Claude loads is an installed copy; the source is `/Volumes/Projects/system/skills`. On a Mac that has the repo, read the port registry, the reference table and `database` there before acting on them: block was first given two Hasura ports that relay already held, and was sent to a shared RDS that had been removed, both from an installed copy a few days old.
- **The shared dev services are on the dev cluster only**: the users service (`state.users.svc.cluster.local`) and the shared Postgres (`db-postgres.db.svc.cluster.local`). A product that signs people in or has a database runs its dev there (`new-app` → kubernetes.md → Dev machines); on any other cluster those names do not resolve. **No skill, script or file names a dev cluster, a machine or a context**: which one it is belongs to the person, and a dev routine checks it by asking the cluster for those services.
- **A dev machine is a pair**, a kube context and a Docker context for the same machine (its Docker engine and its cluster, which runs locally built images with no push),: an image exists only on the daemon that built it. **Only the current contexts are used**: which cluster is current is the person's choice, and a routine, a script or a session never switches a context or names one; when the current pair is not the dev cluster's, it says so and stops. **No file in a repo names a cluster** (no `kubeContext` in `skaffold.yaml`): `skaffold dev` uses the current context. A dev cluster on another machine over Tailscale needs its Docker context on an SSH-forwarded unix socket, not `ssh://` (Skaffold cannot dial it): `new-app` → kubernetes.md → Dev machines. `ghostmind` is the prod context (read-only use): scripts that touch prod always pass `--context ghostmind`, never the current context.
- Compose paths (when an app has them) are **relative to the compose file**; `SRC`/`LOCALHOST_SRC` are legacy.
- `VAULT_ADDR` and `VAULT_TOKEN` are exported in the shell. There is no `~/.vault-token`, so schemas pass the token explicitly.
- Tools on the host: `varlock` (brew `dmno-dev/tap/varlock`), `vault`, `docker`, `kubectl`, `skaffold`, `gh`, `tailscale`, `herdr`.
- Projects sit flat under `/Volumes/Projects`, one folder each, whatever their GitHub org. GitHub orgs: product repos live in **`ghostmind-app`** (older remotes still say `ghostmind-dev` and redirect); system tooling (this plugin, `run`) is in `ghostmind-dev`; public libraries, tools and experiments (`agento`, `ensemble`, `toolkits`, `theme`, `inference`) in `ghostmind-labo`; the house and personal machines (`hub`, `bridge`, `operator`) in `ghostmind-studio`; learning workspaces (`ai`, `food`) in `ghostmind-learn`. Hosts, Tailscale and private addresses: `/Volumes/Projects/home/networking.md`.
- The Tailscale CLI isn't on the Mac's PATH: `/Applications/Tailscale.app/Contents/MacOS/Tailscale`.
- The Mac's shell is zsh: `for path in …` overwrites `$PATH`; an unquoted glob like `--include=*.ts` fails with "no matches found"; `timeout` doesn't exist. Put loops and anything glob-heavy in a `bash` script.
