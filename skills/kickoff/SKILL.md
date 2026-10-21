---
name: kickoff
description: >-
  Start a new Ghostmind project from a description, before any code: the folder, git on dev, the
  root meta.json and one per planned app, the herdr tabs (Claude first, on the routine claude), a
  README that holds the brief, then open the herdr workspace, start Claude in its first tab and hand
  it the brief so the build goes on there. Use when the user runs /system:kickoff, or describes an
  app and says "set it up", "create the space", "open a workspace for it", "kick it off", "get it
  ready so we can start a session there", "initiate the project". For building the app itself, it
  hands off to `new-app`.
---

# Kickoff

The user describes an app. This skill builds only what lets the work move to its own space: a folder, its `meta.json` files, its herdr workspace with a Claude session in the first tab, and the brief that session starts from. **No app code, Dockerfile, schema or manifest**: that is `new-app`, run by the new session in the new workspace, where the whole build happens.

Read the `system` skill's *Layout*, *Naming* and *meta.json and `run`* sections first, and `new-app`'s *Where it goes*. Fetch the herdr schema before writing a `herdr` block: `https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json`.

## Steps

1. **Read the description into a plan.** From the user's words: the project's name (short, lowercase, the folder name and the herdr label), one line of what it is, the apps it will have and their folder names (`ui`, `mcp`, `db`, `native`, `mac`, `cli`… as in the `system` blocks table), and the profiles, the ways of working on it (`web`, `mcp`, `mobile`, `backend`). A product gets the six parts of the core unless the user leaves some out; a prototype gets one app (`new-app` → *How far to go*). Ask only for what you cannot take from the description, usually the name. *Done when you can say the name, the apps and the profiles in one line.*

2. **Check the name is free.** `/Volumes/Projects/<name>` must not exist, and `run projects --json | jq -r '.projects[].label'` must not list it: a second workspace with the same label is a stray. Nothing else is created at the root of `/Volumes/Projects`.

3. **Create the folder.** `mkdir /Volumes/Projects/<name> && git init -b dev` in it. Write:
   - `README.md`: the name, the one line, then **`## Brief`** with the user's description **in their own words**, then the planned apps and profiles from step 1. This is what the next session starts from, so nothing the user said is left out or summarised away.
   - `.gitignore` from `new-app` → docker.md.

4. **Write the root `meta.json`.** `id` 12 random characters (`LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12`), `name`, `type: "project"`, `description`, `tags` (with `playground` for a prototype), and:
   - `routines`: `"claude": "claude"`, `herdr_init` (`run herdr init <name> --all`), `herdr_attach`, `herdr_terminate`.
   - `herdr.workspaces[0]`: `label` = the name, a `color` if the user gave one, and **the first tab `claude`** (`"prefix": false`, `single`), one pane `claude` with `"routine": "claude"` and `profiles` listing every profile from step 1. The claude tab is always first, and always on this routine.

   Copy the shape from `/Volumes/Projects/tags/meta.json`.

5. **Write one `meta.json` per planned app.** In `<name>/<app>/meta.json`: `id`, `name`, `type: "app"`, `description`, empty `routines` (`new-app` writes them), and its tab in the same workspace label, `"prefix": false`, with the panes it will have, each naming the routine it will run and its profiles:

   | App | Tab panes |
   |---|---|
   | Web, MCP, worker, API | `vertical`: `dev` (`dev_keep`), `execution-shell` |
   | Database (Hasura) | `main-side`: `dev` (`dev_keep`), `console` (`console`), `execution-shell` |
   | iOS | the pane running `mobile_local_device` first (`new-app` → non-web.md) |
   | Mac, CLI, Raycast | as its reference in non-web.md |

   Copy the shape from `/Volumes/Projects/format/db/meta.json`. The routines do not exist yet, which is why step 7 starts only the claude pane. The app folders hold nothing but `meta.json` until `new-app` runs. *Done when `jq . ` reads every `meta.json` and each profile a pane names is also on the claude pane.*

6. **Commit.** `git add -A && git commit -m "chore: kickoff"` on `dev`. No GitHub repo until the user asks (`new-app` → *Where it goes*).

7. **Open the workspace, start only Claude.** In the project folder: `run herdr init <name> --all --start --only claude/claude --no-focus`. Every tab is built; only the claude pane runs its routine.

8. **Hand the brief to the new session.** Find its pane: `run projects --json --panes | jq -r '.projects[] | select(.name=="<name>") | .panes[] | select(.routine=="claude") | .paneId'`. Wait for Claude to be ready (`herdr pane wait-output <pane> --regex 'for shortcuts|shift\+tab to cycle' --timeout 60000`: the footer changes with the mode, and a shell prompt may also be a `❯`), then send the first message: `herdr pane run <pane> "Read README.md: its Brief is this project. Build it with /system:new-app."` If the wait times out, don't send it blind: give the user that line to paste.

9. **Move the user there.** Get the workspace id (`.workspace.id` of the project in `run projects --json`) and `herdr workspace focus <id>`. Tell the user the work now goes on in that workspace's claude tab, and that this session is done with it. *Done when the new session has the brief and is answering it.*
