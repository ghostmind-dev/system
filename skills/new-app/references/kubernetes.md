# Service folder on Kubernetes (the default)

Most apps run on Kubernetes in both environments: the k3s cluster on Hetzner in prod, and an OrbStack cluster in dev (this Mac's, or another Mac's over Tailscale). The image and `.env.schema` are the app; the files below are a thin wrapper around them. Copy from the reference and rename:

- **`/Volumes/Projects/portal`** (`portal/` = the ui, `tunnel/`): the full pattern, prod and dev, no Compose.
- **`/Volumes/Projects/tags`** (db, city, mcp, native, tunnel): several apps in one project, with one shared `k8s/dev-setup.sh` at the project root.
- **`/Volumes/Projects/users`**: a shared service that stays up in dev (`start` routine) with its own dev database.
- **`/Volumes/Projects/ghostmind/admin`**: stateful (SQLite on a volume), reachable on the tailnet only through Tailscale Serve.

```
<app>/
  .env.schema                  committed; pointers only
  app/                         source
  docker/  Dockerfile  entrypoint.sh       same image for dev and prod (docker.md)
  k8s/     <app>.yaml  <app>.dev.yaml      prod and dev manifests
  skaffold.yaml                dev: build, deploy to the dev cluster, sync, logs
  .dockerignore                node_modules, .next, dist (required, see below)
  meta.json                    routines dev, dev_keep, delete (and start), herdr tab
```

The dev pre-deploy hook (`k8s/dev-setup.sh` at the project root, shared by the apps; or inline in `skaffold.yaml` when only the namespace is needed) is described below. There is no `compose.*.yaml` and no AppRole login for a Kubernetes app.

## Rules

