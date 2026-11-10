---
name: comply
description: >-
  Audit a Ghostmind project folder against the system's current conventions and fix what drifted:
  root layout, varlock schema, legacy env files and run commands, compose bindings and ports,
  Dockerfiles, routines, herdr, deploy workflows, the product's Claude plugin. Use when the user asks
  to check, audit or review a project, bring it up to date or compliant, or asks "is X following the system?".
---

# Comply

Bring one project in line with the system as it is **today**. The `system` skill and its siblings define the target. This skill measures the gap and closes it.

## Steps

1. **Audit.** Run `bash <this skill's folder>/scripts/check.sh <project-dir>`. It is read-only and prints one finding per line (`FAIL` breaks a rule, `WARN` is likely drift), with the file it's in. Read every line.
2. **Decide the scale.**
   - **A `no-schema` or `legacy-env` FAIL on an app means the app is still on the legacy setup.** That is a migration, not a fix. Tell the user which apps are legacy and hand them to the `migrate` skill, one app at a time, after the user agrees. Audit the rest.
   - **Everything else is drift:** fix it here.
3. **Fix the drift** in the project's files, following the skill that owns each rule:

   | Finding | Fix | Owner |
   |---|---|---|
   | `root` | move app code into a service folder; move notes (plan.md…) under `.claude/` or delete them if the user agrees | `system` |
   | `gitignore` | replace with the template | `new-app` → docker.md |
   | `env-local`, `schema` | delete `.env.local`; `dev`/`prod` enum; pin the plugin; `if(forEnv(prod), …)` instead of `remap()`; `ghostmind/project/` | `secrets` |
   | `meta`, `routine`, `herdr` | drop deprecated keys; routines → `varlock run [--include-internal] -- bash scripts/x.sh`; `bash -c` → a script; `"prefix": false` | `system`, `new-app` → docker.md |
   | `scripts` | `scripts/*.ts` (run custom) → `scripts/*.sh` | `new-app` → docker.md |
   | `compose`, `prod-sh`, `port` | no `env_file`, relative paths, `compose.dev.yaml`; bind `127.0.0.1` / `${PRIVATE_IP}` / `${TAILSCALE_IP}`, never all interfaces; Traefik without host ports; `--force-recreate`; `--port $PORT`; a free port from the registry | `new-app` → docker.md, `system` (Ports) |
   | `dockerfile` | glibc varlock on Debian/Ubuntu; `TARGETARCH`; varlock entrypoint | `new-app` → docker.md |
   | `k8s`, `skaffold`, `target`, `traefik` | prod + dev manifests, `skaffold.yaml` with no `kubeContext` (no file names a cluster) and file sync, `.dockerignore`, routines dev/dev_keep/delete, Vault login by service account, a prod entrypoint that `exec`s (no restart loop), no Traefik; Compose only for a non-cluster target | `new-app` → kubernetes.md |
   | `workflow` | the reusable `_deploy-k8s.yaml` + one `deploy.yaml` (Compose hosts: `_deploy.yaml` + per-app callers) | `deploy` |
   | `runtime-net` | between Hetzner servers, running prod calls use the private address (10.0.0.x); Tailscale only for a deliberate cross-provider link | `system` rule 8 |
   | `mcp-state` | an MCP on the cluster is stateless: SDK v2 (`@modelcontextprotocol/server` + `/node`), no `transports`/session map, `replicas: 2` in the dev manifest. Start with `npx @modelcontextprotocol/codemod@latest v1-to-v2 .`, then follow potion's `mcp/app/src/main.ts` | `new-app` → blocks.md |
   | `plugin` | add `plugin/` (`.mcp.json` + skill) | `new-app` → blocks.md |

   **Ask first, as one batch, before anything that changes prod** when merged: prod manifests, workflows, compose bindings, ports and Service names other apps call. A shared service's consumers must keep working (`deploy` → *Moving a legacy project*, step 2). **Never** change Vault, the prod cluster, Tailscale, GitHub secrets or another project from this skill: list those for the user.
4. **Check what the script can't see:**
   - the project's row in the port registry (`system` skill), with every published port;
   - Vault policies list exactly the paths the schemas read (`vault policy read <project>-<app>`, read-only);
   - reference apps: is there a newer, better pattern in the `system` table this project should follow?
   - a remote MCP on the cluster survives its pod: delete the serving pod mid-session and call a tool again without reconnecting (the tunnel pins a connection to one pod, so load alone proves nothing);
   - does each app still start in dev (`run routine dev`: `skaffold dev` on the current kube context, with the Docker context on the same machine) and hot-reload an edit? Re-run it after any Docker, manifest or schema change.
5. **Re-run the audit** until it reports `0 failing check(s)`. Each remaining `WARN` is fixed or explained. *Done when the audit is at zero failures and every remaining warning has a stated reason.*
6. **Report**: failures before → after, what changed (by file), what needs the user (shared infra, prod changes awaiting a yes, legacy apps to migrate). Don't commit or push unless the user asks.

If a check is wrong, or a project shows a better pattern than the skills describe, fix `scripts/check.sh` or the owning skill in the system repo. The checker is only as current as the rules it encodes.
