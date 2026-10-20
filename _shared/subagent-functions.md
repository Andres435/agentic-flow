---
name: subagent-functions
description: Reusable subagent "function" contracts with fixed inputs and compact outputs, so the orchestrator can fan out token-heavy read work and keep its own context small. Use when start-ticket, complete-task, review-changes, address-pr-comments, or peer-review dispatch parallel work. implement.md dispatches the manifest's specialists[] directly per step instead — a different fan-out shape (per-step domain depth, not per-repo read work) — so it is not a consumer of these specific functions.
keywords: subagent functions, explore-repo, why-repo, branch-setup, verify-repo, review-diff, pr-feedback-fetch, peer-review-pr, fan-out, compact return
---

# Subagent Functions

These are **agentic functions**: reusable subagent contracts with a fixed input shape and a
strict **compact** return shape. The orchestrator calls them like functions and only sees the small
result, so its own context window stays lean (the subagent burns its own window on the heavy reads).

## Why

- **Parallelism:** independent repos/areas run at the same time (see `parallelPlan`, set by the
  `ticket-router` skill).
- **Token discipline:** big diffs, tracker/static-analysis/PR JSON, and broad searches are read
  inside the subagent; only the distilled packet returns.

## Calling Convention

- `dispatch(function, tier)` ([harness-verbs.md](harness-verbs.md)). Each function names a
  **role**; the IDE adapter maps the role to its subagent type and the tier to a model
  ([../adapters/README.md](../adapters/README.md)). Launch independent calls in a single batch
  (one message, multiple tool calls) to run them concurrently.
- **Model:** always pass `model`. Each function's tier is in [model-routing.md](model-routing.md#roles).
  Never inherit the chat model. A slice too large for its tier is split, not upsized.
- Always pass: the **ticket id**, the **resolved path** for the target repo, and the exact
  question/scope. Subagents do not see the parent conversation. Get the path from
  `scripts/ticket/Resolve-TicketRoot.ps1 -Ticket <ticket> -Json` — it returns `repos[].path` for the
  ticket's mode (canonical clone in branch mode; the worktree path only when `mode` is worktree).
  Never construct a worktree path by hand. `peer-review-pr` uses sibling clones from
  [profile.json](../profile.json), not `Resolve-TicketRoot`.
- A packet that later steps reuse goes on the ticket manifest, written by the **orchestrator**
  through the stamp scripts (`Set-VerifyReceipt`, `Set-ReviewReady`, `Set-TicketFeedback`), per
  [ticket-artifacts](ticket-artifacts.md). Never write a side file under `plans/`; reload from the
  manifest instead of re-fetching.

## Global Guardrails

- **Read/implement only inside the given path.** A function never touches another ticket's worktree,
  and never a tree it was not handed — in branch mode the canonical clone *is* the given path, so the
  rule is "stay where you were sent".
- **No side effects outside the working tree.** Subagent functions never commit, push, create PRs,
  or write the tracker. Those stay on the single human-approved orchestrator path
  (`prep-pr` / `complete-task` / `peer-review`).
