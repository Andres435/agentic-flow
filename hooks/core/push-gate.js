"use strict";

/**
 * Fail-closed gate for git push. Names no IDE.
 *
 * A push of a workflow repo clone runs that clone's own Assert-AgenticFlow.ps1, so an
 * installed plugin copy still checks the clone being pushed, not itself.
 * A push from a product repo whose branch names a ticket (profile.ticketPrefix) with a
 * manifest in this clone's plans/ runs Assert-TicketArtifacts -Phase prepush: unverified,
 * unreviewed, or un-Driven work does not leave the machine. Any other push passes untouched.
 * When no PowerShell host is on PATH the gate skips (cannot run the .ps1) and CI still runs
 * the repo gate.
 */

const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const { gitCalls, workflowRoot, ASSERT_REL } = require("./git-target.js");
const { loadProfile } = require("./session-context.js");

/** Directories a command pushes from (see git-target.js for what counts as a push). */
function pushDirs(command, cwd) {
  return gitCalls(command, cwd, "push").map((call) => call.dir);
}

// PowerShell 7 only (see pwsh.js): Windows PowerShell 5.1 would refuse the #Requires -Version 7
// gate scripts and turn every push into a confusing deny.
const { findPowerShell } = require("./pwsh.js");

const NO_PWSH = "PowerShell 7 (pwsh) is not on PATH, so this check was skipped. Install it (MACHINE-SETUP.md); CI still runs the repo gate.";

function runAssert(root) {
  const host = findPowerShell();
  if (!host) {
    return { ok: true, skipped: true, output: "Assert-AgenticFlow skipped: " + NO_PWSH };
  }
  const r = spawnSync(
    host,
    ["-NoProfile", "-NonInteractive", "-File", path.join(root, ASSERT_REL), "-Root", root],
    { encoding: "utf8", timeout: 120000 }
  );
  const output = (String(r.stdout || "") + String(r.stderr || "")).trim();
  if (r.error) return { ok: false, output: String(r.error.message || r.error) };
  return { ok: r.status === 0, output };
}

// The workflow clone this hook runs from: its plans/ holds the ticket manifests.
const WORKFLOW_HOME = path.resolve(__dirname, "..", "..");

/** The <ticket> (profile.ticketPrefix + digits) a product repo's current branch names, or null. */
function ticketFromBranch(dir) {
  const r = spawnSync("git", ["-C", dir, "rev-parse", "--abbrev-ref", "HEAD"], { encoding: "utf8", timeout: 5000 });
  if (r.error || r.status !== 0) return null;
  const profile = loadProfile();
  const prefix = String((profile && profile.ticketPrefix) || "TICKET-");
  const escaped = prefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const m = String(r.stdout || "").trim().match(new RegExp("(?:^|[/_-])" + escaped + "(\\d+)(?:$|[/_-])", "i"));
  return m ? prefix + m[1] : null;
}

/**
 * A ticket branch pushed from a product repo must carry the work checks of close:
 * verify receipts, review stamps with no open Blocker/Major, and the frontend Drive.
 * Only a branch whose ticket has a manifest in this workflow clone is gated.
 */
function runPrepush(ticket) {
  const manifest = path.join(WORKFLOW_HOME, "plans", ticket + "-manifest.json");
  if (!fs.existsSync(manifest)) return null;
  const host = findPowerShell();
  if (!host) {
    return { ok: true, skipped: true, output: "Assert-TicketArtifacts prepush skipped: " + NO_PWSH };
  }
  const script = path.join(WORKFLOW_HOME, "scripts", "ticket", "Assert-TicketArtifacts.ps1");
  const r = spawnSync(host, ["-NoProfile", "-NonInteractive", "-File", script, "-Ticket", ticket, "-Phase", "prepush"], {
    encoding: "utf8",
    timeout: 120000,
  });
  const output = (String(r.stdout || "") + String(r.stderr || "")).trim();
  if (r.error) return { ok: false, kind: "ticket", ticket, output: String(r.error.message || r.error) };
  return { ok: r.status === 0, kind: "ticket", ticket, output };
}

/** Gate every workflow clone and every ticket branch the command pushes; null when nothing failed. */
function gate(command, cwd) {
  const roots = [];
  const tickets = [];
  for (const dir of pushDirs(command, cwd)) {
    const root = workflowRoot(dir);
    if (root) {
      if (roots.indexOf(root) === -1) roots.push(root);
      continue;
    }
    const ticket = ticketFromBranch(dir);
    if (ticket && tickets.indexOf(ticket) === -1) tickets.push(ticket);
  }
  for (const root of roots) {
    const result = runAssert(root);
    if (!result.ok) return result;
  }
  for (const ticket of tickets) {
    const result = runPrepush(ticket);
    if (result && !result.ok) return result;
  }
  return null;
}

function denyMessage(output, failed) {
  const snippet = output ? output.slice(0, 1500) : "(no output)";
  if (failed && failed.kind === "ticket") {
    return (
      "Push blocked: " + failed.ticket + " is not ready to leave this machine (Assert-TicketArtifacts -Phase prepush). " +
      "Verify, review, or Drive the work it names, then push again.\n" + snippet
    );
  }
  return "Push blocked: agentic-flow checks failed. Fix the violations, then push again.\n" + snippet;
}

/**
 * After the gate itself threw: true when the command still pushes a workflow clone, so a
 * bridge denies instead of letting an unchecked push through. A push from any other repo
 * stays allowed. If even the lookup throws, any segment that pushes counts.
 */
function failsClosed(command, cwd) {
  try {
    return pushDirs(command, cwd).some((dir) => Boolean(workflowRoot(dir)));
  } catch {
    return /(^|[;&|\n])\s*(&\s*)?git(\.exe)?\b[^;&|\n]*\bpush\b/i.test(String(command || ""));
  }
}

function crashMessage(error) {
  const why = error && error.message ? error.message : String(error || "unknown error");
  return (
    "Push blocked: the agentic-flow push gate failed to run (" + why + "). " +
    "Run scripts/ticket/Assert-AgenticFlow.ps1 by hand; details are in scripts/.hook-errors.log."
  );
}

module.exports = { gate, runAssert, denyMessage, failsClosed, crashMessage, pushDirs, workflowRoot };
