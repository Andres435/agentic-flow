# agentic-flow

A ticket-driven agentic workflow. Cursor, Claude Code, and Codex each load it as a
plugin (`.cursor-plugin/`, `.claude-plugin/`, `.codex-plugin/`). Claude Code is the only IDE that has run the
enforcement gates end to end; Cursor is untested against them and the Codex adapter is experimental. The
shared core names verbs and model tiers. [adapters/](adapters/README.md) maps them per IDE.

Use this clone as **one host for many small apps** (`apps/<id>/` plus `apps/registry.json`, both kept out of git),
or copy it beside one product made of several related repos. Product specifics live in that overlay
[profile.json](profile.json), not in the core.

**Day-to-day usage:** [USER-MANUAL.md](USER-MANUAL.md). **First clone:** [CUSTOMIZE.md](CUSTOMIZE.md).
**New laptop:** [MACHINE-SETUP.md](MACHINE-SETUP.md). **Maintainers:** [TEMPLATE.md](TEMPLATE.md)
(core vs overlay). **Finding a doc:** [INDEX.md](INDEX.md). **Terms** (manifest, tier, lane,
receipt): [glossary](_shared/glossary.md). **Contributing:** [CONTRIBUTING.md](CONTRIBUTING.md).
**License:** [Apache-2.0](LICENSE).

> **Host:** clone this folder once (the name is yours to pick; the docs say `agentic-flow`) and
> register each personal GitHub repo in `apps/`.
> **One product:** place this folder at `<your-app>/.cursor`, or at `source/repos/.cursor` in a
> multi-repo workspace. Paths in the docs are relative to this folder.

## What you get

- **Ticket workflow:** `/start-ticket`, `/review-changes`, `/complete-task`, `/prep-pr`, plus
  `/implement`, `/address-pr-comments`, `/peer-review`, and the stack commands. Each one is a
  skill under `skills/<name>/`, with its body in `playbooks/` and its detail in `references/`.
- **One record per ticket:** `plans/<ticket>-manifest.json` holds the routing, timestamps, and every
  later result: review stamp and findings, verify results, PR feedback, stack smoke, context %, and
  lanes. Small `Set-*` scripts write it; no step writes a side file.
- **Mechanical gates:** `scripts/ticket/Assert-TicketArtifacts.ps1` checks each phase. The close
  gate needs a passing verify result per repo (`Set-VerifyReceipt.ps1`) and a review stamp
  (`Set-ReviewReady.ps1`) whose reviewed work is still what got committed, with no open Blocker or
  Major. A clean base-branch merge is fine. A merge that contains its own edits, or any later
  commit, means review again. `-Phase prepush` runs the same work checks before `/prep-pr` commits,
  and the push gate runs them on a product branch that names the ticket.
- **Routing and tiers:** `ticket-router` writes a manifest so later steps load only the docs the
  ticket needs. Work runs on fast / standard / deep / frontier tiers
  ([_shared/model-routing.md](_shared/model-routing.md)). Engineering mode routes each step to its
  tier's model.
- **Hooks, written once:** `hooks/core/` holds session context, the commit guard, the push gate,
  the ticket nudge, the closeout guard, and context usage. IDE adapters call it. Swallowed hook
  errors go to `scripts/.hook-errors.log`, and `/doctor` warns when it is not empty.
- **Stack smoke:** `/start-stack` runs `profile.stacks.services`. A smoke pass (a Drive) you
  ask for is stamped with `Set-StackSmoke.ps1` and shown at review and closeout. It is a close gate
  only when an affected repo has profile layer `frontend` and the change touches a
  `profile.uiGlobs` file type.
- **Retrospective ledger:** each close leaves one row in `plans/ticket-ledger.md` (user-local),
  with E / C / $tok scores, measured context %, lanes, and the workflow epoch.

## Quick start

1. Clone this host (or copy it beside one product as `.cursor`).
2. Blank product: `/start-new-project`. Existing checkout: `/adopt-project`. They fill
   `apps/<id>/` or the root [profile.json](profile.json) and [CUSTOMIZE.md](CUSTOMIZE.md).
3. Bootstrap the machine once: `scripts/machine/Initialize-WorkflowMachine.ps1`
   ([MACHINE-SETUP.md](MACHINE-SETUP.md)).
4. Run tickets:

<!-- gen:chats:start -->
```text
Chat 1  /start-ticket <ticket> bug|feature|spike|refactor   → approve plan → build in this chat
Chat 2  /review-changes
Chat 3  /complete-task → /prep-pr
```
<!-- gen:chats:end -->

Worktree mode (`--worktree`, only when `profile.worktreeSupported`) adds `/implement` in the
ticket window. Chat counts per mode and full steps: [USER-MANUAL.md](USER-MANUAL.md). Those ticket commands load the tier contract on their own.
Pin engineering mode for ad-hoc work, or for a long chat.

## Folder map

