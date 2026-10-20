---
name: closeout-search
description: How start-ticket searches prior ticket memory so past gotchas feed the next ticket without dumping every plans/ file into context.
keywords: closeout search, priorFindings, ticket memory, closeout-index, lessons, Search-CloseoutMemory
---

# Closeout Search (ticket memory)

`plans/closeout-index.md` is the compounding knowledge store: one dense row per durable lesson, and
the only surface worth searching. Search it, then keep at most **8** compact lessons on the manifest.

Do **not** read `plans/<ticket>-closeout.md` files. Those exist only for the rare ticket whose
retrospective earned a page ([task-retrospective.md](../../complete-task/references/task-retrospective.md)), and the lesson from any
such ticket is already in the index.

## When

In the `/start-ticket` step 5 fan-out, once the manifest (written at step 3 with
`priorFindings: []`) has `affectedRepos`; update `priorFindings` on the manifest when the results
land. The rule is the router's [Prior closeouts](../SKILL.md#prior-closeouts) section; this file is
the detail and the fallback. Re-run if scope changes (new repo or integration).

## How

1. Build a query from the ticket's title, area, integration, and affected repos.
2. Prefer the script (compact JSON) — once per affected repo, plus one integration-only pass when
   `integration` ≠ `none`:

   ```powershell
   .\.cursor\scripts\ticket\Search-CloseoutMemory.ps1 -Query "<title keywords>" -Repos <repo> -MaxResults 4
   .\.cursor\scripts\ticket\Search-CloseoutMemory.ps1 -Query "<title keywords>" -Integration <name> -MaxResults 4
   ```

   Fallback when the script fails: `Grep` `plans/closeout-index.md` directly.
3. Union, dedupe by ticket id, cap 8, and copy into manifest `priorFindings[]` (`ticket` + one-line `lesson`).
4. Do **not** add closeout files to `docSet`. If a lesson needs detail and that ticket happens to
   have a `<ticket>-closeout.md`, read **only** its **Other findings** slice.

## Guardrails

- Skip when there are no closeouts / index yet; `priorFindings` is `[]`.
- Ticket-specific leftovers (unstaged Web.config, unrelated PRs) stay out of `priorFindings`.
- Durable setup that repeats belongs on an environment card; the index is the retrieval surface
  until a card exists.
