---
name: ticket-artifacts
description: The one contract for per-ticket files — what each phase must produce, and the gate that verifies it. Authoritative over any prose restatement elsewhere.
keywords: artifacts, manifest, plan file, ledger, gate, Assert-TicketArtifacts, branch mode, worktree mode, scratch, plans folder, reviewReady, stackSmoke
---

# Ticket Artifacts Contract

Single source of truth for the ticket-keyed files under `plans/`. When any command,
skill, or doc appears to restate a rule from this file, **this file wins** — fix the other doc
rather than following it.

## Durable vs scratch

| Location | Holds | Committed |
|---|---|---|
| `plans/` | Ticket-keyed artifacts for the user who ran the ticket — the manifest, the approved plan, and `ticket-ledger.md` | **Never** (gitignored, user-local) |
| `plans/examples/` | One sanitized example per artifact shape, plus `ticket-ledger.example.md` | Yes |
| `plans/closeout-index.md` | Lessons shared by the team | Yes |
| `plans/evidence/<ticket>/` | Verify evidence copy (`<repo>-verify.trx`), beside the manifest: under `apps/<id>/plans/` when an app is active | No (user-local); pruned 14 days after close |
| `tmp/tickets/` | Per-ticket scratch — commit/PR-body drafts, temporary exports | No (gitignored); pruned after 14 days |

Ticket files are durable on the user's machine, not in git. **Hard stop:** the `user-plans` check
in `Assert-AgenticFlow.ps1` (CI, pre-push, `/doctor`), the commit hook, and
`hooks/git-hooks/pre-commit` fail any tracked or staged `plans/` path outside `README.md`,
`closeout-index.md`, `workflow-template-plan.md`, and `examples/`. Editing those is the only
allowed change to `plans/`. Moving computers: copy your `plans/` folder yourself.

Nothing regenerable from the tracker or git belongs in `plans/`; a one-off draft goes in `tmp/tickets/`. `tmp/`
is swept at 14 days (after close, daily at session start): one fixed name per purpose, overwritten.

## Ticket mode

Every ticket runs in one mode, recorded as the manifest's `mode`:

- **`branch`** — branches in the canonical clones. Planning and implementation happen in **one
  chat**. Chosen only when the user picks the main tree, or the same message already says main tree
  / branch mode.
- **`worktree`** — repos mirrored under a per-ticket worktree root, planning and implementation in
  **separate chats/windows**. Chosen when the user picks a worktree, or the invocation passes
  `--worktree`.
- **`investigate`** — spike only. Read the canonical clones as they are. No ticket branch and no
  worktree.

`/start-ticket` asks branch vs worktree before writing `mode`, except a spike, which records
`investigate` without asking. `profile.defaultMode` does not skip that question.

Never hardcode a path for either. Ask:

```powershell
scripts/ticket/Resolve-TicketRoot.ps1 -Ticket <ticket> -Json
```

It returns `{ ticket, mode, modeSource, root, rootExists, canonicalRoot, worktreeRoot, repos[] }`.
The manifest's `mode` wins. A leftover populated worktree folder does **not** flip default branch
mode to worktree. `rootExists: false` means **stop** — do not work in the other tree.

## Phase outputs

| Phase | Command | Must exist when the command reports success |
|---|---|---|
| `start` | [start-ticket](../skills/start-ticket/SKILL.md) | `<ticket>-manifest.json` (with `mode`, non-null `startedAtUtc`, and `ticket` object), `<ticket>-<type>-plan.md` |
| `implement` | [implement](../skills/implement/SKILL.md) | inputs above must already exist; no new required output |
| `close` | [complete-task](../skills/complete-task/SKILL.md) | manifest close timestamp, one `<ticket>` row in `plans/ticket-ledger.md` |

`<type>` is the manifest `workType` (`bug`, `feature`, `spike`, `refactor`).

## The gate

Do not self-assess this contract in prose. Run it:

```powershell
scripts/ticket/Assert-TicketArtifacts.ps1 -Ticket <ticket> -Phase start
```

- `start-ticket` runs it with `-Phase start` as its **last artifact action** before the final
  message. A `FAIL` means the command is not finished — write the missing file, then re-run. A
  runtime warmup script, when the profile has one, is started after branch-setup and awaited after
  the start gate; it is not an artifact.
- `implement` runs it with `-Phase implement` as its **first action**. A `FAIL` stops the chat and
  reports what start-ticket skipped; it does not silently re-plan around the gap.
- Any chat that loads ticket state uses `-Phase implement` as its **load-time** gate — including
  `/complete-task`. Do **not** run `-Phase close` at chat start: the close timestamp and the ledger
  row are written *during* `complete-task`, so a load-time close gate always fails.
