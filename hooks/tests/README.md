# Hook tests

Hook logic lives once in `hooks/core/` and names no IDE. Each IDE's hooks are thin
stdin/stdout adapters: Cursor in `adapters/cursor/hooks/` (wired by the root `hooks.json`),
Claude Code in `adapters/claude/hooks/` (wired by its `hooks.json`). The git hooks in
`hooks/git-hooks/` use the same core, so the plans hard stop and the push gate hold outside
any IDE.

These tests cover the core plus the Cursor adapters. The Claude adapters have their own suite,
`node adapters/claude/hooks/tests/claude-hooks.test.js`, which also fails if a Cursor hook has
no Claude counterpart. Run both after changing hook logic.

Requires only Node.js (no framework). Run from the workspace root, for example:

```bash
node hooks/tests/commit-guard.test.js
node hooks/tests/context-usage.test.js
```

| Test file | Under test | What it checks |
|---|---|---|
| `closeout-guard.test.js` | `core/closeout-guard.js` via the Cursor adapter | Deny closeout dumps, allow other files, degrade on bad JSON |
| `session-context.test.js` | `core/session-context.js` via the Cursor adapter | Packet shape, env keys, graceful degrade without PowerShell, a reopened ticket stays open, a stamped PR with no ledger row nudges complete-task |
| `resolve-app.test.js` | `core/resolve-app.js` | Origin normalize, registry match, host plus overlay plugin paths |
| `git-push-agentic-flow.test.js` | `core/push-gate.js`, both adapters, Claude `git-guard.js` | A failing workflow clone is denied through Cursor, Claude Bash, and Claude PowerShell; a ticket branch with a manifest runs `-Phase prepush`; a crash fails closed; `echo "git push"` is not a push |
| `ticket-command-nudge.test.js` | `core/ticket-nudge.js` via the Cursor adapter | Fire only on a leading slash command; the close nudge names Close-Ticket.ps1; engineering-mode names the playbook |
| `script-path-guard.test.js` | `core/script-path-guard.js`, both adapters | Deny writing or running .ps1/.py outside the allowed script root (opt-in: set `AGENTIC_SCRIPT_ALLOW_ROOT`); allow repo, relative and inert commands |
| `commit-guard.test.js` | `core/commit-guard.js`, `git-hooks/pre-commit` | Deny user-local plans/ files; ask for a ticket id only in product repos, read from the message (`-m`, `-F`, `-F -`), not the directory |
| `secret-scan.test.js` | `core/secret-scan.js`, `core/commit-guard.js`, `git-hooks/pre-commit` | Deny a commit that adds a token-shaped secret (patterns in `scripts/ticket/secret-patterns.json`); never echo the token; `secret-scan:allow` exempts a line |
| `session-sweep.test.js` | `core/session-context.js` `maybeSweep`, `core/pwsh.js` | Once-per-UTC-day detached `Clear-WorkflowScratch.ps1`; `TMO_SKIP_SWEEP=1` skips; a failing spawn never throws; packet output unchanged |
| `hooks-manifest.test.js` | root `hooks.json` (Cursor) | Every matcher compiles with no control character (a JSON `` is a backspace) and fires on the commands its hook guards |
| `context-usage.test.js` | `core/context-usage.js`, Claude Stop hook | Measured context from a transcript; per-session record |

All exit 0 on success, 1 on failure. Safe to run without a product repo or PowerShell installed (tests that need `pwsh` say skipped);
`session-context.test.js` stubs the Resolve-TicketRoot path (script not found → graceful degrade). The hook runs `scripts/ticket/Resolve-TicketRoot.ps1` only; the old root forwarder is gone.
