#!/usr/bin/env node
"use strict";

/** Smoke tests for the Codex hook contracts. Run with node adapters/codex/hooks/tests/codex-hooks.test.js. */
const assert = require("assert");
const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

process.env.TMO_SKIP_SWEEP = "1";
const HOOKS = path.join(__dirname, "..");
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), "tmo-codex-hooks-"));
const usageFile = path.join(TMP, "usage.json");
fs.writeFileSync(usageFile, "{}\n");

function run(script, input) {
  return spawnSync(process.execPath, [path.join(HOOKS, script)], {
    input: typeof input === "string" ? input : JSON.stringify(input),
    encoding: "utf8",
    timeout: 15000,
    env: Object.assign({}, process.env, { TMO_CTX_USAGE_FILE: usageFile }),
  });
}

let passed = 0;
let failed = 0;
function test(name, fn) {
  try {
    fn();
    console.log("  ok " + name);
    passed++;
  } catch (err) {
    console.error("  FAIL " + name + "\n    " + err.message);
    failed++;
  }
}

console.log("Codex hooks");

test("plugin manifest points at the Codex hook manifest", () => {
  const pluginPath = path.join(__dirname, "..", "..", "..", "..", ".codex-plugin", "plugin.json");
  const plugin = JSON.parse(fs.readFileSync(pluginPath, "utf8"));
  assert.strictEqual(plugin.hooks, "./adapters/codex/hooks/hooks.json");
  const manifest = JSON.parse(fs.readFileSync(path.join(HOOKS, "hooks.json"), "utf8"));
  assert.ok(manifest.hooks.SessionStart);
  assert.ok(manifest.hooks.PostModelRequest);
});

test("SessionStart returns the shared profile packet in Codex format", () => {
  const r = run("session-context.js", { hook_event_name: "SessionStart", cwd: "C:\\repos" });
  assert.strictEqual(r.status, 0);
  const json = JSON.parse(r.stdout);
  assert.strictEqual(json.hookSpecificOutput.hookEventName, "SessionStart");
  assert.match(json.hookSpecificOutput.additionalContext, /profileId/);
});

test("SessionStart fails open with a valid empty response on malformed input", () => {
  const r = run("session-context.js", "not json");
  assert.strictEqual(r.status, 0);
  assert.deepStrictEqual(JSON.parse(r.stdout), {});
});

test("PostModelRequest records measured input usage silently", () => {
  const r = run("context-usage.js", {
    hook_event_name: "PostModelRequest",
    status: "completed",
    session_id: "codex-1",
    token_usage: { input_tokens: 100000, cached_input_tokens: 90000 },
  });
  assert.strictEqual(r.status, 0);
  assert.strictEqual(String(r.stdout || "").trim(), "");
  const data = JSON.parse(fs.readFileSync(usageFile, "utf8"));
  assert.strictEqual(data.sessions["codex-1"].pct, 50);
  assert.strictEqual(data.sessions["codex-1"].source, "codex-post-model-request");
});

test("records a valid zero input measurement as zero percent", () => {
  const r = run("context-usage.js", {
    hook_event_name: "PostModelRequest", status: "completed", session_id: "codex-zero", token_usage: { input_tokens: 0 },
  });
  assert.strictEqual(r.status, 0);
  const data = JSON.parse(fs.readFileSync(usageFile, "utf8"));
  assert.strictEqual(data.sessions["codex-zero"].pct, 0);
});

for (const [name, event] of [
  ["absent usage", { hook_event_name: "PostModelRequest", status: "completed", session_id: "codex-absent" }],
  ["invalid usage", { hook_event_name: "PostModelRequest", status: "completed", session_id: "codex-invalid", token_usage: { input_tokens: -1 } }],
  ["failed request", { hook_event_name: "PostModelRequest", status: "failed", session_id: "codex-failed", token_usage: { input_tokens: 1000 } }],
  ["wrong event", { hook_event_name: "SessionStart", status: "completed", session_id: "codex-wrong", token_usage: { input_tokens: 1000 } }],
  ["missing session id", { hook_event_name: "PostModelRequest", status: "completed", token_usage: { input_tokens: 1000 } }],
]) {
  test("ignores " + name + " without changing stored usage", () => {
    const before = fs.existsSync(usageFile) ? fs.readFileSync(usageFile, "utf8") : null;
    const r = run("context-usage.js", event);
    assert.strictEqual(r.status, 0);
    const after = fs.existsSync(usageFile) ? fs.readFileSync(usageFile, "utf8") : null;
    if (before !== null) assert.strictEqual(after, before);
    else assert.strictEqual(after, null);
  });
}

fs.rmSync(TMP, { recursive: true, force: true });
console.log("\n" + passed + " passed, " + failed + " failed");
process.exit(failed ? 1 : 0);
