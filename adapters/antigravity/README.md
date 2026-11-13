# Antigravity adapter

Loads the shared workflow in **Antigravity**. Canonical routing, commands, skills, and agents stay in
the repo root. This folder maps tiers to Antigravity `invoke_subagent` models (`deepLane: inline`).

Cursor, Claude Code, and Codex use their own adapters and do not need this one.

## Enable

Antigravity discovers `AGENTS.md` at the repo root automatically as a directory-based rule.
Skills are discovered one level under `skills/<name>/SKILL.md` when registered via `.agents/skills.json`
or declared in [.antigravity-plugin/plugin.json](../../.antigravity-plugin/plugin.json).

An Antigravity session reads [model-usage.md](model-usage.md) because `AGENTS.md` points at it.

## What stays in the repo root

| Shared | Antigravity |
|---|---|
| `_shared/model-routing.md` (tiers only) | [model-usage.md](model-usage.md) |
| `_shared/harness-verbs.md` (verbs) | Antigravity column of that map |
| `hooks/core/` | [hooks/](hooks/) adapters: `Stop` (report-context) |
| `skills/<name>/SKILL.md` | same files, registered via `.agents/skills.json` or `.antigravity-plugin/` |
| `commands/*.md` that are not also skills | listed from `./commands/` |
| Claude `.claude-plugin/plugin.json` | `.antigravity-plugin/plugin.json` |

## Open a ticket worktree

A worktree ticket's chat must be rooted at the ticket worktree: the `root` that
`scripts/ticket/Resolve-TicketRoot.ps1 -Ticket <ticket> -Json` returns. Start Antigravity there.
