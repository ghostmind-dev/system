# system

The Ghostmind development system, packaged as one Claude Code plugin at the repo root (`.claude-plugin/`, `skills/`) with one skill per part. The plan and reasoning behind it are in the Potion note "Ghostmind system revamp — verdict & plan · 2026-09-27".

## Three pillars

- **Secrets**: varlock `.env.schema` in every app, pointing into Vault (`ghostmind/` KV v2: `global/<provider>`, `project/<project>/<app>`).
- **Deploy**: one GitHub workflow per app. Tailscale SSH to the product's Hetzner host, single-use Vault login, `docker compose`.
- **Server**: one small, hardened VM per product. No inbound ports, and no usable credential at rest.

Products are **AI-operable by default**: each ships a remote MCP plus a Claude plugin whose skill teaches the app, so the user can operate it through Claude.

New apps replicate **reference apps** (potion's ui, mcp, db, tunnel…) rather than a rigid template. The `run` CLI and `meta.json` are being retired. Only `run herdr` and `run routine` remain live, and the rest print deprecation warnings.

## Skills

| Skill | For |
|---|---|
| `system` | Overview, rules, naming, building blocks and reference apps. Load first |
| `new-app` | Scaffolding a project or service (web, remote MCP, worker, tunnel, traefik, non-web) |
| `secrets` | `.env.schema`, the Vault layout, adding secrets, debugging variables |
| `deploy` | Workflows, AppRole logins, server hardening, debug sessions |
| `database` | DB and role on the shared RDS, Hasura, migrations |
| `migrate` | Moving a legacy app (`.env.base`, `run vault`, `run custom`) onto the new setup |
| `comply` | Auditing a project against the current rules (`scripts/check.sh`) and fixing drift |

## Status

- Done: skills written; `ghostmind/global/*` seeded from the old `kv/GLOBAL` blob; `run` deprecations on `run`'s `dev` branch.
- Proven in dev: `playground/format` (mac, ui, mcp, db, tunnel, traefik) was built end to end with these skills; its retrospective is folded in.
- Proven in prod: `ghostmind/tags`, the first full legacy migration, deploys on single-use AppRole logins (2026-09-30); its retrospective is folded in.
- Next: build and prove the debug-session command (`deploy` → debug-access.md); migrate potion, users, portal and noice.
