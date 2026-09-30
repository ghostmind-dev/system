---
name: deploy
description: >-
  Deploy a Ghostmind app to production and secure the server: GitHub workflows per app, Tailscale SSH
  to the product's Hetzner host, single-use Vault AppRole logins, server hardening, cutover from the
  legacy deploy, debug sessions. Use when shipping an app to prod, writing or fixing a deploy
  workflow, provisioning or cleaning a server, handling prod secrets, or debugging on a server.
---

# Deploy

**Model:** push to `main` → the app's workflow → CI mints a **single-use** Vault login for that app → hands it to the host over stdin into RAM → `git pull` → `bash scripts/prod.sh` → a health check proves the container restarted and serves → the login files are wiped.

**Where secrets exist:** only in the memory of running containers. They are never on disk, never in `docker inspect`, never in CI logs. At rest the server holds **no usable credential**.

**Reference, proven in prod:** `/Volumes/Projects/ghostmind/tags` (`.github/workflows/_deploy.yaml`, `city.yaml`, `redeploy-all.yaml`; first green run 2026-09-30). Legacy projects (potion, users, portal) still deploy the old way (`run vault kv export` → `/run/secrets` → `env_file`, CI with an admin token) until migrated.

**CI never needs an admin or read token.** When a deploy fails with "permission denied", the fix is the policy (see *Validate before merging*), never a broader token in GitHub secrets.

## Vault setup (once per project, from the Mac)

AppRole is enabled on the Vault. Ask before changing auth methods or anything another project uses.

```bash
P=<project>; HOST_IP=<host tailscale IP>

# 1. per app: a read-only policy listing exactly the paths its .env.schema reads
vault policy write $P-<app> - <<EOF
path "ghostmind/data/project/$P/<app>"       { capabilities = ["read"] }
path "ghostmind/data/project/$P/<app>/prod"  { capabilities = ["read"] }
path "ghostmind/data/project/$P/auth"        { capabilities = ["read"] }
path "ghostmind/data/global/<provider>"      { capabilities = ["read"] }   # one line per global path
EOF
vault write auth/approle/role/$P-<app> token_policies=$P-<app> token_ttl=10m token_max_ttl=30m \
  secret_id_num_uses=1 secret_id_ttl=10m secret_id_bound_cidrs=$HOST_IP/32 token_bound_cidrs=$HOST_IP/32

# 2. per project: CI can only mint single-use logins for this project's apps
#    Vault allows `*` only at the END of a path: list every app explicitly.
vault policy write ci-$P - <<EOF
path "auth/approle/role/$P-<app1>/role-id"   { capabilities = ["read"] }
path "auth/approle/role/$P-<app1>/secret-id" { capabilities = ["update"] }
path "auth/approle/role/$P-<app2>/role-id"   { capabilities = ["read"] }
path "auth/approle/role/$P-<app2>/secret-id" { capabilities = ["update"] }
EOF
vault write auth/approle/role/ci-$P token_policies=ci-$P token_ttl=5m token_bound_cidrs=100.64.0.0/10
```

Store `ci-$P`'s role_id and a secret_id as the repo's GitHub secrets `VAULT_CI_ROLE_ID` / `VAULT_CI_SECRET_ID`, plus `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_SECRET`. Nothing else. Vault sees real tailnet source IPs, so the CIDR bindings hold. A new app means one more pair in `ci-$P`.

## Validate before merging

Every check below has caught a real failure. Run them all before the first deploy of an app.

