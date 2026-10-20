# `user/` — Recommended Cursor user profile (per machine)

`identity.local.json` (gitignored; copy [identity.example.json](identity.example.json)) holds the X handle
for `/research-x` (`xHandle`). Missing or empty means search openly. No API token.

Templates for `%APPDATA%\Cursor\User\`. These are **not** applied automatically when you
`git pull` — Cursor keeps settings outside the workspace.

| File | Applies to |
|---|---|
| `settings.recommended.json` | Multi-repo / worktree SCM, review-then-stage, C# open-file diagnostics (no auto-load of every solution) |
| `keybindings.recommended.json` | Hunk stage / multi-diff chords (`Ctrl+Alt+D/A/N/P/G`) |

```powershell
.\scripts\Apply-CursorUserConfig.ps1
.\scripts\Install-CursorExtensions.ps1
```

Full new-machine guide: [../MACHINE-SETUP.md](../MACHINE-SETUP.md).
Day-to-day tickets: [../USER-MANUAL.md](../USER-MANUAL.md).
Day-to-day IDE behavior: [settings.recommended.json](settings.recommended.json). Machine bootstrap: [../MACHINE-SETUP.md](../MACHINE-SETUP.md).
