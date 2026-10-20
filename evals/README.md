---
name: evals-readme
description: Plugin evals for this project - the template ships none yet; how to add `claude plugin eval` cases and how Select-EvalCases picks the ones a change affects.
keywords: evals, claude plugin eval, Select-EvalCases, case-map, agent behavior, scaffold, pass@1, pass^3
---

# Plugin evals

The Pester and hook tests prove the gates. An eval checks the layer above: an agent that follows
the plugin's playbooks writes what the gates accept and refuses what the playbooks forbid. Each case
runs a real Claude Code session with this plugin loaded.

**This template ships no cases yet.** A project adds its own under `evals/<case>/`. Until it does,
[Select-EvalCases.ps1](../scripts/ticket/Select-EvalCases.ps1) prints `[INFO] no eval needed`.

## Add a case

`claude plugin eval` reads each folder under `evals/`:

- `prompt.md` with frontmatter (`tags: [start-ticket]`, `runs: 3`) and the text to type, plus
  `graders/*.md` (`file_exists`, `regex` over a written file, or `llm`). Use this when the run
  starts from an empty folder.
- `case.yaml` (same fields, graders inline, `tags: [..]`) when the run needs seeded files:
  `context.scaffold_script` points at a `scaffold.sh` that writes them. The harness never copies a
  `workspace/` folder by itself.

Set `runs: 3` so a case has a pass@1 and a pass^3. A regex grader is compiled as JavaScript, so use
no .NET inline flags such as `(?m)`; put flags in the grader's `flags:` field.

## Run

Needs Claude Code 2.1.269+ and a login or `ANTHROPIC_API_KEY`. Each run is real model calls,
about $0.30 per case per run on Sonnet.

```bash
claude plugin eval . --eval-dir evals --trust-plugin --ablation none --allow-tools Write Edit --scaffold --keep-temp --no-publish --threshold 1.0 --model sonnet --max-cost-usd 10 --json tmp/eval.json
```

`--scaffold` runs each case's own `scaffold.sh` (bash, as you); pass it only for your own cases.
On Windows, put Git bash ahead of the WindowsApps `bash.exe` stub (`C:\Program Files\Git\bin` first
on `PATH`): the stub strips the backslashes from the scaffold path and seeded cases score 0.
`--case <name>` runs one case. `--keep-temp` leaves each run's workspace in `%TEMP%\claude-eval-*`.
`scripts/Clear-WorkflowScratch.ps1` prunes those folders older than 14 days and `evals/results/` runs beyond the
newest 5; delete them yourself only to free space sooner.

### Run only what a change affects

`pwsh ./scripts/ticket/Select-EvalCases.ps1` reads the branch's changed files (since the merge-base,
plus uncommitted and untracked), maps them to tags with [case-map.psd1](case-map.psd1) (a file under
`evals/<case>/` maps to that case's own tags), and prints the matching cases, the estimated cost
(cases x 3 runs x $0.30), and the full `claude plugin eval ... --tag <t>` command with a
`--max-cost-usd` of 1.5x the estimate. Nothing mapped prints `[INFO] no eval needed`; `-Json` emits
`{tags, cases, estUsd, command, warnings}`. When a selected case seeds files with `scaffold.sh` and
`bash` on `PATH` is the WindowsApps stub, it prints a `[WARN]` with the fix before you run the command.
Edit the rules in `case-map.psd1` to match the playbooks and gates your project changes.

## When to run

By hand, never on tickets, pushes or PRs (every run costs tokens): after changing what shapes
agent behavior, such as a lifecycle playbook, a reviewer agent, `rules/security.mdc`, a
plan shape doc, or a gate. The deterministic gates and hook tests still run on every push.
