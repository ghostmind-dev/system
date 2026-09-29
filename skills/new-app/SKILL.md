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

1. **Pick the blocks.** Map the request to blocks from the `system` table. A typical product is *web app + remote MCP + database* behind one Google login, **plus the product's Claude plugin** (MCP + skill) so the user can operate it through Claude. Include the plugin unless the user says the product has nothing to do through AI. Add **tunnel** only if something is public, and **traefik** only when the app's public host carries several services (UI + `/mcp` + `/api`). Non-web apps follow their reference app plus [non-web.md](references/non-web.md). Confirm the block list with the user when the request is ambiguous. *Done when every requested capability maps to a block.*
2. **Read the reference app** for each block, both its `app/` code and its structure. Copy what it does well; leave behind its legacy plumbing (`.env.base`, `run custom`, `${SRC}`, `/run/secrets`). *Done when you can name the files you will copy and what you will change.*
3. **Create the service folders** exactly as in [docker.md](references/docker.md): `app/`, `docker/`, `scripts/`, `.env.schema`, `.env.dev`, `.env.prod`, `meta.json`, plus the root `.gitignore` from the same file. The repo root keeps only `README.md`, `CLAUDE.md`, `meta.json`, `.gitignore` and `.github/`. When the repo already holds a single app at its root, move that code into its own service folder (`mac/app`, `cli/app`…) first. Take every port, secondary ones included, from the registry in the `system` skill and add the project's row. *Done when nothing app-specific is left at the root and every published port is in the registry.*
4. **Write the schema** with the `secrets` skill. Create each project secret in Vault under `ghostmind/project/<project>/<app>`: generate random values (`openssl rand -hex 32`). For third-party ones, give the user the exact command to paste, with the right path and key names, e.g. `vault kv patch ghostmind/project/<project>/auth GOOGLE_OAUTH_CLIENT_ID=... GOOGLE_OAUTH_CLIENT_SECRET=...` (`put` if the path doesn't exist yet). Then check that the keys landed where the schema points. Reuse `ghostmind/global/*` for anything shared.
5. **Wire the blocks together** using [blocks.md](references/blocks.md): Google OAuth shared between web and MCP, the DB (`database` skill), tunnel/traefik routes.
6. **Add routines and the herdr tab** to each `meta.json`: `dev` → `varlock run --include-internal -- bash scripts/dev.sh`, `prod` → `bash scripts/prod.sh` (no varlock on the host in prod; see [docker.md](references/docker.md)), plus a herdr tab (`"prefix": false`) with the dev server pane and an `execution-shell` pane.
7. **Prove dev works.** `run routine dev` starts the container. The app answers on its port. Editing a file under `app/` reloads without a rebuild. `varlock load --agent` resolves every variable. *Done when all four have been observed, not assumed.*
8. **Write the plugin** (when the product has one) once the MCP's tools exist: [blocks.md](references/blocks.md) → The product's Claude plugin. *Done when a fresh Claude session with only the plugin installed completes one real task in the app through the MCP.*
9. **Deploy** when the user wants prod: `deploy` skill.
