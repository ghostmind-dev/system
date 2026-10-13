---
name: debrief
description: After a piece of work on a Ghostmind project, find what it taught and write the lessons that would recur into the system's skills and its audit script.
disable-model-invocation: true
---

# Debrief

A piece of work just ended: an app was built, something was deployed, a project was migrated or fixed. Find the **lessons** in it and put each one where the next project will meet it. A lesson is a moment where the system could have saved time or a mistake and did not: a rule that was missing, stale or wrong, a reference that was behind, a step in the wrong order, a check that would have caught it.

The system's source is `/Volumes/Projects/system` (`skills/`, `skills/comply/scripts/check.sh`). Work there, never on the installed copy of the plugin, which may be days old.

## Steps

1. **Collect every detour.** Go back through the session, the project's `git status` and diff, and anything that was built and then undone. List each place where work was redone, a guess was wrong, a command failed for a reason the skills could have told, the user had to correct or repeat something, or a reference and a rule disagreed. Include what went well by a route the skills do not describe. *Done when every retry, reversal and correction of the session is on the list, with what it cost.*

2. **Keep what would recur.** For each one ask: would another project, or another person, meet this again? A lesson about this product alone goes in that project's `CLAUDE.md` and stops there. One that only says what happened is dropped: git has it. *Done when each item is marked system, project or dropped, with the reason for a drop.*

3. **Check each system lesson against the source.** Read the place in `/Volumes/Projects/system/skills` that should have said it.
   - Already said, and it was read: the wording failed. Sharpen that sentence.
   - Already said, and it was not read: the pointer failed. Fix the line that should have led there (a step in `new-app`, a row in a table).
   - Not said: it is new.
   - Then prove the lesson is true **now**: open the reference it names, run the command, look at the cluster or Vault (read-only). A lesson that cannot be proven is written with what was and was not seen, or left out.

   *Done when each lesson has the file and the sentence it changes, and how it was proven.*

4. **Put each lesson in its one place.** The first row that fits:

   | The lesson is | It goes in |
   |---|---|
   | something a script can see in a project's files | `skills/comply/scripts/check.sh`, as a `FAIL` (breaks a rule) or a `WARN` (likely drift). A check is worth more than a sentence: it does not need to be read |
   | a rule every project follows, a name, a port, where something lives | `skills/system/SKILL.md` (and the port registry row in the same change) |
   | a step done too late, too early or not at all | the numbered steps of the skill that owns the work (`new-app`, `deploy`, `migrate`, `database`) |
   | how a mechanism works, and its trap | that skill's `references/` file, beside the mechanism |
   | a project that now does a block better | the reference table in `system`: move the reference to it |
   | a reference that is behind the rules | the "don't copy" sentence under that table. List the project for the user; its own files are not changed from here |
   | about a secret or a Vault path | `skills/secrets/SKILL.md` |

   Change the sentence that was wrong before adding a new one, and delete what the lesson makes stale: the skills are read whole, every time. Say the positive (what to do, and the command), then the trap with what it looked like (the error text, the symptom), so it is recognised next time. Name the project where it happened only as a reference to copy or one not to copy.

5. **Prove the edits.** After a change to `check.sh`: `bash -n` on it, then run it on the project that taught the lesson (it must still say what is true of it) and on one other project (a new check that fires everywhere is wrong, or is a real finding to report). After a change to steps: read the skill from the top as someone starting a new app, and confirm the new line is met before the moment it is needed. *Done when both have been run or read, not assumed.*

6. **Report.** One table: what happened, the lesson, where it went (file and section). Then what was dropped and why, the projects found behind the rules, and anything that needs the user (shared infrastructure, a decision between two patterns). Leave the commit and the version in `.claude-plugin/plugin.json` to the user, and say that installed copies see nothing until the version is raised and released.

## What makes a debrief worth it

- **Trace a mistake to its source.** "I deployed to the wrong cluster" is the event. The lesson is the line that would have stopped it, or the absence of one.
- **Count your own mistakes in.** A wrong turn the agent took alone is the best evidence of a gap: the skills are written for the agent.
- **A short list is a good result.** Work that followed the skills and met no surprise has nothing to add; say so.
