---
name: onboard
description: Walk a new developer through machine setup and workspace initialization for this host.
keywords: onboard, machine setup, new developer, install, bootstrap, initialize, customize
icon: flag
color: brand
---

# /onboard — New Machine Setup

Walk the user through setting up their machine. Read [CUSTOMIZE.md](../../CUSTOMIZE.md), then run
the initialization script.

## When to use

- First clone of this host
- After renaming the host profile (`profile.json` id, displayName)
- When `/doctor` reports failures

## What this does NOT do

- Does not create worktrees (default is branch mode).
- Does not install language-specific dependencies — those are per-app.
- Does not interview for stack or tracker. That is `/start-new-project` or `/adopt-project`.

## Steps

1. If the user wants a **new** product and no `apps/<id>/` overlay exists yet, stop and tell them
   to run `/start-new-project`. If they opened an **existing** checkout that is not in
   [apps/registry.json](../../apps/registry.json), tell them to run `/adopt-project`. If the root
   `profile.json` `id` is still `customize-me` and they are using this clone as the product itself,
   same: `/start-new-project`. Do not interview for those here, and do not start a ticket until
   that command has run.
2. If a profile overlay already exists, skip the questionnaire — run the init script and `/doctor`.
3. **Run the initialization script**:
   ```powershell
   # From this host repo:
   .\scripts\machine\Initialize-WorkflowMachine.ps1
   ```
4. After running the script, run `/doctor` to confirm the workspace is healthy.
5. If `/doctor` shows failures, walk through the specific fix listed.

## Output

After completing setup, show a one-line summary:
```text
Machine setup done — run /doctor to confirm.
```
