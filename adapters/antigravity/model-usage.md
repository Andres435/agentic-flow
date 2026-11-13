---
name: antigravity-model-usage
description: Model tiers (fast/standard/deep/frontier) mapped to Antigravity invoke_subagent for an Antigravity parent. The picked model is deep and stays inline.
---

# Antigravity Model Usage

**Status: probed 2026-11-12.** An Antigravity parent honored fast (`flash_lite`) and standard (`flash`).
On a free-tier account, basic models are active: `flash_lite` and `flash` respond from the Gemini Flash
family; `pro` substituted the session's selected model (Gemini 3.8 Flash, unhonored), so deep stays inline.
Antigravity context reporting is wired through the `Stop` lifecycle hook in [hooks/hooks.json](hooks/hooks.json).

Use this file when the parent session is Antigravity. Tiers and routing rules stay in
[_shared/model-routing.md](../../_shared/model-routing.md). Load this file from `AGENTS.md`. Deep is the
model selected for the session and stays inline. Do not ask for a different model.

## Tiers

Antigravity `invoke_subagent` takes `Model` (`flash_lite`, `flash`, `pro`, `inherit`), `Role`, and
`TypeName` (`research`, `self`). Copy each selector from the confirmed tool options. Do not invent an id.
`/doctor --lanes` from an Antigravity parent on 2026-11-12 recorded the probe below.

| Tier | `invoke_subagent` `Model` | Reasoning effort | Used for |
|---|---|---|---|
| `fast` | `flash_lite` | low | `[low]` steps; explore-repo, why-repo, branch-setup, pr-feedback-fetch, verify-repo |
| `standard` | `flash` | medium | `[med]` steps; review-diff, peer-review-pr, devops-investigate |
| `deep` | **The session's selected model, inline only** | the session's own effort | plans, `[high]` steps, second-opinion reviewer, architect deep candidate, blast-radius |
| `frontier` | a model the user names | only when the user asks | only when the user asks for it in this session |

**`deepLane: inline`** — deep and `[high]` run on the session's model. Never dispatched.

Every `invoke_subagent` passes `Model` from the tier. A lane whose first line names another family, or
nothing, is discarded. Never dispatch the deep tier. If the model cannot be told, ask the user to pick
one and do not name one.

## Subagent-function → `invoke_subagent` mapping

[`_shared/subagent-functions.md`](../../_shared/subagent-functions.md) names a role per function.
`dispatch` maps each to an `invoke_subagent` call:

| Function | `invoke_subagent` `TypeName` | `Role` | Tier | Notes |
|---|---|---|---|---|
| `explore-repo` | `research` | Repo Explorer | fast | Read-only codebase explorer. |
| `why-repo` | `self` | Repo History | fast | Shell/git log and commit history. |
| `branch-setup` | `self` | Branch Setup | fast | Git fetch/branch preparation. |
| `verify-repo` | `self` | Verification Specialist | fast | Runs scoped tests and checks. |
| `review-diff` | `self` | Code Reviewer | standard | Staged/pre-merge diff review. |
| `peer-review-pr` | `self` | PR Reviewer | standard | Coworker PR review; read-only. |
| `pr-feedback-fetch` | `self` | PR Feedback Triage | fast | Fetches PR threads and review feedback. |
| `devops-investigate` | `self` | DevOps Investigator | standard | Pipeline/environment investigation. |
