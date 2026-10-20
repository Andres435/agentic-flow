#!/usr/bin/env node
"use strict";

/**
 * Smoke tests for the Claude Code hook bridges.
 *
 * The shared hooks/core logic and the Cursor adapters are covered by ../../../../hooks/tests/*.test.js. These
 * assert the *Claude* contract instead: tool_input on stdin, and
 * hookSpecificOutput (or a silent exit 0) on stdout.
 *
 * Node only, no framework. Exits 0 on success, 1 on failure.
 */

// Never spawn a real scratch sweep from a test run.
process.env.TMO_SKIP_SWEEP = "1";
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const HOOKS = path.join(__dirname, "..");

let passed = 0;
let failed = 0;

function run(script, input, env) {
  const result = spawnSync(process.execPath, [path.join(HOOKS, script)], {
    input: JSON.stringify(input),
    encoding: "utf8",
    timeout: 15000,
    env: Object.assign({}, process.env, env || {}),
  });
  let json = null;
  const out = String(result.stdout || "").trim();
  if (out) {
    try {
      json = JSON.parse(out);
    } catch {
      json = null;
    }
  }
  return { status: result.status, stdout: out, stderr: result.stderr, json };
}

function check(name, fn) {
  try {
    fn();
    console.log("  \u2713 " + name);
    passed++;
  } catch (err) {
    console.log("  \u2717 " + name + "\n      " + err.message);
    failed++;
  }
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

function assertNoCrash(r) {
  assert(
    !/SyntaxError|ReferenceError|TypeError/.test(String(r.stderr || "")),
    "hook crashed: " + String(r.stderr).split("\n")[0]
  );
}

// --- closeout-read-guard.js (PreToolUse: Read) ---------------------------

console.log("closeout-read-guard.js (Claude PreToolUse contract)");

check("denies a WI closeout dump", () => {
  const r = run("closeout-read-guard.js", {
    tool_name: "Read",
    tool_input: { file_path: "C:\\repos\\tmo-agentic\\plans\\WI21053-closeout.md" },
  });
  assertNoCrash(r);
  assert(r.json, "expected JSON output, got: " + r.stdout);
  const h = r.json.hookSpecificOutput;
  assert(h.hookEventName === "PreToolUse", "wrong hookEventName");
  assert(h.permissionDecision === "deny", "expected deny");
  assert(
    /Search-CloseoutMemory/.test(h.permissionDecisionReason),
    "reason should point at Search-CloseoutMemory.ps1"
  );
});

check("denies closeout-index.md with forward slashes", () => {
  const r = run("closeout-read-guard.js", {
    tool_name: "Read",
    tool_input: { file_path: "plans/closeout-index.md" },
  });
  assertNoCrash(r);
  assert(
    r.json && r.json.hookSpecificOutput.permissionDecision === "deny",
    "expected deny"
  );
});

check("stays silent for a regular plan file", () => {
  const r = run("closeout-read-guard.js", {
    tool_name: "Read",
    tool_input: { file_path: "plans/ticket-ledger.md" },
  });
  assertNoCrash(r);
  assert(r.stdout === "", "expected no output, got: " + r.stdout);
  assert(r.status === 0, "expected exit 0");
});

check("stays silent when tool_input is absent", () => {
  const r = run("closeout-read-guard.js", { tool_name: "Read" });
  assertNoCrash(r);
  assert(r.stdout === "", "expected no output");
});

// --- precompact-nudge.js (PreCompact) ------------------------------------

console.log("\nprecompact-nudge.js (Claude PreCompact contract)");

check("nudges with the ticket recovered from cwd", () => {
  const r = run("precompact-nudge.js", { cwd: "C:\\repos\\WI21952-late-fee" });
  assertNoCrash(r);
  assert(r.json, "expected JSON output, got: " + r.stdout);
  assert(
    /WI21952/.test(r.json.systemMessage),
    "message should name the ticket: " + r.json.systemMessage
  );
  assert(
    /ticket-context-load/.test(r.json.systemMessage),
    "message should point at ticket-context-load"
  );
});

check("stays silent when no ticket is detectable", () => {
  const r = run(
    "precompact-nudge.js",
    { cwd: "C:\\repos" },
    { CLAUDE_PROJECT_DIR: "", TMO_TICKET: "" }
  );
  assertNoCrash(r);
  assert(r.stdout === "", "expected no output, got: " + r.stdout);
});

check("never blocks the compact (no permissionDecision)", () => {
  const r = run("precompact-nudge.js", { cwd: "C:\\repos\\WI21952" });
  assertNoCrash(r);
  assert(!/permissionDecision/.test(r.stdout), "PreCompact must not block");
});

// --- session-context.js (SessionStart) -----------------------------------

console.log("\nsession-context.js (Claude SessionStart contract)");

check("emits the profile slice with no ticket in cwd", () => {
  const r = run("session-context.js", { cwd: "C:\\repos" });
  assertNoCrash(r);
  assert(r.json, "expected JSON output, got: " + r.stdout);
  const h = r.json.hookSpecificOutput;
  assert(h.hookEventName === "SessionStart", "wrong hookEventName");
  assert(/profileId/.test(h.additionalContext), "expected profileId in packet");
});

check("detects a ticket from cwd and labels the packet", () => {
  const r = run("session-context.js", { cwd: "C:\\repos\\WI21053-router" });
  assertNoCrash(r);
  assert(r.json, "expected JSON output");
  const ctx = r.json.hookSpecificOutput.additionalContext;
  assert(/^Ticket tree for WI21053/.test(ctx), "bad label: " + ctx);
  assert(/"ticket":"WI21053"/.test(ctx), "ticket missing from packet: " + ctx);
});

check("packet is compact JSON, not a doc dump", () => {
  const r = run("session-context.js", { cwd: "C:\\repos\\WI21053-router" });
  assertNoCrash(r);
  const ctx = r.json.hookSpecificOutput.additionalContext;
  assert(ctx.length < 4000, "packet too large: " + ctx.length + " chars");
});

check("degrades gracefully on malformed stdin", () => {
  const result = spawnSync(
    process.execPath,
    [path.join(HOOKS, "session-context.js")],
    { input: "not json", encoding: "utf8", timeout: 15000 }
  );
  assert(
    !/SyntaxError|ReferenceError|TypeError/.test(String(result.stderr || "")),
    "hook crashed on bad input"
  );
  assert(result.status === 0, "expected exit 0 on bad input");
});

// --- session-context.js nextAction field ---

const os = require("os");

function withTempPlansClaude(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "tmo-claude-plans-"));
  try {
    fn(dir);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

check("nextAction is 'start-ticket' when manifest absent", () => {
  withTempPlansClaude((dir) => {
    const r = run(
      "session-context.js",
      { cwd: "C:\\repos\\WI21053-router" },
      { AGENTIC_PLANS_DIR: dir }
    );
    assertNoCrash(r);
    assert(r.json, "expected JSON output, got: " + r.stdout);
    const ctx = r.json.hookSpecificOutput.additionalContext;
    assert(/"nextAction":"start-ticket"/.test(ctx), "expected start-ticket, got: " + ctx);
  });
});

check("nextAction is 'review-changes' when manifest has no reviewReady", () => {
  withTempPlansClaude((dir) => {
    fs.writeFileSync(
      path.join(dir, "WI21053-manifest.json"),
      JSON.stringify({ mode: "branch", workType: "feature" })
    );
    const r = run(
      "session-context.js",
      { cwd: "C:\\repos\\WI21053-router" },
      { AGENTIC_PLANS_DIR: dir }
    );
    assertNoCrash(r);
    const ctx = r.json.hookSpecificOutput.additionalContext;
    assert(/"nextAction":"review-changes"/.test(ctx), "expected review-changes, got: " + ctx);
    assert(!/stage first/.test(ctx), "stage-first hint should be gone");
  });
});

check("nextAction is 'complete-task' when reviewReady set but completedAtUtc null", () => {
  withTempPlansClaude((dir) => {
    fs.writeFileSync(
      path.join(dir, "WI21053-manifest.json"),
      JSON.stringify({ mode: "branch", reviewReady: "2026-09-17T10:00:00Z", completedAtUtc: null })
    );
    const r = run(
      "session-context.js",
      { cwd: "C:\\repos\\WI21053-router" },
      { AGENTIC_PLANS_DIR: dir }
    );
    assertNoCrash(r);
    const ctx = r.json.hookSpecificOutput.additionalContext;
    assert(/"nextAction":"complete-task"/.test(ctx), "expected complete-task, got: " + ctx);
  });
});

check("nextAction is 'closed' when completedAtUtc is set", () => {
  withTempPlansClaude((dir) => {
    fs.writeFileSync(
      path.join(dir, "WI21053-manifest.json"),
      JSON.stringify({
        mode: "branch",
        reviewReady: "2026-09-17T10:00:00Z",
        completedAtUtc: "2026-09-17T14:00:00Z",
      })
    );
    const r = run(
      "session-context.js",
      { cwd: "C:\\repos\\WI21053-router" },
      { AGENTIC_PLANS_DIR: dir }
    );
    assertNoCrash(r);
    const ctx = r.json.hookSpecificOutput.additionalContext;
    assert(/"nextAction":"closed"/.test(ctx), "expected closed, got: " + ctx);
  });
});

// --- git-commit-ticket.js (PreToolUse: Bash) -----------------------------

console.log("\ngit-commit-ticket.js (Claude PreToolUse contract)");

check("asks before a commit with no work-item id", () => {
  const r = run("git-commit-ticket.js", {
    tool_name: "Bash",
    tool_input: { command: 'git commit -m "fix the thing"' },
    cwd: "C:\\repos",
  });
  assertNoCrash(r);
  assert(r.json, "expected JSON output, got: " + r.stdout);
  assert(
    r.json.hookSpecificOutput.permissionDecision === "ask",
    "expected ask"
  );
});

check("stays silent when the commit names a work item", () => {
  const r = run("git-commit-ticket.js", {
    tool_name: "Bash",
    tool_input: { command: 'git commit -m "fix(legacy): thing [WI21952]"' },
    cwd: "C:\\repos",
  });
  assertNoCrash(r);
  assert(r.stdout === "", "expected no output, got: " + r.stdout);
});

check("asks before a PowerShell-tool commit with no work-item id", () => {
  const r = run("git-commit-ticket.js", {
    tool_name: "PowerShell",
    tool_input: { command: 'Set-Location C:\\repos; git commit -m "fix the thing"' },
    cwd: "C:\\repos",
  });
  assertNoCrash(r);
  assert(r.json, "expected JSON output, got: " + r.stdout);
  assert(r.json.hookSpecificOutput.permissionDecision === "ask", "expected ask");
});

check("ignores non-commit Bash commands", () => {
  const r = run("git-commit-ticket.js", {
    tool_name: "Bash",
    tool_input: { command: "git status" },
  });
  assertNoCrash(r);
  assert(r.stdout === "", "expected no output");
});

// --- ticket-command-nudge.js (UserPromptSubmit) --------------------------

console.log("\nticket-command-nudge.js (Claude UserPromptSubmit contract)");

check("adds context for /tmo:start-ticket", () => {
  const r = run("ticket-command-nudge.js", {
    prompt: "/tmo:start-ticket WI21053",
  });
  assertNoCrash(r);
  assert(r.json, "expected JSON output, got: " + r.stdout);
  const h = r.json.hookSpecificOutput;
  assert(h.hookEventName === "UserPromptSubmit", "wrong hookEventName");
  assert(/branch/.test(h.additionalContext), "should state the branch default");
});

check("engineering-mode plus start-ticket names the playbook", () => {
  const r = run("ticket-command-nudge.js", {
    prompt: "/tmo:engineering-mode /tmo:start-ticket WI21053",
  });
  assertNoCrash(r);
  assert(r.json, "expected JSON output, got: " + r.stdout);
  const text = r.json.hookSpecificOutput.additionalContext;
  assert(/playbooks\/start-ticket\.md/.test(text), "should name the playbook");
  assert(/ExitPlanMode/.test(text), "should leave plan mode the Claude way");
  assert(!/SwitchMode/.test(text), "should not name the Cursor tool");
});

check("stays silent for a subagent report that mentions ticket commands", () => {
  const r = run("ticket-command-nudge.js", {
    prompt: "[Subagent hand-back] The close gate in /complete-task and /implement only checks bookkeeping.",
  });
  assertNoCrash(r);
  assert(r.stdout === "", "expected no output, got: " + r.stdout);
});

check("stays silent for an unrelated prompt", () => {
  const r = run("ticket-command-nudge.js", { prompt: "what does this do?" });
  assertNoCrash(r);
  assert(r.stdout === "", "expected no output, got: " + r.stdout);
});

check("git-push-agentic-flow.js ignores non-push Bash", () => {
  const r = run("git-push-agentic-flow.js", {
    tool_name: "Bash",
    tool_input: { command: "git status" },
    hook_event_name: "PreToolUse",
  });
  assertNoCrash(r);
  assert(r.stdout === "", "expected no output, got: " + r.stdout);
});

// --- hooks.json wiring ---------------------------------------------------

console.log("\nhooks.json wiring");

check("every declared hook script exists", () => {
  const fs = require("fs");
  const cfg = JSON.parse(
    fs.readFileSync(path.join(HOOKS, "hooks.json"), "utf8")
  );
  const seen = [];
  for (const groups of Object.values(cfg.hooks)) {
    for (const group of groups) {
      for (const hook of group.hooks) {
        const m = hook.command.match(/hooks\/([\w-]+\.js)/);
        assert(m, "unparseable hook command: " + hook.command);
        assert(
          fs.existsSync(path.join(HOOKS, m[1])),
          "missing hook script: " + m[1]
        );
        seen.push(m[1]);
      }
    }
  }
  // git-guard.js runs the commit and push bridges in one process, so 7 entries wire 8 bridges.
  assert(seen.length === 7, "expected 7 wired hooks, found " + seen.length);
  assert(seen.includes("git-guard.js"), "git-guard.js is not wired");
});

check("every Cursor hook has a Claude counterpart", () => {
  const fs = require("fs");
  // workspace-open.js is Cursor's user-level plugin loader; Claude loads the plugin itself.
  const cursorHooks = fs
    .readdirSync(path.join(HOOKS, "..", "..", "cursor", "hooks"))
    .filter((f) => f.endsWith(".js") && f !== "workspace-open.js");
  const claudeHooks = fs
    .readdirSync(HOOKS)
    .filter((f) => f.endsWith(".js"));
  const missing = cursorHooks.filter((f) => !claudeHooks.includes(f));
  assert(
    missing.length === 0,
    "Cursor hooks with no Claude bridge: " + missing.join(", ")
  );
});

console.log("\n" + passed + " passed, " + failed + " failed");
process.exit(failed ? 1 : 0);
