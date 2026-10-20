#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { normalizeOrigin, matchRegistry, resolveApp, pluginPathsForOpen } = require("../core/resolve-app.js");

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

console.log("resolve-app.js");

test("normalizes ssh, https, and trailing .git to one origin", () => {
  const a = normalizeOrigin("git@github.com:Andres435/foo.git");
  const b = normalizeOrigin("https://github.com/Andres435/foo");
  const c = normalizeOrigin("https://github.com/Andres435/foo.git/");
  assert.strictEqual(a, b);
  assert.strictEqual(b, c);
  assert.strictEqual(a, "https://github.com/andres435/foo");
});

test("matchRegistry finds the app id", () => {
  const apps = [{ id: "foo", origin: "https://github.com/Andres435/foo.git" }];
  const hit = matchRegistry(apps, "git@github.com:Andres435/foo.git");
  assert.ok(hit);
  assert.strictEqual(hit.id, "foo");
  assert.strictEqual(matchRegistry(apps, "https://github.com/Andres435/other.git"), null);
});

test("resolveApp maps origin to overlay paths", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "agentic-app-"));
  const overlay = path.join(tmp, "apps", "foo");
  fs.mkdirSync(overlay, { recursive: true });
  const checkout = path.join(tmp, "checkout");
  fs.mkdirSync(checkout);
  const app = resolveApp({
    hostRoot: tmp,
    workspaceRoots: [checkout],
    apps: [{ id: "foo", origin: "https://github.com/Andres435/foo.git" }],
    gitOriginFn: () => "git@github.com:Andres435/foo.git",
  });
  assert.ok(app);
  assert.strictEqual(app.id, "foo");
  assert.strictEqual(app.overlay, overlay);
  assert.strictEqual(app.plansDir, path.join(overlay, "plans"));
  fs.rmSync(tmp, { recursive: true, force: true });
});

test("pluginPathsForOpen returns host plus overlay when the overlay is a plugin", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "agentic-plug-"));
  fs.mkdirSync(path.join(tmp, ".cursor-plugin"), { recursive: true });
  fs.writeFileSync(path.join(tmp, ".cursor-plugin", "plugin.json"), "{}");
  const overlay = path.join(tmp, "apps", "foo");
  fs.mkdirSync(path.join(overlay, ".cursor-plugin"), { recursive: true });
  fs.writeFileSync(path.join(overlay, ".cursor-plugin", "plugin.json"), "{}");
  const checkout = path.join(tmp, "checkout");
  fs.mkdirSync(checkout);
  const paths = pluginPathsForOpen({
    hostRoot: tmp,
    workspaceRoots: [checkout],
    apps: [{ id: "foo", origin: "https://github.com/Andres435/foo.git" }],
    gitOriginFn: () => "https://github.com/Andres435/foo.git",
  });
  const lower = paths.map((p) => p.toLowerCase());
  assert.ok(lower.includes(path.resolve(tmp).toLowerCase()), "host plugin missing");
  assert.ok(lower.includes(path.resolve(overlay).toLowerCase()), "app overlay missing");
  fs.rmSync(tmp, { recursive: true, force: true });
});

test("unregistered origin still loads the host plugin", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "agentic-host-"));
  fs.mkdirSync(path.join(tmp, ".cursor-plugin"), { recursive: true });
  fs.writeFileSync(path.join(tmp, ".cursor-plugin", "plugin.json"), "{}");
  const checkout = path.join(tmp, "checkout");
  fs.mkdirSync(checkout);
  const paths = pluginPathsForOpen({
    hostRoot: tmp,
    workspaceRoots: [checkout],
    apps: [],
    gitOriginFn: () => "https://github.com/Andres435/other.git",
  });
  assert.strictEqual(paths.length, 1);
  assert.strictEqual(path.resolve(paths[0]), path.resolve(tmp));
  fs.rmSync(tmp, { recursive: true, force: true });
});

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
