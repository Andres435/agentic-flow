---
type: regex
pattern: '\bTBD\b|resolve during implement'
match: not_contains
target:
  source: file
  path: plans/TICKET-00002-feature-plan.md
---
No unresolved placeholder rides into the persisted plan.
