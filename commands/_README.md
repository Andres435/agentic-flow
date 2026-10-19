# `commands/` — menu notes

Slash workflows are skills: `skills/<name>/SKILL.md`, with `playbooks/` and `references/` beside that file.
This folder no longer holds slash entries. A command file whose name matches a skill shows up twice.

| Goal | Command |
|---|---|
| Fill profile, env card, and specialist on a new product | `/start-new-project` |
| Attach an existing GitHub checkout | `/adopt-project` |
| Search X on a spike (optional, no API) | `/research-x` |
| Pin for ad-hoc work or a long chat. Do not type it in the same message as a ticket command | `/engineering-mode` |
| Start a ticket | `/start-ticket <id> bug\|feature\|spike\|refactor` |
| Build in a fresh chat | `/implement <id>` |
| Start, swap, or stop the local stack | `/start-stack`, `/swap-stack`, `/stop-stack` |
| Review ticket files; stage the clean ones | `/review-changes` |
| Closeout package | `/complete-task` |
| Commit, push, and open the PR after approval | `/prep-pr` |
| Triage review feedback | `/address-pr-comments` |
| Review a coworker's PR | `/peer-review <id>` |
| Health check | `/doctor` |
| Machine setup | `/onboard` |

Branch mode: `/start-ticket` (plan and build), `/review-changes`, `/complete-task`. Chat counts per
mode: [USER-MANUAL.md](../USER-MANUAL.md). `/implement` is only for a fresh chat.
Stack smoke (`Get-StackSmoke.ps1`) is a close gate when a frontend repo's change touches a
`uiGlobs` file type (a user-confirmed Drive), and optional for the rest. Plan shapes (`bug-fix`, `feature-plan`, `tech-spike`, `document-spike`) are not slash commands.

Icons: run `scripts/Install-UserCursorCommands.ps1`, then reload. Cursor paints badges on user skills, not on plugin copies.
