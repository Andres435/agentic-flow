---
name: codex-model-usage
description: Model tiers mapped to Codex spawn_agent for a Codex parent. The picked model is deep and stays inline.
---

# Codex Model Usage

**Status: partly probed 2026-11-12.** A Codex Desktop parent honored fast and standard, and left deep
inline. The separate `codex exec` CLI did not honor either pinned selector (it returned the broad
GPT family only). Codex Desktop is the supported tiered parent; `codex exec` is not. The Codex
context hooks are wired in [hooks/hooks.json](hooks/hooks.json).

Use this file when the parent session is Codex. Tiers and routing rules stay in
[_shared/model-routing.md](../../_shared/model-routing.md). Load this file from `AGENTS.md`; Codex
has no `@` include. Deep is the model selected for the session and stays inline. Do not ask for a
different model.

## Tiers

Codex `spawn_agent` takes `model` and, when that call exposes it, `reasoning_effort`. Copy each
selector from the installed Codex model list (`codex` model picker). Do not invent an id. This
workspace had no Codex install on 2026-09-25, so the cells below name the slot, not a guessed id.
`/doctor --lanes` from a Codex parent records the id it actually honored.

| Tier | `spawn_agent` `model` | `reasoning_effort` | Used for |
|---|---|---|---|
| `fast` | smallest model on the installed Codex list | `low` when the call accepts it; otherwise omit | `[low]` steps; explore-repo, why-repo, branch-setup, pr-feedback-fetch, verify-repo |
| `standard` | mid model on that list, or the fast model when the list has one id | `medium` when the call accepts it; otherwise omit | `[med]` steps; review-diff, peer-review-pr |
| `deep` | **The session's selected model, inline only** | the session's own effort | plans, `[high]` steps, second-opinion reviewer, architect deep candidate, blast-radius |
| `frontier` | a model the user names | only when the user asks | only when the user asks for it in this session |

**`deepLane: inline`** — deep and `[high]` run on the session's model. Never dispatched.

### `codex exec` probe

On 2026-11-12, read-only probes used `codex exec --json --model <selector> --sandbox read-only
--cd <repo> -` and asked the CLI to name its model. Pinned fast and standard selectors returned
only the broad family name, so the response does not confirm the selected sub-tier; do not use
`codex exec` as the tiered parent. The architect external-lane invocation
`codex exec --sandbox read-only --skip-git-repo-check --ephemeral -` returned `GPT-6`, confirming
that the CLI can run under the broad `gpt` family configuration.

Every `spawn_agent` passes `model` from the tier. A lane whose first line names another family, or
nothing, is discarded. Never dispatch the deep tier. If the model cannot be told, ask the user to
pick one and do not name one.
