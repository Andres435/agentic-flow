#!/usr/bin/env node
"use strict";

/** Smoke tests for the Antigravity hook contracts. Run with node adapters/antigravity/hooks/tests/antigravity-hooks.test.js. */
const assert = require("assert");
const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

process.env.TMO_SKIP_SWEEP = "1";
const HOOKS = path.join(__dirname, "..");
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), "tmo-antigravity-hooks-"));
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

function transcript(name, rows) {
  const p = path.join(TMP, name);
  fs.writeFileSync(p, rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
  return p;
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

console.log("Antigravity hooks");

test("plugin manifest points at the Antigravity hook manifest", () => {
  const pluginPath = path.join(__dirname, "..", "..", "..", "..", ".antigravity-plugin", "plugin.json");
  const plugin = JSON.parse(fs.readFileSync(pluginPath, "utf8"));
  assert.strictEqual(plugin.hooks, "./adapters/antigravity/hooks/hooks.json");
  const manifest = JSON.parse(fs.readFileSync(path.join(HOOKS, "hooks.json"), "utf8"));
  assert.ok(manifest.hooks.Stop);
});

test("Stop hook records measured context occupancy from transcript", () => {
  const p = transcript("antigravity-transcript.jsonl", [
    { step_index: 1, source: "USER", type: "USER_INPUT" },
    { step_index: 2, source: "MODEL", type: "PLANNER_RESPONSE", input_tokens: 50000, cache_read_tokens: 50000, output_tokens: 1000 },
  ]);
  const r = run("context-usage.js", {
    hook_event_name: "Stop",
    conversationId: "ag-test-1",
    transcriptPath: p,
  });
  assert.strictEqual(r.status, 0);
  const data = JSON.parse(fs.readFileSync(usageFile, "utf8"));
  assert.strictEqual(data.sessions["ag-test-1"].pct, 10); // 100k / 1M = 10%
  assert.strictEqual(data.sessions["ag-test-1"].source, "antigravity-transcript");
});

test("Stop hook fails open with decision allow on malformed input", () => {
  const r = run("context-usage.js", "not json");
  assert.strictEqual(r.status, 0);
  const json = JSON.parse(r.stdout);
  assert.strictEqual(json.decision, "allow");
});

test("Stop hook ignores missing transcript without throwing", () => {
  const r = run("context-usage.js", {
    hook_event_name: "Stop",
    conversationId: "ag-test-missing",
    transcriptPath: path.join(TMP, "nonexistent.jsonl"),
  });
  assert.strictEqual(r.status, 0);
  const json = JSON.parse(r.stdout);
  assert.strictEqual(json.decision, "allow");
});

fs.rmSync(TMP, { recursive: true, force: true });
console.log("\n" + passed + " passed, " + failed + " failed");
process.exit(failed ? 1 : 0);
