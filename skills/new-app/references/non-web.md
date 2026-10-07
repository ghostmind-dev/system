# Non-web apps

These run on the Mac (or a device), not in Docker. They are still a service folder (`mac/`, `cli/`…) inside the product repo, never code at the repo root. They still follow the secrets rules: `.env.schema`, and every script and routine runs through `varlock run --`. They usually have no `docker/` folder and no deploy workflow.

| Type | Reference | Notes |
|---|---|---|
| iOS / Expo | `/Volumes/Projects/ghostmind/tags/native` (varlock, signing and creds scripts); older: `potion/native` | Expo app in `app/`; the companion server follows the web pattern |
| Raycast extension | `/Volumes/Projects/labo/projects` | `@raycast/api`; `npm run dev` inside `app/` |
| Swift macOS app | `/Volumes/Projects/ghostmind/format/mac` | `Package.swift` in `app/`. `scripts/dev.sh` watches sources, rebuilds, re-signs with the Apple Development cert (so granted permissions persist) and relaunches, keeping the last good build when compilation fails. Signing in to the product: `app/Sources/Format/Account.swift` |
| Python CLI / package | `/Volumes/Projects/labo/theme` | `pyproject.toml` in `app/` |
| Cloud Run / GPU job, script-driven | `/Volumes/Projects/playground/inference` | bash scripts + gcloud; best example of a varlock schema |
| Claude plugin / skills | `/Volumes/Projects/labo/toolkits`, this repo | `.claude-plugin/marketplace.json` at the root, one plugin, many skills |

## iOS / Expo notes (from tags, Expo SDK 54 on Xcode 27)

- Xcode 27 renamed `Simulator.app` → `DeviceHub.app`, which breaks every `expo run:ios`. Fix it with patch-package on `@expo/cli`; the patch differs per CLI version (potion has one for 54.0.27, tags for 54.0.23, `native/scripts/fix-expo-simulator-check.sh`).
- Pods need a deployment-target config plugin (≥ 15.1). `appleTeamId` comes from Vault (`ghostmind/global/apple`) and sets `DEVELOPMENT_TEAM` on prebuild.
- **Signing without an Xcode login:** `xcodebuild -allowProvisioningUpdates -authenticationKeyPath … -authenticationKeyID … -authenticationKeyIssuerID …` with the App Store Connect key (`global/apple`) creates the profile. See `tags/native/scripts/ios.sh signing`.
- Fresh-Mac sequence in tags: `creds_pull` → `mobile_prebuild` → `mobile_signing` → `mobile_local_device`.

## Credential files that tools insist on (`.p8`, service-account JSON)

Keep them in Vault and materialize them only when needed, with a `scripts/creds.sh pull|push|status`. Write with `vault kv get -format=json … | jq -j '.data.data.KEY' > file`, straight to the file. Going through `$(...)` drops the trailing newline, and the file stops round-tripping byte-identical. Reference: `/Volumes/Projects/ghostmind/tags/native/scripts/creds.sh`.

This playbook grows. When a new kind of app gets built well, add a row pointing at it.
