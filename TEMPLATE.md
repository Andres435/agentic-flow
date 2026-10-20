# TEMPLATE.md — Maintainer map

What is **core** (stable across products) vs **overlay** (per project).

## Core

| Path | Notes |
|---|---|
| `skills/<name>/SKILL.md` | One folder per skill. `playbooks/` and `references/` sit beside it |
| `skills/start-new-project/` | Greenfield: fills root `profile.json` or `apps/<id>/` |
| `skills/adopt-project/` | Existing checkout: detect, ask gaps, write `apps/<id>/` |
| `skills/research-x/` | Optional `search-x` on spikes. No X API |
| `skills/architect/`, `skills/blast-radius/` | Design lanes and what-could-break proof for shared changes |
| `scripts/ticket/` | Artifact gate, epoch, ledger, review stamp, verify receipt, stack smoke, lanes, measured Ctx%, one-call close (`Close-Ticket.ps1`), opt-in external panel lanes (`Invoke-ExternalLane.ps1`, `user/external-lanes.example.json`), evals (`Select-EvalCases.ps1` with `evals/case-map.psd1`, `Assert-EvalArtifacts.ps1` over a `claude plugin eval` result, four sample cases in `evals/`), doc claims and doc-sync (`doc-claims.psd1`: a project appends its own claims) |
| `scripts/Clear-WorkflowScratch.ps1` | Retention sweep: `tmp/` older than 14 days, closed tickets' `plans/evidence/` (host and `apps/*/plans`), `claude-eval-*` in TEMP, old `evals/results/`. Runs after `Close-Ticket.ps1` and once per UTC day from `session-context.js` (`TMO_SKIP_SWEEP=1` skips) |
| `scripts/machine/` | Machine init, user-level slash links, git hooks, Claude overlay |
| `scripts/runtime/Set-ActiveStack.ps1` | One stack owner file |
| `scripts/runtime/Start-TicketStack.ps1`, `Stop-TicketStack.ps1`, `Swap-TicketStack.ps1` + `scripts/lib/StackServices.ps1` | Start, stop and swap any stack from `profile.stacks.services` (presets, `dependsOn`, `ready`, process-tree stop). `scripts/ticket/profile.schema.json` and Assert-AgenticFlow validate the block. No root `scripts/*.ps1` forwarders: every script is called by its folder path |
| `hooks/core/` + `hooks.json` | Shared hook logic; IDE bridges live under `adapters/`. `hook-log.js` writes swallowed errors to `scripts/.hook-errors.log` |
| `hooks/git-hooks/` | pre-commit (no user-local `plans/`) and pre-push (Assert-AgenticFlow) |
| `hooks/tests/` | Hook smoke tests |
| `_shared/ticket-artifacts.md` | Phase gate contract |
| `_shared/ticket-plan-output.md` | Plan and closeout structure |
| `_shared/engineering-decisions.md` | Plan decision gate |
| `_shared/model-routing.md` | Tier contract |
| `_shared/harness-verbs.md` | IDE-neutral verbs |
| `_shared/severity-and-output.md` | Token-class law |
| `commands/_README.md` | Menu notes. No slash shim that duplicates a skill |
| `.cursor-plugin/`, `.claude-plugin/`, `.codex-plugin/` | Same skills, three hosts. A new skill goes in each `skills` list |
| `adapters/`, `output-styles/` | Per-IDE tier maps, hook bridges, engineering-mode output style |
| `local-test-login.example.json` | Shape for a gitignored `local-test-login.local.json` used by browser passes |

## Overlay

| Path | Notes |
|---|---|
| `profile.json` | Host or one-product config. `/start-new-project` fills it. Do not drop `slashCommands` |
| `apps/` | Per-app overlays and `registry.json` when this clone is the host |
| `CUSTOMIZE.md` | Checklist |
| `agents/` | Specialists |
| `environments/` | Env cards |
| `scripts/runtime/` besides the stack owner | `Start-TicketStack.ps1` reads `profile.stacks.services`. `/start-new-project` fills that list |
| `USER-MANUAL.md` | Project notes below the core section |
| `mcp.json` | Project MCP servers |
| `Install-CursorExtensions.ps1`, `Apply-CursorUserConfig.ps1`, `New-CockpitWorkspace.ps1` in `scripts/machine/` | Optional bootstrap phases. Machine init skips each one that is absent |

