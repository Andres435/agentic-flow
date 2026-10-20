# `apps/` — one overlay per personal GitHub repo

This host (`agentic-flow`) keeps the shared workflow. Each unrelated app gets a folder here
instead of a copy of the workflow inside that app.

| File | Who writes it |
|---|---|
| [registry.json](registry.json) | `/start-new-project` or `/adopt-project`. `id` plus git `origin` URL |
| `apps/<id>/profile.json` | stack (`stacks.services`), tracker, specialists |
| `apps/<id>/context.md` | your identity and preferences for that app. Not copied into the app |
| `apps/<id>/rules/` | personal Cursor rules GitHub must not track in the app |
| `apps/<id>/environments/` | local ports and gotchas. No secrets |
| `apps/<id>/plans/` | ticket manifests and the ledger. Gitignored |

Opening a registered checkout loads this host plugin plus `apps/<id>`. Shared files a
collaborator should see (`AGENTS.md`, `.cursor/rules`, CI notes) are written into the app
after you confirm the draft.

A product that is several related repos (the TMO layout) keeps its own workflow copy. Do not
register those origins here.
