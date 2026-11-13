"use strict";

/**
 * report-context, measured. IDE hooks record a chat's real context occupancy here, and
 * scripts/ticket/Set-TicketCtxPct.ps1 reads it when called without -Percent, so ledger
 * CtxS%/CtxR%/Ctx% stop being typed-in estimates. Names no IDE.
 *
 * File: scripts/.ctx-usage.json (gitignored), or TMO_CTX_USAGE_FILE (tests):
 *   { "latest": { session, pct, at, source }, "sessions": { "<id>": { ... } } }
 */

const fs = require("fs");
const path = require("path");
const { writeHookError } = require("./hook-log");

const DEFAULT_FILE = path.join(__dirname, "..", "..", "scripts", ".ctx-usage.json");
const TAIL_BYTES = 512 * 1024;

function usageFile() {
  return process.env.TMO_CTX_USAGE_FILE || DEFAULT_FILE;
}

/** Record one measurement. Keeps the newest 20 sessions. */
function record(session, pct, source) {
  if (!Number.isFinite(pct)) return null;
  const entry = {
    session: String(session || ""),
    pct: Math.max(0, Math.min(100, Math.round(pct))),
    at: new Date().toISOString(),
    source: source || "hook",
  };
  const file = usageFile();
  let data = { latest: null, sessions: {} };
  try {
    data = JSON.parse(fs.readFileSync(file, "utf8"));
    if (!data.sessions) data.sessions = {};
  } catch (error) {
    writeHookError("context-usage", error);
  }
  data.latest = entry;
  if (entry.session) data.sessions[entry.session] = entry;
  const ids = Object.keys(data.sessions).sort((a, b) => (data.sessions[a].at < data.sessions[b].at ? 1 : -1));
  for (const id of ids.slice(20)) delete data.sessions[id];
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
  return entry;
}

/**
 * Context occupancy from a transcript (JSON lines). Uses the last assistant message's
 * usage: input + cache creation + cache read tokens, the same sum a status line's
 * used_percentage reports, over the context window. The window is TMO_CONTEXT_WINDOW,
 * else 200k, else 1M once usage is past 200k.
 */
function fromTranscript(transcriptPath) {
  let text;
  try {
    const fd = fs.openSync(transcriptPath, "r");
    try {
      const size = fs.fstatSync(fd).size;
      const start = Math.max(0, size - TAIL_BYTES);
      const buf = Buffer.alloc(size - start);
      fs.readSync(fd, buf, 0, buf.length, start);
      text = buf.toString("utf8");
    } finally {
      fs.closeSync(fd);
    }
  } catch (error) {
    writeHookError("context-usage", error);
    return null;
  }
  const lines = text.split(/\r?\n/);
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i];
    if (!line.includes('"usage"') && !line.includes('"input_tokens"')) continue;
    let row;
    try {
      row = JSON.parse(line);
    } catch (error) {
      // A tail read starts mid-line. Only a whole object that fails to parse is a hook failure.
      if (line.trimStart().startsWith("{")) writeHookError("context-usage", error);
      continue;
    }
    const usage = row && row.message && row.message.usage;
    let used = 0;
    if (usage && !row.isSidechain) {
      used =
        Number(usage.input_tokens || 0) +
        Number(usage.cache_creation_input_tokens || 0) +
        Number(usage.cache_read_input_tokens || 0);
    } else if (row && (row.input_tokens !== undefined || row.cache_read_tokens !== undefined)) {
      if (row.type === "PLANNER_RESPONSE" || row.source === "MODEL") {
        used =
          Number(row.input_tokens || 0) +
          Number(row.cache_creation_input_tokens || 0) +
          Number(row.cache_read_tokens || 0);
      }
    }
    if (!used) continue;
    const configured = Number(process.env.TMO_CONTEXT_WINDOW);
    const window = configured > 0 ? configured : used > 200000 ? 1000000 : 200000;
    return (used / window) * 100;
  }
  return null;
}

/**
 * Context occupancy from a Codex PostModelRequest token_usage object. Codex input_tokens
 * is the reported prompt total; cached_input_tokens is a subset and is not added again.
 * Codex does not report the context window in this event, so use TMO_CONTEXT_WINDOW or
 * the same heuristic as fromTranscript. A reported zero is a real 0% measurement; missing
 * or invalid usage is unknown and returns null.
 */
function fromTokenUsage(usage) {
  if (!usage || typeof usage !== "object" || Array.isArray(usage)) return null;
  const used = usage.input_tokens;
  if (typeof used !== "number" || !Number.isFinite(used) || used < 0) return null;
  const configured = Number(process.env.TMO_CONTEXT_WINDOW);
  const window = configured > 0 ? configured : used > 200000 ? 1000000 : 200000;
  return (used / window) * 100;
}

module.exports = { record, fromTranscript, fromTokenUsage, usageFile };
