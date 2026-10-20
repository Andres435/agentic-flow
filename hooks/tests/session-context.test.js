#!/usr/bin/env node
"use strict";

/**
 * Smoke tests for hooks/session-context.js
 *
 * Ticket ids come from profile.json ticketPrefix so the same tests pass on TMO
 * (WI) and the vanilla template (TICKET-). Does NOT require PowerShell or a
 * product checkout. Run: node hooks/tests/session-context.test.js
 */

const assert = require("assert");
// Never spawn a real scratch sweep from a test run.
process.env.TMO_SKIP_SWEEP = "1";
const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOOK = path.join(__dirname, "..", "..", "adapters", "cursor", "hooks", "session-context.js");
const PROFILE = path.join(__dirname, "..", "..", "profile.json");

function ticketPrefix() {
  try {
    const profile = JSON.parse(fs.readFileSync(PROFILE, "utf8"));
    return String(profile.ticketPrefix || "WI");
  } catch {
    return "WI";
  }
}

const PREFIX = ticketPrefix();
const TICKET_A = PREFIX + "21053";
const TICKET_B = PREFIX + "99999";

function runHook(inputObj, env = {}) {
  const result = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(inputObj),
    encoding: "utf8",
    timeout: 15000,
    env: { ...process.env, ...env },
  });
  if (result.error) throw result.error;
  return JSON.parse(result.stdout || "{}");
}

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (err) {
    console.error(`  ✗ ${name}`);
    console.error(`    ${err.message}`);
    failed++;
  }
}

console.log("session-context.js smoke tests");

test("injects profile fields even when no ticket is detectable", () => {
  const out = runHook({}, { CURSOR_PROJECT_DIR: "", CLAUDE_PROJECT_DIR: "" });
  assert.ok(typeof out === "object", "output must be an object");
  if (out.additional_context) {
    assert.ok(
      /profileId/.test(out.additional_context),
      `additional_context must include profileId, got: ${out.additional_context}`
    );
  }
  if (out.env) {
    assert.ok("TMO_PROFILE" in out.env, "env.TMO_PROFILE missing");
    assert.ok("TMO_TICKET_SYSTEM" in out.env, "env.TMO_TICKET_SYSTEM missing");
    assert.ok("TMO_LAYOUT" in out.env, "env.TMO_LAYOUT missing");
  }
});

test("detects ticket from workspace_roots and produces packet shape", () => {
  const out = runHook(
    { workspace_roots: ["/source/worktrees/" + TICKET_A] },
    { CURSOR_PROJECT_DIR: "", CLAUDE_PROJECT_DIR: "" }
  );
  assert.ok(typeof out === "object", "output must be an object");
  if (out.additional_context) {
    assert.ok(
      out.additional_context.includes(TICKET_A),
      `additional_context must mention ${TICKET_A}, got: ${out.additional_context}`
    );
  }
});

test("detects ticket from CURSOR_PROJECT_DIR env var", () => {
  const out = runHook(
    {},
    {
      CURSOR_PROJECT_DIR: "C:\\source\\worktrees\\" + TICKET_B,
      CLAUDE_PROJECT_DIR: "",
    }
  );
  assert.ok(typeof out === "object", "output must be an object");
  if (out.additional_context) {
    assert.ok(
      out.additional_context.includes(TICKET_B),
      `must mention detected ticket ${TICKET_B}`
    );
  }
});

test("env block has ticket + profile keys when ticket detected", () => {
  const out = runHook(
    { workspace_roots: ["/source/worktrees/" + TICKET_A] },
    { CURSOR_PROJECT_DIR: "", CLAUDE_PROJECT_DIR: "" }
  );
  if (out.env) {
    assert.ok("TMO_TICKET" in out.env, "env.TMO_TICKET missing");
    assert.ok("TMO_MODE" in out.env, "env.TMO_MODE missing");
    assert.ok("TMO_ROOT" in out.env, "env.TMO_ROOT missing");
    assert.ok("TMO_PROFILE" in out.env, "env.TMO_PROFILE missing");
    assert.strictEqual(out.env.TMO_TICKET, TICKET_A);
  }
});

test("handles malformed JSON input gracefully", () => {
  const result = spawnSync(process.execPath, [HOOK], {
    input: "not-valid-json",
    encoding: "utf8",
    timeout: 5000,
  });
  const out = JSON.parse(result.stdout || "{}");
  assert.ok(typeof out === "object", "must return valid JSON even on bad input");
});

// --- nextAction field ---

