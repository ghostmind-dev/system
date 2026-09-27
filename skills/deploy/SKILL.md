---
name: deploy
description: >-
  Deploy a Ghostmind app to production and secure the server: GitHub workflow per app, Tailscale SSH
  to the product's Hetzner host, single-use Vault AppRole logins, server hardening, debug sessions.
  Use when shipping an app to prod, writing or fixing a deploy workflow, provisioning a server,
  handling prod secrets, or debugging on a server.
---

# Deploy

**Model:** push to `main` → the app's GitHub workflow → it mints a **single-use** Vault login for that app → Tailscale SSH into the product's Hetzner host → `git pull` → `bash scripts/prod.sh` → verify that the container restarted → delete the used login.

**Where secrets exist:** only in the memory of the running container. They are never on disk, never in `docker inspect`, and never in CI logs. At rest the server holds **no usable credential**: the login is single-use, short-lived, and bound to the host's IP.

> Status: target flow, first built in the portal pilot. Existing projects (potion, tags, users, portal) still deploy the old way: `run vault kv export` writes `.env.*` into `/run/secrets`, compose uses `env_file`, and CI mints a 1h token with `-policy=admin`. That leaks every secret through `docker inspect` and gives CI full Vault admin.

## Vault setup (once per project, from the Mac)

AppRole must be enabled once per Vault (`vault auth enable approle`). Ask before enabling it.

```bash
P=<project>; HOST_IP=<host tailscale IP>

# 1. per app: a read-only policy listing exactly the paths in its .env.schema
vault policy write $P-<app> - <<EOF
path "ghostmind/data/project/$P/<app>"      { capabilities = ["read"] }
path "ghostmind/data/project/$P/<app>/prod" { capabilities = ["read"] }
path "ghostmind/data/project/$P/auth"       { capabilities = ["read"] }
path "ghostmind/data/global/<provider>"     { capabilities = ["read"] }
EOF
vault write auth/approle/role/$P-<app> token_policies=$P-<app> token_ttl=10m token_max_ttl=30m \
  secret_id_num_uses=1 secret_id_ttl=10m secret_id_bound_cidrs=$HOST_IP/32 token_bound_cidrs=$HOST_IP/32

# 2. per project: CI can only mint single-use logins for this project's apps
vault policy write ci-$P - <<EOF
path "auth/approle/role/$P-*/role-id"   { capabilities = ["read"] }
path "auth/approle/role/$P-*/secret-id" { capabilities = ["update"] }
EOF
vault write auth/approle/role/ci-$P token_policies=ci-$P token_ttl=5m token_bound_cidrs=100.64.0.0/10
```

Store `ci-$P`'s role_id and a secret_id as the repo's GitHub secrets `VAULT_CI_ROLE_ID` / `VAULT_CI_SECRET_ID`. If they leak, they can only mint logins that work from the product host itself, for one use each.

## Steps for a new app

1. **Server exists and is hardened**: [server.md](references/server.md). *Done when every check passes on the host.*
2. **Vault setup** above, for this app (and the project, if it is the first app).
3. **Container side** follows `new-app` → docker.md. varlock is PID 1 and supervises the app, so a crashed app restarts inside the container without a second Vault login.
4. **Workflow** from [workflow.md](references/workflow.md).
5. **Ship and verify.** The workflow is green. The container `StartedAt` is after the deploy began. The public URL answers. `docker inspect <container> --format '{{.Config.Env}}'` shows no secret. `/run/ghostmind` is empty after the deploy. *Done when all five are observed.*

**Moving an app to another host:** change `HOST` in its workflow, then update the role's `secret_id_bound_cidrs` / `token_bound_cidrs` to the new host's Tailscale IP.

A **host reboot** or a full container recreate needs a fresh login, so it needs a redeploy. Keep a `redeploy-all` workflow (`workflow_dispatch`, one job per app) for that.

## Debugging on a server

Nothing on the host can reach Vault or GitHub by default. To debug, open a session that carries short-lived credentials and revokes them when you exit: [debug-access.md](references/debug-access.md).

## Rules

- CI never holds a Vault token that can read secrets. Its only Vault power is `ci-<project>`.
- A deploy must **fail** when the image build fails: `set -euo pipefail` plus the restart check. (The old `run` hid build failures for days.)
- One deploy at a time per host: a workflow `concurrency` group plus `flock` around `git pull`.
- An app that depends on DB migrations waits for the `db` workflow on the same commit (copy the guard from `/Volumes/Projects/ghostmind/potion/.github/workflows/mcp.yaml`).
