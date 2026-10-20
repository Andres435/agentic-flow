---
name: prep-pr
description: Prepare changed repositories for PR submission. Use when generating commit messages, PR descriptions, testing summaries, SonarQube notes, confidence summaries, or cross-repo PR references.
keywords: PR, commit message, PR description, ADO write-back, approval package, Code Review transition
disable-model-invocation: true
---

# Prepare Pull Requests

Prepare all changed repos for PR submission.

## Modes

- **Draft mode** (default): inventory changes, draft commit messages and PR descriptions, build the approval package, and wait for user approval.
- **Execute-approved-package mode**: use only when the user already approved the package from [../../complete-task/SKILL.md](../../complete-task/SKILL.md). Do not rebuild a second approval package. Re-verify staged files still match the approved package, then execute only the approved commits, pushes, PR creations, tracker writes, and state transitions.

## First: Gather Input

Before starting, ask the user for the **Ticket Number** if not already provided in this message (e.g., `TICKET-42`).

For tracker items, follow `profile.ticketSystem`. Load a custom adapter only if it exists
next to `ticket-intake-generic.md`. Do not ask for hours if the manifest has session timestamps.

1. Re-fetch the active ticket before drafting commit or PR text (skip when `ticketSystem` is `none`).
2. Use the fetched title/type/state as source of truth.
3. Run `./scripts/ticket/Get-SessionHours.ps1 -Ticket <ticket>` and use its hours and point bucket ([../../complete-task/references/session-time-tracking.md](../../complete-task/references/session-time-tracking.md)). Do not recompute them.
4. Keep tracker writes scoped to this ticket id.

## Instructions

Read `.cursor/plans/<ticket>-manifest.json` (if present) and use its `affectedRepos` as the
authoritative repo list. Resolve where to run `git` — do not assume either tree:

```powershell
.\.cursor\scripts\ticket\Resolve-TicketRoot.ps1 -Ticket <ticket> -Json
```

Run every `git` command in the `repos[].path` it returns (the canonical clone in `branch` mode, the
ticket worktree in `worktree` mode). If `rootExists` is false, stop and report it.

1. **Inventory Changes**: For each affected repo with uncommitted, staged, or untracked changes:
   - Run `git status` to see all changes
   - Run `git diff --staged --stat` for staged changes
   - Run `git diff --stat` for unstaged changes
   - List staged, unstaged, and untracked files separately
   - Treat staged changes as the commit candidate; include unstaged/untracked changes as awareness notes so unrelated work is not committed accidentally

2. **Generate Commit Messages** for each repo:
   - Reference the ticket id in the subject: `feat|fix|refactor|docs(scope): description [<ticket>]`;
     subject under 72 characters; pick the type from the ticket and the actual changes
   - **Body:** summarize **total work done** across the change set (what changed and why), one
     cohesive summary
   - **Bugs:** root cause goes on the **ticket** (when the tracker has a field), not in the commit
   - QA notes, hours, and story points belong on the ticket, not in the commit or PR body
   - Do not include unstaged/untracked files unless the user explicitly approves staging them

3. **Generate PR Descriptions** for each repo:
   - **Title:** `<ticket>: <title>` (exact format — not conventional-commit style)
   - **Summary:** What changed and why (2-3 sentences). Do not paste a full changelog, and do not append a generated-by trailer.
   - **Changes:** Bullet list of specific modifications
   - **Ticket:** link only — hours/points stay on the tracker
   - **Static analysis:** note any compliance considerations (optional; only when the project has it)
   - **Confidence:** carry forward the Overall rating from the latest Confidence Score
     ([../../complete-task/references/confidence-score.md](../../complete-task/references/confidence-score.md))
   - **Related PRs:** cross-reference PRs in other repos affected by the same ticket
   - **Deployment / ops checklist** (when applicable): items outside the code diff — config,
     secrets, pipeline, handoffs, manual smoke in a deployed environment
   - **Code checklist** (in-repo only): tests added/updated · no new static-analysis violations in
     touched files · `review-changes` completed for the change set · Confidence Score recorded

4. **Tracker notes** (`profile.ticketSystem` not `none`):
   - Update only this ticket, with fields the tracker actually has: root cause (bugs), QA notes,
     acceptance-criteria coverage (features), outcome and follow-ups (spikes), and hours → story
     points from session-time-tracking. Never write actual points for a spike, even when it ships a
     product change; its hours stay local.
   - Never fabricate required values. Ask only for fields that cannot be derived, or for hours when
     the manifest has no session timestamps.
   - If the tracker blocks a state transition on empty required fields, report the blocking fields
     and leave the ticket in its current state; the PR still stands.
   - Skip this section when `ticketSystem` is `none`.

5. **Approval Package**:
   - Staged files to commit · unstaged/untracked awareness · files that would be staged if the user
     approves including them · commit messages (summary only) · PR titles (`<ticket>: <title>`) ·
     PR descriptions · tracker updates and required-field gaps · hours and converted points · target
     tracker state · optional PR-to-ticket link.
   - If unstaged work should be committed, ask the user to stage it or approve including it.
   - Wait for explicit approval; nothing is submitted before it.

6. **Create PR**:
   - Do not commit, push, create a PR, link a PR, or write the tracker without approval. In
     execute-approved-package mode, do not rebuild the package; execute only the approved actions.
   - **Before the first commit:** run `.\.cursor\scripts\ticket\Assert-TicketArtifacts.ps1 -Ticket <ticket> -Phase prepush`.
     On `FAIL`, commit nothing and report what it names (a missing verify receipt, a stale or
     open-Major review stamp, a frontend Drive not confirmed). The push hook runs the same check
     on a branch that names the ticket, so skipping it here only moves the failure to the push.
   - **Commit message trailer:** with the work staged, run `.\.cursor\scripts\ticket\Get-AgenticProof.ps1 -Ticket <ticket> -Repo <repo>` and add its one line as the last trailer of the commit message ([agentic-proof](../../../_shared/agentic-proof.md)). It refuses when the verify receipt or review stamp no longer matches the staged work; fix that first. After the commit, `Assert-AgenticProof.ps1 -RepoPath <repo>` should print `[PASS]`.
   - Before push in each repo: `git fetch origin`, merge `origin/<baseBranch>`
     (`profile.baseBranchDefault`). Resolve conflicts and include the merge commit; do not open or
     update a PR against a branch that is behind base.
   - After the PR exists, apply the tracker's "in review" state if the adapter defines one.
   - **Close the ticket.** When this chat ran `/complete-task`, return to its step 6 (retrospective,
     ledger row, `-Phase close`). When `/prep-pr` runs in a fresh chat, nobody else will: run
     [../../complete-task/references/task-retrospective.md](../../complete-task/references/task-retrospective.md)
     here (its section 4 ends with one `Close-Ticket.ps1` call: close stamp, ledger row, `-Phase close`
     gate), exactly as complete-task step 6 does. A ticket with a PR and no ledger row is a close that never ran.

## Cross-Repo PR Matrix

When the ticket spans multiple repositories, include this block in the approval package:

| Repository | Branch | PR title | PR link | Depends on |
|---|---|---|---|---|
| `<repo>` | `<ticket>` | `<ticket>: <title>` | TBD | `<upstream repo or none>` |
