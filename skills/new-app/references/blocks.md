# Wiring the blocks

## One auth system: the MCP server is the product's OAuth server

The most common product shape is a remote MCP, a web app and often a native app, all behind one Google login. Reference: `/Volumes/Projects/format` (`mcp`, `ui`, `mac`).

- **The MCP server is the authorization server.** It is remote (streamable HTTP over the tunnel), not stdio: Claude clients connect by URL and go through OAuth. Identity is delegated to Google (a Google proxy). Copy `/Volumes/Projects/format/mcp/app/src/auth/oauth.ts`, which gets three things right:
  - **PKCE is enforced**: the client's `code_challenge` is passed to Google and the `code_verifier` forwarded at `/token`, so Google checks it;
  - **redirect URIs are allow-listed**: loopback plus configured https prefixes, so there's no open redirect;
  - **`state` is HMAC-signed**, with a 15-minute expiry.

  `potion/mcp` predates this and has none of the three; don't copy its OAuth. `PUBLIC_DOMAIN` must be the public host (`<app>.ghostmind.dev`), and the OAuth endpoints and `/.well-known/oauth-*` must route to this server on that host (`system` skill, Domains), or the redirects and discovery point at the wrong place.
- **The web app signs in through the same server** (OAuth + PKCE), so there is one auth system for web, MCP and native. The default web app is static React + TanStack on Vite: `/Volumes/Projects/format/ui`. Use Next.js + next-auth (`potion/ui`) only when the app needs server rendering or its own API routes.
- **One host in dev too, and it is the tunnel's.** A product with a web app or a remote MCP has a `tunnel/` app from its first day, with both environments: `<app>.ghostmind.app` in dev and `<app>.ghostmind.dev` in prod, routed by path the same way (`/mcp`, `/oauth/*`, `/.well-known/oauth-*` and `/api/*` to the MCP's Service, the rest to the web app's). The MCP's dev `PUBLIC_URL` is `https://<app>.ghostmind.app`, that address is in its allowed redirects and in the Google client's redirect URIs, and the project's `.mcp.json` points Claude Code at `https://<app>.ghostmind.app/mcp`. The web app's dev server may also proxy the same paths (`server.proxy`, target from a `MCP_URL=http://<project>-mcp:<port>` schema variable) so that `localhost:<ui port>` works for someone at the machine; it needs `server.allowedHosts` for the tunnel to reach it. Do not build dev on `localhost` alone and leave the tunnel for the day of the prod deploy: block did, and its dev host, its redirect URIs and its docs all had to be changed afterwards. Reference: `/Volumes/Projects/block/tunnel`, `block/mcp/.env.schema` and `block/ui/app/vite.config.ts`.
- **A native app signs in to the same server** with RFC 8252 loopback + PKCE and keeps tokens in the Keychain: `/Volumes/Projects/format/mac/app/Sources/Format/Account.swift`.
- **One Google OAuth client per product.** `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` live once at `ghostmind/project/<project>/auth` (singular `project`), and every schema points there. Shared signing secrets (`HASURA_GRAPHQL_JWT_SECRET`, the state HMAC key) live there too.

## A remote MCP on the cluster is stateless

On Kubernetes an MCP runs several replicas behind a Service and nothing pins a client to a pod. A server that keeps sessions in process memory (a `transports` map filled at `initialize`) answers `404 Session not found` (-32001) as soon as the next request lands on another pod. potion's prod MCP did exactly that at 2 replicas, and dev hid it because dev ran one pod. So: **no session map, no `sessionIdGenerator`, a fresh server per request, the caller resolved from the bearer token and headers on every request. Any pod answers any request.** Reference: `/Volumes/Projects/potion/mcp` (`app/src/main.ts`, `app/src/auth/google.ts`, `app/test/stateless.smoke.ts`, `k8s/mcp.dev.yaml`). Take the transport from potion and the OAuth from format (above).

