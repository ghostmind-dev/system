# Service folder on Kubernetes (the default)

Most apps run on Kubernetes in both environments: the k3s cluster on Hetzner in prod, and an OrbStack cluster in dev (this Mac's, or another Mac's over Tailscale). The image and `.env.schema` are the app; the files below are a thin wrapper around them. Copy from the reference and rename:

- **`/Volumes/Projects/ghostmind/portal`** (`portal/` = the ui, `tunnel/`): the full pattern, prod and dev, no Compose.
- **`/Volumes/Projects/ghostmind/tags`** (db, city, mcp, native, tunnel): several apps in one project, with one shared `k8s/dev-setup.sh` at the project root.
- **`/Volumes/Projects/ghostmind/users`**: a shared service that stays up in dev (`start` routine) with its own local database.
- **`/Volumes/Projects/ghostmind/admin`**: stateful (SQLite on a volume), reachable on the tailnet only through Tailscale Serve.

```
<app>/
  .env.schema                  committed; pointers only
  app/                         source
  docker/  Dockerfile  entrypoint.sh       same image for dev and prod (docker.md)
  k8s/     <app>.yaml  <app>.dev.yaml      prod and dev manifests
  skaffold.yaml                dev: build, deploy to the local cluster, sync, logs
  .dockerignore                node_modules, .next, dist (required, see below)
  meta.json                    routines dev, dev_keep, delete (and start), herdr tab
```

The dev pre-deploy hook (`k8s/dev-setup.sh` at the project root, shared by the apps; or inline in `skaffold.yaml` when only the namespace is needed) is described below. There is no `compose.*.yaml` and no AppRole login for a Kubernetes app.

## Rules

- **The app stays portable.** It works from its image and `.env.schema` alone. No app depends on a Kubernetes feature to work, and it reaches other services only through an address stored in Vault or the schema, never a hardcoded cluster name.
- **Service names keep the container convention:** `<project>-<app>` on the app's port (`http://portal-ui:5096`), identical in dev and prod. One project = one namespace, named after the project.
- **Prod changes only through a merge to main.** No `kubectl apply`, `edit` or `exec` against prod to change an app. Read-only checks (status, logs) are fine.
- **`.dockerignore` is required** and excludes `node_modules`, `.next` and `dist`. Without it the Mac's `node_modules` is copied into the Linux image and hides the image's own.
- **A project with a `shared/` folder builds from the repo root** (potion, tags): TypeScript used by several backends lives in `shared/pure` and `shared/server` at the root and is imported through a `@shared/*` alias. Those apps set skaffold `context: ..` with `dockerfile: <app>/docker/Dockerfile`, list `shared/**` and `<app>/app/src/**` under `sync.infer`, use `context: .` in CI, and share ONE root `.dockerignore`; the Dockerfile copies `shared` next to the app so the image mirrors the repo. Changing `context` in a `skaffold.yaml` is not picked up by a running `skaffold dev`: stop it and start it again.
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

Same Deployment and Service names, one replica, `image: <project>-<app>` (the local image Skaffold builds), `APP_ENV=dev`, no hardening. An app that reads Vault takes `VAULT_ADDR` and `VAULT_TOKEN` from the local Secret `vault-dev` (below). **A remote MCP is the exception: `replicas: 2` in dev too**, because it must be stateless and one pod would hide a request that needs the pod before it (blocks.md → A remote MCP on the cluster is stateless).

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
        - host: { command: ["bash", "scripts/dev-setup.sh"] }
portForward:
  - { resourceType: service, resourceName: <project>-<app>, namespace: <project>, port: <port>, localPort: <port> }
