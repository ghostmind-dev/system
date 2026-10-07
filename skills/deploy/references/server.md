# Server hardening checklist

For a **standalone Compose host** (`compose-host.md`), such as Vault's own server. Cluster nodes are set up by `/Volumes/Projects/ghostmind/start/host/k3s/` and `host/scripts/server-bootstrap.sh` instead; rules 1, 2, 6 and 13 hold for them too.

A Hetzner host (today one VM per product; several products may share one bigger machine, with prod kept apart from dev), provisioned by `/Volumes/Projects/ghostmind/start` (`scripts/init-phase*.sh`). Keep it as small as the product allows. Each item below is a check you can run.

| # | Rule | Check |
|---|---|---|
| 1 | **No inbound from the internet**, and no public sshd (legacy hosts had it on `0.0.0.0:22`). A Hetzner Cloud Firewall denies all inbound. Public traffic arrives only through the outbound cloudflared tunnel | `hcloud firewall describe <fw>` shows no inbound rules |
| 2 | **SSH only over Tailscale** (Tailscale SSH). sshd is not listening publicly, or not running at all | `ss -tlnp` shows no `0.0.0.0:22` |
| 3 | **Containers bind to 127.0.0.1, the host's private address (10.0.0.x), the Tailscale IP, or no port at all.** On one server, services talk over the compose network. **Between Hetzner servers, running prod traffic uses the private address, never Tailscale.** Tailscale carries deploys, SSH, the Mac's access, and deliberate cross-provider links (`system` rule 8). The Tailscale IP is only for things you reach from the Mac (a prod Hasura) | `ss -tlnp` shows nothing on `0.0.0.0` except Tailscale |
| 4 | **No usable credential at rest.** Secrets live only in running containers' memory. `/run/ghostmind` is empty between deploys. No `.env.*` with values, no `~/.env` holding a Vault token | `sudo ls -R /run/ghostmind` is empty; `sudo find / -name '.env.*' -path '*Projects*' 2>/dev/null` finds only committed pointer files |
| 5 | **Vault access is scoped per app.** Single-use AppRole logins bound to this host's Tailscale IP; a read-only policy listing exact paths | `vault read auth/approle/role/<project>-<app>` |
| 6 | **Automatic security updates** | `unattended-upgrades` enabled |
| 7 | **The deploy user is non-root.** Membership in the `docker` group is root-equivalent, so keep that user dedicated to deploys | `id ghostmind` |
| 8 | **Logs don't carry secrets.** Every secret is `@sensitive` in the schema (varlock redacts), and apps never log `process.env` | grep the app for env dumps |

| 9 | **No standing human credentials.** No `~/.vault-token`, no `gh` login, no PAT in git config. Debug sessions bring their own ([debug-access.md](debug-access.md)) | `ls ~/.vault-token; gh auth status` both come up empty |
| 10 | **No GitHub credential for `git pull`** beyond a read-only deploy key for the one repo (`core.sshCommand` points at it) | `git remote -v` is ssh; `gh auth status` is logged out; `git config --get-all credential.helper` is empty |
| 11 | **The node carries `tag:server` and has Tailscale SSH on.** The SSH policy only allows `tag:ci → tag:server`, and CI deploys over Tailscale SSH. A node that re-logs in (e.g. after an outage) can silently lose its tag; SSH off fails with "No ED25519 host key is known" | on the host: `tailscale status --json \| jq '{tags: .Self.Tags, ssh: .Self.sshHostKeys}'` shows `tag:server` and host keys. Fixes: `deploy` → *Validate before merging* #6 |
| 13 | **Is on the Hetzner private network** (10.0.0.x) with the other product servers | `ip -4 -o addr show \| grep ' 10\.0\.0\.'`; the address is listed in `/Volumes/Projects/home/networking.md` |
| 12 | **No registry logins** | `~/.docker/config.json` has no `auths` |

The legacy `~/.env` on existing servers (sourced by `.zshrc`, with a Vault token that CI `sed`s in on every deploy) goes away when the host's last app moves to the new flow.
