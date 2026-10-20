"use strict";

/**
 * Match an opened git checkout to apps/registry.json. Names no IDE.
 * workspaceOpen and sessionStart use this so a small app loads the host plugin
 * plus that app's overlay (profile, plans, context) without copying the workflow
 * into the app repo.
 */

const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

function hostRootFromHook(hookDir) {
  // adapters/<ide>/hooks → repo root
  return path.resolve(hookDir, "..", "..", "..");
}

function hostRootFromCore() {
  // hooks/core → repo root
  return path.resolve(__dirname, "..", "..");
}

function normalizeOrigin(url) {
  let s = String(url || "").trim();
  if (!s) return "";
  s = s.replace(/^git@([^:]+):/i, "https://$1/");
  s = s.replace(/^ssh:\/\/git@([^/]+)\//i, "https://$1/");
  s = s.replace(/\/+$/, "");
  s = s.replace(/\.git$/i, "");
  return s.toLowerCase();
}

function gitOrigin(dir) {
  if (!dir) return "";
  try {
    return execFileSync("git", ["-C", dir, "remote", "get-url", "origin"], {
      encoding: "utf8",
      timeout: 3000,
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}

function gitToplevel(dir) {
  if (!dir) return "";
  try {
    return execFileSync("git", ["-C", dir, "rev-parse", "--show-toplevel"], {
      encoding: "utf8",
      timeout: 3000,
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}

function loadRegistry(hostRoot) {
  const file = path.join(hostRoot, "apps", "registry.json");
  try {
    const data = JSON.parse(fs.readFileSync(file, "utf8"));
    return Array.isArray(data.apps) ? data.apps : [];
  } catch {
    return [];
  }
}

function hasPlugin(dir) {
  try {
    return fs.existsSync(path.join(dir, ".cursor-plugin", "plugin.json"));
  } catch {
    return false;
  }
}

function matchRegistry(apps, origin) {
  const n = normalizeOrigin(origin);
  if (!n) return null;
  for (const app of apps) {
    if (!app || !app.id || !app.origin) continue;
    if (normalizeOrigin(app.origin) === n) return app;
  }
  return null;
}

/**
 * @returns {null | { id, overlay, checkout, profilePath, plansDir, contextPath }}
 */
function resolveApp(opts) {
  const hostRoot = opts.hostRoot;
  const roots = Array.isArray(opts.workspaceRoots) ? opts.workspaceRoots : [];
  const originFn = typeof opts.gitOriginFn === "function" ? opts.gitOriginFn : gitOrigin;
  const toplevelFn = typeof opts.gitToplevelFn === "function" ? opts.gitToplevelFn : gitToplevel;
  const apps = Array.isArray(opts.apps) ? opts.apps : loadRegistry(hostRoot);
  for (const root of roots) {
    if (!root) continue;
    const opened = path.resolve(root);
    const origin = originFn(opened);
    const app = matchRegistry(apps, origin);
    if (!app) continue;
    // Same checkout as Resolve-AgenticApp.ps1: the git toplevel, so a subfolder open still
    // finds repos with path "." at the repository root.
    const top = toplevelFn(opened);
    const checkout = top ? path.resolve(top) : opened;
    const overlay = path.join(hostRoot, "apps", String(app.id));
    return {
      id: String(app.id),
      overlay,
      checkout,
      profilePath: path.join(overlay, "profile.json"),
      plansDir: path.join(overlay, "plans"),
      contextPath: path.join(overlay, "context.md"),
    };
  }
  return null;
}

function addPath(list, seen, dir) {
  if (!dir) return;
  const resolved = path.resolve(dir);
  const key = resolved.toLowerCase();
  if (seen.has(key)) return;
  seen.add(key);
  list.push(resolved);
}

/**
 * Plugin directories to load for this workspace: the host (skills and hooks)
 * plus the matching apps/<id> overlay when the origin is registered.
 * An unregistered app still gets the host so /adopt-project can run.
 */
function pluginPathsForOpen(opts) {
  const hostRoot = path.resolve(opts.hostRoot);
  const roots = Array.isArray(opts.workspaceRoots) ? opts.workspaceRoots : [];
  const found = [];
  const seen = new Set();

  let hostAlreadyProject = false;
  for (const root of roots) {
    if (!root) continue;
    const normalized = path.resolve(root);
    if (path.basename(normalized).toLowerCase() === ".cursor") {
      if (hasPlugin(normalized)) hostAlreadyProject = true;
      continue;
    }
    if (hasPlugin(normalized)) addPath(found, seen, normalized);
    if (normalized.toLowerCase() === hostRoot.toLowerCase()) hostAlreadyProject = true;
  }

  if (!hostAlreadyProject && hasPlugin(hostRoot)) addPath(found, seen, hostRoot);

  const app = resolveApp(opts);
  if (app && hasPlugin(app.overlay)) addPath(found, seen, app.overlay);

  return found;
}

module.exports = {
  hostRootFromHook,
  hostRootFromCore,
  normalizeOrigin,
  gitOrigin,
  loadRegistry,
  matchRegistry,
  resolveApp,
  pluginPathsForOpen,
  hasPlugin,
};
