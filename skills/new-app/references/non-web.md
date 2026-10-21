# Non-web apps

These run on the Mac (or a device), not in Docker. They are still a service folder (`mac/`, `cli/`…) inside the product repo, never code at the repo root. They still follow the secrets rules: `.env.schema`, and every script and routine runs through `varlock run --`. They usually have no `docker/` folder and no deploy workflow.

| Type | Reference | Notes |
|---|---|---|
| iOS app | `/Volumes/Projects/relay/native` (no server of its own, signs in through the product's OAuth); `/Volumes/Projects/tags/native` (with a companion server; signing and creds scripts); older: `potion/native` | *A mobile app*, below. The framework's own steps: the `ios-app` skill (toolkits) |
| Raycast extension | `/Volumes/Projects/labo/projects` | `@raycast/api`; `npm run dev` inside `app/` |
| Mac app around a program we already have | `/Volumes/Projects/relay/mac` (the app contains the product's command-line program and shows what it says) | *A Mac app*, below. The language's own steps: the `mac-app` skill (toolkits) |
| Swift macOS app | `/Volumes/Projects/format/mac` | `Package.swift` in `app/`. `scripts/dev.sh` watches sources, rebuilds, re-signs with the Apple Development cert (so granted permissions persist) and relaunches, keeping the last good build when compilation fails. Signing in to the product: `app/Sources/Format/Account.swift` |
| Python CLI / package | `/Volumes/Projects/theme` | `pyproject.toml` in `app/` |
| Cloud Run / GPU job, script-driven | `/Volumes/Projects/inference` | bash scripts + gcloud; best example of a varlock schema |
| Claude plugin / skills | `/Volumes/Projects/toolkits`, this repo | `.claude-plugin/marketplace.json` at the root, one plugin, many skills |

**A Chrome extension pins its pnpm** (`packageManager` in its `package.json`). Corepack runs its own newer pnpm and stops with `ERR_PNPM_BAD_PM_VERSION`: install with the pinned one, `npx pnpm@<that version> install --frozen-lockfile`.

**A publish or release script asks which version first** (rule 11 of the `system` skill): patch, minor, major, keep, or a version typed in full, before it builds. Copy the question from the reference of the same kind: `tags/native/scripts/publish.sh` (iOS), `tags/chrome/scripts/extension-build.sh` (Chrome extension), `format/mac/scripts/release.sh` (Mac).

## A mobile app

What follows is ours and holds whatever the app is written with. What belongs to a framework (its build
commands, its patches, its traps) is not in this plugin: for the one we use today, it is the `ios-app` skill of
the `toolkits` plugin.

**From nothing to TestFlight, who does what.** Say this to the person at the start, so they know what will be
asked of them:

| Step | Done by |
|---|---|
| The `native/` folder, its schema, routines and scripts; the app itself | the agent |
| One exact app address added to the product's OAuth proxy; merge to main so prod has it | the agent (the merge on the person's say) |
| The two identifiers on Apple Developer, and their capabilities (push) | the agent, through the App Store Connect API with the key in Vault |
| The App Store Connect record (Apple has no API for it) | the agent in the person's browser, signed in to Apple; **the person chooses the store name** |
| A push key, when the app takes notifications (once for the whole team, not per app) | the agent creates it in the browser; **the person clicks Download** (an agent may not fetch a key file); the agent puts it in Vault and deletes the file |
| Build, check, sign, upload | the agent: `run routine mobile_publish` |
| The internal tester group and its people | the agent, through the API |
| Accepting the first TestFlight invitation, on the phone | **the person** (the email "You're invited to test …") |
| Trying it on a real phone: permissions, sign-in, what a simulator cannot show | **the person** |

Nothing else is needed from the person: no Apple password typed anywhere, no certificate to make, no new Google
credential. If a step seems to need one of those, something above was skipped.

- **It is a service folder, `native/`,** with the app in `native/app`, a `.env.schema`, a `meta.json` and
  `scripts/`. It is built and run on the Mac, never in the cluster.
- **No server of its own, unless the product's API cannot take a bearer token.** The phone calls the API the web
  page calls. A second server is a second place for every rule to be wrong. References: `relay/native` (none),
  `tags/native` and `potion/native` (a companion server, which then follows the web pattern).
- **No new Google credential when the product has the OAuth proxy** (the core's Google sign-in). The app opens
  `<product>/oauth/authorize` with PKCE in the system's sign-in sheet; Google only ever sees the product's own
  `/oauth/callback`; the proxy sends the person back to one app address, allowed by exact match
  (`<scheme>://oauth`), never a prefix. The tokens are the product's own client's, so the API sees the person
  themself and does not change. They are kept in the device's keychain. Reference: `relay/mcp/app/src/oauth.js`
  and `relay/native/app/utils/auth.ts`.
- **Apple's credentials are shared and already in Vault**, at `ghostmind/global/apple`: the team id and the App
  Store Connect key (`.p8`, key id, issuer id). A new app points at them and adds nothing. An app without a
  server has no secret of its own: do not invent one.
- **Dev and prod are two apps side by side on the phone**: `com.ghostmind.<project>.dev` named `<Name>-Dev`, and
  `com.ghostmind.<project>` named `<Name>`, each with its own API address, chosen by `APP_ENV` in the one schema.
  **The dev app looks different on the home screen:** its own icon, the prod mark on amber
  (`app/assets/images/icon-dev.png`, set as `ios.icon` when `ENV` is not prod; it replaces a light/dark pair), and
  its name under the icon ends in ` dev` (`infoPlist.CFBundleDisplayName`: `'<Name> dev'`, `'<Name>'` in prod).
  `EXPO_NAME` stays `<Name>-Dev`: it names the Xcode project the scripts build. Without this the two icons are the
  same and only the hyphen in a truncated name tells them apart. Reference: `relay/native/app/app.config.ts`.
- **Register every identifier on Apple Developer** with the App Store Connect key (`POST /v1/bundleIds`), asking
  the user first: it is their account. That is the app's two (dev and prod) and, for each, one per extension
  inside it (a widget is `<app id>.widget`): list them all in `apple.mjs`, and register an extension's before
  the build that first contains it. Do it **before the first run on a phone**: an identifier Apple does not
  know fails the device build with "No profiles for '<id>' were found … Automatic signing is disabled". Then make
  the dev app's signing profile once, with the same key and no Xcode sign-in (routine `mobile_signing`:
  `xcodebuild … -allowProvisioningUpdates -authenticationKeyPath …`). Reference for both:
  `noice/native/scripts/apple.mjs` (`identifiers`, and `app` to look for the record) and `noice/native/scripts/ios.sh signing`.
  **The App Store Connect app record cannot be made through the API**: the user makes it once by hand before the
  first publish, and chooses its store name. Say so; do not pretend it is done.
- **Routines, the same names in every project:** `module_local_prebuild`, `mobile_local` (simulator),
  `mobile_local_device` (the plugged-in phone), `mobile_signing`, `mobile_publish`, `mobile_submit`, `mobile_archive`
  and `test`. Every one runs through `varlock run --`. The herdr pane that runs the device build is in the `mobile` profile
  and is the **main pane of the tab**: the first one listed (in `main-side`, the large one on the left), with the
  companion server, when there is one, and the `execution-shell` beside it. Its log is the one watched.
- **A switch that changes what varlock reads goes in the routine, not in a second varlock.** The signing key is
  read only when asked for: `"mobile_signing": "ASC_KEY=1 varlock run -- bash scripts/ios.sh signing"`, with
  `if($ASC_KEY, vaultSecret(…))` in the schema. A script that starts `varlock run` again from inside one failed with
  `Referenced item "VAULT_TOKEN" is not valid` (noice, 2026-10-13).
- **Each app has its own Metro port, in the port registry** (`system` → Ports). Two apps in dev on 8081 load each
  other's code: noice's app showed relay's screens, from relay's Metro on the same Mac. React Native's core is
  prebuilt with 8081 compiled in, so `--port` and `RCT_METRO_PORT` no longer reach the app: a config plugin sets
  the Debug app's address (`RCTBundleURLProvider.sharedSettings().jsLocation`, the Mac's address from `ip.txt`
  and the project's port), and `scripts/ios.sh` starts Metro there (`npx expo run:ios --port <port>`, for the
  simulator and the device). Both are needed: with `--port` alone, Metro moved but tags' app still asked 8081 and
  would have loaded Potion's code; without it, `expo run:ios` stops after a successful build with
  `Port "8081" became busy running another process` (tags, 2026-10-16). Reference: `noice/native/app/plugins/with-metro-port.js`.
  Potion's app still uses 8081 and is the only one allowed to. In `ios.sh` call the variable `METRO_PORT`: the
  app's `.env.schema` may already have a `PORT` (the companion server's), and varlock runs the script.
