---
name: secrets
description: >-
  Secrets and environment variables in Ghostmind projects with varlock and Vault. Use when writing or
  editing an `.env.schema`, adding/rotating a secret, deciding global vs project secrets, wiring env vars
  into a script, container or workflow, or debugging a missing/wrong variable.
---

# Secrets: varlock + Vault

Every app declares its config in a committed **`.env.schema`**. Values that are secret are **pointers** into Vault, resolved at run time by varlock. Nothing secret is ever written to the repo or to disk.

## Vault layout

Mount `ghostmind/` (KV v2) at `$VAULT_ADDR`:

```
ghostmind/global/<provider>              shared by every project: one path per provider
ghostmind/project/<project>/<app>        this app, all environments
ghostmind/project/<project>/<app>/dev    dev-only values
ghostmind/project/<project>/<app>/prod   prod-only values
```

**Before creating any secret, look in global first.** This prints every global path and its key names, never values:

```bash
for p in $(vault kv list -format=json ghostmind/global | jq -r '.[]'); do
  echo "ghostmind/global/$p: $(vault kv get -format=json ghostmind/global/$p | jq -r '.data.data | keys | join(", ")')"
done
```

If the key is there, point to it. If it's missing and it is shared by nature (a provider API key, infra credentials), ask the user for the value and add it to global. Otherwise it belongs to the project. This repo is public, so write global paths and key names into skills and docs only when a specific app needs them, never as an inventory.

**Global or project?** It is global when the same value serves several products (an OpenRouter key, the RDS admin login, the Hetzner token). It is project-scoped when it belongs to one app (its OAuth client secret, JWT secret, DB password). A new provider gets its own path: `vault kv put ghostmind/global/<provider> KEY=...`. When adding a key to an existing path, use `vault kv patch`, not `put`, so the other keys survive.

The old `kv/` mount (`kv/<meta-id>/<env>/secrets`, one `CREDS` blob per env) is what un-migrated projects still read. Leave it alone.

## The schema

```bash
# @plugin(@varlock/hashicorp-vault-plugin@2.1.1)
# @initHcpVault(url=$VAULT_ADDR, token=$VAULT_TOKEN, roleId=$VAULT_ROLE_ID, secretId=$VAULT_SECRET_ID, defaultPath=ghostmind/project/<project>/<app>)
# @currentEnv=$APP_ENV
# @defaultRequired=true
# @defaultSensitive=false
# ---
# @type=enum(dev, prod)
APP_ENV=dev
# @type=url
VAULT_ADDR=
# dev: your shell's token. prod: empty, the AppRole below is used instead.
# @type=vaultToken @sensitive @required=false
VAULT_TOKEN=
# prod only: set in .env.prod from the files compose mounts (see deploy skill)
# @sensitive @internal @required=false
VAULT_ROLE_ID=
# @sensitive @internal @required=false
VAULT_SECRET_ID=

# --- app config (plain values are fine for non-secrets)
# @type=port
PORT=5001
PUBLIC_URL=https://<app>.ghostmind.app

# --- project secrets: key name = item name, read from defaultPath
# @sensitive
NEXTAUTH_SECRET=vaultSecret()
# @sensitive
GOOGLE_OAUTH_CLIENT_SECRET=vaultSecret()

# --- global secrets: explicit path
# @sensitive
OPENROUTER_API_KEY=vaultSecret("ghostmind/global/openrouter")
```

Values that differ per environment are overridden in committed **`.env.dev`** / **`.env.prod`**. These files hold plain values and pointers only:

```bash
# .env.prod
PUBLIC_URL=https://<app>.ghostmind.dev
STRIPE_SECRET_KEY=vaultSecret("ghostmind/project/potion/ui/prod")
# container auth in prod: files mounted by compose `secrets:`
VAULT_ROLE_ID=exec("cat /run/secrets/vault_role_id")
VAULT_SECRET_ID=exec("cat /run/secrets/vault_secret_id")
```

> The AppRole lines are the target design; the first prod deploy (likely format) is the first real run. If varlock's auth order or `exec` behaves differently than documented, fix this section.

Rules:
- Mark every secret `@sensitive` so varlock redacts it in output and logs.
- Pin the plugin to an exact version. The standalone binary refuses ranges.
- Name the environments `dev` and `prod`. A file named `.env.local` is always loaded by varlock, so it must never exist in a project.
- `.gitignore` carries `.env`, `.env.local` and `.env.*.local`, and nothing that hides `.env.schema`, `.env.dev` or `.env.prod` (template in `new-app` → docker.md). Legacy ones often ignore `.env.prod`; check with `git status` that the pointer files are tracked.
- Paths are `ghostmind/project/...` (singular) and key names match the schema item exactly (`GOOGLE_OAUTH_CLIENT_ID`, not `GOOGLE_OAUTH_CLIENT`). When the user stores a third-party secret, hand them the exact `vault kv patch` command to paste.
- Derived values use functions: `DATABASE_URL=concat("postgres://", $PGUSER, ":", $PGPASSWORD, "@", $PGHOST, "/", $DB_NAME)`. Look up anything beyond this in the docs (`https://varlock.dev/reference/functions/`) rather than guessing.

## Using it

| Where | How |
|---|---|
| Host scripts / routines | `varlock run -- bash scripts/x.sh` |
| A child that needs the Vault token (dev compose passing it to the container, scripts calling the `vault` CLI) | `varlock run --include-internal -- …`: `VAULT_TOKEN` is internal, and without the flag the child gets it **empty** |
| Only part of the schema can resolve yet (bootstrapping the secrets it points to) | `varlock run --filter KEY1,KEY2,… -- …`, as the `database` skill's `create_db` does |
| Compose on the host (for `${PORT}` interpolation in the compose file) | `varlock run --include-internal -- docker compose -f docker/compose.dev.yaml up` |
| Inside a container | `ENTRYPOINT ["varlock","run","--","/entrypoint.sh"]` (see `new-app`) |
| GitHub Actions | `dmno-dev/varlock-action@v1`, or `varlock run --` in a step |
| Next.js / Vite | optional `@varlock/nextjs-integration` / `@varlock/vite-integration` for type-safe `ENV` access; `varlock run` alone is enough |

## Debugging

- `varlock load --agent` resolves everything and prints JSON with secrets redacted. This is the first thing to run when a variable is wrong or missing.
- `varlock load --filter="PG*"` narrows the output. `varlock explain <KEY>` shows where a value came from.
- "No value found" means the path or key does not exist. Check it with `vault kv get -format=json <path> | jq '.data.data | keys'`.
- The process environment wins over every file. A stale `export KEY=...` in the shell, or an old `run` injection, silently overrides the schema.
- Keep varlock current (`brew upgrade varlock`); the plugin needs a recent binary.
