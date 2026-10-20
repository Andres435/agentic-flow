# Index

One row per doc. Search here before Grep. Add your overlay docs to the last table.

## Start here

| Doc | Load when | Keywords |
|---|---|---|
| [README.md](README.md) | what this is; host vs one-product; folder map; doc budgets | overview, folders, budgets, upgrade, agentic-flow |
| [USER-MANUAL.md](USER-MANUAL.md) | running tickets day to day | chats, lifecycle, commands, close gate, tiers |
| [CUSTOMIZE.md](CUSTOMIZE.md) | first clone; `/start-new-project` or `/adopt-project` | customize, profile, tracker, overlay, registry |
| [MACHINE-SETUP.md](MACHINE-SETUP.md) | new laptop; bootstrap; IDE plugin install | setup, pwsh, hooks, Claude Code, Codex |
| [TEMPLATE.md](TEMPLATE.md) | maintaining the host: core vs overlay | core, overlay, versioning, porting, agentic-flow |
| [AGENTS.md](AGENTS.md) | agent routing, subagent functions, domain router | agents, routing, engineering mode |
| [profile.json](profile.json) | repos, tracker, prefix, stack command, slash list | repos, ticketSystem, ticketPrefix, slashCommands, uiGlobs |
| [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) | attribution for adapted ideas | notices, license |
| [.github/SECURITY.md](.github/SECURITY.md) | how to report a vulnerability in private | security, vulnerability, report |

## Contracts (`_shared/`)

| Doc | Load when | Keywords |
|---|---|---|
| [_shared/glossary.md](_shared/glossary.md) | a workflow term is unclear (mode, manifest, epoch, ctxPct, lanes, receipts) | glossary, terms, jargon, receipt, epoch |
| [_shared/ticket-artifacts.md](_shared/ticket-artifacts.md) | which files each phase writes; what the gates check | artifacts, manifest, verify receipt, reviewReady, close gate |
| [_shared/ticket-plan-output.md](_shared/ticket-plan-output.md) | plan and closeout structure | plan digest, work plan, deviations, enter-plan |
| [_shared/engineering-decisions.md](_shared/engineering-decisions.md) | the plan's decision gate | engineering decision, TBD, out of scope |
| [_shared/engineering-principles.md](_shared/engineering-principles.md) | principles cited by plans and reviews | principles |
| [_shared/severity-and-output.md](_shared/severity-and-output.md) | severity labels, chat output budget, token-class law | blocker, major, output budget, ctxPct |
| [_shared/subagent-functions.md](_shared/subagent-functions.md) | fan-out contracts | explore-repo, why-repo, branch-setup, verify-repo, review-diff, peer-review-pr |
| [_shared/review-protocol.md](_shared/review-protocol.md) | review focus areas and rule sources | code review, conventions, security, tests |
| [_shared/performance-ci.md](_shared/performance-ci.md) | review of query cost and pipeline gates | performance, N+1, unbounded query, CI, pipeline gate |
| [_shared/model-routing.md](_shared/model-routing.md) | tier contract for plans and lanes | tier, fast, standard, deep, frontier |
| [_shared/harness-verbs.md](_shared/harness-verbs.md) | IDE-neutral verbs and their per-IDE tools | ask-user, dispatch, enter-plan, report-context |
| [_shared/adr-policy.md](_shared/adr-policy.md) | `profile.adrIndex` is set | ADR, consult, cite |
| [_shared/runtime-verify.md](_shared/runtime-verify.md) | stack recycle, UI verify, browser pass, local login | token rails, stack smoke, CDP, local login |
| [_shared/test-verification.md](_shared/test-verification.md) | scoped tests | tests, regression |
| [_shared/cross-repo-workflow.md](_shared/cross-repo-workflow.md) | multi-repo order from `profile.dependencyOrder` | multi-repo, dependency order |

## Ticket lifecycle (skills)

