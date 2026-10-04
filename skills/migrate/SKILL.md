---
name: migrate
description: >-
  Move an existing Ghostmind project off the legacy setup (.env.base/.env.local/.env.prod, run vault kv,
  run custom, run terraform, SRC/LOCALHOST_SRC, env_file in compose, admin-token deploys) onto varlock +
  Vault and the new deploy flow. Use when converting, upgrading or modernizing an existing project or app.
---

# Migrate a legacy project

Read the `system`, `secrets`, `new-app` and `deploy` skills first: they define the target. The full reference conversion is `/Volumes/Projects/ghostmind/tags` (seven apps, Terraform and iOS included; dev and prod green on 2026-09-30).

**The target is Kubernetes** (prod on the k3s cluster, dev with Skaffold), unless the app is one of the exceptions that stays on Compose. Keep the old files and the old deploy working until the new setup is proven. References: `tags` (a multi-app product) and `/Volumes/Projects/ghostmind/users` (a single-app shared service that other products call). Ask before touching anything another project uses: a `ghostmind/global/*` key, a tailnet node, a shared DB.

## Steps

1. **Inventory each app.** List the key names of its legacy blobs (`kv/<meta.id>/<env>/secrets` → `CREDS`, one dotenv file per env; `base` is the shared one). Never print values. Then grep what the code actually reads (`process.env.*`, `Deno.env.get`) and **drop what no code reads**. tags removed a third of its keys this way.
2. **Compare every value by hash**: `python3 <this skill's folder>/scripts/compare-secrets.py <meta.id> --local <project dir>`. It prints each key's hash and where the same value already lives. From that:
   - in `ghostmind/global/*` → point to the global key;
   - in another project's legacy blobs → shared across products: **promote to global**, except security boundaries (Hasura admin/JWT secrets, `NEXTAUTH_SECRET`). Those stay project-scoped and are flagged for rotation when they're copy-pasted between products;
   - in several apps of this project → one project path, not duplicates;
   - in local `.env.*` files → those files are safe to delete;
   - flagged `${` → the legacy value interpolates. Resolve it first (`PROJECT` = the root meta name, `APP` = the app meta name, `ENVIRONMENT` = `local`/`prod`); `DB_NAME=${PROJECT}-${APP}-${ENVIRONMENT}` looks shared until resolved. **Check that resolved resource names really exist** before writing them into the schema (for databases: `psql -tAc "SELECT datname FROM pg_database"` from a throwaway `postgres:17-alpine` container).
3. **Write values into Vault** without printing them: pipe straight from one command to the other. Normalize the way compose `env_file` did: trim whitespace, **then** strip one pair of matching quotes (`APPLE_ID="x"   ` otherwise lands in Vault with its quotes). Re-check by hash afterwards. Leave `kv/` untouched.
4. **Keep legacy names baked into real resources.** Databases (`tags-db-local`), buckets (`tags-local-bucket`) and Terraform state (`<meta.id>/local/terraform/…`) keep their `local` names. Map them in the schema (`if(forEnv(prod), "prod", "local")`) rather than moving data.
5. **Write the schema** (one `.env.schema` per app, `secrets` skill). `varlock load --agent` resolves with `APP_ENV=dev`, and again with `APP_ENV=prod VAULT_ROLE_ID= VAULT_SECRET_ID=`. *Done when both resolve with no errors.*
6. **Convert Docker, scripts and meta** to `new-app` → kubernetes.md (image and entrypoint from docker.md). Write `k8s/<app>.yaml`, `k8s/<app>.dev.yaml` and `skaffold.yaml`; Service names keep the old container names (`<project>-<app>`), so addresses don't change; drop the `traefik/` app and route the tunnel straight to each Service. The points below still apply, the Compose ones only to an app that stays on Compose:
   - `compose.local.yaml` → `compose.dev.yaml` (and `ingress.local.yaml` → `ingress.dev.yaml`), with relative paths and no `env_file`;
   - keep `-p <project>` identical to the legacy compose project name, so named volumes (`<project>_tunnel-creds`) carry over;
   - the varlock entrypoint, with the binary that matches the base image;
   - `scripts/*.ts` → `scripts/*.sh`. A routine that needs `cd`, `&&` or quotes becomes a script, because `run routine` has no shell;
   - Terraform → the Terraform block in `new-app` → blocks.md. `plan` must show no changes;
   - **a remote MCP moving to the cluster becomes stateless** (`new-app` → blocks.md): an in-memory `transports`/session map or `@modelcontextprotocol/sdk` 1.x is drift. Run `npx @modelcontextprotocol/codemod@latest v1-to-v2 .`, rebuild the entry point on `createMcpHandler` + `toNodeHandler` as in `potion/mcp/app/src/main.ts`, set `replicas: 2` in the dev manifest, and prove it by deleting the serving pod mid-session. Upstream guides: `docs/migration/upgrade-to-v2.md` and `support-2026-07-28.md` in `modelcontextprotocol/typescript-sdk`;
   - herdr tabs get `"prefix": false`;
   - **ports:** new unique ones from the registry in the `system` skill. Check `docker ps` too: tags' legacy ports were all held by potion's running containers;
   - rewrite the root `.gitignore` from docker.md (legacy ones hide the new committed files);
   - app code sitting at the repo root moves into its own service folder.
7. **Delete legacy files carefully.** `.env.local` goes immediately (varlock always loads that name). A legacy `.env.prod` shares its name with a file varlock would read: confirm its values are in Vault by hash, then delete it. Then `.env.base` and `.env.template`. *Done when `git status` shows only `.env.schema` as the committed env file, and nothing app-specific is left at the root.*
8. **Prove dev**: hot reload works and the app behaves exactly as before.
9. **Switch the deploy** with the `deploy` skill: project access on the cluster, a Vault role per app, `_deploy-k8s.yaml` + `deploy.yaml`, its validation checks. Moving from a host to the cluster changes where consumers find a shared service: update its address in Vault and check the consumers. For an app staying on a Compose host: `deploy` → compose-host.md, *Moving a legacy project onto this flow*. That covers the one-time authorization, the redacted survey, **the consumers of every published port** (a shared service's callers break silently), the deploy key, the cutover order (single-app: merging is the cutover) and credential cleanup. *Done when every app is green on the new workflows and the server holds no standing credential.*
10. **Remove the meta.json keys** `compose`, `secrets` and `custom`.

## Traps seen in practice

- **zsh `path`:** in zsh, `for path in …` overwrites `$PATH`, and every command after it fails with "command not found". Use another variable name, or put loops in a `bash` script.
- **Hashing through varlock:** `varlock run` redacts the child's stdout, so hash inside the child (`secrets` skill, Debugging).
- **Copy-paste leftovers** to fix while in the app: wrong meta names, `container_shell` pointing at another project, stale `.env.template`.
- **potion specifics, when its turn comes:** its tunnel keeps the Cloudflare `cert.pem` in plain text in `potion/tunnel/.env.local` (use `ghostmind/global/cloudflare`), and its MCP OAuth is replaced by format's (`system` skill, building blocks).
