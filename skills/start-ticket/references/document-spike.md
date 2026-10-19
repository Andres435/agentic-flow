# Document spike

Run only from `/document-spike`, after the user asks to write the spike down. Finishing a spike does not run this. The investigation lives in [tech-spike.md](tech-spike.md); this file is only the write-up.

## When

- The user asked for a durable page.
- Findings exist. Do not start a blank page from the ticket title.
- Skip with `N/A — <why>` when the spike produced no durable knowledge (pure process, or already covered by an Accepted ADR / existing page).

## What to write

Durable facts a later developer needs: the question, the method, current behavior, constants/limits, risks, the recommendation, and what was not proven. **Do not** paste the Engineering Decisions, Work Plan, or the ticket outcome text verbatim if a shorter page says the same thing. No secrets. Optional source: [/research-x](../../research-x/SKILL.md) when the page cites current public discussion.

Keep workflow memory in [../../../plans/closeout-index.md](../../../plans/closeout-index.md), not the findings page. Do not draft an ADR here ([adr-policy.md](../../../_shared/adr-policy.md)).

## Where

- Ask where the page goes: a path the user names, or `plans/<ticket>-spike.md` when they do not.
- Say which branch is checked out before writing. Do not create or check out `<ticket>`. If it is the base branch, stop and ask the user where the page should land.
- If the project has a docs site with a nav or index, register the page there. A page that is not listed is unpublished.
- Cite code paths and constants; do not invent product behavior.
- Do not commit from this command.

## Done

- The page, uncommitted until the user asks.
- Do not create a tracker item and do not edit `profile.json`.
- `/complete-task` does not treat a missing page as a gap.
