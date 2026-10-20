---
name: tech-spike
description: Plan and conduct technical investigations. Use when the user asks for a spike, research, feasibility analysis, options comparison, proof of concept, or architectural investigation.
keywords: spike, research, feasibility, investigation, timebox, findings
---

# Technical Spike / Investigation

## Purpose

Answer one question well enough for a PM to staff the follow-up and for an engineer to build it. The ticket holds that answer. This file is the local plan, not the ticket.

## First: Gather Input

A spike does not get a branch. `/start-ticket` records `mode: investigate`, fetches the ticket, runs the start gate, classifies, and searches the clones as they are. It does not ask main tree vs worktree and does not create `<ticket>`.

Before researching, take from the ticket or ask once if missing:

- **Ticket id**
- **Question** this spike must answer
- **Spike points** already on the ticket (timebox or story points), when the tracker has them. That number is how long a developer should spend investigating. Repeat it. If it is empty, recommend one and write it only after the user agrees. Do not replace it with session hours or with the build estimate.

## Local plan

Structure follows [../../../_shared/ticket-plan-output.md](../../../_shared/ticket-plan-output.md); plan mode, approval, and the final message stay with `/start-ticket`.

The persisted plan keeps:

1. **Problem Analysis** — the question, unknowns, and what "done" means.
1b. **Engineering Decisions** — scope of the investigation, per [../../../_shared/engineering-decisions.md](../../../_shared/engineering-decisions.md), before research. Candidates: the question this spike answers and the one it does not; the spike-point budget and what gets cut if it binds; whether a POC is in scope; which repos are in the search; an Accepted ADR that already settles part of it (when `adrIndex` is set — a spike answers what is genuinely open, it does not re-litigate an Accepted ADR, [adr-policy](../../../_shared/adr-policy.md)). `None — <why>` is valid. A `[high]` step records `architect: at Recommendation` or `architect skipped: investigation only`.
2. **Work Plan** — short, numbered, each step tagged `[low]|[med]|[high]` ([ticket-plan-output.md](../../../_shared/ticket-plan-output.md)). Research only. Read code on the current checkout; check legacy and modern paths when both exist. Do not edit product code.

Options stay in this plan only when they change the recommendation. Do not require two or three fully written options. Do not paste this plan onto the ticket. When `git blame` or `git log` reveals historical ticket ids, look them up read-only; do not write to them.

When current public discussion would change the answer, optionally run [/research-x](../../research-x/SKILL.md) (`search-x`). Skip it when the repo already answers the question. It is not a close gate.

If the recommendation sets a genuinely new architectural precedent no Accepted ADR covers, name it as an ADR-stub candidate for the implementing ticket to draft — a spike proposes, it does not draft or accept the ADR.

## What the ticket gets

Draft two sections while researching so closeout is a confirmation, not a rewrite: **Outcome** (the recommendation and next steps) and **Findings** (key discoveries, blockers, risks, what was not proven). `/complete-task` shows both before anything is posted; when `profile.ticketSystem` is not `none` it posts them to the ticket, otherwise they stay in the closeout.

**Points to implement** are the estimate to build the recommendation, for one developer using this AI workflow. Say that in one line, and say what would make the number wrong (hidden schema migration, ops queue, unknown vendor). That number is outcome text only. It is not the spike's own point field.

**Database change** and **Ops help** are each Yes or No plus one sentence. Ops means pipelines, configuration, secrets, or infra.

## Confidence Score

Fill out the rubric in [../../complete-task/references/confidence-score.md](../../complete-task/references/confidence-score.md), using `Findings certainty` as the second-row axis. Use **Risks / Unknowns** for residual gaps. If `Findings certainty` is Med or Low, flag the recommendation as provisional and propose a follow-up spike or POC.

## Closeout

Do not close automatically. The user invokes [/complete-task](../../complete-task/SKILL.md). A durable findings page is [/document-spike](../../document-spike/SKILL.md) only when the user asks — it is not part of finishing the spike.
