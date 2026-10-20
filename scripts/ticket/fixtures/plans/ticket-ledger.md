# Ticket ledger

One row per closed ticket. Written by `scripts/ticket/Update-TicketLedger.ps1` at
`/complete-task` -- do not hand-edit, the script owns this format.

This replaces the per-ticket `<ticket>-closeout.md` files. Durable *lessons* live in
[closeout-index.md](../../../../plans/closeout-index.md); a full closeout page is written only when a
retrospective earns one. Scorecard scale 1-5 (5 = excellent). `CtxS%` is the
/start-ticket chat, `CtxR%` is `/review-changes`, `Ctx%` is `/complete-task`.
`/implement` is not recorded. Do not backfill old rows.

| Tickets | Scored | Avg E | Avg C | Avg $tok | Avg CtxS% | Avg CtxR% | Avg Ctx% | Reopened | Avg Days |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 4 | 4 | 3 | n/a | n/a | 45% | 0 | 1.5 |

| Ticket | Type | Closed | Mode | Hours | Pts | E | C | $tok | CtxS% | CtxR% | Ctx% | PR | Lanes | Epoch | Reopened | Days | PRFind |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| WI00001 | feature | 2026-09-01 | branch | 4 | 2 | 4 | 4 | 3 | 40 | 50 | 45 | | | | no | 1.5 | |
