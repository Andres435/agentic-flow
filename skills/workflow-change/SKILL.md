---
name: workflow-change
description: Agentic Workflow. Change this workflow folder itself — a skill, command, hook, gate, script, rule, or adapter. Sequences what the gates cannot enforce, gate run, tech-debt cleanup, the upstream decision, and the plugin refresh. Use for "change the workflow", "edit a skill", "add a gate", "fix a hook", or any branch that edits this repo's workflow files.
keywords: workflow change, maintainer, edit skill, add gate, hook change, upstream, Docs-Unaffected, plugin refresh, tech debt
icon: wrench
color: brand
---

# Workflow Change

For changes to **this workflow repo**, not to a product ticket. The gates already enforce
structure and docs: `scripts/ticket/Assert-AgenticFlow.ps1` ([README](../../README.md); CI and git pre-push) and its
doc-sync, doc-claims, secrets and index checks. This skill only sequences what no check can
decide. Do not restate a gate's rules here; run it and fix what it reports.

## Steps

1. **Branch.** Never commit on `main`. One concern per branch (`workflow/<topic>`, `fix/<topic>`,
   `docs/<topic>`).
2. **Scripts.** A new or changed `.ps1`/`.py` follows [script-authoring](../script-authoring/SKILL.md)
   (a Pester test beside it).
3. **Change, then regenerate.** After editing a command, skill, chat count, or the stack
   services, run `pwsh ./scripts/ticket/Sync-GeneratedDocs.ps1` so the generated sections match.
4. **Gate locally.**
   - `pwsh ./scripts/ticket/Assert-AgenticFlow.ps1` until `[PASS]`.
   - Pester over `./scripts` and the node hook tests ([hooks/tests/README.md](../../hooks/tests/README.md)).
   - A doc-sync failure means the doc that describes the change was not touched: fix that doc,
     or add `Docs-Unaffected: <ruleId>: <why>` only when no doc states the changed fact.
   - **Evals, only when agent behavior can change** (a start-ticket, ticket-router, complete-task or
     review playbook, a reviewer agent, `rules/security.mdc`, a plan shape doc, a gate).
     Run `scripts/ticket/Select-EvalCases.ps1` to pick only the cases the change affects, say its
     estimated cost, then run the command it prints and `Assert-EvalArtifacts.ps1` over its result
     ([evals/README.md](../../evals/README.md#run-only-what-a-change-affects)). Nothing selected: skip.
5. **Upstream.** This repo came from a template ([TEMPLATE.md](../../TEMPLATE.md)). A change that
   works for any project (gates, hooks, lifecycle skills) is worth offering back to the template;
   a project-only change (your stack, ticket system, specialists) stays here. Say which in the PR.
6. **Tech debt.** Deferred work gets a row with why it waits and its first step; a shipped row is
   deleted (git keeps history).
7. **Commit and PR** only after the user approves. The PR body lists what changed, the gate
   result, and the upstream decision.
8. **After merge,** reload the workflow in each IDE: Claude Code reads an installed plugin
   snapshot, so reinstall or refresh it from `main` and restart the session
   ([adapters/README.md](../../adapters/README.md)).

## Stop and ask

- A change to the ticket lifecycle contract (chat counts, what blocks close, approval gates).
- Removing or weakening a gate, a hook, or a secret pattern.
- Anything that writes outside this repo (product repos, user settings).
