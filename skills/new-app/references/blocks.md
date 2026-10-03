# Wiring the blocks

## One auth system: the MCP server is the product's OAuth server

The most common product shape is a remote MCP, a web app and often a native app, all behind one Google login. Reference: `/Volumes/Projects/playground/format` (`mcp`, `ui`, `mac`).

- **The MCP server is the authorization server.** It is remote (streamable HTTP over the tunnel), not stdio: Claude clients connect by URL and go through OAuth. Identity is delegated to Google (a Google proxy). Copy `/Volumes/Projects/playground/format/mcp/app/src/auth/oauth.ts`, which gets three things right:
  - **PKCE is enforced**: the client's `code_challenge` is passed to Google and the `code_verifier` forwarded at `/token`, so Google checks it;
  - **redirect URIs are allow-listed**: loopback plus configured https prefixes, so there's no open redirect;
  - **`state` is HMAC-signed**, with a 15-minute expiry.

  `potion/mcp` predates this and has none of the three; don't copy its OAuth. `PUBLIC_DOMAIN` must be the public host (`<app>.ghostmind.dev`), and the OAuth endpoints and `/.well-known/oauth-*` must route to this server on that host (`system` skill, Domains), or the redirects and discovery point at the wrong place.
- **The web app signs in through the same server** (OAuth + PKCE), so there is one auth system for web, MCP and native. The default web app is static React + TanStack on Vite: `/Volumes/Projects/playground/format/ui`. Use Next.js + next-auth (`potion/ui`) only when the app needs server rendering or its own API routes.
- **A native app signs in to the same server** with RFC 8252 loopback + PKCE and keeps tokens in the Keychain: `/Volumes/Projects/playground/format/mac/app/Sources/Format/Account.swift`.
- **One Google OAuth client per product.** `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` live once at `ghostmind/project/<project>/auth` (singular `project`), and every schema points there. Shared signing secrets (`HASURA_GRAPHQL_JWT_SECRET`, the state HMAC key) live there too.

## The product's Claude plugin (MCP + skill)

The remote MCP gives Claude the app's **actions**; a skill gives it the app's **concepts**: what the entities are, which tool to reach for, and the traps. Ship both together as one Claude plugin in the product repo, so installing the plugin is all a user does. Reference: `/Volumes/Projects/ghostmind/potion/plugin`.

```
<project>/
  .claude-plugin/marketplace.json     { "plugins": [ { "name": "<app>", "source": "./plugin" } ] }
  plugin/
    .claude-plugin/plugin.json        name, description, version
    .mcp.json                         { "mcpServers": { "<app>": { "type": "http", "url": "https://<app>.ghostmind.dev/mcp" } } }
    skills/<app>/SKILL.md             the app's model, tool map, traps
```

- **Design the MCP for an agent, not as a REST mirror.** Tools named for what the user wants done (`add_dictionary`, `try_dictation`), returns that say what happened and what to do next, and refusals that explain themselves. Look at potion's and format's tool sets.
- **The skill caches what the tools can't say**: how the entities relate, which of two similar tools to use, what users mean by their words (potion: "sidebar" means Quick Access), and the mistakes an agent would otherwise make. It stays short; `writing-for-agents` has the craft.
- **One source of truth per fact.** Tool behaviour lives in the tool descriptions; the skill points to tools and adds only the knowledge around them.
- **Keep them in step.** A new or renamed MCP tool updates the skill in the same change, and bumps `plugin.json`'s `version` so installed copies refresh.
- **Dev and prod.** The published `.mcp.json` points to prod. To try unreleased tools, add the dev URL (`https://<app>.ghostmind.app/mcp`) as a separate MCP in your own Claude config; never ship it.

## Bring-your-own OpenRouter

When users pay for their own AI: the user connects their key through OpenRouter's PKCE flow, and it is stored AES-GCM-encrypted in an `ai_connections` table that no user role can read. The product never falls back to the owner's key. References: `/Volumes/Projects/playground/format`, and `potion/agent/ai-connection.ts` for the same pattern.

## Tunnel (only if something is public)

A cloudflared app per project sends each hostname **straight to its app's Service**: no Traefik. The pattern, manifests and credentials are in [kubernetes.md](kubernetes.md) → Tunnel. References: `/Volumes/Projects/ghostmind/portal/tunnel` (prod + dev on Kubernetes) and `/Volumes/Projects/ghostmind/tags/tunnel`.

- **Prod** runs the tunnel from its own credentials JSON (`ghostmind/project/<project>/tunnel/prod#TUNNEL_CREDENTIALS`): no account certificate, no DNS rights.
- **Dev** uses the `ghostmind.app` account certificate (`ghostmind/global/cloudflare#CLOUDFLARED_GHOSTMIND_APP`) to create the dev tunnel and route DNS.
- **Several services on one host** (`/mcp`, `/api`, the UI): `path:` rules in the ingress file, most specific first.

Traefik is no longer part of the pattern. Projects that still have a `traefik/` app (format, potion, noice) drop it when they move to Kubernetes.

## Terraform (cloud resources: buckets, service accounts)

No `run terraform`, and nothing to install: Terraform runs in a throwaway `hashicorp/terraform` container through varlock. Reference: `/Volumes/Projects/ghostmind/tags/bucket` (`.env.schema`, `scripts/terraform.sh`, `infra/`).

- **Schema**: `GOOGLE_CREDENTIALS=vaultSecret("ghostmind/global/gcp#GCP_SERVICE_ACCOUNT_JSON")`, `TERRAFORM_BUCKET_NAME=vaultSecret("ghostmind/global/gcp")`, the `TF_VAR_*` inputs, and `TF_STATE_PREFIX` built with `concat()`.
- **`scripts/terraform.sh <dev|prod> [args]`** re-executes itself through `varlock run` with `APP_ENV` set (routines have no shell to set it), then runs `docker run --rm -v "$PWD/infra:/infra" -w /infra -e GOOGLE_CREDENTIALS -e TF_VAR_… hashicorp/terraform:1.13`: `init -reconfigure -backend-config=bucket=… -backend-config=prefix=$TF_STATE_PREFIX`, then the given command (default `plan`).
- **Existing state from the `run` era** lives at `<meta.id>/<legacy env>/terraform/<component>` in `$TERRAFORM_BUCKET_NAME`, with `local` as the dev env name. Keep that prefix (`concat("<meta.id>/", $TF_VAR_ENVIRONMENT, "/terraform/core")` with `TF_VAR_ENVIRONMENT=if(forEnv(prod), "prod", "local")`) and `plan` must show no changes before anything else.
- **Flag resources that write keys to disk** (`local_file` with a service-account key). Prefer putting the key in Vault.

## Database

See the `database` skill. The app's schema points `DATABASE_URL` (or `HASURA_GRAPHQL_ENDPOINT`) at the project's DB.

## Worker / internal service

Reference: `/Volumes/Projects/ghostmind/potion/worker`. No `ports:`, reached by container name from sibling apps. Add `mem_limit` / `pids_limit` when it processes untrusted input.
