#!/usr/bin/env node
"use strict";

/**
 * Tests for the once-per-UTC-day scratch sweep started by hooks/core/session-context.js.
 * Never spawns a real sweep: the spawn function is injected. Run: node hooks/tests/session-sweep.test.js
 */

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");

process.env.TMO_SKIP_SWEEP = "1"; // the buildPacket calls below must not spawn for real
const { maybeSweep, buildPacket } = require(path.join(__dirname, "..", "core", "session-context.js"));

let passed = 0;
let failed = 0;
function test(name, fn) {
  try {
    fn();
    console.log(`  ok ${name}`);
    passed++;
  } catch (err) {
    console.error(`  FAIL ${name}\n    ${err.message}`);
    failed++;
  }
}

const NOW = "2026-10-19T12:00:00Z";
function makeRoot(marker) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "sweep-"));
  if (marker !== undefined) {
    fs.mkdirSync(path.join(root, "tmp"));
    fs.writeFileSync(path.join(root, "tmp", ".last-sweep"), marker);
  }
  return root;
}
function fakeSpawn(calls) {
  return (cmd, args, opts) => {
    let unref = false;
    calls.push({ cmd, args, opts });
    return { on() {}, unref() { unref = true; } };
  };
}
const found = () => "pwsh";

console.log("session sweep tests");

test("spawns once when the marker is missing", () => {
  const calls = [];
  assert.strictEqual(maybeSweep({ root: makeRoot(), spawn: fakeSpawn(calls), now: NOW, env: {}, findHost: found }), true);
  assert.strictEqual(calls.length, 1);
});

test("spawns when the marker has an older date", () => {
  const calls = [];
  maybeSweep({ root: makeRoot("2026-10-18\n"), spawn: fakeSpawn(calls), now: NOW, env: {}, findHost: found });
  assert.strictEqual(calls.length, 1);
});

test("does not spawn when the marker is today's UTC date", () => {
  const calls = [];
  maybeSweep({ root: makeRoot("2026-10-19\n"), spawn: fakeSpawn(calls), now: NOW, env: {}, findHost: found });
  assert.strictEqual(calls.length, 0);
});

test("TMO_SKIP_SWEEP=1 means no spawn", () => {
  const calls = [];
  maybeSweep({ root: makeRoot(), spawn: fakeSpawn(calls), now: NOW, env: { TMO_SKIP_SWEEP: "1" }, findHost: found });
  assert.strictEqual(calls.length, 0);
});

test("a throwing spawn, missing pwsh, or unreadable marker never throws", () => {
  const boom = () => {
    throw new Error("boom");
  };
  assert.doesNotThrow(() => maybeSweep({ root: makeRoot(), spawn: boom, now: NOW, env: {}, findHost: found }));
  const calls = [];
  maybeSweep({ root: makeRoot(), spawn: fakeSpawn(calls), now: NOW, env: {}, findHost: () => null });
  assert.strictEqual(calls.length, 0);
  const dirAsMarker = makeRoot();
  fs.mkdirSync(path.join(dirAsMarker, "tmp", ".last-sweep"), { recursive: true });
  assert.doesNotThrow(() => maybeSweep({ root: dirAsMarker, spawn: fakeSpawn(calls), now: NOW, env: {}, findHost: found }));
});

test("spawn args and options are exact", () => {
  const calls = [];
  const root = makeRoot();
  maybeSweep({ root, spawn: fakeSpawn(calls), now: NOW, env: {}, findHost: found });
  assert.strictEqual(calls[0].cmd, "pwsh");
  assert.deepStrictEqual(calls[0].args, [
    "-NoProfile",
    "-NonInteractive",
    "-File",
    path.join(root, "scripts", "Clear-WorkflowScratch.ps1"),
    "-Quiet",
  ]);
  assert.strictEqual(calls[0].opts.detached, true);
  assert.strictEqual(calls[0].opts.stdio, "ignore");
  assert.strictEqual(calls[0].opts.windowsHide, true);
});

test("packet output is byte-identical with and without the sweep", () => {
  const hints = ["C:\repos\WI21053-router"];
  const calls = [];
  const without = buildPacket(hints, { env: { TMO_SKIP_SWEEP: "1" } });
  const withSweep = buildPacket(hints, { root: makeRoot(), spawn: fakeSpawn(calls), now: NOW, env: {}, findHost: found });
  assert.strictEqual(calls.length, 1);
  assert.strictEqual(JSON.stringify(withSweep), JSON.stringify(without));
});

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