## Versioning

Tag releases as `core-vX.Y.Z`. Projects copy core files from a tag.
Do not `git merge` a product repo into this host. The GitHub name is `agentic-flow` (the old
`cursor-agentic-template` URL redirects).

## Adding to core

1. Zero product strings (`TmoPro`, `IIS Express`, `Custom.StoryPointsActual`). The template-vanilla check scans `skills/` and `_shared/`.
2. A hook test or a doc-budget check.
3. `skills/<name>/SKILL.md` with `icon` and `color`. Playbooks live in `playbooks/`, not a repo-root folder and not `PLAYBOOK.md` beside `SKILL.md`.
4. Porting from a product repo: diff its workflow commits since the last port, apply the generic hunks, and keep the template's profile-driven pieces (ticket prefix, `adrIndex`, ledger row pattern). Name the source commits in the port commit message.

## Last port

The newest product workflow state this template has absorbed. Start the next port with
`git diff <sha>..main` in the source repo, limited to generic paths.

| Source | Base | Date | Left out |
|---|---|---|---|
| tmo-agentic-workspace `main` | `d570d37` (plus the prep-pr path fix in its PR #18) | 2026-10-08 | product evals (`evals/`, `Assert-EvalArtifacts`, `plugin-eval.yml`), product NuGet credential code, the source's tech-debt list and its own doc claims |
| tmo-agentic-workspace `workflow/close-shippable-tech-debt` | `9062ac6` | 2026-10-08 | product evals, product launchers, the tech-debt list, and `Custom.StoryPointsActual`. Brought hours, the manifest schema, generated docs, the PR nudge, and the analyzer warning gate |
| tmo-agentic-workspace `workflow/apply-review-findings` | `daf22c0` | 2026-10-09 | product evals and their `expect.json` cases, the TMO NuGet PAT fix, the TMO home-anchored script path rule, and the `Template-Port` trailer check (source-only). Brought the shared secret patterns, the commit secret scan and `secrets` gate check, the Cursor matcher fix and its test, `..` normalization in the script path guard, `persist-credentials: false`, and the `workflow-change` skill |
| tmo-agentic-workspace `main` (PR #22) | `bc59564` | 2026-10-09 | product evals and their cases, the `plugin-eval.yml` change, and the source's tech-debt rows. Brought `Close-Ticket.ps1` (and `Get-SessionHours -Preview`), effort per tier, opt-in external lanes (`Invoke-ExternalLane.ps1`), `Select-EvalCases.ps1` with a generic `case-map.psd1`, the short-plan rule, and the secret-never-repeated rule |
| tmo-agentic `main` (PR #29) | `9635fd9` | 2026-10-19 | `Publish-SmokeEvidence` and the ADO smoke-comment close gate, the `scripts/README.md` rows, and the `*.sh` LF rule (no shell scripts here). Brought LF git hooks, the UTF-8 diff fingerprint, the `plans/evidence` verify copy (app-aware), `Clear-WorkflowScratch.ps1` with its daily session sweep, and `hooks/core/pwsh.js` |
| tmo-agentic `b1dc0f2` (eval part) | `b1dc0f2` | 2026-10-19 | the source's product cases (`devops-task-approval`, the migration refusal, `close-bug`, `implement-deviation`, `review-security`, the other `start-*` cases) and its measured rates. Brought `Assert-EvalArtifacts.ps1` (prefix from `profile.ticketPrefix`), `EvalGraders.Tests.ps1`, `plugin-eval.yml`, the `*.sh` LF rule, and four generic sample cases (`start-feature`, `refuse-unconfigured`, `review-staged-secret`, `prep-pr-approval`) |
