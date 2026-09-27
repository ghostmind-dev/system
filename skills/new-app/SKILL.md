---
name: new-app
description: >-
  Scaffold a new Ghostmind project or add a service to one: web app, remote MCP, worker, API,
  tunnel, traefik, or a non-web app (iOS, Raycast, macOS, CLI). Use when the user asks to create,
  start, set up or add an app or service.
---

# New app

Read the `system` skill first: it has the rules, naming, and the **reference app** for each block. This skill turns a request into files.

## Steps

1. **Pick the blocks.** Map the request to blocks from the `system` table. A typical product is *web app + remote MCP + database*, both behind Google login. Add **tunnel** only if something is public, and **traefik** only if several public hostnames share the tunnel. Non-web apps follow their reference app plus [non-web.md](references/non-web.md). Confirm the block list with the user when the request is ambiguous. *Done when every requested capability maps to a block.*
2. **Read the reference app** for each block, both its `app/` code and its structure. Copy what it does well; leave behind its legacy plumbing (`.env.base`, `run custom`, `${SRC}`, `/run/secrets`). *Done when you can name the files you will copy and what you will change.*
3. **Create the service folders** exactly as in [docker.md](references/docker.md): `app/`, `docker/`, `scripts/`, `.env.schema`, `.env.dev`, `.env.prod`, `meta.json`. Pick a port that no other project uses (the `system` skill has the check).
4. **Write the schema** with the `secrets` skill. Create each project secret in Vault under `ghostmind/project/<project>/<app>`: generate random values (`openssl rand -hex 32`) and ask the user for third-party ones. Reuse `ghostmind/global/*` for anything shared.
5. **Wire the blocks together** using [blocks.md](references/blocks.md): Google OAuth shared between web and MCP, the DB (`database` skill), tunnel/traefik routes.
6. **Add routines and the herdr tab** to each `meta.json`: `dev` → `varlock run -- bash scripts/dev.sh`, `prod` → `bash scripts/prod.sh` (no varlock on the host in prod; see [docker.md](references/docker.md)), plus a herdr tab with the dev server pane and an `execution-shell` pane.
7. **Prove dev works.** `run routine dev` starts the container. The app answers on its port. Editing a file under `app/` reloads without a rebuild. `varlock load --agent` resolves every variable. *Done when all four have been observed, not assumed.*
8. **Deploy** when the user wants prod: `deploy` skill.
