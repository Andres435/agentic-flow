#!/usr/bin/env node
"use strict";

/**
 * Smoke tests for hooks/closeout-read-guard.js
 *
 * Tests: deny closeout dump, deny closeout-index, allow other files, handle bad JSON.
 * Run: node hooks/tests/closeout-guard.test.js
 */

const assert = require("assert");
const { spawnSync } = require("child_process");
const path = require("path");

const HOOK = path.join(__dirname, "..", "..", "adapters", "cursor", "hooks", "closeout-read-guard.js");

function runHook(inputObj) {
  const result = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(inputObj),
    encoding: "utf8",
    timeout: 5000,
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

console.log("closeout-read-guard.js smoke tests");

test("denies plans/WI1234-closeout.md (file_path key)", () => {
  const out = runHook({ file_path: "plans/WI1234-closeout.md" });
  assert.strictEqual(out.permission, "deny", `expected deny, got ${out.permission}`);
  assert.ok(out.user_message, "expected user_message");
  assert.ok(/Search-CloseoutMemory/.test(out.user_message), "message should mention Search-CloseoutMemory");
});

test("denies plans/WI99999-closeout.md (path key)", () => {
  const out = runHook({ path: "plans/WI99999-closeout.md" });
  assert.strictEqual(out.permission, "deny");
});

test("denies a closeout under the template prefix (TICKET-42)", () => {
  const out = runHook({ file_path: "plans/TICKET-42-closeout.md" });
  assert.strictEqual(out.permission, "deny");
});

test("allows a non-ticket file that ends in closeout.md", () => {
  const out = runHook({ file_path: "skills/complete-task/closeout.md" });
  assert.strictEqual(out.permission, "allow");
});

test("denies plans/closeout-index.md", () => {
  const out = runHook({ file_path: "plans/closeout-index.md" });
  assert.strictEqual(out.permission, "deny");
});

test("denies Windows-style path separator", () => {
  const out = runHook({ file_path: "plans\\WI21053-closeout.md" });
  assert.strictEqual(out.permission, "deny");
});

test("allows a regular plan file", () => {
  const out = runHook({ file_path: "plans/WI21053-feature-plan.md" });
  assert.strictEqual(out.permission, "allow");
});

test("allows a non-plan file", () => {
  const out = runHook({ file_path: "_shared/ticket-artifacts.md" });
  assert.strictEqual(out.permission, "allow");
});

test("allows empty input (no path)", () => {
  const out = runHook({});
  assert.strictEqual(out.permission, "allow");
});

test("allows malformed JSON gracefully (falls back to allow)", () => {
  const result = spawnSync(process.execPath, [HOOK], {
    input: "not-json",
    encoding: "utf8",
    timeout: 5000,
  });
  const out = JSON.parse(result.stdout || "{}");
  assert.strictEqual(out.permission, "allow");
});

console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
