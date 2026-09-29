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

Reference: `/Volumes/Projects/playground/format/tunnel` (Alpine + varlock); older: `potion/tunnel`. A cloudflared container with `config/ingress.dev.yaml` and `config/ingress.prod.yaml`, which map hostnames → `http://<project>-<target>:<port>` on the compose network. The entrypoint creates the tunnel if missing and routes DNS for each hostname.

- **Credentials:** the account `cert.pem` (base64) is `CLOUDFLARED_CREDS` at `ghostmind/global/cloudflare`: `CLOUDFLARED_CREDS=vaultSecret("ghostmind/global/cloudflare")`. The `CLOUDFLARED_TUNNEL_TOKEN` in the same path is an API token, which the entrypoint does not use.
- The ingress maps each **host** to Traefik, and Traefik splits it by path (see the `system` skill, Domains):

```yaml
# tunnel/config/ingress.prod.yaml
tunnel: <app>-prod
ingress:
  - hostname: <app>.ghostmind.dev
    service: http://<project>-traefik:80
  - service: http_status:404
```

- An app with a single service and nothing else on its host may point the ingress straight at that container and skip Traefik.

## Traefik (whenever one host carries several services)

Reference: `/Volumes/Projects/playground/format/traefik`; older: `potion/traefik`. **It publishes no host port** (no `80:80`, no `8080:8080`), so every project's Traefik can run at once; the tunnel reaches it on the compose network. File provider, `config/dynamic.<env>.yaml`: one host, one router per path prefix. Traefik picks the most specific rule first (longer rules win), so the UI catch-all goes last naturally:

```yaml
# traefik/config/dynamic.prod.yaml
http:
  routers:
    mcp:
      rule: "Host(`<app>.ghostmind.dev`) && (PathPrefix(`/mcp`) || PathPrefix(`/oauth`) || PathPrefix(`/.well-known/oauth-`))"
      service: mcp
      entryPoints: [web]
    api:
      rule: "Host(`<app>.ghostmind.dev`) && PathPrefix(`/api`)"
      service: api
      entryPoints: [web]
    ui:
      rule: "Host(`<app>.ghostmind.dev`)"
      service: ui
      entryPoints: [web]
  services:
    mcp: { loadBalancer: { servers: [ { url: "http://<project>-mcp:<port>" } ] } }
    api: { loadBalancer: { servers: [ { url: "http://<project>-api:<port>" } ] } }
    ui:  { loadBalancer: { servers: [ { url: "http://<project>-ui:<port>" } ] } }
```

`dynamic.dev.yaml` is the same with `ghostmind.app`. When the MCP server also serves the API (as format's does), point both routers at the same service.

## Database

See the `database` skill. The app's schema points `DATABASE_URL` (or `HASURA_GRAPHQL_ENDPOINT`) at the project's DB.

## Worker / internal service

Reference: `/Volumes/Projects/ghostmind/potion/worker`. No `ports:`, reached by container name from sibling apps. Add `mem_limit` / `pids_limit` when it processes untrusted input.