| Folder | What it is | Core or overlay |
|---|---|---|
| [skills/](skills/) | One folder per skill: `SKILL.md`, `playbooks/`, `references/` | Core (add your own beside them) |
| [_shared/](_shared/) | Contracts: artifacts, plan output, tiers, verbs, output budgets | Core |
| [scripts/ticket/](scripts/ticket/) | Artifact gate, receipts, review stamp, ledger, epoch, one-call close (`Close-Ticket.ps1`), external lanes, eval selection | Core |
| [scripts/machine/](scripts/machine/) | Machine bootstrap, slash links, git hooks, Claude overlay | Core |
| [hooks/core/](hooks/core/) + `hooks.json` | Hook logic. `hooks/git-hooks/` holds pre-commit and pre-push | Core |
| [adapters/](adapters/README.md) | Per-IDE tier maps and hook bridges | Core |
| [output-styles/](output-styles/engineering-mode.md) | Engineering mode output style (Claude Code) | Core |
| [commands/](commands/_README.md) | Menu notes. No shim duplicates a skill | Core |
| [profile.json](profile.json) | Host (or one-product) overlay: repos, tracker, prefix, stack, slash list | **Overlay** |
| [apps/](apps/README.md) | Per-app overlays and `registry.json` when this clone is the host (local, gitignored) | **Overlay** |
| [agents/](agents/README.markdown) | Specialists (stub: `fullstack-specialist.md`) | **Overlay** |
| [environments/](environments/README.md) | Setup cards (stub: `local-dev.md`) | **Overlay** |
| [rules/](rules/) | Cursor rules (stub pointers) | Overlay |
| [plans/](plans/README.md) | Per-ticket artifacts and the ledger. User-local, never committed | Runtime |
| [user/](user/README.md) | Recommended IDE settings and keybindings | Optional |

## IDEs

- **Cursor:** `scripts/machine/Install-UserCursorCommands.ps1` links the skills in
  `profile.slashCommands` so slash badges keep their icons. [adapters/cursor/README.md](adapters/cursor/README.md).
- **Claude Code:** `scripts/machine/Install-ClaudeAdapter.ps1` writes `CLAUDE.md` at the workspace
  root, then run `claude --plugin-dir <this folder>`. Commands are namespaced
  (`/agentic:start-ticket`). [adapters/claude/README.md](adapters/claude/README.md).
- **Codex:** add this folder as a plugin marketplace. [adapters/codex/README.md](adapters/codex/README.md).

## Doc budgets and the flow gate

```powershell
scripts/ticket/Assert-AgenticFlow.ps1   # every check CI runs; exit 1 on a violation
scripts/Assert-DocBudget.ps1 -WarnOnly  # line budgets only
```

| File kind | Budget | When over |
|---|---|---|
| `SKILL.md` body | 500 lines | Move detail to `references/` |
| `skills/*/playbooks/*.md` | 500 lines | Split by phase |
| `_shared/*.md` | 150 lines | Move into the owning skill's `references/` |
| `environments/*.md` | 120 lines | Split setup vs gotchas |
| `adapters/claude/model-usage.md` | 70 lines | It is imported into every Claude session |

Human docs (`README.md`, `USER-MANUAL.md`, `MACHINE-SETUP.md`, `CUSTOMIZE.md`) and `AGENTS.md` are
exempt. Before adding any always-on doc or MCP tool, read the token-class law in
[_shared/severity-and-output.md](_shared/severity-and-output.md).

**Docs stay true by check, not by care.** `Assert-DocLinks.ps1` fails a broken link and a
backticked path into this folder that does not exist. It scans the docs git sees (tracked plus
new untracked, not ignored), so a session worktree nested at `.claude/worktrees/` is skipped;
outside a git checkout it walks the tree and skips any folder with its own `.git`. Changing a gate, stamp script, hook, or
lifecycle skill? Update the doc that describes it in the same branch, or add a commit trailer
`Docs-Unaffected: <ruleId>: <why>` (`scripts/ticket/Assert-DocSync.ps1`). Changing a fact the docs
state (what blocks close, chat counts, ...)? Edit its claim in `scripts/ticket/doc-claims.psd1`;
the claim then fails any doc that still says the old thing.

## Upgrading core in a project

Core files can be copied from this repo without touching your overlay. The URL is an example:
point `upstream` at the template you track (this repo or your fork).

```bash
git remote add upstream https://github.com/Andres435/agentic-flow.git
git fetch upstream
git checkout upstream/main -- skills/ _shared/ scripts/ticket/ scripts/machine/ hooks/ adapters/ output-styles/
```

Then re-add any project skills you keep under `skills/`, and run `Assert-AgenticFlow.ps1`. Do not
`git merge` the template into a project: it would overwrite `profile.json`, `agents/`, and
`environments/`. Versioning notes: [TEMPLATE.md](TEMPLATE.md).

## Projects using this template

| Project | Repo | Notes |
|---|---|---|
| TMO | https://github.com/Andres435/tmo-agentic-workspace | ADO, multi-repo, worktrees, IIS and React stacks |
| _(your project here)_ | — | — |
