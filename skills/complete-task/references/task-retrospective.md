---
name: task-retrospective
description: Final closeout step — asks three questions, scores the session, records one ledger row, and writes durable findings only where the user chooses to.
keywords: retrospective, closeout, scorecard, ledger, roadmap candidate, lessons, efficiency, contextualization, cost
---

# Task Retrospective

Run this as the final step of user-invoked `complete-task`, after the approval package and after any
user-approved `prep-pr` actions. Do not run automatically after implementation, verification, or
review. Nothing runs after it unless the user starts a new request.

## The shape of this step

**Ask, then act — do not write a page by default.** Every ticket used to get a 2–6 KB
`<ticket>-closeout.md`; 29 accumulated and nothing read them back. The durable value was always one
ledger row plus, occasionally, one lesson. So:

1. Score the session (three numbers).
2. Ask the three questions below.
3. Propose specific actions for whatever the answers surfaced, and let the **user** pick.
4. Write the ledger row. Write anything else only if chosen.

## 1. Score the session

Score each axis **1–5** (5 = excellent). Heuristic — the IDE does not always expose token counts.
Prefer evidence from the chat over inventing numbers.

### Efficiency (time-to-done / rework)

| Score | Meaning |
|---|---|
| 5 | One-pass solve; plan steps matched reality; little rework |
| 4 | Minor course-correction; still finished in expected slices |
| 3 | Notable rework or wrong-repo exploration that was recovered |
| 2 | Multiple failed approaches; large plan rewrite mid-flight |
| 1 | Thrash; ticket stalled or required restart |

### Contextualization (right docs, not full dump)

| Score | Meaning |
|---|---|
| 5 | Manifest `docSet` / env card / globs loaded what was needed; little irrelevant context |
| 4 | Small gap (one missing card or slice) but recovered quickly |
| 3 | Broad searching before routing; or loaded docs that were unused |
| 2 | Confused modern vs legacy paths / wrong specialist for a long stretch |
| 1 | Context thrash; repeated full-repo scans without a router |

### Cost / tokens (quota discipline)

| Score | Meaning |
|---|---|
| 5 | Plan on the top model; tasks by difficulty; subagents on the cheap tier; packets reused |
| 4 | Slight overuse (e.g. the top model on a `[low]` step) but stayed in the included bucket |
| 3 | Large parent context, repeated ticket/CI fetches, or oversized subagent prompts |
| 2 | Off-plan models used without user direction, or many redundant full-doc loads |
| 1 | Clear on-demand burn or runaway context with no discipline |

Also note the **context percentages** for this closeout chat (`Ctx%`) plus any `CtxS%` / `CtxR%` already on the manifest. Closeout occupancy is why we skip a duplicate review-diff when `/review-changes` is still Ready, and why branch mode
and the merged chat exist — recording it per ticket turns an impression into a trend.

## 2. Ask the three questions

Ask these in chat, together, in one short block. Offer the bracketed options so answering is one
word. Do not pad them with preamble.

1. **Did the plan hold?** — steps wrong · scope missed · estimate off · nothing
2. **Any friction in the agentic flow?** — wrong route/specialist · a doc that was missing or
   unfindable · an avoidable tracker/CI re-fetch · a gate or script that misfired · nothing
3. **Anything durable for next time?** — an environment-card fact · a lesson for the index · a
   workflow roadmap item · nothing

Bring your own evidence to the questions rather than asking blind: if you noticed a wrong specialist
or an avoidable re-fetch during the session, say so as part of asking. The user corrects or confirms;
they should not have to remember the session for you.

## 3. Propose, then let the user choose

For each non-`nothing` answer, propose the **specific** action — named file, one-line content — and
ask which to apply. Never apply them all silently.

| Answer points at | Proposed action | Target |
|---|---|---|
| A durable technical lesson | one row: ticket · domain · one-line lesson · `active` · today | [../../../plans/closeout-index.md](../../../plans/closeout-index.md) |
| An Engineering Decision that proved wrong | one row: ticket · the call · what was right · `active` · today; set an older row it contradicts to `superseded: <why>` | [../../../plans/closeout-index.md](../../../plans/closeout-index.md) |
| Repeating setup or a first-search target | one bullet | the matching card under [../../../environments](../../../environments) |
| A workflow/tooling improvement | one bullet (small, do-now) | a project overlay doc the user names |
| Deferred script/CI/doc-budget work | one row the user names | park it; do not implement unless asked |
| A gate, script, or command that misfired | a fix, or a roadmap bullet if it is not small | the script/command itself |
| Something genuinely needing a page | the full closeout file (shape below) | `../plans/<ticket>-closeout.md` |

