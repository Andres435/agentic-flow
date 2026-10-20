## What and why

<!-- One concern per PR. What changes, and the problem it fixes. -->

## Core or overlay

<!-- Core (skills, _shared, gates, hooks, adapters) or overlay? See TEMPLATE.md. -->

## Checks

- [ ] `pwsh ./scripts/ticket/Assert-AgenticFlow.ps1` prints `[PASS]`
- [ ] `node --test hooks/tests/*.test.js adapters/claude/hooks/tests/*.test.js` passes
- [ ] Docs that describe a changed gate, hook, or script are updated (or a `Docs-Unaffected:` trailer explains why not)
- [ ] No product-specific or personal strings in core files
