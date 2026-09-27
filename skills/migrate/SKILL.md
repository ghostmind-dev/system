---
name: migrate
description: >-
  Move an existing Ghostmind app off the legacy setup (.env.base/.env.local/.env.prod, run vault kv,
  run custom, SRC/LOCALHOST_SRC, env_file in compose) onto varlock + Vault and the new deploy flow.
  Use when converting, upgrading or modernizing an existing project or app.
---

# Migrate a legacy app

Migrate **one app at a time**, and keep the old files until the new setup is proven, so the old deploy still works if something breaks. Read the `system`, `secrets` and `new-app` skills first: they define the target.

## Steps

1. **Inventory.** List every variable the app uses: key names from `.env.base`, `.env.local` and `.env.prod` (never print values), plus `process.env.*` / `Deno.env.get` references in `app/`. For each key, decide:
   - plain config → a value in `.env.schema` / `.env.dev` / `.env.prod`;
   - secret shared across products → an existing `ghostmind/global/<provider>` path;
   - secret owned by the app → `ghostmind/project/<project>/<app>` (or `/dev`, `/prod` when it differs).

   Drop what `run` injected for itself (`TF_VAR_*`, `SRC`, `LOCALHOST_SRC`, `PROJECT`/`APP` unless the app reads them). *Done when every key has a destination and nothing in `app/` references an unlisted key.*
2. **Copy values into Vault.** The legacy blobs live at `kv/<meta.id>/<env>/secrets` → key `CREDS` (a whole dotenv file; `base` is the shared one). Parse them in a script and write each secret to its new path with `vault kv patch` / `put`, piping values straight from one command to the other so they are never printed. Map legacy env `local` → `dev`. Leave `kv/` untouched.
3. **Write `.env.schema`, `.env.dev`, `.env.prod`** (see `secrets`). `varlock load --agent` resolves every item with `APP_ENV=dev` and again with `APP_ENV=prod`. *Done when both resolve with no errors.*
4. **Convert Docker and scripts** to `new-app` → docker.md: `compose.local.yaml` → `compose.dev.yaml` with relative paths and no `env_file`; varlock entrypoint; `scripts/*.ts` → `scripts/*.sh`; routines `dev` / `prod`. A legacy `.env.local` must be deleted, not kept (varlock always loads that name).
5. **Prove dev**: hot reload works and the app behaves exactly as before.
6. **Switch the deploy** (`deploy` skill): Vault roles, new workflow, verify. *Done when a prod deploy is green and `docker inspect` shows no secrets.*
7. **Remove the legacy pieces** only now: `.env.base`, `.env.template`, `scripts/*.ts`, the meta.json keys `compose`/`secrets`/`custom`, and `/run/secrets/<project>/<app>` on the host. `run` skips its own env loading in any folder containing `.env.schema`, so leftover `run routine` calls keep working.

Fix the copy-paste bugs listed in the project's audit while you are in the app (wrong meta names, `container_shell` pointing at another project, stale `.env.template`).