- **SDK v2**, which implements spec revision 2026-07-28 (sessions and the `initialize` handshake are gone from the protocol): `@modelcontextprotocol/server` ^2.3.0 + `@modelcontextprotocol/node`, not `@modelcontextprotocol/sdk` 1.x. It needs `zod` ^4.2.0 and `@types/node` ^20.
- **The shape:**

  ```ts
  const mcpHandler = createMcpHandler(({ authInfo }) => {
    const server = new McpServer({ name, version });
    registerTools(server, authInfo?.extra?.userContext);
    return server;
  });
  const mcpNodeHandler = toNodeHandler(mcpHandler);   // wrapped once, at module level

  app.all('/', async (req, res) => {
    // authenticate; 401 + WWW-Authenticate when there is no caller; GET and DELETE answer 405
    req.auth = { token, clientId, scopes: [], extra: { userContext } };
    await mcpNodeHandler(req, res, req.body);
  });
  ```

  The default `legacy: 'stateless'` also serves clients still on the 2025 handshake; no `Mcp-Session-Id` is issued, and one a client sends is ignored.
- **Auth runs on every request, so cache validated tokens briefly**: per pod, keyed by the sha256 of the token, successes only, 60 s (potion's `auth/google.ts`).
- **The dev manifest runs `replicas: 2`**, so a request that needs the pod before it can't hide in dev.
- **Test by deleting the serving pod mid-session**, then calling again without reconnecting. The tunnel pins a connection to one pod, so load alone never reaches the others. potion: 35 tool calls on one client connection, the serving pod deleted three times, zero failures.
- **Anything a tool must remember between calls lives in the database**, never in the process.

A single-host Compose deploy runs one container and isn't bound by this rule; an MCP that will move to the cluster is.

## The product's Claude plugin (MCP + skill)

The remote MCP gives Claude the app's **actions**; a skill gives it the app's **concepts**: what the entities are, which tool to reach for, and the traps. Ship both together as one Claude plugin in the product repo, so installing the plugin is all a user does. Reference: `/Volumes/Projects/potion/plugin`.

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
- **Let the plugin's user pin a workspace.** When the product has workspaces (`system` → *Workspaces*), the MCP reads a `workspace` header (the workspace's name) and falls back to the person's default, so a project's own `.mcp.json` can add `"headers": { "workspace": "<name>" }` and every call from that project lands in the right place. Reference: `/Volumes/Projects/potion/mcp` and its `shared/server/workspace-resolver.ts`.
- **Keep them in step.** A new or renamed MCP tool updates the skill in the same change, and bumps `plugin.json`'s `version` so installed copies refresh.
- **Dev and prod.** The published `.mcp.json` points to prod. To try unreleased tools, add the dev URL (`https://<app>.ghostmind.app/mcp`) as a separate MCP in your own Claude config; never ship it.

## Bring-your-own OpenRouter

When users pay for their own AI: the user connects their key through OpenRouter's PKCE flow, and it is stored AES-GCM-encrypted in an `ai_connections` table that no user role can read. The product never falls back to the owner's key. References: `/Volumes/Projects/format`, and `potion/agent/ai-connection.ts` for the same pattern.

## Payments: billing

A product that sells a plan does not integrate Stripe. It uses **billing** (`/Volumes/Projects/billing`, repo `ghostmind-app/billing`): one Stripe account, one webhook and one Stripe customer per person, for every product. The product gets no Stripe key, no Stripe package, no webhook route and no billing table. Its README has the contract and stays the source of truth; this is the order of work.

**In the billing repo** (dev first):

1. Add the product to `api/app/catalogue.json`: its key, name, its dev and prod origins (`return_origins`: the only addresses Stripe may send a person back to) and its plans, amounts in cents.
2. `cd api && run routine catalogue`. It creates the Stripe product and prices in test mode, found by lookup key (`<product>_<plan>_monthly`), and the rows in billing's database. Nothing is deleted; a changed amount makes a new price for new buyers.
3. `run routine product_token <product> dev`. It stores the product's one credential at `ghostmind/project/billing/clients/<product>/dev#BILLING_TOKEN`.

**In the product:**

