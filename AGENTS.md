---
name: agents-index
description: Index of workspace agents and routing guidance for ticket work.
---

# Agents Index

**Looking for a doc? Grep [INDEX.md](INDEX.md) first.** One row per doc with its keywords; a gate
keeps it complete. Terms (mode, manifest, epoch, ctxPct, lanes, receipts): [_shared/glossary.md](_shared/glossary.md).

**Running scripts:** run the repo's own scripts or inline commands; never write a helper script to
temp or a scratchpad and run it, and edit files with the edit tools. New or changed scripts follow
[skills/script-authoring/SKILL.md](skills/script-authoring/SKILL.md) (agent: [agents/script-engineer.md](agents/script-engineer.md)); a throwaway goes in the gitignored `tmp/` here. If an application allowlist
guards the machine, see [MACHINE-SETUP.md](MACHINE-SETUP.md#application-allowlist).

Developer overview: [README.md](README.md). How to run tickets: [USER-MANUAL.md](USER-MANUAL.md).
What to customize first: [CUSTOMIZE.md](CUSTOMIZE.md). Before broad searching, check `profile.json`
for repo layout, `environments/` for setup, and the agents below for specialists. Scope searches to
the affected repo path from `scripts/ticket/Resolve-TicketRoot.ps1`.

**Model usage:** work runs on tiers — fast / standard / deep / frontier
([_shared/model-routing.md](_shared/model-routing.md)). Each IDE maps tiers, subagent roles, and its
`deepLane` in its adapter: [Cursor](adapters/cursor/model-usage.md),
[Cursor GPT chat](adapters/gpt/model-usage.md), [Claude Code](adapters/claude/model-usage.md),
[Antigravity](adapters/antigravity/model-usage.md), [Codex](adapters/codex/model-usage.md). IDE actions are neutral verbs —
[_shared/harness-verbs.md](_shared/harness-verbs.md). Chat counts per mode: [USER-MANUAL.md](USER-MANUAL.md).

**Engineering mode** (`/engineering-mode`, or the adapter's way to pin it) makes a chat an
orchestrator that routes each piece of work to its tier's model —
[skills/engineering-mode/SKILL.md](skills/engineering-mode/SKILL.md).

**Codex:** Codex has no `@` include, so read
[adapters/codex/model-usage.md](adapters/codex/model-usage.md) before any dispatch; it maps the tiers.

## Available Agents

> Add your specialist agents to `agents/`, list them in `profile.json` → `specialists`, and here.

- [agents/fullstack-specialist.md](agents/fullstack-specialist.md) — generic fullstack stub; replace with your stack.

## Subagent Functions (parallel, compact-return)

Dispatch reusable subagent "functions" instead of token-heavy reads in the orchestrator. Contracts:
[_shared/subagent-functions.md](_shared/subagent-functions.md).

- `explore-repo` — scope analysis per repo/area (read-only).
- `why-repo` — git blame/log on known files; regressions only (used to work). Skip when it never worked.
- `branch-setup` — per-repo git prep during start-ticket.
- `verify-repo` — scoped tests (+ static analysis when configured) per repo at closeout. The parent
  records each packet with `scripts/ticket/Set-VerifyReceipt.ps1`.
- `review-diff` — staged/pre-merge review per repo. The parent stamps `scripts/ticket/Set-ReviewReady.ps1`.
- `pr-feedback-fetch` — compact PR feedback per ticket.
- `peer-review-pr` — coworker PR comments; no tracker writes.

The [ticket-router](skills/ticket-router/SKILL.md) manifest's `parallelPlan` says which to fan out.
Subagent functions never commit, push, or write to the tracker.

## Routing Notes

- Run [skills/ticket-router/SKILL.md](skills/ticket-router/SKILL.md) first (from `/start-ticket`).
  It reads `profile.json` — repos, specialists, and `ticketSystem` come from there — and writes the
  manifest with `docSet`, `priorFindings`, and the parallel plan.
- **Ask main tree vs worktree** before creating a ticket branch, only when
  `profile.worktreeSupported` is true. A spike is `investigate` and never asks.
- Run [skills/ticket-context-load/SKILL.md](skills/ticket-context-load/SKILL.md) first in any
  **fresh** chat (`complete-task`, `review-changes`, `address-pr-comments`, and `implement` when
  resuming). Not in the `/start-ticket` chat that produced the state, and not for `/peer-review`.
- [_shared/ticket-artifacts.md](_shared/ticket-artifacts.md) is the single contract for which files
  each phase produces, checked by `scripts/ticket/Assert-TicketArtifacts.ps1`. It overrides prose.
- [_shared/severity-and-output.md](_shared/severity-and-output.md#chat-output-budget) caps each
  command's chat output. Link it rather than restating "be compact".
- When `profile.adrIndex` is set, ADRs are the source of truth: plans cite them and never re-decide
  ([_shared/adr-policy.md](_shared/adr-policy.md)).
- [skills/ticket-workflow/SKILL.md](skills/ticket-workflow/SKILL.md) is the lifecycle map; the
  command playbooks own the mechanics.
- [skills/environment-context/SKILL.md](skills/environment-context/SKILL.md) matches cards under
  `environments/` when a ticket names an integration or runtime setup.
- [skills/tdd-red-green-refactor/SKILL.md](skills/tdd-red-green-refactor/SKILL.md) for test-first
  work, regression tests before fixes, or characterization tests.
- [skills/review-changes/SKILL.md](skills/review-changes/SKILL.md) before PR preparation. Findings
  come from staged changes; unstaged and untracked work is awareness only.
- [skills/peer-review/SKILL.md](skills/peer-review/SKILL.md) reviews a **coworker's** PR: draft,
  wait for approval, then post.
- [skills/complete-task/SKILL.md](skills/complete-task/SKILL.md) only when the user invokes it. It
  ends with a retrospective that **asks** three questions; one ledger row is the only automatic output.

## Domain Router

| Work area | Route |
|---|---|
| Frontend + backend spanning features | [agents/fullstack-specialist.md](agents/fullstack-specialist.md) |
| Create or change a .ps1/.py script | [skills/script-authoring/SKILL.md](skills/script-authoring/SKILL.md) → [agents/script-engineer.md](agents/script-engineer.md) |
| Design a change that crosses a module or repo boundary | [skills/architect/SKILL.md](skills/architect/SKILL.md) |
| What could this change break (shared module, public API, schema) | [skills/blast-radius/SKILL.md](skills/blast-radius/SKILL.md) |
| _(add project-specific rows)_ | — |
