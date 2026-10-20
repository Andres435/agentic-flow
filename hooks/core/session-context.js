"use strict";

/**
 * Session-start packet: compact profile + ticket-tree hydration. Names no IDE.
 *
 * Always carries { profileId, ticketSystem, layout } from profile.json when present.
 * Detects a ticket from the given folder hints using profile.ticketPrefix (default WI), or
 * else from the profile repos' current branches (one open ticket only),
 * runs Resolve-TicketRoot.ps1 -Ticket <id> -Json, and adds mode, root, rootExists, repos[]
 * and the next action. Adapters turn { label, compact, env } into their own output.
 */

const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const { writeHookError } = require("./hook-log");
const { resolveApp } = require("./resolve-app");

const REPO_ROOT = path.join(__dirname, "..", "..");

function loadProfile(overlayRoot) {
  const candidates = [];
  if (overlayRoot) candidates.push(path.join(overlayRoot, "profile.json"));
  candidates.push(
    path.join(REPO_ROOT, "profile.json"),
    path.join(process.cwd(), "profile.json"),
    path.join(process.cwd(), ".cursor", "profile.json")
  );
  const seen = new Set();
  for (const candidate of candidates) {
    const key = path.resolve(candidate);
    if (seen.has(key)) continue;
    seen.add(key);
    try {
      return JSON.parse(fs.readFileSync(candidate, "utf8"));
    } catch (error) {
      if (error && error.code !== "ENOENT") writeHookError("session-context", error);
    }
  }
  return null;
}

function readContextSnippet(contextPath) {
  if (!contextPath) return "";
  try {
    const text = fs.readFileSync(contextPath, "utf8").trim();
    if (!text) return "";
    return text.length > 2000 ? text.slice(0, 2000) + "…" : text;
  } catch {
    return "";
  }
}

function detectTicket(hints, profile) {
  const text = hints.filter(Boolean).join(" ");
  const configured = String((profile && profile.ticketPrefix) || "WI");
  const prefixes = configured === "WI" ? ["WI"] : [configured, "WI"];
  for (const prefix of prefixes) {
    const escaped = prefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const match = text.match(new RegExp("\\b" + escaped + "(\\d+)\\b", "i"));
    if (match) return prefix + match[1];
  }
  return null;
}

/**
 * Folder of one profile repos[] entry, relative to the repos root, or null to skip it.
 * Same rule as ManifestFields.ps1 Get-ProfileRepoDir (shared cases in
 * scripts/ticket/fixtures/profile-repo-dirs.json): path "." is the opened checkout, otherwise
 * clones live beside the workflow under their name, and path is only a fallback.
 */
function profileRepoDir(repo) {
  if (typeof repo === "string") return repo || null;
  if (!repo || typeof repo !== "object") return null;
  const rel = repo.path ? String(repo.path) : "";
  if (rel === ".") return ".";
  if (repo.name) return String(repo.name);
  return rel || null;
}

/**
 * Branch-mode fallback for a chat opened at the workspace root: read each profile repo's
 * current branch and keep the one ticket whose manifest is still open. Anything else
 * (no ticket branch, a closed ticket, two open tickets) returns null and the commands ask.
 */
