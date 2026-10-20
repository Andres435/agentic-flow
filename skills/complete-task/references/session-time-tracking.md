---
name: session-time-tracking
description: Automatic dev time spent from start-ticket through complete-task using session timestamps, business-day rules, per-day caps, and hours-to-story-points conversion for ADO.
keywords: hours, story points, timestamps, startedAtUtc, reopen, business days, time tracking
---

# Session Time Tracking

Dev time is computed automatically from session timestamps as **hours**. Show hours in the
approval package; write **story points** on the work item when the tracker has that field.
Hours/points stay on the ticket, not in the PR body.

Do not ask the user for hours unless the timestamps are missing or the calculation needs manual override.

## Where the timestamps live

**On the manifest:** `.cursor/plans/<ticket>-manifest.json`.

**Written by:** [../../ticket-router/SKILL.md](../../ticket-router/SKILL.md) during
[/start-ticket](../../start-ticket/SKILL.md), immediately after ADO intake — before branch setup or
any provisioning, so a late write cannot lose the session clock.

**Updated by:** [/complete-task](../SKILL.md) at closeout.

**Legacy fallback:** tickets started before the timestamps moved onto the manifest still have a
`.cursor/plans/<ticket>-session.json`. Read it when the manifest has no timestamp fields, and write
the close back to it. Nothing creates that file any more.

### Fields (on the manifest)

```json
{
  "workItemId": 18158,
  "workType": "feature",
  "mode": "branch",
  "startedAtUtc": "2026-07-06T20:15:00.000Z",
  "completedAtUtc": null,
  "reopenedAtUtc": null,
  "reclosedAtUtc": null,
  "timezone": "America/Los_Angeles"
}
```

| Field | Meaning |
|---|---|
| `startedAtUtc` | ISO-8601 UTC when the **first** `/start-ticket` finished branch setup. Never overwrite after first write. |
| `completedAtUtc` | ISO-8601 UTC when the **first** `/complete-task` ran. Never overwrite after first write. |
| `reopenedAtUtc` | ISO-8601 UTC when `/start-ticket` resumes a ticket that already has `completedAtUtc` (QA rejection / reopen). |
| `reclosedAtUtc` | ISO-8601 UTC when `/complete-task` runs after a reopen (`reopenedAtUtc` is set). |
| `timezone` | Optional IANA zone for holiday/weekend evaluation (default `America/Los_Angeles`). |

### Write rules

1. **First `/start-ticket`** (manifest has no `startedAtUtc`): write `startedAtUtc` = now; set `completedAtUtc`, `reopenedAtUtc`, and `reclosedAtUtc` to `null`.
2. **First `/complete-task`**: `Close-Ticket.ps1` sets `completedAtUtc` = now, after approval. Do not touch reopen fields.
3. **Reopen `/start-ticket`** when `completedAtUtc` is already set: set `reopenedAtUtc` = now; set `reclosedAtUtc` = `null`. **Do not** overwrite `startedAtUtc` or `completedAtUtc`.
4. **Reclose `/complete-task`** when `reopenedAtUtc` is set: `Close-Ticket.ps1` sets `reclosedAtUtc` = now. **Do not** overwrite `completedAtUtc`.
5. Never replace the original `[startedAtUtc, completedAtUtc]` pair with a single span that includes idle days between close and reopen.

### Parked tickets

A ticket that stops before `/complete-task` (tracker state "needs more info", or closed early) is recorded
with `scripts/ticket/Park-Ticket.ps1 -Outcome more-info|closed-by-ado`. It closes the open span at now
(an explicit entry in `spans`), stamps `parkedAtUtc`, `parkedState`, `parkedOutcome` and `parkedHours`,
and writes a ledger row whose `Outcome` column is the outcome (no scorecard, no points). Resuming runs
`Resume-Ticket.ps1`, which opens a `resume` span at the resume time and moves the park stamps to
`parkHistory`; `Close-Ticket.ps1` ends the open span and sums every span, so the idle gap is never
counted. `completedAtUtc` is only set by the final close.

## Time Calculation (complete-task / prep-pr)

Run `scripts/ticket/Get-SessionHours.ps1 -Ticket <ticket> -Preview` for the approval package:
`-Preview` counts the still-open span up to now and writes nothing. `Close-Ticket.ps1` stamps the
close (`completedAtUtc` or `reclosedAtUtc`) and runs it again for the ledger. Use its hours and
point bucket. Do not recompute them.
`/address-pr-comments` opens and closes a `pr-feedback` span with `-BeginSpan` and `-EndSpan`.
The script does not write a tracker field. Write the point bucket only when the tracker has one,
and never for a spike.

