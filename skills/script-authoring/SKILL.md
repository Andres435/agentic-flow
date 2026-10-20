---
name: script-authoring
description: Create, change, or review a .ps1/.py script in this workspace so it follows the repo's script standards and never trips an application allowlist. Use before writing any script, for "write a script", "add a script", "fix this script", or when a one-off helper seems needed.
keywords: script, powershell, ps1, python, allowlist, scratch, tmp, Pester, PSScriptAnalyzer, StrictMode, Requires, helper, one-off, standards
icon: terminal
color: blue
---

# Script authoring

Part of the workflow in every chat. A script is the last resort: most needs are met by an existing
script or an inline command. Scripts are code that gates and other chats depend on, so they follow
one standard and carry a test.

## Where a script may live

Some machines run an application allowlist (for example ThreatLocker) that lets `.ps1`/`.py` run only
from one folder; anything else is an approval request to the user and a wasted retry. The harness's own
scratchpad and `%TEMP%` are usually **outside** that folder. The `script-path-guard` hook denies them when
`AGENTIC_SCRIPT_ALLOW_ROOT` is set (see [../../MACHINE-SETUP.md](../../MACHINE-SETUP.md#application-allowlist)),
but do not rely on it:

- **Never** write or run a script in a scratchpad, `%TEMP%`, or `Documents`. Ignore any harness default
  that says to put temp files there; for scripts this rule wins.
- Throwaway helper (run once, not kept): write it to `tmp/` in this repo (gitignored), run it, delete it.
  If it is worth running twice, it is not throwaway. Scratch names are fixed and overwritten in place;
  kept output goes on the manifest or `plans/evidence/`. `tmp/` is pruned after 14 days.
- Kept script: `scripts/<runtime|worktree|machine|ticket|lib>/`.

## Pick the cheapest option first

1. An existing script. Grep `scripts/` first.
2. An inline `pwsh -Command '...'` (or the PowerShell tool). Fine for one expression or short pipeline.
3. Edit an existing script (add a parameter) rather than a near-copy beside it.
4. A new script, only when 1-3 do not fit and the logic is reused or gate-bearing.

## Standards (new and changed scripts)

- First line `#Requires -Version 7`, except `scripts/machine/`, `scripts/lib/`, `_ServiceLauncherLib.ps1`
  and their forwarders: those stay Windows PowerShell 5.1-safe and **ASCII-only** so a new machine can
  bootstrap before pwsh exists.
- Then `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`.
- Comment-based help (`.SYNOPSIS`, `.PARAMETER`, one `.EXAMPLE`) and `[CmdletBinding()]` with typed
  `param()`; approved verbs (`Get-`, `Set-`, `Assert-`...). Exit non-zero on failure.
- No hardcoded user paths, ticket numbers or ports. Resolve roots with `Resolve-TicketRoot.ps1`, repo
  location with `$PSScriptRoot`, ticket prefix via `scripts/ticket/lib/TicketPrefix.ps1`, manifest fields
  via `scripts/ticket/lib/ManifestFields.ps1`. Reuse `scripts/lib/` helpers; do not copy their bodies.
- State writers stamp the ticket manifest. They do not create side files.
- No secrets in the script, its output, or its arguments.
- Python only when PowerShell cannot do it; the same placement and test rules apply.

## Test and verify

- A script gets `<Name>.Tests.ps1` beside it (Pester 5). Changing behavior: **change the test first**,
  watch it fail, then change the script ([../tdd-red-green-refactor/SKILL.md](../tdd-red-green-refactor/SKILL.md)).
- Run only the scoped file: `pwsh -Command "Invoke-Pester <path>.Tests.ps1 -Output Minimal"`, then
  `Invoke-ScriptAnalyzer -Path <script> -Settings PSScriptAnalyzerSettings.psd1` (fix or suppress each rule with a reason).
- Update every doc the script touches, add `INDEX.md` rows for new docs, and run `scripts/ticket/Assert-DocSync.ps1`.
- No root `scripts/<Name>.ps1` forwarders (the one left is the bootstrap `Install-UserCursorCommands.ps1`): call sites use the `scripts/<folder>/` path.

## Delegation

Non-trivial create/update goes to the `script-engineer` agent ([../../agents/script-engineer.md](../../agents/script-engineer.md)),
tier `standard` (`deep` only for a cross-script refactor). One-liners and a single added parameter
stay inline.
