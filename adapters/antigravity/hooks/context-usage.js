#!/usr/bin/env node
"use strict";

// Antigravity Stop hook observer. Context usage is read from the transcript
// and stored in the same file Set-TicketCtxPct.ps1 reads. Never blocks.

const { record, fromTranscript } = require("../../../hooks/core/context-usage.js");

let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  raw += chunk;
});
process.stdin.on("end", () => {
  try {
    const input = JSON.parse(raw || "{}");
    const transcriptPath = input.transcriptPath || input.transcript_path;
    const conversationId = input.conversationId || input.session_id;
    if (transcriptPath && conversationId) {
      process.env.TMO_CONTEXT_WINDOW = process.env.TMO_CONTEXT_WINDOW || "1000000";
      const pct = fromTranscript(transcriptPath);
      if (pct !== null) {
        record(conversationId, pct, "antigravity-transcript");
      }
    }
  } catch {
    // Usage reporting is advisory; fail open.
  }
  process.stdout.write(JSON.stringify({ decision: "allow" }));
  process.exit(0);
});