- **The values varlock resolves must reach every step of the native build, and nothing falls back in silence.**
  A native build reads the app's config more than once, and a step started by the IDE's build system does not
  inherit the shell's environment. Have the script write the resolved, non-secret values where that step reads
  them, and make the config stop with the routine to run when a value is missing. A default of prod's address
  put a prod app on a phone that had asked for dev (relay, 2026-10-12).
- **Code shared with the web page is copied, and the copy is checked.** A mobile bundler reads only its own
  folder. Keep the source in the web app as a pure module, copy it with a script, and make `test` fail when the
  two differ. Change the source, never the copy. Reference: `relay/native/scripts/mirrors.sh`.
- **Prove it before the user does, against a pretend backend**: the product's server with a pretend store, plus
  stand-ins for `/oauth/authorize` and `/oauth/token`, on the simulator. Never the user's account or their real
  devices. Then the real phone: the `ios-device` skill (toolkits) gives screenshots and logs over USB.
- **It is built and published from our own machine, by our own script.** Whatever the app is written with, the
  framework's tools may build it, but no outside service builds, signs or uploads it, and none holds a
  certificate. `scripts/publish.sh` asks the version (rule 11), builds, checks that the result is the prod app
  (its identifier, its address, one build number throughout), then signs and uploads with the App Store Connect
  key from Vault, written to a temporary folder for the length of the run. A mode that does everything but
  upload (`mobile_archive`) proves a change before Apple sees it. The script is the same in every project below
  its first lines. References: `relay/native/scripts/publish.sh` (also in `potion` and `tags`).
