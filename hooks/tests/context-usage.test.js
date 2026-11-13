#!/usr/bin/env node
"use strict";

/**
 * Tests for hooks/core/context-usage.js and the Claude Stop hook that feeds it.
 * Run: node hooks/tests/context-usage.test.js
 */
const assert = require("assert");
const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), "ctx-usage-"));
process.env.TMO_CTX_USAGE_FILE = path.join(TMP, "usage.json");
delete process.env.TMO_CONTEXT_WINDOW;
const { record, fromTranscript, fromTokenUsage } = require("../core/context-usage.js");
const STOP_HOOK = path.join(__dirname, "..", "..", "adapters", "claude", "hooks", "context-usage.js");

function transcript(name, rows) {
  const p = path.join(TMP, name);
  fs.writeFileSync(p, rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
  return p;
}

const assistant = (input, cacheCreate, cacheRead, extra) =>
  Object.assign(
    {
      type: "assistant",
      message: {
        role: "assistant",
        usage: { input_tokens: input, cache_creation_input_tokens: cacheCreate, cache_read_input_tokens: cacheRead, output_tokens: 500 },
      },
    },
    extra || {}
  );

let passed = 0;
let failed = 0;
function test(name, fn) {
  try {
    fn();
    console.log("  ✓ " + name);
    passed++;
  } catch (err) {
    console.error("  ✗ " + name);
    console.error("    " + err.message);
    failed++;
  }
}

console.log("context-usage tests");

test("reads the last main-chain assistant usage over a 200k window", () => {
  const p = transcript("a.jsonl", [
    assistant(10, 0, 1000),
    { type: "user", message: { role: "user", content: "hi" } },
    assistant(2000, 8000, 90000),
    assistant(50, 0, 150000, { isSidechain: true }),
  ]);
  assert.strictEqual(Math.round(fromTranscript(p)), 50);
});

test("switches to a 1M window once usage passes 200k", () => {
  const p = transcript("b.jsonl", [assistant(0, 0, 300000)]);
  assert.strictEqual(Math.round(fromTranscript(p)), 30);
});

test("returns null for a missing transcript or one with no usage", () => {
  assert.strictEqual(fromTranscript(path.join(TMP, "nope.jsonl")), null);
  assert.strictEqual(fromTranscript(transcript("c.jsonl", [{ type: "user" }])), null);
});

test("normalizes Codex input token usage without double-counting cached tokens", () => {
  assert.strictEqual(fromTokenUsage({ input_tokens: 100000, cached_input_tokens: 90000 }), 50);
  assert.strictEqual(fromTokenUsage({ input_tokens: 300000, cached_input_tokens: 100000 }), 30);
});

test("uses configured Codex context window and accepts measured zero input", () => {
  process.env.TMO_CONTEXT_WINDOW = "400000";
  assert.strictEqual(fromTokenUsage({ input_tokens: 100000 }), 25);
  assert.strictEqual(fromTokenUsage({ input_tokens: 0 }), 0);
  delete process.env.TMO_CONTEXT_WINDOW;
});

test("returns null for absent or invalid Codex token usage", () => {
  assert.strictEqual(fromTokenUsage(null), null);
  assert.strictEqual(fromTokenUsage({}), null);
  assert.strictEqual(fromTokenUsage({ input_tokens: -1 }), null);
  assert.strictEqual(fromTokenUsage({ input_tokens: "100" }), null);
});

test("record keeps latest and per-session entries", () => {
  record("s1", 41.6, "test");
  record("s2", 12, "test");
  const data = JSON.parse(fs.readFileSync(process.env.TMO_CTX_USAGE_FILE, "utf8"));
  assert.strictEqual(data.latest.session, "s2");
  assert.strictEqual(data.sessions.s1.pct, 42);
});

test("the Claude Stop hook records the session's measured value silently", () => {
  const p = transcript("d.jsonl", [assistant(0, 0, 60000)]);
  const r = spawnSync(process.execPath, [STOP_HOOK], {
    input: JSON.stringify({ session_id: "stop-1", transcript_path: p, hook_event_name: "Stop" }),
    encoding: "utf8",
    env: process.env,
  });
  assert.strictEqual(r.status, 0);
  assert.strictEqual(String(r.stdout || "").trim(), "");
  const data = JSON.parse(fs.readFileSync(process.env.TMO_CTX_USAGE_FILE, "utf8"));
  assert.strictEqual(data.sessions["stop-1"].pct, 30);
});

fs.rmSync(TMP, { recursive: true, force: true });

console.log("\n" + passed + " passed, " + failed + " failed");
process.exit(failed ? 1 : 0);
