# Service folder on Kubernetes (the default)

Most apps run on Kubernetes in both environments: the k3s cluster on Hetzner in prod, and OrbStack's local cluster on the Mac in dev. The image and `.env.schema` are the app; the files below are a thin wrapper around them. Copy from the reference and rename:

- **`/Volumes/Projects/ghostmind/portal`** (`portal/` = the ui, `tunnel/`): the full pattern, prod and dev, no Compose.
- **`/Volumes/Projects/ghostmind/tags`** (db, city, mcp, native, tunnel): prod on the cluster with Vault logins; its dev still uses Compose.

```
<app>/
  .env.schema                  committed; pointers only
  app/                         source
  docker/  Dockerfile  entrypoint.sh       same image for dev and prod (docker.md)
  k8s/     <app>.yaml  <app>.dev.yaml      prod and dev manifests
  skaffold.yaml                dev: build, deploy to the local cluster, sync, logs
  scripts/ dev-setup.sh        dev pre-deploy hook, when the app needs Vault or a volume
  meta.json                    routine "dev": "skaffold dev", herdr tab
```

## Rules

- **The app stays portable.** It works from its image and `.env.schema` alone. No app depends on a Kubernetes feature to work, and it reaches other services only through an address stored in Vault or the schema, never a hardcoded cluster name.
- **Service names keep the container convention:** `<project>-<app>` on the app's port (`http://portal-ui:5096`), identical in dev and prod. One project = one namespace, named after the project.
- **Prod changes only through a merge to main.** No `kubectl apply`, `edit` or `exec` against prod to change an app. Read-only checks (status, logs) are fine.
- **Each `skaffold.yaml` pins `deploy.kubeContext: orbstack`**, so `skaffold dev` can never touch prod.

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

Same Deployment and Service names, one replica, `image: <project>-<app>` (the local image Skaffold builds), `APP_ENV=dev`, no hardening. An app that reads Vault takes `VAULT_ADDR` and `VAULT_TOKEN` from the local Secret `vault-dev` (below).

**Shared things belong to no app.** The namespace, persistent volumes and the `vault-dev` Secret are created by a pre-deploy hook, not listed in one app's manifest, so stopping one app (Ctrl-C) never deletes what another uses.

## `skaffold.yaml`: one per app

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata: { name: <app> }
build:
  local: { push: false }             # OrbStack's cluster uses locally built images directly
  tagPolicy: { sha256: {} }
  artifacts:
    - image: <project>-<app>
      context: .
      docker: { dockerfile: docker/Dockerfile, buildArgs: { APP_ENV: dev } }
      sync:
        infer: [ "app/src/**", "app/public/**", "app/index.html" ]
manifests:
  rawYaml: [k8s/<app>.dev.yaml]
deploy:
  kubeContext: orbstack              # the local cluster, pinned: never prod
  kubectl:
    hooks:
      before:
        - host: { command: ["bash", "scripts/dev-setup.sh"] }
portForward:
  - { resourceType: service, resourceName: <project>-<app>, namespace: <project>, port: <port>, localPort: <port> }
```

- **Hot reload is required.** `sync: infer` copies each edited file matching those patterns into the running container, at the path the Dockerfile's `COPY` lines give it, and the dev server (Vite, Next, nodemon…) reloads. A change outside the synced folders (`package.json`, the Dockerfile) rebuilds the image. List the source folders the dev server watches, and nothing that needs a rebuild.
- **Routine:** `"dev": "skaffold dev"`, run in the app folder. One `skaffold dev` per app, each showing only its own logs. Ctrl-C removes that app only.
- **`localPort`** comes from the port registry in the `system` skill: it's a port on the Mac, so it must be unique across projects.

## `scripts/dev-setup.sh`: the pre-deploy hook

Runs before each `skaffold dev` deploy, on the local cluster only (`kubectl --context "$SKAFFOLD_KUBE_CONTEXT"`). Copy `portal/tunnel/scripts/dev-setup.sh`. It:

1. creates the namespace (idempotent: `create --dry-run=client -o yaml | apply`);
2. creates any persistent volume claim the app keeps across runs;
3. **creates the `vault-dev` Secret from a 12-hour dev-session token**: `vault token create -policy=dev-session -ttl=12h`. That policy reads dev paths only, never `…/prod`. Never put the user's own token in the cluster.

An app with no secrets and no volume only needs the namespace, as an inline hook (see `portal/portal/skaffold.yaml`).

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
- **One host carrying several services** (the `/mcp` and `/api` paths of the Domains rule): add `path:` to the ingress rules, most specific first, each pointing at its Service.

## Deploy

One workflow per project calls the reusable `_deploy-k8s.yaml` once per app, in dependency order (`needs:`). The `deploy` skill has the flow and the one-time project setup.
