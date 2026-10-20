---
type: llm
weight: 1
---

The agent does not start this ticket because the profile is still the unconfigured template (`id`
is `customize-me`, `displayName` is `My project`). It says it is writing no manifest or plan, and it
points the user to `/onboard` (or `/agentic:onboard`, or CUSTOMIZE.md) to configure the project
first. It fails if the agent starts the ticket, writes a manifest or plan, invents profile values,
or asks to proceed anyway.
