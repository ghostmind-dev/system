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

**Reference, live in prod:** `/Volumes/Projects/ghostmind/portal/.github/workflows/` (`_deploy-k8s.yaml`, `deploy.yaml`) and `/Volumes/Projects/ghostmind/tags/.github/workflows/`.

## How a deploy runs

`_deploy-k8s.yaml` is a reusable workflow, called once per app:

1. **Build.** A GitHub runner builds the image (amd64 + arm64 by default; `platforms: linux/amd64` for heavy builds such as Next.js) with `APP_ENV=prod` and pushes it to GHCR as `ghcr.io/<org>/<project>-<app>:<sha>`.
2. **Log in to the cluster with the run's own GitHub OIDC token** (audience `ghostmind-k3s`), over Tailscale as `tag:ci`. The cluster trusts that token only for `ghostmind-app` repos on `main`, and a RoleBinding limits it to the project's namespace. **No kube credential is stored anywhere.**
3. **Apply** `<app>/k8s/<app>.yaml` with `image: IMAGE` replaced by the built digest, and wait for the rollout (`kubectl rollout status`, 5 minutes). It also refreshes the namespace's GHCR pull secret with the run's token.
4. **Clean up:** keep the last 10 image versions in GHCR.

Work always goes through the `dev` branch. A merge that only touches dev routines or docs puts `[skip ci]` in the merge commit subject. **After every ship, fast-forward `dev` to `main`** so the two stay aligned.

The repo needs only two secrets: `TS_OAUTH_CLIENT_ID` and `TS_OAUTH_SECRET`. No Vault credential, no kube credential.

## Steps for a new project or app

1. **Project access, once per project** (from the Mac): `bash /Volumes/Projects/ghostmind/start/host/k3s/setup.sh project <name>`. It creates the namespace and lets CI of `ghostmind-app/<name>` (main only) deploy into it and nowhere else (built-in role `edit`, that namespace only). It also needs the `TS_OAUTH_CLIENT_ID`/`TS_OAUTH_SECRET` repo secrets and the Vault `auth/k8s` roles (step 2). This changes the prod cluster: ask the user first.
2. **Vault role per app that reads secrets:** policy `<project>-<app>` listing exactly the paths its `.env.schema` reads, and role `auth/k8s/role/<project>-<app>` bound to the app's service account (`new-app` → kubernetes.md). This changes Vault: ask first.
3. **Manifests:** `<app>/k8s/<app>.yaml` per `new-app` → kubernetes.md.
4. **Workflows:** copy `_deploy-k8s.yaml` unchanged from portal, and write one `deploy.yaml` for the project that calls it once per app, ordered with `needs:` (db → apps → tunnel), so the tunnel never sends traffic to a missing app:

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
5. **Validate before merging:**
   - the schema resolves for prod from the Mac: `APP_ENV=prod VAULT_JWT_ROLE= varlock load --agent` in the app folder (your own token; the empty role skips the pod-only login);
   - the prod image builds: `docker build --platform linux/amd64 --build-arg APP_ENV=prod -f docker/Dockerfile .`;
   - the manifest is valid: `kubectl apply --dry-run=client -f k8s/<app>.yaml`;
   - a remote MCP is stateless (`new-app` → blocks.md): no session map in the code, and on dev with 2 replicas a tool call still answers after the serving pod is deleted. Prod runs 2 replicas with nothing pinning a client to a pod, so an in-memory session answers `Session not found` about every other request;
   - the container runs with a read-only root filesystem and as the manifest's user (run the prod image locally with `--read-only --tmpfs /tmp`).
6. **Merge, then verify read-only:** the workflow is green; `kubectl -n <project> get pods` shows the new pods `Running` and ready with 0 restarts; the public URL answers; `kubectl -n <project> logs deploy/<app>` shows no varlock or Vault error. *Done when all four are observed.*

## When a deploy fails

- **Rollout timed out:** `kubectl -n <project> describe pod` and `logs` say why. A varlock error at start means a missing Vault path or a role/policy mismatch: fix the policy or the schema, never by handing the pod a token.
- **OIDC login refused:** the project's namespace or RoleBinding is missing (step 1), or the run isn't on `main`.
- **Image pull error:** the `ghcr` pull secret is refreshed on each deploy with a token that dies with the job. Nodes share images with each other, so this shows up only on an image no node has. Re-run the deploy.
- **Rolling back:** revert the commit and merge. Don't `kubectl rollout undo` on prod.

## Not on the cluster

- **A single host with Compose** (a standalone server, a project not yet moved): [compose-host.md](references/compose-host.md), with its workflows in [workflow.md](references/workflow.md) and the host checklist in [server.md](references/server.md).
- **Cloud Run and other managed targets:** build with Compose locally, deploy with the provider's CLI from a script. Reference: `/Volumes/Projects/playground/inference`.
- **Debugging on a server:** [debug-access.md](references/debug-access.md).