| Doc | Load when | Keywords |
|---|---|---|
| [skills/ticket-workflow/SKILL.md](skills/ticket-workflow/SKILL.md) | map of phases and owners | lifecycle, phases |
| [skills/start-new-project/SKILL.md](skills/start-new-project/SKILL.md) | greenfield: fill the profile or `apps/<id>/` | start-new-project, profile |
| [skills/adopt-project/SKILL.md](skills/adopt-project/SKILL.md) | existing checkout: detect, ask gaps, register | adopt-project, registry, detect |
| [skills/research-x/SKILL.md](skills/research-x/SKILL.md) | optional X search on a spike; no API | research-x, search-x, twitter |
| [skills/onboard/SKILL.md](skills/onboard/SKILL.md) | machine setup after the profile exists | onboard, setup |
| [skills/engineering-mode/SKILL.md](skills/engineering-mode/SKILL.md) | pin tier routing for a chat | engineering mode, orchestrator, lanes |
| [skills/doctor/SKILL.md](skills/doctor/SKILL.md) · [playbook](skills/doctor/playbooks/doctor.md) | health check; lane probe | doctor, hooks, lanes, hook-errors |
| [skills/start-ticket/SKILL.md](skills/start-ticket/SKILL.md) · [playbook](skills/start-ticket/playbooks/start-ticket.md) | new ticket: intake, plan, build | intake, plan, branch, worktree, investigate |
| [skills/ticket-router/SKILL.md](skills/ticket-router/SKILL.md) | first step of start-ticket | router, manifest, docSet, parallelPlan |
| [skills/ticket-router/references/closeout-search.md](skills/ticket-router/references/closeout-search.md) | prior lessons for the manifest | priorFindings, closeout search |
| [skills/ticket-context-load/SKILL.md](skills/ticket-context-load/SKILL.md) | first step of complete-task, review-changes, address-pr-comments, implement when resuming | hydrate, load profile |
| [skills/implement/SKILL.md](skills/implement/SKILL.md) · [playbook](skills/implement/playbooks/implement.md) | resume or worktree build | implement, work plan, deviations |
| [skills/review-changes/SKILL.md](skills/review-changes/SKILL.md) · [playbook](skills/review-changes/playbooks/review-changes.md) | review the staged set; stamp the verdict | review, staged, pre-merge, reviewReady |
| [skills/complete-task/SKILL.md](skills/complete-task/SKILL.md) · [playbook](skills/complete-task/playbooks/complete-task.md) | closeout and approval package | verify receipt, approval, retrospective |
| [skills/complete-task/references/confidence-score.md](skills/complete-task/references/confidence-score.md) | confidence axes at closeout | confidence, certainty |
| [skills/complete-task/references/session-time-tracking.md](skills/complete-task/references/session-time-tracking.md) | hours and points from timestamps | hours, points, timestamps |
| [skills/complete-task/references/task-retrospective.md](skills/complete-task/references/task-retrospective.md) | the three questions and the ledger row | retrospective, ledger, E/C/$tok |
| [skills/prep-pr/SKILL.md](skills/prep-pr/SKILL.md) · [playbook](skills/prep-pr/playbooks/prep-pr.md) | approved commit, push, PR, tracker write-back | commit, PR body, push |
| [skills/address-pr-comments/SKILL.md](skills/address-pr-comments/SKILL.md) · [playbook](skills/address-pr-comments/playbooks/address-pr-comments.md) | PR feedback | PR comments, triage |
| [skills/peer-review/SKILL.md](skills/peer-review/SKILL.md) · [playbook](skills/peer-review/playbooks/peer-review.md) | a coworker's PR | peer review, inline comments |
| [skills/peer-review/references/checklist.md](skills/peer-review/references/checklist.md) | what a peer review checks | checklist |
| [skills/peer-review/references/comment-voice.md](skills/peer-review/references/comment-voice.md) | how comments read | comment voice, tone |
| [skills/start-stack/SKILL.md](skills/start-stack/SKILL.md) | run the local apps; optional smoke stamp | start-stack, stack smoke |
| [skills/swap-stack/SKILL.md](skills/swap-stack/SKILL.md) · [skills/stop-stack/SKILL.md](skills/stop-stack/SKILL.md) | hand over or stop the stack | swap-stack, stop-stack, active stack |

## Planning by work type