```

- **Hot reload is required.** `sync: infer` copies each edited file matching those patterns into the running container, at the path the Dockerfile's `COPY` lines give it, and the dev server (Vite, Next, nodemon…) reloads. A change outside the synced folders (`package.json`, the Dockerfile) rebuilds the image. List the source folders the dev server watches, and nothing that needs a rebuild.
- **Routines**, every Kubernetes app gets these in its `meta.json`, run in the app folder (one `skaffold dev` per app, each showing only its own logs):
  - `dev`: `skaffold dev --no-prune`. Ctrl-C removes the workload and keeps the image.
  - `dev_keep`: `skaffold dev --no-prune --cleanup=false`. Ctrl-C leaves the workload running.
  - `delete`: `skaffold delete`. Removes a workload left running; the image stays.
  - `start`: `skaffold run --no-prune`, detached, for an always-on shared service (local users).
  There is no `prod` routine.
- **`localPort`** comes from the port registry in the `system` skill: it's a port on the Mac, so it must be unique across projects.

## `k8s/dev-setup.sh`: the pre-deploy hook

Runs before each Skaffold deploy, on the local cluster only (`kubectl --context "$SKAFFOLD_KUBE_CONTEXT"`). Copy `tags/k8s/dev-setup.sh` (project root, shared by every app of the project). It:

1. creates the namespace (idempotent: `create --dry-run=client -o yaml | apply`);
2. creates any persistent volume claim the app keeps across runs;
3. **creates the `vault-dev` Secret from a 12-hour dev-session token**: `vault token create -policy=dev-session -ttl=12h`, reused while it has more than 1 hour left. That policy reads dev paths only, never `…/prod`. Never put the user's own token in the cluster.

An app with no secrets and no volume only needs the namespace, as an inline hook (see `portal/portal/skaffold.yaml`).

## Shared users service

Apps that need users read `DB_USERS_ENDPOINT` from Vault like any other value; nothing in the app changes between environments.

- **Dev:** the local users service (users repo, `start` routine) at `http://state.users.svc.cluster.local:5090/v1/graphql`, stored in `ghostmind/global/users#DB_USERS_ENDPOINT`, on the dev database `users_state_local`. A new app gets local users with no setup. Dev can never read the prod address (`dev-session` denies `…/prod`).
- **Prod:** the same Service name on port 5080, in `ghostmind/global/users/prod#DB_USERS_ENDPOINT`.

## Dev machines: the kube context and the Docker context travel together

Images are built with `push: false`: an image exists only on the Docker daemon that built it, and only the cluster on that same machine can run it. A dev machine is therefore a **pair**, a kube context and a Docker context for the same OrbStack. Switch both, or the pods fail with `container … can't be pulled`:

```
kubectl config use-context <machine> && docker context use <machine>
```

Contexts live in `~/.kube/config` and `~/.docker/contexts`, per Mac, and **no file in a repo names one**: `skaffold.yaml` has no `deploy.kubeContext`, scripts and manifests name no cluster. The one thing a pin used to buy, never deploying dev to prod, is now a habit: look at `kubectl config current-context` before a dev routine.

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

- **Prod:** two replicas on different servers (two connectors), running the existing tunnel from **its own credentials JSON** in Vault (`ghostmind/project/<project>/tunnel/prod#TUNNEL_CREDENTIALS`), written to a RAM `emptyDir`. That credential can only run this one tunnel: no account certificate in prod, and no DNS rights.
- **Dev:** the `ghostmind.app` account certificate (`ghostmind/global/cloudflare#CLOUDFLARED_GHOSTMIND_APP`) creates the dev tunnel and routes DNS; its credentials JSON lives on a volume kept across runs.
- **No Ingress and no Gateway for now.** The tunnel runs as 2 copies and sends each hostname straight to its Service. If the cluster ever consolidates onto one tunnel, use Gateway API, never classic Ingress (ingress-nginx is retired).
- **No Istio.** Isolate with NetworkPolicies (default deny), and add k3s WireGuard between nodes later.
- **One host carrying several services** (the `/mcp` and `/api` paths of the Domains rule): add `path:` to the ingress rules, most specific first, each pointing at its Service.

## Deploy

One workflow per project calls the reusable `_deploy-k8s.yaml` once per app, in dependency order (`needs:`). The `deploy` skill has the flow and the one-time project setup.