1. **Every schema resolves for prod**, from the app folder: `APP_ENV=prod VAULT_ROLE_ID= VAULT_SECRET_ID= varlock load --agent` (your own token; the empty values skip the `/run/secrets` reads).
2. **The app policy is complete and single-use works.** Create a throwaway role with the same policy, no CIDR binding, `secret_id_num_uses=1`. Then `env -u VAULT_TOKEN APP_ENV=prod VAULT_ROLE_ID=<rid> VAULT_SECRET_ID=<sid> varlock load --agent` in the app folder, and delete the role.
3. **The CI policy works.** The Mac is inside `100.64.0.0/10`, so mint a spare `ci-$P` secret_id and log in with `env -u VAULT_TOKEN`. For each app, read its role-id and mint a secret-id. Every mint creates a live secret-id: take `-format=json`, keep `.data.secret_id_accessor` from the output, and destroy exactly those (`vault write auth/approle/role/<role>/secret-id-accessor/destroy secret_id_accessor=<acc>`). Never run a bare `vault write -f …/secret-id` just to test.
4. **Prod images build on amd64**: `docker build --platform linux/amd64 --build-arg APP_ENV=prod -f docker/Dockerfile .` per app.
5. **DB migrations** apply against the dev DB the way the prod entrypoint applies them (`database` skill).
6. **The host is reachable by CI.** Its Tailscale node needs **both** `tag:server` (the SSH policy only allows `tag:ci → tag:server`) **and Tailscale SSH enabled**. Without SSH the deploy fails with "No ED25519 host key is known… Host key verification failed". Check both from the Mac:
   `/Applications/Tailscale.app/Contents/MacOS/Tailscale status --json | jq '.Peer[] | select(.HostName=="<host>") | {tags: .Tags, sshkeys: (.sshHostKeys | length)}'`
   It must show `tag:server` and a non-zero key count. A node that re-logs in (e.g. after an outage) can silently lose its tag.
   - SSH off → on the host: `sudo tailscale set --ssh --accept-risk=lose-ssh` (the flag is required when you're connected over SSH; the session survives).
   - Tag missing → the admin console or the API (`POST /api/v2/device/<id>/tags`). `tailscale set` has **no** `--advertise-tags`; `tailscale up --advertise-tags=…` needs the node's full flag set.
   - Both change shared infra: ask first.
7. **Consumers still reach it** (a service other servers call): see *Moving a legacy project*, step 2.

## Steps for a new app

1. **Server** is hardened: [server.md](references/server.md).
2. **Vault setup** above (policy, role, and the app's pair in `ci-$P`).
3. **Container side** per `new-app` → docker.md: varlock is PID 1, the entrypoint loops the app in prod, and `prod.sh` uses `--force-recreate`.
4. **Workflows** from [workflow.md](references/workflow.md): the shared `_deploy.yaml`, a thin caller per app, and `redeploy-all.yaml`.
5. **Validate** (above), merge, and watch it green.

A **host reboot** or a full container recreate needs a fresh login: run `redeploy-all`.

## Moving a legacy project onto this flow

0. **Get one explicit authorization first.** The permission system blocks these steps one by one unless the user has authorized them in their own words. Ask once, naming everything:
   - Vault roles and policies for the project;
   - repo secrets (`VAULT_CI_*`);
   - the server's deploy key;
   - credential cleanup on the server;
   - Tailscale tag/SSH settings on the node;
   - merging to main.

   For anything still blocked, hand the user the exact command to run as `! <command>`. A blocked batch means **nothing** ran: check the real state with read-only calls (`gh secret list`, `gh api repos/<org>/<repo>/keys`, `vault list auth/approle/role/<role>/secret-id`) before reporting it.
1. **Survey the server first**:
   - compose project labels on running containers, so the new compose takes them over rather than duplicating them;
   - `git status` in the checkout (a local edit blocks `--ff-only`);
   - the git remote, **redacted**: `git remote -v | sed -E 's#//[^@]*@#//***@#'`. Legacy hosts embed a GitHub token in the remote URL. If one is there, it must be **rotated** on GitHub: switching the remote to the deploy key doesn't revoke it;
   - `~/.env`, `~/.vault-token`, `gh auth status`, `~/.docker/config.json` auths;
   - `/run/secrets`;
   - `ss -tlnp` (what is on `0.0.0.0`, whether sshd is public);
   - the node's Tailscale tags.
2. **List the consumers of every port the project publishes** (a shared service like `users`). Grep every `.env.schema` and legacy blob under `/Volumes/Projects` for its endpoint, host and port. Legacy `0.0.0.0` bindings hide who calls it and how: potion called users at its **private** address `10.0.0.2:5080`, and binding only the Tailscale IP broke it. The new binding must keep every existing caller working, then check the consumer hosts' logs after cutover (`docker logs --since 1h <c> | grep -i ECONN`). Tell the user the ~1-minute window `--force-recreate` causes for consumers that don't retry.
3. **Give the host a read-only deploy key** for `git pull`: generate it on the server, `gh repo deploy-key add`, `git remote set-url` to ssh, and `git config core.sshCommand` pointing at the key.
4. **Cut over.**
   - **Multi-app project:** run `redeploy-all` for the first deploy, not the push-triggered workflows. Several app workflows racing means Traefik switches to new ports before the apps are up.
   - **Single-app project:** merging to main *is* the cutover (the push triggers the app workflow). The node's tag and SSH, the repo secrets and the deploy key must all be in place **before** the merge.
5. **Clean up after green**, in this order:
   1. revoke each stored Vault token with the token itself (`vault token revoke -self`), then delete the file;
   2. delete `~/.env` and the `.zshrc` line that loads it;
   3. `gh auth logout`, and unset the git credential helpers;
   4. `docker logout`;
   5. `rm -rf /run/secrets/<project>`;
   6. check that `git fetch` still works through the deploy key.

## Debugging on a server

Nothing on the host can reach Vault or GitHub by default. To debug, open a session that carries short-lived credentials and revokes them on exit: [debug-access.md](references/debug-access.md).

## Known limits

- **The Vault plugin has no timeout or retry setting** (10 s, no retry on timeout). A read that times out at container start spends the single-use login, and the container can't recover by restarting. The deploy goes red; re-run it. It has shown up under heavy local load, not yet in prod.
- One deploy at a time **per app**: `concurrency: deploy-<project>-<app>`. A group shared by all apps makes GitHub cancel pending runs when one merge triggers several workflows.