4. Two lines in the `.env.schema` of every app whose server reads a plan or asks for a link. That is every backend that imports the product's billing client, not only the web (potion: ui, mcp, native, chrome):

   ```bash
   # @type=url
   BILLING_ENDPOINT=if(forEnv(prod), vaultSecret("ghostmind/global/billing/prod#BILLING_ENDPOINT"), vaultSecret("ghostmind/global/billing#BILLING_ENDPOINT"))
   # @sensitive
   BILLING_TOKEN=if(forEnv(prod), vaultSecret("ghostmind/project/billing/clients/<product>/prod#BILLING_TOKEN"), vaultSecret("ghostmind/project/billing/clients/<product>/dev#BILLING_TOKEN"))
   ```

5. Four server-side calls, each with `Authorization: Bearer $BILLING_TOKEN`. The browser never calls billing.

   | When | Call | Then |
   |---|---|---|
   | A paid feature is gated | `GET /api/v1/entitlement?user_id=` | `plan` is `free` or the plan key. Cache about a minute |
   | The person clicks upgrade | `POST /api/v1/checkout` `{ user_id, plan, success_url, cancel_url }` | redirect the browser to `url` |
   | The person clicks manage | `POST /api/v1/portal` `{ user_id, return_url }` | redirect the browser to `url` |
   | The person deletes their account | `POST /api/v1/cancel` `{ user_id }` | their subscriptions for this product end now |

   - `user_id` is the shared `users.userId` (Google sign-in, above), never a provider id or an id of the product's own. Billing asks the users service and refuses one it does not know.
   - After checkout the person lands on `success_url` a moment before Stripe's webhook reaches billing. Show "confirming" and read the entitlement again for a few seconds; do not grant access from the redirect.
   - A refusal is `{ error, message }`; `already_subscribed` (409) means send them to the portal.
   - When billing cannot be reached, keep the last answer you had for that person; with none, treat them as free and say payment status is unavailable. Never block sign-in on it.

6. Test in dev against Stripe test mode: card `4242 4242 4242 4242`, any future date. `cd /Volumes/Projects/billing/api && run routine e2e <email>` proves billing's own side. The product's side is quickest from a signed-in browser tab on its dev address: `fetch` its own plan, checkout and portal routes and read the answers (free, two Stripe URLs; after a payment `pro`, and checkout refused).

**For prod**, after billing itself is deployed: the catalogue sync through billing's mcp (`sync_catalogue`), `run routine product_token <product> prod`, then the product's `k8s/prod-init.sh --apply`, which adds the two prod paths to its Vault policy, then the merge to `main`. A product with no `prod-init.sh` (potion) adds the two paths to `vault/config/policies/<product>-<app>.hcl`, one file per app from step 4, and uploads each with `vault policy write`. The token and the policies come BEFORE the merge: a pod whose schema names a path its policy cannot read does not start.

What a product may still do itself: decide what each plan unlocks, and count its own usage. Limits live in the product; who paid lives in billing.

**Operating it** is through billing's Claude plugin (the skill `billing`): who pays for what, access given by hand, Stripe's events, reconcile. Its MCP has no public address: `run routine forward` (dev) or `forward_prod` in `billing/mcp`.

**The reference for the product's side is tags**: `/Volumes/Projects/tags/shared/server/billing.ts` (one client for its three backends: the plan of a person kept a minute, asked again before a refusal, the last answer used when billing is down; the two links) and `city/app/src/app/api/stripe/*` (three small routes). Potion is the second one, with four backends: `/Volumes/Projects/potion/shared/server/billing.ts` adds the call to `/cancel` and keeps the product's limits beside the client.

How it holds together, for when something looks wrong:

- **One Stripe account, one webhook endpoint per mode** (test: `billing.ghostmind.app`, live: `billing.ghostmind.dev`). No product has a webhook. A product that had one before moving deletes its endpoint in Stripe at cutover, or Stripe keeps calling a route that is gone.
- **One Stripe customer per person, one subscription per person and product.** The same person can be Pro in one product and free in another; the Stripe portal lists all of theirs.
- **Dev and prod share nothing secret.** Dev is Stripe test mode with its own signing key and tokens; prod's are under `…/prod` paths a dev session cannot read. A dev token never opens prod.
- **Moving a product resets everyone to free**, unless their subscriptions are imported: billing knows only what it sold or was told. Before the merge to `main`, list what the product refuses to a free person (potion: its whole MCP) and decide with the owner: lift the gate, subscribe again, or a grant.
- **Moving a product that already has payers:** each of their Stripe subscriptions gets the metadata `user_id`, `product`, `plan`, then `reconcile_with_stripe` imports them. With a handful of payers, cancelling and subscribing again is simpler and leaves one customer per person.