- **Publish from a copy of `main`, one build at a time.** The publish writes `ios/` again for the prod app and
  takes ten minutes of the machine, so run it in a worktree of `origin/main` (`git worktree add`, then
  `run routine mobile_publish` in its `native/`), not in the folder the dev build lives in. The first publish
  comes before `native/` is on `main`: then copy the folder into the session's scratchpad
  (`rsync -a --exclude node_modules --exclude ios --exclude build`, then `npm install` in its `app/`) and publish
  there; the dev build's `ios/` is left alone (format, 2026-10-16). The version
  question is answered on standard input when no person is there: `printf 'p\n' | run routine mobile_publish`.
  Say you are starting it: two sessions each told to publish the same app stopped each other's build
  (relay, 2026-10-13). After "Uploaded", the new version in `app.json` goes to `main` as a change of its own,
  that one file; left uncommitted it is carried into somebody's next commit.
- **"Upload succeeded" is not "Apple took it".** Apple checks the build after the upload and refuses it in
  silence: `apple.mjs builds` keeps saying "no build yet" and TestFlight sends no invitation. The reason only
  comes by email to the account holder, "Action needed: The uploaded build for <app> has one or more issues"
  (format's first build: ITMS-90683, a purpose string a library needs although the app never uses it). When no
  build shows 15 minutes after the upload, read that email (the person's Gmail, read-only), fix, publish again.
- **A build nobody ran is not a tested build.** Uploading is not proof: say in the report that TestFlight is
  the first run, and what to press there.
- **Before the App Store:** an app that signs in with Google only must also offer Sign in with Apple. With the
  OAuth proxy that is a change to the proxy, shared by every product that uses it. Tell the user early.

## A Mac app

What follows is ours and holds whatever the app is written with. The language's own steps and traps are the
`mac-app` skill of the `toolkits` plugin.

**Who does what.** Say this at the start:

| Step | Done by |
|---|---|
| The `mac/` folder, its routines and scripts; the app itself | the agent |
| A trial build that runs on this Mac | the agent: `run routine build` |
| The **Developer ID Application** certificate, once for the whole team | **the person**, as the account holder (Xcode, Settings, Accounts, Manage Certificates). Without it the app only opens on the Mac that built it |
| Build, sign, have Apple notarise it, upload | the agent: `run routine release`, with the App Store Connect key from Vault |
| The download on the product's website | the agent (the merge on the person's say) |
| Opening it for the first time, granting what macOS asks | **the person** |

- **It is a service folder, `mac/`,** with the app in `mac/app`, a `meta.json`, `scripts/` and, when a routine
  needs a secret, a `.env.schema`. Built on the Mac, never in the cluster.
- **When the product already has a program that does the work, the app contains that program and adds no
  logic.** It starts it, keeps it running, and shows what it says. Give the program two things for it: a way to
  say its state as data (`status --json`) and a way to ask the product's API as the signed-in person
  (`get <path>`). The app then holds no token and no second copy of any rule. Reference: `relay/mac`,
  `relay/cli/app/src/cli.js`.
- **One of it per machine, and the program enforces that, not the app.** A person may have installed the
  command-line version first. The program says it is running in a file beside its config (its process id, and
  what started it) and refuses to start a second time with a sentence naming what to stop. The app, finding one
  running, shows that one and does not start its own. Decide this before the first build: two copies under one
  identity knock each other off, and anything the program does on an event is done twice.
- **Two builds.** A *trial* build for this Mac (this Mac's runtime, the program as it is in the repository, the
  dev address) and a *package* build to give away (the runtime and the program inside the app, the prod address).
  Dev and prod have two identifiers (`com.ghostmind.<project>.mac.dev`, `com.ghostmind.<project>.mac`).
- **A runtime put inside the app is fetched from its maker and checked** against the checksum the maker lists,
  at a version written in the script. It is signed with the app. Never copy the one a package manager installed
  on this Mac: it leans on files that are not in the app.
- **Apple's credentials are the shared ones in Vault** (`ghostmind/global/apple`): the same App Store Connect
  key notarises a Mac app and uploads an iOS one. The certificate itself lives in the person's keychain; the
  script looks for it and says, in one sentence, what is missing and who makes it.
- **Downloads are in one public bucket for every product**: Cloudflare R2 `ghostmind-downloads`, served at
  `https://downloads.ghostmind.dev/<project>/`. A release puts three things there: `<Name>-<version>.dmg`
  (cached for a year, never overwritten), `<Name>.dmg` (always the latest, not cached, saved by browsers under
  the versioned name) and `latest.json` (version, build, date, file name), uploaded last. Needs `wrangler login`
  once on the Mac. Reference: `format/mac/scripts/release.sh`, `relay/mac/scripts/release.sh`.
- **The website reads `latest.json` through the product's own server, or the bucket must know the website.**
  The bucket answers only the origins in its CORS rule. Either add the product's addresses to that rule, or
  have the product's API read the file and say what there is to download (`relay/api/app/src/downloads.js`):
  the second needs no change to shared settings and offers nothing when nothing is published.
- **The release asks which version first** (rule 11), from what is published, and refuses a version that is
  already there. A dry run builds and signs and uploads nothing.
- **An agent cannot see a Mac window.** Screenshots need a permission an agent's shell does not have. Give the
  app a way to print what its window would list (`<App> --describe`) and check that; say plainly that the
  layout itself was not looked at, and have the person look.
- **Routines, the same names in every project:** `build` (trial), `open`, `describe`, `package`, `release`, `test`.

## Credential files that tools insist on (`.p8`, service-account JSON)

Keep them in Vault and materialize them only when needed, with a `scripts/creds.sh pull|push|status`. Write with `vault kv get -format=json … | jq -j '.data.data.KEY' > file`, straight to the file. Going through `$(...)` drops the trailing newline, and the file stops round-tripping byte-identical. Reference: `/Volumes/Projects/tags/native/scripts/creds.sh`.

This playbook grows. When a new kind of app gets built well, add a row pointing at it.
