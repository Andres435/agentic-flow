# Machine setup

One-time setup for a laptop that will run this workflow. Visual Studio, IIS, cloud CLIs, and
product SDKs are not needed unless your project overlay adds them. Day-to-day ticket usage:
[USER-MANUAL.md](USER-MANUAL.md). Terms: [glossary](_shared/glossary.md).

## 1. Folder layout

**Host (many small apps).** Keep this clone as `agentic-flow`. Register each GitHub origin in
[apps/registry.json](apps/registry.json). Opening that checkout loads this plugin plus `apps/<id>/`.
Register the user-level `workspaceOpen` hook from [adapters/cursor/README.md](adapters/cursor/README.md).

**One product.** Place this folder at `<app>/.cursor` (one repo) or `source/repos/.cursor` (sibling repos):

```
my-app/
  .cursor/          ← this repo
  package.json
```

```
source/repos/
  .cursor/          ← this repo
  api/
  web/
```

Repos and paths come from `profile.json`. Do not hardcode product names in core files.

## 2. Prerequisites

| Tool | Why |
|---|---|
| Git | Repos, review fingerprints, the push gate |
| PowerShell 7 (`pwsh`) | Ticket gates, hooks, and Pester tests. Those scripts carry `#Requires -Version 7`; only the machine bootstrap (`scripts/machine/`, `scripts/lib/`) still runs on Windows PowerShell 5.1, so a new machine can run it before `pwsh` exists |
| Node.js LTS | IDE hooks; `npx` starts most MCP servers |
| One IDE: [Cursor](https://cursor.com), [Claude Code](https://claude.ai/code), or Codex | Loads the plugin |
| `gh` (optional) | When `profile.ticketSystem` is `github-issues` |

On a managed Windows device, install PowerShell 7 with the MSI under `Program Files`. A portable
copy in `%LOCALAPPDATA%` can be blocked by application control.

### Application allowlist

If endpoint allowlisting (application control that only runs scripts from approved folders) guards the machine, keep the workspace
clones and this template clone under the one allowed root, and never let agents write helper scripts
to temp or a scratchpad: only scripts run from the allowed root. Each blocked run is an approval
prompt for you. To have the `script-path-guard` hook deny those attempts before they reach the
allowlist, set the user environment variable `AGENTIC_SCRIPT_ALLOW_ROOT` to a regular expression for
the allowed path, for example `[\\/]source[\\/]repos[\\/]`. Unset, the hook allows everything.

## 3. Bootstrap

```powershell
scripts/machine/Initialize-WorkflowMachine.ps1            # -WhatIf previews everything
```

Phases are isolated and safe to re-run:

1. **Preflight**: reports missing tools; never blocks.
2. **Extensions / user config / cockpit**: run only when your overlay adds
   `Install-CursorExtensions.ps1`, `Apply-CursorUserConfig.ps1`, or `New-CockpitWorkspace.ps1` to
   `scripts/machine/`. Otherwise they are listed as skipped.
3. **Claude overlay**: `Install-ClaudeAdapter.ps1` writes `CLAUDE.md` at the workspace root.
4. **Git hooks**: `Install-GitPushHook.ps1` sets `core.hooksPath=hooks/git-hooks`. Then `git commit`
   refuses user-local `plans/` files and `git push` runs `Assert-AgenticFlow.ps1`. Do not use
   `--no-verify`.

Slash commands in Cursor: `scripts/machine/Install-UserCursorCommands.ps1` links each skill in
`profile.slashCommands`. Recommended settings and keybindings are in [user/](user/README.md).

## 4. MCP servers

`mcp.json` ships empty. Add the servers your tracker and tools need. Keep tokens in user
environment variables, never in the file. Restart the IDE completely after setting a variable.
Pin each `npx` server to a version (`some-mcp-server@1.2.3`, never `@latest`): `npx -y` runs fresh
package code that holds your tokens, so a version should move only in a reviewed commit.
`scripts/machine/Install-ClaudeAdapter.ps1 -Check` reports a workspace `.mcp.json` or `CLAUDE.md`
that no longer matches this folder; a plain run replaces it and keeps the old copy as `*.previous`.

## 5. Models (tiers)

Policy is [_shared/model-routing.md](_shared/model-routing.md). Each IDE maps tiers to models in
`adapters/<ide>/model-usage.md` ([Cursor](adapters/cursor/model-usage.md),
[Claude Code](adapters/claude/model-usage.md), [Codex](adapters/codex/model-usage.md)).

| Work | Tier |
|---|---|
| Plans | deep |
| Work Plan steps | fast / standard / deep by the step's `[low]` / `[med]` / `[high]` tag |
| Subagents | fast or standard by role |

After setup, run `/doctor --lanes` once; it records what each tier honored in your user-local
`adapters/<ide>/lane-probe.local.md`. The tracked `model-usage.md` changes only in a reviewed commit.

### Claude Code

Install the CLI if missing (`irm https://claude.ai/install.ps1 | iex` on Windows). Then either run
`claude --plugin-dir <this folder>` from the workspace root, or install the plugin once for every
runtime, desktop app included:

```bash
claude plugin marketplace add <absolute path to this folder>
claude plugin install agentic@agentic
```

The installed plugin is a copy keyed to the HEAD commit. Commit, then update it
([adapters/claude/README.md](adapters/claude/README.md#installed-plugins-are-a-snapshot-not-a-live-link)).
Also add `"env": { "CLAUDE_CODE_SUBAGENT_MODEL": "sonnet" }` to `~/.claude/settings.json` so
unrouted subagents do not inherit the chat model.

### Codex

Add this folder as a Codex plugin marketplace and install `agentic`:
[adapters/codex/README.md](adapters/codex/README.md).

## 6. Day-1 checklist

- [ ] Overlay filled (`/start-new-project` or `/adopt-project`) and the local-dev card describes the stack
- [ ] `git config --get core.hooksPath` prints `hooks/git-hooks`
- [ ] `scripts/ticket/Assert-AgenticFlow.ps1` prints `[PASS]`
- [ ] `/` in chat lists `start-ticket` once (Cursor) or `/agentic:start-ticket` (Claude Code)
- [ ] `/doctor` reports no hook errors and the lane probe recorded each tier
- [ ] (Optional) `node adapters/claude/hooks/tests/claude-hooks.test.js` passes

## 7. Common failures

| Symptom | Likely cause |
|---|---|
| Gate or test scripts fail with "Access ... denied" or a parse error | Running under Windows PowerShell 5.1, or a managed device blocks scripts outside approved folders. Use `pwsh`, and keep this folder under your normal source tree |
| Push blocked by the agentic-flow gate | Read the `[FAIL]` lines. In Claude Code, a stale plugin snapshot can run an old push hook: update the plugin |
| Commit blocked on a `plans/` path | Intended: plans and the ledger are user-local. `git rm --cached` the file |
| Every slash command shows twice in Cursor | A `.cursor` folder and a plugin copy of this folder both load. Keep one |
| Close gate says the review no longer matches | Something was committed after the review. Run `/review-changes` again, then close |

Optional: to add another vendor's CLI as a panel lane, copy `user/external-lanes.example.json` to
`user/external-lanes.local.json` ([adapters/README.md](adapters/README.md#external-lanes-optional)).

