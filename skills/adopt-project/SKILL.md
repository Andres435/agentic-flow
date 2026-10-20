---
name: adopt-project
description: Attach an existing GitHub repo to this host. Read the checkout, fill apps/<id>, ask only where the repo is silent, write shared files into the app.
keywords: adopt, existing repo, detect, profile, registry
disable-model-invocation: true
icon: folder-git
color: brand
---

# Adopt project

Use this when the checkout already has application code. A blank product is
[`/start-new-project`](../start-new-project/SKILL.md). Write the overlay under `apps/<id>/` in this
host. Do not copy another app's specialists.

## Do not

- Rewrite application source.
- Invent a stack the repo does not use.
- Edit `slashCommands` or `epochRerateAfter` on the **host** `profile.json`.
- Put secrets or machine-absolute paths in `apps/<id>/profile.json`.
- Start a ticket, a stack, or a browser.

## Detect

From the opened checkout, read what exists and pre-fill:

| Signal | Field |
|---|---|
| `git remote get-url origin` | registry `origin`; `id` from the repo name |
| `package.json`, `*.csproj`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `Gemfile` | stack recipes in [CUSTOMIZE.md](../../CUSTOMIZE.md#stack-recipes) |
| `.github/workflows/`, `azure-pipelines.yml`, `Dockerfile`, `docker-compose.yml` | devops notes |
| README ports / scripts | `stacks.services` command, port, url |
| `AGENTS.md`, `.cursor/rules/` | already shared; do not duplicate |

Ask at most five questions per turn, only where the repo is silent or two signals contradict.
Do not invent defaults for tracker, ticket prefix, or worktrees.

## Writes (after the user confirms the draft)

1. `apps/<id>/` — `profile.json` (`stacks` as `{ "default": "all", "presets": { "all": [] }, "services": [ ... ] }`; no `startCommand`), `context.md`, `environments/local-dev.md`, `rules/` as needed, `.cursor-plugin/plugin.json` (rules and agents only).
2. `apps/registry.json` — append `{ "id", "origin" }` (create it from `registry.example.json` when missing). It and `apps/<id>/` are gitignored: never stage them.
3. In the **app** checkout, only files that are missing: `AGENTS.md`, shared `.cursor/rules`, and a CI note that matches the detected devops. Personal `context.md` stays in the host.

Then tell the user the next command is `/doctor`, then `/start-ticket <id> feature`.
