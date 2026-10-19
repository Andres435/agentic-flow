---
name: doctor-skill
description: Verify the workspace is correctly set up for agentic workflow — profile, hooks, artifact gate, stack start command, lane probe, and workflow epoch.
keywords: doctor, health check, setup, profile, hooks, workspace validation, lane probe, epoch
disable-model-invocation: true
---

# /doctor — Workspace Health Check

Run all checks in order. Print `[PASS]` or `[FAIL] <one-line fix>` for each. Stop after listing
all failures; do not attempt repairs automatically.

## Checks

### 1. profile.json valid

```powershell
Get-Content profile.json -Raw | ConvertFrom-Json
```

Pass if it parses without error and contains: `id`, `ticketPrefix`, `ticketSystem`, `defaultMode`,
`repos`, `stacks`. Fail with: `profile.json missing required key '<key>' — see
README.md and CUSTOMIZE.md`.

Also run the full schema gate:

```powershell
.\scripts\ticket\Assert-AgenticFlow.ps1 -WarnOnly
```

This surfaces doc-budget, command-shim, retired-artifact, ledger-column, and user-plans (a
`plans/` ticket file tracked in git) failures too.

### 2. Hooks runnable

```
node hooks/tests/closeout-guard.test.js
node hooks/tests/session-context.test.js
node hooks/tests/resolve-app.test.js
node hooks/tests/git-push-agentic-flow.test.js
node hooks/tests/commit-guard.test.js
git config --get core.hooksPath
```

Pass if every test exits 0. Fail with: `hooks test failed — check node is on PATH and hooks/ is intact`.
Warn (not fail) when `core.hooksPath` is not `hooks/git-hooks`: `git pre-push/pre-commit not
installed — run scripts/machine/Install-GitPushHook.ps1`.

Also read `scripts/.hook-errors.log`. Pass when it is missing or empty: `[PASS] hook errors — none`.
Warn (not fail) when it has lines: `hook errors — scripts/.hook-errors.log has swallowed hook errors; read it, then delete it`.

### 3. Artifact gate resolves

```powershell
.\scripts\ticket\Assert-TicketArtifacts.ps1 -Ticket WI00001 -Phase start -Root .\scripts\ticket\fixtures
```

Pass if exit 0. Fail with: `Assert-TicketArtifacts failed on fixture — check fixture files in
scripts/ticket/fixtures/plans/`.

### 4. Stack services

Read `stacks` from `profile.json`. `scripts/ticket/Assert-AgenticFlow.ps1` runs the same checks
(shape from `scripts/ticket/profile.schema.json`, then `Get-StackProfileFindings` in
`scripts/lib/StackServices.ps1`).

- `services` empty → `[PASS] no local stack`.
- Each service has a unique non-empty `name` and a non-empty `command`.
- `cwd` (default `.`, relative to this repo) exists.
- `port` is an integer 1-65535 and no two services share one.
- `dependsOn` and every `presets` entry name real services; no `dependsOn` cycle.
- `ready` is `{ "port": true }` (needs `port`) or `{ "url": "..." }`, with optional `timeoutSec`.
- `env` values are strings. A literal value that matches a pattern in
  `secret-patterns.json` beside the gate fails (use `${env:NAME}`). Skip this check when that file is absent.
- `[FAIL]` on any of the above, quoting the service and field.
- `[WARN] stacks.startCommand is retired` when the old field is still set (anything but `off`):
  the launcher runs it as one service named `app`. Move it into `services`.

### 5. Lane probe (optional)

Run only when the user passes `--lanes`, or after changing a platform, an IDE plan, or an adapter.
Follow [model-routing.md](../../../_shared/model-routing.md).

1. **List the selectors first** when the IDE's dispatch tool exposes a model list. Print the `model`
   values it accepts. Take each tier's selector from that list exactly, never from memory or a
   pattern. A tier whose model has no listed value fails with `lane probe: <tier> has no selector in
   this session's model list`.
