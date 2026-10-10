---
name: new-app
description: >-
  Scaffold a new Ghostmind project or add a service to one: web app, remote MCP, worker, API,
  tunnel, or a non-web app (iOS, Raycast, macOS, CLI). Kubernetes by default (Skaffold in dev, the k3s
  cluster in prod); Compose for non-cluster targets. Also a quick prototype or playground: one small
  app, compliant from the first file and ready to grow. Use when the user describes an app or an
  idea to try, or asks to create, start, set up, prototype or add an app or service.
---

# New app

Read the `system` skill first: it has the rules, naming, and the **reference app** for each block. This skill turns a request into files.

## Where it goes

A new project is a folder at the root of `/Volumes/Projects` (`$RUN_PROJECT`), named after the project: `/Volumes/Projects/<project>`. No org or category folder above it. Run `git init` there on a `dev` branch. Don't create the GitHub repo until the user asks; when they do, it starts in `ghostmind-labo`.

Tag it `playground` in the root `meta.json` while nobody knows whether it will last, next to the tags that say what it is (`"tags": ["playground", "maps"]`). The tag comes off when the project is kept.

## How far to go

Take the depth from how the user asks. When they don't say, build a prototype and say what was left out.

| Depth | The user says | What gets built |
|---|---|---|
| **Prototype** | "a little prototype", "just try", "quick", "playground" | One app, usually the web UI. No sign-in, database, MCP, plugin, tunnel or CI unless the idea can't be shown without it |
| **Product** | "an app", "a product", names users or a domain | The core of every product (step 1), on the cluster |

A prototype is small, not loose. It still has all of this, so growing it later only adds files:

- the service-folder layout (`<project>/<app>/app`), nothing app-specific at the root;
- a root `meta.json` and one per app, with `dev` and `dev_keep` routines and the herdr tab (step 6);
- `.env.schema` and varlock for every variable, even when there are two; no `.env` file, nothing secret in the repo;
- a port from the registry in the `system` skill, with the project's row added;
- `README.md`, `CLAUDE.md` and the `.gitignore` from docker.md.

A prototype's `dev` routine may run the dev server on the Mac through varlock (`varlock run -- npm run dev`) instead of Skaffold: no `docker/`, `k8s/` or `skaffold.yaml` yet. Use the cluster from the start when the idea needs something the cluster gives (a database, a second app, a public hostname). Moving a prototype to the cluster is steps 3 to 7 on the same folders; the `dev` routine changes and nothing moves.

Finish with the `comply` skill: a prototype passes it except for the parts it has not grown yet.

## Steps

1. **Pick the blocks.** Map the request to blocks from the `system` table. A product starts from the **core** in the `system` skill (*The core of every product*): Google sign-in on the shared users database, web UI, database, remote MCP, the Claude plugin (MCP + skills), and bring-your-own OpenRouter for anything AI. For a product, build all six unless the user says to leave one out; don't ask which of them it needs. A prototype starts with one app (*How far to go*). Add **tunnel** only if something is public; it routes straight to each app's Service, with no Traefik. **Decide the target:** the k3s cluster (the default, about 80% of apps) or something else (Cloud Run, a one-off container, a script project), which uses Compose. Non-web apps follow their reference app plus [non-web.md](references/non-web.md). Confirm the block list with the user when the request is ambiguous. *Done when every requested capability maps to a block.*
2. **Read the reference app** for each block, both its `app/` code and its structure. Copy what it does well; leave behind its legacy plumbing (`.env.base`, `run custom`, `${SRC}`, `/run/secrets`, Traefik, Compose for an app headed to the cluster). *Done when you can name the files you will copy and what you will change.*
3. **Create the service folders** as in [kubernetes.md](references/kubernetes.md): `app/`, `docker/` (Dockerfile and entrypoint from [docker.md](references/docker.md)), `k8s/<app>.yaml` + `k8s/<app>.dev.yaml`, `skaffold.yaml`, `.dockerignore`, `.env.schema` (one per app, both environments), `meta.json`, plus, at the project root, `k8s/dev-setup.sh` and `k8s/remove.sh` (kubernetes.md) and the `.gitignore` from docker.md. A non-cluster app gets `docker/compose.*.yaml` and `scripts/` from docker.md instead of `k8s/` and `skaffold.yaml`. The repo root keeps only `README.md`, `CLAUDE.md`, `meta.json`, `.gitignore` and `.github/`. When the repo already holds a single app at its root, move that code into its own service folder (`mac/app`, `cli/app`…) first. Take every port, secondary ones included, from the registry in the `system` skill and add the project's row. *Done when nothing app-specific is left at the root and every published port is in the registry.*
4. **Write the schema** with the `secrets` skill. Create each project secret in Vault under `ghostmind/project/<project>/<app>`: generate random values (`openssl rand -hex 32`). For third-party ones, give the user the exact command to paste, with the right path and key names, e.g. `vault kv patch ghostmind/project/<project>/auth GOOGLE_OAUTH_CLIENT_ID=... GOOGLE_OAUTH_CLIENT_SECRET=...` (`put` if the path doesn't exist yet). Then check that the keys landed where the schema points. Reuse `ghostmind/global/*` for anything shared.
5. **Wire the blocks together** using [blocks.md](references/blocks.md): Google OAuth shared between web and MCP, the MCP built stateless (SDK v2, no session map, `replicas: 2` in dev) when it runs on the cluster, the DB (`database` skill), the tunnel's routes to each Service.
6. **Add routines and the herdr tab** to each `meta.json`: `dev`, `dev_keep`, `delete` (and `start` for an always-on shared service) as in kubernetes.md (one `skaffold dev` per app, each with its own logs), plus a herdr tab (`"prefix": false`) with the dev pane and an `execution-shell` pane. The root `meta.json` gets the `remove` routine. There is no `prod` routine: prod deploys through CI only. (Compose apps: the routines in docker.md.)
7. **Prove dev works.** `run routine dev` deploys the app to the current kube context, building on the current Docker context (same machine, kubernetes.md → Dev machines). It answers on its forwarded port. **Editing a file under the synced source reaches the running app without an image rebuild** (watch Skaffold log a sync, not a build). `varlock load --agent` resolves every variable. For a remote MCP on the cluster, a fifth: delete the serving pod mid-session and call a tool again without reconnecting; it answers. *Done when all of them have been observed, not assumed.*
8. **Write the plugin** (when the product has one) once the MCP's tools exist: [blocks.md](references/blocks.md) → The product's Claude plugin. *Done when a fresh Claude session with only the plugin installed completes one real task in the app through the MCP.*
9. **Deploy** when the user wants prod: `deploy` skill.
