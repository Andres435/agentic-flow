#!/usr/bin/env node
"use strict";

// Codex PostModelRequest observer. Codex usage is normalized by shared core and
// stored in the same file Set-TicketCtxPct.ps1 reads. Never writes hook output.

const { record, fromTokenUsage } = require("../../../hooks/core/context-usage.js");

let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  raw += chunk;
});
process.stdin.on("end", () => {
  try {
    const input = JSON.parse(raw || "{}");
    if (input.hook_event_name !== "PostModelRequest" || input.status !== "completed" || !input.session_id) {
      process.exit(0);
      return;
    }
    const pct = fromTokenUsage(input.token_usage);
    if (pct !== null) record(input.session_id, pct, "codex-post-model-request");
  } catch {
    // Usage reporting is advisory; a malformed event or persistence error must not fail a request.
  }
  process.exit(0);
});
