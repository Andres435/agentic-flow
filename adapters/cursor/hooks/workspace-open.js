#!/usr/bin/env node
"use strict";

/**
 * User-level workspaceOpen hook. Returns plugin paths for the current workspace:
 * this host (skills and hooks) plus apps/<id> when git origin is in apps/registry.json.
 * A folder named .cursor is skipped: Cursor already loads it.
 */

const { hostRootFromHook, pluginPathsForOpen } = require("../../../hooks/core/resolve-app.js");

const HOST = hostRootFromHook(__dirname);

let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  raw += chunk;
});

process.stdin.on("end", () => {
  try {
    const input = JSON.parse(raw || "{}");
    const roots = Array.isArray(input.workspace_roots) ? input.workspace_roots : [];
    const found = pluginPathsForOpen({ hostRoot: HOST, workspaceRoots: roots });
    if (found.length === 0) {
      process.stdout.write("{}");
      return;
    }
    process.stdout.write(JSON.stringify({ pluginPaths: found }));
  } catch {
    process.stdout.write("{}");
  }
});
