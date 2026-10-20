# Claude Code adapter

Loads the shared workflow in **Claude Code**. Routing, skills, and agents stay in the repo root.
This folder maps tiers ([model-usage.md](model-usage.md)), hooks, and install. Verbs map in
[../../_shared/harness-verbs.md](../../_shared/harness-verbs.md).

Humans: [../../USER-MANUAL.md](../../USER-MANUAL.md). Same chat counts; commands are
`/agentic:…` (the `name` in `.claude-plugin/plugin.json`).

## One-time enable

```powershell
scripts/machine/Install-ClaudeAdapter.ps1
```

That writes `CLAUDE.md` at the workspace root (the parent of this folder) from
[workspace-CLAUDE.md](workspace-CLAUDE.md). It also copies `mcp.json` to `.mcp.json` when it
declares servers. Then load the plugin.

### CLI

```bash
cd <workspace root>
claude --plugin-dir <this folder>
```

### Desktop app, IDE extension, or any runtime without `--plugin-dir`

This folder is its own marketplace ([`.claude-plugin/marketplace.json`](../../.claude-plugin/marketplace.json)):

```bash
claude plugin marketplace add <absolute path to this folder>
claude plugin install agentic@agentic
```

Without the CLI, add the same keys to `~/.claude/settings.json` (user scope, so ticket worktrees
outside the workspace still see it), then restart:

```json
{
  "extraKnownMarketplaces": {
    "agentic": { "source": { "source": "directory", "path": "<absolute path to this folder>" } }
  },
  "enabledPlugins": { "agentic@agentic": true }
}
```

### Installed plugins are a snapshot, not a live link

A `directory` marketplace **copies** this folder into
`~/.claude/plugins/cache/<marketplace>/<plugin>/<commit-sha>/`, keyed by the HEAD commit. After
changing anything the plugin ships (skills, hooks, `plugin.json`, output styles):

```bash
git commit -am "…"                                  # bump HEAD, or the refresh is a no-op
claude plugin marketplace update agentic
claude plugin update agentic@agentic --scope user   # the installed copy; restart after
```

`marketplace update` alone refreshes the catalog, not the install. Check the real install in
`~/.claude/plugins/installed_plugins.json` → `gitCommitSha`. A stale snapshot runs old hooks: for
example an old push hook can fail where the current one passes.

## Engineering mode and model routing

Tiers map to Claude models in [model-usage.md](model-usage.md). Pin engineering mode with
`/agentic:engineering-mode` or the **Engineering mode** output style
([../../output-styles/engineering-mode.md](../../output-styles/engineering-mode.md), auto-discovered).
A machine default `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` in `~/.claude/settings.json` `env` keeps
unrouted subagents off the chat model. An explicit `model` still wins. `/agentic:doctor --lanes`
runs the lane probe.

## Hooks

Hook logic lives once in [`hooks/core/`](../../hooks/core/). The scripts in [hooks/](hooks/) are thin
stdin/stdout adapters for Claude's contract, wired by `hooks/hooks.json` (declared in
`.claude-plugin/plugin.json`).

| Intent | Claude event | Script |
|---|---|---|
| Hydrate profile + ticket state at session start; also starts the daily scratch sweep in the background (once per UTC day, skip with `TMO_SKIP_SWEEP=1`) | `SessionStart` | `session-context.js` |
| Deny user `plans/` files; ask for a ticket id on product commits | `PreToolUse` (`Bash|PowerShell`) | `git-guard.js` → `git-commit-ticket.js` |
| Run `Assert-AgenticFlow` before pushing this folder, and `Assert-TicketArtifacts -Phase prepush` before pushing a product branch that names a ticket | `PreToolUse` (`Bash|PowerShell`) | `git-guard.js` → `git-push-agentic-flow.js` |
| Block direct closeout-file reads | `PreToolUse` (`Read`) | `closeout-read-guard.js` |
| Nudge when the prompt starts with a ticket command | `UserPromptSubmit` | `ticket-command-nudge.js` |
| Record measured context; re-hydrate after compact | `PreCompact` | `precompact-nudge.js` |
| Record measured context from the transcript | `Stop` | `context-usage.js` |

`git-guard.js` runs both git bridges in one node process (one start per shell call instead of
two), exits at once when the command has no `git`, and keeps the stricter answer: a push deny
beats a commit question in the same command. The PowerShell tool is matched too, so a commit or
push run there is gated like one run through Bash. When a push bridge itself crashes on a push of
this folder, it denies (fails closed) and logs to `scripts/.hook-errors.log`.

Tests: `node adapters/claude/hooks/tests/claude-hooks.test.js`. It also fails if a Cursor hook has
no Claude counterpart. Do not put Claude-only instructions in `AGENTS.md`.

## plugin.json: how components resolve

| Key | Rule |
|---|---|
| `skills` | Explicit list of each `./skills/<name>` folder. `Assert-AgenticFlow` fails a skill missing from it |
| `agents` | **Omit.** Auto-discovery takes `agents/*.md`. A `./`-prefixed file list resolves to zero; a directory string fails the plugin |
| `commands` | Explicit `./commands/<name>.md` list (empty here: every command is a skill) |
| `mcpServers` | **Omit.** A path string is ignored; the workspace `.mcp.json` supplies servers |

Agent discovery takes every `agents/*.md`, so the folder guide is `agents/README.markdown`.
