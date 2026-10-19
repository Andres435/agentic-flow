# User manual

Day-to-day ticket workflow for humans. Agents: [AGENTS.md](AGENTS.md). First clone: run
`/start-new-project` (blank product) or `/adopt-project` (existing checkout). They fill
[profile.json](profile.json) or `apps/<id>/`, and [CUSTOMIZE.md](CUSTOMIZE.md). Then `/onboard`
for the machine script ([MACHINE-SETUP.md](MACHINE-SETUP.md)). After that, commands run
from the profile and do not re-ask for repos or start commands.

Terms (manifest, tier, lane, receipt, Drive): [glossary](_shared/glossary.md).

Branch mode is three chats. `/start-ticket`, `/review-changes`, and `/complete-task` each load their playbook and the tier contract.

| Chat | Type | Done when |
| --- | --- | --- |
| 1 | `/start-ticket <ticket> bug\|feature\|spike\|refactor` | The change is in the working tree. |
| 2 | `/review-changes` | Clean ticket files are staged and the set has a verdict. |
| 3 | `/complete-task`, then `/prep-pr` after you approve | Only the actions you approved ran. |

If `/review-changes` reports a Blocker or Major, fix it (in any chat) and run `/review-changes`
again before `/complete-task`; close fails while a review stamp still records one.

`/start-stack` runs the local apps. It is not a chat. If chat 1 runs out of context, open a fresh
chat and type `/implement <ticket>`: the approved plan is already on disk.

In Claude Code, commands are namespaced (`/agentic:start-ticket`). After changing plugin files,
commit and update the plugin: Claude reads a snapshot, not the working tree
([adapters/claude/README.md](adapters/claude/README.md)).

## Before you start

1. Open the workspace root (the folder that contains this one), not this folder alone.
2. Confirm `/` lists `start-ticket` **once**.
3. Pass the ticket id on every command that takes one (`TICKET-42`, not a paragraph).
4. Type slash commands. Free-form "please start this ticket" skips intake, branch setup, and the plan.

`/start-ticket` also searches prior closeouts (`plans/closeout-index.md`) and puts matching lessons on
the manifest as `priorFindings`, at most eight. The plan names each id and what it changed.

## Ticket lifecycle

```text
Chat 1 — Plan and build
  /start-ticket <ticket> bug|feature|spike|refactor
  Deep tier drafts the plan. Question it; it revises only the section you asked about.
  Say "approved" in chat. Approval is that statement, never an IDE button.
  Asking it to skip the plan gets a short plan instead: the later chats and close read that file.
  It writes the plan, then builds in this same chat. Each Work Plan step's [low]|[med]|[high]
  tag sets its tier.
  /start-stack <ticket>   when you need the local apps
  Done when: the change is in your working tree

Chat 2 — Review
  /review-changes         new chat; reviews ticket files, stages the clean ones, stamps the verdict

Chat 3 — Close
  /complete-task          new chat; skips review-diff when chat 2 was Ready on the same staged set
  You review the approval package.
  /prep-pr                only after you approve
  Then three short questions (did the plan hold? any friction? anything durable?). It writes only
  what you pick. One ledger row is the only automatic output; the close itself (timestamp, hours,
  ledger row, close gate) is one script call, Close-Ticket.ps1, after you approve.
```

Later PR feedback: new chat, `/address-pr-comments <ticket>`. A coworker's PR: `/peer-review <id>`.

**Close gate.** Close fails until each affected repo has a passing verify receipt and a review stamp
whose reviewed work is still what got committed, with no open Blocker or Major. A base-branch merge
before push is fine. Any other commit after the review means `/review-changes` again. When an
affected repo has profile layer `frontend` and the change touches a `uiGlobs` file type, close also
needs a Drive you confirmed passed (stack smoke Tested). A spike skips all three. `/prep-pr` runs
the same work checks (`-Phase prepush`) before it commits, and the push hook runs them again on a
branch that names the ticket.

### Engineering mode

`/start-ticket`, `/review-changes`, and `/complete-task` each load their playbook and the tier
contract. Pin this for ad-hoc work, or for a long chat that should stay an orchestrator after
compaction. How to pin it is in your IDE's adapter ([Cursor](adapters/cursor/model-usage.md),
[Claude Code](adapters/claude/model-usage.md)). Say "exit engineering mode" to turn it off. Typing
`/engineering-mode` and a ticket command in one message attaches only the first skill.

```text
Engineering mode on — orchestrator: <model> (<tier>)
step N/M [<tag>] → inline | lane (<model>)
```

### Worktree mode (opt-in)

