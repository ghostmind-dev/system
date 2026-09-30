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

**Global or project?** It is global when the same value serves several products (an OpenRouter key, the RDS admin login, the Hetzner token). It is project-scoped when it belongs to one app (its OAuth client secret, JWT secret, DB password). **Exception:** a shared service's own secrets live in global when other products call it with them. users' Hasura admin secret is `ghostmind/global/users#DB_USERS_SECRET`, and users' own schema points there too. A new provider gets its own path: `vault kv put ghostmind/global/<provider> KEY=...`. When adding a key to an existing path, use `vault kv patch`, not `put`, so the other keys survive.

The old `kv/` mount (`kv/<meta-id>/<env>/secrets`, one `CREDS` blob per env) is what un-migrated projects still read. Leave it alone.

## The schema

**One committed `.env.schema` per app, for both environments.** Values that differ per environment use `if(forEnv(prod), <prod>, <dev>)`. Reference: `/Volumes/Projects/ghostmind/tags/city/.env.schema` (proven in dev and prod).

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
# prod: the single-use login compose mounts into the container (deploy skill)
# @sensitive @internal @required=false
VAULT_ROLE_ID=if(forEnv(prod), exec("cat /run/secrets/vault_role_id"))
# @sensitive @internal @required=false
VAULT_SECRET_ID=if(forEnv(prod), exec("cat /run/secrets/vault_secret_id"))

# --- app config
# @type=port
PORT=5001
# @type=url
PUBLIC_URL=if(forEnv(prod), "https://<app>.ghostmind.dev", "https://<app>.ghostmind.app")

# --- project secrets: key name = item name, read from defaultPath
# @sensitive
NEXTAUTH_SECRET=vaultSecret()
# --- a key whose Vault name differs from the item: path#KEY
GOOGLE_CLIENT_ID=vaultSecret("ghostmind/project/<project>/auth#GOOGLE_OAUTH_CLIENT_ID")
# --- per-environment secret
# @sensitive
STRIPE_SECRET_KEY=if(forEnv(prod), vaultSecret("ghostmind/global/stripe/prod"), vaultSecret("ghostmind/global/stripe"))
# --- global secret
# @sensitive
OPENROUTER_API_KEY=vaultSecret("ghostmind/global/openrouter")
```

- **`if()` is lazy**: the branch for the other environment never runs, so prod's `exec("cat /run/secrets/…")` and prod-only Vault paths are never touched in dev.
- **Use `if(forEnv(prod), …)`, not `remap()`.** `remap($APP_ENV, dev=a, prod=b)` returns the literal environment name.
- **`vaultSecret("path#KEY")`** reads a Vault key whose name differs from the item. Use it instead of renaming app code or duplicating a value in Vault.
- Separate `.env.dev` / `.env.prod` files also work (format uses them). New apps use the single schema.

Rules:
- Mark every secret `@sensitive` so varlock redacts it in output and logs.
- Pin the plugin to an exact version. The standalone binary refuses ranges.
- Name the environments `dev` and `prod`. A file named `.env.local` is always loaded by varlock, so it must never exist in a project. If real resources already carry the legacy name `local` (a database `x-db-local`, a bucket, a Terraform state path), keep them and map in the schema: `TF_VAR_ENVIRONMENT=if(forEnv(prod), "prod", "local")`.
- `.gitignore` carries `.env`, `.env.local` and `.env.*.local`, and nothing that hides `.env.schema` (template in `new-app` → docker.md).
- Paths are `ghostmind/project/...` (singular), and key names match the schema item exactly unless you use `path#KEY`. When the user stores a third-party secret, hand them the exact `vault kv patch` command to paste.
- Derived values use functions: `DATABASE_URL=concat("postgres://", $PGUSER, ":", $PGPASSWORD, "@", $PGHOST, "/", $DB_NAME)`. Look anything else up in the docs (`https://varlock.dev/reference/functions/`) rather than guessing.
- **Never rename or remove a shared key** (anything under `ghostmind/global/`) without first grepping every `.env.schema` under `/Volumes/Projects` that reads it, and asking the user. Add the new key alongside instead; remove the old one only when nothing reads it.
- **Cloudflare tunnel certs are per zone; name the key after the domain:** `CLOUDFLARED_GHOSTMIND_APP` (`global/cloudflare`, every dev tunnel), `CLOUDFLARED_<DOMAIN>` for a product's own zone. The older `CLOUDFLARED_CREDS` (in `global/cloudflare` and `global/cloudflare/prod`) is still read by format and ensemble.

## Using it

| Where | How |
|---|---|
| Host scripts / routines | `varlock run -- bash scripts/x.sh`, from the **app folder** (varlock only looks for `.env.schema` in the cwd) |
| A host script that needs prod config (Terraform prod, an EAS publish) | the script re-executes itself: `[ -n "${INNER:-}" ] \|\| exec env APP_ENV=prod VAULT_ROLE_ID= VAULT_SECRET_ID= INNER=1 varlock run -- bash "$0" "$@"`. Your own token is used, and the empty values skip the `/run/secrets` reads |
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
- Check prod from the Mac: `APP_ENV=prod VAULT_ROLE_ID= VAULT_SECRET_ID= varlock load --agent` in the app folder.
- **Compare values by hash, never by printing them.** `varlock run` redacts the child's stdout, so hash inside the child: `varlock run -- bash -c 'printf %s "$KEY" | shasum | cut -c1-8'`. For Vault: `vault kv get -field=KEY <path> | shasum | cut -c1-8`.
- The Vault plugin has a fixed 10 s timeout and no retry. Intermittent timeouts under heavy local load are the plugin, not Vault; re-run.
