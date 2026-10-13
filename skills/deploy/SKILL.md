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
2. **Workflows:** copy `_deploy-k8s.yaml` unchanged from portal, and write one `deploy.yaml` for the project that calls it once per app. It deploys in two ways:

   - **A merge deploys only what it changed.** A change in `mcp/` builds and rolls out the mcp, and nothing else: the db is not restarted, the ui is not rebuilt, the tunnel keeps its connections. An app is deployed when its own folder changed, or something else its image is built from (`shared/`, a package of the same repo such as `lib/`), which the app's word names after a `+`.
   - **Everything, from beginning to end**, in order (db → apps → tunnel): on a run started by hand (`workflow_dispatch`, which also takes a list of apps), and whenever the workflow files themselves change. That is the first deploy of a project, a rebuild after a cluster incident, and the check that the whole chain still works.

   A first job, `changes`, decides which apps this run deploys; each app's job reads its answer. `needs:` keeps the order among the jobs that do run, so the tunnel never sends traffic to a missing app:

   ```yaml
   on:
     push:
       branches: [main]
       paths: [db/**, mcp/**, ui/**, tunnel/**, .github/workflows/deploy.yaml, .github/workflows/_deploy-k8s.yaml]
     workflow_dispatch:
       inputs:
         apps: { description: "all, or the apps to deploy, separated by spaces (mcp ui)", default: all }
   jobs:
     changes:
       runs-on: ubuntu-latest
       permissions: { contents: read }
       outputs: { db: "${{ steps.pick.outputs.db }}", mcp: "${{ steps.pick.outputs.mcp }}", ui: "${{ steps.pick.outputs.ui }}", tunnel: "${{ steps.pick.outputs.tunnel }}" }
       steps:
         - uses: actions/checkout@v4
           with: { fetch-depth: 0 }
         - id: pick
           env: { ASKED: "${{ inputs.apps }}", BEFORE: "${{ github.event.before }}" }
           run: bash .github/workflows/changes.sh db mcp ui tunnel >> "$GITHUB_OUTPUT"   # mcp+shared when its image is built from shared/ too
     db:
       needs: changes
       if: needs.changes.outputs.db == 'true'
       uses: ./.github/workflows/_deploy-k8s.yaml
       permissions: { contents: read, packages: write, id-token: write }
       secrets: inherit
       with: { project: <project>, app: db, context: db, dockerfile: db/docker/Dockerfile, manifest: db/k8s/db.yaml }
     mcp:
       needs: [changes, db]
       # a job whose `needs` was skipped is skipped too, unless it says otherwise: run after db when db ran, alone when it did not
       if: ${{ !failure() && !cancelled() && needs.changes.outputs.mcp == 'true' }}
       uses: ./.github/workflows/_deploy-k8s.yaml
       …
   ```

   `.github/workflows/changes.sh` prints one `<app>=true|false` line per app it is given:

   ```bash
   #!/usr/bin/env bash
   # Which apps this run deploys. By hand: the apps asked for, or all. On a merge: the apps whose folder changed.
   # Each word is an app's folder, with whatever else its image is built from after a +:  db mcp+shared ui+shared tunnel
   set -euo pipefail
   all() { for word in "$@"; do echo "${word%%+*}=true"; done; }
   if [ -n "${ASKED:-}" ]; then
     [ "$ASKED" = all ] && { all "$@"; exit; }
     for word in "$@"; do app=${word%%+*}; case " $ASKED " in *" $app "*) echo "$app=true" ;; *) echo "$app=false" ;; esac; done; exit
   fi
   # A first push, or a history that was rewritten: there is nothing to compare with, so everything goes.
   git cat-file -e "${BEFORE:-}^{commit}" 2>/dev/null || { all "$@"; exit; }
   changed=$(git diff --name-only "$BEFORE" HEAD)
   # The workflows changed: prove the whole chain.
   grep -q '^\.github/workflows/' <<<"$changed" && { all "$@"; exit; }
   for word in "$@"; do
     app=${word%%+*}; folders=${word//+/|}
     # an app built from the repo root also depends on the root .dockerignore
     [ "$word" != "$app" ] && folders="$folders|\.dockerignore"
     if grep -Eq "^($folders)(/|$)" <<<"$changed"; then echo "$app=true"; else echo "$app=false"; fi
   done
   ```

   - **An app that needs a new column** still waits for the db: the merge touches both folders, both jobs run, and `needs: [changes, db]` orders them.
   - **Keep the trap in mind when adding a job:** without `!failure() && !cancelled()` in its `if`, a job is skipped whenever a job it `needs` was skipped, so a merge that touches only the ui would deploy nothing.
   - **Proven in billing** (2026-10-13): a merge that changed the workflows deployed all four apps in order, and the next one, which touched only `mcp/`, ran the mcp's job and skipped db, api and tunnel. Block and tags use the same file; a merge that touches two apps has not been watched yet. Copy `deploy.yaml` and `changes.sh` from `/Volumes/Projects/billing/.github/workflows/` (apps built from the repo root: `/Volumes/Projects/tags/.github/workflows/`). Potion still has one workflow file per app, an older layout: do not copy it.

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
- **No run started.** A minute after a merge, `gh run list -R <repo> --limit 3` shows nothing new: the push that created `main`, and now and then a pull request merged from the command line, start no workflow. Start it by hand (`gh workflow run deploy --ref main -f apps=all`, or the app's own workflow where there is one per app) and say so in the report. Do not conclude the deploy happened from the merge alone.
- **A new repo's default branch is the first one pushed.** `gh repo create … --source .` from `dev` makes `dev` the default; set it before the first deploy: `gh repo edit <repo> --default-branch main`.
- **GitHub's API answers 502 while a run is watched** (`gh run watch` stops, `gh run view` fails). The run goes on. Read the result from the cluster instead: the pods' age (`kubectl -n <project> get pods`) and the public URL, then the run once the API answers.

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