Rules that do not bend:

- **A fix that can be a check should be a check, not another sentence.** If the answer is "the agent
  forgot X", prefer a gate in `scripts/ticket/Assert-TicketArtifacts.ps1` over more prose.
- Durable only. Never put ticket-specific facts (an unstaged Web.config, an unrelated PR) into a card,
  a rule, or the index.
- Never edit rules, skills, or environment cards **beyond the one bullet the user chose**, and never
  implement a roadmap item here — those are separate, user-initiated work.

## 4. Write the ledger row (always)

One call closes the ticket, after the user approved the package and gave the scores above. It stamps
`completedAtUtc` (`reclosedAtUtc` after a reopen), computes hours and points, records `report-context`,
writes the ledger row, and runs the close gate, stopping at the first `[FAIL] close step N (<name>)`:

```powershell
.\.cursor\scripts\ticket\Close-Ticket.ps1 -Ticket <ticket> `
  -Efficiency <1-5> -Contextualization <1-5> -CostTokens <1-5> -Pr <number>
```

`-WhatIf` lists the steps and writes nothing. Type comes from the manifest; omit `-Pr` if none.

**Context percents:** `Close-Ticket.ps1` never passes `-ContextPct`, `-ContextPctStart` or `-ContextPctReview`; the ledger
copies `ctxPct.close` / `.start` / `.review` from the manifest, which `report-context` filled with the
hook-measured value. `Lanes` is copied from `manifest.lanes`. Pass a number only when you can
actually read one; **never estimate**. A value the agent typed shows as `~NN`. `-Phase close` accepts
a blank percent and fails only on one outside 0–100; when nothing was measured, leave it blank and
say so.

Re-running for the same ticket replaces its row, so a reopen updates in place. Omit any switch you
genuinely do not have — a blank cell is honest, a guessed number is not. Never hand-edit
`plans/ticket-ledger.md`; to drop a row entered by mistake, use
`Update-TicketLedger.ps1 -Ticket <ticket> -Remove`.

The row records the workflow `Epoch` it closed under. If `scripts/ticket/Assert-WorkflowEpoch.ps1`
prints `[INFO] re-rate`, say so in one line and offer a re-rating of that epoch's rows; after the
user rates, run `Update-TicketLedger.ps1 -MarkRated`.

The call ends with `Assert-TicketArtifacts.ps1 -Phase close` (verify receipt and review stamp
included; a spike skips both); there is no separate confirm step.

## Closeout file shape (only when chosen)

```markdown
---
ticket: <ticket>
closed: <YYYY-MM-DD>
type: feature | bug | spike
---

# <ticket> Closeout

## Why this ticket earned a page
<one line — what a ledger row and an index lesson could not carry>

## Ticket summary
- What was done, repos/branches/key files, tests run, PR link and ticket state

## Retrospective
- Answers to the three questions, and what was actually changed as a result

## Other findings
- Discoveries, gotchas, deferred work
```

One file per ticket. On a reopen, append `## Closeout YYYY-MM-DD (reopen)` under the existing file and
update the top-level `closed:` — never add a second front-matter block.

## Chat output

Post at most five lines — see
[severity-and-output.md](../../../_shared/severity-and-output.md#chat-output-budget):

```text
TICKET-42 closed — Add CSV export for users; PR 99.
Scorecard E4 / C4 / $tok3 · 3 h → 2 pts · ctx 55% · ledger updated.
Added: closeout-index row (export must use streaming for large datasets).
Declined: roadmap bullet on caching.
```

If all three answers were `nothing`, that is two lines and no files beyond the ledger. Say so plainly
rather than manufacturing a finding.

## After PR feedback, or on reopen

Run this from `/address-pr-comments` after verification, and from a reopen `/start-ticket` (manifest
already has `completedAtUtc`) before any new implementation. It is not the close. Do not write the
first ledger row here; that stays the close step above.

Ask the same three questions, limited to what the review or the reopen changed: a reversed decision,
a missed test, or a wrong plan step. Bring the evidence you already have. For each non-`nothing`
answer, propose one named action and write a ledger update or a lesson only if the user picks it.
If every answer is `nothing`, stop. No scorecard, no closeout page.