function withTempPlans(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "tmo-test-plans-"));
  try {
    fn(dir);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test("nextAction is 'start-ticket' when manifest is absent", () => {
  withTempPlans((dir) => {
    const out = runHook(
      { workspace_roots: ["/source/worktrees/" + TICKET_A] },
      { CURSOR_PROJECT_DIR: "", CLAUDE_PROJECT_DIR: "", AGENTIC_PLANS_DIR: dir }
    );
    if (out.additional_context) {
      assert.ok(
        /"nextAction":"start-ticket"/.test(out.additional_context),
        "expected nextAction start-ticket, got: " + out.additional_context
      );
    }
  });
});

test("nextAction is 'review-changes' when manifest has no reviewReady", () => {
  withTempPlans((dir) => {
    fs.writeFileSync(
      path.join(dir, TICKET_A + "-manifest.json"),
      JSON.stringify({ mode: "branch", workType: "feature" })
    );
    const out = runHook(
      { workspace_roots: ["/source/worktrees/" + TICKET_A] },
      { CURSOR_PROJECT_DIR: "", CLAUDE_PROJECT_DIR: "", AGENTIC_PLANS_DIR: dir }
    );
    if (out.additional_context) {
      assert.ok(
        /"nextAction":"review-changes"/.test(out.additional_context),
        "expected review-changes, got: " + out.additional_context
      );
      assert.ok(!/stage first/.test(out.additional_context), "stage-first hint should be gone");
    }
  });
});

test("nextAction is 'complete-task' when reviewReady is set but completedAtUtc is null", () => {
  withTempPlans((dir) => {
    fs.writeFileSync(
      path.join(dir, TICKET_A + "-manifest.json"),
      JSON.stringify({ mode: "branch", reviewReady: "2026-09-17T10:00:00Z", completedAtUtc: null })
    );
    const out = runHook(
      { workspace_roots: ["/source/worktrees/" + TICKET_A] },
      { CURSOR_PROJECT_DIR: "", CLAUDE_PROJECT_DIR: "", AGENTIC_PLANS_DIR: dir }
    );
    if (out.additional_context) {
      assert.ok(
        /"nextAction":"complete-task"/.test(out.additional_context),
        "expected nextAction complete-task, got: " + out.additional_context
      );
    }
  });
});

test("nextAction is 'closed' when completedAtUtc is set", () => {
  withTempPlans((dir) => {
    fs.writeFileSync(
      path.join(dir, TICKET_A + "-manifest.json"),
      JSON.stringify({
        mode: "branch",
        reviewReady: "2026-09-17T10:00:00Z",
        completedAtUtc: "2026-09-17T14:00:00Z",
      })
    );
    const out = runHook(
      { workspace_roots: ["/source/worktrees/" + TICKET_A] },
      { CURSOR_PROJECT_DIR: "", CLAUDE_PROJECT_DIR: "", AGENTIC_PLANS_DIR: dir }
    );
    if (out.additional_context) {
      assert.ok(
        /"nextAction":"closed"/.test(out.additional_context),
        "expected nextAction closed, got: " + out.additional_context
      );
    }
  });
});

test("nextAction is complete-task when a PR is stamped and the ledger has no row", () => {
  const { resolveNextAction } = require(path.join(__dirname, "..", "core", "session-context.js"));
  withTempPlans((dir) => {
    fs.writeFileSync(
      path.join(dir, TICKET_A + "-manifest.json"),
      JSON.stringify({
        completedAtUtc: "2026-01-02T00:00:00Z",
        feedback: { prs: [{ repo: "app", id: 12, url: "https://example/pr/12" }], items: [] },
      })
    );
    const prev = process.env.AGENTIC_PLANS_DIR;
    process.env.AGENTIC_PLANS_DIR = dir;
    try {
      assert.strictEqual(resolveNextAction(TICKET_A), "complete-task");
      fs.writeFileSync(
        path.join(dir, "ticket-ledger.md"),
        "| Ticket | Type |\n|---|---|\n| " + TICKET_A + " | bug |\n"
      );
      assert.strictEqual(resolveNextAction(TICKET_A), "closed");
    } finally {
      if (prev === undefined) delete process.env.AGENTIC_PLANS_DIR;
      else process.env.AGENTIC_PLANS_DIR = prev;
    }
  });
});

test("nextAction treats a reopened ticket as open until it is re-closed", () => {
  const { resolveNextAction } = require(path.join(__dirname, "..", "core", "session-context.js"));
  withTempPlans((dir) => {
    const prev = process.env.AGENTIC_PLANS_DIR;
    process.env.AGENTIC_PLANS_DIR = dir;
    try {
      const file = path.join(dir, TICKET_A + "-manifest.json");
      const closed = { mode: "branch", reviewReady: { mode: "staged" }, completedAtUtc: "2026-10-01T00:00:00Z" };
      fs.writeFileSync(file, JSON.stringify(closed));
      assert.strictEqual(resolveNextAction(TICKET_A), "closed");
      fs.writeFileSync(file, JSON.stringify(Object.assign({}, closed, { reopenedAtUtc: "2026-10-03T00:00:00Z" })));
      assert.strictEqual(resolveNextAction(TICKET_A), "complete-task");
      fs.writeFileSync(
        file,
        JSON.stringify(Object.assign({}, closed, { reopenedAtUtc: "2026-10-03T00:00:00Z", reclosedAtUtc: "2026-10-04T00:00:00Z" }))
      );
      assert.strictEqual(resolveNextAction(TICKET_A), "closed");
    } finally {
      if (prev === undefined) delete process.env.AGENTIC_PLANS_DIR;
      else process.env.AGENTIC_PLANS_DIR = prev;
    }
  });
});

// Branch-mode fallback: a chat at the workspace root has no ticket in its path.
const { detectTicketFromBranches } = require(path.join(__dirname, "..", "core", "session-context.js"));

function withBranchWorkspace(branches, manifests, fn) {
  const ws = fs.mkdtempSync(path.join(os.tmpdir(), "branch-ws-"));
  const plans = path.join(ws, "plans");
  fs.mkdirSync(plans);
  const git = (cwd, args) => spawnSync("git", ["-C", cwd, ...args], { encoding: "utf8" });
  for (const [name, branch] of Object.entries(branches)) {
    const repo = path.join(ws, name);
    fs.mkdirSync(repo);
    git(repo, ["init", "-q", "-b", "main"]);
    git(repo, ["config", "user.email", "t@example.com"]);
    git(repo, ["config", "user.name", "t"]);
    fs.writeFileSync(path.join(repo, "a.txt"), "one");
    git(repo, ["add", "a.txt"]);
    git(repo, ["commit", "-q", "-m", "init"]);
    if (branch) git(repo, ["switch", "-q", "-c", branch]);
  }
  for (const [key, manifest] of Object.entries(manifests)) {
    fs.writeFileSync(path.join(plans, key + "-manifest.json"), JSON.stringify(manifest));
  }
  const profile = { ticketPrefix: PREFIX, repos: Object.keys(branches).map((name) => ({ name })) };
  try {
    fn(profile, ws, plans);
  } finally {
    fs.rmSync(ws, { recursive: true, force: true });
  }
}

test("branch fallback names the one ticket whose manifest is open", () => {
  withBranchWorkspace({ Api: TICKET_A, Web: TICKET_B }, { [TICKET_A]: { mode: "branch" }, [TICKET_B]: { completedAtUtc: "2026-10-01T00:00:00Z" } }, (profile, ws, plans) => {
    assert.strictEqual(detectTicketFromBranches(profile, ws, plans), TICKET_A);
  });
});

test("branch fallback treats a reopened ticket as open", () => {
  const reopened = { completedAtUtc: "2026-10-01T00:00:00Z", reopenedAtUtc: "2026-10-03T00:00:00Z" };
  withBranchWorkspace({ Api: TICKET_A }, { [TICKET_A]: reopened }, (profile, ws, plans) => {
    assert.strictEqual(detectTicketFromBranches(profile, ws, plans), TICKET_A);
  });
});

test("branch fallback stays silent for a closed ticket, no manifest, or two open tickets", () => {
  withBranchWorkspace({ Api: TICKET_A }, { [TICKET_A]: { completedAtUtc: "2026-10-01T00:00:00Z" } }, (profile, ws, plans) => {
    assert.strictEqual(detectTicketFromBranches(profile, ws, plans), null);
  });
  withBranchWorkspace({ Api: TICKET_A }, {}, (profile, ws, plans) => {
    assert.strictEqual(detectTicketFromBranches(profile, ws, plans), null);
  });
  withBranchWorkspace({ Api: TICKET_A, Web: TICKET_B }, { [TICKET_A]: {}, [TICKET_B]: {} }, (profile, ws, plans) => {
    assert.strictEqual(detectTicketFromBranches(profile, ws, plans), null);
  });
});

console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
