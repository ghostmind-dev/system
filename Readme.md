# system

The Ghostmind development system, packaged as one Claude Code plugin at the repo root (`.claude-plugin/`, `skills/`) with one skill per part. The plan and reasoning behind it are in the Potion note "Ghostmind system revamp — verdict & plan · 2026-09-27".

## Pillars

- **Secrets**: varlock `.env.schema` in every app, pointing into Vault (`ghostmind/` KV v2: `global/<provider>`, `project/<project>/<app>`).
- **Run**: Kubernetes in prod and in dev, for most apps. Prod is a k3s cluster on Hetzner; dev is OrbStack's local cluster with Skaffold and hot reload. Compose remains for targets that aren't the cluster (Cloud Run, a one-off container, a script project).
- **Deploy**: GitHub Actions on merge to main. It builds the image, logs in to the cluster with the run's own OIDC token, and applies the app's manifest by digest. Nothing changes prod any other way, and no cluster or Vault credential is stored in CI. Each pod logs in to Vault with its service-account token.

Products are **AI-operable by default**: each ships a remote MCP plus a Claude plugin whose skill teaches the app, so the user can operate it through Claude.

New apps replicate **reference apps** (portal for how an app is packaged and run; format, tags and potion for app code) rather than a rigid template. The `run` CLI and `meta.json` are being retired. Only `run herdr` and `run routine` remain live, and the rest print deprecation warnings.

## Skills

| Skill | For |
|---|---|
| `system` | Overview, rules, naming, building blocks and reference apps. Load first |
| `new-app` | Scaffolding a project or service (web, remote MCP, worker, tunnel, non-web): Kubernetes manifests, Skaffold, the image |
| `secrets` | `.env.schema`, the Vault layout, adding secrets, debugging variables |
| `deploy` | Deploying to the cluster through GitHub Actions; the non-default Compose host flow, server hardening, debug sessions |
| `database` | DB and role on the shared RDS, Hasura, migrations |
| `migrate` | Moving a legacy app (`.env.base`, `run vault`, `run custom`) onto the new setup |
| `comply` | Auditing a project against the current rules (`scripts/check.sh`) and fixing drift |

## Status

- Kubernetes is the default since 2026-10-03. Live in prod on the cluster: `ghostmind/portal` (also on Kubernetes in dev, with hot reload) and `ghostmind/tags` (dev still on Compose).
- Still to move: tags' dev to Skaffold; format, potion, users and noice to the cluster.
- The earlier Compose-on-a-host flow (single-use AppRole logins) is kept as a reference for apps that aren't on the cluster.
