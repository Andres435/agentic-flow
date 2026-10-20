# `plans/` — Per-ticket artifacts

Ticket-keyed files written by the agentic workflow. In worktree mode they are shared across ticket
windows through the workflow folder ([../environments/worktrees.md](../environments/worktrees.md));
in branch mode there is only ever one root.

**User-local, never committed.** Every `<ticket>-*` file and `ticket-ledger.md` here belongs to the
user who ran the ticket and is gitignored. Git tracks only this README,
[closeout-index.md](closeout-index.md), `workflow-template-plan.md`, and [examples/](examples/)
(`ticket-ledger.example.md` shows the ledger shape). The `user-plans` check in
`scripts/ticket/Assert-AgenticFlow.ps1` (CI, pre-push, `/doctor`), the commit hook, and git
`pre-commit` refuse anything else (see
[../_shared/ticket-artifacts.md](../_shared/ticket-artifacts.md#durable-vs-scratch)).
Moving computers: copy `plans/` yourself; git will not carry it.

**Per-ticket only.** Scratch — cached tracker dumps, commit and PR-body drafts — lives in
`../tmp/tickets/` and is gitignored. `plans/evidence/<ticket>/` holds the verify evidence copy for a
ticket; it is user-local and pruned 14 days after close. If a file is regenerable from the tracker or
from git, it does not belong here. The contract is [../_shared/ticket-artifacts.md](../_shared/ticket-artifacts.md).
Retention runs are in `../scripts/Clear-WorkflowScratch.ps1`.

Humans: [../USER-MANUAL.md](../USER-MANUAL.md) (reload these files instead of re-fetching the ticket).

## Artifact map

| File | Written by | Purpose |
|---|---|---|
| `<ticket>-manifest.json` | ticket-router at start, then the stamp scripts | **The one record per ticket:** mode, repos, docSet, priorFindings, timestamps, and later `reviewReady` (with findings), `verify`, `feedback`, `stackSmoke`, `ctxPct`, `lanes` |
| `<ticket>-<type>-plan.md` | start-ticket, on approval | The approved plan. Opens with a `## Plan Digest`; the only plan implementation follows |
| `ticket-ledger.md` | `scripts/ticket/Update-TicketLedger.ps1` | **One row per closed ticket:** type, close date, mode, hours, points, E/C/`$tok`, CtxS%/CtxR%/Ctx%, Lanes, Epoch |
| `closeout-index.md` | complete-task, when the user picks a lesson | One-line durable lessons — the surface the next `/start-ticket` searches |
| `<ticket>-closeout.md` | complete-task | **Only when a retrospective earns a page.** Not required by any gate |

## Effective usage

1. **Don't hand-edit** `ticket-ledger.md` — the script owns its format. Don't hand-edit session
   timestamps either unless you are correcting a bad clock; `/complete-task` owns the math.
2. After a reopen, `/start-ticket` sets `reopenedAtUtc`; don't reset `startedAtUtc`. A ticket parked before
   `/complete-task` (`Park-Ticket.ps1`) is resumed with `Resume-Ticket.ps1`, which opens a new span. Re-running
   `Update-TicketLedger.ps1` replaces that ticket's row rather than adding one.
3. Use the manifest to see which mode, repos, and specialists a ticket claimed without re-asking the
   agent.
4. The retrospective **asks** before it writes. Durable lessons get promoted into
   [closeout-index.md](closeout-index.md) or an environment card — never into more plan files.
5. `closeout-index.md` is the retrieval surface, so keep its rows dense and specific. A vague row is
   worse than none: it costs `priorFindings` space on every future ticket in that domain.

## Related

- Artifact contract: [`../_shared/ticket-artifacts.md`](../_shared/ticket-artifacts.md)
- Plan structure: [`../_shared/ticket-plan-output.md`](../_shared/ticket-plan-output.md)
- Time math: [session-time-tracking.md](../skills/complete-task/references/session-time-tracking.md)
- Retrospective: [task-retrospective.md](../skills/complete-task/references/task-retrospective.md)
- Memory search: [closeout-search.md](../skills/ticket-router/references/closeout-search.md)