- Return the compact shape only. Do not echo full diffs, full JSON, or file dumps to the parent.
- Every packet's first line is `model: <what the subagent runs on>`. The parent discards a packet
  that reports an automatic choice or a substitute ([model-routing.md](model-routing.md#dispatch-rules) rule 8).

## `explore-repo(repo, question) -> findings`

- **Role:** read-only explorer. **Use:** where X lives / how Y works. **Inputs:** `repo`, `repoPath`, `question`, optional `thoroughness`.
- **Returns (compact):**
  ```
  repo: <name>
  answer: <=5 sentences
  keyFiles: [path:line, ...]         # <=8
  entryPoints: [symbol/file, ...]    # <=5
  risks: [one-liners]                # optional
  ```

## `why-repo(repo, files) -> history`

- **Role:** shell (git). **Regressions only** (used to work). Skip when never worked. Not part of `explore-repo`.
- **Inputs:** `repo`, `repoPath`, explore `keyFiles` (cap 8).
- **Does:** `git log -n 5`, `--grep=revert -20`, `--diff-filter=D --summary` on those files; extract ticket ids (`profile.ticketPrefix`, common forms). No tracker MCP in the lane.
- **Returns:** `model`, `repo`, `files` [path @ sha, date] <=8, `tickets` <=5, `why` <=3 sentences, optional `deleted`. Parent looks up `tickets[]` read-only when `profile.ticketSystem` is not `none`; never writes historical items.

## `branch-setup(repo, ticket) -> {branch, status}`

- **Role:** shell (git)
- **Use:** per-repo git prep during start-ticket (parallel across independent repos).
- **Inputs:** `repo`, `repoPath`, `ticket`, `baseBranch` (default `profile.baseBranchDefault`).
- **Does:** `fetch origin`; resolve resume vs fresh. Local ticket branch without origin → default
  reopen: recreate from latest base, do not merge base into the old lineage. Worktree creation is a
  profile script if present; this function reports the branch decision. If checkout fails because
  the branch is already checked out elsewhere, run `git worktree list` and report that path.
- **Returns (compact):**
  ```
  repo: <name>
  branch: <ticket>
  action: created-from-base | attached-existing | recreated-reopen | skipped-not-local
  ahead/behind: +a/-b vs origin/<base>
  notes: <=2 lines (conflicts, stash, missing remote)
  ```
- **Guardrail:** never force-apply an old pre-merge stash to a recreated branch; stop and report.

## `verify-repo(repo, testFilter) -> {pass, failing, sonar}`

- **Role:** general-purpose (a stack specialist from `manifest.specialists[]` when the stack needs one).
- **Use:** scoped verification per repo at closeout (parallel, read-only).
- **Inputs:** `repo`, `repoPath`, `testFilter` (nearest fixture/project), `sonarKey` (static-analysis
  project key, or none).
- **Does:** run the **smallest** scoped tests first per [test-verification](test-verification.md)
  using the project's test runner. Query static analysis only when `sonarKey` is set. Repos without
  a key stay `sonar: skipped`.
- **Returns (compact):**
  ```
  repo: <name>
  tests: pass | fail | not-run(reason)
  failing: [FullyQualifiedName -> one-line reason]   # <=10
  sonar: OK | ERROR(condition) | skipped(not enrolled) | skipped(no key)
  evidence: <.trx or saved test output path>   # not for not-run
  ```
- **Parent records it:** the subagent writes evidence to one stable path per repo (`tmp/<ticket>-<repo>-verify.trx`, same name each run) and stays read-only. The parent runs `scripts/ticket/Set-VerifyReceipt.ps1`
  per packet with `-Evidence <evidence>` (`OK`→`ok`, `ERROR`→`error`, `skipped(...)`→`not-run`; `not-run` tests pass `-Reason`); it copies the file into `plans/evidence/<ticket>/`. `Assert-TicketArtifacts -Phase close` reads it.

## `review-diff(repo) -> findings`

- **Role:** `code-reviewer` (if the IDE rejects that type, use general-purpose with the code-reviewer prompt — do not skip the review).
- **Use:** staged-diff or pre-merge review per repo (parallel at closeout).
- **Inputs:** `repo`, `repoPath`, `mode` (staged | premerge), optional `branch`.
- **Does:** review per [review-protocol](review-protocol.md) and the report shape in
  [severity-and-output](severity-and-output.md). The parent names the diff: working-tree review is `git diff HEAD` on the candidate paths plus untracked candidates; pre-merge is the three-dot range. For very large
  diffs, chunk per file/module before reviewing to avoid context blowups. **Never runs a stamp
  script** (`Set-ReviewReady`, `Set-TicketCtxPct`): it returns findings and a verdict, and the
  calling chat stamps once for all repos.
- **Returns (compact):** the standard report shape from [severity-and-output](severity-and-output.md)
  (Blocker + Major by default) ending with a `Change-set understanding` Confidence Score.

## `pr-feedback-fetch(ticket) -> triagePacket`

- **Role:** general-purpose
- **Use:** gather + compact PR threads and CI/quality feedback for one ticket (parallel per PR).
- **Inputs:** `ticket`, optional explicit `prTargets[]`.
- **Does:** gather PR threads for this ticket (`gh` or the profile's tracker adapter); trimmed
  thread lists first, full thread only when needed. Writes nothing; do not dump raw JSON.
- **Returns (compact):** a JSON packet in the `manifest.feedback` shape (`prs`, `gate`, `items` with
  `kind`, `ref`, `status`, `file`, `ask`, `context`, `triage`) — see `scripts/ticket/Set-TicketFeedback.ps1`.
  The parent merges packets and records them with that script. No fixes applied.
- **Guardrail:** read-only. Never marks threads resolved or replies -- that stays on the approved
  path in `address-pr-comments`.

## `peer-review-pr(repo, pr) -> proposedComments`

- **Role:** `code-reviewer` (fallback general-purpose).
- **Use:** coworker PR peer review per PR. Complements any pipeline review bot.
- **Inputs:** `ticket`, `repo`, `repoPath` (sibling clone from [profile.json](../profile.json), or
  empty for tracker file reads only), `pullRequestId`, `sourceBranch`, `targetBranch`, compact
  existing-thread list (path:line | thread id | ask).
- **Does:** diff without checkout. Follow
  [checklist.md](../skills/peer-review/references/checklist.md) and
  [comment-voice.md](../skills/peer-review/references/comment-voice.md) before drafting.
  Skip duplicates. Cap 10.
- **Returns:** `repo`, `pr`, `proposed: [{id, path, line, why, comment}]`, `skippedDuplicates`.
- **Guardrail:** read-only; no severity labels. Parent `peer-review` posts after approval.
