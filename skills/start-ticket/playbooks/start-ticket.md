---
name: start-ticket
description: Start a ticket from the project's ticket system, classify it into a work manifest, set up branches (or worktrees with --worktree), build the approved plan, and in branch mode implement it in the same chat.
keywords: start ticket, intake, manifest, branch mode, worktree, plan mode, approval, implement
disable-model-invocation: true
---

# Start Ticket

Starts a ticket. In **branch mode** (the default) it also **builds** it — one chat, plan through
implementation. In **worktree mode** it stops at the handoff. In **investigate mode** (spike) it
researches only.

**Fill-in-the-blanks first.** `profile.json`, `environments/local-dev.md`, and
`agents/fullstack-specialist.md` are the project's setup. If `profile.id` is still `customize-me`,
stop and run `/onboard` — do not invent repos, ticket prefixes, or a start command. After those
files are filled, this command is **automatic**: read the profile, fetch the ticket, plan, and
build. Do not re-ask for stack, layout, or specialists that the profile already names.

Required outputs are defined once in [../../../_shared/ticket-artifacts.md](../../../_shared/ticket-artifacts.md)
and verified by the step 8 gate. Write each file at the step that produces it, not in a batch at the end.

## Invocation

```text
/start-ticket <TICKET-ID> bug|feature|spike|refactor [--worktree]
```

Ask for the ticket id and work type if either is missing. Use `profile.ticketPrefix` (not a
hardcoded prefix). A ticket-system type that names a pre-release defect maps to work type `bug`.

## Load map

Load each row at the step that needs it — nothing else, and not all at intake. An `#anchor` loads
only that heading's section.

