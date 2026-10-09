---
name: deploy
description: >-
  Deploy a Ghostmind app to production: the k3s cluster on Hetzner through GitHub Actions (OIDC login,
  image by digest, rollout), per-project namespace and CI access, Vault login by service account.
  Also covers the non-default single-host Compose deploy, server hardening and debug access. Use when
  shipping an app to prod, writing or fixing a deploy workflow, setting up a project on the cluster,
  handling prod secrets, or checking what runs in prod.
---

# Deploy

**Default target: the k3s cluster on Hetzner.** Three servers (`node-1`, `node-2`, `node-3`), each control plane and worker, on the Hetzner private network. Vault stays on its own server, outside the cluster. The next server is `node-4`. Cluster and node setup live in `/Volumes/Projects/ghostmind/start/host/k3s/` and `host/scripts/server-bootstrap.sh`. Any script that touches prod passes `--context ghostmind`.

**Prod changes only through a merge to main.** GitHub Actions is the only thing that deploys. Never `kubectl apply`, `edit`, `delete` or `exec` against prod to change an app. Read-only checks (`get`, `describe`, `logs`, `rollout status`) are fine.

**Reference, live in prod:** `/Volumes/Projects/portal/.github/workflows/` (`_deploy-k8s.yaml`, `deploy.yaml`) and `/Volumes/Projects/tags/.github/workflows/`.

## How a deploy runs

`_deploy-k8s.yaml` is a reusable workflow, called once per app:

1. **Build.** A GitHub runner builds the image (amd64 + arm64 by default; `platforms: linux/amd64` for heavy builds such as Next.js) with `APP_ENV=prod` and pushes it to GHCR as `ghcr.io/<org>/<project>-<app>:<sha>`.
2. **Log in to the cluster with the run's own GitHub OIDC token** (audience `ghostmind-k3s`), over Tailscale as `tag:ci`. The cluster trusts that token only for `ghostmind-app` repos on `main`, and a RoleBinding limits it to the project's namespace. **No kube credential is stored anywhere.**
3. **Apply** `<app>/k8s/<app>.yaml` with `image: IMAGE` replaced by the built digest, and wait for the rollout (`kubectl rollout status`, 5 minutes). It also refreshes the namespace's GHCR pull secret with the run's token.
4. **Clean up:** keep the last 10 image versions in GHCR.

Work always goes through the `dev` branch. A merge that only touches dev routines or docs puts `[skip ci]` in the merge commit subject. **After every ship, fast-forward `dev` to `main`** so the two stay aligned.

The repo needs only two secrets: `TS_OAUTH_CLIENT_ID` and `TS_OAUTH_SECRET`. No Vault credential, no kube credential.

## Steps for a new project or app

1. **Manifests:** `<app>/k8s/<app>.yaml` per `new-app` → kubernetes.md.
2. **Workflows:** copy `_deploy-k8s.yaml` unchanged from portal, and write one `deploy.yaml` for the project that calls it once per app, ordered with `needs:` (db → apps → tunnel), so the tunnel never sends traffic to a missing app:

   ```yaml
   jobs:
     ui:
       uses: ./.github/workflows/_deploy-k8s.yaml
       permissions: { contents: read, packages: write, id-token: write }
       secrets: inherit
       with: { project: <project>, app: ui, context: <folder>, dockerfile: <folder>/docker/Dockerfile, manifest: <folder>/k8s/ui.yaml }
     tunnel:
       needs: ui
       uses: ./.github/workflows/_deploy-k8s.yaml
       …
   ```