2. **Never dispatch an inline-only tier.** A tier the adapter marks **inline only** reports
   `[PASS] lane probe: <tier> — inline only, not dispatched` and is skipped, so the probe itself
   never runs on a substituted model. Re-test it only when the user passes `--retest-inline` (for
   example after an IDE plan change): dispatch it once, discard the reply whatever it says, and
   remove the inline-only mark only if it passes.
3. In one batch, `dispatch` one tiny read-only lane per remaining tier (`fast`, `standard`, `deep`),
   each with that `model` and the prompt: `Reply with only the model name or family you are running
   on. Use no tools.`
4. Pass if each reply names the **same model family** as the adapter's model for that tier. A lane
   reports a family or display name, not the platform's selector slug, so compare families only.
   An automatic-choice reply, `inherit`, or the chat's own model (when that is not the tier's) is a
   fail: the platform substituted a model.

Fail with: `lane probe: <tier> asked <selector>, got <reply> — record an unhonored tier in the
adapter`. Record every result (pass or unhonored, with the selector used and the date) in
`adapters/<ide>/lane-probe.local.md` (user-local, gitignored as `*.local.md`). Change the adapter
that owns the tier ([../../../adapters/README.md](../../../adapters/README.md)) only when the team
mapping must change, in a reviewed commit, never with one machine's results. Then run
any extra lane check the active adapter lists under its tier table (Claude Code has one).

### 6. Workflow epoch

Run `scripts/ticket/Assert-WorkflowEpoch.ps1` from the repo root. Fail only when it exits non-zero
(a local ledger row with no close date) and print its `[FAIL]` line. Otherwise print its
`[INFO] workflow epoch <id>` line as the pass.

The epoch id is computed from the watched workflow contract, so a contract edit starts a new epoch by
itself — there is no timer and no stamp to accept. When it prints `[INFO] re-rate`, the current epoch
has enough closes (`profile.json` `epochRerateAfter`) and no rating: rate the workflow on that
cohort, then run `scripts/ticket/Update-TicketLedger.ps1 -MarkRated`. A re-rate is a warning, not a
failure.

### 7. Installed overlay is current

When the workspace root has a `CLAUDE.md` or `.mcp.json` (the Claude Code overlay), run
`scripts/machine/Install-ClaudeAdapter.ps1 -Check`. A stale copy loads old instructions or MCP
versions into every session there. On exit 1 print its `[FAIL]` lines as
`[WARN] installed overlay stale — run scripts/machine/Install-ClaudeAdapter.ps1` (it keeps the old
copy as `*.previous`). With no overlay installed, print `[PASS] installed overlay — none`.

### 10. Enforcement upkeep (informational)

Run `scripts/ticket/Get-EnforcementUpkeep.ps1` (`-Days 30` default; `-Days 90` monthly). It prints `[INFO]` lines for
`Docs-Unaffected` waivers per rule (thin reasons flagged), the size of the `doc-claims.psd1` registry, and
`scripts/.hook-errors.log` counts per hook. It never fails and stays out of the count. Act on it monthly:
read any rule with many waivers (its co-change rule may be wrong), retire a claim once a check covers its fact,
and fix a hook that keeps logging errors.

## Output

```text
[PASS] profile.json — id: customize-me, ticketPrefix: TICKET-, 1 repo
[PASS] hooks — closeout-guard OK; session-context OK; commit-guard OK
[PASS] artifact gate — WI00001 start/close pass
[PASS] stacks.services — 2 service(s), 1 preset(s), no cycles
[PASS] workflow epoch — 1a2b3c4d, 2 close(s), re-rate after 3
[PASS] installed overlay — CLAUDE.md and .mcp.json current
```

Print a summary line: `Workspace OK (6/6)` or `Workspace needs attention (5/6 — see above)`. The
lane probe stays out of that count. On an epoch failure, fix the ledger row with
`Update-TicketLedger.ps1`; on a re-rate warning, rate the cohort, then run
`Update-TicketLedger.ps1 -MarkRated`.

## Scope

This command does **not** set up the machine (that is `/onboard`). It validates that the current
checkout is ready for agentic workflow.