- **The app stays portable.** It works from its image and `.env.schema` alone. No app depends on a Kubernetes feature to work, and it reaches other services only through an address stored in Vault or the schema, never a hardcoded cluster name.
- **Service names keep the container convention:** `<project>-<app>` on the app's port (`http://portal-ui:5096`), identical in dev and prod. One project = one namespace, named after the project.
- **Prod changes only through a merge to main.** No `kubectl apply`, `edit` or `exec` against prod to change an app. Read-only checks (status, logs) are fine.
- **`.dockerignore` is required** and excludes `node_modules`, `.next` and `dist`. Without it the Mac's `node_modules` is copied into the Linux image and hides the image's own. An image that installs no dependencies (cloudflared, Hasura) doesn't need one.
- **A project with a `shared/` folder builds from the repo root** (potion, tags): TypeScript used by several backends lives in `shared/pure` and `shared/server` at the root and is imported through a `@shared/*` alias. Those apps set skaffold `context: ..` with `dockerfile: <app>/docker/Dockerfile`, list `shared/**` and `<app>/app/src/**` under `sync.infer`, use `context: .` in CI, and share ONE root `.dockerignore`; the Dockerfile copies `shared` next to the app so the image mirrors the repo. Changing `context` in a `skaffold.yaml` is not picked up by a running `skaffold dev`: stop it and start it again.
- **An app that uses a package kept in the same repo** (block: `mcp` and `ui` use `lib/app`, the npm package the product is about) reads it as a `file:` dependency (`"@ghostmind-dev/block": "file:../../lib/app"`) and builds from the repo root the same way: `context: ..`, a Dockerfile that copies `lib/app` to the place it has in the repo before `npm install` (the dependency is a link to it), `lib/app/src/**` under `sync.infer`, and the root `.dockerignore`. An edit to the package then reaches the running app like an edit to the app. Reference: `/Volumes/Projects/block/ui` (`docker/Dockerfile`, `skaffold.yaml`; Vite also needs `server.fs.allow` to reach outside the app's folder).
- **An app that uses a package kept in another repo, live while both are changed** (Potion and tags using `@ghostmind-dev/colors` from `/Volumes/Projects/colors`): the app depends on the published version, and a `<PACKAGE>_SOURCE=npm|local` variable in its schema (default `npm`) switches its dev to the package's working copy. The pod cannot read the Mac's disk: its node is often another machine (the M1), so a `hostPath` mount is empty there. Local mode instead builds the package and copies its `dist/` into a gitignored folder inside the app's synced source (`app/src/<package>-local`), from a routine that watches the package (`colors_local`); Skaffold syncs that folder like the app's own code and the bundler aliases the package name to it when the folder exists (Turbopack `resolveAlias`, with a `*` entry for subpaths). A bundler that runs on the Mac (Vite, Metro) aliases straight to the package's `dist/` and watches its folder (Metro `watchFolders`). Local mode never reaches a release build: publish and CI install from npm. Reference: `/Volumes/Projects/potion` (`ui/scripts/colors-local.sh`, `ui/app/next.config.mjs`, `native/app/metro.config.js`). An edit in the package then shows in the running app in about ten seconds, without a publish.
- **Never put a `Namespace` object in an app's files.** CI isn't allowed to create namespaces, and Skaffold would delete a shared namespace on Ctrl-C. The pre-deploy hook creates it.
- **No file names a cluster.** `skaffold.yaml` has no `deploy.kubeContext`: `skaffold dev` deploys to the current kube context and builds on the current Docker context, which must be the same machine (Dev machines, below).

## Prod manifest: `k8s/<app>.yaml`

A `ServiceAccount` (when the app reads Vault), a `Deployment` and a `Service`. CI replaces `image: IMAGE` with the built digest. The parts that matter, from `portal/tunnel/k8s/tunnel.yaml` and `tags/city/k8s/city.yaml`:

```yaml
spec:
  replicas: 2
  template:
    spec:
      serviceAccountName: <app>
      imagePullSecrets: [{ name: ghcr }]
      topologySpreadConstraints:      # the two copies on different servers
        - { maxSkew: 1, topologyKey: kubernetes.io/hostname, whenUnsatisfiable: ScheduleAnyway, labelSelector: { matchLabels: { app: <app> } } }
      containers:
        - name: <app>
          image: IMAGE
          env:
            - { name: APP_ENV, value: prod }
            - { name: VAULT_ADDR, value: "http://10.0.0.7:8200" }    # Vault over the Hetzner private network
            - { name: VAULT_JWT_ROLE, value: <project>-<app> }
            - { name: HOME, value: /tmp }
          ports: [{ name: http, containerPort: <port> }]
          volumeMounts:
            - { name: vault-token, mountPath: /var/run/secrets/vault, readOnly: true }
            - { name: tmp, mountPath: /tmp }
          securityContext: { readOnlyRootFilesystem: true, allowPrivilegeEscalation: false, capabilities: { drop: [ALL] } }
          resources: { requests: { cpu: 10m, memory: 48Mi }, limits: { memory: 192Mi } }
          readinessProbe: { httpGet: { path: /, port: http }, periodSeconds: 10 }
          livenessProbe:  { httpGet: { path: /, port: http }, periodSeconds: 20 }
      volumes:
        - name: vault-token
          projected: { sources: [ { serviceAccountToken: { audience: vault, expirationSeconds: 600, path: token } } ] }
        - { name: tmp, emptyDir: {} }
```

- An app with no secrets (a static ui) drops the service account, `VAULT_*` and the `vault-token` volume, and sets `automountServiceAccountToken: false`.
- The read-only root filesystem means anything the app writes needs a mounted `emptyDir` (`/tmp`, a framework cache such as `.next/cache`).
- Set memory limits from what the app uses, not from this example.

## Secrets in the pod: Vault login by service account

The pod's service-account token (audience `vault`, 10 minutes, mounted by Kubernetes) is traded for a Vault token at `auth/k8s`. Nothing secret is handed to the app, and varlock is still the entrypoint. The `secrets` skill has the schema lines; the Vault role is:

- name `<project>-<app>`, bound to `system:serviceaccount:<project>:<app>`, audience `vault`, policy `<project>-<app>`, bound to the private network (`10.0.0.0/24`), a 10-minute token. Compare with an existing one: `vault read auth/k8s/role/portal-tunnel`.
- Creating or changing a role or policy changes Vault: ask the user first.

## Dev manifest: `k8s/<app>.dev.yaml`

Same Deployment and Service names, one replica, `image: <project>-<app>` (the local image Skaffold builds), `APP_ENV=dev`, no hardening. An app that reads Vault takes `VAULT_ADDR` and `VAULT_TOKEN` from the Secret `vault-dev` in the dev cluster (below). **A remote MCP is the exception: `replicas: 2` in dev too**, because it must be stateless and one pod would hide a request that needs the pod before it (blocks.md → A remote MCP on the cluster is stateless).

**Shared things belong to no app.** The namespace, persistent volumes and the `vault-dev` Secret are created by a pre-deploy hook, not listed in one app's manifest, so stopping one app (Ctrl-C) never deletes what another uses.

## `skaffold.yaml`: one per app

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata: { name: <app> }
build:
  local: { push: false }             # no registry: the cluster on the Docker host uses the image directly
  tagPolicy: { sha256: {} }
  artifacts:
    - image: <project>-<app>
      context: .
      docker: { dockerfile: docker/Dockerfile, buildArgs: { APP_ENV: dev } }
      sync:
        infer: [ "app/src/**", "app/public/**", "app/index.html" ]
manifests:
  rawYaml: [k8s/<app>.dev.yaml]
deploy:                              # no kubeContext: the current one (Dev machines, below)
  kubectl:
    hooks:
      before:
        - host: { command: ["bash", "../k8s/dev-setup.sh"] }   # the project's shared hook
portForward:
  - { resourceType: service, resourceName: <project>-<app>, namespace: <project>, port: <port>, localPort: <port> }
```

- **Hot reload is required.** `sync: infer` copies each edited file matching those patterns into the running container, at the path the Dockerfile's `COPY` lines give it, and the dev server (Vite, Next, nodemon…) reloads. A change outside the synced folders (`package.json`, the Dockerfile) rebuilds the image. List the source folders the dev server watches, and nothing that needs a rebuild.
- **Routines**, every Kubernetes app gets these in its `meta.json`, run in the app folder (one `skaffold dev` per app, each showing only its own logs):
  - `dev`: `skaffold dev --no-prune`. Ctrl-C removes the workload and keeps the image.
  - `dev_keep`: `skaffold dev --no-prune --cleanup=false`. Ctrl-C leaves the workload running.
  - `delete`: `skaffold delete`. Removes a workload left running; the image stays.
  - `start`: `skaffold run --no-prune`, detached, for an always-on shared service (the dev users service).
  There is no `prod` routine.
- **`localPort`** comes from the port registry in the `system` skill: it's a port on the Mac, so it must be unique across projects.

## `k8s/dev-setup.sh`: the pre-deploy hook

Runs before each Skaffold deploy, on the dev cluster Skaffold is deploying to (`kubectl --context "$SKAFFOLD_KUBE_CONTEXT"`); it refuses the prod context. Copy `tags/k8s/dev-setup.sh` (project root, shared by every app of the project). It:

1. creates the namespace (idempotent: `create --dry-run=client -o yaml | apply`);
2. creates any persistent volume claim the app keeps across runs;
3. **creates the `vault-dev` Secret from a 12-hour dev-session token**: `vault token create -policy=dev-session -ttl=12h`, reused while it has more than 1 hour left. That policy reads dev paths only, never `…/prod`. Never put the user's own token in the cluster.

An app with no secrets and no volume only needs the namespace, as an inline hook (see `portal/portal/skaffold.yaml`).

## `k8s/remove.sh`: take the project off a dev cluster

The root `meta.json` has a `remove` routine (`bash k8s/remove.sh`). It deletes the project's namespace on the current kube context, and with it every app, Service, Secret and volume; it refuses the context `ghostmind`. Copy `tags/k8s/remove.sh`. The per-app `delete` routine removes one workload; `remove` clears the whole project, for example before moving it to another dev machine. A project lives on one dev cluster at a time: two would fight over the same dev tunnel.

## Shared users service

Apps that need users read `DB_USERS_ENDPOINT` from Vault like any other value; nothing in the app changes between environments.

- **Dev:** the users service on the dev cluster (users repo, `start` routine) at `http://state.users.svc.cluster.local:5090/v1/graphql`, stored in `ghostmind/global/users#DB_USERS_ENDPOINT`, on the dev database `users_state_local`. A new app gets dev users with no setup. Dev can never read the prod address (`dev-session` denies `…/prod`).
- **Prod:** the same Service name on port 5080, in `ghostmind/global/users/prod#DB_USERS_ENDPOINT`.

## Dev machines: the kube context and the Docker context travel together

Images are built with `push: false`: an image exists only on the Docker daemon that built it, and only the cluster on that same machine can run it. A dev machine is therefore a **pair**, a kube context and a Docker context for the same OrbStack. Switch both, or the pods fail with `container … can't be pulled`:

```
kubectl config use-context <machine> && docker context use <machine>
```

Contexts live in `~/.kube/config` and `~/.docker/contexts`, per Mac, and **no file in a repo names one**: `skaffold.yaml` has no `deploy.kubeContext`, scripts and manifests name no cluster. The one thing a pin used to buy, never deploying dev to prod, is now a habit: look at `kubectl config current-context` before a dev routine.

**The switch must be seen to have worked.** `kubectl config use-context` answers `error: open ~/.kube/config.lock: file exists` when a `kubectl` that died left its lock behind, and the context stays where it was: every dev routine after that goes to the wrong cluster while the command line looks right. Read `kubectl config current-context` after switching. A lock that is empty and older than any running `kubectl` is removed by hand (`ls -la ~/.kube/config.lock`, then `rm`). This is how a project was deployed twice, once on the laptop's own cluster where its database could not start (block, 2026-10-13).

**A dev routine refuses the wrong cluster by asking it, not by its name.** `k8s/dev-setup.sh` runs before every deploy: for a product with a database or sign-in, it stops when the cluster has no shared Postgres (`kubectl -n db get service db-postgres`), before it makes the namespace. No file names a cluster, and nothing lands on a laptop by mistake. Reference: `/Volumes/Projects/block/k8s/dev-setup.sh`.

**Which machine.** The shared dev services run on the M1's cluster only: the users service and the shared Postgres. A product that signs people in or has a database therefore runs its dev there (`kubectl config use-context m1 && docker context use m1`). On another Mac's cluster their names do not resolve, and the app fails at its first sign-in or query, not at start. Do not get around it with a Tailscale address in the project's own Vault path: the schema would then differ from every other product's.

**One command on another machine, without switching** (a check, a redeploy while the Mac stays on its own cluster): name both halves on the command line, where no file keeps them.

```
DOCKER_CONTEXT=m1 skaffold run --no-prune --kube-context m1
```

**Do not `git stash` (or switch branch and back) in a repo whose `skaffold dev` is running.** It sees the files go back, then forward, and can build while they are back: its cache then holds the new files' hash against an image made from the old ones, and every later change answers `Found Locally` with that old image (the pod keeps the old `.env.schema`, so a new variable never arrives). To get out without restarting anything: change the content of a file the image depends on, then `touch` the app's `.env.schema`. To compare with the last commit, use `git worktree` or `git show`.

**Do not change the cluster under a running `skaffold dev`.** It reads `skaffold.yaml` again on every change and keeps the Docker daemon it started with: removing a `kubeContext` (or switching the kube context) while it runs sends the next deploy to the other cluster with an image that only the first machine has, and the pod fails with `can't be pulled`. Stop it, change, start it again; then delete the namespace it left on the wrong cluster (`bash k8s/remove.sh` on that context).

**Another Mac's OrbStack over Tailscale** (the kube context's server is the tailnet address). Its Docker daemon cannot be an `ssh://` context: Skaffold reads the context but its built-in Docker client cannot dial `ssh://`, and fails after `Checking cache` with `Cannot connect to the Docker daemon at ssh://<host>`, with or without `useDockerCLI`. Forward the remote socket over SSH to a local socket and point the Docker context at that:

```
mkdir -p ~/.docker/sockets
ssh -o StreamLocalBindUnlink=yes -o ExitOnForwardFailure=yes -fnNT \
  -L ~/.docker/sockets/<machine>.sock:/Users/<user>/.orbstack/run/docker.sock <ssh host>
docker context create <machine> --docker "host=unix://$HOME/.docker/sockets/<machine>.sock"
```

The forward is one `ssh` process: it dies with a reboot or a dropped tailnet link, and the Docker context fails until it is started again (a launchd agent with `KeepAlive` makes it permanent).

## Gotchas

- A bare `kubectl` hits whatever context is current, normally a dev OrbStack. Every script that touches prod passes `--context ghostmind`.
- After an OrbStack restart, builds can fail with `proxy.orb.internal … i/o timeout`: run `orb stop && orb start`. OrbStack has 10 GB of RAM, so keep an eye on how many apps run at once.
- Hasura in a read-only container needs `emptyDir` volumes at `/root/.hasura` and `/hasura-project/seeds` for its CLI.

## Tunnel: straight to the Services, no Traefik

A cloudflared Deployment per project sends each hostname to its app's Service. Reference: `portal/tunnel` and `tags/tunnel`.

```yaml
# tunnel/config/ingress.prod.yaml
tunnel: <project>-prod
ingress:
  - hostname: <app>.ghostmind.dev
    service: http://<project>-ui:<port>
  - service: http_status:404
```