| Doc | When | Why |
|---|---|---|
| [../references/ticket-intake-generic.md](../references/ticket-intake-generic.md) | always | Step 1 fetch and the start gate |
| [../../ticket-router/SKILL.md](../../ticket-router/SKILL.md) | always | Step 3 manifest, docSet, prior-ticket search |
| [../../../_shared/ticket-plan-output.md](../../../_shared/ticket-plan-output.md) | always | Plan structure, digest, final message |
| [../references/bug-fix.md](../references/bug-fix.md) | always | Work-type template; feature and refactor load `feature-plan.md`, spike loads `tech-spike.md` instead |
| [../../../_shared/engineering-decisions.md](../../../_shared/engineering-decisions.md) | always | Engineering Decisions shape and the open-decision gate |
| [../../../_shared/model-routing.md#roles](../../../_shared/model-routing.md#roles) | always | Plan tier and lane roles |
| [../../../_shared/model-routing.md#difficulty-rubric](../../../_shared/model-routing.md#difficulty-rubric) | always | `[low]`/`[med]`/`[high]` step tags |
| [../../../_shared/subagent-functions.md#calling-convention](../../../_shared/subagent-functions.md#calling-convention) | always | Step 5 dispatch packet shape |
| [../../../_shared/subagent-functions.md#explore-reporepo-question---findings](../../../_shared/subagent-functions.md#explore-reporepo-question---findings) | always | Step 5 scope seed |
| [../../../_shared/subagent-functions.md#why-reporepo-files---history](../../../_shared/subagent-functions.md#why-reporepo-files---history) | if-bug-regression | Step 5 why lane (used to work, broke recently) |
| [../../../_shared/subagent-functions.md#branch-setuprepo-ticket---branch-status](../../../_shared/subagent-functions.md#branch-setuprepo-ticket---branch-status) | always | Step 5 branch prep (not investigate) |
| [../../../_shared/severity-and-output.md#chat-output-budget](../../../_shared/severity-and-output.md#chat-output-budget) | always | Step 10 message budget |
| [../references/worktree-handoff.md](../references/worktree-handoff.md) | worktree | Steps 4, 8, 10 in worktree mode |
| [../../../_shared/cross-repo-workflow.md](../../../_shared/cross-repo-workflow.md) | if-multi-repo | Cross-repo order before the plan |
| [../../ticket-router/references/closeout-search.md](../../ticket-router/references/closeout-search.md) | on-failure | Only when `Search-CloseoutMemory.ps1` fails |

The manifest's `docSet` adds the conditional slices (ADR policy, environment card, test
verification) — load those at the step that uses them.

## Mode

Ask where the branch is created **before** step 3 writes `mode` — but only when there is a choice.
`profile.defaultMode` never answers it.

- **A spike** never asks: record `mode: investigate`; do not create or check out `<ticket>`.
- **`profile.worktreeSupported` is not true:** there is one place to work. Record `mode: branch`,
  say so, and do not ask. `--worktree` is refused with the same line.
- **Otherwise** `ask-user` ([harness-verbs](../../../_shared/harness-verbs.md)), two options: **main
  tree** (branch `<ticket>` in the clones at `profile.repos[].path`) or **worktree** (the root
  `Resolve-TicketRoot.ps1` returns). Skip the question only when this same user message passes
  `--worktree` or says main tree / branch mode.

If a clone is already on another ticket branch, name that branch in the question; do not switch it,
and do not leave this ticket's edits there. Main tree means the profile repos are the work tree: one
ticket in flight per repo, stash (with a descriptive message) before any branch switch. Later
commands resolve the mode with `Resolve-TicketRoot.ps1`.

## Workflow

0. **Load `profile.json` (one Read).** If `id` is `customize-me` (or `displayName` is still
   `My project`), run `/onboard` and stop. Otherwise treat `repos`, `ticketSystem`, `ticketPrefix`,
   `specialists`, `stacks.services`, `baseBranchDefault`, and `worktreeSupported` as already decided.

1. **Fetch ticket context** → `manifest.ticket`
   - Per [../references/ticket-intake-generic.md](../references/ticket-intake-generic.md) for
     `profile.ticketSystem` (`none`, `github-issues`, or a custom file next to it).
   - At most **two** fetches ([../../../_shared/runtime-verify.md](../../../_shared/runtime-verify.md)).
     Both fail: stop; the user re-authenticates and re-invokes. No polling.
   - Map only `title`, `type`, `state`, `priority` (`area` if the tracker has it); persist no ticket
     JSON. The plan carries description, repro, and AC.

2. **Start gate**
   - `none`: title + acceptance criteria present. `github-issues`: title and body non-empty.
   - Custom tracker overlay: that adapter's required-field gate if the file exists; otherwise skip
     the transition and note the state.

3. **Classify** → `<ticket>-manifest.json`
   - Run the router and write the manifest **now**, before any branch or provisioning, with
     `startedAtUtc` and `mode` — a late manifest loses the session clock.
   - **Reopen** (manifest has `completedAtUtc`): set `reopenedAtUtc` to now and `reclosedAtUtc` to
     `null`; never overwrite `startedAtUtc` or `completedAtUtc`. Then the short retrospective in
     [../../complete-task/references/task-retrospective.md](../../complete-task/references/task-retrospective.md)
     (After PR feedback, or on reopen). Do not write the first ledger row here.
   - **Resume a parked ticket** (manifest has `parkedAtUtc`: it stopped at "needs more info" or was
     closed early, via `Park-Ticket.ps1`): run `scripts/ticket/Resume-Ticket.ps1 -Ticket <key>`.
     It opens a `resume` span at now so the idle gap is excluded and clears the park stamps; never
     overwrite `startedAtUtc`. The final `/complete-task` close sums every span.
   - Ambiguous repos or integration after the profile list: ask before provisioning.

4. **Worktree only** — provision per [../references/worktree-handoff.md](../references/worktree-handoff.md#provision-step-4).
   Skip in branch and investigate mode.

5. **Fan-out (one parallel batch)** once `affectedRepos` is known:
   - `branch-setup` per affected local repo, with the path from `Resolve-TicketRoot.ps1`. Base branch
     is `profile.baseBranchDefault`. It owns fetch, base freshness, and resume-vs-fresh; read only its
     compact status. Not in investigate mode.
   - `explore-repo` per affected local repo: title + one AC/repro clause, `thoroughness: quick`.
     Skip when there is one local repo **and** the ticket names the file.
   - Bug + **used to work:** `why-repo` per repo with those `keyFiles` (cap 8). Skip
     `why skipped: never worked` or `why skipped: no keyFiles`. Do not guess regression vs
     never-worked — confirm or ask at the bug-fix symptom gate.
   - Prior-ticket search exactly as the router's [Prior closeouts](../../ticket-router/SKILL.md#prior-closeouts) rule says.
   - **Parent checks packets:** drop empty/off-topic; keep contradictions (comment vs statement, a
     shared or protected type as true owner) as Engineering Decisions candidates; never dump
     `keyFiles` raw.
   - Bug + **used to work:** `why-repo` per repo with those `keyFiles` (cap 8). Skip
     `why skipped: never worked` or `why skipped: no keyFiles`. Do not guess regression vs
     never-worked — confirm or ask at the bug-fix symptom gate.
   - Not in investigate mode: **local ticket branch exists but origin does not** → default is a
     rejected or unmerged PR; confirm with the tracker, then recreate from latest
     `origin/<baseBranch>` (stash or cherry-pick what you need; never merge base into the old
     lineage). **Both exist** → check out, fast-forward from `origin/<ticket>`, merge
     `origin/<baseBranch>`.
   - After `branch-setup` returns, start the overlay's `Initialize-TicketRuntime.ps1` (under
     `scripts/runtime/`) **in the background** when it exists; otherwise skip (`/start-stack`
     starts the app).

6. **Draft in plan mode — do not persist yet**
   - `enter-plan` automatically (pre-approved). Plan tier is deep; below deep without engineering
     mode, remind the user once; with engineering mode, draft through the deep planner lane.
   - Seed scope from the step 5 packets; do not re-dispatch `explore-repo` or `why-repo` or run a broad Grep.
   - Shape: the work-type template (bug, feature, refactor → `feature-plan.md` Refactor section,
     spike). Cross-repo or unclear scope: plan the dependency order first.
   - Structure per [../../../_shared/ticket-plan-output.md](../../../_shared/ticket-plan-output.md):
     Plan Digest, then **Engineering Decisions** ([../../../_shared/engineering-decisions.md](../../../_shared/engineering-decisions.md))
     before a tagged Work Plan. A `[high]` step needs the architect result or `architect skipped: <reason>`.
     Each `priorFindings` id is named there, with what it changed or `lesson unchanged: <id> — <why>`.
   - **Open decisions stop the plan.** An unresolved AC, ADR, shared-owner, or extra-repo call →
     `ask-user` and wait. Never draft or persist TBD, "resolve during implement", or an invented
     default. Editing a shared owner is never the default.
   - **Asked to skip the plan** ("no plan", "just code it", "skip Engineering Decisions"): write a
     short plan instead of none. Plan Digest, Engineering Decisions (`None — <why>` is enough for a
     small item), and a tagged Work Plan of only the real steps. Say once why in one line:
     `/implement`, `/review-changes` and `/complete-task` read the file, and close fails without
     it. Then persist and gate it like any plan. A "go" with the request is the approval. A short
     plan never skips step 3: the manifest still comes from ticket-router, in its documented shape.
   - Revise in the plan-mode conversation; re-emit only the changed section, never the whole plan.
   - Features and refactors: clarify batch and consistency report per `feature-plan.md`; the draft is
     not ready while a list is open unless the user accepts the item as out of scope.

7. **Persist on approval** → `<ticket>-<type>-plan.md`
   - Approval is an explicit chat statement ("approved", "build it", "go"); ambiguous → ask once.
   - Write the **exact approved text**. Persist even in branch mode — `/complete-task` and a resumed
     `/implement` are new chats that read the file. A later change: re-approve and overwrite.

8. **Gate** — `.\.cursor\scripts\ticket\Assert-TicketArtifacts.ps1 -Ticket <ticket> -Phase start`.
   `FAIL` = not finished: write the missing piece and re-run. If step 5 started a runtime script,
   wait for it now (not in investigate mode); it never starts the app or a browser. In branch mode,
   confirm every affected repo is on `<ticket>`. Worktree detail:
   [../references/worktree-handoff.md](../references/worktree-handoff.md#runtime-heal-step-8).

9. **Branch mode: build here.** Worktree: skip to step 10. Investigate: run the spike Work Plan
   read-only (no product edits, no branch) until the [../references/tech-spike.md](../references/tech-spike.md)
   outcome text is ready for `/complete-task`.
   - `exit-plan` first; do not report `step N/M done` before leaving plan mode.
   - Follow steps 3–7 of [../../implement/playbooks/implement.md](../../implement/playbooks/implement.md):
     execute in order, log Deviations **before** `step N/M done`, run scoped tests, converge, stop for review.
   - Do not re-run the router, re-fetch the ticket, or re-read the plan docs — they are in this chat.
   - Context short: `report-context` with `-Phase start`, then tell the user to start a fresh chat
     with `/implement <ticket>` and which step was reached.

10. **Final message** (budget: [../../../_shared/severity-and-output.md](../../../_shared/severity-and-output.md#chat-output-budget))
    - **Branch:** startup line, the `implement.md` step 6 summary, then:

      ```powershell
      .\.cursor\scripts\ticket\Set-TicketCtxPct.ps1 -Ticket <ticket> -Phase start
      .\.cursor\scripts\ticket\Set-TicketLanes.ps1 -Ticket <ticket> -Lanes "<fN/sN/dN inline:dN, or off>"
      ```

      `-Lanes off` without engineering mode; otherwise count fast/standard/deep dispatches and deep
      steps run inline (`f2/s1/d0 inline:d3`; a discarded lane that ran inline counts inline). Then:
      stage for review, `/review-changes` in a **new chat**, then `/complete-task` in another. Its
      first line is `report-context` (no `-Percent`; never estimate).
    - **Worktree:** [../references/worktree-handoff.md](../references/worktree-handoff.md#final-message-step-10).
    - **Investigate:** startup line, the outcome text, then `/complete-task` in a new chat.

## Guardrails

- No commit, push, PR, or closeout from this command; no broad tracker search, and no writes to
  historical or unrelated tickets.
- Approval is a chat statement, never an IDE button; persist only after it, and in worktree mode never build in this chat.
- `Assert-TicketArtifacts -Phase start` passes before the final message; prose never overrides a `FAIL`.
- A user cannot waive the plan, only shrink it (step 6): every ticket leaves a manifest and a plan file.
- No dev server, browser, or CDP here (`/start-stack`); subagents are read-only; load only Load map and `docSet` rows, at the step that needs them.