## Html written by a model: the block package

When a product shows html that an AI (or a person) wrote, such as a chart in a note, a dashboard, the box under the mouse on a map or a card in a list, it shows it with **`@ghostmind-dev/block`** (`/Volumes/Projects/block/lib`, plain ESM JavaScript, no dependency, no build). Potion, Relay and Tags each wrote their own frame before the package existed; a new product never does. Read `/Volumes/Projects/block/README.md` first.

What the package is, and what stays the product's:

| The package | The product |
|---|---|
| The frame: `sandbox="allow-scripts"` and a policy with no network, no storage and no way to the page. It does not loosen | Where blocks are kept (a table, a note's text) |
| Libraries: a block names any npm package on its first lines (`<!-- block:use three@0.186 -->`) and gets it as a global. Fetched from jsDelivr by the reader's browser; no cache of ours | The MCP tools that take a block's source, and the skill that teaches writing one |
| Slots: `defineSlot` declares a place and its room (width, height, whether it is clicked); `mount` keeps a block inside it; `slotText` says the same numbers to the model | Which slots exist and how big each is |
| The bridge: `defineHost({ name, calls, events })` makes `window.<name>` in the block; `serve` answers each call with the product's own function | What the block may read and change (`potion.self()`, `relay.act()`), with the product's own permissions, and asking the person before a write |

- **On a web page:** `mount(container, html, { slot, host, handlers, loader })` from `@ghostmind-dev/block/web`. In React, wrap it in one effect: `/Volumes/Projects/block/ui/app/src/frame.tsx`.
- **Anywhere else** (a server that renders the document, a React Native web view): `parse`, `documentOf` and `serve`, which are text in and text out.
- **Declare the slots once, on the server**, and give the same objects to `mount` and to the tool descriptions (`/Volumes/Projects/block/mcp/app/src/blocks/slots.ts`, `contract.ts`). A size written by hand in a tool description and again in the page's CSS drifts: tags stated its hover width three different ways.
- **Bring a block's libraries before saving it** (`makeLoader().loadAll`, as `block/mcp/app/src/blocks/check.ts` does), and refuse the save with the reason when one cannot be brought. The model then fixes the name instead of leaving a block that shows an error.
- **Show what the block threw.** `mount`'s `onError` gives the message; a block that throws is otherwise an empty box nobody can explain.
- **Never loosen the frame for a feature.** A block that needs something from outside gets a call on the product's host.
- Until it is on npm, a product in another repo copies `lib/app/src` or depends on the git repo; block's own apps read it as a `file:` dependency and build from the repo root.

## Tunnel (only if something is public)

A cloudflared app per project sends each hostname **straight to its app's Service**: no Traefik. The pattern, manifests and credentials are in [kubernetes.md](kubernetes.md) → Tunnel. References: `/Volumes/Projects/portal/tunnel` (prod + dev on Kubernetes) and `/Volumes/Projects/tags/tunnel`.

- **Prod** runs the tunnel from its own credentials JSON (`ghostmind/project/<project>/tunnel/prod#TUNNEL_CREDENTIALS`): no account certificate, no DNS rights.
- **Dev** uses the `ghostmind.app` account certificate (`ghostmind/global/cloudflare#CLOUDFLARED_GHOSTMIND_APP`) to create the dev tunnel and route DNS.
- **Several services on one host** (`/mcp`, `/api`, the UI): `path:` rules in the ingress file, most specific first.

Traefik is no longer part of the pattern, and no project has a `traefik/` app any more.

## Terraform (cloud resources: buckets, service accounts)

No `run terraform`, and nothing to install: Terraform runs in a throwaway `hashicorp/terraform` container through varlock. Reference: `/Volumes/Projects/tags/bucket` (`.env.schema`, `scripts/terraform.sh`, `infra/`).

- **Schema**: `GOOGLE_CREDENTIALS=vaultSecret("ghostmind/global/gcp#GCP_SERVICE_ACCOUNT_JSON")`, `TERRAFORM_BUCKET_NAME=vaultSecret("ghostmind/global/gcp")`, the `TF_VAR_*` inputs, and `TF_STATE_PREFIX` built with `concat()`.
- **`scripts/terraform.sh <dev|prod> [args]`** re-executes itself through `varlock run` with `APP_ENV` set (routines have no shell to set it), then runs `docker run --rm -v "$PWD/infra:/infra" -w /infra -e GOOGLE_CREDENTIALS -e TF_VAR_… hashicorp/terraform:1.13`: `init -reconfigure -backend-config=bucket=… -backend-config=prefix=$TF_STATE_PREFIX`, then the given command (default `plan`).
- **Existing state from the `run` era** lives at `<meta.id>/<legacy env>/terraform/<component>` in `$TERRAFORM_BUCKET_NAME`, with `local` as the dev env name. Keep that prefix (`concat("<meta.id>/", $TF_VAR_ENVIRONMENT, "/terraform/core")` with `TF_VAR_ENVIRONMENT=if(forEnv(prod), "prod", "local")`) and `plan` must show no changes before anything else.
- **Flag resources that write keys to disk** (`local_file` with a service-account key). Prefer putting the key in Vault.

## Database

See the `database` skill. The app's schema points `DATABASE_URL` (or `HASURA_GRAPHQL_ENDPOINT`) at the project's DB.

## Things at home: relay

A product in the cloud cannot see a person's home network. **relay** (`/Volumes/Projects/relay`) is the one way in, for every product: the person runs one small program at home, signed in to their relay account, and chooses which of our apps may use it. A product never ships its own program for the home, never asks the person to open a port, and never holds its own connection into the house. Its README has the API, the MCP tools and the protocol; it is on dev only so far (`https://relay.ghostmind.app`), so check its state before relying on it.

**Make a product relay compatible whenever it touches something in the place where the person is** (plays on a speaker, switches a light, reads a sensor). It is three small things, all on the product's server. Reference: `/Volumes/Projects/noice/ui/app/src/speakers.js`.

- **Ask relay as the person, with the token they showed the product.** `GET <RELAY_URL>/api/things?kind=…` lists what their relays see; `POST <RELAY_URL>/api/act` `{ thing, action, params }` tells one thing to do something and returns how it went. `RELAY_URL` is in the product's schema: `if(forEnv(prod), "https://relay.ghostmind.dev", "https://relay.ghostmind.app")`.
- **Be known to relay.** relay recognises a product by the Google OAuth client that issued the token: add `<product>=<its client id>` to `TRUSTED_APPS` in relay's `api/.env.schema`. That is a change in the relay project, deployed there.
- **Pass relay's refusals on, word for word.** Until the person runs `relay allow <product>`, every call answers 403 with the sentence to show. No relay connected, a thing that is away, an action a thing cannot do: each comes back as a sentence a person can act on. Show it in the UI and return it from the MCP tool; do not replace it with a generic error.

- **Put "Connect relay" in the product's settings.** It is where a person looks for what the product is connected to, and it is the same place in every product. It shows whether relay is connected and, when it is not, a button to relay's own page, `<RELAY_URL>/connect?app=<product>&return=<the settings page>`, where the person signs in to relay and allows the product; they come back with `?relay=connected`. Where the product uses a thing (a list of speakers), a short line pointing to settings is enough. Reference for the flow: noice (its button sits under the Player today, before it had a settings page).

Keep the product's own words in its own tools (noice has `play_on_speaker`, not `act`): relay knows things and actions, the product knows what they mean for it.

**What does not exist yet**, so do not design on it: a product *offering* its own things to relay for other products to use (a dashboard in one product driving another through relay), and giving a product some things and not others. Between two products in the cloud, use each product's MCP or API directly.

## Worker / internal service

Reference: `/Volumes/Projects/potion/worker` (`k8s/worker.yaml`). A Deployment and a Service like any app, with no route in the tunnel: sibling apps reach it at `http://<project>-worker:<port>`. Set its memory limit from what it really uses, and keep the prod manifest's hardening (read-only root filesystem, no capabilities) when it processes untrusted input.
