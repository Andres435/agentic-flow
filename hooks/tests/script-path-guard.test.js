#!/usr/bin/env node
"use strict";

/**
 * Tests for hooks/core/script-path-guard.js and its Claude and Cursor adapters.
 * Run: node hooks/tests/script-path-guard.test.js
 */
const assert = require("assert");
const { spawnSync } = require("child_process");
const path = require("path");

const { decideWrite, decideRun } = require("../core/script-path-guard.js");
const CLAUDE = path.join(__dirname, "..", "..", "adapters", "claude", "hooks", "script-path-guard.js");
const CURSOR = path.join(__dirname, "..", "..", "adapters", "cursor", "hooks", "script-path-guard.js");

let passed = 0;
let failed = 0;
function check(name, fn) {
  try {
    fn();
    passed++;
    console.log("ok   " + name);
  } catch (err) {
    failed++;
    console.log("FAIL " + name + "\n     " + err.message);
  }
}

const REPO = String.raw`C:\Users\a\source\repos\app`;
const TEMP = String.raw`C:\Users\a\AppData\Local\Temp\claude\scratchpad`;

// The guard is opt-in: with no allowed root configured it allows everything.
delete process.env.AGENTIC_SCRIPT_ALLOW_ROOT;
check("off by default: a script in temp is allowed", () => {
  assert.strictEqual(decideWrite(TEMP + String.raw`\x.ps1`), null);
  assert.strictEqual(decideRun(String.raw`pwsh -File "` + TEMP + String.raw`\x.ps1"`), null);
});
// The anchored example from MACHINE-SETUP.md. The home prefix expands to os.homedir(), which
// reads USERPROFILE on Windows and HOME elsewhere; pin both so the tests run the same anywhere.
process.env.AGENTIC_SCRIPT_ALLOW_ROOT = String.raw`^(?:[A-Za-z]:[\\/]Users[\\/][^\\/]+|/(?:home|Users)/[^/]+)[\\/]source[\\/]repos[\\/]`;
process.env.USERPROFILE = String.raw`C:\Users\a`;
process.env.HOME = String.raw`C:\Users\a`;

check("write: script in temp is denied", () => assert(decideWrite(TEMP + String.raw`\x.ps1`)));
check("write: python in Documents is denied", () => assert(decideWrite(String.raw`C:\Users\a\Documents\GitHub\x.py`)));
check("write: script under source\\repos is allowed", () => assert.strictEqual(decideWrite(REPO + String.raw`\scripts\x.ps1`), null));
check("write: forward-slash repo path is allowed", () => assert.strictEqual(decideWrite("C:/Users/a/source/repos/t/x.ps1"), null));
check("write: non-script in temp is allowed", () => assert.strictEqual(decideWrite(TEMP + String.raw`\notes.md`), null));
check("write: relative path is allowed", () => assert.strictEqual(decideWrite("scripts/x.ps1"), null));
check("write: .. out of source\\repos is denied", () =>
  assert(decideWrite(REPO + String.raw`\..\..\..\AppData\Local\Temp\x.ps1`)));

check("write: source\\repos nested under another folder is denied", () =>
  assert(decideWrite(String.raw`C:\Temp\source\repos\x.ps1`)));
check("write: <allowed>\\..\\..\\Temp is denied", () =>
  assert(decideWrite(String.raw`C:\Users\a\source\repos\..\..\Temp\x.ps1`)));
check("write: ~ inside the root is allowed", () => assert.strictEqual(decideWrite("~/source/repos/app/x.ps1"), null));
check("write: ~ outside the root is denied", () => assert(decideWrite("~/AppData/Local/Temp/x.ps1")));

check("run: source\\repos nested under another folder is denied", () =>
  assert(decideRun(String.raw`pwsh -File C:\Temp\source\repos\x.ps1`)));
check("run: <allowed>\\..\\..\\Temp is denied", () =>
  assert(decideRun(String.raw`pwsh -File C:\Users\a\source\repos\..\..\Temp\x.ps1`)));
check("run: %USERPROFILE% inside the root is allowed", () =>
  assert.strictEqual(decideRun(String.raw`pwsh -File %USERPROFILE%\source\repos\app\x.ps1`), null));
check("run: %USERPROFILE% outside the root is denied", () =>
  assert(decideRun(String.raw`pwsh -File %USERPROFILE%\Downloads\x.ps1`)));
check("run: ~ and $HOME inside the root are allowed", () => {
  assert.strictEqual(decideRun("python ~/source/repos/app/x.py"), null);
  assert.strictEqual(decideRun("pwsh $HOME/source/repos/app/x.ps1"), null);
});
check("run: ~ and $env:USERPROFILE outside the root are denied", () => {
  assert(decideRun("python ~/Documents/x.py"));
  assert(decideRun(String.raw`pwsh $env:USERPROFILE\source\repos\..\..\x.ps1`));
});
check("run: pwsh -File in temp is denied", () => assert(decideRun('pwsh -File "' + TEMP + String.raw`\x.ps1"`)));
check("run: python in /tmp is denied", () => assert(decideRun("python /tmp/x.py")));
check("run: env-rooted TEMP is denied", () => assert(decideRun(String.raw`pwsh $env:TEMP\x.ps1`)));
check("run: repo script is allowed", () =>
  assert.strictEqual(decideRun("pwsh -File " + REPO + String.raw`\scripts\ticket\Resolve-TicketRoot.ps1`), null));
check("run: relative script is allowed", () => assert.strictEqual(decideRun("pwsh ./scripts/x.ps1"), null));
check("run: inline command is allowed", () => assert.strictEqual(decideRun("pwsh -Command 'Get-Date'"), null));
check("run: deleting a temp script is allowed", () =>
  assert.strictEqual(decideRun("Remove-Item " + TEMP + String.raw`\x.ps1`), null));

function spawn(file, input) {
  return spawnSync("node", [file], { input: JSON.stringify(input), encoding: "utf8" });
}

check("claude: Write to temp emits a deny", () => {
  const r = spawn(CLAUDE, { tool_name: "Write", tool_input: { file_path: TEMP + String.raw`\x.ps1` } });
  assert.strictEqual(JSON.parse(r.stdout).hookSpecificOutput.permissionDecision, "deny");
});
check("claude: Bash of a repo script is silent", () => {
  const r = spawn(CLAUDE, { tool_name: "Bash", tool_input: { command: "pwsh " + REPO + String.raw`\scripts\x.ps1` } });
  assert.strictEqual(r.stdout, "");
});
check("claude: bad JSON degrades silently", () => {
  // The swallowed error is logged; point the log at a temp file so the real one stays clean.
  const log = require("path").join(require("os").tmpdir(), "spg-hook-errors-" + process.pid + ".log");
  const r = spawnSync("node", [CLAUDE], { input: "{", encoding: "utf8", env: { ...process.env, TMO_HOOK_ERRORS_FILE: log } });
  assert.strictEqual(r.status, 0);
  require("fs").rmSync(log, { force: true });
});
check("cursor: temp script run is denied, repo run allowed", () => {
  assert.strictEqual(JSON.parse(spawn(CURSOR, { command: "pwsh " + TEMP + String.raw`\x.ps1` }).stdout).permission, "deny");
  assert.strictEqual(JSON.parse(spawn(CURSOR, { command: "pwsh " + REPO + String.raw`\x.ps1` }).stdout).permission, "allow");
});

console.log("\n" + passed + " passed, " + failed + " failed");
process.exit(failed ? 1 : 0);