| Doc | Load when | Keywords |
|---|---|---|
| [skills/start-ticket/references/feature-plan.md](skills/start-ticket/references/feature-plan.md) | feature plan shape | feature, behaviors, clarify |
| [skills/start-ticket/references/worktree-handoff.md](skills/start-ticket/references/worktree-handoff.md) | worktree mode only: provision, runtime heal, handoff message | worktree, handoff, paste block |
| [skills/start-ticket/references/bug-fix.md](skills/start-ticket/references/bug-fix.md) | bug plan shape | bug, root cause, regression, never-worked, why-repo, fix layer |
| [skills/start-ticket/references/tech-spike.md](skills/start-ticket/references/tech-spike.md) | spike plan shape | spike, investigate, findings |
| [skills/start-ticket/references/document-spike.md](skills/start-ticket/references/document-spike.md) · [skill](skills/document-spike/SKILL.md) | writing a spike page, only when asked | document spike |
| [skills/start-ticket/references/ticket-intake-generic.md](skills/start-ticket/references/ticket-intake-generic.md) | pattern for a tracker intake reference | intake, tracker |
| [skills/architect/SKILL.md](skills/architect/SKILL.md) | design across a module or repo boundary | architect, design lanes |
| [skills/architect/references/design-lane-prompt.md](skills/architect/references/design-lane-prompt.md) · [design-red-flags.md](skills/architect/references/design-red-flags.md) | architect lane prompt and red flags | design lane, red flags |
| [agents/script-engineer.md](agents/script-engineer.md) | creating or changing a .ps1/.py script | script, PowerShell, Pester, PSScriptAnalyzer |
| [skills/workflow-change/SKILL.md](skills/workflow-change/SKILL.md) | changing this workflow repo itself: gate run, upstream decision, TD cleanup, plugin refresh | workflow change, maintainer, edit skill, add gate, plugin refresh |
| [skills/script-authoring/SKILL.md](skills/script-authoring/SKILL.md) | before writing any script: where it may live, standards, tests | script, ps1, tmp, scratch, Requires, StrictMode, Pester |
| [evals/README.md](evals/README.md) | agent-behavior evals: sample cases, grading, running only what a change affects | evals, claude plugin eval, Assert-EvalArtifacts, expect.json, EvalGraders, Select-EvalCases, refusal, pass@1, pass^3 |
| [_shared/agentic-proof.md](_shared/agentic-proof.md) | the commit trailer that carries verify/review proof out of the local manifest; what may leave the machine; pipeline step | agentic proof, Agentic-Proof trailer, fingerprint, PR pipeline, server-side |
| [skills/blast-radius/SKILL.md](skills/blast-radius/SKILL.md) | what a shared change could break | blast radius, shared module, public API |
| [skills/tdd-red-green-refactor/SKILL.md](skills/tdd-red-green-refactor/SKILL.md) | test-first work | TDD, characterization |
| [skills/environment-context/SKILL.md](skills/environment-context/SKILL.md) | ticket names an integration or runtime setup | environment card |

## Adapters and runtime

| Doc | Load when | Keywords |
|---|---|---|
| [adapters/README.md](adapters/README.md) | which IDE adapter applies | adapters, deepLane |
| [adapters/cursor/README.md](adapters/cursor/README.md) · [model-usage.md](adapters/cursor/model-usage.md) | Cursor install and tier map | Cursor, slash links |
| [adapters/gpt/model-usage.md](adapters/gpt/model-usage.md) | Cursor chat on a GPT picker | GPT, tiers |
| [adapters/claude/README.md](adapters/claude/README.md) · [model-usage.md](adapters/claude/model-usage.md) | Claude Code install, snapshot refresh, tier map | Claude Code, plugin, marketplace |
| [adapters/claude/workspace-CLAUDE.md](adapters/claude/workspace-CLAUDE.md) | template for the workspace `CLAUDE.md` | CLAUDE.md, overlay |
| [adapters/codex/README.md](adapters/codex/README.md) · [model-usage.md](adapters/codex/model-usage.md) | Codex install and tier map | Codex, spawn_agent |
| [output-styles/engineering-mode.md](output-styles/engineering-mode.md) | Claude Code engineering-mode output style | output style |
| [rules/model-usage.mdc](rules/model-usage.mdc) · [rules/workspace-context.mdc](rules/workspace-context.mdc) | Cursor rule stubs | rules |
| [rules/security.mdc](rules/security.mdc) | review must not introduce a security gap | security, secrets, SQL injection, auth |
| [commands/_README.md](commands/_README.md) | why commands are skills | commands, slash menu |
| [hooks/tests/README.md](hooks/tests/README.md) | running hook tests | hooks, tests, script-path-guard |
| [environments/README.md](environments/README.md) · [worktrees.md](environments/worktrees.md) | env cards; worktree opt-in | environments, worktrees |
| [user/README.md](user/README.md) | recommended IDE settings and keybindings | settings, keybindings |
| [plans/README.md](plans/README.md) | what lives under `plans/` (user-local) | plans, artifacts |
| [plans/examples/ticket-ledger.example.md](plans/examples/ticket-ledger.example.md) | ledger shape | ledger, Lanes, Epoch |
| [plans/closeout-index.md](plans/closeout-index.md) | durable lessons from closeouts | lessons, priorFindings |
| [apps/README.md](apps/README.md) | per-app overlays on this host | apps, registry, overlay |

## Your overlay docs

> Add rows here as you create project-specific files.

| Doc | Load when | Keywords |
|---|---|---|
| [agents/README.markdown](agents/README.markdown) · [agents/fullstack-specialist.md](agents/fullstack-specialist.md) | specialists | fullstack, specialist |
| [environments/local-dev.md](environments/local-dev.md) | local dev setup | local dev, ports, start |