Only when `profile.worktreeSupported` is true and your overlay ships the worktree scripts. Add
`--worktree` to run a ticket beside another one. That is four chats: plan, `/implement` in the
ticket window, review, close. Later commands read the mode from the manifest.

## Commands

<!-- gen:commands:start -->
| You want                                                   | Type                                                |
| ---------------------------------------------------------- | --------------------------------------------------- |
| Fill the profile for a new project                         | `/start-new-project`                                |
| Attach an existing GitHub checkout                         | `/adopt-project`                                    |
| Search X on a spike (optional)                             | `/research-x`                                       |
| Machine setup after the profile exists                     | `/onboard`                                          |
| Pin model routing for the chat                             | `/engineering-mode`                                 |
| Health check (profile, hooks, gates, lanes)                | `/doctor`                                           |
| Start a ticket                                             | `/start-ticket <ticket> bug|feature|spike|refactor` |
| Build the approved plan (resume / worktree)                | `/implement <ticket>`                               |
| Run the local apps                                         | `/start-stack <ticket>`                             |
| Give the stack to another ticket / stop it                 | `/swap-stack <ticket>` / `/stop-stack`              |
| Review ticket files; stage the clean ones                  | `/review-changes`                                   |
| Closeout and approval package                              | `/complete-task`                                    |
| Commit / push / PR / tracker write-back, after you approve | `/prep-pr`                                          |
| Address PR comments                                        | `/address-pr-comments <ticket>`                     |
| Peer-review a coworker's PR                                | `/peer-review <id>`                                 |
<!-- gen:commands:end -->

`bug-fix`, `feature-plan`, and `tech-spike` are plan shapes `/start-ticket` reads, not commands.

### What "done" means

| Command | Done when | Next |
| --- | --- | --- |
| `/start-ticket` | Artifact gate passes; plan approved; build continues in the same chat | New chat `/review-changes` |
| `/implement` | Work Plan steps complete, tests run | New chat `/review-changes`, then `/complete-task` |
| `/review-changes` | Verdict on screen and `reviewReady` stamped | New chat `/complete-task` |
| `/start-stack` | Script printed URLs, or `[FAIL]` after one recycle | You use the apps |
| `/complete-task` | Approval package is on screen; verify receipt written | You approve, then `/prep-pr` |
| `/prep-pr` | Only the actions you approved ran; the work checks (`-Phase prepush`) passed before the first commit | Retrospective, then stop. Run in a fresh chat, it also does the close (retrospective, ledger row) |
| `/peer-review` | Draft on screen; after approval, comments posted | Stop |

## Models (tiers)

| Work | Tier |
| --- | --- |
| Drafting the plan | deep |
| `[low]` / `[med]` / `[high]` steps | fast / standard / deep |
| Subagents: explore, branch, verify | fast |
| Subagents: review | standard (plus a deep second opinion when the plan has a `[high]` step) |

Each adapter maps tiers to real models: [Cursor](adapters/cursor/model-usage.md),
[Cursor GPT chat](adapters/gpt/model-usage.md), [Claude Code](adapters/claude/model-usage.md),
[Codex](adapters/codex/model-usage.md).

## Local apps

One stack at a time. `/start-stack <ticket>` starts `profile.stacks.services`, in `dependsOn` order. When it fails with
"another ticket owns the stack", "port in use", or leftover processes, run `/stop-stack`, then
`/start-stack <ticket>` once. If it still fails, fix the machine yourself; do not ask the agent to
inspect ports.

The agent does not open the browser on its own. Ask for a smoke pass ("smoke test the UI"). It asks
you whether it passed and stamps Tested only if you approve. Review and closeout show Never tested /
Tested / Untested latest changes. When an affected repo has profile layer `frontend` and the change
touches a `uiGlobs` file type, close fails until that pass is Tested; otherwise you can skip it.

## Staging and review

The staged set is the approval record. Stage hunks yourself, then `/review-changes` or
`/complete-task`. Unstaged work is awareness only unless you include it.

## Done table

| Phase | Artifact | Script gate |
| --- | --- | --- |
| Start | `plans/<ticket>-manifest.json`, `plans/<ticket>-<type>-plan.md` (Plan Digest + Engineering Decisions) | `Assert-TicketArtifacts -Phase start` |
| Review | `reviewReady` (verdict, headSha, fingerprint) + `ctxPct.review` on the manifest | `Set-ReviewReady` / `Set-TicketCtxPct` |
| Close | `verify` on the manifest (pass per repo), review still matching, ledger row | `Assert-TicketArtifacts -Phase close` |

## Project notes

Add project-specific notes below (stack commands, auth steps, known gotchas).
