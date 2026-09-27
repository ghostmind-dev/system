# Server hardening checklist

A Hetzner host (today one VM per product; several products may share one bigger machine, with prod kept apart from dev), provisioned by `/Volumes/Projects/ghostmind/start` (`scripts/init-phase*.sh`). Keep it as small as the product allows. Each item below is a check you can run.

| # | Rule | Check |
|---|---|---|
| 1 | **No inbound from the internet.** A Hetzner Cloud Firewall denies all inbound. Public traffic arrives only through the outbound cloudflared tunnel | `hcloud firewall describe <fw>` shows no inbound rules |
| 2 | **SSH only over Tailscale** (Tailscale SSH). sshd is not listening publicly, or not running at all | `ss -tlnp` shows no `0.0.0.0:22` |
| 3 | **Containers bind to 127.0.0.1 or no port at all.** Services talk over the compose network | `ss -tlnp` shows nothing on `0.0.0.0` except Tailscale |
| 4 | **No usable credential at rest.** Secrets live only in running containers' memory. `/run/ghostmind` is empty between deploys. No `.env.*` with values, no `~/.env` holding a Vault token | `sudo ls -R /run/ghostmind` is empty; `sudo find / -name '.env.*' -path '*Projects*' 2>/dev/null` finds only committed pointer files |
| 5 | **Vault access is scoped per app.** Single-use AppRole logins bound to this host's Tailscale IP; a read-only policy listing exact paths | `vault read auth/approle/role/<project>-<app>` |
| 6 | **Automatic security updates** | `unattended-upgrades` enabled |
| 7 | **The deploy user is non-root.** Membership in the `docker` group is root-equivalent, so keep that user dedicated to deploys | `id ghostmind` |
| 8 | **Logs don't carry secrets.** Every secret is `@sensitive` in the schema (varlock redacts), and apps never log `process.env` | grep the app for env dumps |

| 9 | **No standing human credentials.** No `~/.vault-token`, no `gh` login, no PAT in git config. Debug sessions bring their own ([debug-access.md](debug-access.md)) | `ls ~/.vault-token; gh auth status` both come up empty |
| 10 | **No GitHub credential for `git pull`**, or at most a read-only deploy key for the one repo | `git remote -v`, `~/.ssh` |

The legacy `~/.env` on existing servers (sourced by `.zshrc`, with a Vault token that CI `sed`s in on every deploy) goes away when the host's last app moves to the new flow.
