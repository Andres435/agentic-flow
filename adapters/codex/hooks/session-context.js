#!/usr/bin/env node
"use strict";

// Codex SessionStart bridge. Packet construction stays in hooks/core; this file
// translates Codex's stdin and hookSpecificOutput contract and fails open.

const { buildPacket } = require("../../../hooks/core/session-context.js");

let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  raw += chunk;
});
process.stdin.on("end", () => {
  try {
    const input = JSON.parse(raw || "{}");
    const packet = buildPacket([input.cwd, process.cwd()]);
    if (packet) {
      process.stdout.write(
        JSON.stringify({
          hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: packet.text },
        })
      );
    } else {
      process.stdout.write(JSON.stringify({}));
    }
  } catch {
    // Session context is advisory; malformed input or a core error must not block startup.
    process.stdout.write(JSON.stringify({}));
  }
});
