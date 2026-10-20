# Cursor adapter

Loads the shared workflow in **Cursor**. Routing, skills, and agents stay in the repo root. This
folder holds the Cursor tier map ([model-usage.md](model-usage.md)) and the Cursor hook adapters.
Claude Code and Codex use their own adapters.

## Enable

Place this folder at `<app>/.cursor` (or `source/repos/.cursor`). Cursor reads `rules/`, `hooks.json`,
and `agents/` from a workspace `.cursor` folder directly. Then link the slash commands:

```powershell
scripts/machine/Install-UserCursorCommands.ps1
```

It junctions each skill in `profile.slashCommands` into `%USERPROFILE%\.cursor\skills\` so slash
badges keep their icons, and removes links to skills no longer in that list. `.cursor-plugin/plugin.json`
points `commands` and `skills` at empty folders so the picker is not filled with icon-less copies.
Reload the window after the first install.

If this folder has another name, Cursor does not read it as `.cursor`. [hooks/workspace-open.js](hooks/workspace-open.js)
is a user-level `workspaceOpen` hook that returns this folder in `pluginPaths` (and `apps/<id>/`
when the opened origin is in `apps/registry.json`, see [apps/README.md](../../apps/README.md)); register it in
`%USERPROFILE%\.cursor\hooks.json`. Do not also keep a real `.cursor` folder in the same workspace,
or every slash command shows twice. An unregistered app still loads this host so `/adopt-project`
can run.

## What stays in the repo root

| Shared | Cursor |
|---|---|
| `_shared/model-routing.md` (tiers only) | [model-usage.md](model-usage.md): Cursor tier map, `deepLane`, subagent types |
| `_shared/harness-verbs.md` (verbs) | `AskQuestion`, `SwitchMode`, `Task`, `rename_chat` (map in that file) |
| `skills/`, `rules/`, `agents/` | `rules/*.mdc` load by glob only in Cursor |
| `hooks/core/` (hook logic) | root `hooks.json` → [hooks/](hooks/) adapters: `sessionStart`, `beforeShellExecution` (git commit, git push), `beforeSubmitPrompt`, `beforeReadFile`, `preCompact` |
| GPT picker tiers | [../gpt/model-usage.md](../gpt/model-usage.md) |

Engineering mode is the `engineering-mode` skill, pinned for the chat. Deep work dispatches when the
picker honors the deep model ([model-usage.md](model-usage.md)).