3. **Prod init, once per project and again whenever an app or a prod secret path is added:** `bash k8s/prod-init.sh` at the project root (routine `prod_init`). Copy it unchanged from `/Volumes/Projects/magneto/k8s/prod-init.sh`: it takes everything from the project's own files, so nothing in it is project-specific. Without a flag it prints the plan and changes nothing; `--apply` does every `todo` line and is safe to run again.
   - **Cluster:** the namespace (the `namespace:` of the manifests) and the RoleBinding `ci-deploy`, which lets CI of this repo (the git remote, `main` only) deploy into that namespace and nowhere else (built-in role `edit`). The repo and the project may have different names.
   - **Vault:** for each app whose manifest sets `VAULT_JWT_ROLE`, the policy `<project>-<app>` (read-only on exactly the prod paths its `.env.schema` points to) and the role `auth/k8s/role/<project>-<app>` bound to its service account (`new-app` → kubernetes.md).
   - **Tunnel:** the Cloudflare tunnel and DNS records named in `<app>/config/ingress.prod.yaml`, and its credentials JSON at `ghostmind/project/<project>/tunnel/prod#TUNNEL_CREDENTIALS`. A host outside `ghostmind.dev` passes its zone's certificate: `CF_CERT=ghostmind/global/cloudflare/prod#CLOUDFLARED_<DOMAIN>` (the default is `CLOUDFLARED_GHOSTMIND_DEV` there; prod zone certificates stay under `/prod` so a dev session cannot read them).
   - **Checks:** it warns on a prod Vault path a schema reads that does not exist yet, and on missing `TS_OAUTH_*` secrets or workflows. Fix every `WARN` before merging.

   This changes the prod cluster, Vault and Cloudflare. **Show the user the plan once, then run `--apply`**: one confirmation for the whole setup, never one hand-run command per step.
4. **Validate before merging:**
   - the schema resolves for prod from the Mac: `APP_ENV=prod VAULT_JWT_ROLE= varlock load --agent` in the app folder (your own token; the empty role skips the pod-only login);
   - the prod image builds: `docker build --platform linux/amd64 --build-arg APP_ENV=prod -f docker/Dockerfile .`;
   - the manifest is valid: `kubectl apply --dry-run=client -f k8s/<app>.yaml`;
   - a remote MCP is stateless (`new-app` → blocks.md): no session map in the code, and on dev with 2 replicas a tool call still answers after the serving pod is deleted. Prod runs 2 replicas with nothing pinning a client to a pod, so an in-memory session answers `Session not found` about every other request;
   - the container runs with a read-only root filesystem and as the manifest's user (run the prod image locally with `--read-only --tmpfs /tmp`).
5. **Merge, then verify read-only:** the workflow is green; `kubectl -n <project> get pods` shows the new pods `Running` and ready with 0 restarts; the public URL answers; `kubectl -n <project> logs deploy/<app>` shows no varlock or Vault error. *Done when all four are observed.*

## When a deploy fails

- **Rollout timed out:** `kubectl -n <project> describe pod` and `logs` say why. A varlock error at start means a missing Vault path or a role/policy mismatch: fix the policy or the schema, never by handing the pod a token.
- **OIDC login refused:** the project's namespace or RoleBinding is missing (run `k8s/prod-init.sh`, step 3), or the run isn't on `main`.
- **Image pull error:** the `ghcr` pull secret is refreshed on each deploy with a token that dies with the job. Nodes share images with each other, so this shows up only on an image no node has. Re-run the deploy.
- **Rolling back:** revert the commit and merge. Don't `kubectl rollout undo` on prod.

## Not on the cluster

- **A single host with Compose** (a standalone server; no product uses this today): [compose-host.md](references/compose-host.md), with its workflows in [workflow.md](references/workflow.md) and the host checklist in [server.md](references/server.md).
- **Cloud Run and other managed targets:** build with Compose locally, deploy with the provider's CLI from a script. Reference: `/Volumes/Projects/inference`.
- **Debugging on a server:** [debug-access.md](references/debug-access.md).

## Possible improvement: no per-project setup (not done; today is `k8s/prod-init.sh`)

The goal is "create the project, put its secrets in Vault, merge to main" with nothing run by hand. `prod-init.sh` exists because three things are made per project; each could be made once for every project. None of this is in place, and each item loosens a boundary the system keeps on purpose, so decide with the user before starting.

| Per-project step today | Could become | One-time cost |
|---|---|---|
| Vault policy and role per app | One shared `auth/k8s` role and a templated policy: a pod reads `project/<its namespace>/…` and nothing else (the namespace and account name come from its service-account token) | Changes Vault auth for every project; the shared `global/*` secrets apps need (users, postgres) become readable by every prod pod, or stay as per-app grants |
| Namespace and RoleBinding `ci-deploy` | A cluster admission rule letting a repo's CI create its own namespace and deploy only there | An admission policy to write and test; an error in it is wider than a hand-made binding |
| Tunnel and DNS | The deploy workflow creates them through the Cloudflare API | A Cloudflare API token as an org secret in GitHub; the tunnel token lives in a cluster Secret instead of Vault |

What stays manual either way: the project's real secrets (an OAuth client, a provider key) go into Vault first. Random ones (state secrets, encryption keys, database passwords) can be generated by a script.