function detectTicketFromBranches(profile, reposRoot, plansDir) {
  const prefix = String((profile && profile.ticketPrefix) || "WI");
  const escaped = prefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp("(?:^|[/_-])" + escaped + "(\\d+)$", "i");
  const repos = Array.isArray(profile && profile.repos) ? profile.repos : [];
  const open = new Set();
  for (const repo of repos) {
    const dir = profileRepoDir(repo);
    if (!dir) continue;
    const repoPath = dir === "." ? reposRoot : path.join(reposRoot, dir);
    if (!fs.existsSync(repoPath)) continue;
    let branch = "";
    try {
      branch = execFileSync("git", ["-C", repoPath, "branch", "--show-current"], {
        encoding: "utf8",
        timeout: 3000,
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();
    } catch {
      continue;
    }
    const match = branch.match(pattern);
    if (!match) continue;
    const key = prefix + match[1];
    try {
      const manifest = JSON.parse(fs.readFileSync(path.join(plansDir, key + "-manifest.json"), "utf8"));
      // A reopen keeps completedAtUtc; it is open again until reclosedAtUtc is set.
      const reopened = manifest.reopenedAtUtc && !manifest.reclosedAtUtc;
      if (!manifest.completedAtUtc || reopened) open.add(key);
    } catch {
      // no manifest: not a started ticket, so not a hint
    }
  }
  return open.size === 1 ? [...open][0] : null;
}

function resolveScript() {
  return path.join(REPO_ROOT, "scripts", "ticket", "Resolve-TicketRoot.ps1");
}

function parsesAsJson(text) {
  try {
    JSON.parse(String(text || "").trim());
    return true;
  } catch {
    return false;
  }
}

function runResolve(ticket) {
  const scriptPath = resolveScript();
  if (!fs.existsSync(scriptPath)) return null;
  // PowerShell 7 only: every script carries #Requires -Version 7, and Windows PowerShell
  // 5.1 misreads BOM-less UTF-8. Without pwsh the hook just has no resolve (MACHINE-SETUP.md).
  const shells = ["pwsh"];
  for (const shell of shells) {
    try {
      const result = execFileSync(
        shell,
        ["-NoProfile", "-NonInteractive", "-File", scriptPath, "-Ticket", ticket, "-Json"],
        { timeout: 6000, encoding: "utf8" }
      );
      return JSON.parse(String(result).trim());
    } catch (err) {
      if (!err || err.code !== "ENOENT") {
        // Exit 1 with JSON on stdout is Resolve-TicketRoot reporting a missing root (for
        // example a removed worktree). That is ticket state, not a hook error.
        if (!(err && err.status === 1 && parsesAsJson(err.stdout))) {
          writeHookError("session-context", err);
        }
        return null;
      }
    }
  }
  return null;
}

/**
 * manifest missing                       → "start-ticket"
 * manifest exists, no reviewReady stamp  → "review-changes"
 * reviewReady set, completedAtUtc null   → "complete-task"
 * completedAtUtc set                     → "closed", unless reopened (reopenedAtUtc set and no
 *                                          reclosedAtUtc): a reopen keeps completedAtUtc, so it
 *                                          is open again and takes the rows above
 * feedback.prs has a PR and ticket-ledger.md has no row for the ticket → "complete-task"
 * AGENTIC_PLANS_DIR overrides plans/ (tests).
 */
function ledgerHasTicket(plansDir, ticket) {
  let text;
  try {
    text = fs.readFileSync(path.join(plansDir, "ticket-ledger.md"), "utf8");
  } catch {
    return false;
  }
  const escaped = String(ticket).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp("^\\| " + escaped + " \\|", "m").test(text);
}

function manifestHasPr(manifest) {
  const prs = manifest && manifest.feedback && manifest.feedback.prs;
  return Array.isArray(prs) && prs.some((pr) => pr && (pr.id || pr.url));
}

function resolveNextAction(ticket, plansDirOverride) {
  const plansDir = plansDirOverride || process.env.AGENTIC_PLANS_DIR || path.join(REPO_ROOT, "plans");
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(path.join(plansDir, ticket + "-manifest.json"), "utf8"));
  } catch (error) {
    writeHookError("session-context", error);
    return "start-ticket";
  }
  if (manifestHasPr(manifest) && !ledgerHasTicket(plansDir, ticket)) return "complete-task";
  const reopened = manifest.reopenedAtUtc && !manifest.reclosedAtUtc;
  if (manifest.completedAtUtc && !reopened) return "closed";
  if (manifest.reviewReady) return "complete-task";
  return "review-changes";
}

/** null when there is nothing to say; otherwise { label, compact, env, text }. */
function buildPacket(hints) {
  const app = resolveApp({ hostRoot: REPO_ROOT, workspaceRoots: hints });
  const overlay = app ? app.overlay : REPO_ROOT;
  const plansDir = app ? app.plansDir : process.env.AGENTIC_PLANS_DIR || path.join(REPO_ROOT, "plans");
  const profile = loadProfile(overlay);
  const slice = profile
    ? { profileId: profile.id || null, ticketSystem: profile.ticketSystem || null, layout: profile.layout || null }
    : null;
  const reposRoot = app ? app.checkout : path.join(REPO_ROOT, "..");
  const ticket =
    detectTicket(hints, profile) ||
    detectTicketFromBranches(profile, reposRoot, plansDir);
  if (!ticket && !slice) return null;

  const compact = {};
  if (slice) Object.assign(compact, slice);
  if (app) compact.appId = app.id;
  if (ticket) {
    compact.ticket = ticket;
    const packet = runResolve(ticket);
    if (packet) {
      compact.mode = packet.mode;
      compact.root = packet.root;
      compact.rootExists = packet.rootExists;
      compact.repos = packet.repos;
    }
    compact.nextAction = resolveNextAction(ticket, plansDir);
  }
  const context = app ? readContextSnippet(app.contextPath) : "";
  const label = ticket ? "Ticket tree for " + ticket : "Profile";
  const env = {
    TMO_TICKET: ticket || "",
    TMO_MODE: compact.mode ? String(compact.mode) : "",
    TMO_ROOT: compact.root ? String(compact.root) : "",
    TMO_PROFILE: slice && slice.profileId ? String(slice.profileId) : "",
    TMO_TICKET_SYSTEM: slice && slice.ticketSystem ? String(slice.ticketSystem) : "",
    TMO_LAYOUT: slice && slice.layout ? String(slice.layout) : "",
    AGENTIC_APP_OVERLAY: app ? app.overlay : "",
    AGENTIC_PLANS_DIR: app ? app.plansDir : "",
    AGENTIC_APP_ID: app ? app.id : "",
  };
  let text = label + ": " + JSON.stringify(compact);
  if (context) text += "\nApp context:\n" + context;
  return { label, compact, env, text };
}

module.exports = { buildPacket, detectTicket, detectTicketFromBranches, loadProfile, profileRepoDir, resolveNextAction };
