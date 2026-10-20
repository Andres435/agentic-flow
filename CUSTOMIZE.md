# Customize this workflow for your project

Two layouts:

- **One product** (TMO-style). This clone sits next to related repos. `/start-new-project` fills
  the root `profile.json`, the status boxes below, and `environments/local-dev.md`.
- **Many small GitHub apps.** Keep this host (`agentic-flow`) once. `/start-new-project` (blank
  product) or `/adopt-project` (existing checkout) writes `apps/<id>/` and a row in
  [apps/registry.json](apps/registry.json). Personal context stays here; `AGENTS.md` and shared
  rules go in the app.

Hand-editing still works. Sections marked `(required)` must be done before `/start-ticket`.

**Rule:** these blanks are setup and context. After they are filled, `/start-ticket` and the rest of
the workflow run **automatically** from that profile — they will not re-interview you for repos,
stack, or specialists.

## Status

`/start-new-project` or `/adopt-project` checks these and records the answers under Choices.

- [ ] `profile.json`
- [ ] `environments/local-dev.md`
- [ ] Specialists recorded in `profile.json`

## Choices

Filled by `/start-new-project`. Leave this blank until that command runs.

- **Product:**
- **Tracker:**
- **Layout:**
- **Stack:**
- **Overlay:**

---

## 1. Edit `profile.json` (required)

Open `profile.json` and fill in your project's values:

| Field | What to set |
|---|---|
| `id` | Short slug for your project (e.g. `my-app`) |
| `displayName` | Human-readable project name |
| `ticketSystem` | `none` \| `github-issues` \| `ado` |
| `ticketPrefix` | Ticket ID prefix (e.g. `TICKET-`, `#`, `WI`) |
| `repos[].name` | Your repo name(s) |
| `repos[].path` | Path relative to the `.cursor` folder (`.` for same repo) |
| `specialists` | Match names to agent files in `agents/` |
| `stacks.services` | One object per local app: `name`, `command`, plus optional `cwd`, `setup`, `stop`, `env`, `port`, `url`, `ready`, `dependsOn`. `/start-new-project` fills this; empty means no local stack. See [Stack recipes](#stack-recipes) |
| `stacks.presets` | Name to service names (empty list = all). `stacks.default` names the preset used when none is given |
| `uiGlobs` | File types that count as UI (default `*.js`, `*.jsx`, `*.ts`, `*.tsx`, `*.css`, `*.scss`, `*.html`). Close needs a user-confirmed Drive only when a `frontend` repo's change touches one; add your templates (e.g. `*.vue`, `*.cshtml`) |

**Multi-repo:** add one object per repo to `repos[]` in dependency order (e.g. `["shared", "api", "web"]`).

---

## 2. Fill `environments/local-dev.md` (required)

Replace the stub with your actual:
- Ports and URLs
- Prerequisites and install steps
- Common gotchas (missing env vars, certs, auth tokens)

---

## 3. Customize the fullstack specialist (required)

Edit `agents/fullstack-specialist.md` with your actual tech stack and key conventions. Add more
specialist files if needed (e.g. `backend-specialist.md`, `frontend-specialist.md`) and list them
in `profile.json` → `specialists`.

---

## 4. Set up ticket system (if not `none`)

### GitHub Issues

Add `github-ticket-workflow.md` under `skills/start-ticket/references/` with your intake steps.
See `skills/start-ticket/references/ticket-intake-generic.md` for the pattern.

### Azure DevOps (ADO)

Add `ado-ticket-workflow.md` under `skills/start-ticket/references/` (fetch, required fields, the State
moves you allow) and, if you write fields back, `ado-field-mapping.md`. Use
`ticket-intake-generic.md` as the pattern. Add an `ado` server to `mcp.json` (token in a user
environment variable). Then set `ticketSystem: "ado"` and `ticketPrefix: "WI"` in `profile.json`.

---

## 5. Bootstrap the machine (one-time per machine)

```powershell
scripts/machine/Initialize-WorkflowMachine.ps1
```

This reports missing tools, writes the Claude Code overlay, and installs the git hooks. Phases for
Cursor extensions, user settings, and a cockpit workspace run only when your overlay adds their
scripts to `scripts/machine/`. Details: [MACHINE-SETUP.md](MACHINE-SETUP.md).

---

## 6. Start your first ticket

```
/start-ticket TICKET-1 feature
```

Or with GitHub Issues:
```
/start-ticket #1 feature
```

---

## Stack recipes

`stacks` is blanks to fill, never code to write. `/start-stack`, `/stop-stack` and `/swap-stack` work for
any runtime once each local app is one object in `stacks.services`. Empty `services` means no local
stack. Paste a recipe, change the names, paths and ports, and run `/doctor`.

| Field | Meaning |
|---|---|
| `name` (required) | Unique label. `dependsOn` and presets refer to it |
| `command` (required) | The long-running process. It stays in the foreground (`npm run dev`, `dotnet run`, `docker compose up`) |
| `cwd` | Folder to run in, relative to the folder holding `profile.json`. Default `.` |
| `setup` | Run once before `command`, only with `-Setup` (install, restore). Must exit 0 |
| `stop` | Runs after the process tree is killed, in `cwd` (for example `docker compose down`) |
| `env` | Object of environment variables for this service. Use `"${env:NAME}"` to read a value from your own environment at start. Literal secrets fail `/doctor` |
| `port`, `url` | The port is checked before start (a listener there is skipped, not killed). The url is printed |
| `ready` | `{ "port": true }` or `{ "url": "http://localhost:5000/health" }`, plus optional `timeoutSec` (default 60). The launcher waits before it starts the next service |
| `dependsOn` | Service names that must start (and be ready) first |

`stacks.presets` maps a name to the service names it starts (an empty list means all). Dependencies are
added for you. `stacks.default` is the preset used when none is given. Run
`/start-stack <ticket> <preset>`; `/swap-stack` keeps the same preset.

The old single `stacks.startCommand` field is retired. A profile that still has it (and no `services`)
runs it as one service named `app` and prints a warning; move it into `services`.

**Vite or Next.js**

```json
{ "name": "web", "command": "npm run dev", "setup": "npm install", "port": 5173,
  "url": "http://localhost:5173", "ready": { "port": true } }
```

Next.js: same shape, `"port": 3000`, `"url": "http://localhost:3000"`.

**.NET**

```json
{ "name": "api", "command": "dotnet run --project src/Api", "setup": "dotnet restore",
  "port": 5000, "url": "http://localhost:5000", "ready": { "url": "http://localhost:5000/health" } }
```

**Python (uvicorn)**

```json
{ "name": "api", "command": "uvicorn app.main:app --port 8000", "setup": "pip install -r requirements.txt",
  "port": 8000, "url": "http://localhost:8000", "ready": { "port": true } }
```

**Java (Gradle Spring Boot)**

```json
{ "name": "api", "command": "./gradlew bootRun", "port": 8080, "url": "http://localhost:8080",
  "ready": { "port": true, "timeoutSec": 120 } }
```

**Go**

```json
{ "name": "api", "command": "go run .", "port": 8080, "url": "http://localhost:8080", "ready": { "port": true } }
```

**Docker Compose**

```json
{ "name": "stack", "command": "docker compose up", "stop": "docker compose down",
  "url": "http://localhost:8080", "ready": { "url": "http://localhost:8080/health", "timeoutSec": 180 } }
```

**API plus web, with a preset**

```json
"stacks": {
  "default": "all",
  "presets": { "all": [], "web": ["web"] },
  "services": [
    { "name": "api", "command": "dotnet run --project src/Api", "port": 5000,
      "env": { "ConnectionStrings__Db": "${env:APP_DB_CONNECTION}" }, "ready": { "port": true } },
    { "name": "web", "command": "npm run dev", "cwd": "web", "port": 5173,
      "url": "http://localhost:5173", "dependsOn": ["api"], "ready": { "port": true } }
  ]
}
```

`/start-stack <ticket> web` starts `api` first (a dependency), then `web`. `/stop-stack` stops `web`, then `api`.

---

## What NOT to edit

These are **core** files — leave them alone unless you are upgrading the workflow:

- `skills/` (add your own skills beside them; add intake references under
  `skills/start-ticket/references/`)
- `hooks/`, `hooks.json`, `adapters/`, `output-styles/`
- `scripts/ticket/`, `scripts/machine/`
- `_shared/`

---

## Getting upstream updates

```bash
# From this folder, with the template added as the upstream remote
git fetch upstream
git checkout upstream/main -- skills/ _shared/ scripts/ticket/ scripts/machine/ hooks/ adapters/ output-styles/
```

That overwrites core skill folders, so re-add any project skill or intake reference you keep under
`skills/`, then run `scripts/ticket/Assert-AgenticFlow.ps1`. Your overlay (`profile.json`,
`environments/`, `agents/`, `mcp.json`) is not touched.
