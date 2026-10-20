---
name: ticket-context-load
description: Hydrate a fresh chat from a ticket's existing artifacts — mode and root, manifest, approved plan, doc set, environment card, prior findings — instead of re-fetching the tracker or re-deriving scope. First step of complete-task, review-changes, address-pr-comments, and implement in worktree mode or when resuming.
keywords: context load, hydrate, fresh chat, manifest, mode, root, artifacts gate, prior findings, load profile
icon: book
color: blue
---

# Ticket Context Load

A new chat has **no** ticket context. Everything it needs was already computed by `/start-ticket` and
written to `plans/` (or `apps/<id>/plans/` when this host registered the opened origin). This skill loads that state.

Without it, a fresh chat has only whatever prose the user pasted, so it re-derives scope and
re-plans. That is the failure this skill exists to prevent.

## Load profile — caller determines depth

**`complete-task`** is a fresh closeout chat. It does **not** need the Work Plan steps, the
`docSet`, or the `environmentCard` — those were already executed. Read only:
- `<ticket>-manifest.json` (mode, repos, timestamps, `priorFindings`, optional `stackSmoke`)
- The **Plan Digest**, **Engineering Decisions**, and **Deviations** sections of
  `<ticket>-<type>-plan.md` (skip the Work Plan steps entirely)

**`review-changes`** reviews the diff, not the plan. Read the same files as `complete-task`, minus
`priorFindings` and Deviations. The plan sections are there so findings can cite what was intended.

**`implement` and `address-pr-comments`** need the full plan and `docSet` — use the standard steps
below unchanged.

This profile is applied at step 4 and step 5 below.

## When To Run

As the **first step** of a chat that did not produce the state itself:
[complete-task](../complete-task/SKILL.md),
[review-changes](../review-changes/SKILL.md) (when a ticket key is known),
[address-pr-comments](../address-pr-comments/SKILL.md), and
[implement](../implement/SKILL.md).

**Do not run it** in `/start-ticket` — that command *produces* this state. In branch mode
`/start-ticket` also builds in the same chat, so loading there would re-read what it just wrote.
That avoided reload is the point of branch mode.

**Do not run it** in `/peer-review` — coworker PRs have no local ticket artifacts.

**Do not run it** in `/onboard` or `/doctor`.

## Steps

1. **Resolve the ticket key.** From the invocation (using `profile.ticketPrefix`), else the
   workspace folder name, else the repos' current branches:

   ```powershell
   .\.cursor\scripts\ticket\Get-TicketFromBranch.ps1 -Json
   ```

   Use its `ticket` when `reason` is `open-manifest` or `branch`; confirm with the user when it is
   `closed-manifest`. Ask only when `ticket` is null (no ticket branch, or two open tickets).

2. **Resolve the mode and root.** Do not assume either.

   ```powershell
   .\.cursor\scripts\ticket\Resolve-TicketRoot.ps1 -Ticket <ticket> -Json
   ```

   - **`mode: branch`** — work happens in `profile.repos[].path`. That is the normal case.
   - **`mode: worktree`** — work happens at the worktree root the script returns. If this chat is
     not rooted there, stop and tell the user how to open one that is, per
     [adapters/README.md](../../adapters/README.md#open-a-ticket-worktree).
   - **`rootExists: false`** — stop. Report it and let the user re-run `/start-ticket`.

3. **Run the artifacts gate** with `-Phase implement` — for *every* calling command, closeout
   included:

   ```powershell
   .\.cursor\scripts\ticket\Assert-TicketArtifacts.ps1 -Ticket <ticket> -Phase implement
   ```

   `-Phase implement` is the load-time gate because it checks only what must already exist (manifest
   + plan). `-Phase close` checks the close timestamp and ledger row, which `/complete-task` writes
   *later in its own run* — running it here always fails.

   On `FAIL`, stop and report exactly which artifacts are missing. Offer to reconstruct them from
   what does exist. Do not proceed by inventing a plan. See
   [ticket-artifacts.md](../../_shared/ticket-artifacts.md).

4. **Read `<ticket>-manifest.json`** and treat it as the routing table:
   - `mode` — already resolved in step 2; carry it, do not re-derive.
   - `affectedRepos` — the only repos in scope; scope every `Grep`/`Glob` to the paths
     `Resolve-TicketRoot.ps1` returned.
   - `docSet[]` — **`implement`/`address-pr-comments` only**: load each slice when the step needs it.
     **`complete-task`**: do not load `docSet` or `environmentCard`.
   - `environmentCard` — **`implement`/`address-pr-comments` only**: load when non-null.
   - `specialists[]`, `priorFindings[]`, `baseBranch`, `adrIndex` — carry forward, do not recompute.
   - Session timestamps live here too — `/complete-task` reads them for the hours math.

5. **Read the approved plan** `<ticket>-<type>-plan.md`:
   - **`implement`/`address-pr-comments`**: full plan including Work Plan steps and **Deviations**.
   - **`complete-task`**: **only** `## Plan Digest`, `## Engineering Decisions`, and
     `## Deviations`. Do **not** read the Work Plan steps.

6. **Get title and tracker context from `manifest.ticket`.** Description, repro, and AC are in
   the approved plan. **Do not re-fetch the tracker** unless the user says "refresh".

7. **Report branch state** in each resolved repo path: the current branch and how far it is behind
   `origin/<baseBranch>` (`git rev-list --count HEAD..origin/<baseBranch>` after a fetch). Report
   only; never merge here. Review and closeout run on a staged set, and git refuses a merge over
   staged changes. The base merge belongs to `/implement` (clean index) and `/prep-pr`. Skip this
   step for `mode: investigate`: a spike reads the clones as they are.

8. **Post one compact load line**, then continue with the calling command:

   ```text
   Loaded TICKET-42 — feature | branch | app | none | fullstack | plan: 4 steps | 0 prior findings | on TICKET-42, 2 behind main
   ```

## Guardrails

- Do not re-run [ticket-router](../ticket-router/SKILL.md). Refresh the manifest only when the user
  says scope changed.
- Do not re-fetch the ticket, and do not search the backlog.
- Do not read `plans/*-closeout.md`, `closeout-index.md`, or `ticket-ledger.md`. `priorFindings` is
  the compact answer.
- Do not dump the manifest or plan into chat. One load line.
- Do not commit, push, create PRs, or write the tracker from this skill.
