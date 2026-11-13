# Antigravity setup

Antigravity machine setup. Do [../../MACHINE-SETUP.md](../../MACHINE-SETUP.md) first (prerequisites,
folder layout, MCP auth, product repos).

Same workflow and plugin. Antigravity loads the shared rules, skills, and commands from the repository
root. The compatibility manifest is [.antigravity-plugin/plugin.json](../../.antigravity-plugin/plugin.json).

## Loading the workspace

Start Antigravity with the workspace rooted at this repository or the ticket worktree:

```powershell
# Open the main checkout
cd <path to this repo>

# Or open a ticket worktree (the root from scripts/ticket/Resolve-TicketRoot.ps1 -Ticket <ticket> -Json)
cd <worktree root>
```

Antigravity automatically discovers `AGENTS.md` and loads workspace customizations.

Model policy for Antigravity: [model-usage.md](model-usage.md).