### Segments

The script sums every closed span. Gaps between spans are zero.

| Segment | When included | Interval |
|---|---|---|
| Original | `startedAtUtc` and `completedAtUtc` both set | `[startedAtUtc, completedAtUtc]` |
| Reopen | `reopenedAtUtc` and `reclosedAtUtc` both set | `[reopenedAtUtc, reclosedAtUtc]` |
| PR feedback | a closed `pr-feedback` span | that span's start and end |

Idle time between `completedAtUtc` and `reopenedAtUtc` is **not** counted.

If only the original segment is open (`completedAtUtc` null), use `[startedAtUtc, now]` only for display during an in-progress first pass — do not write ADO points until closeout.

### Rules (per segment)

1. Walk each **calendar day** from segment start through segment end in the session `timezone`.
2. **Skip Saturdays and Sundays** — no hours counted.
3. **US federal holidays** — do not count hours; **flag** each holiday date in the output (see list below). If unsure whether an observed date is a holiday, flag it for user review.
4. **Per-day cap: 8 hours maximum** — for each counted day, compute overlap between the segment interval and that local calendar day, then `min(overlapHours, 8)`.
5. **Sum** capped daily hours across all segments → `calculatedHours` (one decimal place).
6. **Display** each segment, `calculatedHours`, and the daily breakdown to the user in the approval package.
7. **Convert** `calculatedHours` to story points (see table below) and write **only the story-point value** on the work item. Never write raw hours to the tracker. A spike does not use this conversion: session hours stay local, spike points stay the investigation budget already on the work item, and the build estimate stays in the outcome text.

### Hours → Story Points (work item)

Use the **lowest point value whose range includes** `calculatedHours`. Allowed values: **1, 2, 3, 5, 8, 13** only.

| Story points | Calculated hours | Meaning |
|---|---|---|
| **1** | > 0 and ≤ 2 | ~1–2 hours |
| **2** | > 2 and ≤ 4 | Half a day or more |
| **3** | > 4 and ≤ 16 | About one to two days |
| **5** | > 16 and ≤ 24 | About half a week |
| **8** | > 24 and ≤ 40 | A whole week or more |
| **13** | > 40 | A whole sprint or more |

**Manual override:** When the user supplies hours (no recorded timestamps), convert with the same table before writing ADO. Show both hours and converted points in the approval package.

**Examples:**

| Calculated hours | ADO story points |
|---|---|
| 1.5 h | 1 |
| 3.0 h | 2 |
| 10.0 h | 3 |
| 20.0 h | 5 |
| 25.0 h | 8 |
| 45.0 h | 13 |

### US Federal Holidays (flag + exclude)

Fixed (evaluate in session timezone):

| Holiday | Date |
|---|---|
| New Year's Day | January 1 |
| Juneteenth | June 19 |
| Independence Day | July 4 |
| Veterans Day | November 11 |
| Christmas Day | December 25 |

Variable — flag using standard US federal observance for the session year:

| Holiday | Rule |
|---|---|
| Martin Luther King Jr. Day | Third Monday in January |
| Presidents Day | Third Monday in February |
| Memorial Day | Last Monday in May |
| Labor Day | First Monday in September |
| Thanksgiving | Fourth Thursday in November |

When a fixed holiday falls on Saturday, federal observance is often Friday; when on Sunday, often Monday. Flag the **observed** federal date if it differs from the calendar date.

### Output Template

```markdown
## Session time (hours → story points)

| Metric | Value |
|---|---|
| Original start (UTC) | 2026-07-06T20:15:00Z |
| Original end (UTC) | 2026-07-07T02:30:00Z |
| Reopened (UTC) | 2026-07-16T14:00:00Z |
| Reclosed (UTC) | 2026-07-16T21:09:00Z |
| Weekends excluded | Sat 2026-07-11, Sun 2026-07-12 |
| Holidays flagged | None |
| **Calculated hours** | **10.0 h** (original 4.0 + reopen 6.0) |
| **ADO Story Points Actual** | **3** (one to two days tier) |

Daily breakdown:
- Segment original:
  - 2026-07-06 (Mon): 3.8 h
  - 2026-07-07 (Tue): 0.2 h
- Segment reopen:
  - 2026-07-16 (Thu): 6.0 h
```

### Missing Timestamps

If neither `<ticket>-manifest.json` nor the legacy `<ticket>-session.json` has a `startedAtUtc`:

- Report that automatic time tracking is unavailable.
- Do not invent hours.
- Ask the user for hours **or** story points. If they supply hours, convert with the table above before writing points on the work item.
