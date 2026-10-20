---
type: regex
pattern: '"repo"\s*:\s*"app"'
target:
  source: file
  path: plans/TICKET-00002-manifest.json
---
Only a repo from profile.repos, here the one named in the ticket.
