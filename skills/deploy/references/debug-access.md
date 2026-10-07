# Debug access: credentials that live only as long as your session

For a **standalone Compose host**. On the cluster there is no server to log in to: debugging prod is read-only `kubectl --context ghostmind -n <project>` (`get`, `describe`, `logs`, `port-forward`), and a fix goes through a merge to main (`deploy` skill).

Goal: when nobody is debugging, the server holds **no Vault token and no GitHub token**. When you SSH in to debug, you bring short-lived credentials with you. They exist only in that shell's memory and are revoked the moment you exit.

> Status: design, to be built and verified with the first prod deploy. Implement it as `scripts/debug.sh` in this skill and replace this note.

## Flow (from the Mac)

```bash
# debug.sh <project>
set -euo pipefail
P=$1
VT=$(vault token create -policy=$P-debug -ttl=1h -explicit-max-ttl=2h -field=token)
GT=$(gh auth token)                       # or a fine-grained PAT scoped to the product's repos
trap 'vault token revoke "$VT" >/dev/null 2>&1 || true' EXIT
# hand the creds to the session over stdin: never in argv (visible in `ps`), never on disk
tailscale ssh -t ghostmind@$P "bash --rcfile <(printf 'export VAULT_TOKEN=%q GH_TOKEN=%q\n' ...)"
```

The exact way to hand the variables over is to be settled in the pilot. Candidates, best first:
1. Tailscale SSH `acceptEnv` in the tailnet policy, plus `SendEnv VAULT_TOKEN GH_TOKEN`. The variables travel in the SSH protocol and are never written anywhere.
2. Stream them over stdin into a `umask 077` file on `/dev/shm` (RAM), sourced and deleted by the login shell.

Whichever wins, check it: after `exit`, `vault token lookup <token>` fails, and nothing is left on the host (`/dev/shm`, shell history, `~/.vault-token`).

## The `<project>-debug` policy

Read-only on `ghostmind/data/project/<project>/*` plus the global paths that project's apps use, so `varlock load` works in any app folder on the host. It is scoped to one project, and never admin.

## Inside the session

- `cd ~/Projects/<project>/<app> && varlock load --agent` shows what the app sees (redacted). Drop `--agent` to see the real values.
- `gh` / `git` use `GH_TOKEN`.
- `exit` revokes the Vault token (the trap). If the connection drops, the TTL caps the damage at 1h.
