---
description: Plan-artifact eval, feature. Given a work item inline (ticketSystem none), the agent writes a manifest and an approved plan that the start gate accepts.
tags: [start-ticket, plan-artifacts, feature]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Write, Glob, Grep, Skill]
---

/agentic:start-ticket TICKET-00002 feature

Evaluation instructions (plan phase only): this is an evaluation workspace. There is no tracker, no
product repo clone and no git. The plugin's own `profile.json` is the unconfigured template; use
this project profile instead, as if you had read it from `profile.json`:

```json
{ "id": "sample-app", "displayName": "Sample app", "ticketSystem": "none", "ticketPrefix": "TICKET-",
  "layout": "monorepo", "defaultMode": "branch", "worktreeSupported": false, "baseBranchDefault": "main",
  "repos": [{ "name": "app", "path": ".", "layers": ["app"] }], "specialists": ["fullstack"] }
```

The work item text below is the ticket (ticketSystem `none`); skip the fetch, branch setup, explore
dispatches and any build step. Do not ask me anything: every clarifying question has the answer
"out of scope for this item", so record that in the plan instead of asking. Treat the plan as
**approved by me now** and persist it.

Follow the plugin's own instructions for classifying (ticket-router) and for plan structure
(ticket-plan-output, engineering-decisions, feature-plan template). Write both files under
`plans/` in the current directory:

- `plans/TICKET-00002-manifest.json`
- `plans/TICKET-00002-feature-plan.md`

Reply with one line when both files are written.

Work item:
- ID: TICKET-00002, Type: Feature, State: In Progress, Priority: 3
- Title: Orders > History - Export the visible rows to CSV
- Description: add an "Export CSV" button to the Order History page. It exports the rows currently
  shown, including the Discount column, with the same formatting as the grid.
- Acceptance criteria: (1) the button downloads a .csv named OrderHistory_<customerId>.csv;
  (2) the file has one header row and one row per visible order; (3) nothing is exported when the
  grid is empty and the button is disabled.
- Repo: app (the Order History page). No database change, no integration.
