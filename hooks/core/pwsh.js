"use strict";

/** Shared PowerShell 7 lookup for hooks. Names no IDE. */

const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

// PowerShell 7 only. The workflow scripts carry #Requires -Version 7, so Windows PowerShell
// 5.1 would refuse them. Probes by running pwsh (up to 8s): for gates that can afford it.
function findPowerShell() {
  const r = spawnSync("pwsh", ["-NoProfile", "-NonInteractive", "-Command", "exit 0"], {
    timeout: 8000,
    encoding: "utf8",
  });
  return !r.error && r.status === 0 ? "pwsh" : null;
}

/** Instant, spawn-free lookup: "pwsh" when an executable of that name is on PATH, else null. */
function findPwshOnPath(env = process.env) {
  const dirs = String(env.PATH || env.Path || "").split(path.delimiter).filter(Boolean);
  const names = process.platform === "win32" ? ["pwsh.exe", "pwsh.cmd", "pwsh.bat"] : ["pwsh"];
  for (const dir of dirs) {
    for (const name of names) {
      try {
        if (fs.statSync(path.join(dir, name)).isFile()) return "pwsh";
      } catch {
        // not here
      }
    }
  }
  return null;
}

module.exports = { findPowerShell, findPwshOnPath };
