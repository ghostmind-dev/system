# Wiring the blocks

## Web app + remote MCP behind one Google login

The most common product shape. Reference: `/Volumes/Projects/ghostmind/potion/ui` and `/Volumes/Projects/ghostmind/potion/mcp`.

- **One Google OAuth client per product**, with redirect URIs for both apps in both environments (`https://<app>.ghostmind.app/...` for dev, product domain for prod). `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET` go in Vault once, at `ghostmind/project/<project>/auth`, and both schemas point there: `vaultSecret("ghostmind/project/<project>/auth")`.
- **The web app** uses next-auth with the Google provider (see `potion/ui`).
- **The MCP is remote** (streamable HTTP over the public tunnel), not stdio: Claude clients connect by URL and go through OAuth. It implements the MCP authorization flow itself, delegating identity to Google. Copy `potion/mcp/app/src/auth/` (`google.ts`, `oauth-routes.ts`) and `main.ts`'s wiring. `PUBLIC_DOMAIN` must be the public hostname, or the OAuth redirects point at the wrong host.
- **Shared identity**: both apps resolve the Google account to the same user row (users table in the product DB, or Hasura JWT as in potion). Shared signing secrets (`HASURA_GRAPHQL_JWT_SECRET`, etc.) live once in `ghostmind/project/<project>/auth`.

## Tunnel (only if something is public)

Reference: `/Volumes/Projects/ghostmind/potion/tunnel`. A cloudflared container with `config/ingress.dev.yaml` and `config/ingress.prod.yaml`, which map hostnames → `http://<project>-<target>:<port>` on the compose network. The entrypoint creates the tunnel if missing and routes DNS for each hostname. Credentials come from Vault (`CLOUDFLARED_CREDS` in the project path, or `ghostmind/global/cloudflare`).

- One public app → point the ingress straight at that container.
- Several public hostnames → point every hostname at traefik and let it route.

## Traefik (only with several public hostnames)

Reference: `/Volumes/Projects/ghostmind/potion/traefik`. File provider, `config/dynamic.<env>.yaml` with a `Host()` router per hostname → `http://<project>-<app>:<port>`.

## Database

See the `database` skill. The app's schema points `DATABASE_URL` (or `HASURA_GRAPHQL_ENDPOINT`) at the project's DB.

## Worker / internal service

Reference: `/Volumes/Projects/ghostmind/potion/worker`. No `ports:`, reached by container name from sibling apps. Add `mem_limit` / `pids_limit` when it processes untrusted input.
