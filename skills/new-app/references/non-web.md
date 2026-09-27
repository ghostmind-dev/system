# Non-web apps

These run on the Mac (or a device), not in Docker. They still follow the secrets rules: `.env.schema`, and every script and routine runs through `varlock run --`. They usually have no `docker/` folder and no deploy workflow.

| Type | Reference | Notes |
|---|---|---|
| iOS / Expo | `/Volumes/Projects/ghostmind/potion/native` | Expo app in `app/`; companion server (if any) follows the web pattern |
| Raycast extension | `/Volumes/Projects/labo/projects` | `@raycast/api`; `npm run dev` inside `app/` |
| Swift macOS app | `/Volumes/Projects/playground/format` | `Package.swift` + `build.sh` in `app/` |
| Python CLI / package | `/Volumes/Projects/labo/theme` | `pyproject.toml` in `app/` |
| Cloud Run / GPU job, script-driven | `/Volumes/Projects/playground/inference` | bash scripts + gcloud; best example of a varlock schema |
| Claude plugin / skills | `/Volumes/Projects/labo/toolkits`, this repo | `.claude-plugin/marketplace.json` at the root, one plugin, many skills |

This playbook grows. When a new kind of app gets built well, add a row pointing at it.
