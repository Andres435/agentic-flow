# `adapters/` — Per-runtime overlays

The repo root names verbs and tiers. Each adapter's `model-usage.md` maps tiers, subagent roles,
and `deepLane`. Verbs: [../_shared/harness-verbs.md](../_shared/harness-verbs.md).

| Adapter | Runtime | `deepLane` |
|---|---|---|
| [cursor/](cursor/README.md) | Cursor | dispatch |
| [claude/](claude/README.md) | Claude Code | dispatch |
| [gpt/](gpt/model-usage.md) | Cursor chat on a GPT picker | inline |
| [codex/](codex/README.md) | Codex | inline |
| [antigravity/](antigravity/README.md) | Antigravity | inline |

Hook logic lives once in [`../hooks/core/`](../hooks/core/). `cursor/hooks/`, `claude/hooks/`, `codex/hooks/`, and `antigravity/hooks/` are thin adapters over it. Codex wires `SessionStart` context and `PostModelRequest` token usage through its plugin manifest.

## External lanes (optional)

A user can add another vendor's read-only CLI as an extra lane for the architect panel and the
review second opinion. Copy [../user/external-lanes.example.json](../user/external-lanes.example.json) to
`user/external-lanes.local.json` (gitignored) and edit it: each entry has a `name`, `family`, an argv
`command`, `readOnly: true`, and an optional `timeoutSec`. [Invoke-ExternalLane.ps1](../scripts/ticket/Invoke-ExternalLane.ps1)
runs it with the prompt on stdin and accepts the reply only when its first line is `model: <x>` and
`<x>` starts with the entry's `family`; anything else is a one-line dropout, never a substitute
model ([rule 8](../_shared/model-routing.md#dispatch-rules)). Nothing runs unless the user asks for a panel
(`--panel` or "with panel"). The Codex entry was verified with this argv: `codex exec --sandbox read-only --skip-git-repo-check --ephemeral -` (it replied `model: GPT-6`, which satisfies a `gpt` family).

A Gemini external lane needs a Gemini API key (`GEMINI_API_KEY` or `GOOGLE_API_KEY`) and the Gemini CLI installed where your machine policy allows it; until then leave it off. Antigravity itself runs as an internal platform adapter, not an external CLI lane.

## Open a ticket worktree

A worktree ticket's chat must be rooted at the ticket worktree: the `root` that
`scripts/ticket/Resolve-TicketRoot.ps1 -Ticket <ticket> -Json` returns. Shared docs say only that;
how to get there depends on the runtime.

| Runtime | How |
|---|---|
| Cursor | Open the ticket's workspace file (or the worktree folder) and start a new Agent chat in that window. Never call `move_agent_to_root`: Cursor cannot root an agent on a folder of several git repos. |
| Claude Code | Start `claude` (with `--plugin-dir` pointing at this folder) in the worktree root, or change directory there first. |
| Codex | Start Codex in the worktree root. |
| Antigravity | Start Antigravity in the worktree root. |
