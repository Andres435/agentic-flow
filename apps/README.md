# `apps/` — one overlay per personal GitHub repo

This host (`agentic-flow`) keeps the shared workflow. Each unrelated app gets a folder here
instead of a copy of the workflow inside that app.

| File | Who writes it |
|---|---|
| `registry.json` | `/start-new-project` or `/adopt-project`, from [registry.example.json](registry.example.json). `id` plus git `origin` URL |
| `apps/<id>/profile.json` | stack (`stacks.services`), tracker, specialists |
| `apps/<id>/context.md` | your identity and preferences for that app. Not copied into the app |
| `apps/<id>/rules/` | personal Cursor rules GitHub must not track in the app |
| `apps/<id>/environments/` | local ports and gotchas. No secrets |
| `apps/<id>/plans/` | ticket manifests and the ledger |

**Local only.** This repo is public, so everything here except this README and
`registry.example.json` is gitignored: the registry names your personal repos and the overlays
hold your context. Moving computers: copy `apps/` yourself, as with `plans/`.

Ticket scripts pick the app from the folder they run in, or from `AGENTIC_APP_OVERLAY` (the
Claude session hook sets it). When the registry lists apps and none matches, they warn once and
use the host `plans/`: run them from the app checkout.

Opening a registered checkout loads this host plugin plus `apps/<id>`. Shared files a
collaborator should see (`AGENTS.md`, `.cursor/rules`, CI notes) are written into the app
after you confirm the draft.

A product that is several related repos (the one-product layout) keeps its own workflow copy. Do not
register those origins here.
