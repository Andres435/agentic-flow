"use strict";

/**
 * Script path guard (opt-in). Some machines run an application allowlist (for example
 * ThreatLocker) that lets .ps1 and .py run only from under one folder, and every blocked
 * attempt is an approval request to the user. Set AGENTIC_SCRIPT_ALLOW_ROOT to a regular
 * expression anchored to the allowed path, for example
 * `^(?:[A-Za-z]:[\\/]Users[\\/][^\\/]+|/(?:home|Users)/[^/]+)[\\/]source[\\/]repos[\\/]`, and this
 * hook denies writing or running such a script anywhere else (temp, an agent scratchpad,
 * Documents) so the attempt never reaches the allowlist. Leave the `^` in: an unanchored pattern
 * lets C:\Temp\source\repos\x.ps1 through. A home prefix (~, $HOME, $env:USERPROFILE,
 * %USERPROFILE%) is expanded and `..` collapsed before matching. With the variable unset it
 * allows everything. Names no IDE; the Cursor and Claude hooks translate { action, reason }.
 *
 *   write  tool_input.file_path of a Write/Edit
 *   run    a shell command that names a .ps1/.py by an absolute or env-rooted path
 */

const os = require("os");
const path = require("path");
const SCRIPT = /\.(?:ps1|py)$/i;
const HOME_PREFIX = /^(?:~|\$HOME|\$env:USERPROFILE|%USERPROFILE%)(?=[\\/])/i;
// Commands that only read, list or delete a path never execute it.
const INERT = /^\s*(?:rm|del|erase|ls|dir|cat|type|head|tail|stat|Remove-Item|Get-ChildItem|Get-Content|Test-Path|Get-Item)\b/i;
// An absolute, home-, or env-rooted token ending in .ps1/.py.
const ROOTED =
  /(?:^|[\s"'=(])((?:[A-Za-z]:[\\/]|~[\\/]|\/(?:tmp|var|c|home|Users)\/|%[A-Za-z]+%[\\/]|\$env:[A-Za-z]+[\\/]|\$HOME[\\/])[^\s"'|;&()]*\.(?:ps1|py))\b/gi;

const DENY_MSG =
  "This machine only runs .ps1/.py from an allowed folder (AGENTIC_SCRIPT_ALLOW_ROOT). Do not write or run a " +
  "script in temp, a scratchpad, or Documents. Run an inline `pwsh -Command`, run a script that already lives in " +
  "scripts/, or put a one-off in tmp/ (gitignored). New or changed scripts: use the " +
  "script-authoring skill (skills/script-authoring/SKILL.md).";

/** The allowed-path pattern from the environment, or null when the guard is off. */
function allowedPattern() {
  const raw = process.env.AGENTIC_SCRIPT_ALLOW_ROOT;
  if (!raw) return null;
  try {
    return new RegExp(raw, "i");
  } catch {
    return null;
  }
}

/**
 * Home prefix expanded and `..` collapsed, so ~\x.ps1 or repos\..\..\Temp\x.ps1 is judged by
 * where it really points.
 */
function normalize(p) {
  let s = String(p || "").replace(HOME_PREFIX, () => os.homedir());
  s = s.replace(/^\/([A-Za-z])\//, "$1:/"); // Git Bash /c/... -> C:/...
  return /^[A-Za-z]:/.test(s) ? path.win32.normalize(s) : path.posix.normalize(s);
}

function outsideAllowed(p) {
  const allowed = allowedPattern();
  return allowed ? !allowed.test(normalize(p)) : false;
}

function decideWrite(filePath) {
  const p = String(filePath || "");
  if (!SCRIPT.test(p)) return null;
  // A relative path resolves under the session's working directory, which is a repo.
  if (!/^(?:[A-Za-z]:[\\/]|\/|~)/.test(p)) return null;
  return outsideAllowed(p) ? { action: "deny", reason: DENY_MSG } : null;
}

function decideRun(command) {
  const cmd = String(command || "");
  if (INERT.test(cmd)) return null;
  ROOTED.lastIndex = 0;
  let m;
  while ((m = ROOTED.exec(cmd))) {
    if (outsideAllowed(m[1])) return { action: "deny", reason: DENY_MSG };
  }
  return null;
}

module.exports = { decideWrite, decideRun, DENY_MSG };