- **Both environments, from the first day.** `config/ingress.dev.yaml` and `ingress.prod.yaml`, `k8s/tunnel.dev.yaml` and `tunnel.yaml`, a `skaffold.yaml` and the `dev` routines like any app, and a herdr tab. The dev tunnel's credentials volume (`tunnel-creds`) is made by `k8s/dev-setup.sh`. A tunnel written for prod only fails `comply`.
- **Prod:** two replicas on different servers (two connectors), running the existing tunnel from **its own credentials JSON** in Vault (`ghostmind/project/<project>/tunnel/prod#TUNNEL_CREDENTIALS`), written to a RAM `emptyDir`. That credential can only run this one tunnel: no account certificate in prod, and no DNS rights.
- **Dev:** the `ghostmind.app` account certificate (`ghostmind/global/cloudflare#CLOUDFLARED_GHOSTMIND_APP`) creates the dev tunnel and routes DNS; its credentials JSON lives on a volume kept across runs.
- **Do not ask for a new hostname before the tunnel has made it.** A resolver that is asked first keeps the answer "no such name" for as long as the zone says (30 minutes on these zones), and the home router is one: the site is up, `curl` and the browser say it is not. Check with a public resolver (`dig +short <host> @1.1.1.1`, `curl --doh-url https://1.1.1.1/dns-query …`) and wait; flushing the Mac's cache changes nothing.
- **No Ingress and no Gateway for now.** The tunnel runs as 2 copies and sends each hostname straight to its Service. If the cluster ever consolidates onto one tunnel, use Gateway API, never classic Ingress (ingress-nginx is retired).
- **No Istio.** Isolate with NetworkPolicies (default deny), and add k3s WireGuard between nodes later.
- **One host carrying several services** (the `/mcp` and `/api` paths of the Domains rule): add `path:` to the ingress rules, most specific first, each pointing at its Service.

## Deploy

One workflow per project calls the reusable `_deploy-k8s.yaml` once per app, in dependency order (`needs:`). The `deploy` skill has the flow and the one-time project setup.
