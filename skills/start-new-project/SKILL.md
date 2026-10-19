---
name: start-new-project
description: Greenfield product. Interviews for stack, devops, and context, writes apps/<id>/ on this host, scaffolds the new app. Does not start a ticket.
keywords: new project, greenfield, profile, customize, interview
disable-model-invocation: true
icon: folder-plus
color: brand
---

# Start new project

Use this for a **blank** product, before `/start-ticket`. An existing checkout is
[`/adopt-project`](../adopt-project/SKILL.md). Ask at most five questions per turn. Write nothing
until that batch is answered. Do not invent defaults.

A product that is several related repos (one workspace copy of this workflow) still fills the
**host** `profile.json` here, as before. Unrelated personal apps get a folder under `apps/<id>/`.

## Do not

- Copy another product's specialists, environment cards, or launch scripts.
- Invent a framework or add keys `profile.json` does not already have.
- Edit `slashCommands` or `epochRerateAfter` on the host `profile.json`.
- Overwrite a host profile whose `id` is no longer `customize-me` without asking first, when this
  clone is itself the product.
- Start a ticket, a stack, or a browser.
- Run `gh repo create` until the user confirms that step separately.

## Interview

1. **Where it lives.** Host-as-product (fill root `profile.json`) or personal app on this host
   (`apps/<id>/`). Existing application files in the opened folder → stop and send the user to
   `/adopt-project`.
2. **Product.** `id` (short slug) and `displayName`.
3. **Tracker.** `ticketSystem`: `none`, `github-issues`, or `ado`. `ticketPrefix` such as `TICKET-`, `#`, or `WI`.
4. **Repos.** One or more `{ name, path, layers }`. Path `.` means the app checkout. `dependencyOrder` in build order. `layout`: `monorepo` or `multi-repo`. `baseBranchDefault`.
5. **Worktrees.** `worktreeSupported` true or false. `defaultMode` stays `branch` unless the user asks for `worktree`.
6. **Stack.** Each local app is one `stacks.services` object. Ask per service, offering the matching recipe from [CUSTOMIZE.md](../../CUSTOMIZE.md#stack-recipes): `name`, `command` (long-running), `cwd` (relative to the **app checkout**), `setup`, `stop`, `port` and `url`, `ready`, `dependsOn`, and any `env` (use `${env:NAME}`, never a secret). No local stack: leave `services` as `[]`.
7. **Devops.** How CI and deploy will run (GitHub Actions stub, none, other). Enough to write a stub, not a full pipeline.
8. **Specialist.** The stack in one paragraph. `specialists` lists that file's name without `.md`.
9. **Local context.** Ports, URLs, prerequisites, gotchas. No secrets. Personal identity for `context.md`.
10. **Optional.** `adrIndex` path or null. `integrations` names that match cards under `environments/`.

## Writes

After the user confirms the draft, write `stacks` as `{ "default": "all", "presets": { "all": [] }, "services": [ ... ] }` (add the user's presets beside `all`); do not write `startCommand`. Do not put a secret or a machine-specific absolute path in any profile.

### Personal app on this host

1. `apps/<id>/profile.json`, `context.md`, `environments/local-dev.md`, specialist under `apps/<id>/agents/` if needed, `.cursor-plugin/plugin.json` (rules and agents only).
2. `apps/registry.json` — `{ "id", "origin" }` once origin is known (after `gh`, or a path they name).
3. Scaffold the new app: README, gitignore, `AGENTS.md`, shared `.cursor/rules`, and a CI stub that matches the chosen devops. Personal `context.md` stays in the host.
4. [CUSTOMIZE.md](../../CUSTOMIZE.md) — record the **Choices** for this app under the registry section.

### Host-as-product

1. Root `profile.json` — replace only the product fields. Keep `slashCommands` and `epochRerateAfter`.
2. `environments/local-dev.md` — replace the stub.
3. `agents/fullstack-specialist.md` — replace the stub. Keep `name` and `description` frontmatter.
4. `CUSTOMIZE.md` — check the three status boxes and fill **Choices**.

Then tell the user the next command is `/doctor`, then `/start-ticket <id> feature`. Creating the
GitHub repo with `gh` is a separate confirmed step.