- `complete-task` runs `-Phase close` inside the retrospective, as the last step of `scripts/ticket/Close-Ticket.ps1` (close stamp, hours, ctx, ledger row, then the gate), after the user approved.
  A non-spike close also requires, for each local affected repo:
  - `verify.repos.<repo>` on the manifest with boolean `pass: true` and `evidence` (the test-output file hash, `.trx` counts; `scripts/ticket/Set-VerifyReceipt.ps1 -Evidence`), taken on the work that ships (its `headSha` and fingerprint follow the review stamp's rule, so tests run before a later fix fail);
  - a `reviewReady` entry (`scripts/ticket/Set-ReviewReady.ps1`) with verdict Ready, Ready with fixes, or
    No change. When the repo path exists, the reviewed work must still be there: the staged diff,
    or the first-parent commits since the stamp's `headSha`. A later merge of the base branch is
    ignored; any other commit after the review fails, so review again and re-stamp. Conflict edits
    inside that merge commit are not checked.

  A spike skips both, so a spike whose tracker item is a Bug, Issue, story, or Feature fails.
  `stackSmoke` is optional unless an affected repo has profile layer `frontend` and the change
  touches a profile `uiGlobs` file type. Then close fails unless effective status is `passed` on
  the current work. `-Phase prepush` runs these work checks alone, before commit and push.

Exit code `0` = pass, `1` = fail. `-Json` returns `{ phase, ticket, mode, pass, missing[], found[] }`.

## File reference

| File | Written by | Purpose |
|---|---|---|
| `<ticket>-manifest.json` | `ticket-router` skill, then the stamp scripts | **The one record per ticket.** Start and close check it against `scripts/ticket/manifest.schema.json` (extra fields allowed; a spike `parallelPlan` slot must be empty). Classification **and** session state: `mode`, `workType`, `ticket` (title/type/state/area/priority), `affectedRepos`, `integration`, `environmentCard`, `specialists`, `adrIndex`, `baseBranch`, `priorFindings`, `docSet`, `parallelPlan`, `worktreeRoot`, session timestamps, plus later `reviewReady` (verdict, `headSha`, fingerprint, and up to ten Blocker/Major `findings` per repo, from `Set-ReviewReady.ps1`), `verify` (per-repo `pass`, `tests`, `sonar`, `failing`, `reason`, and the work it ran on: `headSha`, `mode`, `fingerprint`, from `Set-VerifyReceipt.ps1`), `feedback` (PRs, analysis gate, triaged items, from `Set-TicketFeedback.ps1`), `stackSmoke` (user-confirmed Drive; a close gate when an affected repo has profile layer `frontend`), `ctxPct` (`start` / `review` / `close`, with `ctxPctSource` measured or reported), and `lanes`. Each `ctxPct` is the hook-measured value or blank; close fails only on a present value outside 0–100. |
| `<ticket>-<type>-plan.md` | start-ticket | The approved plan. Opens with a `## Plan Digest` and carries an **Engineering Decisions** section before the Work Plan (structure in [ticket-plan-output.md](ticket-plan-output.md), shape in [engineering-decisions.md](engineering-decisions.md)). The `-Phase start` gate checks both headings and rejects a plan still carrying `TBD` or "resolve during implement". The only plan `implement` follows. |
| `plans/ticket-ledger.md` | `scripts/ticket/Update-TicketLedger.ps1` | One row per closed ticket: type, close date, mode, hours, points, scorecard, `CtxS%` / `CtxR%` / `Ctx%` (measured, `~NN` when the agent typed it, blank when nothing was measured), `Lanes`, and `Epoch`. Do not invent rows for older tickets. The summary states CtxS coverage on recent scored branch rows. |
| `plans/closeout-index.md` | complete-task | One row per durable lesson. The retrieval surface for `priorFindings` ([closeout-search.md](../skills/ticket-router/references/closeout-search.md)). |
| `<ticket>-closeout.md` | complete-task | **Only when a retrospective earns a page** ([task-retrospective.md](../skills/complete-task/references/task-retrospective.md)). Not required by any gate. |

Keep these small. Subagent packets land on the manifest through the stamp scripts, never as their own
files; do not paste raw JSON into chat. Older side files (`<ticket>-verify.json`, `<ticket>-review.md`,
`<ticket>-feedback.md`) are not read; delete them.

## Session timestamps

`startedAtUtc`, `completedAtUtc`, `reopenedAtUtc`, `reclosedAtUtc`, and `timezone` live **on the
manifest**. Field semantics and the hours math stay in
[session-time-tracking.md](../skills/complete-task/references/session-time-tracking.md). A ticket that stops before `/complete-task` adds `parkedAtUtc`, `parkedState`, `parkedOutcome`, `parkedHours` and a closed span (`Park-Ticket.ps1`); `Resume-Ticket.ps1` moves them to `parkHistory`; `-Phase park` checks the stamp, no open span, and the one ledger row.

## Handoff between chats

**Branch mode** has no handoff — `/start-ticket` plans and then builds in the same chat.

**Worktree mode** ends `/start-ticket` with these lines as **chat text**, not a file. The user opens
a new chat rooted at the ticket worktree ([how, per IDE](../adapters/README.md#open-a-ticket-worktree)) and pastes them:

```
/implement <ticket>

Approved plan: plans/<ticket>-<type>-plan.md
Worktree: <absolute worktree path>
Constraint: <one precise line, or omit this line>
```

The implementation window loads the manifest, plan, and doc set itself — the paste carries a
pointer, not a copy. Do not inline the Work Plan steps, and do not tell the user to `@` or attach a
plan file (that starts a review, not a build). This paste is the only handoff. Worktree layout is an
overlay blank — fill [../environments/worktrees.md](../environments/worktrees.md) if
`profile.worktreeSupported`.

## Rules

- Write each phase's files **as they are produced**, not batched at the end of the command.
- The manifest is written immediately after ticket intake, before branch setup — it carries
  `startedAtUtc`, so a lost manifest loses the session clock.
- Never overwrite `startedAtUtc` after the first write.
- One ledger row per ticket; a reopen updates that row in place (re-run `Update-TicketLedger.ps1`).
- Never hand-edit `plans/ticket-ledger.md` — the script owns its format.
